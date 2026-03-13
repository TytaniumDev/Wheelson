# Minimap Icon & Debug Panel

## Overview

Add a minimap icon using the already-bundled LibDataBroker-1.1 and LibDBIcon-1.0 libraries, with a custom texture. Left-click toggles the main addon window; right-click toggles a debug panel. The debug panel is a separate draggable frame with three tabs that expose addon internals in a copy/screenshot-friendly format.

## Minimap Icon

- **Broker object**: Register a LibDataBroker `data source` of type `launcher` with the addon's custom texture (`Interface\AddOns\MythicPlusWheel\textures\minimap-icon`).
- **Icon registration**: Use LibDBIcon to create the minimap button, backed by `MPW.db.profile.minimap` (already defined in `Config.lua` defaults).
- **Left-click**: Calls `MPW:ToggleMainFrame()`.
- **Right-click**: Calls `MPW:ToggleDebugFrame()`.
- **Tooltip**: Shows addon name, version (`MPW.VERSION`), and current session status (or "No active session").
- **Custom texture**: `textures/minimap-icon.tga` (64x64 TGA, already converted and placed in repo).

### Files touched
- `src/Core.lua` — Add minimap icon initialization in `OnInitialize`, after AceDB setup.

## Debug Panel Frame

A standalone, draggable, resizable frame separate from the main addon window. Registered with `UISpecialFrames` so ESC closes it. Three tabs along the top switch between views.

### Files created
- `src/UI/DebugPanel.lua` — All debug panel logic in one file.

### Frame structure
- Title bar: "MPW Debug" with close button
- Tab bar: State | Comm Log | WoW API
- Content area: A scroll frame containing a non-interactive FontString for the text dump, or an EditBox for copyable text
- Bottom bar: "Copy All" button (present on every tab), plus tab-specific buttons

### Text format
All output uses plain structured text — `key: value` pairs, indented lists, section headers with `===`. This format is readable in screenshots and useful when pasted into a conversation with Claude. Example:

```
=== Session State ===
status: lobby
host: Tytanium
locked: false
playerCount: 3

=== Players ===
  1. Tytanium
     mainRole: tank
     offspecs: melee
     utilities: brez
  2. Healbot
     mainRole: healer
     offspecs: ranged
     utilities: (none)
```

## Tab 1: State

Dumps a full snapshot of `MPW.session` and relevant `MPW.db.profile` fields.

### Sections
1. **Addon Info** — `MPW.VERSION`, `MPW.COMM_PREFIX`
2. **Session State** — `status`, `host`, `locked`, `playerCount`
3. **Players** — For each player: `name`, `mainRole`, `offspecs` (comma-separated), `utilities` (comma-separated)
4. **Groups** — For each group: tank name, healer name, dps names, brez/lust flags, `IsComplete()` result
5. **SavedVariables** — `minimap.hide`, `animationSpeed`, `soundEnabled`, `framePosition` (point/x/y), `lastSession` (timestamp + group count), `sessionHistory` length
6. **Timers** — `lastActivity` (formatted timestamp), session timeout remaining (computed from `lastActivity + SESSION_TIMEOUT - time()`), `rosterUpdatePending`, `commPendingUpdate`

### Behavior
- Text regenerates each time the tab is selected or a "Refresh" button is clicked.

## Tab 2: Comm Log

A live, scrolling log of all AceComm messages sent and received.

### Implementation
- Hook `MPW:OnCommReceived` — after the existing logic, append a log entry.
- Hook `MPW:SendCommMessage` (or wrap `SendSessionUpdate` / `BroadcastSessionEnd`) — log outbound messages before sending.
- Each log entry: `[HH:MM:SS] DIR | sender/target | msg.type | payload_summary`
  - `DIR` = `SEND` or `RECV`
  - `payload_summary` = the decoded `data` table serialized as key=value pairs (truncated if very long)
- Store entries in `MPW.debugLog` table, capped at 200 entries (oldest dropped).
- Log is only populated while the addon is loaded (not persisted across sessions).

### Buttons
- **Clear** — Wipes `MPW.debugLog` and refreshes display.
- **Copy All** — Dumps full log to the clipboard EditBox.

### Behavior
- Auto-scrolls to bottom on new entries if the user hasn't scrolled up.

## Tab 3: WoW API

Queries WoW APIs on demand and displays results.

### Sections
1. **Player Identity** — `UnitName("player")`, `UnitClass("player")` (localized + token), `UnitLevel("player")`, `GetRealmName()`
2. **Specialization** — `GetSpecialization()` index, `GetSpecializationInfo()` (specID, name), mapped role from `MPW.SpecRoles`, all offspecs via `MPW:DetectAllOffspecs()`, detected utilities
3. **Guild** — `IsInGuild()`, `GetGuildInfo("player")`, `GetNumGuildMembers()`, online count, max-level online count (via `MPW:GetOnlineGuildMembers()`)
4. **Party** — `IsInGroup()`, `UnitIsGroupLeader("player")`, `GetNumGroupMembers()`, `MPW:CanInvite()`
5. **DetectLocalPlayer() Result** — Full dump of what `MPW:DetectLocalPlayer()` returns (name, mainRole, offspecs, utilities)

### Buttons
- **Refresh** — Re-queries all APIs and regenerates the text.
- **Copy All** — Dumps to clipboard.

## .toc and Load Order

`src/UI/DebugPanel.lua` is added to `MythicPlusWheel.toc` after `src/UI/GroupDisplay.lua` (last UI file). The debug panel has no dependencies on UI files but needs `Core.lua` and services loaded first.

## Scope Exclusions

- No settings/config UI — this is debug-only.
- No persisted debug log — the comm log resets each session.
- No AceConfig integration — the debug panel is standalone.
