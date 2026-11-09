# Hall of Shame upgrade, part 2 (stolen crowns, trophy case, streaks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pop-ups when someone takes the lead in an award ("stolen crown"), trophies handed out when a crew session
ends, streaks, a Trophies tab in the Hall of Shame and a trophy line in the Crew tab's tooltips.

**Architecture:** Pure rules in a new `Stats/TrophyLogic.lua` (session record, per-person summary and streaks, wire
form, crown leaders and steals). Glue in two new files: `Stats/Trophies.lua` (records saved in
`db.stats.trophies`, recorded from `Stats` right before a session's numbers are wiped, swapped between copies with
three small messages like the calendar's diary swap) and `Stats/Steals.lua` (watches `STATS_CHANGED`, queues steals,
shows at most one pop-up a minute through `Popups.notice`). The board gets a sixth "Trophies" tab.

**Tech Stack:** Lua 5.1 WoW addon; tests with `tests/run.lua` and the fake game `tests/wowstub.lua`. On Windows run
`tools/lua51/lua5.1.exe tests/run.lua [pattern]`. A full run ends with `ALL PASSED (N tests)` (771 before this plan).

**Spec:** `docs/superpowers/specs/2026-11-09-hall-of-shame-upgrade-design.md`, sections 5 and 6.

## Global Constraints

- Never test a value from the game with `if`, `==`, `<` or math before `issecretvalue` says it isn't secret.
- No message per event. Steals are worked out locally from numbers already shared (`STATS`); no message announces a
  steal. The trophy swap is pull-only: a short digest now and then, a record only when someone asks for it.
