---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Main Frame Controller
---------------------------------------------------------------------------

local mainFrame = nil
local currentView = nil -- "lobby" | "wheel" | "results"
local function GetMainFrame()
    if not mainFrame then
        mainFrame = _G["WHLSNMainFrame"]
        if mainFrame then
            mainFrame.CloseButton = _G["WHLSNMainFrameCloseButton"]
            mainFrame.Content = _G["WHLSNMainFrameContent"]

            -- Restore saved position
            if WHLSN.db and WHLSN.db.profile.framePosition then
                local pos = WHLSN.db.profile.framePosition
                mainFrame:ClearAllPoints()
                mainFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
            end

            -- Save position on drag stop
            mainFrame:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                WHLSN:SaveFramePosition()
            end)
            mainFrame:SetScript("OnMouseUp", function(self)
                self:StopMovingOrSizing()
                WHLSN:SaveFramePosition()
            end)
        end
    end
    return mainFrame
end

--- Save the current frame position to SavedVariables.
function WHLSN:SaveFramePosition()
    local frame = GetMainFrame()
    if not frame or not self.db then return end

    local point, _, relPoint, x, y = frame:GetPoint()
    self.db.profile.framePosition = {
        point = point,
        relPoint = relPoint,
        x = x,
        y = y,
    }
end

--- Toggle main frame visibility.
function WHLSN:ToggleMainFrame()
    local frame = GetMainFrame()
    if not frame then
        self:Print("Error: Main frame not found.")
        return
    end

    if frame:IsShown() then
        frame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    else
        frame:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        frame.Content:Show()
        self:UpdateUI()
    end
end

--- Show the main frame (without toggling).
function WHLSN:ShowMainFrame()
    local frame = GetMainFrame()
    if not frame then return end

    if not frame:IsShown() then
        frame:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end
    frame.Content:Show()
    self:UpdateUI()
end

--- Hide all view frames so only the next shown view is visible.
function WHLSN:HideAllViews()
    self:HideLobbyView()
    self:HideWheelView()
    self:HideGroupDisplayView()
end

--- Update the UI based on current session state.
function WHLSN:UpdateUI()
    local frame = GetMainFrame()
    if not frame or not frame:IsShown() then return end

    local status = self.session.status

    if status == self.Status.LOBBY then
        if currentView ~= "lobby" then
            self:HideAllViews()
            self:ShowLobbyView(frame.Content)
            currentView = "lobby"
        end
        self:UpdateLobbyView()
    elseif status == self.Status.SPINNING then
        if currentView ~= "wheel" then
            self:HideAllViews()
            self:ShowWheelView(frame.Content)
            currentView = "wheel"
        end
        self:UpdateWheelView()
    elseif status == self.Status.COMPLETED then
        if currentView ~= "results" then
            self:HideAllViews()
            self:ShowGroupDisplayView(frame.Content)
            currentView = "results"
        end
        self:UpdateGroupDisplayView()
    else
        -- No session: show idle/join state
        if currentView ~= "lobby" then
            self:HideAllViews()
            self:ShowLobbyView(frame.Content)
            currentView = "lobby"
        end
        self:UpdateLobbyView()
    end
end

--- Reset the tracked view so the next UpdateUI recreates it.
function WHLSN:ResetView()
    currentView = nil
end

--- Register the frame with ESC key to close.
table.insert(UISpecialFrames, "WHLSNMainFrame")
