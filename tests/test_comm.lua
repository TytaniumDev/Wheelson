-- Tests for Comm.lua restriction and queuing logic

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
    elseif name == "WagoAnalytics" then
        local noop = setmetatable({}, { __index = function() return function() end end })
        return { Register = function(_, _id) return noop end }
    end
    if silent then return nil end
    return {}
end

_G.SlashCmdList = _G.SlashCmdList or {}
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end

-- Mock namespaces for communication restrictions
_G.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
_G.C_MythicPlus = { IsRunActive = function() return false end }
_G.C_PvP = { IsActiveBattlefield = function() return false end }

dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/GroupCreator.lua")
dofile("src/Session.lua")
dofile("src/Comm.lua")
dofile("src/Discovery.lua")
dofile("src/Core.lua")

local WHLSN = _G.Wheelson

describe("Comm.lua - IsCommRestricted", function()
    local orig_IsEncounterInProgress
    local orig_IsRunActive
    local orig_IsActiveBattlefield

    before_each(function()
        WHLSN.commQueue = {}
        orig_IsEncounterInProgress = _G.C_InstanceEncounter.IsEncounterInProgress
        orig_IsRunActive = _G.C_MythicPlus.IsRunActive
        orig_IsActiveBattlefield = _G.C_PvP.IsActiveBattlefield
    end)

    after_each(function()
        _G.C_InstanceEncounter.IsEncounterInProgress = orig_IsEncounterInProgress
        _G.C_MythicPlus.IsRunActive = orig_IsRunActive
        _G.C_PvP.IsActiveBattlefield = orig_IsActiveBattlefield
    end)

    it("should return false when no restriction is active", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return false end
        _G.C_MythicPlus.IsRunActive = function() return false end
        _G.C_PvP.IsActiveBattlefield = function() return false end
        assert.is_false(WHLSN:IsCommRestricted())
    end)

    it("should handle missing APIs without error", function()
        -- Temporarily nil out the entire namespaces
        local old_IE = _G.C_InstanceEncounter
        local old_MP = _G.C_MythicPlus
        local old_PvP = _G.C_PvP

        _G.C_InstanceEncounter = nil
        _G.C_MythicPlus = nil
        _G.C_PvP = nil

        assert.is_false(WHLSN:IsCommRestricted())

        -- Restore them
        _G.C_InstanceEncounter = old_IE
        _G.C_MythicPlus = old_MP
        _G.C_PvP = old_PvP
    end)

    it("should return true when encounter is in progress", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return true end
        _G.C_MythicPlus.IsRunActive = function() return false end
        _G.C_PvP.IsActiveBattlefield = function() return false end
        assert.is_true(WHLSN:IsCommRestricted())
    end)

    it("should return true when mythic plus is active", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return false end
        _G.C_MythicPlus.IsRunActive = function() return true end
        _G.C_PvP.IsActiveBattlefield = function() return false end
        assert.is_true(WHLSN:IsCommRestricted())
    end)

    it("should return true when pvp battlefield is active", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return false end
        _G.C_MythicPlus.IsRunActive = function() return false end
        _G.C_PvP.IsActiveBattlefield = function() return true end
        assert.is_true(WHLSN:IsCommRestricted())
    end)
end)

describe("Comm.lua - SafeSendCommMessage and Queueing", function()
    local orig_IsEncounterInProgress
    local orig_SendCommMessage

    before_each(function()
        WHLSN.commQueue = {}
        WHLSN.sentMessages = {}

        orig_IsEncounterInProgress = _G.C_InstanceEncounter.IsEncounterInProgress
        orig_SendCommMessage = WHLSN.SendCommMessage

        -- Mock the actual sending function to capture calls
        WHLSN.SendCommMessage = function(self, prefix, message, distribution, target)
            table.insert(self.sentMessages, {
                prefix = prefix,
                message = message,
                distribution = distribution,
                target = target
            })
        end
    end)

    after_each(function()
        _G.C_InstanceEncounter.IsEncounterInProgress = orig_IsEncounterInProgress
        WHLSN.SendCommMessage = orig_SendCommMessage
    end)

    it("should send message immediately when not restricted", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return false end

        WHLSN:SafeSendCommMessage("PREF", "hello", "GUILD")

        assert.equals(1, #WHLSN.sentMessages)
        assert.equals("PREF", WHLSN.sentMessages[1].prefix)
        assert.equals("hello", WHLSN.sentMessages[1].message)
        assert.equals(0, #WHLSN.commQueue)
    end)

    it("should queue message when restricted", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return true end

        WHLSN:SafeSendCommMessage("PREF", "hello_queued", "WHISPER", "TargetPlayer")

        assert.equals(0, #WHLSN.sentMessages)
        assert.equals(1, #WHLSN.commQueue)
        assert.equals("PREF", WHLSN.commQueue[1].prefix)
        assert.equals("hello_queued", WHLSN.commQueue[1].message)
        assert.equals("WHISPER", WHLSN.commQueue[1].distribution)
        assert.equals("TargetPlayer", WHLSN.commQueue[1].target)
    end)

    it("should flush queue when restriction lifts", function()
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return true end
        WHLSN:SafeSendCommMessage("P1", "msg1", "GUILD")
        WHLSN:SafeSendCommMessage("P2", "msg2", "WHISPER", "Target")

        assert.equals(0, #WHLSN.sentMessages)
        assert.equals(2, #WHLSN.commQueue)

        -- Attempting to flush while still restricted should do nothing
        WHLSN:FlushCommQueue()
        assert.equals(0, #WHLSN.sentMessages)
        assert.equals(2, #WHLSN.commQueue)

        -- Lift restriction
        _G.C_InstanceEncounter.IsEncounterInProgress = function() return false end
        WHLSN:FlushCommQueue()

        assert.equals(0, #WHLSN.commQueue)
        assert.equals(2, #WHLSN.sentMessages)

        assert.equals("P1", WHLSN.sentMessages[1].prefix)
        assert.equals("msg1", WHLSN.sentMessages[1].message)

        assert.equals("P2", WHLSN.sentMessages[2].prefix)
        assert.equals("msg2", WHLSN.sentMessages[2].message)
        assert.equals("Target", WHLSN.sentMessages[2].target)
    end)
end)
