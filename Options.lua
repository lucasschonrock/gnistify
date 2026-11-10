-- Gnistify options: a small settings window (/gnist) with a checkbox per
-- feature. The same checkboxes are also added to the game's own
-- Options -> AddOns list when the client supports it.

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"

local OPTIONS = {
    { header = "Ding" },
    { key = "dings",     label = "Vis når nogen i guilden dinger" },
    { key = "sound",     label = "Spil ding-lyd" },
    { key = "banner",    label = "Stor tekst midt på skærmen" },
    { key = "guildChat", label = "Skriv i guild chat når jeg dinger" },
    { header = "PvP" },
    { key = "kills",     label = "Vis guildens drab i chatten" },
    { key = "killSound", label = "Spil lyd ved drab" },
    { key = "killsSend", label = "Del mine drab med guilden" },
    { header = "Chat" },
    { key = "emojis",    label = "Vis :gnist: emoji i chatten" },
}

-- Puts the checkboxes on `parent`, starting at (x, y). Returns the y below them.
local function Build(parent, x, y)
    local checks = {}
    for _, o in ipairs(OPTIONS) do
        if o.header then
            y = y - 6
            local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            h:SetPoint("TOPLEFT", x, y)
            h:SetText(o.header)
            y = y - 20
        else
            local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            cb:SetSize(26, 26)
            cb:SetPoint("TOPLEFT", x, y)
            local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
            text:SetText(o.label)
            cb.key = o.key
            cb:SetScript("OnClick", function(self)
                GnistifyDB[self.key] = self:GetChecked() and true or false
            end)
            checks[#checks + 1] = cb
            y = y - 26
        end
    end
    parent:HookScript("OnShow", function()
        for _, cb in ipairs(checks) do cb:SetChecked(GnistifyDB[cb.key]) end
    end)
    return y
end

-- Stand-alone window -----------------------------------------------------
local win = CreateFrame("Frame", "GnistifyOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(300, 356)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetClampedToScreen(true)
win:Hide()
tinsert(UISpecialFrames, "GnistifyOptionsFrame")   -- Esc closes it

local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -5)
title:SetText(GNIST_ICON .. " |cffffcc00Gnist|r|cffff6600ify|r")

local bottom = Build(win, 16, -30)

local footer = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
footer:SetPoint("TOPLEFT", 18, bottom - 8)
footer:SetText("Længe leve gnisten!")

function Gnistify_ToggleOptions()
    if win:IsShown() then win:Hide() else win:Show() end
end

-- Game's Options -> AddOns list ------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "Gnistify"
local ptitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
ptitle:SetPoint("TOPLEFT", 16, -16)
ptitle:SetText(GNIST_ICON .. " Gnistify")
Build(panel, 16, -44)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Gnistify")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
