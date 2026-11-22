-- Professions: every client shares its own professions and skill levels with the
-- guild, so `/gnist prof <profession>` can list who has what (also offline
-- members, from the saved copy). Profession names are the English names the
-- client returns, on purpose.
--
-- Message on the GnistDing prefix (GUILD), entries are optional and in no
-- fixed order:  PROF;Alchemy=225/300;Engineering=39/75
-- Receivers ignore entries they don't know, so new fields can be appended.
-- PROFREQ asks everyone online to send theirs again.
-- Data: GnistifyDB.profs[name] = { t = time(), Alchemy = { 225, 300 }, ... }

local ns = select(2, ...)
local Readable = ns.Readable
local PREFIX = ns.PREFIX

local SEND_DELAY = 10        -- seconds after login before the first send
local CHANGE_MIN = 30        -- at most one send per this many seconds when skills change
local REPLY_COOLDOWN = 60    -- at most one reply to a PROFREQ per this many seconds
local REQUEST_COOLDOWN = 60  -- at most one PROFREQ per this many seconds
local MAX_BYTES = 240        -- addon messages are limited to 255 bytes
local MAX_SKILL = 700        -- bigger values are junk
local MAX_ROWS = 25

-- Canonical (English) names, primary first
local PROF_LIST = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Leatherworking", "Mining", "Skinning", "Tailoring",
    "Cooking", "First Aid", "Fishing",
}
local KNOWN = {}
for _, name in ipairs(PROF_LIST) do KNOWN[name] = true end

-- Short forms (lower case) that are not just a prefix of the name
local ALIASES = {
    alch = "Alchemy", bs = "Blacksmithing", smith = "Blacksmithing",
    ench = "Enchanting", enchant = "Enchanting", eng = "Engineering", engi = "Engineering",
    herb = "Herbalism", lw = "Leatherworking", leather = "Leatherworking",
    mine = "Mining", skin = "Skinning", tailor = "Tailoring",
    cook = "Cooking", fa = "First Aid", firstaid = "First Aid", fish = "Fishing",
}

