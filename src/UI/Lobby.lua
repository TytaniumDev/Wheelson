---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Lobby View
-- Shows player list and "Spin" button (mirrors activity lobby UI)
---------------------------------------------------------------------------

local lobbyState = { frame = nil, playerRows = {}, historyRows = {} }

local ROLE_ICONS = {
    tank = "Interface\\LFGFrame\\LFGRole_BW",
    healer = "Interface\\LFGFrame\\LFGRole_BW",
    ranged = "Interface\\LFGFrame\\LFGRole_BW",
    melee = "Interface\\LFGFrame\\LFGRole_BW",
}

local ROLE_TEXCOORDS = {
    tank = { 0.5, 0.75, 0, 1 },
    healer = { 0.75, 1, 0, 1 },
    ranged = { 0.25, 0.5, 0, 1 },
    melee = { 0, 0.25, 0, 1 },
}


local function CreateLobbyFrame(parent)
    local frame = CreateFrame("Frame", "WHLSNLobbyFrame", parent)
    frame:SetAllPoints()

    -- Status text
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.statusText:SetPoint("TOP", 0, -4)
    frame.statusText:SetText("Waiting for players...")

    -- Player count and role summary
    frame.countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.countText:SetPoint("TOPRIGHT", -4, -4)
    frame.countText:SetTextColor(0.7, 0.7, 0.7)

    -- Role composition summary
    frame.roleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.roleText:SetPoint("TOPRIGHT", -4, -16)
    frame.roleText:SetTextColor(0.6, 0.6, 0.6)

    -- Scroll frame for player list
    frame.scrollFrame = CreateFrame("ScrollFrame", "WHLSNLobbyScrollFrame", frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", 4, -32)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 48)

    frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth())
    frame.scrollChild:SetHeight(1)
    frame.scrollFrame:SetScrollChild(frame.scrollChild)

    -- Spin button (host only)
    frame.spinButton = CreateFrame("Button", "WHLSNSpinButton", frame, "UIPanelButtonTemplate")
    frame.spinButton:SetSize(160, 32)
    frame.spinButton:SetPoint("BOTTOM", 0, 8)
    frame.spinButton:SetText("Spin the Wheel!")
    frame.spinButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:SpinGroups()
    end)

    -- Join button (for non-hosts)
    frame.joinButton = CreateFrame("Button", "WHLSNJoinButton", frame, "UIPanelButtonTemplate")
    frame.joinButton:SetSize(100, 32)
    frame.joinButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.joinButton:SetText("Join Session")
    frame.joinButton:SetScript("OnClick", function()
        WHLSN:RequestJoin()
    end)

    -- Leave button (for non-hosts who have joined)
    frame.leaveButton = CreateFrame("Button", "WHLSNLeaveButton", frame, "UIPanelButtonTemplate")
    frame.leaveButton:SetSize(100, 32)
    frame.leaveButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.leaveButton:SetText("Leave")
    frame.leaveButton:SetScript("OnClick", function()
        WHLSN:LeaveSession()
    end)

    -- Start Session button (shown when no session is active)
    frame.startButton = CreateFrame("Button", "WHLSNStartButton", frame, "UIPanelButtonTemplate")
    frame.startButton:SetSize(140, 32)
    frame.startButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.startButton:SetText("Start Session")
    frame.startButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:StartSession()
    end)

    -- Test button (shown when no session is active, next to Start Session)
    frame.testButton = CreateFrame("Button", "WHLSNTestButton", frame, "UIPanelButtonTemplate")
    frame.testButton:SetSize(80, 32)
    frame.testButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.testButton:SetText("Test")
    frame.testButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:StartTestSession()
    end)

    -- End Session button (host only, active session)
    frame.endButton = CreateFrame("Button", "WHLSNEndButton", frame, "UIPanelButtonTemplate")
    frame.endButton:SetSize(100, 32)
    frame.endButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.endButton:SetText("End Session")
    frame.endButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:EndSession()
    end)

    -- Add Player button (host only, during active session)
    frame.addPlayerButton = CreateFrame("Button", "WHLSNAddPlayerButton", frame, "UIPanelButtonTemplate")
    frame.addPlayerButton:SetSize(80, 32)
    frame.addPlayerButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.addPlayerButton:SetText("Add Player")
    frame.addPlayerButton:SetScript("OnClick", function()
        if frame.addPlayerInput:IsShown() then
            frame.addPlayerInput:Hide()
            frame.addPlayerConfirm:Hide()
        else
            frame.addPlayerInput:Show()
            frame.addPlayerConfirm:Show()
            frame.addPlayerInput:SetFocus()
        end
    end)

    -- Add Player input (hidden by default)
    frame.addPlayerInput = CreateFrame("EditBox", "WHLSNAddPlayerInput", frame, "InputBoxTemplate")
    frame.addPlayerInput:SetSize(160, 20)
    frame.addPlayerInput:SetPoint("BOTTOMRIGHT", frame.addPlayerButton, "TOPRIGHT", 0, 4)
    frame.addPlayerInput:SetAutoFocus(false)
    frame.addPlayerInput:Hide()

    -- Confirm button for add player
    frame.addPlayerConfirm = CreateFrame("Button", "WHLSNAddPlayerConfirm", frame, "UIPanelButtonTemplate")
    frame.addPlayerConfirm:SetSize(40, 20)
    frame.addPlayerConfirm:SetPoint("RIGHT", frame.addPlayerInput, "LEFT", -2, 0)
    frame.addPlayerConfirm:SetText("OK")
    frame.addPlayerConfirm:Hide()

    local function ConfirmAddPlayer()
        local name = frame.addPlayerInput:GetText()
        if name and strtrim(name) ~= "" then
            local ok, err = WHLSN:AddCommunityPlayer(name)
            if ok then
                local normalized = WHLSN:NormalizeCommunityName(name)
                WHLSN:Print("Added " .. normalized .. " to community roster.")
                -- Immediately ping if session is active
                if WHLSN.session.status == WHLSN.Status.LOBBY then
                    local pingData = {
                        type = "SESSION_PING",
                        host = UnitName("player"),
                        status = WHLSN.session.status,
                        version = WHLSN.VERSION,
                    }
                    local serialized = WHLSN:Serialize(pingData)
                    WHLSN:SendCommMessage(WHLSN.COMM_PREFIX, serialized, "WHISPER", normalized)
                end
            else
                WHLSN:Print("Could not add: " .. (err or "unknown error"))
            end
        end
        frame.addPlayerInput:SetText("")
        frame.addPlayerInput:Hide()
        frame.addPlayerConfirm:Hide()
    end

    frame.addPlayerConfirm:SetScript("OnClick", ConfirmAddPlayer)
    frame.addPlayerInput:SetScript("OnEnterPressed", ConfirmAddPlayer)
    frame.addPlayerInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:Hide()
        frame.addPlayerConfirm:Hide()
    end)

    return frame
