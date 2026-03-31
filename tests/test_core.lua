-- Tests for Core.lua initialization
-- Reproduces BugSack error: attempt to perform arithmetic on a nil value at Core.lua:33

-- Minimal stubs for WoW APIs and libraries
local mock_db = {
    profile = {
        minimap = { hide = false },
        lastSession = nil,
        sessionHistory = {},
        lastGroups = {},
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
            Show = function() end,
            Hide = function() end,
        }
    elseif name == "WagoAnalytics" then
        local noop = setmetatable({}, { __index = function() return function() end end })
        return { Register = function(_, _id) return noop end }
    end
    if silent then return nil end
    return {}
end

-- WoW API stubs
_G.SlashCmdList = _G.SlashCmdList or {}
_G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71 end,
}
_G.GetNumSpecializations = function() return 3 end
_G.time = os.time
_G.date = os.date
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
_G.C_PartyInfo = { InviteUnit = function() end }

_G.GetNormalizedRealmName = function() return "Illidan" end

-- Load source files in order
dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Session.lua")
dofile("src/Comm.lua")
dofile("src/Discovery.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
dofile("src/GroupCreator.lua")
dofile("src/Services/CommunityService.lua")
dofile("src/UI/SpecOverride.lua")
dofile("src/UI/CommunityPanel.lua")
dofile("src/UI/Lobby.lua")
dofile("src/Services/PartyService.lua")
dofile("src/UI/GroupDisplay.lua")

local WHLSN = _G.Wheelson

-- Save original methods before any test can override them
local originalSendSessionUpdate = WHLSN.SendSessionUpdate

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
                WHLSN:OnInitialize()
            end)
        end)
    end)
end)

