-- Gnistify zone presence: when you enter a new zone, one chat line lists the
-- guildies who are online in the same zone. It reads the guild roster (so it
-- works for every guild member, with or without the addon). The roster itself
-- is fetched by Gnistify.lua; it calls ns.ZoneRosterUpdate on every update.

local ns = select(2, ...)

local WAIT = 3                  -- seconds to wait for a fresh roster, then use the cached one
local REPEAT_TIME = 120         -- no new line for the same zone within this many seconds
local MAX_NAMES = 15            -- longest list shown in one line

local pending = nil             -- { id } while we wait for the roster after a zone change
local pendingId = 0
local lastShown = {}            -- lower case zone -> GetTime() of the last automatic line
local firstEnter = true         -- the first PLAYER_ENTERING_WORLD after login

local function Norm(text)
    text = ns.Readable(text)
    if type(text) ~= "string" then return nil end
    text = strtrim(text):lower()
    if text == "" then return nil end
    return text
end

local function CurrentZone()
    local zone = ns.Readable(GetRealZoneText and GetRealZoneText())
    if type(zone) ~= "string" or zone == "" then return nil end
    return zone
end

-- Online guildies (not me) per zone: byZone[lower zone] = { zone = "Name", list = { {name, level} } }
local function ReadRoster()
    local byZone = {}
    if not IsInGuild() then return byZone end
    local num = GetNumGuildMembers()
    if not num or num == 0 then return byZone end
    local me = ns.Me()
    for i = 1, num do
        local fullName, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(i)
        local name, key = ns.Short(fullName), Norm(zone)
        level, online = ns.Readable(level), ns.Readable(online)
        if name and key and online and name ~= me then
            local z = byZone[key]
            if not z then
                z = { zone = strtrim(ns.Readable(zone)), list = {} }
                byZone[key] = z
            end
            z.list[#z.list + 1] = { name = name, level = type(level) == "number" and level or 0 }
        end
    end
    return byZone
end

local function Line(z)
    table.sort(z.list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    local parts = {}
    for i, g in ipairs(z.list) do
        if i > MAX_NAMES then
            parts[#parts + 1] = "og " .. (#z.list - MAX_NAMES) .. " mere"
            break
        end
        parts[#parts + 1] = g.level > 0 and (g.name .. " (" .. g.level .. ")") or g.name
    end
    local n = #z.list
    return n .. (n == 1 and " gnist i " or " gnister i ") .. z.zone .. ": " .. table.concat(parts, ", ")
end

-- Shows the list for one zone from the cached roster. Returns true if anything printed.
local function ShowZone(zone)
    local key = Norm(zone)
    local z = key and ReadRoster()[key]
    if z and #z.list > 0 then
        ns.Print(Line(z))
        return true
    end
    return false
end

-- Called when the roster answer came in, or the wait ran out.
local function Finish(id)
    if not pending or pending.id ~= id then return end   -- already printed for this zone change
    pending = nil
    local zone = CurrentZone()
    if not zone or not GnistifyDB.zonePresence then return end
    local key = Norm(zone)
    lastShown[key] = GetTime()
    ShowZone(zone)
end

local function ZoneEntered()
    if not GnistifyDB or not GnistifyDB.zonePresence or not IsInGuild() then return end
    local _, kind = IsInInstance()
    kind = ns.Readable(kind)
    if kind and kind ~= "none" then return end            -- dungeons, battlegrounds, arenas
    local key = Norm(CurrentZone())
    if not key then return end
    if pending then return end                             -- one line per zone change
    if lastShown[key] and GetTime() - lastShown[key] < REPEAT_TIME then return end
    pendingId = pendingId + 1
    pending = { id = pendingId }
    ns.RequestRoster()
    local id = pendingId
    if C_Timer and C_Timer.After then
        C_Timer.After(WAIT, function() Finish(id) end)
    else
        Finish(id)
    end
end

-- Gnistify.lua calls this on GUILD_ROSTER_UPDATE.
function ns.ZoneRosterUpdate()
    if pending then Finish(pending.id) end
end

-- /gnist her [zone prefix]
function ns.ZoneCommand(rest)
    if not IsInGuild() then ns.Print("Du er ikke i en guild.") return end
    ns.RequestRoster()
    rest = Norm(rest)
    if not rest then
        local zone = CurrentZone()
        if not zone then ns.Print("Kender ikke din zone endnu.") return end
        if not ShowZone(zone) then
            ns.Print("Ingen andre fra guilden i " .. zone .. ".")
        end
        return
    end
    local matches = {}
    for key, z in pairs(ReadRoster()) do
        if key:sub(1, #rest) == rest then matches[#matches + 1] = z end
    end
    if #matches == 0 then
        ns.Print("Ingen fra guilden online i en zone, der starter med \"" .. strtrim(rest) .. "\".")
        return
    end
    table.sort(matches, function(a, b) return a.zone < b.zone end)
    for _, z in ipairs(matches) do ns.Print(Line(z)) end
end

-- /gnist zoner: online guildies per zone, most first
function ns.ZonesCommand()
    if not IsInGuild() then ns.Print("Du er ikke i en guild.") return end
    ns.RequestRoster()
    local zones = {}
    for _, z in pairs(ReadRoster()) do zones[#zones + 1] = z end
    if #zones == 0 then ns.Print("Ingen andre fra guilden er online.") return end
    table.sort(zones, function(a, b)
        if #a.list ~= #b.list then return #a.list > #b.list end
        return a.zone < b.zone
    end)
    ns.Print("Gnister online fordelt på zoner:")
    for _, z in ipairs(zones) do
        ns.Print("  " .. z.zone .. ": " .. #z.list)
    end
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(f.RegisterEvent, f, event)
end
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Only the first one after login; later ones are loading screens
        -- (ZONE_CHANGED_NEW_AREA covers real zone changes).
        if not firstEnter then return end
        firstEnter = false
    end
    ZoneEntered()
end)
