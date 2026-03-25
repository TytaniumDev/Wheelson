-- Tests for Session.lua
local mock_db = {
    profile = {
        minimap = { hide = false },
        lastSession = nil,
        sessionHistory = {},
        lastGroups = {},
        communityRoster = {},
    },
    char = {
        activeSession = nil,
    }
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
            addon.Serialize = function(_, data) return data end
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
        local analytics = {}
        analytics.IncrementCounter = function() end
        return { Register = function(_, _id) return analytics end }
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
    NewTimer = function(_, cb) return { Cancel = function() end, cb = cb } end,
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
_G.random = math.random
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end

-- Load source files
dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/TestData.lua")
dofile("src/Session.lua")
dofile("src/Comm.lua")
dofile("src/Discovery.lua")
dofile("src/Core.lua")
dofile("src/Services/SpecService.lua")
dofile("src/GroupCreator.lua")
dofile("src/Services/CommunityService.lua")
dofile("src/UI/SpecOverride.lua")
dofile("src/UI/CommunityPanel.lua")
dofile("src/UI/Lobby.lua")
dofile("src/Services/PartyService.lua")
dofile("src/UI/GroupDisplay.lua")

local WHLSN = _G.Wheelson

-- Capture real functions to restore them
local realPersistSessionState = WHLSN.PersistSessionState
local realRestoreSessionState = WHLSN.RestoreSessionState

describe("Session", function()
    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.Print = function() end
        WHLSN.ShowMainFrame = function() end
        WHLSN.BroadcastSessionUpdate = function() end
        WHLSN.SendCommunityPings = function() end
        WHLSN.PersistSessionState = function() end
        WHLSN.UpdateUI = function() end
        WHLSN.BroadcastSessionEnd = function() end
        WHLSN.SafeSendCommMessage = function() end
        WHLSN.analytics = { IncrementCounter = function() end }
        mock_db.char.activeSession = nil
        mock_db.profile.sessionHistory = {}
    end)

    describe("CreateLobby", function()
        it("should initialize session state correctly", function()
            WHLSN:CreateLobby()

            assert.equals(WHLSN.Status.LOBBY, WHLSN.session.status)
            assert.equals("TestPlayer-Illidan", WHLSN.session.host)
            assert.is_not_nil(WHLSN.session.players[1])
            assert.equals("TestPlayer-Illidan", WHLSN.session.players[1].name)
        end)

        it("should increment sessionsStarted analytic", function()
            local incremented = false
            WHLSN.analytics.IncrementCounter = function(_, key)
                if key == "sessionsStarted" then incremented = true end
            end

            WHLSN:CreateLobby()
            assert.is_true(incremented)
        end)

        it("should not create a lobby if one is already active", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            local printed = false
            WHLSN.Print = function(_, msg)
                if msg:find("already active") then printed = true end
            end

            WHLSN:CreateLobby()
            assert.is_true(printed)
        end)

        it("should clear sessionRestoreTimer if it exists", function()
            local cancelled = false
            WHLSN.sessionRestoreTimer = { Cancel = function() cancelled = true end }

            WHLSN:CreateLobby()
            assert.is_true(cancelled)
            assert.is_nil(WHLSN.sessionRestoreTimer)
        end)
    end)

    describe("CreateTestLobby", function()
        it("should initialize test lobby state", function()
            WHLSN:CreateTestLobby()
            assert.equals(WHLSN.Status.LOBBY, WHLSN.session.status)
            assert.is_true(WHLSN.session.isTest)
            assert.is_true(#WHLSN.session.players > 0)
        end)

        it("should not create a test lobby if one is already active", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            local printed = false
            WHLSN.Print = function(_, msg)
                if msg:find("already active") then printed = true end
            end
            WHLSN:CreateTestLobby()
            assert.is_true(printed)
        end)
    end)

    describe("CloseLobby", function()
        it("should clear session state when closing a lobby", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            WHLSN:CloseLobby()
            assert.is_nil(WHLSN.session.status)
        end)

        it("should broadcast session end for non-test lobbies", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            WHLSN.session.isTest = false
            local broadcasted = false
            WHLSN.BroadcastSessionEnd = function() broadcasted = true end
            WHLSN:CloseLobby()
            assert.is_true(broadcasted)
        end)

        it("should not broadcast session end for test lobbies", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            WHLSN.session.isTest = true
            local broadcasted = false
            WHLSN.BroadcastSessionEnd = function() broadcasted = true end
            WHLSN:CloseLobby()
            assert.is_false(broadcasted)
        end)
    end)

    describe("LeaveSession", function()
        it("should send a LEAVE_REQUEST and clear local state for non-hosts", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            WHLSN.session.host = "HostPlayer-Illidan"
            local sent = false
            WHLSN.SafeSendCommMessage = function(_, _, payload, channel, target)
                if channel == "GUILD" then
                    local success, data = WHLSN:Deserialize(payload)
                    if success and data.type == "LEAVE_REQUEST" then sent = true end
                end
            end
            WHLSN:LeaveSession()
            assert.is_true(sent)
            assert.is_nil(WHLSN.session.status)
        end)

        it("should prevent the host from leaving their own lobby", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            WHLSN.session.host = "TestPlayer-Illidan"
            local printed = false
            WHLSN.Print = function(_, msg)
                if msg:find("You are the host") then printed = true end
            end
            WHLSN:LeaveSession()
            assert.is_true(printed)
            assert.equals(WHLSN.Status.LOBBY, WHLSN.session.status)
        end)
    end)

    describe("SpinGroups", function()
        it("should transition status to SPINNING and create groups", function()
            WHLSN:CreateTestLobby()
            -- Ensure enough players
            while #WHLSN.session.players < 5 do
                table.insert(WHLSN.session.players, WHLSN.Player:New("Extra", "melee"))
            end

            WHLSN:SpinGroups()

            assert.equals(WHLSN.Status.SPINNING, WHLSN.session.status)
            assert.is_true(#WHLSN.session.groups > 0)
            assert.is_not_nil(WHLSN.session.algorithmSnapshot)
        end)

        it("should exclude removed players", function()
            WHLSN:CreateTestLobby()
            while #WHLSN.session.players < 6 do
                table.insert(WHLSN.session.players, WHLSN.Player:New("Extra", "melee"))
            end
            local playerToHide = WHLSN.session.players[#WHLSN.session.players].name
            WHLSN.session.removedPlayers[playerToHide] = true

            WHLSN:SpinGroups()

            for _, g in ipairs(WHLSN.session.groups) do
                for _, p in ipairs(g:GetPlayers()) do
                    assert.is_not.equals(playerToHide, p.name)
                end
            end
        end)
    end)

    describe("CompleteSession", function()
        it("should transition status to COMPLETED", function()
            WHLSN.session.status = WHLSN.Status.SPINNING
            WHLSN:CompleteSession()
            assert.equals(WHLSN.Status.COMPLETED, WHLSN.session.status)
        end)
    end)

    describe("ViewHistorySession", function()
        it("should restore a previous session from history", function()
            local group = WHLSN.Group:New(WHLSN.Player:New("Tank1", "tank"))
            local record = {
                host = "HostPlayer",
                groups = { group:ToDict() },
                timestamp = 12345,
            }
            WHLSN.db.profile.sessionHistory = { record }

            WHLSN:ViewHistorySession(1)

            assert.equals(WHLSN.Status.COMPLETED, WHLSN.session.status)
            assert.equals("HostPlayer", WHLSN.session.host)
            assert.is_true(WHLSN.session.viewingHistory)
            assert.equals(1, #WHLSN.session.groups)
            assert.equals("Tank1", WHLSN.session.groups[1].tank.name)
        end)

        it("should handle invalid index", function()
            WHLSN.db.profile.sessionHistory = {}
            local printed = false
            WHLSN.Print = function(_, msg)
                if msg:find("Lobby not found") then printed = true end
            end
            WHLSN:ViewHistorySession(1)
            assert.is_true(printed)
        end)
    end)

    describe("HidePlayer and UnhidePlayer", function()
        before_each(function()
            WHLSN:CreateLobby()
            table.insert(WHLSN.session.players, WHLSN.Player:New("OtherPlayer", "healer"))
        end)

        it("should hide a player", function()
            WHLSN:HidePlayer("OtherPlayer")
            assert.is_true(WHLSN.session.removedPlayers["OtherPlayer"])
        end)

        it("should unhide a player", function()
            WHLSN:HidePlayer("OtherPlayer")
            WHLSN:UnhidePlayer("OtherPlayer")
            assert.is_nil(WHLSN.session.removedPlayers["OtherPlayer"])
        end)

        it("should not hide the host", function()
            WHLSN:HidePlayer("TestPlayer-Illidan")
            assert.is_nil(WHLSN.session.removedPlayers["TestPlayer-Illidan"])
        end)
    end)

    describe("Session Timeout", function()
        it("ResetSessionTimeout should create a timer", function()
            WHLSN:ResetSessionTimeout()
            assert.is_not_nil(WHLSN.sessionTimeoutTimer)
        end)

        it("OnSessionTimeout should close the lobby", function()
            WHLSN.session.status = WHLSN.Status.LOBBY
            WHLSN:OnSessionTimeout()
            assert.is_nil(WHLSN.session.status)
        end)

        it("TouchActivity should reset the timer", function()
            local cancelled = false
            WHLSN.sessionTimeoutTimer = { Cancel = function() cancelled = true end }
            WHLSN:TouchActivity()
            assert.is_true(cancelled)
            assert.is_not_nil(WHLSN.sessionTimeoutTimer)
        end)
    end)

    describe("Session Persistence", function()
        it("PersistSessionState should save host session state", function()
            WHLSN.PersistSessionState = realPersistSessionState
            WHLSN:CreateLobby()
            WHLSN:PersistSessionState()

            local saved = WHLSN.db.char.activeSession
            assert.is_not_nil(saved)
            assert.equal(WHLSN.Status.LOBBY, saved.status)
            assert.equal("TestPlayer-Illidan", saved.host)
            assert.is_true(saved.isHost)
        end)

        it("RestoreSessionState should restore host state", function()
            WHLSN.RestoreSessionState = realRestoreSessionState
            WHLSN.SendSessionUpdate = function() end

            mock_db.char.activeSession = {
                host = "TestPlayer-Illidan",
                status = WHLSN.Status.LOBBY,
                timestamp = os.time(),
                isHost = true,
                players = { { name = "TestPlayer-Illidan", mainRole = "tank" } }
            }

            WHLSN:RestoreSessionState()
            assert.equal(WHLSN.Status.LOBBY, WHLSN.session.status)
            assert.equal("TestPlayer-Illidan", WHLSN.session.host)
            assert.equal(1, #WHLSN.session.players)
        end)
    end)
end)
