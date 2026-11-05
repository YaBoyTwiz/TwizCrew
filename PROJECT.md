# TwizCrew: a WoW Forever addon for me and my friends

> Working name. It can change; the addon's folder name in WoW is the addon's name, so pick the final one before
> friends install it.

## What we are making

An addon for **World of Warcraft: Forever** that only my friends and I use. Every friend runs a copy, and the
copies **talk to each other**: they share information (who is where, what they are doing) and **trigger effects on
each other's screens** (a sound, a picture, a message, an arrow on the map).

Other players never see any of it. The messages are hidden addon messages, not chat.

## Where we are (2026-11-05)

- **v1 design approved by the owner** (2026-11-05): `docs/superpowers/specs/2026-11-05-crew-panel-design.md`.
- **Build plan:** `docs/superpowers/plans/2026-11-05-crew-panel.md`. The build was handed to a background agent at
  the owner's request ("do this work on a different agent").
- **v1 is built (2026-11-05):** every test outside the game passes (`tests/run.sh`, including a simulation of two
  and three copies talking to each other). **Not yet tested in game, not published.** What the owner can try in
  game, riskiest first: `docs/TESTING.md`.
- **Testing with friends needs the owner's go-ahead:** friends can only get TwizCrew once it is published (public
  GitHub repository + WowUp, below), and the final name has to be picked before that (see the note at the top).
- The owner liked the idea of sharing information and triggering effects on each other's screens.
- **First feature picked (owner):** show what **layer** each friend is on, and **what each friend with the addon
  is doing**. Details not designed yet.
- **Why layers (owner):** "just an easier way to tell when someone is on a different layer." Not about rares or
  world buffs.
- **Crew panel is the base (owner):** a movable window listing every friend; later features build on it.
- **Look (owner):** layer and events shown as party-frame style rows with red tags like "OTHER LAYER" (mockup B).
- **Layer compare needs the same zone (owner, 2026-11-05):** two friends are compared only when both are in the
  same zone (stricter than "same continent"). Otherwise unknown, shown as nothing.
