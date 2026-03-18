-- Tests for SpecService with mocked WoW APIs
-- Run with: busted addon/tests/

-- Minimal stubs for WoW APIs and libraries
_G.LibStub = function()
    local addon = {}
    addon.NewAddon = function(_, name, ...)
        addon.name = name
        addon.Print = function() end
        addon.RegisterComm = function() end
        addon.RegisterEvent = function() end
        addon.UnregisterAllEvents = function() end
        addon.Serialize = function(_, data) return "serialized" end
        addon.Deserialize = function(_, data) return true, data end
        addon.SendCommMessage = function() end
        return addon
    end
    addon.New = function(_, name, defaults)
        return {
            profile = defaults and defaults.profile or {},
            char = defaults and defaults.char and setmetatable({}, { __index = defaults.char }) or {},
        }
    end
    addon.Register = function(_, _id) return setmetatable({}, { __index = function() return function() end end }) end
    return addon
end

-- WoW API mocks (overridden per test)
_G.C_SpecializationInfo = {
    GetSpecialization = function() return nil end,
    GetSpecializationInfo = function() return nil end,
}
_G.GetNumSpecializations = function() return 0 end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Paladin", "PALADIN" end
_G.GetNormalizedRealmName = function() return "Illidan" end

-- Load source files in order
dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Services/SpecService.lua")

local WHLSN = Wheelson
local Player = WHLSN.Player