- Steal pop-ups: "This session" numbers only; the new holder must be strictly ahead (no shared winner with the old
  holders); none in the first 15 minutes of a session (`STEAL_AFTER = 900` s from the session's start); at most one
  pop-up a minute (`STEAL_GAP = 60`), several together become one ("3 crowns changed hands"); switch under Live
  roasts: "Stolen crown pop-ups" (on by default).
- Trophies: when a session ends (someone starts a new one, or the crew was offline 30 min), each award's winners get
  a trophy. No trophies for a session where nobody played 30 minutes (`ns.Config.COUCH_MIN_PLAYED`, compared with the
  largest session `pt`) or with fewer than 2 people. Kept forever.
- A streak counts the sessions that person took part in (a missed night doesn't break it).
- Fake crew members from the test tools (`ns.isTestName`) never get trophies, never steal, are never sent.
- Plain words in everything a player reads.
- New files go in `TwizCrew.toc`; the release that ships them must set `RESTART_SINCE` to its version
  (`TwizCrew/Core/Init.lua`).
- Commit after each task; messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions made while planning (Claude's call)

- **The ended session** is the one my own numbers belong to (`StatsStore.mine().sid`) when `SESSION_CHANGED` moves
  me to another session without keeping counts (`keep == false`). That covers "/tc session new", a friend's new
  session, and logging in after 30 minutes away (where `old` is nil). Merging two automatic sessions (`keep ==
  true`) is not an end.
- **Recording happens inside `Stats` `onSession`, before `Store.setSession`** wipes the session numbers.
- **The swap only offers the 10 newest sessions** (`DIGEST_SIZE`): a friend who missed more than 10 sessions in a
  row doesn't get the older ones. Messages: `TRD` digest (`r` = up to 10 session ids, comma-separated), `TRQ` ask
  (`s` = one session id), `TRP` one record (`s` id, `t` start, `p` people, `k` number of award fields, then one
  `w_<awardId>` field per award with a winner = winner names comma-separated). Pieces of a `TRP` are merged per
  sender and session id until all `k` award fields and `p` have arrived. The first complete record for a session id
  is kept; later ones are ignored.
- **Steals compare winner sets.** For each award: old winners (last check) and new winners; a steal when both are
  non-empty and share nobody. The pop-up text uses the first thief and first victim (ties: "Twiz & Ginkan").
- **Trophies tab** is not an award tab: it is added by the board after the five `StatsDefs.TABS` (label
  "Trophies"); the This session / All time switch doesn't change it.
- **Tooltip line** on the Crew tab: "12 trophies" plus " · <award> streak x3" for that person's longest current
  streak of 2 or more. Nothing for someone with no trophies.

## File map

- Create `TwizCrew/Stats/TrophyLogic.lua` (pure rules) — Task 1, 3.
- Create `TwizCrew/Stats/Trophies.lua` (records, swap, summary for the UI) — Task 2.
- Create `TwizCrew/Stats/Steals.lua` (steal pop-ups) — Task 3.
- Modify `TwizCrew/TwizCrew.toc` (three new files after `Stats\Stats.lua`, in the order TrophyLogic, Trophies,
  Steals) — Task 1 adds TrophyLogic, Task 2 Trophies, Task 3 Steals.
- Modify `TwizCrew/Stats/Stats.lua` (`onSession` calls `ns.Trophies.sessionEnded`) — Task 2.
- Modify `TwizCrew/Stats/Roasts.lua` (setting `stealPopups`) — Task 3.
- Modify `TwizCrew/UI/BoardLogic.lua`, `TwizCrew/UI/Board.lua` (Trophies tab), `TwizCrew/UI/Panel.lua` (tooltip
  line) — Task 4.
- Tests: new `tests/test_trophies.lua` (logic + glue + steals), `tests/test_board.lua`.
- Docs: `docs/TESTING.md`, `PROJECT.md` — Task 5.

Check how test files are discovered (`tests/run.lua`) and copy the structure of an existing full-boot test file
(`tests/test_stats_share.lua`: `files = "toc"`, `boot`, `receive`) for `tests/test_trophies.lua`.

---

### Task 1: Trophy rules (pure)

**Files:**
- Create: `TwizCrew/Stats/TrophyLogic.lua`
- Modify: `TwizCrew/TwizCrew.toc` (add `Stats\TrophyLogic.lua` right after `Stats\Stats.lua`)
- Test: `tests/test_trophies.lua` (new)

**Interfaces:**
- Produces `ns.TrophyLogic`:
  - `L.record(sid, entries, awardsList, minPlayed) -> record | nil` — `entries` from `StatsStore.entries("session",
    sid)`, `awardsList` from `StatsLogic.awards(entries)`. Record = `{ sid, start, people = { names sorted },
    winners = { [awardId] = { names sorted } } }`; nil when fewer than 2 people or nobody's `pt` reaches `minPlayed`.
    Test names (`ns.isTestName`) are left out everywhere.
  - `L.summary(records) -> { [name] = { total, counts = { [awardId] = n }, streaks = { [awardId] = n } } }` — streak
    = the number of that person's own sessions (newest first, by `start`) in a row in which they won that award; only
    current streaks (from their newest session).
  - `L.toWire(record) -> fields`, `L.fromPieces(fields) -> record | nil` (nil until complete or when broken).

- [ ] **Step 1: Write the failing tests** — create `tests/test_trophies.lua`:

```lua
-- Trophy case, streaks and stolen crowns (Hall of Shame part 2).

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function entry(name, stats) return { name = name, stats = stats } end

return {
  files = "toc",
  tests = {
    a_record_needs_two_people_and_thirty_minutes = function(ns, A)
      local L, S = ns.TrophyLogic, ns.StatsLogic
      local list = { entry("Twiz", { dt = 5, pt = 1900 }), entry("Lurabe", { dt = 2, pt = 600 }),
        entry("Fake (test)", { dt = 50, pt = 5000 }) }
      local r = L.record("Twiz-1000", list, S.awards(list), 1800)
      A.eq(r.sid, "Twiz-1000")
      A.eq(r.start, 1000)
      A.eq(r.people, { "Lurabe", "Twiz" }, "fakes never count")
      A.eq(r.winners.corpse, { "Twiz" })
      A.eq(L.record("Twiz-1000", { list[1] }, S.awards({ list[1] }), 1800), nil, "one person: no trophies")
      local short = { entry("Twiz", { dt = 5, pt = 100 }), entry("Lurabe", { dt = 2, pt = 600 }) }
      A.eq(L.record("Twiz-1000", short, S.awards(short), 1800), nil, "nobody played 30 minutes")
    end,
    summary_counts_and_streaks = function(ns, A)
      local L = ns.TrophyLogic
      local recs = {
        { sid = "a", start = 1, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz" } } },
        { sid = "b", start = 2, people = { "Lurabe" }, winners = { corpse = { "Lurabe" } } }, -- Twiz missed it
        { sid = "c", start = 3, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz" }, bunny = { "Lurabe" } } },
        { sid = "d", start = 4, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz", "Lurabe" } } },
      }
      local s = L.summary(recs)
      A.eq(s.Twiz.total, 3)
      A.eq(s.Twiz.counts.corpse, 3)
      A.eq(s.Twiz.streaks.corpse, 3, "a missed night doesn't break it")
      A.eq(s.Lurabe.counts, { corpse = 2, bunny = 1 })
      A.eq(s.Lurabe.streaks.corpse, 1, "won d, not c")
      A.eq(s.Lurabe.streaks.bunny, nil, "not won in their newest session")
    end,
    records_travel_in_pieces = function(ns, A)
      local L = ns.TrophyLogic
      local r = { sid = "Twiz-1000", start = 1000, people = { "Lurabe", "Twiz" },
        winners = { corpse = { "Twiz" }, bunny = { "Lurabe", "Twiz" } } }
      local f = L.toWire(r)
      A.eq(f.s, "Twiz-1000")
      A.eq(f.k, "2")
      A.eq(f.w_bunny, "Lurabe,Twiz")
      A.eq(L.fromPieces(f), r)
      local part = { s = f.s, t = f.t, p = f.p, k = f.k, w_corpse = f.w_corpse }
      A.eq(L.fromPieces(part), nil, "one award field still missing")
      A.eq(L.fromPieces({ s = "", k = "0", p = "" }), nil)
    end,
  },
}
```

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua test_trophies` → FAIL
  (`ns.TrophyLogic` is nil).

- [ ] **Step 3: Implement** — create `TwizCrew/Stats/TrophyLogic.lua`:

```lua
-- Trophy case and stolen crowns: pure rules (no game calls). A session record is
-- { sid, start, people = { names }, winners = { [awardId] = { names } } }: who was in the session and who won what.
local _, ns = ...

local L = {}
ns.TrophyLogic = L

local function isNumber(v) return type(v) == "number" and v == v end

local function real(name) return type(name) == "string" and name ~= "" and not ns.isTestName(name) end

local function sorted(set)
  local out = {}
  for name in pairs(set) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- The record of a session that just ended, or nil (fewer than 2 people, or nobody played minPlayed seconds).
function L.record(sid, entries, awardsList, minPlayed)
  if type(sid) ~= "string" or sid == "" then return nil end
  local people, longest = {}, 0
  for _, e in ipairs(entries or {}) do
    if real(e.name) then
      people[e.name] = true
      local pt = type(e.stats) == "table" and e.stats.pt
      if isNumber(pt) and pt > longest then longest = pt end
    end
  end
  local names = sorted(people)
  if #names < 2 or longest < (minPlayed or 0) then return nil end
  local winners = {}
  for _, a in ipairs(awardsList or {}) do
    if not a.empty then
      local set = {}
      for _, name in ipairs(a.winners) do if people[name] then set[name] = true end end
      local list = sorted(set)
      if #list > 0 then winners[a.def.id] = list end
    end
  end
  return { sid = sid, start = tonumber(sid:match("%-(%d+)$")) or 0, people = names, winners = winners }
end

local function has(list, name)
  for _, n in ipairs(list or {}) do if n == name then return true end end
  return false
end

-- Per person: total trophies, trophies per award, and current streaks (their own sessions, newest first).
function L.summary(records)
  local list = {}
  for _, r in pairs(records or {}) do if type(r) == "table" then list[#list + 1] = r end end
  table.sort(list, function(a, b)
    if (a.start or 0) ~= (b.start or 0) then return (a.start or 0) > (b.start or 0) end
    return tostring(a.sid) > tostring(b.sid)
  end)
  local out = {}
  local function person(name)
    local p = out[name]
    if not p then p = { total = 0, counts = {}, streaks = {} }; out[name] = p end
    return p
  end
  for _, r in ipairs(list) do
    for id, names in pairs(r.winners or {}) do
      for _, name in ipairs(names) do
        local p = person(name)
        p.total = p.total + 1
        p.counts[id] = (p.counts[id] or 0) + 1
      end
    end
  end
  -- streaks: walk each person's sessions newest first; a streak lives while they keep winning it
  for name, p in pairs(out) do
    local alive = nil -- award ids still going; nil until their newest session
    for _, r in ipairs(list) do
      if has(r.people, name) then
        if alive == nil then
          alive = {}
          for id, names in pairs(r.winners or {}) do
            if has(names, name) then alive[id] = true; p.streaks[id] = 1 end
          end
        else
          for id in pairs(alive) do
            if has(r.winners and r.winners[id], name) then p.streaks[id] = p.streaks[id] + 1 else alive[id] = nil end
          end
        end
        if alive and next(alive) == nil then break end
      end
    end
  end
  return out
end

-- Wire form of a record (TRP): s, t, p, k = number of w_ fields, w_<awardId> = names.
function L.toWire(r)
  local f = { s = r.sid, t = tostring(r.start or 0), p = table.concat(r.people or {}, ",") }
  local k = 0
  for id, names in pairs(r.winners or {}) do
    f["w_" .. id] = table.concat(names, ",")
    k = k + 1
  end
  f.k = tostring(k)
  return f
end

local function split(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for name in s:gmatch("[^,]+") do
    name = ns.Util.truncateUTF8(ns.Util.safeText(name), 24)
    if real(name) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- A record from merged TRP pieces, or nil while incomplete (fewer w_ fields than k, or no p) or broken.
function L.fromPieces(f)
  if type(f) ~= "table" or type(f.s) ~= "string" or f.s == "" or #f.s > 64 then return nil end
  local k = tonumber(f.k)
  if not k or k < 0 or type(f.p) ~= "string" then return nil end
  local winners, n = {}, 0
  for key, v in pairs(f) do
    local id = type(key) == "string" and key:match("^w_(%w+)$")
    if id then
      local names = split(v)
      if #names > 0 then winners[id] = names end
      n = n + 1
    end
  end
  if n < k then return nil end
  local people = split(f.p)
  if #people < 2 then return nil end
  return { sid = f.s, start = tonumber(f.t) or 0, people = people, winners = winners }
end
```

Note: `ns.Util.truncateUTF8` and `ns.Util.safeText` exist (used by `Calendar/Diary.lua`). Add
`Stats\TrophyLogic.lua` to `TwizCrew/TwizCrew.toc` on the line after `Stats\Stats.lua`.

- [ ] **Step 4: Run**: `tools/lua51/lua5.1.exe tests/run.lua test_trophies` → PASS; full suite → ALL PASSED.
  (If `test_lint.lua` checks the TOC against files on disk, it passes once the file is listed.)

- [ ] **Step 5: Commit**: `feat(trophies): session records, streaks and wire form (pure rules)`

---

### Task 2: Trophies saved, recorded at session end, swapped between copies

**Files:**
- Create: `TwizCrew/Stats/Trophies.lua`
- Modify: `TwizCrew/TwizCrew.toc` (add `Stats\Trophies.lua` after `Stats\TrophyLogic.lua`)
- Modify: `TwizCrew/Stats/Stats.lua` (`onSession`)
- Test: `tests/test_trophies.lua`

**Interfaces:**
- Consumes: `TrophyLogic.record`, `summary`, `toWire`, `fromPieces`; `StatsStore.mine()`, `StatsStore.entries`;
  `StatsLogic.awards`.
- Produces `ns.Trophies`:
  - `Trophies.sessionEnded(sid)` — records the session (if it qualifies and isn't known yet).
  - `Trophies.records() -> { [sid] = record }` (the saved table; read only).
  - `Trophies.summary() -> TrophyLogic.summary(records)` (cached until a record is added).
  - `Trophies.lineFor(name) -> string | nil` — "12 trophies" (+ " · <award name> streak x<n>" for the longest
    current streak >= 2; ties: the award earlier in `StatsDefs.AWARDS`).
  - `Trophies.sendDigest(to)` (nil = everyone).
  - Bus event `TROPHIES_CHANGED` when a record is added.

- [ ] **Step 1: Write the failing tests** (add to `tests/test_trophies.lua` `tests`):

```lua
    a_session_that_ends_hands_out_trophies = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      W:advance(1900) -- I play 31 minutes
      ns.Stats.count("dt", 3)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "1", s_pt = "1900" })
      A.eq(next(ns.Trophies.records()), nil, "nothing until the session ends")
      ns.Session.newByHand()
      local r = ns.Trophies.records()[sid]
      A.ok(r, "recorded when the session ended")
      A.eq(r.winners.corpse, { "Twiz" })
      A.eq(r.people, { "Lurabe", "Twiz" })
      A.eq(ns.Trophies.summary().Twiz.counts.corpse, 1)
      A.eq(ns.Trophies.lineFor("Twiz"), "1 trophy", "singular, no streak line for a single win")
      A.eq(ns.Trophies.lineFor("Nobody"), nil)
      A.eq(ns.Log.errors(10), {})
    end,
    a_short_session_hands_out_nothing = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      ns.Stats.count("dt", 3)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "1", s_pt = "60" })
      ns.Session.newByHand()
      A.eq(ns.Trophies.records()[sid], nil)
    end,
    a_friend_who_missed_it_gets_the_record = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local r = { sid = "Lurabe-500", start = 500, people = { "Lurabe", "Twiz" }, winners = { bunny = { "Twiz" } } }
      local mark = #W.sent
      receive(W, ns, "Lurabe", "TRD", { r = "Lurabe-500" })
      local asked
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "TRQ" then asked = msg.fields.s end
      end
      A.eq(asked, "Lurabe-500", "we ask for the one we don't have")
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire(r))
      A.eq(ns.Trophies.records()["Lurabe-500"], r)
      -- asked by someone else: we answer with our copy
      mark = #W.sent
      receive(W, ns, "Lurabe", "TRQ", { s = "Lurabe-500" })
      W:advance(3)
      local sentRecord = false
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "TRP" and msg.fields.s == "Lurabe-500" then sentRecord = true end
      end
      A.ok(sentRecord)
      -- a second, different record for the same session is ignored
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire({ sid = "Lurabe-500", start = 500,
        people = { "Lurabe", "Twiz" }, winners = { bunny = { "Lurabe" } } }))
      A.eq(ns.Trophies.records()["Lurabe-500"].winners.bunny, { "Twiz" }, "the first one is kept")
    end,
