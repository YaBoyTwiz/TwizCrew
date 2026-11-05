# TwizCrew: Stats board ("Hall of Shame"), live roasts, awards show

Date: 2026-11-05. Status: **approved by the owner** ("do it", after a summary of every Claude's call below,
including the shared crew session). The owner **cannot test in game yet** and v1 has not been tried in game: build
blind like v1, every detector with a fallback, a self-disable and a `/tc report` line.
Builds on TwizCrew v1 (`docs/superpowers/specs/2026-11-05-crew-panel-design.md`, built, plan in
`docs/superpowers/plans/2026-11-05-crew-panel.md`). Read `PROJECT.md` first.

Marked **(owner)** = the owner decided it. Marked **(Claude's call)** = decided by Claude; the owner said "up to you,
be creative as needed", and can overrule any of it. Unmarked = left to the builder.

## 1. Intent

**(owner):** "mostly for laughs, roasting each other on stream". The addon quietly counts embarrassing (and a few
nice) things each crew member does, turns them into awards with funny names, and shows them in ways that are fun on
the owner's stream. Not serious progress tracking.

## 2. Goals

1. Count stats per character, **for the current session and all time** **(owner)**, including **steps** **(owner)**.
2. **Efficient, no spamming** **(owner)**: counting is local; numbers are shared rarely and in bulk.
3. A **Hall of Shame** tab in the Crew panel: one row per award, This session / All time switch (Claude's call).
4. **Live roasts**: a small pop-up for the whole crew when something roast-worthy happens (Claude's call).
5. An **awards show**: `/tc awards` reveals the awards one at a time, made to look good on stream (Claude's call).
6. An **award title** under each winner's name on the Crew panel (Claude's call).

## 3. Non-goals (this version)

- Custom art, voice lines or music from the Orchestrator. This version uses the game's own icons and sounds; every
  badge, sound and roast line is one entry in a table so custom assets can replace them later.
- A shared awards show that plays on every friend's screen at once (later extra; the stream shows the owner's
  screen anyway).
- Gold, XP per hour, levels and other serious stats.
- Stats from before the addon was installed; stats of people without the addon.
- Linking alts: each character has its own stats (same as v1 rows).

## 4. Anti-goals

- Messages per event (per step, per jump, per death). Anything that could hit the game's message limit.
- A roast pop-up flood: at most one live roast on screen every 10 seconds per person roasted (Claude's call), each
  roast type can be turned off.
- Lua errors or lag from the counting (it runs all the time).
- Showing a winner with 0 of something ("Professional Corpse: nobody, 0 deaths").

## 5. What we count (Claude's call; all without the combat log)

Each stat is a number per character, kept twice: this session and all time. Key = short id used in messages.

| Key | Stat | How it is detected | Award |
|---|---|---|---|
| `dt` | deaths | `PLAYER_DEAD` | **Professional Corpse** (most) |
| `df` | deaths while falling | `IsFalling()` seen true in the last 2 s before `PLAYER_DEAD` | **Gravity Tester** |
| `dd` | deaths while drowning or fatigued | a `BREATH` or `EXHAUSTION` mirror timer running at death (`MIRROR_TIMER_START` / `STOP`) | **Fish Food** |
| `dw` | deaths to a weak mob | the last hostile NPC you targeted in the last 10 s is ≥ 5 levels below you (values checked with `issecretvalue`; when unknown, not counted) | **Died to a Weakling** |
| `db` | "back for more": died again within 60 s of coming back to life | timestamps | **Back for More** |
| `ld` | lowest level of a mob that killed you | as `dw` | shown with Died to a Weakling ("lvl 4 mob") |
| `pl` | pulls: entered combat in a dungeon while no crew member in the same dungeon was fighting | own `PLAYER_REGEN_DISABLED` + friends' FIGHTING tags already shared by v1 | **Leeroy** |
| `wp` | wipes | in a dungeon, every crew member in that dungeon has the DEAD tag within 30 s; counted once per wipe for everyone in it | **Wipe Squad** (crew stat, shown as a line, not an award) |
| `af` | seconds AFK | `PLAYER_FLAGS_CHANGED` / `UnitIsAFK` | **Furniture** |
| `ds` | seconds dead | `PLAYER_DEAD` → `PLAYER_ALIVE` / `PLAYER_UNGHOST` | shown in tooltip only |
| `st` | steps (on foot) | see section 6 | **Marathon Runner** (most); **Couch Potato** (fewest steps per hour played, only people who played ≥ 30 min) |
| `mt` | yards mounted | section 6 | **Never Walks** (highest mounted ÷ on-foot ratio, min 1,000 yards total) |
| `sw` | yards swimming | section 6 | **Fish** (most) |
| `jp` | jumps | `hooksecurefunc("JumpOrAscendStart", …)` (test it exists in Forever; if not, the stat is hidden) | **Bunny Hopper** |
| `hs` | hearthstones | `UNIT_SPELLCAST_SUCCEEDED` for "player" with the Hearthstone spell (by spell name via `C_Spell.GetSpellName`) | **Homesick** |
| `jk` | gray junk looted | `CHAT_MSG_LOOT` for own loot, item quality 0 | **Trash Collector** |
| `rp` | copper spent on repairs | `GetRepairAllCost()` before a hooked `RepairAllItems`, plus single-item repairs if easy | **Broke** |
| `qa` | quests abandoned | `hooksecurefunc(C_QuestLog, "AbandonQuest", …)` (or the global `AbandonQuest`) | **Quitter** |
| `dl` | duels lost / `dv` duels won | `CHAT_MSG_SYSTEM` matched against the game's duel-result text (`DUEL_WINNER_KNOCKOUT`, `DUEL_WINNER_RETREAT`) | **Duel Loser** |
| `rz` | resurrections cast on others | `UNIT_SPELLCAST_SUCCEEDED` for spells named Resurrection, Redemption, Ancestral Spirit, Rebirth | **Medic** (the one nice award) |
| `pt` | seconds played this session / all time | own clock while logged in | used for "per hour" awards |

Rules for awards (Claude's call): winner = highest number (lowest for Couch Potato); ties show all tied names; no
winner when the best value is 0 or below the minimum noted; only characters with the stats module on take part.

## 6. Steps and distance (owner: "track steps… efficient… not spamming")

- A 0.5 s timer (one timer, shared with the fall check) reads `GetUnitSpeed("player")` and adds `speed × elapsed` to
  one bucket: **mounted** (`IsMounted()`), **swimming** (`IsSwimming()`), **on foot** (otherwise). Nothing is added
  while on a flight path (`UnitOnTaxi`), dead or a ghost (Claude's call: ghost runs don't count as steps), or when
  the speed value is secret or missing.
- **Fallback** if `GetUnitSpeed` is unusable: distance between two `UnitPosition("player")` readings (it returns
  nothing in instances, so dungeons won't count; acceptable).
- Steps = on-foot yards × **1.2** (about one step per 0.75 m; one constant, easy to change).
- Cost: a few function calls twice a second. No messages.

## 7. Sessions (owner: "session based stats, plus all time")

**(Claude's call: one shared crew session, started automatically, restartable by hand.)** A session is "tonight's
crew game", the same window for everybody, so the awards show compares like with like.

- When you log in, your copy waits until it has heard the crew (about 15 s after the channel is up). If an online
  crew member is in a session, you join it. If not, you start a new one.
- A session has an id and a start time (`<starterName>-<wallclock>`), shared in the existing `STATE` message as two
  new fields (`sid`, `sst`).
- If two different automatic sessions meet (two friends started alone, then saw each other), everyone moves to the
  older one and **keeps** their counts.
- **`/tc session new`** (anyone, meant for the owner at stream start) starts a fresh session for everyone online: all
  session counts go to 0. A hand-started session beats automatic ones; between two hand-started ones, the newest
  wins.
- Coming back within 30 minutes (a `/reload`, a disconnect) continues your session if nobody online has moved on.
- When everyone has been offline for more than 30 minutes, the next login starts a new session.
- All-time counts never reset, except by `/tc stats reset` (asks first, your own numbers only). The settings reset
  button does **not** touch stats (it resets settings, as in v1).

## 8. Sharing (no spam)

- Counting is local. A new message type **`STATS`** carries `sid`, then **one field per number**: `s_<key>` for this
  session and `a_<key>` for all time (only non-zero values), e.g. `s_dt=3~a_st=12403`. v1's codec sends the pieces
  after the first as `UPDATE` and cuts single values that don't fit: change it so continuation pieces keep the
  `STATS` type (receivers merge pieces by sender + `sid`), and never cut a number (Claude's call; the builder shapes
  it).
- Sent: about every **5 minutes** but only if a number changed, at logout, and once when someone asks.
- **`STATSREQ`**: sent when someone opens the Hall of Shame or starts the awards show (at most once a minute);
  everyone online answers with `STATS` after the same small random delay v1 uses for `HELLO`.
- The last known numbers of every crew member are saved, so offline friends still appear on the board (with "last
  updated 2h ago" in the tooltip).
- All sends go through v1's queue, so the rate limit and the boss-fight hold apply.

## 9. Live roasts (module "roasts", on by default)

The copy of the person it happened to decides it is roast-worthy and sends one small **`ROAST`** message (`k` kind,
`v` number, `x` extra text like a mob name, `n` which line); every crew copy (and yours) shows the same line.

| Kind | When | Example line |
|---|---|---|
| `weak` | death to a mob ≥ 5 levels below you | "Frostie died to a level 3 Kobold. Embarrassing." |
| `fall` | fall death | "Ginkan forgot gravity exists." |
| `drown` | drowning / fatigue death | "Holyboi tried to breathe water. It didn't work." |
| `again` | "back for more" death | "Frostie is back for more. Dead again in 40 seconds." |
| `deathN` | session deaths reach 5, 10, 20, 50 | "That's death #10 tonight for Pewpew." |
| `wipe` | a wipe (section 5), one roast per wipe, sent by whoever's copy sees it first; others ignore duplicates for 60 s | "WIPE! Everybody down in the Deadmines." |
| `steps` | all-time steps pass 10k, 50k, 100k, then every 100k | "Ginkan just passed 100,000 steps. Still lost." |
| `jumps` | all-time jumps pass 1,000, then every 5,000 | "Stabz has jumped 5,000 times. Why." |
| `quit` | 3rd quest abandoned in one session | "Pewpew gave up on another quest. That's 3 tonight." |

- Several lines per kind (at least 3; the builder writes them, plain and playful, never mean about real-life things);
  the sender picks one at random and sends its number, so every screen shows the same line.
- Look: same pop-up system as v1, orange edge (`c46a00`), shown about 6 s.
- Settings (each with an (i) button): on/off per kind, "Show roasts about me" (on), "Play a sound" (off, as in v1).
- Rate: at most one roast about the same person every 10 s; extra ones are dropped (counting still happens).

## 10. Hall of Shame (module "stats", on by default)

- A **second tab in the Crew panel**: `Crew | Hall of Shame` (tab buttons at the top of the panel).
- Switch at the top: **This session** / **All time**. Under it: "Session started 9:02 pm by Twiz" or "All time".
- One row per award (order of the table in section 5): badge icon, award name, winner name(s) in class colour,
  their number in plain units ("7 deaths", "12,403 steps", "2h 10m AFK", "lvl 4 mob", "3 rezzes").
- Hover a row: the award's (i) text and the top 3 with numbers. Awards with no winner yet are greyed with "nobody
  yet".
- A small "Wipe Squad: 2 wipes tonight" line at the bottom.
- **Titles on the Crew tab** (setting: this session / all time / off; default this session): each winner gets their
  award name (the most "important" one: order of the table) as a small line under their name.
- **Turning the stats module off stops your own counting and sharing** and hides the tab (Claude's call: different
  from v1's "switches only change what you see", because opting out of being roasted is fair). Your saved numbers are
  kept.

## 11. Awards show (`/tc awards`)

- A big window in the middle of the screen, dark with a gold glow (see mockup "3"). Opens on the owner's screen only.
- Uses the current session's numbers (`/tc awards all` for all time).
- First asks the crew for fresh numbers (`STATSREQ`) and waits up to 5 s.
- One award at a time, in a set order with **Medic last** (ends on a nice note): badge pops in, award name, a pause
  (~1.5 s) with "and the award goes to…", then the winner's name and their number with a one-line joke. Click or
  Space for the next one; Escape closes. Awards with no winner are skipped. Last card: "That's the show. GG crew."
- Sounds: the game's built-in sounds for now (a reveal sting per award); off when the stats sound setting is off.
- Badges: the game's own icons for now (builder picks fitting `Interface\Icons\…` ones, fallback question mark).
  Badge, sound and joke per award live in one table so the Orchestrator's art and voice can replace them later.

## 12. Settings (in the v1 settings window)

Module **Stats & Hall of Shame** (`stats`): on/off; titles (session / all time / off); count steps (on); show "Wipe
Squad" line (on); sound in the awards show (on). Module **Live roasts** (`roasts`): on/off per kind; roasts about
me; play a sound (off). Every setting gets its (i) text. Commands added to `/tc help`: `/tc awards`,
`/tc awards all`, `/tc session new`, `/tc stats reset`.

## 12b. Who can opt out of what (Claude's call, settled after review)

The person a stat or roast is **about** decides whether it exists; the viewer only decides what they see.

- **Stats module off (yours):** your copy stops counting, stops sending `STATS` and never sends a `ROAST` about you.
  It sends one `STATS` with `off=1` (and again in reply to `STATSREQ`); friends' copies then drop your numbers from
  the Hall of Shame, titles and awards (your saved numbers on their PCs are kept but hidden; they come back when you
  turn stats on again).
- **"Roasts about me" off (yours):** your copy keeps counting but never sends a `ROAST` about you. Sender side.
- **Live roasts module off, or a roast kind off (yours):** you don't see those roasts (about anyone, including
  yourself). Receiver side; others still see roasts about you.
- Detectors live in the stats module; roasts are produced from the stats detectors, so stats off means no roasts
  about you.

## 13. Built to be fixed (same rules as v1)

- Every detector (fall, drown, weak mob, jumps, repair, abandon, duel, rez, hearthstone, steps) is its own small
  function, wrapped in `Log.safe`; one that errors or whose API is missing turns itself off and is listed in
  `/tc report` ("Stats: jumps off (JumpOrAscendStart missing)"). The other stats keep counting.
- `/tc report` also shows: session id and start, steps method (speed / position / off), last `STATS` sent and heard.
- Detection rules are pure functions tested outside the game (fall window, death classification, session choice,
  award winners, roast rate limit, milestone crossing, stats encode/decode).
- The two-copy simulation from v1 is extended: a friend dies to a weak mob → both screens show the same roast line;
  `/tc session new` → both sessions reset; awards computed the same on both.

## 14. Test in the game

Most stats need only the owner. To check: `GetUnitSpeed` works out of combat and in dungeons; `IsFalling` before
death; mirror timer names; `JumpOrAscendStart` hook; hearthstone and rez spell names; duel text; whether target
level is readable (not secret) right before death; the Crew panel tabs.
