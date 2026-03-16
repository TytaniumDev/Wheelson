# Community Roster Panel Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the inline "Add Player" input with an anchored side panel showing the community roster, autocomplete input, and right-click context menus.

**Architecture:** The community panel is a lazy-created `BackdropTemplate` frame anchored to the right edge of the main Wheelson frame. It lives entirely in `Lobby.lua` alongside the existing lobby view code, following the same lazy-create + toggle pattern used by `DebugPanel.lua`. The panel reuses existing `CommunityService.lua` CRUD functions.

**Tech Stack:** Lua 5.1, WoW 12.0 API, AceAddon-3.0

---

## Chunk 1: Remove Old Add Player UI and Rename Button

### Task 1: Add new WoW globals to luacheckrc

**Files:**
- Modify: `.luacheckrc` (add new WoW API globals)

- [ ] **Step 1: Add new globals used by the community panel**

In `.luacheckrc`, add these entries to the `read_globals` table:

```lua
    -- In the "WoW API functions" section:
    "AutoCompleteEditBox_SetAutoCompleteSource",
    "ChatFrame_OpenChat",
    MenuUtil = { other_fields = true },
    AUTOCOMPLETE_LIST = { other_fields = true },

    -- In the "WoW UI globals" section:
    "GameFontNormalSmall",
```

Note: `GameFontNormalSmall` is already present. Add the other four entries.

- [ ] **Step 2: Commit**

```bash
git add .luacheckrc
git commit -m "chore: add community panel WoW API globals to luacheckrc"
```

### Task 2: Remove inline add-player UI and rename button to "Community Roster"

**Files:**
- Modify: `src/UI/Lobby.lua:113-177` (remove add-player input/confirm, update button)
- Modify: `src/UI/Lobby.lua:295-308` (update `UpdateLobbyButtons`)

- [ ] **Step 1: Replace the add-player button, input, and confirm with the renamed Community Roster button**

In `src/UI/Lobby.lua`, replace lines 113-177 (the `addPlayerButton`, `addPlayerInput`, `addPlayerConfirm`, `ConfirmAddPlayer`, and their script handlers) with:

```lua
    -- Community Roster button (host only, during active session)
    frame.communityRosterButton = CreateFrame("Button", "WHLSNCommunityRosterButton", frame, "UIPanelButtonTemplate")
    frame.communityRosterButton:SetSize(120, 32)
    frame.communityRosterButton:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.communityRosterButton:SetText("Community Roster")
    frame.communityRosterButton:SetScript("OnClick", function()
        WHLSN:ToggleCommunityPanel()
    end)
```

- [ ] **Step 2: Update `UpdateLobbyButtons` to reference the renamed button**

In `src/UI/Lobby.lua`, replace `UpdateLobbyButtons` (lines 295-308) with:

```lua
local function UpdateLobbyButtons(frame, isHost, hasSession, isInSession, playerCount)
    frame.spinButton:SetShown(isHost and hasSession)
    frame.spinButton:SetEnabled(playerCount >= 5)
    frame.joinButton:SetShown(not isHost and hasSession and not isInSession)
    frame.leaveButton:SetShown(not isHost and hasSession and isInSession)
    frame.startButton:SetShown(not hasSession)
    frame.testButton:SetShown(not hasSession)
    frame.endButton:SetShown(isHost and hasSession)
    frame.communityRosterButton:SetShown(isHost and hasSession)
    if not (isHost and hasSession) then
        WHLSN:HideCommunityPanel()
    end
end
```

- [ ] **Step 3: Run lint to check for errors**

Run: `luacheck src/UI/Lobby.lua`
Expected: No errors related to old `addPlayerButton`, `addPlayerInput`, `addPlayerConfirm` references. May have warnings about `WHLSN:ToggleCommunityPanel` and `WHLSN:HideCommunityPanel` being undefined — that's expected, we'll add them in Task 2.

- [ ] **Step 4: Commit**

```bash
git add src/UI/Lobby.lua
git commit -m "refactor: replace Add Player inline UI with Community Roster button"
```

---

## Chunk 2: Create the Community Panel Frame

### Task 3: Create panel frame with lazy creation and toggle

**Files:**
- Modify: `src/UI/Lobby.lua` (add panel creation after `CreateLobbyFrame`, before `CreatePlayerRow`)
- Modify: `src/UI/MainFrame.lua:86-90` (hide panel in `HideAllViews`)

