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
- `ADDON_PONG` — each addon instance auto-replies with `{ name, version }`

**Cache** (`MPW.addonUsersCache`):

- Lua table keyed by player name, values are `{ name, version, lastSeen }`
- Populated when `ADDON_PONG` responses arrive
- Pruned passively via `CHAT_MSG_SYSTEM` — parse "X has gone offline" messages and remove matching entries
- Ephemeral (not persisted to SavedVariables) — cleared on logout/reload
- Zero cost when idle: no timers, no heartbeats, no background processing

**Handler changes in `Core.lua`:**

- `OnCommReceived` gains two new message type branches:
  - `ADDON_PING` received: auto-reply with `ADDON_PONG` containing local player name and `MPW.VERSION`
  - `ADDON_PONG` received: upsert sender into `addonUsersCache`
- Register `CHAT_MSG_SYSTEM` event handler to match "has gone offline" pattern and prune cache
- New method `MPW:SendAddonPing()` that broadcasts `ADDON_PING` to GUILD and marks a scan as in-progress
- New method `MPW:OnAddonPong(sender, data)` that updates the cache and refreshes the options panel if open

### 2. Options Panel (`src/UI/OptionsPanel.lua`)

Built with **AceConfig-3.0**, registered via `LibStub("AceConfig-3.0"):RegisterOptionsTable()` and `Settings.RegisterAddOnCategory()` so it appears under ESC > Options > AddOns > Wheelson.

**Content:**

- **Online Addon Users** section:
  - Descriptive text showing discovered player names and versions from cache
  - "Refresh" button that calls `MPW:SendAddonPing()` and updates the display after a short collection window (~2 seconds)
  - Shows "Scanning..." feedback during the collection window
  - Falls back to "No addon users discovered yet. Click Refresh to scan." when cache is empty

**Scope:** Only the discovery list for now. Future settings (animation speed, sound toggle, minimap visibility) can be added later but are out of scope.

### 3. Start Session Button (`src/UI/Lobby.lua`)

When `hasSession` is false in `UpdateLobbyView`, show a **"Start Session"** button centered at the bottom of the lobby frame. On click, it calls `MPW:StartSession()`, which transitions the session state to `"lobby"` and makes the user the host. This replaces the current dead-end empty state.

## File Changes

| File | Change Type | Description |
|------|-------------|-------------|
| `src/UI/OptionsPanel.lua` | **New** | AceConfig options panel with discovery list and refresh button |
| `src/Core.lua` | Modify | Add `addonUsersCache`, PING/PONG comm handlers, `CHAT_MSG_SYSTEM` listener for offline pruning, `SendAddonPing()` method |
| `src/UI/Lobby.lua` | Modify | Add "Start Session" button when no active session |
| `Wheelson.toc` | Modify | Add `src\UI\OptionsPanel.lua` to load order |

## Out of Scope

- Heartbeat/periodic presence broadcasting (violates "no extra resources when idle" constraint)
- Persisting the addon user cache across sessions
- Settings UI beyond the discovery list
- Any changes to the Wheel, GroupDisplay, or DebugPanel views
