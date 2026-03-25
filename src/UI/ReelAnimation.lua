---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Reel Animation
-- Sound helpers, candidate pool builders, easing curve, scroll mechanics,
-- and the per-frame OnUpdate handler for the slot-machine animation.
---------------------------------------------------------------------------

-- Cache math functions as upvalues for hot-path performance
local math_floor = math.floor
local math_ceil  = math.ceil
local math_min   = math.min
local math_max   = math.max

local RC = WHLSN._REEL_CONSTANTS
local ws = WHLSN._wheelState

---------------------------------------------------------------------------
-- Sound Helpers
-- Custom .ogg files for tick/land/victory (generated via sox, matching
-- MythicPlusDiscordBot audio.ts synthesis parameters).
-- Start sound uses WoW SoundKit (slot machine arm crank).
---------------------------------------------------------------------------

local SOUND_TICK    = "Interface\\AddOns\\Wheelson\\sounds\\tick.ogg"
local SOUND_LAND    = "Interface\\AddOns\\Wheelson\\sounds\\land.ogg"
local SOUND_VICTORY = "Interface\\AddOns\\Wheelson\\sounds\\victory.ogg"
local SOUND_START   = 271526  -- Foley_Goblin_Casino_Slot_Machine_Arm_Crank_Start (keep)

local lastTickTime  = 0
local frameTime     = 0       -- cached GetTime() value, set once per OnUpdate frame

local function PlayTick()
    if not ws.soundEnabled then return end
    if frameTime - lastTickTime < RC.TICK_THROTTLE then return end
    lastTickTime = frameTime
    PlaySoundFile(SOUND_TICK, "SFX")
end

local function PlayLand()
    if not ws.soundEnabled then return end
    PlaySoundFile(SOUND_LAND, "SFX")
end

local function PlayVictory()
    if not ws.soundEnabled then return end
    PlaySoundFile(SOUND_VICTORY, "SFX")
end

local function PlayStart()
    if not ws.soundEnabled then return end
    PlaySound(SOUND_START, "SFX")
end

-- Expose PlayVictory for Wheel.lua
WHLSN._PlayVictory = PlayVictory

---------------------------------------------------------------------------
-- Candidate Pool Helpers
---------------------------------------------------------------------------

