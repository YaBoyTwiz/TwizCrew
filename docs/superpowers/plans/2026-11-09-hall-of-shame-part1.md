# Hall of Shame upgrade, part 1 (new awards + category tabs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 11 awards (Pauper, Money Pit, Ninja, Out of Juice, Too Far Away, Wanderer, Snail, Chatterbox, Emote
Spammer, Tourist, Frequent Flyer) and split the Hall of Shame into five category tabs.

**Architecture:** New stat keys are counted by new guarded detectors in `Stats/Detectors.lua` and saved/shared by the
existing `StatsStore` / `STATS` message. Two new kinds of number join the plain sums: a *set* key (gold carried now,
`gn`) and a *distinct* count (zones visited, `zv`, backed by saved zone sets). Award definitions get a `tab` field;
`BoardLogic.model` shows only the chosen tab's rows; `Board` draws a row of tab buttons.

**Tech Stack:** Lua 5.1 (WoW addon), tests with the repo's own runner and fake game (`tests/run.lua`,
`tests/wowstub.lua`). On Windows run tests with `tools/lua51/lua5.1.exe tests/run.lua [pattern]`; elsewhere
`tests/run.sh [pattern]`. Expected output for a full run: `ALL PASSED (N tests)`.

**Spec:** `docs/superpowers/specs/2026-11-09-hall-of-shame-upgrade-design.md`, sections 3 and 4.

## Global Constraints

- Never test a value from the game with `if`, `==`, `<` or math before `issecretvalue` says it isn't secret (in
  dungeons even `UnitIsAFK` is secret; testing one is a Lua error). In `Detectors.lua` use the existing `secret(v)`
  and `player(f)` helpers.
- No message per event: counting is local; numbers ride the existing `STATS` message (spec, stats board section 8).
- Every new detector: `needs()` reports a missing API (detector turns itself off, logged once), errors inside it
  turn only that detector off (the existing `guard`). `/tc report` already lists detectors that are off.
- Older copies ignore unknown keys: never rename or reuse an existing key.
- Chat and emote counting keeps only the count, never the words.
- Pauper shows the exact amount ("14c") (owner).
- Tabs (owner: "Category tabs"): Deaths, On the Move, Money & Loot, Butterfingers, Lazy & Loud, with the award lists
  of spec section 4. Medic stays the last card of the awards show.
