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
| Johng | melee | — | brez |
| jim | melee | tank | — |
| Raxef | melee | — | — |
| Mickey | melee | — | — |
| Khurri | melee | — | brez |
| Blueshift | ranged | — | lust |

Added to `.toc` load order after Models.lua, before GroupCreator.lua.

Note: "John G" from the original test data renamed to "Johng" since WoW names cannot contain spaces.

### Test Session (`Core.lua`)

New `MPW:StartTestSession()`:
- Sets `session.status = "lobby"`, `session.host = UnitName("player")`
- Sets `session.isTest = true`
- Populates `session.players` with the 15 test players
- Skips `BroadcastSessionUpdate()` (no guild comms)
- Skips session timeout (no `ResetSessionTimeout()` — test sessions don't time out)
- Shows the main frame and updates UI

### Test Button (`UI/Lobby.lua`)

- "Test" button in the lobby content area, next to the existing "Start Session" button
- Visible only when no active session (`session.status == nil`)
- Clicking calls `MPW:StartTestSession()`

### Invite Suppression (`Services/PartyService.lua` + `UI/GroupDisplay.lua`)

Two invite paths must be guarded:

1. **`MPW:InvitePlayers()`** in PartyService.lua — when `self.session.isTest`, print each invite to chat (`"[Wheelson Test] Would invite: <name>"`) instead of calling `InviteUnit()`
2. **`InviteMyGroup()`** in GroupDisplay.lua — route through `MPW:InvitePlayers()` instead of calling `InviteUnit()` directly, so the same guard applies

### Guild Chat Suppression (`UI/GroupDisplay.lua`)

`MPW:PostToGuildChat()` must early-return when `session.isTest == true`, logging the message to chat instead. Otherwise test group results would be posted to real guild chat.

### Broadcast Suppression (`Core.lua`)

`BroadcastSessionUpdate()` and `BroadcastSessionEnd()` early-return when `session.isTest == true`. No guild messages leak during test mode.

### Session Cleanup (`Core.lua`)

`EndSession()` must reset `self.session.isTest = nil` alongside other session fields, so subsequent real sessions don't inherit the test flag.

### Session History

Test sessions are **not saved** to `sessionHistory` in SavedVariables. `SaveSessionResults()` early-returns when `session.isTest == true`.

### Release Build Exclusion

TestData.lua should be excluded from release builds via `.pkgmeta` ignore rules so end users don't receive developer test data.

### Unchanged Behavior

- Full session flow (lobby -> spinning -> completed) works identically
- GroupCreator algorithm runs on test players for real
- Wheel animation plays normally
- GroupDisplay renders results with invite/post/copy buttons
- `EndSession()` cleans up normally (plus `isTest` reset)

## Files

| File | Change |
|------|--------|
| `src/TestData.lua` | New — test player data |
| `Wheelson.toc` | Add TestData.lua to load order |
| `.pkgmeta` | Exclude TestData.lua from release builds |
| `src/Core.lua` | Add `StartTestSession()`, suppress comms/save when `isTest` |
| `src/UI/Lobby.lua` | Add "Test" button |
| `src/UI/GroupDisplay.lua` | Route `InviteMyGroup()` through `InvitePlayers()`, suppress `PostToGuildChat()` |
| `src/Services/PartyService.lua` | Log instead of invite when `isTest` |