```

(Adapt the friend introduction to whatever the existing tests use so that `Lurabe` counts as a known crew member
for the message handlers — see `tests/test_stats_share.lua` / `tests/test_calendar.lua`; the `TRD`/`TRQ`/`TRP`
handlers should ignore unknown senders, test names and myself, like the calendar's `known(sender)`.)

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua test_trophies` → FAIL.

- [ ] **Step 3: Implement**

Create `TwizCrew/Stats/Trophies.lua`:

```lua
-- Trophy case (Hall of Shame part 2): when a crew session ends, each award's winners get a trophy. Records live in
-- db.stats.trophies[sid] (kept forever) and are swapped pull-only, like the calendar's diaries:
--   TRD  digest: r = the DIGEST_SIZE newest session ids I have (to everyone now and then, and to a friend coming online)
--   TRQ  "send me session s" (to one friend whose digest has a session I lack)
--   TRP  one session's record (TrophyLogic.toWire), in pieces merged per sender and session until complete
-- Runs under the feature id "trophies" (not a module): it follows the stats module (no records while it is off).
local _, ns = ...

local Trophies = {}
ns.Trophies = Trophies

local FEATURE = "trophies"
local L = ns.TrophyLogic

local DIGEST_SIZE = 10
local DIGEST_EVERY = 600 -- seconds between digests to everyone
local FIRST_DIGEST = 25  -- after login
local ASK_GAP = 120      -- seconds before asking for the same session again
local SEND_GAP = 30      -- seconds before sending the same record to the same friend again
local PIECE_LIFE = 60    -- seconds an incomplete record waits for its other pieces

local askedAt, sentAt, pending = {}, {}, {}
local cache
local started = false

local function store()
  if not ns.db then return nil end
  if type(ns.db.stats) ~= "table" then ns.db.stats = {} end
  if type(ns.db.stats.trophies) ~= "table" then ns.db.stats.trophies = {} end
  return ns.db.stats.trophies
end

local function on() return ns.Modules.isEnabled("stats") end

function Trophies.records() return store() or {} end

local function add(r)
  local t = store()
  if not t or type(r) ~= "table" or t[r.sid] ~= nil then return false end
  t[r.sid] = r
  cache = nil
  ns.Log.add("info", "trophies: session %s recorded (%d people)", r.sid, #r.people)
  ns.Bus.fire("TROPHIES_CHANGED", r.sid)
  return true
end

-- A session just ended (called by Stats before the session numbers are wiped).
function Trophies.sessionEnded(sid)
  if not on() or type(sid) ~= "string" or sid == "" or Trophies.records()[sid] then return end
  local entries = ns.StatsStore.entries("session", sid)
  local r = L.record(sid, entries, ns.StatsLogic.awards(entries), ns.Config.COUCH_MIN_PLAYED)
  if r then add(r) end
end

function Trophies.summary()
  if not cache then cache = L.summary(Trophies.records()) end
  return cache
end

local function awardName(id)
  for _, d in ipairs(ns.StatsDefs.AWARDS) do if d.id == id then return d.name end end
  return id
end

-- "12 trophies · Professional Corpse streak x3" for the Crew tab's tooltip; nil without trophies.
function Trophies.lineFor(name)
  local p = Trophies.summary()[name]
  if not p or p.total <= 0 then return nil end
  local line = p.total .. (p.total == 1 and " trophy" or " trophies")
  local best, bestN = nil, 1
  for _, d in ipairs(ns.StatsDefs.AWARDS) do
    local n = p.streaks[d.id]
    if n and n > bestN then best, bestN = d.id, n end
  end
  if best then line = line .. " · " .. awardName(best) .. " streak x" .. bestN end
  return line
end

---------------------------------------------------------------------------------------------------------- swap
local function newest()
  local list = {}
  for sid, r in pairs(Trophies.records()) do list[#list + 1] = { sid = sid, start = tonumber(r.start) or 0 } end
  table.sort(list, function(a, b)
    if a.start ~= b.start then return a.start > b.start end
    return a.sid > b.sid
  end)
  local out = {}
  for i = 1, math.min(DIGEST_SIZE, #list) do out[i] = list[i].sid end
  return out
end

local function sendTo(name, msgType, fields, opts)
  if name then
    if not ns.Comm.sendTo(name, msgType, fields, opts) then ns.Comm.send(msgType, fields, opts) end
  else
    ns.Comm.send(msgType, fields, opts)
  end
end

function Trophies.sendDigest(to)
  if not on() then return end
  local ids = newest()
  if #ids == 0 then return end
  sendTo(to, "TRD", { r = table.concat(ids, ",") })
end

local function known(sender)
  return type(sender) == "string" and not ns.isMe(sender) and not ns.isTestName(sender) and ns.roster
    and ns.roster:get(sender) ~= nil
end

local function onDigest(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.r) ~= "string" then return end
  local mine = Trophies.records()
  local count = 0
  for sid in f.r:gmatch("[^,]+") do
    count = count + 1
    if count > DIGEST_SIZE then break end
    if not mine[sid] and (not askedAt[sid] or ns.now() - askedAt[sid] >= ASK_GAP) then
      askedAt[sid] = ns.now()
      sendTo(sender, "TRQ", { s = sid })
    end
  end
end

local function onAsk(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.s) ~= "string" then return end
  local r = Trophies.records()[f.s]
  if not r then return end
  local key = f.s .. ">" .. sender
  if sentAt[key] and ns.now() - sentAt[key] < SEND_GAP then return end
  sentAt[key] = ns.now()
  sendTo(sender, "TRP", L.toWire(r), { repeatKeys = { "s", "k" } })
end

local function onRecord(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.s) ~= "string" then return end
  if Trophies.records()[f.s] then return end
  local key = sender .. ">" .. f.s
  local p = pending[key]
  if not p or ns.now() - p.at > PIECE_LIFE then p = { at = ns.now(), fields = {} }; pending[key] = p end
  for k, v in pairs(f) do p.fields[k] = v end
  local r = L.fromPieces(p.fields)
  if r then
    pending[key] = nil
    add(r)
  end
end

ns.Comm.on("TRD", function(s, f) ns.Log.safe(FEATURE, onDigest, s, f) end)
ns.Comm.on("TRQ", function(s, f) ns.Log.safe(FEATURE, onAsk, s, f) end)
ns.Comm.on("TRP", function(s, f) ns.Log.safe(FEATURE, onRecord, s, f) end)

-- Started by the stats module (onEnable); the timers do nothing while stats are off.
function Trophies.start()
  if started then return end
  started = true
  C_Timer.After(FIRST_DIGEST, function() ns.Log.safe(FEATURE, Trophies.sendDigest) end)
  C_Timer.NewTicker(DIGEST_EVERY, function() ns.Log.safe(FEATURE, Trophies.sendDigest) end)
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", function(name)
    if ns.isTestName(name) then return end
    C_Timer.After(5, function() ns.Log.safe(FEATURE, Trophies.sendDigest, name) end)
  end)
end
```

