# Minimap Icon & Debug Panel Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimap icon (left-click opens main window, right-click opens debug panel) and a 3-tab debug panel showing addon state, comm log, and WoW API results.

**Architecture:** Single new file `src/UI/DebugPanel.lua` contains all debug panel logic. Minor modifications to `Core.lua` for minimap icon init, stub, and slash command. The debug panel hooks existing methods via `hooksecurefunc` to capture comm traffic without modifying Core.lua's message handling.

**Tech Stack:** Lua 5.1, WoW API, LibDataBroker-1.1, LibDBIcon-1.0, AceAddon-3.0

**Testing note:** This feature is entirely UI code (WoW frame creation, rendering). Per project convention, only non-UI logic is tested with busted. No new test files are needed.

---

## Chunk 1: Infrastructure

### Task 1: Update .luacheckrc

**Files:**
- Modify: `.luacheckrc:22-80` (read_globals section)

- [ ] **Step 1: Add missing WoW API globals**

Add these to the `read_globals` table in `.luacheckrc`, in alphabetical order among the existing WoW API entries:

```lua
    "GetNormalizedRealmName",
```

after `GetGuildRosterInfo`, and:

```lua
    "UnitLevel",
```

after `UnitIsGroupLeader`, and:

```lua
    "hooksecurefunc",
```

in the WoW API functions section, alphabetically between `GetSpecializationInfo` and `InviteUnit`.

- [ ] **Step 2: Run luacheck to verify no regressions**

Run: `luacheck src/ tests/`
Expected: Same results as before (no new warnings from config change)

- [ ] **Step 3: Commit**

```bash
git add .luacheckrc
git commit -m "chore: add missing WoW API globals to luacheckrc"
```

---

### Task 2: Add minimap icon initialization and debug stub to Core.lua

**Files:**
- Modify: `src/Core.lua:8-43` (OnInitialize), `src/Core.lua:62-90` (slash commands), `src/Core.lua:567-578` (UI stubs)

- [ ] **Step 1: Add ToggleDebugFrame stub at end of Core.lua**

Add after the existing `UpdateUI` stub (line 578):

```lua
function MPW:ToggleDebugFrame()
    -- Overridden by UI/DebugPanel.lua
end
```

- [ ] **Step 2: Add minimap icon initialization in OnInitialize**

Add after `self:RegisterComm(self.COMM_PREFIX)` (line 35), before the session restore block:

```lua
    -- Minimap icon via LibDataBroker + LibDBIcon
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")

    local launcher = LDB:NewDataObject("Wheelson", {
        type = "launcher",
        icon = "Interface\\AddOns\\Wheelson\\textures\\minimap-icon",
        OnClick = function(_, button)
            if button == "LeftButton" then
                MPW:ToggleMainFrame()
            elseif button == "RightButton" then
                MPW:ToggleDebugFrame()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Mythic+ Wheel", 1, 0.82, 0)
            tooltip:AddLine("|cFFAAAAAAv" .. MPW.VERSION .. "|r")
            if MPW.session.status then
                tooltip:AddLine("Session: " .. MPW.session.status, 0.5, 1, 0.5)
                tooltip:AddLine("Host: " .. (MPW.session.host or "Unknown"), 0.7, 0.7, 0.7)
            else
                tooltip:AddLine("No active session", 0.5, 0.5, 0.5)
            end
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFFFFFFFFLeft-click:|r Open addon", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cFFFFFFFFRight-click:|r Debug panel", 0.8, 0.8, 0.8)
        end,
    })
    LDBIcon:Register("Wheelson", launcher, self.db.profile.minimap)
```

- [ ] **Step 3: Add /mpw debug slash command**

Add a new `elseif` branch in the slash command handler, after the `"history"` case and before the `"help"` case:

```lua
    elseif cmd == "debug" then
        MPW:ToggleDebugFrame()
```

Also add the debug command to the help text output:

```lua
        MPW:Print("  /mpw debug - Toggle the debug panel")
```

- [ ] **Step 4: Run luacheck**

Run: `luacheck src/Core.lua`
Expected: No errors or warnings

- [ ] **Step 5: Commit**

```bash
git add src/Core.lua
git commit -m "feat: add minimap icon init and debug panel stub"
```

---