describe("Discovery", function()
    before_each(function()
        WHLSN.addonUsersCache = {}
        WHLSN.isScanning = false
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel)
            self.sent_messages[#self.sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel }
        end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    describe("OnCommReceived ADDON_PING", function()
        it("should reply with ADDON_PONG when receiving ADDON_PING", function()
            local message = { type = "ADDON_PING" }
            WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.equals(1, #WHLSN.sent_messages)
            local sent = WHLSN.sent_messages[1]
            assert.equals(WHLSN.COMM_PREFIX, sent.prefix)
            assert.equals("GUILD", sent.channel)
            assert.equals("ADDON_PONG", sent.msg.type)
            assert.equals("TestPlayer", sent.msg.name)
            assert.equals(WHLSN.VERSION, sent.msg.version)
        end)

        it("should not reply to own ADDON_PING", function()
            local message = { type = "ADDON_PING" }
            WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, message, "GUILD", "TestPlayer")
            assert.equals(0, #WHLSN.sent_messages)
        end)
    end)

    describe("OnCommReceived ADDON_PONG", function()
        it("should add sender to addonUsersCache", function()
            local message = { type = "ADDON_PONG", name = "OtherPlayer", version = "1.0.0" }
            WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.is_not_nil(WHLSN.addonUsersCache["OtherPlayer"])
            assert.equals("OtherPlayer", WHLSN.addonUsersCache["OtherPlayer"].name)
            assert.equals("1.0.0", WHLSN.addonUsersCache["OtherPlayer"].version)
        end)

        it("should strip realm name from sender", function()
            local message = { type = "ADDON_PONG", name = "OtherPlayer-Sargeras", version = "1.0.0" }
            WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, message, "GUILD", "OtherPlayer-Sargeras")

            assert.is_not_nil(WHLSN.addonUsersCache["OtherPlayer"])
            assert.is_nil(WHLSN.addonUsersCache["OtherPlayer-Sargeras"])
        end)

        it("should update existing entry on repeated PONG", function()
            WHLSN.addonUsersCache["OtherPlayer"] = { name = "OtherPlayer", version = "0.9.0", lastSeen = 100 }

            local message = { type = "ADDON_PONG", name = "OtherPlayer", version = "1.0.0" }
            WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.equals("1.0.0", WHLSN.addonUsersCache["OtherPlayer"].version)
        end)

        it("should not cache own PONG (self-filter blocks it)", function()
            local message = { type = "ADDON_PONG", name = "TestPlayer", version = "1.0.0" }
            WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, message, "GUILD", "TestPlayer")

            assert.is_nil(WHLSN.addonUsersCache["TestPlayer"])
        end)
    end)

    describe("SendAddonPing", function()
        it("should broadcast ADDON_PING to GUILD", function()
            WHLSN:SendAddonPing()

            assert.is_true(#WHLSN.sent_messages > 0)
            local sent = WHLSN.sent_messages[1]
            assert.equals("GUILD", sent.channel)
            assert.equals("ADDON_PING", sent.msg.type)
        end)

        it("should add local player to cache", function()
            WHLSN:SendAddonPing()

            assert.is_not_nil(WHLSN.addonUsersCache["TestPlayer"])
            assert.equals("TestPlayer", WHLSN.addonUsersCache["TestPlayer"].name)
            assert.equals(WHLSN.VERSION, WHLSN.addonUsersCache["TestPlayer"].version)
        end)

        it("should set isScanning to true", function()
            WHLSN:SendAddonPing()
            assert.is_true(WHLSN.isScanning)
        end)
    end)

    describe("PruneAddonUsersCache", function()
        it("should remove players not in online roster", function()
            WHLSN.addonUsersCache["OnlinePlayer"] = { name = "OnlinePlayer", version = "1.0", lastSeen = 100 }
            WHLSN.addonUsersCache["OfflinePlayer"] = { name = "OfflinePlayer", version = "1.0", lastSeen = 100 }

            WHLSN.GetOnlineGuildMembers = function()
                return { { name = "OnlinePlayer", classToken = "WARRIOR", level = 90, online = true } }
            end

            WHLSN:PruneAddonUsersCache()

            assert.is_not_nil(WHLSN.addonUsersCache["OnlinePlayer"])
            assert.is_nil(WHLSN.addonUsersCache["OfflinePlayer"])
        end)

        it("should keep cache empty if no online members", function()
            WHLSN.addonUsersCache["SomePlayer"] = { name = "SomePlayer", version = "1.0", lastSeen = 100 }

            WHLSN.GetOnlineGuildMembers = function() return {} end

            WHLSN:PruneAddonUsersCache()

            assert.is_nil(WHLSN.addonUsersCache["SomePlayer"])
        end)
    end)
end)

describe("ClearSessionState", function()
    before_each(function()
        WHLSN:OnInitialize()
    end)

    it("should reset all session fields to defaults", function()
        WHLSN.session.status = "completed"
        WHLSN.session.host = "SomeHost"
        WHLSN.session.players = { WHLSN.Player:New("P1", "tank") }
        WHLSN.session.groups = { WHLSN.Group:New() }
        WHLSN.session.algorithmSnapshot = { timestamp = 123 }
        WHLSN.session.viewingHistory = true
        WHLSN.session.hostEnded = true
        WHLSN.session.isTest = true

        WHLSN:ClearSessionState()

        assert.is_nil(WHLSN.session.status)
        assert.is_nil(WHLSN.session.host)
        assert.same({}, WHLSN.session.players)
        assert.same({}, WHLSN.session.groups)
        assert.is_nil(WHLSN.session.algorithmSnapshot)
        assert.is_false(WHLSN.session.viewingHistory)
        assert.is_false(WHLSN.session.hostEnded)
        assert.is_nil(WHLSN.session.isTest)
    end)

    it("should initialize hostEnded to false on startup", function()
        assert.is_false(WHLSN.session.hostEnded)
    end)

    it("should clear commQueue to prevent stale messages from flushing after session ends", function()
        WHLSN.commQueue = { { prefix = "WHLSN", message = "stale", distribution = "GUILD" } }

        WHLSN:ClearSessionState()

        assert.same({}, WHLSN.commQueue)
    end)

    it("should clear removedPlayers", function()
        WHLSN.session.removedPlayers = { ["SomePlayer"] = true }

        WHLSN:ClearSessionState()

        assert.same({}, WHLSN.session.removedPlayers)
    end)
end)

describe("HidePlayer and UnhidePlayer", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = {
            WHLSN.Player:New("TestPlayer", "tank", {}, {}),
            WHLSN.Player:New("OtherPlayer", "healer", {}, {}),
            WHLSN.Player:New("ThirdPlayer", "ranged", {}, {}),
        }
        WHLSN.session.removedPlayers = {}
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.UpdateLobbyView = function() end
        WHLSN.Print = function() end
    end)

    it("should mark a player as removed without removing from list", function()
        WHLSN:HidePlayer("OtherPlayer")

        assert.equals(3, #WHLSN.session.players)
        assert.is_true(WHLSN.session.removedPlayers["OtherPlayer"])
    end)

    it("should not allow hiding the host", function()
        WHLSN:HidePlayer("TestPlayer")

        assert.is_nil(WHLSN.session.removedPlayers["TestPlayer"])
    end)

    it("should only work for the host", function()
        WHLSN.session.host = "SomeoneElse"
        WHLSN:HidePlayer("OtherPlayer")

        assert.is_nil(WHLSN.session.removedPlayers["OtherPlayer"])
    end)

    it("should only work in lobby status", function()
        WHLSN.session.status = "spinning"
        WHLSN:HidePlayer("OtherPlayer")

        assert.is_nil(WHLSN.session.removedPlayers["OtherPlayer"])
    end)

    it("should unhide a previously hidden player", function()
        WHLSN:HidePlayer("OtherPlayer")
        assert.is_true(WHLSN.session.removedPlayers["OtherPlayer"])

        WHLSN:UnhidePlayer("OtherPlayer")
        assert.is_nil(WHLSN.session.removedPlayers["OtherPlayer"])
    end)

    it("should handle realm-qualified names", function()
        WHLSN:HidePlayer("OtherPlayer-Illidan")

        assert.is_true(WHLSN.session.removedPlayers["OtherPlayer"])
    end)

    it("should be a no-op for a player not in the session", function()
        WHLSN:HidePlayer("NonexistentPlayer")

        assert.is_nil(WHLSN.session.removedPlayers["NonexistentPlayer"])
    end)

    it("should be idempotent when hiding an already-hidden player", function()
        WHLSN:HidePlayer("OtherPlayer")
        WHLSN:HidePlayer("OtherPlayer")

        assert.is_true(WHLSN.session.removedPlayers["OtherPlayer"])
        assert.equals(3, #WHLSN.session.players)
    end)
end)

describe("SpinGroups", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.removedPlayers = {}
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.UpdateUI = function() end
        WHLSN.TouchActivity = function() end
        WHLSN:ClearLastGroups()
    end)

    it("should capture algorithmSnapshot with players and groups", function()
        local Player = WHLSN.Player
        WHLSN.session.players = {
            Player:New("Tank1", "tank", {}, {"brez"}),
            Player:New("Healer1", "healer", {}, {}),
            Player:New("DPS1", "ranged", {}, {"lust"}),
            Player:New("DPS2", "melee", {}, {}),
            Player:New("DPS3", "ranged", {}, {}),
        }

        WHLSN:SpinGroups()

        local snap = WHLSN.session.algorithmSnapshot
        assert.is_not_nil(snap)
        assert.is_not_nil(snap.players)
        assert.equals(5, #snap.players)
        assert.is_not_nil(snap.groups)
        assert.is_true(#snap.groups > 0)
        assert.equals("TestPlayer", snap.host)
        assert.equals(5, snap.playerCount)
        assert.is_number(snap.timestamp)
    end)

    it("should capture lastGroups in snapshot", function()
        local Player = WHLSN.Player
        local Group = WHLSN.Group
        WHLSN:SetLastGroups({
            Group:New(
                Player:New("OldTank", "tank", {}, {}),
                Player:New("OldHealer", "healer", {}, {}),
                {Player:New("OldDPS1", "melee", {}, {})}
            ),
        })

        WHLSN.session.players = {
            Player:New("Tank1", "tank", {}, {}),
            Player:New("Healer1", "healer", {}, {}),
            Player:New("DPS1", "ranged", {}, {}),
            Player:New("DPS2", "melee", {}, {}),
            Player:New("DPS3", "ranged", {}, {}),
        }

        WHLSN:SpinGroups()

        local snap = WHLSN.session.algorithmSnapshot
        assert.is_not_nil(snap.lastGroups)
        assert.equals(1, #snap.lastGroups)
    end)

    it("should store snapshot data as serialized dicts (not live references)", function()
        local Player = WHLSN.Player
        WHLSN.session.players = {
            Player:New("Tank1", "tank", {}, {}),
            Player:New("Healer1", "healer", {}, {}),
            Player:New("DPS1", "ranged", {}, {}),
            Player:New("DPS2", "melee", {}, {}),
            Player:New("DPS3", "ranged", {}, {}),
        }

        WHLSN:SpinGroups()

        local snap = WHLSN.session.algorithmSnapshot
        assert.is_nil(getmetatable(snap.players[1]))
        assert.equals("Tank1", snap.players[1].name)
    end)

    it("should exclude removed players from group formation", function()
        local Player = WHLSN.Player
        WHLSN.session.players = {
            Player:New("Tank1", "tank", {}, {"brez"}),
            Player:New("Healer1", "healer", {}, {}),
            Player:New("DPS1", "ranged", {}, {"lust"}),
            Player:New("DPS2", "melee", {}, {}),
            Player:New("DPS3", "ranged", {}, {}),
            Player:New("HiddenDPS", "melee", {}, {}),
        }
        WHLSN.session.removedPlayers = { ["HiddenDPS"] = true }

        WHLSN:SpinGroups()

        -- HiddenDPS should not appear in any group
        for _, group in ipairs(WHLSN.session.groups) do
            for _, p in ipairs(group:GetPlayers()) do
                assert.is_not.equals("HiddenDPS", p.name)
            end
        end
    end)

    it("should use active (non-removed) count for minimum player check", function()
        local Player = WHLSN.Player
        WHLSN.session.players = {
            Player:New("Tank1", "tank", {}, {}),
            Player:New("Healer1", "healer", {}, {}),
            Player:New("DPS1", "ranged", {}, {}),
            Player:New("DPS2", "melee", {}, {}),
            Player:New("DPS3", "ranged", {}, {}),
            Player:New("Hidden1", "melee", {}, {}),
        }
        WHLSN.session.removedPlayers = {
            ["Hidden1"] = true,
            ["DPS3"] = true,
        }

        -- Only 4 active players — should not spin
        WHLSN.printed = {}
        WHLSN.Print = function(self, msg)
            self.printed[#self.printed + 1] = msg
        end

        WHLSN:SpinGroups()

        assert.is_nil(WHLSN.session.algorithmSnapshot)
        assert.is_true(#WHLSN.printed > 0)
    end)
end)

describe("ToggleMinimapIcon", function()
    local ldbicon_shown, ldbicon_hidden
    local printed_messages

    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.db.profile.minimap = { hide = false }

        ldbicon_shown = false
        ldbicon_hidden = false
        printed_messages = {}

        -- Override ldbIcon with tracking mock
        WHLSN.ldbIcon = {
            Show = function(_, name) ldbicon_shown = true end,
            Hide = function(_, name) ldbicon_hidden = true end,
        }

        WHLSN.Print = function(_, msg)
            printed_messages[#printed_messages + 1] = msg
        end
    end)

    it("should hide the icon when currently shown", function()
        WHLSN.db.profile.minimap.hide = false

        WHLSN:ToggleMinimapIcon()

        assert.is_true(WHLSN.db.profile.minimap.hide)
        assert.is_true(ldbicon_hidden)
        assert.is_false(ldbicon_shown)
    end)

    it("should show the icon when currently hidden", function()
        WHLSN.db.profile.minimap.hide = true

        WHLSN:ToggleMinimapIcon()

        assert.is_false(WHLSN.db.profile.minimap.hide)
        assert.is_true(ldbicon_shown)
        assert.is_false(ldbicon_hidden)
    end)

    it("should print restore hint when hiding", function()
        WHLSN.db.profile.minimap.hide = false

        WHLSN:ToggleMinimapIcon()

        assert.equals(1, #printed_messages)
        assert.truthy(printed_messages[1]:find("/wheelson minimap"))
    end)

    it("should print confirmation when showing", function()
        WHLSN.db.profile.minimap.hide = true

        WHLSN:ToggleMinimapIcon()

        assert.equals(1, #printed_messages)
        assert.truthy(printed_messages[1]:find("shown"))
    end)
end)

describe("Slash command routing", function()
    local toggled_main, toggled_minimap

    before_each(function()
        toggled_main = false
        toggled_minimap = false
        WHLSN.ToggleMainFrame = function() toggled_main = true end
        WHLSN.ToggleMinimapIcon = function() toggled_minimap = true end
    end)

    it("should open main frame with no args", function()
        SlashCmdList["WHEELSON"]("")
        assert.is_true(toggled_main)
        assert.is_false(toggled_minimap)
    end)

    it("should toggle minimap with 'minimap' arg", function()
        SlashCmdList["WHEELSON"]("minimap")
        assert.is_true(toggled_minimap)
        assert.is_false(toggled_main)
    end)

    it("should handle extra whitespace", function()
        SlashCmdList["WHEELSON"]("  minimap  ")
        assert.is_true(toggled_minimap)
    end)

    it("should fall back to main frame for unknown args", function()
        SlashCmdList["WHEELSON"]("unknown")
        assert.is_true(toggled_main)
        assert.is_false(toggled_minimap)
    end)
end)

describe("leftSessionHost", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel)
            self.sent_messages[#self.sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel }
        end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
        WHLSN.UpdateUI = function() end
        WHLSN.ShowMainFrame = function() end
        WHLSN.DetectLocalPlayer = function()
            return WHLSN.Player:New("TestPlayer", "tank", {}, {})
        end
    end)

    it("should suppress updates from the host you left", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "HostA"
        WHLSN:LeaveSession()

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostA",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostA")

        assert.is_nil(WHLSN.session.status)
    end)

    it("should allow updates from a different host after leaving", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "HostA"
        WHLSN:LeaveSession()

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostB",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostB")

        assert.equals("lobby", WHLSN.session.status)
        assert.equals("HostB", WHLSN.session.host)
    end)

    it("should clear leftSessionHost on CreateLobby", function()
        WHLSN.leftSessionHost = "HostA"
        WHLSN:CreateLobby()

        assert.is_nil(WHLSN.leftSessionHost)
    end)

    it("should clear leftSessionHost on RequestJoin", function()
        WHLSN.leftSessionHost = "HostA"
        WHLSN.session.host = "HostB"

        WHLSN:RequestJoin()

        assert.is_nil(WHLSN.leftSessionHost)
    end)

    it("should block RequestJoin when hostEnded is true", function()
        WHLSN.session.host = "HostA"
        WHLSN.session.hostEnded = true

        WHLSN:RequestJoin()

        assert.equals(0, #WHLSN.sent_messages)
    end)

    it("LeaveSession should use ClearSessionState and set leftSessionHost", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "HostA"
        WHLSN.session.hostEnded = true
        WHLSN.session.algorithmSnapshot = { timestamp = 123 }

        WHLSN:LeaveSession()

        assert.equals("HostA", WHLSN.leftSessionHost)
        assert.is_nil(WHLSN.session.status)
        assert.is_nil(WHLSN.session.host)
        assert.is_false(WHLSN.session.hostEnded)
        assert.is_nil(WHLSN.session.algorithmSnapshot)
    end)

    it("should clear leftSessionHost when accepting a new session", function()
        WHLSN.leftSessionHost = "HostA"

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostB",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostB")

        assert.is_nil(WHLSN.leftSessionHost)
    end)
end)

describe("Session start notification", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.printed = {}
        WHLSN.Print = function(self, msg) self.printed[#self.printed + 1] = msg end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
        WHLSN.UpdateUI = function() end
    end)

    it("should print notification when discovering a new lobby session", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "GuildLeader",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "GuildLeader")

        assert.is_true(#WHLSN.printed > 0)
        local found = false
        for _, msg in ipairs(WHLSN.printed) do
            if msg:find("GuildLeader") and msg:find("wheelson") then found = true end
        end
        assert.is_true(found)
    end)

    it("should not re-notify on subsequent lobby updates from same host", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "GuildLeader",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "GuildLeader")
        local firstCount = #WHLSN.printed

        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "GuildLeader")
        assert.equals(firstCount, #WHLSN.printed)
    end)

    it("should not notify if leftSessionHost matches sender", function()
        WHLSN.leftSessionHost = "GuildLeader"

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "GuildLeader",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "GuildLeader")

        assert.equals(0, #WHLSN.printed)
    end)

    it("should notify when hostEnded is true and new lobby arrives", function()
        WHLSN.session.status = "completed"
        WHLSN.session.hostEnded = true
        WHLSN.session.host = nil

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "NewHost",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "NewHost")

        local found = false
        for _, msg in ipairs(WHLSN.printed) do
            if msg:find("NewHost") then found = true end
        end
        assert.is_true(found)
    end)
end)

describe("HandleSessionEnd", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
        WHLSN.UpdateUI = function() end
    end)

    it("should preserve groups and status for non-hosts", function()
        WHLSN.session.status = "completed"
        WHLSN.session.host = "HostPlayer"
        WHLSN.session.groups = { WHLSN.Group:New(WHLSN.Player:New("T1", "tank"), nil, {}) }
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer", "tank") }

        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX,
            { type = "SESSION_END" }, "GUILD", "HostPlayer")

        assert.equals("completed", WHLSN.session.status)
        assert.equals(1, #WHLSN.session.groups)
        assert.equals(1, #WHLSN.session.players)
        assert.is_true(WHLSN.session.hostEnded)
        assert.is_nil(WHLSN.session.host)
    end)

    it("should still reject SESSION_END from non-host sender", function()
        WHLSN.session.status = "completed"
        WHLSN.session.host = "HostPlayer"

        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX,
            { type = "SESSION_END" }, "GUILD", "RandomPlayer")

        assert.equals("HostPlayer", WHLSN.session.host)
        assert.is_false(WHLSN.session.hostEnded)
    end)

    it("should ignore SESSION_END when not in a session", function()
        -- No active session (host is nil)
        WHLSN.session.status = nil
        WHLSN.session.host = nil

        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX,
            { type = "SESSION_END" }, "GUILD", "SomeHost")

        assert.is_false(WHLSN.session.hostEnded)
    end)

    it("should allow new session after hostEnded", function()
        WHLSN.session.status = "completed"
        WHLSN.session.host = nil
        WHLSN.session.hostEnded = true

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "NewHost",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "NewHost")

        assert.equals("lobby", WHLSN.session.status)
        assert.equals("NewHost", WHLSN.session.host)
        assert.is_false(WHLSN.session.hostEnded)
    end)
end)

