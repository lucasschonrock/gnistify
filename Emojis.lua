-- Gnistify emojis: turns :navn: in chat into small pictures.
-- Only people WITH the addon see the pictures; others see the plain text.
-- (Tip: {star}, {skull} etc. are built into WoW and show for EVERYONE.)

-- name -> picture in Gnistify\emojis\ (square .tga, 32x32 or 64x64)
local EMOJIS = {
    gnist = "emojis\\gnist",
}

local ADDON_DIR = "Interface\\AddOns\\Gnistify\\"

local function Texture(path)
    if not path:find("^Interface\\") then path = ADDON_DIR .. path end
    return "|T" .. path .. ":0|t"   -- 0 = same height as the chat text
end

local function Replace(msg)
    if not msg or not msg:find(":", 1, true) then return msg end
    -- Don't touch item/spell links (they contain colons): only swap
    -- :word: that is not inside a |H...|h link.
    local out, pos = {}, 1
    while true do
        local s, e = msg:find("|H.-|h.-|h", pos)
        local plain = msg:sub(pos, (s or 0) - 1)
        if not s then plain = msg:sub(pos) end
        plain = plain:gsub(":(%w+):", function(name)
            local path = EMOJIS[name:lower()]
            return path and Texture(path) or nil
        end)
        out[#out + 1] = plain
        if not s then break end
        out[#out + 1] = msg:sub(s, e)
        pos = e + 1
    end
    return table.concat(out)
end

local function Filter(_, _, msg, ...)
    if GnistifyDB and GnistifyDB.emojis == false then return false end
    local new = Replace(msg)
    if new ~= msg then return false, new, ... end
    return false
end

for _, event in ipairs({
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
}) do
    ChatFrame_AddMessageEventFilter(event, Filter)
end

-- Used by "/gnist emojis"
function Gnistify_ListEmojis()
    local names = {}
    for name in pairs(EMOJIS) do names[#names + 1] = name end
    table.sort(names)
    local line = {}
    for _, name in ipairs(names) do
        line[#line + 1] = Texture(EMOJIS[name]) .. " :" .. name .. ":"
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[Gnist]|r Emojis: " .. table.concat(line, "  "))
end
