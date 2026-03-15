---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Wheel View
-- Slot-machine-style animated group reveal
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local ROW_HEIGHT        = 20
local VISIBLE_ROWS      = 3
local REEL_HEIGHT       = ROW_HEIGHT * VISIBLE_ROWS
local FADE_HEIGHT       = 16
local MAX_SLOTS         = 15
local REEL_PADDING      = 6

local SUMMARY_ROW_HEIGHT = 18
local MAX_SUMMARY_ROWS   = 4

-- 5 reel definitions: tank, healer, dps x3
local REEL_ROLES = {
    { role = "tank",   label = "TANK",   color = { r = 0.231, g = 0.510, b = 0.961 } },
    { role = "healer", label = "HEALER", color = { r = 0.133, g = 0.773, b = 0.369 } },
    { role = "dps",    label = "DPS 1",  color = { r = 0.937, g = 0.267, b = 0.267 } },
    { role = "dps",    label = "DPS 2",  color = { r = 0.937, g = 0.267, b = 0.267 } },
    { role = "dps",    label = "DPS 3",  color = { r = 0.937, g = 0.267, b = 0.267 } },
}

local GOLD_R = 0.961
local GOLD_G = 0.620
local GOLD_B = 0.043

local BASE_REEL_DURATION = 3000  -- ms, first reel spin time
local REEL_DURATION_OFFSET = 300 -- ms, stagger between successive reels
local BASE_REEL_DURATIONS = {}
for i = 1, 5 do
    BASE_REEL_DURATIONS[i] = BASE_REEL_DURATION + (i - 1) * REEL_DURATION_OFFSET
end

local GLOW_DURATION     = 1.5
local COLLAPSE_DURATION = 0.5
local FINAL_PAUSE       = 2.0
local MIN_POOL_SIZE     = 5
local TARGET_SPEED      = 500   -- px/s during linear phase (uniform across all reels)
local MIN_SPIN_CYCLES   = 1     -- minimum full list cycles for visual spin effect

-- Easing phase boundaries (as fractions of total reel duration)
local P1_END = 0.03     -- end of ease-in
local P2_END = 0.45     -- end of full speed

-- Easing output ranges (fraction of total scroll at each phase boundary)
local P1_OUT_END = 0.01
local P2_OUT_END = 0.60

-- Expose easing constants for testing
WHLSN._EASING = { P1_END = P1_END, P2_END = P2_END, P1_OUT_END = P1_OUT_END, P2_OUT_END = P2_OUT_END }

---------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------

local ws = {
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
-- Helper Functions
---------------------------------------------------------------------------

local function GetAnimationSpeed()
    if WHLSN.db and WHLSN.db.profile then
        return WHLSN.db.profile.animationSpeed or 1.0
    end
    return 1.0
end

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

local TICK_THROTTLE = 0.15    -- seconds; at most one tick sound per 150ms across all reels
local lastTickTime  = 0

local function PlayTick()
    if not ws.soundEnabled then return end
    local now = GetTime()
    if now - lastTickTime < TICK_THROTTLE then return end
    lastTickTime = now
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

    local P3_RANGE = 1.0 - P2_OUT_END

    if t < P1_END then
        local p = t / P1_END
        local eased = p * p * p * p
        return eased * P1_OUT_END

    elseif t < P2_END then
        local p = (t - P1_END) / (P2_END - P1_END)
        return P1_OUT_END + p * (P2_OUT_END - P1_OUT_END)

    else
        local p = (t - P2_END) / (1 - P2_END)
        local eased = 1.0 + (2 ^ (-10 * p)) * math.sin((10 * p - 0.75) * 2 * math.pi / 3)
        return P2_OUT_END + eased * P3_RANGE
    end
end

---------------------------------------------------------------------------
-- Reel Frame Creation (decomposed into composition functions)
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
    glow:SetSize(reelWidth + 8, REEL_HEIGHT + 8)
    glow:SetPoint("CENTER", reel, "CENTER", 0, 0)
    glow:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0)
    return glow
end

