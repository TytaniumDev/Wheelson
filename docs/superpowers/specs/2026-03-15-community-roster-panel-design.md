# Community Roster Panel — Design Spec

## Summary

Replace the inline "Add Player" input box with an anchored side panel that opens to the right of the main Wheelson frame. The panel displays the full community roster with online/offline indicators, provides an autocomplete input for adding new members, and supports right-click context menus on roster entries.

## Requirements

1. **"Community Roster" button** replaces the current "Add Player" button in the lobby bottom bar
2. **Anchored side panel** opens flush against the right edge of the main frame, sharing border styling
3. **Autocomplete input** at the top of the panel using WoW's `AutoCompleteEditBoxTemplate` (friends, guild, recent contacts)
4. **Roster list** showing all community members with online/offline dot indicators
5. **Right-click context menu** on roster entries with "Whisper" and "Remove" options
6. **Toggle behavior** — button toggles panel open/closed; Escape also dismisses

## UI Layout

```
┌──────────────────────────────┐┌──────────────────────┐
│         Wheelson             ││  Community Roster     │
│  Lobby — Hosted by Host     ││  3 members            │
│                              ││                       │
│  🛡 Gazzi              ✓    ││ [Character name...][OK]│
│  ✚ Quill               ✓    ││                       │
│  ⚔ Sorovar                  ││ ─────────────────     │
│  ⚔ Vanyali                  ││ ● Alice-Illidan online│
│  ⚔ Tytaniormu          🏠  ││ ● Bob-Sargeras  online│
│  ... more players ...        ││ ○ Charlie-Area52  off │
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
- **Auto-hide**: Panel hides when main frame hides or session ends
- **Anchoring**: `SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", -1, 0)` so borders overlap seamlessly
- **Screen clamping**: Panel is clamped to screen like the main frame
- **Width**: ~200px, matching WoW side-panel conventions
- **Height**: Matches main frame height

## Autocomplete Input

- Frame type: `CreateFrame("EditBox", "WHLSNCommunityInput", panel, "AutoCompleteEditBoxTemplate")`
- Autocomplete source: `AUTOCOMPLETE_LIST.ALL` (friends, guild, recent contacts)
- **Enter key** or **OK button** triggers `WHLSN:AddCommunityPlayer(name)`, clears input, refreshes roster list
- **Escape** clears focus (standard EditBox behavior)
- No hint text below the input

## Roster List

- Scrollable list of all entries from `db.profile.communityRoster`
- Each row displays:
  - Online indicator dot (green = online, gray = offline)
  - Player name (realm-stripped for display, full name in tooltip on hover)
  - Online/offline text label
- Online status: Best-effort detection via friend/guild APIs; default to neutral if unknown
- List refreshes when a player is added or removed

## Context Menu

Right-click on any roster entry opens a context menu with:
- **Whisper** — opens whisper to that player
- **Remove** — removes from community roster (with confirmation print, no dialog)

Implementation: Use WoW's `MenuUtil.CreateContextMenu` (modern 12.0 API) or fall back to the `EasyMenu` pattern.

## File Changes

### `src/UI/Lobby.lua`
- Remove current `addPlayerInput`, `addPlayerConfirm`, and toggle logic (lines ~113-177)
- Rename button from "Add Player" to "Community Roster"
- Add `CreateCommunityPanel()` function for lazy panel creation
- Add `ToggleCommunityPanel()` for show/hide toggle
- Add `RefreshCommunityRoster()` to rebuild the scrollable roster list
- Add right-click context menu handler
- Wire "Community Roster" button to `ToggleCommunityPanel()`

### `src/UI/MainFrame.lua`
- In `HideAllViews()` or frame `OnHide`, also hide the community panel if shown

### No new files
The panel is part of the Lobby view — no new source files needed.

## Out of Scope

- Drag-to-reorder roster entries
- Sorting or filtering the roster list
- Inline editing of roster entry names
- Persisting panel open/closed state across sessions
