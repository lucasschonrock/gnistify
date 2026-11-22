-- Gnistify tracking: switches the minimap tracking every 5 sec between the
-- ones you tick (Find Herbs, Find Minerals, Track Humanoids), out of combat.
-- Like the Forager addon, but small. Settings are account wide; each character
-- only rotates through the ones it knows, so Track Humanoids simply doesn't
-- take part on a non-hunter (or a druid outside Cat Form).
--
-- The switch is C_Minimap.SetTracking, the call Blizzard's tracking menu makes.
-- Some clients refuse it from a timer and only allow it in a key press. If the
-- game blocks it (ADDON_ACTION_BLOCKED) or three timed switches in a row don't
-- take, it switches on your next key press after the delay instead (movement
-- keys and the like; never keys bound to abilities), until /reload.
--
-- A tracking that is on but not ticked (say Track Beasts, picked by hand)
-- pauses the rotation, so your own pick stays until you pick a ticked one.

local ADDON, ns = ...
local Readable, Print = ns.Readable, ns.Print

local TICK = 0.25
local VERIFY_WAIT = 1.5
local FAIL_SKIP = 60       -- a tracker the game refused (red error) is skipped this long

-- setting key -> spell IDs and English names (fallback match on name)
local KINDS = {
    { key = "trackHerbs",     ids = { [2383] = true },               name = "find herbs" },
    { key = "trackMinerals",  ids = { [2580] = true },               name = "find minerals" },
    { key = "trackHumanoids", ids = { [19883] = true, [5225] = true }, name = "track humanoids" },
}
local DRUID_HUMANOIDS = 5225  -- only works in Cat Form

local method = "timer"       -- "timer", "key" or "none" (for this session)
local lastSwitch = 0
local attempt                -- { key, name, at, source, done, blocked, error }
local silentFails = 0
local failing = {}           -- key -> GetTime() until which it is skipped
local ownKey                 -- the tracker we turned on last
local looting = false
local mutedAt
local told = {}

local function DB() return GnistifyDB end

local function TellOnce(id, msg)
    if told[id] then return end
    told[id] = true
    Print(msg)
end

local function InCatForm()
    local ok, form = pcall(function() return GetShapeshiftFormID and GetShapeshiftFormID() end)
    return ok and Readable(form) == 1
end

-- The kind (setting key) a tracking entry belongs to, or nil.
local function KindOf(spellID, name)
    local lname = type(name) == "string" and name:lower() or nil
    for _, k in ipairs(KINDS) do
        if (spellID and k.ids[spellID]) or lname == k.name then return k end
    end
end