describe("SpecService", function()
    -- Reset mocks before each test
    before_each(function()
        _G.C_SpecializationInfo.GetSpecialization = function() return nil end
        _G.C_SpecializationInfo.GetSpecializationInfo = function() return nil end
        _G.GetNumSpecializations = function() return 0 end
        _G.UnitName = function() return "TestPlayer" end
        _G.UnitClass = function() return "Paladin", "PALADIN" end
        WHLSN.db = nil
    end)

    describe(":DetectLocalPlayer()", function()
        it("should return nil when no specialization is active", function()
            local result = WHLSN:DetectLocalPlayer()
            assert.is_nil(result)
        end)

        it("should return nil when GetSpecializationInfo returns nil", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 1 end
            local result = WHLSN:DetectLocalPlayer()
            assert.is_nil(result)
        end)

        it("should detect a Protection Paladin as tank with brez", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 } -- Holy, Prot, Ret
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end
            _G.UnitName = function() return "Tankadin" end
            _G.UnitClass = function() return "Paladin", "PALADIN" end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("Tankadin", result.name)
            assert.equal("tank", result.mainRole)
            assert.is_true(result:IsTankMain())
            assert.is_true(result:HasBrez())
        end)

        it("should detect offspecs from other specializations", function()
            -- Paladin: Holy (65)=healer, Prot (66)=tank, Ret (70)=melee
            -- If main is Prot (tank), offspecs should be healer and melee
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("tank", result.mainRole)
            -- Should have healer and melee as offspecs
            assert.is_true(result:IsOffhealer())
            assert.is_true(result:IsOffmelee())
        end)

        it("should respect selectedOffspecs filter", function()
            -- Paladin with only healer offspec selected (not melee)
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local selectedOffspecs = { healer = true, melee = false }
            local result = WHLSN:DetectLocalPlayer(selectedOffspecs)
            assert.is_not_nil(result)
            assert.is_true(result:IsOffhealer())
            assert.is_false(result:IsOffmelee())
        end)

        it("should respect overrideRole", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectLocalPlayer(nil, "healer")
            assert.is_not_nil(result)
            assert.equal("healer", result.mainRole)
            assert.is_true(result:IsHealerMain())
        end)

        it("should include active spec role as offspec when overrideRole changes main", function()
            -- Paladin: Holy (65)=healer, Prot (66)=tank, Ret (70)=melee
            -- Active spec is Prot (tank). Override main to healer, select tank as offspec.
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectLocalPlayer({ tank = true }, "healer")
            assert.is_not_nil(result)
            assert.equal("healer", result.mainRole)
            assert.is_true(result:IsOfftank())
        end)

        it("should apply saved overrides when no explicit args provided", function()
            -- Paladin: Holy (65)=healer, Prot (66)=tank, Ret (70)=melee
            -- Active spec is Prot (tank). Saved override: main=healer, offspecs={tank=true}
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            WHLSN.db = {
                char = {
                    specOverrides = {
                        mainRole = "healer",
                        offspecs = { tank = true, melee = true },
                    },
                },
            }

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("healer", result.mainRole)
            assert.is_true(result:IsOfftank())
            assert.is_true(result:IsOffmelee())
        end)

        it("should not apply saved overrides when explicit args provided", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            WHLSN.db = {
                char = {
                    specOverrides = {
                        mainRole = "healer",
                        offspecs = { tank = true },
                    },
                },
            }

            -- Explicit override should take precedence over saved
            local result = WHLSN:DetectLocalPlayer(nil, "melee")
            assert.is_not_nil(result)
            assert.equal("melee", result.mainRole)
        end)

        it("should ignore saved overrides when db is nil", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            WHLSN.db = nil

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("tank", result.mainRole) -- Falls back to WoW-detected spec
        end)

        it("should detect a Restoration Shaman as healer with lust", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 3 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 262, [2] = 263, [3] = 264 } -- Ele, Enh, Resto
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end
            _G.UnitName = function() return "Healbot" end
            _G.UnitClass = function() return "Shaman", "SHAMAN" end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("healer", result.mainRole)
            assert.is_true(result:HasLust())
            assert.is_false(result:HasBrez())
        end)

        it("should detect a Shadow Priest as ranged DPS with no utilities", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 3 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 256, [2] = 257, [3] = 258 } -- Disc, Holy, Shadow
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end
            _G.UnitName = function() return "Shadowfiend" end
            _G.UnitClass = function() return "Priest", "PRIEST" end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("ranged", result.mainRole)
            assert.is_true(result:IsDpsMain())
            assert.is_false(result:HasBrez())
            assert.is_false(result:HasLust())
            -- Offspecs should include healer (from Disc and Holy, but deduplicated)
            assert.is_true(result:IsOffhealer())
        end)

        it("should detect a Blood DK as tank with brez and melee offspecs", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 1 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 250, [2] = 251, [3] = 252 } -- Blood, Frost, Unholy
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end
            _G.UnitName = function() return "Boneshield" end
            _G.UnitClass = function() return "Death Knight", "DEATHKNIGHT" end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("tank", result.mainRole)
            assert.is_true(result:HasBrez())
            assert.is_false(result:HasLust())
            assert.is_true(result:IsOffmelee())
        end)

        it("should handle UnitName returning nil", function()
            _G.UnitName = function() return nil end
            local result = WHLSN:DetectLocalPlayer()
            assert.is_nil(result)
        end)

        it("should detect a Devourer Demon Hunter as ranged DPS", function()
            -- DH: Havoc (577)=melee, Vengeance (581)=tank, Devourer (1480)=ranged
            _G.C_SpecializationInfo.GetSpecialization = function() return 3 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 577, [2] = 581, [3] = 1480 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end
            _G.UnitName = function() return "Voidgaze" end
            _G.UnitClass = function() return "Demon Hunter", "DEMONHUNTER" end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            assert.equal("ranged", result.mainRole)
            assert.is_true(result:IsRanged())
            assert.is_true(result:IsDpsMain())
            assert.is_false(result:HasBrez())
            assert.is_false(result:HasLust())
            -- Offspecs: melee (Havoc) and tank (Vengeance)
            assert.is_true(result:IsOffmelee())
            assert.is_true(result:IsOfftank())
        end)

        it("should handle unknown spec IDs gracefully", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 1 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function() return 99999 end -- Unknown spec
            _G.GetNumSpecializations = function() return 1 end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_nil(result) -- No role mapping for unknown spec
        end)

        it("should not duplicate offspec roles", function()
            -- Priest: Disc (256)=healer, Holy (257)=healer, Shadow (258)=ranged
            -- When main is Shadow, offspecs should be just "healer" (not "healer, healer")
            _G.C_SpecializationInfo.GetSpecialization = function() return 3 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 256, [2] = 257, [3] = 258 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectLocalPlayer()
            assert.is_not_nil(result)
            -- Count healer offspecs - should only appear once
            local healerCount = 0
            for _, os in ipairs(result.offspecs) do
                if os == "healer" then healerCount = healerCount + 1 end
            end
            assert.equal(1, healerCount)
        end)
    end)

    describe(":DetectAllOffspecs()", function()
        it("should return empty when no specialization is active", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return nil end
            local result = WHLSN:DetectAllOffspecs()
            assert.same({}, result)
        end)

        it("should return offspec roles for a Paladin (tank main)", function()
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectAllOffspecs()
            -- Prot Paladin offspecs: healer (Holy) and melee (Ret)
            assert.equal(2, #result)
            local hasHealer, hasMelee = false, false
            for _, r in ipairs(result) do
                if r == "healer" then hasHealer = true end
                if r == "melee" then hasMelee = true end
            end
            assert.is_true(hasHealer)
            assert.is_true(hasMelee)
        end)

        it("should return empty for pure DPS class (Rogue)", function()
            -- Rogue: all 3 specs are melee
            _G.C_SpecializationInfo.GetSpecialization = function() return 1 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 259, [2] = 260, [3] = 261 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectAllOffspecs()
            -- All specs are melee, so no different offspec roles
            assert.same({}, result)
        end)

        it("should return empty for pure DPS class (Mage)", function()
            -- Mage: all 3 specs are ranged
            _G.C_SpecializationInfo.GetSpecialization = function() return 1 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 62, [2] = 63, [3] = 64 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectAllOffspecs()
            assert.same({}, result)
        end)

        it("should handle Druid with 4 specs", function()
            -- Druid: Balance (102)=ranged, Feral (103)=melee, Guardian (104)=tank, Resto (105)=healer
            _G.C_SpecializationInfo.GetSpecialization = function() return 3 end -- Guardian (tank)
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 102, [2] = 103, [3] = 104, [4] = 105 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 4 end

            local result = WHLSN:DetectAllOffspecs()
            -- Guardian Druid offspecs: ranged, melee, healer
            assert.equal(3, #result)
        end)

        it("should include active spec role as offspec when overrideMainRole differs", function()
            -- Paladin: Holy (65)=healer, Prot (66)=tank, Ret (70)=melee
            -- Active spec is Prot (tank). Override main to healer -> tank should be an offspec.
            _G.C_SpecializationInfo.GetSpecialization = function() return 2 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 65, [2] = 66, [3] = 70 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 3 end

            local result = WHLSN:DetectAllOffspecs("healer")
            -- Override to healer: offspecs should be tank (from Prot) and melee (from Ret)
            assert.equal(2, #result)
            local hasTank, hasMelee = false, false
            for _, r in ipairs(result) do
                if r == "tank" then hasTank = true end
                if r == "melee" then hasMelee = true end
            end
            assert.is_true(hasTank)
            assert.is_true(hasMelee)
        end)

        it("should exclude overrideMainRole from offspecs", function()
            -- Druid: Balance (102)=ranged, Feral (103)=melee, Guardian (104)=tank, Resto (105)=healer
            -- Active spec is Guardian (tank). Override main to melee.
            _G.C_SpecializationInfo.GetSpecialization = function() return 3 end
            _G.C_SpecializationInfo.GetSpecializationInfo = function(index)
                local specs = { [1] = 102, [2] = 103, [3] = 104, [4] = 105 }
                return specs[index]
            end
            _G.GetNumSpecializations = function() return 4 end

            local result = WHLSN:DetectAllOffspecs("melee")
            -- Override to melee: offspecs should be ranged, tank, healer (not melee)
            assert.equal(3, #result)
            for _, r in ipairs(result) do
                assert.is_not_equal("melee", r)
            end
        end)
    end)

    describe(":StripRealmName()", function()
        it("should strip realm name from hyphenated names", function()
            assert.equal("Player", WHLSN:StripRealmName("Player-Stormrage"))
        end)

        it("should handle names without realm", function()
            assert.equal("Player", WHLSN:StripRealmName("Player"))
        end)

        it("should handle nil input", function()
            assert.equal("", WHLSN:StripRealmName(nil))
        end)

        it("should handle names with multiple hyphens", function()
            assert.equal("Player", WHLSN:StripRealmName("Player-Area-52"))
        end)

        it("should handle apostrophe in realm name", function()
            assert.equal("Player", WHLSN:StripRealmName("Player-Kel'Thuzad"))
        end)

        it("should handle apostrophe in both character name and realm", function()
            assert.equal("O'Brien", WHLSN:StripRealmName("O'Brien-Kel'Thuzad"))
        end)
    end)

    describe(":DetectGuildMember()", function()
        it("should create a player with no mainRole and correct utilities", function()
            local result = WHLSN:DetectGuildMember("GuildTank-Stormrage", "DEATHKNIGHT")
            assert.equal("GuildTank", result.name)
            assert.is_nil(result.mainRole)
            assert.is_true(result:HasBrez())
            assert.is_false(result:HasLust())
        end)

        it("should detect lust for Shaman", function()
            local result = WHLSN:DetectGuildMember("ShamanDude", "SHAMAN")
            assert.equal("ShamanDude", result.name)
            assert.is_true(result:HasLust())
            assert.is_false(result:HasBrez())
        end)

        it("should detect no utilities for Rogue", function()
            local result = WHLSN:DetectGuildMember("Stabby", "ROGUE")
            assert.equal("Stabby", result.name)
            assert.is_false(result:HasBrez())
            assert.is_false(result:HasLust())
        end)

        it("should detect both utilities for Druid", function()
            -- Druid has brez but not lust
            local result = WHLSN:DetectGuildMember("TreeHugger", "DRUID")
            assert.equal("TreeHugger", result.name)
            assert.is_true(result:HasBrez())
            assert.is_false(result:HasLust())
        end)
    end)

    describe(":GetMyFullName()", function()
        before_each(function()
            _G.UnitName = function() return "TestPlayer" end
            _G.GetNormalizedRealmName = function() return "Illidan" end
            -- Clear the cache between tests
            WHLSN._myFullName = nil
        end)

        it("should return realm-qualified name", function()
            assert.equal("TestPlayer-Illidan", WHLSN:GetMyFullName())
        end)

        it("should cache the result", function()
            local result1 = WHLSN:GetMyFullName()
            _G.UnitName = function() return "Changed" end
            local result2 = WHLSN:GetMyFullName()
            assert.equal(result1, result2)
        end)
    end)

    describe(":NamesMatch()", function()
        before_each(function()
            _G.GetNormalizedRealmName = function() return "Illidan" end
        end)

        it("should match identical realm-qualified names", function()
            assert.is_true(WHLSN:NamesMatch("Alice-Illidan", "Alice-Illidan"))
        end)

        it("should not match different realms", function()
            assert.is_false(WHLSN:NamesMatch("Alice-Illidan", "Alice-Stormrage"))
        end)

        it("should normalize bare names to local realm", function()
            assert.is_true(WHLSN:NamesMatch("Alice", "Alice-Illidan"))
            assert.is_true(WHLSN:NamesMatch("Alice-Illidan", "Alice"))
        end)

        it("should not match bare names when realm differs", function()
            assert.is_false(WHLSN:NamesMatch("Alice", "Alice-Stormrage"))
        end)

        it("should return false for nil inputs", function()
            assert.is_false(WHLSN:NamesMatch(nil, "Alice-Illidan"))
            assert.is_false(WHLSN:NamesMatch("Alice-Illidan", nil))
            assert.is_false(WHLSN:NamesMatch(nil, nil))
        end)

        it("should match two bare names on the same local realm", function()
            assert.is_true(WHLSN:NamesMatch("Alice", "Alice"))
        end)

        it("should not match different bare names", function()
            assert.is_false(WHLSN:NamesMatch("Alice", "Bob"))
        end)
    end)
end)
