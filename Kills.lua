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
-- Short lines for the banner in the middle of the screen (the chat line has
-- all the details). {killer} is just the name, {victim} the coloured name.
local KILL_BANNERS = {
    "{killer} gnistede {victim}!",
    "{victim} gik op i gnister!",
    "{killer} slukkede {victim}!",
    "{killer} sendte {victim} til kirkegården!",
    "{killer} lagde {victim} ned!",
}
local MAX_ASSISTS = 4   -- names shown in "(med ...)"; the rest becomes "+N"
local KILL_SOUND = "Interface\\AddOns\\Gnistify\\sound.mp3"

local seen = {}   -- enemy player GUID -> { level, name, class } while we could see them

-- Pet kills: the game may not send PARTY_KILL when a pet lands the killing
-- blow (Spy ran into this too). So we note which enemy player the pet is
-- attacking; when he dies (UNIT_DIED) and no PARTY_KILL or guildie's KILL
-- message names him within a moment, the kill is ours.
local PET_WINDOW = 4     -- seconds since the pet last had him targeted
local KILL_WAIT = 1.5    -- wait this long for a PARTY_KILL / KILL message before calling it the pet's
local KILL_MATCH = 3     -- a kill of him this close to the death settles it
local petTargets = {}    -- victim GUID -> GetTime() the pet last had him targeted
local killedAt = {}      -- victim GUID -> GetTime() of a PARTY_KILL naming him
local announcedAt = {}   -- victim GUID -> GetTime() we announced a kill of him
local killedNames = {}   -- victim name -> GetTime() of a guildie's KILL message

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
    -- Leaderboard title, e.g. "[Gnistkejseren]" (Leaderboard.lua)
    local title = ns.LeaderTitle and ns.LeaderTitle(killer)
    if title then killerText = killerText .. " |cffffcc00[" .. title .. "]|r" end
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
    -- The same line as a raid-warning style banner, like dings (can be turned off)
    if GnistifyDB.killBanner and RaidNotice_AddMessage and RaidWarningFrame then
        local banner = ns.Fill(ns.Pick(KILL_BANNERS), {
            killer = "|cffff6600" .. killer .. "|r",
            victim = ColoredName(victim, classFile),
        })
        RaidNotice_AddMessage(RaidWarningFrame, GNIST_ICON .. " " .. banner, ChatTypeInfo["GUILD"])
    end
    if GnistifyDB.killSound then
        PlaySoundFile(KILL_SOUND, "Master")
        ns.lastKillSound = GetTime()   -- Leaderboard.lua waits for it before a title sound
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

-- Group -------------------------------------------------------------------------

-- fn(unit, petUnit) for every other member of my group
local function ForGroup(fn)
    local raid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if count == 0 then return end
    local prefix, last = raid and "raid" or "party", raid and count or math.min(count - 1, 4)
    for i = 1, last do
        local unit = prefix .. i
        if Readable(UnitExists(unit)) and not Readable(UnitIsUnit(unit, "player")) then
            fn(unit, prefix .. "pet" .. i)
        end
    end
end

-- Close to me: "in range" (about 40 yards), or "visible" when the range is hidden
local function IsNear(unit)
    if Readable(UnitIsConnected(unit)) == false then return false end
    local inRange = Readable((UnitInRange(unit)))
    if inRange == nil then return Readable(UnitIsVisible(unit)) == true end
    return inRange == true
end

-- Every group member close by: { [name] = true }
local function NearbySet()
    local set = {}
    ForGroup(function(unit)
        local name = IsNear(unit) and ns.FullName(unit)
        if name then set[name] = true end
    end)
    return set
end

