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
| `Options.lua` | Settings UI (`/gnist`, minimap right click). Native: a "Gnistify" category in Options → AddOns with one subcategory per `{ header = ... }` in `OPTIONS` (see "Settings UI" below). Fallback for clients without the vertical-layout Settings API: the old hand-made window and canvas panel. |
| `Kills.lua` | PvP killing-blow announcements (see below). Shares `ns.PREFIX`, `ns.Short` and `ns.Print` from `Gnistify.lua` through the addon namespace. |
| `Leaderboard.lua` | World PvP leaderboard ("PvP-tavle") and its sync (see below). |
| `Duels.lua` | Guild-vs-guild duel detection, chat comments and `DUEL;` sync; the totals live in the PvP leaderboard (see below). |
| `Minimap.lua` | Minimap button with the emblem `icon.tga`. Registers through LibDataBroker + LibDBIcon when another addon (Leatrix Plus, TomTom, AtlasLoot ...) has loaded them, so Leatrix' button collector shows our tooltip instead of "This is a custom button"; position then in `GnistifyDB.minimapLDB`. Gnistify does not ship the libs; without them it builds its own button. Both share `FillTooltip`/`HandleClick`: left click PvP-tavle, right click settings, shift-click or middle click toggles `tracking`, drag to move (`GnistifyDB.minimapAngle`). Tooltip lists title holders (`ns.TitleHolders`). Setting `minimapIcon`. |
| `Elite.lua` | The classic elite dragon around PvP leaders' portraits (player, party, target frames): gold elite for Gnistkejseren (the user wants the emperor to look strongest), silver winged rare-elite for #1 this month, silver rare for #1 today/week (`ns.EliteKind`). Rare-elite falls back to gold if the client lacks it. Texture coords and placement copied from Leatrix Plus' player chain. Setting `eliteFrames`. |
| `Fishing.lua` | Fishing catches, fishing skill dings, fish today and the louder splash (see below). |
| `Streaks.lua` | Login streaks (see below). |
| `Professions.lua` | Shares my professions and skill levels with the guild and answers `/gnist prof` (see below). |
| `Loot.lua` | Epic and legendary loot shout-out (see below). |
| `Caller.lua` | Battleground shot caller ("leder") and the assist button (see below). |
| `Zones.lua` | Zone presence: one chat line with the online guildies in the zone you just entered (see below). Setting `zonePresence`. |
| `Nordvest.lua` | Nordvestlisten, the guild's kill-on-sight list (see below). |
| `Tracking.lua` | Automatic tracking switch (herbs / minerals / humanoids) every 5 sec (see below). |
| `Bindings.xml` | Key bindings "Mål lederens mål" (`CLICK GnistAssistButton:LeftButton`) and "Skift sporing til/fra" (`GNISTIFY_TRACKING`, calls `Gnistify_ToggleTracking`). Loaded by the client from the addon folder; **not** listed in the `.toc`. |
| `dexter.mp3`, `fire.mp3` | Title sounds for the PvP leaderboard (quieter copies; originals in `art/sounds/`). |
| `sound.mp3` | The user's own ~1 sec sound, played via `PlaySoundFile` whenever a guild kill is shown (setting `killSound`). |
| `emojis/gnist.tga` | 64×64 32-bit uncompressed TGA spark (yellow/orange, drawn with a small Python script). |
| `icon.tga` | 128×128 32-bit uncompressed TGA of the round emblem (source `art/emblem.webp`). Used for the minimap button (`SetTexCoord` trims the spike tips), `## IconTexture` in the `.toc` (addon list) and the settings window titles. Chat lines (kills, duels, leaderboard, `:gnist:`) keep the small spark, since the emblem is mush at font size. Rebuild with `magick art/emblem.webp -filter Lanczos -resize 128x128 -unsharp 0x0.6 -define tga:image-origin=TopLeft -type TrueColorAlpha -depth 8 -compress None icon.tga`. |

## How ding detection works (`Gnistify.lua`)

All paths call `Celebrate(name, level)`. It keeps track of which levels it has already
celebrated (the `announced` table), so the same ding never shows twice.

1. **Players with the addon.** On `PLAYER_LEVEL_UP`, the levelling player:
   - sends `DING:<level>` on the hidden addon channel to `GUILD`, using prefix
     **`GnistDing`**;
   - posts one message to guild chat, if `GnistifyDB.guildChat` is on:
     `{star} <random DING_MSGS line> {star}`.
     `{star}` is WoW's built-in raid icon, so everyone sees it.
   - The wording is picked at random from `DING_MSGS` (placeholders `{name}`,
     `{level}`), so each client may show a different variant. The chat line and the
     banner on one client use the same variant. `ns.Pick` and `ns.Fill` do this.

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
`<gnist icon> Killer (med Anna og Bo) gnistede Offer (lvl 34 Magiker) til døde i Zone! (dagens drab nr. 3)`
The wording is picked at random from `KILL_MSGS` (placeholders `{killer}`, `{victim}`,
`{zone}`). The victim's name is shown in their class colour. The killer also sees the
line and hears the sound on their own screen. The banner (setting `killBanner`) uses a short line
from `KILL_BANNERS` instead (killer and victim only), because the full line is too long
for the middle of the screen.

