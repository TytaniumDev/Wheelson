# Slot Machine Wheel Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the card-reveal animation in `src/UI/Wheel.lua` with a slot machine reel system — 5 vertical reels that spin simultaneously with staggered stops, elastic bounce landings, and multi-group auto-advance.

**Architecture:** Complete rewrite of `src/UI/Wheel.lua` maintaining the same public API. Testable logic (candidate pool building, easing math) is exposed on the `WHLSN` table for unit testing. All UI rendering uses WoW's Frame/FontString/Texture APIs driven by a single shared `OnUpdate` handler.

**Tech Stack:** Lua 5.1, WoW 12.0 API (Frame, FontString, Texture, AnimationGroup, C_Timer, PlaySound, SOUNDKIT)

**Spec:** `docs/superpowers/specs/2026-03-14-slot-machine-wheel-design.md`

---

## Chunk 1: Testable Foundation

### Task 1: Candidate Pool Builder

Builds the list of names that scroll through each reel. Pure logic, no UI.

**Files:**
- Modify: `src/UI/Wheel.lua` (will be rewritten incrementally — start fresh)
- Create: `tests/test_wheel.lua`

- [ ] **Step 1: Write failing tests for BuildReelPool**

Create `tests/test_wheel.lua` following the existing test stub pattern (see `tests/test_models.lua` for reference). Stub WoW UI APIs that Wheel.lua will eventually need (`CreateFrame`, `SOUNDKIT`, `PlaySound`, `C_Timer`, `GameFontNormalLarge`, `GameFontNormalSmall`, `GameFontNormal`, `UIPanelButtonTemplate`, `BackdropTemplate`, `UIParent`).

```lua
-- tests/test_wheel.lua
-- Tests for slot machine wheel logic

-- Minimal stubs for WoW APIs and libraries (mirrors tests/test_core.lua pattern)
local mock_db = {
    profile = {
        minimap = { hide = false },
        lastSession = nil,
        sessionHistory = {},
        animationSpeed = 1.0,
        soundEnabled = true,
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
            NewDataObject = function(_, _name, obj) return obj end,
        }
    elseif name == "LibDBIcon-1.0" then
        return {
            Register = function() end,
        }
    elseif name == "AceConfigRegistry-3.0" then
        if silent then return nil end
        return { NotifyChange = function() end }
    end
    if silent then return nil end
    return {}
end

-- WoW API stubs
_G.SlashCmdList = _G.SlashCmdList or {}
_G.time = os.time
_G.table.insert = table.insert
_G.table.remove = table.remove
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Stub WoW UI globals
_G.CreateFrame = function() return {
    SetAllPoints = function() end, SetPoint = function() end,
    ClearAllPoints = function() end,
    SetSize = function() end, Show = function() end, Hide = function() end,
    SetShown = function() end,
    SetScript = function() end, SetText = function() end,
    SetBackdrop = function() end, SetBackdropColor = function() end,
    SetAlpha = function() end, GetWidth = function() return 568 end,
    GetHeight = function() return 400 end, IsShown = function() return false end,
    SetToFinalAlpha = function() end,
    SetResizable = function() end, SetResizeBounds = function() end,
    CreateFontString = function() return {
        SetPoint = function() end, SetText = function() end,
        SetTextColor = function() end, SetAlpha = function() end,
        GetText = function() return "" end,
    } end,
    CreateTexture = function() return {
        SetPoint = function() end, SetSize = function() end,
        SetColorTexture = function() end, SetTexture = function() end,
        SetTexCoord = function() end, SetAlpha = function() end,
        SetDrawLayer = function() end, SetGradient = function() end,
    } end,
    CreateAnimationGroup = function() return {
        CreateAnimation = function() return {
            SetFromAlpha = function() end, SetToAlpha = function() end,
            SetDuration = function() end, SetSmoothing = function() end,
        } end,
        SetScript = function() end, Play = function() end,
    } end,
} end
_G.SOUNDKIT = { AUCTION_WINDOW_OPEN = 1, UI_EPICLOOT_TOAST = 2, READY_CHECK = 3 }
_G.PlaySound = function() end
_G.C_Timer = { NewTimer = function(_, cb) return { Cancel = function() end } end,
               After = function(_, cb) end }
_G.UnitName = function() return "TestPlayer" end
_G.UIParent = {}

dofile("src/Config.lua")
dofile("src/Models.lua")
dofile("src/Core.lua")
dofile("src/UI/Wheel.lua")

local Player = Wheelson.Player

describe("BuildReelPool", function()
    local players

    before_each(function()
        players = {
            Player:New("MainTank", "tank", {}, {"brez"}),
            Player:New("OffTank", "melee", {"tank"}, {}),
            Player:New("MainHealer", "healer", {}, {"lust"}),
            Player:New("OffHealer", "ranged", {"healer"}, {}),
            Player:New("PureDps1", "ranged", {}, {}),
            Player:New("PureDps2", "melee", {}, {}),
            Player:New("HybridDruid", "melee", {"tank", "healer"}, {"brez"}),
        }
    end)

    it("should include main-role players for tank", function()
        local pool = Wheelson.BuildReelPool(players, "tank", nil, {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["MainTank"])
    end)

    it("should include offspec players for tank", function()
        local pool = Wheelson.BuildReelPool(players, "tank", nil, {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["OffTank"])
        assert.is_true(names["HybridDruid"])
    end)

    it("should not include non-eligible players", function()
        local pool = Wheelson.BuildReelPool(players, "tank", nil, {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_nil(names["MainHealer"])
        assert.is_nil(names["PureDps1"])
    end)

    it("should include DPS main and offspec players for dps role", function()
        local pool = Wheelson.BuildReelPool(players, "dps", nil, {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["PureDps1"])
        assert.is_true(names["PureDps2"])
        assert.is_true(names["OffTank"]) -- mainRole is melee
        assert.is_true(names["OffHealer"]) -- mainRole is ranged
        assert.is_true(names["HybridDruid"]) -- mainRole is melee
    end)

    it("should force-insert winner even if not in pool", function()
        local outsider = Player:New("Outsider", nil, {}, {})
        local pool = Wheelson.BuildReelPool(players, "tank", outsider, {})
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["Outsider"])
    end)

    it("should exclude specified names", function()
        local pool = Wheelson.BuildReelPool(players, "tank", nil, { MainTank = true })
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_nil(names["MainTank"])
    end)

    it("should not exclude the winner even if in exclude list", function()
        local winner = players[1] -- MainTank
        local pool = Wheelson.BuildReelPool(players, "tank", winner, { MainTank = true })
        local names = {}
        for _, p in ipairs(pool) do names[p.name] = true end
        assert.is_true(names["MainTank"])
    end)
end)

describe("PadReelPool", function()
    it("should not pad a pool already at min size", function()
        local names = {"A", "B", "C", "D", "E", "F", "G", "H"}
        local padded = Wheelson.PadReelPool(names, 8)
        assert.equal(8, #padded)
    end)

    it("should cycle names to reach min size", function()
        local names = {"A", "B"}
        local padded = Wheelson.PadReelPool(names, 8)
        assert.equal(8, #padded)
        assert.equal("A", padded[1])
        assert.equal("B", padded[2])
        assert.equal("A", padded[3])
        assert.equal("B", padded[4])
    end)

    it("should handle single name", function()
        local names = {"Solo"}
        local padded = Wheelson.PadReelPool(names, 8)
        assert.equal(8, #padded)
        for _, n in ipairs(padded) do
            assert.equal("Solo", n)
        end
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `busted tests/test_wheel.lua`
Expected: FAIL — `BuildReelPool` and `PadReelPool` are not defined yet.

- [ ] **Step 3: Write the Wheel.lua scaffold with BuildReelPool and PadReelPool**

Start a fresh `src/UI/Wheel.lua`. Keep the `WHLSN` global access pattern. Implement only the candidate pool logic for now — the rest of the file will be built up in subsequent tasks.

```lua
---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Slot Machine Wheel View
---------------------------------------------------------------------------

