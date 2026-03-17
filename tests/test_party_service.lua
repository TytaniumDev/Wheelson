-- Tests for PartyService.lua

local mock_db = {
    profile = {
        minimap = { hide = false },
        lastSession = nil,
        sessionHistory = {},
        communityRoster = {},
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
        return { New = function(_, dbName, defaults) return mock_db end }
    elseif name == "LibDataBroker-1.1" then
        return { NewDataObject = function(_, _name, obj) return obj end }
    elseif name == "LibDBIcon-1.0" then
        return { Register = function() end, Show = function() end, Hide = function() end }
    elseif name == "WagoAnalytics" then
        local noop = setmetatable({}, { __index = function() return function() end end })
        return { Register = function(_, _id) return noop end }
    end
    if silent then return nil end
    return {}
end

_G.SlashCmdList = _G.SlashCmdList or {}
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71 end,
}
_G.GetNumSpecializations = function() return 3 end
_G.GetNormalizedRealmName = function() return "Illidan" end
_G.time = os.time
_G.date = os.date
_G.C_Timer = {
    NewTimer = function(_, cb) return { Cancel = function() end } end,
    After = function(_, cb) end,
}
_G.CreateFrame = function()
    return {
        CreateFontString = function()
            return { SetPoint = function() end, SetText = function() end }
        end,
    }
end
_G.Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { ID = name } end,
    RegisterAddOnCategory = function() end,
}
_G.C_PartyInfo = { InviteUnit = function() end }
_G.IsInGroup = function() return false end
_G.UnitIsGroupLeader = function() return false end

dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
dofile("src/GroupCreator.lua")
dofile("src/Services/CommunityService.lua")
dofile("src/Services/PartyService.lua")

local WHLSN = _G.Wheelson

describe("InvitePlayers", function()
    local invited, printed

    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.db.profile.communityRoster = {}
        WHLSN.session.connectedCommunity = {}
        WHLSN.session.isTest = false
        invited = {}
        printed = {}
        _G.C_PartyInfo.InviteUnit = function(name) invited[#invited + 1] = name end
        WHLSN.Print = function(_, msg) printed[#printed + 1] = msg end
    end)

    it("should use realm-qualified name from connectedCommunity", function()
        WHLSN.session.connectedCommunity = { ["Tyler"] = "Tyler-Kel'Thuzad" }
        local players = { WHLSN.Player:New("Tyler", "healer") }

        WHLSN:InvitePlayers(players)

        assert.equals(1, #invited)
        assert.equals("Tyler-Kel'Thuzad", invited[1])
    end)

    it("should fall back to GetCommunityPlayerFullName for roster-only players", function()
        WHLSN:AddCommunityPlayer("Tyler-Kel'Thuzad")
        -- connectedCommunity empty: Tyler not connected this session via whisper
        local players = { WHLSN.Player:New("Tyler", "healer") }

        WHLSN:InvitePlayers(players)

        assert.equals(1, #invited)
        assert.equals("Tyler-Kel'Thuzad", invited[1])
    end)

    it("should use realm-qualified name set by HandleJoinRequest for cross-realm guild members", function()
        -- Simulate a cross-realm guild member joining: HandleJoinRequest sets
        -- player.name to the realm-qualified sender when sender contains "-"
        local players = { WHLSN.Player:New("Healer1-Stormrage", "healer") }

        WHLSN:InvitePlayers(players)

        assert.equals(1, #invited)
        assert.equals("Healer1-Stormrage", invited[1])
    end)

    it("should fall back to bare name for guild-only players", function()
        local players = { WHLSN.Player:New("GuildTank", "tank") }

        WHLSN:InvitePlayers(players)

        assert.equals(1, #invited)
        assert.equals("GuildTank", invited[1])
    end)

    it("should skip the local player", function()
        local players = {
            WHLSN.Player:New("TestPlayer", "tank"),
            WHLSN.Player:New("Healer1", "healer"),
        }

        WHLSN:InvitePlayers(players)

        assert.equals(1, #invited)
        assert.equals("Healer1", invited[1])
    end)

    it("should print 'Invited: <names>' in live mode", function()
        local players = { WHLSN.Player:New("Healer1", "healer") }

        WHLSN:InvitePlayers(players)

        assert.equals(1, #printed)
        assert.truthy(printed[1]:find("^Invited:"))
        assert.truthy(printed[1]:find("Healer1"))
    end)

    it("should not call InviteUnit and print '[Test] Would invite:' in test mode", function()
        WHLSN.session.isTest = true
        local players = { WHLSN.Player:New("Healer1", "healer") }

        WHLSN:InvitePlayers(players)

        assert.equals(0, #invited)
        assert.equals(1, #printed)
        assert.truthy(printed[1]:find("^%[Test%] Would invite:"))
        assert.truthy(printed[1]:find("Healer1"))
    end)

    it("should print 'No players to invite.' when only local player in list", function()
        local players = { WHLSN.Player:New("TestPlayer", "tank") }

        WHLSN:InvitePlayers(players)

        assert.equals(0, #invited)
        assert.equals(1, #printed)
        assert.equals("No players to invite.", printed[1])
    end)
end)

describe("HandleJoinRequest cross-realm", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer", "tank") }
        WHLSN.session.connectedCommunity = {}
        WHLSN.Print = function() end
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.IsCommunityRosterMember = function() return false end
    end)

    it("should preserve realm-qualified name for cross-realm guild members", function()
        local data = {
            type = "JOIN_REQUEST",
            player = {
                name = "CrossRealmPlayer",
                mainRole = "healer",
                offspecs = {},
                utilities = {},
                classToken = "PRIEST",
            },
        }

        WHLSN:HandleJoinRequest(data, "CrossRealmPlayer-Stormrage", "GUILD")

        assert.equals(2, #WHLSN.session.players)
        assert.equals("CrossRealmPlayer-Stormrage", WHLSN.session.players[2].name)
    end)

    it("should keep bare name for same-realm guild members", function()
        local data = {
            type = "JOIN_REQUEST",
            player = {
                name = "SameRealmPlayer",
                mainRole = "melee",
                offspecs = {},
                utilities = {},
                classToken = "ROGUE",
            },
        }

        WHLSN:HandleJoinRequest(data, "SameRealmPlayer", "GUILD")

        assert.equals(2, #WHLSN.session.players)
        assert.equals("SameRealmPlayer", WHLSN.session.players[2].name)
    end)

    it("should update realm-qualified name on re-join", function()
        -- First join
        local data = {
            type = "JOIN_REQUEST",
            player = {
                name = "CrossRealmPlayer",
                mainRole = "healer",
                offspecs = {},
                utilities = {},
                classToken = "PRIEST",
            },
        }
        WHLSN:HandleJoinRequest(data, "CrossRealmPlayer-Stormrage", "GUILD")

        -- Re-join with updated spec
        data.player.mainRole = "ranged"
        WHLSN:HandleJoinRequest(data, "CrossRealmPlayer-Stormrage", "GUILD")

        assert.equals(2, #WHLSN.session.players)
        assert.equals("CrossRealmPlayer-Stormrage", WHLSN.session.players[2].name)
        assert.equals("ranged", WHLSN.session.players[2].mainRole)
    end)
end)