- [ ] **Step 1: Add the community panel state and creation function**

In `src/UI/Lobby.lua`, add this block after the `lobbyState` declaration (after line 9) and before `CreateLobbyFrame`:

```lua
local communityPanel = nil
```

Then add this block after the `CreateLobbyFrame` function ends (after the new `communityRosterButton` code, before `CreatePlayerRow`):

```lua
local COMMUNITY_PANEL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function CreateCommunityPanel()
    local mainFrame = _G["WHLSNMainFrame"]
    if not mainFrame then return nil end

    local panel = CreateFrame("Frame", "WHLSNCommunityPanel", mainFrame, "BackdropTemplate")
    panel:SetWidth(200)
    panel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", -2, 0)
    panel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMRIGHT", -2, 0)
    panel:SetBackdrop(COMMUNITY_PANEL_BACKDROP)
    panel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)

    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -12)
    panel.title:SetText("|cFFFFD100Community Roster|r")

    -- Member count
    panel.countText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.countText:SetPoint("TOP", panel.title, "BOTTOM", 0, -2)
    panel.countText:SetTextColor(0.6, 0.6, 0.6)

    -- Add player input (with autocomplete fallback)
    local template = "InputBoxTemplate"
    local ok = pcall(CreateFrame, "EditBox", nil, panel, "AutoCompleteEditBoxTemplate")
    if ok then
        template = "AutoCompleteEditBoxTemplate"
    end

    panel.input = CreateFrame("EditBox", "WHLSNCommunityInput", panel, template)
    panel.input:SetSize(140, 20)
    panel.input:SetPoint("TOPLEFT", 12, -48)
    panel.input:SetAutoFocus(false)
    panel.input.Instructions = panel.input:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.input.Instructions:SetPoint("LEFT", 6, 0)
    panel.input.Instructions:SetText("Character name...")
    panel.input.Instructions:SetTextColor(0.5, 0.5, 0.5)
    panel.input:SetScript("OnEditFocusGained", function(self)
        self.Instructions:Hide()
    end)
    panel.input:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.Instructions:Show()
        end
    end)

    -- Set up autocomplete if available
    if template == "AutoCompleteEditBoxTemplate" and AUTOCOMPLETE_LIST then
        AutoCompleteEditBox_SetAutoCompleteSource(panel.input, AUTOCOMPLETE_LIST.ALL)
    end

    -- OK button
    panel.okButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.okButton:SetSize(36, 20)
    panel.okButton:SetPoint("LEFT", panel.input, "RIGHT", 2, 0)
    panel.okButton:SetText("OK")

    -- Add player logic
    local function ConfirmAddPlayer()
        local name = panel.input:GetText()
        if name and strtrim(name) ~= "" then
            local added, err = WHLSN:AddCommunityPlayer(name)
            if added then
                local normalized = WHLSN:NormalizeCommunityName(name)
                WHLSN:Print("Added " .. normalized .. " to community roster.")
                if WHLSN.session.status == WHLSN.Status.LOBBY then
                    local pingData = {
                        type = "SESSION_PING",
                        host = UnitName("player"),
                        status = WHLSN.session.status,
                        version = WHLSN.VERSION,
                    }
                    local serialized = WHLSN:Serialize(pingData)
                    WHLSN:SendCommMessage(WHLSN.COMM_PREFIX, serialized, "WHISPER", normalized)
                end
                WHLSN:RefreshCommunityPanel()
                WHLSN:UpdateLobbyView()
            else
                WHLSN:Print("Could not add: " .. (err or "unknown error"))
            end
        end
        panel.input:SetText("")
        panel.input.Instructions:Show()
        panel.input:ClearFocus()
    end

    panel.okButton:SetScript("OnClick", ConfirmAddPlayer)
    panel.input:SetScript("OnEnterPressed", ConfirmAddPlayer)
    panel.input:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self.Instructions:Show()
        self:ClearFocus()
    end)

    -- Divider line
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -74)
    divider:SetPoint("TOPRIGHT", -8, -74)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Container for roster rows
    panel.rosterContainer = CreateFrame("Frame", nil, panel)
    panel.rosterContainer:SetPoint("TOPLEFT", 8, -80)
    panel.rosterContainer:SetPoint("BOTTOMRIGHT", -8, 8)

    panel.rosterRows = {}

    return panel
end
```

