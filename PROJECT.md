# TwizCrew: a WoW Forever addon for me and my friends

> **Final name: TwizCrew** (owner, 2026-11-05). Public repository: https://github.com/YaBoyTwiz/TwizCrew

## What we are making

An addon for **World of Warcraft: Forever** that only my friends and I use. Every friend runs a copy, and the
copies **talk to each other**: they share information (who is where, what they are doing) and **trigger effects on
each other's screens** (a sound, a picture, a message, an arrow on the map).

Other players never see any of it. The messages are hidden addon messages, not chat. Since 2026-11-21 the crew is
the owner's **guild**: copies talk through the guild and only guild members are trusted.

## Where we are (started 2026-11-05, newest entry first; each entry carries its own date)

- **v0.4.2 released (2026-11-23, owner: "release it"):** the quest window (quests by zone, ticks, one ask for
  several) with its review fixes. Released without an in-game try. It adds two files, so `RESTART_SINCE` is 0.4.2.
- **Quests by zone, ticks and one ask for several (2026-11-23, owner: "its nice that we can see all quest but its hard
  to know what quest to ask for when looking at someones quest because they are all together. is it possible to filter
  them by zone ... also can we put like a check box system that will let the user check a box beside all the quest
  they want requested and then press the button this way they can cherry pick the quest"; approved the written
  description: "yes build it"):** "Their quests" now opens a small window: their quests under the zone headings of
  their quest log, my zone first, a check box per quest I can get, "Tick this zone", "Only this zone", and one button
  "Ask for 3 quests"; the friend gets ONE pop-up and their copy shares the quests one at a time. On the branch
  `pin-party`, **not released, not seen in the game. It adds 2 files (`Crew/QuestAsk.lua`, `UI/QuestWindow.lua`), so
  the next release must set `RESTART_SINCE` to its own version (the game must be fully restarted).** Details: section
  "Quest list (2026-11-22)" below, from "Quests by zone"; checks: `docs/TESTING.md`, "Quests by zone and asking for
  several".
- **v0.4.1 released (2026-11-23, owner: "release it when its done"):** the "Classic only" change below, nothing
  else. Released without an in-game try. No files added, so `RESTART_SINCE` stays 0.4.0.
- **Classic only (2026-11-23, just after v0.4.0; owner: "For crew let's use Classic as the default and remove the
  other themes."):** Crowned crew and Tavern night, their art and the theme picker are removed; Classic (the game's
  own art) is the only look. The icon set stays exactly as it is (the owner likes the icons). A `theme` saved by
  v0.4.0 is deleted at start. On the branch `pin-party`, **not released, not seen in the game; files were only
  removed (no new ones), so a `/reload` is enough.** Details: section "Themes and icons (2026-11-23)" below; checks:
  `docs/TESTING.md`, same name.
- **v0.4.0 released (2026-11-23, owner: "release the update"):** everything built after v0.3.0 on the branch
  `pin-party`: the party pin fix, the fixes from the review of v0.3.0, tips and the About page, the away and welcome
  cards, the crew tab with the after-fight summary and the Activity tab, see-through when idle, simpler settings, the
  three themes and the icon set, and the two probes `/tc caltest` and `/tc chattest`. **Released without an in-game
  try of any of it**: the "not released, not seen in the game" notes in the entries below are from before the
  release. First things to learn from the crew: does the game load the icon art, and is anything upside down
  (`Theme.FLIP_ART`). It adds files and pictures, so the game must be fully restarted (`RESTART_SINCE` is 0.4.0).
  Two of its three themes were removed again the same day: "Classic only" above.
- **Themes and icons (2026-11-23, owner picked from mock-ups: three themes, Classic, Crowned crew (the default) and
  Tavern night, chosen in the settings; a set of 55 icons; and the settings layout that waited for the look):** built
  on the branch `pin-party` and released in v0.4.0 (3 code files and 10 picture files, so a full game restart the
  first time). Crowned crew, Tavern night and the picker were removed right after (see "Classic only"); the icons
  and the settings layout stay. Details: section "Themes and icons (2026-11-23)" below.
- **Simpler settings (2026-11-23, owner: "some of the things in my addon might leave people with information
  paralysis ... just figure out what you would change"; approved Claude's proposal: "i think u can remove them",
  "yes start on all eight"):** about 45 fine-tuning switches removed, two groups merged into one choice each, plainer
  names, the test buttons in their own window, a short `/tc help`, trimmed menus, the What's new line only while
  unread. The window's six-tab layout came with the themes (see "Themes and icons"). On the branch `pin-party`, **not
  released, not seen in the game; no new files (a `/reload` is enough).** Details: section "Simpler settings
  (2026-11-23)" below; checks: `docs/TESTING.md`, same name.
