# TwizCrew: a WoW Forever addon for me and my friends

> **Final name: TwizCrew** (owner, 2026-11-05). Public repository: https://github.com/YaBoyTwiz/TwizCrew

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
- **Stats board built too (2026-11-05):** Hall of Shame tab, live roasts, `/tc awards`. Not tested in game, not
  published. Details in the "Stats board" section below.
- **"Tell crew to update" button built (2026-11-05):** not tested in game, not published. Details in its section
  below.
- **Minimap button built (2026-11-05, owner asked):** left-click settings, right-click panel, drag around the edge,
  `/tc minimap`, also in the minimap's AddOns list. Not tested in game, not published; its release needs a game
  restart. Plan and Claude's calls: `docs/superpowers/plans/2026-11-05-minimap-button.md`; checks: `docs/TESTING.md`.
- **Update notice and version number built (2026-11-05, owner asked):** version in the panel title and minimap
  tooltip; when a friend is newer: gold "!" on the minimap button, gold "Update available" line on the panel, and a
  how-to-update pop-up once per version (HELLO and STATE now carry `rs`); README tells friends to let WowUp
  auto-update and start with the computer. Not tested in game, not published. Plan and Claude's calls:
  `docs/superpowers/plans/2026-11-05-update-notice.md`; checks: `docs/TESTING.md`.
- **Level progress built (2026-11-05, owner said "all three"):** "Lv 12 · 63%" on each row, a hover tooltip with
  XP to level, rested XP and "About 25 min to level", and a "<Name> reached level 13!" pop-up (sound off by
  default). Not tested in game, not published; no restart needed. Plan and Claude's calls:
  `docs/superpowers/plans/2026-11-05-level-progress.md`; checks: `docs/TESTING.md`.
- **Test tools built (2026-11-05, owner: "in the addon add a way to test"):** `/tc` → **Try it out** (and `/tc test`):
  pretend friends, a copy of yourself, ding / death / layer / roast pop-ups and the update notice through the real
  code, only on your own screen, never sent or saved. Not tested in game, not published; no restart needed. Plan and
  Claude's calls: `docs/superpowers/plans/2026-11-05-test-tools.md`; checks: `docs/TESTING.md`.
- **Published (2026-11-05, owner said yes to "keep the name TwizCrew and publish now"):** public repository
  https://github.com/YaBoyTwiz/TwizCrew, release v0.1.0. Friends install it with WowUp (README.md). Still not
  tested in game. Before going public, the owner's WoW account folder name was removed from every file and from
  the history; docs use `WTF/Account/*/` instead. Never write it into the repository.
