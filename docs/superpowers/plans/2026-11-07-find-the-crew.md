# TwizCrew: Find the crew — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** arrows to group members on the Crew panel, a big arrow on click, and a crew meet-up placed by
Ctrl + right-click on the world map (party or everyone), shown as a pop-up, a big arrow and an icon on the maps.

**Architecture:** one new extras module, `find` ("Find the crew"), in a new `TwizCrew/Find/` folder: pure maths and
rules (`FindLogic`), safe game reads (`Where`), the module itself (`Find`: positions in and out, meet-ups), the big
arrow (`BigArrow`) and the map side (`MeetMap`: map click, world map and minimap icons). The Crew panel draws the
row arrows from `ns.Find.arrowFor(name)`. Two new message types: `POS` (group only) and `MEET`.

**Tech Stack:** Lua 5.1 (WoW Forever, Interface 16001), the repo's own test runner (`tests/run.sh`, fake game in
`tests/wowstub.lua`, multi-client harness in `tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-07-find-the-crew-design.md` (approved by the owner, "do it").

Builds on every earlier plan; their Global Constraints and "Changes during build" still hold.

## Global Constraints

- Lua 5.1, every handler inside `ns.Log.safe` (Widgets.script for frame scripts), plain words, local commits only,
  no version bump, no `RESTART_SINCE` change, no release, no push.
- `tests/run.sh` ends with `ALL PASSED`, including the 598 earlier tests.
- **Never** call `C_Map.SetUserWaypoint`, `C_Map.ClearUserWaypoint` or anything in `C_SuperTrack` (a lint test checks).
- Positions only to the group (`PARTY` / `RAID`), never whispered; not in a group = no position messages at all.
- Meet-up audience: `party` or `all`, the sender's choice; placed only by Ctrl + right-click on the world map.
- No in-world marker, no friend dots on the maps.
- Every position / facing read goes through `pcall` and `issecretvalue`; unknown = hidden, never an error.
- Don't touch other addons' code; never write the owner's WoW account folder name into the repo.
- New files and `.toc` lines are allowed (the release that ships this sets `RESTART_SINCE`; not this plan).

## Claude's calls (the owner can overrule)

1. **Numbers:** position check every 1 s; a POS goes out when you moved 10+ yards and the last one is 3+ s old, or
   30 s passed (keep-alive), or the group changed (then right away, at most once a second). A position older than
   60 s is unknown. Row arrows hide within 15 yards; the big arrow closes within 15 yards of a friend and 20 yards
   of a meet-up. A meet-up lives 15 minutes.
2. **POS fields:** `c` (continent / instance id from `C_Map.GetWorldPosFromMapPos`), `x`, `y` (world yards, whole
   numbers; x = north, y = west, as the game gives them), or `u=1` (unknown: instance, no position).
3. **MEET fields:** `id`, `c`, `x`, `y`, `p` (place name), `a` (`party` / `all`), `l` (seconds left); a clear is
   `id` + `clr=1` + `a`. Same id again = an update, never a second pop-up.
4. **Late joiners:** only the sender's copy resends: an "everyone" meet-up to a friend who comes online
   (`Comm.sendTo`, else to all), a party meet-up to the group when it grows. (The spec said "rides along with STATE";
   this does the same job without making STATE longer.)
5. **Live party positions:** `UnitPosition` on party / raid units when readable and not secret, else the friend's
   last POS.
6. **Row arrow:** a small button at the right of the name line: same zone = rotating arrow + "120 yd"; same
   continent but another zone = a still arrow icon, no distance (tooltip says the zone); click = big arrow. Tiny
   rows drop the distance text.
7. **Big arrow:** default spot `TOP`, x 230, y -150 (QuestMaster's arrow sits at `TOP`, 0, -150). Draggable unless
   the Crew panel is locked; position saved in the module. If facing can't be read: north-up compass with "N".
8. **Map icons:** a frame on the world map's canvas (`WorldMapFrame:GetCanvas()`), placed from the meet-up's world
   position with `C_Map.GetMapPosFromWorldPos` (or `OpenMapAPI.CanvasFromWorldPos` while OpenMap shows its stitched
   map); minimap icon placed by our own maths (zoom table, rotating minimap, indoor / outdoor, edge when far, using
   `MinimapLogic.offset` for the edge). No library needed.
9. **Map click:** a hook on the world map's canvas `OnMouseUp` (and OpenMap's stitched view through the same canvas):
   Ctrl + right-click → menu at the cursor "Meet here: My party / Everyone / Cancel" (only Everyone when not grouped).
   The map point comes from `WorldMapFrame:GetNormalizedCursorPosition()` + `GetMapID()`, or
   `OpenMapAPI.CursorPosition` + `MapAt` + `MapFromWorld` while stitched.
