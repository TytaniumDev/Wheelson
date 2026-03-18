---@class Wheelson
local WHLSN = LibStub("AceAddon-3.0"):NewAddon(
    "Wheelson", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0"
)
_G.Wheelson = WHLSN

-- Wago Analytics (Shim guarantees WagoAnalytics is never nil)
WHLSN.analytics = LibStub("WagoAnalytics"):Register("kGryLYKy")

-- Addon communication prefix (max 16 chars)
WHLSN.COMM_PREFIX = "WHLSN"

-- Session states (mirrors shared/types.ts SessionStatus)
WHLSN.Status = {
    LOBBY = "lobby",
    SPINNING = "spinning",
    COMPLETED = "completed",
}

-- Role identifiers (mirrors shared/config.ts)
WHLSN.Roles = {
    TANK = "tank",
    HEALER = "healer",
    RANGED = "ranged",
    MELEE = "melee",
}

-- Utility identifiers
WHLSN.Utilities = {
    BREZ = "brez",
    LUST = "lust",
}

-- WoW spec ID → role mapping
-- Updated for Midnight (12.0.1)
WHLSN.SpecRoles = {
    -- Death Knight
    [250] = "tank",    -- Blood
    [251] = "melee",   -- Frost
    [252] = "melee",   -- Unholy
    -- Demon Hunter
    [577] = "melee",   -- Havoc
    [581] = "tank",    -- Vengeance
    [1480] = "ranged", -- Devourer
    -- Druid
    [102] = "ranged",  -- Balance
    [103] = "melee",   -- Feral
    [104] = "tank",    -- Guardian
    [105] = "healer",  -- Restoration
    -- Evoker
    [1467] = "ranged", -- Devastation
    [1468] = "healer", -- Preservation
    [1473] = "ranged", -- Augmentation
    -- Hunter
    [253] = "ranged",  -- Beast Mastery
    [254] = "ranged",  -- Marksmanship
    [255] = "melee",   -- Survival
    -- Mage
    [62] = "ranged",   -- Arcane
    [63] = "ranged",   -- Fire
    [64] = "ranged",   -- Frost
    -- Monk
    [268] = "tank",    -- Brewmaster
    [270] = "healer",  -- Mistweaver
    [269] = "melee",   -- Windwalker
    -- Paladin
    [65] = "healer",   -- Holy
    [66] = "tank",     -- Protection
    [70] = "melee",    -- Retribution
    -- Priest
    [256] = "healer",  -- Discipline
    [257] = "healer",  -- Holy
    [258] = "ranged",  -- Shadow
    -- Rogue
    [259] = "melee",   -- Assassination
    [260] = "melee",   -- Outlaw
    [261] = "melee",   -- Subtlety
    -- Shaman
    [262] = "ranged",  -- Elemental
    [263] = "melee",   -- Enhancement
    [264] = "healer",  -- Restoration
    -- Warlock
    [265] = "ranged",  -- Affliction
    [266] = "ranged",  -- Demonology
    [267] = "ranged",  -- Destruction
    -- Warrior
    [71] = "melee",    -- Arms
    [72] = "melee",    -- Fury
    [73] = "tank",     -- Protection
}

-- Class IDs that have battle rez capability
WHLSN.BrezClasses = {
    ["DEATHKNIGHT"] = true,
    ["DRUID"] = true,
    ["WARLOCK"] = true,
    ["PALADIN"] = true,
}

-- Class IDs that have lust/heroism capability
WHLSN.LustClasses = {
    ["SHAMAN"] = true,
    ["MAGE"] = true,
    ["EVOKER"] = true,
    ["HUNTER"] = true,
}

-- Role colors for UI display (single source of truth)
WHLSN.RoleColors = {
    tank   = { r = 0.53, g = 0.74, b = 0.87, hex = "87BCDE" },
    healer = { r = 0.53, g = 1.0,  b = 0.53, hex = "87FF87" },
    ranged = { r = 1.0,  g = 0.53, b = 0.53, hex = "FF8787" },
    melee  = { r = 1.0,  g = 0.82, b = 0.53, hex = "FFD187" },
}

-- Shared utility icon paths
WHLSN.BREZ_ICON = "Interface\\Icons\\Spell_Nature_Reincarnation"
WHLSN.LUST_ICON = "Interface\\Icons\\Spell_Nature_Bloodlust"

-- Max player level for current expansion (Midnight)
WHLSN.MAX_LEVEL = 90

-- Addon version (replaced by packager with git tag)
WHLSN.VERSION = "@project-version@"
WHLSN.RELEASE_URL = "https://github.com/TytaniumDev/Wheelson/releases/tag/@project-version@"

-- Session timeout in seconds (default 30 minutes)
WHLSN.SESSION_TIMEOUT = 1800

-- Message throttle interval in seconds
WHLSN.COMM_THROTTLE = 0.5

-- Duration in seconds to collect ADDON_PONG responses after a ping
WHLSN.DISCOVERY_SCAN_DURATION = 2

-- Max number of sessions to keep in history
WHLSN.MAX_HISTORY = 10

-- Default saved variables
WHLSN.defaults = {
    profile = {
        minimap = {
            hide = false,
        },
        lastSession = nil,
        sessionHistory = {},
        lastGroups = {},
        framePosition = nil,
        animationSpeed = 1.0,
        soundEnabled = true,
        communityRoster = {},
    },
    char = {
        specOverrides = nil,
    },
}
