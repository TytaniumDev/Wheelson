---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Session Management
---------------------------------------------------------------------------

--- Start a new lobby. Any guild member can host.
function WHLSN:CreateLobby()
    -- Allow starting a new session if we're just waiting for a restore query
    if self.sessionRestoreTimer then
        self:ClearSessionState()
    end

    if self.session.status then
        self:Print("A lobby is already active.")
        return
    end

    self.leftSessionHost = nil
    self.session.status = self.Status.LOBBY
    self.session.host = self:GetMyFullName()
    self.session.players = {}
    self.session.groups = {}
    self.session.algorithmSnapshot = nil
    self.session.connectedCommunity = {}
    self.session.removedPlayers = {}
    -- Wago Analytics
    self.analytics:IncrementCounter("sessionsStarted")

    -- Auto-add the host as the first player
    local hostPlayer = self:DetectLocalPlayer()
    if hostPlayer then
        self.session.players[1] = hostPlayer
    end

    self.lastActivity = time()
    self:ResetSessionTimeout()
    self:ShowMainFrame()
    self:BroadcastSessionUpdate()
    self:SendCommunityPings()
    self:PersistSessionState()
    self:Print("Lobby created! Guild members can join via the Wheelson addon.")
end

--- Start a test lobby with hardcoded players (no guild comms).
function WHLSN:CreateTestLobby()
    if self.session.status then
        self:Print("A lobby is already active.")
        return
    end

    self.session.status = self.Status.LOBBY
    self.session.host = self:GetMyFullName()
    self.session.players = self:GetTestPlayers()
    self.session.groups = {}
    self.session.isTest = true
    self.session.algorithmSnapshot = nil
    self.session.connectedCommunity = {}
    self.session.removedPlayers = {}

    self:ShowMainFrame()
    self:UpdateUI()
    self:Print("[Test Mode] Lobby created with " .. #self.session.players .. " test players.")
end

--- Close the current lobby and clean up.
function WHLSN:CloseLobby()
    if not self.session.status then
        self:Print("No active lobby.")
        return
    end

    local wasViewing = self.session.viewingHistory or false
    local wasTest = self.session.isTest or false
    local wasCommunity = self.session.connectedCommunity or {}

    self:ClearSessionState()

    if not wasViewing and not wasTest then
        self:BroadcastSessionEnd(wasCommunity)
        self:Print("Lobby closed.")
    elseif wasTest then
        self:Print("[Test Mode] Lobby closed.")
    end

    self:UpdateUI()
end

--- Leave the current session (for non-hosts).
function WHLSN:LeaveSession()
    if not self.session.status then
        self:Print("No active lobby.")
        return
    end

    if self:NamesMatch(self.session.host, self:GetMyFullName()) then
        self:Print("You are the host. Use the Close Lobby button to close the lobby.")
        return
    end

    self.leftSessionHost = self.session.host

    local data = {
        type = "LEAVE_REQUEST",
        playerName = self:GetMyFullName(),
    }
    local serialized = self:Serialize(data)

    if self.session.commChannel == "WHISPER" and self.session.host then
        self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "WHISPER", self.session.host)
    else
        self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
    end

    self:ClearSessionState()
    self:Print("You have left the lobby.")
end