- **Find the crew built (2026-11-07, owner: "do it"):** an arrow and the distance on each group member's row (click:
  a big arrow in their class colour), and meet-ups: Ctrl + right-click a spot on the world map, for the party or
  everyone (sender's choice), shown as a pop-up, the big arrow and an icon on the world map and minimap. Positions
  go to the group only (owner: "we dont need position updates for players not in the group"); no friend dots on
  the maps; no in-world marker for now (owner: "dont worry about the marker for now"). Never uses the game's
  waypoint, so QuestMaster's keeps working. Not tested in game, not published; **its release adds files, so it
  needs a game restart** (set `RESTART_SINCE`). Design: `docs/superpowers/specs/2026-11-07-find-the-crew-design.md`;
  plan and Claude's calls: `docs/superpowers/plans/2026-11-07-find-the-crew.md`; checks: `docs/TESTING.md`.
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

## Stats board ("Hall of Shame"), live roasts, awards show (2026-11-05)

- **Design approved by the owner ("do it"):** `docs/superpowers/specs/2026-11-05-stats-board-design.md`. Sessions:
  one shared crew session, started automatically, restartable with `/tc session new` (Claude's call).
- **Built (2026-11-05), not yet tested in game, not published.** Plan and every change made while building (with
  the reasons): `docs/superpowers/plans/2026-11-05-stats-board.md` ("Changes during build"). All tests outside the
  game pass (`tests/run.sh`, including two and three copies talking). Built on the local git branch `stats-board`.
  What the owner can try in game, riskiest first: `docs/TESTING.md`, section "Stats, roasts and the awards show".
- **Changed from the design while building (Claude's call):** a death counts as a fall only after about a second of
  real falling (a normal jump is not a fall); "Died to a Weakling" only blames a mob that was fighting you; a
  `/reload` continues your session only if the crew online hasn't moved to another one.

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

- **Hall of Shame upgrade (designed 2026-11-09, owner said yes to every section; written spec waiting for review):**
  `docs/superpowers/specs/2026-11-09-hall-of-shame-upgrade-design.md`. Crew asked for a "poorest" award; the owner
  picked Pauper + Money Pit (exact gold shown), 9 more awards, category tabs, stolen crown pop-ups, trophy case with
  streaks, the awards show on everyone's screen and a Clown of the Night vote. Not wanted for now: predictions,
  custom awards. Built in three parts, each its own release. **Part 1 (new awards, tabs) built 2026-11-09** on
  branch `hall-of-shame-part1`, plan `docs/superpowers/plans/2026-11-09-hall-of-shame-part1.md`; not tried in game
  yet (checks: `docs/TESTING.md`). Part 2 (stolen crowns, trophies, streaks) built 2026-11-09, plan
  `docs/superpowers/plans/2026-11-09-hall-of-shame-part2.md`; not tried in game. New files: the next release sets
  RESTART_SINCE. The swap offers up to the 10 newest sessions (fewer when their ids are long). A record saved at login (the session ended while I was away) is
  "late" and is swapped for a full one from someone who stayed; a late one never replaces a full one. When the crew
  logs off one by one, every copy ends up with the late version made from the freshest numbers (the friend who
  stayed latest), once they've been online together. Stolen-crown pop-ups skip Pauper, Couch Potato, Snail
  and Never Walks (they change without anyone doing anything), and a friend's very first numbers never count as a
  steal. Part 3 (the awards show on everyone's screen, Clown of the Night vote) built 2026-11-09 on branch
  `hall-of-shame-part3`, plan `docs/superpowers/plans/2026-11-09-hall-of-shame-part3.md`; not tried in game (checks:
  `docs/TESTING.md`). New file `UI/ShowLogic.lua`: the release sets RESTART_SINCE. The presenter sends one message
  per card (AWS start, AWC card with `m` = winners left out so it fits one message, AWX close); viewers follow,
  a fight makes them catch up afterwards, 60 s with no new card closes it everywhere; setting "Show the crew's
  awards show on my screen". Vote (session view, 2+ people): AWV / AWB / AWR, 30 s, only the presenter's count
  is shown; more than 8 candidates: buttons for the first 8 by name. The clown is saved in `db.stats.clown`, gets
  the Crew-tab title "Clown of the Night" (only while award titles are on) and a `clown` trophy
  (`StatsDefs.EXTRA_TROPHIES`, from `db.stats.clownBySid`). The presenter's 30 s start once its AWV has left the
  send queue (viewers get the full time); a card (AWC) still waiting in the queue is replaced by the next one
  (`Comm.send` option `replace`). Exception to "no frames in combat": a viewer's AwardsShow frame may be built in a
  fight (a friend's AWS arrives) so its fight-end handler is registered; it is a plain frame (no secure templates),
  which the game allows. Built-in notes: Wanderer counts one run-off per group
  member left behind (a flight away from the group counts too; a hearthstone, portal, summon or releasing your
  ghost doesn't); Pauper needs 30 minutes played (a forgotten alt doesn't win it); with only one person, solo awards
  like Pauper always have a winner (same as the old awards); Snail ignores readings taken mid-ding.

## "Tell crew to update" button (owner approved 2026-11-05)

- Addons can't update themselves (no downloads, no file writes). Flow: owner says "release it" → GitHub release →
  friends' WowUp auto-update (each friend turns it on once) → owner presses **Tell crew to update** in `/tc`
  settings → online crew get a pop-up "Twiz says vX is out" with a **Reload now** button (`ReloadUI()` on click) and
  "If nothing changed, open WowUp and click Update first". Updates that add files or change the `.toc` say
  "restart the game" instead.
- Settings window lists every crew member's version with ✓ / ✗.
- Safety (Claude's call): a copy only accepts the request from someone whose version is newer than its own.
- Needs publishing first (owner's go-ahead + final name) before it does anything useful.
- **Built (2026-11-05), not tested in game, not published.** Plan, Claude's calls and every change made while
  building: `docs/superpowers/plans/2026-11-05-update-button.md`. In-game checks: `docs/TESTING.md`, section
  "Tell crew to update" button. Built on the local branch `update-button`.
- **Releasing (for Claude):** only when the owner says "release it". Bump `ADDON_VERSION` in `TwizCrew/Core/Init.lua` and `## Version` in
  `TwizCrew/TwizCrew.toc` together (a test checks they match). When a release adds or removes files or changes the
  `.toc` in any other way, also set `RESTART_SINCE` (same file) to the new version, and say "restart the game" in
  the release notes. Commit, then run `scripts/release.sh "notes for friends"`: it checks versions and tests,
  builds `TwizCrew-<version>-forever.zip` (WowUp picks a zip ending in `-forever`) plus `release.json` (flavor
  `forever`), tags `v<version>`, pushes `master` and creates the GitHub release. Then the owner can press **Tell
  crew to update**.

## Decisions (owner)

- **Goal:** slowly build "the ultimate addon" for the owner and a small group of friends, useful for playing
  together and fun. Grow it bit by bit.
- **Modular:** players can turn parts on and off.
- **Two tiers:** the parts that must be there (essentials) are kept apart from the nice-to-have extras.
- **One button sets everything back to defaults.**
- **Settings: Basics and Advanced tabs (2026-11-07):** "too many advanced features... not so daunting". The window
  opens on Basics (transparency, size, row style, panel on/off, offline friends, lock, hide in fights, pop-ups,
  auto-away, minimap button); Advanced lists everything.
- **Clown of the Night rules (2026-11-09, owner):** the title lasts "until the next show": every vote result
  replaces it (a winner: those names; "No clown tonight." or Skip: no clown); an all-time show (no vote) leaves it
  alone. The trophy for a session goes to the last clown actually voted in that session; a later no-clown or
  skipped vote in the same session clears the title but doesn't take the trophy away. Each copy saves what it saw,
  so clown titles and trophies can differ between friends when some didn't see the reveal (accepted).
- **Quests and the row menu (2026-11-07):** each copy shares the quest you're on (qn / qo / qc: the one whose
  objectives moved last, else the first watched; never C_SuperTrack, see test_lint). Rows show "Quest (3/8)" with a
  ! or ?, hover adds where, quest objectives, status and distance; right-click a row for Whisper, Invite, Inspect
  (when near), Point the arrow, Mock (when dead), Add to friends. Switches: Show quests, Share my quest (Panel).
- **Advanced sub-tabs (2026-11-07):** "way too much stuff and takes forever to drag to the bottom". Advanced has
  sub-tabs: Panel, Roasts, Pop-ups, Find, Crew, Test, and All (the old single page).
- **AFK lives in the panel only (2026-11-07):** the AFK button and `/tc afk` tell the crew, never set the game's own
  AFK flag ("i dont need the game to set the afk flag"); the game's `/afk` shows the same way. No AFK pop-ups ("just
  do it within the panel"): the AFK tag, a "zzz" on the portrait and a faded row. Auto-away after 3 idle minutes
  (setting). Look (2026-11-07): rows in the class color, gold XP bar that brightens as it fills, icons on tags.

- **Quality of life, v0.1.12 (2026-11-08):** "What's new" window (UI/Changelog.lua: HISTORY, newest first, one entry
  per release; opened by clicking the panel title, /tc new, Settings Basics; a blue "New in vX" line shows once after
  an update, never on a new install). The panel lists only online friends plus your own row by default; offline
  friends sit behind an "Offline (N)" bar at the bottom (click to open; remembered, same as Show offline friends).
  Fade default 50% ("its already too transparent"). Pop-up "Frostie is online" (Pop-ups: Friends coming online, on):
  not during the login quiet time, not when they were gone under 2 minutes (a /reload), several at once share one,
  click = whisper. Older saved settings were switched once (db.panelSince0112).
  v0.1.13: the What's new line always stays (dim once read: "so people can always see it"); my own row off again
  ("too much clutter", db.panelSince0113); my options (Me: set my status, Me: go AFK) are on every row's right-click
  menu, the place for future "me" actions.
- **Congrats button and Tools (2026-11-08):** a Congrats button on a friend's row for 5 minutes after they level up
  (also: clicking their level-up pop-up, "Congratulate them" in the row menu). It rides on MOCK with k = "g" (older
  copies show a plain line); the friend sees the sender's character /cheer (animation 68) with the level-up fanfare.
  Switch: Roasts, Congrats button. The standalone RankUp addon was merged in as module "rankup" (Tools/RankUp.lua,
  Settings Advanced sub-tab Tools and a Tools part on Basics, /tc rankup, panel menus, optional on-screen button).

- **Spell helpers (2026-11-08, v0.1.20, owner: "build it"):** module "spellhelp" (Tools/SpellHelpersLogic.lua pure,
  Tools/SpellHelpers.lua). A window (wrench menu, /tc spells) lists every spell you know, bar spells first, with
  three switches each: Newest rank (default on; off = the rank updater skips it), Smart target (default off; a
  harmful spell at a friend hits the friend's target, a helpful one at an enemy lands on its target or you),
  Switch target (with smart: /assist, so that unit becomes your target). Each column has all on / all off and an
  (i). Smart target = a character macro: `#showtooltip` +
  `/cast [@target,harm,nodead][@targettarget,harm,nodead][] X` or `/cast [@target,help][@targettarget,help][@player] X`
  (switch: `/assist [help,nodead]` / `/assist [harm,nodead]` first); cast by name = always the top rank, unless
  Newest rank is off, then `X(Rank N)` (the rank its macro had, else the top one). Macro named after the spell
  (16 letters, no rank in new names). Only this character's macros (deleting account macros could break alts'
  bars), only ones whose text is exactly ours are changed or deleted. Runs out of combat, at login and after
  learning. Choices per character in TwizCrewDB.spellHelp. Learning a spell or rank: a pop-up (Popups.notice) with
  its Newest rank / Smart target state; click = the window at that spell. Played in game by the owner.
- **Spell helpers never touch the bars (2026-11-08, owner):** the first version put each macro into the spell's bar
  slots by itself, re-checked all 180 slots (form bars and extra pages too) after every bar change, and deleted
  macros it thought unused; the owner had to rearrange their bars (wrong bars, bear bar messed up). Now it only
  makes, edits and deletes its own macros; a Macro column in the window has a drag icon per spell (click or drag =
  the macro on the cursor), and the owner places them. A macro keeps its name when its text changes, so it stays
  on the bars. Turning Smart target off deletes the macro (the game empties its slot); the spell isn't put back.
  Basic Action Update (also installed) swaps ranks on the bars too.
- **Running-off alarm is silent (2026-11-08, owner):** "I don't mind a visible indication but not a sound". The
  flashing row arrow, the pop-up and the big arrow stay; its raid-warning sound and the "With a sound" setting are
  gone, and the running-off pop-up doesn't play the general pop-up sound either.

- **Crew calendar, step 1 (2026-11-08, v0.1.16):** module "calendar" (Calendar/CalendarLogic.lua pure, Diary.lua
  data and swaps, CalendarUI.lua window). Each copy writes its own diary: 15-minute slots online (and AFK) per UTC
  day, 30 days kept, keyed by a random id per WoW account (alts = one person). Swaps are pull-only: CALD digests
  (slots known per person) to everyone every 10 min and to a friend who comes online; whoever knows less asks once
  (CALQ) and gets CALP (one field per day, repeatKeys i). Masks merge by OR, so order never matters; nobody can write
  your own diary. Views: Month, a day's timeline (AFK lighter; each stretch's times written on the row, hover = who was on at that moment, wheel scrolls past 9 people; the month tooltip lists each person's times; a class icon starts each bar; click a row = their Usual grid), Usual times (weekday x hour grid over 4 weeks, for everyone or the people picked from the list (one = their class color, several = how many of them on + their best time together; "See real weeks" = a past week, who was really on hour by hour, arrows step weeks, click a square = that day; day view has "This week as a grid"), best
  time to play together, habits). Open: wrench menu, /tc cal. Switch: Share my play times. Step 2 (next): events
  (dungeon runs) with sign-ups, roles, reminders and "invite everyone going", stored and swapped the same way.
  Notes (v0.1.17, Calendar/Notes.lua): click a day, type a note, pick one of 16 icons; shared via CALN (sent to
  everyone on add/delete; the CALD digest carries nh, a checksum, and a different one pulls all notes with CALQ n=1).
  Key = author id + created time; only the author deletes (a deletion marker spreads); kept 90 days. Icons were also
  added to the menus, pop-ups and settings rows ("use icons where it makes sense").
  Timed notes keep "at" (UTC seconds); each viewer sees it at their computer's local time and date (never the
  server's: friends abroad on US realms get their real time). "+ Create note" window: day, hour/minute or no time,
  note / dungeon / raid (Notes.DUNGEONS; g on the wire), icon, words. A dungeon note fills its month cell with
  artwork: tries the Encounter Journal button, group finder icon, loading screen files in turn (SetTexture false
  = missing), else the note's icon. Not seen in game yet which of those files exist on Forever.
  Note window (Calendar/NoteView.lua): click a note (day list or timeline icon). Going / Maybe / Can't make it,
  "seen by" (marked when a friend opens it), comments. Replies are CALR records keyed "<note>|s|<id>",
  "<note>|r|<id>" (one answer per person, newest wins), "<note>|c|<id>-<time>"; counted in the notes checksum so
  they swap like notes. Dungeon picker: recommended levels (Notes.DUNGEONS min/max/size), lowest first, colored
  for your level, group finder icon when the file exists.

- **v0.1.18 quality of life (2026-11-08):** key bindings (Bindings.xml + TwizCrew_Binding in Commands.lua, under
  AddOns in the game's Keybindings); minimap right-click = a menu (panel, a note, the wrench's tools, settings; the
  addon compartment's right-click still toggles the panel); quick statuses in the status box; "Also on it" in a
  friend's tooltip (same quest ID, else name; "you" too); Today's recap (UI/Recap.lua, module "recap": own numbers
  since login, shown on PLAYER_CAMPING / PLAYER_QUITING and with /tc recap; mocks/congrats counted via ABOUT_ME).

## Ideas so far (not decided)

- **Friend radar:** a small panel with each friend's level, zone and what they are doing.
- **Pokes and soundboard:** send a friend an air horn, a "LOL", a jump scare or a big emoji on their screen.
- ~~**"Come here" ping**~~: built as Find the crew's meet-ups (2026-11-07, see "Where we are").
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
  Channels: `PARTY`, `RAID`, `GUILD`, `WHISPER` (one person), `CHANNEL` (a custom chat channel; on WoW Forever
  these are never delivered, see below).
- Save its data between sessions (SavedVariables, written at logout or `/reload`).

**Cannot / limits:**
- **No playing for you:** it cannot move, cast, or target on its own. Every action needs a key press or a click.
- **Short messages, few per second:** about 255 characters per message, and the game throttles bursts (send a few
  per second at most; queue the rest).
- **One message is several sends (TwizCrew, 2026-11-09):** in automatic mode `Comm.send` sends one copy per
  destination (the group, a whisper to each channel member outside it, and the channel), all through the ~2 a
  second queue. A live feature must keep its message count low (or replace waiting ones), or it falls behind.
- **A brand-new custom channel refuses addon messages for a moment (seen in game, 2026-11-05):** on the owner's
  first login TwizCrew created `TwizCrewHQ`, and the sends in the same second as the join came back with result 7
  (very likely `InvalidChannel`). On the next login every send worked. TwizCrew now waits out refusals for 10 s
  after a join and tries a failed channel again after 1 minute (then 2, 4, 5 min…); details in the crew-panel plan.
- **Sender names come in two forms (seen in game, 2026-11-05):** channel senders and `UnitName("player")` are
  just the name ("Yaboytwiz"); party and whisper senders came as "Yaboytwiz Noodledog" (the WTF character folder
  is `91/Yaboytwiz-Noodledog`). TwizCrew now uses the name before the first space or hyphen everywhere.
- **WoW Forever never delivers addon messages sent to a custom channel (seen in game 2026-11-06, and reported by
  other addon makers: [Blizzard forum](https://us.forums.blizzard.com/en/wow/t/add-on-messages-are-blocked-in-chat-channels/2403369),
  [BFF addon fix](https://github.com/Shtian/bff-wow/pull/133)):** the send says it worked, but nobody gets it,
  not even the sender. That is why friends saw each other as offline (v0.1.4 and older). Joining the channel, its
  member list (`ListChannelByName` → `CHAT_MSG_CHANNEL_LIST`) and join / leave notices still work, and addon
  whispers arrive. So since v0.1.5 the channel is used to see who is in it; automatic mode whispers each member
  (the full name the game gives, e.g. "Yaboytwiz Noodledog"), sends to the group when grouped, and still sends one
  copy to the channel in case the game delivers it again. Copies of v0.1.4 or older can hear a newer copy but not
  be heard. `/tc report` shows "Crew in the channel" and "Channel echoes heard" (0 = the channel still does not
  deliver).
- **NPC layer keys don't identify a layer on WoW Forever (seen in game 2026-11-07):** the owner and Chaos stood
  together in Darkshore on one layer, and TwizCrew read key "1" for the owner and "11" for Chaos from the zone part
  of NPC GUIDs. Forever Layer Hop's code says the same: since build 70450 two clients on one layer can get
  different zoneUIDs, and equal ones aren't proof either. So since v0.1.6 keys are still shared (for `/tc report`)
  but never decide anything. A friend counts as **same layer** when the game shows them (party unit
  `UnitIsVisible`, or their nameplate is up), and **different** when they are in our group, within 40 yards by
  `UnitPosition`, and hidden for 8 s. Otherwise the last verdict stands while both stay in the zone; never seen
  = unknown (no tag). Ghosts are skipped (the living can't see them on any layer). Not yet checked in game:
  that `UnitPosition` works on party members in Forever.
- **Boss fights:** addon messages are reported to be **blocked during a boss fight** inside dungeons and raids. Plan:
  queue them and send after `ENCOUNTER_END`. The rest of the dungeon (trash, between pulls) is reported to work.
  Your own screen can still show things during a boss fight.
- **"Secret" combat numbers:** during combat, health, buffs and enemy info can come back as secret values: you
  can show them (pass them straight to a status bar) but not compare or do math on them. Check with
  `issecretvalue()`.
- **Seen in game (2026-11-08): inside a dungeon even `UnitIsAFK("player")` is secret,** and `if x then` on it errors
  ("attempt to perform boolean test on a secret boolean value"). That error every redraw switched the Crew panel
  off mid-dungeon (3 errors in 60 s turns a module off until /reload). Every yes/no from a game function must be
  run through `issecretvalue` first (Tags' `try`, Stats' `player`, Report's `call` do this now). The log keeps 500
  lines, so a flood of one error pushes out the earlier ones.
- **No combat log** for addons in Forever (reported); Blizzard ships its own damage meter and cooldown tracker.
- **No internet, no files, no other programs.** The only thing it writes is its SavedVariables file. A program
  outside the game could read that file after a `/reload` (e.g. for a stream overlay).
- **The game's calendar works on the server, its window is switched off** (research 2026-11-08, from the code
  and notes of Ultimate Calendar v1.9.2, CurseForge 1339939, which supports Forever; not tried by us):
  Forever ships Blizzard's calendar code (`C_Calendar`) with no window. Ultimate Calendar draws its own window
  and creates real server-side events through it, seen working on Forever by its author 2026-10-20. Guild
  events (`C_Calendar.CreateGuildSignUpEvent`) are stored by Blizzard and seen by the whole guild with the
  creator offline. That is the way to plug the "note made while nobody else was on" gap once the crew has a
  guild: post the note as a guild event, read the guild's events back in. Limits: title 31 bytes,
  description 255 bytes; only today up to `C_Calendar.GetMaxCreateDate()`; `AddEvent` / `UpdateEvent` are
  marked restricted, so they are saved on the player's own click (the Create note button). Any member can
  create guild events in Classic (no permission); guild event invites have been broken since Classic
  1.15.3; characters outside a guild may only see changes after a relog. Comments and play times stay
  peer-to-peer (too big).
- Some interface changes are **locked during combat** (`InCombatLockdown()`): wait for `PLAYER_REGEN_ENABLED`.
- **Lua 5.1**, Blizzard's version: no `goto`, no `//`, no bit operators (use the `bit` library), no `require`,
  `io` or `os`. The `.toc` file lists the files to load.

## Technical facts

- **Interface number: `16001`.** Confirm in game: `/run print((select(4, GetBuildInfo())))`.
- **TOC file:** `TwizCrew.toc` with `## Interface: 16001`. A Forever-only file may be named `TwizCrew_Forever.toc`
  (the Warcraft Wiki also lists `_Camelot` as an older alias). Questie and Quest Master ship both.
- **Use modern API names:** `C_Spell`, `C_Item`, `C_ChatInfo`… Old globals like `GetSpellInfo` / `GetItemInfo` were
  reported missing.
- **`.gitignore` used to say `tools/`, which on Windows (case-insensitive) also hid `TwizCrew/Tools/`:** RankUp and
  Spell helpers were never committed, so releases (built with `git archive`) lacked them. Fixed 2026-11-08 to
  `/tools/` (only the top-level Lua folder). On Windows the tests run with `tools/lua51/lua5.1.exe tests/run.lua`.
- **The owner's Windows PC (2026-11-08):** the game is at `C:\Program Files (x86)\World of Warcraft\_forever_`, account
  folder `WTF/Account/TWIZTIDFURY`. There `Interface/AddOns/TwizCrew` is a plain copy (not a link to the working
  copy), so changes reach the game only when copied there (or through a release).
- **Where the game is on this PC:** Lutris (Flatpak) → Battle.net (on GE-Proton11-12) → WoW Forever.
  AddOns folder:
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`
- **Already installed there:** Questie 12.6.3 + QuestieDB 1.0.12 (GitHub Questie/Questie bundle release),
  QuestMaster 2.74.0 (CurseForge project 1427310 "Quest Master - Forever"; both updated by hand 2026-11-07), OpenMap (v0.7.5-beta from
  https://github.com/openmap-world/openmap, installed by hand 2026-11-05; conflicts with Leatrix Maps, Mapster and
  Magnify), What's Training? Forever (v1.1.1 from CurseForge project 1701676, by hand 2026-11-05),
  DungeonJournal (ForeverDungeonJournal v1.6.7, CurseForge project 1707971, by hand 2026-11-05),
  Spoken 3.8.3 (AI voiceover, https://github.com/rusty-key/spoken-wow, 6 addon folders + 7 English voice-pack
  folders, about 2.6 GB, by hand 2026-11-05),
  Lore Forever 1.1.0 (CurseForge project 1715510, addon + male English narrator packs, no quest-dialogue packs
  because Spoken voices quests, by hand 2026-11-05),
  DialogueUI 1.0.7 b (Peterodox, CurseForge project 989270, by hand 2026-11-05),
  DialogKey - Numy Edition v1.2.62 (https://github.com/NumyAddon/DialogKey_Numy, by hand 2026-11-05),
  Basic Action Update 0.0.2 (TxRx, CurseForge project 1779962, `/bau`, puts the highest rank of each spell on your
  bars, waits until a fight ends; by hand 2026-11-06), and **TwizTracker** (a small starter addon Claude wrote:
  `/twiz` shows XP per hour, time to level and gold this session; not yet tested in game).
- **WowUp-CF 2.25.4 installed (2026-11-05, owner asked):** `~/Applications/WowUp-CF-2.25.4.AppImage`, menu entry
  `~/.local/share/applications/wowup-cf.desktop`. Its auto-detect misses our Flatpak-Lutris game, so Claude wrote
  the WoW Forever install (client type 10, path to `_forever_/Wow.exe`) into `~/.config/WowUpCf/preferences.json`. Never add
  TwizCrew to it on this PC (TwizCrew is a symbolic link to the working copy, below).
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

- **Mock show (built 2026-11-07, not yet seen in game):** a friend's mock about you shows their character laughing
  (animation 70) in a speech bubble pop-up (UI/MockShow.lua). Picture, best first: live (`SetUnit` on a visible
  party unit or nameplate), remembered (a model loaded with `SetUnit` while they were near, kept shown off screen for
  the session; lost on /reload), stand-in (`SetCustomRace` + `TryOn` from the shared `lo` field: race, sex,
  visible gear item IDs), class icon. Face, hair and skin can't be read or set by addons (owner asked; explained).
  Check in game with Try it out: Try a mock (live / icon), which say when a mode falls back.
  **Stand-in dropped (owner, 2026-11-07):** "the mock stand in doesn't look good, let's not use it". Forever has no
  `SetCustomRace`; the race-model fallback (`SetDisplayInfo`) wasn't worth it. `lo` now carries race and sex only (the
  laugh voice: `PlaySoundFile` with the race's laugh file ID from the community listfile).

- Addons can show **game** models: `PlayerModel`, `DressUpModel`, `ModelScene` actors. Units (`player`, `party1`,
  `target`) only when that player is loaded nearby; far away they show blank.
- Any creature by display ID; any item tried on with `DressUpModel:TryOn`.
- A far-away friend's look can only be **approximated**: a stand-in body of their race wearing their item IDs (sent
  over addon messages). Face, hair and skin cannot be set. No existing addon does the far-away version.

## Working with the owner

- Plain words, short messages, one question at a time. The owner often types from a phone: read for intent, not typos.
- No multiple-choice pop-ups; ask in plain words.
- **Text and icons a little bigger everywhere** (owner, 2026-11-08: "the font and the icons need to be a bit
  bigger... across the board"): Theme.FONT is the game's two fonts + Theme.TEXT_GROW (1.5) points, and icon
  sizes go through Theme.icon(n) (x Theme.ICON_SCALE, 1.2). New UI uses both; windows keep their size where
  they can (the panel grows a little taller: row lines are 15 px).
- **Every option that isn't super obvious gets an (i) button** (Widgets' info button) saying what it does and
  why you'd want it, with an example. Easy to find and click. Owner, 2026-11-08: "everything that isn't super
  obvious needs this".
- The owner streams (OBS + Discord). Anything on the game screen is on stream.
- The repository is public (owner's go-ahead, 2026-11-05), but each new release still waits for the owner's
  "release it". Pushing work-in-progress commits to GitHub also waits for that.

## Sources

- WoW Forever addon developer guide (fan site; most limits there are from beta testing):
  https://wowforeverguides.com/addons/developers
- Warcraft Wiki, TOC format: https://warcraft.wiki.gg/wiki/TOC_format
- Midnight (12.0) notes for addon makers (boss-fight message block): https://wow-midnight-addon-template.vercel.app/midnight/
- Icy Veins, combat addon restrictions eased in Midnight:
  https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/
- Questie (Forever support, interface 16001): https://github.com/Questie/Questie/releases
