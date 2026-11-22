-- Gnistify BG queue together: a synced countdown, so several group leaders in
-- the guild can press "Join Battle" at the same second and land in the same BG
-- (BG groups are capped at 5).
--
-- The addon can NOT queue for anyone: JoinBattlefield is protected and needs a
-- real click. So this only counts down; each leader clicks the button
-- themselves at "KØ NU!". The PvP frame is not opened for them, because the
-- addon can't be sure that is safe on Forever.
--
-- Message on the GnistDing prefix to GUILD (older versions ignore it, because
-- they only match ^DING:, ^KILL; and so on). Only ever append fields at the end.
--   BGQ;endTime    endTime = GetServerTime() when the countdown reaches "KØ NU!"
-- The end time is a server time, so every client ends at the same second no
-- matter how late the message arrives.

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local COUNTDOWN = 5          -- seconds from /gnist kø until "KØ NU!"
local MAX_AHEAD = 30         -- an end time further away than this is not ours
local RATE_LIMIT = 15        -- seconds between starts from the same sender
local HOLD = 2.5             -- seconds "KØ NU!" stays on screen

local TICK_SOUND = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856
local GO_SOUND = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960

local ending = nil           -- server time the running countdown ends, or nil
local lastShown = nil        -- last number shown, so a tick sounds once per second
local lastStart = {}         -- sender -> GetTime() of their last accepted start
local ticker

local frame = CreateFrame("Frame", "GnistifyBGQueueFrame", UIParent)
frame:SetSize(400, 140)
frame:SetPoint("CENTER", 0, 120)
frame:SetFrameStrata("HIGH")
frame:Hide()

local who = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
who:SetPoint("TOP", 0, 0)
local number = frame:CreateFontString(nil, "OVERLAY")
number:SetFont(STANDARD_TEXT_FONT, 96, "THICKOUTLINE")
number:SetPoint("TOP", who, "BOTTOM", 0, -4)

-- Only a leader or someone without a group can queue the group.
local function CanQueue()
    if not IsInGroup() then return true end
    return Readable(UnitIsGroupLeader("player")) == true
end

local function Stop()
    ending, lastShown = nil, nil
    if ticker then ticker:Cancel(); ticker = nil end
    frame:Hide()
end

local function Update()
    if not ending then return end
    local left = ending - (Readable(GetServerTime()) or ending)
    if left > 0 then
        if left ~= lastShown then
            lastShown = left
            number:SetText("|cffffcc00" .. left .. "…|r")
            PlaySound(TICK_SOUND, "Master")
        end
    elseif lastShown ~= 0 then
        lastShown = 0
        number:SetText("|cff00ff00KØ NU!|r")
        PlaySound(GO_SOUND, "Master")
        ending = nil
        if ticker then ticker:Cancel(); ticker = nil end
        C_Timer.After(HOLD, function()
            if not ending then frame:Hide() end
        end)
    end
end

local function Begin(sender, endTime)
    Stop()
    ending = endTime
    who:SetText(sender .. " starter BG-kø")
    number:SetText("")
    frame:Show()
    ticker = C_Timer.NewTicker(0.1, Update)
    Update()
end

local function OnStart(sender, endTime)
    if not GnistifyDB.bgQueue then return end
    local now = Readable(GetServerTime())
    if type(now) ~= "number" or endTime <= now or endTime - now > MAX_AHEAD then
        return    -- stale, or nonsense
    end
    local t = GetTime()
    if lastStart[sender] and t - lastStart[sender] < RATE_LIMIT then return end
    lastStart[sender] = t

    ns.Print(sender .. " starter BG-kø om " .. (endTime - now) .. " sekunder.")
    if CanQueue() then
        Begin(sender, endTime)
    end
end

-- /gnist kø
function ns.BGQueueCommand()
    if not IsInGuild() then
        ns.Print("Du er ikke i en guild.")
        return
    end
    local now = Readable(GetServerTime())
    if type(now) ~= "number" then return end
    local me = ns.Me() or "?"
    if lastStart[me] and GetTime() - lastStart[me] < RATE_LIMIT then
        ns.Print("Vent lidt, før du starter en ny BG-kø.")
        return
    end
    ns.SendAddon("BGQ;" .. (now + COUNTDOWN))   -- we get our own copy back and show it then
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    prefix, msg = Readable(prefix), Readable(msg)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    local endTime = tonumber(msg:match("^BGQ;(%d+)"))
    local name = ns.Short(sender)
    if endTime and name then OnStart(name, endTime) end
end)