end

local function CreatePlayerRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 26)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * 26)
    row:EnableMouse(true)

    -- Class icon
    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(18, 18)
    row.classIcon:SetPoint("LEFT", 4, 0)
    row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

    -- Role icon
    row.roleIcon = row:CreateTexture(nil, "ARTWORK")
    row.roleIcon:SetSize(20, 20)
    row.roleIcon:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)

    -- Player name
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row.roleIcon, "RIGHT", 8, 0)
    row.nameText:SetJustifyH("LEFT")

    -- Utility icons
    row.brezIcon = row:CreateTexture(nil, "ARTWORK")
    row.brezIcon:SetSize(16, 16)
    row.brezIcon:SetPoint("RIGHT", -48, 0)
    row.brezIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

    row.lustIcon = row:CreateTexture(nil, "ARTWORK")
    row.lustIcon:SetSize(16, 16)
    row.lustIcon:SetPoint("RIGHT", -28, 0)
    row.lustIcon:SetTexture(WHLSN.LUST_ICON)

    -- Kick button (host only, shown on hover)
    row.kickButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.kickButton:SetSize(40, 18)
    row.kickButton:SetPoint("RIGHT", -4, 0)
    row.kickButton:SetText("X")
    row.kickButton:Hide()

    -- Tooltip for utility details + kick button hover
    row:SetScript("OnEnter", function(self)
        if self.playerData then
            WHLSN:ShowPlayerTooltip(self, self.playerData)
        end

        -- Show kick button if host
        if WHLSN.session.host == UnitName("player") and self.playerData then
            if self.playerData.name ~= UnitName("player") then
                self.kickButton:Show()
            end
        end
    end)

    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.kickButton:Hide()
    end)

    return row
end

local function CreateHistoryRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * 22)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)

    row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.dateText:SetPoint("LEFT", 4, 0)
    row.dateText:SetWidth(100)
    row.dateText:SetJustifyH("LEFT")
    row.dateText:SetTextColor(0.7, 0.7, 0.7)

    row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.infoText:SetPoint("LEFT", row.dateText, "RIGHT", 8, 0)
    row.infoText:SetPoint("RIGHT", -4, 0)
    row.infoText:SetJustifyH("LEFT")

    return row
end

--- Hide the lobby view.
function WHLSN:HideLobbyView()
    if lobbyState.frame then lobbyState.frame:Hide() end
end

--- Show the lobby view inside the given content frame.
function WHLSN:ShowLobbyView(parent)
    if not lobbyState.frame then
        lobbyState.frame = CreateLobbyFrame(parent)
    end
    lobbyState.frame:SetParent(parent)
    lobbyState.frame:SetAllPoints()
    lobbyState.frame:Show()
end

---------------------------------------------------------------------------
-- UpdateLobbyView sub-functions
---------------------------------------------------------------------------

local function UpdateLobbyStatus(frame, session, hasSession)
    if hasSession then
        frame.statusText:SetText("Lobby - Hosted by " .. (session.host or "Unknown"))
    else
        frame.statusText:SetText("No active session")
    end
