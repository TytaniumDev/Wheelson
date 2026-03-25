---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Reel Frame Creation
-- Shared constants, state, and decomposed composition functions for
-- building individual reel UI frames.
-- Loads BEFORE ReelAnimation.lua and Wheel.lua.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Shared Constants (promoted to WHLSN for cross-file access)
---------------------------------------------------------------------------

-- Cache math functions as upvalues for hot-path performance
local math_floor = math.floor

WHLSN._REEL_CONSTANTS = {
    ROW_HEIGHT          = 20,
    VISIBLE_ROWS        = 3,
    REEL_HEIGHT         = 20 * 3,   -- ROW_HEIGHT * VISIBLE_ROWS
    FADE_HEIGHT         = 16,
    MAX_SLOTS           = 15,
    REEL_PADDING        = 6,

    SUMMARY_ROW_HEIGHT  = 18,
    MAX_SUMMARY_ROWS    = 4,

    GOLD_R              = 0.961,
    GOLD_G              = 0.620,
    GOLD_B              = 0.043,

    BASE_REEL_DURATION  = 3000,     -- ms, first reel spin time
    REEL_DURATION_OFFSET = 300,     -- ms, stagger between successive reels

    GLOW_DURATION       = 1.5,
    COLLAPSE_DURATION   = 0.5,
    FINAL_PAUSE         = 2.0,
    MIN_POOL_SIZE       = 5,
    TARGET_SPEED        = 500,      -- px/s during linear phase (uniform across all reels)
    MIN_SPIN_CYCLES     = 1,        -- minimum full list cycles for visual spin effect

    -- Easing phase boundaries (as fractions of total reel duration)
    P1_END              = 0.03,     -- end of ease-in
    P2_END              = 0.45,     -- end of full speed

    -- Easing output ranges (fraction of total scroll at each phase boundary)
    P1_OUT_END          = 0.01,
    P2_OUT_END          = 0.60,

    GLOW_FADE_DURATION  = 0.3,     -- seconds for glow to fade in when a reel lands
    TICK_THROTTLE       = 0.15,    -- seconds; at most one tick sound per 150ms across all reels
}

-- Derived easing constants (Phase 3 Hermite spline coefficients)
-- m0 matches Phase 2's exit velocity for a smooth transition at the boundary;
-- m1 < 0 creates overshoot-and-settle (slot machine bounce, ~1 name past winner).
do
    local RC = WHLSN._REEL_CONSTANTS
    RC.P3_RANGE = 1.0 - RC.P2_OUT_END
    RC.P3_M0 = ((RC.P2_OUT_END - RC.P1_OUT_END) * (1 - RC.P2_END))
        / ((RC.P2_END - RC.P1_END) * RC.P3_RANGE)
    RC.P3_M1 = -0.5
    RC.P3_A  = RC.P3_M0 + RC.P3_M1 - 2
    RC.P3_B  = 3 - 2 * RC.P3_M0 - RC.P3_M1
end

local RC = WHLSN._REEL_CONSTANTS

-- 5 reel definitions: tank, healer, dps x3
WHLSN._REEL_ROLES = {
    { role = "tank",   label = "TANK",   color = { r = 0.231, g = 0.510, b = 0.961 } },
    { role = "healer", label = "HEALER", color = { r = 0.133, g = 0.773, b = 0.369 } },
    { role = "dps",    label = "DPS 1",  color = { r = 0.937, g = 0.267, b = 0.267 } },
    { role = "dps",    label = "DPS 2",  color = { r = 0.937, g = 0.267, b = 0.267 } },
    { role = "dps",    label = "DPS 3",  color = { r = 0.937, g = 0.267, b = 0.267 } },
}

WHLSN._BASE_REEL_DURATIONS = {}
for i = 1, 5 do
    WHLSN._BASE_REEL_DURATIONS[i] = RC.BASE_REEL_DURATION + (i - 1) * RC.REEL_DURATION_OFFSET
end

-- Expose easing constants for testing
WHLSN._EASING = {
    P1_END = RC.P1_END, P2_END = RC.P2_END,
    P1_OUT_END = RC.P1_OUT_END, P2_OUT_END = RC.P2_OUT_END,
}

---------------------------------------------------------------------------
-- Shared Module State (promoted to WHLSN for cross-file access)
---------------------------------------------------------------------------

WHLSN._wheelState = WHLSN._wheelState or {
    frame           = nil,
    reelFrames      = {},
    reelState       = {},
    summaryCount    = 0,
    currentGroup    = 0,
    isAnimating     = false,
    timer           = nil,
    reelNames       = {},
    soundEnabled    = true,
}

---------------------------------------------------------------------------
-- Composition helpers (each adds one visual layer to a reel frame)
---------------------------------------------------------------------------

local function CreateReelBackground(reel, roleDef)
    local bg = reel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(roleDef.color.r * 0.12, roleDef.color.g * 0.12, roleDef.color.b * 0.12, 0.9)
end

