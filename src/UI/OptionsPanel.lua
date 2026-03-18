---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Options Panel
-- AceConfig-based settings panel shown in Interface > AddOns > Wheelson.
-- Displays online guild members who have the addon installed.
---------------------------------------------------------------------------

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
        communityHeader = {
            order = 20,
            type = "header",
            name = "Community Roster",
        },
        communityDesc = {
            order = 21,
            type = "description",
            name = "Add non-guild players who have Wheelson installed. They'll be whispered when you create a lobby.",
            fontSize = "medium",
        },
        communityAddName = {
            order = 22,
            type = "input",
            name = "Add Player",
            desc = "Enter player name (e.g., 'Tyler' for same realm, 'Tyler-Illidan' for cross-realm)",
            set = function(_, val)
                local ok, err = WHLSN:AddCommunityPlayer(val)
                if ok then
                    WHLSN:Print("Added " .. WHLSN:NormalizeCommunityName(val) .. " to community roster.")
                else
                    WHLSN:Print("Could not add: " .. (err or "unknown error"))
                end
            end,
            get = function() return "" end,
            width = "full",
        },
        communityList = {
            order = 23,
            type = "description",
            name = function()
                local roster = WHLSN.db and WHLSN.db.profile.communityRoster or {}
                if #roster == 0 then
                    return "No players in roster."
                end
                local lines = {}
                for _, entry in ipairs(roster) do
                    lines[#lines + 1] = "  " .. entry.name
                end
                return table.concat(lines, "\n")
            end,
            fontSize = "medium",
        },
        communityRemoveName = {
            order = 24,
            type = "input",
            name = "Remove Player",
            desc = "Enter player name to remove from roster",
            set = function(_, val)
                if not val or strtrim(val) == "" then return end
                local ok = WHLSN:RemoveCommunityPlayer(val)
                if ok then
                    WHLSN:Print("Removed '" .. val .. "' from community roster.")
                else
                    WHLSN:Print("Player '" .. val .. "' not found in roster.")
                end
            end,
            get = function() return "" end,
            width = "full",
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

function WHLSN:SetupOptionsPanel()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    AceConfig:RegisterOptionsTable("Wheelson", options)
    AceConfigDialog:AddToBlizOptions("Wheelson")
end
