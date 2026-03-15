---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Wheel View
-- Slot-machine-style animated group reveal
---------------------------------------------------------------------------

local wheelFrame = nil

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local ROW_HEIGHT        = 20
local VISIBLE_ROWS      = 3
local REEL_HEIGHT       = ROW_HEIGHT * VISIBLE_ROWS
local FADE_HEIGHT       = 16
local REEL_PADDING      = 6

local SUMMARY_ROW_HEIGHT = 18
local MAX_SUMMARY_ROWS   = 4

-- 5 reel definitions: tank, healer, dps x3
local REEL_ROLES = {
    { role = "tank",   label = "Tank",   color = { r = 0.53, g = 0.76, b = 1.0 } },
    { role = "healer", label = "Healer", color = { r = 0.53, g = 1.0,  b = 0.53 } },
    { role = "dps",    label = "DPS",    color = { r = 1.0,  g = 0.4,  b = 0.4 } },
    { role = "dps",    label = "DPS",    color = { r = 1.0,  g = 0.4,  b = 0.4 } },
    { role = "dps",    label = "DPS",    color = { r = 1.0,  g = 0.4,  b = 0.4 } },
}

local GOLD_R = 0.961
local GOLD_G = 0.620
local GOLD_B = 0.043

local BASE_REEL_DURATIONS = { 4000, 4300, 4600, 4900, 5200 }

local GLOW_DURATION     = 1.5
local COLLAPSE_DURATION = 0.5
local FINAL_PAUSE       = 2.0
local MIN_POOL_SIZE     = 8

---------------------------------------------------------------------------
-- Animation State Variables
---------------------------------------------------------------------------

local reelFrames        = {}
local reelState         = {}
local summaryRows       = {}
local currentGroupIndex = 0
local isAnimating       = false
local animTimer         = nil

---------------------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------------------

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
-- Task 3: Reel Frame Scaffolding
---------------------------------------------------------------------------

