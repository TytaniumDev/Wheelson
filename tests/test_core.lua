-- Tests for Core.lua initialization
-- Reproduces BugSack error: attempt to perform arithmetic on a nil value at Core.lua:33

-- Minimal stubs for WoW APIs and libraries
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

_G.GetNormalizedRealmName = function() return "Illidan" end

-- Load source files in order
dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
dofile("src/GroupCreator.lua")
dofile("src/Services/CommunityService.lua")
dofile("src/UI/Lobby.lua")

local WHLSN = _G.Wheelson

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
end)

describe("SpinGroups", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.session.status = WHLSN.Status.LOBBY
        WHLSN.session.host = "TestPlayer"
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

    it("should clear leftSessionHost on StartSession", function()
        WHLSN.leftSessionHost = "HostA"
        WHLSN:StartSession()

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

    it("should store realm-qualified host name", function()
        local data = { type = "SESSION_PING", host = "HostPlayer", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "HostPlayer-Illidan")
        assert.equals("HostPlayer-Illidan", WHLSN.session.hostFullName)
    end)

    it("should set session status and host", function()
        local data = { type = "SESSION_PING", host = "HostPlayer", status = "lobby", version = WHLSN.VERSION }
        WHLSN:HandleSessionPing(data, "HostPlayer-Illidan")
        assert.equals("lobby", WHLSN.session.status)
        assert.equals("HostPlayer", WHLSN.session.host)
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
            player = { name = "CommunityGuy", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "CommunityGuy-Stormrage", "WHISPER")
        assert.equals(2, #WHLSN.session.players)
    end)

    it("should track community player in connectedCommunity", function()
        WHLSN:AddCommunityPlayer("CommunityGuy-Stormrage")
        local data = {
            type = "JOIN_REQUEST",
            player = { name = "CommunityGuy", mainRole = "healer", offspecs = {}, utilities = {} },
        }
        WHLSN:HandleJoinRequest(data, "CommunityGuy-Stormrage", "WHISPER")
        assert.equals("CommunityGuy-Stormrage", WHLSN.session.connectedCommunity["CommunityGuy"])
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
        WHLSN.session.connectedCommunity = { ["Tyler"] = "Tyler-Stormrage" }
        WHLSN.session.commChannel = "WHISPER"
        WHLSN.session.hostFullName = "Host-Realm"

        WHLSN:ClearSessionState()

        assert.same({}, WHLSN.session.connectedCommunity)
        assert.is_nil(WHLSN.session.commChannel)
        assert.is_nil(WHLSN.session.hostFullName)
    end)
end)

describe("CommRestriction", function()
    local sent_messages
    local original_IsEncounterInProgress
    local original_C_MythicPlus
    local original_C_PvP

    before_each(function()
        WHLSN:OnInitialize()
        sent_messages = {}
        WHLSN.SendCommMessage = function(self, prefix, msg, channel, target)
            sent_messages[#sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
        end
        original_IsEncounterInProgress = _G.IsEncounterInProgress
        original_C_MythicPlus = _G.C_MythicPlus
        original_C_PvP = _G.C_PvP
    end)

    after_each(function()
        _G.IsEncounterInProgress = original_IsEncounterInProgress
        _G.C_MythicPlus = original_C_MythicPlus
        _G.C_PvP = original_C_PvP
    end)

    it("should send immediately when not restricted", function()
        _G.IsEncounterInProgress = function() return false end

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(1, #sent_messages)
        assert.equals("GUILD", sent_messages[1].channel)
    end)

    it("should queue message when IsEncounterInProgress is true", function()
        _G.IsEncounterInProgress = function() return true end

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
        assert.equals("GUILD", WHLSN.commQueue[1].distribution)
    end)

    it("should queue message when C_MythicPlus run is active", function()
        _G.IsEncounterInProgress = function() return false end
        _G.C_MythicPlus = { IsRunActive = function() return true end }

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
    end)

    it("should queue message when PvP match is active", function()
        _G.IsEncounterInProgress = function() return false end
        _G.C_PvP = { IsActiveBattlefield = function() return true end }

        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
    end)

    it("should flush queued messages on FlushCommQueue when no longer restricted", function()
        _G.IsEncounterInProgress = function() return true end
        WHLSN:SafeSendCommMessage("WHLSN", "msg1", "GUILD")
        WHLSN:SafeSendCommMessage("WHLSN", "msg2", "WHISPER", "Player-Realm")
        assert.equals(2, #WHLSN.commQueue)

        _G.IsEncounterInProgress = function() return false end
        WHLSN:FlushCommQueue()

        assert.equals(2, #sent_messages)
        assert.equals("GUILD", sent_messages[1].channel)
        assert.equals("WHISPER", sent_messages[2].channel)
        assert.equals("Player-Realm", sent_messages[2].target)
        assert.equals(0, #WHLSN.commQueue)
    end)

    it("should not flush if still restricted", function()
        _G.IsEncounterInProgress = function() return true end
        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")

        WHLSN:FlushCommQueue()

        assert.equals(0, #sent_messages)
        assert.equals(1, #WHLSN.commQueue)
    end)

    it("IsCommRestricted should return false when no restriction APIs are present", function()
        _G.IsEncounterInProgress = nil
        _G.C_MythicPlus = nil
        _G.C_PvP = nil

        assert.is_false(WHLSN:IsCommRestricted())
    end)

    it("ENCOUNTER_END handler flushes the queue once restriction lifts", function()
        -- Queue a message during an encounter
        _G.IsEncounterInProgress = function() return true end
        WHLSN:SafeSendCommMessage("WHLSN", "msg", "GUILD")
        assert.equals(1, #WHLSN.commQueue)

        -- Simulate encounter ending; make C_Timer.After invoke synchronously
        _G.IsEncounterInProgress = function() return false end
        local original_after = _G.C_Timer.After
        _G.C_Timer.After = function(_, cb) cb() end

        WHLSN:ENCOUNTER_END()

        _G.C_Timer.After = original_after

        assert.equals(1, #sent_messages)
        assert.equals(0, #WHLSN.commQueue)
    end)
end)
