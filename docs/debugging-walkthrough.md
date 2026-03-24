# Debugging Walkthrough: Host + Joiner Communication

This document traces every addon message exchanged between a **host** (the player who creates the lobby) and a **joiner** (a guild member who joins), with references to the source code and the debug log entries you can expect to see.

All messages use **AceComm** with prefix `"WHLSN"` over the `"GUILD"` distribution channel (visible to all guild members running the addon). Community (non-guild) players use `"WHISPER"` instead.

---

## Opening the Debug Panel

**Right-click the Wheelson minimap icon** to open the Debug Panel (`src/UI/DebugPanel.lua`).

The panel hooks into `OnCommReceived`, `SendSessionUpdate`, `BroadcastSessionEnd`, `LeaveSession`, and `RequestJoin` via `hooksecurefunc`. Every message is logged as:

```
[HH:MM:SS] RECV/SEND | sender_or_channel | MESSAGE_TYPE | key=value summary
```

The log is capped at 200 entries, auto-scrolls, and has **Copy All** (markdown format), **Refresh**, and **Clear** buttons.

> **Important:** Debug hooks are only installed when you first open the panel. Open it on both characters **before** creating/joining the lobby to capture all messages from the start.

---

## Phase 1: Host Creates a Lobby

**Host clicks "Create Lobby"** -> `WHLSN:CreateLobby()` (`src/Core.lua:137`)

1. Sets `session.status = "lobby"` and `session.host = "HostName-Realm"`.
2. Calls `DetectLocalPlayer()` (`src/Services/SpecService.lua:49`) to build the host's `Player` object from their active WoW spec, offspecs, utilities (brez/lust), and class token.
3. Auto-adds the host as `session.players[1]`.
4. Calls `BroadcastSessionUpdate()` (`src/Core.lua:620`) -> `SendSessionUpdate()` (`src/Core.lua:642`).

### Message sent by host

```
Channel: GUILD
Type: SESSION_UPDATE
Payload: {
    type         = "SESSION_UPDATE",
    version      = "<addon version>",
    status       = "lobby",
    host         = "HostName-Realm",
    playerCount  = 1,
    players      = [ { name, mainRole, offspecs, utilities, classToken } ],
    community    = {},
    removedPlayers = {},
}
```

5. Also calls `SendCommunityPings()` (`src/Services/CommunityService.lua:107`) -- sends a `SESSION_PING` via `WHISPER` to each saved community roster member (non-guild friends).

### Debug log (host)

```
[HH:MM:SS] SEND | GUILD | SESSION_UPDATE | status=lobby, players=1, groups=0
```

---

## Phase 2: Joiner Receives the Lobby Announcement

**Joiner's addon receives the message** -> `OnCommReceived()` (`src/Core.lua:687`)

1. Deserializes the message, sees `type = "SESSION_UPDATE"`.
2. Routes to `HandleSessionUpdate()` (`src/Core.lua:744`).
3. Since the joiner has no active session (`session.status == nil`) and `data.status == "lobby"`, prints:
   ```
   HostName-Realm created a lobby! Type /wheelson to join.
   ```
4. Stores `session.status = "lobby"`, `session.host = "HostName-Realm"`, and the player list.
5. Calls `UpdateUI()` -- the lobby view shows the host's player list with a **"Join Lobby"** button.

### Debug log (joiner)

```
[HH:MM:SS] RECV | HostName | SESSION_UPDATE | type=SESSION_UPDATE, version=..., status=lobby, host=HostName-Realm, playerCount=1, players=[table]
```

---

## Phase 3: Joiner Clicks "Join Lobby"

**Joiner clicks "Join Lobby"** -> `WHLSN:RequestJoin()` (`src/UI/Lobby.lua:950`)

1. Calls `DetectLocalPlayer()` to build the joiner's `Player` object from their current spec.
2. If spec detection fails, prints `"Could not detect your spec..."` and aborts.
3. Serializes and sends:

### Message sent by joiner

