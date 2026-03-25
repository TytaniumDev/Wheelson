---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Community Panel
-- Side panel for managing the community roster (add/remove players)
---------------------------------------------------------------------------

local communityPanel = nil

local COMMUNITY_PANEL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function CreateCommunityPanel()
    local mainFrame = _G["WHLSNMainFrame"]
    if not mainFrame then return nil end

    local panel = CreateFrame("Frame", "WHLSNCommunityPanel", mainFrame, "BackdropTemplate")
    panel:SetWidth(200)
    panel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", -2, 0)
    panel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMRIGHT", -2, 0)
    panel:SetBackdrop(COMMUNITY_PANEL_BACKDROP)
    panel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)

    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -12)
    panel.title:SetText("|cFFFFD100Community Roster|r")

    -- Member count
    panel.countText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.countText:SetPoint("TOP", panel.title, "BOTTOM", 0, -2)
    panel.countText:SetTextColor(0.6, 0.6, 0.6)

    -- Add player input
    panel.input = CreateFrame("EditBox", "WHLSNCommunityInput", panel, "InputBoxTemplate")
    panel.input:SetSize(140, 20)
    panel.input:SetPoint("TOPLEFT", 12, -48)
    panel.input:SetFontObject("ChatFontNormal")
    panel.input:SetAutoFocus(false)
    panel.input.Instructions = panel.input:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.input.Instructions:SetPoint("LEFT", 6, 0)
    panel.input.Instructions:SetText("Character name...")
    panel.input.Instructions:SetTextColor(0.5, 0.5, 0.5)
    panel.input:SetScript("OnEditFocusGained", function(self)
        self.Instructions:Hide()
    end)
    panel.input:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.Instructions:Show()
        end
    end)

    -- Autocomplete dropdown (GetAutoCompleteResults signature changed in 12.0)
    local acInclude = AUTOCOMPLETE_FLAG_ALL or 0xFFFFFFFF
    local acExclude = AUTOCOMPLETE_FLAG_NONE or 0
    local acDropdown = CreateFrame("Frame", nil, panel.input, "BackdropTemplate")
    acDropdown:SetBackdrop(COMMUNITY_PANEL_BACKDROP)
    acDropdown:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
    acDropdown:SetPoint("TOPLEFT", panel.input, "BOTTOMLEFT", 0, -2)
    acDropdown:SetPoint("RIGHT", panel.input, "RIGHT")
    acDropdown:SetFrameStrata("TOOLTIP")
    acDropdown:Hide()
    acDropdown.buttons = {}

    local function HideAC() acDropdown:Hide() end

    local function UpdateAC()
        local text = panel.input:GetText()
        if not text or #text == 0 then HideAC(); return end
        local MAX_AC_RESULTS = 8
        local ok, results = pcall(GetAutoCompleteResults, text, MAX_AC_RESULTS, #text, true, acInclude, acExclude)
        if not ok or not results or #results == 0 then HideAC(); return end
        local count = math.min(#results, MAX_AC_RESULTS)
        for i = 1, count do
            local btn = acDropdown.buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, acDropdown)
                btn:SetHeight(18)
                btn:SetNormalFontObject("GameFontHighlightSmall")
                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 0.82, 0, 0.15)
                btn:SetScript("OnClick", function(self)
                    panel.input:SetText(self.acName)
                    panel.input:SetCursorPosition(#self.acName)
                    HideAC()
                end)
                acDropdown.buttons[i] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 4, -(i - 1) * 18 - 4)
            btn:SetPoint("RIGHT", -4, 0)
            local r = results[i]
            local name = type(r) == "table" and r.name or tostring(r)
            -- ⚡ Bolt: Use plain string search to bypass regex overhead
            if not name:find("-", 1, true) then
                name = name .. "-" .. GetNormalizedRealmName()
            end
            btn.acName = name
            btn:SetText(name)
            local fs = btn:GetFontString()
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
            fs:SetJustifyH("LEFT")
            btn:Show()
        end
        for i = count + 1, #acDropdown.buttons do acDropdown.buttons[i]:Hide() end
        acDropdown:SetHeight(count * 18 + 8)
        acDropdown:Show()
    end

    panel.input:SetScript("OnTextChanged", function(_, userInput)
        if userInput then UpdateAC() end
    end)

    -- OK button
    panel.okButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.okButton:SetSize(36, 20)
    panel.okButton:SetPoint("LEFT", panel.input, "RIGHT", 2, 0)
    panel.okButton:SetText("OK")

    -- Add player logic
    local function ConfirmAddPlayer()
        HideAC()
        local name = panel.input:GetText()
        if name and strtrim(name) ~= "" then
            local added, err = WHLSN:AddCommunityPlayer(name)
            if added then
                local normalized = WHLSN:NormalizeCommunityName(name)
                WHLSN:Print("Added " .. normalized .. " to community roster.")
                if WHLSN.session.status == WHLSN.Status.LOBBY then
                    local pingData = {
                        type = "SESSION_PING",
                        host = WHLSN:GetMyFullName(),
                        status = WHLSN.session.status,
                        version = WHLSN.VERSION,
                    }
                    local serialized = WHLSN:Serialize(pingData)
                    WHLSN:SafeSendCommMessage(WHLSN.COMM_PREFIX, serialized, "WHISPER", normalized)
                end
                WHLSN:RefreshCommunityPanel()
                WHLSN:UpdateLobbyView()
            else
                WHLSN:Print("Could not add: " .. (err or "unknown error"))
            end
        end
        panel.input:SetText("")
        panel.input.Instructions:Show()
        panel.input:ClearFocus()
    end

    panel.okButton:SetScript("OnClick", ConfirmAddPlayer)
    panel.input:SetScript("OnEnterPressed", ConfirmAddPlayer)
    panel.input:SetScript("OnEscapePressed", function(self)
        HideAC()
        self:SetText("")
        self.Instructions:Show()
        self:ClearFocus()
    end)

    -- Divider line
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -74)
    divider:SetPoint("TOPRIGHT", -8, -74)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Container for roster rows
    panel.rosterContainer = CreateFrame("Frame", nil, panel)
    panel.rosterContainer:SetPoint("TOPLEFT", 8, -80)
    panel.rosterContainer:SetPoint("BOTTOMRIGHT", -8, 8)

    panel.rosterRows = {}

    panel:Hide()
    return panel
