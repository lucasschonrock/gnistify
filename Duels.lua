-- Gnistify dueller: duel results between guild members for Gnisterne.
--
-- The game tells everyone nearby with a system message when a duel ends:
--   DUEL_WINNER_KNOCKOUT  "%1$s has defeated %2$s in a duel"
--   DUEL_WINNER_RETREAT   "%2$s has fled from %1$s in a duel"   (%1 winner, %2 loser)
-- Only duels where BOTH players are in the guild count. The duel is shown in
-- the chat window with a random Danish comment and counted in the PvP-tavle.
--
-- No double counting:
--   * Every client that sees the system message counts the duel itself (both
--     names must be guild members), so it works without anyone sending.
--   * Only a participant sends it to the others: the winner at once; the loser
--     only after SEND_WAIT sec and only if nobody else has sent it by then
--     (the winner may not have the addon).
--   * A duel is only counted once per winner+loser within DEDUPE_WINDOW sec, so
--     the system message and the addon message of the same duel never both count.
--
-- Only the total of duel wins per member is kept, as `duels` in the member's
-- PvP-tavle record (GnistifyDB.pvpBoard, see Leaderboard.lua: ns.DuelWin). It
-- is shown as the "Dueller" column there and synced and reset with the board.
--
-- Sync on the GnistDing prefix, to GUILD (older versions ignore it):
--   DUEL;winner;loser;fled      fled = 1 when the loser ran away. Append fields only.

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local DEDUPE_WINDOW = 20   -- sec: the same winner+loser inside this is the same duel
local SEND_WAIT = 4        -- sec the loser waits for the winner to send first

-- One is picked at random for every duel. {winner} and {loser} are the names.
local DUEL_MSGS = {
    "{winner} smadrede {loser} i en duel!",
    "{winner} gnistede {loser} ned i en duel!",
    "{loser} fik tæsk af {winner} i en duel!",
    "{winner} viste {loser} hvem der er best i en duel!",
    "Av! {loser} tabte stort til {winner} i en duel.",
    "{winner} tørrede gulvet op med {loser} i en duel!",
    "{loser} må ud og øve sig efter at have tabt til {winner}!",
    "{winner} slukkede {loser} i en duel. Længe leve gnisten!",
}
-- When the loser ran away. Same placeholders.
local FLED_MSGS = {
    "{loser} stak af fra {winner}! Fej!",
    "{loser} tabte nerven og flygtede fra {winner}!",
    "{winner} skræmte {loser} på flugt i en duel!",
    "Kyllingealarm! {loser} løb væk fra {winner}!",
    "{loser} nåede aldrig at tabe: bare at løbe fra {winner}!",
    "{winner} vandt, fordi {loser} turde ikke blive.",
}

-- Patterns -------------------------------------------------------------------

