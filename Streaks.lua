-- Gnistify streaks: counts the days in a row each character logs in, and
-- celebrates milestones with the guild.
--
-- Data: GnistifyDB.streakDays[name] = { last = "YYYY-MM-DD", count = n, best = n,
--   ann = "YYYY-MM-DD" }. GnistifyDB is account-wide, so every character has its
--   own record. `ann` is the day a milestone was last announced (once a day at most).
-- Message on the GnistDing prefix to GUILD: STREAK;days. Receivers ignore their
-- own echo. Append fields only.

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local DING_SOUND = 888          -- SOUNDKIT "LEVELUP"
local ANNOUNCE_DELAY = 10       -- seconds after login, so the guild channel is ready
local FIXED = { 3, 7, 14, 30, 50, 100, 150, 200, 365 }
local MAX_DAYS = 100000         -- sanity limit for what other clients send us

-- One of these is picked at random for every milestone. {name} and {days} are
-- filled in. The guild chat post wraps it in {star} raid icons.
local STREAK_MSGS = {
    "{name} har gnistret {days} dage i træk! Længe leve gnisten!",
    "{days} dage i træk! {name} kan simpelthen ikke holde sig væk fra Azeroth!",
    "{name} har logget ind {days} dage i streg. Gnisten brænder!",
    "Hold da op! {name} har været på {days} dage i træk. Går der overhovedet noget i fjernsynet?",
    "{name}s gnist har brændt i {days} dage i træk! Skål!",
    "{days} dage i træk! {name} har ikke et liv, og det elsker vi!",
    "Gnistrende dedikation: {name} har mødt op {days} dage i træk!",
    "{name} er på {days} dage i træk. Fjenderne kan ikke få fred!",
}

local started = false           -- the login check has run once this session

local function Today(t) return date("%Y-%m-%d", t) end

-- Yesterday's date string. Goes via local noon, so daylight saving changes
-- (days of 23 or 25 hours) and month/year boundaries can't give the wrong day.
local function Yesterday()
    local d = date("*t")
    return Today(time({ year = d.year, month = d.month, day = d.day - 1, hour = 12 }))
end

local function IsMilestone(n)
    for _, m in ipairs(FIXED) do
        if n == m then return true end
    end
    return n > 365 and n % 100 == 0
end

local function Records()
    GnistifyDB.streakDays = GnistifyDB.streakDays or {}
    return GnistifyDB.streakDays
end

local function Text(template, name, days, colored)
    return ns.Fill(template, { name = name, days = days },
        colored and { name = "ff6600", days = "ffff00" } or nil)
end

-- Shows the celebration on this client (chat line, banner, sound).
local function Show(name, days)
    if not GnistifyDB.streaks then return end
    local template = ns.Pick(STREAK_MSGS)
    ns.Print(Text(template, name, days, true))
    if RaidNotice_AddMessage and RaidWarningFrame and GnistifyDB.banner then
        RaidNotice_AddMessage(RaidWarningFrame, Text(template, name, days), ChatTypeInfo["GUILD"])
    end
    if GnistifyDB.sound then PlaySound(DING_SOUND, "Master") end
end

-- Announce my own milestone: locally, to other Gnistify users and in guild chat.
local function Announce(me, rec)
    if not GnistifyDB.streaks then return end
    if rec.ann == rec.last then return end          -- already announced today
    rec.ann = rec.last
    local template = ns.Pick(STREAK_MSGS)
    ns.Print(Text(template, me, rec.count, true))
    if RaidNotice_AddMessage and RaidWarningFrame and GnistifyDB.banner then
        RaidNotice_AddMessage(RaidWarningFrame, Text(template, me, rec.count), ChatTypeInfo["GUILD"])
    end
    if GnistifyDB.sound then PlaySound(DING_SOUND, "Master") end
    if IsInGuild() then
        ns.SendAddon("STREAK;" .. rec.count)
        if GnistifyDB.guildChat then
            ns.SendGuild("{star} " .. Text(template, me, rec.count) .. " {star}")
        end
    end
end

-- Counts today's login. Returns the record.
local function CheckLogin(me)
    local recs = Records()
    local rec = recs[me] or { count = 0, best = 0 }
    recs[me] = rec
    local today = Today()
    if rec.last == today then return rec end        -- same day: nothing
    if rec.last == Yesterday() then
        rec.count = (rec.count or 0) + 1
    else
        rec.count = 1
    end
    rec.last = today
    rec.best = math.max(rec.best or 0, rec.count)
    return rec
end

function ns.StreakCommand()
    local me = ns.Me()
    local rec = me and Records()[me]
    if not rec or not rec.count then
        ns.Print("Ingen streak endnu. Log ind i morgen igen!")
        return
    end
    local days = rec.count == 1 and "1 dag" or rec.count .. " dage"
    local best = rec.best == 1 and "1 dag" or rec.best .. " dage"
    ns.Print("Din gnist-streak: |cffffff00" .. days .. "|r i træk. Din rekord: |cffffff00" .. best .. "|r.")
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON" }) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if started or not GnistifyDB then return end
        local me = ns.Me()
        if not me then return end
        started = true
        local rec = CheckLogin(me)
        if IsMilestone(rec.count) and rec.ann ~= rec.last and C_Timer and C_Timer.After then
            C_Timer.After(ANNOUNCE_DELAY, function() Announce(me, rec) end)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg = ns.Readable(prefix), ns.Readable(msg)
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        local days = tonumber(msg:match("^STREAK;(%d+)"))
        if not days then return end
        local name = ns.Short(sender)
        if not name or name == ns.Me() then return end   -- already shown
        if days >= 1 and days <= MAX_DAYS then Show(name, days) end
    end
end)