local function CreateReelSlots(reel, reelWidth)
    local inner = CreateFrame("Frame", nil, reel)
    inner:SetPoint("TOPLEFT", reel, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", -1, 1)
    inner:SetClipsChildren(true)

    local slots = {}
    for j = 1, MAX_SLOTS do
        local fs = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", inner, "TOPLEFT", 2, -(j - 1) * ROW_HEIGHT)
        fs:SetSize(reelWidth - 4, ROW_HEIGHT)
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
    fadeTop:SetHeight(FADE_HEIGHT)
    fadeTop:SetColorTexture(1, 1, 1, 1)
    fadeTop:SetGradient("VERTICAL",
        CreateColor(bgR, bgG, bgB, 0),
        CreateColor(bgR, bgG, bgB, 0.85))

    local fadeBottom = reel:CreateTexture(nil, "OVERLAY")
    fadeBottom:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", 1, 1)
    fadeBottom:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", -1, 1)
    fadeBottom:SetHeight(FADE_HEIGHT)
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

--- Create a single reel frame for a given role (coordinator).
---@param parent table  parent frame (the reel container)
---@param index number  1-based reel index (1=tank, 2=healer, 3-5=dps)
---@param roleDef table  entry from REEL_ROLES
---@return table  the reel frame
local function CreateReelFrame(parent, index, roleDef)
    local parentWidth = parent:GetWidth()
    local reelWidth = math.floor((parentWidth - REEL_PADDING * (5 + 1)) / 5)
    local xOffset = REEL_PADDING + (index - 1) * (reelWidth + REEL_PADDING)

    local reel = CreateFrame("Frame", nil, parent)
    reel:SetSize(reelWidth, REEL_HEIGHT)
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

---------------------------------------------------------------------------
-- Wheel Frame Creation
---------------------------------------------------------------------------

--- Create the wheel frame and all child UI elements.
---@param parent table  parent content frame
---@return table  the wheel frame
local function CreateWheelFrame(parent)
    local frame = CreateFrame("Frame", "WHLSNWheelFrame", parent)
    frame:SetAllPoints()

    -- Gold group header text
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", frame, "TOP", 0, -8)
    header:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
    header:SetText("Group 1 of 1")
    frame.header = header

    -- Reel container (holds the 5 reels side by side, vertically centred)
    local reelContainer = CreateFrame("Frame", nil, frame)
    local containerWidth = parent:GetWidth() - 20
    if containerWidth < 200 then containerWidth = 200 end
    reelContainer:SetSize(containerWidth, REEL_HEIGHT)
    reelContainer:SetPoint("CENTER", frame, "CENTER", 0, 10)
    frame.reelContainer = reelContainer

    -- Create 5 reels
    ws.reelFrames = {}
    for i = 1, 5 do
        ws.reelFrames[i] = CreateReelFrame(reelContainer, i, REEL_ROLES[i])
    end

    -- Reusable AnimationGroup for collapse transitions (fixes leak)
    local collapseAG = reelContainer:CreateAnimationGroup()
    local collapseFade = collapseAG:CreateAnimation("Alpha")
    collapseFade:SetFromAlpha(1)
    collapseFade:SetToAlpha(0)
    collapseFade:SetSmoothing("OUT")
    collapseAG:SetToFinalAlpha(true)
    frame.collapseAG = collapseAG
    frame.collapseFade = collapseFade

    -- Summary container (scrolling list of previous groups, anchored near bottom)
    local summaryContainer = CreateFrame("Frame", nil, frame)
    summaryContainer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
    summaryContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)
    summaryContainer:SetHeight(MAX_SUMMARY_ROWS * SUMMARY_ROW_HEIGHT)
    frame.summaryContainer = summaryContainer

    -- Pre-create summary row FontStrings (fixes FontString accumulation)
    frame.summarySlots = {}
    for i = 1, MAX_SUMMARY_ROWS do
        local fs = summaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("CENTER")
        fs:SetSize(summaryContainer:GetWidth(), SUMMARY_ROW_HEIGHT)
        fs:Hide()
        frame.summarySlots[i] = fs
    end

    -- Skip button
    local skipBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    skipBtn:SetSize(80, 22)
    skipBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    skipBtn:SetText("Skip")
    skipBtn:SetScript("OnClick", function()
        WHLSN:SkipWheelAnimation()
    end)
    frame.skipBtn = skipBtn

    return frame
end

---------------------------------------------------------------------------
-- Reel Visual Reset Helpers
---------------------------------------------------------------------------