- Plain words in everything a player reads (README/CLAUDE.md style: short, no jargon).
- Commit only when the owner has asked for commits (the owner said "build it"; ask before the first commit if
  unsure). Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions made while planning (Claude's call)

- **Tab button labels are short** so five fit in the 320 px board: `Deaths`, `Moving`, `Money`, `Oops`, `Lazy`. The
  tab's full name (spec section 4) starts the subtitle line: "Butterfingers: session started 9:02 pm by Twiz".
- **Snail** uses two keys: `xg` (XP gained) and `xt` (seconds played below max level). Value = `xg / (xt / 3600)`,
  taking part only with `xt >= COUCH_MIN_PLAYED` (30 min). Max-level time is never in `xt`, so max-level characters
  never take part.
- **Wanderer** reuses `FindLogic.runaway` with the two positions swapped (spec section 3), inside `Find.lua`, which
  fires the bus event `RAN_OFF`; the `wander` detector counts it. It counts even when the alarm is switched off.
- **Gold carried** (`gn`) is sent even when it is 0 (0 gold is the best Pauper). Every other key is still sent only
  when above 0.
- The award table is reordered tab by tab. Award titles on the Crew tab follow table order, so title priority now
  follows the tabs (Deaths first): Furniture moves after the movement awards.

## New stat keys (all added to `StatsDefs.KEYS`, in this order, after `pt`)

| Key | Meaning | Kind |
|---|---|---|
| `gn` | copper carried now | set (same number in session and all time) |
| `ml` | copper lost (sum of every drop) | sum |
| `mg` | copper gained (sum of every rise) | sum |
| `nj` | Need rolls won in a group | sum |
| `oj` | "Not enough mana/rage/energy/focus" errors (2 s apart) | sum |
| `tf` | "Out of range" / "You are too far away" errors (2 s apart) | sum |
| `wd` | times you ran off from a group member | sum |
| `xg` | XP gained | sum |
| `xt` | seconds played below max level | sum, time key (never makes a send due) |
| `ch` | your party/raid/instance chat messages | sum |
| `em` | your emotes | sum |
| `zv` | different zones visited | distinct count |
| `fp` | flight paths taken | sum |

## File map

- Modify `TwizCrew/Stats/StatsDefs.lua`: keys, `SET_KEYS`, `TIME_KEYS`, `TABS`, `ERRORS`, reordered `AWARDS` with
  `tab`, 11 new awards.
- Modify `TwizCrew/Stats/StatsStore.lua`: `Store.set`, `Store.addZone`, zone sets reset with the session.
- Modify `TwizCrew/Stats/StatsLogic.lua`: wire sends set keys at 0, `errorKey`, `needWin`, `xpGained`, new unit words.
- Modify `TwizCrew/Stats/Stats.lua`: `Stats.set`, `Stats.zone`, api entries, `boardTab` default.
- Modify `TwizCrew/Stats/Detectors.lua`: detectors `gold`, `errors`, `ninja`, `chatter`, `travel`, `xp`, `wander`.
- Modify `TwizCrew/Find/Find.lua`: mirrored running-off check → `RAN_OFF`.
- Modify `TwizCrew/UI/BoardLogic.lua`, `TwizCrew/UI/Board.lua`: tabs.
- Tests: `tests/test_statslogic.lua`, `tests/test_stats.lua`, `tests/test_board.lua`, `tests/test_find_ui.lua`.
- Docs: `docs/TESTING.md` (in-game checks), `PROJECT.md` (status line).

---

### Task 1: New keys, set and distinct numbers in the store and on the wire

**Files:**
- Modify: `TwizCrew/Stats/StatsDefs.lua:4-10`
- Modify: `TwizCrew/Stats/StatsStore.lua`
- Modify: `TwizCrew/Stats/StatsLogic.lua` (`L.toWire`)
- Test: `tests/test_stats.lua`, `tests/test_statslogic.lua`

**Interfaces:**
- Produces: `ns.StatsDefs.SET_KEYS = { gn = true }`; `Store.set(key, value) -> changed:boolean`;
  `Store.addZone(zone) -> added:boolean` (adds 1 to `zv` in each view where the zone is new);
  `L.toWire` sends set keys even at 0.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_stats.lua` inside `tests = { ... }` (helpers `start`, `get` already exist there):

```lua
    set_and_distinct_numbers = function(ns, A, W)
      start(ns, W)
      local S = ns.StatsStore
      S.markSent()
      A.eq(S.set("gn", 500), true)
      A.eq(get(ns, "session", "gn"), 500)
      A.eq(get(ns, "all", "gn"), 500, "the same number in both views")
      A.ok(S.dirty())
      S.markSent()
      A.eq(S.set("gn", 500), false, "no change: not dirty")
      A.no(S.dirty())
      A.eq(S.set("gn", 0), true, "0 gold is a real value")
      A.eq(get(ns, "session", "gn"), 0)
      A.eq(S.set("dt", 9), false, "only set keys can be set")
      -- zones: counted once per view
      A.eq(S.addZone("Elwynn Forest"), true)
      A.eq(S.addZone("Elwynn Forest"), false)
      A.eq(S.addZone("Westfall"), true)
      A.eq(get(ns, "session", "zv"), 2)
      A.eq(get(ns, "all", "zv"), 2)
      A.eq(S.addZone(""), false)
      -- a new session: session zones start over, all time keeps them
      S.setSession("Ginkan-1", nil, false)
      A.eq(get(ns, "session", "zv"), 0)
      A.eq(S.addZone("Westfall"), true, "new this session")
      A.eq(get(ns, "session", "zv"), 1)
      A.eq(get(ns, "all", "zv"), 2, "not new for all time")
      A.eq(get(ns, "session", "gn"), 0, "gold carried is gone until set again")
    end,
```

Add to `tests/test_statslogic.lua` inside `tests = { ... }`:

```lua
    wire_sends_gold_carried_at_zero = function(ns, A)
      local L = ns.StatsLogic
      local f = L.toWire({ sid = "x", q = "1", s = { gn = 0, dt = 0, ml = 50 }, a = { gn = 0, zv = 3 } })
      A.eq(f.s_gn, "0", "0 gold goes out")
      A.eq(f.s_dt, nil, "other zeros don't")
      A.eq(f.s_ml, "50")
      A.eq(f.a_zv, "3")
      local back = L.fromWire(f)
      A.eq(back.s.gn, 0)
      A.eq(back.a.zv, 3)
    end,
```

- [ ] **Step 2: Run them to see them fail**

Run: `tools/lua51/lua5.1.exe tests/run.lua "set_and_distinct|wire_sends_gold"`
Expected: FAIL (`attempt to call field 'set' (a nil value)` and `s_gn` nil).

- [ ] **Step 3: Implement**

In `TwizCrew/Stats/StatsDefs.lua` replace the `KEYS`, `MIN_KEYS` and `TIME_KEYS` lines with:

```lua
  -- Every stat key, in wire order. All are sums except "ld" (a minimum), "gn" (set: the number now, the same in
  -- both views, sent even at 0) and "zv" (distinct zones, see StatsStore.addZone).
  KEYS = { "dt", "df", "dd", "dw", "db", "ld", "pl", "wp", "af", "ds", "st", "mt", "sw", "jp", "hs", "jk", "rp",
           "qa", "dl", "dv", "rz", "pt", "gn", "ml", "mg", "nj", "oj", "tf", "wd", "xg", "xt", "ch", "em", "zv", "fp" },
  MIN_KEYS = { ld = true },
  SET_KEYS = { gn = true },
  -- Keys that never make a send due (time just passing).
  TIME_KEYS = { pt = true, xt = true },
```

In `TwizCrew/Stats/StatsStore.lua`:

1. In `Store.mine()` after `if type(rec.a) ~= "table" then rec.a = {} end` add:

```lua
  -- zones seen (names -> true): this session and all time, for "zv" (Tourist)
  if type(rec.zs) ~= "table" then rec.zs = {} end
  if type(rec.za) ~= "table" then rec.za = {} end
```

2. After `function Store.add(...) ... end` add:

```lua
-- A set key (Defs.SET_KEYS): the number now, the same in both views. Returns true when it changed.
function Store.set(key, value)
  if not Defs.SET_KEYS[key] or not isNumber(value) or value < 0 then return false end
  local rec = Store.mine()
  if not rec then return false end
  if rec.s[key] == value and rec.a[key] == value then return false end
  rec.s[key], rec.a[key] = value, value
  isDirty = true
  return true
end

-- A zone visited: "zv" goes up by one in each view where it is new. Returns true when it was new anywhere.
function Store.addZone(zone)
  if type(zone) ~= "string" or zone == "" then return false end
  local rec = Store.mine()
  if not rec then return false end
  local added = false
  for _, pair in ipairs({ { rec.zs, rec.s }, { rec.za, rec.a } }) do
    local seen, t = pair[1], pair[2]
    if not seen[zone] then
      seen[zone] = true
      t.zv = (isNumber(t.zv) and t.zv or 0) + 1
      added = true
    end
  end
  if added then isDirty = true end
  return added
end
```

3. In `Store.setSession`, change `if not (keep and fromId ~= nil and rec.sid == fromId) then rec.s = {} end` to:

```lua
  if not (keep and fromId ~= nil and rec.sid == fromId) then rec.s, rec.zs = {}, {} end
```

4. In `Store.resetMine`, change `rec.s, rec.a = {}, {}` to `rec.s, rec.a, rec.zs, rec.za = {}, {}, {}, {}`.

In `TwizCrew/Stats/StatsLogic.lua` `L.toWire`, replace `if v > 0 then f[prefix .. "_" .. key] = string.format("%.0f", v) end` with:

```lua
          if v > 0 or (v == 0 and ns.StatsDefs.SET_KEYS[key]) then
            f[prefix .. "_" .. key] = string.format("%.0f", v)
          end
```

- [ ] **Step 4: Run them to see them pass, then the whole suite**

Run: `tools/lua51/lua5.1.exe tests/run.lua "set_and_distinct|wire_sends_gold"` → `ALL PASSED (2 tests)`
Run: `tools/lua51/lua5.1.exe tests/run.lua` → `ALL PASSED`

- [ ] **Step 5: Commit** (if the owner allowed commits)

```bash
git add TwizCrew/Stats/StatsDefs.lua TwizCrew/Stats/StatsStore.lua TwizCrew/Stats/StatsLogic.lua tests/test_stats.lua tests/test_statslogic.lua
git commit -m "feat(stats): gold-carried and zones-visited numbers, 13 new stat keys"
```

---

### Task 2: Tabs and the 11 new award definitions

**Files:**
- Modify: `TwizCrew/Stats/StatsDefs.lua` (`AWARDS`, new `TABS`)
- Modify: `TwizCrew/Stats/StatsLogic.lua` (`UNIT_WORDS`, `L.valueText`)
- Test: `tests/test_statslogic.lua` (the existing award-table test near line 132, plus a new one)

**Interfaces:**
- Consumes: keys from Task 1.
- Produces: `ns.StatsDefs.TABS = { { id, label, name } x5 }`; every award has `tab` (one of the tab ids); award ids
  `pauper, moneypit, ninja, juice, toofar, wanderer, snail, chatter, emotes, tourist, flyer`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_statslogic.lua`, replace the lines that check the old table (`A.eq(#D.AWARDS, 18)` through the
`couch`/`lowest` check, around lines 132-136) with:

```lua
      A.eq(#D.AWARDS, 29)
      A.eq(D.AWARDS[1].id, "corpse")
      A.eq(D.AWARDS[29].id, "medic")
      A.ok(D.AWARDS[29].last)
      local tabs, perTab = {}, {}
      for _, t in ipairs(D.TABS) do tabs[t.id] = true; perTab[t.id] = 0 end
      A.eq(#D.TABS, 5)
      local lastTab = 1
      for _, d in ipairs(D.AWARDS) do
        A.ok(tabs[d.tab], d.id .. " has a tab")
        perTab[d.tab] = perTab[d.tab] + 1
        local idx
        for i, t in ipairs(D.TABS) do if t.id == d.tab then idx = i end end
        A.ok(idx >= lastTab, d.id .. ": the table runs tab by tab")
        lastTab = idx
      end
      A.eq(perTab, { deaths = 6, move = 7, loot = 5, oops = 6, lazy = 5 })
```

(Keep the existing `for _, d in ipairs(D.AWARDS) do` loop that follows, which checks icons/info/jokes.) Also change
`A.eq(#list, 18)` (around line 163) to `A.eq(#list, 29)`.

Add a new test:

```lua
    new_awards_pick_the_right_winner = function(ns, A)
      local L = ns.StatsLogic
      local function award(list, id)
        for _, a in ipairs(L.awards(list)) do if a.def.id == id then return a end end
      end
      local list = {
        { name = "Twiz", stats = { gn = 14, ml = 5000, mg = 1000, xg = 3000, xt = 3600, zv = 4, fp = 2 } },
        { name = "Lurabe", stats = { gn = 90000, ml = 100, mg = 900, xg = 9000, xt = 3600 } },
        { name = "Ginkan", stats = { gn = 0, xg = 100, xt = 600 } },
      }
      local p = award(list, "pauper")
      A.eq(p.winners, { "Ginkan" }, "0 gold wins")
      A.eq(p.text, "0c")
      local m = award(list, "moneypit")
      A.eq(m.winners, { "Twiz" })
      A.eq(m.text, "40s", "lost 5000, gained 1000")
      local s = award(list, "snail")
      A.eq(s.winners, { "Twiz" }, "Ginkan played under 30 minutes: not taking part")
      A.eq(s.text, "3,000 XP per hour")
      A.eq(award(list, "tourist").text, "4 zones")
      A.eq(award(list, "flyer").text, "2 flights")
      A.ok(award(list, "ninja").empty, "nobody yet")
    end,
```

- [ ] **Step 2: Run them to see them fail**

Run: `tools/lua51/lua5.1.exe tests/run.lua test_statslogic`
Expected: FAIL (`expected 29, got 18`).

- [ ] **Step 3: Implement**

In `TwizCrew/Stats/StatsDefs.lua`, before `ns.StatsDefs.AWARDS`, add:

```lua
-- The Hall of Shame's tabs, in order (owner: "Category tabs"). label = the short button text (five must fit in the
-- 320 px board); name = the full name, shown at the start of the subtitle.
ns.StatsDefs.TABS = {
  { id = "deaths", label = "Deaths", name = "Deaths" },
  { id = "move", label = "Moving", name = "On the Move" },
  { id = "loot", label = "Money", name = "Money & Loot" },
  { id = "oops", label = "Oops", name = "Butterfingers" },
  { id = "lazy", label = "Lazy", name = "Lazy & Loud" },
}
```

Replace the whole `ns.StatsDefs.AWARDS = { ... }` table with the version below. The 18 old entries keep their exact
fields (only `tab` is added and the order changes); the 11 new ones are marked `-- new`.

```lua
-- Every award, tab by tab (TABS order), in show order. `key` = plain stat, or `value(stats)` -> number | nil (nil =
-- not taking part). `lowest` = the smallest value wins; `last` = shown at the end of the show.
ns.StatsDefs.AWARDS = {
  -- Deaths
  { id = "corpse", tab = "deaths", name = "Professional Corpse", key = "dt", unit = "death",
    icon = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    info = "Died the most.", joke = "Has seen more graveyards than loading screens." },
  { id = "gravity", tab = "deaths", name = "Gravity Tester", key = "df", unit = "fall",
    icon = "Interface\\Icons\\Spell_Magic_FeatherFall",
    info = "Died from falling the most.", joke = "Proved gravity works, again and again." },
  { id = "fishfood", tab = "deaths", name = "Fish Food", key = "dd", unit = "drown",
    icon = "Interface\\Icons\\Spell_Shadow_DemonBreath",
    info = "Drowned the most.", joke = "Forgot that water is not a floor." },
  { id = "weakling", tab = "deaths", name = "Died to a Weakling", key = "dw", unit = "weak",
    icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    info = "Died the most to monsters far below their own level.",
    joke = "Lost to something a few levels away from being a critter." },
  { id = "again", tab = "deaths", name = "Back for More", key = "db", unit = "again",
    icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
    info = "Died again within a minute of coming back the most.",
    joke = "The graveyard door had barely closed." },
  { id = "leeroy", tab = "deaths", name = "Leeroy", key = "pl", unit = "pull",
    icon = "Interface\\Icons\\Ability_Warrior_Charge",
    info = "Started the most fights in a dungeon before the crew was ready.",
    joke = "Who needs a plan when you have a charge button?" },
  -- On the Move
  { id = "marathon", tab = "move", name = "Marathon Runner", key = "st", unit = "steps",
    icon = "Interface\\Icons\\INV_Misc_Foot_Kodo",
    info = "Walked the most steps on foot.", joke = "Never met a mount they could not out-walk." },
  { id = "couch", tab = "move", name = "Couch Potato", unit = "perhour", lowest = true,
    value = function(st)
      local pt = st.pt
      if type(pt) ~= "number" or pt < ns.Config.COUCH_MIN_PLAYED then return nil end
      -- no steps at all = not taking part (Count steps off, or nothing counted): never a winner with 0
      if type(st.st) ~= "number" or st.st <= 0 then return nil end
      return st.st / (pt / 3600)
    end,
    icon = "Interface\\Icons\\INV_Misc_Fork&Knife",
    info = "Walked the fewest steps per hour (needs at least 30 minutes played).",
    joke = "Moves only when the loot window opens." },
  { id = "neverwalks", tab = "move", name = "Never Walks", unit = "ratio",
    value = function(st)
      local mt, yards = st.mt or 0, (st.st or 0) / ns.Config.STEPS_PER_YARD
      if mt + yards < ns.Config.NEVERWALKS_MIN_YARDS then return nil end
      return mt / math.max(yards, 1)
    end,
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    info = "Rode a mount far more than walked (needs at least 1,000 yards travelled).",
    joke = "Their own two feet are mostly decoration." },
  { id = "fish", tab = "move", name = "Fish", key = "sw", unit = "yards",
    icon = "Interface\\Icons\\INV_Misc_Fish_02",
    info = "Swam the most yards.", joke = "Was probably a murloc in a past life." },
  { id = "bunny", tab = "move", name = "Bunny Hopper", key = "jp", unit = "jumps",
    icon = "Interface\\Icons\\Ability_Rogue_Sprint",
    info = "Jumped the most times.", joke = "The space bar is worn smooth." },
  { id = "tourist", tab = "move", name = "Tourist", key = "zv", unit = "zones", -- new
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    info = "Visited the most different zones.", joke = "Has a postcard from every zone and a quest done in none." },
  { id = "flyer", tab = "move", name = "Frequent Flyer", key = "fp", unit = "flights", -- new
    icon = "Interface\\Icons\\Ability_Hunter_EagleEye",
    info = "Took the most flight paths.", joke = "The flight master knows their coffee order." },
  -- Money & Loot
  { id = "pauper", tab = "loot", name = "Pauper", key = "gn", unit = "money", lowest = true, -- new
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    info = "Carries the least gold right now.", joke = "Checks the couch cushions for copper." },
  { id = "moneypit", tab = "loot", name = "Money Pit", unit = "money", -- new
    value = function(st)
      local lost = (type(st.ml) == "number" and st.ml or 0) - (type(st.mg) == "number" and st.mg or 0)
      if lost <= 0 then return nil end
      return lost
    end,
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    info = "Lost the most gold (spent more than they made).", joke = "Gold goes in. Gold does not come out." },
  { id = "broke", tab = "loot", name = "Broke", key = "rp", unit = "money",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    info = "Paid the most for repairs.", joke = "The repair bot sends a thank-you card." },
  { id = "trash", tab = "loot", name = "Trash Collector", key = "jk", unit = "junk",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    info = "Picked up the most gray junk items.", joke = "Bags full of treasures nobody wants." },
  { id = "ninja", tab = "loot", name = "Ninja", key = "nj", unit = "needs", -- new
    icon = "Interface\\Icons\\Ability_Stealth",
    info = "Won the most Need rolls in a group.", joke = "Needed it. For an alt. Probably." },
  -- Butterfingers
  { id = "juice", tab = "oops", name = "Out of Juice", key = "oj", unit = "nojuice", -- new
    icon = "Interface\\Icons\\INV_Potion_76",
    info = "Tried to use a spell without enough mana, rage or energy the most.",
    joke = "Runs on fumes and good intentions." },
  { id = "toofar", tab = "oops", name = "Too Far Away", key = "tf", unit = "toofar", -- new
    icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    info = "Got \"Out of range\" or \"You are too far away\" the most.", joke = "Measures distance in hopes." },
  { id = "wanderer", tab = "oops", name = "Wanderer", key = "wd", unit = "wanders", -- new
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    info = "Ran off from a group member the most.", joke = "Was right behind you. Then wasn't." },
  { id = "quitter", tab = "oops", name = "Quitter", key = "qa", unit = "quests",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    info = "Abandoned the most quests.", joke = "The quest log is a list of good intentions." },
  { id = "duel", tab = "oops", name = "Duel Loser", key = "dl", unit = "duels",
    icon = "Interface\\Icons\\INV_Sword_04",
    info = "Lost the most duels.", joke = "Will definitely win the next one." },
  { id = "homesick", tab = "oops", name = "Homesick", key = "hs", unit = "hearths",
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    info = "Used the Hearthstone the most.", joke = "Always one step away from the inn." },
  -- Lazy & Loud
  { id = "chatter", tab = "lazy", name = "Chatterbox", key = "ch", unit = "messages", -- new
    icon = "Interface\\Icons\\Spell_Holy_Silence",
    info = "Sent the most party and raid chat messages (only the count is kept).",
    joke = "Types faster than they pull." },
  { id = "emotes", tab = "lazy", name = "Emote Spammer", key = "em", unit = "emotes", -- new
    icon = "Interface\\Icons\\Spell_Shadow_SoothingKiss",
    info = "Used the most emotes, like /dance and /lol.", joke = "Has a /dance for every occasion." },
  { id = "furniture", tab = "lazy", name = "Furniture", key = "af", unit = "afk",
    icon = "Interface\\Icons\\Spell_Nature_Sleep",
    info = "Spent the most time away from the keyboard.",
    joke = "Could be mistaken for a very quiet statue." },
  { id = "snail", tab = "lazy", name = "Snail", unit = "xpperhour", lowest = true, -- new
    value = function(st)
      local xt = st.xt
      if type(xt) ~= "number" or xt < ns.Config.COUCH_MIN_PLAYED then return nil end
      return (type(st.xg) == "number" and st.xg or 0) / (xt / 3600)
    end,
    icon = "Interface\\Icons\\Spell_Nature_Slow",
    info = "Gained the least XP per hour (needs at least 30 minutes played below max level).",
    joke = "Levels at the speed of continental drift." },
  { id = "medic", tab = "lazy", name = "Medic", key = "rz", unit = "rezzes", last = true,
    icon = "Interface\\Icons\\Spell_Holy_Resurrection",
    info = "Brought the most people back to life.", joke = "The crew's favorite sight after a wipe." },
}
```

In `TwizCrew/Stats/StatsLogic.lua`, add these to `UNIT_WORDS` (inside the table):

```lua
  zones = { "zone", "zones" }, flights = { "flight", "flights" }, needs = { "Need roll won", "Need rolls won" },
  nojuice = { "time out of juice", "times out of juice" }, toofar = { "time too far", "times too far" },
  wanders = { "run-off", "run-offs" }, messages = { "message", "messages" }, emotes = { "emote", "emotes" },
```

and in `L.valueText`, after `if unit == "perhour" then ... end` add:

```lua
  if unit == "xpperhour" then return L.number(value) .. " XP per hour" end
```

- [ ] **Step 4: Run the tests**

Run: `tools/lua51/lua5.1.exe tests/run.lua test_statslogic` → `ALL PASSED`
Run the whole suite: `tools/lua51/lua5.1.exe tests/run.lua`. Expected failures only in `test_board.lua` (tests that
look up awards no longer on the first tab are fixed in Task 9) and `test_awards.lua` if it checks card order. Fix
any `test_awards.lua` expectation that lists award ids in the old order by building the expected order from
`ns.StatsDefs.AWARDS` instead of a hard-coded list. Note the board failures; don't fix them here.

- [ ] **Step 5: Commit** (if allowed)

```bash
git add TwizCrew/Stats/StatsDefs.lua TwizCrew/Stats/StatsLogic.lua tests/test_statslogic.lua tests/test_awards.lua
git commit -m "feat(stats): 11 new awards, awards grouped into five tabs"
```

---

### Task 3: Gold detector (Pauper, Money Pit)

**Files:**
- Modify: `TwizCrew/Stats/Stats.lua` (`Stats.set`, api)
- Modify: `TwizCrew/Stats/Detectors.lua` (new detector `gold` after `repair`)
- Test: `tests/test_stats.lua`

**Interfaces:**
- Consumes: `Store.set` (Task 1).
- Produces: `api.set(key, value)`; `Stats.set(key, value)`.

- [ ] **Step 1: Write the failing test**

```lua
    gold_carried_lost_and_gained = function(ns, A, W)
      W.state.money = 10000
      start(ns, W)
      W:advance(1)
      A.eq(get(ns, "session", "gn"), 10000)
      A.eq(get(ns, "all", "ml"), 0, "the first reading is only where we start")
      W.state.money = 7500
      W:fire("PLAYER_MONEY")
      A.eq(get(ns, "session", "gn"), 7500)
      A.eq(get(ns, "session", "ml"), 2500)
      W.state.money = 8000
      W:advance(1) -- the tick notices too
      A.eq(get(ns, "session", "mg"), 500)
      local hidden = {}
      W.state.secret[hidden] = true
      W.state.money = hidden
      W:advance(1)
      A.eq(get(ns, "session", "gn"), 8000, "a secret amount is skipped")
      A.ok(statusOf(ns, "gold").on, "and never an error")
    end,
```

- [ ] **Step 2: Run it to see it fail**

Run: `tools/lua51/lua5.1.exe tests/run.lua gold_carried` → FAIL (`gn` is 0).

- [ ] **Step 3: Implement**

In `TwizCrew/Stats/Stats.lua` after `function Stats.count(...) ... end` add:

```lua
-- A set key (gold carried now): the same number in both views; STATS_CHANGED only when it changed.
function Stats.set(key, value)
  if not enabled then return end
  if Store.set(key, value) then changed() end
end
```

and add to the `api` table: `set = function(key, value) Stats.set(key, value) end,`

In `TwizCrew/Stats/Detectors.lua`, update the header comment line `-- api = { count(key, n), died(), alive(), wipe(zone) } (the stats module).`
to `-- api = { count(key, n), set(key, v), zone(name), died(), alive(), wipe(zone) } (the stats module).`
Then after the `repair` detector (`tick = readCost })`) add:

```lua
-- Gold carried now (Pauper) and every drop / rise of it (Money Pit). The first reading is only the starting point.
local lastMoney
local function readGold()
  local m = money()
  if m == nil then return end
  api.set("gn", m)
  if lastMoney ~= nil then
    local d = m - lastMoney
    if d < 0 then api.count("ml", -d) elseif d > 0 then api.count("mg", d) end
  end
  lastMoney = m
end

add({ id = "gold", label = "gold carried, lost and gained",
  needs = function() local why = missingOf("GetMoney"); return why == nil, why end,
  start = function()
    lastMoney = nil
    onEvent(byId.gold, "PLAYER_MONEY", readGold)
    readGold()
  end,
  tick = readGold })
```

In `D.stopAll`, change `merchantOpen, repairCost, repairMoney, lastPos = false, 0, nil, nil` to
`merchantOpen, repairCost, repairMoney, lastPos, lastMoney = false, 0, nil, nil, nil`.

- [ ] **Step 4: Run tests**

Run: `tools/lua51/lua5.1.exe tests/run.lua gold_carried` → PASS. The detector-list test in `test_stats.lua`
(around line 783) now fails: add `"gold"` after `"repair"` in its expected list.

- [ ] **Step 5: Commit** (if allowed): `feat(stats): count gold carried, lost and gained`

---

### Task 4: Red-error detector (Out of Juice, Too Far Away)

**Files:**
- Modify: `TwizCrew/Stats/StatsDefs.lua` (`ERRORS`), `TwizCrew/Stats/StatsLogic.lua` (`L.errorTexts`, `L.errorKey`),
  `TwizCrew/Stats/Detectors.lua` (detector `errors`)
- Test: `tests/test_statslogic.lua`, `tests/test_stats.lua`

**Interfaces:**
- Produces: `ns.StatsDefs.ERRORS = { oj = {global names}, tf = {global names} }`;
  `L.errorTexts(lists, globals) -> { [text] = key }`; `L.errorKey(message, texts) -> key | nil`.

- [ ] **Step 1: Write the failing tests**

`tests/test_statslogic.lua`:

```lua
    red_errors_are_matched_by_the_games_own_text = function(ns, A)
      local L = ns.StatsLogic
      local texts = L.errorTexts({ oj = { "ERR_OUT_OF_MANA", "ERR_NOPE" }, tf = { "ERR_USE_TOO_FAR" } },
        { ERR_OUT_OF_MANA = "Not enough mana", ERR_USE_TOO_FAR = "You are too far away." })
      A.eq(texts, { ["Not enough mana"] = "oj", ["You are too far away."] = "tf" }, "missing names are skipped")
      A.eq(L.errorKey("Not enough mana", texts), "oj")
      A.eq(L.errorKey("You are too far away.", texts), "tf")
      A.eq(L.errorKey("Can't do that while moving", texts), nil)
      A.eq(L.errorKey(nil, texts), nil)
    end,
```

`tests/test_stats.lua`:

```lua
    red_errors_count_once_per_two_seconds = function(ns, A, W)
      start(ns, W, function()
        W.env.ERR_OUT_OF_MANA = "Not enough mana"
        W.env.ERR_OUT_OF_RANGE = "Out of range."
      end)
      W:fire("UI_ERROR_MESSAGE", 51, "Not enough mana")
      W:fire("UI_ERROR_MESSAGE", 51, "Not enough mana") -- mashing the button
      A.eq(get(ns, "session", "oj"), 1)
      W:advance(2.1)
      W:fire("UI_ERROR_MESSAGE", "Not enough mana") -- older clients: the text comes first
      A.eq(get(ns, "session", "oj"), 2)
      W:fire("UI_ERROR_MESSAGE", 52, "Out of range.")
      A.eq(get(ns, "session", "tf"), 1)
      W:fire("UI_ERROR_MESSAGE", 53, "Can't do that while moving")
      A.eq(get(ns, "session", "oj") + get(ns, "session", "tf"), 3)
    end,
```

- [ ] **Step 2: Run to see them fail**

Run: `tools/lua51/lua5.1.exe tests/run.lua "red_errors"` → FAIL.

- [ ] **Step 3: Implement**

`TwizCrew/Stats/StatsDefs.lua`, inside `ns.StatsDefs = { ... }` after `SPELLS`:

```lua
  -- Red error texts, by the game's own global names (their text is read at start; a missing name is skipped).
  ERRORS = {
    oj = { "ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_FOCUS" },
    tf = { "ERR_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE", "ERR_USE_TOO_FAR" },
  },
```

`TwizCrew/Stats/StatsLogic.lua`, after `L.junkCount`:

```lua
-- { [error text] = stat key } from lists of global names (ns.StatsDefs.ERRORS) and the globals table.
function L.errorTexts(lists, globals)
  local out = {}
  for key, names in pairs(lists or {}) do
    for _, name in ipairs(names) do
      local text = globals and globals[name]
      if type(text) == "string" and text ~= "" then out[text] = key end
    end
  end
  return out
end

function L.errorKey(message, texts)
  if type(message) ~= "string" or type(texts) ~= "table" then return nil end
  return texts[message]
end
```

`TwizCrew/Stats/Detectors.lua`, after the `gold` detector:

```lua
-- Red errors: "Not enough mana" (Out of Juice), "Out of range" (Too Far Away). Repeats within ERROR_GAP s count once.
local ERROR_GAP = 2
local errorTexts, errorLimiter
add({ id = "errors", label = "red error messages",
  needs = function()
    errorTexts = Logic.errorTexts(ns.StatsDefs.ERRORS, _G)
    if next(errorTexts) == nil then return false, "no error texts" end
    return true
  end,
  start = function()
    errorLimiter = Logic.newLimiter(ERROR_GAP)
    onEvent(byId.errors, "UI_ERROR_MESSAGE", function(a, b)
      local message = a
      if type(a) ~= "string" then message = b end -- newer clients send (errorType, message)
      if secret(message) then return end
      local key = Logic.errorKey(message, errorTexts)
      if key and errorLimiter:allow(key, ns.now()) then api.count(key, 1) end
    end)
  end })
```

Note: `secret(a)` for the number argument is not needed; only `message` is tested. `type(a)` on a secret value is
allowed (it doesn't test the value).

- [ ] **Step 4: Run tests**: `red_errors` passes; add `"errors"` after `"gold"` in the detector-list test.

- [ ] **Step 5: Commit** (if allowed): `feat(stats): count out-of-power and out-of-range errors`

---

### Task 5: Ninja detector (Need rolls won)

**Files:**
- Modify: `TwizCrew/Stats/StatsLogic.lua` (`L.needWin`), `TwizCrew/Stats/Detectors.lua` (detector `ninja`)
- Test: `tests/test_statslogic.lua`, `tests/test_stats.lua`

**Interfaces:**
- Produces: `L.needWin(text, needFmt, wonFmt, needed, now, keep) -> boolean` (removes the matched link from `needed`).

- [ ] **Step 1: Write the failing tests**

`tests/test_statslogic.lua`:

```lua
    need_rolls_won = function(ns, A)
      local L = ns.StatsLogic
      local link = "|cff1eff00|Hitem:1:|h[Sword]|h|r"
      A.ok(L.needWin("You (Need - 87) Won: " .. link, "You (Need - %d) Won: %s", "You won: %s", {}, 10, 300),
        "the client says Need itself")
      local needed = { [link] = 5 }
      A.ok(L.needWin("You won: " .. link, nil, "You won: %s", needed, 10, 300), "we rolled Need on it")
      A.eq(needed[link], nil, "used up")
      A.no(L.needWin("You won: " .. link, nil, "You won: %s", needed, 10, 300), "Greed (not in the list)")
      A.no(L.needWin("You won: " .. link, nil, "You won: %s", { [link] = 1 }, 400, 300), "too long ago")
      A.no(L.needWin("Ginkan won: " .. link, nil, "You won: %s", { [link] = 5 }, 10, 300))
    end,
```

`tests/test_stats.lua`:

```lua
    need_rolls_won_in_a_group = function(ns, A, W)
      local link = "|cff1eff00|Hitem:1:|h[Sword]|h|r"
      start(ns, W, function()
        W.env.LOOT_ROLL_YOU_WON = "You won: %s"
        W.env.RollOnLoot = function() end
        W.env.GetLootRollItemLink = function(id) return id == 7 and link or nil end
      end)
      W.state.inGroup = true
      W.env.RollOnLoot(7, 1) -- Need
      W:fire("CHAT_MSG_LOOT", "You won: " .. link)
      A.eq(get(ns, "session", "nj"), 1)
      W.env.RollOnLoot(7, 2) -- Greed
      W:fire("CHAT_MSG_LOOT", "You won: " .. link)
      A.eq(get(ns, "session", "nj"), 1, "Greed doesn't count")
      W.state.inGroup = false
      W.env.RollOnLoot(7, 1)
      W:fire("CHAT_MSG_LOOT", "You won: " .. link)
      A.eq(get(ns, "session", "nj"), 1, "only in a group")
    end,
```

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua need_rolls` → FAIL.

- [ ] **Step 3: Implement**

`TwizCrew/Stats/StatsLogic.lua`, after `L.errorKey`:

```lua
-- A Need roll won? needFmt: the client's own "You (Need - %d) Won: %s" (nil when missing); wonFmt: "You won: %s";
-- needed: { [item link] = when we rolled Need } (the matched link is removed); keep: how long a roll is remembered.
function L.needWin(text, needFmt, wonFmt, needed, now, keep)
  if matchFormat(text, needFmt) then return true end
  local r = matchFormat(text, wonFmt)
  local link = r and r[1]
  if type(link) ~= "string" or type(needed) ~= "table" then return false end
  local at = needed[link]
  needed[link] = nil
  return isNumber(at) and now - at <= keep
end
```

`TwizCrew/Stats/Detectors.lua`, after the `errors` detector:

```lua
-- Need rolls won in a group (Ninja). The roll's type comes from our own RollOnLoot click (1 = Need); a client that
-- says "You (Need - 87) Won: X" itself needs no click.
local NEED_KEEP = 300
local needed = {}
local function inGroup()
  for _, f in ipairs({ IsInGroup, IsInRaid }) do
    local v = call(f)
    if not secret(v) and v then return true end
  end
  return false
end

add({ id = "ninja", label = "Need rolls won",
  needs = function()
    if type(LOOT_ROLL_YOU_WON) ~= "string" and type(LOOT_ROLL_YOU_WON_NO_SPAM_NEED) ~= "string" then
      return false, "LOOT_ROLL_YOU_WON missing"
    end
    return true
  end,
  start = function()
    local d = byId.ninja
    needed = {}
    if fn("RollOnLoot") and fn("hooksecurefunc") then
      hook(d, nil, "RollOnLoot", function(rollID, rollType)
        if secret(rollType) or rollType ~= 1 or not fn("GetLootRollItemLink") then return end
        local link = GetLootRollItemLink(rollID)
        if not secret(link) and type(link) == "string" then needed[link] = ns.now() end
      end)
    end
    onEvent(d, "CHAT_MSG_LOOT", function(text)
      if secret(text) or not inGroup() then return end
      local needFmt = type(LOOT_ROLL_YOU_WON_NO_SPAM_NEED) == "string" and LOOT_ROLL_YOU_WON_NO_SPAM_NEED or nil
      if Logic.needWin(text, needFmt, LOOT_ROLL_YOU_WON, needed, ns.now(), NEED_KEEP) then api.count("nj", 1) end
    end)
  end })
```

Note: when the hook fires outside a group, the link is still remembered for up to 5 minutes; the win only counts
while in a group (the test checks this).

- [ ] **Step 4: Run tests**: pass; add `"ninja"` after `"errors"` in the detector-list test.

- [ ] **Step 5: Commit** (if allowed): `feat(stats): count Need rolls won in a group`

---

### Task 6: Chat and emote detector (Chatterbox, Emote Spammer)

**Files:**
- Modify: `TwizCrew/Stats/Detectors.lua` (detector `chatter`)
- Test: `tests/test_stats.lua`

- [ ] **Step 1: Write the failing test**

```lua
    my_chat_and_emotes_are_counted = function(ns, A, W)
      start(ns, W)
      W:fire("CHAT_MSG_PARTY", "pull?", "Twiz-Realm")
      W:fire("CHAT_MSG_RAID_LEADER", "go", "Twiz")
      W:fire("CHAT_MSG_PARTY", "no", "Ginkan-Realm")
      A.eq(get(ns, "session", "ch"), 2, "only my own messages")
      W:fire("CHAT_MSG_TEXT_EMOTE", "You dance.", "Twiz")
      W:fire("CHAT_MSG_EMOTE", "flexes", "Twiz")
      W:fire("CHAT_MSG_TEXT_EMOTE", "Ginkan laughs.", "Ginkan")
      A.eq(get(ns, "session", "em"), 2)
      A.eq(ns.db.stats.chars.Twiz.s.pull, nil, "the words are never kept")
    end,
```

- [ ] **Step 2: Run to see it fail**: `tools/lua51/lua5.1.exe tests/run.lua my_chat` → FAIL.

- [ ] **Step 3: Implement** (after the `ninja` detector)

```lua
-- My own party / raid / instance chat lines (Chatterbox) and emotes (Emote Spammer): only counted, never kept.
local CHAT_KEYS = {
  CHAT_MSG_PARTY = "ch", CHAT_MSG_PARTY_LEADER = "ch", CHAT_MSG_RAID = "ch", CHAT_MSG_RAID_LEADER = "ch",
  CHAT_MSG_INSTANCE_CHAT = "ch", CHAT_MSG_INSTANCE_CHAT_LEADER = "ch",
  CHAT_MSG_TEXT_EMOTE = "em", CHAT_MSG_EMOTE = "em",
}
add({ id = "chatter", label = "chat lines and emotes",
  needs = function() return true end,
  start = function()
    for event, key in pairs(CHAT_KEYS) do
      onEvent(byId.chatter, event, function(_, sender)
        if secret(sender) or type(sender) ~= "string" then return end
        if ns.shortName(sender) == ns.playerName() then api.count(key, 1) end
      end)
    end
  end })
```

- [ ] **Step 4: Run tests**: pass; add `"chatter"` after `"ninja"` in the detector-list test.

- [ ] **Step 5: Commit** (if allowed): `feat(stats): count my chat lines and emotes`

---

### Task 7: Travel detector (Tourist, Frequent Flyer) and XP detector (Snail)

**Files:**
- Modify: `TwizCrew/Stats/Stats.lua` (`Stats.zone`, api), `TwizCrew/Stats/StatsLogic.lua` (`L.xpGained`),
  `TwizCrew/Stats/Detectors.lua` (detectors `travel`, `xp`)
- Test: `tests/test_statslogic.lua`, `tests/test_stats.lua`

**Interfaces:**
- Consumes: `Store.addZone` (Task 1).
- Produces: `api.zone(name)`; `L.xpGained(prev, cur) -> number` where `prev`/`cur` = `{ level, xp, max }`.

- [ ] **Step 1: Write the failing tests**

`tests/test_statslogic.lua`:

```lua
    xp_gained_across_a_level_up = function(ns, A)
      local L = ns.StatsLogic
      A.eq(L.xpGained({ level = 10, xp = 100, max = 1000 }, { level = 10, xp = 250, max = 1000 }), 150)
      A.eq(L.xpGained({ level = 10, xp = 900, max = 1000 }, { level = 11, xp = 50, max = 1200 }), 150, "the ding")
      A.eq(L.xpGained({ level = 10, xp = 900, max = 1000 }, { level = 10, xp = 100, max = 1000 }), 0, "never minus")
      A.eq(L.xpGained(nil, { level = 10, xp = 1, max = 1000 }), 0, "the first reading")
      A.eq(L.xpGained({ level = 10, xp = 1, max = 1000 }, { level = 13, xp = 1, max = 2000 }), 0, "a jump: unknown")
    end,
```

`tests/test_stats.lua`:

```lua
    zones_flights_and_xp = function(ns, A, W)
      W.state.zone = "Elwynn Forest"
      W.state.level, W.state.xp, W.state.xpMax = 10, 100, 1000
      start(ns, W)
      A.eq(get(ns, "session", "zv"), 1, "where we are counts")
      W.state.zone = "Westfall"
      W:fire("ZONE_CHANGED_NEW_AREA")
      W.state.zone = "Elwynn Forest"
      W:fire("ZONE_CHANGED_NEW_AREA")
      A.eq(get(ns, "session", "zv"), 2)
      W.state.taxi = true
      W:advance(1)
      W:advance(30)
      W.state.taxi = false
      W:advance(1)
      W.state.taxi = true
      W:advance(1)
      A.eq(get(ns, "session", "fp"), 2, "one per flight, not per second")
      W.state.xp = 400
      W:advance(1)
      A.eq(get(ns, "session", "xg"), 300)
      A.ok(get(ns, "session", "xt") > 30, "time below max level")
      W.state.level = ns.maxLevel()
      local xt = get(ns, "session", "xt")
      W:advance(10)
      A.eq(get(ns, "session", "xt"), xt, "max level: no Snail time")
    end,
```

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua "xp_gained|zones_flights"` → FAIL.

- [ ] **Step 3: Implement**

`TwizCrew/Stats/StatsLogic.lua`, after `L.needWin`:

```lua
-- XP gained between two readings { level, xp, max }: the same level, or one ding (the rest of the old level plus
-- the new xp). Anything else (first reading, several levels at once, odd numbers) is 0.
function L.xpGained(prev, cur)
  if type(prev) ~= "table" or type(cur) ~= "table" then return 0 end
  if not (isNumber(prev.level) and isNumber(prev.xp) and isNumber(cur.level) and isNumber(cur.xp)) then return 0 end
  if cur.level == prev.level then return math.max(0, cur.xp - prev.xp) end
  if cur.level == prev.level + 1 and isNumber(prev.max) and prev.max >= prev.xp then
    return (prev.max - prev.xp) + math.max(0, cur.xp)
  end
  return 0
end
```

`TwizCrew/Stats/Stats.lua`, after `Stats.set`:

```lua
-- A zone visited (Tourist): counted once per view.
function Stats.zone(name)
  if not enabled then return end
  if Store.addZone(name) then changed() end
end
```

and add `zone = function(name) Stats.zone(name) end,` to `api`.

`TwizCrew/Stats/Detectors.lua`, after the `chatter` detector:

```lua
-- Zones visited (Tourist) and flights taken (Frequent Flyer: the start of each ride).
local wasTaxi
local function readZone()
  local zone = call(GetRealZoneText)
  if not secret(zone) and type(zone) == "string" and zone ~= "" then api.zone(zone) end
end

add({ id = "travel", label = "zones visited and flights",
  needs = function() local why = missingOf("GetRealZoneText", "UnitOnTaxi"); return why == nil, why end,
  start = function()
    local d = byId.travel
    wasTaxi = player(UnitOnTaxi) and true or false -- logging in mid-flight is not a new flight
    onEvent(d, "ZONE_CHANGED_NEW_AREA", readZone)
    onEvent(d, "PLAYER_ENTERING_WORLD", readZone)
    readZone()
  end,
  tick = function()
    local now = player(UnitOnTaxi) and true or false
    if now and not wasTaxi then api.count("fp", 1) end
    wasTaxi = now
  end })

-- XP gained (Snail) and time played below max level.
local lastXp
local function readXp()
  local level, xp, max = call(UnitLevel, "player"), call(UnitXP, "player"), call(UnitXPMax, "player")
  if secret(level) or secret(xp) or secret(max) then return nil end
  if type(level) ~= "number" or type(xp) ~= "number" then return nil end
  return { level = level, xp = xp, max = type(max) == "number" and max or nil }
end

add({ id = "xp", label = "XP gained",
  needs = function() local why = missingOf("UnitLevel", "UnitXP", "UnitXPMax"); return why == nil, why end,
  start = function() lastXp = readXp() end,
  tick = function(elapsed)
    local cur = readXp()
    if not cur then return end
    local gained = Logic.xpGained(lastXp, cur)
    if gained > 0 then api.count("xg", gained) end
    lastXp = cur
    if cur.level < ns.maxLevel() then api.count("xt", elapsed) end
  end })
```

In `D.stopAll`, also reset: `wasTaxi, lastXp = nil, nil` (add as its own line).

- [ ] **Step 4: Run tests**: pass; add `"travel", "xp"` after `"chatter"` in the detector-list test.

- [ ] **Step 5: Commit** (if allowed): `feat(stats): count zones, flights and XP per hour`

---

### Task 8: Wanderer (running off yourself)

**Files:**
- Modify: `TwizCrew/Find/Find.lua` (`checkRunaways`)
- Modify: `TwizCrew/Stats/Detectors.lua` (detector `wander`)
- Test: `tests/test_find_ui.lua`

**Interfaces:**
- Produces: bus event `RAN_OFF(name, dist)` fired when *I* ran off from group member `name`.

- [ ] **Step 1: Write the failing test** (in `tests/test_find_ui.lua`; helpers `boot`, `group`, `friend`, `hear`
exist; the player starts at world x -9000 = map y 0.5 on map 1429, and map y runs along world x: y 0.57 = x -9140)

```lua
    running_off_yourself_counts_for_wanderer = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1) -- the stats session decides
      group(W)
      friend(ns, W, "Frostie")
      ns.Modules.set("find", "runaway", false) -- counts even with the alarm off
      local ran = {}
      ns.Bus.on("test", "RAN_OFF", function(name) ran[#ran + 1] = name end)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" }) -- 10 yards: right next to us
      W:advance(1.1)
      W.state.map.y = 0.57 -- we walk 140 yards away; Frostie stays
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" })
      W:advance(3)
      A.eq(ran, { "Frostie" })
      A.no(ns.Find.isRunningOff("Frostie"), "no alarm about Frostie: we moved, not them")
      A.eq(ns.StatsStore.get("session", "wd"), 1)
      W:advance(10)
      A.eq(ns.StatsStore.get("session", "wd"), 1, "once, until we're close again")
      A.eq(ns.Log.errors(10), {})
    end,
```

- [ ] **Step 2: Run to see it fail**: `tools/lua51/lua5.1.exe tests/run.lua running_off_yourself` → FAIL.

- [ ] **Step 3: Implement**

In `TwizCrew/Find/Find.lua`, change the `local runTracks, runUntil = {}, {}` line to
`local runTracks, runUntil, selfTracks = {}, {}, {}`, and replace `checkRunaways` with:

```lua
-- Each group member: the alarm when they ran off from us (setting "runaway"), and RAN_OFF when we ran off from
-- them (the same rule with the two positions swapped; the stats count it for Wanderer, alarm setting or not).
local function checkRunaways()
  if not ns.roster then return end
  local me = Where.me()
  if not me then return end
  local c = cfg()
  local opts = { near = c.FIND_RUN_NEAR, far = c.FIND_RUN_FAR, window = c.FIND_RUN_WINDOW }
  local alarmOn = setting("runaway") ~= false
  for _, name in ipairs(ns.roster:names()) do
    local them = Find.positionOf(name)
    if them then
      if alarmOn then
        local track, alarm, dist = Logic.runaway(runTracks[name], me, them, ns.now(), opts)
        runTracks[name] = track
        if alarm then
          runUntil[name] = ns.now() + c.FIND_RUN_ALARM
          ns.Log.add("info", "find: %s is running off (%d yd)", name, math.floor(dist or 0))
          ns.Bus.fire("RUNNING_OFF", name, dist)
          -- no sound (owner, 2026-11-08): the flashing arrow and the pop-up are enough
          if ns.Popups and ns.Popups.runaway then ns.Popups.runaway(name, Logic.distanceText(dist or 0)) end
        end
      else
        runTracks[name] = nil
      end
      local mine, ran, dist = Logic.runaway(selfTracks[name], them, me, ns.now(), opts)
      selfTracks[name] = mine
      if ran then ns.Bus.fire("RAN_OFF", name, dist) end
    else
      runTracks[name], selfTracks[name] = nil, nil
    end
  end
end
```

(Compare with the current function before replacing: keep any line it has that isn't shown here.)

In `TwizCrew/Stats/Detectors.lua`, after the `xp` detector:

```lua
-- Times I ran off from a group member (Wanderer): Find the crew fires RAN_OFF.
add({ id = "wander", label = "running off from the group",
  needs = function() return true end,
  start = function()
    onBus(byId.wander, "RAN_OFF", function(name)
      if ns.isTestName(name) then return end
      api.count("wd", 1)
    end)
  end })
```

- [ ] **Step 4: Run tests**: the new test and the existing running-off tests in `test_find_ui.lua` pass; add
`"wander"` after `"xp"` in the detector-list test in `test_stats.lua`. Full suite: only board failures remain.

- [ ] **Step 5: Commit** (if allowed): `feat(stats): count running off from the group (Wanderer)`

---

### Task 9: Category tabs on the Hall of Shame

**Files:**
- Modify: `TwizCrew/UI/BoardLogic.lua` (`BoardLogic.model`)
- Modify: `TwizCrew/UI/Board.lua` (tab buttons, `Board.setTab`, `Board.tab`)
- Modify: `TwizCrew/Stats/Stats.lua` (default `boardTab = "deaths"`)
- Test: `tests/test_board.lua`

**Interfaces:**
- Consumes: `ns.StatsDefs.TABS`, `def.tab` (Task 2).
- Produces: `BoardLogic.model(view, awardsList, ctx)` reads `ctx.tab` (default `TABS[1].id`) and returns
  `{ subtitle, rows, footer, tabs = { { id, label, active } } }` with rows of that tab only; `Board.setTab(id)`,
  `Board.tab() -> id`.

- [ ] **Step 1: Write the failing tests** (in `tests/test_board.lua`; `model`, `rowById`, `start` exist)

```lua
    tabs_show_one_category_at_a_time = function(ns, A)
      local list = { { name = "Twiz", stats = { dt = 3, gn = 14 } } }
      local m = model(ns, "session", list)
      A.eq(#m.tabs, 5)
      A.eq(m.tabs[1], { id = "deaths", label = "Deaths", active = true })
      A.eq(#m.rows, 6, "Deaths has six awards")
      A.ok(rowById(m, "corpse"))
      A.eq(rowById(m, "pauper"), nil, "Pauper is on another tab")
      A.eq(m.subtitle, "Deaths: session started 9:02 pm by Twiz")
      m = model(ns, "session", list, { tab = "loot" })
      A.ok(m.tabs[3].active)
      A.eq(rowById(m, "pauper").text, "14c")
      A.eq(m.subtitle, "Money & Loot: session started 9:02 pm by Twiz")
      m = model(ns, "all", list, { tab = "nope" })
      A.ok(m.tabs[1].active, "an unknown tab falls back to the first")
      A.eq(m.subtitle, "Deaths: all time")
    end,
    the_tab_is_remembered = function(ns, A, W)
      start(ns, W)
      ns.Board.setTab("oops")
      A.eq(ns.Board.tab(), "oops")
      A.eq(ns.Modules.setting("stats", "boardTab"), "oops")
      ns.Board.setTab("bogus")
      A.eq(ns.Board.tab(), "oops", "unknown tabs are ignored")
    end,
```

Then fix the existing tests broken by tabs (from the Task 2 run): where a test checks
`#m.rows == #ns.StatsDefs.AWARDS`, change the expected value to the number of awards on the tab it shows (6 for the
default Deaths tab); where it looks up a row that is now on another tab (for example `broke`, `trash`, `quitter`,
`furniture`, `medic`), pass `{ tab = "<that award's tab id>" }` as the `extra` argument of `model(...)`. Where a test
checks the subtitle text, prefix the expected text with `"Deaths: "` and lower-case the first letter after it
(`"Session started ..."` becomes `"Deaths: session started ..."`, `"All time"` becomes `"Deaths: all time"`,
`"Waiting for the crew session to start"` becomes `"Deaths: waiting for the crew session to start"`).

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua test_board` → FAIL (`m.tabs` nil).

- [ ] **Step 3: Implement**

`TwizCrew/UI/BoardLogic.lua`: replace `BoardLogic.model` with:

```lua
local function tabOf(id)
  for _, t in ipairs(ns.StatsDefs.TABS) do if t.id == id then return t end end
  return ns.StatsDefs.TABS[1]
end

local function lowerFirst(s) return (s:gsub("^%u", string.lower)) end

-- view: "session" | "all"; awardsList from StatsLogic.awards; ctx = { tab, session, starter, timeText, wipeLine,
-- entries = { [name] = entry }, online = fn(name) -> bool, wall }. Returns { subtitle, rows, footer, tabs }: the
-- rows of the chosen tab only (unknown tab: the first), tabs = { { id, label, active } } in order.
function BoardLogic.model(view, awardsList, ctx)
  ctx = ctx or {}
  local session = view == "session"
  local tab = tabOf(ctx.tab)
  local out = { rows = {}, tabs = {} }
  for _, t in ipairs(ns.StatsDefs.TABS) do
    out.tabs[#out.tabs + 1] = { id = t.id, label = t.label, active = t.id == tab.id }
  end
  local sub
  if not session then
    sub = "All time"
  elseif type(ctx.session) == "table" then
    sub = "Session started " .. text(ctx.timeText) .. " by " .. text(ctx.starter)
  else
    sub = "Waiting for the crew session to start"
  end
  out.subtitle = tab.name .. ": " .. lowerFirst(sub)
  for _, a in ipairs(awardsList or {}) do
    if a.def.tab == tab.id then out.rows[#out.rows + 1] = row(a, ctx) end
  end
  if ctx.wipeLine then
    local n = wipes(ctx)
    if n > 0 then
      out.footer = "Wipe Squad: " .. n .. (n == 1 and " wipe" or " wipes") .. (session and " tonight" or "")
    end
  end
  return out
end
```

`TwizCrew/Stats/Stats.lua`: in the module `defaults`, add `boardTab = "deaths"` (no settings entry: it is only
remembered, not shown in the settings window).

`TwizCrew/UI/Board.lua`:

1. Change `local frame, sessionButton, allButton, subtitle, footer` to
   `local frame, sessionButton, allButton, subtitle, footer, tabButtons`.
2. In `buildModel()`, add `tab = Board.tab(),` to the `ctx` table.
3. In `build(parent)`, after the `allButton` lines, add:

```lua
  tabButtons = {}
  local prev
  for _, t in ipairs(ns.StatsDefs.TABS) do
    local id = t.id
    local b = Board.textButton(frame, t.label, function() Board.setTab(id) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, -(SWITCH_HEIGHT + 2)) end
    tabButtons[#tabButtons + 1] = b
    prev = b
  end
```

4. In `Board.draw`, after `allButton:SetActive(view == "all")` add:

```lua
  for i, t in ipairs(m.tabs) do
    if tabButtons[i] then tabButtons[i]:SetActive(t.active) end
  end
```

   and change `local y = SWITCH_HEIGHT + 2` to `local y = 2 * (SWITCH_HEIGHT + 2)` (the tab row sits under the
   session switch).
5. After `function Board.view() return view end` add:

```lua
local function tabKnown(id)
  for _, t in ipairs(ns.StatsDefs.TABS) do if t.id == id then return true end end
  return false
end

-- The chosen tab (remembered in the stats setting "boardTab").
function Board.tab()
  local id = ns.Modules.setting("stats", "boardTab")
  if tabKnown(id) then return id end
  return ns.StatsDefs.TABS[1].id
end

function Board.setTab(id)
  if not tabKnown(id) then return end
  ns.Modules.set("stats", "boardTab", id)
  if ns.Panel and ns.Panel.refresh then ns.Panel.refresh() end
end
```

6. Update the file's header comment: add "five category tabs under the switch (TABS); only the chosen tab's awards
   are listed" to the first sentence.

- [ ] **Step 4: Run tests**: `tools/lua51/lua5.1.exe tests/run.lua test_board` → PASS; full suite → `ALL PASSED`.

- [ ] **Step 5: Commit** (if allowed): `feat(board): Hall of Shame category tabs`

---

### Task 10: In-game checks and project notes

**Files:**
- Modify: `docs/TESTING.md` (section "Stats, roasts and the awards show")
- Modify: `PROJECT.md` (the Hall of Shame upgrade line)

- [ ] **Step 1: Add the in-game checks** to `docs/TESTING.md`, under the stats section, as a new list headed
"Hall of Shame part 1 (new awards, tabs)", riskiest first:

```markdown
### Hall of Shame part 1 (new awards, tabs)

1. Cast a spell with too little mana (or rage/energy), and one out of range. `/tc report`: the "errors" detector is
   on. The Hall of Shame, Oops tab: Out of Juice and Too Far Away each show 1 (pressing it 5 times fast still 1).
   If not: copy the exact red text into a note for Claude (the game's wording may differ).
2. In a group, roll Need on an item and win it: Money tab, Ninja shows 1 Need roll won. Greed doesn't count.
3. Buy or sell something: Money tab shows your exact gold under Pauper (if you're the poorest) and Money Pit moves
   when you end up with less gold than you started with.
4. Walk 100+ yards away from a group member who stays put: Oops tab, Wanderer shows 1 run-off; your friend's
   screen shows the running-off warning about you (if theirs is on).
5. Say something in party chat and do a /dance: Lazy tab, Chatterbox and Emote Spammer count them.
6. Take a flight path and enter a new zone: Moving tab, Frequent Flyer and Tourist count them.
7. Play 30 minutes below max level: Lazy tab, Snail shows XP per hour (lowest wins).
8. Click each tab: the right awards show, the subtitle starts with the tab's full name, and the tab you picked is
   still picked after /reload.
9. Inside a dungeon: none of the above causes "turned itself off" in chat.
```

- [ ] **Step 2: Update `PROJECT.md`**: change the Hall of Shame upgrade line's ending "Nothing built yet." to
"Part 1 (new awards, tabs) built 2026-11-09, plan `docs/superpowers/plans/2026-11-09-hall-of-shame-part1.md`; not
tried in game yet. Parts 2 and 3 not started."

- [ ] **Step 3: Run the full suite one last time**: `tools/lua51/lua5.1.exe tests/run.lua` → `ALL PASSED`.

- [ ] **Step 4: Commit** (if allowed): `docs: in-game checks for Hall of Shame part 1`
