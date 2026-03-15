---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Group Display View (final results)
---------------------------------------------------------------------------

local displayFrame = nil

local ROLE_COLORS = {
    tank = "87BCDE",
    healer = "87FF87",
    ranged = "FF8787",
    melee = "FFD187",
}

local DEFAULT_ROLE_COLOR = "CCCCCC"
local UTILITY_MISSING_ALPHA = 0.3
local UTILITY_MISSING_COLOR = "888888"
local UTILITY_NAME_OFFSET_X = -6
local BREZ_ICON_PATH = "Interface\\Icons\\Spell_Nature_Reincarnation"
local LUST_ICON_PATH = "Interface\\Icons\\Spell_Nature_Bloodlust"

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

    -- Bottom button bar: chain left-to-right to avoid overlap
    -- Row 1 (left-aligned): Invite, Post, Report
    frame.inviteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.inviteButton:SetSize(130, 30)
    frame.inviteButton:SetPoint("BOTTOMLEFT", 8, 5)
    frame.inviteButton:SetText("Invite My Group")
    frame.inviteButton:GetFontString():SetFontObject("GameFontNormalLarge")
    frame.inviteButton:SetScript("OnClick", function()
        WHLSN:InviteMyGroup()
    end)

    frame.postButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.postButton:SetSize(90, 24)
    frame.postButton:SetPoint("LEFT", frame.inviteButton, "RIGHT", 4, 0)
    frame.postButton:SetText("Post to Guild")
    frame.postButton:SetScript("OnClick", function()
        WHLSN:PostToGuildChat(WHLSN.session.groups)
    end)

    frame.reportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.reportButton:SetSize(60, 24)
    frame.reportButton:SetPoint("LEFT", frame.postButton, "RIGHT", 4, 0)
    frame.reportButton:SetText("Report")
    frame.reportButton:SetScript("OnClick", function()
        if WHLSN.session.algorithmSnapshot then
            WHLSN:CopyReportToClipboard(WHLSN.session.algorithmSnapshot)
        else
            WHLSN:Print("No algorithm data available to report.")
        end
    end)

    -- Row 1 (right-aligned): Finish
    frame.endButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.endButton:SetSize(70, 24)
    frame.endButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.endButton:SetText("Finish")
    frame.endButton:SetScript("OnClick", function()
        WHLSN:EndSession()
        WHLSN:ToggleMainFrame()
    end)

    return frame
end

local function CreatePlayerLine(card, prefix, color, player, lineY)
    local lineFrame = CreateFrame("Frame", nil, card)
    lineFrame:SetPoint("TOPLEFT", 12, lineY)
    lineFrame:SetPoint("TOPRIGHT", -132, lineY)
    lineFrame:SetHeight(14)
    lineFrame:EnableMouse(true)

    local text = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT")
    if player then
        text:SetText(color .. prefix .. "|r  " .. player.name)
    else
        text:SetText("|cFF666666" .. prefix .. " (empty)|r")
    end

    -- Tooltip on hover showing player details
    if player then
        lineFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(player.name, 1, 1, 1)
            if player.mainRole then
                GameTooltip:AddLine("Role: " .. player.mainRole, 0.8, 0.8, 0.8)
            end
            if #player.offspecs > 0 then
                GameTooltip:AddLine("Offspecs: " .. table.concat(player.offspecs, ", "), 0.6, 0.6, 0.6)
            end
            if player:HasBrez() then
                GameTooltip:AddLine("Battle Rez", 0, 1, 0)
            end
            if player:HasLust() then
                GameTooltip:AddLine("Bloodlust/Heroism", 1, 0.27, 0)
            end
            GameTooltip:Show()
        end)
        lineFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return lineFrame
end

