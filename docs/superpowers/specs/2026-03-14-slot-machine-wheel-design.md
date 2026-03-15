# Slot Machine Wheel Redesign

## Summary

Replace the current card-reveal animation in `src/UI/Wheel.lua` with a slot machine reel system. Five vertical reels (Tank, Healer, DPS1, DPS2, DPS3) spin simultaneously with staggered stops, showing player names scrolling vertically through a visible window. The animation mimics a physical slot machine lever pull with snap-start, full-speed blur, smooth deceleration, and an elastic landing bounce.

## Reel Structure

Each reel is a vertical scrolling window showing **3 fully visible name rows** (plus partial names peeking in from the gradient-faded edges). Each row is 20px tall; the reel viewport is 60px tall. Top and bottom 16px of the viewport are covered by overlay textures with alpha gradients (solid background color to transparent), creating a smooth fade-in/out effect for names entering and leaving the viewport. This overlay approach is used instead of `MaskTexture` because WoW's mask textures don't apply to FontStrings.

- **Role label** above each reel: TANK (blue `#3b82f6`), HEALER (green `#22c55e`), DPS (red `#ef4444`)
- **Role-colored border** around each reel
- **Dark background** with subtle role-color tint
- **Center pointer line** — gold horizontal indicator marking the landing position
- **Layout** — all 5 reels side-by-side in a single row, filling the content area width

Names display as plain white text during the spin — no role tags or utility indicators until after landing.

## Reel Candidate Population

Groups are pre-computed by `GroupCreator` before the wheel view is shown. The winner for each slot is already known; the reel animation is purely visual.

**Candidate pool per reel**: Derived from `self.session.players` by checking both `mainRole` and `offspecs`. A player appears in every reel for which they are eligible — the same player can show up in multiple reels (e.g., a Druid who can tank and DPS appears in the Tank reel and all DPS reels):
- Tank reel: players whose `mainRole` is `"tank"` OR who have `"tank"` in `offspecs`
- Healer reel: players whose `mainRole` is `"healer"` OR who have `"healer"` in `offspecs`
- DPS reels: players whose `mainRole` is `"ranged"` or `"melee"` OR who have DPS roles in `offspecs`

The UI is independent of the algorithm. The reels show all *possible* players for a role, not just those the algorithm considered. The algorithm determines the groups when spin is pressed; the UI then animates to reach that predetermined outcome.

**Winner force-insert**: The actual winner for each reel is always included in that reel's candidate list, even if role filtering would otherwise exclude them (safety net for edge cases).

**Small pool padding**: If a role pool has fewer than 5 candidates, the list is repeated/cycled to create at least 8 entries. This ensures enough names scroll through for a convincing animation even with a small candidate pool (e.g., 2 tanks → cycle to 8 entries).

**Cross-group pools**: For group N+1's reels, winners already assigned to previous groups are excluded from the candidate pool (they're placed). Players who were *not* selected remain in the pool and can appear in subsequent reels.

**Empty role slots**: If a group has no tank or no healer (`group.tank == nil`), that reel is shown in an inactive state: dark background, no spin animation, displays "(none)" in dim text. Same for unused DPS slots if a group has fewer than 3 DPS.

## Scroll Target Calculation

The winner is placed at a known index in the candidate array. The total scroll distance is pre-calculated as:

```
totalScroll = (numFullCycles * listHeight) + winnerOffset
```

Where `numFullCycles` is 8–11 (randomized for visual variety) and `winnerOffset` is the Y position that aligns the winner's FontString with the center line. The animation interpolates from 0 to `totalScroll` using the phased easing function, guaranteeing the reel lands exactly on the winner.

## Animation Physics

The spin has 4 distinct phases that mimic a mechanical slot machine lever pull:

### Phase 1 — Snap Start (0–150ms)
Sharp, near-instant acceleration. The reel snaps into full speed like a spring releasing. Aggressive ease-in (cubic or quartic). Creates the feel of a physical mechanism engaging.

### Phase 2 — Full Speed (150ms–2500ms)
Names scroll at maximum velocity. At this speed, names get reduced alpha (~0.5) to simulate motion blur. Tick sound fires on every name crossing the center line, creating a rapid clicking cadence.

### Phase 3 — Deceleration (2500ms–3700ms)
Smooth easeOutCubic slowdown. Names gradually become fully opaque and readable. Tick sounds naturally space out as velocity drops. This is the suspense phase.

### Phase 4 — Landing Bounce (3700ms–4000ms)
The reel overshoots the target name by a few pixels, then snaps back with a small elastic bounce (overshoot, slight undershoot, settle). Uses a damped spring formula: `1 - e^(-t*k) * cos(t*w)`. A landing sound plays at the settle point.

### Stagger Timing
All 5 reels snap-start simultaneously, but each reel's total duration is offset by 300ms:
- Tank: 4000ms
- Healer: 4300ms
- DPS1: 4600ms
- DPS2: 4900ms
- DPS3: 5200ms

Creates a left-to-right cascade of landing clicks.

### Post-Land Glow
After each reel's bounce settles, the winning name turns gold and a gold border fades in on that reel (~200ms). After all 5 land, a victory sound plays.

### Animation Speed Setting
All timings are scaled by the existing `animationSpeed` saved variable (same as the current implementation).

## Utility Icons

After a reel lands, if the winner has Bloodlust or Battle Rez, small (~12x12) spell icon textures fade in next to the winner's name:
- Bloodlust: `Interface\Icons\Spell_Nature_Bloodlust`
- Battle Rez: `Interface\Icons\Spell_Nature_Reincarnation`

