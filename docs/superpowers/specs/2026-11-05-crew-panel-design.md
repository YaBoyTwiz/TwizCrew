# TwizCrew v1: Crew panel, layer tracker, pop-ups, settings

Date: 2026-11-05. Status: **draft, waiting for the owner's approval.**
Read `PROJECT.md` first: it holds the game facts, the API limits and where the game is on this PC.

Marked **(owner)** = the owner decided it. Marked **(Claude's call)** = decided by Claude, the owner can overrule.
Everything else unmarked is left to the builder.

## 1. Intent

The owner and about 5 friends (more over time) play World of Warcraft: Forever together. On a busy realm the game
splits the world into **layers** (copies of the world); friends on different layers cannot see each other even when
standing in the same place. Today they have no easy way to tell. **(owner):** "just an easier way to tell when
someone is on a different layer", plus seeing what each friend is doing.

This is the first piece of a long-running project: "the ultimate addon" for this group, grown bit by bit
**(owner)**. So v1 also lays the foundation every later feature plugs into: a module system, a settings window, the
messaging between copies, and a reset button.

## 2. Goals (v1)

1. A **Crew panel**: one movable window with a frame per crew member (class icon, name, level, zone, typed status,
   XP bar, tags). It is the base later features build on **(owner)**.
2. A **layer tracker**: a red **OTHER LAYER** tag on a friend who is on a different layer than you **(owner)**.
3. **Activity tags**: FIGHTING, DEAD, DUNGEON, FLYING, AFK on each friend's frame.
4. **Small pop-ups** for layer changes and deaths **(owner)**.
5. A **modular** addon: parts can be turned on and off **(owner)**, with essentials kept apart from nice-to-have
   extras **(owner)**, and **one button that resets everything to defaults** **(owner)**.
6. **Lots of panel settings** so people tailor the panel rather than turn it off **(owner)**.
7. An **(i) info button on every setting** explaining what it is for **(owner)**.
8. A **version check** that tells you when a crew member runs a newer version (already decided in `PROJECT.md`).

## 3. Non-goals (v1)

- Pokes, soundboard, races, mini-games, quest sync, "come here" ping: later extras.
- Real layer **numbers** ("Layer 2"). v1 only says same / different / unknown (Claude's call: matching each other is
  what the owner asked for, and numbers need data from many players).
- Cross-faction or cross-realm crews (the crew is all one realm and one faction **(owner)**).
- A minimap button (Claude's call; `/twiz` and the Options menu are the ways in; can be an extra later).
- Linking a player's alts into one row. Each character is its own row in v1 (Claude's call).
- Publishing, GitHub repository, releases: nothing is published until the owner says so.
- Merging the existing **TwizTracker** addon into TwizCrew (it stays separate for now).

## 4. Anti-goals (failure even if it "works")

- Anything visible to people outside the crew: no messages in public chat, the hidden channel never shows in chat
  windows.
- Spamming the screen: pop-ups are small, short and only for layer changes and deaths.
- Lua errors on screen, or "Interface action blocked" messages in combat (taint).
- Saying "OTHER LAYER" when it is not sure. **Unknown shows nothing**, never a guess (Claude's call).
- Settings so hidden or confusing that people turn the addon off instead.
- Lag or getting the player disconnected for sending too many messages.

## 5. Constraints

All of `PROJECT.md` → "What an addon can and cannot do in WoW Forever" applies. The ones that shape this design:

- Interface `16001`, Lua 5.1, modern `C_` API names. Many limits are reported by beta testers, not Blizzard: they
  must be **tested in the real game** (see section 13).
- Addon messages: ≤ 255 characters each, a few per second at most; **blocked during boss fights** (queue and send
  after `ENCOUNTER_END`).
- "Secret values" in combat: some unit info can be unreadable. Check `issecretvalue()` before using a value.
- Some interface changes are locked in combat (`InCombatLockdown()`). The panel is a plain frame (no secure buttons),
  so it should be safe; if a change is blocked, wait for `PLAYER_REGEN_ENABLED`.
- The owner streams: everything on screen is on stream.

## 6. Structure: core + modules

**Tiers (owner: essentials apart from extras; Claude's call: the three names):**

| Tier | Can be turned off? | v1 contents |
|---|---|---|
| **Essentials** | No | Crew connection (messaging), Version check, Settings window, Reset |
| **Modules** | Yes | Crew panel, Layer tracker, Activity tags, Pop-ups |
| **Extras** | Yes | None in v1. Shown in settings as grayed "coming later" rows: Pokes & soundboard, Group races |

**The Crew panel is a module, on by default, and can be hidden** **(owner)**. Hiding the panel does not stop
pop-ups.

**Module contract (Claude's call, the builder shapes the details):** each module registers itself with the core
giving its id, display name, tier, an info text, its **defaults table**, its settings list (each setting with label,
type, default and info text), and enable/disable hooks. The settings window is built from these registrations, so a
new module appears in settings automatically. Turning a module off unregisters its events and hides its frames.

**What a module switch controls (Claude's call):** what **you see**. Your copy keeps **sharing** your own data
(zone, level, tags, layer key) with the crew regardless, because that is the crew connection, an essential. This
keeps one person's settings from breaking another person's panel.

**Defaults live in one place** per module and the reset button restores all of them (section 11).

## 7. Crew connection (essential)

- **Same realm, same faction, no guild yet** **(owner)**.
- **Hidden custom channel (Claude's call):** on login the addon joins a password-protected custom chat channel and
  removes it from every chat window so it is never seen. All copies send to it with
  `C_ChatInfo.SendAddonMessage(prefix, text, "CHANNEL", channelIndex)`. This works when not grouped and across zones.
  Channel name and password: built-in defaults, changeable in settings as a "crew code" (so the crew can change it if
  it leaks; the repository will be public). Exact names are the builder's call.
- **When grouped**, also send to `PARTY` / `RAID` (builder decides whether to send twice or prefer one; receivers
  must ignore duplicates).
- **Later guild:** a setting switches the channel to `GUILD`. Not needed for v1 but the sending code should take the
  channel as a setting, not hard-code it.
- **Fallback if custom channels do not work in Forever:** whisper each known crew member (`WHISPER`). Fine for ~5–10.
- **Prefix:** one registered prefix, e.g. `TwizCrew` (≤ 16 characters).
- **Message types (Claude's call, the builder designs the exact format):**
  - `HELLO`: sent on login / `/reload`; includes version. Every copy that hears it answers with its full state
    (spread out by a small random delay so they don't all answer at once).
  - `STATE`: full snapshot (class, level, XP %, zone, subzone, typed status, tags, layer key, version).
  - `UPDATE`: only the fields that changed. Sent when something changes.
  - `PING`: "still here", about every 60 seconds.
  - Every message starts with a protocol version number so future versions can tell old messages apart.
- **Offline:** no message from someone for about 3 minutes → shown as offline with "last seen …". Also use a clean
  logout message if one can be sent at `PLAYER_LOGOUT` (best effort).
- **Throttle:** one send queue for the whole addon; a few messages per second at most; merge repeated updates for the
  same field; hold everything during boss fights and send after `ENCOUNTER_END`.
- **Crew list memory:** the last known class, level, zone and time seen of each crew member is saved
  (SavedVariables), so offline friends can show greyed out after a restart.
- **Who is crew:** anyone running TwizCrew who sends on the crew channel with the right prefix.

## 8. Crew panel (module, on by default)

**Look (owner):** party-frame style rows (mockup "B"), tags as coloured pills in the frame's corner.
**Class icons (owner):** use the game's built-in class icons (e.g. the atlas `classicon-<class>` or the texture
`Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES` with `CLASS_ICON_TCOORDS`; test which exists in
Forever). No custom art needed.

Each frame shows, in Full style:
- Class icon, name in class colour, level
- Zone, subzone (e.g. "Elwynn Forest, Goldshire"; "Flight to Stormwind" when on a flight path)
- Typed status, if set (e.g. "LF Deadmines")
- XP bar (Claude's call: XP instead of health; health would need constant messages and is secret in combat)
- Tags in the corner (section 9)
- Offline: greyed out, "Offline, last seen 2h ago"

Header: "TwizCrew" and "4 of 5 online". Right-click on the header opens a small menu with the most-used switches
(Claude's call).

Typed status: set with `/twiz status <text>` and from the right-click menu; `/twiz status` alone clears it. Short
limit (about 40 characters, builder's call). Shared to the crew.

**Panel settings (owner: "plenty of ways"; Claude's list, each with an (i) button):**

| Group | Setting | Default |
|---|---|---|
| Size & look | Scale | 100 % |
| | Background opacity | ~80 % |
| | Row style: Full / Compact (icon, name, level, tags) / Tiny (icon, name, tags) | Full |
| | Show zone line | on |
| | Show typed status | on |
| | Show XP bar | on |
| | Fade when the mouse is not over it (and how much) | off |
| Where & when | Show panel | on |
| | Lock position | off |
| | Grow direction: down / up | down |
| | Hide during fights | off |
| | Hide in dungeons and raids | off |
| | Hide when no crew is online | off |
| | Show offline friends | on |
| What's on it | Sort: name / level / online first / same layer first | online first |
| | Show myself in the list | off |
| | Each tag on or off one by one (OTHER LAYER, FIGHTING, DEAD, DUNGEON, FLYING, AFK) | all on |

More than ~8 rows: the panel scrolls (or the builder picks a better way to grow; Claude's call to keep ~5 rows the
designed-for case).

Tags can also have a hover tooltip saying what they mean (Claude's call, in the spirit of the (i) request).

## 9. Activity tags (module)

| Tag | Meaning | How it is detected (sender side) |
|---|---|---|
| OTHER LAYER | not on your layer | layer tracker, computed on the receiver side (section 10) |
| FIGHTING | in combat | `PLAYER_REGEN_DISABLED` / `ENABLED` |
| DEAD | dead or a ghost | `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`, `UnitIsDeadOrGhost("player")` |
| DUNGEON | inside a dungeon or raid | `IsInInstance()` type `party` / `raid` |
| FLYING | on a flight path | `UnitOnTaxi("player")` |
| AFK | flagged away | `PLAYER_FLAGS_CHANGED`, `UnitIsAFK("player")` |

Several tags can show at once. If space is short, show by priority: DEAD, OTHER LAYER, FIGHTING, DUNGEON, FLYING, AFK
(Claude's call).

## 10. Layer tracker (module)

**How (Claude's call, a well-known method):** every NPC has a GUID like
`Creature-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]`. The zone part differs per layer. The addon reads
GUIDs of NPCs the player mouses over, targets, or sees nameplates for (`UPDATE_MOUSEOVER_UNIT`,
`PLAYER_TARGET_CHANGED`, `NAME_PLATE_UNIT_ADDED`), keeps only `Creature` / `Vehicle` types (not pets, not players),
and builds a **layer key** from it together with the current continent / map. It shares the key with the crew.

**Comparing:** two players are compared only when both keys are known **and** both are on the same continent and
not inside an instance. Different keys → OTHER LAYER on that friend. Same → nothing. Anything missing → nothing
(unknown never shows as different).

**When a key becomes stale (unknown again):** changing continent, entering or leaving an instance, a loading screen,
joining or leaving a group (the game can move you to the leader's layer), and after a time limit with no new NPC
seen (builder's call, e.g. 10 minutes). Then it waits for the next NPC.

**Avoid flicker:** a builder's call, e.g. need two matching readings before announcing a change.

**Secret values:** if a GUID comes back secret (`issecretvalue`), skip it.

**Unknowns to test first (section 13):** whether Forever has layering at all, and whether the GUID zone part really
differs per layer in Forever. If either fails, the module stays in the code, shows nothing, and the owner is told.

## 11. Pop-ups (module)

**(owner):** a small pop-up for layer changes and deaths.

- "**Frostie** is on a different layer" (and the hint "Click to invite them to your group"). Clicking it sends a
  group invite, which makes the game move them to the leader's layer (Claude's idea, the owner can drop it).
  `C_PartyInfo.InviteUnit(name)` is a click, so it is allowed.
- "**Ginkan** is back on your layer".
- "**Holyboi** died" with the zone and subzone below.
- Near the top centre of the screen, about 5 seconds, then fade; several stack (newest on top or bottom: builder's
  call). Movable position can be a setting (builder's call).
- **When the layer pop-ups fire (Claude's call):**
  - "different layer" when a friend goes from same → different, **or** unknown → different (e.g. a friend logs in
    already on another layer: that is the main case the owner wants to know about).
  - "back on your layer" when a friend goes from different → same. Unknown → same is quiet.
  - Changes that arrive within a few seconds of each other are **combined** into one pop-up ("Frostie and Ginkan are
    on a different layer"; "3 friends are on a different layer"), so when **you** change layer you get one pop-up,
    not one per friend.
  - For the first ~30 seconds after your own login or `/reload`, stay quiet, then show one combined pop-up for anyone
    on a different layer.
- They still show during fights (Claude's call; they are small).
- Deaths during a boss fight arrive late (messages are blocked until the fight ends). Acceptable.

| Setting | Default |
|---|---|
| Pop-up: layer changes | on |
| Pop-up: back on my layer | on |
| Pop-up: deaths | on |
| Play a sound | **off** |
| How long it stays (seconds) | 5 |

## 12. Settings window (essential) and reset

- Opened with **`/twiz`** and from the game's **Options → AddOns** (register a category with the `Settings` API; the
  builder decides whether the full window lives there or the category just opens our own window).
- Header: name, version, "everyone up to date" or "Ginkan has v1.3, you have v1.2. Update in WowUp."
- Sections in order: **Essentials** (no off switch, still have small options), **Modules** (on/off + their
  settings), **Extras** (grayed "coming later" in v1).
- **(i) button next to every setting and every module** **(owner)**: hover (and click, for people who don't hover)
  shows a short plain explanation of what it does and why someone would change it. Info text is part of each
  setting's registration so no setting can be added without one.
- **Reset everything to defaults** **(owner)** at the bottom; asks "Reset all TwizCrew settings and the panel
  position?" Yes / No. Resets every setting of every module and the panel position. It does **not** delete the saved
  crew list or the crew code (Claude's call: a reset should fix the look, not disconnect you from your friends).
- Chat commands (Claude's call): `/twiz` is **already taken** by the owner's TwizTracker addon, so TwizCrew uses
  **`/tc`** and **`/twizcrew`** (same commands): `/tc` (settings), `/tc show`, `/tc hide`, `/tc status <text>`,
  `/tc reset` (asks first). Wherever this document says `/twiz`, read `/tc`.
- Settings are saved account-wide in SavedVariables (Claude's call), so every character of a player looks the same.
  The builder can make the panel position per character if that proves nicer.

## 13. Test in the game before building on it

The builder should do the risky checks first, in the real game, before building everything on top:

1. Interface number is `16001`; the `.toc` loads.
2. Custom channel: join, hide from chat, `SendAddonMessage` over `CHANNEL` reaches a friend who is not grouped.
3. Layering exists in Forever, and NPC GUID zone parts differ between two friends on different layers (needs two
   players; joining a group moves layers, so it is testable).
4. Class icon atlas or texture shows.
5. `UnitOnTaxi`, `UnitIsAFK`, `IsInInstance` behave as expected.
6. No Lua errors, no "action blocked" in combat.

The owner can test alone for most things; items 2 and 3 need at least one friend.

**How testing will happen (owner):** "we will test with WowUp", and the owner **cannot test right now**. So the
whole v1 is built before any of the risky parts are proven, and testing with friends needs the public GitHub
repository + WowUp setup from `PROJECT.md` (only when the owner says "publish"). Therefore:

### Built to be fixed (owner: "build in a way that will make it easier to fix if something doesn't work")

- **Risky parts sit behind small swappable pieces (Claude's call):**
  - *Transport:* one sender/receiver with interchangeable ways to deliver: hidden `CHANNEL`, `PARTY`/`RAID`,
    `WHISPER` to each known crew member, later `GUILD`. Selectable in settings (Essentials, with an (i) button;
    default "automatic": try the channel, fall back to whispers if the channel cannot be joined or sends fail).
    A fix should be a setting change or a few lines, not a rewrite.
  - *Layer detection:* one function "give me my layer key" and one "are these two keys the same layer". The GUID
    method lives only there, so a different method can replace it without touching the panel or pop-ups.
  - *Class icons:* one function returning the icon; try the atlas, then the texture, then nothing (text only).
- **Every risky call is protected:** wrapped so a failure is caught (`pcall`), logged, and the feature that failed
  turns itself off quietly instead of throwing Lua errors on screen. The rest keeps working.
- **Debug log the owner never has to read:** a rolling log (last ~500 lines: what was sent and received, layer keys
  seen, errors, which fallback was used) saved in SavedVariables. After a `/reload` it is on disk in the WTF folder
  on the owner's PC, so **Claude can read it directly** and see what went wrong. Friends' logs: they can paste the
  output of `/tc report` (below) into Discord.
- **`/tc report`:** prints a short health check in chat and puts it in a box to copy: version, interface number,
  which transport is working, last message heard from each crew member, own layer key and when it was last seen,
  class icon method, recent errors. One look tells what broke.
- **`/tc debug`:** toggles extra chat output for live checking (off by default; never on during stream unless
  turned on).
- **Old and new copies tolerate each other:** messages carry a protocol version; unknown fields and unknown message
  types are ignored, so a fixed version can roll out to the crew one person at a time.
- **Settings that might need fixing are named, not hard-coded:** channel name, timings (ping interval, offline
  timeout, stale-layer timer, pop-up time) are in one config table, easy to change.

## 14. Files and setup (Claude's call)

- Source in this folder: `TwizCrew/` with `TwizCrew.toc` (`## Interface: 16001`, `## SavedVariables: TwizCrewDB`),
  core files, one file (or folder) per module.
- A symbolic link from the AddOns folder (path in `PROJECT.md`) to the source, so edit + `/reload` is the loop.
- Pure logic (message encode/decode, layer key compare, defaults/reset) should be written so it can be tested
  outside the game with plain Lua 5.1; UI is tested in game.
- "TwizCrew" is still a working name; the folder name becomes the addon name, so the owner picks the final name
  before friends install it.

## 15. Left to the builder

Exact message format and field names; channel name and password defaults; file layout; how the settings window is
drawn; the module registration API shape; colours and sizes (the mockups are the guide: dark frame, gold border, gold
title, class colours, coloured tag pills); pop-up animation; stale-layer timer; flicker rule; scroll vs other
growth past ~8 rows; whether to also show a short chat line for the version check.

## 16. Mockups

In `.superpowers/brainstorm/` (local only): `layer-display.html` (A/B/C, owner picked B look and the A panel as
base), `crew-panel-v2.html`, `popups.html`, `settings.html`.