Before using them, confirm `ns.isMe`, `ns.Comm.sendTo` and the `repeatKeys` option exist exactly as used (they are
used by `TwizCrew/Calendar/Diary.lua`). If `ns.roster:get(sender)` needs the short name, use the same form the
calendar uses.

In `TwizCrew/Stats/Stats.lua` `onSession`, before `Store.setSession(...)`, add:

```lua
  -- the session my numbers belong to has ended (a new one, counts not kept): hand out its trophies first
  local mine = Store.mine()
  if not keep and mine and mine.sid ~= "" and mine.sid ~= new.id and ns.Trophies then
    ns.Log.safe("trophies", ns.Trophies.sessionEnded, mine.sid)
  end
```

and at the end of the module's `onEnable`, add `if ns.Trophies then ns.Trophies.start() end`.

Add `Stats\Trophies.lua` to the TOC after `Stats\TrophyLogic.lua` (both before any UI file).

- [ ] **Step 4: Run**: `test_trophies` → PASS; full suite → ALL PASSED. If a test that counts messages sent after
  login now sees an extra `TRD`, that test is fine to adjust only if the digest is legitimately sent (it is not sent
  when there are no records, so most tests are unaffected).

- [ ] **Step 5: Commit**: `feat(trophies): hand out trophies when a session ends; swap missed sessions`