describe("HandleSessionUpdate community broadcast", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.UpdateUI = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should populate connectedCommunity from data.community", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {},
            community = { ["Tyler"] = "Tyler-Kel'Thuzad" },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.same({ ["Tyler"] = "Tyler-Kel'Thuzad" }, WHLSN.session.connectedCommunity)
    end)

    it("should leave connectedCommunity unchanged when community field absent", function()
        WHLSN.session.connectedCommunity = { ["Existing"] = "Existing-Realm" }
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.same({ ["Existing"] = "Existing-Realm" }, WHLSN.session.connectedCommunity)
    end)
end)

describe("HandleSessionPing", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.UpdateUI = function() end
        WHLSN.ShowMainFrame = function() end
    end)

    it("should set commChannel to WHISPER", function()
        local data = { type = "SESSION_PING", host = "HostPlayer", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "HostPlayer-Illidan")
        assert.equals("WHISPER", WHLSN.session.commChannel)
    end)

    it("should store host from sender (realm-qualified)", function()
        local data = { type = "SESSION_PING", host = "HostPlayer", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "HostPlayer-Illidan")
        assert.equals("HostPlayer-Illidan", WHLSN.session.host)
    end)

    it("should set session status and host from sender", function()
        local data = { type = "SESSION_PING", host = "HostPlayer", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "HostPlayer-Illidan")
        assert.equals("lobby", WHLSN.session.status)
        assert.equals("HostPlayer-Illidan", WHLSN.session.host)
    end)

    it("should not overwrite an active session from a different host", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "ExistingHost"

        local data = { type = "SESSION_PING", host = "OtherHost", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "OtherHost-Illidan")
        assert.equals("ExistingHost", WHLSN.session.host)
    end)

    it("should not overwrite an active GUILD session from same host", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "SameHost"

        local data = { type = "SESSION_PING", host = "SameHost", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "SameHost-Illidan")
        -- Should not set commChannel to WHISPER since session is already active via GUILD
        assert.is_nil(WHLSN.session.commChannel)
    end)
end)

describe("HandleJoinRequest community", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer", "tank", {}, {}) }
        WHLSN.BroadcastSessionUpdate = function() end
    end)

    it("should accept join from realm-qualified sender", function()
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "OtherPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "OtherPlayer-Illidan", "GUILD")
        assert.equals(2, #WHLSN.session.players)
    end)

    it("should reject whisper join from non-community-roster player", function()
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "Stranger", mainRole = "tank", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "Stranger-Stormrage", "WHISPER")
        assert.equals(1, #WHLSN.session.players)
    end)

    it("should accept whisper join from community roster member", function()
        WHLSN:AddCommunityPlayer("CommunityGuy-Stormrage")
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "CommunityGuy-Stormrage", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "CommunityGuy-Stormrage", "WHISPER")
        assert.equals(2, #WHLSN.session.players)
    end)

    it("should track community player in connectedCommunity", function()
        WHLSN:AddCommunityPlayer("CommunityGuy-Stormrage")
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "CommunityGuy-Stormrage", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "CommunityGuy-Stormrage", "WHISPER")
        assert.equals("CommunityGuy-Stormrage", WHLSN.session.connectedCommunity["CommunityGuy-Stormrage"])
    end)
