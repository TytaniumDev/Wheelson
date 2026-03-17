---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Debug Panel
-- Right-click minimap icon to toggle.
-- Three tabs: State, Comm Log, WoW API
---------------------------------------------------------------------------

local debugFrame = nil

-- Comm log storage (populated by hooks, capped at 200 entries)
WHLSN.debugLog = {}
local DEBUG_LOG_MAX = 200

local MIN_WIDTH = 400
local MIN_HEIGHT = 300
local MAX_WIDTH = 800
local MAX_HEIGHT = 600

---------------------------------------------------------------------------
-- GenerateStateText — decomposed into section generators
---------------------------------------------------------------------------

local function GenerateCommLogText()
    if #WHLSN.debugLog == 0 then
        return "(No comm messages logged yet)\n\nMessages will appear here as they are sent/received."
    end

    local lines = {}
    for _, entry in ipairs(WHLSN.debugLog) do
        lines[#lines + 1] = entry
    end
    return table.concat(lines, "\n")
end


---------------------------------------------------------------------------
-- Comm Log Hooks
---------------------------------------------------------------------------

local function FormatLogPayload(data)
    if type(data) ~= "table" then return tostring(data) end
    local parts = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            parts[#parts + 1] = k .. "=[table]"
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    local result = table.concat(parts, ", ")
    if #result > 200 then
        result = result:sub(1, 197) .. "..."
    end
    return result
end

local function AddLogEntry(entry)
    WHLSN.debugLog[#WHLSN.debugLog + 1] = entry
    while #WHLSN.debugLog > DEBUG_LOG_MAX do
        table.remove(WHLSN.debugLog, 1)
    end

    -- Auto-refresh if comm tab is visible
    if debugFrame and debugFrame:IsShown() and currentTab == "comm" then
        debugFrame.editBox:SetText(GenerateCommLogText())
        -- Auto-scroll to bottom
        debugFrame.scrollFrame:SetVerticalScroll(
            debugFrame.scrollFrame:GetVerticalScrollRange()
        )
    end
end

local function SetupCommHooks()
    hooksecurefunc(WHLSN, "OnCommReceived", function(_, prefix, message, _, sender)
        if prefix ~= WHLSN.COMM_PREFIX then return end
        local success, data = WHLSN:Deserialize(message)
        local payload = success and FormatLogPayload(data) or "(deserialize failed)"
        local entry = string.format("[%s] RECV | %s | %s | %s",
            date("%H:%M:%S"), sender, success and data.type or "?", payload)
        AddLogEntry(entry)
    end)

    hooksecurefunc(WHLSN, "SendSessionUpdate", function(_)
        local playerCount = #WHLSN.session.players
        local groupCount = #WHLSN.session.groups
        local entry = string.format(
            "[%s] SEND | GUILD | SESSION_UPDATE | status=%s, players=%d, groups=%d",
            date("%H:%M:%S"), tostring(WHLSN.session.status), playerCount, groupCount)
        AddLogEntry(entry)
    end)

    hooksecurefunc(WHLSN, "BroadcastSessionEnd", function(_)
        local entry = string.format("[%s] SEND | GUILD | SESSION_END", date("%H:%M:%S"))
        AddLogEntry(entry)
    end)

    hooksecurefunc(WHLSN, "LeaveSession", function(_)
        local entry = string.format("[%s] SEND | GUILD | LEAVE_REQUEST | player=%s",
            date("%H:%M:%S"), UnitName("player") or "?")
        AddLogEntry(entry)
    end)

    hooksecurefunc(WHLSN, "RequestJoin", function(_)
        local entry = string.format("[%s] SEND | GUILD | JOIN_REQUEST | player=%s",
            date("%H:%M:%S"), UnitName("player") or "?")
        AddLogEntry(entry)
    end)
end

---------------------------------------------------------------------------
-- Frame Creation — decomposed
---------------------------------------------------------------------------



local function CreateDebugScrollContent(frame)
    local scrollFrame = CreateFrame(
        "ScrollFrame", "WHLSNDebugScrollFrame", frame, "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    frame.scrollFrame = scrollFrame

    local editBox = CreateFrame("EditBox", "WHLSNDebugEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnChar", function(self) self:SetText(self.lastText or "") end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.lastText or "")
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox
end

local function CreateDebugResizeHandle(frame)
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT")
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    end)
end

local function CreateDebugBottomButtons(frame)
    frame.copyAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.copyAllBtn:SetSize(80, 24)
    frame.copyAllBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.copyAllBtn:SetText("Copy All")
    frame.copyAllBtn:SetScript("OnClick", function()
        frame.editBox:HighlightText()
        frame.editBox:SetFocus()
        WHLSN:Print("Text selected. Press Ctrl+C to copy.")
    end)

    frame.refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refreshBtn:SetSize(80, 24)
    frame.refreshBtn:SetPoint("BOTTOMRIGHT", frame.copyAllBtn, "BOTTOMLEFT", -4, 0)
    frame.refreshBtn:SetText("Refresh")
    frame.refreshBtn:SetScript("OnClick", function()
        WHLSN:RefreshDebugPanel()
    end)

    frame.clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clearBtn:SetSize(80, 24)
    frame.clearBtn:SetPoint("BOTTOMLEFT", 8, 8)
    frame.clearBtn:SetText("Clear")
    frame.clearBtn:SetScript("OnClick", function()
        wipe(WHLSN.debugLog)
        WHLSN:RefreshDebugPanel()
    end)
end

local function CreateDebugFrame()
    local frame = CreateFrame("Frame", "WHLSNDebugPanel", UIParent, "BackdropTemplate")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cFFFFD100Wheelson Debug|r")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)


    CreateDebugScrollContent(frame)
    CreateDebugResizeHandle(frame)
    CreateDebugBottomButtons(frame)

    return frame
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Refresh the debug panel content for the current tab.
function WHLSN:RefreshDebugPanel()
    if not debugFrame or not debugFrame:IsShown() then return end


    local text = GenerateCommLogText()
    debugFrame.editBox.lastText = text
    debugFrame.editBox:SetText(text)
    debugFrame.editBox:SetCursorPosition(0)
    debugFrame.clearBtn:SetShown(true)
end

--- Toggle debug frame visibility. Overrides stub in Core.lua.
function WHLSN:ToggleDebugFrame()
    if not debugFrame then
        debugFrame = CreateDebugFrame()
        SetupCommHooks()
        UISpecialFrames[#UISpecialFrames + 1] = "WHLSNDebugPanel"
    end

    if debugFrame:IsShown() then
        debugFrame:Hide()
    else
        debugFrame:Show()
        self:RefreshDebugPanel()
    end
end
