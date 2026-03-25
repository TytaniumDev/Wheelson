---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Addon Discovery
---------------------------------------------------------------------------

function WHLSN:HandleAddonPing(_sender)
    -- Reply with our presence info, broadcast to GUILD so all clients can cache
    local data = {
        type = "ADDON_PONG",
        name = UnitName("player"),
        version = self.VERSION,
    }
    local serialized = self:Serialize(data)
    self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
end

function WHLSN:HandleAddonPong(data, sender)
    local name = self:StripRealmName(sender)
    self.addonUsersCache[name] = {
        name = name,
        version = data.version or "unknown",
        lastSeen = time(),
    }

    -- Refresh options panel if open so it live-updates as PONGs arrive
    local ACR = LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("Wheelson")
    end
end

--- Broadcast a discovery ping to find online addon users.
function WHLSN:SendAddonPing()
    -- Add local player to cache (bypasses self-filter in OnCommReceived)
    local myName = UnitName("player")
    self.addonUsersCache[myName] = {
        name = myName,
        version = self.VERSION,
        lastSeen = time(),
    }

    local data = { type = "ADDON_PING" }
    local serialized = self:Serialize(data)
    self:SafeSendCommMessage(self.COMM_PREFIX, serialized, "GUILD")

    self.isScanning = true
    C_Timer.After(self.DISCOVERY_SCAN_DURATION, function()
        self.isScanning = false
        -- Refresh options panel if AceConfigRegistry is available
        local ACR = LibStub("AceConfigRegistry-3.0", true)
        if ACR then
            ACR:NotifyChange("Wheelson")
        end
    end)
end

--- Remove cached addon users who are no longer online in the guild roster.
function WHLSN:PruneAddonUsersCache()
    local onlineMembers = self:GetOnlineGuildMembers()
    local onlineSet = {}
    for _, m in ipairs(onlineMembers) do
        onlineSet[m.name] = true
    end

    for name in pairs(self.addonUsersCache) do
        if not onlineSet[name] then
            self.addonUsersCache[name] = nil
        end
    end
end