--- Run the group creation algorithm and transition to spinning.
function WHLSN:SpinGroups()
    if self.session.status ~= self.Status.LOBBY then
        self:Print("Can only spin from the lobby.")
        return
    end

    -- Filter out removed/hidden players
    local activePlayers = {}
    for _, p in ipairs(self.session.players) do
        if not self.session.removedPlayers[p.name] then
            activePlayers[#activePlayers + 1] = p
        end
    end

    if #activePlayers < 5 then
        self:Print("Need at least 5 players to form a group.")
        return
    end

    -- Capture algorithm inputs before running
    local playerDicts = {}
    for _, p in ipairs(activePlayers) do
        playerDicts[#playerDicts + 1] = p:ToDict()
    end

    local previousGroups = self:GetLastGroups()
    local lastGroupDicts = {}
    for _, g in ipairs(previousGroups) do
        lastGroupDicts[#lastGroupDicts + 1] = g:ToDict()
    end

    self.session.groups = self:CreateMythicPlusGroups(activePlayers)
    self.session.status = self.Status.SPINNING

    -- Wago Analytics
    self.analytics:IncrementCounter("spins")
    self.analytics:IncrementCounter("groupsFormed", #self.session.groups)
    self.analytics:IncrementCounter("totalPlayersInLobbies", #activePlayers)

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
        playerCount = #activePlayers,
    }

    self.lastActivity = time()
    self:BroadcastSessionUpdate()
    -- Re-send after a short delay for reliability with large groups
    if #self.session.groups > 1 then
        C_Timer.After(2, function()
            if WHLSN.session.status == WHLSN.Status.SPINNING then
                WHLSN:SendSessionUpdate()
            end
        end)
    end
    self:UpdateUI()
    self:PersistSessionState()
end

--- Mark session as completed after wheel animation finishes.
function WHLSN:CompleteSession()
    self.session.status = self.Status.COMPLETED
    self:SaveSessionResults()
    if self:IsHost() then
        self:BroadcastSessionUpdate()
    end
    self:PersistSessionState()
end

--- Save session results to SavedVariables.
function WHLSN:SaveSessionResults()
    if self.session.isTest then return end
    if not self.db then return end

    local groupData = {}
    for _, g in ipairs(self.session.groups) do
        groupData[#groupData + 1] = g:ToDict()
    end

    local snap = self.session.algorithmSnapshot
    local sessionRecord = {
        groups = groupData,
        host = self.session.host,
        playerCount = snap and snap.playerCount or #self.session.players,
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
        self:Print("Lobby not found.")
        return
    end

    local record = history[index]
    if not record.groups or #record.groups == 0 then
        self:Print("No group data for that lobby.")
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

--- Hide a player from the session (host only). Player stays in the list
--- but is excluded from group formation and shown as dimmed/struck-through.
---@param playerName string
function WHLSN:HidePlayer(playerName)
    if not self:NamesMatch(self.session.host, self:GetMyFullName()) then return end
    if self.session.status ~= self.Status.LOBBY then return end
    if self:NamesMatch(playerName, self:GetMyFullName()) then return end

    for _, p in ipairs(self.session.players) do
        if self:NamesMatch(p.name, playerName) then
            self.session.removedPlayers[p.name] = true
            self:NotifySessionChange()
            self:Print(self:StripRealmName(playerName) .. " hidden from lobby.")
            return
        end
    end
end

--- Unhide a previously hidden player (host only).
---@param playerName string
function WHLSN:UnhidePlayer(playerName)
    if not self:NamesMatch(self.session.host, self:GetMyFullName()) then return end
    if self.session.status ~= self.Status.LOBBY then return end

    for _, p in ipairs(self.session.players) do
        if self:NamesMatch(p.name, playerName) then
            self.session.removedPlayers[p.name] = nil
            self:NotifySessionChange()
            self:Print(self:StripRealmName(playerName) .. " restored to lobby.")
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

    self:Print("Lobby timed out after " .. math.floor(self.SESSION_TIMEOUT / 60) .. " minutes of inactivity.")
    self:CloseLobby()
end

--- Touch the session activity timer (called on meaningful actions).
function WHLSN:TouchActivity()
    self.lastActivity = time()
    self:ResetSessionTimeout()
end

--- Clear all local session state (shared by host CloseLobby and non-host Finish).
function WHLSN:ClearSessionState()
    self:CancelSessionTimeout()
    if self.commThrottleTimer then
        self.commThrottleTimer:Cancel()
        self.commThrottleTimer = nil
    end
    self.commPendingUpdate = false
    self.session.status = nil
    self.session.host = nil
    self.session.players = {}
    self.session.groups = {}
    self.session.algorithmSnapshot = nil
    self.session.viewingHistory = false
    self.session.hostEnded = false
    self.session.isTest = nil
    self.session.connectedCommunity = {}
    self.session.removedPlayers = {}
    self.session.commChannel = nil
    self.session.joinPending = false
    if self.joinAckTimer then
        self.joinAckTimer:Cancel()
        self.joinAckTimer = nil
    end
    self.commQueue = {}
    if self.db and self.db.char then
        self.db.char.activeSession = nil
    end
    if self.sessionRestoreTimer then
        self.sessionRestoreTimer:Cancel()
        self.sessionRestoreTimer = nil
    end
end

--- Persist minimal session state to SavedVariables for /reload recovery.
function WHLSN:PersistSessionState()
    if not self.db or not self.db.char then return end
    if not self.session.status then
        self.db.char.activeSession = nil
        return
    end

    local isHost = self:NamesMatch(self.session.host, self:GetMyFullName())

    local saved = {
        host = self.session.host,
        status = self.session.status,
        commChannel = self.session.commChannel,
        timestamp = time(),
        isHost = isHost,
    }

    if isHost then
        local playerDicts = {}
        for _, p in ipairs(self.session.players) do
            playerDicts[#playerDicts + 1] = p:ToDict()
        end
        saved.players = playerDicts
        saved.removedPlayers = self.session.removedPlayers
        saved.connectedCommunity = self.session.connectedCommunity
    end

    self.db.char.activeSession = saved
end

--- Restore session state from SavedVariables after /reload.
function WHLSN:RestoreSessionState()
    if not self.db or not self.db.char then return end

    local saved = self.db.char.activeSession
    if not saved then return end

    if saved.timestamp and (time() - saved.timestamp) > self.SESSION_TIMEOUT then
        self.db.char.activeSession = nil
        return
    end

    self.session.status = saved.status
    self.session.host = saved.host
    self.session.commChannel = saved.commChannel

    if saved.isHost then
        if saved.players then
            self.session.players = {}
            for _, pd in ipairs(saved.players) do
                self.session.players[#self.session.players + 1] = WHLSN.Player.FromDict(pd)
            end
        end
        if saved.removedPlayers then
            self.session.removedPlayers = saved.removedPlayers
        end
        if saved.connectedCommunity then
            self.session.connectedCommunity = saved.connectedCommunity
        end
        self:SendSessionUpdate()
        self:ResetSessionTimeout()
    else
        self:SendSessionQuery()
        self.sessionRestoreTimer = C_Timer.NewTimer(10, function()
            if WHLSN.session.status and #WHLSN.session.players == 0 then
                WHLSN:Print("Previous lobby is no longer active.")
                WHLSN:ClearSessionState()
                WHLSN:UpdateUI()
            end
            WHLSN.sessionRestoreTimer = nil
        end)
    end
end
