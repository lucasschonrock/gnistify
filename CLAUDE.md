# Gnistify

A for-fun World of Warcraft addon for the guild **Gnisterne** (a group of friends).
When a guild member levels up ("dings"), every Gnistify user hears the level-up sound
and sees a celebration message in Danish. Players can also type `:gnist:` in chat to
show a small spark picture.

All text the players see is in **Danish**. Keep it that way.

## Client / environment

- Server: **WoW Forever** (a private server). The install is at
  `/Applications/World of Warcraft/_forever_/`, and addons live in `Interface/AddOns/`.
- The source lives in the git repo `~/Documents/GitHub/gnistify`. In-game it must sit
  at `Interface/AddOns/Gnistify` (capital G). File paths in the code, such as
  `Interface\AddOns\Gnistify\sound.mp3`, depend on that folder name.
- **Forever runs the modern retail client (interface 16001) on the Vanilla world.** The
  `.toc` lists `## Interface: 16001, 11509`, the same as the other Forever addons in this
  install. This has two big consequences:
  - **The combat log is closed to addons.** Registering `COMBAT_LOG_EVENT_UNFILTERED`
    is a forbidden action and shows the "Gnistify has been blocked from an action only
    available to the Blizzard UI" popup at every login. Never use it or
    `CombatLogGetCurrentEventInfo`. Use the `PARTY_KILL` event and unit tokens instead.
  - **Values can be secret.** The API can return opaque values that addon code may not
    compare, concatenate or use as table keys. Pass every API value through
    `ns.Readable` (in `Gnistify.lua`), which turns a secret into nil.
  - **Names have a surname and there are no realms** ("Torden Tim"). The client puts the
    surname where other versions put the realm: `UnitName` returns `first, surname`,
    `GetPlayerInfoByGUID` returns it as the realm, and chat/roster/addon senders are
    `"First-Surname"`. Always use `ns.FullName(unit)`, `ns.Me()` and `ns.Short(name)`,
    which turn these into `"First Surname"`. Never use `Ambiguate`, which would cut
    the surname off.
  - `Spy/Forever.lua` in the AddOns folder is a good reference for what works on Forever.
- APIs used: `C_GuildInfo.GuildRoster`, `C_ChatInfo.SendAddonMessage`,
  `C_ChatInfo.SendChatMessage`, `C_Timer`, `Ambiguate`, `UnitIsInMyGuild`,
  `ChatFrameUtil.AddMessageEventFilter`. The code falls back to the older global
  functions where it's cheap to do so, and registers events with `pcall`.
- `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` aimed at Gnistify are saved in
  `GnistifyDB.lastBlocked` (read it from `WTF/Account/*/SavedVariables/Gnistify.lua`
  after the user logs out or reloads).
- **Nothing can be tested from here.** There is no game client and no `luac` on the
  machine. Review changes by eye and tell the user to test them in-game.

## Files

| File | Purpose |
|---|---|
| `Gnistify.toc` | Addon manifest. The file name **must** match the folder name. Lists `SavedVariables: GnistifyDB`. |
| `Gnistify.lua` | Ding detection, celebration, guild chat post, `/gnist` slash command. |
| `Emojis.lua` | Chat filter that turns `:gnist:` into a picture. |
| `Options.lua` | Settings window (`/gnist`) with one checkbox per feature. The same checkboxes are added to the game's Options → AddOns list (`Settings.RegisterCanvasLayoutCategory`, or `InterfaceOptions_AddCategory` as a fallback). To add a setting: give it a default in `ADDON_LOADED` in `Gnistify.lua` and add an entry to `OPTIONS`. |
| `Kills.lua` | PvP killing-blow announcements (see below). Shares `ns.PREFIX`, `ns.Short` and `ns.Print` from `Gnistify.lua` through the addon namespace. |
| `sound.mp3` | The user's own ~1 sec sound, played via `PlaySoundFile` whenever a guild kill is shown (setting `killSound`). |
| `emojis/gnist.tga` | 64×64 32-bit uncompressed TGA spark (yellow/orange, drawn with a small Python script). |