```
Channel: GUILD  (or WHISPER if community player)
Type: JOIN_REQUEST
Payload: {
    type   = "JOIN_REQUEST",
    player = { name, mainRole, offspecs, utilities, classToken },
}
```

4. Prints `"Join request sent."`.
5. Sets `session.joinPending = true` and starts a **5-second timeout timer**.
6. If no `JOIN_ACK` arrives within 5 seconds, prints `"Join request may not have been received. Try again."`.

### Debug log (joiner)

```
[HH:MM:SS] SEND | GUILD | JOIN_REQUEST | player=JoinerName
```

---

## Phase 4: Host Receives the Join Request

**Host's addon receives the message** -> `OnCommReceived()` -> `HandleJoinRequest()` (`src/Core.lua:816`)

1. Validates: Is this addon the host? Is the lobby in `"lobby"` status? Does `data.player.name` match `sender`?
2. For `WHISPER` distribution: also checks `IsCommunityRosterMember(sender)`.
3. Deserializes the player data via `Player.FromDict()`.
4. Calls `ResolvePlayerName(player, sender)` (`src/Services/SpecService.lua:142`) to normalize the realm-qualified name.
5. Checks if the player already exists in `session.players` -- if so, replaces them (handles reconnects / spec changes).
6. Otherwise appends the player to `session.players`.
7. Sends a **JOIN_ACK** back:

### Message sent by host

```
Channel: GUILD  (or WHISPER if community player)
Type: JOIN_ACK
Payload: {
    type       = "JOIN_ACK",
    playerName = "JoinerName-Realm",
}
```

8. Calls `NotifySessionChange()` -> `BroadcastSessionUpdate()` -- a new `SESSION_UPDATE` with the updated player list goes out to the entire guild.

### Debug log (host)

```
[HH:MM:SS] RECV | JoinerName | JOIN_REQUEST | type=JOIN_REQUEST, player=[table]
[HH:MM:SS] SEND | GUILD | SESSION_UPDATE | status=lobby, players=2, groups=0
```

---

## Phase 5: Joiner Receives JOIN_ACK + Updated Session

**Joiner receives JOIN_ACK** -> `HandleJoinAck()` (`src/Core.lua:868`)

- Clears `joinPending`, cancels the 5-second timeout timer.
- The "Join Lobby" button switches to "Leave".

**Joiner receives SESSION_UPDATE** -> `HandleSessionUpdate()` (`src/Core.lua:744`)

- Updates the local player list from the host's authoritative state.
- UI refreshes showing all players in the lobby.

### Debug log (joiner)

```
[HH:MM:SS] RECV | HostName | JOIN_ACK | type=JOIN_ACK, playerName=JoinerName-Realm
[HH:MM:SS] RECV | HostName | SESSION_UPDATE | type=SESSION_UPDATE, status=lobby, playerCount=2, players=[table]
```

---

## Phase 6: Host Spins the Wheel

**Host clicks "Spin the Wheel!"** -> `WHLSN:SpinGroups()` (`src/Core.lua:247`)

1. Filters out hidden/removed players.
2. Requires at least 5 active players.
3. Runs the group creation algorithm (`src/GroupCreator.lua`).
4. Sets `session.status = "spinning"`.
5. Broadcasts `SESSION_UPDATE` now including `groups` data.

### Message payload additions

```
{
    status = "spinning",
    groups = [
        { tank = {...}, healer = {...}, dps = [{...}, {...}, {...}] },
        ...
    ],
}
```

### Debug log (host)

```
[HH:MM:SS] SEND | GUILD | SESSION_UPDATE | status=spinning, players=N, groups=M
```

### Debug log (joiner)

```
[HH:MM:SS] RECV | HostName | SESSION_UPDATE | type=SESSION_UPDATE, status=spinning, playerCount=N, groups=[table]
```

---

## Phase 7: Session Completion

After the wheel animation finishes -> `WHLSN:CompleteSession()` (`src/Core.lua:308`)

1. Sets `session.status = "completed"`.
2. Saves results to SavedVariables via `SaveSessionResults()`.
3. Broadcasts final `SESSION_UPDATE`.

### Debug log (host)

