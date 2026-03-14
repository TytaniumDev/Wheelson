---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Group Display View (final results)
---------------------------------------------------------------------------

local displayFrame = nil

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

    -- Invite My Group button
    frame.inviteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.inviteButton:SetSize(120, 28)
    frame.inviteButton:SetPoint("BOTTOMLEFT", 8, 8)
    frame.inviteButton:SetText("Invite My Group")
    frame.inviteButton:SetScript("OnClick", function()
        WHLSN:InviteMyGroup()
    end)

    -- Post to Guild Chat button
    frame.postButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.postButton:SetSize(100, 28)
    frame.postButton:SetPoint("BOTTOM", -60, 8)
    frame.postButton:SetText("Post to Guild")
    frame.postButton:SetScript("OnClick", function()
        WHLSN:PostToGuildChat(WHLSN.session.groups)
    end)

    -- Copy to Clipboard button
    frame.copyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.copyButton:SetSize(80, 28)
    frame.copyButton:SetPoint("BOTTOM", 40, 8)
    frame.copyButton:SetText("Copy")
    frame.copyButton:SetScript("OnClick", function()
        WHLSN:CopyGroupsToClipboard(WHLSN.session.groups)
    end)

    -- End Session button (host only)
    frame.endButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.endButton:SetSize(100, 28)
    frame.endButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.endButton:SetText("End Session")
    frame.endButton:SetScript("OnClick", function()
        WHLSN:EndSession()
    end)

    -- New Session button (host only)
    frame.newButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.newButton:SetSize(100, 28)
    frame.newButton:SetPoint("BOTTOMRIGHT", frame.endButton, "BOTTOMLEFT", -4, 0)
    frame.newButton:SetText("New Session")
    frame.newButton:SetScript("OnClick", function()
        WHLSN:EndSession()
        WHLSN:StartSession()
    end)

    return frame
end

local function CreatePlayerLine(card, prefix, color, player, lineY)
    local lineFrame = CreateFrame("Frame", nil, card)
    lineFrame:SetPoint("TOPLEFT", 12, lineY)
    lineFrame:SetPoint("TOPRIGHT", -12, lineY)
    lineFrame:SetHeight(14)
    lineFrame:EnableMouse(true)

    local text = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT")
    if player then
        local utilStr = ""
        if player:HasBrez() then utilStr = utilStr .. " |cFF00FF00[BR]|r" end
        if player:HasLust() then utilStr = utilStr .. " |cFFFF4400[BL]|r" end
        text:SetText(color .. prefix .. "|r  " .. player.name .. utilStr)
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
    displayFrame.newButton:SetShown(isHost and not isViewing)
    displayFrame.inviteButton:SetShown(not isViewing)
    displayFrame.postButton:SetShown(not isViewing)
    displayFrame.copyButton:SetShown(not isViewing)

    -- Update title for historical views
    if isViewing then
        displayFrame.title:SetText("|cFFFFD100Past Session Results|r")
        displayFrame.endButton:SetText("Close")
    else
        displayFrame.title:SetText("|cFFFFD100Mythic+ Groups|r")
        displayFrame.endButton:SetText("End Session")
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