## How ding detection works (`Gnistify.lua`)

All paths call `Celebrate(name, level)`. It keeps track of which levels it has already
celebrated (the `announced` table), so the same ding never shows twice.

1. **Players with the addon.** On `PLAYER_LEVEL_UP`, the levelling player:
   - sends `DING:<level>` on the hidden addon channel to `GUILD`, using prefix
     **`GnistDing`**;
   - posts one message to guild chat, if `GnistifyDB.guildChat` is on:
     `{star} DING! <Navn> er dinget level <X>! Længe leve gnisten! {star}`.
     `{star}` is WoW's built-in raid icon, so everyone sees it.

   Other clients get `CHAT_MSG_ADDON` and celebrate straight away.
2. **Guildies without the addon:**
   - `UNIT_LEVEL` catches party and raid members, the target and the mouseover
     instantly, if `UnitIsInMyGuild`.
   - The guild roster is fetched every 10 sec (`ROSTER_POLL`). The game throttles
     fetches to about 10 sec, so polling faster doesn't help.
   - Any `CHAT_MSG_GUILD` message triggers an immediate roster fetch, since people
     often type "ding".
   - `GUILD_ROSTER_UPDATE` with `canRequestRosterUpdate` set also triggers a fetch.
   - `ScanRoster` compares levels with the `knownLevels` table. The first scan after
     login only records levels and doesn't celebrate anything.
   - For 20 sec after every loading screen (`PLAYER_ENTERING_WORLD`: login, `/reload`,
     zoning) roster and `UNIT_LEVEL` changes are only recorded, not celebrated, and a
     jump of more than 2 levels is never celebrated. The roster arrives in pieces or
     with stale levels then, which used to cause false dings at login. `DING:`
     messages from addon users are always trusted.

The celebration plays sound `888` (the LEVELUP sound) unless the levelling player is
you, because the game already plays it for you. It also prints a coloured line in the
chat frame and shows a raid-warning style banner.

**Never change the addon prefix `GnistDing`.** Friends running older versions
(previously called GnistDingdong) depend on it.

## PvP kills (`Kills.lua`)

Gnisterne is a PvP guild. When a member gets the **killing blow** on an enemy player,
every Gnistify user sees this in their own chat window (not guild chat):
`<gnist icon> Killer gnistede Offer (lvl 34 Magiker) til døde i Zone!`
The victim's name is shown in their class colour.

- **Who announces:** only the client of the player who landed the killing blow. This
  stops duplicates when several guildies are grouped together. Detection uses the
  `PARTY_KILL` event (`attackerGUID, targetGUID`), where the attacker is the player or
  their pet and the victim's GUID starts with `Player-`.
- **What is sent:** the killer's client shows the line locally and sends
  `KILL;victim;level;classFile;zone` on the `GnistDing` prefix to `GUILD`. Receivers
  ignore their own echo.
- **Victim name, class and level:** `PARTY_KILL` only gives GUIDs. Name, class and
  level are cached per GUID from the target, mouseover, focus, nameplates and
  `UNIT_LEVEL`, so they're still known after the nameplate disappears.
  `GetPlayerInfoByGUID` is the fallback for name and class. Unknown is shown as `?`, and a skull-level player as `??`.
- **Class name:** comes from the client's `LOCALIZED_CLASS_NAMES_MALE`.
- **Toggles:** `kills` turns off *showing* kills, and `killsSend` stops sending your
  own kills to the guild.
- **Compatibility:** older versions ignore `KILL;` messages, because they only match
  `^DING:`.

## Settings and commands

