-- Gnistify: DING! when a guildie levels up, announced in Danish.
--
-- Detection:
--   1) Players WITH the addon broadcast their own level-up over the hidden
--      addon channel, so everyone else with the addon hears it instantly.
--   2) For guildies WITHOUT the addon:
--      - group members / target / mouseover: UNIT_LEVEL fires instantly
--      - everyone else: the guild roster is refreshed every 10 sec (the game
--        won't allow faster) and right away whenever someone talks in guild
--        chat (people usually type "ding!").
-- The player who dings also posts one message in guild chat (can be turned off).

local ADDON = "Gnistify"
local ns = select(2, ...)       -- shared with Kills.lua
local PREFIX = "GnistDing"      -- NEVER change: older versions listen on this
local DING_SOUND = 888          -- SOUNDKIT "LEVELUP" (the classic ding)
local ROSTER_POLL = 10          -- seconds between roster refreshes (game throttles to ~10s)
local QUIET_TIME = 20           -- seconds after a loading screen where roster/unit
                                -- level changes are only recorded, not celebrated
local MAX_JUMP = 2              -- a bigger level jump is stale data, not a ding

-- One of these is picked at random for every ding. {name} and {level} are
-- filled in. The guild chat post wraps it in {star} raid icons.
local DING_MSGS = {
    "DING! {name} er dinget level {level}! Længe leve gnisten!",
    "DING DING! {name} har ramt level {level}! Længe leve gnisten!",
    "{name} er nu level {level}! Gnisten brænder stærkere end nogensinde!",
    "Level {level}! {name} gnistrer som aldrig før!",
    "Skål for {name}, der lige er dinget level {level}!",
    "DING! {name} er level {level}. Fjenderne skælver!",
    "Gnisten vokser: {name} er nu level {level}!",
    "Hold da op! {name} er dinget level {level}! Længe leve gnisten!",
}

local knownLevels = {}          -- name -> level from roster
local announced = {}            -- name -> highest level already celebrated
local rosterReady = false
local quietUntil = math.huge    -- set on PLAYER_ENTERING_WORLD

-- Right after login, /reload or a loading screen the guild roster and unit
-- levels can arrive in pieces or with old cached levels. A level that "goes up"
-- then is not a real ding, so only trust changes outside that window, and only
-- small jumps. (Addon users' own DING: messages are always trusted.)
local function LooksLikeDing(old, level)
    return old and level and level > old and level - old <= MAX_JUMP
        and GetTime() >= quietUntil
end

-- WoW Forever runs the modern retail client, where the API can hand out
-- "secret" values that addon code may not compare or use as table keys.
-- Readable turns those into nil.
local function Readable(value)
    if value ~= nil and issecretvalue and issecretvalue(value) then return nil end
    return value
end

-- Forever characters have a first name and a surname ("Torden Tim") and no
-- realms. The client puts the surname where other versions put the realm:
-- UnitName returns (first, surname), and chat/roster names are "First-Surname".
local toc = select(4, GetBuildInfo()) or 0
local IS_FOREVER = toc >= 16000 and toc < 20000

-- A display name from a chat/roster name: "Torden-Tim" -> "Torden Tim" on
-- Forever, "Name-Realm" -> "Name" elsewhere.
local function Short(name)
    name = Readable(name)
    if type(name) ~= "string" or name == "" then return nil end
    if IS_FOREVER then return (name:gsub("%-", " ")) end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end

-- A unit's full display name, with the surname on Forever.
local function FullName(unit)
    local first, second = UnitName(unit)
    first, second = Readable(first), Readable(second)
    if type(first) ~= "string" or first == "" then return nil end
    if IS_FOREVER and type(second) == "string" and second ~= "" then
        return first .. " " .. second
    end
    return first
end

local function Me() return FullName("player") end

local function Pick(templates) return templates[math.random(#templates)] end

-- Fill in {key} placeholders from vars. color (optional) maps a key to a
-- |cff colour code, for chat-frame output.
local function Fill(text, vars, color)
    return (text:gsub("{(%a+)}", function(key)
        local v = vars[key]
        if v == nil then return nil end
        v = tostring(v)
        if color and color[key] then v = "|cff" .. color[key] .. v .. "|r" end
        return v
    end))
end

local function DingText(template, name, level, colored)
    return Fill(template, { name = name, level = level },
        colored and { name = "ff6600", level = "ffff00" } or nil)
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[Gnist]|r " .. msg)
end

local function SendAddon(msg)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then return end
    local ok, result = pcall(send, PREFIX, msg, "GUILD")
    result = Readable(result)
    -- The game drops messages when we send too many: newer clients return a
    -- result code (0 = sent), older ones true/false. Keep count, to find out
    -- whether missed kills come from that.
    if not ok or result == false or (type(result) == "number" and result ~= 0) then
        if GnistifyDB then
            local f = GnistifyDB.sendFailures or { n = 0 }
            f.n = (f.n or 0) + 1
            f.last = date("%Y-%m-%d %H:%M:%S") .. " " .. (msg:match("^[^;:]*") or "?")
                .. " -> " .. tostring(ok and result or "error")
            GnistifyDB.sendFailures = f
        end
    end
end

local function SendGuild(msg)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, msg, "GUILD") end
end

ns.PREFIX, ns.Short, ns.Print, ns.Readable, ns.SendAddon =
    PREFIX, Short, Print, Readable, SendAddon
ns.FullName, ns.Me, ns.IS_FOREVER, ns.Fill, ns.Pick = FullName, Me, IS_FOREVER, Fill, Pick
ns.SendGuild = SendGuild

local function PlayDing()
    if GnistifyDB.sound then
        PlaySound(DING_SOUND, "Master")
    end
end

local function RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

ns.RequestRoster = RequestRoster

-- Central celebration; dedupes between addon messages and roster scans.
local function Celebrate(name, level)
    name = Short(name)
    level = tonumber(level)
    if not name or not level then return end
    if announced[name] and announced[name] >= level then return end
    announced[name] = level
    knownLevels[name] = math.max(knownLevels[name] or 0, level)
    if not GnistifyDB.dings then return end

    if name ~= Me() then
        PlayDing()               -- the game already dings for yourself
    end
    local template = Pick(DING_MSGS)
    Print(DingText(template, name, level, true))
    if RaidNotice_AddMessage and RaidWarningFrame and GnistifyDB.banner then
        RaidNotice_AddMessage(RaidWarningFrame, DingText(template, name, level), ChatTypeInfo["GUILD"])
    end
end

local function ScanRoster()
    if not IsInGuild() then return end
    local num = GetNumGuildMembers()
    if not num or num == 0 then return end
    for i = 1, num do
        local fullName, _, _, level = GetGuildRosterInfo(i)
        local name = Short(fullName)
        level = Readable(level)
        if name and type(level) == "number" and level > 0 then
            local old = knownLevels[name]
            if rosterReady and LooksLikeDing(old, level) then
                Celebrate(name, level)
            end
            knownLevels[name] = level
        end
    end
    rosterReady = true
end

local f = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP",
    "GUILD_ROSTER_UPDATE", "CHAT_MSG_ADDON", "CHAT_MSG_GUILD", "UNIT_LEVEL",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        GnistifyDB = GnistifyDB or {}
        local db = GnistifyDB
        if db.sound == nil then db.sound = true end
        if db.guildChat == nil then db.guildChat = true end
        if db.banner == nil then db.banner = true end
        if db.kills == nil then db.kills = true end
        if db.killsSend == nil then db.killsSend = true end
        if db.killSound == nil then db.killSound = true end
        if db.killBanner == nil then db.killBanner = true end
        if db.dings == nil then db.dings = true end
        if db.emojis == nil then db.emojis = true end
        if db.callerFrame == nil then db.callerFrame = true end
        if db.callerFollow == nil then db.callerFollow = true end
        if db.callerSound == nil then db.callerSound = false end
        if db.minimapIcon == nil then db.minimapIcon = true end
        if db.crownSound == nil then db.crownSound = true end
        if db.eliteFrames == nil then db.eliteFrames = true end
        if db.fishing == nil then db.fishing = true end
        if db.fishingSound == nil then db.fishingSound = true end
        if db.fishingBanner == nil then db.fishingBanner = true end
        if db.fishingSend == nil then db.fishingSend = true end
        if db.fishingSplash == nil then db.fishingSplash = true end
        if db.streaks == nil then db.streaks = true end
        if db.profShare == nil then db.profShare = true end
        if db.zonePresence == nil then db.zonePresence = true end
        if db.loot == nil then db.loot = true end
        if db.lootSound == nil then db.lootSound = true end
        if db.lootBanner == nil then db.lootBanner = true end
        if db.lootSend == nil then db.lootSend = true end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
        end

    elseif event == "PLAYER_LOGIN" then
        RequestRoster()
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(ROSTER_POLL, RequestRoster)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        quietUntil = GetTime() + QUIET_TIME
        RequestRoster()

    elseif event == "PLAYER_LEVEL_UP" then
        local level = tonumber(Readable((...))) or Readable(UnitLevel("player"))
        local me = Me()
        if type(level) ~= "number" then return end
        Celebrate(me, level)
        if IsInGuild() then
            SendAddon("DING:" .. level)
            if GnistifyDB.guildChat then
                SendGuild("{star} " .. DingText(Pick(DING_MSGS), me, level) .. " {star}")
            end
        end

    elseif event == "GUILD_ROSTER_UPDATE" then
        local canRequest = Readable((...))
        ScanRoster()
        if ns.ZoneRosterUpdate then ns.ZoneRosterUpdate() end
        if canRequest then RequestRoster() end   -- server says newer data exists

    elseif event == "CHAT_MSG_GUILD" then
        -- Someone spoke in guild (often "ding!") - refresh roster right away
        RequestRoster()

    elseif event == "UNIT_LEVEL" then
        -- Instant for guildies we can "see": party/raid members, target, mouseover
        local unit = ...
        if unit and unit ~= "player" and Readable(UnitIsPlayer(unit))
           and UnitIsInMyGuild and Readable(UnitIsInMyGuild(unit)) then
            local name = FullName(unit)
            local level = Readable(UnitLevel(unit))
            local old = name and knownLevels[name]
            if LooksLikeDing(old, level) then
                Celebrate(name, level)
            elseif name and level and level > 0 then
                knownLevels[name] = math.max(old or 0, level)
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg = Readable(prefix), Readable(msg)
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        local level = msg:match("^DING:(%d+)$")
        if level and Short(sender) ~= Me() then
            Celebrate(sender, level)
        elseif msg == "GNISTREGN" and Short(sender) ~= Me() then
            ns.PlayCrownSound("big")
        end

    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- Keep the name of anything the game refused us, so it can be fixed
        local addon, fn = ...
        if Readable(addon) == ADDON and GnistifyDB then
            GnistifyDB.lastBlocked = event .. ": " .. tostring(Readable(fn)) .. " @ " .. date()
        end
    end
end)

-- /gnist slash command
SLASH_GNISTIFY1 = "/gnist"
SLASH_GNISTIFY2 = "/gnistify"
SlashCmdList.GNISTIFY = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local db = GnistifyDB
    local function onoff(v) return v and "|cff00ff00til|r" or "|cffff0000fra|r" end

    if cmd == "lyd" or cmd == "sound" then
        db.sound = not db.sound
        Print("Lyd: " .. onoff(db.sound))
    elseif cmd == "guild" or cmd == "chat" then
        db.guildChat = not db.guildChat
        Print("Skriv i guild chat når DU dinger: " .. onoff(db.guildChat))
    elseif cmd == "banner" then
        db.banner = not db.banner
        Print("Stor tekst midt på skærmen: " .. onoff(db.banner))
    elseif cmd == "drab" or cmd == "kills" then
        db.kills = not db.kills
        Print("Vis guildens drab i chatten: " .. onoff(db.kills))
    elseif cmd == "top" or cmd == "tavle" or cmd == "pvp" then
        ns.ToggleLeaderboard()
    elseif cmd == "gnistregn" then
        local big = rest:lower() == "stor"
        ns.PlayCrownSound(big and "big" or "small")
        Print(big and "fire.mp3" or "dexter.mp3")
    elseif cmd == "startfire" then
        ns.PlayCrownSound("big")
        if IsInGuild() then SendAddon("GNISTREGN") end
    elseif cmd == "reset" or cmd == "nulstil" then
        ns.ResetCommand()
    elseif cmd == "ja" or cmd == "yes" then
        ns.ResetVoteYes()
    elseif cmd == "fisk" or cmd == "fishing" then
        ns.FishingCommand()
    elseif cmd == "streak" or cmd == "dage" then
        ns.StreakCommand()
    elseif cmd == "prof" or cmd == "professioner" or cmd == "professions" then
        ns.ProfCommand(rest)
    elseif cmd == "leder" or cmd == "caller" then
        ns.CallerCommand(rest)
    elseif cmd == "makro" or cmd == "macro" then
        ns.MakeCallerMacro()
    elseif cmd == "her" or cmd == "zone" then
        ns.ZoneCommand(rest)
    elseif cmd == "zoner" or cmd == "zones" then
        ns.ZonesCommand()
    elseif cmd == "emojis" or cmd == "emoji" then
        Gnistify_ListEmojis()
    elseif cmd == "" then
        Gnistify_ToggleOptions()     -- the settings window (Options.lua)
    else
        Print("Kommandoer:")
        Print("  /gnist        - åbn indstillinger")
        Print("  /gnist lyd    - lyd " .. onoff(db.sound))
        Print("  /gnist guild  - skriv i guild chat når du dinger " .. onoff(db.guildChat))
        Print("  /gnist banner - stor tekst på skærmen " .. onoff(db.banner))
        Print("  /gnist drab   - vis guildens drab i chatten " .. onoff(db.kills))
        Print("  /gnist top    - vis guildens PvP-tavle (world PvP)")
        Print("  /gnist reset  - foreslå at nulstille PvP-tavlen (kræver 4 ja)")
        Print("  /gnist ja     - stem ja til at nulstille PvP-tavlen")
        Print("  /gnist fisk   - vis dagens fangst i guilden")
        Print("  /gnist prof   - vis hvem i guilden der har en profession (fx /gnist prof alch)")
        Print("  /gnist her    - vis guildens gnister i din zone")
        Print("  /gnist her <zone> - vis gnister i en bestemt zone")
        Print("  /gnist zoner  - vis hvor mange gnister der er online i hver zone")
        Print("  /gnist emojis - vis alle :emojis: du kan skrive i chatten")
        Print("  /gnist streak - vis din streak (dage i træk)")
        Print("  /gnist leder  - vælg dit mål som leder (eller åbn leder-vinduet)")
        Print("  /gnist leder <navn> / mig / ingen - vælg leder")
        Print("  /gnist makro  - lav en makro der tager lederens mål")
    end
end