-- { list = { {key, index, name, active, kind} ... }, rotation = {...}, active = entry }
local function Scan()
    local s = { list = {}, rotation = {}, byKey = {} }
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return s end
    local okN, n = pcall(C_Minimap.GetNumTrackingTypes)
    n = okN and Readable(n)
    if type(n) ~= "number" then return s end
    local db = DB()
    for i = 1, n do
        local ok, info = pcall(C_Minimap.GetTrackingInfo, i)
        if ok and type(info) == "table" then
            local spellID = Readable(info.spellID)
            local name = Readable(info.name)
            local key = spellID or name
            -- Only spells (Find Minerals, Track Beasts...). Town trackers like
            -- Innkeeper or Flight Master stay on alongside and must not count
            -- as "a tracking picked by hand", or the rotation never starts.
            if key and (spellID or Readable(info.type) == "spell") then
                local e = { key = key, index = i, name = type(name) == "string" and name or tostring(key),
                            active = Readable(info.active) and true or false, kind = KindOf(spellID, name) }
                s.list[#s.list + 1] = e
                s.byKey[key] = e
                if e.kind and db[e.kind.key] and not (spellID == DRUID_HUMANOIDS and not InCatForm()) then
                    s.rotation[#s.rotation + 1] = e
                end
                -- Find Treasure stays on alongside the others; don't treat it as "the" one.
                if e.active and not (type(name) == "string" and name:lower() == "find treasure") then
                    if not s.active or e.key == ownKey then s.active = e end
                end
            end
        end
    end
    return s
end

local function InRotation(s, key)
    for _, e in ipairs(s.rotation) do if e.key == key then return true end end
    return false
end

local function NextEntry(s)
    local rot, n = s.rotation, #s.rotation
    if n == 0 then return nil end
    local pos = 0
    for i, e in ipairs(rot) do if s.active and e.key == s.active.key then pos = i end end
    local now = GetTime()
    for step = 1, n do
        local e = rot[(pos + step - 1) % n + 1]
        if not (s.active and e.key == s.active.key) and (failing[e.key] or 0) <= now then return e end
    end
end

local function Busy()
    local ok, casting = pcall(function()
        return (UnitCastingInfo and Readable(UnitCastingInfo("player")))
            or (UnitChannelInfo and Readable(UnitChannelInfo("player")))
    end)
    return ok and casting ~= nil
end

local function OnCooldown(spellID)
    if type(spellID) ~= "number" or not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local ok, onCd = pcall(function()
        local cd = C_Spell.GetSpellCooldown(spellID)
        local start, dur = cd and Readable(cd.startTime), cd and Readable(cd.duration)
        if type(start) ~= "number" or type(dur) ~= "number" then return false end
        return start > 0 and dur > 0 and start + dur > GetTime()
    end)
    return ok and onCd
end

-- Safe moments: a switch starts the global cooldown, so it is held (without
-- resetting the countdown) while you are about to fight or busy doing things.
local CAST_QUIET = 3       -- sec after one of my own casts
local lastCastAt = 0

local function Hostile(unit)
    local ok, yes = pcall(function()
        return Readable(UnitExists(unit)) and Readable(UnitCanAttack("player", unit))
            and not Readable(UnitIsDeadOrGhost(unit))
    end)
    return ok and yes and true or false
end

local function EnemyPlayerNear()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if Hostile(unit) then
            local ok, isPlayer = pcall(UnitIsPlayer, unit)
            if ok and Readable(isPlayer) then return true end
        end
    end
    return false
end

local function Moving()
    if IsMounted and Readable(IsMounted()) then return true end
    local ok, speed = pcall(GetUnitSpeed, "player")
    speed = ok and Readable(speed)
    return type(speed) ~= "number" or speed > 0 -- unknown counts as moving
end

-- nil when now is a good moment, else why not (Danish, for /gnist spor).
local function Hold()
    if Busy() then return "du caster" end
    if looting then return "du looter" end
    if GetTime() - lastCastAt < CAST_QUIET then return "du har lige brugt en evne" end
    if Hostile("target") then return "du har et fjendtligt mål" end
    if EnemyPlayerNear() then return "en fjendtlig spiller er i nærheden" end
    if DB().trackOnlyMoving and not Moving() then return "du står stille" end
end

local function ForagerRunning()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Forager"))
        or (IsAddOnLoaded and IsAddOnLoaded("Forager"))
    return loaded and not (ForagerDB and ForagerDB.enabled == false)
end

local DELAY = 5
local function Delay() return DELAY end

-- nil when a switch may happen now, else why not (Danish, for /gnist spor).
local function Blocker(s)
    local db = DB()
    if not db.tracking then return "slået fra" end
    if method == "none" then return "spillet afviser skiftet" end
    if ForagerRunning() then return "Forager skifter allerede din sporing" end
    if InCombatLockdown() or UnitAffectingCombat("player") then return "i kamp" end
    if UnitIsDeadOrGhost("player") then return "død" end
    if UnitOnTaxi("player") then return "på flyvetur" end
    if IsResting() then return "i en by eller kro" end
    local inside, kind = IsInInstance()
    if inside and kind ~= "none" then return "i en dungeon, raid eller battleground" end
    if #s.rotation < 2 then return "mindre end to af de valgte sporinger kendes af denne karakter" end
    if s.active and not InRotation(s, s.active.key) and s.active.key ~= ownKey then
        return s.active.name .. " er slået til, og den er ikke valgt"
    end
    if not NextEntry(s) then return "de andre sporinger kan ikke bruges lige nu" end
end

---------------------------------------------------------------------------
-- Muting the switch sound
---------------------------------------------------------------------------

local function Unmute()
    if not (mutedAt or DB().trackUnmute) then return end
    pcall(SetCVar, "Sound_EnableSFX", "1")
    mutedAt, DB().trackUnmute = nil, nil
end

local function Mute()
    local db = DB()
    if not db.trackQuiet or db.fishingSaved then return end
    if mutedAt then mutedAt = GetTime() return end
    local ok, value = pcall(GetCVar, "Sound_EnableSFX")
    if not ok or value ~= "1" then return end
    if pcall(SetCVar, "Sound_EnableSFX", "0") then
        mutedAt = GetTime()
        db.trackUnmute = true -- restored at the next login after a crash or reload
    end
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------

local SetUpKeys

local function Verify(a)
    if a.done then return end
    a.done = true
    local s = Scan()
    if mutedAt then Unmute() end
    if s.byKey[a.key] and s.byKey[a.key].active then
        ownKey = a.key
        silentFails = 0
        failing[a.key] = nil
    elseif a.error then
        failing[a.key] = GetTime() + FAIL_SKIP
    elseif not a.blocked then
        silentFails = silentFails + 1
        if a.source == "timer" and silentFails >= 3 then
            method, silentFails = "key", 0
            TellOnce("silent", "Sporing: skift fra en timer virker ikke her, så den skifter når du trykker på en tast (fx når du går), indtil /reload.")
            SetUpKeys()
        end
    end
end

local function Cast(e, source)
    Mute()
    local a = { key = e.key, name = e.name, at = GetTime(), source = source }
    attempt = a
    local ok = pcall(C_Minimap.SetTracking, e.index, true)
    if not ok then a.error = "error" end
    C_Timer.After(VERIFY_WAIT, function() Verify(a) end)
end

local function TrySwitch(source)
    if attempt and not attempt.done then return end
    if GetTime() - lastSwitch < Delay() then return end
    local s = Scan()
    if Blocker(s) or Hold() then return end
    local e = NextEntry(s)
    if OnCooldown(e.key) then return end
    -- Count the try as a switch, so a refusal isn't repeated every tick.
    lastSwitch = GetTime()
    Cast(e, source)
end

---------------------------------------------------------------------------
-- Key press fallback (same idea as Forager's): a frame that sees key presses
-- but passes every key on to the game. Pass-through is switched on and checked
-- first: a frame that captures keys without passing them on swallows the whole
-- keyboard. Keys bound to abilities, modifiers, Tab, Escape and Enter never switch.
---------------------------------------------------------------------------

local ABILITY_BINDINGS = {
    "^ACTIONBUTTON", "^MULTIACTIONBAR", "^BONUSACTIONBUTTON", "^SHAPESHIFTBUTTON",
    "^PETACTIONBUTTON", "^CLICK ", "^SPELL ", "^MACRO ", "^ITEM ", "^INTERACT",
}
local NO_SWITCH_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, TAB = true, ESCAPE = true, ENTER = true, CAPSLOCK = true,
}

local function IsAbilityKey(key)
    local action = GetBindingAction and GetBindingAction(key, true)
    if not action or action == "" then return false end
    for _, pattern in ipairs(ABILITY_BINDINGS) do
        if action:find(pattern) then return true end
    end
    return false
end

local keyFrame, keysReady

local function OnKey(_, key)
    if method ~= "key" then return end
    if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return end
    if NO_SWITCH_KEYS[key] then return end
    if IsControlKeyDown() or IsAltKeyDown() or IsShiftKeyDown() then return end
    if IsAbilityKey(key) then return end
    TrySwitch("key")
end

SetUpKeys = function()
    if keysReady or method ~= "key" or InCombatLockdown() then return end
    keyFrame = keyFrame or CreateFrame("Frame", "GnistifyTrackKeys", UIParent)
    local ok = pcall(keyFrame.SetPropagateKeyboardInput, keyFrame, true)
    if not ok or (keyFrame.GetPropagateKeyboardInput and not keyFrame:GetPropagateKeyboardInput()) then
        pcall(keyFrame.EnableKeyboard, keyFrame, false)
        method = "none"
        TellOnce("nokeys", "Sporing: spillet tillader ikke at skifte sporing for dig. Brug minimap-menuen.")
        return
    end
    keyFrame:SetScript("OnKeyDown", OnKey)
    keyFrame:EnableKeyboard(true)
    keysReady = true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "LOOT_OPENED", "LOOT_CLOSED",
                      "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
                      "PLAYER_LOGOUT", "MINIMAP_UPDATE_TRACKING", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(f.RegisterEvent, f, ev)
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Unmute() -- left muted by a crash or reload mid-switch
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(TICK, function()
                if mutedAt and GetTime() - mutedAt > 2 then Unmute() end
                if method == "timer" and DB().tracking then TrySwitch("timer") end
            end)
        end
        if DB().tracking and ForagerRunning() then
            C_Timer.After(5, function()
                TellOnce("forager", "Sporing: Forager er slået til og skifter allerede din sporing, så Gnistify lader den være. Slå den ene fra.")
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetUpKeys()
    elseif event == "LOOT_OPENED" then
        looting = true
    elseif event == "LOOT_CLOSED" then
        looting = false
    elseif event == "UI_ERROR_MESSAGE" then
        local a = attempt
        if a and not a.done and GetTime() - a.at < 1 then a.error = true end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon = Readable((...))
        local a = attempt
        if addon ~= ADDON or not a or a.done or GetTime() - a.at > 1 then return end
        a.blocked = true
        if a.source == "timer" then
            method = "key"
            TellOnce("blocked", "Sporing: spillet tillader kun at skifte sporing under et tastetryk, så den skifter når du trykker på en tast (fx når du går), indtil /reload.")
            SetUpKeys()
        else
            method = "none"
            TellOnce("refused", "Sporing: spillet afviser at Gnistify skifter sporing. Slået fra indtil /reload.")
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Readable((...)) ~= "player" then return end
        -- Our own tracking cast doesn't count as "busy".
        local a = attempt
        if a and GetTime() - a.at < 1 then return end
        lastCastAt = GetTime()
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        -- Picked by hand from the minimap menu: give it a full turn.
        if not (attempt and not attempt.done) then lastSwitch = GetTime() end
    elseif event == "PLAYER_LOGOUT" then
        Unmute()
    end
end)

---------------------------------------------------------------------------
-- Minimap shift-click / middle click and the key binding "Sporing til/fra".
function ns.ToggleTracking()
    local db = DB()
    if not db then return end
    db.tracking = not db.tracking
    if db.tracking then lastSwitch = 0 end
    local why = db.tracking and (Blocker(Scan()) or Hold())
    Print("Skift sporing: " .. (db.tracking and "|cff00ff00til|r" or "|cffff0000fra|r")
        .. (why and ("  (venter: " .. why .. ")") or ""))
end
Gnistify_ToggleTracking = function() ns.ToggleTracking() end
BINDING_NAME_GNISTIFY_TRACKING = "Skift sporing til/fra"

-- /gnist spor [til|fra]
---------------------------------------------------------------------------

function ns.TrackingCommand(arg)
    local db = DB()
    arg = (arg or ""):lower()
    if arg == "til" or arg == "on" then
        db.tracking = true
    elseif arg == "fra" or arg == "off" then
        db.tracking = false
    elseif arg == "" then
        db.tracking = not db.tracking
    end
    if db.tracking then lastSwitch = 0 end

    local s = Scan()
    local names = {}
    for _, e in ipairs(s.rotation) do names[#names + 1] = e.name end
    Print("Skift sporing automatisk: " .. (db.tracking and "|cff00ff00til|r" or "|cffff0000fra|r")
        .. ", hvert " .. Delay() .. ". sek")
    if #names > 0 then
        Print("  Skifter mellem: " .. table.concat(names, ", "))
    end
    local why = db.tracking and (Blocker(s) or Hold())
    if why then Print("  Venter: " .. why) end
    if method == "key" then Print("  Skifter når du trykker på en tast (timeren blev afvist).") end
end
