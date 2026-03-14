---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Spec Detection Service
-- Detects the local player's spec, role, and utilities using WoW APIs.
---------------------------------------------------------------------------

--- Detect all available offspecs for the local player.
---@return string[] allOffspecs All possible offspec roles
function WHLSN:DetectAllOffspecs()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then return {} end

    local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not specID then return {} end

    local mainRole = WHLSN.SpecRoles[specID]
    local offspecs = {}
    local numSpecs = GetNumSpecializations()

    for i = 1, numSpecs do
        if i ~= specIndex then
            local otherSpecID = C_SpecializationInfo.GetSpecializationInfo(i)
            if otherSpecID then
                local otherRole = WHLSN.SpecRoles[otherSpecID]
                if otherRole and otherRole ~= mainRole then
                    local found = false
                    for _, existing in ipairs(offspecs) do
                        if existing == otherRole then found = true; break end
                    end
                    if not found then
                        offspecs[#offspecs + 1] = otherRole
                    end
                end
            end
        end
    end

    return offspecs
end

--- Detect the local player and build an WHLSNPlayer from their current spec.
---@param selectedOffspecs? table<string, boolean> Map of offspec role -> enabled
---@param overrideRole? string Optional role override from the UI dropdown
---@return WHLSNPlayer|nil
function WHLSN:DetectLocalPlayer(selectedOffspecs, overrideRole)
    local name = UnitName("player")
    if not name then return nil end

    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then return nil end

    local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not specID then return nil end

    local mainRole = overrideRole or WHLSN.SpecRoles[specID]
    if not mainRole then return nil end

    -- Detect offspecs from other specializations
    local offspecs = {}
    local allOffspecs = self:DetectAllOffspecs()

    if selectedOffspecs then
        -- Use player-selected offspecs
        for _, role in ipairs(allOffspecs) do
            if selectedOffspecs[role] then
                offspecs[#offspecs + 1] = role
            end
        end
    else
        -- Default: include all offspecs
        offspecs = allOffspecs
    end

    -- Detect utilities from class
    local utilities = {}
    local _, classToken = UnitClass("player")
    if WHLSN.BrezClasses[classToken] then
        utilities[#utilities + 1] = "brez"
    end
    if WHLSN.LustClasses[classToken] then
        utilities[#utilities + 1] = "lust"
    end

    return WHLSN.Player:New(name, mainRole, offspecs, utilities)
end

--- Strip realm name from a character name.
---@param name string
---@return string
function WHLSN:StripRealmName(name)
    if not name then return name end
    return name:match("^([^%-]+)") or name
end

--- Detect a guild member's likely role from guild roster info.
--- Less accurate than DetectLocalPlayer since we can't see their spec directly.
---@param name string
---@param classToken string
---@return WHLSNPlayer
function WHLSN:DetectGuildMember(name, classToken)
    -- Strip realm name for consistency
    name = self:StripRealmName(name)

    -- Without inspect data, we can only infer from class
    -- The player will correct via join request with actual spec data
    local utilities = {}
    if WHLSN.BrezClasses[classToken] then
        utilities[#utilities + 1] = "brez"
    end
    if WHLSN.LustClasses[classToken] then
        utilities[#utilities + 1] = "lust"
    end

    return WHLSN.Player:New(name, nil, {}, utilities)
end