- **Pop-ups (owner):** a small pop-up too, for **layer changes and deaths**. Other tags stay quiet on the panel.
- **The crew (owner):** all on the **same realm and same faction**, **no guild yet**. So the copies talk over a
  hidden custom channel (Claude's call), and over `PARTY` when grouped; switch to `GUILD` later if they make one.
- **Crew size (owner):** about **5**, probably more over time. Build the panel for ~5 but let it grow (scroll or a
  compact view past ~8; Claude's call).
- **Crew panel can be hidden (owner)** but is **on by default**. Give it **plenty of settings** so people tailor
  it to their comfort instead of turning it off.
- **Testing (owner):** "we will test with WowUp"; the owner **can't test right now**, so build v1 "in a way that
  will make it easier to fix if something doesn't work" (fallbacks, a debug log Claude can read from the WTF
  folder after `/reload`, `/tc report`). See the design document, section 13.
- **Chat command `/tc` (and `/twizcrew`)**, because TwizTracker already uses `/twiz` (Claude's call).
- **(i) info button on every setting (owner)** that explains what it is for.
- **Class icons in the Crew panel (owner).** The game has its own class icons built in, so no picture making is
  needed for these.

## Next feature being brainstormed: stats board (2026-11-05)

- **Design approved by the owner ("do it"):** `docs/superpowers/specs/2026-11-05-stats-board-design.md`. Plan
  and build handed to a background agent. Sessions: one shared crew session, started
  automatically, restartable with `/tc session new` (Claude's call).

- **Owner picked the stats board** as the next idea to flesh out.
- **Purpose (owner):** "mostly for laughs, roasting each other on stream". Not serious progress tracking.
- Owner: "up to you, be creative as needed". **Claude's pitch (not approved yet):** three ways it shows up: live
  roast pop-ups, a "Hall of Shame" tab in the Crew panel (weekly awards, resets Monday), and an awards show the
  owner starts on stream (`/tc awards`). Mockup: `.superpowers/brainstorm/…/stats-board.html`. Stats are limited to
  what an addon can see without the combat log (deaths with fall/drown/weak-mob guesses, first into combat,
  rezzes given, AFK time, jumps, hearthstones, junk looted, repair bills, quests abandoned, duels lost).
- **Time ranges (owner):** "session based stats, plus all time". Replaces the weekly reset in the pitch.
- **Track steps too (owner)**, "find an efficient way… so it's not spamming". Claude's plan: a 0.5 s local timer adds
  `GetUnitSpeed("player") × time` (fallback: distance between `UnitPosition` readings), split into on foot (shown as
  steps, about 1.2 steps per yard), mounted, swimming; flight paths excluded. Counting stays local; totals are
  shared only every few minutes when changed, at logout, and when someone opens the board. Milestone roasts only
  at big round numbers.

## Decisions (owner)

- **Goal:** slowly build "the ultimate addon" for the owner and a small group of friends, useful for playing
  together and fun. Grow it bit by bit.
- **Modular:** players can turn parts on and off.
- **Two tiers:** the parts that must be there (essentials) are kept apart from the nice-to-have extras.
- **One button sets everything back to defaults.**

## Ideas so far (not decided)

- **Friend radar:** a small panel with each friend's level, zone and what they are doing.
- **Pokes and soundboard:** send a friend an air horn, a "LOL", a jump scare or a big emoji on their screen.
- **"Come here" ping:** press a button and friends get an arrow on their map pointing at you.
- **Quest sync:** see which quests friends still need, so you do them together.
- **Group races:** first to level 30, most gold this week, fewest deaths, with a shared leaderboard.
- **Mini-games:** dice duels, bets on who dies first, a fishing contest, trivia.
- **Stream moments:** friends trigger a funny effect on the owner's screen and the stream sees it (OBS records the
  game screen, so anything the addon shows is on stream).

## How friends get it and stay updated (Claude's recommendation; the owner said "ok")

1. The addon lives in a **public GitHub repository** on the owner's account (YaBoyTwiz). WowUp only sees public
   repositories. The owner's other repositories stay private.
2. Friends install **WowUp** (free addon manager, Windows / Mac / Linux), choose **Install from URL** once and paste
   the GitHub link. WowUp then offers every new release, with one click or automatically.
3. Claude publishes a release when the owner says "release it".
4. **Built-in version check:** each copy tells the others its version; if a friend has a newer one, the player sees
   "Ginkan has v1.3, you have v1.2. Update in WowUp."

Rejected for now: sending zips on Discord (every update is manual for everyone), CurseForge (public to everyone,
every upload waits for review; made for addons aimed at strangers).

## What an addon can and cannot do in WoW Forever

WoW Forever runs on the **modern WoW engine** (Blizzard: "we did opt for the modern API approach"), so the strict
rules from the Midnight expansion apply. Most of the details below come from players and addon makers testing the
beta, not from Blizzard, so **test every one of them in the real game**.

**Can:**
- Draw its own windows, bars, buttons, text, icons; play sounds; change or hide Blizzard's screens.
- React to game events (XP gained, loot, quest done, death, friend logged in, zone changed…).
- Read your XP, gold, bags, quests, map position, zone, friends, guild.
- Add chat commands (`/twiz`).
- **Send hidden messages to other copies of the addon** with `C_ChatInfo.SendAddonMessage(prefix, text, channel,
  target)` after `C_ChatInfo.RegisterAddonMessagePrefix(prefix)`, received with the `CHAT_MSG_ADDON` event.
  Channels: `PARTY`, `RAID`, `GUILD`, `WHISPER` (one person), `CHANNEL` (a custom chat channel only the friends
  join, which works without being in a group).
- Save its data between sessions (SavedVariables, written at logout or `/reload`).

**Cannot / limits:**
- **No playing for you:** it cannot move, cast, or target on its own. Every action needs a key press or a click.
- **Short messages, few per second:** about 255 characters per message, and the game throttles bursts (send a few
  per second at most; queue the rest).
- **Boss fights:** addon messages are reported to be **blocked during a boss fight** inside dungeons and raids. Plan:
  queue them and send after `ENCOUNTER_END`. The rest of the dungeon (trash, between pulls) is reported to work.
  Your own screen can still show things during a boss fight.
- **"Secret" combat numbers:** during combat, health, buffs and enemy info can come back as secret values: you
  can show them (pass them straight to a status bar) but not compare or do math on them. Check with
  `issecretvalue()`.
- **No combat log** for addons in Forever (reported); Blizzard ships its own damage meter and cooldown tracker.
- **No internet, no files, no other programs.** The only thing it writes is its SavedVariables file. A program
  outside the game could read that file after a `/reload` (e.g. for a stream overlay).
- Some interface changes are **locked during combat** (`InCombatLockdown()`): wait for `PLAYER_REGEN_ENABLED`.
- **Lua 5.1**, Blizzard's version: no `goto`, no `//`, no bit operators (use the `bit` library), no `require`,
  `io` or `os`. The `.toc` file lists the files to load.

## Technical facts

- **Interface number: `16001`.** Confirm in game: `/run print((select(4, GetBuildInfo())))`.
- **TOC file:** `TwizCrew.toc` with `## Interface: 16001`. A Forever-only file may be named `TwizCrew_Forever.toc`
  (the Warcraft Wiki also lists `_Camelot` as an older alias). Questie and Quest Master ship both.
- **Use modern API names:** `C_Spell`, `C_Item`, `C_ChatInfo`… Old globals like `GetSpellInfo` / `GetItemInfo` were
  reported missing.
- **Where the game is on this PC:** Lutris (Flatpak) → Battle.net (on GE-Proton11-12) → WoW Forever.
  AddOns folder:
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`
- **Already installed there:** Questie, QuestieDB, QuestMaster, and **TwizTracker** (a small starter addon Claude wrote:
  `/twiz` shows XP per hour, time to level and gold this session; not yet tested in game).
- **How TwizCrew gets into the game (set up 2026-11-05):** the AddOns folder has a symbolic link `TwizCrew` →
  `~/Documents/GitHub/twizcrew/TwizCrew`, so an edit here plus `/reload` in game is the whole test loop. Lutris is a
  Flatpak; its permissions include `filesystems=home` (checked with
  `flatpak info --show-permissions net.lutris.Lutris`), so the game can read the link's target and no Flatpak
  override or copy script is needed.
- **TwizCrew's log and saved data:**
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/TwizCrew.lua`
  (written at `/reload` or logout; Claude reads it there).

## Making pictures for the addon

- **The owner said we can use their Twiz-Orchestrator for images** (`~/Documents/GitHub/Twiz-Orchestrator`, their
  own app that runs ComfyUI; its default text-to-image and edit model is Qwen Image 2.1). Use it for icons, tags,
  pop-up pictures, emojis and the like.
- WoW reads **`.blp`, `.tga`, `.png` and `.jpg`** pictures (Warcraft Wiki), with sides that are powers of two (64,
  128, 256…). Path must include `.png` for PNGs. Check in game which formats Forever accepts.
- **Sounds:** `.ogg` and `.mp3` from the addon folder with `PlaySoundFile(path, "Master")` ("Master" so muted
  effects don't silence it). **Fonts:** own `.ttf` works.
- **Animated pictures:** sprite sheets with the `FlipBook` animation (since 10.0). This is how Blender renders become
  "3D-looking" effects.
- **No video** from addons. **No custom 3D model files** (treat as impossible).
- **New files:** since 9.0.1 a `/reload` picks up new files in an existing addon folder; a new addon folder or a
  changed `.toc` needs a full game restart (reported; test).
- Assets cannot be sent between players: every friend needs the file already, so new art/sounds ship in an update.

## In-world waypoints (Claude's knowledge, not yet checked for Forever)

- Addons can't draw freely in the 3D world (there is no "world to screen" function). The in-world marker comes from
  Blizzard's own **map pin + tracking**: `C_Map.SetUserWaypoint(...)` and
  `C_SuperTrack.SetSuperTrackedUserWaypoint(true)` show a floating marker with distance; addons can restyle it via
  `C_Navigation.GetFrame()`. Markers on units (players, NPCs) are attached to their nameplates.
- **Forever has them:** QuestMaster (installed here, `Modules/WorldMarker.lua`) says "WoW Forever has them" and
  uses them. Its method: put a map waypoint (`C_Map.SetUserWaypoint` + `UiMapPoint.CreateFromCoordinates`), super-track
  it, then hang its own marker art on `C_Navigation.GetFrame()` (the game moves that frame to the target's spot on
  screen), hide the game's diamond, scale with `C_Navigation.GetDistance()`, and show an edge arrow when
  `C_Navigation.WasClampedToScreen()`. It credits WaypointUI for the technique. Limit: **one** navigation target at a
  time (the game only super-tracks one thing), and it fights with QuestMaster/Blizzard over that one slot.
- QuestMaster is GPL-3.0: learn the technique, don't copy its code or art.
- Possible use: the "come here" ping.

## 3D models (research 2026-11-05, Warcraft Wiki + forums; not tested in Forever)

- Addons can show **game** models: `PlayerModel`, `DressUpModel`, `ModelScene` actors. Units (`player`, `party1`,
  `target`) only when that player is loaded nearby; far away they show blank.
- Any creature by display ID; any item tried on with `DressUpModel:TryOn`.
- A far-away friend's look can only be **approximated**: a stand-in body of their race wearing their item IDs (sent
  over addon messages). Face, hair and skin cannot be set. No existing addon does the far-away version.

## Working with the owner

- Plain words, short messages, one question at a time. The owner often types from a phone: read for intent, not typos.
- No multiple-choice pop-ups; ask in plain words.
- The owner streams (OBS + Discord). Anything on the game screen is on stream.
- Nothing is published (GitHub release, public repository) until the owner says so.

## Sources

- WoW Forever addon developer guide (fan site; most limits there are from beta testing):
  https://wowforeverguides.com/addons/developers
- Warcraft Wiki, TOC format: https://warcraft.wiki.gg/wiki/TOC_format
- Midnight (12.0) notes for addon makers (boss-fight message block): https://wow-midnight-addon-template.vercel.app/midnight/
- Icy Veins, combat addon restrictions eased in Midnight:
  https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/
- Questie (Forever support, interface 16001): https://github.com/Questie/Questie/releases
