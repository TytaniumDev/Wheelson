---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Group Display View (final results)
---------------------------------------------------------------------------

local displayFrame = nil
local cardPool = {}

local CARD_HEIGHT = 106
local DEFAULT_ROLE_COLOR = "CCCCCC"
local UTILITY_MISSING_ALPHA = 0.3
local UTILITY_MISSING_COLOR = "888888"
local UTILITY_NAME_OFFSET_X = -6

local function CreateGroupDisplayFrame(parent)
    local frame = CreateFrame("Frame", "WHLSNGroupDisplayFrame", parent)
    frame:SetAllPoints()

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -4)
    frame.title:SetText("|cFFFFD100Mythic+ Groups|r")

    -- Scroll frame for group results
    frame.scrollFrame = CreateFrame("ScrollFrame", "WHLSNResultsScrollFrame", frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", 4, -28)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", -28, 48)

    frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth())
    frame.scrollChild:SetHeight(1)
    frame.scrollFrame:SetScrollChild(frame.scrollChild)

    -- Bottom button bar
    frame.inviteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.inviteButton:SetSize(180, 34)
    frame.inviteButton:SetPoint("BOTTOM", 0, 8)
    frame.inviteButton:SetText("Invite My Group")
    frame.inviteButton:SetNormalFontObject("GameFontNormalLarge")
    frame.inviteButton:SetHighlightFontObject("GameFontHighlightLarge")
    frame.inviteButton:SetScript("OnClick", function()
        WHLSN:InviteMyGroup()
    end)

    frame.reportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.reportButton:SetSize(60, 24)
    frame.reportButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.reportButton:SetText("Report")
    frame.reportButton:SetScript("OnClick", function()
        if WHLSN.session.algorithmSnapshot then
            WHLSN:CopyReportToClipboard(WHLSN.session.algorithmSnapshot)
        else
            WHLSN:Print("No algorithm data available to report.")
        end
    end)

    frame.endButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.endButton:SetSize(70, 24)
    frame.endButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.endButton:SetText("Finish")
    frame.endButton:SetScript("OnClick", function()
        local isHost = WHLSN:NamesMatch(WHLSN.session.host, WHLSN:GetMyFullName())
        WHLSN:ToggleMainFrame()
        if isHost then
            WHLSN:CloseLobby()
        else
            WHLSN:ClearSessionState()
        end
    end)

    return frame
end

---------------------------------------------------------------------------
-- Card creation — build the shell with all reusable sub-elements
---------------------------------------------------------------------------

local function CreatePlayerLineFrame(card, lineIndex)
    local lineY = -24 - (lineIndex - 1) * 14
    local lineFrame = CreateFrame("Frame", nil, card)
    lineFrame:SetPoint("TOPLEFT", 12, lineY)
    lineFrame:SetPoint("TOPRIGHT", -132, lineY)
    lineFrame:SetHeight(14)
    lineFrame:EnableMouse(true)

    lineFrame.text = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lineFrame.text:SetPoint("LEFT")

    return lineFrame
end

local function CreateUtilityRowFrame(parent, yOffset, rowHeight, texturePath)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    row:SetHeight(rowHeight)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPRIGHT", 0, 0)
    row.icon:SetPoint("BOTTOMRIGHT", 0, 0)
    row.icon:SetWidth(rowHeight)
    row.icon:SetTexture(texturePath)

    row.names = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.names:SetPoint("RIGHT", row.icon, "LEFT", UTILITY_NAME_OFFSET_X, 0)
    row.names:SetJustifyH("RIGHT")
    row.names:SetJustifyV("MIDDLE")

    return row
end

--- Create a reusable group card shell with all sub-frames pre-created.
local function CreateGroupCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(CARD_HEIGHT)
    card:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.1, 0.1, 0.15, 0.9)

    card.header = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.header:SetPoint("TOPLEFT", 8, -6)

    -- 5 player line frames: [1]=tank, [2]=healer, [3..5]=dps
    card.lines = {}
    for i = 1, 5 do
        card.lines[i] = CreatePlayerLineFrame(card, i)
    end

    -- Utility panel
    local panelPadTop = 12
    local panelPadBottom = 12
    local panelPadRight = 4
    local panelGap = 12
    local panelHeight = CARD_HEIGHT - panelPadTop - panelPadBottom
    local rowHeight = math.floor((panelHeight - panelGap) / 2)

    card.utilPanel = CreateFrame("Frame", nil, card)
    card.utilPanel:SetPoint("TOPRIGHT", card, "TOPRIGHT", -panelPadRight, -panelPadTop)
    card.utilPanel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -panelPadRight, panelPadBottom)
    card.utilPanel:SetWidth(120)

    card.brezRow = CreateUtilityRowFrame(card.utilPanel, 0, rowHeight, WHLSN.BREZ_ICON)
    card.lustRow = CreateUtilityRowFrame(card.utilPanel, rowHeight + panelGap, rowHeight, WHLSN.LUST_ICON)

    return card
end

---------------------------------------------------------------------------
-- Card update — populate existing shell with group data
---------------------------------------------------------------------------

