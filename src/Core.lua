---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Addon Lifecycle
---------------------------------------------------------------------------

function WHLSN:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("WheelsonDB", WHLSN.defaults, true)

    -- Current session state
    self.session = {
        status = nil,    -- nil | "lobby" | "spinning" | "completed"
        players = {},    -- WHLSNPlayer[]
        groups = {},     -- WHLSNGroup[]
        host = nil,      -- player name who started the session
        isTest = false,  -- true when running a test session (no guild comms)
        viewingHistory = false, -- true when displaying a past session
    }

    -- Throttle timer for roster update events
    self.rosterUpdatePending = false

    -- Session timeout timer
    self.sessionTimeoutTimer = nil
    -- Last activity timestamp for timeout tracking
    self.lastActivity = 0

    -- Comm throttle state
    self.commThrottleTimer = nil
    self.commPendingUpdate = false

    -- Addon user discovery cache (ephemeral, not saved)
    self.addonUsersCache = {}
    self.isScanning = false

    self:RegisterComm(self.COMM_PREFIX)

    -- Minimap icon via LibDataBroker + LibDBIcon
    local LDB = LibStub("LibDataBroker-1.1")
    self.ldbIcon = LibStub("LibDBIcon-1.0")

    local launcher = LDB:NewDataObject("Wheelson", {
        type = "launcher",
        icon = "Interface\\AddOns\\Wheelson\\textures\\minimap-icon",
        OnClick = function(_, button)
            if button == "LeftButton" then
                WHLSN:ToggleMainFrame()
            elseif button == "RightButton" then
                WHLSN:ToggleDebugFrame()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Wheelson", 1, 0.82, 0)
            tooltip:AddLine("|cFFAAAAAA" .. WHLSN.VERSION .. "|r")
            if WHLSN.session.status then
                tooltip:AddLine("Session: " .. WHLSN.session.status, 0.5, 1, 0.5)
                tooltip:AddLine("Host: " .. (WHLSN.session.host or "Unknown"), 0.7, 0.7, 0.7)
            else
                tooltip:AddLine("No active session", 0.5, 0.5, 0.5)
            end
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFFFFFFFFLeft-click:|r Open addon", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cFFFFFFFFRight-click:|r Debug panel", 0.8, 0.8, 0.8)
        end,
    })
    self.ldbIcon:Register("Wheelson", launcher, self.db.profile.minimap)

    self:Print("Wheelson loaded. Type /wheelson to open.")
end

--- Toggle minimap icon visibility and persist the setting.
function WHLSN:ToggleMinimapIcon()
    local db = self.db.profile.minimap
    local icon = self.ldbIcon
    db.hide = not db.hide
    if db.hide then
        icon:Hide("Wheelson")
        self:Print("Minimap icon hidden. Type /wheelson minimap to show it again.")
    else
        icon:Show("Wheelson")
        self:Print("Minimap icon shown.")
    end
end

function WHLSN:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
end

function WHLSN:OnDisable()
    self:UnregisterAllEvents()
    self:CancelSessionTimeout()
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

SLASH_WHEELSON1 = "/wheelson"
SLASH_WHEELSON2 = "/wheel"

SlashCmdList["WHEELSON"] = function()
    WHLSN:ToggleMainFrame()
end

---------------------------------------------------------------------------
-- Session Management
---------------------------------------------------------------------------

--- Start a new lobby session. Any guild member can host.
function WHLSN:StartSession()
    if self.session.status then
        self:Print("A session is already active.")
        return
    end

    self.hasLeftSession = false
    self.session.status = self.Status.LOBBY
    self.session.host = UnitName("player")
    self.session.players = {}
    self.session.groups = {}
    self.session.algorithmSnapshot = nil
    -- Auto-add the host as the first player
    local hostPlayer = self:DetectLocalPlayer()
    if hostPlayer then
        self.session.players[1] = hostPlayer
    end

    self.lastActivity = time()
    self:ResetSessionTimeout()
    self:ShowMainFrame()
    self:BroadcastSessionUpdate()
    self:Print("Session started! Guild members can join via the Wheelson addon.")
end

