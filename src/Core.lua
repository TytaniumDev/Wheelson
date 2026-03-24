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
        hostEnded = false, -- true when the host explicitly ended the session
        connectedCommunity = {},  -- sender -> sender (host only, realm-qualified keys)
        removedPlayers = {},      -- full player name -> true (hidden from group formation)
        commChannel = nil,        -- "GUILD" or "WHISPER" (community clients only)
        joinPending = false,      -- true while waiting for JOIN_ACK from host
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

    -- Queue for messages that could not be sent due to encounter restrictions
    self.commQueue = {}

    -- Addon user discovery cache (ephemeral, not saved)
    self.addonUsersCache = {}
    self.isScanning = false

    -- Throttle timestamp for SESSION_QUERY broadcasts
    self.lastSessionQuery = 0

    self:RegisterComm(self.COMM_PREFIX)
    self:RestoreSessionState()

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
            elseif button == "MiddleButton" then
                WHLSN:ToggleMinimapIcon()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Wheelson", 1, 0.82, 0)
            tooltip:AddLine("|cFFAAAAAA" .. WHLSN.VERSION .. "|r")
            if WHLSN.session.status then
                tooltip:AddLine("Lobby: " .. WHLSN.session.status, 0.5, 1, 0.5)
                tooltip:AddLine("Host: " .. WHLSN:StripRealmName(WHLSN.session.host or "Unknown"), 0.7, 0.7, 0.7)
            else
                tooltip:AddLine("No active lobby", 0.5, 0.5, 0.5)
            end
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFFFFFFFFLeft-click:|r Open addon", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cFFFFFFFFRight-click:|r Debug panel", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cFFFFFFFFMiddle-click:|r Hide icon", 0.8, 0.8, 0.8)
        end,
    })
    self.ldbIcon:Register("Wheelson", launcher, self.db.profile.minimap)

    self:SetupOptionsPanel()
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
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self:RegisterEvent("CHALLENGE_MODE_RESET")
    self:RegisterEvent("PVP_MATCH_COMPLETE")
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

SlashCmdList["WHEELSON"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "minimap" then
        WHLSN:ToggleMinimapIcon()
    else
        WHLSN:ToggleMainFrame()
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

function WHLSN:SetupOptionsPanel()
    -- Overridden by UI/OptionsPanel.lua
end