```
[HH:MM:SS] SEND | GUILD | SESSION_UPDATE | status=completed, players=N, groups=M
```

---

## Phase 8: Leaving / Closing

### Joiner clicks "Leave"

`WHLSN:LeaveSession()` (`src/Core.lua:217`)

```
Channel: GUILD (or WHISPER)
Type: LEAVE_REQUEST
Payload: { type = "LEAVE_REQUEST", playerName = "JoinerName-Realm" }
```

Host processes via `HandleLeaveRequest()` (`src/Core.lua:902`) -- removes the player, broadcasts updated session.

### Debug log (joiner)

```
[HH:MM:SS] SEND | GUILD | LEAVE_REQUEST | player=JoinerName
```

### Debug log (host)

```
[HH:MM:SS] RECV | JoinerName | LEAVE_REQUEST | type=LEAVE_REQUEST, playerName=JoinerName-Realm
[HH:MM:SS] SEND | GUILD | SESSION_UPDATE | status=lobby, players=1, groups=0
```

### Host clicks "Close Lobby"

`WHLSN:CloseLobby()` (`src/Core.lua:194`)

```
Channel: GUILD
Type: SESSION_END
Payload: { type = "SESSION_END" }
```

All non-hosts receive via `HandleSessionEnd()` (`src/Core.lua:803`) -- marks `hostEnded = true`, UI updates to show the lobby has ended.

### Debug log (host)

```
[HH:MM:SS] SEND | GUILD | SESSION_END
```

### Debug log (joiner)

```
[HH:MM:SS] RECV | HostName | SESSION_END | type=SESSION_END
```

---

## Complete Message Type Reference

| Message | Sender | Channel | Purpose |
|---|---|---|---|
| `SESSION_UPDATE` | Host | GUILD + WHISPER (community) | Full session state sync |
| `SESSION_END` | Host | GUILD + WHISPER (community) | Lobby closed |
| `SESSION_PING` | Host | WHISPER | Notify community roster of lobby |
| `SESSION_QUERY` | Non-host | GUILD / WHISPER | Request session state (after /reload) |
| `JOIN_REQUEST` | Joiner | GUILD / WHISPER | Request to join lobby |
| `JOIN_ACK` | Host | GUILD / WHISPER | Confirm join received |
| `LEAVE_REQUEST` | Joiner | GUILD / WHISPER | Leave the lobby |
| `SPEC_UPDATE` | Joiner | GUILD / WHISPER | Update spec/role after joining |
| `ADDON_PING` | Any | GUILD | Discover who has addon installed |
| `ADDON_PONG` | Any | GUILD | Reply to discovery ping |

---

## Key Validation Rules

These are the guards in the host's message handlers that silently drop messages. If a join isn't working, check these:

- **`HandleJoinRequest`**: Sender must match `data.player.name`. Distribution must be `GUILD` or `WHISPER`. For `WHISPER`, sender must be in the community roster.
- **`HandleLeaveRequest`**: Sender must match `data.playerName`.
- **`HandleSessionUpdate`**: Sender must match `session.host` (or host must be nil). Updates from a host you explicitly left (`leftSessionHost`) are suppressed.
- **`HandleSpecUpdate`**: Same validation as `HandleJoinRequest`.
- **`OnCommReceived`**: Messages from yourself (`sender == UnitName("player")`) are always ignored.

## Throttling

- `BroadcastSessionUpdate()` throttles to one send per `COMM_THROTTLE` (0.5 seconds). Rapid changes are batched.
- `SendSessionQuery()` throttles to one per 10 seconds.
- Addon comm is queued (not sent) during boss encounters, active M+ runs, and PvP matches (`IsCommRestricted()`). The queue flushes 1 second after the encounter/run ends.

## Session Restore After /reload

- **Host**: Restores full session from SavedVariables and immediately sends a `SESSION_UPDATE`.
- **Non-host**: Sends a `SESSION_QUERY` to the guild. The host responds with a `SESSION_UPDATE`. If no response arrives within 10 seconds, the session is cleared with `"Previous lobby is no longer active."`.
