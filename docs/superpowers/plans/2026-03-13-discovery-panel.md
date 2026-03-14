# Discovery Panel & Start Session Button Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add on-demand addon user discovery (ping/pong), an AceConfig options panel showing discovered users, and a "Start Session" button to the main frame's empty lobby state.

**Architecture:** New comm message types (ADDON_PING/ADDON_PONG) broadcast to GUILD channel for zero-idle-cost discovery. Cache is ephemeral (table keyed by player name), pruned via GUILD_ROSTER_UPDATE. Options panel uses AceConfig-3.0 + AceConfigDialog-3.0. Start Session button is added to the existing Lobby view's no-session state.

**Tech Stack:** Lua 5.1, WoW API, AceAddon-3.0, AceComm-3.0, AceConfig-3.0, AceConfigDialog-3.0, AceGUI-3.0, busted (tests)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/Core.lua` | Modify | Add `addonUsersCache`, `isScanning`, `SendAddonPing()`, PING/PONG comm handlers, GUILD_ROSTER_UPDATE cache pruning |
| `src/UI/OptionsPanel.lua` | Create | AceConfig options table with discovery list and Refresh button |
| `src/UI/Lobby.lua` | Modify | Add "Start Session" button when no active session |
| `Wheelson.toc` | Modify | Add AceConfigDialog-3.0 lib and OptionsPanel.lua |
| `.pkgmeta` | Modify | Add AceConfigDialog-3.0 external |
| `tests/test_core.lua` | Modify | Add tests for ping/pong handlers and cache pruning |

---

## Chunk 1: Discovery System + Tests

### Task 1: Add PING/PONG comm handlers and cache to Core.lua

**Files:**
- Modify: `src/Core.lua:8-31` (OnInitialize — add cache + scanning state)
- Modify: `src/Core.lua:462-487` (OnCommReceived — add PING/PONG branches)
- Modify: `src/Core.lua:578-594` (GUILD_ROSTER_UPDATE — add cache pruning)
- Test: `tests/test_core.lua`

- [ ] **Step 1: Write failing tests for ADDON_PING handler**

First, add `dofile("src/Services/SpecService.lua")` to the load sequence at the top of the file, after `dofile("src/Core.lua")`. This is needed because `HandleAddonPong` calls `self:StripRealmName()` which is defined in SpecService.

Then add to `tests/test_core.lua` after the existing `describe("Core", ...)` block:

```lua
describe("Discovery", function()
    before_each(function()
        MPW.addonUsersCache = {}
        MPW.isScanning = false
        MPW.sent_messages = {}
        MPW.SendCommMessage = function(self, prefix, msg, channel)
            self.sent_messages[#self.sent_messages + 1] = { prefix = prefix, msg = msg, channel = channel }
        end
        MPW.Serialize = function(self, data) return data end
        MPW.Deserialize = function(self, msg) return true, msg end
    end)

    describe("OnCommReceived ADDON_PING", function()
        it("should reply with ADDON_PONG when receiving ADDON_PING", function()
            local message = { type = "ADDON_PING" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.equals(1, #MPW.sent_messages)
            local sent = MPW.sent_messages[1]
            assert.equals(MPW.COMM_PREFIX, sent.prefix)
            assert.equals("GUILD", sent.channel)
            assert.equals("ADDON_PONG", sent.msg.type)
            assert.equals("TestPlayer", sent.msg.name)
            assert.equals(MPW.VERSION, sent.msg.version)
        end)

        it("should not reply to own ADDON_PING", function()
            local message = { type = "ADDON_PING" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "TestPlayer")
            assert.equals(0, #MPW.sent_messages)
        end)
    end)

    describe("OnCommReceived ADDON_PONG", function()
        it("should add sender to addonUsersCache", function()
            local message = { type = "ADDON_PONG", name = "OtherPlayer", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.is_not_nil(MPW.addonUsersCache["OtherPlayer"])
            assert.equals("OtherPlayer", MPW.addonUsersCache["OtherPlayer"].name)
            assert.equals("1.0.0", MPW.addonUsersCache["OtherPlayer"].version)
        end)

        it("should strip realm name from sender", function()
            local message = { type = "ADDON_PONG", name = "OtherPlayer-Sargeras", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer-Sargeras")

            assert.is_not_nil(MPW.addonUsersCache["OtherPlayer"])
            assert.is_nil(MPW.addonUsersCache["OtherPlayer-Sargeras"])
        end)

        it("should update existing entry on repeated PONG", function()
            MPW.addonUsersCache["OtherPlayer"] = { name = "OtherPlayer", version = "0.9.0", lastSeen = 100 }

            local message = { type = "ADDON_PONG", name = "OtherPlayer", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "OtherPlayer")

            assert.equals("1.0.0", MPW.addonUsersCache["OtherPlayer"].version)
        end)

        it("should not cache own PONG (self-filter blocks it)", function()
            local message = { type = "ADDON_PONG", name = "TestPlayer", version = "1.0.0" }
            MPW:OnCommReceived(MPW.COMM_PREFIX, message, "GUILD", "TestPlayer")

            assert.is_nil(MPW.addonUsersCache["TestPlayer"])
        end)
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `busted tests/test_core.lua`
Expected: FAIL — "ADDON_PING"/"ADDON_PONG" message types not handled yet

- [ ] **Step 3: Add cache and scanning state to OnInitialize**

In `src/Core.lua`, add after line 30 (`self.commPendingUpdate = false`):

```lua
    -- Addon user discovery cache (ephemeral, not saved)
    self.addonUsersCache = {}
    self.isScanning = false
```

- [ ] **Step 4: Add PING/PONG handling to OnCommReceived**

In `src/Core.lua`, in the `OnCommReceived` method, add two new `elseif` branches after the `LEAVE_REQUEST` handler (after line 485):

```lua
    elseif data.type == "ADDON_PING" then
        self:HandleAddonPing(sender)
    elseif data.type == "ADDON_PONG" then
        self:HandleAddonPong(data, sender)
```

Then add the handler methods. Place them after the `HandleLeaveRequest` method (after line 572), before the `-- Event Handlers` section:

```lua
function MPW:HandleAddonPing(_sender)
    -- Reply with our presence info, broadcast to GUILD so all clients can cache
    local data = {
        type = "ADDON_PONG",
        name = UnitName("player"),
        version = self.VERSION,
    }
    local serialized = self:Serialize(data)
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")
end

function MPW:HandleAddonPong(data, sender)
    local name = self:StripRealmName(sender)
    self.addonUsersCache[name] = {
        name = name,
        version = data.version or "unknown",
        lastSeen = time(),
    }

    -- Refresh options panel if open so it live-updates as PONGs arrive
    local ACR = LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("Wheelson")
    end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `busted tests/test_core.lua`
Expected: All PING/PONG tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/Core.lua tests/test_core.lua
git commit -m "feat: add ADDON_PING/PONG discovery comm handlers and cache"
```

---

### Task 2: Add SendAddonPing method and cache pruning

**Files:**
- Modify: `src/Core.lua` (add SendAddonPing method, extend GUILD_ROSTER_UPDATE)
- Test: `tests/test_core.lua`

- [ ] **Step 1: Write failing tests for SendAddonPing and cache pruning**

Add to the `describe("Discovery", ...)` block in `tests/test_core.lua`:

```lua
    describe("SendAddonPing", function()
        it("should broadcast ADDON_PING to GUILD", function()
            MPW:SendAddonPing()

            assert.is_true(#MPW.sent_messages > 0)
            local sent = MPW.sent_messages[1]
            assert.equals("GUILD", sent.channel)
            assert.equals("ADDON_PING", sent.msg.type)
        end)

        it("should add local player to cache", function()
            MPW:SendAddonPing()

            assert.is_not_nil(MPW.addonUsersCache["TestPlayer"])
            assert.equals("TestPlayer", MPW.addonUsersCache["TestPlayer"].name)
            assert.equals(MPW.VERSION, MPW.addonUsersCache["TestPlayer"].version)
        end)

        it("should set isScanning to true", function()
            MPW:SendAddonPing()
            assert.is_true(MPW.isScanning)
        end)
    end)

    describe("PruneAddonUsersCache", function()
        it("should remove players not in online roster", function()
            MPW.addonUsersCache["OnlinePlayer"] = { name = "OnlinePlayer", version = "1.0", lastSeen = 100 }
            MPW.addonUsersCache["OfflinePlayer"] = { name = "OfflinePlayer", version = "1.0", lastSeen = 100 }

            -- Mock GetOnlineGuildMembers to return only OnlinePlayer
            MPW.GetOnlineGuildMembers = function()
                return { { name = "OnlinePlayer", classToken = "WARRIOR", level = 90, online = true } }
            end

            MPW:PruneAddonUsersCache()

            assert.is_not_nil(MPW.addonUsersCache["OnlinePlayer"])
            assert.is_nil(MPW.addonUsersCache["OfflinePlayer"])
        end)

        it("should keep cache empty if no online members", function()
            MPW.addonUsersCache["SomePlayer"] = { name = "SomePlayer", version = "1.0", lastSeen = 100 }

            MPW.GetOnlineGuildMembers = function() return {} end

            MPW:PruneAddonUsersCache()

            assert.is_nil(MPW.addonUsersCache["SomePlayer"])
        end)
    end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `busted tests/test_core.lua`
Expected: FAIL — `SendAddonPing` and `PruneAddonUsersCache` not defined

- [ ] **Step 3: Add SendAddonPing method**

In `src/Core.lua`, add after the `HandleAddonPong` method:

```lua
--- Broadcast a discovery ping to find online addon users.
function MPW:SendAddonPing()
    -- Add local player to cache (bypasses self-filter in OnCommReceived)
    local myName = UnitName("player")
    self.addonUsersCache[myName] = {
        name = myName,
        version = self.VERSION,
        lastSeen = time(),
    }

    local data = { type = "ADDON_PING" }
    local serialized = self:Serialize(data)
    self:SendCommMessage(self.COMM_PREFIX, serialized, "GUILD")

    self.isScanning = true
    C_Timer.After(2, function()
        self.isScanning = false
        -- Refresh options panel if AceConfigRegistry is available
        local ACR = LibStub("AceConfigRegistry-3.0", true)
        if ACR then
            ACR:NotifyChange("Wheelson")
        end
    end)
end
```

- [ ] **Step 4: Add PruneAddonUsersCache method**

In `src/Core.lua`, add after `SendAddonPing`:

```lua
--- Remove cached addon users who are no longer online in the guild roster.
function MPW:PruneAddonUsersCache()
    local onlineMembers = self:GetOnlineGuildMembers()
    local onlineSet = {}
    for _, m in ipairs(onlineMembers) do
        onlineSet[m.name] = true
    end

    for name in pairs(self.addonUsersCache) do
        if not onlineSet[name] then
            self.addonUsersCache[name] = nil
        end
    end
end
```

- [ ] **Step 5: Extend GUILD_ROSTER_UPDATE to prune cache**

In `src/Core.lua`, modify the `GUILD_ROSTER_UPDATE` handler (line 582-584):

Replace:
```lua
function MPW:GUILD_ROSTER_UPDATE()
    self:ThrottledUpdateUI()
end
```

With:
```lua
function MPW:GUILD_ROSTER_UPDATE()
    self:PruneAddonUsersCache()
    self:ThrottledUpdateUI()
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `busted tests/test_core.lua`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/Core.lua tests/test_core.lua
git commit -m "feat: add SendAddonPing and cache pruning on roster update"
```

---

## Chunk 2: Options Panel + Start Session Button + Wiring

### Task 3: Add AceConfigDialog-3.0 dependency

**Files:**
- Modify: `Wheelson.toc:11-22` (add AceConfigDialog-3.0 lib entry)
- Modify: `.pkgmeta:3-26` (add AceConfigDialog-3.0 external)

- [ ] **Step 1: Add AceConfigDialog-3.0 to .pkgmeta externals**

In `.pkgmeta`, add after the `libs/AceConfig-3.0` entry (after line 18):

```yaml
  libs/AceConfigDialog-3.0:
    url: https://repos.curseforge.com/wow/ace3/trunk/AceConfigDialog-3.0
```

- [ ] **Step 2: Add AceConfigDialog-3.0 to Wheelson.toc**

In `Wheelson.toc`, add after line 19 (`libs\AceConfig-3.0\AceConfig-3.0.lua`):

```
libs\AceConfigDialog-3.0\AceConfigDialog-3.0.lua
```

- [ ] **Step 3: Run build validation**

Run: `bash scripts/build.sh`
Expected: Build validation passes (AceConfigDialog-3.0 is fetched at release time, not checked on disk)

Note: If build.sh checks that listed files exist on disk, this will fail because libs are gitignored and fetched by the BigWigsMods packager at release. In that case, skip this check — CI handles it via the packager.

- [ ] **Step 4: Commit**

```bash
git add Wheelson.toc .pkgmeta
git commit -m "feat: add AceConfigDialog-3.0 dependency for options panel"
```

---

### Task 4: Create OptionsPanel.lua

**Files:**
- Create: `src/UI/OptionsPanel.lua`
- Modify: `Wheelson.toc` (add to load order)

- [ ] **Step 1: Create OptionsPanel.lua**

Create `src/UI/OptionsPanel.lua`:

```lua
---@class Wheelson
local MPW = _G.Wheelson

---------------------------------------------------------------------------
-- Options Panel
-- AceConfig-based settings panel shown in Interface > AddOns > Wheelson.
-- Displays online guild members who have the addon installed.
---------------------------------------------------------------------------

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local function GetDiscoveryText()
    if MPW.isScanning then
        return "Scanning..."
    end

    local lines = {}
    for _, entry in pairs(MPW.addonUsersCache) do
        lines[#lines + 1] = entry.name .. "  (v" .. entry.version .. ")"
    end

    if #lines == 0 then
        return "No addon users discovered yet. Click Refresh to scan."
    end

    table.sort(lines)
    return table.concat(lines, "\n")
end

local options = {
    name = "Wheelson",
    type = "group",
    args = {
        discoveryHeader = {
            order = 1,
            type = "header",
            name = "Online Addon Users",
        },
        discoveryDesc = {
            order = 2,
            type = "description",
            name = function() return GetDiscoveryText() end,
            fontSize = "medium",
        },
        refresh = {
            order = 3,
            type = "execute",
            name = "Refresh",
            desc = "Scan for guild members with Wheelson installed",
            func = function()
                MPW:SendAddonPing()
            end,
        },
    },
}

AceConfig:RegisterOptionsTable("Wheelson", options)
AceConfigDialog:AddToBlizOptions("Wheelson")
```

- [ ] **Step 2: Add OptionsPanel.lua to Wheelson.toc**

In `Wheelson.toc`, add after the `src\UI\DebugPanel.lua` line (line 44):

```
src\UI\OptionsPanel.lua
```

- [ ] **Step 3: Run lint**

Run: `luacheck src/UI/OptionsPanel.lua`
Expected: No errors (warnings about globals like `LibStub` are OK — they are defined at runtime)

- [ ] **Step 4: Commit**

```bash
git add src/UI/OptionsPanel.lua Wheelson.toc
git commit -m "feat: add options panel with addon user discovery list"
```

---

### Task 5: Add Start Session button to Lobby

**Files:**
- Modify: `src/UI/Lobby.lua:63-103` (add button in CreateLobbyFrame)
- Modify: `src/UI/Lobby.lua:237-244` (show/hide in UpdateLobbyView)

- [ ] **Step 1: Add Start Session button to CreateLobbyFrame**

In `src/UI/Lobby.lua`, add after the lock button creation (after line 101, before `return frame`):

```lua
    -- Start Session button (shown when no session is active)
    frame.startButton = CreateFrame("Button", "MPWStartButton", frame, "UIPanelButtonTemplate")
    frame.startButton:SetSize(160, 32)
    frame.startButton:SetPoint("BOTTOM", 0, 8)
    frame.startButton:SetText("Start Session")
    frame.startButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        MPW:StartSession()
    end)
```

- [ ] **Step 2: Wire up visibility in UpdateLobbyView**

In `src/UI/Lobby.lua`, in the `UpdateLobbyView` function, add the start button visibility logic. After line 241 (`lobbyFrame.leaveButton:SetShown(not isHost and hasSession and isInSession)`), add:

```lua
    lobbyFrame.startButton:SetShown(not hasSession)
```

- [ ] **Step 3: Run lint**

Run: `luacheck src/UI/Lobby.lua`
Expected: No errors

- [ ] **Step 4: Run all tests**

Run: `busted`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/UI/Lobby.lua
git commit -m "feat: add Start Session button to lobby empty state"
```

---

### Task 6: Final validation

- [ ] **Step 1: Run full lint**

Run: `luacheck src/ tests/`
Expected: No errors (warnings about WoW globals are OK)

- [ ] **Step 2: Run full test suite**

Run: `busted`
Expected: All tests PASS

- [ ] **Step 3: Run build validation**

Run: `bash scripts/build.sh`
Expected: Build passes

- [ ] **Step 4: Verify TOC load order is correct**

Read `Wheelson.toc` and confirm:
1. `libs\AceConfigDialog-3.0\AceConfigDialog-3.0.lua` is in the `# Embedded Libraries` section
2. `src\UI\OptionsPanel.lua` is in the `# UI` section after `DebugPanel.lua`

- [ ] **Step 5: Commit any remaining fixes if needed**