--- Start a test session with hardcoded players (no guild comms).
function WHLSN:StartTestSession()
    if self.session.status then
        self:Print("A session is already active.")
        return
    end

    self.session.status = self.Status.LOBBY
    self.session.host = UnitName("player")
    self.session.players = self:GetTestPlayers()
    self.session.groups = {}
    self.session.isTest = true

    self:ShowMainFrame()
    self:UpdateUI()
    self:Print("[Test Mode] Session started with " .. #self.session.players .. " test players.")
end

--- End the current session and clean up.
function WHLSN:EndSession()
    if not self.session.status then
        self:Print("No active session.")
        return
    end

    local wasViewing = self.session.viewingHistory or false
    local wasTest = self.session.isTest or false

    self:CancelSessionTimeout()

    self.session.status = nil
    self.session.host = nil
    self.session.players = {}
    self.session.groups = {}
    self.session.viewingHistory = false
    self.session.isTest = nil
    self.session.algorithmSnapshot = nil

    if not wasViewing and not wasTest then
        self:BroadcastSessionEnd()
        self:Print("Session ended.")
    elseif wasTest then
        self:Print("[Test Mode] Session ended.")
    end

    self:UpdateUI()
end

--- Leave the current session (for non-hosts).
function WHLSN:LeaveSession()
    if not self.session.status then
        self:Print("No active session.")
        return
    end

    local myName = UnitName("player")
    if self.session.host == myName then
        self:Print("You are the host. Use the End Session button to end the session.")
        return
    end

    -- Send leave notification to host
    local data = {
        type = "LEAVE_REQUEST",
        playerName = myName,
    }
    local serialized = self:Serialize(data)
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")

    self.session.status = nil
    self.session.host = nil
    self.session.players = {}
    self.session.groups = {}
    self.hasLeftSession = true
    self:Print("You have left the session.")
end

--- Run the group creation algorithm and transition to spinning.
function WHLSN:SpinGroups()
    if self.session.status ~= self.Status.LOBBY then
        self:Print("Can only spin from the lobby.")
        return
    end

    if #self.session.players < 5 then
        self:Print("Need at least 5 players to form a group.")
        return
    end

    -- Capture algorithm inputs before running
    local playerDicts = {}
    for _, p in ipairs(self.session.players) do
        playerDicts[#playerDicts + 1] = p:ToDict()
    end

    local previousGroups = self:GetLastGroups()
    local lastGroupDicts = {}
    for _, g in ipairs(previousGroups) do
        lastGroupDicts[#lastGroupDicts + 1] = g:ToDict()
    end

    self.session.groups = self:CreateMythicPlusGroups(self.session.players)
    self.session.status = self.Status.SPINNING

    -- Capture algorithm outputs
    local groupDicts = {}
    for _, g in ipairs(self.session.groups) do
        groupDicts[#groupDicts + 1] = g:ToDict()
    end

    self.session.algorithmSnapshot = {
        players = playerDicts,
        lastGroups = lastGroupDicts,
        groups = groupDicts,
        timestamp = time(),
        host = self.session.host,
        playerCount = #self.session.players,
    }

    self.lastActivity = time()
    self:BroadcastSessionUpdate()
    self:UpdateUI()
end

--- Mark session as completed after wheel animation finishes.
function WHLSN:CompleteSession()
    self.session.status = self.Status.COMPLETED
    self:SaveSessionResults()
    self:BroadcastSessionUpdate()
end

--- Save session results to SavedVariables.
function WHLSN:SaveSessionResults()
    if self.session.isTest then return end
    if not self.db then return end

    local groupData = {}
    for _, g in ipairs(self.session.groups) do
        groupData[#groupData + 1] = g:ToDict()
    end

    local sessionRecord = {
        groups = groupData,
        host = self.session.host,
        playerCount = #self.session.players,
        timestamp = time(),
    }

    self.db.profile.lastSession = sessionRecord
    self:SaveSessionToHistory(sessionRecord)
end

--- Save a session record to the history log.
---@param record table Session record with groups, host, playerCount, timestamp
function WHLSN:SaveSessionToHistory(record)
    if not self.db then return end

    local history = self.db.profile.sessionHistory
    if not history then
        history = {}
        self.db.profile.sessionHistory = history
    end

    -- Add to the front (most recent first)
    table.insert(history, 1, record)

    -- Trim to max history size
    while #history > self.MAX_HISTORY do
        history[#history] = nil
    end
end

--- View a saved session from history in the GroupDisplay.
---@param index number Index into sessionHistory (1 = most recent)
function WHLSN:ViewHistorySession(index)
    if self.session.status and not self.session.viewingHistory then return end

    local history = self.db and self.db.profile.sessionHistory
    if not history or not history[index] then
        self:Print("Session not found.")
        return
    end

    local record = history[index]
    if not record.groups or #record.groups == 0 then
        self:Print("No group data for that session.")
        return
    end

    -- Load groups into session state for display only (no broadcast)
    self.session.groups = {}
    for _, gd in ipairs(record.groups) do
        self.session.groups[#self.session.groups + 1] = WHLSN.Group.FromDict(gd)
    end

    self.session.status = self.Status.COMPLETED
    self.session.host = record.host
    self.session.players = {}
    self.session.viewingHistory = true

    self:ShowMainFrame()
end

--- Remove a player from the session (host only).
---@param playerName string
function WHLSN:KickPlayer(playerName)
    if self.session.host ~= UnitName("player") then return end
    if self.session.status ~= self.Status.LOBBY then return end

    for i, p in ipairs(self.session.players) do
        if p.name == playerName then
            table.remove(self.session.players, i)
            self:BroadcastSessionUpdate()
            self:Print(playerName .. " removed from session.")
            return
        end
    end
end

---------------------------------------------------------------------------
-- Session Timeout
---------------------------------------------------------------------------

--- Reset the session timeout timer.
function WHLSN:ResetSessionTimeout()
    self:CancelSessionTimeout()
    self.lastActivity = time()
    self.sessionTimeoutTimer = C_Timer.NewTimer(self.SESSION_TIMEOUT, function()
        WHLSN:OnSessionTimeout()
    end)
end

--- Cancel the session timeout timer.
function WHLSN:CancelSessionTimeout()
    if self.sessionTimeoutTimer then
        self.sessionTimeoutTimer:Cancel()
        self.sessionTimeoutTimer = nil
    end
end

--- Handle session timeout.
function WHLSN:OnSessionTimeout()
    if not self.session.status then return end

    self:Print("Session timed out after " .. math.floor(self.SESSION_TIMEOUT / 60) .. " minutes of inactivity.")
    self:EndSession()
end

--- Touch the session activity timer (called on meaningful actions).
function WHLSN:TouchActivity()
    self.lastActivity = time()
    self:ResetSessionTimeout()
end

---------------------------------------------------------------------------
-- Addon Communication
---------------------------------------------------------------------------

--- Broadcast session state to the guild (throttled).
function WHLSN:BroadcastSessionUpdate()
    if self.session.isTest then return end
    self:TouchActivity()

    -- Throttle broadcasts to avoid flooding
    if self.commThrottleTimer then
        self.commPendingUpdate = true
        return
    end

    self:SendSessionUpdate()

    self.commThrottleTimer = C_Timer.NewTimer(self.COMM_THROTTLE, function()
        self.commThrottleTimer = nil
        if self.commPendingUpdate then
            self.commPendingUpdate = false
            self:SendSessionUpdate()
        end
    end)
end

--- Send the actual session update message.
function WHLSN:SendSessionUpdate()
    local playerList = {}
    for _, p in ipairs(self.session.players) do
        playerList[#playerList + 1] = p:ToDict()
    end

    local data = {
        type = "SESSION_UPDATE",
        version = self.VERSION,
        status = self.session.status,
        host = self.session.host,
        playerCount = #self.session.players,
        players = playerList,
    }

    if self.session.status == self.Status.SPINNING or
       self.session.status == self.Status.COMPLETED then
        local groupData = {}
        for _, g in ipairs(self.session.groups) do
            groupData[#groupData + 1] = g:ToDict()
        end
        data.groups = groupData
    end

    local serialized = self:Serialize(data)
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
end

--- Broadcast session end to the guild.
function WHLSN:BroadcastSessionEnd()
    if self.session.isTest then return end
    local serialized = self:Serialize({ type = "SESSION_END" })
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
end

--- Handle incoming addon messages.
function WHLSN:OnCommReceived(prefix, message, _distribution, sender)
    if prefix ~= self.COMM_PREFIX then return end
    if sender == UnitName("player") then return end

    local success, data = self:Deserialize(message)
    if not success then return end

    -- Version handshake warning (skip for discovery messages to avoid noise)
    if data.type ~= "ADDON_PING" and data.type ~= "ADDON_PONG" then
        if data.version and data.version ~= self.VERSION then
            if data.version ~= "@project-version@" and self.VERSION ~= "@project-version@" then
                self:Print("Warning: " .. sender .. " is using addon version " .. tostring(data.version)
                    .. " (you have " .. tostring(self.VERSION) .. ")")
            end
        end
    end

    if data.type == "SESSION_UPDATE" then
        self:HandleSessionUpdate(data, sender)
    elseif data.type == "SESSION_END" then
        self:HandleSessionEnd(sender)
    elseif data.type == "JOIN_REQUEST" then
        self:HandleJoinRequest(data, sender)
    elseif data.type == "LEAVE_REQUEST" then
        self:HandleLeaveRequest(data, sender)
    elseif data.type == "ADDON_PING" then
        self:HandleAddonPing(sender)
    elseif data.type == "ADDON_PONG" then
        self:HandleAddonPong(data, sender)
    end
end

function WHLSN:HandleSessionUpdate(data, sender)
    -- Ignore updates after intentionally leaving a session
    if self.hasLeftSession then return end

    -- Only accept updates from the session host
    if self.session.host and sender ~= self.session.host then return end

    if data.host then
        self.session.status = data.status
        self.session.host = data.host
        -- Update full player list from host
        if data.players then
            self.session.players = {}
            for _, pd in ipairs(data.players) do
                self.session.players[#self.session.players + 1] = WHLSN.Player.FromDict(pd)
            end
        end

        if data.groups then
            self.session.groups = {}
            for _, gd in ipairs(data.groups) do
                self.session.groups[#self.session.groups + 1] = WHLSN.Group.FromDict(gd)
            end
        end

        self:UpdateUI()
    end
end

function WHLSN:HandleSessionEnd(sender)
    -- Only accept end from the session host
    if self.session.host and sender ~= self.session.host then return end

    self.session.status = nil
    self.session.host = nil
    self.session.players = {}
    self.session.groups = {}
    self.session.algorithmSnapshot = nil
    self.session.viewingHistory = false
    self:UpdateUI()
end

function WHLSN:HandleJoinRequest(data, sender)
    -- Only the host processes join requests
    if self.session.host ~= UnitName("player") then return end
    if self.session.status ~= self.Status.LOBBY then return end

    -- Validate sender matches the player data to prevent spoofing
    if not data.player or data.player.name ~= sender then return end

    -- Validate guild membership
    if not self:IsGuildMember(sender) then return end

    local player = WHLSN.Player.FromDict(data.player)
    -- Replace if already in list
    for i, p in ipairs(self.session.players) do
        if p.name == player.name then
            self.session.players[i] = player
            self:BroadcastSessionUpdate()
            return
        end
    end

    self.session.players[#self.session.players + 1] = player
    self:BroadcastSessionUpdate()
end

function WHLSN:HandleLeaveRequest(data, sender)
    -- Only the host processes leave requests
    if self.session.host ~= UnitName("player") then return end
    if not data.playerName or data.playerName ~= sender then return end

    for i, p in ipairs(self.session.players) do
        if p.name == sender then
            table.remove(self.session.players, i)
            self:BroadcastSessionUpdate()
            return
        end
    end
end

---------------------------------------------------------------------------
-- Addon Discovery
---------------------------------------------------------------------------

function WHLSN:HandleAddonPing(_sender)
    -- Reply with our presence info, broadcast to GUILD so all clients can cache
    local data = {
        type = "ADDON_PONG",
        name = UnitName("player"),
        version = self.VERSION,
    }
    local serialized = self:Serialize(data)
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
end

function WHLSN:HandleAddonPong(data, sender)
    local name = self:StripRealmName(sender)
    self.addonUsersCache[name] = {
        name = name,
        version = data.version or "unknown",
        lastSeen = time(),
    }

    -- Refresh options panel if open so it live-updates as PONGs arrive
    local ACR = LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("Wheelson")
    end
end

--- Broadcast a discovery ping to find online addon users.
function WHLSN:SendAddonPing()
    -- Add local player to cache (bypasses self-filter in OnCommReceived)
    local myName = UnitName("player")
    self.addonUsersCache[myName] = {
        name = myName,
        version = self.VERSION,
        lastSeen = time(),
    }

    local data = { type = "ADDON_PING" }
    local serialized = self:Serialize(data)
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")

    self.isScanning = true
    C_Timer.After(self.DISCOVERY_SCAN_DURATION, function()
        self.isScanning = false
        -- Refresh options panel if AceConfigRegistry is available
        local ACR = LibStub("AceConfigRegistry-3.0", true)
        if ACR then
            ACR:NotifyChange("Wheelson")
        end
    end)
end

--- Remove cached addon users who are no longer online in the guild roster.
function WHLSN:PruneAddonUsersCache()
    local onlineMembers = self:GetOnlineGuildMembers()
    local onlineSet = {}
    for _, m in ipairs(onlineMembers) do
        onlineSet[m.name] = true
    end

    for name in pairs(self.addonUsersCache) do
        if not onlineSet[name] then
            self.addonUsersCache[name] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------

function WHLSN:GROUP_ROSTER_UPDATE()
    self:ThrottledUpdateUI()
end

function WHLSN:GUILD_ROSTER_UPDATE()
    self:PruneAddonUsersCache()
    self:ThrottledUpdateUI()
end

--- Throttle UI updates from rapid roster events (fires at most once per 0.5s).
function WHLSN:ThrottledUpdateUI()
    if self.rosterUpdatePending then return end
    self.rosterUpdatePending = true
    C_Timer.After(0.5, function()
        self.rosterUpdatePending = false
        self:UpdateUI()
    end)
end

---------------------------------------------------------------------------
-- UI Stubs (implemented in UI files)
---------------------------------------------------------------------------

function WHLSN:ToggleMainFrame()
    -- Overridden by UI/MainFrame.lua
end

function WHLSN:ShowMainFrame()
    -- Overridden by UI/MainFrame.lua
end

function WHLSN:UpdateUI()
    -- Overridden by UI/MainFrame.lua
end

function WHLSN:ToggleDebugFrame()
    -- Overridden by UI/DebugPanel.lua
end
