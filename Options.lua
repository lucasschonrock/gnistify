-- Gnistify options. Native path: a "Gnistify" category in the game's Options ->
-- AddOns with one subcategory per header in OPTIONS (retail Settings API, settings
-- bound straight to GnistifyDB). Fallback for clients without it: a hand-made
-- checkbox window (/gnist) plus a canvas panel in the old Interface Options.
-- OPTIONS is the only thing to edit when adding a setting (plus its default in
-- Gnistify.lua); both paths are built from it.

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
    { header = "Streaks" },
    { key = "streaks",       label = "Fejr dage i træk (streaks)" },
    { header = "Professioner" },
    { key = "profShare",  label = "Del mine professioner med guilden" },
    { header = "Episk loot" },
    { key = "loot",       label = "Vis guildens episke loot i chatten" },
    { key = "lootSound",  label = "Spil lyd ved episk loot" },
    { key = "lootBanner", label = "Stor tekst midt på skærmen ved loot" },
    { key = "lootSend",   label = "Del mit episke loot med guilden" },
    { header = "Battleground (leder)" },
    { key = "callerFrame",  label = "Vis leder-vinduet i BG og dungeons" },
    { key = "callerFollow", label = "Følg leder valgt af andre" },
    { key = "callerSound",  label = "Lyd når lederen skifter mål" },
    { buttons = {
        { label = "Åbn leder-vindue", func = function() ns.OpenCallerWindow() end },
        { label = "Lav makro",        func = function() ns.MakeCallerMacro() end },
    } },
    { header = "Guild" },
    { key = "zonePresence", label = "Vis gnister i zonen når jeg skifter zone" },
    { header = "Chat" },
    { key = "emojis",    label = "Vis :gnist: emoji i chatten" },
}

-- Everything defaults to on, except these (keep in step with ADDON_LOADED in Gnistify.lua).
local DEFAULT_OFF = { callerSound = true }

-- Runs after a setting changed, so modules can react at once.
local function AfterChange()
    if ns.RefreshCaller then ns.RefreshCaller() end
    if ns.RefreshFishing then ns.RefreshFishing() end
    if ns.RefreshMinimap then ns.RefreshMinimap() end
    if ns.RefreshElite then pcall(ns.RefreshElite) end
end

-- Native settings (retail Settings API) ------------------------------------
local mainCategory          -- the "Gnistify" category, set once registered
local nativeSettings = {}   -- { { key =, setting = }, ... } to re-sync from GnistifyDB

local function AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get("Gnistify", "Version")
    if not v or v == "" or v:find("@", 1, true) then return "dev" end   -- unpackaged checkout
    return v
end

-- Registers one boolean setting bound to GnistifyDB[key]. The signature of
-- RegisterAddOnSetting changed between retail builds, so try the modern direct
-- binding first and fall back to a proxy setting with a getter and setter.
local function RegisterBool(category, key, label)
    local variable = "Gnistify_" .. key
    local vtype = (Settings.VarType and Settings.VarType.Boolean) or "boolean"
    local default = not DEFAULT_OFF[key]
    local setting
    if Settings.RegisterAddOnSetting then
        -- modern: (category, variable, variableKey, variableTbl, type, name, default)
        local ok, s = pcall(Settings.RegisterAddOnSetting, category, variable, key,
            GnistifyDB, vtype, label, default)
        if ok and type(s) == "table" then setting = s end
    end
    if setting then
        -- direct binding writes GnistifyDB[key] itself; just tell the modules
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(AfterChange)
        elseif Settings.SetOnValueChangedCallback then
            Settings.SetOnValueChangedCallback(variable, AfterChange)
        end
    elseif Settings.RegisterProxySetting then
        setting = Settings.RegisterProxySetting(category, variable, vtype, label, default,
            function() return GnistifyDB[key] and true or false end,
            function(value) GnistifyDB[key] = value and true or false; AfterChange() end)
    end
    return setting
end

local function AddCheckbox(category, setting, tooltip)
    local create = Settings.CreateCheckbox or Settings.CreateCheckBox
    return create(category, setting, tooltip)
end