-- Case-insensitive match of what the player typed. Returns the profession,
-- or nil and a list of the professions it could have meant (empty = none).
local function MatchProfession(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if input == "" then return nil, {} end
    if ALIASES[input] then return ALIASES[input] end
    local found = {}
    for _, name in ipairs(PROF_LIST) do
        local lower = name:lower()
        if lower == input then return name end
        if lower:sub(1, #input) == input then found[#found + 1] = name end
    end
    if #found == 1 then return found[1] end
    return nil, found
end

-- "Alchemy=225/300;Fishing=1/75" from { Alchemy = {225,300}, ... }, with the
-- "PROF;" in front. Stays under MAX_BYTES (drops the last entries if needed).
local function Encode(skills)
    local msg = "PROF"
    for _, name in ipairs(PROF_LIST) do
        local s = skills[name]
        if s then
            local part = (";%s=%d/%d"):format(name, s[1], s[2])
            if #msg + #part > MAX_BYTES then break end
            msg = msg .. part
        end
    end
    return msg
end

-- The skills in a PROF message, or nil if it isn't one. Unknown names and
-- bad numbers are skipped.
local function Decode(msg)
    if type(msg) ~= "string" then return nil end
    if msg ~= "PROF" and not msg:find("^PROF;") then return nil end
    local skills = {}
    for part in msg:gmatch("[^;]+") do
        local name, cur, max = part:match("^([%a ]+)=(%d+)/(%d+)$")
        cur, max = tonumber(cur), tonumber(max)
        if name and KNOWN[name] and cur and max and cur >= 1 and cur <= max and max <= MAX_SKILL then
            skills[name] = { cur, max }
        end
    end
    return skills
end

-- Reads my professions. Retail has GetProfessions/GetProfessionInfo, classic has
-- GetSkillLineInfo; on Forever's client both may exist, so use both (retail first).
-- Every value goes through Readable and pcall.
local function ReadMine()
    local skills = {}
    local function add(name, cur, max)
        name, cur, max = Readable(name), Readable(cur), Readable(max)
        if type(name) == "string" and KNOWN[name] and not skills[name]
           and type(cur) == "number" and type(max) == "number"
           and cur >= 1 and cur <= max and max <= MAX_SKILL then
            skills[name] = { cur, max }
        end
    end

    if GetProfessions and GetProfessionInfo then
        local got = { pcall(GetProfessions) }   -- may have nil holes (no second profession)
        if got[1] then
            for i = 2, 6 do
                local index = Readable(got[i])
                if type(index) == "number" then
                    local ok2, name, _, rank, maxRank = pcall(GetProfessionInfo, index)
                    if ok2 then add(name, rank, maxRank) end
                end
            end
        end
    end

    if GetNumSkillLines and GetSkillLineInfo then
        local ok, num = pcall(GetNumSkillLines)
        num = ok and Readable(num)
        if type(num) == "number" then
            for i = 1, num do
                local ok2, name, header, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
                if ok2 and not Readable(header) then add(name, rank, maxRank) end
            end
        end
    end
    return skills
end

local function Store(name, skills)
    local db = GnistifyDB
    if not db or not name then return end
    db.profs = db.profs or {}
    skills.t = time()
    db.profs[name] = skills
end

-- Sending ----------------------------------------------------------------

local lastSent, lastMsg = 0, nil
local lastReply = 0
local lastRequest = 0
local changeTimer

-- Reads and stores my professions; sends them unless sharing is off.
-- force sends even if nothing changed since the last send.
local function Refresh(force)
    local me = ns.Me()
    if not me or not GnistifyDB then return end
    local skills = ReadMine()
    local msg = Encode(skills)
    Store(me, skills)
    if not GnistifyDB.profShare or not IsInGuild() then return end
    if not force and msg == lastMsg then return end
    lastMsg, lastSent = msg, GetTime()
    ns.SendAddon(msg)
end

local function After(seconds, func)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, func) else func() end
end

-- Skills changed (the event can fire a lot): send at most once per CHANGE_MIN sec
local function OnSkillsChanged()
    if changeTimer then return end
    changeTimer = true
    After(math.max(2, CHANGE_MIN - (GetTime() - lastSent)), function()
        changeTimer = nil
        Refresh(false)
    end)
end

-- Someone asked: answer after a random delay, so not everybody answers at once
local function OnRequest()
    if not GnistifyDB or not GnistifyDB.profShare then return end
    local now = GetTime()
    if now - lastReply < REPLY_COOLDOWN then return end
    lastReply = now
    After(1 + math.random() * 8, function() Refresh(true) end)
end

-- /gnist prof [profession] -----------------------------------------------

local function AgeText(t)
    local days = math.floor((time() - (tonumber(t) or time())) / 86400)
    if days < 1 then return "" end
    return (" |cff999999(%d %s gammel)|r"):format(days, days == 1 and "dag" or "dage")
end

function ns.ProfCommand(rest)
    local db = GnistifyDB
    local profs = db.profs or {}

    -- Ask everyone online to send theirs again, so the next lookup is fresh
    if IsInGuild() and GetTime() - lastRequest >= REQUEST_COOLDOWN then
        lastRequest = GetTime()
        ns.SendAddon("PROFREQ")
    end

    rest = rest or ""
    if rest:match("^%s*$") then
        -- No argument: how many known members have each profession
        local counts, any = {}, false
        for _, skills in pairs(profs) do
            for name in pairs(skills) do
                if KNOWN[name] then counts[name] = (counts[name] or 0) + 1; any = true end
            end
        end
        if not any then
            ns.Print("Ingen professioner kendt endnu. Prøv igen om lidt, når de andre har svaret.")
            return
        end
        ns.Print("Professioner i guilden (skriv /gnist prof <profession>):")
        for _, name in ipairs(PROF_LIST) do
            if counts[name] then
                ns.Print(("  %s: %d"):format(name, counts[name]))
            end
        end
        return
    end

    local prof, options = MatchProfession(rest)
    if not prof then
        if #options > 1 then
            ns.Print("Mente du: " .. table.concat(options, ", ") .. "?")
        else
            ns.Print("Kender ikke professionen \"" .. rest .. "\". Prøv: " .. table.concat(PROF_LIST, ", ") .. ".")
        end
        return
    end

    local list = {}
    for name, skills in pairs(profs) do
        local s = skills[prof]
        if type(s) == "table" then
            list[#list + 1] = { name = name, cur = s[1], max = s[2], t = skills.t }
        end
    end
    if #list == 0 then
        ns.Print(prof .. ": ingen kendt endnu.")
        return
    end
    table.sort(list, function(a, b)
        if a.cur ~= b.cur then return a.cur > b.cur end
        return a.name < b.name
    end)
    local parts = {}
    for i = 1, math.min(#list, MAX_ROWS) do
        local e = list[i]
        parts[#parts + 1] = ("|cffff6600%s|r %d/%d%s"):format(e.name, e.cur, e.max, AgeText(e.t))
    end
    local more = #list > MAX_ROWS and (" ... og %d mere"):format(#list - MAX_ROWS) or ""
    ns.Print(prof .. ": " .. table.concat(parts, ", ") .. more)
end

ns.MatchProfession, ns.ProfEncode, ns.ProfDecode = MatchProfession, Encode, Decode

-- Events -----------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "CHAT_MSG_ADDON",
}) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        After(SEND_DELAY, function()
            Refresh(true)
            -- A new user (nobody but me in the cache) asks the others for theirs
            local others = 0
            for name in pairs(GnistifyDB.profs or {}) do
                if name ~= ns.Me() then others = others + 1 end
            end
            if IsInGuild() and others == 0 then
                lastRequest = GetTime()
                ns.SendAddon("PROFREQ")
            end
        end)

    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        OnSkillsChanged()

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg = Readable(prefix), Readable(msg)
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        if not msg:find("^PROF") then return end
        local name = ns.Short(sender)
        if not name or name == ns.Me() then return end   -- my own data is stored locally
        if msg == "PROFREQ" then
            OnRequest()
        else
            local skills = Decode(msg)
            if skills then Store(name, skills) end
        end
    end
end)