- **The crew tab (2026-11-23, owner picked mock-up "E, Hidden tab" out of ten: "many of the guild mates want more of
  their screen back"):** the panel tucks away into a small tab on the screen edge; resting the mouse on it slides the
  whole panel out, news slides out one row at a time, and a wide "Keep open" switch at the top keeps it out like
  before. Replaces the minimize button. On the branch `pin-party`, **not released, not seen in the game; a file was
  renamed (`UI/PanelMini.lua` -> `UI/PanelTab.lua`), so the game must be restarted.** Details: section "The crew tab
  (2026-11-23)" below; checks: `docs/TESTING.md`, "The crew tab".
- **"While you were away" and the welcome card (2026-11-23, owner picked them from a research list: "i like the
  while u were away part. welcome card"; approved the written description: "yes do it"):** on the branch
  `feat-away-welcome` (on top of `pin-party`), **not released, not seen in the game; it adds 4 files, so the game must be restarted.** Details:
  section "While you were away and the welcome card" below; checks: `docs/TESTING.md`, same two names. Two ideas
  from the same list were dropped: "who still needs what" (the game has its own party quest progress tooltip:
  `C_TooltipInfo.GetQuestPartyProgress` exists in Forever 1.60.1, not seen on screen by us) and the dungeon prep
  check (not low-hanging: it needs a quest list per dungeon). A review the same day (code only) led to fixes, now in
  that section: crowds of joins or leaves are not believed (a list of only the online members can look whole), the
  snapshot is not lost while the card waits for the end of a dungeon, test fakes never hold a crown, my characters
  are matched in this guild only, the start card waits for an invite that comes after install, and the About page
  waits for it longer.
- **Tips everywhere and a "How to use TwizCrew" page (2026-11-23, owner: "can we create (i) or mouse over tooltips
  that explain what things are and do ... maybe also create an about tab ... keep it simple and be clear it might
  update in the future"; approved: "yes do it"):** about 60 things that did not explain themselves got a mouse-over
  tip (a gold title and one or two plain sentences): the panel's count, tabs, bars, headings, pin buttons, the
  status box; every row now has a tooltip (a guild member without the addon and an offline row too) with short
  lines saying what the row's marks mean; the Hall of Shame switch, tabs and Wipe Squad line; the Clown vote and
  Skip; most calendar buttons, a colour key under the Events month, the note window and the note maker; pop-ups
  whose click does something unsaid, the big arrow, the settings tabs, reset and choice buttons, My mocks. All the
  words are in `UI/Help.lua` (tested for length and no em dash); the helper is `Widgets.addTip` / `helpTip`. The
  About window (`UI/About.lua`, `ns.About.open/close/toggle`) is a short page in plain words that ends saying it
  will change. **Claude's call:** a window opened by a "?" button rather than a panel tab, because the panel is too
  narrow to read a page in. Ways in: the "?" after the panel's tabs (only while stats or the calendar is on, and
  when it fits), the wrench menu (so also the minimap menu), the settings window (a link at the top, next to What's new), `/tc about`, `/tc help`
  (also prints the command list; an unknown word still only prints the list). It opens once by itself on a new
  install only (no saved data at all: `db.aboutSeen = false`, account-wide; older data gets `true` silently), never
  in a fight or a dungeon or raid. In a guild the welcome card comes instead (about 30 s after login, with a "How to
  use TwizCrew" button) and the page does not also open; only when that card cannot show (no guild) the page opens
  by itself, about 20 s after login (About asks `Welcome.startOwed` every 15 s: while the card is not decided yet up
  to the card's own 2 minutes, while it is owed and only waits for a free moment for as long as that takes; the same
  "busy" rule as the cards; Claude's call: one window at first login). On the branch, **not released, not seen in the game; two new
  files, so the game must be restarted.** Checks: `docs/TESTING.md`, "Tips and the About page".
- **Review of v0.3.0, fixes (2026-11-23):** a review of the released code (never run in the game) found 8 defects;
  all are fixed on the branch `pin-party`, **not released, not seen in the game**. The quest list no longer floods
  the queue in a group (one group copy, newer replaces older; no whisper to a member who just got the group's copy;
  asks wait a few seconds), never announces more quests than it sends; hovering a row asks once. A note from my
  other install is never "new"; a note counts as mine by name only when the class matches too. The note window's
  time line stays one line; the calendar size is kept to the screen's height and keeps the window's middle in
  place; after only a /reload on an update that added a file, opening the calendar says to restart the game.
  Checks: `docs/TESTING.md`, "Calendar: edit and remove notes" 7-8, "Calendar size" 3, "Quest list" 11.
- **v0.3.0 released (2026-11-22, owner: "yes add it, and release"):** everything built on 2026-11-22 after v0.2.0:
  the calendar work (button and pulse, Events / Play times, time zones, edit and remove, bigger window, colored
  days) and the quest list with its heads-up and the "why a share was refused" message. **Released without an
  in-game try of any of it**: the "not tested in game, not released" notes in the entries below are from before
  the release, and their checks in `docs/TESTING.md` are still to do. `RESTART_SINCE` is 0.3.0 (new files).
- **All of a friend's quests, and a heads-up in a group (2026-11-22, owner: "do 1 and 3 in one pass"):** until now a
  copy only told the crew the one quest you're on, so that was the only quest a friend could ask for. Now a copy
  can ask a friend for their whole quest log and shows which of those quests you can get. Details: "Quest list"
  below. Same branch, **not tested in game, not released; it adds a file (Crew/QuestList.lua), so the game must be
  restarted, not only reloaded.** Check: `docs/TESTING.md`, "Quest list".
- **Calendar window bigger (2026-11-22, owner: "I would like the calendar by default to be bigger on the screen"):**
  the window is drawn at 125% of its design size (700 x 570), and "Calendar size" (70% to 180%) is a slider in the
  calendar's settings (`size`, read in Calendar.refresh). The note window and "Create a note" keep their size.
  Same branch, **not tested in game, not released.** Check: `docs/TESTING.md`, "Calendar size".
- **Event days are colored (2026-11-22, owner's idea, approved: "do it"):** on the Events month a day with
  something planned has a see-through color over its square and an edge in the same color; empty days stay dark.
  Gold = a plain note, blue = a dungeon run, purple = a raid (the biggest thing that day wins). Dungeon artwork
  stays as it was, now with the edge. Calendar/CalendarEvents.lua (`KIND_COLOR`, `TINT_ALPHA` 0.22, `EDGE` 2).
  Same branch, **not tested in game, not released.** Check: `docs/TESTING.md`, "Colored event days".
- **Calendar notes: edit, remove and a fuller right-click menu (2026-11-22, owner asked: "I can't remove a note ...
  let me right click on a date to create notes, edit and remove"):** on the same branch `feat/calendar-button`.
  **Not tested in game, not released.** Details in the section "Calendar: edit and remove notes" below; checks in
  `docs/TESTING.md` under the same name. He also asked whether notes can include images: not answered by a build
  yet (an addon cannot send picture files; only art already in the game or shipped inside the addon can show).
- **Calendar time zones by name, and the author's time on a note (2026-11-22, owner asked: "it's showing my
  timezone as UTC when I'm actually CST, make sure it uses the creator's real time zone"):** on the same branch
  `feat/calendar-button`. **Not tested in game, not released.** Details in the section "Calendar: time zones" below;
  checks in `docs/TESTING.md` under the same name.
- **Calendar split into Events and Play times (2026-11-22, owner asked, design approved in chat: "do this"):** on
  the same branch `feat/calendar-button`. Tests outside the game pass. **Not tested in game, not released.** It adds
  a file (`Calendar/CalendarEvents.lua`), so the game needs a full restart. Details in the section "Calendar: Events
  and Play times" below; checks in `docs/TESTING.md` under the same name.
- **Calendar button next to the tabs built (2026-11-22, owner asked, design approved in chat: "do it"):** on the
  branch `feat/calendar-button`, on top of v0.2.0. Tests outside the game pass. **Not tested in game, not released**
  (no version bump or Changelog entry yet: they come with "release it"). Details in the section "Calendar button
  next to the tabs" below; checks in `docs/TESTING.md` under the same name.
- **v0.2.0 released (2026-11-22, owner: "release it"):** the guild conversion (section "Guild conversion
  (2026-11-21)"). Released after one clean session on the owner's main; two copies of the new version talking over
  the guild is still unproven. `RESTART_SINCE` is 0.2.0.
- **After v0.2.0, not released (branch `pin-party`, 2026-11-22):** the owner could not pin someone in their party
  (a party row had no "+"; the Find-the-crew arrow sat where it would be). A party row now has the "+" and the
  right-click entry "Pin to main view" like every other row. Not yet seen in the game.
- **First run in the game (owner's main, 2026-11-22, read from the saved log and `/tc report`):** the final guild
  code loaded with no errors or problems. The game gives the guild's name; old data attached by itself and the old
  friends were pinned; the guild list came with offline members (8 members, 3 online) and names with first and last
  word. `/tc guildtest`: guild send accepted and our own echo came back (as the full name), so `GUILD` addon messages
  are delivered; nobody answered because nobody else has this version. A friend still on the released v0.1.24 was
  heard normally (positions, stats, state) and showed online, so old and new copies still reach each other at least
  for a guild member in the party. Still unproven: two copies of the new version talking over the guild. The one
  error in the log (`Crew.lua:331`, 20:02 on 2026-11-21) came from the game loading files in the middle of the build.
- **Guild conversion built on the branch `guild-conversion` (2026-11-21).**
  The copies now talk through the guild, trust only guild members, keep the crew's data per guild, and the panel has
  sections and pins. The whole-branch review and its fix wave are done. Everything is in the section "Guild
  conversion (2026-11-21)" below, including what is still open. Released as v0.2.0. The first thing to do in the game is
  `/tc guildtest` (`docs/TESTING.md`, "Guild conversion").
- **v1 design approved by the owner** (2026-11-05): `docs/superpowers/specs/2026-11-05-crew-panel-design.md`.
- **Build plan:** `docs/superpowers/plans/2026-11-05-crew-panel.md`. The build was handed to a background agent at
  the owner's request ("do this work on a different agent").
- **v1 is built (2026-11-05):** every test outside the game passes (`tests/run.sh`, including a simulation of two
  and three copies talking to each other). **Not yet tested in game, not published.** What the owner can try in
  game, riskiest first: `docs/TESTING.md`.
- **Stats board built too (2026-11-05):** Hall of Shame tab, live roasts, `/tc awards`. Not tested in game, not
  published. Details in the "Stats board" section below.
- **v0.1.24 released (2026-11-12, owner: "release it"):** the minimize / activity feed work and the hardening pass
  (sections below). Released without an in-game try; `RESTART_SINCE` is 0.1.24. The "not tested in game, not
  published" notes in those two sections are from before the release: the in-game checks in `docs/TESTING.md` are
  still open.
- **Minimize, activity feed, peek and chat lines built (2026-11-11, owner left the design to Claude):** released in
  v0.1.24, not tested in game. Details in the section "Minimize, activity feed, peek and
  chat lines" below.
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
- **The crew (owner):** all on the **same realm and same faction**. Until 2026-11-21 there was **no guild**, so the
  copies talked over a hidden custom channel (Claude's call, 2026-11-05) and whispers. **Update (owner, 2026-11-21):
  the owner is now a guild master.** The guild is the owner's gaming buddies and stream regulars, small, may grow a
  little, and TwizCrew now talks through it. What was decided and built is in the section "Guild conversion
  (2026-11-21)" below; the research on what the game allows is in "What an addon can and cannot do". Ideas for using
  the guild further (the Guild Board, guild-wide Hall of Shame and news) are designed only in outline there.
- **Crew size (owner):** about **5**, probably more over time. Build the panel for ~5 but let it grow (scroll or a
  compact view past ~8; Claude's call).
- **Crew panel can be hidden (owner)** but is **on by default**. Give it **plenty of settings** so people tailor
  it to their comfort instead of turning it off. **Reversed in part 2026-11-23** (owner: too many settings leave
  people with "information paralysis"): about 45 fine-tuning switches are gone, see "Simpler settings (2026-11-23)".
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

## Minimize, activity feed, peek and chat lines (2026-11-11)

**Replaced in part on 2026-11-23 by the crew tab** (section "The crew tab (2026-11-23)"): the minimize button, the
minimized bar, its notices, the peek and "open while my mouse is on the bar" are gone; the bullets below about them
are history. Still true here: the activity feed, the chat lines, the Recent window and the test tools' buttons.

- **Why:** a friend said the panel clutters the screen (wants to minimize it, still get useful information, and open
  it again easily). The owner also wants a record in chat of what happened (e.g. what someone said in a congrats).
  The owner approved building it and left the design to Claude ("use your best judgement"). **All the decisions below
  are Claude's calls.**
- **Built (2026-11-11), not tested in game, not published.** Tests outside the game pass (`tests/run.sh`; new files
  `tests/test_feed.lua`, `tests/test_minimize.lua`). In-game checks, riskiest first: `docs/TESTING.md`, section
  "Minimize, activity feed, peek and chat lines". **The release needs `RESTART_SINCE`** set to the new version: three
  files were added (`UI/FeedLogic.lua`, `UI/Feed.lua`, `UI/Recent.lua`) and `TwizCrew.toc` and `Bindings.xml` changed.
  No version bump, changelog entry or release yet (the owner says "release it").
- **(History, replaced by the crew tab) Minimize (Panel, PanelLogic.view):** a minus / plus button at the far right of the title bar, `/tc mini` (also
  `/tc minimize`), the key binding "Minimize or restore the crew panel" (`TWIZCREW_MINI`), and a "Minimize the panel" /
  "Restore the panel" entry in the title bar's right-click menu. Minimized = just the header (24 px, same width,
  same corner): title, the online count, the missed number and the button; the AFK, tools and settings
  buttons and the update and What's new lines are hidden. Clicking the title restores it (when minimized the title no
  longer opens What's new, since that line is hidden then). Saved as the panel setting `minimized` (so **Reset to
  defaults brings the panel back**). For a panel that grows up, the saved y while minimized means "where the bar is",
  so the bar does not jump when it opens or closes (`PanelLogic.yAfterMinimize` etc.). The header got 20 px
  narrower for the title in the full view (one more button): in Compact and Tiny rows the version and the long count
  go sooner. **Not looked at in game.**
- **Activity feed (`UI/FeedLogic.lua` pure rules, `UI/Feed.lua` game side, module "activity"):** newest 50 events in
  `ns.db.feed` (kept by Reset to defaults), each `{ kind, who, at (wall clock), line, dir, zone, subzone, level, words,
  other, class }`. Kinds: online, offline, died, levelup, congrats, mock, roast. It listens to the roster's
  `MEMBER_ONLINE / OFFLINE / DIED / LEVELUP` (the sources the pop-ups listen to) and to two new bus events fired by
  the roasts module only when something is shown on this screen: `MOCK_SEEN (sender, target, words, cheer)` and
  `ROAST_SHOWN (sender, text)`. The gates copy the pop-ups': 30 s login quiet time for online / offline / died /
  level-up, and "back online within 120 s of going offline is a /reload, not news" (same numbers; Popups keeps its own
  copy). **What a copy knows about a congrats or mock (the MOCK message, `k = "g"` = congrats):** the sender, who it is
  about (`t`), and the finished text (`x`, at most 120 letters, the built-in or the sender's own line with the
  placeholders filled in). There is no emote and no level in the message, so the feed shows the words only. A death
  carries only the zone and subzone (the cause guesses -- fall, drown, weak mob -- travel as separate ROAST messages,
  which the feed logs as "roast" lines), so a death line has the place, not the cause. Mocks and congrats about
  *other* friends that show on my screen are logged too (dir "seen"). Text goes through `ns.Util.safeText` and a
  `issecretvalue` guard; the test tools' fakes are kept in memory only (never saved, gone with Clear test stuff).
- **(History, replaced by the crew tab) Bar notices (Panel):** while minimized, online / died / level-up (when the matching pop-up switch is on) and
  congrats / mocks sent to me replace the count on the bar for 6 s (3 s when two or more wait behind it), the friend's
  name in class colour, with a gold glow that fades in 1.6 s. Further events queue (8 waiting at most, the oldest
  waiting one is dropped past that). A red number on the bar counts the events since the panel was last open;
  restoring clears it, and so does opening the list from it. Clicking the notice does what the pop-up would
  (level-up: congratulate; online: whisper; others: open the list) and moves to the next.
- **(History, replaced by the crew tab) Peek:** setting `peek` (default on, `peekSeconds` default 5): with each notice that starts, the panel drops open
  under the bar with only that friend's row (so the Congrats button is on it after a level-up), then closes. The mouse
  on the panel (or on one of its menus) keeps it open until it leaves. Never in a fight: a peek due in a fight is
  dropped (the plain-text bar notice still shows, since the panel's own frames already change in combat), and a fight
  closes a peek. `barHover` ("Open while my mouse is on the bar", default off): hovering the bar shows the full panel
  until the mouse leaves.
- **(History, replaced by the crew tab) No doubling up:** `barInstead` (default on): while minimized, and only while the bar is on screen and the activity
  feed is on, the online / died / level-up pop-ups are not made (so there is no pop-up sound either). Everything else
  (layer pop-ups, roasts, meet-ups, quest shares) still pops up. Not minimized: exactly as before.
- **Chat lines:** `activity` module settings: master `chat` (default on) plus one per kind. Defaults: died, level-up,
  congrats, mock on; online, offline, roast off (the game already prints logins). Local only (`DEFAULT_CHAT_FRAME`
  `:AddMessage`, else `print`; never `SendChatMessage`), prefix "TwizCrew:" in gold, names in class colour. Printed
  whether or not the panel is minimized.
- **Recent window (`UI/Recent.lua`):** 10 rows, newest first, class icon (or a picture of the kind), "5m ago", the
  line; mouse wheel scrolls; hover shows the clock time. Opened by the missed number, `/tc recent`, the wrench menu
  ("Recent activity") and a button on the Activity feed settings. Built the first time it is opened and not in combat
  (in a fight the first open says so and waits).
- **Settings:** Basics got Minimize the panel (now Keep open), Peek at the friend (now Slide out news) and Write
  events in my chat. The rest are on
  Advanced, Panel (the panel's and the new "Activity feed" module's switches), each with an (i) text.
- **Test tools:** Ding, Death pop-up and Roast already ran through the real events, so they now show the bar notice,
  peek and chat line too. New buttons / commands: **Friend comes online** (`/tc test online`) and **Congrats from a
  friend** (`/tc test congrats in`, a MOCK message from Testbuddy through the real path).
- **Not done / open:** auto-minimize rules, a group-only mini view and a minimap badge (out of scope); no new messages
  between copies. Unsure until tried in game: how the bar looks at the three row widths, whether `IsMouseOver` on the
  panel behaves for hover and peek, the glow, the missed number's placement.

## Hardening pass (2026-11-12)

- **Why:** the owner asked a newer Claude model to look over the whole addon and fix what it found. Review, plan and
  every decision Claude took while building: `docs/superpowers/plans/2026-11-12-hardening.md` (plan) and the section
  "Hardening pass" in `docs/TESTING.md` (what to check in game). Built on the local branch `hardening`, on top of the
  minimize / activity feed work. **Not tested in game, not published.** The release needs `RESTART_SINCE` (files were
  added and the `.toc` changed).
- **Solved by the guild (owner, 2026-11-12: "lets not worry about the crew code part just yet"; solved 2026-11-21):**
  until then nothing checked that a sender belonged to the crew: the channel name and password were in the public
  repository, so anyone on the realm who installed TwizCrew showed up in the panel and could send mocks (their own
  words on a streamed screen), "update" notices and calendar notes. Now only guild members are trusted (the guild
  master decides who is in), so no crew code is needed; it was removed with the channel.
- **Game values (the 2026-11-08 dungeon bug, everywhere):** one helper, `ns.Util.plain(fn, ...)`, reads game
  functions (a secret or failing result becomes nil); a test (`test_lint`) fails when a file calls `UnitIsAFK`,
  `IsInInstance`, `UnitAffectingCombat` and the like directly. Combat is read with `InCombatLockdown()` only.
- **Log:** errors and warnings are also kept in their own list of 100 (`db.problems`, shown in `/tc report` under
  "Problems"). The per-message send / recv lines are stored only while debug is on; `/tc report` shows counts per
  message type instead. (Seen in the owner's saved log: 83% of the 500 lines were position messages, 15 minutes of
  history.)
- **A module that turned itself off comes back** after 5 minutes (10, 20, at most 30 on repeats). Crew, Self, Away,
  Quest, LayerSensor, MockShow and MockEditor have their own error ids, so a bug in one no longer switches off a
  whole feature.
- **Messages:** bulk swaps (stats, trophies, calendar answers) wait in a second lane behind live messages. (The copy
  to the custom channel, sent only for PING, is gone since 2026-11-21.) A send refused 20 times is dropped with a warning. The layer key no longer triggers a message by
  itself. PING carries a short checksum of what I last sent; a friend whose copy of my state differs twice in a row
  asks me for it once (`SREQ`), so a lost message repairs itself within about two minutes. The send rate stays 2 a
  second (not known whether Forever throttles lower; `/tc report` counts refused sends).
- **Forget a friend:** right-click an offline row, or `/tc forget Name`. Names not seen for 60 days are dropped at
  login, with their stats.
- **Stats:** a friend's numbers are laid over the stored ones piece by piece (no more zeros while a snapshot
  arrives); an older snapshot arriving within 10 minutes of a newer one is ignored; a reset travels as explicit
  zeros; "stole the crown" waits until a friend's numbers have settled; two different full trophy records for one
  session end up the same everywhere (the smaller checksum wins).
- **Calendar:** a note or comment is at most 100 bytes (accents and emoji count more), so it always fits one
  message; at most 300 notes and 30 comments per note, the oldest kept; notes older than 90 days (UTC) do not count
  anywhere. The digest carries 8 small checksums, and only the differing groups of notes are swapped; a friend still
  on v0.1.23 is swapped with in full at most once an hour while nothing changed. Online friends' play time for today
  and yesterday rides in the digest. Timed notes use the clock offset of their own date (clock changes).
- **Files split (no behaviour change):** `UI/Panel.lua` → Panel, PanelRows, PanelHeader, PanelMenus, PanelMini (PanelTab since 2026-11-23);
  `Calendar/CalendarUI.lua` → CalendarUI, CalendarMonth, CalendarDay, CalendarUsual, CalendarMaker; the test tools
  moved from `UI/Report.lua` to `UI/TestTools.lua`.
- **Small fixes:** dragging the mock show (it raised an error and three drags switched Live roasts off); changing
  Scale no longer moves the panel; the Recent window opens in a fight; "running off" stays quiet for a dead friend,
  a hearthstone or a flight; the Furniture award counts the panel's own AFK; settings of a module whose file failed
  to load are no longer erased; the bar setting "instead of pop-ups" is off by default.
- **Tests are stricter:** the stub knows the real method names of each kind of frame (a typo fails), refuses sends
  over 255 bytes, and its secret values raise on use. (History: until 2026-11-21 most older tests ran as if the
  custom channel delivered messages; the channel and those tests were removed then.)
- **Known gap with v0.1.23 friends:** when a friend still on v0.1.23 resets their stats, updated copies keep showing
  their old numbers (all-time until each number counts up again, session until the next session). It ends when they
  update.
- **Left alone on purpose (Claude's calls; history: the channel join / retry code that was left alone here was
  removed on 2026-11-21, only the code that leaves the old channel once remains):** the dungeon artwork fallbacks in the calendar (need the game to judge), the periodic stats send
  (still a full snapshot, so v0.1.23 copies keep showing all-time numbers).

## Guild conversion (2026-11-21)

Built on the branch `guild-conversion` (tasks 1 to 7), released as v0.2.0 on 2026-11-22 (first in-game run: "Where we are"). Design:
`docs/superpowers/specs/2026-11-21-guild-conversion-design.md` (its top section lists what changed while building).
What to check in the game: `docs/TESTING.md`, "Guild conversion".

**Why.** The owner became guild master of a small guild (gaming buddies, stream regulars). A guild fixes two things:
one `GUILD` addon message reaches everyone online, and membership (which the guild master controls) says who is
trusted.

**Owner's words and decisions** (all quotes kept as written):
- "no fir now make it guild only": TwizCrew works inside a guild only (so: no friends outside the guild).
- "its fine for now": every guild member has the same powers; ranks maybe later.
- The panel: "maybe by default just tge ones in your paty, but have a drop down tab just like we have with ofgline
  wgere we can see the others and msybe a way to click to add them to the msin view orvrekove them".
- The Guild Board (part 2): "do 1,2,3,and maybe a tyoe of cavan boatd or something..." (looking-for-group cards,
  planned runs, matches from shared quests, with a canvas-like board).
- Calendar sign-ups plan (the game's own calendar event first, copies passing cards on as a backup): "looks good we
  will piviot latwr if needed".
- Data per guild: "maybe we can have data saved by guild nane or sonething so this isnt an issue if someone has
  other characters in different guilds".
- A website tie-in may come later, not now.

**What changed**
- **Talking.** `Comm.send` is one `GUILD` message. `Comm.sendTo` (one person) is a whisper, only to a guild member.
  Group-only messages (Find the crew positions) stay on `PARTY` / `RAID`. The queue (about 2 a second, bulk lane,
  lockdown hold) stays. Only about 3 "responder" copies answer a newcomer with shared data (session, trophies,
  calendar); replies are spread over a few seconds; several asks for the same thing get one guild answer. Measured in
  the test with 50 online and 1 newcomer in the first minute: 47 copies send 2 messages, 2 responders 7, the one copy
  that answers calendar diaries about 57 (50 of them diaries, slow lane), the newcomer about 10.
- **Trust.** A `GUILD` message is from a member by definition. A whisper or group message counts only when the sender
  is in the guild list; until the list has loaded (up to 10 s) the transport waits. Nothing at all is accepted while
  TwizCrew is not using this guild's data (`Guild.active()`), including the first seconds before the game has said
  whether the character is in a guild. Everyone else is dropped and counted, not logged one by one. A name ending in
  " <realm>" (the space form the game also uses) is read as a member only when the part before it is a listed
  member's full name: a stranger called "<a member's first word> <realm>" is not that member (final review fix). A same-named character from another realm is not told apart (the "-Realm" suffix
  is cut; Claude's call, revisit after `/tc guildtest` shows the name forms).
- **Members.** Who is in the guild comes from the game's guild list (`Crew/Guild.lua` and helpers). Member identity,
  Claude's call: the **first word** of the name is the key (it is the same however the game writes a name); a later
  namesake is stored under the **full name**; names inside messages are the first word unless two current members
  share it, then the full name; trophy records store full names. "Is this me" uses the full name when it is known.
- **Data per guild (owner decision).** Per guild: roster, crew stats, crew session, trophies, the clown, calendar
  notes and diaries, the activity feed, pins, member keys (pins are per guild). Shared by all the player's characters: settings, own
  status and mock lines, own characters' stats, the log. The first login of a character in a different guild than
  the loaded data needs one `/reload` (the addon is quiet and says so). If the game never gives the guild's name the
  addon runs with one shared set named "?" and no per-guild separation (accepted limit).
- **Data from v0.1.24** is attached to a guild by itself at once when nothing in it is about anyone else (no saved
  friends, crew stats, trophies or calendar notes by others: a user whose old panel was always empty), else only
  when at least two and at least half of the saved friends are in its member list (first word and class). Only a
  whole list (below) can refuse it; a list that may lack the offline members keeps the addon waiting quietly. Otherwise the addon stays quiet and prints one line, and the
  player decides: `/tc guild` (this character's guild, the data in use, and every kept set with a number),
  `/tc guild use` (`use yes` to insist when few friends match), `/tc guild new` (a fresh set for this guild after
  `/reload`; `new yes` when the game gives no guild names), `/tc guild load <number>` previews and `load <number>
  yes` (same session) brings a kept set back for this guild at the next `/reload`; the replaced set is kept as
  "<name> (replaced)". A request that could not be carried out is explained in one chat line at that character's
  next login (results are kept per character). Nothing is ever deleted by these. When the old data is adopted (also
  through `load`), every saved friend starts pinned (once). With "?" in use, `/tc guild new yes` starts the shared
  set fresh (the old one is parked).
  A character's guild is remembered only once the data on top is that guild's, so a quick `/reload` or disconnect
  before the guild list loads cannot swap data away.
- **Whole list (final review fix).** If the guild window's "Show Offline Members" box is unticked the game may list
  only the online members. A read is *complete* when it is exact or the same counts came back three times (enough for
  keys, the member list and adopting old data that fits); it is *whole* when it is exact, or complete and lists at
  least one offline member. Only a whole list hides saved friends missing from it, lets the 60-day rule run, and
  refuses old data that does not fit. **To check in the game:** `/tc guildtest` says "offline members included: yes /
  no / cannot tell"; with "no" the panel says to tick Show Offline Members.
- **Forgetting (Claude's call, replaces the design's 30 days).** A member missing from the guild list is only hidden
  and comes back with their data. The only automatic forgetting is the old 60 days not seen, and it runs only on a
  whole guild list that fits the saved friends (at least two and at least half match), or when this set fitted this
  same guild before (`guild.fitIn`, per set: written with the guild's real name whenever the list fits; otherwise a
  set where over half the friends left would never be cleaned again); data loaded in a guild it does not fit is never
  cleaned (a "?" or nameless session is cleaned only while its list fits the saved friends).
  (The design's 30-day forgetting was an idea dropped before release.) Reason: saved data is per
  account and a partial list read or an alt in another guild must never delete a real member's data. `/tc forget
  <name>` (also `/tc remove`, and "Forget this friend" on an offline row) deletes an offline member's saved data.
- **Panel.** Sections: my party, pinned, a "Guild online (N)" bar (closed by default; open when there is no party and
  no pin), an "Offline (N)" bar. My own row (when shown) sits at the top with no heading and is not a pin. The header
  reads "N here · M online" ("here" counts me). A green "+" pins, the raid-target star unpins (also in the row menu).
  Members without the addon are shown dimmed from the guild list ("Show guild members without the addon", on).
  Body lines say: not in a guild (only after the game said so for 10 s), needs `/reload`, older data waits for
  `/tc guild`, waiting for the full guild list (tick Show Offline Members), the guild's name cannot be read, waiting
  for the guild list. While TwizCrew is quiet nobody counts as pinned and no online / offline notices go out.
- **Notices.** Online, level-up and death notices (pop-ups, bar, chat) fire only for my party and pinned members by
  default ("Tell me about"); the Recent list records everyone. With the panel module off everyone is in scope. The
  Congrats button on a row stays for everyone. Mocks and congrats aimed at me always show.
- **Words.** The settings "Connection", "Crew channel" and "Crew code" are gone; a test (`test_lint`) fails if player
  text mentions the hidden channel, a crew code, a Connection setting or whispers as a choice. `/tc` help lists
  `guild`, `guildtest` and `forget`. The addon still says "crew" and "friends" where that reads naturally.
- **Removed.** The hidden channel (the addon leaves the old one once so it disappears from chat windows), the
  Connection setting, the crew code, `/tc add`, the stored crew channel data (`db.crew`).

**`/tc guildtest`** (needs one other member online with the addon; takes about 8 s; a second run within 10 s only asks to wait) prints: the
guild name (or that the game gives none), first why TwizCrew is quiet when it is; "N counted, M readable, offline
members included: yes / no / cannot tell" (guild list rows); whether the guild send was
accepted and whether my own copy heard it back, with the sender name form; who answered by whisper and that name
form; and whether the chat-lockdown functions exist. `/tc report` has a "Guild" line and a "Connection" line.

**Unproven until `/tc guildtest` runs in the game** (the three things only the game can tell): what `UnitName` gives
for party members (one word or two); whether the guild list gives GUIDs; whether offline members are in the list
when "show offline members" is unticked. Also: that `GUILD` addon messages are delivered at all (others report so;
we have not seen it), the name forms on guild and whisper messages, and how the new panel textures look.

**Open**
- *Must be checked in the game* (`docs/TESTING.md`, "Guild conversion"): the three only-the-game-can-tell items
  above; whether the game gives the guild's name and GUIDs; whether the pin button overlaps the Mock / Congrats
  buttons on the right edge of Compact and Tiny rows (and how the star texture and the state lines look); whether a
  one-word namesake from another realm can whisper (and so be trusted as a member).
  Also from the last re-check (2026-11-21): a member whose whole name is ONE word ("Twiz") cannot be told apart from a
  stranger named "Twiz <realm name>" on a whisper or party message (whispers carry no id); `/tc guildtest` shows the
  name forms, and if one-word names never appear with the realm added, that strip can be removed for them.
- *Known small limits:* v0.1.24 copies read only part of a long trophy name list and cut names at 24 letters (a
  bounded resend until they update); a newcomer with an empty calendar gets about 50 diaries from one copy in the slow
  lane (about 100 s); a few places still write while the addon is quiet (the local mock echo, `/tc session new`,
  typed notes); a stale remembered guild costs one extra `/reload` and may leave an empty set; after a downgrade to
  v0.1.24 and back, its writes are counted into the set on top; in a gap in the game's guild names a set loaded
  there becomes the shared "?" set and the named character brings its own back later (no data lost, may repeat).
  On a game that gives no guild names, a v0.1.24 user with no saved friends still gets the "choose" line and needs
  `/tc guild use yes` once (with names it attaches by itself); in `/tc guildtest`, a sender the guild list does not
  have yet, whose first word is someone else's key, gets no answer.
- *What only the game can tell (whole-branch review):* whether `GUILD` addon messages arrive at all and how fast;
  the sender name forms on guild messages and whispers; whether the guild list gives GUIDs and offline members (the
  Show Offline Members box); whether `GetChannelName` and `LeaveChannelByName` drop the old channel; whether
  `IsInGuild`, `UnitName` / `UnitGUID("player")` and `GetGuildInfo` turn unreadable inside dungeons (the addon keeps
  sending and keeps knowing itself then); whether the guild's name comes within 10 s of login; the new panel lines
  and textures.
- *Follow-up work:* `Crew/Guild.lua` was split on 2026-11-23, behaviour unchanged, into `Crew/GuildNames.lua`
  (rows, keys, names, the loaded list), `Crew/GuildIdentity.lua` (whose saved data is on top, the fit rule),
  `Crew/Guild.lua` (membership, the guild's name, active(), reads, events) and `Crew/GuildCommands.lua` (`/tc guild
  use`, `new`, `load`); shared state goes through the private table `ns.Guild._`. Still open: **part 2, the Guild Board** and **part 3, guild-wide Hall of Shame and news**, designed only in
  outline (the design's "three parts"; research on the game calendar and other addons in "What an addon can and
  cannot do"). No version bump and no Changelog entry yet.

**Claude's calls in this work (change any):** the details are in the design document's "Changed while building"
section; the list: first word as the key; stripping "-Realm"; sending and whispers wait for the guild list up to
10 s; about 3 responders; guild identity is the name only (no realm, so same-named guilds on two realms share data);
the guild name is remembered for the session; no readable name after 10 s means one shared "?" set; the guild list
counts as complete after three identical reads, and as whole only when exact or listing an offline member; the fit rule (two and half) for old data and for the 60-day clean-up;
old friends start pinned; pins are per guild; hiding instead of deleting; the `/tc guild` commands and the wording of
their lines; `Crew/Guild.lua` not split in this work (split later, see Follow-up work).

## Calendar button next to the tabs (2026-11-22)

The owner: "make it so the crew calendar is a first class citizen and sits next to the crew and hall of shame
buttons, so it's easy to access, maybe make it pulsate or flash or blink when updated."

- **The button (UI/Panel.lua):** "Calendar" on the bar under the header, right of "Crew" and "Hall of Shame". It
  opens and closes the calendar's own window (not a tab: the month view is far wider than the panel; the panel keeps
  its tab). Which buttons the bar holds, when it shows and its short words: "The crew tab (2026-11-23)", Activity tab.
- **The small scroll in the header is gone** (owner approved). The wrench menu, `/tc cal`, the key binding, the
  minimap menu and the settings button still open the calendar.
- **What counts as new (owner picked "new notes and replies to your notes"):** a note by someone else, or a comment
  or an answer (going / maybe / can't, also a changed answer) by someone else on a note of mine. Not news: my own
  notes and replies, deletions, an answer taken back, "seen" marks, comments on other people's notes, anything on a
  date before yesterday (UTC days), and whatever arrives while the calendar window is open.
- **The pulse:** a gold glow behind the button fades in and out about every 1.5 s (PanelLogic.pulseAlpha, a 0.1 s
  ticker that runs only while the button is on screen and something is new), and the word turns bright. It stops
  when the calendar is opened by any route. Only while the panel is on screen: tucked into the crew tab nothing
  pulses (a new note or an answer slides out of the tab as news instead, "New calendar note from ...").
- **How it is kept (Calendar/Notes.lua):** `db.calendar.fresh` = the latest day (a UTC day number) that has news,
  saved with the guild's calendar, so it survives a logout and belongs to the guild. Set where notes and replies
  arrive (Notes.receive, Notes.receiveReply), cleared by Calendar.open; it runs out by itself once that day is past
  and the daily clean-up drops it. `CALENDAR_FRESH` fires when the answer of `Notes.fresh()` changes (the panel
  redraws on it). A flag set on arrival was chosen over comparing times with "when I last looked": the crew's clocks
  and the order messages arrive in cannot be trusted for that.
- **Not done:** nothing on the minimap button for calendar news; the button does not show which note is new. (The
  crew tab says it since 2026-11-23.)
- **The source folder on the Windows PC (2026-11-22):** `master` was moved to the released v0.2.0 (GitHub's history
  had been rewritten by the release). The uncommitted work that was there (a quest list, feed and panel changes from
  2026-11-15, never released, not in v0.2.0) is kept on the local branch `old/0.1.24-quest-list`. The owner: "let's
  just use and keep the new stuff".

## Calendar: Events and Play times (2026-11-22)

The owner: "the calendar is too cluttered ... I want events to catch people's eyes and it's hard when it's mixed
with the icons showing who has played recently." He picked one window with two tabs over two windows.

- **Two tabs in the one calendar window (Calendar/CalendarUI.lua):** "Events" and "Play times". The window always
  opens on Events (the panel's Calendar button, `/tc cal`, everywhere), and saving a note lands on its day there.
  Views: `events`, `eventDay` (Events); `month`, `day`, `usual` (Play times). A small Month / Usual times switch
  sits next to the tabs while Play times is open (Usual times used to be the second tab).
- **Events month (Calendar/CalendarEvents.lua, new):** a day shows only its notes: icon, time and the first words,
  three lines, the last one "+N more" when there are more. A dungeon or raid still fills its day with its artwork,
  time, name and "N going". Past days are dimmer. Click a day for its list, right-click to add a note.
- **"new":** a note by someone else that I have not opened (no "seen" reply of mine: Notes.isNew), on a day from
  today on, carries a gold "new" on the month and in the day's list. Opening the note takes it away. This is apart
  from the panel button's pulse (which opening the calendar clears).
- **A day's events:** eight tall rows (icon, time and words, then the author, going / maybe / comment counts and my
  own answer), the mouse wheel scrolls past eight, "Create a note for this day" under them.
- **Play times month (Calendar/CalendarMonth.lua):** class icons (two rows now, 14) and the hours together; no note
  icons, no artwork, no right-click menu. Click a day for the timeline.
- **Timeline (Calendar/CalendarDay.lua):** the notes list under it is gone. The small marks for timed notes stay (who
  was on at event time), and right-click still adds a note at that time.
- **Across:** "Who played this day" on a day's events, "This day's events (N)" on the timeline.
- **Nothing about the data changed:** the same notes, replies and messages, so copies on v0.2.0 are not affected.

## Calendar: time zones (2026-11-22)

The owner read "Your time zone: UTC-6" as "it thinks I am on UTC" (he is on Central time; the offset was right).

- **Zones have names (CalendarLogic.zoneLabel):** "CST", "CDT", "EST" ... for the US zones and GMT / BST / CET /
  CEST / EET / EEST; any other offset is still written "UTC+5:30". The game gives no zone name, so it comes from the
  computer's offset plus whether its clocks are on summer time then (Diary.zoneAt: summer time is the larger of the
  year's January and July offsets). The same offset has two names (UTC-6 = CST in winter, MDT in summer).
- **A timed note carries its author's zone:** kept as `z` (minutes to add to UTC) and `zd` (summer time), sent in
  CALN as `z` ("-360", "-300d"). Readers still convert the shared time to their own computer's time as before; a
  reader in another zone now also sees the author's: "7pm CST your time · 8pm EST for Frostie" in the note's window,
  "8pm EST their time" in the day's list. On the same zone only one time shows. The month's small lines stay as
  they were (the reader's time only).
- **Older copies and notes:** v0.2.0 ignores `z` and drops it when it passes a note on; a copy that first heard a
  note that way takes the zone when it later hears the same note (same `u`) with one. Notes made before this have no
  zone: only the reader's time shows. The checksums do not change (they use key and `u`).

## Calendar: edit and remove notes (2026-11-22)

- **Why he could not remove his note:** the owner plays the same characters on two installs of the game. Each
  install has its own diary id (`calendar.me`), and a note's key starts with its author's id, so a note made on the
  other install looked like someone else's here: no remove control (and it counted as "new"). Seen in his saved data:
  two ids, both with the alts Yaboytwiz and Warpedpathos. **Notes.isMine now also says yes when the note's author
  name is my character or one of my own alts, and its class is that character's** (the class part since
  2026-11-23: two members can share a first name). Only notes are covered: an answer (going / maybe) given on the other
  install is still a second person's answer.
- **Edit (Notes.update, new):** changes one of my notes in place (day, time, words, icon, dungeon). The key stays,
  so answers and comments stay; `u` goes up, so every copy (v0.2.0 too) takes it as a newer copy of the same note.
  The "Create a note" window opens filled in as "Edit note" (`Calendar.openMaker({ edit = key })`).
- **Where:** right-click a day on the Events month: the two "Create" lines, then up to four of that day's notes
  ("Edit: ..." and "Remove: ..." for mine, "Open: ..." for others; more: "See all N notes"). A row of a day's list:
  "Edit" and "Remove" buttons on mine (the small "X" is gone), right-click for Open / Edit / Remove. The note's own
  window: "Edit my note" next to "Delete my note". Remove asks nothing first.

## Quest list (2026-11-22)

- **What the owner asked:** "so far it only shows one quest ... is there a way we can improve this". He picked
  option 1 (see every quest a friend can share) and option 3 (a heads-up when you group). Option 2 (one click
  shares everything you're missing) was left out: nobody has checked that the game accepts several shares from one
  click. On 2026-11-23 he asked for zones and ticks (see "Quests by zone" below), which brings back a form of option 2
  with that question still open.
- **How it travels (Crew/QuestList.lua):** `QLQ` = "send me your quest list" (t = who should answer). `QLA` = the
  list: `s` (a stamp, the same in every piece), `n` (how many quests), and one `q<questID>` = flag + title per
  quest (flag: 1 can be shared, 0 can't, ? the game doesn't say; title cut to 40 like the row's). A full log takes
  several messages; a list is used only once all `n` quests arrived, so half a list never replaces a whole one.
  Whispered when the friend can be whispered, else sent to the group. Sent in the slow lane (bulk).
  **Since 2026-11-23 (list format 2)** the list also carries: `f` = "2" (in every piece, with `s` and `n`), `h<n>` =
  the name of the n-th heading row of the sender's quest log (the zone, or a group like a class; cut to 30 letters),
  and `z<questID>` = the number of the heading the quest is under (0: none). `q<id>` keeps its meaning, so v0.4.1 and
  older copies read the list as before and skip the new fields (checked in a test that reads a new list the way they
  do). A format-2 list is used only once every quest's `z` and every heading it points at arrived too (the pieces can
  come in any order). A list without `f` is from an older copy: one list, no headings. `f` also says the copy takes
  an ask for several quests (below). A full log takes more messages than before: 30 quests with 40-letter names were 8
  pieces, now 9 with one heading, 10 with 5, 11 with 10 (2 to 3 more for a usual log).
- **When a copy asks:** when you hover a friend's row (once per hover) or open its right-click menu (not again
  within 20 s, and not while the list is younger than 60 s), and, 6 s after the group changes, for every crew member
  in your group whose list did not come by itself (not while their list is younger than 5 minutes). A copy in a
  group sends its list to the group again by itself, 2 s after its quests change (a newer list replaces one still
  waiting in the queue). An asker gets at most one answer per 10 s, and none when they were in my group when my
  list went to it less than 30 s ago with the same quests. A list holds at most 30 quests, none without a name.
- **What you see:** the row's right-click menu has "Their quests (4 you can get)"; a click opens their quests in a
  window (until 2026-11-23 a second menu; the window is described under "Quests by zone" below). The row's tooltip
  adds "Can share N quests with you". The row itself still shows the one quest they're on, with its green or red
  mark, as before.
- **"You can get it" is the same rule as the row's mark:** yes when Questie says so, or, without Questie, when the
  game says it can be shared and you neither have it nor did it. Without Questie that can count a quest you are too
  low for.
- **The heads-up:** when a group member's list shows quests you can get, one pop-up ("Frostie has 4 quests you can
  get", click = their quests window) and one chat line. Once per friend per grouping; leaving the group resets it. Switch:
  "Tell me what my group can share" (`questHeadsUp`, Panel, on by default).
- **Privacy:** "Share my quest" is now "Share my quests": off means the list goes out empty too.
- **Questie is not needed (owner: "I want it usable if the user doesn't have it").** Without Questie nothing knows
  ahead of time that you are too low or miss an earlier quest, so such a quest is offered. What happens then
  (Crew/Quest.lua, "why a share didn't work"): the game tells only the sharer why a share failed, as a system line
  ("Twiz is not eligible for that quest"). For 10 s after a share made from a friend's request, the sharer's copy
  watches for that line about that friend (the game's own texts `ERR_QUEST_PUSH_..._S`, else the English ones) and
  sends the reason back: `QRES` (t = who asked, q = title, i = quest ID, r = inv / done / have / full / busy / decl
  / far). The asker's copy prints why; "not eligible" and "already done" are remembered, so that quest shows as
  "Can't share" everywhere (list, row mark, tooltip) until a level-up, a quest turned in, or a /reload.
  **Not checked on Forever:** that the game prints these lines there, and their exact words.
- **Older copies (v0.2.0 and before)** drop both message types: for them the menu says "Their quests (asking...)"
  and only the one quest on the row can be asked for, as before.
- **Quests by zone (2026-11-23, owner's words in "Where we are"):** the window (`UI/QuestWindow.lua`, opened by
  "Their quests" and by the heads-up's click; Escape closes it; a plain frame, fine in a fight) shows their quests
  under their quest log's headings. The heading that matches the zone I'm in (`GetZoneText` or `GetRealZoneText`,
  same letters, any case) comes first with "(you are here)", the others in the order of their log, quests under no
  heading last as "Other quests". No real distance (zone names only; Questie is not used for this). Each quest I can
  get (the same rule as the row's mark) has a check box; a click on the line ticks it too. The others are grey with the
  reason: "<quest> (you both have)" or "Can't share: <quest> (why)". Each heading with something to tick has "Tick
  this zone" (ticks all I can get under it; "Untick this zone" once all are ticked). "Only this zone" at the top
  hides every other heading (not saved; when they have nothing in my zone: "<Name> has no quests in <zone>.", or "in
  this zone" when the game names none); ticks in hidden zones still count (Claude's call: the button's number always
  says what will be asked). The mouse wheel scrolls (14 lines show; "Scroll for more"). The button at the bottom:
  "Ask for 3 quests" (follows the ticks; "Ask for quests" and greyed at 0; at most 25 in one ask), "Stop asking"
  while an ask runs; when I'm in no group, or they are not in mine, the click prints the usual "quest sharing only
  works in a group. Invite <Name> first." line. The ticks stay after an ask: a quest I take, or one refused for good,
  drops out by itself, so after "No answer" or "busy" the same ask is one click again. A line next to the button says
  how the ask goes. The window redraws itself when I change zone or my group changes. An older copy's list: the
  same window, one list, no headings and no "Only this zone".
- **Asking for several (Crew/QuestAsk.lua):** `QMR` = the ask (t = who shares, k = a stamp, q = quest IDs "33,42";
  one message, at most 25; Claude's call: no titles, they would need several messages, and the sharer takes the names
  from its own log). The sharer's copy takes it only from a guild member in its group, meant for it, one ask per
  friend per 15 s, IDs that really are in its log and shareable (the others are left out; none left: it answers
  "none"). With "Share my quests" off it answers "off" (so the asker hears at once). A new ask from the friend whose
  share is running (their copy forgot the old one, after a /reload say) replaces it; anyone else gets "busy". It shows
  ONE pop-up, "Twiz asks for 3 quests" (20 s, then "no"). Its click shares the first quest; then one at a time: the
  next goes out once the last is answered, because the game shows the asker one offer at once. Answered = the asker's
  copy says it took it (`QMU` with the quest ID, from its `QUEST_ACCEPTED`), or the game's line on the sharer's side
  (the "why a share didn't work" watcher above, one watch per friend, here 45 s per quest; also "<Name> has accepted
  your quest" when the game prints it, except in the first 2 s after a share, when it is late news of the quest
  before). A refusal is told back (`QRES`) and the next quest follows, except: "busy" (a window was open) offers the
  same quest once more 5 s later; "quest log full", "too far away" and 45 s with no answer end the whole share (they
  would fail the same way for every quest left, or the last offer may still be open). The sharer's news goes to the
  asker as `QMS` (st = yes / no / busy (sharing for someone else) / next (a click is needed) / end with r = why and d =
  how many were taken). It also stops when the group breaks, the asker goes offline or stops (`QMU` x = 1), or a
  "share next" pop-up gets no click. The asker sees the progress in the window, the usual one line per refused quest
  (`QRES`, new codes "gone" (not in their log any more) and "cant"), and one line at the end: "You got 2 of 3 quests
  from Frostie." (or "No answer from ...", "... is sharing quests with someone else", "... stopped sharing (your
  quest log is full / you are too far away from them / no answer to the last offer / they turned quest sharing off /
  the group broke up / they went offline / ...)", "Stopped asking ..."). The asker gives up after 30 s without "yes"
  or "no", and after 2 minutes without any news (both tell the sharer's copy to stop), and when the friend goes
  offline or leaves my group. Sharing puts the quest log's own pick back afterwards (an open quest log does not jump).
- **One click or one click per quest? (not known; the first thing to check in the game):** after the sharer's one
  click, the next shares are made by a timer, without a click (`QuestAsk.AUTO_NEXT = true`, one switch at the top of
  `Crew/QuestAsk.lua`). If the game wants a hardware click for each `QuestLogPushQuest`, it reports a blocked action
  (`ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` naming TwizCrew, and `QuestLogPushQuest` when it names the
  function) within 2 s of a timer share; TwizCrew then offers that quest again as a pop-up "Share next quest (2 of
  3)" and uses such a pop-up for every next share until the next /reload. If the game instead silently ignores the
  call, nothing tells us: then set `AUTO_NEXT = false` (every next share is a pop-up).
- **Asking an older copy for several:** a friend whose list has no `f` (v0.4.1 and older) drops `QMR`. Their copy
  also drops a second `QREQ` from the same friend within 15 s (counted when it arrives there) and shows one pop-up per
  `QREQ`. So TwizCrew says once "<Name> has an older TwizCrew, so you ask for one quest at a time (they click for each
  one)" and sends the usual single asks one after another: the next once the last is answered (I took it, or a
  `QRES`), never sooner than 20 s after the last. A quest with no answer after 45 s is asked once more, then skipped
  ("<Name> didn't answer about "<quest>", so it was skipped."). It stops when they go offline or leave my group, or
  after 150 s without any answer. Each ask prints the usual "asked <Name> to share ..." line, and one line at the end.
- **Known limit:** at most 5 pop-ups show at once; a new one pushes out the oldest, so an ask's pop-up can be pushed out
  by a burst of other pop-ups (left as it is; the asker then hears "No answer").

## While you were away and the welcome card (2026-11-23)

- **"While you were away" (UI/AwayCard.lua, rules in UI/AwayLogic.lua):** about 10 s after login, when this
  account last logged out with this guild's data 12 hours ago or more, one card: "You were gone 3 days", then new
  calendar notes, who joined, who left, Hall of Shame crowns that changed hands ("Chaos took Money Pit from
  Frostie"), and level-ups ("Irek 27 -> 30"), at most 12 lines (the last "...and N more"). Nothing to say = no
  card. Click = close; a click on the calendar line opens the calendar, on a crown line the Hall of Shame
  (all-time) at that award's tab. The wrench menu has "While you were away" once a card was shown this session.
  Switch: Today's recap, "Show what changed while I was away" (`awayCard`, on; needs the Today's recap module on).
- **Where the data lives:** `db.away.snap` = { at, guild (its name), members[key] = { level, class, name as shown,
  full, guid }, crowns[award id] = winner keys }, per guild (`away` in `DB.GUILD_PATHS`: an alt in another guild
  compares against that guild's list; the snapshot's own guild name is checked too). Written at `PLAYER_LOGOUT` (a
  `/reload` too), only after this session's card was worked out and shown, or found to have nothing to say (a
  quick `/reload` right after login, or a logout while the card still waits for the end of a dungeon, keeps the
  old one), only while TwizCrew uses this guild's data and the list is complete. A whole list with at least 80% of
  the snapshot's members replaces it; any other list (one that may lack the offline members, or a whole one much
  smaller: a list of only the online members can look whole) only updates the members it lists (the rest are
  kept), and only an existing snapshot is updated that way (limit: after a real cut of over a fifth of the guild,
  the members who went stay in the snapshot; their "left" lines are a crowd and never show). Crowns are written
  only while the stats module is on.
- **When lines appear:** members are matched by GUID, then full name (a member whose key changed is the same
  member). Level-ups: same member, higher level. Joined: in the list now, not in the snapshot. Left: in the
  snapshot, not in the list now, and only when the list is whole (`Guild.whole()`). **Crowds are not believed**
  (real joins and leaves come a few at a time; if the game counts only the online members, a list without the
  offline ones looks whole): more "left" lines than 3 and than 10% of the snapshot's members drop all "left"
  lines; the same for "joined" against the list now. Level-ups stay. My own characters in this guild are never
  listed: the GUIDs and keys in this guild's `guild.mine`, the full names those match in the list, my key and GUID
  now (not the names in `stats.chars`: those are first words of my characters in any guild, and a new member here
  may share one). The card waits for a whole list up to 90 s after login, then goes on with a complete one without
  "left" lines. Calendar: notes by someone else made after the last logout (the time in the note's key), not
  opened yet, still in the keep window (`Notes.newSince`), counted when the card shows (notes that sync later are
  not counted: Claude's call, the simpler honest option). Crowns: all-time winners at logout against now, rates
  (`noSteal`) and test fakes left out, a crown counts as taken only when none of the old holders still holds it;
  friends' numbers only arrive after login, so this line shows only what has arrived by then. Never during a fight
  or inside an instance (checked every 3 s until out).
- **Welcome pop-up (UI/Welcome.lua, rules in UI/WelcomeLogic.lua):** someone in the guild list who was not in the
  last WHOLE list of this session (so never on the first list of a session, and never before a whole list was
  seen: with "Show Offline Members" unticked there are no welcome pop-ups at all, as long as the game still counts
  the offline members), not in the snapshot of the last logout (they are on the away card instead), not one of my
  characters, not welcomed before on this account: "Say hi to Sneakz", "Level 8 Mage just joined the guild - click
  to say hello" (`Popups.notice`, 20 s). The click itself calls `SendChatMessage(line, "GUILD")` (needs the
  click), one of four lines at random ("Welcome to the guild, Sneakz!"); if the game refuses, the chat box opens
  with "/g <line>"; without that, one chat line says what to type. At most 3 a minute (more over several lists are
  dropped); more than 3 new names in ONE list are a resync, not joins: nothing shows and that list becomes the new
  baseline. My characters as on the away card (GUID first). Switch: Pop-ups, "New guild members" (`newMember`, on;
  needs the Pop-ups module on); not filtered by "Tell me about" (someone brand new is in nobody's party or pins).
  Welcomed names: `db.welcome.welcomed[lower(full name)]` = when, per guild, forgotten after 400 days. Limit: a
  brand-new alt that never ran TwizCrew cannot be told from a stranger: it gets a "joined" line on the away card,
  and a pop-up when it joins while I am online with another account.
- **The newcomer's start card:** once per guild set on this account (`db.welcome.start` = "due", "shown" or "no").
  The first time TwizCrew uses a guild's data, it is owed only when this copy had no saved crew data for it at
  login (`Guild.dataEmpty()` right after the login swap, so an old user whose data is adopted, or anyone with
  saved keys, gets "no"). **Installed before the invite:** while the game says there is no guild nothing is
  decided (no 2-minute cut-off); the guild list decides once the invite comes. A copy that saw itself as a new
  install (nothing saved at login) in no guild, on an account that never read a guild's name, sets
  `db.welcomePending = true` (account-wide), so the card is still owed after a logout before the invite; the first
  guild that decides uses it up. Shown about 30 s after login once the list loaded (owed until shown: a fight or a
  dungeon all session moves it to the next login): "Welcome to TwizCrew" (it also greets a long-time member who
  just installed it), under it "You are in <guild>.", "Online near your level: Frostie (24), Chaos (26)" (online,
  within 5 levels, nearest first, at most 5) or "Nobody near your level is on right now", "The crew usually plays:
  Tue 8pm-11pm" only when the play times already on this copy cover at least two other people (a brand-new copy
  rarely has them by then; nothing is invented), a "How to use TwizCrew" button when `ns.About.open` exists (the
  About window is built on another branch), and Close.
- **Start-up:** `Core/Boot.lua` starts both right after the login swap of saved data, before the modules, so they
  read the last logout's data before anything writes and hear the guild list's first events.
- **Claude's calls (change any):** 12 hours; 10 s / 90 s; 12 lines; the order of the lines; the crowd limits (3
  and 10%; 3 new names in one list; 80% to replace the snapshot); the snapshot written only at logout; the
  calendar count at show time; the crown rule (no tie counts); the four greetings; 3 pop-ups a minute and dropping
  the rest; 20 s pop-up; the start card at 30 s; "near" = 5 levels, 5 names; two other people for a best time; the
  setting inside Today's recap; the re-show in the wrench menu (no `/tc away`, it would clash with `/tc afk`).

## The crew tab (2026-11-23)

**The owner's words.** "The UI panel ... takes up too much screen real estate. I like how it functions and what it
does, but ... many of the guild mates want more of their screen back." Measured: the default panel was about 246 x
630 UI units on a normal evening (about 15% of the screen). Out of ten mock-ups he chose "E, Hidden tab": "just having
it slide out info that is important and hiding it again is nice; we can make info that has an optional reaction stick
a little longer, such as the congrats or mock. Also when a player mouses over it or interacts with the tab I would
like the whole thing to slide out and look mostly like it currently does, so they can see everything like now ...
this means we no longer need the minimize button because the tab by default will always just take up a small part of
the screen." Later the same day: Keep open is off for everyone, existing users included ("I don't like the idea that
someone who doesn't know there is a better way misses it"), and the Keep open control must be "extremely easy and
visible": a clearly labelled switch, not a small icon.

**What it does (approved description).**
- **Quiet:** only a small tab (24 x 86) on the left or right screen edge: "C R E W" and the number of people here
  (the header's "here": me, my party and pinned members online). Drag it along its edge or across to the other edge;
  its side and height are saved per account (`tabSide`, `tabY`, Panel settings; kept on screen after a resolution or
  scale change). "Lock position" stops the tab too. Right-click: Keep open, Recent activity (N new), Lock position,
  Open settings, Hide panel.
- **Everything:** the mouse resting on the tab about 0.3 s, or a click, slides the whole panel out as it always looked
  (header, Keep open switch, tabs, sections, bars, Hall of Shame, Calendar button, "?", menus, tooltips). It slides
  back about 1 s after the mouse has left the tab, the panel and any menu opened from them. A click while it is out
  closes it, except a click within about 1 s of a hover-open: that keeps it out (as a click-open). A right-click
  during the hover pause opens the menu alone (no hover-open until the mouse leaves the tab; the menu's full-screen
  catcher takes the mouse, so this block holds for as long as the tab's menu is open, and after it closes until the mouse
  has left the tab once). A click on a stolen-crown pop-up or on a crown line of the "While you were away" card
  opens the Hall of Shame and, while tucked, slides the panel out ("note" open: stays at least about 6 s). Opening it
  counts what was missed as seen and hides the tab's tooltip.
- **News:** one row slides out (the news line in the title bar and that friend's row; a calendar note has no row),
  then back. Plain news stays 5 s (`PanelLogic.NEWS_SECONDS`; the `peekSeconds` setting is gone since 2026-11-23): came online, died, levelled up, other layer / back on
  my layer, ran off, a new calendar note (or an answer on mine). News whose row shows a button stays
  `PanelLogic.REACT_SECONDS` (12): Congrats after a level-up, Mock after a death, **Mock back** on a mock or congrats
  aimed at me (decided by `PanelLogic.newsReactable` from `Roasts.canCheer` / `canMock`, the same rules the row's
  buttons use). With two or more waiting, plain news shortens to 3 s and reactable news to 5 s. The mouse on the row
  keeps it out; it goes 0.6 s after the mouse leaves. A right-click menu on it keeps it out. A click on the news line:
  congratulate (level-up), whisper (online), the calendar (a note), the big arrow (running off), the whole panel (a
  layer change), else the Recent list. Scope: exactly the old rules (`FeedLogic.inScope`, `Panel.noticeInScope`,
  "Tell me about"). Layer, running-off and calendar news are made by the panel itself (`FeedLogic.newsEntry`, never in
  the Recent list or chat); layer news follows the pop-up switches Layer changes / Back on my layer, said once until
  "back"; calendar news is said once per sync (`CALENDAR_NEWS` from Calendar/Notes.lua); none of it in the first 30 s
  after login (counted from login, not from when the files were read: a long loading screen does not eat it).
- **After a fight** (owner, 2026-11-23: "is there any way to batch it to show stuff when the fight is over"): in a
  fight news is only counted (and pop-ups show, even with "Show news on the tab"). About 3 s after the fight ends (not
  in a new fight: then it waits for that one's end too, and the news of both fights goes together), the news that
  came in the fight, was in scope and was not already shown by a pop-up (`Popups.shownSince`) slides out: one piece
  as usual (its button and the 12 s rule); two or more as ONE summary: the title line "3 things happened in that
  fight", and either the row of the first one with a button (Congrats, Mock, Mock back) or, when none has one, the
  note line under the title naming two in short form ("Frostie died · Irek reached 28 +1 more"). The summary stays
  12 s; a click on its line opens the panel on the Activity tab. Not with "Slide out news" off (the count is as
  before), not in the 3 s after login; a fight that ends with my death still shows it. The rule:
  `FeedLogic.afterFight` (short forms `FeedLogic.shortLine`). Because pop-ups show in fights, deaths, level-ups,
  online and layer news (whose pop-up switches must be on for the tab to take them) mostly had their pop-up already:
  the summary is mainly mocks and congrats aimed at me, calendar notes and running off with pop-ups off.
- **Activity tab** (owner, 2026-11-23: "is there an activity tab"): a third panel tab after "Crew" and "Hall of Shame"
  (the bar: Crew, Hall of Shame while stats is on, Activity while the activity module is on, the Calendar button while
  calendar is on, then "?"; it shows whenever it holds more than Crew). It lists the Recent window's entries at the
  panel's normal width, 10 at a time, newest first: the same rows (icon, line, "5m ago", the tooltip with the clock
  time; `Recent.entries`, `Recent.newRow`, `Recent.fillRow` serve both), the mouse wheel scrolls, "Scroll for more
  (1-10 of N)" under it, "Nothing has happened yet." when empty. The label counts entries added since the Activity tab
  or the Recent window was last looked at ("Activity (3)"; only what "Tell me about" covers; session only). Opening
  it clears that count and the tab's missed number. The red number on the crew tab (a button now) opens the panel
  straight on Activity, so does a click on the after-fight summary; a click on the tab body keeps the last tab. When
  the bar is too narrow the words shorten in this order: "Cal", "Act", the "?" goes, "Shame". The Recent window,
  `/tc recent` and the menu entries stay.
- **The tab's marks:** unseen news: a soft gold glow (a brighter flash when it arrives) and a red number; a party
  member or pinned friend DEAD: a small red skull mark; on OTHER LAYER: a portal mark in the layer tag's colour; an
  update waiting: the gold "!".
- **Keep open** (`keepOpen`, default off): a wide switch right under the header, "Keep open: OFF" (dim) / "Keep open:
  ON" (gold, lit with a check mark), "Keep: OFF/ON" in Tiny rows, tip from `Help.TIPS.keepOpen`. On: the panel is the
  old ordinary window (drag anywhere, saved position, fade, grow direction, lock), the tab is hidden. Also `/tc mini`
  (and `/tc minimize`), the key binding "Keep the crew panel open, or let it tuck away", the title bar menu ("Keep
  open" / "Tuck away"), the tab's menu, the minimap button's menu and the setting.
- **See-through when idle** (owner, 2026-11-23: "i want the panel by default to be transparent unless its being
  interacted with, but if news happens or slides etc that doesnt need to be transparent"; **not tested in the game
  yet**). The tab, and the panel when Keep open is on, fade as whole frames (text and bars too: `SetAlpha`, fine in
  fights) to the setting `idleAlpha` ("See-through when idle", 10% to 100%, default 40% for everyone; 100% = off; a
  change applies at once; tip `Help.TIPS.idleAlpha`). It replaced the old "Fade when the mouse is not over it" and
  "How much to fade" (`fadeOut`, `fadeAlpha`, Keep open only). Solid (1) while: the mouse is on the tab, the panel or
  the holder (the same focus check as hover); the panel is out (hover, click, the note) or sliding; news is showing
  or the tab flashes for new news; a menu opened from the panel or tab is open; the tab or the kept-open panel is
  being dragged. To solid in 0.2 s; back to idle 1 s after the last reason ended, over 0.4 s. The rules are
  `PanelLogic.seeTarget` / `seeStep`; the work is in `UI/PanelTab.lua` (the 0.1 s ticker decides the target, a frame's
  OnUpdate smooths the fade and runs only while it moves). The ticker stops when settled. A kept-open panel has no tab
  to wake the ticker, so it polls the mouse (an OnUpdate, 10 times a second) while it is see-through. The update "!"
  and the missed glow do not hold it solid. Only the mouse rises over 0.2 s; news, an open panel, a slide and a drag
  go to solid at once (the ticker's first step runs the moment it starts, so news never slides out faint). Parts that
  stay solid on purpose, whatever the panel's alpha (`SetIgnoreParentAlpha`): the update line, the news line, and the
  Mock, Congrats and Share buttons (news and reactions are not see-through). The Keep open switch bar fades with the
  panel. Old saved `fadeOut` / `fadeAlpha` are deleted once at the tab migration (no value is mapped; everyone gets
  40%).
- **Pop-ups:** they show as before, and the news slides out of the tab too. "Show news on the tab, not as pop-ups"
  (`barInstead`, default off) stops the online, death, level-up, layer and running-off pop-ups while the panel is
  tucked, the tab is on screen and news slides out, never in a fight (nothing slides out then, so the pop-up shows).
- Hide during fights / in dungeons / when no crew is online and `/tc hide` hide the tab too. Hiding closes a panel
  that was out: it comes back as the tab.

**Claude's calls (designer and builder; change any).** A 0.3 s pause before hover opens; no hover-open while
`IsMouselooking()` or a mouse button is held (the pause starts again), in a fight (`InCombatLockdown`) or in a dungeon
or raid; a click always works. Hover (and the mouse keeping the panel out) also needs the game's mouse focus on the
tab, the panel or one of their children (`GetMouseFoci()`, else `GetMouseFocus()`, else the mouse position alone), so
bags or action bars lying over the tab do not open it. The Hall of Shame is not drawn while the panel is tucked and
closed; it is drawn when the panel slides out. No news slides out in a fight (a fight drops the waiting news; it is still counted, and kept
for the after-fight news, at most 20). The slide: the panel frame hangs in a holder (`TwizCrewPanelHolder`) that clips its children
(`SetClipsChildren`, guarded: without it the panel shows at once); the panel is laid out once (while tucked it is laid
out as the full panel behind the closed holder, ready to slide) and only the holder's width is eased over 0.18 s by an
OnUpdate, also finished by the 0.1 s ticker; the holder is clamped to the screen, the panel itself not (it must sit
beside the narrow holder). Tooltips and menus open toward the middle of the screen when the tab is on the right
(`Widgets.menu`'s `toLeft`). The guild list is read often whenever the tab or the panel is on screen (the tab shows the
count; the away card needs complete reads). The tab's menu, the Mock back button, the tab marks as small icons beside
the tab, the 0.6 s "goes shortly after the mouse leaves", one calendar line per sync, the steady glow instead of a
pulse (no ticker running for it), the tab scaled with the Scale setting, "Keep open" as a check-marked bar instead of a
tack icon (the owner's later word).

**How the old settings map.** `minimized` is gone (deleted from saved settings once); everyone gets the tab, whatever
it was. `peek` is "Slide out news", `peekSeconds` "How long news stays out". `barHover` is "Open when my mouse rests on
the tab", default **on**. `barInstead` keeps its meaning ("Show news on the tab, not as pop-ups"). Grow direction
and lock apply to Keep open mode (their help says so); lock also locks the tab. The old fade settings are gone:
"See-through when idle" applies to the tab and the kept-open panel. Saved settings hold every default
(`DB.init` merges them in), so a changed default never reaches an existing user by itself: the first run of this
version (`db.panelTabSince`, account-wide) sets `keepOpen` off and `barHover` on for an existing user (one who has the
older marks `panelSince0112` / `fadeOnSince017`), places the tab on the edge nearest to where the panel was, at about
its height (`PanelLogic.tabFromPosition`), turns a grow-up position saved while minimized back into the panel's, keeps
the panel's own position for Keep open, and shows a one-time note (`db.tabNoteDue`; a chat line and a pop-up about
10 s after login, never in a fight or inside a dungeon or raid: it waits, `ns.AwayCard.busy`): "TwizCrew now tucks
away into a small tab. Mouse over the tab, or click it, to see everything. Want it always open? Click Keep open at the
top of the panel." Clicking the pop-up opens the panel (`openTab("note")`): it stays until the mouse has been on the
tab or the panel and left, or at least 6 s. A new install gets the tab and no note.

**Files.** `UI/PanelTab.lua` (was `UI/PanelMini.lua`): the tab, the holder and the slide, the ticker, hover and click,
the news queue and its kinds, pop-up suppression, Keep open. `UI/PanelLogic.lua`: view, hoverOpens, tabCount,
clampTabY, tabSnap, tabFromPosition, tabMarks, newsReactable, newsSeconds, slideWidth, keepLabel, keepSwitchText.
`UI/FeedLogic.lua`: newsEntry, the queue's per-entry lengths (`lengths`), `endAfter`, `has`, afterFight, shortLine.
`UI/Recent.lua`: the rows and entries the Activity tab shares with the Recent window. `UI/Panel.lua`: the Activity tab. Tests: `tests/test_tab.lua`
(was `tests/test_minimize.lua`).

**Only the game can tell:** whether `SetClipsChildren` exists and clips on Forever (and so whether the slide shows or
it pops at once); whether the slide looks smooth and the holder's clamp keeps a tall panel on screen near the bottom
edge; whether `IsMouseOver` on the tab and the panel behaves for hover, the 1 s close and a menu; whether
`IsMouselooking` / `IsMouseButtonDown` exist and stop hover while turning the camera; whether the tab drags and snaps
right and stays on screen after a resolution or UI scale change, and with Scale not 100%;
whether `GetMouseFoci` / `GetMouseFocus` exist on Forever and name the tab and the panel's rows while the mouse is on
them (if not, hover would never open: tell Claude); whether "C R E W" on four lines and the number fit
and read well, and the marks, badge and "!" beside the tab look right; whether the Keep open switch reads as a switch
at a glance; whether the right-edge tooltips and menus land toward the middle; whether re-parenting the panel between
the holder and the screen (Keep open on and off) leaves it in the right place; the one-time note's timing.

## Simpler settings (2026-11-23)

**The owner's words.** "I find that some of the things in my addon might leave people with information paralysis,
for example when looking at the settings there is just a lot there ... maybe subtabs or removing and condensing things
that might be overkill." Claude counted and proposed; the owner chose to remove (not hide) and approved all eight
parts. **This reverses three earlier owner decisions:** "plenty of settings" (2026-11-05), the What's new line that
always shows (v0.1.13) and the "Me: ..." entries on every friend's menu (2026-11-08).

**Counts.** Before: 105 choices in the settings window (93 settings and 12 part switches), 9 buttons, a text box, 2
lists, 15 test buttons and 6 rows that were only notes ("always on", "coming later"); Basics had 22 controls, the
Advanced Panel page 53 rows. After: 59 choices (47 settings and 12 part switches), 5 buttons (How to use, What's
new, My mocks, Tell crew to update, Try it out...) and the crew versions list; Basics has 8 controls and the two help
buttons; the longest page (Panel) 21 rows.

**The window now** (`UI/Settings.lua`: `BASICS` and `SUBTABS` are lists of items; a module no page names lands at the
end of More). Basics: Keep the panel open, Panel size, Fade when I'm not using it, Whose news I get, Pop-ups, News in
my chat, Sounds, Mark me AFK when I stop playing (How to use TwizCrew and What's new are links at the top since the
themes). The other pages: Panel, Alerts, Fun, Find, More (the old All and Test sub-tabs are gone); each ends with a
"Rarely needed" heading. Since the new layout every setting is on exactly one page (see "Themes and icons").
The "always on" and "coming later" rows are gone (Pokes and Group races stay registered, unseen).

**Removed (everyone gets the value shown; the code reads it fixed, the dead branches are deleted).** Panel: How long
news stays out (5 s), the zone / typed status / quest / XP bar / level and XP number lines (row style decides), XP
details on hover (on), Grow direction (automatic, below), the six tag switches (on; the Tags on rows switch still
hides all). Pop-ups: How long they stay (5 s). Roasts: the nine roast-kind switches (on), Add a roast and My roasts
(the My mocks window does both). Hall of Shame: the Wipe Squad line (shown when there were wipes). Find: the meet-up
pop-up, big arrow and minimap parts (one Meet-ups switch). Buttons that only repeated another way in: Show recent
activity, Open the crew calendar, Show today's recap now, Update my spell ranks now. Out of the window but still
working from their own control: Show offline friends and Show the guild online list (the guild online list opens from its bar; the title menu only has Show offline friends),
Only use my own roasts (the My mocks window), Show technical messages (`/tc debug`). Clear the list moved to the
Recent window (a red button next to Close).

**Merged.** "News in my chat" (`activity.chatNews`: off / important / all, default important = deaths, level-ups,
congrats, mocks; all adds online, offline, roasts) replaces the master chat switch and seven per-kind ones.
"Sounds" (`popups.sounds`: off / shows / all, default shows = the mock laugh and the awards show; all adds the
pop-up, level-up and roast sounds; `Popups.soundOn("show" | "all")`) replaces five switches. "Share my quests" now
also decides whether friends may ask for a share (Quest Share requests is gone). "Layer changes" covers both
directions (Back on my layer is gone). "Remind me to update" (the updates module, was Update reminders) also
decides the version chat line (Tell me in chat is gone).

**Saved data** (`Core/DB.lua`). Once per account (`db.simpleSettings`) the two new choices take the old switches:
`DB.chatNewsFrom` (chat off: off; online, offline or roast lines on: all; else important) and `DB.soundsFrom`
(pop-up, level-up or roast sound on: all; mock laugh or awards show sound off: off; else shows). The values are set
explicitly because the defaults are already merged in. Then the keys in `DB.REMOVED_KEYS` are deleted, at every
start (it also cleans data an older copy wrote back). No other mapping: someone who had turned off a removed switch
gets it back on; custom news or pop-up seconds go back to 5; Quest share requests off with Share my quests on lets
friends ask again; Back on my layer off with Layer changes on shows that pop-up again.

**Grow direction (automatic).** When the kept-open panel is dropped after a drag, it is anchored at its top-left
(grows down) if its middle is in the top half of the screen, else at its bottom-left (grows up):
`PanelLogic.growsUp`. The corner stays until the next drag (no flipping while it grows); a reset's "LEFT" default is
converted once. An old grow-up panel keeps its bottom-left corner.

**Outside the window.** Test tools: their own window "Try it out" (`TestTools.open`; More's "Try it out..." button
and `/tc test`; `/tc test help` prints the commands). `/tc help`: about a dozen everyday lines (`Commands.HELP`),
`/tc help more` the rest (`Commands.HELP_MORE`); `/tc guildtest`, `caltest`, `chattest` work but are on neither
list. The wrench menu (so the minimap menu too) lost the two spell-rank switches and Recent activity. A friend's row
menu lost the Me: entries (my own row and the title menu keep Set my status and Go AFK). The panel's What's new line
shows only while there is something new ("New in vX!"); the title, the wrench menu and `/tc new` open What's new any
time. Renamed: Activity tags -> Tags on rows, Layer tracker -> Other-layer warnings, Activity feed -> Activity list,
Stats & Hall of Shame -> Hall of Shame, Update reminders -> Remind me to update, plus plainer labels (Whose news I
get, Panel size, Background darkness, Fade when I'm not using it, Order, Show news from the tab, Open on
mouse-over, No pop-ups for news the tab shows, Mark me AFK when I stop playing, Let the crew roast me, Mock button,
Show the mocker's character, Award titles under names, Watch the crew's awards show, Count my steps). New tip texts
are in `UI/Help.lua` (`sounds`, `chatNews`); the other (i) texts stay with their settings.

**Left for the layout step:** all done with the themes (2026-11-23): one row of six tabs, a grey line under each
Basics control, the "Rarely needed" heading under a thin divider, the two help buttons as links at the top, and
a Clear button on the panel's Activity tab. See "Themes and icons (2026-11-23)".

## Themes and icons (2026-11-23)

**The owner's picks.** After the mock-ups (`looks.html`: L1 = Classic, A1 = Crowned crew, A2 = Tavern night, the Icons
sections) he approved three themes chosen in the settings, one set of 55 icons used in the "must" and "nice" places
of the designer's table, and the settings layout that waited for the look. That shipped in v0.4.0. **The same day,
right after the release, he changed his mind on the themes: "For crew let's use Classic as the default and remove
the other themes."** So now: **Classic is the only look**, there is no theme picker and no `panel.theme` setting,
and the art of the other two (`Art/CrownedCrew`, `Art/TavernNight`) is deleted. The icons stay exactly as they were.
The build document (cut down to what is still true) is `docs/THEMES-SPEC.md`.

**Not tested in the game** (neither v0.4.0's themes nor the Classic-only build).

**The look (Classic).** The game's own dialog art: the panel and the menu in the grey dialog border, cards, pop-ups
and the other windows in the gold-bordered dark dialog box, the tucked tab a small dialog box; the title plate
(`UI-DialogBox-Header`) behind the panel's title (it sticks 10 above the panel) and behind a card's title; the game's
red buttons (Congrats tinted green) and character tabs; the Keep open switch as a game button that lights up while
on; a 1 px gold-brown line fading out after the panel's headings and above "Rarely needed"; gold titles, headings,
tabs and links. No emblem anywhere: nothing hangs under the panel, cards have no watermark, the minimap button keeps
its own icon. Background darkness and the see-through fade work as before. The values are data in `UI/Themes.lua`
(`Theme.CLASSIC`); `UI/Skin.lua` draws them (`Theme.skin`, `skinButton`, `skinTab`, `skinKeep`, `divider`;
`Theme.apply` repaints everything); `Theme.ink` gives texts their colour and outline. No picture files of ours.

**Which windows take it.** The panel and its tucked tab; cards (While you were away, Welcome, Today's recap) and
pop-ups (their coloured edge stays); the settings, Recent activity, calendar, How to use TwizCrew and What's new
windows; the menu; the report, Try it out, My mocks, Set my status, the awards show, the calendar's note maker and
note window, How to update, the test probe window. Not skinned: the Hall of Shame drawing inside the panel (only its
icons), the mock speech bubble, the calendar's day squares, crew rows, pills, the XP bar, the red Reset / Clear
buttons. Every texture call is guarded; no edge (a border, a button's cap) is ever more than half a frame's smaller
side; the pop-ups and the tucked tab have smaller borders (16 and 12, the spec said 32 and 16).

**The tucked panel's holder.** While tucked, the panel hangs in a holder that clips it for the slide. The holder is
taller than the panel by the skin's overhang (the title plate's 10 above, times Panel size; nothing below since the
crest went) and sits that much higher, so the plate is not cut off and the panel is where it always was. The
holder's screen clamp leaves the overhang out (`SetClampRectInsets`).

**Saved data.** v0.4.0 saved `panel.theme` (`"crowned"` by default). It is in `DB.REMOVED_KEYS`, so it is deleted
at every start, like the keys removed by "Simpler settings"; it cannot be set again.

**Icons** (`UI/Icons.lua`; one atlas, `Art/Icons/Icons.tga`, used with its exact texcoords, never the game icons'
0.08 / 0.92 trim). Placed: the Hall of Shame award rows and category buttons (the category icons only when the whole
row fits; else the words alone, as before), the awards show's badge, the row buttons Mock / Mock back / Congrats,
pop-ups (death, roast, level-up, online, running off, a stolen crown, a new guild member), Recent and Activity rows
(when a row has no class icon), an icon left of the news line while news is slid out of the tab, the panel's tabs
(Crew, Hall of Shame, Activity, Calendar; the words are chosen first, as without icons, and the icons show only when
they also fit at that step: icons never take the words' place), the crown or clown before an award title, the card
logos, the settings tabs, and the calendar's "Fun" and "Crew" notes. Kept the game's icons: tags, layer news, quest
share, the meet-up, pins, the header buttons, the tucked tab's marks, the other 14 note kinds.

**Icon fallback.** The first time an icon is drawn, TwizCrew asks the game once whether the atlas loads (a hidden
texture; `SetTexture`'s answer; no answer counts as loaded). Missing: every place draws what it drew before the icons
(no empty squares). `/tc report` has the line "Look: Classic (the game's own art); TwizCrew icons loaded" (or
"missing (the game's icons are shown instead)", or "loaded (the game gave no answer)").

**Upside down?** The atlas is a TGA stored bottom row first. If the icons show upside down, one switch flips them:
`Theme.FLIP_ART` in `UI/Theme.lua`.

**Settings window** (`UI/Settings.lua`). One row of six tabs (Basics, Panel, Alerts, Fun, Find, More) in the game's
tab look, each with its icon (dropped, not the words, if the row is wider than the page); "TwizCrew settings" with
How to use TwizCrew · What's new as links on the title line (they replace the two help buttons); a grey one-line
explanation under each Basics control (words in `UI/Help.lua`, `SETTING_LINES`); "Rarely needed" muted under a thin
divider. Basics starts with "The panel" and Keep the panel open; the Panel page with the Crew panel switch. Every
setting is on exactly one page; the old `setTab("advanced", page)` still works. The panel's Activity tab has a
"Clear" button right of "Scroll for more" (only while there is more to scroll; the Recent window keeps its red one).

**Claude's calls, where the build differs from the spec** (still true).
- The designer's row, pill, XP bar, guild bar and row hover colours are not applied: the brief limited the look to
  frames, header, tabs and buttons, the tucked tab, accent and title font.
- The gold reaches the skinned texts (titles, headings, tabs, links, the Keep open switch), not every gold text drawn
  once at start-up.
- There is no "Clown of the Night" line on the Hall of Shame board, so its 26 px clown icon has no place; the awards
  show's header has no logo, so it got none (its badge uses the icons).
- The Hall of Shame's Trophies tab button gets the trophy icon, so the category row has no gap.

**Files.** `UI/Themes.lua` (Classic as data), `UI/Skin.lua` (drawing it), `UI/Theme.lua` (the file check, the flip,
`Theme.ink`, the report line), `UI/Icons.lua`, `UI/Settings.lua`. Tests: `tests/test_themes.lua`.

**Only the game can tell (riskiest first):** whether Forever loads our icon TGA at all (else the icons are the
game's); whether it shows upside down; whether `SetClampRectInsets` takes its signs as written (if not, a tucked
panel near the very top of the screen sits a little off); whether `SetTexture` really answers false for a missing
file; the icons sharp at 13 to 19 px; how the title plate (sticking 10 above the frame) looks and whether the tucked
panel's holder cuts it while it slides out; the game button and tab textures' texcoords (from memory of Blizzard's
templates); whether the six settings tabs fit with icons.

## Website and Discord (on hold, owner 2026-11-11)

- The owner wants TwizCrew tied to a website (a subfolder of twizgame.com first, movable to its own domain) and
  later Discord. **Put on hold the same day** ("put it on hold i want to work on something else"). Nothing
  designed or built.
- What the owner asked for, Claude's ideas, the suggested order and the open questions:
  `docs/website-and-discord-ideas.md`.

## Decisions (owner)

- **Goal:** slowly build "the ultimate addon" for the owner and a small group of friends, useful for playing
  together and fun. Grow it bit by bit.
- **Modular:** players can turn parts on and off.
- **Two tiers:** the parts that must be there (essentials) are kept apart from the nice-to-have extras.
- **One button sets everything back to defaults.**
- **Settings: Basics and Advanced tabs (2026-11-07):** "too many advanced features... not so daunting". **Since
  2026-11-23 one row of six tabs (Basics, Panel, Alerts, Fun, Find, More): "Themes and icons (2026-11-23)"; what they
  hold: "Simpler settings (2026-11-23)".** Until then the window opened on Basics (transparency, size, row style, panel on/off, offline friends, lock, hide in fights, pop-ups,
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
  Since 2026-11-22 a friend's whole quest log can be asked for too: see "Quest list". Since 2026-11-23 (owner: "yes
  build it") it opens in a window by zone, with ticks and one ask for several: same section, "Quests by zone".
- **Advanced sub-tabs (2026-11-07):** "way too much stuff and takes forever to drag to the bottom". Advanced got
  sub-tabs (Panel, Roasts, Pop-ups, Find, Crew, Test, All); since 2026-11-23 they are Panel, Alerts, Fun, Find, More
  (see "Simpler settings"), now tabs of their own next to Basics (see "Themes and icons").
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
  v0.1.13: the What's new line always stays (dim once read: "so people can always see it"; **reversed 2026-11-23**:
  it shows only while unread); my own row off again
  ("too much clutter", db.panelSince0113); my options (Me: set my status, Me: go AFK; **since 2026-11-23 only on my
  own row and the title menu**, not every friend's) are on every row's right-click
  menu, the place for future "me" actions.
- **Congrats button and Tools (2026-11-08):** a Congrats button on a friend's row for 5 minutes after they level up
  (also: clicking their level-up pop-up, "Congratulate them" in the row menu). It rides on MOCK with k = "g" (older
  copies show a plain line); the friend sees the sender's character /cheer (animation 68) with the level-up fanfare.
  Switch: Roasts, Congrats button. The standalone RankUp addon was merged in as module "rankup" (Tools/RankUp.lua,
  Settings Advanced, More since 2026-11-23, /tc rankup, the wrench menu, optional on-screen button).

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
- **Spell helpers removed (2026-11-09, owner: "it isn't needed"):** the module, its window, /tc spells, the wrench
  menu entry and the "new spell" pop-up are gone. Macros it already made stay in the game's macro list (the owner
  can delete them in /macro). The rank updater (RankUp) now updates every bar spell again.
- **Running-off alarm is silent (2026-11-08, owner):** "I don't mind a visible indication but not a sound". The
  flashing row arrow, the pop-up and the big arrow stay; its raid-warning sound and the "With a sound" setting are
  gone, and the running-off pop-up doesn't play the general pop-up sound either.

- **Crew calendar, step 1 (2026-11-08, v0.1.16):** module "calendar" (Calendar/CalendarLogic.lua pure, Diary.lua
  data and swaps, CalendarUI.lua window, split 2026-11-12 into CalendarUI / Month / Day / Usual / Maker). Each copy writes its own diary: 15-minute slots online (and AFK) per UTC
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
- **One message is one send (TwizCrew, since 2026-11-21):** `Comm.send` sends one `GUILD` message whatever the
  guild's size, through the ~2 a second queue. (Before, in the hidden-channel days, one message was several sends:
  the group, a whisper to each channel member, and the channel.) Only answers to one person are whispers. A live
  feature must still keep its message count low (or replace waiting ones), or it falls behind.
- **History: a brand-new custom channel refuses addon messages for a moment (seen in game, 2026-11-05; the channel is gone since 2026-11-21):** on the owner's
  first login TwizCrew created `TwizCrewHQ`, and the sends in the same second as the join came back with result 7
  (very likely `InvalidChannel`). On the next login every send worked. TwizCrew now waits out refusals for 10 s
  after a join and tries a failed channel again after 1 minute (then 2, 4, 5 min…); details in the crew-panel plan.
- **Sender names come in two forms (seen in game, 2026-11-05; which form a guild message gives is checked by `/tc guildtest`):** channel senders and `UnitName("player")` are
  just the name ("Yaboytwiz"); party and whisper senders came as "Yaboytwiz Noodledog" (the WTF character folder
  is `91/Yaboytwiz-Noodledog`). TwizCrew uses the name before the first space or hyphen as the key (see the guild section for namesakes).
- **Lesson, WoW Forever never delivers addon messages sent to a custom channel (seen in game 2026-11-06, and reported by
  other addon makers: [Blizzard forum](https://us.forums.blizzard.com/en/wow/t/add-on-messages-are-blocked-in-chat-channels/2403369),
  [BFF addon fix](https://github.com/Shtian/bff-wow/pull/133)):** the send says it worked, but nobody gets it,
  not even the sender. That is why friends saw each other as offline (v0.1.4 and older). Joining the channel, its
  member list (`ListChannelByName` → `CHAT_MSG_CHANNEL_LIST`) and join / leave notices still work, and addon
  whispers arrive. That is why the hidden channel was dropped for the guild on 2026-11-21. History: from v0.1.5 the channel was used to see who is in it; automatic mode whispered each member
  (the full name the game gives, e.g. "Yaboytwiz Noodledog"), sends to the group when grouped, and still sends one
  copy to the channel in case the game delivers it again (all gone now; `/tc report` has a Guild line instead).
- **Guild addon messages (research 2026-11-21, other addon makers; our own send and echo seen in game 2026-11-22):**
  `GUILD` addon messages are delivered on Forever 1.60.1 (the guild-vendetta probe: result 0, received, also by the
  sender; ForeverGuild+ and LibGuildSync sync over it). `AreOutgoingAddonChatMessagesRestricted()` is true in the
  open world although guild and whisper addon messages go through (use `InChatMessagingLockdown` and the send
  result). Guild roster names come "with spaces, without a realm" and carry GUID, class, level, rank, note, online and
  last online. Addons cannot write officer notes or the guild info text. `SendChatMessage` to `GUILD` (real chat)
  needs a key press or click. Trial and veteran accounts cannot send addon messages (they look like "no addon").
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
- **Talking to a program on the same PC (Claude Code, a local model), owner asked 2026-11-12, nothing tried in
  game:** there is no direct connection, only side doors. Out of the game: SavedVariables (at `/reload` or logout),
  `Screenshot()` (an image file at once; data can be drawn on screen as coloured squares), the chat log file
  (`/chatlog`, written with a delay). Into the game: the helper writes a Lua data file in the addon folder or the
  SavedVariables file, and the game reads it at the next `/reload` or login (how the WeakAuras, TSM and Raider.IO
  companion apps work); or the player pastes text into a box. Nothing gets in while playing without a `/reload`,
  except a helper that presses keys for you, which Blizzard's rules forbid (do not build).
  Idea (owner asked 2026-11-12): the addon takes a screenshot at a moment (death, wipe, level-up) with a caption
  drawn on screen, a helper watching `_forever_/Screenshots` gives it to a model that can see images, and the
  reaction comes out **outside the game** (spoken voice, a window over the game, a Discord post), since it cannot
  get back in live.
  **Research 2026-11-23 (web and other addons' source, nothing tried by us; the owner is planning a personal
  local-model helper, separate from TwizCrew):**
  - *Correction to the above:* data CAN get in while playing without a `/reload`, by tricks other Forever addons
    use: (1) "slot" addons marked load-on-demand, made before the game starts; a helper writes the next slot's
    Lua file and the addon calls `C_AddOns.LoadAddOn`, which reads it from disk then; each slot works once per UI
    session, a `/reload` frees the pool; a "doorbell" tells the addon mail is waiting (a sound file over 174,762
    bytes is re-read from disk on each play; `C_Sound.IsPlaying` 0.15 s after `PlaySoundFile` tells a real file
    from a missing one; needs game sound on). Measured by t3code-wow under Proton: about 1.2 s. (2) hundreds of
    empty dummy addons as bits through the character's `AddOns.txt` (`C_AddOns.SaveAddOns` / `ResetAddOns` /
    `GetAddOnEnableState`): Windows-only so far, has damaged a player's own addon list, untested on Proton.
  - *Out of the game, live:* the chat log file is NOT live on Forever (written every few minutes or at exit), so
    the only live ways out are a strip of coloured pixels read by screen capture (the technique pixel bots use;
    one author removed it for that reason) or the `AddOns.txt` bits. Chat text inside dungeons, raids and
    battlegrounds is a secret value: an addon can show it but not encode it.
  - *Sending:* `C_ChatInfo.SendChatMessage` to WHISPER, PARTY, RAID, GUILD needs no hardware event per the wiki
    (our own check found guild chat needs a click); a button click is a hardware event anyway. Chat is restricted
    during boss encounters. Copy and paste between Linux and the game under Proton is reported unreliable.
  - *Rules (Blizzard EULA of 2024-03-21, Anti-cheating Agreement, add-on policy):* forbidden and enforced: a
    program pressing keys, reading game memory, "automated control of a Game, or any other feature of the
    Platform" (chat is a feature, so no sends without the player's own click or key). Not named anywhere:
    reading and suggesting. No confirmed ban was found for a tool that only read and suggested. The data-mining
    clause ("reads ... information generated ... by the Platform") is broad on paper. Blizzard's habit with live
    data bridges is to break them by a patch (combat log, 10.2). One self-reported 2023 ban involved a script
    writing addon files plus a reload macro and scripts moving addons ("injecting data into the game").
    Risk order, safest first: output outside the game; reading files the game writes; a data file read at a
    manual `/reload`; pre-filled chat box or paste with the player's Enter; screen pixels with no input; live
    file tricks; automatic chat; pressing keys; memory reading.
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
- **Probes for notes that reach offline guild mates (2026-11-23, results pending):** two test commands, which change
  nothing in TwizCrew, check the two server-side stores in the game before anything is designed. `/tc caltest`
  lists this month's guild calendar events; `/tc caltest make` makes a guild event "TCtest <name>" (typed and by a
  button click, since `AddEvent` wants the player's own action); `/tc caltest remove` deletes it. `/tc chattest`
  reads the guild tab's chat channels (`C_Club` streams), asks the server for older lines and ends with "History kept
  by the server: yes / no / can't tell"; `/tc chattest send` posts a test line. The real test: after a full relog,
  and on a guild mate who was offline at the time, is the event or line still there? Steps: `docs/TESTING.md`,
  "Server-side storage probes". Their lines also go to the saved log.
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
  folder `WTF/Account/*/`. There `Interface/AddOns/TwizCrew` is a plain copy (not a link to the working
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
  bars, waits until a fight ends; by hand 2026-11-06), EllesmereUI 9.8.4 (full UI replacement, 24 folders
  `EllesmereUI*`, https://github.com/EllesmereGaming/EllesmereUI, CurseForge project 1477613; installed 2026-11-10,
  checked latest 2026-11-11), Spy (Forever) 1.3.8-forever26 (CurseForge project 1701654, by hand 2026-11-20; finds
  enemies by nameplate / target / mouseover since Forever has no combat log), and **TwizTracker** (a small starter addon Claude wrote:
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
