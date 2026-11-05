# TwizCrew: Stats board ("Hall of Shame"), live roasts, awards show — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each copy of TwizCrew quietly counts embarrassing (and a few nice) things its player does, per shared crew
session and all time, shares the numbers rarely and in bulk, and shows them as live roast pop-ups, a Hall of Shame
tab in the Crew panel with award titles, and an on-stream awards show (`/tc awards`).

**Architecture:** New folder `TwizCrew/Stats/`: a table of stats and awards (`StatsDefs`), pure rules (`StatsLogic`,
`SessionLogic`), the crew session (`Session`, always running like the layer sensor), saved numbers (`StatsStore`),
WoW-facing detectors (`Detectors`, each one guarded and able to turn itself off), the module `stats` (counting +
`STATS`/`STATSREQ` sharing) and the module `roasts` (`ROAST` messages shown through v1's pop-up frames). UI: a pure
`BoardLogic`, the Hall of Shame tab drawn inside v1's Crew panel (`Board`), and the awards show window
(`AwardsShow`). Everything plugs into v1's module registry, bus, comm queue and test harness.

**Tech Stack:** Lua 5.1 (WoW dialect), WoW Forever API (interface 16001), v1's test runner (`tests/run.sh`, fake WoW
API in `tests/wowstub.lua`, multi-client helper `H` in `tests/run.lua`). No libraries.

**Spec:** `docs/superpowers/specs/2026-11-05-stats-board-design.md` (approved, including section 12b). Builds on v1:
`docs/superpowers/specs/2026-11-05-crew-panel-design.md` and `docs/superpowers/plans/2026-11-05-crew-panel.md` (its
Global Constraints, Shared names and "Changes during build" still hold). Read `PROJECT.md`, the stats spec and the
v1 plan before any task, then the v1 files your task touches.

## Global Constraints

- Everything in the v1 plan's Global Constraints still applies (Lua 5.1, no `os`/`io`/`require`/`goto`/`//` in addon
  code, `/tc` only, every module and setting has `info`, `ns.Util.safeText` on text from other players, local commits
  only, plain words in every string a player sees).
- `tests/run.sh` must end with `ALL PASSED`, including all 219 v1 tests. A v1 test may only change where this plan
  says the behaviour changes on purpose (none planned).
- **No message per event.** Counting is local. `STATS` goes out at most every `STATS_SEND_INTERVAL = 300` s and only
  when a number other than `pt` changed, at logout, once after the session is decided, and in reply to `STATSREQ`.
  `STATSREQ` at most once per `STATSREQ_GAP = 60` s. All sends go through `ns.Comm.send` (queue, rate limit,
  boss-fight hold), except the logout send which goes directly like v1's `BYE`.
- **No roast flood:** at most one roast about the same person every `ROAST_GAP = 10` s (on the sender and on every
  receiver), wipe roasts deduped for `WIPE_ROAST_DEDUPE = 60` s. Extra roasts are dropped; counting still happens.
