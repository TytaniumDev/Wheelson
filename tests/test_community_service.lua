-- Tests for CommunityService.lua

local mock_db = {
    profile = {
        minimap = { hide = false },
        lastSession = nil,
        sessionHistory = {},
        communityRoster = {},
    },
}

_G.LibStub = function(name, silent)
    if name == "AceAddon-3.0" then
        local addon = {}
        addon.NewAddon = function(_, addonName, ...)
            addon.name = addonName
            addon.Print = function() end
            addon.RegisterComm = function() end
            addon.RegisterEvent = function() end
            addon.UnregisterAllEvents = function() end
            addon.Serialize = function(_, data) return "serialized" end
            addon.Deserialize = function(_, data) return true, data end
            addon.SendCommMessage = function() end
            return addon
        end
        return addon
    elseif name == "AceDB-3.0" then
        return { New = function(_, dbName, defaults) return mock_db end }
    elseif name == "LibDataBroker-1.1" then
        return { NewDataObject = function(_, _name, obj) return obj end }
    elseif name == "LibDBIcon-1.0" then
        return { Register = function() end, Show = function() end, Hide = function() end }
    end
    if silent then return nil end
    return {}
end

_G.SlashCmdList = _G.SlashCmdList or {}
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71 end,
}
_G.GetNumSpecializations = function() return 3 end
_G.GetNormalizedRealmName = function() return "Illidan" end
_G.time = os.time
_G.date = os.date
_G.C_Timer = {
    NewTimer = function(_, cb) return { Cancel = function() end } end,
    After = function(_, cb) end,
}
_G.CreateFrame = function()
    return {
        CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end,
    }
end
_G.Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { ID = name } end,
    RegisterAddOnCategory = function() end,
}

dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")

_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
dofile("src/GroupCreator.lua")
dofile("src/Services/CommunityService.lua")

local WHLSN = _G.Wheelson