local function CreateUtilityRow(parent, yOffset, rowHeight, texturePath, players)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    row:SetHeight(rowHeight)

    -- Icon (square, anchored to right side, fills row height)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPRIGHT", 0, 0)
    icon:SetPoint("BOTTOMRIGHT", 0, 0)
    icon:SetWidth(rowHeight)
    icon:SetTexture(texturePath)

    -- Player names to the left of the icon
    local nameStr
    if #players == 0 then
        nameStr = "|cFF" .. UTILITY_MISSING_COLOR .. "—|r"
        row:SetAlpha(UTILITY_MISSING_ALPHA)
        icon:SetDesaturated(true)
    else
        local parts = {}
        for _, p in ipairs(players) do
            local c = ROLE_COLORS[p.mainRole] or DEFAULT_ROLE_COLOR
            parts[#parts + 1] = "|cFF" .. c .. p.name .. "|r"
        end
        nameStr = table.concat(parts, "\n")
    end

    local names = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    names:SetPoint("RIGHT", icon, "LEFT", UTILITY_NAME_OFFSET_X, 0)
    names:SetJustifyH("RIGHT")
    names:SetJustifyV("MIDDLE")
    names:SetText(nameStr)

    return row
end

local function RenderGroupCard(parent, index, group, yOffset)
    local cardHeight = 106

    -- Card background
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 0, -yOffset)
    card:SetPoint("TOPRIGHT", 0, -yOffset)
    card:SetHeight(cardHeight)
    card:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.1, 0.1, 0.15, 0.9)

    -- Color-code completeness
    local size = group:GetSize()
    local completenessColor
    if size == 5 then
        completenessColor = "|cFF00FF00"
    elseif size == 4 then
        completenessColor = "|cFFFFFF00"
    else
        completenessColor = "|cFFFF0000"
    end

    -- Group header
    local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetText("|cFFFFD100Group " .. index .. "|r  " .. completenessColor .. "(" .. size .. "/5)|r")

    -- Player lines with tooltips
    local lineY = -24
    CreatePlayerLine(card, "TANK", "|cFF87BCDE", group.tank, lineY)
    lineY = lineY - 14
    CreatePlayerLine(card, "HEAL", "|cFF87FF87", group.healer, lineY)
    lineY = lineY - 14
    for _, dps in ipairs(group.dps) do
        local tag = dps:IsRanged() and "RDPS" or "MDPS"
        local color = dps:IsRanged() and "|cFFFF8787" or "|cFFFFD187"
        CreatePlayerLine(card, tag, color, dps, lineY)
        lineY = lineY - 14
    end

    -- Utility panel (right side of card)
    local panelPadTop = 12
    local panelPadBottom = 12
    local panelPadRight = 4
    local panelGap = 12
    local panelHeight = cardHeight - panelPadTop - panelPadBottom
    local rowHeight = math.floor((panelHeight - panelGap) / 2)

    local utilPanel = CreateFrame("Frame", nil, card)
    utilPanel:SetPoint("TOPRIGHT", card, "TOPRIGHT", -panelPadRight, -panelPadTop)
    utilPanel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -panelPadRight, panelPadBottom)
    utilPanel:SetWidth(120)

    -- Collect players with each utility
    local brezPlayers = {}
    local lustPlayers = {}
    for _, p in ipairs(group:GetPlayers()) do
        if p:HasBrez() then brezPlayers[#brezPlayers + 1] = p end
        if p:HasLust() then lustPlayers[#lustPlayers + 1] = p end
    end

    CreateUtilityRow(utilPanel, 0, rowHeight, BREZ_ICON_PATH, brezPlayers)
    CreateUtilityRow(utilPanel, rowHeight + panelGap, rowHeight, LUST_ICON_PATH, lustPlayers)

    return cardHeight + 8
end

--- Hide the group display view.
function WHLSN:HideGroupDisplayView()
    if displayFrame then displayFrame:Hide() end
end

--- Show the group display view.
function WHLSN:ShowGroupDisplayView(parent)
    if displayFrame then displayFrame:Hide() end

    displayFrame = CreateGroupDisplayFrame(parent)
    displayFrame:Show()
end

--- Update the group display with session results.
function WHLSN:UpdateGroupDisplayView()
    if not displayFrame then return end

    -- Clear old children from scroll child
    local children = { displayFrame.scrollChild:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    local isHost = self.session.host == UnitName("player")
    local isViewing = self.session.viewingHistory or false
    displayFrame.endButton:SetShown(isHost or isViewing)
    displayFrame.inviteButton:SetShown(not isViewing)
    displayFrame.postButton:SetShown(not isViewing)
    displayFrame.reportButton:SetShown(not isViewing and WHLSN.session.algorithmSnapshot ~= nil)

    -- Update title for historical views
    if isViewing then
        displayFrame.title:SetText("|cFFFFD100Past Session Results|r")
        displayFrame.endButton:SetText("Close")
    else
        displayFrame.title:SetText("|cFFFFD100Mythic+ Groups|r")
        displayFrame.endButton:SetText("Finish")
    end

    -- Render each group
    local yOffset = 0
    for i, group in ipairs(self.session.groups) do
        local height = RenderGroupCard(displayFrame.scrollChild, i, group, yOffset)
        yOffset = yOffset + height
    end

    displayFrame.scrollChild:SetHeight(math.max(1, yOffset))
end

--- Invite players from the group containing the local player.
function WHLSN:InviteMyGroup()
    local myName = UnitName("player")
    for _, group in ipairs(self.session.groups) do
        for _, player in ipairs(group:GetPlayers()) do
            if player.name == myName then
                self:InvitePlayers(group:GetPlayers())
                return
            end
        end
    end
    self:Print("Could not find your group.")
end