end)

describe("SendSessionUpdate with community", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer", "tank", {}, {}) }
        WHLSN.session.connectedCommunity = { ["CommunityGuy"] = "CommunityGuy-Stormrage" }
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            self.sent_messages[#self.sent_messages + 1] = { channel = channel, target = target }
        end
        WHLSN.Serialize = function(self, data) return data end
    end)

    it("should send to GUILD and WHISPER community players", function()
        WHLSN:SendSessionUpdate()
        assert.equals(2, #WHLSN.sent_messages)
        assert.equals("GUILD", WHLSN.sent_messages[1].channel)
        assert.equals("WHISPER", WHLSN.sent_messages[2].channel)
        assert.equals("CommunityGuy-Stormrage", WHLSN.sent_messages[2].target)
    end)

    it("should include community map in SESSION_UPDATE payload", function()
        local sentData
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            if channel == "GUILD" then sentData = msg end
        end
        WHLSN.Serialize = function(self, data) return data end

        WHLSN:SendSessionUpdate()

        assert.is_not_nil(sentData)
        assert.is_not_nil(sentData.community)
        assert.same({ ["CommunityGuy"] = "CommunityGuy-Stormrage" }, sentData.community)
    end)
end)

describe("ClearSessionState community fields", function()
    before_each(function()
        WHLSN:OnInitialize()
    end)

    it("should clear community session fields", function()
        WHLSN.session.connectedCommunity = { ["Tyler-Stormrage"] = "Tyler-Stormrage" }
        WHLSN.session.commChannel = "WHISPER"

        WHLSN:ClearSessionState()

        assert.same({}, WHLSN.session.connectedCommunity)
        assert.is_nil(WHLSN.session.commChannel)
    end)

    it("should cancel commThrottleTimer and clear commPendingUpdate", function()
        local cancelled = false
        WHLSN.commThrottleTimer = { Cancel = function() cancelled = true end }
        WHLSN.commPendingUpdate = true

        WHLSN:ClearSessionState()

        assert.is_true(cancelled)
        assert.is_nil(WHLSN.commThrottleTimer)
        assert.is_false(WHLSN.commPendingUpdate)
    end)
end)

describe("CommRestriction", function()
    local sent_messages
    local original_C_InstanceEncounter
    local original_C_MythicPlus
    local original_C_PvP

    before_each(function()
        WHLSN:OnInitialize()
        sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            sent_messages[#sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
        end
        original_C_InstanceEncounter = _G.C_InstanceEncounter
        original_C_MythicPlus = _G.C_MythicPlus
        original_C_PvP = _G.C_PvP
    end)

    after_each(function()
        _G.C_InstanceEncounter = original_C_InstanceEncounter
        _G.C_MythicPlus = original_C_MythicPlus
        _G.C_PvP = original_C_PvP
    end)

    it("should send immediately when not restricted", function()
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(1, #sent_messages)
        assert.equals("GUILD", sent_messages[1].channel)
    end)

    it("should queue message when C_InstanceEncounter reports active encounter", function()
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return true end }

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
        assert.equals("GUILD", WHLSN.commQueue[1].distribution)
    end)

    it("should queue message when C_MythicPlus run is active", function()
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
        _G.C_MythicPlus = { IsRunActive = function() return true end }

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
    end)

    it("should queue message when PvP match is active", function()
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
        _G.C_PvP = { IsActiveBattlefield = function() return true end }

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
    end)

    it("should flush queued messages on FlushCommQueue when no longer restricted", function()
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return true end }
        WHLSN:SafeSendCommMessage("WHLSN", "msg1", "GUILD")
        WHLSN:SafeSendCommMessage("WHLSN", "msg2", "WHISPER", "Player-Realm")
        assert.equals(2, #WHLSN.commQueue)

        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
        WHLSN:FlushCommQueue()

        assert.equals(2, #sent_messages)
        assert.equals("GUILD", sent_messages[1].channel)
        assert.equals("WHISPER", sent_messages[2].channel)
        assert.equals("Player-Realm", sent_messages[2].target)
        assert.equals(0, #WHLSN.commQueue)
    end)

    it("should not flush if still restricted", function()
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return true end }
        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        WHLSN:FlushCommQueue()

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
    end)

    it("IsCommRestricted should return false when no restriction APIs are present", function()
        _G.C_InstanceEncounter = nil
        _G.C_MythicPlus = nil
        _G.C_PvP = nil

        assert.is_false(WHLSN:IsCommRestricted())
    end)

    it("ENCOUNTER_END handler flushes the queue once restriction lifts", function()
        -- Queue a message during an encounter
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return true end }
        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")
        assert.equals(1, #WHLSN.commQueue)

        -- Simulate encounter ending; make C_Timer.After invoke synchronously
        _G.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
        local original_after = _G.C_Timer.After
        _G.C_Timer.After = function(_, cb) cb() end

        WHLSN:ENCOUNTER_END()

        _G.C_Timer.After = original_after

        assert.equals(1, #sent_messages)
        assert.equals(0, #WHLSN.commQueue)
    end)
end)

describe("InviteMyGroup", function()
    local invited, printed

    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.isTest = false
        WHLSN.session.connectedCommunity = {}
        invited = {}
        printed = {}
        _G.C_PartyInfo.InviteUnit = function(name) invited[#invited + 1] = name end
        WHLSN.Print = function(_, msg) printed[#printed + 1] = msg end
        _G.UnitName = function() return "TestPlayer" end
    end)

    it("should invite the other 4 members of the local player's group", function()
        WHLSN.session.groups = {
            WHLSN.Group:New(
                WHLSN.Player:New("TestPlayer", "tank"),
                WHLSN.Player:New("Healer1", "healer"),
                {
                    WHLSN.Player:New("DPS1", "ranged"),
                    WHLSN.Player:New("DPS2", "melee"),
                    WHLSN.Player:New("DPS3", "ranged"),
                }
            ),
        }
        WHLSN:InviteMyGroup()
        assert.equals(4, #invited)
    end)

    it("should find local player when name has realm suffix (StripRealmName fix)", function()
        WHLSN.session.groups = {
            WHLSN.Group:New(
                WHLSN.Player:New("TestPlayer-Illidan", "tank"),
                WHLSN.Player:New("Healer1", "healer"),
                {
                    WHLSN.Player:New("DPS1", "ranged"),
                    WHLSN.Player:New("DPS2", "melee"),
                    WHLSN.Player:New("DPS3", "ranged"),
                }
            ),
        }
        WHLSN:InviteMyGroup()
        -- StripRealmName("TestPlayer-Illidan") == "TestPlayer" so group is found
        assert.equals(4, #invited)
    end)

    it("should print error when local player not in any group", function()
        WHLSN.session.groups = {
            WHLSN.Group:New(
                WHLSN.Player:New("Tank1", "tank"),
                WHLSN.Player:New("Healer1", "healer"),
                {
                    WHLSN.Player:New("DPS1", "ranged"),
                    WHLSN.Player:New("DPS2", "melee"),
                    WHLSN.Player:New("DPS3", "ranged"),
                }
            ),
        }
        WHLSN:InviteMyGroup()
        assert.equals(1, #printed)
        assert.truthy(printed[1]:find("Could not find"))
    end)
end)

describe("HandleSpecUpdate", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = {
            WHLSN.Player:New("TestPlayer", "tank", {}, {}),
            WHLSN.Player:New("OtherPlayer", "healer", { "ranged" }, { "brez" }),
        }
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should update existing player's spec data", function()
        local data = {
            type = "SPEC_UPDATE",
            player = { name = "OtherPlayer", mainRole = "tank", offspecs = { "healer" }, utilities = { "brez" } },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "OtherPlayer")

        local updated = WHLSN.session.players[2]
        assert.equals("tank", updated.mainRole)
        assert.same({ "healer" }, updated.offspecs)
    end)

    it("should reject SPEC_UPDATE when sender does not match player name", function()
        local data = {
            type = "SPEC_UPDATE",
            player = { name = "OtherPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "Impersonator")

        local unchanged = WHLSN.session.players[2]
        assert.equals("healer", unchanged.mainRole)
    end)

    it("should ignore SPEC_UPDATE for player not in session", function()
        local data = {
            type = "SPEC_UPDATE",
            player = { name = "Stranger", mainRole = "tank", offspecs = {}, utilities = {} },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "Stranger")

        assert.equals(2, #WHLSN.session.players)
    end)

    it("should only process on host", function()
        WHLSN.session.host = "SomeoneElse"

        local data = {
            type = "SPEC_UPDATE",
            player = { name = "OtherPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "OtherPlayer")

        local unchanged = WHLSN.session.players[2]
        assert.equals("healer", unchanged.mainRole)
    end)

    it("should handle realm-qualified sender", function()
        local data = {
            type = "SPEC_UPDATE",
            player = { name = "OtherPlayer", mainRole = "ranged", offspecs = {}, utilities = { "brez" } },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "OtherPlayer-Illidan")

        local updated = WHLSN.session.players[2]
        assert.equals("ranged", updated.mainRole)
    end)
end)

describe("SessionQuery", function()
    local origSendSessionUpdate

    before_each(function()
        WHLSN:OnInitialize()
        origSendSessionUpdate = WHLSN.SendSessionUpdate
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.UpdateUI = function() end
        WHLSN.UpdateLobbyView = function() end
        WHLSN.Serialize = function(self, data) return data end
    end)

    after_each(function()
        WHLSN.SendSessionUpdate = origSendSessionUpdate
    end)

    it("HandleSessionQuery should call SendSessionUpdate with fullSync when host", function()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer-Illidan"
        local calledWith = nil
        WHLSN.SendSessionUpdate = function(_, fullSync) calledWith = fullSync end
        WHLSN:HandleSessionQuery("OtherPlayer-Illidan")
        assert.is_true(calledWith)
    end)

    it("HandleSessionQuery should ignore when not host", function()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "SomeoneElse-Illidan"
        local called = false
        WHLSN.SendSessionUpdate = function() called = true end
        WHLSN:HandleSessionQuery("OtherPlayer-Illidan")
        assert.is_false(called)
    end)

    it("HandleSessionQuery should ignore when no session", function()
        WHLSN.session.status = nil
        WHLSN.session.host = nil
        local called = false
        WHLSN.SendSessionUpdate = function() called = true end
        WHLSN:HandleSessionQuery("OtherPlayer-Illidan")
        assert.is_false(called)
    end)

    it("SendSessionQuery should be throttled", function()
        local sent = 0
        WHLSN.SendCommMessage = function() sent = sent + 1 end
        WHLSN:SendSessionQuery()
        WHLSN:SendSessionQuery()
        assert.equal(1, sent)
    end)

    it("OnCommReceived should route SESSION_QUERY to HandleSessionQuery", function()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer-Illidan"
        local called = false
        WHLSN.SendSessionUpdate = function() called = true end
        WHLSN.Deserialize = function(self, msg) return true, msg end
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, { type = "SESSION_QUERY" }, "GUILD", "OtherPlayer")
        assert.is_true(called)
    end)
end)

describe("SendSessionUpdate removedPlayers", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer", "tank", {}, {}) }
        WHLSN.session.removedPlayers = { ["HiddenGuy"] = true }
        WHLSN.session.connectedCommunity = {}
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            self.sent_messages[#self.sent_messages + 1] = { channel = channel, data = msg }
        end
        WHLSN.Serialize = function(self, data) return data end
    end)

    it("should include removedPlayers in SESSION_UPDATE payload", function()
        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_not_nil(sentData.removedPlayers)
        assert.same({ ["HiddenGuy"] = true }, sentData.removedPlayers)
    end)
end)

describe("HandleSessionUpdate removedPlayers", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.UpdateUI = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should populate removedPlayers from data", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {},
            removedPlayers = { ["SomeGuy"] = true },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.same({ ["SomeGuy"] = true }, WHLSN.session.removedPlayers)
    end)

    it("should leave removedPlayers unchanged when field is absent", function()
        WHLSN.session.removedPlayers = { ["Existing"] = true }
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {},
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.same({ ["Existing"] = true }, WHLSN.session.removedPlayers)
    end)
end)

describe("Realm-qualified identity", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.UpdateUI = function() end
        WHLSN.ShowMainFrame = function() end
        WHLSN.UpdateLobbyView = function() end
        WHLSN.SendCommunityPings = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.analytics = setmetatable({}, { __index = function() return function() end end })
    end)

    it("CreateLobby should set host as realm-qualified name", function()
        WHLSN:CreateLobby()
        assert.equal("TestPlayer-Illidan", WHLSN.session.host)
    end)

    it("LeaveSession should compare host using NamesMatch", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "TestPlayer-Illidan"
        WHLSN:LeaveSession()
        assert.equal("lobby", WHLSN.session.status)
    end)

    it("HandleJoinRequest should accept with realm-qualified host", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "TestPlayer-Illidan"
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer-Illidan", "tank", {}, {}) }
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "Other", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "Other-Illidan", "GUILD")
        assert.equals(2, #WHLSN.session.players)
    end)

    it("HandleSessionEnd should match realm-qualified host", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "HostPlayer-Illidan"
        WHLSN:HandleSessionEnd("HostPlayer-Illidan")
        assert.is_true(WHLSN.session.hostEnded)
    end)

    it("HidePlayer should key removedPlayers by full name", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "TestPlayer-Illidan"
        local player = WHLSN.Player:New("Other-Illidan", "healer", {}, {})
        WHLSN.session.players = {
            WHLSN.Player:New("TestPlayer-Illidan", "tank", {}, {}),
            player,
        }
        WHLSN:HidePlayer("Other-Illidan")
        assert.is_true(WHLSN.session.removedPlayers["Other-Illidan"] or false)
        assert.is_nil(WHLSN.session.removedPlayers["Other"])
    end)
end)

describe("JoinAck", function()
    local sent_messages

    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer-Illidan"
        WHLSN.session.players = { WHLSN.Player:New("TestPlayer-Illidan", "tank", {}, {}) }
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.UpdateLobbyView = function() end
        sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            sent_messages[#sent_messages + 1] = { msg = msg, channel = channel, target = target }
        end
        WHLSN.Serialize = function(self, data) return data end
    end)

    it("HandleJoinRequest should send JOIN_ACK to GUILD joiner", function()
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "Joiner", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "Joiner-Illidan", "GUILD")

        local ack = nil
        for _, msg in ipairs(sent_messages) do
            if type(msg.msg) == "table" and msg.msg.type == "JOIN_ACK" then
                ack = msg
                break
            end
        end
        assert.is_not_nil(ack)
        assert.equal("GUILD", ack.channel)
        assert.equal("Joiner-Illidan", ack.msg.playerName)
    end)

    it("HandleJoinRequest should send JOIN_ACK via WHISPER for community joiner", function()
        WHLSN:AddCommunityPlayer("CommunityGuy-Stormrage")
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "CommunityGuy-Stormrage", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "CommunityGuy-Stormrage", "WHISPER")

        local ack = nil
        for _, msg in ipairs(sent_messages) do
            if type(msg.msg) == "table" and msg.msg.type == "JOIN_ACK" then
                ack = msg
                break
            end
        end
        assert.is_not_nil(ack)
        assert.equal("WHISPER", ack.channel)
        assert.equal("CommunityGuy-Stormrage", ack.target)
    end)

    it("HandleJoinAck should clear joinPending when name matches", function()
        WHLSN.session.joinPending = true
        WHLSN.joinAckTimer = { Cancel = function() end }
        WHLSN:HandleJoinAck({ playerName = "TestPlayer-Illidan" }, "HostPlayer-Illidan")
        assert.is_false(WHLSN.session.joinPending)
        assert.is_nil(WHLSN.joinAckTimer)
    end)

    it("HandleJoinAck should ignore when name does not match", function()
        WHLSN.session.joinPending = true
        WHLSN.joinAckTimer = { Cancel = function() end }
        WHLSN:HandleJoinAck({ playerName = "OtherPlayer-Illidan" }, "HostPlayer-Illidan")
        assert.is_true(WHLSN.session.joinPending)
    end)

    it("HandleJoinAck should ignore when not pending", function()
        WHLSN.session.joinPending = false
        WHLSN:HandleJoinAck({ playerName = "TestPlayer-Illidan" }, "HostPlayer-Illidan")
        assert.is_false(WHLSN.session.joinPending)
    end)

    it("OnCommReceived should route JOIN_ACK to HandleJoinAck", function()
        WHLSN.session.joinPending = true
        WHLSN.joinAckTimer = { Cancel = function() end }
        WHLSN.Deserialize = function(self, msg) return true, msg end
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, {
            type = "JOIN_ACK", playerName = "TestPlayer-Illidan",
        }, "GUILD", "HostPlayer")
        assert.is_false(WHLSN.session.joinPending)
    end)
end)

describe("SessionPersistence", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.UpdateUI = function() end
        WHLSN.ShowMainFrame = function() end
        WHLSN.UpdateLobbyView = function() end
        WHLSN.SendCommunityPings = function() end
        WHLSN.SendSessionQuery = function() end
        WHLSN.SendSessionUpdate = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.analytics = setmetatable({}, { __index = function() return function() end end })
        if not WHLSN.db.char then
            WHLSN.db.char = {}
        end
        -- Clear any leftover persisted session from previous test
        WHLSN.db.char.activeSession = nil
        WHLSN.session.status = nil
    end)

    it("PersistSessionState should save host session state", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "TestPlayer-Illidan"
        WHLSN.session.players = {
            WHLSN.Player:New("TestPlayer-Illidan", "tank", {}, {}),
            WHLSN.Player:New("Other-Illidan", "healer", {}, {}),
        }
        WHLSN.session.removedPlayers = {}
        WHLSN.session.connectedCommunity = {}

        WHLSN:PersistSessionState()

        local saved = WHLSN.db.char.activeSession
        assert.is_not_nil(saved)
        assert.equal("lobby", saved.status)
        assert.equal("TestPlayer-Illidan", saved.host)
        assert.is_true(saved.isHost)
        assert.is_not_nil(saved.players)
        assert.equal(2, #saved.players)
    end)

    it("PersistSessionState should save non-host session state without players", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "OtherHost-Illidan"
        WHLSN.session.players = { WHLSN.Player:New("OtherHost-Illidan", "tank", {}, {}) }

        WHLSN:PersistSessionState()

        local saved = WHLSN.db.char.activeSession
        assert.is_not_nil(saved)
        assert.equal("OtherHost-Illidan", saved.host)
        assert.is_false(saved.isHost)
        assert.is_nil(saved.players)
    end)

    it("ClearSessionState should clear persisted state", function()
        WHLSN.db.char.activeSession = { host = "X", status = "lobby" }
        WHLSN:ClearSessionState()
        assert.is_nil(WHLSN.db.char.activeSession)
    end)

    it("RestoreSessionState should restore host state with players", function()
        WHLSN.db.char.activeSession = {
            host = "TestPlayer-Illidan",
            status = "lobby",
            commChannel = nil,
            timestamp = time(),
            isHost = true,
            players = {
                { name = "TestPlayer-Illidan", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "Other-Illidan", mainRole = "healer", offspecs = {}, utilities = {} },
            },
            removedPlayers = {},
            connectedCommunity = {},
        }

        local broadcastCalled = false
        WHLSN.SendSessionUpdate = function() broadcastCalled = true end

        WHLSN:RestoreSessionState()

        assert.equal("lobby", WHLSN.session.status)
        assert.equal("TestPlayer-Illidan", WHLSN.session.host)
        assert.equal(2, #WHLSN.session.players)
        assert.is_true(broadcastCalled)
    end)

    it("RestoreSessionState should send SESSION_QUERY for non-host", function()
        WHLSN.db.char.activeSession = {
            host = "OtherHost-Illidan",
            status = "lobby",
            commChannel = nil,
            timestamp = time(),
            isHost = false,
        }

        local queryCalled = false
        WHLSN.SendSessionQuery = function() queryCalled = true end

        WHLSN:RestoreSessionState()

        assert.equal("lobby", WHLSN.session.status)
        assert.equal("OtherHost-Illidan", WHLSN.session.host)
        assert.is_true(queryCalled)
    end)

    it("RestoreSessionState should discard stale sessions", function()
        WHLSN.db.char.activeSession = {
            host = "OtherHost-Illidan",
            status = "lobby",
            timestamp = time() - WHLSN.SESSION_TIMEOUT - 1,
            isHost = false,
        }

        WHLSN:RestoreSessionState()

        assert.is_nil(WHLSN.session.status)
        assert.is_nil(WHLSN.db.char.activeSession)
    end)

    it("PersistSessionState should clear when no status", function()
        WHLSN.db.char.activeSession = { host = "X", status = "lobby" }
        WHLSN.session.status = nil
        WHLSN:PersistSessionState()
        assert.is_nil(WHLSN.db.char.activeSession)
    end)
end)

describe("ReconstructGroups", function()
    before_each(function()
        WHLSN:OnInitialize()
    end)

    it("should rebuild full Group objects from compact format", function()
        local players = {
            WHLSN.Player:New("Tank1", "tank", {}, { "brez" }, "WARRIOR"),
            WHLSN.Player:New("Healer1", "healer", { "ranged" }, { "lust" }, "SHAMAN"),
            WHLSN.Player:New("DPS1", "ranged", {}, {}, "MAGE"),
            WHLSN.Player:New("DPS2", "melee", {}, {}, "ROGUE"),
            WHLSN.Player:New("DPS3", "ranged", {}, { "brez" }, "DRUID"),
        }

        local compactGroups = {
            {
                tank = "Tank1",
                healer = "Healer1",
                dps = { "DPS1", "DPS2", "DPS3" },
            },
        }

        local groups = WHLSN:ReconstructGroups(compactGroups, players)

        assert.equals(1, #groups)
        local g = groups[1]
        assert.is_not_nil(g.tank)
        assert.equals("Tank1", g.tank.name)
        assert.equals("tank", g.tank.mainRole)
        assert.equals("WARRIOR", g.tank.classToken)
        assert.is_not_nil(g.healer)
        assert.equals("Healer1", g.healer.name)
        assert.equals("healer", g.healer.mainRole)
        assert.equals(3, #g.dps)
        assert.equals("DPS1", g.dps[1].name)
        assert.equals("ranged", g.dps[1].mainRole)
        assert.equals("MAGE", g.dps[1].classToken)
    end)

    it("should handle missing players gracefully by creating placeholders", function()
        local players = {
            WHLSN.Player:New("Tank1", "tank", {}, {}, "WARRIOR"),
            WHLSN.Player:New("Healer1", "healer", {}, {}, "PRIEST"),
        }

        local compactGroups = {
            {
                tank = "Tank1",
                healer = "Healer1",
                dps = { "UnknownDPS1", "UnknownDPS2", "UnknownDPS3" },
            },
        }

        local groups = WHLSN:ReconstructGroups(compactGroups, players)

        assert.equals(1, #groups)
        local g = groups[1]
        assert.equals("Tank1", g.tank.name)
        assert.equals("tank", g.tank.mainRole)
        assert.equals(3, #g.dps)
        -- Placeholder players should have the name but no role/class data
        assert.equals("UnknownDPS1", g.dps[1].name)
        assert.is_nil(g.dps[1].mainRole)
        assert.is_nil(g.dps[1].classToken)
    end)

    it("should handle cross-realm name lookup via short name", function()
        local players = {
            WHLSN.Player:New("Tank1-Illidan", "tank", {}, {}, "WARRIOR"),
            WHLSN.Player:New("Healer1-Illidan", "healer", {}, {}, "PRIEST"),
        }

        local compactGroups = {
            {
                tank = "Tank1",
                healer = "Healer1",
                dps = {},
            },
        }

        local groups = WHLSN:ReconstructGroups(compactGroups, players)

        assert.equals(1, #groups)
        assert.equals("Tank1-Illidan", groups[1].tank.name)
        assert.equals("tank", groups[1].tank.mainRole)
    end)

    it("should handle nil tank and healer in compact format", function()
        local players = {
            WHLSN.Player:New("DPS1", "ranged", {}, {}, "MAGE"),
        }

        local compactGroups = {
            {
                tank = nil,
                healer = nil,
                dps = { "DPS1" },
            },
        }

        local groups = WHLSN:ReconstructGroups(compactGroups, players)

        assert.equals(1, #groups)
        assert.is_nil(groups[1].tank)
        assert.is_nil(groups[1].healer)
        assert.equals(1, #groups[1].dps)
        assert.equals("DPS1", groups[1].dps[1].name)
    end)

    it("should handle multiple groups", function()
        local players = {
            WHLSN.Player:New("Tank1", "tank", {}, {}, "WARRIOR"),
            WHLSN.Player:New("Tank2", "tank", {}, {}, "PALADIN"),
            WHLSN.Player:New("Healer1", "healer", {}, {}, "PRIEST"),
            WHLSN.Player:New("Healer2", "healer", {}, {}, "SHAMAN"),
            WHLSN.Player:New("DPS1", "ranged", {}, {}, "MAGE"),
            WHLSN.Player:New("DPS2", "melee", {}, {}, "ROGUE"),
        }

        local compactGroups = {
            { tank = "Tank1", healer = "Healer1", dps = { "DPS1" } },
            { tank = "Tank2", healer = "Healer2", dps = { "DPS2" } },
        }

        local groups = WHLSN:ReconstructGroups(compactGroups, players)

        assert.equals(2, #groups)
        assert.equals("Tank1", groups[1].tank.name)
        assert.equals("Tank2", groups[2].tank.name)
        assert.equals("DPS1", groups[1].dps[1].name)
        assert.equals("DPS2", groups[2].dps[1].name)
    end)
end)

describe("SendSessionUpdate compactGroups", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.SendSessionUpdate = originalSendSessionUpdate
        WHLSN.session.status = WHLSN.Status.SPINNING
        WHLSN.session.host = "TestPlayer"
        WHLSN.session.players = {
            WHLSN.Player:New("Tank1", "tank", {}, {}, "WARRIOR"),
            WHLSN.Player:New("Healer1", "healer", {}, {}, "PRIEST"),
            WHLSN.Player:New("DPS1", "ranged", {}, {}, "MAGE"),
            WHLSN.Player:New("DPS2", "melee", {}, {}, "ROGUE"),
            WHLSN.Player:New("DPS3", "ranged", {}, {}, "WARLOCK"),
        }
        WHLSN.session.groups = {
            WHLSN.Group:New(
                WHLSN.Player:New("Tank1", "tank", {}, {}, "WARRIOR"),
                WHLSN.Player:New("Healer1", "healer", {}, {}, "PRIEST"),
                {
                    WHLSN.Player:New("DPS1", "ranged", {}, {}, "MAGE"),
                    WHLSN.Player:New("DPS2", "melee", {}, {}, "ROGUE"),
                    WHLSN.Player:New("DPS3", "ranged", {}, {}, "WARLOCK"),
                }
            ),
        }
        WHLSN.session.connectedCommunity = {}
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            self.sent_messages[#self.sent_messages + 1] = { channel = channel, data = msg }
        end
        WHLSN.Serialize = function(self, data) return data end
    end)

    it("should use compactGroups instead of groups for SPINNING status", function()
        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_not_nil(sentData.compactGroups)
        assert.is_nil(sentData.groups)
        assert.equals(1, #sentData.compactGroups)
        assert.equals("Tank1", sentData.compactGroups[1].tank)
        assert.equals("Healer1", sentData.compactGroups[1].healer)
        assert.same({ "DPS1", "DPS2", "DPS3" }, sentData.compactGroups[1].dps)
    end)

    it("should use compactGroups for COMPLETED status", function()
        WHLSN.session.status = WHLSN.Status.COMPLETED

        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_not_nil(sentData.compactGroups)
        assert.is_nil(sentData.groups)
    end)

    it("should not include compactGroups for LOBBY status", function()
        WHLSN.session.status = WHLSN.Status.LOBBY

        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_nil(sentData.compactGroups)
        assert.is_nil(sentData.groups)
    end)

    it("should omit players, community, and removedPlayers for SPINNING", function()
        WHLSN.session.connectedCommunity = { ["Comm1"] = "Comm1" }
        WHLSN.session.removedPlayers = { ["Removed1"] = true }

        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_nil(sentData.players)
        assert.is_nil(sentData.community)
        assert.is_nil(sentData.removedPlayers)
        -- But status and host are still present
        assert.equals("spinning", sentData.status)
        assert.is_not_nil(sentData.host)
    end)

    it("should omit players for COMPLETED", function()
        WHLSN.session.status = WHLSN.Status.COMPLETED

        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_nil(sentData.players)
    end)

    it("should include players for LOBBY", function()
        WHLSN.session.status = WHLSN.Status.LOBBY

        WHLSN:SendSessionUpdate()

        local sentData = WHLSN.sent_messages[1].data
        assert.is_not_nil(sentData.players)
        assert.equals(5, #sentData.players)
    end)

    it("should never include playerCount", function()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN:SendSessionUpdate()
        assert.is_nil(WHLSN.sent_messages[1].data.playerCount)

        WHLSN.sent_messages = {}
        WHLSN.session.status = WHLSN.Status.SPINNING
        WHLSN:SendSessionUpdate()
        assert.is_nil(WHLSN.sent_messages[1].data.playerCount)
    end)

    it("should include all fields when fullSync is true even for SPINNING", function()
        WHLSN.session.connectedCommunity = { ["Comm1"] = "Comm1" }
        WHLSN.session.removedPlayers = { ["Hidden1"] = true }

        WHLSN:SendSessionUpdate(true)

        local sentData = WHLSN.sent_messages[1].data
        assert.is_not_nil(sentData.players)
        assert.equals(5, #sentData.players)
        assert.is_not_nil(sentData.community)
        assert.is_not_nil(sentData.removedPlayers)
        assert.is_not_nil(sentData.compactGroups)
    end)

    it("should include all fields when fullSync is true for COMPLETED", function()
        WHLSN.session.status = WHLSN.Status.COMPLETED

        WHLSN:SendSessionUpdate(true)

        local sentData = WHLSN.sent_messages[1].data
        assert.is_not_nil(sentData.players)
        assert.is_not_nil(sentData.compactGroups)
    end)
end)

describe("LeaveSession UI update", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel)
            self.sent_messages[#self.sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel }
        end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
        WHLSN.ShowMainFrame = function() end
        WHLSN.DetectLocalPlayer = function()
            return WHLSN.Player:New("TestPlayer", "tank", {}, {})
        end
    end)

    it("should call UpdateUI after leaving session", function()
        WHLSN.session.status = "lobby"
        WHLSN.session.host = "HostA"

        local uiUpdated = false
        WHLSN.UpdateUI = function() uiUpdated = true end

        WHLSN:LeaveSession()

        assert.is_true(uiUpdated)
    end)
end)

-- Save the real DetectLocalPlayer before any tests can monkey-patch it
local realDetectLocalPlayer = WHLSN.DetectLocalPlayer

describe("HandleSessionUpdate spec override preservation", function()
    before_each(function()
        if not mock_db.char then mock_db.char = {} end
        mock_db.char.activeSession = nil
        WHLSN:OnInitialize()
        -- Restore real DetectLocalPlayer (previous tests may have monkey-patched it)
        WHLSN.DetectLocalPlayer = realDetectLocalPlayer
        WHLSN.UpdateUI = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should re-apply local spec override when receiving stale host data", function()
        -- Simulate the non-host having saved a spec override to "healer"
        WHLSN.db.char.specOverrides = { mainRole = "healer", offspecs = {} }

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {
                { name = "TestPlayer-Illidan", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "HostPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
            },
        }
        WHLSN:HandleSessionUpdate(data, "HostPlayer")

        -- The local player's role should be "healer" (from override), not "tank" (from stale data)
        local localPlayer = nil
        for _, p in ipairs(WHLSN.session.players) do
            if WHLSN:NamesMatch(p.name, WHLSN:GetMyFullName()) then
                localPlayer = p
                break
            end
        end
        assert.is_not_nil(localPlayer)
        assert.equals("healer", localPlayer.mainRole)
    end)

    it("should not re-apply spec overrides for the host", function()
        -- When we ARE the host, host data is authoritative.
        -- Call HandleSessionUpdate directly because OnCommReceived filters out
        -- messages from self (sender == UnitName("player")).
        WHLSN.db.char.specOverrides = { mainRole = "healer", offspecs = {} }

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "TestPlayer-Illidan",
            players = {
                { name = "TestPlayer-Illidan", mainRole = "tank", offspecs = {}, utilities = {} },
            },
        }
        WHLSN:HandleSessionUpdate(data, "TestPlayer-Illidan")

        -- Should remain "tank" since we are the host
        local localPlayer = WHLSN.session.players[1]
        assert.equals("tank", localPlayer.mainRole)
    end)

    it("should not crash when no spec overrides are saved", function()
        WHLSN.db.char.specOverrides = nil

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {
                { name = "TestPlayer-Illidan", mainRole = "tank", offspecs = {}, utilities = {} },
            },
        }
        assert.has_no.errors(function()
            WHLSN:HandleSessionUpdate(data, "HostPlayer")
        end)

        assert.equals("tank", WHLSN.session.players[1].mainRole)
    end)
end)

describe("HandleSessionUpdate implicit joinPending ACK", function()
    before_each(function()
        if not mock_db.char then mock_db.char = {} end
        mock_db.char.activeSession = nil
        WHLSN:OnInitialize()
        WHLSN.UpdateUI = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should clear joinPending when local player is in host player list", function()
        WHLSN.session.joinPending = true
        local timerCancelled = false
        WHLSN.joinAckTimer = { Cancel = function() timerCancelled = true end }

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {
                { name = "HostPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "TestPlayer-Illidan", mainRole = "healer", offspecs = {}, utilities = {} },
            },
        }
        WHLSN:HandleSessionUpdate(data, "HostPlayer")

        assert.is_false(WHLSN.session.joinPending)
        assert.is_true(timerCancelled)
        assert.is_nil(WHLSN.joinAckTimer)
    end)

    it("should not clear joinPending when local player is not in player list", function()
        WHLSN.session.joinPending = true
        WHLSN.joinAckTimer = { Cancel = function() end }

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {
                { name = "HostPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "OtherPlayer", mainRole = "healer", offspecs = {}, utilities = {} },
            },
        }
        WHLSN:HandleSessionUpdate(data, "HostPlayer")

        assert.is_true(WHLSN.session.joinPending)
    end)
end)

describe("HandleSessionUpdate compactGroups", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.UpdateUI = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should reconstruct groups from compact format", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "spinning",
            host = "HostPlayer",
            players = {
                { name = "Tank1", mainRole = "tank", offspecs = {}, utilities = { "brez" }, classToken = "WARRIOR" },
                { name = "Healer1", mainRole = "healer", offspecs = {}, utilities = {}, classToken = "PRIEST" },
                { name = "DPS1", mainRole = "ranged", offspecs = {}, utilities = {}, classToken = "MAGE" },
                { name = "DPS2", mainRole = "melee", offspecs = {}, utilities = {}, classToken = "ROGUE" },
                { name = "DPS3", mainRole = "ranged", offspecs = {}, utilities = {}, classToken = "WARLOCK" },
            },
            compactGroups = {
                { tank = "Tank1", healer = "Healer1", dps = { "DPS1", "DPS2", "DPS3" } },
            },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.equals(1, #WHLSN.session.groups)
        local g = WHLSN.session.groups[1]
        assert.equals("Tank1", g.tank.name)
        assert.equals("tank", g.tank.mainRole)
        assert.equals("WARRIOR", g.tank.classToken)
        assert.equals("Healer1", g.healer.name)
        assert.equals(3, #g.dps)
        assert.equals("DPS1", g.dps[1].name)
        assert.equals("ranged", g.dps[1].mainRole)
    end)

    it("should still handle legacy groups format", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "spinning",
            host = "HostPlayer",
            players = {
                { name = "Tank1", mainRole = "tank", offspecs = {}, utilities = {} },
            },
            groups = {
                {
                    tank = { name = "Tank1", mainRole = "tank", offspecs = {}, utilities = {} },
                    healer = nil,
                    dps = {},
                },
            },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.equals(1, #WHLSN.session.groups)
        assert.equals("Tank1", WHLSN.session.groups[1].tank.name)
    end)

    it("should prefer compactGroups over legacy groups when both present", function()
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "spinning",
            host = "HostPlayer",
            players = {
                { name = "Tank1", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "Healer1", mainRole = "healer", offspecs = {}, utilities = {} },
            },
            compactGroups = {
                { tank = "Tank1", healer = "Healer1", dps = {} },
            },
            groups = {
                {
                    tank = { name = "WrongTank", mainRole = "tank", offspecs = {}, utilities = {} },
                    healer = nil,
                    dps = {},
                },
            },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.equals("Tank1", WHLSN.session.groups[1].tank.name)
    end)

    it("should use existing player list when SPINNING update omits players", function()
        -- Simulate having received the player list during LOBBY phase
        WHLSN.session.host = "HostPlayer"
        WHLSN.session.status = "lobby"
        WHLSN.session.players = {
            WHLSN.Player:New("Tank1", "tank", {}, { "brez" }, "WARRIOR"),
            WHLSN.Player:New("Healer1", "healer", {}, {}, "PRIEST"),
            WHLSN.Player:New("DPS1", "ranged", {}, {}, "MAGE"),
        }

        -- SPINNING update arrives without players (normal compact update)
        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "spinning",
            host = "HostPlayer",
            compactGroups = {
                { tank = "Tank1", healer = "Healer1", dps = { "DPS1" } },
            },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        -- Player list should be preserved from LOBBY phase
        assert.equals(3, #WHLSN.session.players)
        assert.equals("Tank1", WHLSN.session.players[1].name)
        -- Groups should be reconstructed with full player data
        assert.equals(1, #WHLSN.session.groups)
        assert.equals("tank", WHLSN.session.groups[1].tank.mainRole)
        assert.equals("WARRIOR", WHLSN.session.groups[1].tank.classToken)
        assert.is_true(WHLSN.session.groups[1].tank:HasBrez())
    end)

    it("should preserve community and removedPlayers when SPINNING update omits them", function()
        WHLSN.session.host = "HostPlayer"
        WHLSN.session.status = "lobby"
        WHLSN.session.players = {
            WHLSN.Player:New("Tank1", "tank"),
        }
        WHLSN.session.connectedCommunity = { ["Comm1"] = "Comm1" }
        WHLSN.session.removedPlayers = { ["Hidden1"] = true }

        local data = {
            type = "SESSION_UPDATE",
            version = WHLSN.VERSION,
            status = "spinning",
            host = "HostPlayer",
            compactGroups = {
                { tank = "Tank1", dps = {} },
            },
        }
        WHLSN:OnCommReceived(WHLSN.COMM_PREFIX, data, "GUILD", "HostPlayer")

        assert.equals("Comm1", WHLSN.session.connectedCommunity["Comm1"])
        assert.is_true(WHLSN.session.removedPlayers["Hidden1"])
    end)
end)

describe("CompleteSession host guard", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.SPINNING
        WHLSN.session.groups = {
            WHLSN.Group:New(
                WHLSN.Player:New("Tank1", "tank"),
                WHLSN.Player:New("Healer1", "healer"),
                { WHLSN.Player:New("DPS1", "ranged"), WHLSN.Player:New("DPS2", "melee"),
                  WHLSN.Player:New("DPS3", "ranged") }
            ),
        }
        WHLSN.session.players = {}
        WHLSN.SaveSessionResults = function() end
    end)

    it("should broadcast when host", function()
        WHLSN.session.host = "TestPlayer-Illidan"
        local broadcastCalled = false
        WHLSN.BroadcastSessionUpdate = function() broadcastCalled = true end

        WHLSN:CompleteSession()

        assert.equals(WHLSN.Status.COMPLETED, WHLSN.session.status)
        assert.is_true(broadcastCalled)
    end)

    it("should not broadcast when not host", function()
        WHLSN.session.host = "SomeoneElse-Illidan"
        local broadcastCalled = false
        WHLSN.BroadcastSessionUpdate = function() broadcastCalled = true end

        WHLSN:CompleteSession()

        assert.equals(WHLSN.Status.COMPLETED, WHLSN.session.status)
        assert.is_false(broadcastCalled)
    end)
end)

describe("HandleSessionUpdate implicit joinPending ACK", function()
    before_each(function()
        if not mock_db.char then mock_db.char = {} end
        mock_db.char.activeSession = nil
        WHLSN:OnInitialize()
        WHLSN.UpdateUI = function() end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.Deserialize = function(self, msg) return true, msg end
    end)

    it("should clear joinPending when local player is in host player list", function()
        WHLSN.session.joinPending = true
        local timerCancelled = false
        WHLSN.joinAckTimer = { Cancel = function() timerCancelled = true end }

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {
                { name = "HostPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "TestPlayer-Illidan", mainRole = "healer", offspecs = {}, utilities = {} },
            },
        }
        WHLSN:HandleSessionUpdate(data, "HostPlayer")

        assert.is_false(WHLSN.session.joinPending)
        assert.is_true(timerCancelled)
        assert.is_nil(WHLSN.joinAckTimer)
    end)

    it("should not clear joinPending when local player is not in player list", function()
        WHLSN.session.joinPending = true
        WHLSN.joinAckTimer = { Cancel = function() end }

        local data = {
            version = WHLSN.VERSION,
            status = "lobby",
            host = "HostPlayer",
            players = {
                { name = "HostPlayer", mainRole = "tank", offspecs = {}, utilities = {} },
                { name = "OtherPlayer", mainRole = "healer", offspecs = {}, utilities = {} },
            },
        }
        WHLSN:HandleSessionUpdate(data, "HostPlayer")

        assert.is_true(WHLSN.session.joinPending)
    end)
end)

describe("JOIN_ACK timer duration", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel)
            self.sent_messages[#self.sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel }
        end
        WHLSN.Serialize = function(self, data) return data end
        WHLSN.UpdateLobbyView = function() end
        WHLSN.DetectLocalPlayer = function()
            return WHLSN.Player:New("TestPlayer", "tank", {}, {})
        end
    end)

    it("should use a 10 second timeout for JOIN_ACK", function()
        WHLSN.session.host = "HostPlayer"
        WHLSN.session.status = "lobby"

        local timerDuration = nil
        local origNewTimer = _G.C_Timer.NewTimer
        _G.C_Timer.NewTimer = function(duration, cb)
            timerDuration = duration
            return { Cancel = function() end }
        end

        WHLSN:RequestJoin()

        _G.C_Timer.NewTimer = origNewTimer

        assert.equals(10, timerDuration)
    end)
end)
