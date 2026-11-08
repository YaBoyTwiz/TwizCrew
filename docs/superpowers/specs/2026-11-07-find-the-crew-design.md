# TwizCrew: Find the crew — Design

**Owner's words (2026-11-07):** "right now me and my crew are focused on questing, meeting up and levelling
together, its kinda dynamic because we all keep dropping in and out going afk and coming back etc, but we always get
together, sometimes we lose track of where everyone ran off to." Borrowing from other addons is fine.

**Group only (owner, 2026-11-07):** "we dont need position updates for players not in the group, seems wasteful".
Positions are shared **only with friends in your group**. Friends outside the group show their zone on the panel,
as now, and nothing more.

**Approved by the owner ("do it", 2026-11-07)** after this was played back in chat: arrows on each Crew panel row,
a big arrow on click, friends on the map, a "meet here" pin, and our arrow / pins looking clearly different from
QuestMaster's ("we can keep both, lets just make sure our arrow/waypoint looks different"). Changed after that by
the owner: positions in the group only, no friend dots on the map (the game shows party members already), and the
meet-up goes to the party or everyone, the sender's choice, and shows on the map.

Builds on v1 (`2026-11-05-crew-panel-design.md`) and every later plan; their Global Constraints still hold.

## 1. Why, and what success looks like

The crew plays loosely: people drop out, go AFK, come back, wander off to finish a quest. The panel already says
each friend's zone and sub-zone. What's missing is **"where exactly, and which way do I go?"** Success: a friend
comes back from AFK, glances at the Crew panel, sees an arrow and "340 yd" next to Frostie's name, and walks there
without typing "where r u" in chat.

## 2. What gets built

### 2a. Arrow on each Crew panel row (owner approved as described)

- Only for friends **in your group** (owner: group only).
- A small arrow next to the friend's name **points toward them as you turn**, with the distance under or
  beside it ("120 yd").
- Only when **you and they are in the same zone**. Otherwise the row shows their zone, as it does now.
- **Hidden in dungeons / instances** (the game gives no position there), and when they are **right next to you**
  (about 15 yards).
- Follows them live if the game gives party positions (see 4); otherwise updates every few seconds from positions
  the friend's copy sends to the group.
- In the friend's **class colour**, like their row.

### 2b. The big arrow (owner approved as described)

- Shows only when you **click a group member's row arrow** (or a meet-up, 2d). It points the way with the friend's name
  and the distance; **it goes away by itself when you arrive** (about 15 yards) and can be closed with a click.
- Class-coloured, with the name under it, so it can't be mistaken for QuestMaster's gold / grey arrow. Movable;
  follows the panel's "lock" setting.
- **Claude's call:** the big arrow also works when the group member (or meet-up spot) is in **another zone on the same
  continent** (it says "Westfall · 1.2k yd"). The row arrows stay same-zone only, as approved. Why: the big arrow
  is the "take me there" tool, and the far case is exactly when you need it. Cost if wrong: one rule to tighten.
  Since row arrows are same-zone only, a far group member's big arrow starts from a small arrow button that
  replaces the zone text's spot on their row (builder's call on the exact spot; never the dead friend's Mock button).

### 2c. On the map: only the meet-up (owner, 2026-11-07)

- **No friend dots** (owner: "we dont need minimap updates if they are in the party, i just need the arrows"). The
  game already shows every group member on the world map and minimap with its own party dots.
- **The meet-up spot shows on the map** (owner: "it can draw on the map"): a TwizCrew icon on the **world map** and,
  Claude's call, the **minimap** too (on the edge when it's off the minimap; handles a rotating minimap, every zoom
  level, indoors and outdoors). The sender's name on hover. Never the game's waypoint pin.
- Must work on Blizzard's world map **and OpenMap's stitched map** (the owner uses OpenMap; friends may not).
  OpenMap has a public `OpenMapAPI` (`AddOns/OpenMap/API.lua`, e.g. `CanvasFromWorldPos`); Questie's pins work on
  it today, so the same method Questie uses should too. The builder checks.
- **Placing a meet-up is a click on the world map** (2d). Clicking in the 3D world can't work: the game never tells
  an addon where a click in the world lands (told to the owner, 2026-11-07).

### 2d. Meet-up (owner: "keep the meet up but make it so we can choose between just for the party or everyone")

