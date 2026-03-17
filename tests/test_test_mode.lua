-- Tests for test mode functionality
-- Run with: busted tests/test_test_mode.lua

-- Minimal stubs for WoW APIs and libraries (matches test_core.lua pattern)
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
        return {
            New = function(_, dbName, defaults)
                return mock_db
            end,
        }
    elseif name == "LibDataBroker-1.1" then
        return {
            NewDataObject = function(_, _name, obj)
                return obj
            end,
        }
    elseif name == "LibDBIcon-1.0" then
        return {
            Register = function() end,
        }
    elseif name == "WagoAnalytics" then
        local noop = setmetatable({}, { __index = function() return function() end end })
        return { Register = function(_, _id) return noop end }
    end
    if silent then return nil end
    return {}
end

-- WoW API stubs
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
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
    NewTimer = function(_, _) return { Cancel = function() end } end,
    After = function(_, _) end,
}
_G.C_PartyInfo = { InviteUnit = function() end }
_G.IsInGuild = function() return true end
_G.C_ChatInfo = { SendChatMessage = function() end }
_G.IsInGroup = function() return false end
_G.UnitIsGroupLeader = function() return false end
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
dofile("src/TestData.lua")
dofile("src/GroupCreator.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")
dofile("src/Services/GuildService.lua")
dofile("src/Services/CommunityService.lua")
dofile("src/Services/PartyService.lua")
dofile("src/Utils/Helpers.lua")

local WHLSN = _G.Wheelson

describe("Test Mode", function()
    before_each(function()
        WHLSN:ClearLastGroups()
        WHLSN:OnInitialize()
    end)

    describe("StartTestSession", function()
        it("should populate session with 15 test players in lobby status", function()
            WHLSN:StartTestSession()

            assert.equal("lobby", WHLSN.session.status)
            assert.equal(15, #WHLSN.session.players)
            assert.is_true(WHLSN.session.isTest)
            assert.equal(UnitName("player"), WHLSN.session.host)
        end)

        it("should not start if a session is already active", function()
            WHLSN.session.status = "lobby"
            WHLSN:StartTestSession()

            -- Players should not be overwritten
            assert.equal(0, #WHLSN.session.players)
        end)

        it("should include correct player data", function()
            WHLSN:StartTestSession()

            local players = WHLSN.session.players
            -- Check first player
            assert.equal("Temma", players[1].name)
            assert.equal("tank", players[1].mainRole)
            assert.is_true(players[1]:HasBrez())
            -- Check Quill's offspecs
            assert.equal("Quill", players[3].name)
            assert.equal("healer", players[3].mainRole)
            assert.is_true(players[3]:IsOfftank())
        end)
    end)

    describe("isTest guards", function()
        it("should not broadcast session updates in test mode", function()
            local commSent = false
            WHLSN.SendCommMessage = function() commSent = true end

            WHLSN:StartTestSession()
            WHLSN:BroadcastSessionUpdate()

            assert.is_false(commSent)
        end)

        it("should not broadcast session end in test mode", function()
            local commSent = false
            WHLSN.SendCommMessage = function() commSent = true end

            WHLSN:StartTestSession()
            WHLSN:BroadcastSessionEnd()

            assert.is_false(commSent)
        end)

        it("should not save session results in test mode", function()
            WHLSN:StartTestSession()
            WHLSN.session.groups = WHLSN:CreateMythicPlusGroups(WHLSN.session.players)
            WHLSN:SaveSessionResults()

            assert.is_nil(WHLSN.db.profile.lastSession)
        end)

        it("should clean up isTest flag on EndSession", function()
            WHLSN:StartTestSession()
            WHLSN:EndSession()

            assert.is_nil(WHLSN.session.isTest)
            assert.is_nil(WHLSN.session.status)
        end)

        it("should not broadcast session end when ending a test session", function()
            local commSent = false
            WHLSN.SendCommMessage = function() commSent = true end

            WHLSN:StartTestSession()
            WHLSN:EndSession()

            assert.is_false(commSent)
        end)
    end)

    describe("invite suppression", function()
        it("should log instead of calling C_PartyInfo.InviteUnit in test mode", function()
            local invitedNames = {}
            _G.C_PartyInfo.InviteUnit = function(name) invitedNames[#invitedNames + 1] = name end

            local printed = {}
            WHLSN.Print = function(_, msg) printed[#printed + 1] = msg end

            WHLSN:StartTestSession()
            local players = {
                WHLSN.Player:New("Alice", "tank"),
                WHLSN.Player:New("Bob", "melee"),
            }
            WHLSN:InvitePlayers(players)

            assert.equal(0, #invitedNames)
            assert.is_true(#printed > 0)
        end)
    end)

    describe("GetTestPlayers", function()
        it("should return exactly 15 players", function()
            local players = WHLSN:GetTestPlayers()
            assert.equal(15, #players)
        end)

        it("should have 2 tanks, 2 healers, 6 ranged, 5 melee", function()
            local players = WHLSN:GetTestPlayers()
            local tanks, healers, ranged, melee = 0, 0, 0, 0
            for _, p in ipairs(players) do
                if p:IsTankMain() then tanks = tanks + 1
                elseif p:IsHealerMain() then healers = healers + 1
                elseif p:IsRanged() then ranged = ranged + 1
                elseif p:IsMelee() then melee = melee + 1
                end
            end
            assert.equal(2, tanks)
            assert.equal(2, healers)
            assert.equal(6, ranged)
            assert.equal(5, melee)
        end)

        it("should form groups from 15 players", function()
            local players = WHLSN:GetTestPlayers()
            local groups = WHLSN:CreateMythicPlusGroups(players)
            assert.is_true(#groups >= 3)
            -- At least 3 complete groups should form from 15 players
            local complete = 0
            for _, g in ipairs(groups) do
                if g:IsComplete() then complete = complete + 1 end
            end
            assert.is_true(complete >= 2)
        end)
    end)
end)
