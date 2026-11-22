-- Gnistify loot: when a Gnisterne member loots an EPIC (purple) or LEGENDARY
-- (orange) item, every guildie with the addon sees (in their own chat window,
-- not guild chat), like PvP kills:
--   <gnist> Bo Hansen har fået fingrene i [Thunderfury]! Misundelse i guilden: 100%
--
-- Only the client of the looter announces it. Everyone else just listens, and
-- ignores their own echo.
--
-- Detected from "You receive loot: [Item]." (CHAT_MSG_LOOT, built from the
-- LOOT_ITEM_SELF and LOOT_ITEM_SELF_MULTIPLE globals). Crafted items ("You
-- create: ...") have their own message and are never matched. Items bought from
-- vendors and quest rewards both use "You receive item: ..." (LOOT_ITEM_PUSHED_SELF),
-- which can't be told apart, so that message is ignored on purpose.
--
-- Message on the GnistDing prefix (older versions ignore it, because they only
-- match ^DING:, ^KILL; and so on). Only ever append fields at the end.
--   LOOT;itemLink;quality;itemID   itemLink is empty if it would make the
--                                  message too long; then the ID is used.

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local EPIC = 4
local LEGENDARY = 5
local MAX_MSG = 250   -- addon messages may be 255 bytes; keep a little margin
-- The game's own epic / legendary loot toast sounds, with numeric fallbacks
local EPIC_SOUND = (SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST) or 31578
local LEGENDARY_SOUND = (SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST) or EPIC_SOUND

-- Item colours by quality, for building a link from an ID and spotting quality
-- from a link's colour code (old "|cffa335ee" style)
local QUALITY_COLORS = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}

-- {name}, {item}
local LOOT_MSGS = {
    "Gnisten lyser lilla! {name} har fået fingrene i {item}!",
    "{item} faldt til {name}. Misundelse i guilden: 100%",
    "{name} fandt {item}. Resten af os har bare lyst.",
    "Hold da op! {name} lootede {item}!",
    "Drop-heldet smiler til {name}: {item}!",
    "{name} slog rod i loot-tabellen og fik {item}!",
    "Lilla gnister over {name}! {item} er landet i tasken.",
    "{name} har fået {item}. Vi er stolte. Og lidt misundelige.",
    "Rul for dem alle: {name} løb med {item}!",
    "{item}! {name} fik virkelig held i dag. Længe leve gnisten!",
}
local LOOT_BANNERS = {
    "{name} fik {item}!",
    "Lilla loot til {name}: {item}!",
    "{item} faldt til {name}!",
    "{name} lootede {item}!",
}
-- Quality 5 gets extra enthusiasm
local LEGENDARY_MSGS = {
    "ORANGE GNISTER! {name} har fået {item}! LEGENDARISK! Længe leve gnisten!",
    "Alle mand på dæk! {name} har lootet {item}! Det er LEGENDARISK!",
    "{name} har fået {item}!!! Hele guilden bukker sig i støvet!",
    "Historiske tider: {item} tilhører nu {name}! Orange gnister over hele guilden!",
    "Det her sker ikke. {name} har {item}! LEGENDARISK!",
}
local LEGENDARY_BANNERS = {
    "LEGENDARISK! {name} fik {item}!",
    "{name} har lootet {item}!!!",
    "ORANGE GNISTER! {item} til {name}!",
}

-- Parsing ------------------------------------------------------------------

-- "You receive loot: %s." -> a Lua pattern with captures for %s (and %d)
local function PatternFrom(format)
    if type(format) ~= "string" then return nil end
    -- Escape the magic characters except "%", then turn %s and %d into captures
    local p = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local SELF_MULTIPLE = PatternFrom(LOOT_ITEM_SELF_MULTIPLE)   -- tried first: ends in "x%d"
local SELF = PatternFrom(LOOT_ITEM_SELF)

