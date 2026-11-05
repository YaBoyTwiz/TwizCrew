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
  the owner's request ("do this work on a different agent"). Not tested in game, not published.
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
- **Suggested way to work** (Claude's call, change if it fights you): keep the addon's source in this folder and put a
  symbolic link to it in the AddOns folder, so an edit here plus `/reload` in game is the whole test loop.

## Making pictures for the addon

- **The owner said we can use their Twiz-Orchestrator for images** (`~/Documents/GitHub/Twiz-Orchestrator`, their
  own app that runs ComfyUI; its default text-to-image and edit model is Qwen Image 2.1). Use it for icons, tags,
  pop-up pictures, emojis and the like.
- WoW reads **`.tga`** (and `.blp`) pictures, with sides that are powers of two (64, 128, 256…) and an alpha channel
  for transparency. Convert the PNGs before shipping. Check in game which formats Forever accepts.

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
