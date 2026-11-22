-- Gnistify minimap button: left click opens the PvP-tavle, right click the
-- settings, shift-click or middle click turns the tracking switch on/off. Drag it around the minimap. The tooltip shows who holds the titles.
-- Built by hand (no LibDBIcon), like Spy's button in Spy/Forever.lua.
-- Setting: minimapIcon. Position (degrees around the minimap): GnistifyDB.minimapAngle.

local ns = select(2, ...)

local DEFAULT_ANGLE = 200

local button

local function Place()
    local angle = math.rad(GnistifyDB.minimapAngle or DEFAULT_ANGLE)
    local r = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function AngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffffcc00Gnist|r|cffff6600ify|r")
    local holders = ns.TitleHolders and ns.TitleHolders() or {}
    if #holders == 0 then
        GameTooltip:AddLine("Ingen titler endnu. Gnisten venter...", 0.7, 0.7, 0.7)
    end
    for _, h in ipairs(holders) do
        GameTooltip:AddDoubleLine(h.title, h.name .. " (" .. h.n .. ")",
            1, 0.8, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    local on = GnistifyDB and GnistifyDB.tracking
    GameTooltip:AddDoubleLine("Skift sporing", on and "til" or "fra",
        1, 0.8, 0, on and 0 or 1, on and 1 or 0.3, on and 0 or 0.3)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Venstreklik: PvP-tavle", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Højreklik: indstillinger", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-klik / midterklik: sporing til/fra", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Træk: flyt knappen", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Create()
    if button or not Minimap then return end
    button = CreateFrame("Button", "GnistifyMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Gnistify\\emojis\\gnist")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "MiddleButton" or (mouseButton == "LeftButton" and IsShiftKeyDown()) then
            ns.ToggleTracking()
            if GameTooltip:IsOwned(self) then ShowTooltip(self) end
        elseif mouseButton == "RightButton" then
            Gnistify_ToggleOptions()
        else
            ns.ToggleLeaderboard()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            GnistifyDB.minimapAngle = AngleFromCursor()
            Place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Called at login and when the setting changes in the options window
function ns.RefreshMinimap()
    if not GnistifyDB then return end
    if not button then
        if not GnistifyDB.minimapIcon then return end
        Create()
        if not button then return end
    end
    Place()
    button:SetShown(GnistifyDB.minimapIcon and true or false)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() ns.RefreshMinimap() end)