Settings are stored in the `GnistifyDB` saved variable, and all of them default to on:
`dings` (show guild dings at all), `sound`, `banner`, `guildChat`, `kills` (show the
guild's kills), `killSound` (play `sound.mp3` on a kill), `killsSend` (send my own kills to the guild), `emojis`.

| Command | Effect |
|---|---|
| `/gnist` or `/gnistify` | Open the settings window |
| `/gnist hjælp` | Show the command list |
| `/gnist lyd` | Toggle the sound |
| `/gnist guild` | Toggle the guild chat post when you ding |
| `/gnist banner` | Toggle the banner in the middle of the screen |
| `/gnist drab` | Toggle showing the guild's PvP kills in chat |
| `/gnist emojis` | List the available emojis |

## Emojis (`Emojis.lua`)

- `EMOJIS` maps a name to a texture path. Paths are relative to
  `Interface\AddOns\Gnistify\` unless they start with `Interface\`.
- The filter runs on guild, officer, party, raid, say, yell, emote, whisper and channel
  messages. It skips `|H...|h` item and spell links.
- Only addon users see the pictures. Everyone else sees the plain text `:gnist:`.
- WoW chat can't show animated pictures, so GIFs aren't possible.
- A new texture file needs a full game restart. `/reload` is not enough.

## Decisions the user has made

- Only the `:gnist:` emoji. A larger set of built-in icons was removed on purpose.
- The message wording is "er dinget level X! Længe leve gnisten!". Earlier versions
  used "opsteget ... i Gnisthood" and then "i Gnistskab", and the user rejected both.
- The test commands (`/gnist test` and the secret `/dingdong test`) were removed on
  request. Don't add them back unless the user asks.
- Dings should be detected as close to real time as possible.
- The addon is shared with friends as a zip of the `Gnistify` folder.

## After every addon change: sync to WoW (do this automatically)

The user wants this to happen without being asked. After **any** change to the addon's
files (`.lua`, `.toc`, `sound.mp3`, `emojis/`), run this command to copy the repo into
the game's AddOns folder:

```bash
rsync -a --delete --exclude '.git' --exclude '.github' --exclude '.DS_Store' --exclude '.gitignore' --exclude '.pkgmeta' --exclude 'CLAUDE.md' --exclude 'README.md' --exclude 'art' ~/Documents/GitHub/gnistify/ "/Applications/World of Warcraft/_forever_/Interface/AddOns/Gnistify/"
```

Then tell the user what they need to do in-game. Lua and `.toc` changes need
`/reload`. New or renamed files (sounds, textures, new `.lua` files) need a full restart
of WoW.

## Releases (CurseForge and GitHub)

- **Every push to `main` is a release.** `.github/workflows/release.yml` bumps the patch
  version (for example `v1.0.3` → `v1.0.4`), creates and pushes the tag, then runs the
  BigWigs packager to build the zip and upload it to CurseForge and GitHub Releases.
  - Pushing a tag yourself, such as `v1.1.0`, releases that version instead. Use this for
    minor or major version bumps.
  - Pushes that only change `README.md`, `CLAUDE.md`, `art/`, `.github/` or
    `.gitignore` don't release.
  - `[skip ci]` in a commit message skips the release on purpose.
  - So **pushing to `main` publishes to CurseForge.** Only push when the user asks.
- `.pkgmeta` packages the addon as the folder `Gnistify` (capital G) and leaves out
  `CLAUDE.md` and `README.md`. Dotfiles are left out automatically.
- `## Version: @project-version@` in the `.toc` is replaced with the tag name.
- The CurseForge upload needs three things:
  - the repo secret `CF_API_KEY`;
  - `## X-Curse-Project-ID: <id>` in `Gnistify.toc`;
  - optionally, the repo variable `CF_GAME_VERSION`, which defaults to `1.60.1` (the game version CurseForge lists for WoW Forever). It's
    needed because CurseForge doesn't know WoW Forever's interface number `16001`.
- `sound.mp3` is the user's own file. CurseForge requires that the uploader owns, or has
  permission to use, every file.
- `README.md` is in Danish and written for players.

## Gotchas

- WoW only loads an addon whose `.toc` file name matches its folder name.
- Renaming a `SavedVariables` name resets the user's settings.
- Strings are UTF-8. Danish letters (æ, ø, å) display fine.
- `SendChatMessage(..., "GUILD")` is allowed outside a key press. Only SAY, YELL and
  CHANNEL are restricted.
