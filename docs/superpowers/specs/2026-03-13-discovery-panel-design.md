# Discovery Panel & Start Session Button

## Problem

When a user types `/wheelson` or clicks the minimap icon, they see a blank panel with "No active session" and no actionable UI. There is no way to:

1. See which guild members are online and have the addon installed
2. Start a session without knowing the `/wheelson host` slash command

## Solution

Three changes:

1. **On-demand ping/pong discovery system** to detect online addon users
2. **Options panel** (ESC > Options > AddOns > Wheelson) showing discovered addon users
3. **"Start Session" button** in the main frame's empty lobby state

## Design

### 1. Discovery System (Ping/Pong Comm + Cache)

**New AceComm message types** on the existing `MPWheel` prefix:

- `ADDON_PING` — broadcast to `GUILD` channel when the options panel opens or user clicks Refresh
- `ADDON_PONG` — each addon instance auto-replies to `GUILD` channel with `{ name, version }`. Sent to GUILD (not whispered) so all addon clients can populate their caches from any ping.

**Cache** (`MPW.addonUsersCache`):

- Lua table keyed by player name (realm-stripped via `SpecService` helpers for consistency with `Player.name`), values are `{ name, version, lastSeen }`
- Populated when `ADDON_PONG` responses arrive
- The local player is added to the cache directly in `SendAddonPing()` (bypasses the self-message filter in `OnCommReceived` which drops messages from the local player)
- Pruned passively via `GUILD_ROSTER_UPDATE` — diff online guild roster against cache and remove members who are no longer online. Note: `CHAT_MSG_SYSTEM` "has gone offline" only fires for friends, not guild members, so it cannot be used.
- Ephemeral (not persisted to SavedVariables) — cleared on logout/reload
- Zero cost when idle: no timers, no heartbeats, no background processing

**Handler changes in `Core.lua`:**

- `OnCommReceived` gains two new message type branches:
  - `ADDON_PING` received: auto-reply with `ADDON_PONG` containing local player name and `MPW.VERSION`, broadcast to GUILD
  - `ADDON_PONG` received: upsert sender (realm-stripped) into `addonUsersCache`
- Register `GUILD_ROSTER_UPDATE` event handler to prune cache entries for players no longer online
- New method `MPW:SendAddonPing()` that broadcasts `ADDON_PING` to GUILD, adds local player to cache, sets `MPW.isScanning = true`, and starts a `C_Timer.After(2, callback)` that sets `isScanning = false` and refreshes the options panel via `LibStub("AceConfigRegistry-3.0"):NotifyChange("Wheelson")`
- New method `MPW:OnAddonPong(sender, data)` that updates the cache and calls `NotifyChange` to refresh the options panel if open

### 2. Options Panel (`src/UI/OptionsPanel.lua`)

Built with **AceConfig-3.0** and **AceConfigDialog-3.0**. Registered via `LibStub("AceConfig-3.0"):RegisterOptionsTable("Wheelson", optionsTable)` and `LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Wheelson")` for Blizzard settings integration.

AceConfigDialog-3.0 is not currently in the TOC or `.pkgmeta` and must be added to both.

**Content:**

- **Online Addon Users** section:
  - A `description` widget whose `name` function dynamically rebuilds a multi-line string from the cache on each render, listing player names and versions
  - "Refresh" execute button that calls `MPW:SendAddonPing()`
  - During the 2-second scan window (`MPW.isScanning == true`), the description shows "Scanning..."
  - When cache is empty and not scanning, shows "No addon users discovered yet. Click Refresh to scan."

**Scope:** Only the discovery list for now. Future settings (animation speed, sound toggle, minimap visibility) can be added later but are out of scope.

### 3. Start Session Button (`src/UI/Lobby.lua`)

When `hasSession` is false in `UpdateLobbyView`, show a **"Start Session"** button centered at the bottom of the lobby frame. On click, it calls `MPW:StartSession()`, which transitions the session state to `"lobby"` and makes the user the host. This replaces the current dead-end empty state.

Note: If another player is already hosting a session, the local player will receive their `SESSION_UPDATE` broadcast and the UI will switch to show that session. Starting a competing session is the same behavior as `/wheelson host` today — acceptable for now.

## File Changes

| File | Change Type | Description |
|------|-------------|-------------|
| `src/UI/OptionsPanel.lua` | **New** | AceConfig options panel with discovery list and refresh button |
| `src/Core.lua` | Modify | Add `addonUsersCache`, PING/PONG comm handlers, `GUILD_ROSTER_UPDATE` listener for offline pruning, `SendAddonPing()` method |
| `src/UI/Lobby.lua` | Modify | Add "Start Session" button when no active session |
| `Wheelson.toc` | Modify | Add `libs\AceConfigDialog-3.0\AceConfigDialog-3.0.lua` and `src\UI\OptionsPanel.lua` to load order |
| `.pkgmeta` | Modify | Add AceConfigDialog-3.0 external |

### Load Order

`OptionsPanel.lua` loads after `Core.lua` (depends on `MPW` methods). In the TOC, it goes in the `# UI` section after `DebugPanel.lua`. `AceConfigDialog-3.0` goes in the `# Embedded Libraries` section alongside the other Ace3 libs.

## Out of Scope

- Heartbeat/periodic presence broadcasting (violates "no extra resources when idle" constraint)
- Persisting the addon user cache across sessions
- Settings UI beyond the discovery list
- Any changes to the Wheel, GroupDisplay, or DebugPanel views
