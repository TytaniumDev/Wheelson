# Slot Machine Wheel Redesign

## Summary

Replace the current card-reveal animation in `src/UI/Wheel.lua` with a slot machine reel system. Five vertical reels (Tank, Healer, DPS1, DPS2, DPS3) spin simultaneously with staggered stops, showing player names scrolling vertically through a visible window. The animation mimics a physical slot machine lever pull with snap-start, full-speed blur, smooth deceleration, and an elastic landing bounce.

## Reel Structure

Each reel is a vertical scrolling window showing **3 visible name rows** at a time:

- **Role label** above each reel: TANK (blue `#3b82f6`), HEALER (green `#22c55e`), DPS (red `#ef4444`)
- **Role-colored border** around each reel
- **Dark background** with subtle role-color tint
- **Center pointer line** — gold horizontal indicator marking the landing position
- **Gradient fade** at top and bottom edges so names appear/disappear smoothly
- **Layout** — all 5 reels side-by-side in a single row, filling the content area width

Each reel is populated with all candidates eligible for that role slot. Names display as plain white text during the spin — no role tags or utility indicators until after landing.

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

Summary rows stack upward from the bottom, remaining visible during subsequent spins so players see groups forming.

### Final Group Completion
After the final group's gold glow moment, a ~2s pause, then auto-navigate to the GroupDisplay results view. No Continue button needed. The Skip button remains available during animation. Host sees Re-spin button during the glow moment.

## Sound Effects

### Primary sounds — One-Armed Bandit (Liberation of Undermine)
Look up FileDataIDs for the One-Armed Bandit boss encounter's slot machine sounds:
- Reel spinning / tick sounds
- Reel stop / landing sound
- Jackpot / victory sound

Played via `PlaySoundFile(fileDataID)`.

### Fallback sounds — SOUNDKIT
If One-Armed Bandit FileDataIDs cannot be found:
- Tick: subtle UI click sound per name crossing
- Landing: `SOUNDKIT.UI_EPICLOOT_TOAST`
- Victory: `SOUNDKIT.READY_CHECK`

### Sound toggle
Respects the existing `soundEnabled` saved variable.

## WoW Implementation Details

### Reel rendering
Each reel is a `Frame` containing a taller inner frame with ~10-15 `FontString` widgets. The `OnUpdate` handler repositions the inner frame's Y offset each frame based on current velocity. When a FontString scrolls out of view, it wraps to the other end and gets the next name in the cycle.

### Gradient fade masks
Use `MaskTexture` on the reel frame for top/bottom edge fade. Alternatively, overlay textures with alpha gradients (solid-to-transparent).

### Gold glow effect
Simulated using a slightly larger texture behind the reel border with gold color and low alpha, faded in via an Alpha animation.

### Easing functions
Implemented in pure Lua as custom interpolation functions driven by `OnUpdate` elapsed time accumulation.

### Landing bounce
Damped spring formula: `1 - e^(-t*k) * cos(t*w)` where k controls damping and w controls oscillation frequency.

## Scope

### Modified files
- `src/UI/Wheel.lua` — Complete rewrite with same public API

### Unchanged files
- `src/UI/MainFrame.lua` — Same `ShowWheelView`/`HideWheelView`/`UpdateWheelView` interface
- `src/UI/MainFrame.xml` — No changes
- `src/UI/GroupDisplay.lua` — No changes, auto-navigated to after final group
- `src/Core.lua` — Session state machine untouched
- `src/GroupCreator.lua` — Groups pre-computed before wheel view

### Not in scope
- No changes to group formation logic
- No changes to addon comms / session management
- No new saved variables (existing `animationSpeed` and `soundEnabled` reused)
- No custom texture files — uses WoW built-in textures and icons
