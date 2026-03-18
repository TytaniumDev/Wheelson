---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Spec Detection Service
-- Detects the local player's spec, role, and utilities using WoW APIs.
---------------------------------------------------------------------------

--- Detect all available offspecs for the local player.
---@param overrideMainRole? string When provided, consider all specs (including active) and exclude this role
---@return string[] allOffspecs All possible offspec roles
function WHLSN:DetectAllOffspecs(overrideMainRole)
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then return {} end

    local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not specID then return {} end

    local mainRole = overrideMainRole or WHLSN.SpecRoles[specID]
    local offspecs = {}
    local numSpecs = GetNumSpecializations()

    for i = 1, numSpecs do
        -- When main role is overridden, consider all specs (active spec may provide a valid offspec)
        if overrideMainRole or i ~= specIndex then
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

    -- Apply saved overrides when no explicit override provided
    local savedOverrides = self.db and self.db.char and self.db.char.specOverrides
    if not overrideRole and not selectedOffspecs and savedOverrides then
        overrideRole = savedOverrides.mainRole
        selectedOffspecs = savedOverrides.offspecs
    end

    local mainRole = overrideRole or WHLSN.SpecRoles[specID]
    if not mainRole then return nil end

    -- Detect offspecs from other specializations
    local offspecs = {}
    local allOffspecs = self:DetectAllOffspecs(overrideRole)

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

    return WHLSN.Player:New(name, mainRole, offspecs, utilities, classToken)
end

local realmNameCache = {}

--- Strip realm name from a character name.
---@param name string
---@return string
function WHLSN:StripRealmName(name)
    if not name then return "" end

    -- ⚡ Bolt: Cache string match results since player names don't change
    -- Reduces regex overhead significantly during repeated lookups in loops
    local cached = realmNameCache[name]
    if cached then return cached end

    cached = name:match("^([^%-]+)") or name
    realmNameCache[name] = cached
    return cached
end

--- Get the local player's full realm-qualified name (cached).
---@return string
function WHLSN:GetMyFullName()
    if self._myFullName then return self._myFullName end
    local name = UnitName("player")
    local realm = GetNormalizedRealmName()
    if name and realm then
        self._myFullName = name .. "-" .. realm
    end
    return self._myFullName or name or ""
end

--- Compare two player names for identity, normalizing bare names to local realm.
---@param a string|nil
---@param b string|nil
---@return boolean
function WHLSN:NamesMatch(a, b)
    if not a or not b then return false end
    if not a:find("-") then a = a .. "-" .. GetNormalizedRealmName() end
    if not b:find("-") then b = b .. "-" .. GetNormalizedRealmName() end
    return a == b
end

--- Resolve a player's name using the comm sender, preserving realm for cross-realm players.
---@param player WHLSNPlayer
---@param sender string The addon comm sender (may include "-RealmName")
function WHLSN:ResolvePlayerName(player, sender)
    if sender:find("-") then
        player.name = sender
    end
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

    return WHLSN.Player:New(name, nil, {}, utilities, classToken)
end
