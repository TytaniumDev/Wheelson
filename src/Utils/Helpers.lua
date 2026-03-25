---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Utility Helpers
---------------------------------------------------------------------------

--- WoW class colors (RAID_CLASS_COLORS equivalent for addon use).
WHLSN.CLASS_COLORS = {
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23, hex = "C41E3A" },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79, hex = "A330C9" },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04, hex = "FF7C0A" },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50, hex = "33937F" },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45, hex = "AAD372" },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92, hex = "3FC7EB" },
    MONK        = { r = 0.00, g = 1.00, b = 0.60, hex = "00FF98" },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73, hex = "F48CBA" },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00, hex = "FFFFFF" },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41, hex = "FFF468" },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87, hex = "0070DD" },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93, hex = "8788EE" },
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43, hex = "C69B6D" },
}

--- Format a group summary for chat output.
---@param groups WHLSNGroup[]
---@return string
function WHLSN:FormatGroupSummary(groups)
    local lines = {}
    for i, group in ipairs(groups) do
        local parts = { "Group " .. i .. ":" }

        if group.tank then
            parts[#parts + 1] = "[T] " .. group.tank.name
        end
        if group.healer then
            parts[#parts + 1] = "[H] " .. group.healer.name
        end
        for _, dps in ipairs(group.dps) do
            parts[#parts + 1] = "[D] " .. dps.name
        end

        local utils = {}
        if group:HasBrez() then utils[#utils + 1] = "BR" end
        if group:HasLust() then utils[#utils + 1] = "BL" end
        if #utils > 0 then
            parts[#parts + 1] = "(" .. table.concat(utils, "/") .. ")"
        end

        lines[#lines + 1] = table.concat(parts, " ")
    end
    return table.concat(lines, "\n")
end

--- Get a class-colored name string for display.
---@param player WHLSNPlayer
---@return string
function WHLSN:ColoredPlayerName(player)
    local cc = player.classToken and self.CLASS_COLORS[player.classToken]
    local color = cc and cc.hex or "FFFFFF"
    return "|cFF" .. color .. player.name .. "|r"
end

--- Get a class-colored name string for display.
---@param name string
---@param classToken string
---@return string
function WHLSN:ClassColoredName(name, classToken)
    local classColor = self.CLASS_COLORS[classToken]
    if classColor then
        return "|cFF" .. classColor.hex .. name .. "|r"
    end
    return name
end

--- Get role count summary string.
---@param players WHLSNPlayer[]
---@return string
function WHLSN:GetRoleCountSummary(players)
    local tanks, healers, dps = 0, 0, 0
    for _, p in ipairs(players) do
        if p:IsTankMain() then tanks = tanks + 1
        elseif p:IsHealerMain() then healers = healers + 1
        else dps = dps + 1 end
    end
    return string.format("%d Tank, %d Healer, %d DPS", tanks, healers, dps)
end

--- Get group quality score description.
---@param group WHLSNGroup
---@return string
function WHLSN:GetGroupQuality(group)
    local parts = {}
    if group:HasBrez() then parts[#parts + 1] = "Brez" end
    if group:HasLust() then parts[#parts + 1] = "Lust" end
    if group:HasRanged() then parts[#parts + 1] = "Ranged" end
    if #parts == 0 then return "Missing utilities" end
    return table.concat(parts, ", ")
end

--- Show a player tooltip on a frame. Shared by Lobby and GroupDisplay.
---@param owner table  frame to anchor tooltip to
---@param player WHLSNPlayer  player data
function WHLSN:ShowPlayerTooltip(owner, player)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local cc = player.classToken and self.CLASS_COLORS[player.classToken]
    if cc then
        GameTooltip:AddLine(player.name, cc.r, cc.g, cc.b)
    else
        GameTooltip:AddLine(player.name, 1, 1, 1)
    end

    local role = player.mainRole
    if role then
        local rc = self.RoleColors[role] or { r = 1, g = 1, b = 1 }
        GameTooltip:AddLine("Role: " .. role, rc.r, rc.g, rc.b)
    end

    if #player.offspecs > 0 then
        GameTooltip:AddLine("Offspecs: " .. table.concat(player.offspecs, ", "), 0.7, 0.7, 0.7)
    end

    if player:HasBrez() then
        GameTooltip:AddLine("Battle Rez", 0, 1, 0)
    end
    if player:HasLust() then
        GameTooltip:AddLine("Bloodlust/Heroism", 1, 0.27, 0)
    end

    GameTooltip:Show()
end
