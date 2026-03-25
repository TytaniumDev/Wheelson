---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Addon Communication
---------------------------------------------------------------------------

--- Return true when WoW 12.0 restricts addon comms (boss encounter, M+ run, or PvP match).
function WHLSN:IsCommRestricted()
    return (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress
                and C_InstanceEncounter.IsEncounterInProgress())
        or (C_MythicPlus and C_MythicPlus.IsRunActive and C_MythicPlus.IsRunActive())
        or (C_PvP and C_PvP.IsActiveBattlefield and C_PvP.IsActiveBattlefield())
        or false
end

--- Send an addon message, queuing it if communication is currently restricted.
function WHLSN:SafeSendCommMessage(prefix, message, distribution, target)
    if self:IsCommRestricted() then
        self.commQueue[#self.commQueue + 1] = {
            prefix = prefix, message = message, distribution = distribution, target = target,
        }
        return
    end
    self:SendCommMessage(prefix, message, distribution, target)
end

--- Flush all queued addon messages once communication is no longer restricted.
function WHLSN:FlushCommQueue()
    if self:IsCommRestricted() then return end
    local queue = self.commQueue
    self.commQueue = {}
    for _, msg in ipairs(queue) do
        self:SendCommMessage(msg.prefix, msg.message, msg.distribution, msg.target)
    end
end

--- Flush the comm queue when a restriction lifts (delayed 1s to let state settle).
local function flushAfterDelay()
    C_Timer.After(1, function()
        WHLSN:FlushCommQueue()
    end)
end

function WHLSN:ENCOUNTER_END()        flushAfterDelay() end
function WHLSN:CHALLENGE_MODE_COMPLETED() flushAfterDelay() end
function WHLSN:CHALLENGE_MODE_RESET()     flushAfterDelay() end
function WHLSN:PVP_MATCH_COMPLETE()       flushAfterDelay() end

--- Broadcast session state to the guild (throttled) and refresh the host's lobby UI.
function WHLSN:NotifySessionChange()
    self:BroadcastSessionUpdate()
    self:UpdateLobbyView()
    self:PersistSessionState()
end

--- Broadcast session state to the guild (throttled).
function WHLSN:BroadcastSessionUpdate()
    if self.session.isTest then return end
    self:TouchActivity()

    -- Throttle broadcasts to avoid flooding
    if self.commThrottleTimer then
        self.commPendingUpdate = true
        return
    end

    self:SendSessionUpdate()

    self.commThrottleTimer = C_Timer.NewTimer(self.COMM_THROTTLE, function()
        self.commThrottleTimer = nil
        if self.commPendingUpdate then
            self.commPendingUpdate = false
            self:SendSessionUpdate()
        end
    end)
end

