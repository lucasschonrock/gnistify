-- Gnistify Nordvestlisten: the guild's kill-on-sight list.
--
-- Right-click a player (target frame, nameplate menu, chat name) and pick
-- "Sæt på Nordvestlisten", optionally with a reason. Every Gnistify user in the
-- guild is told, and from then on:
--   - seeing him (target, mouseover, focus, nameplate) gives a chat line, a
--     banner and the raid-warning sound (at most once per ALERT_REPEAT per name);
--   - a red skull sits above his nameplate and on the target portrait, and his
--     tooltip says who put him on the list and why;
--   - the first to spot him tells the guild where he is (NVSEEN);
--   - killing him gives an extra "NORDVEST-DRAB!" line and the big fire sound.
--
-- Messages on GnistDing to GUILD (append fields only):
--   NV;name;t;by;removed;live;kills;class;level;guild;reason
--       One record. t = server time of the last add/remove: the newer t wins.
--       kills only goes up: the higher one always wins, whatever t says.
--       live = 1 right after someone added/removed him (shown in chat).
--   NVREQ          sent 20 sec after login; everyone queues all records. Like the
--                  PvP-tavle: a queued record is dropped when someone else sends
--                  the same or newer one, and hearing an older one queues ours.
--   NVSEEN;name;zone   I just spotted him.
-- Data: GnistifyDB.nordvestList[name] = { t, by, removed, kills, class, level, guild, reason, seen, seenBy, seenZone }
-- Removed records stay (as removed) so the removal spreads; pruned after 60 days.

local ns = select(2, ...)
local Readable = ns.Readable

local LIST_NAME = "Nordvestlisten"
local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local SKULL_ICON = "|T" .. SKULL .. ":0|t"
local ALERT_SOUND = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
local SEEN_SOUND = (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175
local ALERT_REPEAT = 120   -- seconds before the same player alerts me again
local SEEN_REPEAT = 120    -- seconds before the same player's sighting is shared/shown again
local SEND_GAP = 1.2       -- seconds between queued records
local REQ_DELAY = 20       -- seconds after login before NVREQ
local MAX_REASON = 80
local MAX_ENTRIES = 300
local PRUNE_DAYS = 60

local ALERT_MSGS = {
    "{victim} er på Nordvestlisten! Gnist løs!",
    "Nordvest i sigte: {victim}! Ingen nåde!",
    "Pas på: {victim} står på Nordvestlisten. Sluk lyset!",
    "{victim} er tilbage! Nordvestlisten glemmer ikke!",
    "Kill on sight: {victim}! Længe leve gnisten!",
}
local ADD_MSGS = {
    "{by} har sat {victim} på Nordvestlisten!",
    "{victim} er skrevet på Nordvestlisten af {by}. Gnist ved første øjekast!",
    "Ny på Nordvestlisten: {victim} (tilføjet af {by}).",
}
local REMOVE_MSGS = {
    "{by} har fjernet {victim} fra Nordvestlisten. Tilgivet... for nu.",
    "{victim} er strøget fra Nordvestlisten af {by}.",
}
local KILL_MSGS = {
    "NORDVEST-DRAB! {victim} fik sin straf af {killer}!",
    "NORDVEST-DRAB! {killer} har udført dommen over {victim}!",
    "NORDVEST-DRAB! {victim} lærte det på den hårde måde. Tak, {killer}!",
}

local function DB()
    GnistifyDB.nordvestList = GnistifyDB.nordvestList or {}
    return GnistifyDB.nordvestList
end

local function ServerTime()
    return (GetServerTime and Readable(GetServerTime())) or time()
end

-- The active record for a name, or nil
local function Entry(name)
    if not name or not GnistifyDB then return nil end
    local e = DB()[name]
    if e and not e.removed then return e end
end
ns.NordvestEntry = Entry

-- Find a record by name, ignoring case ("torden tim" -> "Torden Tim")
local function FindName(text)
    if not text or text == "" then return nil end
    local lower = text:lower()
    for name in pairs(DB()) do
        if name:lower() == lower then return name end
    end
end

-- "torden tim" -> "Torden Tim" (ASCII first letters only, good enough)
local function Capitalize(text)
    return (text:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b end))
end

