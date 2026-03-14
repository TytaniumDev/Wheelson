---@class Wheelson
local MPW = _G.Wheelson

---------------------------------------------------------------------------
-- Options Panel
-- AceConfig-based settings panel shown in Interface > AddOns > Wheelson.
-- Displays online guild members who have the addon installed.
---------------------------------------------------------------------------

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local function GetDiscoveryText()
    if MPW.isScanning then
        return "Scanning..."
    end

    local lines = {}
    local cache = MPW.addonUsersCache or {}
    for _, entry in pairs(cache) do
        lines[#lines + 1] = entry.name .. "  (v" .. entry.version .. ")"
    end

    if #lines == 0 then
        return "No addon users discovered yet. Click Refresh to scan."
    end

    table.sort(lines)
    return table.concat(lines, "\n")
end

local options = {
    name = "Wheelson",
    type = "group",
    args = {
        discoveryHeader = {
            order = 1,
            type = "header",
            name = "Online Addon Users",
        },
        discoveryDesc = {
            order = 2,
            type = "description",
            name = function() return GetDiscoveryText() end,
            fontSize = "medium",
        },
        refresh = {
            order = 3,
            type = "execute",
            name = "Refresh",
            desc = "Scan for guild members with Wheelson installed",
            func = function()
                MPW:SendAddonPing()
            end,
        },
    },
}

AceConfig:RegisterOptionsTable("Wheelson", options)
AceConfigDialog:AddToBlizOptions("Wheelson")