end

local function UpdateLobbyButtons(frame, isHost, hasSession, isInSession, playerCount)
    frame.spinButton:SetShown(isHost and hasSession)
    frame.spinButton:SetEnabled(playerCount >= 5)
    frame.joinButton:SetShown(not isHost and hasSession and not isInSession)
    frame.leaveButton:SetShown(not isHost and hasSession and isInSession)
    frame.startButton:SetShown(not hasSession)
    frame.testButton:SetShown(not hasSession)
    frame.endButton:SetShown(isHost and hasSession)
    frame.addPlayerButton:SetShown(isHost and hasSession)
    if not (isHost and hasSession) then
        frame.addPlayerInput:Hide()
        frame.addPlayerConfirm:Hide()
    end
end

local function PopulatePlayerRows(frame, players)
    local rows = lobbyState.playerRows
    for i, player in ipairs(players) do
        if not rows[i] then
            rows[i] = CreatePlayerRow(frame.scrollChild, i)
        end

        local row = rows[i]
        row.playerData = player
        row.nameText:SetText(player.name)

        local role = player.mainRole
        if role and ROLE_TEXCOORDS[role] then
            row.roleIcon:SetTexture(ROLE_ICONS[role])
            local tc = ROLE_TEXCOORDS[role]
            row.roleIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            row.roleIcon:Show()

            local rc = WHLSN.RoleColors[role]
            row.nameText:SetTextColor(rc.r, rc.g, rc.b)
        else
            row.roleIcon:Hide()
            row.nameText:SetTextColor(1, 1, 1)
        end

        row.classIcon:Hide()
        row.brezIcon:SetShown(player:HasBrez())
        row.lustIcon:SetShown(player:HasLust())

        row.kickButton:SetScript("OnClick", function()
            WHLSN:KickPlayer(player.name)
        end)
        row.kickButton:Hide()

        row:Show()
    end

    frame.scrollChild:SetHeight(math.max(1, #players * 26))
end

local function PopulateHistoryRows(frame, history)
    local rows = lobbyState.historyRows
    frame.statusText:SetText("Recent Sessions")
    frame.countText:SetText(#history .. " sessions")

    for i, record in ipairs(history) do
        if not rows[i] then
            rows[i] = CreateHistoryRow(frame.scrollChild, i)
        end

        local row = rows[i]
        local dateStr = record.timestamp and date("%m/%d %H:%M", record.timestamp) or "Unknown"
        local groupCount = record.groups and #record.groups or 0
        local playerCount = record.playerCount or 0

        row.dateText:SetText(dateStr)
        row.infoText:SetText(string.format("%s  |  %d players, %d groups",
            record.host or "Unknown", playerCount, groupCount))

        local idx = i
        row:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            WHLSN:ViewHistorySession(idx)
        end)

        row:Show()
    end

    frame.scrollChild:SetHeight(math.max(1, #history * 22))
end

--- Update the lobby view with current session data.
function WHLSN:UpdateLobbyView()
    local frame = lobbyState.frame
    if not frame then return end

    local players = self.session.players
    local isHost = self.session.host == UnitName("player")
    local hasSession = self.session.status ~= nil
    local myName = UnitName("player")

    UpdateLobbyStatus(frame, self.session, hasSession)

    frame.countText:SetText(#players .. " players")

    if #players > 0 then
        frame.roleText:SetText(self:GetRoleCountSummary(players))
    else
        frame.roleText:SetText("")
    end

    local isInSession = false
    for _, p in ipairs(players) do
        if self:StripRealmName(p.name) == myName then
            isInSession = true
            break
        end
    end

    UpdateLobbyButtons(frame, isHost, hasSession, isInSession, #players)

    -- Hide all dynamic rows before repopulating
    for _, row in ipairs(lobbyState.playerRows) do row:Hide() end
    for _, row in ipairs(lobbyState.historyRows) do row:Hide() end

    if hasSession then
        PopulatePlayerRows(frame, players)
    else
        local history = self.db and self.db.profile.sessionHistory
        if history and #history > 0 then
            PopulateHistoryRows(frame, history)
        else
            frame.scrollChild:SetHeight(1)
        end
    end
end

--- Send a join request to the session host.
function WHLSN:RequestJoin()
    if not self.session.host then
        self:Print("No active session to join.")
        return
    end

    if self.session.hostEnded then
        self:Print("That session has ended.")
        return
    end

    self.leftSessionHost = nil

    local playerData = WHLSN:DetectLocalPlayer()
    if not playerData then
        self:Print("Could not detect your spec. Make sure you have a specialization active.")
        return
    end

    local data = {
        type = "JOIN_REQUEST",
        player = playerData:ToDict(),
    }

    local serialized = self:Serialize(data)

    if self.session.commChannel == "WHISPER" and self.session.hostFullName then
        self:SendCommMessage(self.COMM_PREFIX, serialized, "WHISPER", self.session.hostFullName)
    else
        self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
    end

    self:Print("Join request sent.")
end
