---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Wheel View
-- Slot-machine-style animated group reveal
---------------------------------------------------------------------------

local wheelFrame = nil

---------------------------------------------------------------------------
-- Candidate Pool Helpers
---------------------------------------------------------------------------

--- Build the candidate pool (list of WHLSNPlayer) for a single reel.
--- Filters the players list by eligibility for the given role, excludes
--- names in excludeNames (except the winner), then force-inserts the winner
--- if they aren't already present.
---@param players WHLSNPlayer[]
---@param role string  "tank"|"healer"|"dps"
---@param winner string  name of the winning player
---@param excludeNames table  map of name→true for names to skip
---@return WHLSNPlayer[]
function WHLSN.BuildReelPool(players, role, winner, excludeNames)
    local pool = {}
    local winnerInPool = false

    for _, p in ipairs(players) do
        -- Check eligibility for the requested role
        local eligible = false
        if role == "tank" then
            eligible = p:IsTankMain() or p:IsOfftank()
        elseif role == "healer" then
            eligible = p:IsHealerMain() or p:IsOffhealer()
        elseif role == "dps" then
            eligible = p:IsDpsMain() or p:IsOffdps()
        end

        if eligible then
            -- Exclude logic: skip excluded names unless this player is the winner
            if p.name == winner or not excludeNames[p.name] then
                pool[#pool + 1] = p
                if p.name == winner then
                    winnerInPool = true
                end
            end
        end
    end

    -- Force-insert the winner if they weren't found in the eligible pool.
    -- Search the full players list first; if the winner isn't there at all,
    -- synthesise a minimal Player entry so the reel can still show the name.
    if not winnerInPool then
        local found = false
        for _, p in ipairs(players) do
            if p.name == winner then
                pool[#pool + 1] = p
                found = true
                break
            end
        end
        if not found then
            pool[#pool + 1] = WHLSN.Player:New(winner, nil, {}, {})
        end
    end

    return pool
end

--- Pad (or return as-is) a names array so it has at least minSize entries,
--- cycling through the existing names as needed.
---@param names string[]
---@param minSize number
---@return string[]
function WHLSN.PadReelPool(names, minSize)
    if #names >= minSize then
        -- Return a copy up to minSize so callers get a fresh table
        local result = {}
        for i = 1, #names do
            result[#result + 1] = names[i]
        end
        return result
    end

    local result = {}
    local i = 1
    while #result < minSize do
        result[#result + 1] = names[i]
        i = i + 1
        if i > #names then i = 1 end
    end
    return result
end

---------------------------------------------------------------------------
-- Public API stubs
---------------------------------------------------------------------------

--- Hide the wheel view and cancel any pending animation timers.
function WHLSN:HideWheelView()
    if wheelFrame then wheelFrame:Hide() end
end

--- Show the wheel view inside the given content frame (stub).
---@param parent table
function WHLSN:ShowWheelView(parent) -- luacheck: ignore 212
end

--- Update the wheel view (no-op stub; animation is self-driven).
function WHLSN:UpdateWheelView()
end

--- Skip remaining animation and show all reels at their final positions (stub).
function WHLSN:SkipWheelAnimation()
end

--- Called when all reels have settled (stub).
function WHLSN:OnWheelComplete()
end