- **Who announces:** only the client of the player who landed the killing blow. This
  stops duplicates when several guildies are grouped together. Detection uses the
  `PARTY_KILL` event (`attackerGUID, targetGUID`), where the attacker is the player or
  their pet and the victim's GUID starts with `Player-`.
- **Pet kills:** the game may not send `PARTY_KILL` when a pet lands the killing blow.
  So the pet's enemy-player target is noted (`UNIT_TARGET` for `pet`, plus a 1 sec
  ticker). When that player dies (`UNIT_DIED`) within 4 sec of being the pet's target,
  and no `PARTY_KILL` (any attacker) or guildie's `KILL;` message names him within
  3 sec, it's announced as my kill after 1.5 sec. Not in battlegrounds or arenas, where
  `PARTY_KILL` is secret. `announcedAt` stops a late `PARTY_KILL` announcing it twice.
  Same idea as `Spy/PetKills.lua`.
- **What is sent:** the killer's client shows the line locally and sends
  `KILL;victim;level;classFile;zone;count;assists` on the `GnistDing` prefix to
  `GUILD`. Receivers ignore their own echo. Fields 6 and 7 were added later; older
  versions only read the first five. Only ever append new fields at the end.
- **Kills today:** `count` is the killer's kills today, kept per character in
  `GnistifyDB.killCount[name] = { day = "YYYY-MM-DD", n = N }`.
- **Helpers (who really helped):** Forever has the game's own damage meter
  (`C_DamageMeter`, the source Details and Light Damage use). It's secret in combat and
  readable after. Its `EnemyDamageTaken` list has one source per enemy (by GUID);
  `GetCombatSessionSourceFromType/FromID` for that enemy gives one `combatSpells` entry
  per group member who hit him (`totalAmount`, `combatSpellDetails.unitName`).
  `HealingDone` lists the healers of the fight; the source view per healer gives
  their `combatSpells` with the healed targets in `combatSpellDetails.unitName`
  (`HealedDamager`). Healing only counts when it landed on someone else (not the
  healer, not a pet) who damaged the victim, so potions, bandages, Mend Pet and
  healing in another fight give no credit. If that breakdown can't be read, healing
  gives no credit. The healer must also be near the killer (`IsNear`:
  `UnitInRange`, or `UnitIsVisible`). The fight's `sessionID` (public in combat) is noted at the kill and
  read after `PLAYER_REGEN_ENABLED` (up to 5 tries, 1 sec apart).
  - **Credit is self-decided:** `PARTY_KILL` reaches every group member, whoever made
    the kill (even without Gnistify). For a group member's kill, my client reads my own
    meter after combat and calls `ns.LeaderboardKill()` if I damaged the victim, or
    healed someone who damaged the victim while near the killer (`QueueMyHelp` / `CreditMe`).
  - **Display:** the killer's client sends `HELP;victim;classFile;Name:d,Name:dh,...,+N`
    (d damage, h heal, n nearby only when the meter had nothing) and every client
    shows "Hjalp til med drabet på X: ...". `HELP` gives no credit (1.0.16 and older
    credited from it; this way nothing counts twice).
- **Kill log:** the last 50 kill events, newest first, in `GnistifyDB.killLog`
  (`kind` = `mine`, `mine-helpers`, `group-kill` with `damaged`/`healed`/`nearKiller`/
  `credited`, `guild-kill`, `help-msg`, `reset`). Read it from SavedVariables when a
  kill was credited wrong. `GnistifyDB.sendFailures` counts addon messages the game
  refused to send (throttling), with the last one.
- **Assists field:** `assists` in `KILL;` is now empty when the meter will send
  `HELP` later. Without the meter it's still the "nearby" list (`UnitInRange`, or
  `UnitIsVisible`), at most 4 names plus `+N`, shown as "(med Anna og Bo)".
- **Victim name, class and level:** `PARTY_KILL` only gives GUIDs. Name, class and
  level are cached per GUID from the target, mouseover, focus, nameplates and
  `UNIT_LEVEL`, so they're still known after the nameplate disappears.
  `GetPlayerInfoByGUID` is the fallback for name and class. Unknown is shown as `?`, and a skull-level player as `??`.
