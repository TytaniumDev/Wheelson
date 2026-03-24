---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Wheel View
-- Slot-machine-style animated group reveal
-- Constants and shared state are initialised in ReelFrames.lua (loads first).
---------------------------------------------------------------------------

-- Cache math functions as upvalues for hot-path performance
local math_min   = math.min
local math_max   = math.max

local RC = WHLSN._REEL_CONSTANTS
local ws = WHLSN._wheelState

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
    header:SetTextColor(RC.GOLD_R, RC.GOLD_G, RC.GOLD_B, 1)
    header:SetText("Group 1 of 1")
    frame.header = header

    -- Reel container (holds the 5 reels side by side, vertically centred)
    local reelContainer = CreateFrame("Frame", nil, frame)
    local containerWidth = parent:GetWidth() - 20
    if containerWidth < 200 then containerWidth = 200 end
    reelContainer:SetSize(containerWidth, RC.REEL_HEIGHT)
    reelContainer:SetPoint("CENTER", frame, "CENTER", 0, 10)
    frame.reelContainer = reelContainer

    -- Create 5 reels
    ws.reelFrames = {}
    for i = 1, 5 do
        ws.reelFrames[i] = WHLSN._CreateReelFrame(reelContainer, i, WHLSN._REEL_ROLES[i])
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
    summaryContainer:SetHeight(RC.MAX_SUMMARY_ROWS * RC.SUMMARY_ROW_HEIGHT)
    frame.summaryContainer = summaryContainer

    -- Pre-create summary row FontStrings (fixes FontString accumulation)
    frame.summarySlots = {}
    for i = 1, RC.MAX_SUMMARY_ROWS do
        local fs = summaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("CENTER")
        fs:SetSize(summaryContainer:GetWidth(), RC.SUMMARY_ROW_HEIGHT)
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
                if reel.glow.fadeAG then reel.glow.fadeAG:Stop() end
                reel.glow:SetAlpha(0)
                reel.glow:SetColorTexture(RC.GOLD_R, RC.GOLD_G, RC.GOLD_B, 0)
            end
            for _, border in ipairs(reel.borders or {}) do
                local roleDef = WHLSN._REEL_ROLES[i]
                border:SetColorTexture(roleDef.color.r, roleDef.color.g, roleDef.color.b, 1)
            end
            if reel.brezIcon then reel.brezIcon:Hide() end
            if reel.lustIcon then reel.lustIcon:Hide() end
            for j = 1, RC.MAX_SLOTS do
                reel.slots[j]:SetText("")
                reel.slots[j]:SetTextColor(1, 1, 1, 1)
            end
        end
    end
end

local function ResetSummaryRows()
    if ws.frame and ws.frame.summarySlots then
        for i = 1, RC.MAX_SUMMARY_ROWS do
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
        local roleDef = WHLSN._REEL_ROLES[i]
        local pool = WHLSN.BuildReelPool(players, roleDef.role, nil, {})

        local names = {}
        for _, p in ipairs(pool) do
            names[#names + 1] = p.name
        end

        names = WHLSN.PadReelPool(names, RC.MIN_POOL_SIZE)
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
            local numNames = math_min(#finalNames, RC.MAX_SLOTS)

            ws.reelState[i] = {
                active     = true,
                names      = finalNames,
                numNames   = numNames,
                winner     = winner,
                elapsed    = 0,
                duration   = WHLSN._BASE_REEL_DURATIONS[i] / 1000.0 / GetAnimationSpeed(),
                landed     = false,
                lastRow    = -1,
                lastAlpha  = -1,
            }

            if ws.reelFrames[i] then
                ws.reelFrames[i]:Show()
                for j = 1, RC.MAX_SLOTS do
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
                for j = 1, RC.MAX_SLOTS do
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
-- Multi-Group Flow & Completion
---------------------------------------------------------------------------

--- Forward declarations for inter-calling local functions
local CollapseAndAdvance
local OnFinalGroupComplete

--- Called once all 5 reels for the current group have settled.
function WHLSN._OnAllReelsLanded()
    ws.isAnimating = false

    WHLSN._PlayVictory()

    local groups = WHLSN.session.groups
    local totalGroups = #groups

    local glowDelay = RC.GLOW_DURATION / GetAnimationSpeed()
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
    local function addColored(player)
        if player then
            local cc = player.classToken and WHLSN.CLASS_COLORS[player.classToken]
            if cc then
                parts[#parts + 1] = "|cFF" .. cc.hex .. player.name .. "|r"
            else
                parts[#parts + 1] = player.name
            end
        end
    end

    addColored(group.tank)
    addColored(group.healer)
    for k = 1, 3 do
        addColored(group.dps[k])
    end

    local summaryText = table.concat(parts, " · ")

    -- Write to pre-created summary slot by index
    if ws.frame and ws.frame.summarySlots then
        ws.summaryCount = ws.summaryCount + 1
        local sc = ws.frame.summaryContainer

        -- Position visible summary rows; hide oldest if > MAX_SUMMARY_ROWS
        local visibleStart = math_max(1, ws.summaryCount - RC.MAX_SUMMARY_ROWS + 1)
        for idx = 1, ws.summaryCount do
            -- Map to slot index (circular use of pre-created slots)
            local slotIdx = ((idx - 1) % RC.MAX_SUMMARY_ROWS) + 1
            local slot = ws.frame.summarySlots[slotIdx]
            if idx < visibleStart then
                slot:Hide()
            else
                local rowPos = idx - visibleStart
                if idx == ws.summaryCount then
                    slot:SetText("Group " .. idx .. ": " .. summaryText)
                end
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -rowPos * RC.SUMMARY_ROW_HEIGHT)
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
        ws.frame.collapseFade:SetDuration(RC.COLLAPSE_DURATION / GetAnimationSpeed())
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
    ws.timer = C_Timer.NewTimer(RC.FINAL_PAUSE / GetAnimationSpeed(), function()
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
        if ws.frame.collapseAG then
            ws.frame.collapseAG:Stop()
            ws.frame.collapseAG:SetScript("OnFinished", nil)
        end
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
        if ws.frame.collapseAG then
            ws.frame.collapseAG:Stop()
            ws.frame.collapseAG:SetScript("OnFinished", nil)
        end
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
