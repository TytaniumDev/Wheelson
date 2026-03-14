# Test Mode for Wheelson

## Problem

The addon needs to be tested end-to-end (algorithm + UI + wheel animation) without other guild members having the addon installed. A test mode lets the developer simulate a full session with hardcoded players, suppressing guild comms and party invites.

## Design

### Test Data (`src/TestData.lua`)

New file providing `MPW:GetTestPlayers()` returning 15 `MPW.Player` objects matching the MythicPlusDiscordBot PR #254 test case:

| Name | Main Role | Offspecs | Utilities |
|------|-----------|----------|-----------|
| Temma | tank | melee | brez |
| Gazzi | tank | — | brez |
| Quill | healer | tank, ranged, melee | brez |
| Sorovar | healer | — | — |
| Vanyali | ranged | — | — |
| Tytaniormu | ranged | — | lust |
| Heretofore | ranged | — | lust |
| Poppybrosjr | ranged | — | lust |
| Volkareth | ranged | healer | lust |
| John G | melee | — | brez |
| jim | melee | tank | — |
| Raxef | melee | — | — |
| Mickey | melee | — | — |
| Khurri | melee | — | brez |
| Blueshift | ranged | — | lust |

Added to `.toc` load order after Models.lua, before GroupCreator.lua.

### Test Session (`Core.lua`)

New `MPW:StartTestSession()`:
- Sets `session.status = "lobby"`, `session.host = UnitName("player")`
- Sets `session.isTest = true`
- Populates `session.players` with the 15 test players
- Skips `BroadcastSessionUpdate()` (no guild comms)
- Shows the main frame and updates UI

### Test Button (`UI/MainFrame.lua`)

- "Test" button on the main frame, near existing close/minimize buttons
- Visible only when no active session (`session.status == nil`)
- Clicking calls `MPW:StartTestSession()`

### Invite Suppression (`Services/PartyService.lua`)

In `MPW:InvitePlayers()`, when `self.session.isTest`:
- Print each invite to chat: `"[Wheelson Test] Would invite: <name>"`
- Do not call `InviteUnit()`

### Broadcast Suppression (`Core.lua`)

`BroadcastSessionUpdate()` and `SendEndSession()` early-return when `session.isTest == true`. No guild messages leak during test mode.

### Unchanged Behavior

- Full session flow (lobby -> spinning -> completed) works identically
- GroupCreator algorithm runs on test players for real
- Wheel animation plays normally
- GroupDisplay renders results with invite/post/copy buttons
- `EndSession()` cleans up normally

## Files

| File | Change |
|------|--------|
| `src/TestData.lua` | New — test player data |
| `Wheelson.toc` | Add TestData.lua to load order |
| `src/Core.lua` | Add `StartTestSession()`, suppress comms when `isTest` |
| `src/UI/MainFrame.lua` | Add "Test" button |
| `src/Services/PartyService.lua` | Log instead of invite when `isTest` |