- **Class name:** comes from the client's `LOCALIZED_CLASS_NAMES_MALE`.
- **Toggles:** `kills` turns off *showing* kills, and `killsSend` stops sending your
  own kills to the guild.
- **Compatibility:** older versions ignore `KILL;` messages, because they only match
  `^DING:`.

## PvP leaderboard (`Leaderboard.lua`)

Ranks guild members by world PvP kills today, this week (from Monday), this
month and of all time. A kill is a killing blow or helping with one (see Helpers
above). Kills in battlegrounds and arenas (`IsInInstance` type `pvp`, `arena`) don't
count. `Kills.lua` calls `ns.LeaderboardKill()` after showing my kill, and when my
own damage meter shows I helped with a group member's kill.

- **Titles** (the user wants these to feel like an honour): #1 today "Dagens
  Gnistsprutter", week "Ugens Brandfakkel", month "Månedens Bålkonge", all time
  "Gnistkejseren", #2/#3 all time "Gnistprinsen"/"Gnistridderen". Ties share a title.
  `ns.LeaderTitle(name)` gives the best one; the kill line shows it as `[title]` after
  the killer. When a live kill makes someone the sole #1, "Ny leder på PvP-tavlen!" plus
  a line from `CROWN_MSGS` is shown (and a banner for a new Gnistkejser).
- **Title sounds** (setting `crownSound`): one sound per kill, `fire.mp3` if the kill won
  month or all time, else `dexter.mp3`. Played on the `SFX` channel after `sound.mp3`
  has finished (`ns.lastKillSound`). While one is playing, a new one is skipped unless
  it's fire cutting off dexter (`StopSound`). The files are lowered to about -24 LUFS
  with ffmpeg; the originals are in `art/sounds/`. Re-lower any replacement the same way.
- **Data:** `GnistifyDB.pvpBoard[name] = { total, days = { [dayNumber] = n } }`, a copy
  of everyone's record. Day number = local noon `time()` / 86400. Days older than 40
  are pruned at login; `total` stays.
- **Sync** on `GnistDing` to `GUILD`: `LB;name;total;start;c1,c2,...;live` (counts from
  day `start` to the sender's today, empty = 0; `live` = 1 right after the kill) and
  `LBREQ` (15 sec after login). `total` is the version: higher always wins, even for
  my own record (restores it after a reinstall). On `LBREQ` everyone queues all
  records; a queued record is dropped when someone else sends the same or newer one,
  and hearing an older record queues ours as a correction. The queue sends one record
  per 1.1 sec. My own record isn't sent if `killsSend` is off.
- **Reset by vote:** `/gnist reset` sends `LBVOTE;epoch;name`; everyone online gets a
  `StaticPopup` (`GNISTIFY_RESET`) and answers with `LBYES;epoch` (or `/gnist ja`). At
  `RESET_VOTES` (4, the asker counts) yes within `VOTE_TIME` (90 sec) every client wipes
  `pvpBoard` and `killCount` and stores `GnistifyDB.boardEpoch` = the vote's server time.
  Every `LB;` record carries the epoch as its last field (missing = 0). A record from an
  older epoch is ignored and answered with `LBRESET;epoch` (throttled); a newer epoch
  wipes my copy first and, since I missed the vote, sends `LBREQ` 2 sec later to get
  the kills made since the reset (otherwise my board stays too low). On `LBREQ`, clients with an epoch send `LBRESET` too, so friends
  who were offline wipe their copy at login. Versions without epochs never reset and
  are ignored once a reset has happened.
- `/gnist top` (`tavle`, `pvp`) or the "Åbn PvP-tavle" button opens the window: four kill
  lists side by side (the all-time one is headed "All-time største slambert", the
  user's wording). It shows every player (up to `MAX_ROWS`, then "... og N mere") and
  grows in height with the longest list. #1's title is in each header; only all-time
  #2/#3 show theirs after the name.

## Duels (`Duels.lua`)

Duels between two guild members are shown with a random Danish comment and counted as
**duel wins** in the PvP leaderboard (a fifth list, "Dueller", in the `/gnist top` window).

- **Detection:** `CHAT_MSG_SYSTEM`, matched against patterns built from the globals
  `DUEL_WINNER_KNOCKOUT` (`%1$s has defeated %2$s in a duel`) and `DUEL_WINNER_RETREAT`
  (`%2$s has fled from %1$s in a duel`; %1 is the winner, %2 the one who fled), with
  English fallbacks. `BuildPattern` handles argument order. Names may be `First Surname`,
  `First-Surname` or just a first name; `Resolve` maps them to a roster member (a first
  name shared by two members is ignored). Both players must be guild members.
- **Data:** only the winner's total, as `duels` in `GnistifyDB.pvpBoard[name]` (`ns.DuelWin`
  in `Leaderboard.lua`; a record may have `total = 0` and only duels). No losses and no
  head-to-head are kept.
- **Sync and reset** are the leaderboard's: `LB;` records carry `duels` as the last field (after
  the epoch; missing = 0). Like `total`, it only goes up and the higher value wins, so a
  record with the same kills but more duels is taken, and one with fewer is answered with
  ours. The reset vote wipes `pvpBoard`, so it wipes duel totals too.