describe("CommunityService", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.db.profile.communityRoster = {}
    end)

    describe("ValidateCommunityName", function()
        it("should reject empty string", function()
            local ok = WHLSN:ValidateCommunityName("")
            assert.is_false(ok)
        end)

        it("should reject whitespace-only string", function()
            local ok = WHLSN:ValidateCommunityName("   ")
            assert.is_false(ok)
        end)

        it("should accept valid name", function()
            local ok = WHLSN:ValidateCommunityName("Tyler")
            assert.is_true(ok)
        end)

        it("should accept name with realm", function()
            local ok = WHLSN:ValidateCommunityName("Tyler-Illidan")
            assert.is_true(ok)
        end)

        it("should reject names with numbers", function()
            local ok = WHLSN:ValidateCommunityName("Tyler123")
            assert.is_false(ok)
        end)
    end)

    describe("NormalizeCommunityName", function()
        it("should append realm to bare name", function()
            assert.equals("Tyler-Illidan", WHLSN:NormalizeCommunityName("Tyler"))
        end)

        it("should keep realm-qualified name as-is", function()
            assert.equals("Tyler-Stormrage", WHLSN:NormalizeCommunityName("Tyler-Stormrage"))
        end)

        it("should trim whitespace", function()
            assert.equals("Tyler-Illidan", WHLSN:NormalizeCommunityName("  Tyler  "))
        end)
    end)

    describe("AddCommunityPlayer", function()
        it("should add a player to the roster", function()
            local ok = WHLSN:AddCommunityPlayer("Tyler")
            assert.is_true(ok)
            assert.equals(1, #WHLSN.db.profile.communityRoster)
            assert.equals("Tyler-Illidan", WHLSN.db.profile.communityRoster[1].name)
        end)

        it("should prevent duplicate names (case-insensitive)", function()
            WHLSN:AddCommunityPlayer("Tyler")
            local ok = WHLSN:AddCommunityPlayer("tyler")
            assert.is_false(ok)
            assert.equals(1, #WHLSN.db.profile.communityRoster)
        end)

        it("should reject empty names", function()
            local ok = WHLSN:AddCommunityPlayer("")
            assert.is_false(ok)
            assert.equals(0, #WHLSN.db.profile.communityRoster)
        end)

        it("should store realm-qualified name", function()
            WHLSN:AddCommunityPlayer("Arthas-Stormrage")
            assert.equals("Arthas-Stormrage", WHLSN.db.profile.communityRoster[1].name)
        end)
    end)

    describe("RemoveCommunityPlayer", function()
        it("should remove a player from the roster", function()
            WHLSN:AddCommunityPlayer("Tyler")
            local ok = WHLSN:RemoveCommunityPlayer("Tyler-Illidan")
            assert.is_true(ok)
            assert.equals(0, #WHLSN.db.profile.communityRoster)
        end)

        it("should match by bare name", function()
            WHLSN:AddCommunityPlayer("Tyler")
            local ok = WHLSN:RemoveCommunityPlayer("Tyler")
            assert.is_true(ok)
            assert.equals(0, #WHLSN.db.profile.communityRoster)
        end)

        it("should return false if player not found", function()
            assert.is_false(WHLSN:RemoveCommunityPlayer("Nobody"))
        end)
    end)

    describe("IsCommunityRosterMember", function()
        it("should return true for roster member by bare name", function()
            WHLSN:AddCommunityPlayer("Tyler-Stormrage")
            assert.is_true(WHLSN:IsCommunityRosterMember("Tyler"))
        end)

        it("should return true for roster member by full name", function()
            WHLSN:AddCommunityPlayer("Tyler-Stormrage")
            assert.is_true(WHLSN:IsCommunityRosterMember("Tyler-Stormrage"))
        end)

        it("should return false for non-member", function()
            assert.is_false(WHLSN:IsCommunityRosterMember("Nobody"))
        end)
    end)

    describe("SendCommunityPings", function()
        it("should whisper each roster member", function()
            WHLSN.db.profile.communityRoster = {
                { name = "Tyler-Stormrage" },
                { name = "Arthas-Illidan" },
            }
            WHLSN.session.status = "lobby"

            local sent = {}
            WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
                sent[#sent + 1] = { channel = channel, target = target }
            end
            WHLSN.Serialize = function(self, data) return data end

            WHLSN:SendCommunityPings()

            assert.equals(2, #sent)
            assert.equals("WHISPER", sent[1].channel)
            assert.equals("Tyler-Stormrage", sent[1].target)
        end)

        it("should skip self in community roster", function()
            WHLSN.db.profile.communityRoster = {
                { name = "TestPlayer-Illidan" },
                { name = "Tyler-Stormrage" },
            }
            WHLSN.session.status = "lobby"

            local sent = {}
            WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
                sent[#sent + 1] = { channel = channel, target = target }
            end
            WHLSN.Serialize = function(self, data) return data end

            WHLSN:SendCommunityPings()

            assert.equals(1, #sent)
            assert.equals("Tyler-Stormrage", sent[1].target)
        end)

        it("should not send pings in test mode", function()
            WHLSN.session.isTest = true

            local sent = {}
            WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
                sent[#sent + 1] = true
            end

            WHLSN:SendCommunityPings()

            assert.equals(0, #sent)
        end)
    end)

    describe("WhisperCommunityPlayers", function()
        it("should whisper all connected community players", function()
            WHLSN.session.connectedCommunity = {
                ["Tyler"] = "Tyler-Stormrage",
                ["Arthas"] = "Arthas-Illidan",
            }

            local sent = {}
            WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
                sent[#sent + 1] = { channel = channel, target = target }
            end

            WHLSN:WhisperCommunityPlayers("test-message")

            assert.equals(2, #sent)
            for _, s in ipairs(sent) do
                assert.equals("WHISPER", s.channel)
            end
        end)

        it("should accept an override community list", function()
            WHLSN.session.connectedCommunity = {}
            local overrideList = { ["Tyler"] = "Tyler-Stormrage" }

            local sent = {}
            WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
                sent[#sent + 1] = { channel = channel, target = target }
            end

            WHLSN:WhisperCommunityPlayers("test-message", overrideList)

            assert.equals(1, #sent)
            assert.equals("Tyler-Stormrage", sent[1].target)
        end)
    end)
end)
