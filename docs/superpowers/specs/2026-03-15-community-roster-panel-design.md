# Community Roster Panel — Design Spec

## Summary

Replace the inline "Add Player" input box with an anchored side panel that opens to the right of the main Wheelson frame. The panel displays the full community roster, provides an autocomplete input for adding new members, and supports right-click context menus on roster entries.

## Requirements

1. **"Community Roster" button** replaces the current "Add Player" button in the lobby bottom bar
2. **Anchored side panel** opens flush against the right edge of the main frame, sharing border styling
3. **Autocomplete input** at the top of the panel using WoW's `AutoCompleteEditBoxTemplate` (friends, guild, recent contacts)
4. **Roster list** showing all community members
5. **Right-click context menu** on roster entries with "Whisper" and "Remove" options
6. **Toggle behavior** — button toggles panel open/closed; Escape also dismisses
7. **Always visible** — the "Community Roster" button is shown to the host whenever a session is active (matching current "Add Player" visibility), since community roster management is a host action

## UI Layout

```
┌──────────────────────────────┐┌──────────────────────┐
│         Wheelson             ││  Community Roster     │
│  Lobby — Hosted by Host     ││  3 members            │
│                              ││                       │
│  🛡 Gazzi              ✓    ││ [Character name...][OK]│
│  ✚ Quill               ✓    ││                       │
│  ⚔ Sorovar                  ││ ─────────────────     │
│  ⚔ Vanyali                  ││   Alice-Illidan       │
│  ⚔ Tytaniormu          🏠  ││   Bob-Sargeras        │
│  ... more players ...        ││   Charlie-Area52      │
│                              ││                       │
│                              ││  Right-click: options │
├──────────────────────────────┤└──────────────────────┘
│[End Session][Spin!][Community Roster]│
└──────────────────────────────┘
```

The side panel anchors to the main frame's right edge. The main frame and panel share a continuous border, appearing as one unified window.

## Panel Behavior

- **Lazy creation**: Panel frame is created on first toggle, then reused (same pattern as DebugPanel)
- **ESC dismissal**: Registered in `UISpecialFrames`
- **Auto-hide**: Panel hides when `HideAllViews()` is called (session state transitions away from lobby, main frame hides, or session ends)
- **Anchoring**: `SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", -2, 0)` — offset of -2 to fully overlap the main frame's 2px right border texture, producing a seamless visual join
- **Screen clamping**: Panel is clamped to screen like the main frame
- **Width**: ~200px, matching WoW side-panel conventions
- **Height**: Matches main frame height
- **Border styling**: Uses `BackdropTemplate` with the same backdrop table as DebugPanel (`UI-Tooltip-Border` edgeFile, dark background). The left edge of the panel visually replaces the main frame's right border where they overlap.

## Autocomplete Input

- Frame type: `CreateFrame("EditBox", "WHLSNCommunityInput", panel, "AutoCompleteEditBoxTemplate")`
- Autocomplete source: `AUTOCOMPLETE_LIST.ALL` (friends, guild, recent contacts)
- **Fallback**: If `AutoCompleteEditBoxTemplate` is unavailable at runtime, fall back to `InputBoxTemplate` (already used in the codebase). The autocomplete is a nice-to-have enhancement.
- **Enter key** or **OK button** triggers `WHLSN:AddCommunityPlayer(name)`, clears input, refreshes roster list
- **Escape** clears focus (standard EditBox behavior)
- **Placeholder text**: "Character name..." shown when the input is empty

## Roster List

- Simple list of dynamically created rows from `db.profile.communityRoster` (no scroll frame needed — community rosters are small, typically under 10-15 entries; if the list exceeds the panel height, rows simply clip)
- Each row displays:
  - Player name (realm-stripped for display via `StripRealmName()`)
  - Full realm-qualified name shown in tooltip on hover
- No online/offline indicators — there's no reliable WoW API for detecting online status of cross-realm non-guild players. The addon's comm ping response (`addonUsersCache`) only reflects addon users who've responded in the current session, which would be misleading as a general online indicator.
- List refreshes when a player is added or removed

## Context Menu

Right-click on any roster entry opens a context menu with:
- **Whisper** — opens whisper to that player
- **Remove** — removes from community roster (prints confirmation, no dialog)

Implementation: Use `MenuUtil.CreateContextMenu` (modern WoW 12.0 API), consistent with the project's rule to use modern C_ namespaced APIs and avoid deprecated patterns.

## File Changes

### `src/UI/Lobby.lua`
- Remove current `addPlayerInput`, `addPlayerConfirm`, and inline toggle logic (lines ~113-177)
- Rename button from "Add Player" to "Community Roster"
- Update `UpdateLobbyButtons()` (~lines 296-308) to reference renamed button and remove `addPlayerInput`/`addPlayerConfirm` hide logic
- Add `CreateCommunityPanel()` function for lazy panel creation
- Add `ToggleCommunityPanel()` for show/hide toggle
- Add `RefreshCommunityRoster()` to rebuild the roster list
- Add right-click context menu handler
- Wire "Community Roster" button to `ToggleCommunityPanel()`

### `src/UI/MainFrame.lua`
- In `HideAllViews()`, also hide the community panel if it exists and is shown

### No new files
The panel is part of the Lobby view — no new source files needed.

## Out of Scope

- Drag-to-reorder roster entries
- Sorting or filtering the roster list
- Inline editing of roster entry names
- Persisting panel open/closed state across sessions
- Online/offline status indicators
