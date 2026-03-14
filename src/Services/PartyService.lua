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
        if player.name ~= myName then
            if not self.session.isTest then
                C_PartyInfo.InviteUnit(player.name)
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