- **Only from the world map** (owner: "we dont need a come to me, we should just be able to click a spot on the
  world map"). No "Come to me" button and no "send my own spot" command. Claude's call: **Ctrl + right-click** a
  spot on the world map (Blizzard's map and OpenMap's stitched map); the builder checks it doesn't clash with
  OpenMap, Questie, QuestMaster or the game's own map clicks, and picks another modifier if it does. The spot must
  be on a zone or continent map the game can turn into world coordinates; elsewhere (the whole-world view, an
  instance map) the click does nothing but a short "Pick a spot inside a zone" line.
- Whoever sends it **chooses who gets it: just the party, or everyone in the crew** (owner). Claude's call on how:
  after the click, a small menu at the cursor asks "Meet here: My party / Everyone / Cancel". Not in a group: only
  "Everyone" (and Cancel).
- Friends who get it see a **small pop-up** through the existing pop-up system ("Twiz wants to meet up: Goldshire"),
  with the same sound rules as the other pop-ups (off by default), and **their big arrow turns on toward the spot**
  (setting, on by default; works anywhere on the same continent, see 2b). Plus the icon on their maps (2c).
- **One meet-up at a time:** the newest replaces the old one for everyone who got it (Claude's call). It shows who
  sent it.
- It ends after **15 minutes**, when anyone it went to clears it (right-click the meet-up icon on the map → "Clear", or `/tc meet clear`), or when a new
  one replaces it. Arriving within ~20 yards closes **your** big arrow ("You're here") but leaves the meet-up for the
  others.

### 2e. Smaller rules (Claude's calls, from the builder check)

- A meet-up **reaches friends who come online later** if it was sent to everyone (it rides along with STATE while it
  lives); a party-only meet-up reaches whoever joins the party while it lives.
- A new meet-up **switches an open big arrow to the meet-up spot** (it's the newest "go here").
- If `GetPlayerFacing` can't be read, row arrows and the big arrow **turn into a compass**: north-up arrow with
  the distance, and a small "N" mark so nobody reads it as "ahead of you". If even positions are unknown, nothing
  shows.
- **Try it out** gets pretend group members who walk around, so the arrows and a meet-up can be seen without the crew.

## 3. Goals, non-goals, anti-goals

**Goals:** find a friend in seconds; see at a glance who is near and which way; meet up with one click.

**Non-goals (this round):** shared quest progress, one-click group invites, back-from-AFK alerts, in-world 3D
markers. **In-world marker at the meet-up spot: the owner asked, then said "dont worry about the marker for now"
(2026-11-07).** It would need the game's single super-track slot, which QuestMaster uses (see PROJECT.md, "In-world
waypoints"), so it was left for later. **Back-from-AFK alerts were suggested in chat but are left out on purpose:** the owner decided on
2026-11-07 that AFK shows in the panel only, with no AFK pop-ups (PROJECT.md, "AFK lives in the panel only").

**Anti-goals (failure even if it "works"):**
- **Touching the game's single waypoint / super-track** (`C_Map.SetUserWaypoint`, `C_SuperTrack.*`). QuestMaster,
  OpenMap and Questie all use it; taking it would wipe their quest waypoint. TwizCrew never calls those.
- Looking like QuestMaster's arrow or the game's waypoint pin.
- Flooding addon messages so other TwizCrew messages (STATE, roasts, pop-ups) get late.
- Errors or a frozen panel when a position is missing or secret.

## 4. Constraints and what the game gives (checked on this PC, 2026-11-07)

- WoW Forever is the modern engine (Interface 16001, Lua 5.1). Installed addons that work on Forever already use:
  `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition("player")`, `C_Map.GetWorldPosFromMapPos`,
  `GetPlayerFacing`, `Minimap:GetZoom`, `GetCVar("rotateMinimap")`, `WorldMapFrame:AddDataProvider`
  (QuestMaster, OpenMap, Questie with its HereBeDragons library). So your own position and facing are readable in
  the open world.
- **`UnitPosition` can come back secret on Forever** (OpenMap's API comment). So a friend's position should come from
  **their own copy** (it reads its own `C_Map.GetPlayerMapPosition`), sent as an addon message. Live party positions
  are a bonus only when readable and not secret. Every read goes through `pcall` and `issecretvalue`; a missing or
  secret value means "unknown" (arrow hidden), never an error.
- **Messages:** addon channel messages are never delivered on Forever; TwizCrew whispers each crew member, plus one
  group copy (v0.1.5). The send queue is 2 per second, burst 4 (`SEND_PER_SECOND`, `SEND_BURST`), and one broadcast
  already costs one item per crew member. So position sending **must stay cheap**. Targets (builder settles the
  numbers and writes them down):
  - send your position **only to your group**, as one `PARTY` / `RAID` message (owner: group only). Never whispered,
    never to friends outside the group. Not in a group = no position messages at all;
  - only **when you moved** (say 10+ yards) and **at most every few seconds**; nothing while standing still
    (a slow keep-alive is fine);
  - a newer position **replaces** an unsent older one in the queue (never a backlog of stale positions);
  - nothing during boss fights (already queued by the transport rules) and nothing in instances.
- Position message: map ID + x, y (enough decimals for ~1 yard), or world coordinates; builder's call. Receivers
  convert to continent + yards with `C_Map.GetWorldPosFromMapPos` for distance and direction. A position older than
  about a minute counts as unknown (arrow hidden).
- **New files and `.toc` lines are fine** (borrowing from other addons is fine too, owner: "its ok if you borrow
  from other addons"; respect licences: QuestMaster is GPL-3.0, learn from it, don't copy it). Claude's call:
  **HereBeDragons-2.0 + HereBeDragons-Pins-2.0 (BSD licence)**, the copy Questie ships, is allowed for placing the
  meet-up icon on the world map and minimap, because it already handles minimap zoom / rotation / indoors and works
  on Forever. Keep its licence file. If the builder writes its own placement instead, it must cover the same cases.
  This overrides the minimap plan's "no libraries" call for this feature only.
- **Release note:** new files and `.toc` changes mean the release that ships this sets `RESTART_SINCE` to its version
  and says "restart the game". No version bump and no release until the owner says "release it".
- Plain frames only; nothing protected, so it all works in fights except where the game forbids it.

## 5. Look

- **Row arrow:** the game's minimap player arrow (`Interface\Minimap\MinimapArrow`) or a similar game texture,
  rotated and tinted in the friend's class colour (Claude's suggestion; any game texture that reads as an arrow
  is fine, no new art needed). Distance in the panel's small font. The tiny row style may drop the distance text
  if it doesn't fit (builder's call).
- **Big arrow:** the same arrow, larger, class-coloured, with "Frostie" and "340 yd" (or "Westfall · 1.2k yd") under
  it, and a small close button. Default spot: upper middle of the screen but **not where QuestMaster's arrow sits
  by default** (the builder checks QuestMaster's default position and picks a clear spot). Draggable.
- **Big arrow toward a meet-up:** the same arrow in the sender's class colour, with "Meet Twiz" and the distance, so
  it's clear it points at a spot, not at a person who may have moved.
- **Meet-up icon on the maps:** the minimap button's icon (`ns.Config.MINIMAP_ICON`) in a ring, tinted or ringed in
  the sender's class colour, so it can't be mistaken for the game's waypoint pin or a quest icon.

## 6. Settings

A new **extras** module, **"Find the crew"** (on by default), with an (i) on every switch like every other setting.

- **Basics tab:** "Arrows on the Crew panel", "Meet-ups", "Share my position with my group".
- **Advanced tab:** meet-up on the minimap, meet-up pop-up, "Big arrow turns on for a meet-up", big arrow
  size (builder may add more).
- **Share my position** off: your copy sends no position and friends see your row without an arrow. Reset to defaults puts everything back on.

## 7. Report and testing

- `/tc report` gets a line such as `Find the crew: position ok (map 1429), facing ok, group members with positions: 3,
  meet-up: Twiz (party) in Elwynn Forest, 4 min left` (placed where older report tests stay valid, as before).
- Tests outside the game (`tests/run.sh`) cover: direction and distance maths, same-zone / instance / stale /
  secret rules, the send budget (moved / not moved, replace-unsent, group only, nothing when not grouped), the meet-up's life and who gets it (party / everyone),
  and a multi-copy simulation (two group members walk, the third sees arrows move; a friend outside the group gets no positions; a party meet-up reaches only the party and an "everyone" meet-up reaches all).
- `docs/TESTING.md` gets the in-game checks, riskiest first: whether `GetPlayerFacing` and map positions work on
  Forever outside instances; whether party `UnitPosition` is secret; a party-only meet-up never reaching friends outside the party; the meet-up icon on OpenMap's map and on a rotating
  minimap; no clash with QuestMaster's arrow.

## 8. Left to the builder

Exact numbers (send gaps, yards, sizes), the message format, frame layout inside rows, how the meet-up icon is
placed on the maps (library or own code, within section 4), and anything not named here, as long as it serves section 1 and
respects section 3's anti-goals. Write every such call in the plan's "Changes during build", as before.