end

function WHLSN:ToggleCommunityPanel()
    if not communityPanel then
        communityPanel = CreateCommunityPanel()
        if not communityPanel then return end
        UISpecialFrames[#UISpecialFrames + 1] = "WHLSNCommunityPanel"
    end

    if communityPanel:IsShown() then
        communityPanel:Hide()
    else
        communityPanel:Show()
        self:RefreshCommunityPanel()
    end
end

function WHLSN:HideCommunityPanel()
    if communityPanel and communityPanel:IsShown() then
        communityPanel:Hide()
    end
end

local function OnRosterRowEnter(r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.fullName, 1, 1, 1)
    GameTooltip:Show()
end

local function OnRosterRowLeave()
    GameTooltip:Hide()
end

local function OnRosterRowMouseUp(r, button)
    if button == "RightButton" then
        MenuUtil.CreateContextMenu(r, function(_, rootDescription)
            rootDescription:CreateTitle(r.fullName)
            rootDescription:CreateButton("Whisper", function()
                ChatFrame_OpenChat("/w " .. r.fullName .. " ")
            end)
            rootDescription:CreateButton("|cFFFF6666Remove|r", function()
                WHLSN:RemoveCommunityPlayer(r.fullName)
                WHLSN:Print("Removed " .. r.fullName .. " from community roster.")
                WHLSN:RefreshCommunityPanel()
            end)
        end)
    end
end

function WHLSN:RefreshCommunityPanel()
    if not communityPanel or not communityPanel:IsShown() then return end

    local roster = self.db.profile.communityRoster
    communityPanel.countText:SetText(#roster .. " members")

    -- Hide existing rows
    for _, row in ipairs(communityPanel.rosterRows) do
        row:Hide()
    end

    -- Create/update rows
    for i, entry in ipairs(roster) do
        local row = communityPanel.rosterRows[i]
        if not row then
            row = CreateFrame("Frame", nil, communityPanel.rosterContainer)
            row:SetHeight(20)
            row:EnableMouse(true)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetJustifyH("LEFT")

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 0.82, 0, 0.1)

            row:SetScript("OnEnter", OnRosterRowEnter)
            row:SetScript("OnLeave", OnRosterRowLeave)
            row:SetScript("OnMouseUp", OnRosterRowMouseUp)

            communityPanel.rosterRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        row:SetPoint("RIGHT", 0, 0)

        row.nameText:SetText(entry.name)
        row.nameText:SetTextColor(0.9, 0.9, 0.9)
        row.fullName = entry.name

        row:Show()
    end
end
