-- Tests for Wheel.lua: BuildReelPool, PadReelPool, and easing functions

-- LibStub stub that dispatches by library name
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
                return { profile = defaults and defaults.profile or {} }
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
    elseif name == "AceConfigRegistry-3.0" then
        return {
            RegisterOptionsTable = function() end,
            NotifyChange = function() end,
        }
    end
    if silent then return nil end
    return {}
end

-- WoW API stubs
_G.SlashCmdList = {}
_G.time = os.time
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

_G.SOUNDKIT = {}
_G.PlaySound = function() end
_G.C_Timer = {
    NewTimer = function(_, cb) return { Cancel = function() end } end,
    After = function(_, cb) end,
}
_G.UnitName = function() return "TestPlayer" end
_G.UIParent = {}

local function makeFrame()
    local frame = {}
    frame.SetAllPoints = function() end
    frame.SetPoint = function() end
    frame.ClearAllPoints = function() end
    frame.SetSize = function() end
    frame.Show = function() end
    frame.Hide = function() end
    frame.SetShown = function() end
    frame.SetScript = function() end
    frame.SetText = function() end
    frame.SetBackdrop = function() end
    frame.SetBackdropColor = function() end
    frame.SetAlpha = function() end
    frame.GetWidth = function() return 568 end
    frame.GetHeight = function() return 400 end
    frame.IsShown = function() return false end
    frame.SetToFinalAlpha = function() end
    frame.SetResizable = function() end
    frame.SetResizeBounds = function() end
    frame.CreateFontString = function()
        return {
            SetPoint = function() end,
            SetText = function() end,
            SetTextColor = function() end,
            SetAlpha = function() end,
        }
    end
    frame.CreateTexture = function()
        return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
            SetTexture = function() end,
        }
    end
    frame.CreateAnimationGroup = function()
        local ag = {}
        ag.CreateAnimation = function()
            return {
                SetFromAlpha = function() end,
                SetToAlpha = function() end,
                SetDuration = function() end,
                SetSmoothing = function() end,
            }
        end
        ag.SetScript = function() end
        ag.Play = function() end
        return ag
    end
    return frame
end

_G.CreateFrame = function(frameType, name, parent, template)
    return makeFrame()
end

-- Stub WoW API calls used in Core.lua
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71 end,
}
_G.GetNumSpecializations = function() return 3 end
_G.date = os.date
_G.Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { ID = name } end,
    RegisterAddOnCategory = function() end,
}
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end

-- Load source files in order
dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Core.lua")
dofile("src/UI/Wheel.lua")

local WHLSN = _G.Wheelson
local Player = WHLSN.Player

-- ---------------------------------------------------------------------------
-- BuildReelPool tests
-- ---------------------------------------------------------------------------

describe("BuildReelPool", function()
    local tankMain, offtank, healerMain, dpsMain, offDps

    before_each(function()
        tankMain   = Player:New("TankPlayer",   "tank",   {},         {})
        offtank    = Player:New("OfftankPlayer", "melee",  {"tank"},   {})
        healerMain = Player:New("HealPlayer",   "healer", {},         {})
        dpsMain    = Player:New("DpsPlayer",    "ranged", {},         {})
        offDps     = Player:New("OffDpsPlayer", "tank",   {"ranged"}, {})
    end)

    it("should include main-role players for tank", function()
        local pool = WHLSN.BuildReelPool({tankMain, healerMain, dpsMain}, "tank", "TankPlayer", {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["TankPlayer"])
    end)

    it("should include offspec players for tank", function()
        local pool = WHLSN.BuildReelPool({tankMain, offtank, dpsMain}, "tank", "TankPlayer", {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["OfftankPlayer"])
    end)

    it("should not include non-eligible players", function()
        local pool = WHLSN.BuildReelPool({tankMain, healerMain, dpsMain}, "tank", "TankPlayer", {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_nil(names["HealPlayer"])
        assert.is_nil(names["DpsPlayer"])
    end)

    it("should include DPS main and offspec players for dps role", function()
        local pool = WHLSN.BuildReelPool({dpsMain, offDps, tankMain, healerMain}, "dps", "DpsPlayer", {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["DpsPlayer"])
        assert.is_true(names["OffDpsPlayer"])
        assert.is_nil(names["TankPlayer"])
        assert.is_nil(names["HealPlayer"])
    end)

    it("should force-insert winner even if not in pool", function()
        -- healerMain is not a tank, but is the winner for a tank reel
        local pool = WHLSN.BuildReelPool({tankMain, dpsMain}, "tank", "HealPlayer", {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["HealPlayer"])
    end)

    it("should exclude specified names", function()
        local pool = WHLSN.BuildReelPool({tankMain, offtank, dpsMain}, "tank", "TankPlayer", {OfftankPlayer = true})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_nil(names["OfftankPlayer"])
        assert.is_true(names["TankPlayer"])
    end)

    it("should not exclude the winner even if in exclude list", function()
        local pool = WHLSN.BuildReelPool({tankMain, offtank}, "tank", "TankPlayer", {TankPlayer = true})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["TankPlayer"])
    end)
end)

-- ---------------------------------------------------------------------------
-- PadReelPool tests
-- ---------------------------------------------------------------------------

describe("PadReelPool", function()
    it("should not pad a pool already at min size", function()
        local names = {"Alice", "Bob", "Charlie", "Dave", "Eve"}
        local result = WHLSN.PadReelPool(names, 5)
        assert.equal(5, #result)
    end)

    it("should cycle names to reach min size", function()
        local names = {"Alice", "Bob"}
        local result = WHLSN.PadReelPool(names, 5)
        assert.equal(5, #result)
        -- First two should be original
        assert.equal("Alice", result[1])
        assert.equal("Bob", result[2])
        -- Should cycle: Alice, Bob, Alice
        assert.equal("Alice", result[3])
        assert.equal("Bob", result[4])
        assert.equal("Alice", result[5])
    end)

    it("should handle single name", function()
        local names = {"Solo"}
        local result = WHLSN.PadReelPool(names, 4)
        assert.equal(4, #result)
        for _, n in ipairs(result) do
            assert.equal("Solo", n)
        end
    end)
end)