## Chunk 2: Debug Panel Frame Shell

### Task 3: Create DebugPanel.lua with frame and tab switching

**Files:**
- Create: `src/UI/DebugPanel.lua`

This task creates the frame shell, tab buttons, scroll frame with EditBox, and Copy All button. Tab content rendering is added in subsequent tasks.

- [ ] **Step 1: Create DebugPanel.lua with frame creation and tab switching**

Create `src/UI/DebugPanel.lua`:

```lua
---@class Wheelson
local MPW = _G.Wheelson

---------------------------------------------------------------------------
-- Debug Panel
-- Right-click minimap icon or /mpw debug to toggle.
-- Three tabs: State, Comm Log, WoW API
---------------------------------------------------------------------------

local debugFrame = nil
local currentTab = "state" -- "state" | "comm" | "api"

-- Comm log storage (populated by hooks, capped at 200 entries)
MPW.debugLog = {}
local DEBUG_LOG_MAX = 200

local MIN_WIDTH = 400
local MIN_HEIGHT = 300
local MAX_WIDTH = 800
local MAX_HEIGHT = 600

---------------------------------------------------------------------------
-- Tab Content Generators (each returns a string)
---------------------------------------------------------------------------

local function GenerateStateText()
    local lines = {}
    lines[#lines + 1] = "=== Addon Info ==="
    lines[#lines + 1] = "version: " .. tostring(MPW.VERSION)
    lines[#lines + 1] = "commPrefix: " .. tostring(MPW.COMM_PREFIX)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== Session State ==="
    lines[#lines + 1] = "status: " .. tostring(MPW.session.status or "(none)")
    lines[#lines + 1] = "host: " .. tostring(MPW.session.host or "(none)")
    lines[#lines + 1] = "locked: " .. tostring(MPW.session.locked or false)
    lines[#lines + 1] = "playerCount: " .. #MPW.session.players
    lines[#lines + 1] = ""

    if #MPW.session.players > 0 then
        lines[#lines + 1] = "=== Players ==="
        for i, p in ipairs(MPW.session.players) do
            lines[#lines + 1] = "  " .. i .. ". " .. p.name
            lines[#lines + 1] = "     mainRole: " .. tostring(p.mainRole or "(none)")
            local offspecs = #p.offspecs > 0 and table.concat(p.offspecs, ", ") or "(none)"
            lines[#lines + 1] = "     offspecs: " .. offspecs
            local utils = #p.utilities > 0 and table.concat(p.utilities, ", ") or "(none)"
            lines[#lines + 1] = "     utilities: " .. utils
        end
        lines[#lines + 1] = ""
    end

    if #MPW.session.groups > 0 then
        lines[#lines + 1] = "=== Groups ==="
        for i, g in ipairs(MPW.session.groups) do
            lines[#lines + 1] = "  Group " .. i .. ":"
            lines[#lines + 1] = "    tank: " .. (g.tank and g.tank.name or "(none)")
            lines[#lines + 1] = "    healer: " .. (g.healer and g.healer.name or "(none)")
            local dpsNames = {}
            for _, d in ipairs(g.dps) do dpsNames[#dpsNames + 1] = d.name end
            lines[#lines + 1] = "    dps: " .. (#dpsNames > 0 and table.concat(dpsNames, ", ") or "(none)")
            lines[#lines + 1] = "    hasBrez: " .. tostring(g:HasBrez())
            lines[#lines + 1] = "    hasLust: " .. tostring(g:HasLust())
            lines[#lines + 1] = "    isComplete: " .. tostring(g:IsComplete())
        end
        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "=== SavedVariables ==="
    if MPW.db and MPW.db.profile then
        local prof = MPW.db.profile
        lines[#lines + 1] = "minimap.hide: " .. tostring(prof.minimap and prof.minimap.hide or false)
        lines[#lines + 1] = "animationSpeed: " .. tostring(prof.animationSpeed)
        lines[#lines + 1] = "soundEnabled: " .. tostring(prof.soundEnabled)
        if prof.framePosition then
            local fp = prof.framePosition
            lines[#lines + 1] = "framePosition: " .. tostring(fp.point) .. " (" .. tostring(fp.x) .. ", " .. tostring(fp.y) .. ")"
        else
            lines[#lines + 1] = "framePosition: (none)"
        end
        if prof.lastSession then
            local ts = prof.lastSession.timestamp and date("%Y-%m-%d %H:%M:%S", prof.lastSession.timestamp) or "unknown"
            local gc = prof.lastSession.groups and #prof.lastSession.groups or 0
            lines[#lines + 1] = "lastSession: " .. ts .. " (" .. gc .. " groups)"
        else
            lines[#lines + 1] = "lastSession: (none)"
        end
        local histLen = prof.sessionHistory and #prof.sessionHistory or 0
        lines[#lines + 1] = "sessionHistory: " .. histLen .. " entries"
    else
        lines[#lines + 1] = "db: (not initialized)"
    end
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== Timers ==="
    if MPW.lastActivity and MPW.lastActivity > 0 then
        lines[#lines + 1] = "lastActivity: " .. date("%H:%M:%S", MPW.lastActivity)
        local remaining = (MPW.lastActivity + MPW.SESSION_TIMEOUT) - time()
        if MPW.session.status and remaining > 0 then
            lines[#lines + 1] = "timeoutRemaining: " .. math.floor(remaining) .. "s"
        else
            lines[#lines + 1] = "timeoutRemaining: (inactive)"
        end
    else
        lines[#lines + 1] = "lastActivity: (none)"
        lines[#lines + 1] = "timeoutRemaining: (inactive)"
    end
    lines[#lines + 1] = "rosterUpdatePending: " .. tostring(MPW.rosterUpdatePending or false)
    lines[#lines + 1] = "commPendingUpdate: " .. tostring(MPW.commPendingUpdate or false)

    return table.concat(lines, "\n")
end

local function GenerateCommLogText()
    if #MPW.debugLog == 0 then
        return "(No comm messages logged yet)\n\nMessages will appear here as they are sent/received."
    end

    local lines = {}
    for _, entry in ipairs(MPW.debugLog) do
        lines[#lines + 1] = entry
    end
    return table.concat(lines, "\n")
end

local function GenerateAPIText()
    local lines = {}

    lines[#lines + 1] = "=== Player Identity ==="
    lines[#lines + 1] = "UnitName: " .. tostring(UnitName("player"))
    local localizedClass, classToken = UnitClass("player")
    lines[#lines + 1] = "UnitClass: " .. tostring(localizedClass) .. " (" .. tostring(classToken) .. ")"
    lines[#lines + 1] = "UnitLevel: " .. tostring(UnitLevel("player"))
    lines[#lines + 1] = "Realm: " .. tostring(GetNormalizedRealmName())
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== Specialization ==="
    local specIndex = GetSpecialization()
    lines[#lines + 1] = "GetSpecialization(): " .. tostring(specIndex)
    if specIndex then
        local specID, specName = GetSpecializationInfo(specIndex)
        lines[#lines + 1] = "specID: " .. tostring(specID)
        lines[#lines + 1] = "specName: " .. tostring(specName)
        if specID then
            lines[#lines + 1] = "mappedRole: " .. tostring(MPW.SpecRoles[specID] or "(unmapped)")
        end
    end
    local allOffspecs = MPW:DetectAllOffspecs()
    lines[#lines + 1] = "allOffspecs: " .. (#allOffspecs > 0 and table.concat(allOffspecs, ", ") or "(none)")
    local detectedUtils = {}
    if classToken and MPW.BrezClasses[classToken] then detectedUtils[#detectedUtils + 1] = "brez" end
    if classToken and MPW.LustClasses[classToken] then detectedUtils[#detectedUtils + 1] = "lust" end
    lines[#lines + 1] = "detectedUtilities: " .. (#detectedUtils > 0 and table.concat(detectedUtils, ", ") or "(none)")
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== Guild ==="
    lines[#lines + 1] = "IsInGuild: " .. tostring(IsInGuild())
    lines[#lines + 1] = "GuildInfo: " .. tostring(GetGuildInfo("player"))
    local numTotal = GetNumGuildMembers()
    lines[#lines + 1] = "GetNumGuildMembers: " .. tostring(numTotal)
    local onlineMembers = MPW:GetOnlineGuildMembers()
    lines[#lines + 1] = "onlineMaxLevel: " .. #onlineMembers
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== Party ==="
    lines[#lines + 1] = "IsInGroup: " .. tostring(IsInGroup())
    lines[#lines + 1] = "UnitIsGroupLeader: " .. tostring(UnitIsGroupLeader("player"))
    lines[#lines + 1] = "GetNumGroupMembers: " .. tostring(GetNumGroupMembers())
    lines[#lines + 1] = "CanInvite: " .. tostring(MPW:CanInvite())
    lines[#lines + 1] = ""

    lines[#lines + 1] = "=== DetectLocalPlayer() ==="
    local player = MPW:DetectLocalPlayer()
    if player then
        lines[#lines + 1] = "name: " .. player.name
        lines[#lines + 1] = "mainRole: " .. tostring(player.mainRole or "(none)")
        local os_ = #player.offspecs > 0 and table.concat(player.offspecs, ", ") or "(none)"
        lines[#lines + 1] = "offspecs: " .. os_
        local ut = #player.utilities > 0 and table.concat(player.utilities, ", ") or "(none)"
        lines[#lines + 1] = "utilities: " .. ut
    else
        lines[#lines + 1] = "(returned nil -- no spec active?)"
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Comm Log Hooks
---------------------------------------------------------------------------

local function FormatLogPayload(data)
    if type(data) ~= "table" then return tostring(data) end
    local parts = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            parts[#parts + 1] = k .. "=[table]"
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    local result = table.concat(parts, ", ")
    if #result > 200 then
        result = result:sub(1, 197) .. "..."
    end
    return result
end

local function AddLogEntry(entry)
    MPW.debugLog[#MPW.debugLog + 1] = entry
    while #MPW.debugLog > DEBUG_LOG_MAX do
        table.remove(MPW.debugLog, 1)
    end

    -- Auto-refresh if comm tab is visible
    if debugFrame and debugFrame:IsShown() and currentTab == "comm" then
        debugFrame.editBox:SetText(GenerateCommLogText())
        -- Auto-scroll to bottom
        debugFrame.scrollFrame:SetVerticalScroll(debugFrame.scrollFrame:GetVerticalScrollRange())
    end
end

local function SetupCommHooks()
    -- Hook inbound messages
    hooksecurefunc(MPW, "OnCommReceived", function(_, prefix, message, distribution, sender)
        if prefix ~= MPW.COMM_PREFIX then return end
        local success, data = MPW:Deserialize(message)
        local payload = success and FormatLogPayload(data) or "(deserialize failed)"
        local entry = string.format("[%s] RECV | %s | %s | %s",
            date("%H:%M:%S"), sender, success and data.type or "?", payload)
        AddLogEntry(entry)
    end)

    -- Hook outbound session updates
    hooksecurefunc(MPW, "SendSessionUpdate", function(_)
        local playerCount = #MPW.session.players
        local groupCount = #MPW.session.groups
        local entry = string.format("[%s] SEND | SESSION_UPDATE | status=%s, players=%d, groups=%d",
            date("%H:%M:%S"), tostring(MPW.session.status), playerCount, groupCount)
        AddLogEntry(entry)
    end)

    -- Hook outbound session end
    hooksecurefunc(MPW, "BroadcastSessionEnd", function(_)
        local entry = string.format("[%s] SEND | SESSION_END", date("%H:%M:%S"))
        AddLogEntry(entry)
    end)
end

---------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------

local function CreateTabButton(parent, label, tabKey, xOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(90, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -28)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        currentTab = tabKey
        MPW:RefreshDebugPanel()
    end)
    return btn
end

local function UpdateTabHighlights(frame)
    local tabs = { state = frame.tabState, comm = frame.tabComm, api = frame.tabAPI }
    for key, btn in pairs(tabs) do
        if key == currentTab then
            btn:SetEnabled(false) -- Visually depressed = active
        else
            btn:SetEnabled(true)
        end
    end
end

local function CreateDebugFrame()
    local frame = CreateFrame("Frame", "MPWDebugPanel", UIParent, "BackdropTemplate")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

    -- Dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cFFFFD100MPW Debug|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Tab buttons
    frame.tabState = CreateTabButton(frame, "State", "state", 8)
    frame.tabComm = CreateTabButton(frame, "Comm Log", "comm", 102)
    frame.tabAPI = CreateTabButton(frame, "WoW API", "api", 196)

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", "MPWDebugScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -54)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    frame.scrollFrame = scrollFrame

    -- EditBox inside scroll frame (read-only-ish, for text selection)
    local editBox = CreateFrame("EditBox", "MPWDebugEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Prevent user edits but allow text selection
    editBox:SetScript("OnChar", function(self) self:SetText(self.lastText or "") end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.lastText or "")
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Resize handle
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT")
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        editBox:SetWidth(scrollFrame:GetWidth())
    end)

    -- Bottom buttons
    frame.copyAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.copyAllBtn:SetSize(80, 24)
    frame.copyAllBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.copyAllBtn:SetText("Copy All")
    frame.copyAllBtn:SetScript("OnClick", function()
        frame.editBox:HighlightText()
        frame.editBox:SetFocus()
        MPW:Print("Text selected. Press Ctrl+C to copy.")
    end)

    frame.refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refreshBtn:SetSize(80, 24)
    frame.refreshBtn:SetPoint("BOTTOMRIGHT", frame.copyAllBtn, "BOTTOMLEFT", -4, 0)
    frame.refreshBtn:SetText("Refresh")
    frame.refreshBtn:SetScript("OnClick", function()
        MPW:RefreshDebugPanel()
    end)

    -- Clear button (only visible on comm tab)
    frame.clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clearBtn:SetSize(80, 24)
    frame.clearBtn:SetPoint("BOTTOMLEFT", 8, 8)
    frame.clearBtn:SetText("Clear")
    frame.clearBtn:SetScript("OnClick", function()
        wipe(MPW.debugLog)
        MPW:RefreshDebugPanel()
    end)

    return frame
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Refresh the debug panel content for the current tab.
function MPW:RefreshDebugPanel()
    if not debugFrame or not debugFrame:IsShown() then return end

    UpdateTabHighlights(debugFrame)

    local text
    if currentTab == "state" then
        text = GenerateStateText()
    elseif currentTab == "comm" then
        text = GenerateCommLogText()
    elseif currentTab == "api" then
        text = GenerateAPIText()
    end

    debugFrame.editBox.lastText = text
    debugFrame.editBox:SetText(text)
    debugFrame.editBox:SetCursorPosition(0)

    -- Show Clear button only on comm tab
    debugFrame.clearBtn:SetShown(currentTab == "comm")
end

--- Toggle debug frame visibility. Overrides stub in Core.lua.
function MPW:ToggleDebugFrame()
    if not debugFrame then
        debugFrame = CreateDebugFrame()
        SetupCommHooks()
        UISpecialFrames[#UISpecialFrames + 1] = "MPWDebugPanel"
    end

    if debugFrame:IsShown() then
        debugFrame:Hide()
    else
        debugFrame:Show()
        self:RefreshDebugPanel()
    end
end
```