---

### Task 3: Stolen crown pop-ups

**Files:**
- Modify: `TwizCrew/Stats/TrophyLogic.lua` (`L.leaders`, `L.steals`)
- Create: `TwizCrew/Stats/Steals.lua`
- Modify: `TwizCrew/TwizCrew.toc` (add `Stats\Steals.lua` after `Stats\Trophies.lua`)
- Modify: `TwizCrew/Stats/Roasts.lua` (setting)
- Test: `tests/test_trophies.lua`

**Interfaces:**
- Produces: `L.leaders(awardsList) -> { [awardId] = { names } }`; `L.steals(old, awardsList, valueOf) -> list of
  { def, thieves, victims, thiefText, victimText }` where `valueOf(def, name) -> text`; `ns.Steals.check()` (for
  tests), `ns.Steals.flush()`.

- [ ] **Step 1: Write the failing tests**:

```lua
    steals_need_new_leaders_who_share_nobody = function(ns, A)
      local L, S = ns.TrophyLogic, ns.StatsLogic
      local before = { entry("Twiz", { dt = 7 }), entry("Lurabe", { dt = 8 }) }
      local old = L.leaders(S.awards(before))
      A.eq(old.corpse, { "Lurabe" })
      local after = { entry("Twiz", { dt = 9 }), entry("Lurabe", { dt = 8 }) }
      local list = S.awards(after)
      local st = L.steals(old, list, function(def, name) return name == "Twiz" and "9 deaths" or "8 deaths" end)
      A.eq(#st, 1)
      A.eq(st[1].def.id, "corpse")
      A.eq(st[1].thieves, { "Twiz" })
      A.eq(st[1].victims, { "Lurabe" })
      A.eq(st[1].thiefText, "9 deaths")
      A.eq(st[1].victimText, "8 deaths")
      local tie = { entry("Twiz", { dt = 8 }), entry("Lurabe", { dt = 8 }) }
      A.eq(#L.steals(old, S.awards(tie), function() return "" end), 0, "a tie is not a steal")
      A.eq(#L.steals({}, list, function() return "" end), 0, "nobody held it before")
    end,
    stolen_crown_pop_ups = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "2" })
      ns.Steals.check()
      ns.Stats.count("dt", 3) -- I take Professional Corpse, but the session is young
      ns.Steals.check()
      ns.Steals.flush()
      A.eq(ns.Steals.lastShown(), nil, "not in the first 15 minutes")
      W:advance(901)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "2", s_dt = "5" })
      ns.Steals.check()
      ns.Steals.flush()
      A.eq(ns.Steals.lastShown(), "Lurabe just stole Professional Corpse from Twiz!")
      -- two at once inside a minute: one pop-up for both
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "3", s_dt = "5", s_jp = "50" })
      ns.Stats.count("jp", 60)
      ns.Stats.count("dt", 4) -- 7 deaths: back to me
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.contains(ns.Steals.lastShown(), "crowns changed hands")
      -- switched off
      ns.Modules.set("roasts", "stealPopups", false)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "4", s_dt = "20", s_jp = "50" })
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.contains(ns.Steals.lastShown(), "crowns changed hands", "nothing new while off")
      A.eq(ns.Log.errors(10), {})
    end,
```

