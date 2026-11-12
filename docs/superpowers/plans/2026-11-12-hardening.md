# Hardening Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bugs and weak spots found in the 2026-11-12 whole-addon review, without adding features and without the crew-code / sender-trust work (the owner put that on hold).

**Architecture:** No new architecture. One shared safe-read helper replaces a dozen private copies; the test stub gets strict so the tests catch what the game would; the stats and calendar swaps get cheaper and order-safe; three oversized files are split by responsibility at the end.

**Tech Stack:** Lua 5.1 (WoW Forever, interface 16001). Tests: `tests/run.sh` (plain Lua 5.1 against `tests/wowstub.lua`). No libraries.

**Spec:** this file. The review findings it implements are restated inside each task. Background on the game's limits: `PROJECT.md`, sections "What an addon can and cannot do in WoW Forever" and "Technical facts".

## Global Constraints

- Lua 5.1 only: no `goto`, no `//`, no bit operators, no `require`, `io` or `os` in addon files. No new globals (the addon's only globals are `TwizCrewDB`, the slash-command and binding names and the three `TwizCrew_OnAddonCompartment*` functions).
- **Friends still run v0.1.23.** Every message a new copy sends must still be understood by a v0.1.23 copy, and every message a v0.1.23 copy sends must still work. New fields may be added to existing messages (old copies ignore unknown fields); a new message type must be harmless when an old copy ignores it. Never change the meaning of an existing field.
- One addon message is at most 255 bytes (`ns.Config.MAX_MESSAGE`); one logical message costs one send per destination through a queue of about 2 sends a second, so new traffic must be small and rare.
- A value returned by a game function may be "secret" inside dungeons: comparing it, doing math on it or using it in `if` raises an error. Every yes/no or number from a `Unit*`, `Is*`, `Get*` game call goes through the shared helper from Task 2 before it is tested.
- Never create, show, hide, move or resize a secure/protected frame in combat. Plain frames are allowed.
- Every handler that the game or a timer calls runs inside `ns.Log.safe(featureId, fn, ...)`.
- Text shown to players is plain, short English. Every new setting needs an `info` text (the module registry asserts it).
- Do **not** bump `ADDON_VERSION`, `## Version`, `RESTART_SINCE`, or add a `Changelog.lua` entry: that happens only when the owner says "release it".
- Do not push, tag or release. Commit on the current branch (`hardening`) only.
- Out of scope, do not build: checking whether a sender belongs to the crew, crew codes, allow-lists, author checks on calendar records.
- `tests/run.sh` must end with `ALL PASSED` before every commit. Run one file with `tests/run.sh <pattern>` (e.g. `tests/run.sh test_comm`).
- Commit messages end with the line `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

## Review Focus

- A game call returns a secret value in a dungeon: the feature keeps working or goes quiet; it never raises an error (Tasks 2, 3).
- A v0.1.23 friend and a new copy are online together: both still see each other's state, stats, notes and trophies (Tasks 6, 7, 8, 9).
- A note or comment of the maximum length written with multi-byte letters ("é", emoji) or the codec's escape characters (`~ = ^ %`): it arrives in one piece (Task 9).
- Messages arrive out of order, twice, or with one piece missing: stores converge and nothing shows zeros (Tasks 8, 9).
- A module raises errors: it turns itself off, says so once, and comes back by itself later (Task 3).

---

### Task 1: Strict test stub

**Why:** `tests/wowstub.lua` accepts any method name on any frame, so a typo such as `SetPonit` passes all tests and errors in the game. The fake `SendAddonMessage` accepts any length. Secret values are ordinary tables, so math on them passes.

**Files:**
- Modify: `tests/wowstub.lua`, `tests/test_lint.lua`
- Create: `tests/test_stub.lua`
- Modify (only if the stricter stub exposes a real mistake): the addon file with the mistake

**Interfaces:**
- Produces: `wowstub` secrets are `newproxy(true)` userdata whose metatable raises on `__add __sub __mul __div __mod __unm __concat __lt __le __eq __call __index __len`; `issecretvalue(v)` is true for them. Keep whatever function the tests already use to make a secret (look for the existing helper near `issecretvalue` in `tests/wowstub.lua`) with the same name and call shape.

- [ ] **Step 1:** Read `tests/wowstub.lua` and `tests/run.lua`. List every method name the addon calls on frames, textures, font strings, animation groups, model frames, edit boxes, sliders, status bars, buttons, scroll frames and cooldowns: `grep -rhoE ':[A-Z][A-Za-z]+\(' TwizCrew | sort | uniq -c`. Separate game-object methods from the addon's own table methods.
- [ ] **Step 2:** Write `tests/test_stub.lua` first (it fails now): (a) `CreateFrame("Frame"):SetPonit()` raises an error whose text names the method; (b) `CreateFrame("Frame"):SetPoint("CENTER")` does not; (c) a frame after `:Hide()` answers `IsShown() == false`, after `:Show()` true, and `IsVisible()` is false when a parent is hidden; (d) the fake `C_ChatInfo.SendAddonMessage` raises (or records a failure the test can assert) for a 256-byte text and accepts 255; (e) `secret + 1`, `secret .. "x"`, `secret < 1` each raise, and `issecretvalue(secret)` is true.
- [ ] **Step 3:** Replace the permissive object with a whitelist: one set of real method names shared by all regions (`SetPoint, ClearAllPoints, SetSize, SetWidth, SetHeight, GetWidth, GetHeight, Show, Hide, IsShown, IsVisible, SetShown, SetAlpha, GetAlpha, SetParent, GetParent, SetScale, GetScale, GetLeft, GetRight, GetTop, GetBottom, GetCenter, IsMouseOver, ...`) plus a set per widget type (Frame, Button, EditBox, Slider, StatusBar, ScrollFrame, PlayerModel/DressUpModel, Cooldown, Texture, FontString, AnimationGroup, Animation). `CreateFrame(type)` picks the set from `type`; an unknown type raises. A method not in the set raises `"<Type> has no method <name>"`. Only names that exist in the real WoW API go in; when the addon calls a name you believe does not exist in the modern client, do not whitelist it: report it. Track shown/hidden state per object.
- [ ] **Step 4:** Run `tests/run.sh`. For each failure decide: stub missing a real method (add it) or a real mistake in the addon (fix the addon file, name it in the report).
- [ ] **Step 5:** Add to `tests/test_lint.lua` a global-write scan: compile every file in the `.toc` with `tools/lua-5.1.5/src/luac -l -p` (use `lua5.1`'s sibling `luac5.1` when present) and fail on any `SETGLOBAL` whose name is not in the allowed list (`TwizCrewDB`, `SLASH_*`, `SlashCmdList` writes, `BINDING_*`, `TwizCrew_*`). Skip the test with a printed note when no `luac` is found.
- [ ] **Step 6:** `tests/run.sh` → `ALL PASSED`. Commit: `test: strict widget stub, 255-byte send check, real secret values, global-write lint`.

---

### Task 2: One safe-read helper, used everywhere

**Why:** In a dungeon even `UnitIsAFK("player")` is secret and `if x then` on it raises. That error turned the panel off on 2026-11-08. About twelve files carry their own `try` / `call` / `readable` helper with different guarantees, and several places wrap the call in `pcall` but test the result outside it.

**Files:**
- Modify: `TwizCrew/Core/Util.lua`, `tests/test_util.lua`, `tests/test_lint.lua`
- Modify (adopt the helper): `TwizCrew/Crew/SelfState.lua` (lines ~69-71: `onTaxi`, `inInstance`), `TwizCrew/Layer/Layer.lua` (~38, 57, 171: `IsInRaid`, `IsInGroup`, `UnitExists`, `UnitIsPlayer`), `TwizCrew/Tags/Tags.lua`, `TwizCrew/Crew/Quest.lua`, `TwizCrew/Stats/Detectors.lua` (~109 `IsInInstance`, 129-130 `IsMounted` / `IsSwimming`, 157 `IsFalling`, 246-256 `UnitExists` / `UnitIsPlayer` / `UnitCanAttack`), `TwizCrew/UI/Updates.lua:29` (`inFight`), `TwizCrew/UI/Panel.lua` (~1413, 1457 row menu; ~2163-2165 startup combat read), `TwizCrew/UI/Popups.lua:85-86`, `TwizCrew/UI/Commands.lua:139-141`, `TwizCrew/UI/Report.lua:82-93`, and every other private copy `grep -rnE 'issecretvalue' TwizCrew` finds.

**Interfaces:**
- Produces: `ns.Util.plain(fn, ...)` → the results of `fn(...)` with every secret result replaced by `nil`; returns nothing when `fn` is not a function or raises. Never raises. `ns.Util.isSecret(v)` → true when `issecretvalue` exists and says so (false when the game has no `issecretvalue`).

- [ ] **Step 1:** Tests in `tests/test_util.lua` (fail first): `plain` passes through `1, "a", true, nil` in position (use `select("#", ...)` to check a `nil` in the middle survives); a secret result becomes `nil` while its neighbours stay; a raising `fn` returns nothing; `plain(nil)` returns nothing; `isSecret(secret)` true, `isSecret(5)` false, and false when `_G.issecretvalue` is `nil`.
- [ ] **Step 2:** Implement both in `Core/Util.lua` (it loads before every user).
- [ ] **Step 3:** Replace each private helper with `ns.Util.plain` (keep a file-local alias `local plain = ns.Util.plain`); delete the private copies. For combat state use `InCombatLockdown()` (never secret) instead of `UnitAffectingCombat("player")` in `Updates.lua` `inFight` and the `Panel.lua` startup read.
- [ ] **Step 4:** For each adopted site add or extend a test that makes the game call return a secret and asserts no error is logged and the feature's result is its "unknown" value (examples: `Self.gather()` returns a table with `ins == "0"`; the Layer recompute leaves verdicts unchanged; a detector tick adds nothing; the row menu builds). Use the stub's secret maker from Task 1.
- [ ] **Step 5:** Lint rule in `tests/test_lint.lua`: in addon files other than `Core/Util.lua`, a line may not call one of `UnitIsAFK UnitIsDeadOrGhost UnitIsDead UnitIsGhost UnitAffectingCombat UnitOnTaxi UnitExists UnitIsPlayer UnitCanAttack UnitIsVisible UnitInParty UnitInRaid UnitPosition UnitIsConnected IsInInstance IsInGroup IsInRaid IsMounted IsSwimming IsFalling IsResting` directly with `(`; the name may only appear as an argument (`plain(UnitIsAFK, "player")`). Fix every remaining hit.
- [ ] **Step 6:** `tests/run.sh` → `ALL PASSED`. Commit: `fix: one safe-read helper for game values; no bare tests on values that can be secret`.

---

### Task 3: Log that keeps errors, a breaker that recovers

**Why:** In the owner's real saved log 83% of the 500 lines are `send POS` / `recv POS`, so it covers 15 minutes and earlier errors are gone. Three errors in 60 s turn a module off until `/reload`, and unrelated parts share one feature id, so a cosmetic bug takes down a whole feature. `Log.safe` allocates two tables and two closures on every call, including every frame. One failing section kills all of `/tc report`.

**Files:**
- Modify: `TwizCrew/Core/Log.lua`, `TwizCrew/Core/Modules.lua`, `TwizCrew/Core/DB.lua`, `TwizCrew/Core/Boot.lua`, `TwizCrew/Core/Init.lua` (Config), `TwizCrew/Comm/Comm.lua` (lines ~138-168), `TwizCrew/UI/Report.lua` (~140-171), `TwizCrew/UI/MockShow.lua`, `TwizCrew/UI/MockEditor.lua`, `TwizCrew/Crew/SelfState.lua`, `TwizCrew/Crew/Quest.lua`, `TwizCrew/Layer/LayerSensor.lua`, `TwizCrew/Tags/Tags.lua` (Away), `TwizCrew/Crew/Crew.lua`
- Test: `tests/test_log_events.lua`, `tests/test_modules_db.lua`, `tests/test_comm.lua`

**Interfaces:**
- Produces: `ns.Log.problems()` → array of the kept ERROR and WARN lines (oldest first), stored in `db.problems`, at most `Config.PROBLEMS_MAX = 100`. `ns.Log.count(key)` adds one to a session counter; `ns.Log.counts()` → `{ key = n }`. `Config.BREAK_REARM = 300`.

- [ ] **Step 1 (errors ring):** every ERROR and WARN line is written to both the rolling log and `db.problems` (`DB.init` default `problems = {}`; `Log.attach(lines, problems)`; trimmed to `PROBLEMS_MAX`; same repair of non-string entries as the log). `Log.errors(n)` reads from the ring. A traceback line that follows an error is kept in the ring too. Tests: 600 debug lines after one error → `Log.errors(1)` still returns it; the ring never exceeds 100.
- [ ] **Step 2 (comm chatter):** in `Comm.lua` the per-message `recv` and per-destination `send` lines are stored only while `Log.chatDebug` is on. Always: `Log.count("recv " .. type)`, `Log.count("send " .. type)`, and `Log.count("send failed")` for a refused send. `/tc report` prints the counters as one line (`Messages this session: recv POS 195, send POS 218, ...`, sorted by name). Tests: with debug off, 50 received messages add no log lines and the counter says 50.
- [ ] **Step 3 (breaker re-arm):** `BREAK_REARM` seconds after a feature is marked broken, `Log` forgets its failures and `Modules` clears `broken[id]`, starts the module again if it is enabled, fires `MODULE_TOGGLED`, and logs `info "<id> switched back on"`. A second break in the same session re-arms after twice as long (cap 30 min). `Modules.broken()` lists only currently broken ids. Use `C_Timer.After` inside `Log.safe`. Tests with the stub's clock: 3 errors → off; +300 s → on and `onEnable` ran again; break again → back on only after 600 s.
- [ ] **Step 4 (own feature ids):** `Boot.login` starts `Crew`, `Self`, `LayerSensor`, `Away`, `Quest` each under its own id (`"crew"`, `"self"`, `"layersensor"`, `"away"`, `"quest"`) instead of `"comm"`, and each of those files uses that id for its `Events.on`, `Bus.on` and `Log.safe` calls. `MockShow.lua` and `MockEditor.lua` use `"mockshow"` / `"mockeditor"` instead of `"roasts"`. These ids are not registered modules: `Modules.markBroken` on an unknown id must log a warning once and do nothing else (check that this is what happens today; make it so). Test: three errors under `"mockshow"` leave `Modules.isEnabled("roasts")` true.
- [ ] **Step 5 (`Log.safe` without garbage):** no table and no closure allocated on the success path when `fn` raises nothing. The game's `xpcall` accepts extra arguments (`xpcall(fn, handler, ...)`), plain Lua 5.1 does not: detect once at load (`select(2, xpcall(function(a) return a end, function() end, 7)) == 7`) and pick the implementation; the plain-Lua fallback may keep one closure. The handler is one file-level function. Return values must be unchanged: `true, results...` or `false, err`. Test: results with a `nil` in the middle survive (`Log.safe("x", function() return 1, nil, 3 end)` → `true, 1, nil, 3`).
- [ ] **Step 6 (`/tc report` sections):** in `Report.lua` wrap every section builder in a local `section(name, fn)` that pcalls and, on error, adds the line `<name>: failed (<error text>)`. Add a "Problems" section printing the newest 5 lines of `Log.problems()`. Test: a section that raises still yields a report containing the other sections and the `failed` line.
- [ ] **Step 7:** `tests/run.sh` → `ALL PASSED`. Commit: `fix(log): keep errors apart from chatter, re-arm broken modules, own ids per part`.

---

### Task 4: Small fixes, UI

**Why:** each is a confirmed small defect from the review. One commit, one review.

**Files and changes:**
- `TwizCrew/UI/MockShow.lua:176` and `:322`: two file-local functions are both named `remember`; the drag handler at `:272` calls the look-remembering one with no arguments and raises. Rename the position one to `savePosition`, declare it above `build()`, call it from `OnDragStop`. Test (`tests/test_mockshow.lua`): simulate drag stop → no error logged and `db` holds the saved spot (`mockShowPos`).
- `TwizCrew/UI/Panel.lua:69`: `local fullHeight, curHeight, curView = nil, nil, HEADER_HEIGHT, "full"` → `= nil, HEADER_HEIGHT, "full"`. Check each later use of `curHeight` / `curView` still behaves (the first redraw sets them).
- `TwizCrew/UI/Panel.lua` (`applyLook`, ~202-211 and ~278): when the `scale` setting changes, multiply the saved `x` and `y` by `oldScale / newScale` before `applyPosition`, so the panel's corner stays where it is on screen. Put the arithmetic in `PanelLogic` as `PanelLogic.rescalePosition(x, y, oldScale, newScale)` → `x2, y2` with a test (`600, -300, 1.0, 1.5` → `400, -200`; `oldScale` nil or 0 → unchanged).
- `TwizCrew/UI/Panel.lua` (fade, ~284) and `TwizCrew/UI/Popups.lua:154`: the `OnUpdate` handlers enter `Log.safe` every frame. Accumulate `elapsed` in a raw handler and call into `Log.safe` only when the 0.1 s (panel fade) step is due; pop-ups likewise at their existing step.
- `TwizCrew/UI/Panel.lua` (~1984-1987, ~2020-2023): the "Open while my mouse is on the bar" ticker runs ten times a second for the whole session; cancel it while the panel is not shown or not minimized and start it again when both are true.
- `TwizCrew/UI/Panel.lua` (~2098-2109, `noticeClicked`): act on `bar:current()`; if that is not the notice drawn (`noticeShown`), return without acting or dismissing.
- `TwizCrew/UI/Recent.lua:140-146`: remove the "not the first time in a fight" gate; the window is a plain frame and may be built in combat.
- `TwizCrew/UI/Popups.lua:92-105` and `TwizCrew/UI/Panel.lua:1422-1426`: one shared `ns.Util.whisper(name)` in `Core/Util.lua` (full "Name Realm" from `ns.Transport.fullName` when it knows one; tries `ChatFrameUtil.SendTell`, then `ChatFrame_SendTell`, then `ChatFrame_OpenChat("/w " .. name .. " ")`; returns true when one existed). Both callers use it. Test: with only `ChatFrameUtil.SendTell` defined, an "online" pop-up click calls it with the full name.
- `TwizCrew/UI/Panel.lua` setting `barInstead`: default `false` (was `true`), and its `info` text says pop-ups keep showing unless this is on. Update the test that asserts the default.
- `TwizCrew/UI/MinimapButton.lua:2` and `:243-244`: the comment and the (i) text say right-click shows or hides the panel; since v0.1.18 it opens a menu. Correct both.
- `TwizCrew/Tools/RankUp.lua:224-228`: every "learned" event starts its own 1 s timer and full scan; use one pending flag so a burst gives one scan. `:128`: do not call `ClearCursor()` when the automatic update finds the cursor already holding something (`GetCursorInfo()` non-nil) — skip that run and try at the next trigger. Tests for both in `tests/test_qol.lua` or the file that covers RankUp.

- [ ] **Step 1:** Write the failing tests named above.
- [ ] **Step 2:** Make the changes.
- [ ] **Step 3:** `tests/run.sh` → `ALL PASSED`. Commit: `fix(ui): mock show drag, scale keeps the panel in place, per-frame work, small UI defects`.

---

### Task 5: Small fixes, logic

**Files and changes:**
- `TwizCrew/Core/DB.lua:34-36`: saved settings of a module id that is not registered are deleted at load, so one file failing to load erases that module's settings for good. Delete only ids in an explicit `local REMOVED = { spellhelp = true }` list; leave other unknown ids alone. Test in `tests/test_modules_db.lua`: unknown id `"future"` survives `DB.init`; `"spellhelp"` is removed.
- `TwizCrew/Comm/Codec.lua:125-126` and its caller in `Comm/Comm.lua`: `decode` returns the protocol number and nobody reads it. Ignore a message whose protocol is greater than `Config.PROTOCOL` (count it with `ns.Log.count("recv newer protocol")` if Task 3's counter exists, else one info log line per sender per session). Test in `tests/test_comm.lua`.
- `TwizCrew/Layer/Layer.lua:182` (and 168-170): `recompute` runs on every `NAME_PLATE_UNIT_ADDED`, `MEMBER_UPDATED` and `SELF_UPDATED`. Those events set a dirty flag; one recompute runs at most every 0.5 s (`Config.LAYER_RECOMPUTE_GAP = 0.5`); the existing 2 s ticker stays. Test: 40 nameplate events in one instant → one recompute.
- `TwizCrew/Find/Find.lua:326-339` ("running off" alarm): do not raise it for a friend whose roster tags say dead or ghost, nor when their move since the last reading is faster than `Config.MAX_RUN_SPEED` yards a second (a hearthstone, flight or ghost release). Tests in `tests/test_find.lua`.
- `TwizCrew/Find/Where.lua:219`: `ipairs({ UnitInParty, UnitInRaid })` builds a table per call and stops at a nil; use two plain calls through `ns.Util.plain`.
- `TwizCrew/Find/Find.lua:23`: `meetIds` only grows; drop ids older than `Config.MEET_LIFE` when a new one is added.
- `TwizCrew/Stats/Detectors.lua:167` (Furniture / AFK time): count time while the addon's own away state is on (the same source that sets the AFK tag in `Tags.lua` — `ns.Away`), not only the game's AFK flag. Test in `tests/test_stats.lua`: away via the AFK button for 60 s adds 60 s.
- `TwizCrew/Stats/Detectors.lua:61-72` (`guard`) and `TwizCrew/Stats/StatsStore.lua:54` (`Store.add`): no table or closure allocated per call (write the two views out in `Store.add`; pass arguments through instead of capturing them).
- `TwizCrew/UI/MockShow.lua:285`: the closure created every frame while the show is up becomes one file-level function.
- `TwizCrew/Stats/Roasts.lua:363-372` (Mock button): take the 10 s limiter only after a usable line was found; when "Only use my own roasts" leaves no usable line, fall back to a built-in line. Test in `tests/test_roasts.lua`.
- `TwizCrew/Tags/Tags.lua:111` (auto-away): never auto-away while on a flight path.
- `TwizCrew/Stats/StatsDefs.lua`: the Money Pit and Pauper award texts say that any gold leaving the bags counts (mail, trades, auction bids too).

- [ ] **Step 1:** Write the failing tests named above.
- [ ] **Step 2:** Make the changes. Game reads go through `ns.Util.plain` (Task 2).
- [ ] **Step 3:** `tests/run.sh` → `ALL PASSED`. Commit: `fix: keep unknown modules' settings, layer recompute at most twice a second, small logic defects`.

---

### Task 6: Fewer, better-ordered sends

**Why:** on WoW Forever a send to the custom channel is never delivered, yet every broadcast spends one queue slot on it (20% with four friends). The layer key `lk` decides nothing since v0.1.6 but each change still triggers an UPDATE to every friend. A PING from an unknown name makes this copy broadcast HELLO without STATE, which wipes its tags on every friend's screen. Bulk swaps (stats, calendar, trophies) share one first-in-first-out queue with live messages, which then wait minutes. A permanently refused destination can sit at the front of the queue forever.

**Files:**
- Modify: `TwizCrew/Comm/Queue.lua`, `TwizCrew/Comm/Comm.lua`, `TwizCrew/Comm/Transport.lua` (~534-620), `TwizCrew/Crew/Crew.lua:72-82`, `TwizCrew/Crew/SelfState.lua:114`, `TwizCrew/Core/Init.lua` (Config), and the bulk senders: `TwizCrew/Stats/Stats.lua` (STATS), `TwizCrew/Stats/Trophies.lua` (trophy pieces), `TwizCrew/Calendar/Diary.lua` (CALP), `TwizCrew/Calendar/Notes.lua` (`sendAll`)
- Test: `tests/test_queue.lua`, `tests/test_comm.lua`, `tests/test_crew.lua`

**Interfaces:**
- Produces: `ns.Comm.send(type, fields, opts)` and `ns.Comm.sendTo(name, type, fields, opts)` accept `opts.bulk = true`: the items wait in a second lane that is served only when the normal lane is empty. Existing options (`replace`, key, sent callback) keep working in both lanes. `Config.SEND_RETRY_MAX = 10`.

- [ ] **Step 1 (bulk lane):** tests first in `tests/test_queue.lua`: three bulk items then one normal item → the normal one leaves first; bulk items keep their own order; `replace` only replaces within the same lane. Implement in `Queue.lua`; thread `opts.bulk` through `Comm.send` / `sendTo`. Mark the four bulk senders above (answers to a request and periodic swaps; not the small digests).
- [ ] **Step 2 (retry cap):** an item refused `SEND_RETRY_MAX` times is dropped with one WARN line (`send to <dest> given up after 10 tries`) and the queue moves on. Test in `tests/test_comm.lua`.
- [ ] **Step 3 (channel copy):** in automatic mode the copy to the custom channel is sent only for `PING`, or for every type once `Comm.echoCount() > 0` (the channel has delivered something this session). The mode a player explicitly set to "Hidden channel" is unchanged. Tests: 4 channel members, no echo yet → an UPDATE makes exactly 4 sends; a PING makes 5; after an echo an UPDATE makes 5.
- [ ] **Step 4 (`lk` rides along):** add `lk = true` to `RIDE_ALONG` in `SelfState.lua`. Test: only `lk` changed → no UPDATE; `lk` plus `zn` changed → one UPDATE carrying both.
- [ ] **Step 5 (PING from a stranger):** `Crew.onPing` for an unknown sender answers that sender only: `if ns.Comm.sendTo(sender, "HELLO", hello()) then ns.Comm.sendTo(sender, "STATE", ns.Self.fullState()) end`, no broadcast. Test in `tests/test_crew.lua`: three copies; C pings A as a stranger → B receives nothing new from A and still shows A's DEAD tag.
- [ ] **Step 6:** `tests/run.sh` → `ALL PASSED`. Commit: `fix(comm): bulk lane behind live messages, no dead channel copies, PING answer goes to the asker only`.

---

### Task 7: Repair after a lost message; forget a friend

**Why:** UPDATE carries only what changed and a refused send is dropped, so one lost `tg=DEAD` stays wrong on a friend's panel until that field changes again. And a name can never leave the roster: old alts and typos stay in the Offline list and on the all-time board, and in fallback mode every broadcast whispers each of them.

**Files:**
- Modify: `TwizCrew/Crew/Crew.lua`, `TwizCrew/Crew/SelfState.lua`, `TwizCrew/Crew/Roster.lua` (~148, `Roster:remove` ~234), `TwizCrew/Comm/Transport.lua:557-560`, `TwizCrew/Stats/StatsStore.lua`, `TwizCrew/UI/Panel.lua` (row menu), `TwizCrew/UI/Commands.lua`, `TwizCrew/Core/Init.lua` (Config)
- Test: `tests/test_crew.lua`, `tests/test_roster.lua`, `tests/test_sim.lua`

**Interfaces:**
- Produces: `ns.Self.digest()` → a short string (at most 6 characters) that is equal on sender and receiver exactly when the receiver holds every field the sender last sent, ignoring the ride-along keys `xc`, `rx`, `lk`. `Roster:digest(name)` → the same function over what this copy holds for `name`. `ns.Crew.forget(name)` → true when a friend was removed. `Config.FORGET_AFTER_DAYS = 60`.

- [ ] **Step 1 (digest in PING):** PING gains field `h = Self.digest()`. A receiver that knows the sender compares it with `Roster:digest(sender)`; on the second mismatch in a row from that sender (two PINGs, so a change in flight does not trigger it) it sends `SREQ` to that sender only, at most once per `Config.PING_INTERVAL` per sender. `SREQ` is answered with `sendTo(asker, "STATE", Self.fullState())`. A PING without `h` (a v0.1.23 copy) is never a mismatch; a v0.1.23 copy ignores `SREQ` (check in `Comm.lua` / `Codec.lua` that an unknown type is dropped quietly and say so in the report). The digest must be computed from the same key set on both sides: use the sorted keys of the sender's last-sent table minus the ride-along keys, hashed with the string hash the addon already has (look in `Core/Util.lua`; the calendar's notes checksum uses one). Tests in `tests/test_sim.lua`: two copies; drop one UPDATE (`tg=DEAD`) on the way to B; after two PINGs B asks, A answers, B shows DEAD. With no loss, ten PINGs cause zero `SREQ`.
- [ ] **Step 2 (forget):** `ns.Crew.forget(name)`: removes the roster row and `crew.extra` entry, `db.stats.crew[name]`, and any whisper destination `Transport` keeps for the name; fires the roster's removal event so the panel redraws. Never forgets yourself or an online friend (returns false and the caller prints why). Row right-click menu, offline rows only: "Forget this friend" (with an icon, like its neighbours). `/tc forget <name>`; `/tc remove` keeps working and now calls it. A friend who shows up again later is simply added again.
- [ ] **Step 3 (prune at load):** when the roster loads, drop saved rows whose last-seen wall-clock time is older than `FORGET_AFTER_DAYS` days (rows with no saved time get today's time at first load, so nobody vanishes on the update), and their `db.stats.crew` records.
- [ ] **Step 4 (fallback whispers):** in fallback / whisper mode a broadcast whispers only roster names that are online; HELLO still goes to everyone in the roster (that is how offline friends are found again).
- [ ] **Step 5:** tests for 2-4 in `tests/test_roster.lua` / `tests/test_crew.lua`; `tests/run.sh` → `ALL PASSED`. Commit: `feat(crew): repair a friend's state after a lost message; forget a friend; old names expire`.

---

### Task 8: Stats swaps that never show zeros

**Why:** a friend's numbers travel as a snapshot in 3-4 pieces. The store replaces the record on the first piece, so for a few seconds most of their numbers are zero: the board shows wrong winners, "X stole the crown" pop-ups can fire, and a session ending in that window saves wrong trophies. Each piece also redraws the panel and re-runs the steal check, unthrottled. A late snapshot can overwrite a newer one. When a session is ended by hand, two copies can save different "full" trophy records for it and never reconcile.

**Files:**
- Modify: `TwizCrew/Stats/StatsStore.lua:150-172`, `TwizCrew/Stats/Stats.lua:135-170, 221-236`, `TwizCrew/Stats/TrophyLogic.lua:160-170`, `TwizCrew/Stats/Trophies.lua`, `TwizCrew/Stats/Steals.lua`
- Test: `tests/test_stats.lua`, `tests/test_stats_share.lua`, `tests/test_trophies.lua`, `tests/test_sim_stats.lua`

- [ ] **Step 1 (overlay, not replace):** when a STATS piece arrives for a friend whose stored record has the same session id (`sid`), the new numbers are laid over the stored ones (keys absent from the piece keep their stored value). A different `sid` starts the session view fresh as today; the all-time view is always overlaid (all-time numbers only grow). Test (fail first): store a full record for Frostie, feed only piece 1 of a newer snapshot → every award leader is unchanged from before the piece, and after all pieces the record equals the new snapshot exactly.
- [ ] **Step 2 (older snapshot loses):** a snapshot whose `q` (its sender's wall-clock stamp; read how `q` is produced in `Stats.lua` and compare the way that fits — if it is not ordered today, make new copies send an ordered one in a new field and keep `q` untouched for v0.1.23) is older than the stored record's is ignored. Test: newer then older → stored numbers stay the newer ones.
- [ ] **Step 3 (throttle):** a received piece calls the same throttled `changed()` path local changes use (`Config.STATS_CHANGED_GAP`), not `fireChanged()` directly. Test: 20 pieces within one second → `STATS_CHANGED` fires at most twice.
- [ ] **Step 4 (steals wait for the whole snapshot):** `Steals` must not announce a steal from numbers that arrived less than `Config.STATS_CHANGED_GAP` seconds ago for that friend; it re-checks when the gap has passed. Test in `tests/test_sim_stats.lua`: a snapshot delivered piece by piece with 2 s between pieces produces no steal pop-up that the complete snapshot does not justify.
- [ ] **Step 5 (trophy records reconcile):** two "full" records for the same session with the same number of people but different content must end up identical on every copy. Add a short checksum of each offered record to the trophy digest as a new field (v0.1.23 ignores it). When a peer offers a full record for a session I also hold in full, with the same people count and a different checksum, the record with the **smaller checksum string** wins everywhere: the holder of the larger one asks for the other through the existing ask / pieces path and replaces its own. Keep every existing rule (late never replaces full; more people beats fewer). Tests in `tests/test_trophies.lua`: A and B hold different full records for one session → after one digest each way both hold the same one, and a third digest causes no further asks.
- [ ] **Step 6:** `tests/run.sh` → `ALL PASSED`. Commit: `fix(stats): pieces overlay the stored numbers, older snapshots lose, trophy records converge`.

---

### Task 9: Calendar swaps that converge and stay small

**Why:**
1. A note is capped at 120 *letters*, but a message is 255 *bytes*: a long note with "é" or the codec's escape characters is split into pieces that every copy rejects, so it never arrives, and the notes checksum then differs for good.
2. Any checksum difference makes the receiver ask for *all* notes and replies, from every friend, one whisper each (hundreds of sends).
3. Notes are pruned at login by local date while the checksum counts everything stored, so copies that logged in on different days disagree for ever and hand the pruned note back.
4. Notes and replies have no cap while logged in; comments per note are unlimited.
5. Play-time diaries: the digest compares total slot counts and the answer is the whole 30 days, and an online friend's count grows every 15 minutes, so everyone keeps re-asking everyone.
6. One fixed UTC offset (today's) is used for every date, so a timed note made before a clock change shows an hour off after it.

**Files:**
- Modify: `TwizCrew/Calendar/Notes.lua` (`clean` ~138-142, `hash` ~187-197, `fields` / `send` ~200-215, `sendAll` ~217-223, replies ~241-254, `receiveReply` ~342-362, `receive` ~397-418, `prune` ~421-437), `TwizCrew/Calendar/Diary.lua` (~59-67, 144-153, 187-267), `TwizCrew/Calendar/CalendarLogic.lua` (~158), `TwizCrew/Calendar/CalendarUI.lua:981`, `TwizCrew/Calendar/NoteView.lua` (comment box limit)
- Test: `tests/test_calendar.lua`

**Interfaces:**
- Consumes: `opts.bulk` on `ns.Comm.send` / `sendTo` (Task 6).
- Produces: `Notes.MAX_BYTES = 100` (the words of a note or a comment, counted after the codec's escaping); `Notes.MAX_COMMENTS = 30` per note; `Notes.BUCKETS = 8`.

- [ ] **Step 1 (size):** tests first: for every calendar message type (CALN, CALR in its three kinds, CALD, CALQ, CALP) build the largest record the code allows with words made of "é", of "~", and of emoji, encode it, and assert exactly one piece of at most 255 bytes that the receiving handler accepts. Then: `clean()` cuts words to `MAX_BYTES` measured on the escaped form, never inside a UTF-8 sequence (`ns.Util.truncateUTF8` exists); `fields()` / the reply fields cut again, so notes saved by older versions are shortened on the way out; the note and comment edit boxes stop at the limit.
- [ ] **Step 2 (same window everywhere):** one function decides whether a note or reply counts: its day is within the keep window (90 days for notes) measured in UTC days from the current UTC day. `hash()`, `sendAll()`, `receive()` and `receiveReply()` all skip what is outside it; a reply whose note is missing or outside is skipped too. `prune` uses the same function and also runs once a day while logged in. Test: copy A pruned a 91-day-old note, copy B still stores it → equal checksums, no request, and A does not store it again when B sends it.
- [ ] **Step 3 (caps on receive):** `receive` refuses a new note when `MAX_NOTES` live notes are stored (an update to a stored key is still taken); `receiveReply` refuses a new comment past `MAX_COMMENTS` for its note. Both copies apply the same rule to their own writes. A refused record must not make checksums differ for ever: the checksum counts only records a copy would accept, in key order (so the same oldest-first / lowest-key-first choice is made everywhere). Test it: A holds 31 comments on one note, B applies the cap → equal checksums.
- [ ] **Step 4 (buckets):** the digest (CALD) keeps `nh` for v0.1.23 and adds `nb`: `BUCKETS` short checksums, one per bucket, a note and its replies falling in the bucket chosen by a hash of the **note key**. A receiver whose `nb` differs asks with `CALQ` carrying `b` = the list of differing bucket numbers (plus `n=1`, which v0.1.23 answers with everything); a new copy answering a request with `b` sends only those buckets' notes and replies, with `opts.bulk`. A digest without `nb` (v0.1.23) is handled as today. A copy answers at most one notes request per 60 s over all askers (later askers ask again at the next digest). Tests: two copies differing by one note → exactly one bucket requested and only that bucket's records sent; five copies where one misses one note → total sends counted and asserted under 40; a v0.1.23-style digest (only `nh`) still gets the old full exchange.
- [ ] **Step 5 (diary without re-asking):** the 10-minute digest also carries the sender's own slot masks for today and yesterday (UTC days) in new fields, merged by the receiver with the existing OR rule; and the comparison that decides whether to ask a friend for their full diary ignores today's and yesterday's slots of the person who sent the digest. Assert the digest still fits one 255-byte message with `nb` and both masks at their largest. Test: five copies online for one simulated hour → zero CALQ / CALP after the first exchange, and every copy shows every other's last hour.
- [ ] **Step 6 (clock changes):** a timed note's stored time comes from `time({ year, month, day, hour, min })`, which uses the offset of *that* date; day and timeline views compute the local offset per displayed day (`date("*t", dayStart)`), cached by day, instead of one offset for all days. Tests with a stubbed `time` / `date` pair that changes offset on a given day: an "8pm" note created before the change for a day after it shows at 8pm on that day.
- [ ] **Step 7:** `tests/run.sh` → `ALL PASSED`. Commit: `fix(calendar): notes fit one message, swaps converge and send only what differs`.

---

### Task 10: Split the three oversized files

**Why:** `UI/Panel.lua` (about 2,300 lines), `Calendar/CalendarUI.lua` (about 1,500) and the test tools inside `UI/Report.lua` (about 500 of 760 lines) are too large to change safely. This task moves code; it changes no behaviour.

**Files:**
- `TwizCrew/UI/Panel.lua` → keeps: module registration and settings, frame creation, look / position, the redraw loop, enable / disable. New files (loaded right after it in `TwizCrew.toc`, in this order): `UI/PanelRows.lua` (row widgets, row drawing, arrows, row tooltips), `UI/PanelHeader.lua` (header build and `drawHeader`, title, count, update and What's-new lines), `UI/PanelMenus.lua` (row menu, title menu, wrench menu, status box), `UI/PanelMini.lua` (minimize, bar notices, missed number, peek, bar hover).
- `TwizCrew/Calendar/CalendarUI.lua` → keeps: the window, navigation between views, shared helpers. New files after it: `Calendar/CalendarMonth.lua`, `Calendar/CalendarDay.lua` (day timeline), `Calendar/CalendarUsual.lua` (usual-times grid and real-week grid), `Calendar/CalendarMaker.lua` ("+ Create note" window and dungeon picker).
- `TwizCrew/UI/Report.lua` → keeps `/tc report`. New: `UI/TestTools.lua` (everything behind "Try it out" / `/tc test`, i.e. `ns.TestTools`), loaded right after `Report.lua`.
- Modify: `TwizCrew/TwizCrew.toc`; tests only where they load files by name (`tests/run.lua` reads the `.toc`; check).

**Interfaces:**
- Shared state moves from file-local upvalues to one private table per family: `ns.Panel._` (alias `local P = ns.Panel._` at the top of each panel file), `ns.CalendarUI._`. Every function or variable used by more than one of the new files lives on that table; everything else stays file-local. Public names (`ns.Panel.*`, `ns.CalendarUI.*`, `ns.TestTools.*`, `ns.Report.*`) do not change.

- [ ] **Step 1:** Before moving anything, record `tests/run.sh | tail -1` (the test count) and `wc -l` of the three files.
- [ ] **Step 2:** Split `Report.lua` / `TestTools.lua` first (smallest). Run the tests.
- [ ] **Step 3:** Split `Panel.lua`. Lua 5.1 allows 200 locals and 60 upvalues per function: keep an eye on both at file level. Order of definition matters for locals: a function must be defined (or reached through `P.`) before the code that calls it runs, not before it is written. Run the tests after each new file.
- [ ] **Step 4:** Split `CalendarUI.lua` the same way.
- [ ] **Step 5:** No file in the three families is over about 800 lines; the test count equals Step 1's; `git diff --stat` shows no test assertions weakened or removed. While moving, replace the repeated tooltip `OnEnter` / `OnLeave` block and the repeated icon-button block with `ns.Widgets.tip(frame, titleFn, linesFn)` and `ns.Widgets.iconButton(parent, icon, size, onClick, tip)` in `UI/Widgets.lua` **only where the replaced code is identical in behaviour**; leave any variant that differs as it is.
- [ ] **Step 6:** `tests/run.sh` → `ALL PASSED`. Commit: `refactor: split Panel, CalendarUI and the test tools by responsibility (no behaviour change)`.
