---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Party Service
-- Handles party invite management for formed groups.
---------------------------------------------------------------------------

--- Invite a list of players to a party.
---@param players WHLSNPlayer[]
function WHLSN:InvitePlayers(players)
    local myName = UnitName("player")
    local invited = {}

    for _, player in ipairs(players) do
        if self:StripRealmName(player.name) ~= myName then
            -- Use realm-qualified name for community players; fall back to
            -- community roster lookup, then bare name for same-realm guild members
            local inviteName = (self.session.connectedCommunity
                and self.session.connectedCommunity[player.name])
                or self:GetCommunityPlayerFullName(player.name)
                or player.name
            if not self.session.isTest then
                C_PartyInfo.InviteUnit(inviteName)
            end
            invited[#invited + 1] = player.name
        end
    end

    local prefix = self.session.isTest and "[Test] Would invite: " or "Invited: "
    if #invited > 0 then
        self:Print(prefix .. table.concat(invited, ", "))
    else
        self:Print("No players to invite.")
    end
end

--- Check if we can invite players (are we leader or not in a group).
---@return boolean
function WHLSN:CanInvite()
    if IsInGroup() then
        return UnitIsGroupLeader("player")
    end
    return true -- Not in a group, can start one
end
