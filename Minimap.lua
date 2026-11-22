-- Gnistify minimap button: left click opens the PvP-tavle, right click the
-- settings, shift-click or middle click turns the tracking switch on/off. Drag it around the minimap. The tooltip shows who holds the titles.
-- Uses LibDataBroker + LibDBIcon when another addon has loaded them (Leatrix Plus,
-- TomTom, AtlasLoot ...), so button collectors like Leatrix' show our own tooltip
-- instead of "This is a custom button". Otherwise a hand-made button, like Spy's.
-- Setting: minimapIcon. Position (degrees around the minimap): GnistifyDB.minimapAngle
-- (hand-made) or GnistifyDB.minimapLDB.minimapPos (LibDBIcon).

local ns = select(2, ...)

local DEFAULT_ANGLE = 200

local button
local dbi            -- LibDBIcon-1.0, when it is used
local ICON = "Interface\\AddOns\\Gnistify\\icon"
-- Trim the tips of the four gold spikes so the round emblem fills the button.
local COORDS = { 0.06, 0.94, 0.06, 0.94 }

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

local function FillTooltip(tt)
    tt:AddLine("|cffffcc00Gnist|r|cffff6600ify|r")
    local holders = ns.TitleHolders and ns.TitleHolders() or {}
    if #holders == 0 then
        tt:AddLine("Ingen titler endnu. Gnisten venter...", 0.7, 0.7, 0.7)
    end
    for _, h in ipairs(holders) do
        tt:AddDoubleLine(h.title, h.name .. " (" .. h.n .. ")",
            1, 0.8, 0, 1, 1, 1)
    end
    tt:AddLine(" ")
    local on = GnistifyDB and GnistifyDB.tracking
    tt:AddDoubleLine("Skift sporing", on and "til" or "fra",
        1, 0.8, 0, on and 0 or 1, on and 1 or 0.3, on and 0 or 0.3)
    tt:AddLine(" ")
    tt:AddLine("Venstreklik: PvP-tavle", 0.8, 0.8, 0.8)
    tt:AddLine("Højreklik: indstillinger", 0.8, 0.8, 0.8)
    tt:AddLine("Shift-klik / midterklik: sporing til/fra", 0.8, 0.8, 0.8)
    tt:AddLine("Træk: flyt knappen", 0.6, 0.6, 0.6)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    FillTooltip(GameTooltip)
    GameTooltip:Show()
end

-- Shared by both buttons. Returns true when the tooltip should be redrawn.
local function HandleClick(mouseButton)
    if mouseButton == "MiddleButton" or (mouseButton == "LeftButton" and IsShiftKeyDown()) then
        ns.ToggleTracking()
        return true
    elseif mouseButton == "RightButton" then
        Gnistify_ToggleOptions()
    else
        ns.ToggleLeaderboard()
    end
end

-- LibDBIcon path. Only when both libraries are already loaded by some other addon;
-- Gnistify doesn't ship them.
local function CreateLDB()
    local stub = _G.LibStub
    if not stub then return false end
    local ldb = stub("LibDataBroker-1.1", true)
    local lib = stub("LibDBIcon-1.0", true)
    if not (ldb and lib and ldb.NewDataObject and lib.Register) then return false end
    local ok = pcall(function()
        local obj = ldb:GetDataObjectByName("Gnistify") or ldb:NewDataObject("Gnistify", {
            type = "launcher",
            label = "Gnistify",
            text = "Gnistify",
            icon = ICON,
            iconCoords = COORDS,
            OnClick = function(frame, mouseButton)
                local tt = dbi and dbi.tooltip or GameTooltip
                if HandleClick(mouseButton) and frame and tt.IsOwned and tt:IsOwned(frame) then
                    local enter = frame:GetScript("OnEnter")
                    if enter then enter(frame) end
                end
            end,
            OnTooltipShow = function(tt) if tt and tt.AddLine then FillTooltip(tt) end end,
        })
        GnistifyDB.minimapLDB = GnistifyDB.minimapLDB
            or { minimapPos = GnistifyDB.minimapAngle or DEFAULT_ANGLE }
        GnistifyDB.minimapLDB.hide = not GnistifyDB.minimapIcon
        if not lib:IsRegistered("Gnistify") then
            lib:Register("Gnistify", obj, GnistifyDB.minimapLDB)
        end
    end)
    if ok then dbi = lib end
    return ok
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

    local icon = button:CreateTexture("GnistifyMinimapButtonIcon", "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)
    icon:SetTexCoord(unpack(COORDS))

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(self, mouseButton)
        if HandleClick(mouseButton) and GameTooltip:IsOwned(self) then ShowTooltip(self) end
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
    if dbi then
        GnistifyDB.minimapLDB.hide = not GnistifyDB.minimapIcon
        if GnistifyDB.minimapIcon then dbi:Show("Gnistify") else dbi:Hide("Gnistify") end
        return
    end
    if not button then
        if not GnistifyDB.minimapIcon then return end
        if CreateLDB() then return end
        Create()
        if not button then return end
    end
    Place()
    button:SetShown(GnistifyDB.minimapIcon and true or false)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() ns.RefreshMinimap() end)
