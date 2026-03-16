# Minimap Icon Toggle Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players show/hide the minimap icon via options panel, slash command, or middle-click.

**Architecture:** Add a `ToggleMinimapIcon()` method to `Core.lua` that flips `db.profile.minimap.hide` and calls LibDBIcon `Show`/`Hide`. Wire it into three surfaces: AceConfig toggle, slash subcommand, and middle-click handler.

**Tech Stack:** Lua, AceAddon-3.0, AceConfig-3.0, LibDBIcon-1.0

**Spec:** `docs/superpowers/specs/2026-03-15-minimap-icon-toggle-design.md`

---

## Chunk 1: Core toggle + slash command + middle-click

### Task 1: Add ToggleMinimapIcon tests

**Files:**
- Modify: `tests/test_core.lua`

- [ ] **Step 1: Write tests for ToggleMinimapIcon**

Add a new `describe` block at the end of `tests/test_core.lua`:

```lua
describe("ToggleMinimapIcon", function()
    local ldbicon_shown, ldbicon_hidden
    local printed_messages

    before_each(function()
        WHLSN:OnInitialize()
        WHLSN.db.profile.minimap = { hide = false }

        ldbicon_shown = false
        ldbicon_hidden = false
        printed_messages = {}

        -- Mock LibDBIcon
        _G._test_ldbicon = {
            Show = function(_, name) ldbicon_shown = true end,
            Hide = function(_, name) ldbicon_hidden = true end,
        }

        WHLSN.Print = function(_, msg)
            printed_messages[#printed_messages + 1] = msg
        end
    end)

    it("should hide the icon when currently shown", function()
        WHLSN.db.profile.minimap.hide = false

        WHLSN:ToggleMinimapIcon()

        assert.is_true(WHLSN.db.profile.minimap.hide)
        assert.is_true(ldbicon_hidden)
        assert.is_false(ldbicon_shown)
    end)

    it("should show the icon when currently hidden", function()
        WHLSN.db.profile.minimap.hide = true

        WHLSN:ToggleMinimapIcon()

        assert.is_false(WHLSN.db.profile.minimap.hide)
        assert.is_true(ldbicon_shown)
        assert.is_false(ldbicon_hidden)
    end)

    it("should print restore hint when hiding", function()
        WHLSN.db.profile.minimap.hide = false

        WHLSN:ToggleMinimapIcon()

        assert.equals(1, #printed_messages)
        assert.truthy(printed_messages[1]:find("/wheelson minimap"))
    end)

    it("should print confirmation when showing", function()
        WHLSN.db.profile.minimap.hide = true

        WHLSN:ToggleMinimapIcon()

        assert.equals(1, #printed_messages)
        assert.truthy(printed_messages[1]:find("shown"))
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `busted tests/test_core.lua`
Expected: FAIL — `ToggleMinimapIcon` does not exist yet

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test_core.lua
git commit -m "test: add ToggleMinimapIcon tests"
```

### Task 2: Implement ToggleMinimapIcon

**Files:**
- Modify: `src/Core.lua:39-67` (minimap icon section)

- [ ] **Step 1: Update LibDBIcon mock in test file to use LibStub**

The test mock for LibDBIcon in `tests/test_core.lua` needs to return the `_test_ldbicon` object so `ToggleMinimapIcon` can fetch it via `LibStub`. Update the `LibStub` mock's `LibDBIcon-1.0` branch (around line 40-43):

```lua
    elseif name == "LibDBIcon-1.0" then
        return _G._test_ldbicon or {
            Register = function() end,
            Show = function() end,
            Hide = function() end,
        }
```

- [ ] **Step 2: Add ToggleMinimapIcon method to Core.lua**

Add after the `LDBIcon:Register(...)` line (after line 67), before the `self:Print("Wheelson loaded...")` line:

```lua
--- Toggle minimap icon visibility and persist the setting.
function WHLSN:ToggleMinimapIcon()
    local db = self.db.profile.minimap
    local icon = LibStub("LibDBIcon-1.0")
    db.hide = not db.hide
    if db.hide then
        icon:Hide("Wheelson")
        self:Print("Minimap icon hidden. Type /wheelson minimap to show it again.")
    else
        icon:Show("Wheelson")
        self:Print("Minimap icon shown.")
    end
end
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `busted tests/test_core.lua`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add src/Core.lua tests/test_core.lua
git commit -m "feat: add ToggleMinimapIcon method"
```