-- Placeholder for UI state (populated in later tasks)
local wheelFrame = nil

---------------------------------------------------------------------------
-- Candidate Pool Logic (testable, no UI dependency)
---------------------------------------------------------------------------

--- Build the candidate pool for a reel.
--- @param players WHLSNPlayer[] All session players
--- @param role string "tank"|"healer"|"dps"
--- @param winner WHLSNPlayer|nil The predetermined winner (force-inserted)
--- @param excludeNames table<string, boolean> Names to exclude (previous group winners)
--- @return WHLSNPlayer[]
function WHLSN.BuildReelPool(players, role, winner, excludeNames)
    local pool = {}
    local winnerInPool = false

    for _, p in ipairs(players) do
        if excludeNames[p.name] and not (winner and p.name == winner.name) then
            -- skip excluded (but never skip the winner)
        else
            local eligible = false
            if role == "tank" then
                eligible = p:IsTankMain() or p:IsOfftank()
            elseif role == "healer" then
                eligible = p:IsHealerMain() or p:IsOffhealer()
            elseif role == "dps" then
                eligible = p:IsDpsMain() or p:IsOffdps()
            end

            if eligible then
                pool[#pool + 1] = p
                if winner and p.name == winner.name then
                    winnerInPool = true
                end
            end
        end
    end

    -- Force-insert winner if not already in pool
    if winner and not winnerInPool then
        pool[#pool + 1] = winner
    end

    return pool
end

--- Pad a name list by cycling to reach minSize.
--- @param names string[] List of names
--- @param minSize number Minimum result length
--- @return string[]
function WHLSN.PadReelPool(names, minSize)
    if #names == 0 then return names end
    if #names >= minSize then return names end

    local padded = {}
    for i = 1, minSize do
        padded[i] = names[((i - 1) % #names) + 1]
    end
    return padded
end

---------------------------------------------------------------------------
-- Public API stubs (implemented in later tasks)
---------------------------------------------------------------------------

function WHLSN:HideWheelView()
    if wheelFrame then wheelFrame:Hide() end
end

function WHLSN:ShowWheelView(parent)
    -- Will be implemented in Task 3
end

function WHLSN:UpdateWheelView()
    -- No-op: animation is self-driven via OnUpdate
end

function WHLSN:SkipWheelAnimation()
    -- Will be implemented in Task 7
end

function WHLSN:OnWheelComplete()
    -- Will be implemented in Task 6
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `busted tests/test_wheel.lua`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/UI/Wheel.lua tests/test_wheel.lua
git commit -m "feat(wheel): add candidate pool builder with tests

TDD implementation of BuildReelPool and PadReelPool for slot machine
reel candidate population. Replaces old Wheel.lua with fresh scaffold."
```

---

### Task 2: Easing Functions

Pure math for the 4-phase animation curve and damped spring bounce.

**Files:**
- Modify: `src/UI/Wheel.lua`
- Modify: `tests/test_wheel.lua`

- [ ] **Step 1: Write failing tests for easing functions**

Append to `tests/test_wheel.lua`:

```lua
describe("SlotEasing", function()
    it("should return 0 at t=0", function()
        assert.near(0, Wheelson.SlotEasing(0), 0.001)
    end)

    it("should return ~1 at t=1 (before bounce)", function()
        -- At t=1.0 the easing should be near 1.0
        -- The bounce may cause slight overshoot, so check it's close
        assert.near(1, Wheelson.SlotEasing(1), 0.05)
    end)

    it("should accelerate quickly in phase 1 (snap start)", function()
        -- At 5% through (phase 1), should already have some progress
        local earlyProgress = Wheelson.SlotEasing(0.05)
        assert.is_true(earlyProgress > 0)
    end)

    it("should be monotonically increasing before bounce phase", function()
        local prev = 0
        -- Check up to 92% (just before bounce at 92.5%)
        for i = 1, 92 do
            local t = i / 100
            local val = Wheelson.SlotEasing(t)
            assert.is_true(val >= prev, "Not monotonic at t=" .. t)
            prev = val
        end
    end)

    it("should be continuous at phase boundaries (no visible jumps)", function()
        local epsilon = 0.001
        -- Phase 1->2 boundary at 0.0375
        local before_p2 = Wheelson.SlotEasing(0.0375 - epsilon)
        local after_p2 = Wheelson.SlotEasing(0.0375 + epsilon)
        assert.near(before_p2, after_p2, 0.01)
        -- Phase 2->3 boundary at 0.625
        local before_p3 = Wheelson.SlotEasing(0.625 - epsilon)
        local after_p3 = Wheelson.SlotEasing(0.625 + epsilon)
        assert.near(before_p3, after_p3, 0.01)
        -- Phase 3->4 boundary at 0.925
        local before_p4 = Wheelson.SlotEasing(0.925 - epsilon)
        local after_p4 = Wheelson.SlotEasing(0.925 + epsilon)
        assert.near(before_p4, after_p4, 0.01)
    end)
end)

describe("DampedSpring", function()
    it("should return 1 at t=0 (start of bounce = target position)", function()
        -- At the start of the bounce phase, we're at the target
        assert.near(1, Wheelson.DampedSpring(0), 0.01)
    end)

    it("should overshoot past 1 briefly", function()
        -- The spring should overshoot at some point
        local foundOvershoot = false
        for i = 1, 50 do
            local t = i / 100
            if Wheelson.DampedSpring(t) > 1.01 then
                foundOvershoot = true
                break
            end
        end
        assert.is_true(foundOvershoot)
    end)

    it("should settle near 1 at t=1", function()
        assert.near(1, Wheelson.DampedSpring(1), 0.01)
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `busted tests/test_wheel.lua`
Expected: FAIL — `SlotEasing` and `DampedSpring` not defined.

- [ ] **Step 3: Implement easing functions in Wheel.lua**

Add after the candidate pool section, before the public API stubs:

```lua
---------------------------------------------------------------------------
-- Easing Functions (testable, no UI dependency)
---------------------------------------------------------------------------

--- Damped spring for the landing bounce.
--- NOTE: The spec describes `1 - e^(-t*k) * cos(t*w)` which approaches 1 from 0.
--- For the landing bounce, we need a function that starts AT 1 (target reached at end
--- of Phase 3) and oscillates around it. This adapted formula does exactly that.
--- Returns a value that overshoots 1, oscillates, and settles at 1.
--- @param t number Normalized time 0-1 within the bounce phase
--- @return number Position (1.0 = target, >1 = overshoot)
function WHLSN.DampedSpring(t)
    if t <= 0 then return 1 end
    if t >= 1 then return 1 end
    local k = 8   -- damping factor
    local w = 12  -- oscillation frequency
    return 1 + math.exp(-k * t) * math.sin(w * t) * 0.15
end

--- Combined 4-phase slot machine easing.
--- Phase 1 (0-0.0375): Snap start — aggressive ease-in
--- Phase 2 (0.0375-0.625): Full speed — linear
--- Phase 3 (0.625-0.925): Deceleration — easeOutCubic
--- Phase 4 (0.925-1.0): Landing bounce — damped spring
--- @param t number Normalized time 0-1 over the full reel duration
--- @return number Normalized scroll progress 0-1
function WHLSN.SlotEasing(t)
    -- Phase boundaries (as fractions of total duration)
    -- 150ms / 4000ms = 0.0375
    -- 2500ms / 4000ms = 0.625
    -- 3700ms / 4000ms = 0.925
    local P1_END = 0.0375
    local P2_END = 0.625
    local P3_END = 0.925

    if t <= 0 then return 0 end
    if t >= 1 then return 1 end

    if t <= P1_END then
        -- Phase 1: Snap start (quartic ease-in)
        local p = t / P1_END
        local progress = p * p * p * p
        -- Phase 1 covers 0 to ~3% of scroll distance
        return progress * 0.03
    elseif t <= P2_END then
        -- Phase 2: Full speed (linear)
        local p = (t - P1_END) / (P2_END - P1_END)
        -- Phase 2 covers 3% to 85% of scroll distance
        return 0.03 + p * 0.82
    elseif t <= P3_END then
        -- Phase 3: Deceleration (easeOutCubic)
        local p = (t - P2_END) / (P3_END - P2_END)
        local eased = 1 - (1 - p) * (1 - p) * (1 - p)
        -- Phase 3 covers 85% to ~100% of scroll distance
        return 0.85 + eased * 0.15
    else
        -- Phase 4: Landing bounce (damped spring around target)
        local p = (t - P3_END) / (1 - P3_END)
        return WHLSN.DampedSpring(p)
    end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `busted tests/test_wheel.lua`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/UI/Wheel.lua tests/test_wheel.lua
git commit -m "feat(wheel): add slot machine easing functions with tests

4-phase easing curve: snap start, full speed, easeOutCubic decel,
and damped spring bounce. TDD implementation."
```

---

## Chunk 2: Reel UI & Animation

### Task 3: Reel Frame Scaffolding

Build the static UI layout — 5 reel containers with role labels, borders, gradient overlays, center pointer, skip button, and group header. No animation yet.

**Files:**
- Modify: `src/UI/Wheel.lua`

- [ ] **Step 1: Add animation constants and helper functions**

Add near the top of `src/UI/Wheel.lua`, after the `local WHLSN` line:

```lua
---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local ROW_HEIGHT = 20         -- Height of each name row in a reel
local VISIBLE_ROWS = 3        -- Number of fully visible rows
local REEL_HEIGHT = ROW_HEIGHT * VISIBLE_ROWS  -- 60px viewport
local FADE_HEIGHT = 16        -- Gradient overlay height at top/bottom
local REEL_PADDING = 6        -- Horizontal gap between reels
local SUMMARY_ROW_HEIGHT = 18 -- Height of collapsed group summary
local MAX_SUMMARY_ROWS = 4    -- Max visible summary rows

-- Role definitions for the 5 reels
local REEL_ROLES = {
    { role = "tank",   label = "TANK",   r = 0.231, g = 0.510, b = 0.961 }, -- #3b82f6
    { role = "healer", label = "HEALER", r = 0.133, g = 0.773, b = 0.369 }, -- #22c55e
    { role = "dps",    label = "DPS 1",  r = 0.937, g = 0.267, b = 0.267 }, -- #ef4444
    { role = "dps",    label = "DPS 2",  r = 0.937, g = 0.267, b = 0.267 },
    { role = "dps",    label = "DPS 3",  r = 0.937, g = 0.267, b = 0.267 },
}

-- Gold accent color
local GOLD_R, GOLD_G, GOLD_B = 0.961, 0.620, 0.043 -- #f59e0b

-- Base reel durations (ms) — scaled by animationSpeed
local BASE_REEL_DURATIONS = { 4000, 4300, 4600, 4900, 5200 }

-- Glow/transition timing (seconds)
local GLOW_DURATION = 1.5
local COLLAPSE_DURATION = 0.5
local RISE_DURATION = 0.5
local FINAL_PAUSE = 2.0
local MIN_POOL_SIZE = 8

---------------------------------------------------------------------------
-- Animation state
---------------------------------------------------------------------------

local wheelFrame = nil
local reelFrames = {}         -- reelFrames[1..5] = reel frame objects
local reelState = {}          -- reelState[1..5] = { scrollOffset, targetScroll, ... }
local summaryRows = {}        -- Completed group summary rows
local currentGroupIndex = 0   -- Which group is currently spinning
local isAnimating = false
local animTimer = nil         -- C_Timer handle for sequencing

local function GetAnimationSpeed()
    if WHLSN.db and WHLSN.db.profile then
        return WHLSN.db.profile.animationSpeed or 1.0
    end
    return 1.0
end

local function ShouldPlaySounds()
    if WHLSN.db and WHLSN.db.profile then
        return WHLSN.db.profile.soundEnabled ~= false
    end
    return true
end
```

- [ ] **Step 2: Implement CreateReelFrame — builds one reel's visual structure**

```lua
---------------------------------------------------------------------------
-- Reel UI Construction
---------------------------------------------------------------------------

--- Create a single reel frame (viewport + inner scroll + gradient overlays).
--- @param parent Frame Parent container
--- @param index number 1-5
--- @param roleDef table { role, label, r, g, b }
--- @return Frame The reel frame with .inner, .label, .pointer, .glowTex, .nameSlots
local function CreateReelFrame(parent, index, roleDef)
    local totalReels = 5
    local availableWidth = parent:GetWidth() - (REEL_PADDING * (totalReels - 1))
    local reelWidth = availableWidth / totalReels

    local reel = CreateFrame("Frame", nil, parent)
    local xOffset = (index - 1) * (reelWidth + REEL_PADDING)
    reel:SetPoint("TOPLEFT", xOffset, 0)
    reel:SetSize(reelWidth, REEL_HEIGHT)

    -- Background with role color tint
    local bg = reel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(roleDef.r * 0.1, roleDef.g * 0.1, roleDef.b * 0.1, 0.9)

    -- Role-colored border (4 edge textures)
    local borderSize = 2
    local borders = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, borderSize },       -- top
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, borderSize },  -- bottom
        { "TOPLEFT", "BOTTOMLEFT", borderSize, nil },      -- left
        { "TOPRIGHT", "BOTTOMRIGHT", borderSize, nil },     -- right
    }) do
        local b = reel:CreateTexture(nil, "BORDER")
        b:SetPoint(edge[1])
        b:SetPoint(edge[2])
        if edge[3] then b:SetWidth(edge[3]) end
        if edge[4] then b:SetHeight(edge[4]) end
        b:SetColorTexture(roleDef.r, roleDef.g, roleDef.b, 0.8)
        borders[#borders + 1] = b
    end
    reel.borders = borders

    -- Glow texture (behind the reel, initially hidden)
    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", reel, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", 4, -4)
    glow:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0)
    reel.glowTex = glow

    -- Inner frame (taller than viewport, holds FontStrings)
    local inner = CreateFrame("Frame", nil, reel)
    inner:SetWidth(reelWidth)
    inner:SetHeight(ROW_HEIGHT * 15) -- room for ~15 name slots
    inner:SetPoint("TOP", 0, 0)
    reel.inner = inner

    -- Pre-create FontString slots on the inner frame
    reel.nameSlots = {}
    for i = 1, 15 do
        local fs = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("TOP", 0, -((i - 1) * ROW_HEIGHT))
        fs:SetHeight(ROW_HEIGHT)
        fs:SetWidth(reelWidth - 8)
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetText("")
        reel.nameSlots[i] = fs
    end

    -- Gradient fade overlays (above FontStrings in draw order)
    -- Uses white base texture + gradient vertex color to create fade from
    -- opaque background color at edges to transparent at center
    local bgR, bgG, bgB = roleDef.r * 0.1, roleDef.g * 0.1, roleDef.b * 0.1

    local fadeTop = reel:CreateTexture(nil, "OVERLAY")
    fadeTop:SetPoint("TOPLEFT")
    fadeTop:SetPoint("TOPRIGHT")
    fadeTop:SetHeight(FADE_HEIGHT)
    fadeTop:SetColorTexture(1, 1, 1, 1)
    fadeTop:SetGradient("VERTICAL",
        CreateColor(bgR, bgG, bgB, 0),  -- bottom of overlay: transparent
        CreateColor(bgR, bgG, bgB, 1))  -- top of overlay: opaque (hides names entering)

    local fadeBottom = reel:CreateTexture(nil, "OVERLAY")
    fadeBottom:SetPoint("BOTTOMLEFT")
    fadeBottom:SetPoint("BOTTOMRIGHT")
    fadeBottom:SetHeight(FADE_HEIGHT)
    fadeBottom:SetColorTexture(1, 1, 1, 1)
    fadeBottom:SetGradient("VERTICAL",
        CreateColor(bgR, bgG, bgB, 1),  -- bottom of overlay: opaque (hides names exiting)
        CreateColor(bgR, bgG, bgB, 0))  -- top of overlay: transparent

    -- Center pointer line (gold)
    local pointer = reel:CreateTexture(nil, "OVERLAY")
    pointer:SetPoint("LEFT", 0, 0)
    pointer:SetPoint("RIGHT", 0, 0)
    pointer:SetHeight(1)
    pointer:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.6)
    reel.pointer = pointer

    -- Role label (above the reel)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", reel, "TOP", 0, 4)
    label:SetText(roleDef.label)
    label:SetTextColor(roleDef.r, roleDef.g, roleDef.b, 1)
    reel.label = label

    -- Utility icons (hidden until post-land)
    local brezIcon = reel:CreateTexture(nil, "OVERLAY")
    brezIcon:SetSize(12, 12)
    brezIcon:SetPoint("LEFT", reel, "RIGHT", -28, 0)
    brezIcon:SetTexture("Interface\\Icons\\Spell_Nature_Reincarnation")
    brezIcon:SetAlpha(0)
    reel.brezIcon = brezIcon

    local lustIcon = reel:CreateTexture(nil, "OVERLAY")
    lustIcon:SetSize(12, 12)
    lustIcon:SetPoint("LEFT", brezIcon, "RIGHT", 2, 0)
    lustIcon:SetTexture("Interface\\Icons\\Spell_Nature_Bloodlust")
    lustIcon:SetAlpha(0)
    reel.lustIcon = lustIcon

    return reel
end
```

- [ ] **Step 3: Implement CreateWheelFrame — the main container with all 5 reels**

```lua
--- Create the full wheel frame with header, 5 reels, and skip button.
--- @param parent Frame The content container from MainFrame
--- @return Frame
local function CreateWheelFrame(parent)
    local frame = CreateFrame("Frame", "WHLSNWheelFrame", parent)
    frame:SetAllPoints()

    -- Group header ("Group 1 of 3")
    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.header:SetPoint("TOP", 0, -4)
    frame.header:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)

    -- Reel container (holds the 5 reels + role labels)
    frame.reelContainer = CreateFrame("Frame", nil, frame)
    frame.reelContainer:SetPoint("TOPLEFT", 8, -40)
    frame.reelContainer:SetPoint("RIGHT", -8, 0)
    frame.reelContainer:SetHeight(REEL_HEIGHT)

    -- Create 5 reels
    reelFrames = {}
    for i, roleDef in ipairs(REEL_ROLES) do
        reelFrames[i] = CreateReelFrame(frame.reelContainer, i, roleDef)
    end

    -- Summary row container (below reels, grows upward from bottom)
    frame.summaryContainer = CreateFrame("Frame", nil, frame)
    frame.summaryContainer:SetPoint("BOTTOMLEFT", 8, 48)
    frame.summaryContainer:SetPoint("BOTTOMRIGHT", -8, 48)
    frame.summaryContainer:SetHeight(MAX_SUMMARY_ROWS * SUMMARY_ROW_HEIGHT)

    -- Skip button
    frame.skipButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.skipButton:SetSize(100, 28)
    frame.skipButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.skipButton:SetText("Skip")
    frame.skipButton:SetScript("OnClick", function()
        WHLSN:SkipWheelAnimation()
    end)

    return frame
end
```

- [ ] **Step 4: Wire up ShowWheelView to create the frame and populate reel names (no animation yet)**

Update the `ShowWheelView` stub:

```lua
--- Show the wheel view and start the slot machine animation.
function WHLSN:ShowWheelView(parent)
    if wheelFrame then wheelFrame:Hide() end
    reelFrames = {}
    reelState = {}
    summaryRows = {}
    currentGroupIndex = 0
    isAnimating = false

    wheelFrame = CreateWheelFrame(parent)
    wheelFrame:Show()

    self:SpinForGroup(1)
end
```

Add a placeholder `SpinForGroup` that just populates names statically (animation comes in Task 4):

```lua
--- Prepare and spin reels for a specific group index.
--- @param groupIndex number
function WHLSN:SpinForGroup(groupIndex)
    currentGroupIndex = groupIndex
    local groups = self.session.groups
    local group = groups[groupIndex]
    if not group then return end

    local numGroups = #groups

    -- Update header
    if numGroups == 1 then
        wheelFrame.header:SetText("Group 1")
    else
        wheelFrame.header:SetText("Group " .. groupIndex .. " of " .. numGroups)
    end

    -- Build exclude list from previous groups' winners
    local excludeNames = {}
    for i = 1, groupIndex - 1 do
        local prev = groups[i]
        if prev.tank then excludeNames[prev.tank.name] = true end
        if prev.healer then excludeNames[prev.healer.name] = true end
        for _, dps in ipairs(prev.dps) do
            excludeNames[dps.name] = true
        end
    end

    -- Get winners for each reel slot
    local winners = {
        group.tank,     -- reel 1: tank
        group.healer,   -- reel 2: healer
        group.dps[1],   -- reel 3: dps1
        group.dps[2],   -- reel 4: dps2
        group.dps[3],   -- reel 5: dps3
    }

    -- Populate each reel
    for i, roleDef in ipairs(REEL_ROLES) do
        local winner = winners[i]
        if winner then
            local pool = WHLSN.BuildReelPool(self.session.players, roleDef.role, winner, excludeNames)
            local names = {}
            for _, p in ipairs(pool) do
                names[#names + 1] = p.name
            end
            names = WHLSN.PadReelPool(names, MIN_POOL_SIZE)

            -- Place winner at a known index for scroll targeting
            -- Shuffle names but ensure winner is at index 1
            local winnerIdx = nil
            for j, n in ipairs(names) do
                if n == winner.name then winnerIdx = j; break end
            end
            if winnerIdx and winnerIdx ~= 1 then
                names[winnerIdx] = names[1]
                names[1] = winner.name
            end

            -- Populate FontString slots
            for j, slot in ipairs(reelFrames[i].nameSlots) do
                local nameIdx = ((j - 1) % #names) + 1
                slot:SetText(names[nameIdx])
            end

            -- Store reel state for animation (Task 4)
            reelState[i] = {
                names = names,
                winner = winner,
                winnerName = winner.name,
                active = true,
                landed = false,
            }
        else
            -- Inactive reel (no winner for this slot)
            for _, slot in ipairs(reelFrames[i].nameSlots) do
                slot:SetText("")
            end
            local centerSlot = reelFrames[i].nameSlots[2] -- middle row
            if centerSlot then
                centerSlot:SetText("|cFF666666(none)|r")
            end
            reelState[i] = { active = false, landed = true }
        end
    end

    -- Animation will be started here in Task 4
    -- For now, just show the winners statically in the center slot
    for i = 1, 5 do
        if reelState[i].active then
            local centerSlot = reelFrames[i].nameSlots[2]
            centerSlot:SetText(reelState[i].winnerName)
            centerSlot:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
        end
    end
end
```

- [ ] **Step 5: Run lint and existing tests to verify nothing is broken**

Run: `luacheck src/ tests/ && busted`
Expected: All pass. Lint clean.

- [ ] **Step 6: Commit**

```bash
git add src/UI/Wheel.lua
git commit -m "feat(wheel): add reel frame scaffolding with 5 reels

Static layout with role labels, colored borders, gradient fade
overlays, center pointer, glow texture, utility icons, skip button,
and group header. Names populated but no animation yet."
```

---

### Task 4: Reel Scroll Animation

The core animation: OnUpdate-driven scrolling with the 4-phase easing, FontString recycling, motion blur alpha, and tick sounds.

**Files:**
- Modify: `src/UI/Wheel.lua`

- [ ] **Step 1: Add the shared OnUpdate handler for all 5 reels**

Add after the reel construction functions, before `SpinForGroup`:

```lua
---------------------------------------------------------------------------
-- Reel Animation Engine
---------------------------------------------------------------------------

--- Start the spin animation for all active reels.
local function StartReelAnimations()
    isAnimating = true
    local speed = GetAnimationSpeed()

    for i = 1, 5 do
        local state = reelState[i]
        if state.active then
            local numCycles = math.random(8, 11)
            local listHeight = #state.names * ROW_HEIGHT
            -- Winner is at index 1 in the names array. The center visible slot
            -- is FontString j=2. In the scroll math, nameIdx for slot j is:
            --   nameIdx = ((baseSlot + j - 1) % #names) + 1
            -- For winner (index 1) to land at j=2, we need:
            --   (baseSlot + 1) % #names == 0  →  baseSlot = #names - 1
            -- So finalOffset = (n-1) * ROW_HEIGHT, and totalScroll is:
            local n = #state.names
            local winnerOffset = (n - 1) * ROW_HEIGHT
            state.totalScroll = (numCycles * listHeight) + winnerOffset
            state.duration = BASE_REEL_DURATIONS[i] / 1000 / speed
            state.elapsed = 0
            state.scrollOffset = 0
            state.landed = false
            state.lastTickSlot = -1  -- Track which name slot was last at center (for tick sound)
        end
    end

    -- Play start sound
    if ShouldPlaySounds() then
        PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN)
    end

    -- Single shared OnUpdate handler
    wheelFrame:SetScript("OnUpdate", function(_, dt)
        local allLanded = true

        for i = 1, 5 do
            local state = reelState[i]
            if not state.active or state.landed then
                -- skip
            else
                allLanded = false
                state.elapsed = state.elapsed + dt
                local t = state.elapsed / state.duration
                if t >= 1 then t = 1 end

                -- Calculate scroll position using our easing
                local progress = WHLSN.SlotEasing(t)
                state.scrollOffset = progress * state.totalScroll

                -- Update inner frame position
                local reel = reelFrames[i]
                local yOffset = state.scrollOffset % (#state.names * ROW_HEIGHT)

                -- Reposition FontString slots based on scroll offset
                local baseSlot = math.floor(yOffset / ROW_HEIGHT)
                local subPixel = yOffset % ROW_HEIGHT

                for j, slot in ipairs(reel.nameSlots) do
                    local nameIdx = ((baseSlot + j - 1) % #state.names) + 1
                    slot:SetText(state.names[nameIdx])
                    slot:SetPoint("TOP", 0, -((j - 1) * ROW_HEIGHT) + subPixel)

                    -- Motion blur: reduce alpha at high speed
                    local speed_fraction = 0
                    if t < 0.625 then
                        speed_fraction = math.min(1, t / 0.0375) -- ramp up in phase 1
                    elseif t < 0.925 then
                        speed_fraction = 1 - ((t - 0.625) / 0.3) -- ramp down in phase 3
                    end
                    local blur_alpha = 1 - (speed_fraction * 0.5)
                    slot:SetAlpha(math.max(0.5, blur_alpha))
                end

                -- Tick sound when a new name crosses center
                local currentTickSlot = math.floor(state.scrollOffset / ROW_HEIGHT)
                if currentTickSlot ~= state.lastTickSlot and ShouldPlaySounds() then
                    state.lastTickSlot = currentTickSlot
                    -- Use a subtle UI tick sound
                    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
                end

                -- Check if this reel has landed
                if t >= 1 then
                    state.landed = true
                    state.scrollOffset = state.totalScroll

                    -- Snap to final position
                    local finalOffset = state.totalScroll % (#state.names * ROW_HEIGHT)
                    local finalBase = math.floor(finalOffset / ROW_HEIGHT)
                    for j, slot in ipairs(reel.nameSlots) do
                        local nameIdx = ((finalBase + j - 1) % #state.names) + 1
                        slot:SetText(state.names[nameIdx])
                        slot:SetPoint("TOP", 0, -((j - 1) * ROW_HEIGHT))
                        slot:SetAlpha(1)
                    end

                    -- Highlight winner in gold
                    local centerSlot = reel.nameSlots[2]
                    centerSlot:SetTextColor(GOLD_R, GOLD_G, GOLD_B)

                    -- Show gold border glow
                    reel.glowTex:SetAlpha(0.3)
                    for _, b in ipairs(reel.borders) do
                        b:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
                    end

                    -- Show utility icons
                    if state.winner then
                        if state.winner:HasBrez() then reel.brezIcon:SetAlpha(1) end
                        if state.winner:HasLust() then reel.lustIcon:SetAlpha(1) end
                    end

                    -- Play landing sound
                    if ShouldPlaySounds() then
                        PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)
                    end
                end
            end
        end

        -- All reels landed
        if allLanded then
            wheelFrame:SetScript("OnUpdate", nil)
            isAnimating = false
            WHLSN:OnAllReelsLanded()
        end
    end)
end
```

- [ ] **Step 2: Update SpinForGroup to call StartReelAnimations instead of showing static winners**

Replace the "For now, just show the winners statically" block at the end of `SpinForGroup` with:

```lua
    -- Start the animation
    StartReelAnimations()
```

- [ ] **Step 3: Run lint to verify**

Run: `luacheck src/UI/Wheel.lua`
Expected: Clean (possibly warnings about globals like `SOUNDKIT` which are WoW-provided).

- [ ] **Step 4: Commit**

```bash
git add src/UI/Wheel.lua
git commit -m "feat(wheel): add reel scroll animation with 4-phase easing

OnUpdate-driven scroll animation with snap start, full speed motion
blur, easeOutCubic deceleration, damped spring bounce, tick sounds,
gold winner highlight, and utility icon reveal on landing."
```

---

### Task 5: Multi-Group Flow & Completion

Group transitions (collapse → summary → rise), auto-advance between groups, final auto-navigate, and skip.

**Files:**
- Modify: `src/UI/Wheel.lua`

- [ ] **Step 1: Implement OnAllReelsLanded — the post-spin glow moment**

```lua
--- Called when all 5 reels have landed for the current group.
function WHLSN:OnAllReelsLanded()
    -- Victory sound
    if ShouldPlaySounds() then
        PlaySound(SOUNDKIT.READY_CHECK)
    end

    local numGroups = #self.session.groups

    -- After glow duration, either advance or complete
    local glowTime = GLOW_DURATION / GetAnimationSpeed()
    animTimer = C_Timer.NewTimer(glowTime, function()
        if currentGroupIndex >= numGroups then
            -- Final group: pause then auto-navigate
            WHLSN:OnFinalGroupComplete()
        else
            -- More groups: collapse and advance
            WHLSN:CollapseAndAdvance()
        end
    end)
end
```

- [ ] **Step 2: Implement CollapseAndAdvance — reel collapse and summary row**

```lua
--- Collapse current reels into a summary row, then spin next group.
function WHLSN:CollapseAndAdvance()
    if not wheelFrame then return end
    local group = self.session.groups[currentGroupIndex]
    if not group then return end

    -- Build summary text with role-colored names
    local parts = {}
    if group.tank then
        parts[#parts + 1] = "|cFF3b82f6" .. group.tank.name .. "|r"
    end
    if group.healer then
        parts[#parts + 1] = "|cFF22c55e" .. group.healer.name .. "|r"
    end
    for _, dps in ipairs(group.dps) do
        parts[#parts + 1] = "|cFFef4444" .. dps.name .. "|r"
    end
    local summaryText = "|cFFFFD100Group " .. currentGroupIndex .. ":|r  "
        .. table.concat(parts, "  |cFF555555·|r  ")

    -- Create summary row
    local row = wheelFrame.summaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row:SetHeight(SUMMARY_ROW_HEIGHT)
    row:SetText(summaryText)
    row:SetJustifyH("LEFT")
    summaryRows[#summaryRows + 1] = row

    -- Position all visible rows (hide oldest if more than MAX_SUMMARY_ROWS)
    local startIdx = math.max(1, #summaryRows - MAX_SUMMARY_ROWS + 1)
    for idx = 1, #summaryRows do
        local r = summaryRows[idx]
        if idx < startIdx then
            r:Hide()
        else
            r:ClearAllPoints()
            local visibleIdx = idx - startIdx
            r:SetPoint("BOTTOMLEFT", 0, visibleIdx * SUMMARY_ROW_HEIGHT)
            r:SetPoint("BOTTOMRIGHT", 0, visibleIdx * SUMMARY_ROW_HEIGHT)
            r:Show()
        end
    end

    -- Fade out current reels
    for i = 1, 5 do
        local reel = reelFrames[i]
        local fadeOut = reel:CreateAnimationGroup()
        fadeOut:SetToFinalAlpha(true)
        local alpha = fadeOut:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0)
        alpha:SetDuration(COLLAPSE_DURATION / GetAnimationSpeed())
        alpha:SetSmoothing("OUT")
        fadeOut:Play()
        reel.glowTex:SetAlpha(0)
        reel.label:SetAlpha(0)
    end

    -- After collapse, reset reels and spin next group
    local collapseTime = COLLAPSE_DURATION / GetAnimationSpeed()
    animTimer = C_Timer.NewTimer(collapseTime, function()
        -- Reset reel visuals for next group
        for i = 1, 5 do
            local reel = reelFrames[i]
            reel:SetAlpha(1)
            reel.label:SetAlpha(1)
            reel.brezIcon:SetAlpha(0)
            reel.lustIcon:SetAlpha(0)
            for _, b in ipairs(reel.borders) do
                local roleDef = REEL_ROLES[i]
                b:SetColorTexture(roleDef.r, roleDef.g, roleDef.b, 0.8)
            end
            for _, slot in ipairs(reel.nameSlots) do
                slot:SetTextColor(1, 1, 1, 1)
                slot:SetAlpha(1)
            end
        end

        WHLSN:SpinForGroup(currentGroupIndex + 1)
    end)
end
```

- [ ] **Step 3: Implement OnFinalGroupComplete — pause then auto-navigate**

```lua
--- Handle the final group completion: pause, then navigate to results.
function WHLSN:OnFinalGroupComplete()
    -- Single-group: skip collapse, just pause and navigate
    local pauseTime = FINAL_PAUSE / GetAnimationSpeed()
    animTimer = C_Timer.NewTimer(pauseTime, function()
        WHLSN:OnWheelComplete()
    end)
end
```

- [ ] **Step 4: Implement OnWheelComplete — complete session and auto-navigate**

Replace the `OnWheelComplete` stub:

```lua
--- Called when all groups have been revealed. Completes session and navigates to results.
function WHLSN:OnWheelComplete()
    -- Guard against double-call (race between final landing and skip)
    if self.session.status ~= self.Status.COMPLETED then
        self:CompleteSession()
    end

    -- Auto-navigate to GroupDisplay results view
    self:ResetView()
    self:UpdateUI()
end
```

- [ ] **Step 5: Implement SkipWheelAnimation and HideWheelView**

Replace the stubs:

```lua
--- Skip remaining animation and jump to results.
function WHLSN:SkipWheelAnimation()
    -- Cancel any pending timers
    if animTimer then
        animTimer:Cancel()
        animTimer = nil
    end

    -- Stop OnUpdate
    if wheelFrame then
        wheelFrame:SetScript("OnUpdate", nil)
    end
    isAnimating = false

    self:OnWheelComplete()
end

--- Hide the wheel view and cancel all animations.
function WHLSN:HideWheelView()
    if animTimer then
        animTimer:Cancel()
        animTimer = nil
    end
    if wheelFrame then
        wheelFrame:SetScript("OnUpdate", nil)
        wheelFrame:Hide()
    end
    isAnimating = false
end
```

- [ ] **Step 6: Run lint and all tests**

Run: `luacheck src/ tests/ && busted`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add src/UI/Wheel.lua
git commit -m "feat(wheel): add multi-group flow with collapse, summary, and auto-navigate

Implements glow moment, reel collapse to summary row, auto-advance
to next group, final pause with auto-navigate to GroupDisplay, skip
button, and CompleteSession idempotency guard. Removes ReSpin."
```

---

## Chunk 3: Sound Research & Polish

### Task 6: One-Armed Bandit Sound Research

Look up Liberation of Undermine slot machine sound IDs and integrate them.

**Files:**
- Modify: `src/UI/Wheel.lua`

- [ ] **Step 1: Research One-Armed Bandit sound FileDataIDs**

Search WoW.tools sound database and Wowhead for One-Armed Bandit / Gallywix encounter sounds from Liberation of Undermine. Look for:
- Slot machine reel spinning/tick sound
- Reel stop/landing sound
- Jackpot/victory fanfare

If found, note the SoundKit IDs. If not found, confirm fallback sounds from `SOUNDKIT`.

- [ ] **Step 2: Update sound constants in Wheel.lua**

Add a sound constants section near the top of the file. Use the discovered IDs or fallbacks:

```lua
-- Sound effects
-- Primary: One-Armed Bandit (Liberation of Undermine) slot machine sounds
-- Fallback: SOUNDKIT built-ins
local SOUND_TICK = nil       -- Set to SoundKit ID if found, else nil for fallback
local SOUND_LAND = nil       -- Set to SoundKit ID if found, else nil for fallback
local SOUND_VICTORY = nil    -- Set to SoundKit ID if found, else nil for fallback

local function PlayTick()
    if not ShouldPlaySounds() then return end
    if SOUND_TICK then
        PlaySound(SOUND_TICK)
    else
        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end
end

local function PlayLand()
    if not ShouldPlaySounds() then return end
    if SOUND_LAND then
        PlaySound(SOUND_LAND)
    else
        PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)
    end
end

local function PlayVictory()
    if not ShouldPlaySounds() then return end
    if SOUND_VICTORY then
        PlaySound(SOUND_VICTORY)
    else
        PlaySound(SOUNDKIT.READY_CHECK)
    end
end

local function PlayStart()
    if not ShouldPlaySounds() then return end
    PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN)
end
```

- [ ] **Step 3: Replace inline PlaySound calls with the helper functions**

In `StartReelAnimations`: replace `PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN)` with `PlayStart()`
In the OnUpdate tick: replace `PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)` with `PlayTick()`
In the landing block: replace `PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)` with `PlayLand()`
In `OnAllReelsLanded`: replace `PlaySound(SOUNDKIT.READY_CHECK)` with `PlayVictory()`

- [ ] **Step 4: Run lint and tests**

Run: `luacheck src/ tests/ && busted`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add src/UI/Wheel.lua
git commit -m "feat(wheel): add sound effect helpers with One-Armed Bandit support

Centralizes sound playback through helper functions. Supports
One-Armed Bandit SoundKit IDs when available, falls back to
standard SOUNDKIT sounds."
```

---

### Task 7: Final Polish & Cleanup

Ensure the gradient overlays render correctly, test the full flow manually, and clean up any remaining issues.

**Files:**
- Modify: `src/UI/Wheel.lua`

- [ ] **Step 1: Verify gradient overlays and overall visual correctness**

Review the `CreateReelFrame` gradient code to confirm:
- Top overlay: opaque at reel top edge, transparent toward center (hides names entering)
- Bottom overlay: opaque at reel bottom edge, transparent toward center (hides names exiting)
- `SetGradient` uses `CreateColor` objects (WoW 12.0 API)
- White base texture (`SetColorTexture(1,1,1,1)`) with gradient vertex color modulation

The gradient code was written correctly in Task 3 using `CreateColor`. Verify it works as expected.

- [ ] **Step 2: Run full test suite and lint**

Run: `luacheck src/ tests/ && busted`
Expected: All pass.

- [ ] **Step 4: Run build validation**

Run: `bash scripts/build.sh`
Expected: PASS — all .toc-listed files exist.

- [ ] **Step 5: Commit**

```bash
git add src/UI/Wheel.lua tests/test_wheel.lua
git commit -m "fix(wheel): correct gradient overlay API and polish

Fixes SetGradient usage for WoW 12.0 API, adds CreateColor test stub,
verifies build and all tests pass."
```