- **No double counting:** every client that sees the system message counts the duel itself
  (`ns.DuelWin`). Only a participant sends it: the winner at once, the loser after 4 sec and only
  if nobody has sent it by then (the winner may lack the addon). The same winner+loser is only
  counted once per 20 sec (`DEDUPE_WINDOW`), so the system and addon message never both count.
- **Message:** `DUEL;winner;loser;fled` on `GnistDing` to `GUILD` (`fled` 1 = the loser ran
  away). Append fields only. Only the live duel is sent; offline friends catch up through the
  `LB;` record sync. **Receivers only accept it from the winner or the loser**, and both names
  must resolve to guild members (`Resolve`), so nobody can hand out duel wins to others.
  (The `LB;` sync itself still trusts any sender, for kills and duels alike.)
- **Display:** `DUEL_MSGS` / `FLED_MSGS` (`{winner}`, `{loser}`) plus the winner's duel-win total.
  Setting `duels` turns off showing them; counting continues.

## Nordvestlisten (`Nordvest.lua`)

The guild's kill-on-sight list. The user named it "Nordvestlisten"; keep that name.

- **Adding:** `Menu.ModifyMenu` entries ("Sæt på Nordvestlisten" / "Fjern fra Nordvestlisten")
  on the PLAYER, TARGET, FOCUS, ENEMY_PLAYER, PARTY, RAID_PLAYER, RAID, FRIEND and CHAT_ROSTER
  menus (same as `Spy/Watch.lua`). Never for me or a guild member; any other player can go on
  it (also same-faction). Adding opens the `GNISTIFY_NORDVEST` `StaticPopup` with an optional
  reason (80 chars). Also `/gnist nordvest tilføj [grund]` (target) or `tilføj <navn>`.
- **Guild chat:** adding/removing posts a plain line with `{skull}` to guild chat
  (setting `nordvestGuildChat`), so members without the addon see it.
- **Alerts** (setting `nordvest`): seeing a listed player as target, mouseover, focus or
  nameplate gives a chat line from `ALERT_MSGS`, a banner (`nordvestBanner`) and
  `SOUNDKIT.RAID_WARNING` (`nordvestSound`), at most once per `ALERT_REPEAT` (120 sec) per name.
  The first to spot him sends `NVSEEN;name;zone` (`nordvestSend`); receivers show
  "X har spottet Y i Zone" and nobody re-sends within `SEEN_REPEAT`.
- **Visuals** (`nordvestMarks`): a red skull (raid icon 8 + red glow) above the nameplate
  (frame parented to `C_NamePlate.GetNamePlateForUnit`, skipped if forbidden), a skull on the
  target portrait, and tooltip lines (who, when, reason, kills) via `TooltipDataProcessor`.
- **Kills:** `Kills.lua`'s `Show` calls `ns.NordvestKill(victim, killer)` for every kill (also
  when showing kills is off), which counts `kills` and prints a `KILL_MSGS` "NORDVEST-DRAB!"
  line plus `ns.PlayCrownSound("big")`.
- **Data:** `GnistifyDB.nordvestList[name] = { t, by, removed, kills, class, level, guild, reason,
  seen, seenBy, seenZone }` (not `GnistifyDB.nordvest`, which is the setting). Removed entries
  stay as tombstones so the removal spreads; pruned after 60 days. At most 300 entries.
- **Sync** on `GnistDing` to `GUILD`: `NV;name;t;by;removed;live;kills;class;level;guild;reason`
  (append fields only; reason is cut to fit 250 bytes). Newer `t` (server time of the last
  add/remove) wins; `kills` only goes up (max wins). `live` = 1 is shown in chat. `NVREQ` 20 sec
  after login: everyone queues all records (shuffled, 1.2 sec apart), dropped when someone
  else sends the same or newer, like the PvP-tavle. Anyone in the guild may add or remove.
- `/gnist nordvest` (`nv`, `kos`) lists it; `tilføj`, `fjern [navn]`, anything else = help.

## Fishing (`Fishing.lua`)

For the guild's anglers. Settings `fishing` (show), `fishingSound`, `fishingBanner`,
`fishingSend` (share mine), `fishingSplash`.

- **Catch detection:** `LOOT_OPENED` with `IsFishingLoot()` (fallback: my Fishing channel
  ended under 3 sec ago). One loot window = one catch; `counted` resets on `LOOT_CLOSED`.
