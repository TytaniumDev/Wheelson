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
-- Easing Functions
---------------------------------------------------------------------------

--- Damped spring oscillation function used for Phase 4 (landing bounce).
--- Returns a value that starts at 1 and oscillates around 1 with decaying
--- amplitude, simulating a physical spring settling.
--- f(t) = 1 + e^(-k*t) * sin(w*t) * 0.15,  k=8, w=12
--- Clamped to return exactly 1 for t<=0 or t>=1.
---@param t number  normalised time [0, 1]
---@return number
function WHLSN.DampedSpring(t)
    if t <= 0 or t >= 1 then return 1 end
    local k = 8
    local w = 12
    return 1 + math.exp(-k * t) * math.sin(w * t) * 0.15
end

--- Four-phase slot-machine easing curve.
---
---  Phase 1 (0   → P1_END=0.0375): quartic ease-in,      maps scroll to  0% –  3%
---  Phase 2 (P1_END → P2_END=0.625): linear,              maps scroll to  3% – 85%
---  Phase 3 (P2_END → P3_END=0.925): easeOutCubic,        maps scroll to 85% – 100%
---  Phase 4 (P3_END → 1.0):          DampedSpring bounce  (oscillates around 1)
---
--- Returns 0 for t<=0, 1 for t>=1.
---@param t number  normalised time [0, 1]
---@return number
function WHLSN.SlotEasing(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end

    local P1_END = 0.0375
    local P2_END = 0.625
    local P3_END = 0.925

    -- Output range for each phase (scroll progress)
    local P1_OUT_START = 0.00
    local P1_OUT_END   = 0.03
    local P2_OUT_END   = 0.85
    local P3_OUT_END   = 1.00

    if t < P1_END then
        -- Phase 1: quartic ease-in
        local p = t / P1_END
        local eased = p * p * p * p
        return P1_OUT_START + eased * (P1_OUT_END - P1_OUT_START)

    elseif t < P2_END then
        -- Phase 2: linear
        local p = (t - P1_END) / (P2_END - P1_END)
        return P1_OUT_END + p * (P2_OUT_END - P1_OUT_END)

    elseif t < P3_END then
        -- Phase 3: easeOutCubic  1 - (1-p)^3
        local p = (t - P2_END) / (P3_END - P2_END)
        local eased = 1 - (1 - p) * (1 - p) * (1 - p)
        return P2_OUT_END + eased * (P3_OUT_END - P2_OUT_END)

    else
        -- Phase 4: damped spring bounce around 1
        local p = (t - P3_END) / (1 - P3_END)
        return WHLSN.DampedSpring(p)
    end
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