-- Turn a game format string ("%1$s has defeated %2$s in a duel") into a Lua
-- pattern and the order of the arguments: order[k] is which argument (1 or 2)
-- the k'th capture holds. Plain "%s" counts as the next argument.
local function BuildPattern(fmt)
    local out, order, i, n = {}, {}, 1, 0
    while i <= #fmt do
        local s, e, idx = fmt:find("^%%(%d)%$s", i)
        if not s then s, e = fmt:find("^%%s", i) end
        if s then
            n = n + 1
            order[#order + 1] = tonumber(idx) or n
            out[#out + 1] = "(.+)"
            i = e + 1
        else
            out[#out + 1] = (fmt:sub(i, i):gsub("%p", "%%%0"))   -- escape magic characters
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$", order
end

local function Pattern(global, fallback)
    local fmt = type(global) == "string" and global:find("%%") and global or fallback
    local pat, order = BuildPattern(fmt)
    return { pat = pat, order = order }
end

local KNOCKOUT = Pattern(DUEL_WINNER_KNOCKOUT, "%1$s has defeated %2$s in a duel")
local RETREAT  = Pattern(DUEL_WINNER_RETREAT,  "%2$s has fled from %1$s in a duel")

-- A duel system message -> winner, loser, fled (names as the game wrote them,
-- maybe only a first name), or nil
local function ParseDuel(msg)
    if type(msg) ~= "string" then return nil end
    for _, p in ipairs({ { KNOCKOUT, false }, { RETREAT, true } }) do
        local caps = { msg:match(p[1].pat) }
        if #caps == #p[1].order then
            local args = {}
            for k, arg in ipairs(p[1].order) do args[arg] = caps[k] end
            if args[1] and args[2] then return args[1], args[2], p[2] end
        end
    end
end
ns.ParseDuel = ParseDuel

-- Names ----------------------------------------------------------------------

local function FirstName(name) return name:match("^(%S+)") or name end

-- A guild member's full "First Surname" from a name as the system message may
-- write it ("First Surname", "First-Surname" or just "First"), or nil when it
-- is not a guild member (or a first name that two members share).
local function Resolve(name)
    name = ns.Short(name)
    if not name then return nil end
    local lname = name:lower()
    local me = ns.Me()
    if me and (me:lower() == lname or FirstName(me):lower() == lname) then return me end
    local byFirst, ambiguous = {}, {}
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local full = ns.Short((GetGuildRosterInfo(i)))
        if full then
            if full:lower() == lname then return full end
            local first = FirstName(full):lower()
            if byFirst[first] then ambiguous[first] = true end
            byFirst[first] = full
        end
    end
    if not name:find(" ") and not ambiguous[lname] then return byFirst[lname] end
end

-- Records --------------------------------------------------------------------

local function ServerTime()
    return (GetServerTime and Readable(GetServerTime())) or time()
end

local lastDuel = {}    -- "winner\nloser" -> server time it was last counted
local heardFrom = {}   -- "winner\nloser" -> server time someone else sent it

-- Show the duel in the chat window with a random comment
local function Show(winner, loser, fled, wins)
    if not GnistifyDB.duels then return end   -- the setting
    local text = ns.Fill(ns.Pick(fled and FLED_MSGS or DUEL_MSGS),
        { winner = winner, loser = loser },
        { winner = "ff6600", loser = "ffff00" })
    DEFAULT_CHAT_FRAME:AddMessage(GNIST_ICON .. " " .. text
        .. " |cffaaaaaa(" .. wins .. (wins == 1 and " duel-sejr" or " duel-sejre") .. ")|r")
end

-- A duel (from a system message or from the guild). Counted once per
-- winner+loser within DEDUPE_WINDOW. Returns true if it was new.
function ns.RecordDuel(winner, loser, fled)
    if not winner or not loser or winner == loser then return false end
    local key = winner .. "\n" .. loser
    local now = ServerTime()
    if lastDuel[key] and now - lastDuel[key] < DEDUPE_WINDOW then return false end
    lastDuel[key] = now
    Show(winner, loser, fled, ns.DuelWin(winner))   -- the total lives in the PvP-tavle
    return true
end

-- A duel I saw as a system message: count it if both are in the guild, and
-- tell the guild if I was in it.
local function OnSystemMessage(msg)
    local a, b, fled = ParseDuel(msg)
    if not a then return end
    if not IsInGuild() then return end
    local winner, loser = Resolve(a), Resolve(b)
    if not winner or not loser then return end   -- guild against guild only
    if not ns.RecordDuel(winner, loser, fled) then return end
    local me = ns.Me()
    local key = winner .. "\n" .. loser
    local text = "DUEL;" .. winner .. ";" .. loser .. ";" .. (fled and "1" or "0")
    if me == winner then
        ns.SendAddon(text)
    elseif me == loser and C_Timer then
        C_Timer.After(SEND_WAIT, function()
            -- The winner usually sends it; only step in if nobody did
            local heard = heardFrom[key]
            if not (heard and ServerTime() - heard < DEDUPE_WINDOW + SEND_WAIT) then
                ns.SendAddon(text)
            end
        end)
    end
end

-- A duel from the guild. Only a participant may report it (the winner, or the
-- loser when the winner has no addon), and both must be guild members, so
-- nobody can hand out duel wins to others.
local function OnAddonMessage(msg, sender)
    local _, winner, loser, fled = strsplit(";", msg)
    if type(winner) ~= "string" or winner == "" or type(loser) ~= "string" or loser == "" then return end
    winner, loser = Resolve(winner), Resolve(loser)
    if not winner or not loser then return end
    if sender ~= winner and sender ~= loser then return end
    heardFrom[winner .. "\n" .. loser] = ServerTime()
    ns.RecordDuel(winner, loser, fled == "1")
end

-- Events ---------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON" }) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(Readable((...)))
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        prefix, msg, channel = Readable(prefix), Readable(msg), Readable(channel)
        if prefix ~= PREFIX or channel ~= "GUILD" or type(msg) ~= "string" then return end
        if not msg:find("^DUEL;") then return end
        sender = ns.Short(Readable(sender))
        if not sender or sender == ns.Me() then return end   -- my own echo
        OnAddonMessage(msg, sender)
    end
end)
