# Wheelson

**Form balanced Mythic+ groups from your guild with a wheel-spin reveal.**

Wheelson takes the guesswork out of splitting your guild into Mythic+ groups. Invite your guildies to a session, hit spin, and Wheelson builds balanced 5-player groups — complete with an animated reveal. Every group gets a tank, a healer, and DPS, with smart prioritization for battle rez, bloodlust, and ranged coverage. No more arguing over comps in Discord.

## How It Works

### 1. Start a Session

Type `/wheelson` (or `/wheel`) to open the addon. Click **Start Session** to create a new lobby. Your session is automatically broadcast to every guild member running Wheelson.

### 2. Gather Players

Guild members see your active session and can join with one click. The lobby shows everyone who's in — their role, offspecs, and utilities (brez/lust) — updated in real time. As the host, you can kick players or lock the lobby when you're ready.

### 3. Spin the Wheel

Once you have 5 or more players, hit **Spin the Wheel**. Wheelson runs its group formation algorithm and reveals the results with an animated sequence — groups appear one at a time, players fading in slot by slot, with sound cues to build the tension.

### 4. Get Into Groups

After the reveal, everyone can see their assigned group. One click to **invite your group** to a party, **post results to guild chat**, or **copy to clipboard**. The host can re-spin for fresh groups or start a new session entirely.

## The Group Algorithm

Wheelson doesn't just randomly shuffle players — it fills each group in a specific priority order to maximize composition quality:

1. **Tanks** — Every group gets a tank first. Players whose main spec is tank are assigned before offspec tanks.
2. **Bloodlust** — Each group gets a lust provider if one is available (Shaman, Mage, Evoker, Hunter).
3. **Battle Rez** — Each group gets a brez provider if one is available (Death Knight, Druid, Warlock, Paladin).
4. **Healers** — Every group gets a healer. Main-spec healers are placed before offspec.
5. **Ranged DPS** — The algorithm tries to get at least one ranged DPS per group for better coverage.
6. **Remaining DPS** — Remaining slots are filled with any available DPS.

If there aren't enough players to form full 5-player groups, leftover players are placed into partial groups with tank and healer slots prioritized.

### Avoiding Repeat Comps

Wheelson remembers your recent group history. When forming new groups, it actively avoids putting the same players together again — so you get variety across runs instead of the same comp every time.

## Features

- **Real-time guild sync** — Session state is broadcast to all guild members via addon-to-addon communication. No setup required beyond installing the addon.
- **Role-aware** — Automatically detects each player's current spec and maps it to tank, healer, ranged DPS, or melee DPS. Supports offspecs for flexible players.
- **Animated reveal** — Groups are revealed sequentially with fade-in animations and sound effects. Skip the animation if you're impatient, or adjust the speed in settings.
- **One-click party invites** — After groups are formed, invite your entire group to a party with a single button.
- **Session history** — Your last 10 sessions are saved. Review past group assignments any time.
- **Minimap button** — Quick access to open the addon or check session status.
- **Test mode** — Try out the addon solo with simulated players to see how it works before running a real session.

## Installation

Install from [CurseForge](https://www.curseforge.com/wow/addons/wheelson) or [Wago](https://addons.wago.io/addons/wheelson) using your preferred addon manager.

**Requirements:** World of Warcraft 12.0 (Midnight). All guild members who want to participate need Wheelson installed.

## Slash Commands

| Command | Description |
|---------|-------------|
| `/wheelson` | Open or close the Wheelson window |
| `/wheel` | Shorthand alias |

