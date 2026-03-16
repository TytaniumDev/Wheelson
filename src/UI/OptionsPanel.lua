---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Options Panel
-- AceConfig-based settings panel shown in Interface > AddOns > Wheelson.
-- Displays online guild members who have the addon installed.
---------------------------------------------------------------------------

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local function GetDiscoveryText()
    if WHLSN.isScanning then
        return "Scanning..."
    end

    local lines = {}
    local cache = WHLSN.addonUsersCache or {}
    for _, entry in pairs(cache) do
        lines[#lines + 1] = entry.name .. "  (" .. entry.version .. ")"
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
        minimapIcon = {
            order = 0,
            type = "toggle",
            name = "Show Minimap Icon",
            desc = "Show or hide the Wheelson minimap button",
            get = function() return not WHLSN.db.profile.minimap.hide end,
            set = function(_, value)
                local isVisible = not WHLSN.db.profile.minimap.hide
                if value ~= isVisible then
                    WHLSN:ToggleMinimapIcon()
                end
            end,
        },
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
                WHLSN:SendAddonPing()
            end,
        },
        versionHeader = {
            order = 10,
            type = "header",
            name = "Version",
        },
        versionDesc = {
            order = 11,
            type = "description",
            name = WHLSN.VERSION,
            fontSize = "medium",
        },
        releaseUrl = {
            order = 12,
            type = "input",
            name = "Release Link",
            desc = "Copy this URL to view the release on GitHub",
            get = function() return WHLSN.RELEASE_URL end,
            set = function() end,
            width = "full",
        },
    },
}

AceConfig:RegisterOptionsTable("Wheelson", options)
AceConfigDialog:AddToBlizOptions("Wheelson")
