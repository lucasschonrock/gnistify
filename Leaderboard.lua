-- Gnistify PvP-tavle: a world PvP leaderboard for Gnisterne.
--
-- Every kill of an enemy player OUTSIDE battlegrounds and arenas counts: the
-- killing blow, and helping (damaging the victim or healing in the fight, read
-- from the game's damage meter after combat; see Helpers in Kills.lua).
-- The board ranks guild members by kills today, this week (from Monday), this
-- month and of all time. #1 in each gets a title (an honour):
--   I dag: Dagens Gnistsprutter    Uge: Ugens Brandfakkel
--   Måned: Månedens Bålkonge       Altid: Gnistkejseren (#2 Gnistprinsen, #3 Gnistridderen)
--
-- Every client keeps a copy of everybody's record in GnistifyDB.pvpBoard:
--   [name] = { total = N, days = { [dayNumber] = kills } }
-- Each player is the source of their own record; total only ever goes up, so it
-- works as a version number: a record with a higher total always wins.
-- Duel wins (Duels.lua) are kept in the same record as `duels` (a total that
-- only goes up too; the higher one always wins) and are shown as a fifth list.
--
-- Sync (all on the GnistDing prefix, to GUILD; older versions ignore it):
--   LB;name;total;start;c1,c2,...;live;epoch;duels
--       A record. start is the day number of the first count; the counts run
--       up to the sender's today (empty = 0). live = 1 when sent right after
--       the kill, which is when new title holders are announced.
--   LBREQ
--       Sent a little after login. Everyone online (and the newcomer) then
--       queues every record they know. A queued record is dropped when someone
--       else sends the same or a newer one first, and anyone hearing an older
--       record than their own queues theirs as a correction. That way records
--       of players who are offline still travel from friend to friend.
--
-- Reset by vote: "/gnist reset" asks everyone online; at RESET_VOTES "ja" every
-- kill counter is wiped. Each reset starts a new "epoch" (the server time of
-- the vote), sent as the last field of every LB record. Records from an older
-- epoch are ignored, so a friend who was offline can't bring the old counts
-- back; instead they're told about the reset and wipe their copy too.
--   LBVOTE;epoch;name    name asks to reset (and votes yes)
--   LBYES;epoch          a yes vote
--   LBRESET;epoch        a reset happened (for those who missed the vote)

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local KEEP_DAYS = 40      -- day counts older than this are thrown away (total stays)
local SEND_GAP = 1.1      -- seconds between queued records (the game throttles addon messages)
local MIN_ROWS = 5        -- the window is never shorter than this many rows
local MAX_ROWS = 25       -- names shown per list; the rest becomes "... og N mere"
local DUEL_COL = { key = "duels", label = "Dueller", sub = "Vundne dueller", w = 170, titles = {} }

local PERIODS = {
    { key = "today", label = "I dag",       titles = { "Dagens Gnistsprutter" } },
    { key = "week",  label = "Denne uge",   titles = { "Ugens Brandfakkel" } },
    { key = "month", label = "Denne måned", titles = { "Månedens Bålkonge" } },
    { key = "all",   label = "All-time største slambert",  titles = { "Gnistkejseren", "Gnistprinsen", "Gnistridderen" } },
}
-- Shown when a kill makes someone the new (sole) #1. {name}, {titles}
local CROWN_MSGS = {
    "Kronen skifter hoved: {name} er nu {titles}!",
    "Bøj jer i støvet! {name} er nu {titles}!",
    "{name} har gnistret sig til titlen {titles}!",
    "Ny gnist på tronen: {name} er nu {titles}!",
    "Hils på {titles}: {name}! Længe leve gnisten!",
}
local MEDALS = { "ffd700", "c0c0c0", "cd7f32" }

-- Title sounds. One per kill, never on top of each other: a new month/all-time
-- #1 gets the big one, a new today/week #1 the small one. The files are made
-- quieter than the originals in art/sounds (about -24 LUFS) so they sit a bit
-- under the game's own sounds.
local CROWN_SOUNDS = {
    small = { file = "Interface\\AddOns\\Gnistify\\dexter.mp3", length = 10.7, rank = 1 },
    big   = { file = "Interface\\AddOns\\Gnistify\\fire.mp3",   length = 13.6, rank = 2 },
}
local KILL_SOUND_LENGTH = 1.1   -- sound.mp3, played with the kill line

-- Days ---------------------------------------------------------------------

-- A whole number per calendar day (local time). Noon, so daylight saving
-- can't push it over a day boundary.
local function DayNum(t)
    local d = date("*t", t)
    return math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end

-- today, first day of this week (Monday), first day of this month
local function Ranges()
    local t = date("*t")
    local today = DayNum()
    return today, today - (t.wday + 5) % 7, today - (t.day - 1)
end

-- Board --------------------------------------------------------------------

local function Board()
    GnistifyDB.pvpBoard = GnistifyDB.pvpBoard or {}
    return GnistifyDB.pvpBoard
end

local function Count(rec, key, today, weekStart, monthStart)
    if key == "all" then return rec.total or 0 end
    if key == "duels" then return rec.duels or 0 end
    local from = key == "today" and today or key == "week" and weekStart or monthStart
    local n = 0
    for d, c in pairs(rec.days or {}) do
        if d >= from and d <= today then n = n + c end
    end
    return n
end

-- { { name, n }, ... } best first, only players with kills in that period
local function Ranked(key)
    local today, ws, ms = Ranges()
    local list = {}
    for name, rec in pairs(Board()) do
        local n = Count(rec, key, today, ws, ms)
        if n > 0 then list[#list + 1] = { name = name, n = n } end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return list
end

-- Rank with ties: 1 + the number of players with strictly more kills
local function RankOf(list, i)
    local r = i
    while r > 1 and list[r - 1].n == list[i].n do r = r - 1 end
    return r
end

-- The title a name holds in one period, or nil
local function PeriodTitle(p, name, list)
    list = list or Ranked(p.key)
    for i, e in ipairs(list) do
        if e.name == name then return p.titles[RankOf(list, i)] end
    end
end

-- The best title a guild member holds right now (for the kill lines), or nil.
-- The all-time titles (top 3) beat month, week and today.
function ns.LeaderTitle(name)
    if not GnistifyDB or not GnistifyDB.pvpBoard or not name then return nil end
    return PeriodTitle(PERIODS[4], name) or PeriodTitle(PERIODS[3], name)
        or PeriodTitle(PERIODS[2], name) or PeriodTitle(PERIODS[1], name)
end

-- Which elite dragon a name gets on unit frames (Elite.lua): "elite" (gold)
-- for Gnistkejseren, "rareelite" (silver with wings) for #1 this month, "rare"
-- (silver) for #1 today or this week.
function ns.EliteKind(name)
    if not name or not GnistifyDB or not GnistifyDB.pvpBoard then return nil end
    local function first(p)
        local list = Ranked(p.key)
        for i, e in ipairs(list) do
            if RankOf(list, i) > 1 then return false end
            if e.name == name then return true end
        end
        return false
    end
    if first(PERIODS[4]) then return "elite" end
    if first(PERIODS[3]) then return "rareelite" end
    if first(PERIODS[2]) or first(PERIODS[1]) then return "rare" end
    return nil
end

-- Everyone holding a title right now: { { title, name, n }, ... } in period order
-- (today, week, month, all time). For the minimap tooltip.
function ns.TitleHolders()
    local out = {}
    if not GnistifyDB or not GnistifyDB.pvpBoard then return out end
    for _, p in ipairs(PERIODS) do
        local list = Ranked(p.key)
        for i, e in ipairs(list) do
            local t = p.titles[RankOf(list, i)]
            if not t then break end
            out[#out + 1] = { title = t, name = e.name, n = e.n }
        end
    end
    return out
end

-- Who is alone at the top of each period
local function SoleLeaders()
    local tops = {}
    for _, p in ipairs(PERIODS) do
        local list = Ranked(p.key)
        if list[1] and (not list[2] or list[2].n < list[1].n) then tops[p.key] = list[1].name end
    end
    return tops
end

-- "a", "a og b", "a, b og c"
local function JoinWords(words)
    if #words <= 1 then return words[1] or "" end
    return table.concat(words, ", ", 1, #words - 1) .. " og " .. words[#words]
end

local playing   -- { handle, ends, rank } of the title sound playing now

local function PlayCrownSound(which)
    local s = CROWN_SOUNDS[which]
    local now = GetTime()
    if playing and now < playing.ends then
        -- Something is playing: only a bigger sound may cut it off
        if s.rank <= playing.rank then return end
        if StopSound and playing.handle then StopSound(playing.handle, 500) end
    end
    local willPlay, handle = PlaySoundFile(s.file, "SFX")
    if willPlay then playing = { handle = handle, ends = now + s.length, rank = s.rank } end
end

function ns.PlayCrownSound(which) PlayCrownSound(which) end

-- Start the title sound once the kill sound is done, so they don't overlap
local function CrownSound(which)
    if not GnistifyDB.crownSound then return end
    local wait = ns.lastKillSound and (KILL_SOUND_LENGTH - (GetTime() - ns.lastKillSound)) or 0
    if wait > 0 and C_Timer then
        C_Timer.After(wait, function() PlayCrownSound(which) end)
    else
        PlayCrownSound(which)
    end
end

-- After a live kill: announce titles the killer has just taken
local function AnnounceCrowns(name, before)
    if not GnistifyDB.kills then return end
    local after, won, big = SoleLeaders(), {}, false
    for _, p in ipairs(PERIODS) do
        if after[p.key] == name and before[p.key] ~= name then
            won[#won + 1] = "|cffffcc00" .. p.titles[1] .. "|r"
            if p.key == "month" or p.key == "all" then big = true end
        end
    end
    if #won == 0 then return end
    local text = ns.Fill(ns.Pick(CROWN_MSGS), { name = "|cffff6600" .. name .. "|r", titles = JoinWords(won) })
    DEFAULT_CHAT_FRAME:AddMessage(GNIST_ICON .. " |cffffcc00Ny leder på PvP-tavlen!|r " .. text)
    CrownSound(big and "big" or "small")
    -- A new emperor deserves the big letters too
    if after.all == name and before.all ~= name and GnistifyDB.killBanner
       and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame,
            GNIST_ICON .. " " .. ns.Fill("{name} er den nye Gnistkejser!", { name = name }),
            ChatTypeInfo["GUILD"])
    end
end

local function Prune()
    local oldest = DayNum() - KEEP_DAYS
    for _, rec in pairs(Board()) do
        rec.days = rec.days or {}
        for d in pairs(rec.days) do
            if d < oldest then rec.days[d] = nil end
        end
    end
end

-- Window (defined further down) ---------------------------------------------
local Refresh

-- Resets -------------------------------------------------------------------

local RESET_VOTES = 4      -- yes votes needed (the one asking counts)
local VOTE_TIME = 90       -- seconds a vote stays open
local RESET_NOTICE_GAP = 30   -- at most one LBRESET from me this often

local function Epoch()
    return GnistifyDB.boardEpoch or 0
end

local function ServerTime()
    return (GetServerTime and Readable(GetServerTime())) or time()
end

local lastResetNotice = 0
local function SendResetNotice()
    if Epoch() == 0 or not IsInGuild() then return end
    if GetTime() - lastResetNotice < RESET_NOTICE_GAP then return end
    lastResetNotice = GetTime()
    ns.SendAddon("LBRESET;" .. Epoch())
end

local ClearQueue   -- the send queue, defined under Sending

-- Wipe every kill counter and start epoch e. late: I missed the vote (or my
-- client didn't count it to 4) and only hear of the reset now, so the others
-- already have kills since the reset that I don't: ask for the whole board.
local function AdoptEpoch(e, why, late)
    if e <= Epoch() then return end
    GnistifyDB.boardEpoch = e
    if ns.KillLog then ns.KillLog({ kind = "reset", epoch = e, late = late or false }) end
    wipe(Board())
    GnistifyDB.killCount = {}
    if ClearQueue then ClearQueue() end
    if late then
        ns.Print("|cffffcc00PvP-tavlen er blevet nulstillet,|r mens du ikke var med. Henter tavlen fra de andre...")
        if C_Timer then
            C_Timer.After(2, function()
                if IsInGuild() then ns.SendAddon("LBREQ") end
            end)
        end
    else
        ns.Print("|cffffcc00PvP-tavlen er nulstillet!|r " .. (why or "") .. " Alle drab starter forfra.")
    end
    if Refresh then Refresh() end
    if ns.RefreshElite then pcall(ns.RefreshElite) end
end

-- Sending ------------------------------------------------------------------

local function Encode(name)
    local rec = Board()[name]
    if not rec then return nil end
    local today, ws, ms = Ranges()
    local start = math.min(ws, ms)
    local counts = {}
    for d = start, today do
        local c = rec.days and rec.days[d]
        counts[#counts + 1] = (c and c > 0) and tostring(c) or ""
    end
    return table.concat({ "LB", name, rec.total or 0, start, table.concat(counts, ",") }, ";")
end

local function SendRecord(name, live)
    if not IsInGuild() then return end
    -- Turned off sharing my kills: don't spread my own record either
    if name == ns.Me() and not GnistifyDB.killsSend then return end
    local msg = Encode(name)
    -- The epoch goes last: older versions read only the fields before it
    if msg then
        ns.SendAddon(msg .. ";" .. (live and "1" or "0") .. ";" .. Epoch()
            .. ";" .. (Board()[name].duels or 0))
    end
end

local queue, queued, sending = {}, {}, false

local function SendNext()
    while #queue > 0 do
        local name = table.remove(queue, 1)
        if queued[name] then
            queued[name] = nil
            SendRecord(name, false)
            C_Timer.After(SEND_GAP, SendNext)
            return
        end
    end
    sending = false
end

-- Send a record soon. The random wait gives someone else the chance to send
-- it first, so not everyone online sends the same thing.
local function Queue(name)
    if queued[name] or not C_Timer then return end
    queued[name] = true
    queue[#queue + 1] = name
    if not sending then
        sending = true
        C_Timer.After(1 + math.random() * 4, SendNext)
    end
end

ClearQueue = function()
    wipe(queue)
    wipe(queued)
end

local function QueueAll()
    for name in pairs(Board()) do Queue(name) end
end

-- Receiving ----------------------------------------------------------------

local function Receive(msg)
    local _, name, total, start, counts, live, epoch, duels = strsplit(";", msg)
    total, start, epoch = tonumber(total), tonumber(start), tonumber(epoch) or 0
    duels = math.max(tonumber(duels) or 0, 0)
    if type(name) ~= "string" or name == "" or not total or not start or total < 0 then return end
    if epoch < Epoch() then
        SendResetNotice()          -- from before a reset: tell them, don't take it
        return
    elseif epoch > Epoch() then
        AdoptEpoch(epoch, nil, true)   -- they know of a reset I missed
    end
    local board = Board()
    local rec = board[name]
    local have = rec and rec.total or -1
    local haveDuels = rec and rec.duels or 0
    if have >= total then
        if duels > haveDuels then   -- same or older kills, but more duel wins
            rec.duels = duels
            if Refresh then Refresh() end
        end
        if have > total or haveDuels > duels then
            Queue(name)           -- they have an older record: send ours
        else
            queued[name] = nil    -- someone else already sent the same one
        end
        return
    end
    local before = live == "1" and SoleLeaders()
    local days, i = {}, 0
    for c in ((counts or "") .. ","):gmatch("([^,]*),") do
        local n = tonumber(c)
        if n and n > 0 then days[start + i] = n end
        i = i + 1
        if i > 62 then break end
    end
    board[name] = { total = total, days = days, duels = math.max(duels, haveDuels) }
    if haveDuels > duels then Queue(name) else queued[name] = nil end
    if before then AnnounceCrowns(name, before) end
    if Refresh then Refresh() end
    if ns.RefreshElite then pcall(ns.RefreshElite) end
end

-- A kill of mine, or one I helped with (called by Kills.lua) ----------------

function ns.LeaderboardKill()
    local _, instanceType = IsInInstance()
    instanceType = Readable(instanceType)
    if instanceType == "pvp" or instanceType == "arena" then return end   -- world PvP only
    local me = ns.Me()
    if not me then return end
    local board = Board()
    local before = SoleLeaders()
    local rec = board[me] or { total = 0, days = {} }
    board[me] = rec
    rec.days = rec.days or {}
    local today = DayNum()
    rec.total = (rec.total or 0) + 1
    rec.days[today] = (rec.days[today] or 0) + 1
    AnnounceCrowns(me, before)
    queued[me] = nil
    SendRecord(me, true)
    if Refresh then Refresh() end
    if ns.RefreshElite then pcall(ns.RefreshElite) end
end

-- A duel won by a guild member (called by Duels.lua): the winner's duel total
-- goes up. Every client counts each duel itself, so nothing is sent here; the
-- total reaches those who missed it through the normal record sync.
function ns.DuelWin(name)
    local rec = Board()[name]
    if not rec then
        rec = { total = 0, days = {} }
        Board()[name] = rec
    end
    rec.duels = (rec.duels or 0) + 1
    if Refresh then Refresh() end
    return rec.duels
end

-- Reset vote ---------------------------------------------------------------

local vote   -- { epoch, by, yes = { [name] = true }, ends }

local function VoteCount()
    local n = 0
    for _ in pairs(vote.yes) do n = n + 1 end
    return n
end

local function EndVote()
    vote = nil
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "GNISTIFY_RESET") end
end

local function AddYes(epoch, name)
    if not vote or vote.epoch ~= epoch or not name or vote.yes[name] then return end
    vote.yes[name] = true
    local n = VoteCount()
    if n >= RESET_VOTES then
        local e = vote.epoch
        EndVote()
        AdoptEpoch(e, "(" .. n .. " stemte ja)")
    else
        ns.Print("Nulstil PvP-tavlen: |cff00ff00" .. name .. "|r stemte ja (" .. n .. "/" .. RESET_VOTES .. ").")
    end
end

local function VoteYes()
    if not vote then
        ns.Print("Der er ingen afstemning lige nu.")
        return
    end
    local me = ns.Me()
    if vote.yes[me] then return end
    ns.SendAddon("LBYES;" .. vote.epoch)
    AddYes(vote.epoch, me)
end

local function StartVote(epoch, by)
    if vote and GetTime() < vote.ends then return false end
    vote = { epoch = epoch, by = by, yes = {}, ends = GetTime() + VOTE_TIME }
    C_Timer.After(VOTE_TIME, function()
        if vote and vote.epoch == epoch then
            ns.Print("Afstemningen om at nulstille PvP-tavlen er slut. Der kom kun "
                .. VoteCount() .. " af " .. RESET_VOTES .. " ja. Intet er nulstillet.")
            EndVote()
        end
    end)
    return true
end

if StaticPopupDialogs then
    StaticPopupDialogs["GNISTIFY_RESET"] = {
        text = "%s vil nulstille ALLE drab på PvP-tavlen.\n\nEr du enig? Der skal "
            .. RESET_VOTES .. " ja til.",
        button1 = "Ja, nulstil",
        button2 = "Nej",
        OnAccept = function() VoteYes() end,
        timeout = VOTE_TIME,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- /gnist reset
function ns.ResetCommand()
    if not IsInGuild() then
        ns.Print("Du skal være i en guild for at nulstille PvP-tavlen.")
        return
    end
    if vote and GetTime() < vote.ends then
        ns.Print("Der er allerede en afstemning i gang (" .. VoteCount() .. "/" .. RESET_VOTES .. " ja).")
        return
    end
    local epoch = math.max(ServerTime(), Epoch() + 1)
    local me = ns.Me()
    StartVote(epoch, me)
    ns.SendAddon("LBVOTE;" .. epoch .. ";" .. me)
    ns.Print("Du har bedt om at nulstille PvP-tavlen. Der skal " .. RESET_VOTES
        .. " ja til inden for " .. VOTE_TIME .. " sek. Du har selv stemt ja.")
    AddYes(epoch, me)
end

function ns.ResetVoteYes() VoteYes() end

local function ReceiveVote(msg, sender)
    local kind, epoch, by = strsplit(";", msg)
    epoch = tonumber(epoch)
    if not epoch then return end
    if kind == "LBRESET" then
        AdoptEpoch(epoch, nil, true)
    elseif kind == "LBVOTE" then
        if epoch <= Epoch() then return end
        by = (by and by ~= "") and by or sender
        if not StartVote(epoch, by) then return end
        AddYes(epoch, by)
        ns.Print("|cffff6600" .. by .. "|r vil nulstille PvP-tavlen. Stem ja i vinduet eller med /gnist ja.")
        if StaticPopup_Show then pcall(StaticPopup_Show, "GNISTIFY_RESET", by) end
    elseif kind == "LBYES" then
        AddYes(epoch, sender)
    end
end

-- Window -------------------------------------------------------------------
-- Five lists side by side (today, week, month, all time, duel wins). The window grows
-- with the longest list, so the whole guild fits (up to MAX_ROWS each).

local COL_W, ROW_H = 250, 18
local TOP, LIST_TOP = -34, -78   -- header row, first name row (from the window top)
local win = CreateFrame("Frame", "GnistifyPvPFrame", UIParent, "BasicFrameTemplateWithInset")
win:SetWidth(COL_W * #PERIODS + DUEL_COL.w + 32)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetClampedToScreen(true)
win:Hide()
tinsert(UISpecialFrames, "GnistifyPvPFrame")   -- Esc closes it

local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -5)
title:SetText(GNIST_ICON .. " |cffffcc00Gnisternes|r |cffff6600PvP-tavle|r")

local footer = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
footer:SetPoint("BOTTOM", 0, 12)
footer:SetText("Kun killing blows i world PvP tæller (ikke BG og arena). Dueller: kun guild mod guild.")

local cells = {}
for i = 1, #PERIODS + 1 do
    local p = PERIODS[i] or DUEL_COL      -- the duel list is the last one, a bit narrower
    local x = 16 + (i - 1) * COL_W
    local c = { period = p, rows = {}, x = x, w = p.w or COL_W }
    c.header = win:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    c.header:SetPoint("TOPLEFT", x + 4, TOP)
    c.header:SetWidth(c.w - 12)
    c.header:SetJustifyH("LEFT")
    c.header:SetText(p.label)
    c.sub = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    c.sub:SetPoint("TOPLEFT", x + 4, TOP - 22)
    c.sub:SetText(p.sub or ("Titel: " .. p.titles[1]))
    c.me = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cells[i] = c
end

-- Row r of a list, made the first time it's needed
local function Row(c, r)
    local row = c.rows[r]
    if row then return row end
    local y = LIST_TOP - (r - 1) * ROW_H
    row = {}
    if r % 2 == 0 then   -- faint stripes make long lists easier to read
        row.bg = win:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.bg:SetColorTexture(1, 1, 1, 0.04)
        row.bg:SetPoint("TOPLEFT", c.x, y + 2)
        row.bg:SetSize(c.w - 6, ROW_H)
    end
    row.name = win:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", c.x + 4, y)
    row.name:SetWidth(c.w - 50)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.n = win:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.n:SetPoint("TOPRIGHT", win, "TOPLEFT", c.x + c.w - 12, y)
    row.n:SetJustifyH("RIGHT")
    c.rows[r] = row
    return row
end

local function SetRow(row, name, n)
    row.name:SetText(name)
    row.n:SetText(n)
    row.name:Show(); row.n:Show()
    if row.bg then row.bg:Show() end
end

local function HideRow(row)
    row.name:Hide(); row.n:Hide()
    if row.bg then row.bg:Hide() end
end

Refresh = function()
    if not win:IsShown() then return end
    local me = ns.Me()
    local tallest = MIN_ROWS
    for _, c in ipairs(cells) do
        local list = Ranked(c.period.key)
        local shown = math.min(#list, MAX_ROWS)
        local myRank, mine
        for i, e in ipairs(list) do
            if e.name == me then myRank, mine = RankOf(list, i), e.n end
        end
        for r = 1, math.max(shown, 1, #c.rows) do
            local e = list[r]
            if r <= shown then
                local rank = RankOf(list, r)
                local color = e.name == me and "ff6600" or "ffffff"
                -- #1's title is in the header; only #2 and #3 all-time get theirs here
                local t = rank > 1 and c.period.titles[rank]
                SetRow(Row(c, r), ("|cff%s%d.|r |cff%s%s|r%s"):format(MEDALS[rank] or "aaaaaa", rank,
                    color, e.name, t and (" |cffffcc00(" .. t .. ")|r") or ""), e.n)
            elseif r == 1 then
                SetRow(Row(c, 1), c.period == DUEL_COL and "|cffaaaaaaIngen dueller endnu|r" or "|cffaaaaaaIngen drab endnu|r", "")
            elseif c.rows[r] then
                HideRow(c.rows[r])
            end
        end
        -- Under the list: how many more, and where I am if I'm not shown
        local extra = {}
        if #list > shown then extra[#extra + 1] = ("... og %d mere"):format(#list - shown) end
        if myRank and myRank > shown then
            extra[#extra + 1] = ("Dig: nr. %d med %d %s"):format(myRank, mine,
                c.period == DUEL_COL and "sejre" or "drab")
        end
        c.me:ClearAllPoints()
        c.me:SetPoint("TOPLEFT", c.x + 4, LIST_TOP - math.max(shown, 1) * ROW_H - 4)
        c.me:SetText(table.concat(extra, "  "))
        tallest = math.max(tallest, shown + (#extra > 0 and 1 or 0))
    end
    win:SetHeight(-LIST_TOP + tallest * ROW_H + 44)
end

win:SetScript("OnShow", Refresh)
-- Keep "today" right across midnight while the window is open
local elapsed = 0
win:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 30 then elapsed = 0; Refresh() end
end)

function ns.ToggleLeaderboard()
    if win:IsShown() then win:Hide() else win:Show() end
end

-- Events -------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON" }) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Prune()
        -- Guild info isn't there right at login; ask for the board a bit later
        if C_Timer then
            C_Timer.After(15, function()
                if not IsInGuild() then return end
                ns.SendAddon("LBREQ")
                QueueAll()
            end)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        prefix, msg, channel = Readable(prefix), Readable(msg), Readable(channel)
        if prefix ~= PREFIX or channel ~= "GUILD" or type(msg) ~= "string" then return end
        if not msg:find("^LB") then return end
        if ns.Short(sender) == ns.Me() then return end   -- my own echo
        if msg == "LBREQ" then
            QueueAll()
            if Epoch() > 0 and C_Timer then
                C_Timer.After(math.random() * 4, SendResetNotice)   -- a newcomer may have missed a reset
            end
        elseif msg:find("^LB;") then
            Receive(msg)
        elseif msg:find("^LB%u+;") then
            ReceiveVote(msg, ns.Short(sender))
        end
    end
end)
