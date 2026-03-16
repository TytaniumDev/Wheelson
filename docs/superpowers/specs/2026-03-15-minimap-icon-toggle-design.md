# Minimap Icon Toggle

## Summary

Add a user-facing toggle to show/hide the Wheelson minimap icon, exposed through three surfaces: the AceConfig options panel, a `/wheelson minimap` slash subcommand, and middle-click on the minimap icon itself.

## Background

The addon already has LibDBIcon-1.0 registered with `self.db.profile.minimap` (which contains `{ hide = false }` by default). LibDBIcon reads the `hide` field at registration time and respects `Show()`/`Hide()` calls at runtime. No new libraries or saved variables are needed — just UI to flip the existing flag.

## Design

### Core toggle method

A new `WHLSN:ToggleMinimapIcon()` method on the addon object:

- Flips `self.db.profile.minimap.hide`
- Calls `LDBIcon:Show("Wheelson")` or `LDBIcon:Hide("Wheelson")` for immediate effect
- Prints a status message: on hide, tells the user how to restore it (`/wheelson minimap`)

This method lives in `Core.lua` alongside the existing minimap icon setup code.

### Surface 1: Options panel toggle

A new `toggle` entry in the AceConfig options table in `OptionsPanel.lua`:

- Label: "Show Minimap Icon"
- Inserted at order 0 (before the discovery section header at order 1)
- `get` returns `not WHLSN.db.profile.minimap.hide` (inverted because the stored field is `hide` but the label is positive)
- `set` writes `hide = not value`, then calls `LDBIcon:Show`/`:Hide` accordingly

### Surface 2: Slash command subcommand

The existing `SlashCmdList["WHEELSON"]` handler in `Core.lua` currently calls `ToggleMainFrame()` unconditionally. Change it to parse the first argument:

- No args → `ToggleMainFrame()` (existing behavior)
- `"minimap"` → `ToggleMinimapIcon()`

### Surface 3: Middle-click on minimap icon

The `OnClick` handler in the LibDataBroker launcher object (Core.lua) currently handles `LeftButton` and `RightButton`. Add a `MiddleButton` branch that:

- Calls `WHLSN:ToggleMinimapIcon()` (which will hide the icon since it's currently visible if you can click it)

### Tooltip hint

Add a line to `OnTooltipShow`: `"|cFFFFFFFFMiddle-click:|r Hide icon"` below the existing right-click hint.

## Files changed

| File | Change |
|---|---|
| `src/Core.lua` | Add `ToggleMinimapIcon()`, update slash command handler to route subcommands, add `MiddleButton` to `OnClick`, add tooltip hint line |
| `src/UI/OptionsPanel.lua` | Add "Show Minimap Icon" toggle at order 0 |

## Testing

- Existing tests should not break (no changes to Models, GroupCreator, or Services)
- Manual verification: toggle via options panel, slash command, and middle-click all produce consistent behavior
- Verify icon reappears on `/wheelson minimap` after being hidden
- Verify setting persists across `/reload`