local function CreateReelBorders(reel, roleDef)
    local borders = {}

    local bTop = reel:CreateTexture(nil, "BORDER")
    bTop:SetHeight(1)
    bTop:SetPoint("TOPLEFT", reel, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", reel, "TOPRIGHT", 0, 0)
    bTop:SetColorTexture(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
    borders[#borders + 1] = bTop

    local bBottom = reel:CreateTexture(nil, "BORDER")
    bBottom:SetHeight(1)
    bBottom:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", 0, 0)
    bBottom:SetColorTexture(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
    borders[#borders + 1] = bBottom

    local bLeft = reel:CreateTexture(nil, "BORDER")
    bLeft:SetWidth(1)
    bLeft:SetPoint("TOPLEFT", reel, "TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", 0, 0)
    bLeft:SetColorTexture(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
    borders[#borders + 1] = bLeft

    local bRight = reel:CreateTexture(nil, "BORDER")
    bRight:SetWidth(1)
    bRight:SetPoint("TOPRIGHT", reel, "TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", 0, 0)
    bRight:SetColorTexture(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
    borders[#borders + 1] = bRight

    return borders
end

local function CreateReelGlow(parent, reel, reelWidth)
    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(reelWidth + 8, RC.REEL_HEIGHT + 8)
    glow:SetPoint("CENTER", reel, "CENTER", 0, 0)
    glow:SetColorTexture(RC.GOLD_R, RC.GOLD_G, RC.GOLD_B, 0)
    glow:SetAlpha(0)

    -- Reusable AnimationGroup for smooth glow fade-in
    local glowAG = glow:CreateAnimationGroup()
    local glowFade = glowAG:CreateAnimation("Alpha")
    glowFade:SetFromAlpha(0)
    glowFade:SetToAlpha(1)
    glowFade:SetDuration(RC.GLOW_FADE_DURATION)
    glowFade:SetSmoothing("OUT")
    glowAG:SetToFinalAlpha(true)
    glow.fadeAG = glowAG

    return glow
end

local function CreateReelSlots(reel, reelWidth)
    local inner = CreateFrame("Frame", nil, reel)
    inner:SetPoint("TOPLEFT", reel, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", -1, 1)
    inner:SetClipsChildren(true)

    local slots = {}
    for j = 1, RC.MAX_SLOTS do
        local fs = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", inner, "TOPLEFT", 2, -(j - 1) * RC.ROW_HEIGHT)
        fs:SetSize(reelWidth - 4, RC.ROW_HEIGHT)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        fs:SetText("")
        slots[j] = fs
    end

    return inner, slots
end

local function CreateReelFades(reel, roleDef)
    local bgR, bgG, bgB = roleDef.color.r * 0.12, roleDef.color.g * 0.12, roleDef.color.b * 0.12

    local fadeTop = reel:CreateTexture(nil, "OVERLAY")
    fadeTop:SetPoint("TOPLEFT", reel, "TOPLEFT", 1, -1)
    fadeTop:SetPoint("TOPRIGHT", reel, "TOPRIGHT", -1, -1)
    fadeTop:SetHeight(RC.FADE_HEIGHT)
    fadeTop:SetColorTexture(1, 1, 1, 1)
    fadeTop:SetGradient("VERTICAL",
        CreateColor(bgR, bgG, bgB, 0),
        CreateColor(bgR, bgG, bgB, 0.85))

    local fadeBottom = reel:CreateTexture(nil, "OVERLAY")
    fadeBottom:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", 1, 1)
    fadeBottom:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", -1, 1)
    fadeBottom:SetHeight(RC.FADE_HEIGHT)
    fadeBottom:SetColorTexture(1, 1, 1, 1)
    fadeBottom:SetGradient("VERTICAL",
        CreateColor(bgR, bgG, bgB, 0.85),
        CreateColor(bgR, bgG, bgB, 0))

    return fadeTop, fadeBottom
end

local function CreateReelUtilityIcons(parent, reel)
    local brezIcon = parent:CreateTexture(nil, "OVERLAY")
    brezIcon:SetSize(12, 12)
    brezIcon:SetPoint("TOPRIGHT", reel, "TOPRIGHT", -2, -2)
    brezIcon:SetTexture(WHLSN.BREZ_ICON)
    brezIcon:Hide()

    local lustIcon = parent:CreateTexture(nil, "OVERLAY")
    lustIcon:SetSize(12, 12)
    lustIcon:SetPoint("TOPLEFT", reel, "TOPLEFT", 2, -2)
    lustIcon:SetTexture(WHLSN.LUST_ICON)
    lustIcon:Hide()

    return brezIcon, lustIcon
end

---------------------------------------------------------------------------
-- Coordinator: assemble a complete reel frame from its parts
---------------------------------------------------------------------------

--- Create a single reel frame for a given role.
---@param parent table  parent frame (the reel container)
---@param index number  1-based reel index (1=tank, 2=healer, 3-5=dps)
---@param roleDef table  entry from WHLSN._REEL_ROLES
---@return table  the reel frame
local function CreateReelFrame(parent, index, roleDef)
    local parentWidth = parent:GetWidth()
    local reelWidth = math_floor((parentWidth - RC.REEL_PADDING * (5 + 1)) / 5)
    local xOffset = RC.REEL_PADDING + (index - 1) * (reelWidth + RC.REEL_PADDING)

    local reel = CreateFrame("Frame", nil, parent)
    reel:SetSize(reelWidth, RC.REEL_HEIGHT)
    reel:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, 0)

    CreateReelBackground(reel, roleDef)
    reel.borders = CreateReelBorders(reel, roleDef)
    reel.glow = CreateReelGlow(parent, reel, reelWidth)
    reel.inner, reel.slots = CreateReelSlots(reel, reelWidth)
    reel.fadeTop, reel.fadeBottom = CreateReelFades(reel, roleDef)

    -- Role label FontString above reel
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", reel, "TOP", 0, 2)
    label:SetText(roleDef.label)
    label:SetTextColor(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
    reel.label = label

    reel.brezIcon, reel.lustIcon = CreateReelUtilityIcons(parent, reel)

    return reel
end

-- Expose coordinator so Wheel.lua can call it
WHLSN._CreateReelFrame = CreateReelFrame