- [ ] **Step 2: Run luacheck on the new file**

Run: `luacheck src/UI/DebugPanel.lua`
Expected: No errors (warnings about unused args in hook callbacks are acceptable)

- [ ] **Step 3: Commit**

```bash
git add src/UI/DebugPanel.lua
git commit -m "feat: add debug panel with state, comm log, and API tabs"
```

---

## Chunk 3: TOC, Build Validation, and Final Verification

### Task 4: Update .toc file

**Files:**
- Modify: `Wheelson.toc:42` (after GroupDisplay.lua)

- [ ] **Step 1: Add DebugPanel.lua to the .toc**

Add after the `src\UI\GroupDisplay.lua` line:

```
src\UI\DebugPanel.lua
```

- [ ] **Step 2: Commit**

```bash
git add Wheelson.toc
git commit -m "feat: add DebugPanel.lua to toc load order"
```

---

### Task 5: Full lint and build validation

- [ ] **Step 1: Run luacheck on entire project**

Run: `luacheck src/ tests/`
Expected: No errors. If there are warnings, fix them.

- [ ] **Step 2: Run build validation**

Run: `bash scripts/build.sh`
Expected: All files listed in .toc exist on disk, build passes.

- [ ] **Step 3: Run tests**

Run: `busted`
Expected: All existing tests pass (no regressions).

- [ ] **Step 4: Fix any issues found, commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve lint/build issues from debug panel"
```

(Skip this step if no fixes were needed.)