Icons are only revealed after landing, not visible during the spin.

## Multi-Group Flow

When multiple groups are formed:

1. **Header** shows "Group 1 of N" in gold text above the reels
2. **Reels spin** with full 4-phase animation
3. **Gold glow moment** (~1.5s) — all 5 winners highlighted with gold borders/glow, utility icons fade in
4. **Collapse** (~0.5s) — reels shrink/fade into a compact summary row: "Group 1: Tankbro · Restoking · Firemage · Shadow · Zapmaster" with role-colored names, anchored at the bottom
5. **Rise** (~0.5s) — fresh reels fade in, header updates to "Group 2 of N", reels immediately snap-start
6. Repeat until all groups done

Summary rows stack upward from the bottom, remaining visible during subsequent spins so players see groups forming. Each summary row is ~18px tall. Maximum 4 summary rows visible; if more groups exist, oldest rows are hidden (they'll be visible in the final GroupDisplay view anyway).

### Single-Group Flow
Header shows "Group 1" (no "of 1"). After the gold glow moment, skip the collapse step — go directly to the 2s pause, then auto-navigate to GroupDisplay.

### Final Group Completion
After the final group's gold glow moment, a ~2s pause, then `CompleteSession()` is called and the view auto-navigates to the GroupDisplay results view. No Continue button exists.

### Skip Behavior
The Skip button is visible during the spin animation. Pressing it:
- Cancels all in-progress reel animations
- Immediately calls `CompleteSession()` and auto-navigates to GroupDisplay
- Works the same regardless of single or multi-group scenarios
- Guard against double-calls: if `CompleteSession()` has already been called (e.g., race between final reel landing and skip press), the second call is a no-op (check `self.session.status == self.Status.COMPLETED` before broadcasting)

## Sound Effects

### Primary sounds — One-Armed Bandit (Liberation of Undermine)
Look up FileDataIDs for the One-Armed Bandit boss encounter's slot machine sounds:
- Reel spinning / tick sounds
- Reel stop / landing sound
- Jackpot / victory sound

Played via `PlaySound(soundKitID)` (not `PlaySoundFile` — `PlaySound` accepts both SoundKit IDs and FileDataIDs). To find the IDs, search WoW.tools or Wowhead's sound database for "One-Armed Bandit" or "Gallywix" encounter sounds. The slot machine reel sounds are likely tagged under the Liberation of Undermine raid zone.

### Fallback sounds — SOUNDKIT
If One-Armed Bandit sound IDs cannot be found:
- Tick: subtle UI click sound per name crossing
- Landing: `SOUNDKIT.UI_EPICLOOT_TOAST`
- Victory: `SOUNDKIT.READY_CHECK`

### Sound toggle
Respects the existing `soundEnabled` saved variable.

## WoW Implementation Details

### Reel rendering
Each reel is a `Frame` containing a taller inner frame with ~10-15 `FontString` widgets. A single shared `OnUpdate` handler on the parent frame drives all 5 reels each frame (rather than 5 independent handlers), repositioning each reel's inner frame Y offset based on current velocity. When a FontString scrolls out of view, it wraps to the other end and gets the next name in the cycle.

### Gradient fade overlays
Overlay textures with alpha gradients (solid background color to transparent) at the top and bottom of each reel viewport. These sit above the FontStrings in draw layer order, creating a smooth fade effect.

### Gold glow effect
Simulated using a slightly larger texture behind the reel border with gold color and low alpha, faded in via an Alpha animation.

### Easing functions
Implemented in pure Lua as custom interpolation functions driven by `OnUpdate` elapsed time accumulation.

### Landing bounce
Damped spring formula: `1 - e^(-t*k) * cos(t*w)` where k controls damping and w controls oscillation frequency.

### Non-host viewers
The animation is entirely client-side. Each player (host and non-host) runs the reel animation independently using the same pre-computed group data received via addon comms. No synchronization between clients — visual-only animation with predetermined results.

## Scope & Public API

### Public API (changed)
- `WHLSN:ShowWheelView(parent)` — Creates reel UI and starts spin for group 1
- `WHLSN:HideWheelView()` — Cancels animations, hides the wheel frame
- `WHLSN:UpdateWheelView()` — Remains a no-op (animation is self-driven via OnUpdate)
- `WHLSN:SkipWheelAnimation()` — Cancels animations, calls CompleteSession, auto-navigates to GroupDisplay
- `WHLSN:OnWheelComplete()` — Calls CompleteSession, triggers auto-navigate to GroupDisplay
- `WHLSN:ReSpin()` — **Removed**. Re-spin functionality is removed from the addon entirely.

### Modified files
- `src/UI/Wheel.lua` — Complete rewrite. `ReSpin()` method removed.

### Unchanged files
- `src/UI/MainFrame.lua` — Same `ShowWheelView`/`HideWheelView`/`UpdateWheelView` interface
- `src/UI/MainFrame.xml` — No changes
- `src/UI/GroupDisplay.lua` — No changes
- `src/Core.lua` — Session state machine untouched
- `src/GroupCreator.lua` — Groups pre-computed before wheel view

### Not in scope
- No changes to group formation logic
- No changes to addon comms / session management
- No new saved variables (existing `animationSpeed` and `soundEnabled` reused)
- No custom texture files — uses WoW built-in textures and icons
