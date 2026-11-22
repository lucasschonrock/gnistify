-- Gnistify options: a small settings window (/gnist) with a checkbox per
-- feature. The same checkboxes are also added to the game's own
-- Options -> AddOns list when the client supports it.

local ns = select(2, ...)
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
    { key = "killBanner", label = "Stor tekst midt på skærmen ved drab" },
    { key = "killsSend", label = "Del mine drab med guilden" },
    { key = "crownSound", label = "Spil lyd ved ny leder på PvP-tavlen" },
    { key = "eliteFrames", label = "Elite-drage om PvP-ledernes portræt" },
    { buttons = {
        { label = "Åbn PvP-tavle", func = function() ns.ToggleLeaderboard() end },
    } },
    { key = "minimapIcon", label = "Vis gnist-knap ved minimap" },
    { header = "Fiskeri" },
    { key = "fishing",       label = "Vis guildens fangster og fiske-dings" },
    { key = "fishingSound",  label = "Spil lyd ved store fangster" },
    { key = "fishingBanner", label = "Stor tekst midt på skærmen ved fangst" },
    { key = "fishingSend",   label = "Del mine fangster med guilden" },
    { key = "fishingSplash", label = "Højere plask når jeg fisker" },
    { header = "Battleground (leder)" },
    { key = "callerFrame",  label = "Vis leder-vinduet i BG og dungeons" },
    { key = "callerFollow", label = "Følg leder valgt af andre" },
    { key = "callerSound",  label = "Lyd når lederen skifter mål" },
    { buttons = {
        { label = "Åbn leder-vindue", func = function() ns.OpenCallerWindow() end },
        { label = "Lav makro",        func = function() ns.MakeCallerMacro() end },
    } },
    { key = "bgQueue",      label = "Vis BG-kø nedtælling (kun for ledere)" },
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
        elseif o.buttons then
            local bx = x + 4
            for _, def in ipairs(o.buttons) do
                local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
                b:SetSize(124, 22)
                b:SetPoint("TOPLEFT", bx, y - 2)
                b:SetText(def.label)
                b:SetScript("OnClick", def.func)
                bx = bx + 130
            end
            y = y - 28
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
                if ns.RefreshCaller then ns.RefreshCaller() end
                if ns.RefreshFishing then ns.RefreshFishing() end
                if ns.RefreshMinimap then ns.RefreshMinimap() end
                if ns.RefreshElite then pcall(ns.RefreshElite) end
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
win:SetSize(300, 802)
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