-- Group members close by when I got the killing blow, as sent in KILL: at most
-- MAX_ASSISTS names plus "+N". Only used when the damage meter isn't there.
local function Assists()
    local names, extra = {}, 0
    for name in pairs(NearbySet()) do
        if #names < MAX_ASSISTS then names[#names + 1] = name else extra = extra + 1 end
    end
    table.sort(names)
    if extra > 0 then names[#names + 1] = "+" .. extra end
    return table.concat(names, ",")
end

-- The group member (or their pet) with this GUID
local function GroupUnitByGUID(guid)
    local found
    ForGroup(function(unit, pet)
        if not found and (Readable(UnitGUID(unit)) == guid or Readable(UnitGUID(pet)) == guid) then
            found = unit
        end
    end)
    return found
end

-- Kill log ----------------------------------------------------------------------
-- The last LOG_MAX kill events, newest first, in GnistifyDB.killLog, so a kill
-- that was credited wrong can be looked up afterwards (after /reload or logout).
local LOG_MAX = 50

local function Log(entry)
    if not GnistifyDB then return end
    GnistifyDB.killLog = GnistifyDB.killLog or {}
    entry.time = date("%Y-%m-%d %H:%M:%S")
    table.insert(GnistifyDB.killLog, 1, entry)
    while #GnistifyDB.killLog > LOG_MAX do table.remove(GnistifyDB.killLog) end
end
ns.KillLog = Log

-- Helpers ---------------------------------------------------------------------
-- Everyone in my group who damaged the victim, or healed someone who did while
-- near the killer, gets the kill on the PvP-tavle too, not just the one with the
-- killing blow. Forever's own damage meter (C_DamageMeter) knows who: its
-- "enemy damage taken" list breaks each enemy's damage down per group member,
-- and "healing done" lists the healers, with whom they healed per spell. The numbers are secret in combat and readable after.
--
-- Credit: every client decides for itself. PARTY_KILL tells every group member
-- about a kill, whoever made it (even without Gnistify). After combat my client
-- reads my own meter and, if I helped, calls ns.LeaderboardKill().
--
-- Display: the killer's client reads the meter too and sends
--   HELP;victim;classFile;Name:d,Name:dh,...,+N
-- (d = damaged the victim, h = healed near the killer, n = only nearby: the
-- meter had nothing, so it's the old guess). Every client shows the line. It
-- gives no credit (version 1.0.16 and older credit from it; this one doesn't,
-- so nothing is counted twice). Older versions ignore HELP.
local HELP_TRIES = 5      -- seconds to wait for the meter to turn readable after combat
local HELP_BYTES = 240    -- addon messages max out at 255 bytes
local pendingHelp = {}    -- kills waiting for combat to end (see QueueHelpers / QueueMyHelp)
local helpSeen = {}       -- victim GUID -> GetTime(), one self-check per death

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function Open(t)
    return type(t) == "table" and not IsSecret(t) and not (canaccesstable and not canaccesstable(t))
end

-- t[key], or nil when t or the value is secret
local function Field(t, key)
    if not Open(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not IsSecret(v) then return v end
end

local function MeterReady()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and C_DamageMeter.GetCombatSessionSourceFromType and Enum and Enum.DamageMeterType
        and Enum.DamageMeterType.EnemyDamageTaken and Enum.DamageMeterSessionType and C_Timer
        and true or false
end

-- The fight going on now. Its number (not the numbers in it) is public in
-- combat, and reading it by number later still works after a new fight starts.
local function LiveSessionID()
    if not C_DamageMeter.GetAvailableCombatSessions or not C_DamageMeter.GetCombatSessionFromID then return nil end
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or not Open(list) or #list == 0 then return nil end
    local id = Field(list[#list], "sessionID")
    return type(id) == "number" and id or nil
end

local function GetSession(id, dmType)
    if id then return pcall(C_DamageMeter.GetCombatSessionFromID, id, dmType) end
    return pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, dmType)
end

local function GetSource(id, dmType, guid, creature)
    if id then return pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, dmType, guid, creature) end
    return pcall(C_DamageMeter.GetCombatSessionSourceFromType, Enum.DamageMeterSessionType.Current,
        dmType, guid, creature)
end

-- Did this healer heal someone else who hit the victim? The meter's per-healer
-- view breaks the healing down per spell and per target (combatSpellDetails,
-- like the damage view does per attacker). Unreadable counts as no: better no
-- credit than credit for healing that had nothing to do with the kill.
local function HealedDamager(id, src, damagers)
    local healer = Field(src, "name")
    healer = type(healer) == "string" and ns.Short(healer)
    local okD, detail = GetSource(id, Enum.DamageMeterType.HealingDone,
        Field(src, "sourceGUID"), Field(src, "sourceCreatureID"))
    local spells = okD and Field(detail, "combatSpells")
    if not Open(spells) then return false end
    for _, sp in ipairs(spells) do
        local amount = Field(sp, "totalAmount")
        local d = Field(sp, "combatSpellDetails")
        if type(amount) == "number" and amount > 0 and Open(d) then
            local targets = Field(d, "unitName") ~= nil and { d } or d
            for _, x in ipairs(targets) do
                local target = Field(x, "unitName")
                target = type(target) == "string" and target ~= "" and ns.Short(target)
                if target and target ~= healer and not Field(x, "isPet")
                   and damagers[target] then
                    return true
                end
            end
        end
    end
    return false
end

-- Who hit this victim and who healed in the fight: { [name] = "d" / "h" / "dh" }.
-- nil while the meter is still secret or doesn't know the victim.
local function ReadHelpers(guid, id)
    local T = Enum.DamageMeterType
    local ok, session = GetSession(id, T.EnemyDamageTaken)
    local list = ok and Field(session, "combatSources")
    if not Open(list) then return nil end
    local victim
    for _, src in ipairs(list) do
        if Field(src, "sourceGUID") == guid then victim = src break end
    end
    if not victim then return nil end
    local okD, detail = GetSource(id, T.EnemyDamageTaken, guid, Field(victim, "sourceCreatureID"))
    local spells = okD and Field(detail, "combatSpells")
    if not Open(spells) then return nil end

    local roles = {}
    local function Add(name, role)
        name = type(name) == "string" and name ~= "" and ns.Short(name)
        if not name then return end
        local r = roles[name] or ""
        if not r:find(role, 1, true) then roles[name] = r .. role end
    end
    local function AddUnit(d)
        if Field(d, "isPet") or Field(d, "isMob") then return end   -- a hunter's pet counts as the hunter
        Add(Field(d, "unitName"), "d")
    end
    -- One entry per group member who hit him; the amount is on the entry
    for _, sp in ipairs(spells) do
        local amount = Field(sp, "totalAmount")
        local d = Field(sp, "combatSpellDetails")
        if type(amount) == "number" and amount > 0 and Open(d) then
            if Field(d, "unitName") ~= nil then
                AddUnit(d)
            else
                for _, x in ipairs(d) do AddUnit(x) end
            end
        end
    end
    -- Healing only counts when it landed on someone who hit the victim, and not
    -- on the healer: a potion, bandage, Mend Pet or healing someone in another
    -- fight is not helping with this kill.
    local damagers = {}
    for name in pairs(roles) do damagers[name] = true end
    local okH, heal = GetSession(id, T.HealingDone)
    local healers = okH and Field(heal, "combatSources")
    if Open(healers) then
        for _, src in ipairs(healers) do
            local amount = Field(src, "totalAmount")
            if type(amount) == "number" and amount > 0 and HealedDamager(id, src, damagers) then
                Add(Field(src, "name"), "h")
            end
        end
    end
    return roles
end

-- Healing only counts near the killer: the meter can't say whom they healed,
-- and a guildie questing across the zone shouldn't get the kill
local function DropFarHealers(roles, near)
    for name, r in pairs(roles) do
        if r == "h" and not near[name] then roles[name] = nil end
    end
    return roles
end

local ROLE_TEXT = { d = "skade", h = "heling", dh = "skade og heling", n = "i nærheden" }

local function ShowHelpers(victim, classFile, list)
    if not GnistifyDB.kills then return end
    local parts = {}
    for entry in (list or ""):gmatch("[^,]+") do
        local extra = entry:match("^%+(%d+)$")
        if extra then
            parts[#parts + 1] = extra .. (extra == "1" and " anden" or " andre")
        else
            local name, role = entry:match("^(.-):(%a*)$")
            name = name or entry
            local r = ROLE_TEXT[role or ""]
            parts[#parts + 1] = "|cffff6600" .. name .. "|r" .. (r and (" (" .. r .. ")") or "")
        end
    end
    if #parts == 0 then return end
    DEFAULT_CHAT_FRAME:AddMessage(GNIST_ICON .. " |cffffcc00Hjalp til med drabet på|r "
        .. ColoredName(victim, classFile) .. ": " .. JoinNames(parts))
end

-- After my killing blow: show and send who helped
local function SendHelpers(job, roles, source)
    local me = ns.Me()
    local names = {}
    for name in pairs(roles) do
        if name ~= me then names[#names + 1] = name end
    end
    table.sort(names)
    local entries, extra = {}, 0
    local size = #"HELP;;;" + #job.victim + #(job.class or "")
    for _, name in ipairs(names) do
        local e = name .. ":" .. roles[name]
        if size + #e + 6 <= HELP_BYTES then
            entries[#entries + 1] = e
            size = size + #e + 1
        else
            extra = extra + 1
        end
    end
    if extra > 0 then entries[#entries + 1] = "+" .. extra end
    local list = table.concat(entries, ",")
    Log({ kind = "mine-helpers", victim = job.victim, list = list, source = source })
    if #entries == 0 then return end
    ShowHelpers(job.victim, job.class, list)
    if IsInGuild() and GnistifyDB.killsSend then
        ns.SendAddon(table.concat({ "HELP", job.victim, job.class or "", list }, ";"))
    end
end

-- A group member's kill: did I help? Then it counts for me too.
local function CreditMe(job, roles)
    local me = ns.Me()
    local r = roles and me and roles[me] or ""
    local damaged = r:find("d", 1, true) ~= nil
    local healed = r:find("h", 1, true) ~= nil
    local credited = damaged or (healed and job.nearKiller)
    Log({ kind = "group-kill", killer = job.killer, victim = job.victim, meter = roles and "ok" or "none",
        damaged = damaged, healed = healed, nearKiller = job.nearKiller, credited = credited })
    if credited and ns.LeaderboardKill then ns.LeaderboardKill() end
end

-- Combat is over: read the meter for every kill of this fight
local function ProcessHelp()
    if #pendingHelp == 0 then return end
    if Readable(InCombatLockdown()) or Readable(UnitAffectingCombat("player")) then return end
    local jobs = pendingHelp
    pendingHelp = {}
    for _, job in ipairs(jobs) do
        local tries = 0
        local function Try()
            local roles = ReadHelpers(job.guid, job.session)
            if not roles and job.session then roles = ReadHelpers(job.guid, nil) end
            tries = tries + 1
            if not roles and tries < HELP_TRIES then
                C_Timer.After(1, Try)
            elseif job.mine then
                if roles then
                    SendHelpers(job, DropFarHealers(roles, job.near), "meter")
                else
                    -- The meter had nothing: show the old "nearby" guess
                    local nearby = {}
                    for name in pairs(job.near) do nearby[name] = "n" end
                    SendHelpers(job, nearby, "nearby")
                end
            else
                CreditMe(job, roles)
            end
        end
        C_Timer.After(1, Try)
    end
end

-- Called with my killing blow. False when the old "nearby" list must be used.
local function QueueHelpers(guid, victim, classFile)
    if not MeterReady() then return false end
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if count == 0 then return true end   -- alone: nobody to thank
    pendingHelp[#pendingHelp + 1] = {
        mine = true, guid = guid, victim = victim, class = classFile,
        near = NearbySet(), session = LiveSessionID(),
    }
    C_Timer.After(2, ProcessHelp)   -- in case combat is already over (pet kills)
    return true
end

-- PARTY_KILL by someone else in my group: check my own part after combat
local function QueueMyHelp(attacker, guid)
    if not MeterReady() then return end
    if helpSeen[guid] and GetTime() - helpSeen[guid] <= KILL_MATCH then return end
    helpSeen[guid] = GetTime()
    local _, instanceType = IsInInstance()
    instanceType = Readable(instanceType)
    if instanceType == "pvp" or instanceType == "arena" then return end   -- world PvP only
    local unit = GroupUnitByGUID(attacker)
    LookAround(guid)
    local info = seen[guid] or {}
    pendingHelp[#pendingHelp + 1] = {
        guid = guid, victim = info.name and ns.Short(info.name) or "?",
        killer = unit and ns.FullName(unit) or "?",
        nearKiller = unit and IsNear(unit) or false, session = LiveSessionID(),
    }
    C_Timer.After(2, ProcessHelp)
end

local function OnKillingBlow(guid)
    -- Never twice for one death (a late PARTY_KILL after the pet fallback)
    local last = announcedAt[guid]
    if last and GetTime() - last <= KILL_MATCH then return end
    announcedAt[guid] = GetTime()
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
    -- Who really helped comes after combat (HELP); until then no "(med ...)"
    local assists = QueueHelpers(guid, victim, classFile) and "" or Assists()
    Log({ kind = "mine", victim = victim, guid = guid, count = count })

    -- I see my own kill (and hear the sound) right away
    Show(me, victim, level, classFile, zone, assists, count)
    -- World PvP leaderboard (skips battlegrounds and arenas itself)
    if ns.LeaderboardKill then ns.LeaderboardKill() end
    if IsInGuild() and GnistifyDB.killsSend then
        -- ";" and "," never appear in names or zone names. Fields 6 and 7 are
        -- new; older versions only read the first five, so this stays compatible.
        ns.SendAddon(table.concat({ "KILL", victim, level, classFile or "", zone, count, assists }, ";"))
    end
end

local function IsMine(guid)
    return guid == Readable(UnitGUID("player")) or guid == Readable(UnitGUID("pet"))
end

local function NotePetTarget()
    local target = Readable(UnitGUID("pettarget"))
    if type(target) == "string" and target:find("^Player%-") then
        petTargets[target] = GetTime()
        Remember("pettarget")
    end
end

local function CleanUp()
    local now = GetTime()
    for guid, t in pairs(petTargets) do if now - t > 60 then petTargets[guid] = nil end end
    for guid, t in pairs(killedAt) do if now - t > 60 then killedAt[guid] = nil end end
    for guid, t in pairs(announcedAt) do if now - t > 60 then announcedAt[guid] = nil end end
    for name, t in pairs(killedNames) do if now - t > 60 then killedNames[name] = nil end end
    for guid, t in pairs(helpSeen) do if now - t > 60 then helpSeen[guid] = nil end end
end

-- An enemy player died: was he my pet's target, with nobody named as killer?
local function OnUnitDied(guid)
    guid = Readable(guid)
    local petSaw = guid and petTargets[guid]
    if not petSaw or GetTime() - petSaw > PET_WINDOW then return end
    -- In battlegrounds and arenas the game hides who killed whom, so we can't
    -- tell the pet's kills from everybody else's there
    local _, instanceType = IsInInstance()
    instanceType = Readable(instanceType)
    if instanceType == "pvp" or instanceType == "arena" then return end
    local died = GetTime()
    C_Timer.After(KILL_WAIT, function()
        local k = killedAt[guid]
        if k and math.abs(died - k) <= KILL_MATCH then return end   -- the game said who
        local name = seen[guid] and seen[guid].name
        local other = name and killedNames[ns.Short(name)]
        if other and math.abs(died - other) <= KILL_MATCH then return end      -- a guildie got him
        petTargets[guid] = nil
        OnKillingBlow(guid)
    end)
end

local f = CreateFrame("Frame")
for _, event in ipairs({
    "PARTY_KILL", "CHAT_MSG_ADDON", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "UNIT_LEVEL", "PLAYER_ENTERING_WORLD", "UNIT_DIED", "UNIT_PET",
    "PLAYER_REGEN_ENABLED",
}) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end
pcall(f.RegisterUnitEvent, f, "UNIT_TARGET", "pet")
-- UNIT_TARGET only fires when the pet switches target, so also look every second
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
        NotePetTarget()
        CleanUp()
    end)
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PARTY_KILL" then
        local attacker, target = ...
        attacker, target = Readable(attacker), Readable(target)
        -- Someone in the group got him: the pet fallback must not claim him
        if type(target) == "string" then killedAt[target] = GetTime() end
        if type(target) ~= "string" or not target:find("^Player%-") or not attacker then return end
        if IsMine(attacker) then
            -- Only the one who got the killing blow (or whose pet did) announces
            OnKillingBlow(target)
        else
            QueueMyHelp(attacker, target)   -- a group member's kill: did I help?
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg, sender = Readable(prefix), Readable(msg), Readable(sender)
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        local killer = ns.Short(sender)
        if not killer or killer == ns.Me() then return end   -- already shown
        if msg:find("^HELP;") then
            local _, victim, classFile, list = strsplit(";", msg)
            if victim and list then
                ShowHelpers(victim, classFile ~= "" and classFile or nil, list)
                Log({ kind = "help-msg", killer = killer, victim = victim, list = list })
            end
            return
        end
        if not msg:find("^KILL;") then return end
        local _, victim, level, classFile, zone, count, assists = strsplit(";", msg)
        if victim then
            Log({ kind = "guild-kill", killer = killer, victim = victim, assists = assists })
            killedNames[victim] = GetTime()
            Show(killer, victim, level or "?", classFile ~= "" and classFile or nil, zone or "?",
                assists, count)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_LEVEL" then
        Remember((...))
    elseif event == "UNIT_DIED" then
        OnUnitDied((...))
    elseif event == "UNIT_TARGET" or event == "UNIT_PET" then
        NotePetTarget()
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(1, ProcessHelp)
    elseif event == "PLAYER_ENTERING_WORLD" then
        GnistifyDB.dmDump = nil   -- left over from testing the damage meter
        wipe(seen)
        wipe(petTargets)
    end
end)
