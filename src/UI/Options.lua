local MPW = _G.Wheelson

function MPW:InitOptions()
    local panel = CreateFrame("Frame", "WheelsonOptionsPanel")

    local title = panel:CreateFontString("WheelsonOptionsTitle", "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Wheelson")

    local version = panel:CreateFontString("WheelsonOptionsVersion", "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    version:SetText("Version: " .. MPW.VERSION)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Wheelson")
    Settings.RegisterAddOnCategory(category)
end