-- The item link in a "You receive loot" message, or nil for anything else
-- (other people's loot, crafted items, "You receive item: ...").
local function ParseLootMessage(msg)
    if type(msg) ~= "string" then return nil end
    local text, count
    if SELF_MULTIPLE then text, count = msg:match(SELF_MULTIPLE) end
    if not text and SELF then text = msg:match(SELF) end
    if not text then return nil end
    local link = text:match("|c%x+|Hitem:[^|]+|h%[.-%]|h|r")
        or text:match("|cn[%w_:]+:|Hitem:[^|]+|h%[.-%]|h|r")
    if not link then return nil end
    return link, tonumber(count) or 1
end

local function ItemID(link)
    return tonumber(link and link:match("|Hitem:(%d+)"))
end

-- Quality 0-7 for an item link: the game's item info if it's cached, else the
-- link's colour (so an uncached item still works).
local function QualityOf(link)
    if type(link) ~= "string" then return nil end
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, link)
        q = ok and Readable(q)
        if type(q) == "number" then return q end
    end
    if GetItemInfo then
        local ok, q = pcall(function() return (select(3, GetItemInfo(link))) end)
        q = ok and Readable(q)
        if type(q) == "number" then return q end
    end
    local n = link:match("|cnIQ(%d):")
    if n then return tonumber(n) end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    if hex then
        hex = hex:lower()
        for q, c in pairs(QUALITY_COLORS) do
            if c == hex then return q end
        end
    end
    return nil
end

-- Show ---------------------------------------------------------------------

local function Looter(name) return "|cffff6600" .. name .. "|r" end

-- A link from an item ID, for the rare message that was too long for the link
local function LinkFromID(id, quality)
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getter then
        local ok, _, link = pcall(getter, id)
        link = ok and Readable(link)
        if type(link) == "string" then return link end
    end
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[EPIC]
    return "|cff" .. color .. "|Hitem:" .. id .. "|h[Item " .. id .. "]|h|r"
end

local function Show(name, link, quality)
    if not GnistifyDB or not GnistifyDB.loot then return end
    local legendary = quality >= LEGENDARY
    local vars = { name = Looter(name), item = link }
    DEFAULT_CHAT_FRAME:AddMessage(GNIST_ICON .. " "
        .. ns.Fill(ns.Pick(legendary and LEGENDARY_MSGS or LOOT_MSGS), vars))
    if GnistifyDB.lootBanner and RaidNotice_AddMessage and RaidWarningFrame then
        local banner = ns.Fill(ns.Pick(legendary and LEGENDARY_BANNERS or LOOT_BANNERS), vars)
        RaidNotice_AddMessage(RaidWarningFrame, GNIST_ICON .. " " .. banner, ChatTypeInfo["GUILD"])
    end
    if GnistifyDB.lootSound then
        PlaySound(legendary and LEGENDARY_SOUND or EPIC_SOUND, "Master")
    end
end

-- My own loot ----------------------------------------------------------------

local function OnMyLoot(msg)
    local link = ParseLootMessage(msg)
    if not link then return end
    local quality = QualityOf(link)
    if type(quality) ~= "number" or quality < EPIC then return end
    local me = ns.Me()
    if not me then return end
    Show(me, link, quality)
    if IsInGuild() and GnistifyDB.lootSend then
        local id = ItemID(link)
        local out = "LOOT;" .. link .. ";" .. quality .. ";" .. (id or "")
        -- A very long link would push the message over the limit: send just the ID
        if #out > MAX_MSG and id then out = "LOOT;;" .. quality .. ";" .. id end
        if #out <= MAX_MSG then ns.SendAddon(out) end
    end
end

-- Events -----------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_ADDON" }) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        OnMyLoot(Readable((...)))

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg = Readable(prefix), Readable(msg)
        if prefix ~= PREFIX or type(msg) ~= "string" or not msg:find("^LOOT;") then return end
        local looter = ns.Short(sender)
        if not looter or looter == ns.Me() then return end   -- already shown
        -- ";" never appears in item links
        local _, link, quality, id = strsplit(";", msg)
        id = tonumber(id) or ItemID(link)
        quality = tonumber(quality) or QualityOf(link)
        if type(quality) ~= "number" or quality < EPIC then return end
        if not link or link == "" then
            if not id then return end
            link = LinkFromID(id, quality)
        end
        Show(looter, link, quality)
    end
end)

-- For testing outside the game
ns.ParseLootMessage, ns.LootQuality = ParseLootMessage, QualityOf