local function ResetReelVisuals()
    for i = 1, 5 do
        local reel = ws.reelFrames[i]
        if reel then
            if reel.glow then
                reel.glow:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0)
            end
            for _, border in ipairs(reel.borders or {}) do
                local roleDef = REEL_ROLES[i]
                border:SetColorTexture(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
            end
            if reel.brezIcon then reel.brezIcon:Hide() end
            if reel.lustIcon then reel.lustIcon:Hide() end
            for j = 1, MAX_SLOTS do
                reel.slots[j]:SetText("")
                reel.slots[j]:SetTextColor(1, 1, 1, 1)
            end
        end
    end
end

local function ResetSummaryRows()
    if ws.frame and ws.frame.summarySlots then
        for i = 1, MAX_SUMMARY_ROWS do
            ws.frame.summarySlots[i]:SetText("")
            ws.frame.summarySlots[i]:Hide()
        end
    end
    ws.summaryCount = 0
end

---------------------------------------------------------------------------
-- SpinForGroup
---------------------------------------------------------------------------

--- Build the consistent name lists for all 5 reels (called once per session spin).
local function BuildReelNameLists()
    local players = WHLSN.session.players or {}
    ws.reelNames = {}

    for i = 1, 5 do
        local roleDef = REEL_ROLES[i]
        local pool = WHLSN.BuildReelPool(players, roleDef.role, nil, {})

        local names = {}
        for _, p in ipairs(pool) do
            names[#names + 1] = p.name
        end

        names = WHLSN.PadReelPool(names, MIN_POOL_SIZE)
        ws.reelNames[i] = names
    end
end

--- Prepare the reel name list for a specific group spin.
---@param baseNames string[]
---@param winner WHLSNPlayer|nil
---@return string[] names with winner at index 1
function WHLSN._PrepareReelNames(baseNames, winner)
    if not winner or not baseNames or #baseNames == 0 then return baseNames end

    local winnerName = winner.name

    local winnerPos = nil
    for idx, n in ipairs(baseNames) do
        if n == winnerName then
            winnerPos = idx
            break
        end
    end

    if not winnerPos then
        local names = { winnerName }
        for _, n in ipairs(baseNames) do
            names[#names + 1] = n
        end
        return names
    end

    local names = {}
    for i = winnerPos, #baseNames do
        names[#names + 1] = baseNames[i]
    end
    for i = 1, winnerPos - 1 do
        names[#names + 1] = baseNames[i]
    end
    return names
end

local function SpinForGroup(groupIndex)
    ws.currentGroup = groupIndex
    local groups = WHLSN.session.groups
    local totalGroups = #groups
    local group = groups[groupIndex]

    -- Update header text
    if ws.frame and ws.frame.header then
        if totalGroups == 1 then
            ws.frame.header:SetText("Group 1")
        else
            ws.frame.header:SetText("Group " .. groupIndex .. " of " .. totalGroups)
        end
    end

    -- Get the 5 winners for this group: tank, healer, dps[1], dps[2], dps[3]
    local winners = {
        group.tank,
        group.healer,
        group.dps[1],
        group.dps[2],
        group.dps[3],
    }

    -- Initialise reelState
    ws.reelState = {}

    for i = 1, 5 do
        local winner = winners[i]

        if winner then
            local finalNames = WHLSN._PrepareReelNames(ws.reelNames[i], winner)
            local numNames = math.min(#finalNames, MAX_SLOTS)

            ws.reelState[i] = {
                active     = true,
                names      = finalNames,
                numNames   = numNames,
                winner     = winner,
                elapsed    = 0,
                duration   = BASE_REEL_DURATIONS[i] / 1000.0 / GetAnimationSpeed(),
                landed     = false,
                lastRow    = -1,
            }

            if ws.reelFrames[i] then
                ws.reelFrames[i]:Show()
                for j = 1, MAX_SLOTS do
                    if j <= numNames then
                        ws.reelFrames[i].slots[j]:SetText(finalNames[j])
                        ws.reelFrames[i].slots[j]:SetTextColor(1, 1, 1, 0.5)
                        ws.reelFrames[i].slots[j]:SetAlpha(1)
                    else
                        ws.reelFrames[i].slots[j]:SetText("")
                        ws.reelFrames[i].slots[j]:SetTextColor(1, 1, 1, 0)
                    end
                end
            end
        else
            ws.reelState[i] = { active = false, landed = true }
            if ws.reelFrames[i] then
                ws.reelFrames[i]:Show()
                for j = 1, MAX_SLOTS do
                    local text = (j == 2) and "(none)" or ""
                    ws.reelFrames[i].slots[j]:SetText(text)
                    ws.reelFrames[i].slots[j]:SetTextColor(0.5, 0.5, 0.5, 0.7)
                end
            end
        end
    end

    -- Start animations
    ws.isAnimating = true
    WHLSN._StartReelAnimations()
end

---------------------------------------------------------------------------
-- Reel Scroll Animation
---------------------------------------------------------------------------

--- Forward declaration for the OnUpdate handler; assigned below.
local OnUpdateHandler

--- Calculate scroll metrics for a reel, targeting a uniform linear-phase speed.
---@param state table  reelState entry (needs .names and .duration)
---@return number listHeight, number scrollBase, number scrollDistance
function WHLSN._CalcScrollMetrics(state)
    local numNames = state.numNames or math.min(#state.names, MAX_SLOTS)
    local listHeight = numNames * ROW_HEIGHT

    local linearTimeFrac   = P2_END - P1_END
    local linearScrollFrac = P2_OUT_END - P1_OUT_END
    local scrollDistance = TARGET_SPEED * linearTimeFrac * state.duration / linearScrollFrac

    local totalScroll = math.max(
        MIN_SPIN_CYCLES * listHeight,
        math.ceil(scrollDistance / listHeight) * listHeight
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
        ws.frame:SetScript("OnUpdate", OnUpdateHandler)
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
        if t >= P1_END and t < P2_END then
            speed = 1.0
        elseif t < P1_END then
            speed = t / P1_END
        else
            speed = 1.0 - (t - P2_END) / (1 - P2_END)
        end
    end
    local slotAlpha = 1.0 - speed * 0.5

    -- Only update slots whose positions are within or near the visible viewport
    local reel = ws.reelFrames[i]
    if reel and reel.slots then
        for j = 1, numNames do
            local rawY = (-scrollOffset - (j - 1) * ROW_HEIGHT) % listHeight - ROW_HEIGHT
            if rawY > ROW_HEIGHT then
                rawY = rawY - listHeight
            end
            -- Only reposition slots near the visible area (viewport is 0 to -REEL_HEIGHT)
            if rawY > -REEL_HEIGHT - ROW_HEIGHT and rawY < ROW_HEIGHT * 2 then
                reel.slots[j]:ClearAllPoints()
                reel.slots[j]:SetPoint("TOPLEFT", reel.inner, "TOPLEFT", 2, rawY)
                reel.slots[j]:SetTextColor(1, 1, 1, slotAlpha)
            end
        end

        -- Tick sound: detect when a new name scrolls past the centre row
        local currentRow = math.floor(scrollOffset / ROW_HEIGHT)
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
            reel.slots[j]:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
        else
            reel.slots[j]:SetTextColor(0.7, 0.7, 0.7, 0.8)
        end
        reel.slots[j]:SetAlpha(1)
    end

    if reel.glow then
        reel.glow:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.35)
    end
    for _, border in ipairs(reel.borders or {}) do
        border:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
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
    local anyActive = false
    for i = 1, 5 do
        if ws.reelState[i] and ws.reelState[i].active then
            anyActive = true
            break
        end
    end
    if anyActive then
        if ws.frame then
            ws.frame:SetScript("OnUpdate", nil)
        end
        WHLSN._OnAllReelsLanded()
    else
        if ws.frame then
            ws.frame:SetScript("OnUpdate", nil)
        end
        ws.isAnimating = false
    end
end

--- The shared per-frame update handler.
---@param _ table  frame (unused)
---@param dt number  seconds since last frame
OnUpdateHandler = function(_, dt)
    if not ws.isAnimating then return end
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

---------------------------------------------------------------------------
-- Multi-Group Flow & Completion
---------------------------------------------------------------------------

--- Forward declarations for inter-calling local functions
local CollapseAndAdvance
local OnFinalGroupComplete

--- Called once all 5 reels for the current group have settled.
function WHLSN._OnAllReelsLanded()
    ws.isAnimating = false

    PlayVictory()

    local groups = WHLSN.session.groups
    local totalGroups = #groups

    local glowDelay = GLOW_DURATION / GetAnimationSpeed()
    if ws.currentGroup < totalGroups then
        ws.timer = C_Timer.NewTimer(glowDelay, function()
            ws.timer = nil
            CollapseAndAdvance()
        end)
    else
        ws.timer = C_Timer.NewTimer(glowDelay, function()
            ws.timer = nil
            OnFinalGroupComplete()
        end)
    end
end

--- Add a summary row for the given group index using pre-created FontStrings.
local function AddSummaryRow(groupIndex)
    local groups = WHLSN.session.groups
    local group  = groups[groupIndex]

    local parts = {}
    local function addColored(player, colorR, colorG, colorB)
        if player then
            parts[#parts + 1] = "|cff"
                .. string.format("%02x%02x%02x",
                    math.floor(colorR * 255),
                    math.floor(colorG * 255),
                    math.floor(colorB * 255))
                .. player.name .. "|r"
        end
    end

    addColored(group.tank,   REEL_ROLES[1].color.r, REEL_ROLES[1].color.g, REEL_ROLES[1].color.b)
    addColored(group.healer, REEL_ROLES[2].color.r, REEL_ROLES[2].color.g, REEL_ROLES[2].color.b)
    for k = 1, 3 do
        addColored(group.dps[k], REEL_ROLES[3].color.r, REEL_ROLES[3].color.g, REEL_ROLES[3].color.b)
    end

    local summaryText = table.concat(parts, " · ")

    -- Write to pre-created summary slot by index
    if ws.frame and ws.frame.summarySlots then
        ws.summaryCount = ws.summaryCount + 1
        local sc = ws.frame.summaryContainer

        -- Position visible summary rows; hide oldest if > MAX_SUMMARY_ROWS
        local visibleStart = math.max(1, ws.summaryCount - MAX_SUMMARY_ROWS + 1)
        for idx = 1, ws.summaryCount do
            -- Map to slot index (circular use of pre-created slots)
            local slotIdx = ((idx - 1) % MAX_SUMMARY_ROWS) + 1
            local slot = ws.frame.summarySlots[slotIdx]
            if idx < visibleStart then
                slot:Hide()
            else
                local rowPos = idx - visibleStart
                if idx == ws.summaryCount then
                    slot:SetText("Group " .. idx .. ": " .. summaryText)
                end
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -rowPos * SUMMARY_ROW_HEIGHT)
                slot:Show()
            end
        end
    end
end

--- Collapse the current reels into a summary row and spin for the next group.
CollapseAndAdvance = function()
    AddSummaryRow(ws.currentGroup)

    -- Reuse the pre-created AnimationGroup for collapse fade
    local container = ws.frame and ws.frame.reelContainer
    if container and ws.frame.collapseAG then
        local ag = ws.frame.collapseAG
        ag:Stop()
        ws.frame.collapseFade:SetDuration(COLLAPSE_DURATION / GetAnimationSpeed())
        ag:SetScript("OnFinished", function()
            container:SetAlpha(1)
            ResetReelVisuals()
            SpinForGroup(ws.currentGroup + 1)
        end)
        ag:Play()
    else
        SpinForGroup(ws.currentGroup + 1)
    end
end

--- Called after the last group's glow period expires.
OnFinalGroupComplete = function()
    AddSummaryRow(ws.currentGroup)
    ws.timer = C_Timer.NewTimer(FINAL_PAUSE / GetAnimationSpeed(), function()
        ws.timer = nil
        WHLSN:OnWheelComplete()
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Hide the wheel view and cancel any pending animation timers.
function WHLSN:HideWheelView()
    if ws.timer then
        ws.timer:Cancel()
        ws.timer = nil
    end
    if ws.frame then
        ws.frame:SetScript("OnUpdate", nil)
        ws.frame:Hide()
    end
    ws.isAnimating = false
end

--- Show the wheel view inside the given content frame.
---@param parent table
function WHLSN:ShowWheelView(parent)
    -- Cancel any pending timers from a previous spin
    if ws.timer then
        ws.timer:Cancel()
        ws.timer = nil
    end
    ws.isAnimating = false

    -- Create frame on first call; reuse on subsequent calls
    if not ws.frame then
        ws.frame = CreateWheelFrame(parent)
    end
    ws.frame:SetParent(parent)
    ws.frame:SetAllPoints()

    -- Reset visual state for new spin
    ws.reelState  = {}
    ws.currentGroup = 0
    ResetReelVisuals()
    ResetSummaryRows()

    ws.frame:Show()

    -- Build consistent reel name lists once for all groups
    BuildReelNameLists()

    -- Start with group 1
    SpinForGroup(1)
end

--- Update the wheel view (no-op; animation is self-driven).
function WHLSN:UpdateWheelView()
end

--- Skip remaining animation and jump straight to completion.
function WHLSN:SkipWheelAnimation()
    if ws.timer then
        ws.timer:Cancel()
        ws.timer = nil
    end
    if ws.frame then
        ws.frame:SetScript("OnUpdate", nil)
    end
    ws.isAnimating = false
    self:OnWheelComplete()
end

--- Called when all reels have settled on the final group.
function WHLSN:OnWheelComplete()
    -- Guard: only complete session if not already completed
    if self.session and self.session.status ~= self.Status.COMPLETED then
        self:CompleteSession()
    end
    -- Auto-navigate to results view
    self:ResetView()
    self:UpdateUI()
end
