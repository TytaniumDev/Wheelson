## 2024-05-18 - Tooltips on Disabled Buttons
**Learning:** In the WoW UI API, disabled buttons do not receive motion events by default, making it impossible to show a tooltip explaining *why* the button is disabled without special handling.
**Action:** Call `button:SetMotionScriptsWhileDisabled(true)` on buttons that can be disabled, and check `if not self:IsEnabled()` in the `OnEnter` script to show a helpful explanatory tooltip. Ensure `OnLeave` verifies `GameTooltip:GetOwner() == self` before hiding.