--- Build the candidate pool (list of WHLSNPlayer) for a single reel.
---@param players WHLSNPlayer[]
---@param role string  "tank"|"healer"|"dps"
---@param winner string  name of the winning player
---@param excludeNames table  map of name→true for names to skip
---@return WHLSNPlayer[]
function WHLSN.BuildReelPool(players, role, winner, excludeNames)
    local pool = {}
    local winnerInPool = false

    for _, p in ipairs(players) do
        local eligible = false
        if role == "tank" then
            eligible = p:IsTankMain() or p:IsOfftank()
        elseif role == "healer" then
            eligible = p:IsHealerMain() or p:IsOffhealer()
        elseif role == "dps" then
            eligible = p:IsDpsMain() or p:IsOffdps()
        end

        if eligible then
            if p.name == winner or not excludeNames[p.name] then
                pool[#pool + 1] = p
                if p.name == winner then
                    winnerInPool = true
                end
            end
        end
    end

    if winner and not winnerInPool then
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

--- Pad (or return as-is) a names array so it has at least minSize entries.
---@param names string[]
---@param minSize number
---@return string[]
function WHLSN.PadReelPool(names, minSize)
    if #names == 0 then return {} end
    if #names >= minSize then
        local result = {}
        for i = 1, #names do
            result[#result + 1] = names[i]
        end
        return result
    end

    local result = {}
    while #result < minSize do
        for i = 1, #names do
            result[#result + 1] = names[i]
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Easing Functions
---------------------------------------------------------------------------

--- Three-phase slot-machine easing curve.
---@param t number  normalised time [0, 1]
---@return number
function WHLSN.SlotEasing(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end

    if t < RC.P1_END then
        local p = t / RC.P1_END
        local eased = p * p * p * p
        return eased * RC.P1_OUT_END

    elseif t < RC.P2_END then
        local p = (t - RC.P1_END) / (RC.P2_END - RC.P1_END)
        return RC.P1_OUT_END + p * (RC.P2_OUT_END - RC.P1_OUT_END)

    else
        local p = (t - RC.P2_END) / (1 - RC.P2_END)
        local eased = RC.P3_A * p * p * p + RC.P3_B * p * p + RC.P3_M0 * p
        return RC.P2_OUT_END + eased * RC.P3_RANGE
    end
end

---------------------------------------------------------------------------
-- Reel Scroll Animation
---------------------------------------------------------------------------

--- Calculate scroll metrics for a reel, targeting a uniform linear-phase speed.
---@param state table  reelState entry (needs .names and .duration)
---@return number listHeight, number scrollBase, number scrollDistance
function WHLSN._CalcScrollMetrics(state)
    local numNames = state.numNames or math_min(#state.names, RC.MAX_SLOTS)
    local listHeight = numNames * RC.ROW_HEIGHT

    local linearTimeFrac   = RC.P2_END - RC.P1_END
    local linearScrollFrac = RC.P2_OUT_END - RC.P1_OUT_END
    local scrollDistance = RC.TARGET_SPEED * linearTimeFrac * state.duration / linearScrollFrac

    local totalScroll = math_max(
        RC.MIN_SPIN_CYCLES * listHeight,
        math_ceil(scrollDistance / listHeight) * listHeight
    )

    local scrollBase = totalScroll - scrollDistance
    return listHeight, scrollBase, scrollDistance
end

--- Start the scroll animation for all active reels.
function WHLSN._StartReelAnimations()
    -- Cache sound preference once at animation start
    if WHLSN.db and WHLSN.db.profile then
        ws.soundEnabled = WHLSN.db.profile.soundEnabled ~= false
    else
        ws.soundEnabled = true
    end

    PlayStart()

    for i = 1, 5 do
        local state = ws.reelState[i]
        if state and state.active then
            local listHeight, scrollBase, scrollDistance = WHLSN._CalcScrollMetrics(state)
            state.listHeight     = listHeight
            state.scrollBase     = scrollBase
            state.scrollDistance = scrollDistance
            state.elapsed        = 0
        end
    end

    if ws.frame then
        ws.frame:SetScript("OnUpdate", WHLSN._OnUpdateHandler)
    end
end

---------------------------------------------------------------------------
-- OnUpdate decomposed sub-functions
---------------------------------------------------------------------------

--- Update scroll position and tick sounds for a single active reel.
local function UpdateReelScroll(i, state, dt)
    state.elapsed = state.elapsed + dt
    local t = state.elapsed / state.duration
    if t > 1 then t = 1 end

    local progress     = WHLSN.SlotEasing(t)
    local scrollOffset = state.scrollBase + progress * state.scrollDistance
    local listHeight   = state.listHeight
    local numNames     = state.numNames

    -- Motion-blur alpha based on speed
    local speed = 0
    if t > 0 and t < 1 then
        if t >= RC.P1_END and t < RC.P2_END then
            speed = 1.0
        elseif t < RC.P1_END then
            speed = t / RC.P1_END
        else
            speed = 1.0 - (t - RC.P2_END) / (1 - RC.P2_END)
        end
    end
    local slotAlpha = 1.0 - speed * 0.5

    local reel = ws.reelFrames[i]
    if reel and reel.slots then
        local alphaChanged = slotAlpha ~= state.lastAlpha
        local inner = reel.inner
        local slots = reel.slots
        for j = 1, numNames do
            local rawY = (-scrollOffset - (j - 1) * RC.ROW_HEIGHT) % listHeight - RC.ROW_HEIGHT
            if rawY > RC.ROW_HEIGHT then
                rawY = rawY - listHeight
            end
            local slot = slots[j]
            -- SetPoint with the same anchor name replaces the existing point;
            -- ClearAllPoints() is unnecessary when only one anchor is used.
            slot:SetPoint("TOPLEFT", inner, "TOPLEFT", 2, rawY)
            if alphaChanged then
                slot:SetTextColor(1, 1, 1, slotAlpha)
            end
        end
        state.lastAlpha = slotAlpha

        -- Tick sound: detect when a new name scrolls past the centre row
        local currentRow = math_floor(scrollOffset / RC.ROW_HEIGHT)
        if currentRow ~= state.lastRow and speed > 0.1 then
            PlayTick()
            state.lastRow = currentRow
        end
    end

    return t
end

--- Highlight the winner on a landed reel.
local function HighlightReelWinner(i, state)
    local reel = ws.reelFrames[i]
    if not reel or not reel.slots then return end

    local numNames = state.numNames
    for j = 1, numNames do
        if j == 1 then
            reel.slots[j]:SetTextColor(RC.GOLD_R, RC.GOLD_G, RC.GOLD_B, 1)
        else
            reel.slots[j]:SetTextColor(0.7, 0.7, 0.7, 0.8)
        end
        reel.slots[j]:SetAlpha(1)
    end

    if reel.glow then
        reel.glow:SetColorTexture(RC.GOLD_R, RC.GOLD_G, RC.GOLD_B, 0.35)
        if reel.glow.fadeAG then
            reel.glow.fadeAG:Stop()
            reel.glow.fadeAG:Play()
        end
    end
    for _, border in ipairs(reel.borders or {}) do
        border:SetColorTexture(RC.GOLD_R, RC.GOLD_G, RC.GOLD_B, 1)
    end

    local winner = state.winner
    if winner then
        if winner:HasBrez() and reel.brezIcon then reel.brezIcon:Show() end
        if winner:HasLust() and reel.lustIcon then reel.lustIcon:Show() end
    end

    PlayLand()
end

--- Check if all reels have completed and handle completion.
local function CheckAllReelsComplete()
    if ws.frame then
        ws.frame:SetScript("OnUpdate", nil)
    end

    local anyWereActive = false
    for i = 1, 5 do
        if ws.reelState[i] and ws.reelState[i].active then
            anyWereActive = true
            break
        end
    end

    if anyWereActive then
        WHLSN._OnAllReelsLanded()
    else
        ws.isAnimating = false
    end
end

--- The shared per-frame update handler.
---@param _ table  frame (unused)
---@param dt number  seconds since last frame
WHLSN._OnUpdateHandler = function(_, dt)
    if not ws.isAnimating then return end
    frameTime = GetTime()
    local allLanded = true

    for i = 1, 5 do
        local state = ws.reelState[i]
        if state and state.active and not state.landed then
            allLanded = false
            local t = UpdateReelScroll(i, state, dt)
            if t >= 1 then
                state.landed = true
                HighlightReelWinner(i, state)
            end
        end
    end

    if allLanded then
        CheckAllReelsComplete()
    end
end
