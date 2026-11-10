-- Gnistify kills: when a Gnisterne member gets the KILLING BLOW on an enemy
-- player, every guildie with the addon sees (in their own chat window, not
-- guild chat):
--   <gnist> Killer gnistede Offer (lvl 34 Magiker) til døde i Zone!
--
-- No duplicates when several of us are grouped: only the client of the player
-- who landed the killing blow announces it. Everyone else just listens.

local ns = select(2, ...)
local PREFIX = ns.PREFIX

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local KILL_MSG = "%s |cffff6600%s|r gnistede %s (lvl %s %s) til døde i |cffffff00%s|r!"
local KILL_SOUND = "Interface\\AddOns\\Gnistify\\sound.mp3"

local levelCache = {}   -- enemy player GUID -> last seen level

-- Remember enemy players' levels while we can see them, because after the
-- kill the nameplate/target may already be gone.
local function Remember(unit)
    if unit and UnitExists(unit) and UnitIsPlayer(unit) then
        local guid, level = UnitGUID(unit), UnitLevel(unit)
        if guid and level then levelCache[guid] = level end
    end
end

local function FindLevel(guid)
    local units = { "target", "mouseover", "pettarget" }
    for i = 1, 4 do units[#units + 1] = "party" .. i .. "target" end
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            Remember(unit)
            break
        end
    end
    local level = levelCache[guid]
    if not level then return "?" end
    if level < 1 then return "??" end   -- skull: much higher level than us
    return tostring(level)
end

local function ClassText(classFile)
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile or "?"
    return name
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

local function OnKillingBlow(destGUID, destName)
    local _, classFile, _, _, _, name = GetPlayerInfoByGUID(destGUID)
    local victim = ns.Short(name or destName) or "?"
    local level = FindLevel(destGUID)
    local zone = GetRealZoneText() or GetZoneText() or "?"
    local me = UnitName("player")

    Show(me, victim, level, classFile, zone)   -- I see my own kill right away
    if IsInGuild() and GnistifyDB.killsSend then
        local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
        -- ";" never appears in names or zone names
        send(PREFIX, table.concat({ "KILL", victim, level, classFile or "", zone }, ";"), "GUILD")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("UNIT_LEVEL")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, sub, _, srcGUID, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
        if sub ~= "PARTY_KILL" then return end
        -- Only the one who got the killing blow (or whose pet did) announces
        if srcGUID ~= UnitGUID("player") and srcGUID ~= UnitGUID("pet") then return end
        if not destGUID or not destGUID:find("^Player%-") then return end
        OnKillingBlow(destGUID, destName)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX or not msg:find("^KILL;") then return end
        local killer = ns.Short(sender)
        if killer == UnitName("player") then return end   -- already shown
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
        wipe(levelCache)
    end
end)
