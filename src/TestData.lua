---@class Wheelson
local WHLSN = _G.Wheelson

--- Return the 15-player test roster from MythicPlusDiscordBot PR #254.
---@return WHLSNPlayer[]
function WHLSN:GetTestPlayers()
    local P = self.Player
    return {
        P:New("Temma",       "tank",   {"melee"},                    {"brez"}),
        P:New("Gazzi",       "tank",   {},                           {"brez"}),
        P:New("Quill",       "healer", {"tank", "ranged", "melee"},  {"brez"}),
        P:New("Sorovar",     "healer", {},                           {}),
        P:New("Vanyali",     "ranged", {},                           {}),
        P:New("Tytaniormu",  "ranged", {},                           {"lust"}),
        P:New("Heretofore",  "ranged", {},                           {"lust"}),
        P:New("Poppybrosjr", "ranged", {},                           {"lust"}),
        P:New("Volkareth",   "ranged", {"healer"},                   {"lust"}),
        P:New("Johng",       "melee",  {},                           {"brez"}),
        P:New("jim",         "melee",  {"tank"},                     {}),
        P:New("Raxef",       "melee",  {},                           {}),
        P:New("Mickey",      "melee",  {},                           {}),
        P:New("Khurri",      "melee",  {},                           {"brez"}),
        P:New("Blueshift",   "ranged", {},                           {"lust"}),
    }
end