- **Notable:** quality green or better, a name in `NOTABLE_NAMES` (English, lower case),
  or a name containing a word from `NOTABLE_WORDS` (chests). Shown with a random line
  from `CATCH_MSGS` and a banner from `CATCH_BANNERS`, plus the game's fishing reel-in
  sound (`SOUNDKIT.FISHING_REEL_IN`, 3407).
- **Fish today:** `GnistifyDB.fishToday = { day, counts = { [name] = n } }` holds me and
  every angler who sent a count today. Counts in `TALLY` are announced. `/gnist fisk`
  shows the top 5.
- **Skill:** `CHAT_MSG_SKILL` parsed with a pattern built from `SKILL_RANK_UP`. Every 25
  points is announced; 75/150/225/300 (`SKILL_TITLES`) get a banner and sound 888.
- **Messages** on `GnistDing`: `FISK;count;zone;itemLink` on every catch (link empty unless
  notable) and `FSKILL;skill`. Receivers ignore their own echo. Append fields only.
- **Louder splash:** on the player's Fishing `UNIT_SPELLCAST_CHANNEL_START` the sound
  CVars in `SPLASH_CVARS` are saved to `GnistifyDB.fishingSaved` and changed; they are
  restored 10 sec after the last channel stop, on logout, at login (crash) and when the
  setting is turned off (`ns.RefreshFishing`).

## Streaks (`Streaks.lua`)

Counts consecutive days each character logs in; setting `streaks` (default on).

- **Data:** `GnistifyDB.streakDays[name] = { last = "YYYY-MM-DD", count, best, ann }`, per
  character (full name, `ns.Me()`), because `GnistifyDB` is account-wide. (Not
  `GnistifyDB.streaks`, which is the on/off setting.) Local date. Yesterday is computed
  via local noon of `day - 1`, so DST and month/year boundaries work.
- **On login** (first `PLAYER_ENTERING_WORLD` of the session): same day = nothing,
  `last == yesterday` = `count + 1`, else `count = 1`; `best` is updated.
- **Milestones:** 3, 7, 14, 30, 50, 100, 150, 200, 365, then every 100. 10 sec after login
  (`ANNOUNCE_DELAY`) the chat line, banner (`banner`), sound (`sound`), `STREAK;days`
  addon message on `GnistDing` to `GUILD`, and (if `guildChat`) a guild chat line are
  sent. Text from `STREAK_MSGS` (`{name}`, `{days}`). `ann` holds the day it was
  announced, so it is at most once per day per character. Receivers ignore their own
  echo; `streaks` off hides everyone's and stops announcing mine.
- `/gnist streak` (`dage`) prints my current and best streak.

## Professions (`Professions.lua`)

Lets the guild look up who has which profession. Setting `profShare` (share mine; looking
up others always works). **Profession names are English on purpose** (the user wants it),
in commands and output; the surrounding text is Danish.

- **Reading mine:** `GetProfessions()` + `GetProfessionInfo(i)` (retail) and
  `GetNumSkillLines()` + `GetSkillLineInfo(i)` (classic) are both tried, in `pcall` and
  through `ns.Readable`. Only the 12 names in `PROF_LIST` count (Alchemy, Blacksmithing,
  Enchanting, Engineering, Herbalism, Leatherworking, Mining, Skinning, Tailoring, Cooking,
  First Aid, Fishing). Collapsed skill headers are not expanded, so a classic skill list
  may hide some; the retail API covers them.
- **Message** on `GnistDing` to `GUILD`: `PROF;Alchemy=225/300;First Aid=1/75` (entries in
  `PROF_LIST` order, cut off before 240 bytes) and `PROFREQ`. Receivers skip unknown names
  and bad numbers (skill must be 1..max, max at most 700), so only append new entries.
  Receivers ignore their own echo.
- **When sent:** 10 sec after login, when `SKILL_LINES_CHANGED` / `CHAT_MSG_SKILL` fire
  (at most once per 30 sec, and only if the text changed), and in reply to `PROFREQ`
  (random 1-9 sec delay, at most once per 60 sec). A client with no other member in its
  cache sends `PROFREQ` at login. With `profShare` off nothing is sent, but my own
  professions are still stored.
- **Data:** `GnistifyDB.profs[name] = { t = time(), Alchemy = { 225, 300 }, ... }`, account
  wide, so offline members and my other characters show up. A new message replaces the
  member's whole entry.
- **`/gnist prof <profession>`** lists everyone known, best skill first, as
  `Alchemy: Frosbe Echoshot 225/300, Bo Hansen 150/150 (3 dage gammel)` (age only when
  over a day, at most 25 rows). The name is matched case-insensitively: aliases
  (`alch`, `bs`, `ench`, `eng`, `herb`, `lw`, `skin`, `tailor`, `cook`, `fa`, `fish`, ...) or
  a unique prefix; an ambiguous one ("e") answers "Mente du: ...". With no argument it lists
  each profession with how many known members have it. Every run also sends `PROFREQ`
  (at most once per 60 sec), so the next lookup is fresher.

