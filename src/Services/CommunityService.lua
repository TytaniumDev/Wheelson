---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Community Service
-- Manages the persistent community roster and whisper-based communication
-- for non-guild players who have the addon installed.
---------------------------------------------------------------------------

--- Validate a community player name.
---@param name string
---@return boolean ok
---@return string|nil error
function WHLSN:ValidateCommunityName(name)
    if not name then return false, "Name is required" end
    local trimmed = strtrim(name)
    if trimmed == "" then return false, "Name cannot be empty" end
    -- Validate format: Name or Name-Realm (realm may contain digits, e.g., Area52)
    if not trimmed:match("^[%a']+$") and not trimmed:match("^[%a']+%-[%a%d%-]+$") then
        return false, "Invalid name format. Use 'Player' or 'Player-Realm'."
    end
    return true
end

--- Normalize a community player name to realm-qualified form.
---@param name string
---@return string
function WHLSN:NormalizeCommunityName(name)
    local trimmed = strtrim(name)
    if not trimmed:find("-") then
        local realm = GetNormalizedRealmName()
        if realm then
            trimmed = trimmed .. "-" .. realm
        end
    end
    return trimmed
end

--- Add a player to the persistent community roster.
---@param name string Bare or realm-qualified name
---@return boolean ok
---@return string|nil error
function WHLSN:AddCommunityPlayer(name)
    local ok, err = self:ValidateCommunityName(name)
    if not ok then return false, err end

    local normalized = self:NormalizeCommunityName(name)
    local bareName = self:StripRealmName(normalized):lower()

    for _, entry in ipairs(self.db.profile.communityRoster) do
        if self:StripRealmName(entry.name):lower() == bareName then
            return false, "Player already in roster"
        end
    end

    self.db.profile.communityRoster[#self.db.profile.communityRoster + 1] = { name = normalized }
    return true
end

--- Remove a player from the persistent community roster.
---@param name string Bare or realm-qualified name
---@return boolean ok
function WHLSN:RemoveCommunityPlayer(name)
    local bareName = self:StripRealmName(name):lower()

    for i, entry in ipairs(self.db.profile.communityRoster) do
        if self:StripRealmName(entry.name):lower() == bareName then
            table.remove(self.db.profile.communityRoster, i)
            return true
        end
    end

    return false
end

--- Check if a player name exists in the community roster.
---@param name string Bare or realm-qualified name
---@return boolean
function WHLSN:IsCommunityRosterMember(name)
    local bareName = self:StripRealmName(name):lower()

    for _, entry in ipairs(self.db.profile.communityRoster) do
        if self:StripRealmName(entry.name):lower() == bareName then
            return true
        end
    end

    return false
end

--- Get the realm-qualified name for a community roster member.
---@param name string Bare or realm-qualified name
---@return string|nil
function WHLSN:GetCommunityPlayerFullName(name)
    local bareName = self:StripRealmName(name):lower()

    for _, entry in ipairs(self.db.profile.communityRoster) do
        if self:StripRealmName(entry.name):lower() == bareName then
            return entry.name
        end
    end

    return nil
end

--- Send SESSION_PING whispers to all community roster members.
function WHLSN:SendCommunityPings()
    if self.session.isTest then return end

    local data = {
        type = "SESSION_PING",
        host = UnitName("player"),
        status = self.session.status,
        version = self.VERSION,
    }
    local serialized = self:Serialize(data)

    local myName = UnitName("player")
    for _, entry in ipairs(self.db.profile.communityRoster) do
        if self:StripRealmName(entry.name) ~= myName then
            self:SendCommMessage(self.COMM_PREFIX, serialized, "WHISPER", entry.name)
        end
    end
end

--- Whisper a serialized message to all connected community players.
---@param serialized string Already-serialized message data
---@param communityList table|nil Optional override list; defaults to session.connectedCommunity
function WHLSN:WhisperCommunityPlayers(serialized, communityList)
    local list = communityList or self.session.connectedCommunity
    local myName = UnitName("player")

    for bareName, fullName in pairs(list) do
        if bareName ~= myName then
            self:SendCommMessage(self.COMM_PREFIX, serialized, "WHISPER", fullName)
        end
    end
end