- **Never a winner with 0** (or below the award's minimum). Ties show every tied name.
- **Opt-out (spec 12b):** stats module off → no counting, no `STATS` (except one `off=1`), no `ROAST` about you.
  "Roasts about me" off → counting continues, no `ROAST` about you. Roasts module or a kind off → you don't see
  those roasts; others still do.
- **Stream safety:** roast lines and jokes are playful, about the game only, never about real-life things. Nothing
  from the hidden channel, session ids or wire text ever shows in chat.
- Every detector is its own small function behind a guard: a missing API turns it off with a reason (logged as
  `warn`, never `error`); a Lua error inside it turns it off (logged as `error`); the rest keep counting. All other
  handlers run inside `ns.Log.safe`.
- `issecretvalue(v)` (when it exists) is checked before any value from `GetUnitSpeed`, `UnitLevel`, `UnitName`,
  `UnitGUID`-like reads or spell ids is compared or used in math.
- The settings reset (v1) does **not** touch `db.stats`. Stats only reset with `/tc stats reset yes`.

## Review Focus

1. **Friends on v1 copies, or broken numbers** (no `sid` in their STATE, no STATS at all, a STATS with `s_dt=-4`,
   `a_st=abc`, `a_st=1e999`, unknown keys, no `sid`): ignored or partly used, never an error, never shown as a
   winner. Tests: Task 3 `wire_rejects_garbage`, Task 6 `stats_from_broken_copy_is_tamed`.
2. **Secret or missing values in the game** (speed secret, target level secret or `-1`, `UnitPosition` nil inside a
   dungeon, no target at death): that stat is simply not counted. Tests: Task 2 `motion_rules`,
   `classify_death_cases`, Task 5 `secret_values_are_not_counted`.
3. **APIs missing in Forever** (`JumpOrAscendStart`, `RepairAllItems`, `C_QuestLog.AbandonQuest`, `GetUnitSpeed`,
   `IsFalling`, `hooksecurefunc`): that detector is off with a reason in `/tc report`, everything else counts, no
   `error` lines. Test: Task 5 `missing_apis_turn_detectors_off`.
4. **Two sessions meeting** (two friends log in alone at nearly the same time; `/tc session new` while another copy
   is still deciding; a `/reload` inside 30 minutes): every online copy ends in the same session. Tests: Task 4
   `two_auto_sessions_converge_to_older`, `manual_session_wins_and_resets`, Task 10 `session_new_resets_both`.
5. **Player or mob names with `|`, `^`, `~`, `=`, or letters like "ø"** in roast text, award rows and titles: shown
   as plain text, arrive intact. Tests: Task 7 `roast_text_is_safe`, Task 8 `board_rows_model`.

## Design notes (decisions made while planning; the owner can overrule)

- **Session fields:** `sid` = `"<starterName>-<startWallclock>"`; `sst` = start wallclock, with a trailing `m` when
  the session was started by hand (`"1700000000m"`). So the "hand-started beats automatic" rule travels in the two
  fields the spec names. Both keys go right after `zn`, `ins`, `lk` in the codec's fixed key order, so they always
  arrive in the same message piece.
- **STATS pieces:** the codec gets `opts.repeatKeys`: those keys (`sid`, `q`, `off`) are written first in every
  piece. `q` is a token that changes with every full snapshot; a receiver starts a fresh record when `(sid, q)`
  differs from the last one, and merges further pieces with the same `(sid, q)`. This is how "receivers merge pieces
  by sender + sid" also handles numbers that went back to 0. Continuation pieces keep their own type; only `STATE`
  continues as `UPDATE` (v1 copies need that). Numeric values and repeated keys are never cut.
- **Session decision** happens `SESSION_DECIDE_AFTER = 20` s after start (5 s channel join + about 15 s of hearing
  the crew). Counts made in those 20 s land in the old session record and are zeroed if the session changes.
- **Leeroy needs company:** a pull only counts when at least one other crew member is online in the same dungeon.
- **Lowest mob level (`ld`)** is recorded with weak-mob deaths only (it is shown with "Died to a Weakling").
- **Repairs:** the repair cost is read while the merchant window is open (the hook on `RepairAllItems` runs after
  the repair, when the cost is already 0). Single-item repairs are not counted.
- **Spells** are matched by English name **or** a list of known spell ids (Hearthstone 8690; Resurrection,
  Redemption, Ancestral Spirit, Rebirth ranks).
- **`/tc stats reset`** asks in chat; `/tc stats reset yes` does it. **`/tc awards`** refuses during a fight (the
  show takes the Space key).
- **Wipe Squad line** = the highest `wp` among the shown people (everyone in a wipe counts it).

## File map

```
TwizCrew/
  Stats/StatsDefs.lua     stat keys, award table (name, unit, badge, joke, info, sound), roast kinds  (pure data)
  Stats/StatsLogic.lua    pure rules: motion, deaths, milestones, limiter, duel/junk text, pulls, wipes,
                          formatting, awards, titles, wire encode/decode, awards-show cards
  Stats/SessionLogic.lua  pure session rules: parse/wire, better, atLogin, switch
  Stats/Session.lua       crew session runtime (always runs; started by Boot)
  Stats/StatsStore.lua    db.stats: my counts per character, crew records, entries for the board
  Stats/Detectors.lua     every WoW-facing detector, guarded, with the shared 0.5 s ticker
  Stats/Stats.lua         module "stats": counting glue, deaths, milestones, STATS/STATSREQ sharing
  Stats/Roasts.lua        module "roasts": lines, ROAST send/receive, rate limits
  UI/BoardLogic.lua       pure Hall of Shame model
  UI/Board.lua            Hall of Shame tab drawn inside the Crew panel
  UI/AwardsShow.lua       /tc awards window
```

TOC order: v1 order up to `UI\Popups.lua`, then `Stats\StatsDefs.lua`, `Stats\StatsLogic.lua`,
`Stats\SessionLogic.lua`, `Stats\Session.lua`, `Stats\StatsStore.lua`, `Stats\Detectors.lua`, `Stats\Stats.lua`,
`Stats\Roasts.lua`, `UI\BoardLogic.lua`, `UI\Board.lua`, `UI\AwardsShow.lua`, then v1's `UI\Extras.lua`,
`UI\Settings.lua`, `UI\Report.lua`, `UI\Commands.lua`, `Core\Boot.lua`. Each task adds its own files. Files reach
later files (`ns.Board`, `ns.Roasts`, `ns.AwardsShow`, `ns.Session`) only at call time.

## Shared names (used across tasks)

**Added to `ns.Config`** (Core/Init.lua):

```lua
STATS_TICK = 0.5, STEPS_PER_YARD = 1.2, MAX_RUN_SPEED = 100, FALL_WINDOW = 2, DROWN_GRACE = 1,
WEAK_LEVELS = 5, WEAK_WINDOW = 10, AGAIN_WINDOW = 60, WIPE_WINDOW = 30,
STATS_SEND_INTERVAL = 300, STATSREQ_GAP = 60, STATS_CHANGED_GAP = 5,
SESSION_DECIDE_AFTER = 20, SESSION_RESUME = 1800, SESSION_ACTIVE_TICK = 60,
ROAST_GAP = 10, WIPE_ROAST_DEDUPE = 60, ROAST_SECONDS = 6,
SHOW_WAIT = 5, SHOW_BADGE = 0.6, SHOW_DRUMROLL = 1.5,
COUCH_MIN_PLAYED = 1800, NEVERWALKS_MIN_YARDS = 1000,
```

**Stat keys** (`StatsDefs.KEYS`, in this order): `dt df dd dw db ld pl wp af ds st mt sw jp hs jk rp qa dl dv rz pt`.
`ld` is a minimum (kept as the lowest value, 0 = unknown), every other key is a sum. `st` is stored in steps
(on-foot yards × `STEPS_PER_YARD`), `mt`/`sw` in yards, `af`/`ds`/`pt` in seconds, `rp` in copper. Values may be
fractional locally; the wire carries `math.floor`.

**Message types** (added to the codec's known types): `STATS` (fields `sid`, `q`, `off`, `s_<key>`, `a_<key>`),
`STATSREQ` (no fields), `ROAST` (`k` kind, `v` number, `x` extra text, `n` line number). STATE/UPDATE gain `sid`,
`sst`.

**Roast kinds** (`StatsDefs.ROAST_KINDS`, also the roasts module's setting keys): `weak fall drown again deaths wipe
steps jumps quit`.

**Bus events:** `SESSION_CHANGED(new, old, keep)` (new/old: session tables or nil), `STATS_CHANGED()`.

**Module ids:** `stats` ("Stats & Hall of Shame"), `roasts` ("Live roasts"), both tier `module`, default on.

**Saved data** `db.stats = { chars = { [name] = { sid = "", s = {}, a = {} } }, crew = { [name] = { sid, q, off,
s = {}, a = {}, at } }, session = { id, start, manual, lastActive } }` (session table may be empty).

**Session table:** `{ id = "Twiz-1700000000", start = 1700000000, manual = false }`.

---

### Task 1: Codec, config and saved-data groundwork

**Files:**
- Modify: `TwizCrew/Comm/Codec.lua`, `TwizCrew/Comm/Comm.lua`, `TwizCrew/Core/Init.lua`, `TwizCrew/Core/DB.lua`,
  `tests/test_codec.lua`, `tests/test_modules_db.lua`

**Interfaces:**
- Produces `ns.Codec.encode(msgType, fields, opts) → array of strings`. `opts` optional, `opts.repeatKeys` = array of
  keys written (in that order, if present in `fields`) at the start of **every** piece; the other keys follow in v1's
  order, with `FIRST = { zn = 1, ins = 2, lk = 3, sid = 4, sst = 5 }`. Continuation type: `STATE` → `UPDATE`, any
  other type keeps its own type. A value that is a plain number (`^%-?%d+%.?%d*$`) and every repeated key is never
  cut (if it cannot fit it is dropped and nothing else breaks); other values are cut as in v1.
- Known types: v1's plus `STATS`, `STATSREQ`, `ROAST`.
- Produces `ns.Comm.send(msgType, fields, opts)` (passes `opts` to `Codec.encode`).
- Produces the `ns.Config` additions above, and `db.stats` (Shared names) built and repaired by `DB.init`;
  `DB.resetSettings` leaves it alone.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/test_codec.lua (add)
stats_pieces_keep_type_and_repeat_keys:
  local f = { sid = "Holybøi-Realm-1700000000", q = "1700000000-1" }
  for i, k in ipairs({ "dt","df","dd","dw","db","ld","pl","wp","af","ds","st","mt","sw","jp","hs","jk","rp","qa","dl","dv","rz","pt" }) do
    f["s_" .. k] = tostring(100000 + i); f["a_" .. k] = tostring(123456789 + i) end
  local out = ns.Codec.encode("STATS", f, { repeatKeys = { "sid", "q", "off" } })
  A.ok(#out >= 2); local merged = {}
  for _, s in ipairs(out) do A.ok(#s <= 255); local m = ns.Codec.decode(s); A.eq(m.type, "STATS")
    A.eq(m.fields.sid, f.sid); A.eq(m.fields.q, f.q); for k, v in pairs(m.fields) do merged[k] = v end end
  A.eq(merged, f)
state_continuation_is_still_update: (v1's long_state_splits_under_limit keeps passing unchanged)
session_fields_follow_layer_fields: A.eq(ns.Codec.encode("STATE", { a = "1", sst = "5m", sid = "T-5", lk = "1", zn = "Z" })[1],
  "1^STATE^zn=Z~lk=1~sid=T-5~sst=5m~a=1")
new_types_decode: for _, t in ipairs({ "STATS", "STATSREQ", "ROAST" }) do A.eq(ns.Codec.decode("1^" .. t .. "^").type, t) end
numbers_are_never_cut: a STATS with st = string.rep("x", 300) and s_dt = "12345" → s_dt arrives as "12345" in some piece
-- tests/test_modules_db.lua (add)
init_builds_stats_and_reset_keeps_it:
  local db = ns.DB.init(nil, ns.Modules.list()); A.eq(db.stats, { chars = {}, crew = {}, session = {} })
  A.eq(ns.DB.init({ stats = 5 }, ns.Modules.list()).stats.chars, {})
  db.stats.chars.Twiz = { sid = "x", s = { dt = 1 }, a = { dt = 4 } }; ns.Modules.attach(db); ns.Modules.resetAll()
  A.eq(db.stats.chars.Twiz.a.dt, 4)
```

- [ ] **Step 2: Run** `tests/run.sh "codec|modules_db"`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the codec options, known types, `Comm.send` pass-through, Config values, `db.stats`.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED` (219 + new).
- [ ] **Step 5: Commit** `feat: codec pieces for STATS, stats config and saved data`.

---

### Task 2: Stat table and pure detection rules

**Files:**
- Create: `TwizCrew/Stats/StatsDefs.lua`, `TwizCrew/Stats/StatsLogic.lua` (rules part), `tests/test_statslogic.lua`
- Modify: TOC

**Interfaces:**
- Produces `ns.StatsDefs`: `KEYS` (Shared names), `MIN_KEYS = { ld = true }`, `TIME_KEYS = { pt = true }` (keys that
  never make a send due), `ROAST_KINDS` (Shared names), `SPELLS = { hearth = { names = {"Hearthstone"}, ids = {8690} },
  rez = { names = {"Resurrection","Redemption","Ancestral Spirit","Rebirth"}, ids = { 2006, 2010, 10880, 10881, 20770,
  7328, 10322, 10324, 20772, 20773, 2008, 20609, 20610, 20776, 20777, 20484, 20739, 20742, 20747, 20748 } } }`.
  (`AWARDS` and `SOUNDS` come in Task 3.)
- Produces `ns.StatsLogic` (pure; `c` = `ns.Config`):
  - `motionBucket(s) → "foot"|"mount"|"swim"|nil` with `s = { taxi, dead, mounted, swimming }`: nil when on a taxi or
    dead/ghost; else mount, then swim, then foot.
  - `speedYards(speed, elapsed, secret) → yards|nil` (nil when `secret`, not a number, NaN, negative, or above
    `MAX_RUN_SPEED`).
  - `positionYards(a, b) → yards|nil`, `a`/`b` = `{ x, y, instance, t }` (nil when either is missing, instances
    differ, `t` not increasing, or the implied speed is above `MAX_RUN_SPEED`, i.e. a teleport).
  - `classifyDeath(i) → r` with `i = { now, myLevel, fallingAt, breathRunning, breathStoppedAt, target = { level,
    name, at } | nil, aliveAt }` and `r = { fall, drown, weak, mobLevel, mobName, again, againSeconds }`: fall when
    `now - fallingAt <= FALL_WINDOW`; drown when `breathRunning` or `now - breathStoppedAt <= DROWN_GRACE`; weak when
    a target was seen within `WEAK_WINDOW`, its level is a number ≥ 1 and `myLevel - level >= WEAK_LEVELS`; again
    when `aliveAt` and `now - aliveAt <= AGAIN_WINDOW` (`againSeconds` = whole seconds).
  - `milestone(kind, old, new) → number|nil`: highest mark in `(old, new]`. `"deaths"` {5, 10, 20, 50};
    `"steps"` {10000, 50000, 100000, then every 100000}; `"jumps"` {1000, then every 5000}; `"quit"` {3}.
  - `newLimiter(gap) → l`; `l:allow(key, now) → bool` (true at most once per `gap` per key; a refused call does not
    restart the gap).
  - `duelResult(text, me, knockoutFmt, retreatFmt) → "won"|"lost"|nil`. Formats are the game's (`DUEL_WINNER_KNOCKOUT
    = "%1$s has defeated %2$s in a duel"`, `DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"`; `%1` is the
    winner). Build a Lua pattern from the format (escape magic characters, `%N$s` and `%s` become captures, keep
    their argument numbers); names compare after stripping a `-Realm` suffix.
  - `junkCount(text, selfFmt, multiFmt) → n`: 0 unless `text` matches `LOOT_ITEM_SELF` ("You receive loot: %s.") or
    `LOOT_ITEM_SELF_MULTIPLE` ("You receive loot: %sx%d.") and the item link's colour is `ff9d9d9d` (grey); then 1
    or the count.
  - `isPull(me, members) → bool`: `me = { zone, dungeon }`; true when `me.dungeon`, at least one member is `online`,
    `inInstance` and in `me.zone`, and none of those has `tags.COMBAT`.
  - `newWipeWatch(window) → w`: `w:dead(name, now)`, `w:alive(name)`, `w:check(names, now) → bool` true once when
    `#names >= 2`, everyone in `names` is dead, and their death times lie within `window`; it stays latched (false)
    until one of them is alive again.

- [ ] **Step 1: Write the failing tests** (`files = { "Core/Init.lua", "Core/Util.lua", "Stats/StatsDefs.lua", "Stats/StatsLogic.lua" }`)

```lua
motion_rules: L.motionBucket({}) == "foot"; ({ mounted = true }) "mount"; ({ swimming = true }) "swim";
  ({ taxi = true, mounted = true }) nil; ({ dead = true }) nil
  L.speedYards(7, 0.5) == 3.5; L.speedYards(7, 0.5, true) nil; L.speedYards(nil, 0.5) nil; L.speedYards(0/0, 0.5) nil
  L.speedYards(500, 0.5) nil
  L.positionYards({ x = 0, y = 0, instance = 0, t = 1 }, { x = 3, y = 4, instance = 0, t = 1.5 }) == 5
  ...instance 1 vs 0 → nil; 300 yards in 0.5 s → nil; nil reading → nil
classify_death_cases:
  local base = { now = 100, myLevel = 20 }
  fall: fallingAt = 98.5 → r.fall; fallingAt = 97 → not
  drown: breathRunning → r.drown; breathStoppedAt = 99.5 → r.drown; breathStoppedAt = 98 → not
  weak: target = { level = 14, name = "Kobold Miner", at = 95 } → weak, mobLevel 14, mobName "Kobold Miner"
    level 16 → not weak; at = 85 → not; level = -1 → not; level = "14" → not; target nil → not
  again: aliveAt = 60 → again, againSeconds 40; aliveAt = 30 → not
milestone_crossings: ("deaths", 4, 5) 5; ("deaths", 5, 6) nil; ("deaths", 9, 21) 20; ("steps", 9990, 10002) 10000;
  ("steps", 99000, 100500) 100000; ("steps", 199999, 200001) 200000; ("steps", 150000, 160000) nil
  ("jumps", 999, 1000) 1000; ("jumps", 4999, 5000) 5000; ("jumps", 5000, 9999) nil; ("jumps", 9999, 10000) 10000
  ("quit", 2, 3) 3; ("quit", 3, 4) nil
limiter_gap: l = newLimiter(10); allow("A", 0) true; ("A", 5) false; ("B", 5) true; ("A", 10) true; ("A", 15) false
duel_text: K, R = "%1$s has defeated %2$s in a duel", "%2$s has fled from %1$s in a duel"
  duelResult("Ginkan has defeated Twiz in a duel", "Twiz", K, R) == "lost"; (… "Twiz has defeated Ginkan…") "won"
  ("Twiz has fled from Ginkan in a duel") "lost"; ("Ginkan has fled from Twiz in a duel") "won"
  ("Ginkan-Realm has defeated Twiz-Realm in a duel") "lost"; ("Stabz has defeated Ginkan in a duel") nil; ("hello") nil
junk_text: S, M = "You receive loot: %s.", "You receive loot: %sx%d."
  junkCount("You receive loot: |cff9d9d9d|Hitem:2211::::::::1:::::::|h[Broken Fang]|h|r.", S, M) == 1
  ("You receive loot: |cff9d9d9d|Hitem:2211|h[Broken Fang]|h|rx3.") 3; white item |cffffffff → 0
  ("Ginkan receives loot: |cff9d9d9d…") 0
pull_rules: me = { zone = "The Deadmines", dungeon = true }
  members { { online = true, inInstance = true, zone = "The Deadmines", tags = {} } } → true
  same with tags = { COMBAT = true } → false; no member in the dungeon → false; me.dungeon false → false
wipe_watch: w = newWipeWatch(30); w:dead("Twiz", 0); w:check({"Twiz","Frostie"}, 0) false
  w:dead("Frostie", 20); w:check({"Twiz","Frostie"}, 20) true; again false; w:alive("Twiz"); w:dead("Twiz", 70)
  w:check(…, 70) false (Frostie died 50 s earlier); w:check({"Twiz"}, 70) false (alone is not a wipe)
```

- [ ] **Step 2: Run** `tests/run.sh statslogic`. Expected: FAIL.
- [ ] **Step 3: Implement** StatsDefs (keys, kinds, spells) and the StatsLogic rules.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: stat table and pure detection rules`.

---

### Task 3: Awards, formatting and the STATS wire format

**Files:**
- Modify: `TwizCrew/Stats/StatsDefs.lua`, `TwizCrew/Stats/StatsLogic.lua`, `tests/test_statslogic.lua`

**Interfaces:**
- Produces `StatsDefs.AWARDS` (array in this order; each `{ id, name, key | value = fn(stats) → number|nil, unit,
  lowest, min, icon, info, joke, last }`) and `StatsDefs.SOUNDS = { badge = { kit = "READY_CHECK", id = 8960 },
  reveal = { kit = "RAID_WARNING", id = 8959 } }`, `StatsDefs.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"`:

| id | name | value | unit | icon (`Interface\Icons\…`) |
|---|---|---|---|---|
| corpse | Professional Corpse | `dt` | death | Ability_Rogue_FeignDeath |
| gravity | Gravity Tester | `df` | fall | Spell_Magic_FeatherFall |
| fishfood | Fish Food | `dd` | drown | Spell_Shadow_DemonBreath |
| weakling | Died to a Weakling | `dw` | weak (text adds `ld`) | INV_Misc_Bone_HumanSkull_01 |
| again | Back for More | `db` | again | Spell_Shadow_RaiseDead |
| leeroy | Leeroy | `pl` | pull | Ability_Warrior_Charge |
| furniture | Furniture | `af` | afk | Spell_Nature_Sleep |
| marathon | Marathon Runner | `st` | steps | INV_Misc_Foot_Kodo |
| couch | Couch Potato | `st / (pt / 3600)` only when `pt >= COUCH_MIN_PLAYED`; `lowest = true` | perhour | INV_Misc_Fork&Knife |
| neverwalks | Never Walks | `mt / max(st / STEPS_PER_YARD, 1)` only when `mt + st / STEPS_PER_YARD >= NEVERWALKS_MIN_YARDS` | ratio | Ability_Mount_RidingHorse |
| fish | Fish | `sw` | yards | INV_Misc_Fish_02 |
| bunny | Bunny Hopper | `jp` | jumps | Ability_Rogue_Sprint |
| homesick | Homesick | `hs` | hearths | INV_Misc_Rune_01 |
| trash | Trash Collector | `jk` | junk | INV_Misc_Gear_01 |
| broke | Broke | `rp` | money | INV_Misc_Coin_01 |
| quitter | Quitter | `qa` | quests | INV_Misc_Note_01 |
| duel | Duel Loser | `dl` | duels | INV_Sword_04 |
| medic | Medic | `rz` | rezzes | Spell_Holy_Resurrection, `last = true` |

  Each award gets a one-sentence `info` ("Died the most.") and a playful one-line `joke` for the show (about the
  game only). Unit texts (singular/plural): death(s), fall death(s), drowning(s), death(s) (+ `" (lvl N mob)"` when
  `ld > 0`), quick death(s), pull(s), `"<duration> AFK"`, steps, `"<n> steps per hour"`, `"rides <x>x more than
  walks"` (one decimal), yards swum, jump(s), hearthstone(s), junk item(s), `money`, quest(s) abandoned, duel(s)
  lost, rez(zes).
- Produces in `ns.StatsLogic`:
  - `number(n) → "12,403"` (floor, thousands separators), `duration(s) → "2h 10m" | "45m" | "30s"`,
    `money(copper) → "3g 20s 5c"` (zero parts dropped, `"0c"` for 0), `valueText(award, value, stats) → string`.
  - `awards(entries) → list` (one item per `AWARDS` def, same order): `entries` = array of `{ name, class, stats }`.
    Item = `{ def, winners = { names, sorted }, value, text, top = { { name, value, text }, … up to 3 }, empty }`.
    Winner = highest value (lowest when `def.lowest`); values that are nil are skipped; `empty` when no entry has a
    value, or the best is ≤ 0 (for non-`lowest` awards); ties list every tied name.
  - `titles(awardsList) → { [name] = awardName }`: each winner gets the first award (table order) they won.
  - `toWire(snap) → fields` with `snap = { sid, q, off, s = {}, a = {} }`: `sid`, `q` always (when present), `off =
    "1"` when off (and then no numbers), `s_<key>` / `a_<key>` = `tostring(math.floor(v))` only for known keys with
    `floor(v) > 0`.
  - `fromWire(fields) → snap | nil`: nil without a `sid` string; keeps known keys only, values that are finite
    numbers ≥ 0 (floored), ignores the rest.
  - `showCards(awardsList) → cards`: one `{ kind = "award", award }` per non-empty award in table order, awards with
    `last` moved to the end, then `{ kind = "end" }`.

- [ ] **Step 1: Write the failing tests** (same file as Task 2)

```lua
formatting: L.number(12403.7) == "12,403"; L.number(5) == "5"; L.number(1234567) == "1,234,567"
  L.duration(7800) == "2h 10m"; L.duration(2700) == "45m"; L.duration(30) == "30s"
  L.money(32005) == "3g 20s 5c"; L.money(30000) == "3g"; L.money(0) == "0c"
award_winners_and_ties:
  local e = { { name = "Twiz", stats = { dt = 7, st = 12403, pt = 3600 } }, { name = "Frostie", stats = { dt = 7, jp = 3 } },
              { name = "Ginkan", stats = { dt = 2, pt = 600, st = 90000 } } }
  local list = L.awards(e); local by = {}; for _, a in ipairs(list) do by[a.def.id] = a end
  A.eq(by.corpse.winners, { "Frostie", "Twiz" }); A.eq(by.corpse.text, "7 deaths")
  A.eq(by.marathon.winners, { "Ginkan" }); A.eq(by.marathon.text, "90,000 steps")
  A.ok(by.gravity.empty)                       -- nobody has df: never "nobody, 0"
  A.eq(by.couch.winners, { "Twiz" })           -- Ginkan played under 30 min
  A.eq(by.corpse.top[1].value, 7); A.eq(#by.corpse.top, 3)
  A.eq(list[#list].def.id, "medic")
weakling_shows_mob_level: entries Twiz { dw = 2, ld = 4 } → text "2 deaths (lvl 4 mob)"
never_walks_ratio_and_minimum: Twiz { mt = 5000, st = 480 } (400 yards on foot) → winner, text "rides 12.5x more than walks";
  Frostie { mt = 500, st = 120 } only → empty
titles_first_award_wins: Twiz wins corpse and bunny → titles.Twiz == "Professional Corpse"
wire_roundtrip: snap { sid = "T-1", q = "1-1", s = { dt = 3, st = 10.7, jp = 0 }, a = { st = 12403.2 } }
  → toWire == { sid = "T-1", q = "1-1", s_dt = "3", s_st = "10", a_st = "12403" }; fromWire(that).s == { dt = 3, st = 10 }
  off snap { sid = "T-1", q = "2", off = true, s = { dt = 3 } } → { sid = "T-1", q = "2", off = "1" }; fromWire(...).off == true
wire_rejects_garbage: L.fromWire({}) nil; L.fromWire({ sid = "T", s_dt = "-4", a_st = "abc", a_jp = "1e999",
  s_zz = "5", a_dt = "2.9", x = "1" }) → s == {}, a == { dt = 2 }
show_cards_medic_last: awards where medic and corpse have winners, gravity empty → kinds/ids
  { award corpse, award medic, end }
```

- [ ] **Step 2: Run** `tests/run.sh statslogic`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the award table, jokes, info texts, formatting, awards, titles, wire, show cards.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: awards, number formats and the STATS wire format`.

---

### Task 4: Crew session (pure rules + runtime)

**Files:**
- Create: `TwizCrew/Stats/SessionLogic.lua`, `TwizCrew/Stats/Session.lua`, `tests/test_session.lua`
- Modify: TOC, `TwizCrew/Crew/SelfState.lua` (`gather` adds `sid`, `sst`), `TwizCrew/Core/Boot.lua` (start it)

**Interfaces:**
- Produces `ns.SessionLogic` (pure):
  - `toWire(s) → sid, sst` (`"", ""` for nil; `sst = tostring(start) .. (manual and "m" or "")`),
    `fromWire(sid, sst) → s | nil` (nil when `sid` is empty/not a string or `sst` is not digits with an optional `m`).
  - `better(a, b) → a|b`: a non-nil one beats nil; manual beats automatic; two manual → larger `start` wins; two
    automatic → smaller `start` wins; equal → smaller `id` (string compare).
  - `newSession(me, wall, manual) → s` (`id = me .. "-" .. wall`).
  - `atLogin(own, heard, wall, me, resume) → session, keep`: `own` = saved `{ id, start, manual, lastActive }` or
    nil; `heard` = array of sessions of online crew. Resumable = `own.lastActive` and `wall - own.lastActive <=
    resume`. Pool = heard plus own if resumable. Empty pool → `newSession(me, wall, false), false`. Best of pool;
    `keep` = resumable and (best is own, or both best and own are automatic).
  - `switch(current, incoming) → session, changed, keep`: no change when incoming is nil, the same id, or
    `better(current, incoming) == current`; otherwise incoming wins with `keep = not incoming.manual`.
- Produces `ns.Session` (feature id `"session"`; always runs, like the layer sensor):
  - `start()` (Boot calls it after `LayerSensor.start`; idempotent): listens to member session fields (registered
    once at file load with `ns.Comm.on("STATE"/"UPDATE")`, merging `sid`/`sst` per sender: a piece without one of
    them keeps the earlier value; `ns.Comm.on("HELLO")` forgets the sender's), `MEMBER_OFFLINE` forgets them. After
    `SESSION_DECIDE_AFTER` s: `atLogin` with the sessions of online roster members → becomes current. After that
    every member session heard goes through `switch`. Ticker every `SESSION_ACTIVE_TICK` s and `PLAYER_LOGOUT`
    save `lastActive = wallclock()`.
  - On any change: save `db.stats.session = { id, start, manual, lastActive }`, fire
    `SESSION_CHANGED(new, old, keep)`, `ns.Self.refresh("session")`, log one `info` line.
  - `current() → s|nil`, `decided() → bool`, `wire() → sid, sst`, `newByHand() → s` (a manual session from me now,
    switches at once even before the decision, `keep = false`), `starter(s) → name` (id without the trailing
    `-<digits>`), `forTest.decideNow()`.
- `Self.gather()` adds `sid`, `sst` from `ns.Session.wire()` when `ns.Session` exists (else `""`).

- [ ] **Step 1: Write the failing tests** (`files = "toc"` for runtime tests; boot as in test_ui: `ADDON_LOADED`,
  `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`; friends' messages via `Codec.encode` + `CHAT_MSG_ADDON`)

```lua
wire_roundtrip: S.toWire({ id = "Twiz-100", start = 100, manual = true }) == "Twiz-100", "100m"
  S.fromWire("Twiz-100", "100m") == { id = "Twiz-100", start = 100, manual = true }; fromWire("", "1") nil; fromWire("a", "x") nil
better_rules: manual(200) beats auto(100); manual 300 beats manual 200; auto 100 beats auto 200; better(nil, x) == x
at_login_cases (resume 1800, wall 10000, me "Twiz"):
  nothing heard, no own → new auto "Twiz-10000", keep false
  own { id = "Twiz-9000", start = 9000, lastActive = 9500 } nothing heard → own, keep true
  own lastActive 7000 (over 30 min) → new session, keep false
  heard { Frostie-9800 auto } and resumable own Twiz-9000 auto → own (older), keep true
  heard { Frostie-8000 auto } → Frostie's, keep true; heard { Frostie-9900 manual } → Frostie's, keep false
switch_rules: switch(autoA(100), autoB(50)) → B, true, keep true; switch(B, A) → B, false
  switch(auto, manual) → manual, keep false; switch(manualOld, manualNew) → manualNew; switch(x, x) → no change
first_login_alone_starts_session: boot; W:advance(19) → current() nil; W:advance(2) → current().id == "Twiz-<wall>",
  an UPDATE was sent with sid and sst; db.stats.session.id equals it
joins_friend_session_heard_at_login: boot; Frostie STATE { sid = "Frostie-123", sst = "123" } at t+3 → after 20 s
  current().id == "Frostie-123"
two_auto_sessions_converge_to_older: decided alone (Twiz-<wall>); Frostie UPDATE sid "Frostie-1", sst "1"
  → current() is Frostie's; SESSION_CHANGED fired with keep true
manual_session_wins_and_resets: decided; ns.Session.newByHand() → manual; Frostie auto "Frostie-1" heard → stays mine;
  Frostie UPDATE manual newer ("Frostie-9999999999", "9999999999m") → switches, keep false
split_fields_merge: Frostie UPDATE { sid = "Frostie-5" } then UPDATE { sst = "5" } → Session takes Frostie-5 once both known
resume_after_reload: db.stats.session = { id = "Twiz-1", start = 1, manual = true, lastActive = <now - 600> } before
  PLAYER_LOGIN → after 21 s current().id == "Twiz-1", manual true
```

- [ ] **Step 2: Run** `tests/run.sh session`. Expected: FAIL.
- [ ] **Step 3: Implement** SessionLogic, Session, the `gather` fields and the Boot line.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED` (v1's crew tests see `sid = ""` in every gather, so
  their diffs do not change).
- [ ] **Step 5: Commit** `feat: shared crew session`.

---

### Task 5: Saved numbers, detectors and the stats module (counting)

**Files:**
- Create: `TwizCrew/Stats/StatsStore.lua`, `TwizCrew/Stats/Detectors.lua`, `TwizCrew/Stats/Stats.lua`,
  `tests/test_stats.lua`
- Modify: TOC, `tests/wowstub.lua`

**Interfaces:**
- Adds to the stub (all read `W.state` at call time; a `W.state.missing[name] = true` entry makes that global or
  table function nil): `GetUnitSpeed("player") → st.speed` (default 0), `IsMounted`, `IsSwimming`, `IsFalling`
  (`st.mounted`, `st.swimming`, `st.falling`), `UnitPosition("player") → st.pos.y, st.pos.x, 0, st.pos.instance` (nil
  when `st.pos` is nil), `UnitExists(unit)`, `UnitCanAttack("player", unit)`, `UnitIsPlayer(unit)`, `UnitName(unit)`
  and `UnitLevel(unit)` for `st.units[unit] = { name, level, hostile, player }` (player behaviour unchanged),
  `hooksecurefunc([tbl,] name, fn)` (wraps: original first, then fn), `JumpOrAscendStart()`, `RepairAllItems(guild)`,
  `GetRepairAllCost() → st.repairCost, st.repairCost > 0`, `C_QuestLog.AbandonQuest()`, `AbandonQuest()`,
  `C_Spell.GetSpellName(id) → st.spellNames[id]`, `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`,
  `DUEL_WINNER_KNOCKOUT`, `DUEL_WINNER_RETREAT` (English texts from Task 2).
- Produces `ns.StatsStore` (needs `ns.db`; my name = `ns.playerName()`):
  `mine() → rec` (creates `db.stats.chars[me] = { sid = "", s = {}, a = {} }`), `add(key, n)` (unknown keys
  ignored; `MIN_KEYS` keep the lowest positive value; others add to `s` and `a`; marks dirty unless `TIME_KEYS`),
  `get(view, key) → number` (`view` `"session"|"all"`), `setSession(newId, fromId, keep)` (nothing when `rec.sid ==
  newId`; keeps `s` when `keep and rec.sid == fromId`; else `s = {}`; then `rec.sid = newId`), `resetMine()` (both
  to `{}`), `dirty() → bool`, `markSent()`, `snapshot(off) → snap` (`q = wallclock .. "-" .. counter`).
- Produces `ns.Detectors`: each detector `{ id, label, needs() → ok, why, start(api), tick(elapsed) }` in this list
  and order: `motion` (steps/mount/swim, speed then position fallback; skipped when the stats setting `countSteps`
  is off), `fall` (`IsFalling` in the tick → `ctx.fallingAt`), `timers` (`af` when `UnitIsAFK`, `ds` when
  `UnitIsDeadOrGhost`, `pt` always; per tick), `death` (`PLAYER_DEAD` → `api.died()`; `PLAYER_ALIVE` when not dead
  or ghost and `PLAYER_UNGHOST` → `ctx.aliveAt = now`, `api.alive()`), `drown` (`MIRROR_TIMER_START/STOP` for
  `BREATH`/`EXHAUSTION` → `ctx.breathRunning`, `ctx.breathStoppedAt`), `target` (`PLAYER_TARGET_CHANGED` and again
  at death: hostile non-player target → `ctx.target = { level, name, at }`, skipped when level or name is secret),
  `pulls` (`PLAYER_REGEN_DISABLED` + `StatsLogic.isPull` over the roster → `pl`), `wipes` (`newWipeWatch`: my death,
  `MEMBER_DIED`, my revival, and a friend whose tags lose DEAD (`MEMBER_UPDATED`) → `alive`; on a wipe `wp` +
  `api.wipe(zone)`), `jumps` (`hooksecurefunc("JumpOrAscendStart")` once → `jp`), `spells`
  (`UNIT_SPELLCAST_SUCCEEDED("player", _, spellID)`: secret ids skipped; name via `C_Spell.GetSpellName` (fallback
  `GetSpellInfo`) or the id list → `hs` / `rz`), `junk` (`CHAT_MSG_LOOT` + `junkCount` → `jk`), `repair`
  (`MERCHANT_SHOW`/`MERCHANT_CLOSED`; cost read in the tick and on `UPDATE_INVENTORY_DURABILITY` while open; hook
  `RepairAllItems(guild)` once → `rp` += last cost unless `guild`), `abandon` (hook `C_QuestLog.AbandonQuest`, else
  global `AbandonQuest` → `qa`), `duel` (`CHAT_MSG_SYSTEM` + `duelResult` → `dl` / `dv`).
  `Detectors.ctx` (shared state above), `startAll(api)`, `stopAll()` (cancels the one `STATS_TICK` ticker,
  `Events.off`/`Bus.off` per detector feature id `"stats_" .. id`; hooks stay but do nothing while stopped),
  `status() → array { id, on, why }`, `stepsMethod() → "speed"|"position"|"off"`. Guard: `needs()` false → off with
  `why` (logged `warn`, e.g. `"JumpOrAscendStart missing"`); a Lua error inside → off with `why = "error"` (logged
  `error` with the message); a turned-off detector stays off until `/reload`. `motion` uses speed while
  `GetUnitSpeed` exists, else position; `"off"` when neither or `countSteps` is off.
- Produces `ns.Stats` (module `stats`, name "Stats & Hall of Shame"): defaults/settings `titles` "session" (choice
  session "This session" / all "All time" / off "Off"), `countSteps` true, `wipeLine` true, `showSound` true, each
  with an `info` text. `onEnable` → `Detectors.startAll(api)`, sharing (Task 6); `onDisable` → `stopAll()`.
  `Stats.count(key, n)` (via `StatsStore.add`; then milestone checks: session `dt` → `"deaths"`, all-time `st` →
  `"steps"`, all-time `jp` → `"jumps"`, session `qa` → `"quit"`; a crossed mark calls
  `ns.Roasts.send(kind, mark)` when `ns.Roasts` exists); `Stats.died()`: `classifyDeath` with `Detectors.ctx`,
  `UnitLevel("player")`, now → counts `dt` and `df`/`dd`/`dw`/`db`, `ld` (weak deaths), then one roast by priority
  weak (`v` = mob level, `x` = mob name) > fall > drown > again (`v` = seconds) > deaths milestone; `Stats.wipe(zone)`
  → roast `wipe` with `x = zone`. Fires `STATS_CHANGED` at most every `STATS_CHANGED_GAP` s for own counts.
  Listens to `SESSION_CHANGED` → `StatsStore.setSession(new.id, old and old.id, keep)` + `STATS_CHANGED`.

- [ ] **Step 1: Write the failing tests** (`files = "toc"`, full boot; `Stats.count` and the detectors drive
  `StatsStore`; `ns.Roasts` is absent until Task 7, so the tests stub it: `ns.Roasts = { send = record }`)

```lua
steps_by_speed_split_by_mode: st.speed = 7; W:advance(10) → get("all","st") ≈ 7*10*1.2 (±1.2);
  st.mounted = true → mt grows; st.swimming = true, mounted false → sw grows; st.taxi = true → nothing grows
  Stats setting countSteps false → nothing grows; stepsMethod() == "off"
position_fallback: W.state.missing.GetUnitSpeed = true before boot; st.pos moves 3 yards per 0.5 s → st grows,
  stepsMethod() == "position"; st.pos = nil (dungeon) → nothing, no error
timers_count_afk_dead_played: st.afk = true 60 s → af ≈ 60; pt ≈ elapsed; st.dead = true 10 s → ds ≈ 10
fall_death_counts: st.falling = true, advance 1, st.falling = false, st.dead = true, fire PLAYER_DEAD →
  dt 1, df 1, roast "fall" recorded
weak_mob_death: st.level 20; st.units.target = { name = "Kobold Miner", level = 3, hostile = true }; fire
  PLAYER_TARGET_CHANGED; advance 5; die → dw 1, ld 3, roast { "weak", 3, "Kobold Miner" }
drown_and_again: MIRROR_TIMER_START "BREATH" then die → dd 1; PLAYER_ALIVE (alive) at t, die at t+40 → db 1,
  roast { "again", 40 }
secret_values_are_not_counted: st.secret[7] = true with st.speed = 7 → no steps; target level secret → no dw
jumps_hearth_rez_junk_repair_abandon_duel: W.env.JumpOrAscendStart() ×3 → jp 3;
  UNIT_SPELLCAST_SUCCEEDED("player", "x", 8690) → hs 1; spell id 999 named "Redemption" → rz 1;
  CHAT_MSG_LOOT grey ×2 → jk 2; MERCHANT_SHOW, repairCost 32005, advance 1, RepairAllItems() → rp 32005;
  RepairAllItems(true) → unchanged; C_QuestLog.AbandonQuest() → qa 1;
  CHAT_MSG_SYSTEM "Ginkan has defeated Twiz in a duel" → dl 1
pulls_need_a_quiet_friend: in dungeon "The Deadmines" with Frostie STATE { zn = "The Deadmines", ins = "1", tg = "" }
  → PLAYER_REGEN_DISABLED → pl 1; Frostie tg = "COMBAT" → next pull not counted
wipe_counts_once: in a dungeon with Frostie; Frostie UPDATE tg "DEAD"; I die 10 s later → wp 1 and api wipe once;
  another PLAYER_DEAD without anyone alive between → still 1
milestones_roast: Stats.count("dt", 4) then ("dt", 1) → roast { "deaths", 5 }; count("jp", 1000) → { "jumps", 1000 }
missing_apis_turn_detectors_off: missing JumpOrAscendStart, RepairAllItems, AbandonQuest (both), IsFalling, hooksecurefunc
  → status() shows jumps, repair, abandon, fall off with reasons ("JumpOrAscendStart missing"…); steps still count;
  ns.Log.errors(10) == {}
erroring_detector_turns_off_alone: make C_Spell.GetSpellName error → spells off (why "error"), one error line;
  steps still count
module_off_stops_counting: Modules.setEnabled("stats", false); move/jump → nothing changes; on again → counts
session_change_resets_or_keeps: count dt 2; SESSION_CHANGED to a new id with keep false → session dt 0, all dt 2;
  keep true from the current id → session dt kept
```

- [ ] **Step 2: Run** `tests/run.sh stats`. Expected: FAIL.
- [ ] **Step 3: Implement** the stub additions, StatsStore, Detectors, Stats (counting part).
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED` (v1's start-ups now also start the stats module; its
  missing-API notes are `warn`, so v1's no-error checks hold).
- [ ] **Step 5: Commit** `feat: stats module with guarded detectors`.

---

### Task 6: Sharing numbers (STATS, STATSREQ, off) and crew records

**Files:**
- Modify: `TwizCrew/Stats/Stats.lua`, `TwizCrew/Stats/StatsStore.lua`, `tests/test_stats.lua`

**Interfaces:**
- `StatsStore.applyWire(name, fields, wall) → changed`: `fromWire`; nil → nothing. New `(sid, q)` → the record is
  replaced by the snapshot; the same `(sid, q)` → numbers merged in; `off` → `rec.off = true` (numbers kept); always
  `rec.at = wall`. Saved in `db.stats.crew[name]`.
- `StatsStore.entries(view, sessionId) → array { name, class, stats, mine = bool, at }`: my characters
  (`db.stats.chars`; my current character only while the stats module is on) plus crew records not `off` and not
  one of my characters; for `"session"` only records whose `sid == sessionId` (none when `sessionId` is nil), using
  `s`, else `a`. Class from the roster, or `UnitClass("player")` for me, else nil.
- `ns.Stats`: `send()` (snapshot → `Comm.send("STATS", toWire(snap), { repeatKeys = { "sid", "q", "off" } })`,
  `markSent`, remembers `lastSent`), `request() → bool` (STATSREQ at most once per `STATSREQ_GAP`), `status() →
  { lastSent, lastHeard = { name, at } }`. Comm handlers registered at file load: `STATS` → `applyWire`, fire
  `STATS_CHANGED`; `STATSREQ` → one shared reply after a random `HELLO_JITTER_MIN..MAX` s: a snapshot when the
  module is on, `{ sid, q, off = 1 }` when off. Sends: the first `SESSION_CHANGED` after start; a
  `STATS_SEND_INTERVAL` ticker when `dirty()`; `PLAYER_LOGOUT` (direct `Transport.send` of each piece to each
  destination, only when dirty, module on); `onDisable` → one `off` snapshot via `Comm.send`; `onEnable` after the
  session is decided → `send()`.

- [ ] **Step 1: Write the failing tests**

```lua
sends_after_session_and_only_when_changed: boot; advance 21 → one STATS sent (decoded, sid = current id);
  advance 300 with nothing counted → no STATS; count jp 1, advance 300 → one STATS with s_jp = "1"
played_time_alone_does_not_send: advance 600 (pt grows) → no STATS after the first
statsreq_gets_one_jittered_reply: two STATSREQ from Frostie and Ginkan within 1 s → exactly one STATS within 5 s
request_is_rate_limited: Stats.request() true, again false, after 61 s true
off_is_announced_and_hides_me: setEnabled("stats", false) → a STATS with off = "1" and no s_/a_ keys;
  STATSREQ then → reply has off = "1"
friend_numbers_saved_and_replaced: STATS Frostie { sid = S, q = "1", s_dt = "3", a_dt = "9" } then
  { sid = S, q = "1", a_jp = "4" } (second piece) → crew.Frostie.s.dt 3, a.jp 4, a.dt 9;
  then { sid = S, q = "2", a_dt = "10" } → crew.Frostie.a == { dt = 10 }, s == {}
entries_filter_session_and_off: Frostie sid S, Ginkan sid other → entries("session", S) has me and Frostie, not
  Ginkan; entries("all") has all three; Ginkan off = "1" → not in either
stats_from_broken_copy_is_tamed: STATS without sid, STATS { sid = S, q = "x", s_dt = "-4", a_st = "abc" } →
  no error lines, Frostie's numbers empty
logout_sends_stats_directly: count jp 1; PLAYER_LOGOUT → a STATS text in W.sent right away (no advance)
```

- [ ] **Step 2: Run** `tests/run.sh stats`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the sharing.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: share stats rarely and in bulk`.

---

### Task 7: Live roasts (module "roasts")

**Files:**
- Create: `TwizCrew/Stats/Roasts.lua`, `tests/test_roasts.lua`
- Modify: TOC, `TwizCrew/UI/Popups.lua` (roast frames), `tests/test_stats.lua` (drop the Task 5 `ns.Roasts` stand-in
  where the real module now answers)

**Interfaces:**
- `Popups.showRoast(text, seconds)`: shows one pop-up with an orange edge `c46a00` for `seconds` (+ fade), whether
  or not the pop-ups module is on; a frame whose time is over closes itself in `OnUpdate` (no ticker needed). It is
  in `shownForTest()` / `textsForTest()`.
- Produces `ns.Roasts`: `LINES[kind]` (at least 3 lines per kind, placeholders `{name}`, `{v}` (number, formatted
  with `StatsLogic.number`), `{x}`), e.g. weak: `"{name} died to a level {v} {x}. Embarrassing."`, fall: `"{name}
  forgot gravity exists."`, drown: `"{name} tried to breathe water. It didn't work."`, again: `"{name} is back for
  more. Dead again in {v} seconds."`, deaths: `"That's death #{v} tonight for {name}."`, wipe: `"WIPE! Everybody
  down in {x}."`, steps: `"{name} just passed {v} steps. Still lost."`, jumps: `"{name} has jumped {v} times.
  Why."`, quit: `"{name} gave up on another quest. That's {v} tonight."` (these first lines are the spec's); the
  builder writes the rest, plain and playful, about the game only.
  - `text(kind, n, name, v, x) → string` (pure): `n` out of range → line 1; `name` and `x` through `safeText`
    (missing `x` → `"mob"` for weak, `"a dungeon"` for wipe).
  - `send(kind, v, x)`: nothing unless the `stats` module is on and the roasts setting `aboutMe` is on; sender
    limiter `ROAST_GAP` keyed by me; wipe: skip when a wipe roast was seen in the last `WIPE_ROAST_DEDUPE` s, else
    wait a random 0–2 s and check again; `n = math.random(#LINES[kind])`; `Comm.send("ROAST", { k, v, x, n })`, then
    shows it locally through the receive path as from me.
  - Receive (`Comm.on("ROAST")` at file load): unknown kind → ignored; wipe → dropped within `WIPE_ROAST_DEDUPE` of
    the last wipe roast; others → per-sender `ROAST_GAP` limiter; then, only when the roasts module is on and the
    kind's setting is on: `Popups.showRoast(text, ROAST_SECONDS)`, `PlaySound(SOUNDKIT.RAID_WARNING)` when `sound`
    is on, one `info` log line. `forTest.shown()` lists shown texts.
  - Module `roasts` ("Live roasts"): toggles `weak`, `fall`, `drown`, `again`, `deaths`, `wipe`, `steps`, `jumps`,
    `quit` (labels in plain words, e.g. "Died to a weak mob"), `aboutMe` ("Roasts about me", on), `sound` ("Play a
    sound", **off**); each with an `info` text; `aboutMe`'s says it stops your copy from sending roasts about you.

- [ ] **Step 1: Write the failing tests** (`files = "toc"`, boot; past the 20 s session decision)

```lua
roast_text_is_safe: Roasts.text("weak", 1, "Holy|bøi", 3, "|cffKobold") == "Holy||bøi died to a level 3 ||cffKobold. Embarrassing."
  Roasts.text("steps", 1, "Ginkan", 100000) == "Ginkan just passed 100,000 steps. Still lost."; Roasts.text("weak", 99, "A", 3) uses line 1
every_kind_has_three_lines: for each ROAST_KINDS kind, #LINES[kind] >= 3, and each line has "{name}" or (wipe) "{x}"
own_roast_is_sent_and_shown: Roasts.send("fall") → one ROAST in W.sent (k = "fall", n in range); textsForTest has
  a line containing "Twiz"
received_roast_shows_same_line: ROAST from Frostie { k = "fall", n = "2" } → shown text == Roasts.text("fall", 2, "Frostie")
rate_limit_per_person: two ROASTs from Frostie 3 s apart → one shown; one from Ginkan meanwhile → shown;
  Frostie again after 11 s → shown
wipe_dedupe: ROAST wipe from Frostie, then from Ginkan 5 s later → one shown; my own Roasts.send("wipe", nil, "X")
  within 60 s → nothing sent
about_me_off_sends_nothing: Modules.set("roasts", "aboutMe", false); Roasts.send("fall") → no ROAST sent, nothing shown
stats_off_sends_nothing: Modules.setEnabled("stats", false) → Roasts.send("fall") sends nothing
receiver_side_switches: Modules.set("roasts", "fall", false) → Frostie's fall roast not shown, Frostie's weak shown;
  Modules.setEnabled("roasts", false) → nothing shown, but my own Roasts.send still sends
sound_off_by_default: a roast shown → no PlaySound; sound on → recorded
roast_popup_closes_itself: popups module off; a roast shows, W:advance(7) → Popups.visibleCount() == 0
```

- [ ] **Step 2: Run** `tests/run.sh roasts`. Expected: FAIL.
- [ ] **Step 3: Implement** `Popups.showRoast` and Roasts.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: live roasts`.

---

### Task 8: Hall of Shame tab and award titles

**Files:**
- Create: `TwizCrew/UI/BoardLogic.lua`, `TwizCrew/UI/Board.lua`, `tests/test_board.lua`
- Modify: TOC, `TwizCrew/UI/PanelLogic.lua` (row `title`), `TwizCrew/UI/Panel.lua` (tabs, title line, board
  hosting, redraw on `STATS_CHANGED`, `SESSION_CHANGED`)

**Interfaces:**
- `PanelLogic.rows(members, settings, relationOf, tagsOn, now, wall, titleOf)`: new optional `titleOf(name) →
  string|nil`; row gets `title` (through `safeText`), not for offline rows.
- Produces `ns.BoardLogic` (pure):
  - `model(view, awardsList, ctx) → { subtitle, rows, footer }` with `ctx = { session = s|nil, starter, timeText,
    wipeLine = bool, entries = { [name] = entry }, online = fn(name) → bool, wall }`. `subtitle`: session view → `"Session started <timeText> by <starter>"` (or `"Waiting for the
    crew session to start"` when `session` is nil); all → `"All time"`. Rows one per award: `{ id, name, icon,
    winners = array of names (safeText), text, empty, tip = array of lines }`; empty → `text = "nobody yet"`.
    `tip` = award `info`, then up to 3 lines `"1. Name: 7 deaths"`; the corpse row adds `"Time dead: <duration>"`
    for each top name with `ds`; a top line of someone who is offline (`ctx.online(name)` false, not mine) ends
    with `" (updated 2h ago)"` (`Util.ago(ctx.wall - entry.at)`; `ctx.entries` maps names to entries). `footer`: when `wipeLine` and the highest `wp` > 0 → `"Wipe Squad: N wipe(s)
    tonight"` (session) / `"Wipe Squad: N wipe(s)"` (all); else nil.
  - `timeText(wall) → "9:02 pm"` (from `date("%I:%M %p")`, leading zero dropped, lower case).
- Produces `ns.Board`: `draw(parent, top, width) → height` (rows pooled: badge icon (`def.icon`, fallback
  `ICON_FALLBACK`), award name, winners in class colours, number text; greyed rows for empty; hover → GameTooltip
  with `tip`; two switch buttons "This session" / "All time" at the top; footer line), `hide()`, `view() →
  "session"|"all"`, `setView(v)`, `modelForTest() → last model`. Opening the tab or switching view calls
  `ns.Stats.request()`.
- `Panel`: header shows two tab buttons "Crew" and "Hall of Shame" while the `stats` module is on; `Panel.setTab(id)`
  (`"crew"|"shame"`), `Panel.tab()`; the shame tab hides crew rows and calls `Board.draw`; stats off → back to crew,
  tabs hidden. Titles: when the stats setting `titles` is not `"off"`, `titleOf` = `StatsLogic.titles(awards(entries(
  view, Session.current() id)))` for that view (computed once per redraw), drawn as a small muted line under the
  name in every row style.

- [ ] **Step 1: Write the failing tests** (`files = "toc"`, boot; numbers put in with `StatsStore.add` and
  `applyWire`)

```lua
title_on_row_model: rows with titleOf = function(n) return n == "Ginkan" and "Professional Corpse" or nil end
  → Ginkan row title "Professional Corpse", others nil; offline row → nil
board_rows_model: awards from entries Twiz dt 7, "Holy|bøi" dt 9 → model("session", list, { session = s, starter =
  "Twiz", timeText = "9:02 pm", wipeLine = true }): subtitle "Session started 9:02 pm by Twiz"; corpse row winners
  { "Holy||bøi" }, text "9 deaths"; gravity row empty, text "nobody yet"; tip[1] == corpse info, tip[2] == "1. Holy||bøi: 9 deaths"
offline_friend_tip_says_when: Frostie offline, entry at = wall - 7200 → her tip line ends " (updated 2h ago)"
board_footer: wp 2 → "Wipe Squad: 2 wipes tonight"; all view "Wipe Squad: 2 wipes"; wipeLine false → nil; wp 0 → nil
time_text: BoardLogic.timeText at a wall time whose date gives "09:02 PM" → "9:02 pm" (stub date via os.date in tests)
tabs_switch_and_request: Panel.setTab("shame") → a STATSREQ sent, Board.modelForTest() not nil, crew rows hidden
  (Panel.rowCountForTest() == 0); setTab("crew") → rows back; Modules.setEnabled("stats", false) → Panel.tab() == "crew"
titles_follow_setting: Frostie session dt 3 (sid = current) → Panel.models() Frostie row title "Professional Corpse";
  Modules.set("stats", "titles", "off") → nil
board_draws_without_errors: 12 friends with numbers, both views, setView, STATS_CHANGED, resetAll → ns.Log.errors(10) == {}
```

- [ ] **Step 2: Run** `tests/run.sh board`. Expected: FAIL.
- [ ] **Step 3: Implement** BoardLogic, Board, the PanelLogic and Panel changes.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED` (v1 panel tests unchanged).
- [ ] **Step 5: Commit** `feat: Hall of Shame tab and award titles`.

---

### Task 9: Awards show, commands and report

**Files:**
- Create: `TwizCrew/UI/AwardsShow.lua`, `tests/test_awards.lua`
- Modify: TOC, `TwizCrew/UI/Commands.lua`, `TwizCrew/UI/Report.lua`, `tests/test_ui.lua` (new command tests only)

**Interfaces:**
- Produces `ns.AwardsShow`: `start(view)` (`"session"|"all"`): refuses with a chat line when the stats module is off
  (`TwizCrew: turn on Stats & Hall of Shame in /tc first.`) or during a fight (`InCombatLockdown()` or
  `UnitAffectingCombat("player")`: `TwizCrew: the awards show waits until the fight is over.`); else opens the window
  "TwizCrewAwards" (centre, dark `0d0d12` with a gold `ffd100` border/glow, about 420×260, strata DIALOG, in
  `UISpecialFrames` so Escape closes it), shows "Getting the latest numbers…" (phase `loading`), calls `Stats.request()`, and after
  `SHOW_WAIT` s builds `StatsLogic.showCards(awards(entries(view, session id)))`. No award won → one card "Nobody has
  won anything yet." before the end card. Each award card: phase `badge` (icon, award name; `SOUNDS.badge`), after
  `SHOW_BADGE` s `drum` ("and the award goes to…"), after `SHOW_DRUMROLL` s `reveal` (winner names in class colour,
  number text, `def.joke`; `SOUNDS.reveal`). Click or Space: before `reveal` → jump to reveal; at reveal → next card.
  End card: "That's the show. GG crew." (next → close). Sounds only when the stats setting `showSound` is on
  (`PlaySound(SOUNDKIT[kit] or id)`). Keyboard: `EnableKeyboard(true)` out of combat; `OnKeyDown` sets
  `SetPropagateKeyboardInput(key ~= "SPACE")` only when not `InCombatLockdown()`; `PLAYER_REGEN_DISABLED` →
  `EnableKeyboard(false)` (clicks still work). Hooks: `isOpen()`, `close()`, `next()`, `stateForTest() → { phase,
  index, count, title, winners, text }`.
- `Commands`: `awards` (`""` → session, `"all"` → all time), `session` (`"new"` → `Session.newByHand()` +
  `TwizCrew: new session started. Everyone's session stats start from 0.`; else help), `stats` (`"reset"` → `TwizCrew:
  this sets all your own stats (this session and all time) back to 0. Type /tc stats reset yes to do it.`; `"reset
  yes"` → `StatsStore.resetMine()`, `Stats.send()`, `TwizCrew: your stats are back to 0.`). Help gains, in plain
  words: `/tc awards`, `/tc awards all`, `/tc session new`, `/tc stats reset`.
- `Report.lines()` gains, after "Turned off after errors": `"Stats: <on|off>, steps by <speed|position|off>,
  detectors off: <id (why), …|none>"`, `"Session: <id> started <timeText> (<by hand|automatic>)"` or `"Session: not
  decided yet"`, `"Stats sent <ago|never>, heard <ago> from <name>|never"`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/test_awards.lua (boot, past 21 s, Frostie's and my numbers in the current session)
show_walks_through_cards: Twiz dt 7, Frostie rz 2 (sid = current) → AwardsShow.start("session"); a STATSREQ sent;
  stateForTest().phase == "loading"; W:advance(5) → phase "badge", title "Professional Corpse";
  W:advance(0.6) → "drum"; W:advance(1.5) → "reveal", winners { "Twiz" }, text "7 deaths"; next() → title "Medic"
  (medic last), next() during badge → "reveal"; next() → end card text "That's the show. GG crew."; next() → closed
show_skips_empty_and_handles_nobody: no numbers at all → after 5 s card "Nobody has won anything yet."
show_refuses_in_fight_and_when_off: st.combat = true → printed fight line, not open; stats off → printed off line
show_all_time_uses_all_numbers: Frostie record with another sid but a_dt 9 → "all" winner Frostie
sounds_follow_setting: reveal → PlaySound recorded; Modules.set("stats", "showSound", false) → no new sounds
-- tests/test_ui.lua (add)
session_new_command: tc("session new") → Session.current().manual, printed line, an UPDATE with the new sid
stats_reset_asks_first: count dt 3; tc("stats reset") → still 3, printed question; tc("stats reset yes") → 0, a STATS sent
awards_command_opens_show: tc("awards") → AwardsShow.isOpen(); tc("awards all") after close → open
help_lists_new_commands: tc("help") printed lines contain "/tc awards", "/tc session new", "/tc stats reset"
report_has_stats_lines: Report.lines() contains a line starting "Stats: on, steps by speed", "Session: ", "Stats sent "
```

- [ ] **Step 2: Run** `tests/run.sh "awards|ui"`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** AwardsShow, the commands and the report lines.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: awards show, session and stats commands, report lines`.

---

### Task 10: Two-copy simulation, in-game checklist, PROJECT.md

**Files:**
- Modify: `tests/test_sim.lua`, `docs/TESTING.md`, `PROJECT.md`, this plan ("Changes during build")

**Interfaces:**
- Consumes everything above through the multi-client helper (`H.client`, `H.link`, `H.advance`, `login`, `tc`).

- [ ] **Step 1: Write the new simulation tests** (they should pass if Tasks 1–9 are right; any failure is a real bug
  to fix in the owning file)

```lua
same_session_on_both: Twiz and Frostie log in, H.advance(25) → both Session.current().id equal
weak_mob_roast_on_both_screens: Frostie level 20 targets a hostile level 3 "Kobold Miner" and dies; H.advance(3)
  → the same roast text ("…Frostie…Kobold Miner…") in both clients' Roasts.forTest.shown()
session_new_resets_both: both counted deaths; tc(tw, "session new"); H.advance(5) → both on Twiz's manual session,
  both session dt 0, all-time dt kept
awards_same_on_both: both count different things; Twiz opens the Hall of Shame (STATSREQ), H.advance(6) →
  StatsLogic.awards(entries("session", id)) gives the same winners/values on both clients
stats_off_hides_me_for_friends: Frostie turns stats off; H.advance(3) → Twiz's entries have no Frostie
no_errors_with_stats: the v1 sequence (other layer, zone change, death, odd status, report) plus a roast and the
  awards show (next() to the end), H.advance(320) → every client's ns.Log.errors(50) == {}
```

- [ ] **Step 2: Run** `tests/run.sh sim`. Expected: `ALL PASSED`, or fix the bug found and run again.
- [ ] **Step 3: Write the new in-game checks into `docs/TESTING.md`** (a new section "Stats, roasts and the awards
  show", riskiest first, plain words): no lag or errors with stats on for a long session; `/tc report` "Stats:" line
  (steps by speed, which detectors are off); steps go up when walking and not on a flight path; a fall death, a
  drowning, a death to a low mob (target it first) each give the right roast; jumps, hearthstone, junk loot,
  repair, abandon a quest, lose a duel each count (check the Hall of Shame); the Crew panel tabs and the Hall of
  Shame look; titles under names; `/tc awards` on stream (Space, click, Escape); with a friend: same session, roasts
  on both screens, `/tc session new`, stats off hides you.
- [ ] **Step 4: Update `PROJECT.md`** "Where we are": stats board built, plan path, not tested in game, not published.
- [ ] **Step 5: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 6: Commit** `feat: stats simulation tests, in-game checklist`.

## Changes during build

(Filled in while building.)
