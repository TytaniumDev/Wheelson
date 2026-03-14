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

_G.LibStub = function(name)
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
    return {}
end

-- WoW API stubs
_G.SlashCmdList = _G.SlashCmdList or {}
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "TestPlayer" end
_G.time = os.time
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
dofile("src/UI/Options.lua")

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
