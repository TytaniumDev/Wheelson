---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Spec Override Section
-- "Your Specs" panel: lets the player choose their main role and offspecs
---------------------------------------------------------------------------

--- Create the "Your Specs" override section.
---@param parent Frame  the lobby frame
---@return Frame
local function CreateSpecOverrideSection(parent)
    local section = CreateFrame("Frame", nil, parent)
    section:SetHeight(62)
    section:SetPoint("BOTTOMLEFT", 8, 44)
    section:SetPoint("BOTTOMRIGHT", -8, 44)

    -- Divider line at top
    local divider = section:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", 0, 0)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Title
    local title = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 0, -6)
    title:SetText("|cFFFFD100Your Specs|r")

    -- Main spec label
    local mainLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainLabel:SetPoint("TOPLEFT", 0, -22)
    mainLabel:SetText("Main:")
    mainLabel:SetTextColor(0.6, 0.6, 0.6)

    -- Offspec label
    local offLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    offLabel:SetPoint("TOPLEFT", 0, -40)
    offLabel:SetText("Off:")
    offLabel:SetTextColor(0.6, 0.6, 0.6)

    section.mainButtons = {}
    section.offButtons = {}
    section.selectedMain = nil
    section.selectedOffs = {}

    local allRoles = { "tank", "healer", "ranged", "melee" }

    -- Style a role button based on selection state
    local function StyleButton(btn, role, selected)
        local rc = WHLSN.RoleColors[role]
        if selected then
            btn:GetFontString():SetTextColor(rc.r, rc.g, rc.b)
        else
            btn:GetFontString():SetTextColor(0.4, 0.4, 0.4)
        end
    end

    local function SendSpecUpdate()
        local selectedOffspecs = {}
        for role, enabled in pairs(section.selectedOffs) do
            if enabled then
                selectedOffspecs[role] = true
            end
        end

        -- Persist spec overrides to character storage
        if WHLSN.db and WHLSN.db.char then
            WHLSN.db.char.specOverrides = {
                mainRole = section.selectedMain,
                offspecs = selectedOffspecs,
            }
        end

        local playerData = WHLSN:DetectLocalPlayer(selectedOffspecs, section.selectedMain)
        if not playerData then return end

        -- Update local player in session
        for i, p in ipairs(WHLSN.session.players) do
            if WHLSN:NamesMatch(p.name, WHLSN:GetMyFullName()) then
                WHLSN.session.players[i] = playerData
                break
            end
        end

        -- Send to host (unless we are the host — already updated locally)
        if not WHLSN:NamesMatch(WHLSN.session.host, WHLSN:GetMyFullName()) then
            local data = {
                type = "SPEC_UPDATE",
                player = playerData:ToDict(),
            }
            local serialized = WHLSN:Serialize(data)
            if WHLSN.session.commChannel == "WHISPER" and WHLSN.session.host then
                WHLSN:SafeSendCommMessage(WHLSN.COMM_PREFIX, serialized, "WHISPER", WHLSN.session.host)
            else
                WHLSN:SafeSendCommMessage(WHLSN.COMM_PREFIX, serialized, "GUILD")
            end
        else
            WHLSN:BroadcastSessionUpdate()
        end

        WHLSN:UpdateLobbyView()
    end

    local function RefreshOffButtons()
        for _, btn in ipairs(section.offButtons) do
            btn:Hide()
        end

        local idx = 0
        for _, role in ipairs(allRoles) do
            if role ~= section.selectedMain then
                idx = idx + 1
                local btn = section.offButtons[idx]
                if not btn then
                    btn = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
                    btn:SetSize(60, 18)
                    btn:GetFontString():SetJustifyH("CENTER")
                    section.offButtons[idx] = btn
                end
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", mainLabel, "TOPLEFT", 36 + (idx - 1) * 64, -18)
                btn:SetText(role)
                btn.role = role

                local selected = section.selectedOffs[role] or false
                StyleButton(btn, role, selected)

                btn:SetScript("OnClick", function()
                    section.selectedOffs[role] = not section.selectedOffs[role]
                    StyleButton(btn, role, section.selectedOffs[role])
                    SendSpecUpdate()
                end)
                btn:Show()
            end
        end
    end

    -- Create main spec buttons
    for i, role in ipairs(allRoles) do
        local btn = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
        btn:SetSize(60, 18)
        btn:SetPoint("TOPLEFT", mainLabel, "TOPLEFT", 36 + (i - 1) * 64, 0)
        btn:SetText(role)
        btn:GetFontString():SetJustifyH("CENTER")
        btn.role = role

        btn:SetScript("OnClick", function()
            if section.selectedMain == role then return end
            -- Deselect old main from offspecs if it was selected
            section.selectedOffs[role] = nil
            -- Update main
            section.selectedMain = role
            -- Style all main buttons
            for _, mb in ipairs(section.mainButtons) do
                StyleButton(mb, mb.role, mb.role == role)
            end
            RefreshOffButtons()
            SendSpecUpdate()
        end)

        section.mainButtons[i] = btn
    end

    --- Initialize the section from saved overrides or the local player's detected spec data.
    function section:Initialize()
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if not specIndex then return end
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        if not specID then return end

        -- Restore from saved overrides if available
        self.selectedOffs = {}
        local saved = WHLSN.db and WHLSN.db.char and WHLSN.db.char.specOverrides
        if saved and saved.mainRole then
            self.selectedMain = saved.mainRole
            if saved.offspecs then
                for role, enabled in pairs(saved.offspecs) do
                    if enabled then
                        self.selectedOffs[role] = true
                    end
                end
            end
        else
            self.selectedMain = WHLSN.SpecRoles[specID]

            local allOffspecs = WHLSN:DetectAllOffspecs()
            for _, offRole in ipairs(allOffspecs) do
                self.selectedOffs[offRole] = true
            end
        end

        -- Style main buttons
        for _, btn in ipairs(self.mainButtons) do
            StyleButton(btn, btn.role, btn.role == self.selectedMain)
        end

        RefreshOffButtons()
    end

    return section
end

WHLSN.CreateSpecOverrideSection = CreateSpecOverrideSection
