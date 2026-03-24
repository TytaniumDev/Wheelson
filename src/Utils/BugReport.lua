---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Bug Report Formatting & Clipboard
---------------------------------------------------------------------------

--- Format a Lua table literal for a string array (e.g., {"tank", "healer"}).
---@param arr table
---@return string
local function luaArrayStr(arr)
    if #arr == 0 then return "{}" end
    local parts = {}
    for _, v in ipairs(arr) do
        parts[#parts + 1] = '"' .. tostring(v) .. '"'
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Format the human-readable markdown section of a bug report.
local function FormatBugReportMarkdown(self, snapshot, groups, lines)
    local fullCount = 0
    local incompleteCount = 0
    for _, g in ipairs(groups) do
        if g:IsComplete() then
            fullCount = fullCount + 1
        else
            incompleteCount = incompleteCount + 1
        end
    end

    local groupCountDesc = #groups .. " (" .. fullCount .. " full"
    if incompleteCount > 0 then
        groupCountDesc = groupCountDesc .. ", " .. incompleteCount .. " incomplete"
    end
    groupCountDesc = groupCountDesc .. ")"

    lines[#lines + 1] = "## Bad Grouping Report"
    lines[#lines + 1] = "- **Host:** " .. (snapshot.host or "Unknown")
    lines[#lines + 1] = "- **Players:** " .. (snapshot.playerCount or #snapshot.players)
    lines[#lines + 1] = "- **Groups created:** " .. groupCountDesc
    lines[#lines + 1] = "- **Timestamp:** "
        .. (snapshot.timestamp and date("%Y-%m-%d %H:%M:%S", snapshot.timestamp) or "Unknown")

    lines[#lines + 1] = "### Players"
    lines[#lines + 1] = "| Name | Main Role | Offspecs | Utilities |"
    lines[#lines + 1] = "|------|-----------|----------|-----------|"
    for _, pd in ipairs(snapshot.players) do
        local offspecs = pd.offspecs and #pd.offspecs > 0 and table.concat(pd.offspecs, ", ") or "-"
        local utilities = pd.utilities and #pd.utilities > 0 and table.concat(pd.utilities, ", ") or "-"
        lines[#lines + 1] = "| " .. pd.name .. " | " .. (pd.mainRole or "none") .. " | "
            .. offspecs .. " | " .. utilities .. " |"
    end
    lines[#lines + 1] = ""

    lines[#lines + 1] = "### Groups"
    lines[#lines + 1] = self:FormatGroupSummary(groups)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "### Last Groups (duplicate-avoidance context)"
    if #snapshot.lastGroups > 0 then
        local prevGroups = {}
        for _, gd in ipairs(snapshot.lastGroups) do
            prevGroups[#prevGroups + 1] = WHLSN.Group.FromDict(gd)
        end
        lines[#lines + 1] = self:FormatGroupSummary(prevGroups)
    else
        lines[#lines + 1] = "None - first lobby"
    end
    lines[#lines + 1] = ""
end

--- Format the Lua test case section of a bug report.
local function FormatBugReportTestCase(snapshot, lines)
    local function formatPlayerNew(pd)
        if not pd then return "nil" end
        return "Player:New("
            .. '"' .. pd.name .. '", '
            .. (pd.mainRole and ('"' .. pd.mainRole .. '"') or "nil") .. ", "
            .. luaArrayStr(pd.offspecs or {}) .. ", "
            .. luaArrayStr(pd.utilities or {}) .. ")"
    end

    lines[#lines + 1] = "--- LUA TEST CASE ---"
    lines[#lines + 1] = "```lua"
    lines[#lines + 1] = "-- Paste into tests/test_group_creator.lua"
    lines[#lines + 1] = 'it("should handle reported bad grouping", function()'

    lines[#lines + 1] = "    local players = {"
    for _, pd in ipairs(snapshot.players) do
        lines[#lines + 1] = "        " .. formatPlayerNew(pd) .. ","
    end
    lines[#lines + 1] = "    }"

    if #snapshot.lastGroups > 0 then
        lines[#lines + 1] = "    local lastGroups = {"
        for _, gd in ipairs(snapshot.lastGroups) do
            lines[#lines + 1] = "        Group:New("
            lines[#lines + 1] = "            " .. formatPlayerNew(gd.tank) .. ","
            lines[#lines + 1] = "            " .. formatPlayerNew(gd.healer) .. ","
            lines[#lines + 1] = "            {"
            if gd.dps then
                for _, dpsDict in ipairs(gd.dps) do
                    lines[#lines + 1] = "                " .. formatPlayerNew(dpsDict) .. ","
                end
            end
            lines[#lines + 1] = "            }"
            lines[#lines + 1] = "        ),"
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = '    WHLSN:SetLastGroups(lastGroups)'
    end

    lines[#lines + 1] = "    for trial = 1, 20 do"
    lines[#lines + 1] = "        local groups = WHLSN:CreateMythicPlusGroups(players)"
    lines[#lines + 1] = "        -- TODO: Add assertions for the invariant that was violated"
    lines[#lines + 1] = "        -- Bad output had " .. #snapshot.groups .. " groups from "
        .. #snapshot.players .. " players"
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = "end)"
    lines[#lines + 1] = "```"
end

--- Format a bug report from an algorithm snapshot.
--- Returns a string with two sections: human-readable markdown and a Lua test case.
---@param snapshot table  algorithmSnapshot captured at spin time
---@return string
function WHLSN:FormatBugReport(snapshot)
    local Group = WHLSN.Group
    local lines = {}

    local groups = {}
    for _, gd in ipairs(snapshot.groups) do
        groups[#groups + 1] = Group.FromDict(gd)
    end

    FormatBugReportMarkdown(self, snapshot, groups, lines)
    FormatBugReportTestCase(snapshot, lines)

    return table.concat(lines, "\n")
end

--- Get or create the shared clipboard popup (WoW has no direct clipboard API).
--- Shows a dialog with a selectable EditBox so the user can Ctrl+C.
local function getClipboardFrame(self)
    if not self.clipboardFrame then
        local frame = CreateFrame("Frame", "WHLSNClipboardFrame", UIParent, "BackdropTemplate")
        frame:SetSize(450, 300)
        frame:SetPoint("CENTER")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        frame:SetBackdropColor(0, 0, 0, 1)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetToplevel(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:Hide()

        frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.titleText:SetPoint("TOP", 0, -12)

        local xButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        xButton:SetPoint("TOPRIGHT", -2, -2)

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("BOTTOM", 0, 36)
        hint:SetText("Press Ctrl+A to select all, then Ctrl+C to copy")

        local scrollFrame = CreateFrame("ScrollFrame", "WHLSNClipboardScrollFrame", frame,
            "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", -32, 52)

        local editBox = CreateFrame("EditBox", "WHLSNClipboardEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetMaxLetters(0)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("ChatFontNormal")
        scrollFrame:SetScript("OnSizeChanged", function(_, w)
            editBox:SetWidth(w - 20)
        end)
        editBox:SetScript("OnEscapePressed", function()
            frame:Hide()
        end)
        scrollFrame:SetScrollChild(editBox)
        editBox:SetWidth(scrollFrame:GetWidth() - 20)

        UISpecialFrames[#UISpecialFrames + 1] = "WHLSNClipboardFrame"

        local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        closeButton:SetSize(80, 22)
        closeButton:SetPoint("BOTTOM", 0, 10)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function()
            frame:Hide()
        end)

        self.clipboardFrame = frame
        self.clipboardEditBox = editBox
    end
    return self.clipboardFrame
end

function WHLSN:ShowClipboardPopup(title, text)
    local frame = getClipboardFrame(self)
    frame.titleText:SetText("|cFFFFD100" .. title .. "|r")
    frame:Show()
    self.clipboardEditBox:SetText(text)
    self.clipboardEditBox:HighlightText()
    self.clipboardEditBox:SetFocus()
end

--- Copy a bug report to the clipboard and show instructions.
---@param snapshot table  algorithmSnapshot from session
function WHLSN:CopyReportToClipboard(snapshot)
    self:ShowClipboardPopup("Copy Bug Report", self:FormatBugReport(snapshot))
end
