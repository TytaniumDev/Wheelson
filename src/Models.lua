---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- WoWPlayer
---------------------------------------------------------------------------

---@class WHLSNPlayer
---@field name string
---@field mainRole string|nil  "tank"|"healer"|"ranged"|"melee"
---@field offspecs string[]
---@field utilities string[]
local Player = {}
Player.__index = Player
WHLSN.Player = Player

--- Create a new player.
---@param name string
---@param mainRole string|nil
---@param offspecs? string[]
---@param utilities? string[]
---@return WHLSNPlayer
function Player:New(name, mainRole, offspecs, utilities)
    local p = setmetatable({}, self)
    p.name = name
    p.mainRole = mainRole
    p.offspecs = offspecs or {}
    p.utilities = utilities or {}
    return p
end

-- Computed role checks (mirrors WoWPlayer getters in models.ts)
function Player:IsTankMain() return self.mainRole == "tank" end
function Player:IsHealerMain() return self.mainRole == "healer" end
function Player:IsDpsMain() return self.mainRole == "ranged" or self.mainRole == "melee" end
function Player:IsRanged() return self.mainRole == "ranged" end
function Player:IsMelee() return self.mainRole == "melee" end

function Player:IsOfftank()
    for _, v in ipairs(self.offspecs) do if v == "tank" then return true end end
    return false
end

function Player:IsOffhealer()
    for _, v in ipairs(self.offspecs) do if v == "healer" then return true end end
    return false
end

function Player:IsOffdps()
    for _, v in ipairs(self.offspecs) do
        if v == "ranged" or v == "melee" then return true end
    end
    return false
end

function Player:IsOffranged()
    for _, v in ipairs(self.offspecs) do if v == "ranged" then return true end end
    return false
end

function Player:IsOffmelee()
    for _, v in ipairs(self.offspecs) do if v == "melee" then return true end end
    return false
end

function Player:HasBrez()
    for _, v in ipairs(self.utilities) do if v == "brez" then return true end end
    return false
end

function Player:HasLust()
    for _, v in ipairs(self.utilities) do if v == "lust" then return true end end
    return false
end

function Player:HasRoles()
    return self.mainRole ~= nil or #self.offspecs > 0
end

function Player:Equals(other)
    return self.name == other.name
end

--- Serialize to a table for addon comms.
function Player:ToDict()
    return {
        name = self.name,
        mainRole = self.mainRole,
        offspecs = self.offspecs,
        utilities = self.utilities,
    }
end

--- Deserialize from addon comms table.
---@param data table
---@return WHLSNPlayer
function Player.FromDict(data)
    return Player:New(
        data.name,
        data.mainRole,
        data.offspecs or {},
        data.utilities or {}
    )
end

---------------------------------------------------------------------------
-- WoWGroup
---------------------------------------------------------------------------

---@class WHLSNGroup
---@field tank WHLSNPlayer|nil
---@field healer WHLSNPlayer|nil
---@field dps WHLSNPlayer[]
local Group = {}
Group.__index = Group
WHLSN.Group = Group

--- Create a new group.
---@param tank? WHLSNPlayer
---@param healer? WHLSNPlayer
---@param dps? WHLSNPlayer[]
---@return WHLSNGroup
function Group:New(tank, healer, dps)
    local g = setmetatable({}, self)
    g.tank = tank or nil
    g.healer = healer or nil
    g.dps = dps or {}
    return g
end

function Group:GetPlayers()
    local all = {}
    if self.tank then all[#all + 1] = self.tank end
    if self.healer then all[#all + 1] = self.healer end
    for _, p in ipairs(self.dps) do all[#all + 1] = p end
    return all
end

function Group:GetSize()
    local n = #self.dps
    if self.tank then n = n + 1 end
    if self.healer then n = n + 1 end
    return n
end

function Group:IsComplete()
    return self.tank ~= nil and self.healer ~= nil and #self.dps == 3
end

function Group:HasBrez()
    if self.tank and self.tank:HasBrez() then return true end
    if self.healer and self.healer:HasBrez() then return true end
    for _, p in ipairs(self.dps) do
        if p:HasBrez() then return true end
    end
    return false
end

function Group:HasLust()
    if self.tank and self.tank:HasLust() then return true end
    if self.healer and self.healer:HasLust() then return true end
    for _, p in ipairs(self.dps) do
        if p:HasLust() then return true end
    end
    return false
end

function Group:HasRanged()
    if self.tank and self.tank:IsRanged() then return true end
    if self.healer and self.healer:IsRanged() then return true end
    for _, p in ipairs(self.dps) do
        if p:IsRanged() then return true end
    end
    return false
end

--- Serialize to a table for addon comms.
function Group:ToDict()
    local dpsData = {}
    for _, p in ipairs(self.dps) do
        dpsData[#dpsData + 1] = p:ToDict()
    end
    return {
        tank = self.tank and self.tank:ToDict() or nil,
        healer = self.healer and self.healer:ToDict() or nil,
        dps = dpsData,
    }
end

--- Deserialize from addon comms table.
---@param data table
---@return WHLSNGroup
function Group.FromDict(data)
    local tank = data.tank and Player.FromDict(data.tank) or nil
    local healer = data.healer and Player.FromDict(data.healer) or nil
    local dps = {}
    if data.dps then
        for _, d in ipairs(data.dps) do
            dps[#dps + 1] = Player.FromDict(d)
        end
    end
    return Group:New(tank, healer, dps)
end