## Epic loot (`Loot.lua`)

When a member loots an item of quality 4 (epic) or 5 (legendary), every Gnistify user
sees a random line from `LOOT_MSGS` (`LEGENDARY_MSGS` for quality 5) in their own chat
window, e.g. `Gnisten lyser lilla! Bo har fået fingrene i [Item]!`, like kills. The
banner uses `LOOT_BANNERS` / `LEGENDARY_BANNERS`. Settings `loot` (show), `lootSound`
(`SOUNDKIT.UI_EPICLOOT_TOAST`, 31578 fallback), `lootBanner`, `lootSend` (share mine).

- **Detection:** `CHAT_MSG_LOOT`, matched against patterns built from `LOOT_ITEM_SELF_MULTIPLE`
  and `LOOT_ITEM_SELF` ("You receive loot: ..."). Crafting ("You create: ...") never
  matches. Vendor purchases and quest rewards both arrive as `LOOT_ITEM_PUSHED_SELF`
  ("You receive item: ..."), which can't be told apart, so it is ignored on purpose.
- **Quality:** `C_Item.GetItemQualityByID`, then `GetItemInfo`, then the link's colour
  code (all through `ns.Readable`).
- **Message** on `GnistDing` to `GUILD`: `LOOT;itemLink;quality;itemID`. If that would
  exceed 250 bytes the link is left empty. Only the looter sends; receivers ignore their
  own echo, and the looter sees the line locally once. Append fields only.
- **Receivers never trust the sender's text** (`OnOthersLoot`): the quality field is
  ignored; name, link and quality come from this client's `GetItemInfo(itemID)`, and
  below epic is dropped. An uncached item is requested (`C_Item.RequestLoadItemDataByID`)
  and shown on `GET_ITEM_INFO_RECEIVED`, or dropped after 5 sec. The sent link is only
  kept (for random suffixes) if it is one plain item link for the same ID whose name
  starts with the real name, and it gets the real colour (`SafeLink`).

## Shot caller (`Caller.lua`)

For battlegrounds: the group picks one shot caller ("leder"), and everyone presses one
key to target the caller's target.

- **Targeting is protected.** Addon code may never call `TargetUnit`/`AssistUnit`.
  The hidden secure button `GnistAssistButton` (`SecureActionButtonTemplate`,
  `type="assist"`, `unit=<caller's raidN/partyN token>`) does the targeting. Players
  press it with the key binding in `Bindings.xml` or a macro `/click GnistAssistButton`
  (`/gnist makro` creates the character macro `GnistMål` and puts it on the cursor).
  It's registered for `AnyUp` and `AnyDown`, so it works with either "cast on key
  down" setting; assisting twice is harmless.
- Unit tokens, not names, because targeting by name is unreliable with Forever
  surnames (see `Spy/Forever.lua`, `Spy:TargetMacro`).
- **Secure attributes can't change in combat.** A caller picked in combat, or a roster
  change in combat, sets `pending` and is applied on `PLAYER_REGEN_ENABLED`.
- **Sharing:** picking a caller sends `LEDER;<First Surname>` (empty = none) on the
  `GnistDing` prefix to `INSTANCE_CHAT`, `RAID` or `PARTY`. Receivers in the same group
  follow it if `callerFollow` is on. The caller re-sends it (throttled) on
  `GROUP_ROSTER_UPDATE` so newcomers learn it. The caller is saved in
  `GnistifyDB.callerName`, the window position in `GnistifyDB.callerPos`.
- **Window:** opens by itself when in a group inside a battleground, arena or dungeon
  (`IsInInstance` type `pvp`, `arena`, `party`; setting `callerFrame`). Anywhere else
  only by hand: `/gnist leder` or the "Åbn leder-vindue" button in `/gnist` (which also
  has a "Lav makro" button). Its X hides it until the next loading screen.
  It grows in width to fit the longest line (no word wrap). Under the target's name is
  a health bar (red for enemies). Health can be secret on Forever, so `UnitHealth` and
  `UnitHealthMax` go straight into the `StatusBar` (in `pcall`) without `Readable`. The
  game sends no `UNIT_HEALTH` for `raidNtarget`, so the bar refreshes every 0.1 sec while
  the window is shown.
