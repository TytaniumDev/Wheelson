# Palette's Journal

## Daily UX Learnings

## 2024-05-18 - Disabled Button Tooltips
**Learning:** In the WoW UI API, disabled buttons don't fire `OnEnter` or `OnLeave` motion scripts by default, meaning users don't get hover tooltips explaining why a button is disabled. This hurts accessibility and UX.
**Action:** When adding a tooltip to a button that can be disabled (like a "Spin" or "Submit" button), always call `button:SetMotionScriptsWhileDisabled(true)` so the tooltip can still provide feedback about the disabled state.
