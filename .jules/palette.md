## 2024-05-18 - Tooltips for Disabled Buttons
**Learning:** In the WoW addon UI context, disabled buttons without explanation leave users confused about what action they need to take next.
**Action:** When disabling a primary action button (like "Spin the Wheel"), always attach an `OnEnter` script that checks `not self:IsEnabled()` and displays a helpful tooltip (e.g., "Need at least 5 players to spin") explaining the prerequisite.