--- Send the actual session update message.
function WHLSN:SendSessionUpdate()
    local playerList = {}
    for _, p in ipairs(self.session.players) do
        playerList[#playerList + 1] = p:ToDict()
    end

    local data = {
        type = "SESSION_UPDATE",
        version = self.VERSION,
        status = self.session.status,
        host = self.session.host,
        playerCount = #self.session.players,
        players = playerList,
        community = self.session.connectedCommunity,
        removedPlayers = self.session.removedPlayers,
    }

    if self.session.status == self.Status.SPINNING or
       self.session.status == self.Status.COMPLETED then
        local groupData = {}
        for _, g in ipairs(self.session.groups) do
            groupData[#groupData + 1] = g:ToDict()
        end
        data.groups = groupData
    end

    local serialized = self:Serialize(data)
    self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")

    -- Also whisper connected community players
    self:WhisperCommunityPlayers(serialized)
end

--- Broadcast session end to the guild (and community players).
---@param communityList table|nil Optional community list captured before session cleanup
function WHLSN:BroadcastSessionEnd(communityList)
    local serialized = self:Serialize({ type = "SESSION_END" })
    self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")

    if communityList then
        self:WhisperCommunityPlayers(serialized, communityList)
    end
end

--- Handle incoming addon messages.
function WHLSN:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= self.COMM_PREFIX then return end
    if sender == UnitName("player") then return end

    local success, data = self:Deserialize(message)
    if not success then return end

    -- Version handshake warning (skip for discovery and ping messages to avoid noise)
    if data.type ~= "ADDON_PING" and data.type ~= "ADDON_PONG" and data.type ~= "SESSION_PING"
        and data.type ~= "JOIN_ACK" and data.type ~= "SESSION_QUERY" then
        if data.version and data.version ~= self.VERSION then
            if data.version ~= "@project-version@" and self.VERSION ~= "@project-version@" then
                self:Print("Warning: " .. sender .. " is using addon version " .. tostring(data.version)
                    .. " (you have " .. tostring(self.VERSION) .. ")")
            end
        end
    end

    if data.type == "SESSION_UPDATE" then
        self:HandleSessionUpdate(data, sender, distribution)
    elseif data.type == "SESSION_END" then
        self:HandleSessionEnd(sender)
    elseif data.type == "JOIN_REQUEST" then
        self:HandleJoinRequest(data, sender, distribution)
    elseif data.type == "LEAVE_REQUEST" then
        self:HandleLeaveRequest(data, sender)
    elseif data.type == "SPEC_UPDATE" then
        self:HandleSpecUpdate(data, sender, distribution)
    elseif data.type == "JOIN_ACK" then
        self:HandleJoinAck(data, sender)
    elseif data.type == "SESSION_QUERY" then
        self:HandleSessionQuery(sender)
    elseif data.type == "SESSION_PING" then
        self:HandleSessionPing(data, sender)
    elseif data.type == "ADDON_PING" then
        self:HandleAddonPing(sender)
    elseif data.type == "ADDON_PONG" then
        self:HandleAddonPong(data, sender)
    end
end

function WHLSN:HandleSessionPing(data, sender)
    -- Ignore if already in any active session (guild members get SESSION_UPDATE via GUILD,
    -- so a SESSION_PING would incorrectly overwrite their channel to WHISPER)
    if self.session.status then return end
    -- Ignore if we intentionally left this host
    if self.leftSessionHost and self:NamesMatch(self.leftSessionHost, data.host) then
        return
    end

    self.session.status = data.status
    self.session.host = sender
    self.session.commChannel = "WHISPER"

    self:UpdateUI()
end

function WHLSN:HandleSessionUpdate(data, sender, distribution)
    -- Security: Validate communication channel and sender authorization
    if distribution ~= "GUILD" and distribution ~= "WHISPER" then return end
    if distribution == "WHISPER" and not self:IsCommunityRosterMember(sender) then return end

    -- Suppress updates from the specific host we left (scoped, not global)
    if self.leftSessionHost and self:NamesMatch(sender, self.leftSessionHost) then
        return
    end

    -- Only accept updates from the session host (or accept new sessions when no host set)
    if self.session.host and not self:NamesMatch(sender, self.session.host) then
        return
    end

    if data.host then
        -- Notify on first lobby discovery (no active session, or previous session ended by host)
        if data.status == "lobby"
            and (self.session.status == nil or self.session.hostEnded) then
            self:Print(data.host .. " created a lobby! Type /wheelson to join.")
        end

        self.session.status = data.status
        self.session.host = data.host

        -- Clear stale leftSessionHost when accepting a new session
        self.leftSessionHost = nil
        self.session.hostEnded = false

        -- Update full player list from host
        if data.players then
            self.session.players = {}
            for _, pd in ipairs(data.players) do
                self.session.players[#self.session.players + 1] = WHLSN.Player.FromDict(pd)
            end
        end

        if data.groups then
            self.session.groups = {}
            for _, gd in ipairs(data.groups) do
                self.session.groups[#self.session.groups + 1] = WHLSN.Group.FromDict(gd)
            end
        end

        if data.community then
            self.session.connectedCommunity = {}
            for k, v in pairs(data.community) do
                self.session.connectedCommunity[k] = v
            end
        end

        if data.removedPlayers then
            self.session.removedPlayers = {}
            for k, v in pairs(data.removedPlayers) do
                self.session.removedPlayers[k] = v
            end
        end

        self:UpdateUI()
        self:PersistSessionState()
    end
end

function WHLSN:HandleSessionEnd(sender)
    -- Only accept end from the session host; ignore if not in a session
    if not self.session.host then return end
    if not self:NamesMatch(self.session.host, sender) then return end

    -- Non-host: preserve display state, mark session as host-ended
    self.session.hostEnded = true
    self.session.host = nil  -- allow new sessions through the host-match guard
    self.session.algorithmSnapshot = nil

    self:UpdateUI()
end

function WHLSN:HandleJoinRequest(data, sender, distribution)
    -- Only the host processes join requests
    if not self:NamesMatch(self.session.host, self:GetMyFullName()) then return end
    if self.session.status ~= self.Status.LOBBY then return end

    -- Validate sender matches the player data
    if not data.player then return end
    if not self:NamesMatch(data.player.name, sender) then return end

    -- Only accept joins over expected channels
    if distribution ~= "GUILD" and distribution ~= "WHISPER" then return end
    -- Whisper joins require community roster membership
    if distribution == "WHISPER" then
        if not self:IsCommunityRosterMember(sender) then return end
    end

    local player = WHLSN.Player.FromDict(data.player)
    self:ResolvePlayerName(player, sender)

    local ackData = { type = "JOIN_ACK", playerName = player.name }
    local ackSerialized = self:Serialize(ackData)

    local function sendAck()
        if distribution == "WHISPER" then
            self:SafeSendCommMessage(self.COMM_PREFIX, ackSerialized, "WHISPER", sender)
        else
            self:SafeSendCommMessage(self.COMM_PREFIX, ackSerialized, "GUILD")
        end
    end

    -- Replace if already in list
    for i, p in ipairs(self.session.players) do
        if self:NamesMatch(p.name, player.name) then
            self.session.players[i] = player
            sendAck()
            self:NotifySessionChange()
            return
        end
    end

    self.session.players[#self.session.players + 1] = player

    -- Track community player for whisper broadcasts
    if distribution == "WHISPER" then
        self.session.connectedCommunity[sender] = sender
    end

    sendAck()
    self:NotifySessionChange()
end

--- Handle JOIN_ACK from host (client-side).
function WHLSN:HandleJoinAck(data, _sender)
    if not self.session.joinPending then return end
    if not self:NamesMatch(data.playerName, self:GetMyFullName()) then return end
    self.session.joinPending = false
    if self.joinAckTimer then
        self.joinAckTimer:Cancel()
        self.joinAckTimer = nil
    end
end

--- Handle SESSION_QUERY from a non-host (host only).
function WHLSN:HandleSessionQuery(_sender)
    if not self:NamesMatch(self.session.host, self:GetMyFullName()) then return end
    if not self.session.status then return end
    self:SendSessionUpdate()
end

--- Broadcast a SESSION_QUERY to discover or validate an active session.
--- Throttled to at most one per 10 seconds.
function WHLSN:SendSessionQuery()
    local now = time()
    if self.lastSessionQuery and (now - self.lastSessionQuery) < 10 then return end
    self.lastSessionQuery = now

    local data = { type = "SESSION_QUERY" }
    local serialized = self:Serialize(data)

    if self.session.commChannel == "WHISPER" and self.session.host then
        self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "WHISPER", self.session.host)
    else
        self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
    end
end

function WHLSN:HandleLeaveRequest(data, sender)
    -- Only the host processes leave requests
    if not self:NamesMatch(self.session.host, self:GetMyFullName()) then return end
    if not data.playerName then return end
    if not self:NamesMatch(data.playerName, sender) then return end

    for i, p in ipairs(self.session.players) do
        if self:NamesMatch(p.name, sender) then
            table.remove(self.session.players, i)
            self.session.connectedCommunity[sender] = nil
            self.session.removedPlayers[p.name] = nil
            self:NotifySessionChange()
            return
        end
    end
end

function WHLSN:HandleSpecUpdate(data, sender, distribution)
    -- Only the host processes spec updates
    if not self:NamesMatch(self.session.host, self:GetMyFullName()) then return end
    if self.session.status ~= self.Status.LOBBY then return end

    -- Validate sender matches the player data
    if not data.player then return end
    if not self:NamesMatch(data.player.name, sender) then return end

    -- Only accept over expected channels
    if distribution ~= "GUILD" and distribution ~= "WHISPER" then return end
    if distribution == "WHISPER" then
        if not self:IsCommunityRosterMember(sender) then return end
    end

    local player = WHLSN.Player.FromDict(data.player)
    self:ResolvePlayerName(player, sender)

    -- Find and replace existing player
    for i, p in ipairs(self.session.players) do
        if self:NamesMatch(p.name, player.name) then
            self.session.players[i] = player
            self:NotifySessionChange()
            return
        end
    end
    -- If player not found in session, ignore (they must join first)
end