- **Clickable window:** `GnistAssistButton` is also the window's click area. The window
  (`GnistifyCallerFrame`, insecure) is anchored *to* the button, never the reverse:
  anchoring a secure frame to an insecure one makes the insecure one protected, and its
  in-combat resizing would be blocked. `SyncButton` copies the window's size and
  visibility to the button out of combat only (catching up on `PLAYER_REGEN_ENABLED`).
  The window has `EnableMouse(false)` so clicks reach the button; Vælg and X sit on a
  higher frame level. Only `type1` is set, so left click assists and right-drag moves
  (the position is saved for the button in `GnistifyDB.callerPos`).
  Shows the caller, the caller's target (`UNIT_TARGET`) and whether you have the same
  target. Plays `SOUNDKIT.MAP_PING` when the caller switches to a new enemy you don't
  have targeted (`callerSound`, at most every 1.5 sec).

## Settings UI (`Options.lua`)

- `OPTIONS` is the single source: `{ header = "..." }` starts a section, `{ key = "...", label = "..." }`
  is a checkbox bound to `GnistifyDB[key]`, `{ buttons = { { label, func }, ... } }` is a row of
  buttons. Optional field `tooltip` on a checkbox or a button entry. Keep this format: open pull
  requests add lines to the table.
- **Native path** (`BuildNative`): `Settings.RegisterVerticalLayoutCategory("Gnistify")` plus one
  `RegisterVerticalLayoutSubcategory` per header. Checkboxes use `Settings.RegisterAddOnSetting`
  bound straight to `GnistifyDB` (modern signature `category, variable, key, tbl, type, name,
  default`; if that fails, `RegisterProxySetting` with getter/setter), then `Settings.CreateCheckbox`
  (or `CreateCheckBox`). Buttons are `CreateSettingsButtonInitializer` added with
  `layout:AddInitializer`. The front page shows the version and the PvP-tavle and leder buttons.
- **Timing:** registered on `PLAYER_LOGIN`, so `GnistifyDB` (created in `ADDON_LOADED` in
  `Gnistify.lua`) exists. `Gnistify_ToggleOptions` is `Settings.OpenToCategory` and re-syncs the
  checkboxes from `GnistifyDB` first (slash commands like `/gnist lyd` change values directly).
- **Fallback** (`BuildFallback`): used when the vertical-layout API is missing or registration
  errors. The window height is computed from the rows, no constant to edit.
- **To add a setting:** give it a default in `ADDON_LOADED` in `Gnistify.lua` (and in
  `DEFAULT_OFF` in `Options.lua` if the default is off) and add an entry to `OPTIONS`. A new
  header makes a new subcategory.

## Zone presence (`Zones.lua`)

When you enter a new zone, one chat line lists the online guildies in the same zone:
`3 gnister i Stranglethorn Vale: Bo Hansen (34), Tim (31), Mink Jageren (36)` (sorted by
level, at most 15 names then "og N mere"). It reads the guild roster
(`GetGuildRosterInfo`: name, level, zone, online), so it works for every guild member,
with or without the addon; no addon messages. Me is excluded; nobody there = no line.

- **Triggers:** `ZONE_CHANGED_NEW_AREA` and the first `PLAYER_ENTERING_WORLD` after
  login. Not inside instances, battlegrounds or arenas (`IsInInstance` type other than
  `none`). Zone is `GetRealZoneText()`; zones are compared trimmed and lower case with
  the roster's zone (both English on this client).
- **Roster:** no second poller. `Gnistify.lua` exports `ns.RequestRoster` and calls
  `ns.ZoneRosterUpdate()` from `GUILD_ROSTER_UPDATE`. A zone change requests the roster
  and prints on the next update, or after `WAIT` (3 sec) from cached data. `pending`
  makes sure a zone change prints once.
- **No spam:** the same zone is not announced again within `REPEAT_TIME` (120 sec).
- **Commands:** `/gnist her` (`zone`) lists my zone now; `/gnist her <zone prefix>` lists
  every matching zone; `/gnist zoner` counts online guildies per zone (most first).

## Tracking switch (`Tracking.lua`)

Like the Forager addon, but small: rotates the minimap tracking between the ticked kinds
every 5 sec (`DELAY`), out of combat. Setting `tracking` (default **off**).

- **Kinds:** `trackHerbs` (Find Herbs 2383), `trackMinerals` (Find Minerals 2580),
  `trackHumanoids` (Track Humanoids 19883 hunter, 5225 druid, the druid one only in Cat
  Form). Account-wide settings; each character only rotates through the ones in its
  `C_Minimap.GetTrackingInfo` list (spell entries only; town trackers like Innkeeper are ignored; matched by spell ID, then English name), so humanoids
  are simply absent on non-hunters. Fewer than two = nothing happens.
- **Switch:** `C_Minimap.SetTracking(index, true)`, checked 1.5 sec later. Pauses in
  combat, dead, taxi, resting, instances, while casting/channelling or looting, on the
  spell's cooldown (GCD), and while a tracking that isn't ticked is on (a manual pick is
  respected). A manual pick (`MINIMAP_UPDATE_TRACKING`) gets a full turn. Skipped
  entirely while Forager is loaded and enabled.