local function UpdatePlayerLine(lineFrame, prefix, hexColor, player)
    if player then
        local cc = player.classToken and WHLSN.CLASS_COLORS[player.classToken]
        local nameColor = cc and cc.hex or "FFFFFF"
        lineFrame.text:SetText("|cFF" .. hexColor .. prefix .. "|r  |cFF" .. nameColor .. player.name .. "|r")
        lineFrame:SetScript("OnEnter", function(self)
            WHLSN:ShowPlayerTooltip(self, player)
        end)
        lineFrame:SetScript("OnLeave", function(self)
            if GameTooltip:GetOwner() == self then
                GameTooltip:Hide()
            end
        end)
    else
        lineFrame.text:SetText("|cFF666666" .. prefix .. " (empty)|r")
        lineFrame:SetScript("OnEnter", nil)
        lineFrame:SetScript("OnLeave", nil)
    end
    lineFrame:Show()
end

local function UpdateUtilityRow(row, players)
    if #players == 0 then
        row.names:SetText("|cFF" .. UTILITY_MISSING_COLOR .. "—|r")
        row:SetAlpha(UTILITY_MISSING_ALPHA)
        row.icon:SetDesaturated(true)
    else
        local parts = {}
        for _, p in ipairs(players) do
            local cc = p.classToken and WHLSN.CLASS_COLORS[p.classToken]
            local c = cc and cc.hex or DEFAULT_ROLE_COLOR
            parts[#parts + 1] = "|cFF" .. c .. p.name .. "|r"
        end
        row.names:SetText(table.concat(parts, "\n"))
        row:SetAlpha(1)
        row.icon:SetDesaturated(false)
    end
end

local function UpdateGroupCard(card, index, group, yOffset)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, -yOffset)
    card:SetPoint("TOPRIGHT", 0, -yOffset)

    local size = group:GetSize()
    local completenessColor
    if size == 5 then
        completenessColor = "|cFF00FF00"
    elseif size == 4 then
        completenessColor = "|cFFFFFF00"
    else
        completenessColor = "|cFFFF0000"
    end
    card.header:SetText("|cFFFFD100Group " .. index .. "|r  " .. completenessColor .. "(" .. size .. "/5)|r")

    -- Update player lines
    UpdatePlayerLine(card.lines[1], "TANK", WHLSN.RoleColors.tank.hex, group.tank)
    UpdatePlayerLine(card.lines[2], "HEAL", WHLSN.RoleColors.healer.hex, group.healer)

    for di = 1, 3 do
        local dps = group.dps[di]
        if dps then
            local tag = dps:IsRanged() and "RDPS" or "MDPS"
            local roleKey = dps:IsRanged() and "ranged" or "melee"
            UpdatePlayerLine(card.lines[2 + di], tag, WHLSN.RoleColors[roleKey].hex, dps)
        else
            card.lines[2 + di].text:SetText("")
            card.lines[2 + di]:Hide()
        end
    end

    -- Update utility rows
    local brezPlayers = {}
    local lustPlayers = {}
    for _, p in ipairs(group:GetPlayers()) do
        if p:HasBrez() then brezPlayers[#brezPlayers + 1] = p end
        if p:HasLust() then lustPlayers[#lustPlayers + 1] = p end
    end
    UpdateUtilityRow(card.brezRow, brezPlayers)
    UpdateUtilityRow(card.lustRow, lustPlayers)

    card:Show()
    return CARD_HEIGHT + 8
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Hide the group display view.
function WHLSN:HideGroupDisplayView()
    if displayFrame then displayFrame:Hide() end
end

--- Show the group display view.
function WHLSN:ShowGroupDisplayView(parent)
    if not displayFrame then
        displayFrame = CreateGroupDisplayFrame(parent)
    end
    displayFrame:SetParent(parent)
    displayFrame:SetAllPoints()
    displayFrame:Show()
end

--- Update the group display with session results.
function WHLSN:UpdateGroupDisplayView()
    if not displayFrame then return end

    local isViewing = self.session.viewingHistory or false
    displayFrame.endButton:SetShown(true)
    displayFrame.inviteButton:SetShown(not isViewing)
    displayFrame.reportButton:SetShown(not isViewing and WHLSN.session.algorithmSnapshot ~= nil)

    if isViewing then
        displayFrame.title:SetText("|cFFFFD100Past Lobby Results|r")
        displayFrame.endButton:SetText("Close")
    else
        displayFrame.title:SetText("|cFFFFD100Mythic+ Groups|r")
        displayFrame.endButton:SetText("Finish")
    end

    -- Hide all pooled cards
    for ci = 1, #cardPool do
        cardPool[ci]:Hide()
    end

    -- Render each group, reusing pooled cards or creating new ones
    local yOffset = 0
    for i, group in ipairs(self.session.groups) do
        if not cardPool[i] then
            cardPool[i] = CreateGroupCard(displayFrame.scrollChild)
        end
        local height = UpdateGroupCard(cardPool[i], i, group, yOffset)
        yOffset = yOffset + height
    end

    displayFrame.scrollChild:SetHeight(math.max(1, yOffset))
end

--- Invite players from the group containing the local player.
function WHLSN:InviteMyGroup()
    for _, group in ipairs(self.session.groups) do
        for _, player in ipairs(group:GetPlayers()) do
            if self:NamesMatch(player.name, self:GetMyFullName()) then
                self:InvitePlayers(group:GetPlayers())
                return
            end
        end
    end
    self:Print("Could not find your group.")
end
