-- Tests for Helpers.lua bug report formatting
math.randomseed(1)
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
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
    addon.New = function(_, name, defaults) return { profile = defaults and defaults.profile or {} } end
    return addon
end

_G.date = os.date
_G.IsInGuild = function() return true end
_G.C_ChatInfo = { SendChatMessage = function() end }

dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Utils/Helpers.lua")

local WHLSN = _G.Wheelson
local Player = WHLSN.Player
local Group = WHLSN.Group

describe("FormatBugReport", function()
    it("should contain both human-readable and lua test case sections", function()
        local snapshot = {
            timestamp = 1710460542,
            host = "TestHost",
            playerCount = 5,
            players = {
                Player:New("Tank1", "tank", {}, {"brez"}):ToDict(),
                Player:New("Healer1", "healer", {"ranged"}, {}):ToDict(),
                Player:New("DPS1", "ranged", {}, {"lust"}):ToDict(),
                Player:New("DPS2", "melee", {}, {}):ToDict(),
                Player:New("DPS3", "ranged", {}, {}):ToDict(),
            },
            groups = {
                Group:New(
                    Player:New("Tank1", "tank", {}, {"brez"}),
                    Player:New("Healer1", "healer", {"ranged"}, {}),
                    {
                        Player:New("DPS1", "ranged", {}, {"lust"}),
                        Player:New("DPS2", "melee", {}, {}),
                        Player:New("DPS3", "ranged", {}, {}),
                    }
                ):ToDict(),
            },
            lastGroups = {},
        }

        local report = WHLSN:FormatBugReport(snapshot)

        -- Should contain human-readable section
        assert.truthy(report:find("Bad Grouping Report"))
        assert.truthy(report:find("Host:.*TestHost"))
        assert.truthy(report:find("Players:.*5"))
        -- Should contain player table
        assert.truthy(report:find("Tank1"))
        assert.truthy(report:find("Healer1"))

        -- Should contain group summary
        assert.truthy(report:find("Group 1"))

        -- Should contain lua test case section with multi-trial loop
        assert.truthy(report:find("LUA TEST CASE"))
        assert.truthy(report:find("for trial = 1, 20 do"))
        assert.truthy(report:find("CreateMythicPlusGroups"))
    end)

    it("should show full and incomplete group counts", function()
        local snapshot = {
            timestamp = 1710460542,
            host = "Host",
            playerCount = 7,
            players = {},
            groups = {
                Group:New(
                    Player:New("T1", "tank", {}, {}),
                    Player:New("H1", "healer", {}, {}),
                    {
                        Player:New("D1", "melee", {}, {}),
                        Player:New("D2", "melee", {}, {}),
                        Player:New("D3", "ranged", {}, {}),
                    }
                ):ToDict(),
                Group:New(
                    nil,
                    nil,
                    {
                        Player:New("D4", "melee", {}, {}),
                        Player:New("D5", "ranged", {}, {}),
                    }
                ):ToDict(),
            },
            lastGroups = {},
        }

        local report = WHLSN:FormatBugReport(snapshot)
        assert.truthy(report:find("Groups created:.*2"))
        assert.truthy(report:find("1 full"))
        assert.truthy(report:find("1 incomplete"))
    end)

    it("should include lastGroups when present", function()
        local snapshot = {
            timestamp = 1710460542,
            host = "Host",
            playerCount = 5,
            players = {
                Player:New("Tank1", "tank", {}, {}):ToDict(),
            },
            groups = {
                Group:New(
                    Player:New("Tank1", "tank", {}, {}),
                    nil,
                    {}
                ):ToDict(),
            },
            lastGroups = {
                Group:New(
                    Player:New("OldTank", "tank", {}, {}),
                    Player:New("OldHealer", "healer", {}, {}),
                    {
                        Player:New("OldDPS1", "melee", {}, {}),
                        Player:New("OldDPS2", "ranged", {}, {}),
                        Player:New("OldDPS3", "ranged", {}, {}),
                    }
                ):ToDict(),
            },
        }

        local report = WHLSN:FormatBugReport(snapshot)
        assert.truthy(report:find("Last Groups"))
        assert.truthy(report:find("OldTank"))
    end)

    it("should show 'None' for lastGroups when empty", function()
        local snapshot = {
            timestamp = 1710460542,
            host = "Host",
            playerCount = 5,
            players = {},
            groups = {},
            lastGroups = {},
        }

        local report = WHLSN:FormatBugReport(snapshot)
        assert.truthy(report:find("None"))
    end)

    it("should produce valid lua table syntax in test case", function()
        local snapshot = {
            timestamp = 1710460542,
            host = "Host",
            playerCount = 1,
            players = {
                Player:New("Tank1", "tank", {"healer", "melee"}, {"brez"}):ToDict(),
            },
            groups = {},
            lastGroups = {},
        }

        local report = WHLSN:FormatBugReport(snapshot)
        -- Check that offspecs and utilities are formatted as lua tables
        assert.truthy(report:find('"healer"'))
        assert.truthy(report:find('"brez"'))
    end)
end)
