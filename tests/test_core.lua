-- Tests for Core.lua initialization
-- Reproduces BugSack error: attempt to perform arithmetic on a nil value at Core.lua:33

-- Minimal stubs for WoW APIs and libraries
local mock_db = {
    profile = {
        minimap = { hide = false },
        lastSession = nil,
        sessionHistory = {},
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
    end
    if silent then return nil end
    return {}
end

-- WoW API stubs
_G.SlashCmdList = _G.SlashCmdList or {}
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return 71 end
_G.GetNumSpecializations = function() return 3 end
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

-- Load source files in order
dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")

local MPW = _G.Wheelson

describe("Core", function()
    describe("OnInitialize", function()
        local original_tostring

        setup(function()
            original_tostring = _G.tostring
        end)

        teardown(function()
            _G.tostring = original_tostring
        end)

        it("should not error with WoW-style table addresses containing hex letters", function()
            -- WoW's Lua formats tables as "table: 00000213F7A2B460" (no 0x prefix).
            -- Standard Lua uses "table: 0x..." which tonumber() handles.
            -- Override tostring to simulate WoW behavior and reproduce the bug.
            _G.tostring = function(v)
                local s = original_tostring(v)
                if s:match("^table:") then
                    return "table: 00000213F7A2B460"
                end
                return s
            end

            assert.has_no.errors(function()
                MPW:OnInitialize()
            end)
        end)
    end)
end)

describe("Discovery", function()
    before_each(function()
        MPW.addonUsersCache = {}
        MPW.isScanning = false
        MPW.sent_messages = {}
        MPW.SendCommMessage = function(self, prefix, msg, channel)
            self.sent_messages[#self.sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel }
        end
        MPW.Serialize = function(self, data) return data end
        MPW.Deserialize = function(self, msg) return true, msg end
    end)

    describe("OnCommReceived ADDON_PING", function()
        it("should reply with ADDON_PONG when receiving ADDON_PING", function()
            local message = { type = "ADDON_PING" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.equals(1, #MPW.sent_messages)
            local sent = MPW.sent_messages[1]
            assert.equals(MPW.COMM_PREFIX, sent.prefix)
            assert.equals("GUILD", sent.channel)
            assert.equals("ADDON_PONG", sent.msg.type)
            assert.equals("TestPlayer", sent.msg.name)
            assert.equals(MPW.VERSION, sent.msg.version)
        end)

        it("should not reply to own ADDON_PING", function()
            local message = { type = "ADDON_PING" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "TestPlayer")
            assert.equals(0, #MPW.sent_messages)
        end)
    end)

    describe("OnCommReceived ADDON_PONG", function()
        it("should add sender to addonUsersCache", function()
            local message = { type = "ADDON_PONG", name = "OtherPlayer", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.is_not_nil(MPW.addonUsersCache["OtherPlayer"])
            assert.equals("OtherPlayer", MPW.addonUsersCache["OtherPlayer"].name)
            assert.equals("1.0.0", MPW.addonUsersCache["OtherPlayer"].version)
        end)

        it("should strip realm name from sender", function()
            local message = { type = "ADDON_PONG", name = "OtherPlayer-Sargeras", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer-Sargeras")

            assert.is_not_nil(MPW.addonUsersCache["OtherPlayer"])
            assert.is_nil(MPW.addonUsersCache["OtherPlayer-Sargeras"])
        end)

        it("should update existing entry on repeated PONG", function()
            MPW.addonUsersCache["OtherPlayer"] = { name = "OtherPlayer", version = "0.9.0", lastSeen = 100 }

            local message = { type = "ADDON_PONG", name = "OtherPlayer", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.equals("1.0.0", MPW.addonUsersCache["OtherPlayer"].version)
        end)

        it("should not cache own PONG (self-filter blocks it)", function()
            local message = { type = "ADDON_PONG", name = "TestPlayer", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "TestPlayer")

            assert.is_nil(MPW.addonUsersCache["TestPlayer"])
        end)
    end)

    describe("SendAddonPing", function()
        it("should broadcast ADDON_PING to GUILD", function()
            MPW:SendAddonPing()

            assert.is_true(#MPW.sent_messages > 0)
            local sent = MPW.sent_messages[1]
            assert.equals("GUILD", sent.channel)
            assert.equals("ADDON_PING", sent.msg.type)
        end)

        it("should add local player to cache", function()
            MPW:SendAddonPing()

            assert.is_not_nil(MPW.addonUsersCache["TestPlayer"])
            assert.equals("TestPlayer", MPW.addonUsersCache["TestPlayer"].name)
            assert.equals(MPW.VERSION, MPW.addonUsersCache["TestPlayer"].version)
        end)

        it("should set isScanning to true", function()
            MPW:SendAddonPing()
            assert.is_true(MPW.isScanning)
        end)
    end)

    describe("PruneAddonUsersCache", function()
        it("should remove players not in online roster", function()
            MPW.addonUsersCache["OnlinePlayer"] = { name = "OnlinePlayer", version = "1.0", lastSeen = 100 }
            MPW.addonUsersCache["OfflinePlayer"] = { name = "OfflinePlayer", version = "1.0", lastSeen = 100 }

            MPW.GetOnlineGuildMembers = function()
                return { { name = "OnlinePlayer", classToken = "WARRIOR", level = 90, online = true } }
            end

            MPW:PruneAddonUsersCache()

            assert.is_not_nil(MPW.addonUsersCache["OnlinePlayer"])
            assert.is_nil(MPW.addonUsersCache["OfflinePlayer"])
        end)

        it("should keep cache empty if no online members", function()
            MPW.addonUsersCache["SomePlayer"] = { name = "SomePlayer", version = "1.0", lastSeen = 100 }

            MPW.GetOnlineGuildMembers = function() return {} end

            MPW:PruneAddonUsersCache()

            assert.is_nil(MPW.addonUsersCache["SomePlayer"])
        end)
    end)
end)