--- Create a single reel frame for a given role.
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

    -- Dark background tinted with role colour
    local bg = reel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(roleDef.color.r * 0.12, roleDef.color.g * 0.12, roleDef.color.b * 0.12, 0.9)

    -- 4 role-coloured border edge textures (1px each side)
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

    reel.borders = borders

    -- Glow texture (on parent frame, behind reel, gold, initially hidden)
    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(reelWidth + 8, REEL_HEIGHT + 8)
    glow:SetPoint("CENTER", reel, "CENTER", 0, 0)
    glow:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0)
    reel.glow = glow

    -- Inner clip frame holding 15 pre-created FontString name slots
    local inner = CreateFrame("Frame", nil, reel)
    inner:SetPoint("TOPLEFT", reel, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", -1, 1)
    reel.inner = inner

    local slots = {}
    for j = 1, 15 do
        local fs = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", inner, "TOPLEFT", 2, -(j - 1) * ROW_HEIGHT)
        fs:SetSize(reelWidth - 4, ROW_HEIGHT)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        fs:SetText("")
        slots[j] = fs
    end
    reel.slots = slots

    -- Gradient fade overlays — top and bottom
    local fadeTop = reel:CreateTexture(nil, "OVERLAY")
    fadeTop:SetPoint("TOPLEFT", reel, "TOPLEFT", 1, -1)
    fadeTop:SetPoint("TOPRIGHT", reel, "TOPRIGHT", -1, -1)
    fadeTop:SetHeight(FADE_HEIGHT)
    fadeTop:SetColorTexture(1, 1, 1, 1)
    fadeTop:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, 0.85),
        CreateColor(0, 0, 0, 0))
    reel.fadeTop = fadeTop

    local fadeBottom = reel:CreateTexture(nil, "OVERLAY")
    fadeBottom:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", 1, 1)
    fadeBottom:SetPoint("BOTTOMRIGHT", reel, "BOTTOMRIGHT", -1, 1)
    fadeBottom:SetHeight(FADE_HEIGHT)
    fadeBottom:SetColorTexture(1, 1, 1, 1)
    fadeBottom:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, 0),
        CreateColor(0, 0, 0, 0.85))
    reel.fadeBottom = fadeBottom

    -- Gold centre pointer line (1px, positioned at centre slot)
    local pointer = reel:CreateTexture(nil, "OVERLAY")
    pointer:SetHeight(1)
    pointer:SetPoint("LEFT", reel, "LEFT", 1, 0)
    pointer:SetPoint("RIGHT", reel, "RIGHT", -1, 0)
    pointer:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.8)
    reel.pointer = pointer

    -- Role label FontString above reel
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", reel, "TOP", 0, 2)
    label:SetText(roleDef.label)
    label:SetTextColor(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
    reel.label = label

    -- Utility icons: brezIcon and lustIcon (12x12, initially hidden)
    local brezIcon = parent:CreateTexture(nil, "OVERLAY")
    brezIcon:SetSize(12, 12)
    brezIcon:SetPoint("TOPRIGHT", reel, "TOPRIGHT", -2, -2)
    brezIcon:SetTexture("Interface\\Icons\\Spell_Shaman_SpiritWalk")
    brezIcon:Hide()
    reel.brezIcon = brezIcon

    local lustIcon = parent:CreateTexture(nil, "OVERLAY")
    lustIcon:SetSize(12, 12)
    lustIcon:SetPoint("TOPLEFT", reel, "TOPLEFT", 2, -2)
    lustIcon:SetTexture("Interface\\Icons\\Spell_Nature_TimeStop")
    lustIcon:Hide()
    reel.lustIcon = lustIcon

    return reel
end

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

    -- Reel container (holds the 5 reels side by side)
    local reelContainer = CreateFrame("Frame", nil, frame)
    local containerWidth = parent:GetWidth() - 20
    if containerWidth < 200 then containerWidth = 200 end
    reelContainer:SetSize(containerWidth, REEL_HEIGHT)
    reelContainer:SetPoint("TOP", header, "BOTTOM", 0, -24)
    frame.reelContainer = reelContainer

    -- Create 5 reels
    reelFrames = {}
    for i = 1, 5 do
        reelFrames[i] = CreateReelFrame(reelContainer, i, REEL_ROLES[i])
    end

    -- Summary container (scrolling list of previous groups, anchored near bottom)
    local summaryContainer = CreateFrame("Frame", nil, frame)
    summaryContainer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
    summaryContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)
    summaryContainer:SetHeight(MAX_SUMMARY_ROWS * SUMMARY_ROW_HEIGHT)
    frame.summaryContainer = summaryContainer

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
-- Task 3 (continued): SpinForGroup
---------------------------------------------------------------------------