local function Clean(text, max)
    text = tostring(text or ""):gsub("[;|\n\r]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if max and #text > max then text = text:sub(1, max) end
    return text
end

local function ClassText(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or nil
end

local function ColoredName(name, classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
    return "|cffff2020" .. name .. "|r"
end

-- "Torden Tim (lvl 34 Magiker) <Guild>"
local function Describe(name, e)
    local parts = { ColoredName(name, e.class) }
    local info = {}
    if e.level and e.level > 0 then info[#info + 1] = "lvl " .. e.level end
    local cls = ClassText(e.class)
    if cls then info[#info + 1] = cls end
    if #info > 0 then parts[#parts + 1] = "(" .. table.concat(info, " ") .. ")" end
    if e.guild and e.guild ~= "" then parts[#parts + 1] = "<" .. e.guild .. ">" end
    return table.concat(parts, " ")
end

local function Ago(t)
    local s = ServerTime() - (t or 0)
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min" end
    if s < 86400 then return math.floor(s / 3600) .. " t" end
    local d = math.floor(s / 86400)
    return d .. (d == 1 and " dag" or " dage")
end

local function Banner(text)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"] or ChatTypeInfo["GUILD"])
    end
end

-- Units ---------------------------------------------------------------------

local function IsGuildie(unit)
    return UnitIsInMyGuild and Readable(UnitIsInMyGuild(unit)) == true
end

-- name, or nil when the unit can't go on the list (not a player, me, a guildie)
local function UnitListName(unit)
    if not unit or not Readable(UnitExists(unit)) or not Readable(UnitIsPlayer(unit)) then return nil end
    if Readable(UnitIsUnit(unit, "player")) or IsGuildie(unit) then return nil end
    return ns.FullName(unit)
end

-- Keep class, level and guild up to date while we can see him (local only)
local function Refresh(e, unit)
    e.class = Readable((select(2, UnitClass(unit)))) or e.class
    local level = Readable(UnitLevel(unit))
    if type(level) == "number" and level > 0 then e.level = level end
    local guild = Readable((GetGuildInfo(unit)))
    if type(guild) == "string" and guild ~= "" then e.guild = guild end
end

-- Sending -------------------------------------------------------------------

local function Record(name, e, live)
    local msg = table.concat({
        "NV", name, e.t or 0, e.by or "", e.removed and 1 or 0, live and 1 or 0, e.kills or 0,
        e.class or "", e.level or 0, Clean(e.guild, 40), "",
    }, ";")
    local reason = Clean(e.reason, MAX_REASON)
    -- addon messages max out at 255 bytes: shorten the reason to fit
    local room = 250 - #msg
    if #reason > room then reason = room > 0 and reason:sub(1, room) or "" end
    return msg .. reason
end

local function SendRecord(name, live)
    local e = DB()[name]
    if e and IsInGuild() then ns.SendAddon(Record(name, e, live)) end
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

-- Random wait first, so someone else may send it and we can skip ours
local function Queue(name)
    if queued[name] or not C_Timer then return end
    queued[name] = true
    table.insert(queue, math.random(#queue + 1), name)   -- shuffled: not everyone in the same order
    if not sending then
        sending = true
        C_Timer.After(1 + math.random() * 4, SendNext)
    end
end

-- Visuals -------------------------------------------------------------------

local plateMarks = {}   -- nameplate frame -> our marker frame
local targetSkull

local function PlateMark(plate)
    local m = plateMarks[plate]
    if m then return m end
    m = CreateFrame("Frame", nil, plate)
    m:SetSize(26, 26)
    m:SetPoint("BOTTOM", plate, "TOP", 0, -4)
    m:SetFrameStrata("HIGH")
    local tex = m:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(SKULL)
    local glow = m:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(40, 40)
    glow:SetTexture("Interface\\Cooldown\\star4")
    glow:SetVertexColor(1, 0.1, 0.1, 0.8)
    glow:SetBlendMode("ADD")
    m:Hide()
    plateMarks[plate] = m
    return m
end

local function UpdatePlate(unit)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local show = GnistifyDB.nordvestMarks and Entry(UnitListName(unit))
    if show then
        PlateMark(plate):Show()
    elseif plateMarks[plate] then
        plateMarks[plate]:Hide()
    end
end

local function UpdateAllPlates()
    for _, m in pairs(plateMarks) do m:Hide() end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if Readable(UnitExists(unit)) then pcall(UpdatePlate, unit) end
    end
end

local function UpdateTarget()
    local c = TargetFrame and TargetFrame.TargetFrameContainer
    local portrait = (c and c.Portrait) or TargetFramePortrait
    local parent = (c and c.Portrait and c) or TargetFrame
    if not portrait or not parent then return end
    if not targetSkull then
        targetSkull = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        targetSkull:SetTexture(SKULL)
        targetSkull:SetSize(24, 24)
        targetSkull:SetPoint("CENTER", portrait, "TOPRIGHT", -6, -6)
    end
    targetSkull:SetShown(GnistifyDB.nordvestMarks and Entry(UnitListName("target")) and true or false)
end

local function RefreshVisuals()
    if not GnistifyDB then return end
    pcall(UpdateAllPlates)
    pcall(UpdateTarget)
end
ns.RefreshNordvest = RefreshVisuals

-- Tooltip line: who put him on the list and why
local function OnTooltipUnit(tt)
    if tt ~= GameTooltip or not GnistifyDB then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    unit = ok and Readable(unit)
    if type(unit) ~= "string" then return end
    local e = Entry(UnitListName(unit))
    if not e then return end
    tt:AddLine(SKULL_ICON .. " |cffff2020Nordvestlisten|r", 1, 0.2, 0.2)
    local line = "Tilføjet af " .. (e.by ~= "" and e.by or "?") .. " for " .. Ago(e.t) .. " siden"
    tt:AddLine(line, 0.9, 0.9, 0.9)
    if e.reason and e.reason ~= "" then tt:AddLine("\"" .. e.reason .. "\"", 1, 0.82, 0, true) end
    if (e.kills or 0) > 0 then tt:AddLine("Gnistet " .. e.kills .. " gang" .. (e.kills == 1 and "" or "e"), 0.7, 0.7, 0.7) end
    tt:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt)
        pcall(OnTooltipUnit, tt)
    end)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(OnTooltipUnit, tt) end)
end

-- Alerts --------------------------------------------------------------------

local alerted = {}      -- name -> GetTime() I was last alerted
local seenShared = {}   -- name -> GetTime() of the last sighting (mine sent or theirs heard)

local function Zone()
    return Readable(GetRealZoneText()) or Readable(GetZoneText()) or "?"
end

local function Alert(name, e, unit)
    Refresh(e, unit)
    local now = GetTime()
    if alerted[name] and now - alerted[name] < ALERT_REPEAT then return end
    alerted[name] = now
    e.seen, e.seenBy, e.seenZone = ServerTime(), ns.Me(), Zone()
    if not GnistifyDB.nordvest then return end
    local text = ns.Fill(ns.Pick(ALERT_MSGS), { victim = Describe(name, e) })
    if e.reason and e.reason ~= "" then text = text .. " |cffaaaaaa(\"" .. e.reason .. "\")|r" end
    DEFAULT_CHAT_FRAME:AddMessage(SKULL_ICON .. " |cffff2020[Nordvest]|r " .. text)
    if GnistifyDB.nordvestBanner then
        Banner(SKULL_ICON .. " NORDVEST: " .. ColoredName(name, e.class) .. "! " .. SKULL_ICON)
    end
    if GnistifyDB.nordvestSound then PlaySound(ALERT_SOUND, "Master") end
    -- Tell the guild where he is, unless someone just did
    if GnistifyDB.nordvestSend and IsInGuild()
       and not (seenShared[name] and now - seenShared[name] < SEEN_REPEAT) then
        seenShared[name] = now
        ns.SendAddon("NVSEEN;" .. name .. ";" .. Clean(Zone(), 60))
    end
end

local function Check(unit)
    if not GnistifyDB then return end
    local name = UnitListName(unit)
    local e = Entry(name)
    if e then Alert(name, e, unit) end
end

-- Adding and removing ---------------------------------------------------------

local function Announce(msgs, name, e, by)
    if not GnistifyDB.nordvest then return end
    local text = ns.Fill(ns.Pick(msgs), { victim = Describe(name, e), by = "|cffff6600" .. (by or "?") .. "|r" })
    if not e.removed and e.reason and e.reason ~= "" then
        text = text .. " |cffaaaaaa(\"" .. e.reason .. "\")|r"
    end
    DEFAULT_CHAT_FRAME:AddMessage(SKULL_ICON .. " |cffff2020[Nordvest]|r " .. text)
end

-- A plain guild chat line (setting nordvestGuildChat), so guildies without the
-- addon hear it too. No colour codes: guild chat doesn't allow them.
local function GuildPost(name, e)
    if not GnistifyDB.nordvestGuildChat or not IsInGuild() or not ns.SendGuild then return end
    local text
    if e.removed then
        text = "Jeg har fjernet " .. name .. " fra Nordvestlisten."
    else
        local info = {}
        if e.level and e.level > 0 then info[#info + 1] = "lvl " .. e.level end
        info[#info + 1] = ClassText(e.class)
        if e.guild and e.guild ~= "" then info[#info + 1] = "<" .. e.guild .. ">" end
        text = "{skull} Jeg har sat " .. name .. (#info > 0 and " (" .. table.concat(info, " ") .. ")" or "")
            .. " på Nordvestlisten!"
        if e.reason and e.reason ~= "" then text = text .. " Grund: " .. e.reason .. "." end
        text = text .. " Kill on sight! {skull}"
    end
    ns.SendGuild(text:sub(1, 250))
end

-- unit (optional) fills in class, level and guild
local function Add(name, reason, unit)
    if not name then return end
    local db = DB()
    local e = db[name]
    if not e then
        local count = 0
        for _ in pairs(db) do count = count + 1 end
        if count >= MAX_ENTRIES then
            ns.Print("Nordvestlisten er fuld (" .. MAX_ENTRIES .. "). Fjern nogen først.")
            return
        end
        e = { kills = 0 }
        db[name] = e
    end
    e.t = math.max(ServerTime(), (e.t or 0) + 1)
    e.by = ns.Me() or "?"
    e.removed = nil
    e.reason = Clean(reason, MAX_REASON)
    if unit then Refresh(e, unit) end
    alerted[name] = GetTime()   -- don't alert me about the one I just added
    Announce(ADD_MSGS, name, e, e.by)
    SendRecord(name, true)
    GuildPost(name, e)
    RefreshVisuals()
end

local function Remove(name)
    local e = name and DB()[name]
    if not e or e.removed then
        ns.Print((name or "?") .. " står ikke på Nordvestlisten.")
        return
    end
    e.t = math.max(ServerTime(), (e.t or 0) + 1)
    e.by = ns.Me() or "?"
    e.removed = true
    Announce(REMOVE_MSGS, name, e, e.by)
    SendRecord(name, true)
    GuildPost(name, e)
    RefreshVisuals()
end

-- Popup asking for a reason; data = { name =, unit = }
if StaticPopupDialogs then
    local function EditBox(self)
        return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
    end
    local function Accept(self, data)
        local box = EditBox(self)
        local reason = box and box:GetText() or ""
        if data and data.name then
            -- the unit may point at someone else by now
            local unit = data.unit and UnitListName(data.unit) == data.name and data.unit or nil
            Add(data.name, reason, unit)
        end
    end
    StaticPopupDialogs["GNISTIFY_NORDVEST"] = {
        text = "Sæt |cffff2020%s|r på Nordvestlisten?\n\nHvorfor? (valgfrit)",
        button1 = "Sæt på listen",
        button2 = "Annuller",
        hasEditBox = true,
        maxLetters = MAX_REASON,
        OnAccept = Accept,
        EditBoxOnEnterPressed = function(box)
            local popup = box:GetParent()
            Accept(popup, popup.data)
            popup:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function AskAdd(name, unit)
    if not name then return end
    if StaticPopup_Show then
        local ok = pcall(StaticPopup_Show, "GNISTIFY_NORDVEST", name, nil, { name = name, unit = unit })
        if ok then return end
    end
    Add(name, "", unit)
end

-- Right-click menus -----------------------------------------------------------
-- Forever has the retail menus: Menu.ModifyMenu adds entries to the player menus
-- (same as Spy/Watch.lua). Guild members and I never get the entry.

local MENUS = { "PLAYER", "TARGET", "FOCUS", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "RAID",
    "FRIEND", "CHAT_ROSTER" }

local function MenuName(contextData)
    if type(contextData) ~= "table" then return nil end
    local unit = Readable(contextData.unit)
    if type(unit) == "string" then return UnitListName(unit), unit end
    local name = Readable(contextData.name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then
        name = ns.Short(name)
    else
        local server = Readable(contextData.server)
        if ns.IS_FOREVER and type(server) == "string" and server ~= "" then name = name .. " " .. server end
    end
    if not name or name == ns.Me() then return nil end
    -- a guild member clicked in chat
    if GetNumGuildMembers then
        for i = 1, (GetNumGuildMembers() or 0) do
            if ns.Short((GetGuildRosterInfo(i))) == name then return nil end
        end
    end
    return name
end

local function AddMenuEntries(owner, description, contextData)
    pcall(function()
        local name, unit = MenuName(contextData)
        if not name then return end
        description:CreateDivider()
        description:CreateTitle("Gnistify")
        if Entry(name) then
            description:CreateButton("Fjern fra Nordvestlisten", function() Remove(name) end)
        else
            description:CreateButton("|cffff2020Sæt på Nordvestlisten|r", function() AskAdd(name, unit) end)
        end
    end)
end

if Menu and Menu.ModifyMenu then
    for _, which in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, AddMenuEntries)
    end
end

-- Kills -----------------------------------------------------------------------
-- Called by Kills.lua for every kill it shows (mine and the guild's). Each online
-- client counts it once; offline ones catch up through the record sync (max wins).
function ns.NordvestKill(victim, killer)
    local e = Entry(victim)
    if not e then return end
    e.kills = (e.kills or 0) + 1
    e.lastKill, e.lastKiller = ServerTime(), killer
    if not GnistifyDB.nordvest then return end
    local text = ns.Fill(ns.Pick(KILL_MSGS), {
        victim = ColoredName(victim, e.class), killer = "|cffff6600" .. (killer or "?") .. "|r",
    })
    DEFAULT_CHAT_FRAME:AddMessage(SKULL_ICON .. " |cffff2020" .. text .. "|r |cffaaaaaa(gnistet "
        .. e.kills .. " gang" .. (e.kills == 1 and "" or "e") .. ")|r")
    if GnistifyDB.nordvestSound and ns.PlayCrownSound and C_Timer then
        C_Timer.After(1.2, function() ns.PlayCrownSound("big") end)   -- after the kill sound
    end
end

-- Receiving -------------------------------------------------------------------

local function OnRecord(sender, msg)
    local _, name, t, by, removed, live, kills, class, level, guild, reason = strsplit(";", msg)
    t, kills, level = tonumber(t), tonumber(kills) or 0, tonumber(level) or 0
    if not name or name == "" or not t then return end
    if name == ns.Me() then return end   -- nobody puts me on my own list
    local db = DB()
    local e = db[name]
    local mineT, mineKills = e and e.t or -1, e and e.kills or 0
    if not e then
        local count = 0
        for _ in pairs(db) do count = count + 1 end
        if count >= MAX_ENTRIES then return end
    end
    if t > mineT then
        local wasOn = e and not e.removed
        e = e or {}
        db[name] = e
        e.t, e.by, e.removed = t, by or "", removed == "1" or nil
        e.reason = Clean(reason, MAX_REASON)
        if class and class ~= "" then e.class = class end
        if level > 0 then e.level = level end
        if guild and guild ~= "" then e.guild = guild end
        e.kills = math.max(mineKills, kills)
        queued[name] = nil
        if live == "1" then
            if e.removed then Announce(REMOVE_MSGS, name, e, by)
            else Announce(ADD_MSGS, name, e, by) end
        elseif not wasOn and not e.removed and GnistifyDB.nordvest then
            ns.Print(SKULL_ICON .. " Ny på Nordvestlisten mens du var væk: " .. Describe(name, e))
        end
        if kills < mineKills then Queue(name) end
        RefreshVisuals()
    elseif t == mineT and kills >= mineKills then
        e.kills = kills
        queued[name] = nil   -- someone sent the same record: no need for mine
    else
        if kills > mineKills then e.kills = kills end
        Queue(name)          -- they have an older one: send ours
    end
end

local function OnSeen(sender, msg)
    local _, name, zone = strsplit(";", msg)
    local e = Entry(name)
    if not e then return end
    local now = GetTime()
    if seenShared[name] and now - seenShared[name] < SEEN_REPEAT then return end
    seenShared[name] = now
    e.seen, e.seenBy, e.seenZone = ServerTime(), sender, zone
    if not GnistifyDB.nordvest then return end
    DEFAULT_CHAT_FRAME:AddMessage(SKULL_ICON .. " |cffff2020[Nordvest]|r |cffff6600" .. sender
        .. "|r har spottet " .. Describe(name, e) .. " i |cffffff00" .. (zone or "?") .. "|r!")
    if GnistifyDB.nordvestSound then PlaySound(SEEN_SOUND, "Master") end
end

-- Login: prune old removals and ask the guild for its list
local function Prune()
    local cutoff = ServerTime() - PRUNE_DAYS * 86400
    local db = DB()
    for name, e in pairs(db) do
        if e.removed and (e.t or 0) < cutoff then db[name] = nil end
    end
end

-- Events ----------------------------------------------------------------------

local requested = false
local ev = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "CHAT_MSG_ADDON" }) do
    pcall(ev.RegisterEvent, ev, event)   -- an unknown event must not break the rest
end

ev:SetScript("OnEvent", function(_, event, ...)
    if not GnistifyDB then return end
    if event == "PLAYER_TARGET_CHANGED" then
        Check("target")
        pcall(UpdateTarget)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Check("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Check("focus")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        Check(unit)
        pcall(UpdatePlate, unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and plate and plateMarks[plate] then plateMarks[plate]:Hide() end
    elseif event == "PLAYER_LOGIN" then
        Prune()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshVisuals()
        if not requested and C_Timer then
            requested = true
            C_Timer.After(REQ_DELAY, function()
                if IsInGuild() then ns.SendAddon("NVREQ") end
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg, sender = Readable(prefix), Readable(msg), ns.Short(Readable(sender))
        if prefix ~= ns.PREFIX or type(msg) ~= "string" or not sender or sender == ns.Me() then return end
        if msg:find("^NV;") then
            OnRecord(sender, msg)
        elseif msg:find("^NVSEEN;") then
            OnSeen(sender, msg)
        elseif msg == "NVREQ" then
            for name in pairs(DB()) do Queue(name) end
        end
    end
end)

-- /gnist nordvest ------------------------------------------------------------

local function List()
    local names = {}
    for name, e in pairs(DB()) do
        if not e.removed then names[#names + 1] = name end
    end
    if #names == 0 then
        ns.Print("Nordvestlisten er tom. Højreklik en fjende og vælg \"Sæt på Nordvestlisten\".")
        return
    end
    table.sort(names, function(a, b) return (DB()[a].t or 0) > (DB()[b].t or 0) end)
    ns.Print(SKULL_ICON .. " |cffff2020Nordvestlisten|r (" .. #names .. "):")
    for _, name in ipairs(names) do
        local e = DB()[name]
        local line = "  " .. Describe(name, e) .. " |cffaaaaaa- " .. (e.by ~= "" and e.by or "?")
            .. ", " .. Ago(e.t) .. " siden"
        if (e.kills or 0) > 0 then line = line .. ", gnistet " .. e.kills .. "x" end
        if e.seen and e.seenZone then
            line = line .. ", sidst set i " .. e.seenZone .. " for " .. Ago(e.seen) .. " siden"
        end
        line = line .. "|r"
        if e.reason and e.reason ~= "" then line = line .. " |cffffd100\"" .. e.reason .. "\"|r" end
        ns.Print(line)
    end
end
ns.NordvestList = List

function ns.NordvestCommand(rest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "vis" or sub == "liste" then
        List()
    elseif sub == "tilføj" or sub == "add" or sub == "+" then
        local unitName = UnitListName("target")
        if unitName then
            -- with a target, the rest is the reason
            if arg ~= "" then Add(unitName, arg, "target") else AskAdd(unitName, "target") end
        elseif arg ~= "" then
            Add(FindName(arg) or Capitalize(Clean(arg, 40)), "")
        else
            ns.Print("Tag en fjende i target, eller skriv navnet: /gnist nordvest tilføj Navn Efternavn")
        end
    elseif sub == "fjern" or sub == "remove" or sub == "-" then
        local name = arg ~= "" and (FindName(arg) or Capitalize(arg)) or UnitListName("target")
        if name then Remove(name) else ns.Print("Hvem? /gnist nordvest fjern Navn Efternavn") end
    else
        ns.Print("Nordvestlisten:")
        ns.Print("  /gnist nordvest            - vis listen")
        ns.Print("  /gnist nordvest tilføj [grund] - sæt dit target på listen")
        ns.Print("  /gnist nordvest tilføj <navn>  - sæt en spiller på listen")
        ns.Print("  /gnist nordvest fjern [navn]   - fjern target eller navn fra listen")
        ns.Print("  Eller: højreklik en spiller -> \"Sæt på Nordvestlisten\"")
    end
end