local function AddButton(layout, label, func, tooltip)
    layout:AddInitializer(CreateSettingsButtonInitializer("", label, func, tooltip, true))
end

-- Builds the whole native tree from OPTIONS. Errors out (caller pcalls) if the
-- client lacks the vertical layout API.
local function BuildNative()
    local main, mainLayout = Settings.RegisterVerticalLayoutCategory("Gnistify")
    assert(main and mainLayout and mainLayout.AddInitializer
        and CreateSettingsButtonInitializer and Settings.RegisterVerticalLayoutSubcategory)

    -- front page: intro and the most used buttons
    if CreateSettingsListSectionHeaderInitializer then
        mainLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
            "Gnistify " .. AddonVersion() .. " - Længe leve gnisten!"))
    end
    AddButton(mainLayout, "Åbn PvP-tavle", function() ns.ToggleLeaderboard() end,
        "Verdens-PvP rangliste for guilden")
    AddButton(mainLayout, "Åbn leder-vindue", function() ns.OpenCallerWindow() end,
        "Skudkalderens vindue til battlegrounds")

    -- one subcategory per header; rows before the first header go on the front page
    local category, layout = main, mainLayout
    for _, o in ipairs(OPTIONS) do
        if o.header then
            category, layout = Settings.RegisterVerticalLayoutSubcategory(main, o.header)
        elseif o.buttons then
            for _, def in ipairs(o.buttons) do
                AddButton(layout, def.label, def.func, def.tooltip)
            end
        elseif o.key then
            local setting = RegisterBool(category, o.key, o.label)
            assert(setting)
            AddCheckbox(category, setting, o.tooltip)
            nativeSettings[#nativeSettings + 1] = { key = o.key, setting = setting }
        end
    end

    Settings.RegisterAddOnCategory(main)
    return main
end

-- Re-reads GnistifyDB into the settings (slash commands such as /gnist lyd change it
-- behind the panel's back).
local function SyncNative()
    for _, e in ipairs(nativeSettings) do
        local v = GnistifyDB[e.key] and true or false
        pcall(function()
            if e.setting:GetValue() ~= v then e.setting:SetValue(v) end
            if Settings.NotifyUpdate then Settings.NotifyUpdate("Gnistify_" .. e.key) end
        end)
    end
end

local function OpenNative()
    SyncNative()
    local id = mainCategory.GetID and mainCategory:GetID() or mainCategory
    if SettingsPanel and SettingsPanel:IsShown() then
        local cur = SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory()
        if cur and cur.GetParentCategory and (cur == mainCategory or cur:GetParentCategory() == mainCategory) then
            HideUIPanel(SettingsPanel)   -- toggles off when already looking at Gnistify
            return
        end
    end
    Settings.OpenToCategory(id)
end

-- Fallback: hand-made checkboxes ------------------------------------------
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
                AfterChange()
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

local function BuildFallback()
    -- stand-alone window; its height follows the number of rows
    local win = CreateFrame("Frame", "GnistifyOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(300, 100)
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
    win:SetHeight(-bottom + 40)

    function Gnistify_ToggleOptions()
        if win:IsShown() then win:Hide() else win:Show() end
    end

    -- the game's Options -> AddOns list (old Interface Options)
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
end

-- Setup --------------------------------------------------------------------
-- Must run after GnistifyDB exists (ADDON_LOADED in Gnistify.lua), so wait for login.
local started
local function Setup()
    if started then return end
    started = true
    local ok, cat = false, nil
    if Settings and Settings.RegisterVerticalLayoutCategory then
        ok, cat = pcall(BuildNative)
    end
    if ok and cat then
        mainCategory = cat
        Gnistify_ToggleOptions = OpenNative
        if SettingsPanel and SettingsPanel.HookScript then
            SettingsPanel:HookScript("OnShow", SyncNative)
        end
    else
        wipe(nativeSettings)
        BuildFallback()
    end
end

-- Until then, /gnist must not error.
function Gnistify_ToggleOptions()
    Setup()
    Gnistify_ToggleOptions()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Setup()
end)
if IsLoggedIn and IsLoggedIn() then Setup() end