--- Called internally to kick off the spin animation for a given group index.
---@param groupIndex number  1-based index into self.session.groups
local function SpinForGroup(groupIndex)
    currentGroupIndex = groupIndex
    local groups = WHLSN.session.groups
    local totalGroups = #groups
    local group = groups[groupIndex]

    -- Update header text
    if wheelFrame and wheelFrame.header then
        wheelFrame.header:SetText("Group " .. groupIndex .. " of " .. totalGroups)
    end

    -- Build exclude list: all winners from previously displayed groups
    local excludeNames = {}
    for gi = 1, groupIndex - 1 do
        local prevGroup = groups[gi]
        if prevGroup.tank then excludeNames[prevGroup.tank.name] = true end
        if prevGroup.healer then excludeNames[prevGroup.healer.name] = true end
        for _, dp in ipairs(prevGroup.dps) do
            excludeNames[dp.name] = true
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
    reelState = {}

    local players = WHLSN.session.players or {}

    for i = 1, 5 do
        local roleDef = REEL_ROLES[i]
        local winner = winners[i]

        if winner then
            -- Build pool of candidates (BuildReelPool takes winner as a string name)
            local pool = WHLSN.BuildReelPool(players, roleDef.role, winner.name, excludeNames)

            -- Extract names from pool
            local names = {}
            for _, p in ipairs(pool) do
                names[#names + 1] = p.name
            end

            -- Pad to MIN_POOL_SIZE
            names = WHLSN.PadReelPool(names, MIN_POOL_SIZE)

            -- Place winner at index 1 so it lands at the centre slot (j=2)
            -- Remove any existing occurrence of winner.name, then prepend
            local winnerName = winner.name
            local cleanedNames = {}
            for _, n in ipairs(names) do
                if n ~= winnerName then
                    cleanedNames[#cleanedNames + 1] = n
                end
            end
            -- Insert winner at front
            local finalNames = { winnerName }
            for _, n in ipairs(cleanedNames) do
                finalNames[#finalNames + 1] = n
            end
            -- Re-pad in case we ended up short after removing duplicates
            if #finalNames < MIN_POOL_SIZE then
                finalNames = WHLSN.PadReelPool(finalNames, MIN_POOL_SIZE)
                -- Winner must stay at index 1
                finalNames[1] = winnerName
            end

            reelState[i] = {
                active     = true,
                names      = finalNames,
                winner     = winner,       -- WHLSNPlayer object (for HasBrez/HasLust)
                elapsed    = 0,
                duration   = BASE_REEL_DURATIONS[i] / 1000.0 / GetAnimationSpeed(),
                landed     = false,
                lastCenter = -1,           -- for tick sound tracking
            }

            -- Show reel
            if reelFrames[i] then
                reelFrames[i]:Show()
                -- Populate slots with initial names
                for j = 1, 15 do
                    local nameIdx = ((j - 1) % #finalNames) + 1
                    reelFrames[i].slots[j]:SetText(finalNames[nameIdx])
                    reelFrames[i].slots[j]:SetTextColor(1, 1, 1, 1)
                    reelFrames[i].slots[j]:SetAlpha(1)
                end
            end
        else
            -- Inactive reel: show "(none)" in dim text
            reelState[i] = { active = false, landed = true }
            if reelFrames[i] then
                reelFrames[i]:Show()
                for j = 1, 15 do
                    local text = (j == 2) and "(none)" or ""
                    reelFrames[i].slots[j]:SetText(text)
                    reelFrames[i].slots[j]:SetTextColor(0.5, 0.5, 0.5, 0.7)
                end
            end
        end
    end

    -- Start animations
    isAnimating = true
    WHLSN._StartReelAnimations()
end

---------------------------------------------------------------------------
-- Task 4: Reel Scroll Animation
---------------------------------------------------------------------------

--- Forward declaration for the OnUpdate handler; assigned below.
local OnUpdateHandler

--- Calculate scroll metrics for a reel.
---@param state table  reelState entry
---@return number numCycles, number listHeight, number winnerOffset, number totalScroll
local function CalcScrollMetrics(state)
    local numCycles  = math.random(8, 11)
    local listHeight = #state.names * ROW_HEIGHT
    -- winner is at index 1; centre slot is visual row j=2 (0-indexed offset = 1*ROW_HEIGHT)
    local winnerOffset = (#state.names - 1) * ROW_HEIGHT
    local totalScroll  = numCycles * listHeight + winnerOffset
    return numCycles, listHeight, winnerOffset, totalScroll
end

--- Start the scroll animation for all active reels.
function WHLSN._StartReelAnimations()
    if ShouldPlaySounds() then
        PlaySound(SOUNDKIT.IG_ABILITY_OPEN or 841, "SFX")
    end

    -- Pre-calculate scroll metrics for each active reel
    for i = 1, 5 do
        local state = reelState[i]
        if state and state.active then
            local _, listHeight, _, totalScroll = CalcScrollMetrics(state)
            state.listHeight  = listHeight
            state.totalScroll = totalScroll
            state.elapsed     = 0
        end
    end

    -- Set a single shared OnUpdate handler on wheelFrame
    if wheelFrame then
        wheelFrame:SetScript("OnUpdate", OnUpdateHandler)
    end
end

--- The shared per-frame update handler.
---@param _ table  frame (unused)
---@param dt number  seconds since last frame
OnUpdateHandler = function(_, dt)
    if not isAnimating then return end
    local allLanded = true

    for i = 1, 5 do
        local state = reelState[i]
        if state and state.active and not state.landed then
            allLanded = false

            state.elapsed = state.elapsed + dt
            local t = state.elapsed / state.duration
            if t > 1 then t = 1 end

            local progress     = WHLSN.SlotEasing(t)
            local scrollOffset = progress * state.totalScroll
            local listHeight   = state.listHeight
            local numNames     = #state.names

            -- yOffset within one list cycle; baseSlot = which name is at top
            local yOffset  = scrollOffset % listHeight
            local baseSlot = math.floor(yOffset / ROW_HEIGHT) -- 0-indexed name index
            local subPixel = -(yOffset % ROW_HEIGHT)          -- fractional pixel offset

            -- Motion-blur alpha based on speed (fast = dim, slow = clear)
            -- speed ∈ [0,1] where 1 is max speed (linear phase)
            local speed = 0
            if t > 0 and t < 1 then
                local P2_END = 0.625
                local P3_END = 0.925
                if t >= 0.0375 and t < P2_END then
                    speed = 1.0
                elseif t < 0.0375 then
                    speed = t / 0.0375
                elseif t < P3_END then
                    speed = 1.0 - (t - P2_END) / (P3_END - P2_END)
                end
            end
            local slotAlpha = 1.0 - speed * 0.5  -- 0.5 at full speed, 1.0 at rest

            -- Reposition each FontString slot
            local reel = reelFrames[i]
            if reel and reel.slots then
                for j = 1, 15 do
                    local nameIdx = ((baseSlot + j - 1) % numNames) + 1
                    local yPos    = -(j - 1) * ROW_HEIGHT + subPixel
                    reel.slots[j]:ClearAllPoints()
                    reel.slots[j]:SetPoint("TOPLEFT", reel.inner, "TOPLEFT", 2, yPos)
                    reel.slots[j]:SetText(state.names[nameIdx])
                    reel.slots[j]:SetTextColor(1, 1, 1, slotAlpha)
                end

                -- Tick sound: detect when a new name crosses the centre line
                local centerName = ((baseSlot + 1) % numNames) + 1  -- slot j=2 nameIdx
                if centerName ~= state.lastCenter and ShouldPlaySounds() and speed > 0.1 then
                    PlaySound(1115, "SFX")  -- generic UI tick
                    state.lastCenter = centerName
                end
            end

            -- When t >= 1: snap to final position and highlight winner
            if t >= 1 then
                state.landed = true

                if reel and reel.slots then
                    -- Snap: winner (names[1]) should be at slot j=2 (centre row)
                    for j = 1, 15 do
                        local nameIdx = ((j - 1) % numNames) + 1  -- j=1 → names[1]=winner
                        reel.slots[j]:ClearAllPoints()
                        reel.slots[j]:SetPoint("TOPLEFT", reel.inner, "TOPLEFT", 2, -(j - 1) * ROW_HEIGHT)
                        reel.slots[j]:SetText(state.names[nameIdx])
                        if j == 1 then
                            -- Winner slot: gold highlight
                            reel.slots[j]:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
                        else
                            reel.slots[j]:SetTextColor(0.7, 0.7, 0.7, 0.8)
                        end
                        reel.slots[j]:SetAlpha(1)
                    end

                    -- Gold glow on reel borders
                    if reel.glow then
                        reel.glow:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.35)
                    end
                    for _, border in ipairs(reel.borders or {}) do
                        border:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
                    end

                    -- Utility icons
                    local winner = state.winner
                    if winner then
                        if winner:HasBrez() and reel.brezIcon then
                            reel.brezIcon:Show()
                        end
                        if winner:HasLust() and reel.lustIcon then
                            reel.lustIcon:Show()
                        end
                    end

                    -- Landing sound
                    if ShouldPlaySounds() then
                        PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT or 879, "SFX")
                    end
                end
            end
        end
    end

    -- Check if all active reels have landed
    if allLanded then
        local anyActive = false
        for i = 1, 5 do
            if reelState[i] and reelState[i].active then
                anyActive = true
                break
            end
        end
        if anyActive then
            -- Clear the OnUpdate handler
            if wheelFrame then
                wheelFrame:SetScript("OnUpdate", nil)
            end
            WHLSN._OnAllReelsLanded()
        end
    end
end

---------------------------------------------------------------------------
-- Task 5: Multi-Group Flow & Completion
---------------------------------------------------------------------------

--- Forward declarations for inter-calling local functions
local CollapseAndAdvance
local OnFinalGroupComplete

--- Called once all 5 reels for the current group have settled.
function WHLSN._OnAllReelsLanded()
    isAnimating = false

    if ShouldPlaySounds() then
        PlaySound(SOUNDKIT.RAID_WARNING or 8959, "SFX")
    end

    local groups = WHLSN.session.groups
    local totalGroups = #groups

    if currentGroupIndex < totalGroups then
        -- More groups to show: wait GLOW_DURATION then collapse and advance
        animTimer = C_Timer.NewTimer(GLOW_DURATION, function()
            animTimer = nil
            CollapseAndAdvance()
        end)
    else
        -- Last group
        animTimer = C_Timer.NewTimer(GLOW_DURATION, function()
            animTimer = nil
            OnFinalGroupComplete()
        end)
    end
end

--- Collapse the current reels into a summary row and spin for the next group.
CollapseAndAdvance = function()
    local groups = WHLSN.session.groups
    local group  = groups[currentGroupIndex]

    -- Build summary text with role-coloured names joined by " · "
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

    -- Create summary FontString row in summaryContainer
    if wheelFrame and wheelFrame.summaryContainer then
        local sc  = wheelFrame.summaryContainer
        local row = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetJustifyH("CENTER")
        row:SetSize(sc:GetWidth(), SUMMARY_ROW_HEIGHT)
        row:SetText("Group " .. currentGroupIndex .. ": " .. summaryText)

        summaryRows[#summaryRows + 1] = row

        -- Position visible summary rows; hide oldest if > MAX_SUMMARY_ROWS
        local visibleStart = math.max(1, #summaryRows - MAX_SUMMARY_ROWS + 1)
        for idx, r in ipairs(summaryRows) do
            if idx < visibleStart then
                r:Hide()
            else
                local rowPos = idx - visibleStart  -- 0-indexed from top
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -rowPos * SUMMARY_ROW_HEIGHT)
                r:Show()
            end
        end
    end

    -- Fade out the reel container using AnimationGroup
    local container = wheelFrame and wheelFrame.reelContainer
    if container then
        local ag = container:CreateAnimationGroup()
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(COLLAPSE_DURATION)
        fade:SetSmoothing("OUT")
        ag:SetToFinalAlpha(true)
        ag:SetScript("OnFinished", function()
            -- Reset reel visuals for the next spin
            container:SetAlpha(1)
            for i = 1, 5 do
                local reel = reelFrames[i]
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
                    for j = 1, 15 do
                        reel.slots[j]:SetText("")
                        reel.slots[j]:SetTextColor(1, 1, 1, 1)
                    end
                end
            end

            -- Advance to next group
            SpinForGroup(currentGroupIndex + 1)
        end)
        ag:Play()
    else
        -- No container to fade; advance directly
        SpinForGroup(currentGroupIndex + 1)
    end
end

--- Called after the last group's glow period expires.
OnFinalGroupComplete = function()
    animTimer = C_Timer.NewTimer(FINAL_PAUSE, function()
        animTimer = nil
        WHLSN:OnWheelComplete()
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Hide the wheel view and cancel any pending animation timers.
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

--- Show the wheel view inside the given content frame.
---@param parent table
function WHLSN:ShowWheelView(parent)
    -- Reset animation state
    reelFrames        = {}
    reelState         = {}
    summaryRows       = {}
    currentGroupIndex = 0
    isAnimating       = false
    if animTimer then
        animTimer:Cancel()
        animTimer = nil
    end

    -- Create or recreate the wheel frame
    if wheelFrame then
        wheelFrame:Hide()
        wheelFrame = nil
    end
    wheelFrame = CreateWheelFrame(parent)
    wheelFrame:Show()

    -- Start with group 1
    SpinForGroup(1)
end

--- Update the wheel view (no-op; animation is self-driven).
function WHLSN:UpdateWheelView()
end

--- Skip remaining animation and jump straight to completion.
function WHLSN:SkipWheelAnimation()
    if animTimer then
        animTimer:Cancel()
        animTimer = nil
    end
    if wheelFrame then
        wheelFrame:SetScript("OnUpdate", nil)
    end
    isAnimating = false
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