### Task 3: Add slash command subcommand routing and middle-click

**Files:**
- Modify: `src/Core.lua:86-91` (slash command handler)
- Modify: `src/Core.lua:46-52` (OnClick handler)
- Modify: `src/Core.lua:53-65` (OnTooltipShow)
- Modify: `tests/test_core.lua`

- [ ] **Step 1: Write tests for slash command routing**

Add to `tests/test_core.lua`:

```lua
describe("Slash command routing", function()
    local toggled_main, toggled_minimap

    before_each(function()
        toggled_main = false
        toggled_minimap = false
        WHLSN.ToggleMainFrame = function() toggled_main = true end
        WHLSN.ToggleMinimapIcon = function() toggled_minimap = true end
    end)

    it("should open main frame with no args", function()
        SlashCmdList["WHEELSON"]("")
        assert.is_true(toggled_main)
        assert.is_false(toggled_minimap)
    end)

    it("should toggle minimap with 'minimap' arg", function()
        SlashCmdList["WHEELSON"]("minimap")
        assert.is_true(toggled_minimap)
        assert.is_false(toggled_main)
    end)

    it("should handle extra whitespace", function()
        SlashCmdList["WHEELSON"]("  minimap  ")
        assert.is_true(toggled_minimap)
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `busted tests/test_core.lua`
Expected: FAIL — slash command currently always calls `ToggleMainFrame`

- [ ] **Step 3: Update slash command handler in Core.lua**

Replace lines 89-91:

```lua
SlashCmdList["WHEELSON"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "minimap" then
        WHLSN:ToggleMinimapIcon()
    else
        WHLSN:ToggleMainFrame()
    end
end
```

- [ ] **Step 4: Add MiddleButton to OnClick handler**

Replace the `OnClick` function (lines 46-52) with:

```lua
        OnClick = function(_, button)
            if button == "LeftButton" then
                WHLSN:ToggleMainFrame()
            elseif button == "RightButton" then
                WHLSN:ToggleDebugFrame()
            elseif button == "MiddleButton" then
                WHLSN:ToggleMinimapIcon()
            end
        end,
```

- [ ] **Step 5: Add tooltip hint line**

In `OnTooltipShow` (line 64), after the right-click line, add:

```lua
            tooltip:AddLine("|cFFFFFFFFMiddle-click:|r Hide icon", 0.8, 0.8, 0.8)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `busted tests/test_core.lua`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/Core.lua tests/test_core.lua
git commit -m "feat: add slash command routing and middle-click toggle"
```

## Chunk 2: Options panel toggle

### Task 4: Add options panel toggle

**Files:**
- Modify: `src/UI/OptionsPanel.lua`

- [ ] **Step 1: Add minimap toggle to options table**

In `OptionsPanel.lua`, add a new entry inside the `args` table, before `discoveryHeader` (order 1). Insert after line 35 (`args = {`):

```lua
        minimapIcon = {
            order = 0,
            type = "toggle",
            name = "Show Minimap Icon",
            desc = "Show or hide the Wheelson minimap button",
            get = function() return not WHLSN.db.profile.minimap.hide end,
            set = function(_, value)
                WHLSN.db.profile.minimap.hide = not value
                local icon = LibStub("LibDBIcon-1.0")
                if value then
                    icon:Show("Wheelson")
                else
                    icon:Hide("Wheelson")
                end
            end,
        },
```

- [ ] **Step 2: Run full test suite**

Run: `busted`
Expected: All tests PASS (OptionsPanel is UI code, not loaded in tests — this verifies no regressions)

- [ ] **Step 3: Run lint**

Run: `luacheck src/ tests/`
Expected: No new warnings

- [ ] **Step 4: Commit**

```bash
git add src/UI/OptionsPanel.lua
git commit -m "feat: add minimap icon toggle to options panel"
```

### Task 5: Final validation

- [ ] **Step 1: Run full test suite**

Run: `busted`
Expected: All tests PASS

- [ ] **Step 2: Run lint**

Run: `luacheck src/ tests/`
Expected: No new warnings

- [ ] **Step 3: Run build validation**

Run: `bash scripts/build.sh`
Expected: Build passes
