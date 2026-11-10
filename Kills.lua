-- Gnistify kills: when a Gnisterne member gets the KILLING BLOW on an enemy
-- player, every guildie with the addon sees (in their own chat window, not
-- guild chat):
--   <gnist> Killer gnistede Offer (lvl 34 Magiker) til døde i Zone!
--
-- No duplicates when several of us are grouped: only the client of the player
-- who landed the killing blow announces it. Everyone else just listens.
--
-- WoW Forever runs the modern retail client: the combat log is closed to
-- addons (registering COMBAT_LOG_EVENT_UNFILTERED is a forbidden action and
-- shows the "blocked from an action" popup). The PARTY_KILL event
-- (attackerGUID, targetGUID) replaces it. Values can be "secret", so every
-- value from the API goes through ns.Readable first.

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local KILL_MSG = "%s |cffff6600%s|r gnistede %s (lvl %s %s) til døde i |cffffff00%s|r!"
local KILL_SOUND = "Interface\\AddOns\\Gnistify\\sound.mp3"

local seen = {}   -- enemy player GUID -> { level, name, class } while we could see them

-- Remember players while we can see them, because after the kill the
-- nameplate/target may already be gone (and GetPlayerInfoByGUID may be hidden).
local function Remember(unit)
    if not unit or not Readable(UnitExists(unit)) or not Readable(UnitIsPlayer(unit)) then return end
    local guid = Readable(UnitGUID(unit))
    if type(guid) ~= "string" then return end
    local info = seen[guid] or {}
    info.level = Readable(UnitLevel(unit)) or info.level
    info.name = Readable((UnitName(unit))) or info.name
    info.class = Readable((select(2, UnitClass(unit)))) or info.class
    seen[guid] = info
end

local function LookAround(guid)
    local units = { "target", "mouseover", "pettarget", "focus" }
    for i = 1, 4 do units[#units + 1] = "party" .. i .. "target" end
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, unit in ipairs(units) do
        if Readable(UnitGUID(unit)) == guid then
            Remember(unit)
            return
        end
    end
end

local function LevelText(level)
    if type(level) ~= "number" then return "?" end
    if level < 1 then return "??" end   -- skull: much higher level than us
    return tostring(level)
end

local function ClassText(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile or "?"
end

local function ColoredName(name, classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
    return name
end

local function Show(killer, victim, level, classFile, zone)
    if not GnistifyDB or not GnistifyDB.kills then return end
    DEFAULT_CHAT_FRAME:AddMessage(KILL_MSG:format(
        GNIST_ICON, killer, ColoredName(victim, classFile), level, ClassText(classFile), zone))
    if GnistifyDB.killSound then
        PlaySoundFile(KILL_SOUND, "Master")
    end
end

local function OnKillingBlow(guid)
    LookAround(guid)
    local info = seen[guid] or {}
    local name, classFile = info.name, info.class
    if not name or not classFile then
        local ok, _, cls, _, _, _, n = pcall(GetPlayerInfoByGUID, guid)
        if ok then
            name = name or Readable(n)
            classFile = classFile or Readable(cls)
        end
    end
    local victim = (type(name) == "string" and name ~= "" and ns.Short(name)) or "?"
    local level = LevelText(info.level)
    local zone = Readable(GetRealZoneText()) or Readable(GetZoneText()) or "?"
    local me = UnitName("player")

    Show(me, victim, level, classFile, zone)   -- I see my own kill right away
    if IsInGuild() and GnistifyDB.killsSend then
        -- ";" never appears in names or zone names
        ns.SendAddon(table.concat({ "KILL", victim, level, classFile or "", zone }, ";"))
    end
end

local function IsMine(guid)
    return guid == Readable(UnitGUID("player")) or guid == Readable(UnitGUID("pet"))
end

local f = CreateFrame("Frame")
for _, event in ipairs({
    "PARTY_KILL", "CHAT_MSG_ADDON", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "UNIT_LEVEL", "PLAYER_ENTERING_WORLD",
}) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PARTY_KILL" then
        local attacker, target = ...
        attacker, target = Readable(attacker), Readable(target)
        -- Only the one who got the killing blow (or whose pet did) announces
        if not attacker or not IsMine(attacker) then return end
        if type(target) ~= "string" or not target:find("^Player%-") then return end
        OnKillingBlow(target)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg, sender = Readable(prefix), Readable(msg), Readable(sender)
        if prefix ~= PREFIX or type(msg) ~= "string" or not msg:find("^KILL;") then return end
        local killer = ns.Short(sender)
        if not killer or killer == UnitName("player") then return end   -- already shown
        local _, victim, level, classFile, zone = strsplit(";", msg)
        if victim then
            Show(killer, victim, level or "?", classFile ~= "" and classFile or nil, zone or "?")
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_LEVEL" then
        Remember((...))
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(seen)
    end
end)