(`ns.Steals.lastShown()` returns the title of the last steal pop-up shown, or nil.)

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua "steals_need|stolen_crown"` → FAIL.

- [ ] **Step 3: Implement**

Add to `TwizCrew/Stats/TrophyLogic.lua`:

```lua
-- Stolen crowns: who leads each award now ({ [awardId] = { names } }, only awards with a winner).
function L.leaders(awardsList)
  local out = {}
  for _, a in ipairs(awardsList or {}) do
    if not a.empty then
      local list = {}
      for _, name in ipairs(a.winners) do if real(name) then list[#list + 1] = name end end
      if #list > 0 then out[a.def.id] = list end
    end
  end
  return out
end

-- Steals between the old leaders and the awards now: the new winners share nobody with the old ones.
-- valueOf(def, name) -> the person's number as text ("8 deaths").
function L.steals(old, awardsList, valueOf)
  local out = {}
  local now = L.leaders(awardsList)
  for _, a in ipairs(awardsList or {}) do
    local id = a.def.id
    local before, after = old and old[id], now[id]
    if before and after and #before > 0 then
      local shared = false
      for _, name in ipairs(after) do if has(before, name) then shared = true end end
      if not shared then
        out[#out + 1] = { def = a.def, thieves = after, victims = before,
          thiefText = valueOf(a.def, after[1]) or "", victimText = valueOf(a.def, before[1]) or "" }
      end
    end
  end
  return out
end
```

(`has` and `real` are the local helpers already in the file; keep these functions below them.)

Create `TwizCrew/Stats/Steals.lua`:

```lua
-- Stolen crown pop-ups (Hall of Shame part 2): when someone takes the lead in an award this session, a pop-up says
-- so. Worked out from the numbers every copy already has (no message of its own). Not in the first STEAL_AFTER s of
-- a session; at most one pop-up every STEAL_GAP s (several steals together share one). Switch: Live roasts,
-- "Stolen crown pop-ups". Click: the Hall of Shame at that award's tab. Feature id "steals" (not a module).
local _, ns = ...

local Steals = {}
ns.Steals = Steals

local FEATURE = "steals"
local L = ns.TrophyLogic
local STEAL_AFTER, STEAL_GAP = 900, 60

local leaders, leadersSid -- the last check's leaders and the session they belong to
local queue = {}
local lastPopup, lastTitle

local function names(list) return table.concat(list, " & ") end

local function wanted()
  return ns.Modules.isEnabled("roasts") and ns.Modules.setting("roasts", "stealPopups") ~= false
end

local function openAt(def)
  if ns.Commands and ns.Commands.setPanel and not ns.Modules.isEnabled("panel") then ns.Commands.setPanel(true, true) end
  if ns.Board and ns.Board.setTab then ns.Board.setTab(def.tab) end
  if ns.Panel and ns.Panel.setTab then ns.Panel.setTab("shame") end
end

-- Compares the session's leaders with the last check; queues steals once the session is old enough.
function Steals.check()
  local session = ns.Session and ns.Session.current()
  if not session then return end
  local entries = ns.StatsStore.entries("session", session.id)
  local list = ns.StatsLogic.awards(entries)
  local byName = {}
  for _, e in ipairs(entries) do byName[e.name] = e end
  if leadersSid == session.id and ns.wallclock() - (session.start or 0) >= STEAL_AFTER then
    local found = L.steals(leaders, list, function(def, name)
      local e = byName[name]
      local v = e and ns.StatsLogic.awardValue(def, e.stats)
      return v and ns.StatsLogic.valueText(def, v, e.stats) or ""
    end)
    for _, s in ipairs(found) do queue[#queue + 1] = s end
  end
  leaders, leadersSid = L.leaders(list), session.id
end

-- Shows what's queued: one steal, or one pop-up for several. At most once every STEAL_GAP s.
function Steals.flush()
  if #queue == 0 then return end
  if lastPopup and ns.now() - lastPopup < STEAL_GAP then return end
  local list = queue
  queue = {}
  if not wanted() or not ns.Popups or not ns.Popups.notice then return end
  lastPopup = ns.now()
  local first = list[1]
  local title, sub
  if #list == 1 then
    title = names(first.thieves) .. " just stole " .. first.def.name .. " from " .. names(first.victims) .. "!"
    sub = "(" .. first.thiefText .. " vs " .. first.victimText .. ")  -  click to see"
  else
    title = #list .. " crowns changed hands"
    local parts = {}
    for _, s in ipairs(list) do parts[#parts + 1] = s.def.name .. ": " .. names(s.thieves) end
    sub = table.concat(parts, ", ")
  end
  lastTitle = title
  ns.Popups.notice(first.def.icon, title, sub, function() openAt(first.def) end)
end

function Steals.lastShown() return lastTitle end

ns.Bus.on(FEATURE, "STATS_CHANGED", function() ns.Log.safe(FEATURE, Steals.check) end)
ns.Bus.on(FEATURE, "SESSION_CHANGED", function() leaders, leadersSid, queue = nil, nil, {} end)
C_Timer.NewTicker(5, function() ns.Log.safe(FEATURE, Steals.flush) end)
```

Notes for the implementer:
- `StatsLogic.awardValue` is currently a local function (`local function awardValue(def, stats)`); expose it as
  `L.awardValue = awardValue` right after its definition in `TwizCrew/Stats/StatsLogic.lua` (keep the local).
- `C_Timer.NewTicker` at file load: check whether other files create tickers at load time; if the fake game or the
  real client needs it after login, start the ticker from the bus event `ADDON_READY`/the stats module's `onEnable`
  instead (follow the pattern in `Trophies.start`). The flush ticker must not run test-visible pop-ups during other
  tests: it only shows something when steals were queued.
- `ns.Commands.setPanel(true, true)` is how the minimap button shows the panel.

In `TwizCrew/Stats/Roasts.lua`, after the `cheers` setting is added (before `mockModel`), add:

```lua
settings[#settings + 1] = { key = "stealPopups", label = "Stolen crown pop-ups", kind = "toggle",
  info = "A pop-up when someone takes the lead in a Hall of Shame award this session, like \"Twiz just stole "
    .. "Professional Corpse from Lurabe!\". Not in the first 15 minutes of a session, and at most one a minute." }
```

and add `stealPopups = true` to the `defaults` table at the top of that block.

- [ ] **Step 4: Run**: the two tests pass; full suite ALL PASSED.

- [ ] **Step 5: Commit**: `feat(trophies): stolen crown pop-ups`

---

### Task 4: Trophies tab and the Crew tooltip line

**Files:**
- Modify: `TwizCrew/UI/BoardLogic.lua`, `TwizCrew/UI/Board.lua`, `TwizCrew/UI/Panel.lua`
- Test: `tests/test_board.lua`, `tests/test_trophies.lua`

**Interfaces:**
- Consumes: `Trophies.summary()`, `Trophies.lineFor(name)`, bus `TROPHIES_CHANGED`.
- Produces: `BoardLogic.TROPHY_TAB = { id = "trophies", label = "Trophies", name = "Trophies" }`; with
  `ctx.tab == "trophies"`, `BoardLogic.model` returns rows from `ctx.trophies` (a summary) instead of awards.

- [ ] **Step 1: Write the failing tests**

`tests/test_board.lua` (uses the file's `model` helper):

```lua
    the_trophies_tab = function(ns, A)
      local summary = {
        Twiz = { total = 7, counts = { corpse = 6, bunny = 1 }, streaks = { corpse = 3 } },
        Lurabe = { total = 2, counts = { fish = 2 }, streaks = {} },
      }
      local m = model(ns, "session", {}, { tab = "trophies", trophies = summary })
      A.eq(#m.tabs, 6)
      A.eq(m.tabs[6], { id = "trophies", label = "Trophies", active = true })
      A.eq(m.subtitle, "Trophies: from every session the crew played")
      A.eq(#m.rows, 2)
      A.eq(m.rows[1].name, "Twiz", "most trophies first")
      A.eq(m.rows[1].text, "7 trophies")
      A.eq(m.rows[1].winners, { "Professional Corpse x6, Bunny Hopper x1" })
      A.contains(table.concat(m.rows[1].tip, "\n"), "Professional Corpse: 3 sessions in a row")
      local empty = model(ns, "session", {}, { tab = "trophies", trophies = {} })
      A.eq(#empty.rows, 1)
      A.ok(empty.rows[1].empty)
      A.eq(empty.rows[1].name, "No trophies yet")
    end,
```

`tests/test_trophies.lua`:

```lua
    the_crew_tooltip_shows_trophies = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local t = ns.db.stats.trophies or {}
      ns.db.stats.trophies = t
      t["a-1"] = { sid = "a-1", start = 1, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Lurabe" } } }
      t["a-2"] = { sid = "a-2", start = 2, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Lurabe" } } }
      ns.Bus.fire("TROPHIES_CHANGED", "a-2")
      W:advance(1)
      local tip
      for _, m in ipairs(ns.Panel.models()) do if m.name == "Lurabe" then tip = m.tip end end
      A.contains(table.concat(tip or {}, "\n"), "2 trophies · Professional Corpse streak x2")
    end,
```

(Setting records directly bypasses `add`, so the test fires `TROPHIES_CHANGED` itself; make the summary cache
listen to `TROPHIES_CHANGED` too, or clear it in the test via the event — implement whichever keeps
`Trophies.summary()` correct.)

- [ ] **Step 2: Run to see them fail**: `tools/lua51/lua5.1.exe tests/run.lua "the_trophies_tab|crew_tooltip_shows"`.

- [ ] **Step 3: Implement**

`TwizCrew/UI/BoardLogic.lua`:
- Add `BoardLogic.TROPHY_TAB = { id = "trophies", label = "Trophies", name = "Trophies" }`.
- Make `tabOf(id)` also return `TROPHY_TAB` when `id == "trophies"`; `out.tabs` lists the five award tabs and then
  `TROPHY_TAB` (with `active`).
- When the tab is `"trophies"`: subtitle `"Trophies: from every session the crew played"`, rows from
  `ctx.trophies` (sorted by total, most first, then name), no Wipe Squad footer:

```lua
local function awardDef(id)
  for _, d in ipairs(ns.StatsDefs.AWARDS) do if d.id == id then return d end end
end

-- One row per person with trophies: "7 trophies", their awards by count, a tooltip with every award and streak.
local function trophyRows(summary, ctx)
  local people = {}
  for name, p in pairs(summary or {}) do
    if type(p) == "table" and (p.total or 0) > 0 then people[#people + 1] = { name = name, p = p } end
  end
  table.sort(people, function(a, b)
    if a.p.total ~= b.p.total then return a.p.total > b.p.total end
    return a.name < b.name
  end)
  local rows = {}
  for _, x in ipairs(people) do
    local awards = {}
    for id, n in pairs(x.p.counts) do
      local d = awardDef(id)
      if d then awards[#awards + 1] = { name = d.name, n = n, streak = x.p.streaks[id] } end
    end
    table.sort(awards, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      return a.name < b.name
    end)
    local parts, tip = {}, { text(x.name) .. ": " .. x.p.total .. (x.p.total == 1 and " trophy" or " trophies") }
    for i, a in ipairs(awards) do
      if i <= 2 then parts[#parts + 1] = a.name .. " x" .. a.n end
      local line = a.name .. ": " .. a.n
      if a.streak and a.streak >= 2 then line = line .. " (" .. a.name .. ": " .. a.streak .. " sessions in a row)" end
      tip[#tip + 1] = line
    end
    local e = ctx.entries and ctx.entries[x.name]
    rows[#rows + 1] = {
      id = x.name, name = text(x.name), icon = "Interface\\Icons\\INV_Misc_Ribbon_01",
      text = x.p.total .. (x.p.total == 1 and " trophy" or " trophies"),
      winners = { table.concat(parts, ", ") }, classes = { type(e) == "table" and e.class or false },
      more = 0, empty = false, tip = tip,
    }
  end
  if #rows == 0 then
    rows[1] = { id = "none", name = "No trophies yet", icon = ns.StatsDefs.ICON_FALLBACK, text = "", winners = {},
      classes = {}, more = 0, empty = true,
      tip = { "Trophies are handed out when a crew session ends (at least 30 minutes, at least 2 people)." } }
  end
  return rows
end
```

  (The streak tooltip text must contain "Professional Corpse: 3 sessions in a row" for the test; simplify the line to
  `a.name .. ": " .. a.n .. (streak and " (" .. a.streak .. " sessions in a row)" or "")` if you prefer, and update
  the test's expected substring to match — keep it plain English.)
- In `BoardLogic.model`, branch: `if tab.id == "trophies" then out.subtitle = ...; out.rows = trophyRows(ctx.trophies,
  ctx); return out end` before the award rows.

`TwizCrew/UI/Board.lua`:
- Build one more tab button for `ns.BoardLogic.TROPHY_TAB` after the five (same row). Check the six labels still
  fit 320 px: if `Board.textButton` widths sum above the board width, shrink the gap to 0 rather than wrapping.
- `buildModel()`: add `trophies = ns.Trophies and ns.Trophies.summary() or {}` to `ctx`.
- `tabKnown(id)` accepts `"trophies"`.
- The Trophies rows use the same row frames; `winnersText` colours the one "winner" string by the person's class —
  acceptable.

`TwizCrew/UI/Panel.lua`: after the row models are built in `redraw` (right after `models, hidden = Logic.rows(...)`
and the `dingAt` loop), add:

```lua
  if ns.Trophies then
    for _, m in ipairs(models) do
      local line = not m.self and ns.Trophies.lineFor(m.name)
      if line then
        m.tip = m.tip or {}
        m.tip[#m.tip + 1] = line
      end
    end
  end
```

(Check the field that marks your own row in the models — use the real one; showing your own trophy line is also
fine if there's no such field.) Also add `"TROPHIES_CHANGED"` to the panel's `REDRAW_ON` list so tooltips and the
board refresh when a record arrives.

- [ ] **Step 4: Run**: both tests pass; full suite ALL PASSED.

- [ ] **Step 5: Commit**: `feat(board): Trophies tab and trophy line in the crew tooltip`

---

### Task 5: In-game checks and notes

**Files:** `docs/TESTING.md`, `PROJECT.md`

- [ ] **Step 1**: Add to `docs/TESTING.md` after "Hall of Shame part 1":

```markdown
### Hall of Shame part 2 (stolen crowns, trophies)

1. Play 15+ minutes with a friend, then let them pass you in an award (more deaths, more jumps): a pop-up "<Name>
   just stole <Award> from <you>!" appears within about 5 minutes (numbers are shared every few minutes). Click it:
   the Hall of Shame opens at that award's tab. Several at once: one "N crowns changed hands" pop-up.
2. Live roasts > "Stolen crown pop-ups" off: no more steal pop-ups.
3. After 30+ minutes with a friend, type `/tc session new`: the Hall of Shame's Trophies tab lists the winners of
   the session that just ended. Your friend's Trophies tab shows the same.
4. A friend who was offline when that session ended logs in: within a minute their Trophies tab has it too.
5. Win the same award two sessions in a row: the Trophies tab's tooltip and your row's tooltip on the Crew tab say
   "streak x2".
```

- [ ] **Step 2**: In `PROJECT.md`'s Hall of Shame upgrade line, add after the part 1 sentence: "Part 2 (stolen
  crowns, trophies, streaks) built 2026-11-09, plan `docs/superpowers/plans/2026-11-09-hall-of-shame-part2.md`; not
  tried in game. New files: the next release sets RESTART_SINCE. The swap offers only the 10 newest sessions."
- [ ] **Step 3**: Full suite → ALL PASSED. Commit: `docs: in-game checks for Hall of Shame part 2`