10. **Settings (module `find`, extras, on by default):** `rowArrows`, `meetups`, `sharePosition` (Basics, under
    "Handy"); `meetPopup`, `meetArrow`, `meetMinimap`, `arrowScale`, `arrowPos` (Advanced).
11. **Pop-up:** new pop-up kind `meet` in the existing system ("Twiz wants to meet up", place + "click to point the
    way"; click = big arrow to the meet-up), shown even in the login quiet time, same sound switch.
12. **Try it out:** a "Walking buddy" button: a pretend group member who walks around near you (POS through the real
    code), and a pretend meet-up 120 yards north of you.

## Review Focus

1. Not in a group, or the group breaks up: no POS is sent and every row arrow disappears (test: positions after
   leaving the group).
2. A party meet-up from someone not in your group (they left, or a stale message): ignored (test).
3. Your own position unknown (instance, missing map APIs, secret values): no arrows, no POS, no errors (test).
4. A meet-up clicked on a map the game can't place (whole world, instance): nothing sent, one short line (test).
5. Two meet-ups at once: the newest wins everywhere; clearing an old id doesn't clear the new one (test).

## File map

```
TwizCrew/Find/FindLogic.lua   pure: vectors, bearing, distance text, arrow state, send rule, meet-up life, minimap maths
TwizCrew/Find/Where.lua       safe game reads: my position / facing / zone, party unit positions, map <-> world
TwizCrew/Find/Find.lua        module "find": POS out/in, meet-ups (MEET), arrowFor, /tc meet, report line
TwizCrew/Find/BigArrow.lua    the big arrow frame
TwizCrew/Find/MeetMap.lua     Ctrl + right-click on the world map, meet-up icon on the world map and minimap
TwizCrew/Comm/Codec.lua       + POS, MEET
TwizCrew/Comm/Queue.lua       + Queue:replace(key, item)
TwizCrew/Comm/Transport.lua   + Transport.groupDestination()
TwizCrew/Comm/Comm.lua        + Comm.sendGroup(msgType, fields, opts)
TwizCrew/UI/Panel.lua         row arrow button + distance, a light ticker that turns visible arrows
TwizCrew/UI/PopupLogic.lua    + kind "meet";  TwizCrew/UI/Popups.lua + Popups.meet(name, place)
TwizCrew/UI/Settings.lua      Basics: the three find switches
TwizCrew/UI/Commands.lua      /tc meet clear;  TwizCrew/UI/Report.lua report line + "Walking buddy"
TwizCrew/Core/Init.lua        + FIND_* numbers;  TwizCrew/TwizCrew.toc + the five files
tests/wowstub.lua             + C_Map, GetPlayerFacing, CreateVector2D, IsControlKeyDown, IsIndoors, GetCVar, WorldMapFrame
tests/test_findlogic.lua, tests/test_find.lua, tests/test_find_ui.lua, tests/test_sim_find.lua
```

## Tasks

### Task 1: FindLogic (pure)

**Files:** Create `TwizCrew/Find/FindLogic.lua`, `tests/test_findlogic.lua`.

**Produces:**
- `FindLogic.vector(from, to) -> distance, bearing` (`from`/`to` = `{ c, x, y }`; nil when continents differ or a
  value is missing; bearing radians counter-clockwise from north = `atan2(dy, dx)`).
- `FindLogic.relative(bearing, facing) -> angle` (wrapped to (-pi, pi]; facing nil -> bearing, "compass").
- `FindLogic.distanceText(yards) -> "120 yd" | "1.2k yd"` (under 1000 whole yards, else one decimal "k").
- `FindLogic.rowArrow(me, them, now, opts) -> nil | { angle, text, still }` (rules: unknown / stale (opts.staleAfter)
  / other continent / within opts.near -> nil; other zone -> `{ still = true }`).
- `FindLogic.shouldSend(last, pos, now, cfg) -> bool` (moved >= cfg.move and >= cfg.gap since last, or >= cfg.keepAlive).
- `FindLogic.meetLeft(meet, now) -> seconds` (0 when over).
- `FindLogic.minimapOffset(dist, bearing, facing, rotate, zoom, indoors, width) -> x, y, onEdge`.

- [ ] Tests first: distance / bearing for north, west, east, south; other continent -> nil; relative wraps; text at
  999 / 1000 / 1234 yards; rowArrow: stale, near, same zone, other zone; shouldSend: still, moved, keep-alive;
  minimapOffset: north up when not rotating, east on the right, rotation follows facing, far = on the edge.
- [ ] Implement; `tests/run.sh findlogic` passes; commit.

### Task 2: Fake game + Where

**Files:** Modify `tests/wowstub.lua`; create `TwizCrew/Find/Where.lua`, tests in `tests/test_find.lua`.

**Produces:** `Where.me() -> { c, x, y, map, zone } | nil`, `Where.facing() -> radians | nil`,
`Where.unitFor(name) -> unit | nil` (party / raid token), `Where.unit(unit) -> { c, x, y } | nil`,
`Where.toWorld(mapID, mx, my) -> c, x, y | nil`, `Where.toMap(mapID, c, x, y) -> mx, my | nil`,
`Where.mapName(mapID) -> string | nil`, `Where.inGroup() -> bool`.

Fake game state: `st.map = { id, x, y }` (player on map), `st.maps[id] = { c, x0, y0, x1, y1, name }` (map corners in
world yards, a straight line between them), `st.facing`, `st.indoors`, `st.cvars`, `st.ctrl`, `st.worldMap`
(`{ shown, mapID, cursor = { x, y } }`). All hideable through `st.missing`.

- [ ] Tests first: position read through map APIs; secret value / missing API / instance -> nil; facing nil when
  secret; party unit found by short name; toWorld / toMap round trip.
- [ ] Implement; tests pass; commit.

### Task 3: Messages: POS, MEET, group-only send, replace unsent

**Files:** Modify `Codec.lua`, `Queue.lua`, `Transport.lua`, `Comm.lua`; tests in `test_queue.lua`, `test_comm.lua`.

**Produces:** `Queue:replace(key, item)` (an unsent item with the same `key` gets the new text, else pushed),
`Transport.groupDestination() -> dest | nil`, `Comm.sendGroup(msgType, fields, opts) -> bool` (false, nothing sent,
when not in a group; opts.replace = key).

- [ ] Tests first: replace keeps one item; sendGroup sends one PARTY message, never a WHISPER or CHANNEL, returns
  false alone; POS and MEET decode.
- [ ] Implement; tests pass; commit.

### Task 4: Find module (positions, meet-ups, command, report)

**Files:** Create `TwizCrew/Find/Find.lua`; modify `Init.lua` (FIND_* numbers), `.toc`, `Commands.lua`,
`Report.lua`, `PopupLogic.lua`, `Popups.lua`; tests `test_find.lua`, `test_sim_find.lua`.

**Produces:** `Find.arrowFor(name) -> nil | { angle, text, still, compass }`, `Find.positionOf(name)`,
`Find.meet() -> meet | nil`, `Find.placeMeet(mapID, mx, my, audience) -> ok, why`, `Find.clearMeet()`,
`Find.reportLine()`, Bus `FIND_CHANGED` (arrow set or meet-up changed). `Popups.meet(name, place)`.

- [ ] Tests first: POS only when grouped and moved; replace unsent; keep-alive; nothing in instances; positions
  from non-group senders ignored; stale after 60 s; party meet-up reaches the party only (sim); everyone meet-up
  reaches all and a friend who logs in later; newest wins; clear by anyone; expiry; `sharePosition` off sends
  nothing; `/tc meet clear`; report line.
- [ ] Implement; tests pass; commit.

### Task 5: Big arrow and row arrows

**Files:** Create `TwizCrew/Find/BigArrow.lua`; modify `Panel.lua`; tests `test_find_ui.lua`.

**Produces:** `BigArrow.point(target)` (`{ kind = "member", name }` or `{ kind = "meet" }`), `BigArrow.close()`,
`BigArrow.stateForTest()`; `Panel.rowArrowForTest(i)`.

- [ ] Tests first: row arrow shown only for group members in the same zone (text), still for another zone, none
  outside the group; click opens the big arrow; arrival closes it; meet-up opens it (setting); compass when no facing.
- [ ] Implement; tests pass; commit.

### Task 6: Map click and map icons

**Files:** Create `TwizCrew/Find/MeetMap.lua`; tests in `test_find_ui.lua`.

- [ ] Tests first: Ctrl + right-click on the map opens the menu (party + everyone when grouped, everyone alone);
  choosing sends MEET; a plain right-click does nothing; a map without world coordinates says "Pick a spot inside a
  zone"; the world map icon shows for the active meet-up; minimap icon follows `meetMinimap`; lint: no waypoint calls.
- [ ] Implement; tests pass; commit.

### Task 7: Try it out, Basics, docs

- [ ] "Walking buddy" test button and `/tc test walk`; Basics rows; README Use line; `docs/TESTING.md`; `PROJECT.md`.
- [ ] Whole-branch review, fixes, `tests/run.sh` ALL PASSED, commit.

## Changes during build

(filled in while building)
