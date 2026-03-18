---@class Wheelson
local WHLSN = _G.Wheelson

---------------------------------------------------------------------------
-- Utility Helpers
---------------------------------------------------------------------------

--- WoW class colors (RAID_CLASS_COLORS equivalent for addon use).
WHLSN.CLASS_COLORS = {
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23, hex = "C41E3A" },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79, hex = "A330C9" },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04, hex = "FF7C0A" },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50, hex = "33937F" },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45, hex = "AAD372" },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92, hex = "3FC7EB" },
    MONK        = { r = 0.00, g = 1.00, b = 0.60, hex = "00FF98" },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73, hex = "F48CBA" },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00, hex = "FFFFFF" },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41, hex = "FFF468" },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87, hex = "0070DD" },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93, hex = "8788EE" },
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43, hex = "C69B6D" },
}

--- Format a group summary for chat output.
---@param groups WHLSNGroup[]
---@return string
function WHLSN:FormatGroupSummary(groups)
    local lines = {}
    for i, group in ipairs(groups) do
        local parts = { "Group " .. i .. ":" }

        if group.tank then
            parts[#parts + 1] = "[T] " .. group.tank.name
        end
        if group.healer then
            parts[#parts + 1] = "[H] " .. group.healer.name
        end
        for _, dps in ipairs(group.dps) do
            parts[#parts + 1] = "[D] " .. dps.name
        end

        local utils = {}
        if group:HasBrez() then utils[#utils + 1] = "BR" end
        if group:HasLust() then utils[#utils + 1] = "BL" end
        if #utils > 0 then
            parts[#parts + 1] = "(" .. table.concat(utils, "/") .. ")"
        end

        lines[#lines + 1] = table.concat(parts, " ")
    end
    return table.concat(lines, "\n")
end

--- Get a class-colored name string for display.
---@param player WHLSNPlayer
---@return string
function WHLSN:ColoredPlayerName(player)
    local cc = player.classToken and self.CLASS_COLORS[player.classToken]
    local color = cc and cc.hex or "FFFFFF"
    return "|cFF" .. color .. player.name .. "|r"
end

--- Get a class-colored name string for display.
---@param name string
---@param classToken string
---@return string
function WHLSN:ClassColoredName(name, classToken)
    local classColor = self.CLASS_COLORS[classToken]
    if classColor then
        return "|cFF" .. classColor.hex .. name .. "|r"
    end
    return name
end

--- Get role count summary string.
---@param players WHLSNPlayer[]
---@return string
function WHLSN:GetRoleCountSummary(players)
    local tanks, healers, dps = 0, 0, 0
    for _, p in ipairs(players) do
        if p:IsTankMain() then tanks = tanks + 1
        elseif p:IsHealerMain() then healers = healers + 1
        else dps = dps + 1 end
    end
    return string.format("%d Tank, %d Healer, %d DPS", tanks, healers, dps)
end

--- Get group quality score description.
---@param group WHLSNGroup
---@return string
function WHLSN:GetGroupQuality(group)
    local parts = {}
    if group:HasBrez() then parts[#parts + 1] = "Brez" end
    if group:HasLust() then parts[#parts + 1] = "Lust" end
    if group:HasRanged() then parts[#parts + 1] = "Ranged" end
    if #parts == 0 then return "Missing utilities" end
    return table.concat(parts, ", ")
end

--- Show a player tooltip on a frame. Shared by Lobby and GroupDisplay.
---@param owner table  frame to anchor tooltip to
---@param player WHLSNPlayer  player data
function WHLSN:ShowPlayerTooltip(owner, player)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local cc = player.classToken and self.CLASS_COLORS[player.classToken]
    if cc then
        GameTooltip:AddLine(player.name, cc.r, cc.g, cc.b)
    else
        GameTooltip:AddLine(player.name, 1, 1, 1)
    end

    local role = player.mainRole
    if role then
        local rc = self.RoleColors[role] or { r = 1, g = 1, b = 1 }
        GameTooltip:AddLine("Role: " .. role, rc.r, rc.g, rc.b)
    end

    if #player.offspecs > 0 then
        GameTooltip:AddLine("Offspecs: " .. table.concat(player.offspecs, ", "), 0.7, 0.7, 0.7)
    end

    if player:HasBrez() then
        GameTooltip:AddLine("Battle Rez", 0, 1, 0)
    end
    if player:HasLust() then
        GameTooltip:AddLine("Bloodlust/Heroism", 1, 0.27, 0)
    end

    GameTooltip:Show()
end

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
