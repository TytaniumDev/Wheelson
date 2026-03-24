---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Lobby View
-- Shows player list and "Spin" button (mirrors activity lobby UI)
---------------------------------------------------------------------------

local lobbyState = { frame = nil, playerRows = {}, historyRows = {}, specSection = nil }

local ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\LFGRole_BW"

local ROLE_TEXCOORDS = {
    tank = { 0.5, 0.75, 0, 1 },
    healer = { 0.75, 1, 0, 1 },
    ranged = { 0, 0.25, 0, 1 },   -- matches melee (sword)
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
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 110)

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
    frame.spinButton:SetMotionScriptsWhileDisabled(true)
    frame.spinButton:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Need at least 5 players to spin", 1, 0.1, 0.1)
            GameTooltip:Show()
        end
    end)
    frame.spinButton:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    -- Join button (for non-hosts)
    frame.joinButton = CreateFrame("Button", "WHLSNJoinButton", frame, "UIPanelButtonTemplate")
    frame.joinButton:SetSize(100, 32)
    frame.joinButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.joinButton:SetText("Join Lobby")
    frame.joinButton:SetScript("OnClick", function()
        WHLSN:RequestJoin()
    end)
    frame.joinButton:SetMotionScriptsWhileDisabled(true)
    frame.joinButton:SetScript("OnEnter", function(self)
        if not self:IsEnabled() and self:GetText() == "Joining..." then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Waiting for response...", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.joinButton:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    -- Leave button (for non-hosts who have joined)
    frame.leaveButton = CreateFrame("Button", "WHLSNLeaveButton", frame, "UIPanelButtonTemplate")
    frame.leaveButton:SetSize(100, 32)
    frame.leaveButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.leaveButton:SetText("Leave")
    frame.leaveButton:SetScript("OnClick", function()
        WHLSN:LeaveSession()
    end)

    -- Create Lobby button (shown when no lobby is active)
    frame.startButton = CreateFrame("Button", "WHLSNStartButton", frame, "UIPanelButtonTemplate")
    frame.startButton:SetSize(140, 32)
    frame.startButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.startButton:SetText("Create Lobby")
    frame.startButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:CreateLobby()
    end)

    -- Test button (shown when no lobby is active, next to Create Lobby)
    frame.testButton = CreateFrame("Button", "WHLSNTestButton", frame, "UIPanelButtonTemplate")
    frame.testButton:SetSize(80, 32)
    frame.testButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.testButton:SetText("Test")
    frame.testButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:CreateTestLobby()
    end)

    -- Close Lobby button (host only, active lobby)
    frame.endButton = CreateFrame("Button", "WHLSNEndButton", frame, "UIPanelButtonTemplate")
    frame.endButton:SetSize(100, 32)
    frame.endButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.endButton:SetText("Close Lobby")
    frame.endButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        WHLSN:CloseLobby()
    end)

    -- Community Roster button (host only, during active lobby)
    frame.communityRosterButton = CreateFrame("Button", "WHLSNCommunityRosterButton", frame, "UIPanelButtonTemplate")
    frame.communityRosterButton:SetSize(120, 32)
    frame.communityRosterButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.communityRosterButton:SetText("Community Roster")
    frame.communityRosterButton:SetScript("OnClick", function()
        WHLSN:ToggleCommunityPanel()
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
    row.brezIcon:SetPoint("RIGHT", -68, 0)
    row.brezIcon:SetTexture(WHLSN.BREZ_ICON)

    row.lustIcon = row:CreateTexture(nil, "ARTWORK")
    row.lustIcon:SetSize(16, 16)
    row.lustIcon:SetPoint("RIGHT", -48, 0)
    row.lustIcon:SetTexture(WHLSN.LUST_ICON)

    -- Strikethrough line (hidden by default)
    row.strikethrough = row:CreateTexture(nil, "OVERLAY")
    row.strikethrough:SetHeight(1)
    row.strikethrough:SetPoint("LEFT", row.roleIcon, "LEFT", 0, 0)
    row.strikethrough:SetPoint("RIGHT", row.lustIcon, "RIGHT", 0, 0)
    row.strikethrough:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    row.strikethrough:Hide()

    -- Kick button (host only, shown on hover)
    row.kickButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.kickButton:SetSize(40, 18)
    row.kickButton:SetPoint("RIGHT", -4, 0)
    row.kickButton:SetText("X")
    row.kickButton:Hide()

    local function ShowHover(rowFrame)
        if rowFrame.playerData then
            WHLSN:ShowPlayerTooltip(rowFrame, rowFrame.playerData)
        end

        -- Show kick button if host
        if WHLSN:NamesMatch(WHLSN.session.host, WHLSN:GetMyFullName()) and rowFrame.playerData then
            if not WHLSN:NamesMatch(rowFrame.playerData.name, WHLSN:GetMyFullName()) then
                rowFrame.kickButton:Show()
            end
        end
    end

    local function HideHover(rowFrame)
        if not rowFrame:IsMouseOver() then
            GameTooltip:Hide()
            rowFrame.kickButton:Hide()
        end
    end

    row.kickButton:SetScript("OnEnter", function(btn)
        -- Don't call ShowHover since it resets tooltip and shows player info.
        -- We only want to show the specific button tooltip.
        if btn.tooltipText then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(btn.tooltipText, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    row.kickButton:SetScript("OnLeave", function(btn)
        -- When leaving the button, we should show the player tooltip again
        -- if we are still hovering the row.
        if btn:GetParent():IsMouseOver() then
            ShowHover(btn:GetParent())
        else
            HideHover(btn:GetParent())
        end
    end)

    -- Tooltip for utility details + kick button hover
    row:SetScript("OnEnter", ShowHover)
    row:SetScript("OnLeave", HideHover)

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
        lobbyState.specSection = WHLSN.CreateSpecOverrideSection(lobbyState.frame)
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
        frame.statusText:SetText("Lobby - Hosted by " .. WHLSN:StripRealmName(session.host or "Unknown"))
    else
        frame.statusText:SetText("No active lobby")
    end
end

local function UpdateLobbyButtons(frame, isHost, hasSession, isInSession, playerCount)
    frame.spinButton:SetShown(isHost and hasSession)
    frame.spinButton:SetEnabled(playerCount >= 5)
    local isPending = WHLSN.session.joinPending or false
    frame.joinButton:SetShown(not isHost and hasSession and not isInSession and not isPending)
    frame.leaveButton:SetShown(not isHost and hasSession and isInSession)
    frame.startButton:SetShown(not hasSession)
    frame.testButton:SetShown(not hasSession)
    frame.endButton:SetShown(isHost and hasSession)
    frame.communityRosterButton:SetShown(isHost and hasSession)
    if not (isHost and hasSession) then
        WHLSN:HideCommunityPanel()
    end
    -- Show "Joining..." text when pending
    if isPending and not isInSession then
        frame.joinButton:SetShown(true)
        frame.joinButton:SetText("Joining...")
        frame.joinButton:SetEnabled(false)
    else
        frame.joinButton:SetText("Join Lobby")
        frame.joinButton:SetEnabled(true)
    end
end

--- Build a WoW color-escaped string showing the player's name, main role, and offspecs.
---@param player WHLSNPlayer
---@param classColor table|nil  { r, g, b, hex }
---@return string
local function FormatPlayerLabel(player, classColor)
    local hex = classColor and classColor.hex or "FFFFFF"
    local parts = { "|cFF" .. hex .. WHLSN:StripRealmName(player.name) .. "|r" }

    if player.mainRole then
        local rc = WHLSN.RoleColors[player.mainRole]
        if rc then
            parts[#parts + 1] = " |cFF" .. rc.hex .. player.mainRole .. "|r"
        end
    end

    if #player.offspecs > 0 then
        parts[#parts + 1] = " |cFF808080| off:|r "
        for i, spec in ipairs(player.offspecs) do
            if i > 1 then
                parts[#parts + 1] = "|cFF808080, |r"
            end
            local rc = WHLSN.RoleColors[spec]
            if rc then
                parts[#parts + 1] = "|cFF" .. rc.hex .. spec .. "|r"
            else
                parts[#parts + 1] = spec
            end
        end
    end

    return table.concat(parts)
end

local function PopulatePlayerRows(frame, players)
    local rows = lobbyState.playerRows
    for i, player in ipairs(players) do
        if not rows[i] then
            rows[i] = CreatePlayerRow(frame.scrollChild, i)
        end

        local row = rows[i]
        row.playerData = player

        local role = player.mainRole
        if role and ROLE_TEXCOORDS[role] then
            row.roleIcon:SetTexture(ROLE_ICON_TEXTURE)
            local tc = ROLE_TEXCOORDS[role]
            row.roleIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            row.roleIcon:Show()
        else
            row.roleIcon:Hide()
        end

        local cc = player.classToken and WHLSN.CLASS_COLORS[player.classToken]
        row.nameText:SetText(FormatPlayerLabel(player, cc))
        row.nameText:SetTextColor(1, 1, 1)  -- color is in the escape sequences now

        row.classIcon:Hide()
        row.brezIcon:SetShown(player:HasBrez())
        row.lustIcon:SetShown(player:HasLust())

        local isRemoved = WHLSN.session.removedPlayers
            and WHLSN.session.removedPlayers[player.name]

        if isRemoved then
            row.nameText:SetAlpha(0.35)
            row.roleIcon:SetAlpha(0.35)
            row.brezIcon:SetAlpha(0.35)
            row.lustIcon:SetAlpha(0.35)
            row.strikethrough:Show()
            row.kickButton:SetText("+")
            row.kickButton.tooltipText = "Include in lobby"
            row.kickButton:SetScript("OnClick", function()
                WHLSN:UnhidePlayer(player.name)
            end)
        else
            row.nameText:SetAlpha(1)
            row.roleIcon:SetAlpha(1)
            row.brezIcon:SetAlpha(1)
            row.lustIcon:SetAlpha(1)
            row.strikethrough:Hide()
            row.kickButton:SetText("X")
            row.kickButton.tooltipText = "Remove from lobby"
            row.kickButton:SetScript("OnClick", function()
                WHLSN:HidePlayer(player.name)
            end)
        end
        row.kickButton:Hide()

        row:Show()
    end

    frame.scrollChild:SetHeight(math.max(1, #players * 26))
end

local function PopulateHistoryRows(frame, history)
    local rows = lobbyState.historyRows
    frame.statusText:SetText("Recent Lobbies")
    frame.countText:SetText(#history .. " lobbies")

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
    local isHost = self:NamesMatch(self.session.host, self:GetMyFullName())
    local hasSession = self.session.status ~= nil

    UpdateLobbyStatus(frame, self.session, hasSession)

    -- Count only active (non-removed) players
    local activePlayers = {}
    for _, p in ipairs(players) do
        if not self.session.removedPlayers
            or not self.session.removedPlayers[p.name] then
            activePlayers[#activePlayers + 1] = p
        end
    end

    frame.countText:SetText(#activePlayers .. " players")

    if #activePlayers > 0 then
        frame.roleText:SetText(self:GetRoleCountSummary(activePlayers))
    else
        frame.roleText:SetText("")
    end

    local isInSession = false
    for _, p in ipairs(players) do
        if self:NamesMatch(p.name, self:GetMyFullName()) then
            isInSession = true
            break
        end
    end

    UpdateLobbyButtons(frame, isHost, hasSession, isInSession, #activePlayers)

    -- Show spec override section only when local player is in an active lobby session
    local specSection = lobbyState.specSection
    if specSection then
        local showSpec = hasSession and isInSession
        specSection:SetShown(showSpec)
        if showSpec and not specSection.initialized then
            specSection:Initialize()
            specSection.initialized = true
        end
    end

    -- Hide all dynamic rows before repopulating
    for _, row in ipairs(lobbyState.playerRows) do row:Hide() end
    for _, row in ipairs(lobbyState.historyRows) do row:Hide() end

    if hasSession then
        PopulatePlayerRows(frame, players)
    else
        if specSection then
            specSection.initialized = false
        end
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
        self:Print("No active lobby to join.")
        return
    end

    if self.session.hostEnded then
        self:Print("That lobby has ended.")
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

    if self.session.commChannel == "WHISPER" and self.session.host then
        self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "WHISPER", self.session.host)
    else
        self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
    end

    self:Print("Join request sent.")
    self.session.joinPending = true
    self.joinAckTimer = C_Timer.NewTimer(5, function()
        WHLSN.session.joinPending = false
        WHLSN.joinAckTimer = nil
        WHLSN:Print("Join request may not have been received. Try again.")
        WHLSN:UpdateLobbyView()
    end)
    self:UpdateLobbyView()
end
