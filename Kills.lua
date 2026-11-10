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
-- One of these is picked at random for every kill. {killer} is the one with
-- the killing blow (plus "(med X og Y)" for group members nearby), {victim} is
-- "Navn (lvl 34 Magiker)" and {zone} the zone.
local KILL_MSGS = {
    "{killer} gnistede {victim} til døde i {zone}!",
    "{victim} blev gnistet ned af {killer} i {zone}!",
    "{killer} sendte {victim} hjem til kirkegården fra {zone}!",
    "{killer} slukkede lyset for {victim} i {zone}!",
    "{killer} gjorde kort proces med {victim} i {zone}!",
    "Puf! {victim} gik op i gnister. Skyldig: {killer} i {zone}!",
    "{killer} lagde {victim} ned i {zone}. Længe leve gnisten!",
    "{victim} mødte gnisten i {zone}. Gnisten hedder {killer}!",
    "{killer} gav {victim} en gratis tur til spirit healeren i {zone}!",
}
local MAX_ASSISTS = 4   -- names shown in "(med ...)"; the rest becomes "+N"
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
    info.name = ns.FullName(unit) or info.name
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

-- "Anna", "Anna og Bo", "Anna, Bo og Cille"
local function JoinNames(names)
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " og " .. names[#names]
end

-- assists: comma separated names (as sent), count: the killer's kills today
local function Show(killer, victim, level, classFile, zone, assists, count)
    if not GnistifyDB or not GnistifyDB.kills then return end
    local killerText = "|cffff6600" .. killer .. "|r"
    local names = {}
    for n in (assists or ""):gmatch("[^,]+") do names[#names + 1] = n end
    if #names > 0 then
        killerText = killerText .. " (med " .. JoinNames(names) .. ")"
    end
    local text = ns.Fill(ns.Pick(KILL_MSGS), {
        killer = killerText,
        victim = ColoredName(victim, classFile) .. " (lvl " .. level .. " " .. ClassText(classFile) .. ")",
        zone = "|cffffff00" .. zone .. "|r",
    })
    count = tonumber(count)
    if count then
        text = text .. " |cffaaaaaa(" .. (count == 1 and "dagens første drab"
            or "dagens drab nr. " .. count) .. ")|r"
    end
    DEFAULT_CHAT_FRAME:AddMessage(GNIST_ICON .. " " .. text)
    if GnistifyDB.killSound then
        PlaySoundFile(KILL_SOUND, "Master")
    end
end

-- My kills today, per character, kept across /reload and logout.
local function CountKill(me)
    GnistifyDB.killCount = GnistifyDB.killCount or {}
    local today = date("%Y-%m-%d")
    local c = GnistifyDB.killCount[me]
    if not c or c.day ~= today then
        c = { day = today, n = 0 }
        GnistifyDB.killCount[me] = c
    end
    c.n = c.n + 1
    return c.n
end

-- Group members close by when I got the killing blow. The combat log is closed
-- on Forever, so we can't see who actually hit the victim: "in range" (about
-- 40 yards) is the best guess, or "visible" when the range is hidden.
local function Assists()
    local names, extra = {}, 0
    local raid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if count == 0 then return "" end
    local prefix, last = raid and "raid" or "party", raid and count or math.min(count - 1, 4)
    for i = 1, last do
        local unit = prefix .. i
        if Readable(UnitExists(unit)) and not Readable(UnitIsUnit(unit, "player"))
           and Readable(UnitIsConnected(unit)) ~= false then
            local inRange = Readable((UnitInRange(unit)))
            local near = inRange
            if inRange == nil then near = Readable(UnitIsVisible(unit)) end
            local name = near and ns.FullName(unit)
            if name then
                if #names < MAX_ASSISTS then
                    names[#names + 1] = name
                else
                    extra = extra + 1
                end
            end
        end
    end
    if extra > 0 then names[#names + 1] = "+" .. extra end
    return table.concat(names, ",")
end

local function OnKillingBlow(guid)
    LookAround(guid)
    local info = seen[guid] or {}
    local name, classFile = info.name, info.class
    if not name or not classFile then
        local ok, _, cls, _, _, _, n, surname = pcall(GetPlayerInfoByGUID, guid)
        if ok then
            n, surname = Readable(n), Readable(surname)
            -- On Forever the "realm" slot holds the surname
            if ns.IS_FOREVER and type(n) == "string" and type(surname) == "string" and surname ~= "" then
                n = n .. " " .. surname
            end
            name = name or n
            classFile = classFile or Readable(cls)
        end
    end
    local victim = (type(name) == "string" and name ~= "" and ns.Short(name)) or "?"
    local level = LevelText(info.level)
    local zone = Readable(GetRealZoneText()) or Readable(GetZoneText()) or "?"
    local me = ns.Me() or "?"
    local count = CountKill(me)
    local assists = Assists()

    -- I see my own kill (and hear the sound) right away
    Show(me, victim, level, classFile, zone, assists, count)
    if IsInGuild() and GnistifyDB.killsSend then
        -- ";" and "," never appear in names or zone names. Fields 6 and 7 are
        -- new; older versions only read the first five, so this stays compatible.
        ns.SendAddon(table.concat({ "KILL", victim, level, classFile or "", zone, count, assists }, ";"))
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
        if not killer or killer == ns.Me() then return end   -- already shown
        local _, victim, level, classFile, zone, count, assists = strsplit(";", msg)
        if victim then
            Show(killer, victim, level or "?", classFile ~= "" and classFile or nil, zone or "?",
                assists, count)
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