- **Safe moments** (`Hold`): each switch starts the GCD, so a due switch is held, without
  resetting the countdown, while casting or looting, within 3 sec of my own
  `UNIT_SPELLCAST_SUCCEEDED` (not the tracking cast itself), with an attackable live target,
  while an enemy player's nameplate (`nameplate1..40`) is shown, and, with `trackOnlyMoving`
  (default off), while standing still (mounted counts as moving).
- **Fallback:** if `ADDON_ACTION_BLOCKED/FORBIDDEN` hits a timed switch, or three timed
  switches don't take, it switches on the next key press instead (a keyboard frame with
  `SetPropagateKeyboardInput(true)`, checked before the script is set; ability-bound keys,
  modifiers, Tab, Esc, Enter never switch), until `/reload`. Same idea as Forager.
- **Quiet:** `trackQuiet` turns `Sound_EnableSFX` off during the switch (not while the
  fishing splash holds the CVars); `GnistifyDB.trackUnmute` restores it at login after a crash.
- **Toggle:** shift-click or middle click on the minimap button (tooltip shows the state), the key binding
  "Skift sporing til/fra", or the checkbox (`ns.ToggleTracking`).
- `/gnist spor` toggles and prints the rotation and why it's waiting; `/gnist spor til|fra`.

## Settings and commands

Settings are stored in the `GnistifyDB` saved variable, and all of them except `callerSound`,
`tracking` and `trackOnlyMoving` default to on:
`dings` (show guild dings at all), `sound`, `banner`, `guildChat`, `kills` (show the
guild's kills), `killSound` (play `sound.mp3` on a kill), `killBanner` (show kills as a raid-warning banner too), `killsSend` (send my own kills to the guild), `minimapIcon` (the minimap button), `crownSound` (sound for a new leaderboard #1), `eliteFrames` (elite dragon on leaders' portraits), `emojis`, `callerFrame` (open the leader
window by itself in BGs, arenas and dungeons), `callerFollow` (follow a caller picked by others), `callerSound`
(ping when the caller changes target, default off), `fishing`, `fishingSound`, `fishingBanner`,
`fishingSend`, `fishingSplash`, `streaks` (celebrate login streaks), `profShare` (share my professions), `zonePresence` (list guildies in the zone I enter), `loot`, `lootSound`, `lootBanner`, `lootSend`, `duels` (show guild duels in chat), `tracking`, `trackHerbs`, `trackMinerals`, `trackHumanoids`, `trackQuiet`, `trackOnlyMoving` (tracking switch), `nordvest`, `nordvestSound`,
`nordvestBanner`, `nordvestMarks`, `nordvestSend`, `nordvestGuildChat` (Nordvestlisten).

| Command | Effect |
|---|---|
| `/gnist` or `/gnistify` | Open the settings (Options → AddOns → Gnistify) |
| `/gnist hjælp` | Show the command list |
| `/gnist lyd` | Toggle the sound |
| `/gnist guild` | Toggle the guild chat post when you ding |
| `/gnist banner` | Toggle the banner in the middle of the screen |
| `/gnist drab` | Toggle showing the guild's PvP kills in chat |
| `/gnist top` | Open the world PvP leaderboard (also lists duel wins) |
| `/gnist reset` | Ask the guild to reset the PvP-tavle (popup for everyone, 4 yes needed) |
| `/gnist ja` | Vote yes to a reset (same as the popup's button) |
| `/gnist fisk` | Show today's catch counts in the guild |
| `/gnist streak` (or `dage`) | Show your current and best login streak |
| `/gnist prof [profession]` | List guild members with a profession, best first (no argument: how many have each) |
| `/gnist her [zone]` (`zone`) | List online guildies in my zone, or in zones starting with the given text |
| `/gnist zoner` | Count of online guildies per zone |
| `/gnist spor [til\|fra]` | Toggle the automatic tracking switch (every 5 sec) |
| `/gnist nordvest [tilføj\|fjern] [navn/grund]` (`nv`, `kos`) | Show Nordvestlisten, add the target (or a name), remove someone |
| `/gnist emojis` | List the available emojis |
| `/gnist leder [navn\|mig\|ingen]` | Make your target (or the named member, yourself, nobody) the caller; with no target, open the leader window |
| `/gnist makro` | Create the `GnistMål` macro and put it on the cursor |

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
- The ding and kill messages are picked at random from lists, at the user's request,
  so they vary. The ding list keeps "er dinget level X! Længe leve gnisten!" as one
  variant. The user rejected "opsteget ... i Gnisthood" and "i Gnistskab"; don't use
  those.
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