- [ ] **Step 2: Add toggle, hide, and refresh functions**

Add these after the `CreateCommunityPanel` function:

```lua
function WHLSN:ToggleCommunityPanel()
    if not communityPanel then
        communityPanel = CreateCommunityPanel()
        if not communityPanel then return end
        UISpecialFrames[#UISpecialFrames + 1] = "WHLSNCommunityPanel"
    end

    if communityPanel:IsShown() then
        communityPanel:Hide()
    else
        communityPanel:Show()
        self:RefreshCommunityPanel()
    end
end

function WHLSN:HideCommunityPanel()
    if communityPanel and communityPanel:IsShown() then
        communityPanel:Hide()
    end
end

function WHLSN:RefreshCommunityPanel()
    if not communityPanel or not communityPanel:IsShown() then return end

    local roster = self.db.profile.communityRoster
    communityPanel.countText:SetText(#roster .. " members")

    -- Hide existing rows
    for _, row in ipairs(communityPanel.rosterRows) do
        row:Hide()
    end

    -- Create/update rows
    for i, entry in ipairs(roster) do
        local row = communityPanel.rosterRows[i]
        if not row then
            row = CreateFrame("Frame", nil, communityPanel.rosterContainer)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
            row:SetPoint("RIGHT", 0, 0)
            row:EnableMouse(true)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetJustifyH("LEFT")

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 0.82, 0, 0.1)

            communityPanel.rosterRows[i] = row
        end

        local displayName = self:StripRealmName(entry.name)
        row.nameText:SetText(displayName)
        row.nameText:SetTextColor(0.9, 0.9, 0.9)
        row.fullName = entry.name

        -- Tooltip showing full realm-qualified name
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullName, 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Right-click context menu
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                MenuUtil.CreateContextMenu(self, function(_, rootDescription)
                    rootDescription:CreateTitle(self.fullName)
                    rootDescription:CreateButton("Whisper", function()
                        ChatFrame_OpenChat("/w " .. self.fullName .. " ")
                    end)
                    rootDescription:CreateButton("|cFFFF6666Remove|r", function()
                        WHLSN:RemoveCommunityPlayer(self.fullName)
                        WHLSN:Print("Removed " .. self.fullName .. " from community roster.")
                        WHLSN:RefreshCommunityPanel()
                    end)
                end)
            end
        end)

        row:Show()
    end
end
```

- [ ] **Step 3: Update `HideAllViews` in MainFrame.lua to hide the community panel**

In `src/UI/MainFrame.lua`, replace `HideAllViews` (lines 86-90):

```lua
--- Hide all view frames so only the next shown view is visible.
function WHLSN:HideAllViews()
    self:HideLobbyView()
    self:HideWheelView()
    self:HideGroupDisplayView()
    self:HideCommunityPanel()
end
```

- [ ] **Step 4: Run lint**

Run: `luacheck src/UI/Lobby.lua src/UI/MainFrame.lua`
Expected: PASS (no errors)

- [ ] **Step 5: Commit**

```bash
git add src/UI/Lobby.lua src/UI/MainFrame.lua
git commit -m "feat: add community roster side panel with autocomplete input and context menu"
```

---

## Chunk 3: Tests and Final Validation

### Task 4: Update tests

**Files:**
- Modify: `tests/test_community_service.lua` (no changes needed — existing tests cover CRUD, which is unchanged)

The community panel is entirely UI code (frame creation, anchoring, event handlers). The codebase convention is to only test non-UI logic (Models, GroupCreator, GuildService, SpecService, CommunityService). The CommunityService CRUD functions being called by the panel are already fully tested. No new test file is needed.

- [ ] **Step 1: Run the full test suite to verify nothing is broken**

Run: `busted`
Expected: All tests pass. The UI changes don't affect any tested code paths.

- [ ] **Step 2: Run lint on all source files**

Run: `luacheck src/ tests/`
Expected: PASS

- [ ] **Step 3: Run build validation**

Run: `bash scripts/build.sh`
Expected: PASS (no new files to add to .toc)

- [ ] **Step 4: Commit any test fixes if needed**

Only if a previous step required changes:
```bash
git add -A && git commit -m "fix: resolve test/lint issues from community panel changes"
```
