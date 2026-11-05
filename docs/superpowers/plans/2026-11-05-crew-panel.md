# TwizCrew v1 (Crew panel, layer tracker, pop-ups, settings) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Forever addon, TwizCrew v1: copies talk to each other, show every crew member in a movable Crew
panel with class icon, level, zone, status, XP and tags (including OTHER LAYER), pop up layer changes and deaths,
and offer a settings window built from a module registry with (i) buttons and a reset button.

**Architecture:** One addon folder `TwizCrew/` (symlinked into the game's AddOns folder). A small core (namespace,
log, event bus, module registry, saved data), a messaging layer (codec, throttled queue, swappable transport), crew
state (roster, own state, layer sensor), then modules (panel, tags, layer, pop-ups) and UI (widgets, settings,
commands, report). Pure logic is tested outside the game with plain Lua 5.1 against a fake WoW API; UI is checked by
a load test and a two-copy simulation, then by the owner in game later.

**Tech Stack:** Lua 5.1 (WoW dialect), WoW Forever API (interface 16001), a hand-written test runner
(`tests/run.lua`) and fake WoW API (`tests/wowstub.lua`) run with `lua5.1`. No libraries (no Ace3, no LibStub).

**Spec:** `docs/superpowers/specs/2026-11-05-crew-panel-design.md`. Also read `PROJECT.md` (game facts, limits,
paths). Read both before any task.

## Global Constraints

- `## Interface: 16001`, `## SavedVariables: TwizCrewDB` (account-wide), addon folder and name `TwizCrew`.
- Lua 5.1: no `goto`, no `//`, no bit operators, no `require`, no `io`, no `os` in addon code (tests may use them).
- Use modern API names (`C_ChatInfo`, `C_Timer`, `C_PartyInfo`, `C_AddOns`…). Any API that may be missing in
  Forever is called through `ns.Log.safe` or guarded with an existence check, with a fallback.
- Addon messages: at most 255 characters each; at most `SEND_PER_SECOND = 2` sends per second (burst 4); nothing is
  sent between `ENCOUNTER_START` and `ENCOUNTER_END` (held and sent after).
- `issecretvalue(v)` (if the function exists) is checked before using any GUID.
- No Lua errors may reach the screen: every event handler, timer callback and bus listener runs inside
  `ns.Log.safe(featureId, fn, ...)`.
- Unknown layer never shows as OTHER LAYER.
- Chat commands: `/tc` and `/twizcrew` (`/twiz` belongs to TwizTracker; never register it).
- Every module and every setting has a non-empty `info` text (enforced by `Modules.register`).
- Defaults: everything on, except **Play a sound** (off). Reset restores every module's settings and the panel
  position; it keeps the roster, the crew code (`db.crew`), the typed status and the log.
- Text that came from another player is passed through `ns.Util.safeText` before being shown (WoW treats `|` as
  an escape code).
- Nothing is published (no GitHub remote, no push, no release). Local git commits only. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Plain words in every string the player sees (the owner and friends are not technical).

## Review Focus

1. **Player names with a realm suffix or special letters** ("Holybøi", "Ginkan-Realm"): the same person must map to
   one roster row, and your own messages must be ignored. Test: Task 6 `receive_normalizes_realm_and_ignores_self`.
2. **Typed status containing separator or WoW escape characters** (`^ ~ = %` and `|T…|t`, `|cff…`): it must arrive
   unchanged and be shown as plain text. Tests: Task 4 `roundtrip_escapes_separators`, Task 1
   `safeText_escapes_pipes`.
3. **Messages from another version, or garbage** (protocol 2, unknown type, unknown fields, empty string, no `^`):
   ignored or partially used, never an error. Test: Task 4 `decode_tolerates_unknown_and_garbage`.
4. **Old or broken saved data** (`TwizCrewDB` nil, a number, `modules` missing, a setting of the wrong type, a
   module that no longer exists): repaired on load. Test: Task 3 `init_repairs_broken_saved_data`.
5. **Many friends at once** (12 crew members answering a HELLO in the same second): the send rate is never
   exceeded and the panel still shows everyone (scrolls past 8 rows). Tests: Task 5 `rate_never_exceeded_under_burst`,
   Task 11 `rows_scroll_past_max`.

## Design notes (decisions made while planning; the owner can overrule)

- **Layer comparison needs the same zone, not just the same continent** (spec section 10 says continent). Two
  friends are compared only when both report the same zone name; otherwise "unknown". This is stricter, so it can
  only show *fewer* OTHER LAYER tags, never wrong ones, and meeting up happens inside one zone anyway. The layer key
  is reset on every zone change.
- **Typed status is a crew-shared piece of data, not a setting**, so reset keeps it.
- **Pop-up deaths are not combined**; only layer pop-ups are (spec section 11 only asks to combine layer changes).
- **Choice settings use a click-to-cycle button**, not a dropdown, and the panel's right-click menu is our own small
  frame (fewer APIs that might be missing in Forever).
- **The hidden channel is joined 5 seconds after entering the world**, so it does not take the slot of the General or
  Trade channel.

## File map

```
twizcrew/
  .gitignore                      .superpowers/  tools/
  TwizCrew/                       the addon (this folder is what gets symlinked / shipped)
    TwizCrew.toc
    Core/Init.lua                 ns basics, ns.Config, clocks, player name
    Core/Util.lua                 pure helpers
    Core/Log.lua                  rolling log, ns.Log.safe, debug print
    Core/Events.lua               WoW event dispatcher (ns.Events) + internal bus (ns.Bus)
    Core/Modules.lua              module registry
    Core/DB.lua                   saved data init, repair, reset
    Comm/Codec.lua                message encode/decode (pure)
    Comm/Queue.lua                throttled send queue (pure)
    Comm/Transport.lua            channel / whisper / group / guild delivery, fallback
    Comm/Comm.lua                 send/receive pipeline, dedupe, handlers; registers module "comm"
    Crew/Roster.lua               crew members (pure)
    Crew/SelfState.lua            own state gather/diff/flush (ns.Self)
    Crew/Crew.lua                 HELLO/STATE/UPDATE/PING/BYE glue, offline ticker
    Core/Version.lua              version check; registers module "version"
    Tags/Tags.lua                 tag ids, labels, colors, detection; registers module "tags"
    Layer/LayerKey.lua            GUID parse, tracker, relation (pure)
    Layer/LayerSensor.lua         own layer key from NPCs (always runs: sharing is essential)
    Layer/Layer.lua               relations per friend; registers module "layer"
    UI/Theme.lua                  colors and fonts from the mockups
    UI/Widgets.lua                (i) button, toggle, slider, choice, text, menu, tag pill
    UI/ClassIcon.lua              class icon with fallbacks
    UI/PanelLogic.lua             pure row models, visibility, sorting glue
    UI/Panel.lua                  Crew panel; registers module "panel"
    UI/PopupLogic.lua             pure combine / quiet / text rules
    UI/Popups.lua                 pop-up frames; registers module "popups"
    UI/Extras.lua                 "coming later" extras: "pokes", "races"
    UI/Settings.lua               settings window + Options → AddOns entry
    UI/Report.lua                 /tc report text + copy box
    UI/Commands.lua               /tc, /twizcrew
    Core/Boot.lua                 ADDON_LOADED / PLAYER_LOGIN start-up (loads last)
  tests/
    run.lua  run.sh  wowstub.lua  test_*.lua
  docs/TESTING.md                 in-game checklist for the owner (Task 13)
```

TOC load order is exactly the order of the file map above (Init, Util, Log, Events, Modules, DB, Codec, Queue,
Transport, Comm, Roster, SelfState, Crew, Version, Tags, LayerKey, LayerSensor, Layer, Theme, Widgets, ClassIcon,
PanelLogic, Panel, PopupLogic, Popups, Extras, Settings, Report, Commands, Boot). Each task adds its own files to
the TOC.

## Shared names (used across tasks)

**`ns.Config`** (Core/Init.lua), the one place for tunable values:

```lua
PREFIX = "TwizCrew", PROTOCOL = 1,
DEFAULT_CHANNEL = "TwizCrewHQ", DEFAULT_PASSWORD = "goldshire",
CHANNEL_JOIN_DELAY = 5, CHANNEL_JOIN_TIMEOUT = 10, CHANNEL_FAILS_BEFORE_FALLBACK = 3,
PING_INTERVAL = 60, OFFLINE_AFTER = 180, OFFLINE_TICK = 15,
LAYER_STALE_AFTER = 600, LAYER_CONFIRMATIONS = 2, LAYER_TICK = 30,
POPUP_COMBINE_WINDOW = 3, LOGIN_QUIET = 30, POPUP_MAX = 5,
SELF_FLUSH_DELAY = 1, HELLO_JITTER_MIN = 0.5, HELLO_JITTER_MAX = 5,
SEND_PER_SECOND = 2, SEND_BURST = 4, DEDUPE_WINDOW = 2, MAX_MESSAGE = 255,
LOG_MAX = 500, STATUS_MAX = 40, BREAK_ERRORS = 3, BREAK_WINDOW = 60, PANEL_MAX_ROWS = 8,
```

**Wire field keys** (Codec, Roster, Self): `cl` class file ("WARRIOR"), `lv` level, `xp` XP percent 0–100,
`zn` zone, `sz` subzone, `st` typed status, `tg` tags ("DEAD,AFK"), `lk` layer key, `ins` "1"/"0" in instance,
`ver` addon version. Message types: `HELLO`, `STATE`, `UPDATE`, `PING`, `BYE`.

**Bus events** (`ns.Bus.fire(name, ...)`): `MEMBER_UPDATED(name, changes)`, `MEMBER_ONLINE(name)`,
`MEMBER_OFFLINE(name)`, `MEMBER_DIED(name, zone, subzone)`, `SELF_UPDATED(changes)`,
`LAYER_RELATION(name, old, new)`, `SETTING_CHANGED(id, key, value)`, `SETTINGS_RESET()`, `MODULE_TOGGLED(id, on)`,
`VERSION_NEWER(name, version)`.

**Module ids:** essentials `comm`, `version`; modules `panel`, `tags`, `layer`, `popups`; extras `pokes`, `races`.

**Tag ids:** `DEAD`, `LAYER`, `COMBAT`, `DUNGEON`, `TAXI`, `AFK` (this is also the priority order).

---

### Task 1: Repository, test runner, fake WoW API, TOC, Init and Util

**Files:**
- Create: `.gitignore`, `TwizCrew/TwizCrew.toc`, `TwizCrew/Core/Init.lua`, `TwizCrew/Core/Util.lua`
- Create: `tests/run.lua`, `tests/run.sh`, `tests/wowstub.lua`, `tests/test_util.lua`, `tests/test_lint.lua`

**Interfaces:**
- Produces (test harness): a test file returns `{ files = {...} | "toc", tests = { name = function(ns, A, W) end } }`.
  `files` are paths relative to `TwizCrew/`; `"toc"` loads every file listed in the TOC, in order. For each test the
  runner makes a fresh `W = Stub.new()`, a fresh `ns = {}`, loads each file with `loadfile`, `setfenv(chunk, W.env)`,
  calls `chunk("TwizCrew", ns)`, then the test. Assertions `A.eq(actual, expected, msg)` (deep), `A.ok(v, msg)`,
  `A.no(v, msg)`, `A.errors(fn, pattern)`, `A.contains(str, sub)`. Run: `tests/run.sh [pattern]`; last line
  `ALL PASSED (N tests)` and exit 0, or `FAILED k of N` and exit 1.
- Produces (stub): `W.env` (globals the addon sees: Lua std whitelist `string table math pairs ipairs next type
  tostring tonumber select unpack error assert pcall xpcall setmetatable getmetatable rawget rawset rawequal`, plus
  `print` captured into `W.printed`, plus the fake WoW API), `W.state` (editable game state, see below),
  `W:advance(seconds)` (moves `GetTime()` and `time()`, runs due `C_Timer` callbacks and tickers), `W:fire(event, ...)`
  (calls every frame that registered `event`), `W.sent` (list of `{prefix, text, chatType, target}`).
  Base fake API in this task: `GetTime`, `time`, `date`, `C_Timer.After`, `C_Timer.NewTicker` (returns object with
  `:Cancel()`), `CreateFrame` (permissive: `RegisterEvent`, `UnregisterEvent`, `SetScript`/`GetScript` work;
  `Create*` methods return new permissive objects; `Is*` return false; `Get*` return 0; anything else is a no-op),
  `UIParent`, `GameTooltip` (permissive), `UnitName("player") → W.state.player`, `GetRealmName`, `Ambiguate(name,
  "none")` (strips `-<W.state.realm>`, keeps other realms), `C_AddOns.GetAddOnMetadata(addon, "Version") →
  W.state.version`, `GetBuildInfo` (4th value `16001`), `SlashCmdList` (table), `InCombatLockdown`. `W.state` starts
  as `{ player="Twiz", realm="Realm", version="0.1.0" }`; later tasks add fields and fakes and say so.
- Produces (addon): `ns.ADDON` ("TwizCrew"), `ns.VERSION` (from TOC metadata, fallback "0.0.0"), `ns.Config` (values
  in Shared names), `ns.now() → number` (GetTime), `ns.wallclock() → number` (time()), `ns.playerName() → string`
  (Ambiguate of UnitName("player")).
- Produces (`ns.Util`, pure): `split(s, sep) → array` (keeps empty fields, `sep` is a plain single char),
  `trim(s) → string`, `copy(v) → deep copy`, `mergeDefaults(target, defaults) → target` (fills missing keys
  recursively; replaces a value whose type differs from the default's; never touches matching keys),
  `compareVersions(a, b) → -1|0|1` (numeric per dot part; missing parts are 0; non-numeric versions compare as 0),
  `truncateUTF8(s, maxChars) → string` (never cuts a multi-byte letter), `safeText(s) → string` (`|` → `||`),
  `ago(seconds) → string` ("just now" under 60 s, "5m ago", "2h ago", "3d ago").

- [ ] **Step 1: Get Lua 5.1.** `command -v lua5.1`. If missing, ask the owner to run `! sudo apt install lua5.1`.
  If they would rather not, build it without sudo: download `https://www.lua.org/ftp/lua-5.1.5.tar.gz` into
  `tools/` (new empty folder), `make posix` there, and `tests/run.sh` uses `tools/lua-5.1.5/src/lua` when
  `lua5.1` is not on the PATH. Expected: `lua5.1 -v` (or the tools path) prints `Lua 5.1.5`.
- [ ] **Step 2: `git init`** in the project root; `.gitignore` with `.superpowers/` and `tools/`.
- [ ] **Step 3: Write the runner, the stub and the failing tests.**

```lua
-- tests/test_util.lua   files = {"Core/Init.lua", "Core/Util.lua"}
split_keeps_empty_fields: A.eq(ns.Util.split("a^^b", "^"), {"a", "", "b"}); A.eq(ns.Util.split("", "^"), {""})
mergeDefaults_fills_and_repairs:
  local t = { a = 5, b = "wrong", nested = { x = 1 } }
  ns.Util.mergeDefaults(t, { a = 1, b = true, c = 3, nested = { x = 9, y = 2 } })
  A.eq(t, { a = 5, b = true, c = 3, nested = { x = 1, y = 2 } })
compareVersions_numeric: A.eq(ns.Util.compareVersions("1.10.0", "1.2.0"), 1)
  A.eq(ns.Util.compareVersions("1.2", "1.2.0"), 0); A.eq(ns.Util.compareVersions("0.9", "1.0"), -1)
  A.eq(ns.Util.compareVersions("abc", "0"), 0)
truncateUTF8_keeps_letters_whole: A.eq(ns.Util.truncateUTF8("Holybøi rocks", 6), "Holybø")
  A.eq(ns.Util.truncateUTF8("abc", 40), "abc")
safeText_escapes_pipes: A.eq(ns.Util.safeText("hi |TInterface\\x:0|t |cffff0000red"), "hi ||TInterface\\x:0||t ||cffff0000red")
ago_buckets: A.eq(ns.Util.ago(30), "just now"); A.eq(ns.Util.ago(300), "5m ago")
  A.eq(ns.Util.ago(7200), "2h ago"); A.eq(ns.Util.ago(3 * 86400), "3d ago")
init_reads_version_and_player: A.eq(ns.VERSION, "0.1.0"); A.eq(ns.playerName(), "Twiz"); A.eq(ns.Config.PREFIX, "TwizCrew")
```

```lua
-- tests/test_lint.lua   (runs in the runner's own environment, may use io)
every_lua_file_is_in_toc_and_exists     -- both directions; paths use "\" or "/" consistently in the TOC (use "\")
toc_has_required_lines                  -- "## Interface: 16001", "## SavedVariables: TwizCrewDB", "## Version: "
no_forbidden_lua                        -- after stripping comments and string literals, no "os.", "io.",
                                        -- "require", "goto", "//", "SLASH_.*= *\"/twiz\"" in any addon file
```

- [ ] **Step 4: Run** `tests/run.sh`. Expected: FAIL (Init/Util missing).
- [ ] **Step 5: Implement** `TwizCrew.toc` (Title `TwizCrew`, Notes `See what your crew is doing and which layer
  they're on. Type /tc`, Author `YaBoyTwiz`, Version `0.1.0`, SavedVariables `TwizCrewDB`, files Init and Util),
  `Core/Init.lua`, `Core/Util.lua`.
- [ ] **Step 6: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 7: Commit** `chore: test runner, fake WoW API, TOC, Init and Util`.

---

### Task 2: Log, safe calls, event dispatcher and bus

**Files:**
- Create: `TwizCrew/Core/Log.lua`, `TwizCrew/Core/Events.lua`, `tests/test_log_events.lua`
- Modify: `TwizCrew/TwizCrew.toc` (add both)

**Interfaces:**
- Consumes: `ns.Config.LOG_MAX`, `BREAK_ERRORS`, `BREAK_WINDOW`, `ns.now`.
- Produces `ns.Log`: `attach(lines)` (binds to the saved array `db.log`; before attach, lines go to a temporary
  array that is moved in on attach), `add(level, fmt, ...)` (level `"info"|"warn"|"error"|"debug"`; stores
  `"[HH:MM:SS] LEVEL text"`, keeps the newest `LOG_MAX`), `lines() → array`, `errors(n) → last n error lines`,
  `safe(featureId, fn, ...) → ok, ...` (catches errors with `xpcall`, logs them with the feature id and a traceback
  line if `debugstack` exists; after `BREAK_ERRORS` errors for the same feature within `BREAK_WINDOW` seconds calls
  `ns.Log.onBroken(featureId)` once), `onBroken` (assignable callback, default no-op; Task 3 sets it),
  `debug(fmt, ...)` (adds a `debug` line; also prints `TwizCrew: …` in chat when `ns.Log.chatDebug` is true).
- Produces `ns.Events`: `on(featureId, event, fn)` (fn receives `(...)` event args, runs inside `Log.safe(featureId)`),
  `off(featureId)` (removes every handler of that feature and unregisters events nobody else needs).
- Produces `ns.Bus`: `on(featureId, name, fn)`, `off(featureId)`, `fire(name, ...)` (each listener in `Log.safe`).

- [ ] **Step 1: Write the failing tests** (`files = {"Core/Init.lua","Core/Util.lua","Core/Log.lua","Core/Events.lua"}`)

```lua
log_keeps_newest_LOG_MAX: for i = 1, 510 do ns.Log.add("info", "n%d", i) end
  A.eq(#ns.Log.lines(), 500); A.contains(ns.Log.lines()[500], "n510"); A.contains(ns.Log.lines()[1], "n11")
log_attach_moves_early_lines: ns.Log.add("info", "early"); local saved = {}; ns.Log.attach(saved)
  A.contains(saved[1], "early")
safe_catches_and_logs: local ok = ns.Log.safe("layer", function() error("boom") end)
  A.no(ok); A.contains(ns.Log.errors(1)[1], "layer"); A.contains(ns.Log.errors(1)[1], "boom")
safe_breaks_after_three_in_window: local broken = {}; ns.Log.onBroken = function(id) broken[#broken+1] = id end
  for i = 1, 3 do ns.Log.safe("panel", error, "x") end
  A.eq(broken, {"panel"}); ns.Log.safe("panel", error, "x"); A.eq(#broken, 1)
safe_errors_spread_out_do_not_break: (3 errors, W:advance(61) between each) → broken stays empty
events_dispatch_and_off: ns.Events.on("a", "PLAYER_LOGIN", fn_counting); W:fire("PLAYER_LOGIN") → count 1
  ns.Events.off("a"); W:fire("PLAYER_LOGIN") → count still 1
events_handler_error_does_not_stop_others: two features on the same event, first errors, second still runs
bus_fire_reaches_listeners_and_off_removes: ns.Bus.on("x", "SETTINGS_RESET", fn); fire → called; off("x"); fire → not
```

- [ ] **Step 2: Run** `tests/run.sh log_events`. Expected: FAIL.
- [ ] **Step 3: Implement** Log and Events. One hidden frame does all WoW event registration.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: log with safe calls, event dispatcher, bus`.

---

### Task 3: Module registry and saved data (defaults, repair, reset)

**Files:**
- Create: `TwizCrew/Core/Modules.lua`, `TwizCrew/Core/DB.lua`, `tests/test_modules_db.lua`
- Modify: TOC

**Interfaces:**
- Consumes: `ns.Util.mergeDefaults`, `ns.Util.copy`, `ns.Log`, `ns.Events.off`, `ns.Bus`.
- Produces `ns.Modules`:
  - `register(def)` where `def = { id, name, tier = "essential"|"module"|"extra", info, defaultEnabled = true,
    comingSoon = false, defaults = { key = value }, settings = { { key, label, info, kind =
    "toggle"|"slider"|"choice"|"text", min, max, step, choices = { {value, label} }, parent = otherKey,
    store = "crew" } }, onEnable = fn(), onDisable = fn(), onSettingChanged = fn(key, value) }`. Errors (at load, so
    a builder sees it at once) if `id` is duplicate, `info` is empty, any setting lacks `info`, or a non-`store`
    setting has no default in `defaults`. Essentials are always enabled.
  - `list(tier) → array` (registration order), `get(id) → def`, `attach(db)`, `startAll()` (calls `onEnable` of
    every enabled module inside `Log.safe(id)`), `isEnabled(id) → bool` (false when broken), `setEnabled(id, on)`
    (ignored for essentials and comingSoon; calls onEnable/onDisable; `Events.off(id)` and `Bus.off(id)` on disable;
    fires `MODULE_TOGGLED`), `setting(id, key) → value`, `set(id, key, value)` (stores, calls `onSettingChanged`,
    fires `SETTING_CHANGED`), `resetAll()` (`DB.resetSettings`, then re-applies enable/disable per new state, calls
    `onSettingChanged` for every key, fires `SETTINGS_RESET`), `markBroken(id)` (session only: disables it and
    prints once `TwizCrew: <name> hit a problem and turned itself off. Type /tc report for details.`),
    `broken() → array of ids`. Sets `ns.Log.onBroken = ns.Modules.markBroken`. Essentials are never marked broken
    (only logged).
- Produces `ns.DB`: `init(saved, defs) → db` (accepts nil or any type; returns a repaired table shaped
  `{ schema = 1, modules = { [id] = { enabled = bool, settings = {...} } }, crew = { channel, password, extra = {} },
  roster = {}, log = {}, myStatus = "" }`; drops `modules[id]` entries for unknown ids; fixes wrong types via
  `mergeDefaults`), `resetSettings(db, defs)` (rebuilds `db.modules` from defaults only).
- Boot later does: `TwizCrewDB = ns.DB.init(TwizCrewDB, ns.Modules.list())`; `ns.db = TwizCrewDB`;
  `ns.Log.attach(ns.db.log)`; `ns.Modules.attach(ns.db)`.

- [ ] **Step 1: Write the failing tests** (loads Init, Util, Log, Events, Modules, DB; each test registers two fake
  modules: essential `core1` with `defaults = { debug = false }`, module `m1` with
  `defaults = { scale = 1, position = { point = "LEFT", x = 40, y = 100 } }`)

```lua
register_requires_info_everywhere: A.errors(function() ns.Modules.register({ id="x", name="X", tier="module", info="" }) end, "info")
  A.errors(function() ns.Modules.register({ id="y", name="Y", tier="module", info="ok", defaults={a=1},
    settings={{ key="a", label="A", kind="toggle" }} }) end, "info")
register_rejects_duplicate_id
init_from_nil_builds_defaults: local db = ns.DB.init(nil, ns.Modules.list())
  A.eq(db.modules.m1.settings.scale, 1); A.eq(db.modules.m1.enabled, true); A.eq(db.crew.channel, "TwizCrewHQ")
init_repairs_broken_saved_data:
  A.eq(ns.DB.init(42, ns.Modules.list()).schema, 1)
  local db = ns.DB.init({ modules = { m1 = { enabled = "yes", settings = { scale = "big" } }, gone = {} } }, ns.Modules.list())
  A.eq(db.modules.m1.settings.scale, 1); A.eq(type(db.modules.m1.enabled), "boolean"); A.no(db.modules.gone)
essentials_cannot_be_disabled: attach; setEnabled("core1", false); A.ok(ns.Modules.isEnabled("core1"))
setEnabled_calls_hooks_and_fires_bus
reset_restores_settings_keeps_crew_data:
  db.modules.m1.settings.scale = 2; db.modules.m1.settings.position.x = 999; db.modules.m1.enabled = false
  db.crew.channel = "Secret"; db.roster.Ginkan = { level = 14 }; db.myStatus = "brb"; db.log[1] = "x"
  ns.Modules.resetAll()
  A.eq(db.modules.m1.settings.scale, 1); A.eq(db.modules.m1.settings.position.x, 40); A.ok(db.modules.m1.enabled)
  A.eq(db.crew.channel, "Secret"); A.eq(db.roster.Ginkan.level, 14); A.eq(db.myStatus, "brb"); A.eq(#db.log, 1)
reset_fires_SETTINGS_RESET_and_onSettingChanged
markBroken_disables_and_prints_once: two markBroken("m1") → one line in W.printed containing "/tc report"
```

- [ ] **Step 2: Run** `tests/run.sh modules_db`. Expected: FAIL.
- [ ] **Step 3: Implement** Modules and DB.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: module registry and saved data with reset`.

---

### Task 4: Message codec

**Files:**
- Create: `TwizCrew/Comm/Codec.lua`, `tests/test_codec.lua`
- Modify: TOC

**Interfaces:**
- Consumes: `ns.Config.PROTOCOL`, `MAX_MESSAGE`, `ns.Util.split`.
- Produces `ns.Codec`:
  - `encode(msgType, fields) → array of strings`. Format `<protocol>^<TYPE>^<k>=<v>~<k>=<v>…`. In keys and values,
    `%`, `^`, `~`, `=` are escaped as `%25 %5E %7E %3D` (escape `%` first). Field order: sorted by key (stable output
    for tests). When the result would exceed `MAX_MESSAGE`, fields are spread over several messages: the first has
    `msgType`, the rest have type `UPDATE`; each ≤ `MAX_MESSAGE`. A single field too long on its own is cut with
    `Util.truncateUTF8` so it fits.
  - `decode(text) → msg | nil, reason` with `msg = { protocol = n, type = "STATE", fields = { k = v } }`. Returns
    nil for: empty, no `^`, non-numeric protocol, protocol greater than `PROTOCOL` with a type we don't know. Unknown
    types at our protocol → nil, "unknown type". Unknown field keys are kept (callers ignore them). A field without
    `=` is skipped.

- [ ] **Step 1: Write the failing tests** (`files = Init, Util, Codec`)

```lua
roundtrip_escapes_separators:
  local f = { st = "50% off ^_^ a~b c=d |Tx|t", zn = "Elwynn Forest", lv = "14" }
  local out = ns.Codec.encode("STATE", f); A.eq(#out, 1)
  A.eq(ns.Codec.decode(out[1]), { protocol = 1, type = "STATE", fields = f })
encode_is_stable: A.eq(ns.Codec.encode("PING", {})[1], "1^PING^")
long_state_splits_under_limit:
  local f = { st = string.rep("x", 40), zn = string.rep("Z", 120), sz = string.rep("S", 120), cl = "MAGE" }
  local out = ns.Codec.encode("STATE", f); A.ok(#out >= 2)
  for _, s in ipairs(out) do A.ok(#s <= 255) end
  A.eq(ns.Codec.decode(out[1]).type, "STATE"); A.eq(ns.Codec.decode(out[2]).type, "UPDATE")
  -- merging all decoded fields gives back f exactly
decode_tolerates_unknown_and_garbage:
  A.no(ns.Codec.decode("")); A.no(ns.Codec.decode("hello")); A.no(ns.Codec.decode("x^STATE^a=1"))
  A.no(ns.Codec.decode("2^NEWTHING^a=1")); A.no(ns.Codec.decode("1^NEWTHING^a=1"))
  A.eq(ns.Codec.decode("2^STATE^lv=3~zz=9~broken").fields, { lv = "3", zz = "9" })
```

- [ ] **Step 2: Run** `tests/run.sh codec`. Expected: FAIL.
- [ ] **Step 3: Implement** Codec. Known types: HELLO, STATE, UPDATE, PING, BYE.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: message codec`.

---

### Task 5: Throttled send queue

**Files:**
- Create: `TwizCrew/Comm/Queue.lua`, `tests/test_queue.lua`
- Modify: TOC

**Interfaces:**
- Produces `ns.Queue.new(opts) → q` with `opts = { perSecond, burst, now = fn }` (token bucket: starts full at
  `burst`, refills `perSecond` per second, never above `burst`). `q:push(item)` (any value, kept in order),
  `q:pump(sendFn) → number sent` (calls `sendFn(item)` while tokens ≥ 1 and not held; a `sendFn` returning `false`
  keeps the item at the front and stops this pump), `q:hold(on)` (held: pump sends nothing), `q:size() → n`.

- [ ] **Step 1: Write the failing tests** (`files = Init, Util, Queue`; `now` is a local variable the test moves)

```lua
burst_then_rate: push 10; pump at t=0 → 4 sent; t=0.5 → 1; t=1.0 → 1; t=10 → remaining 4 (bucket capped at 4)
hold_blocks_until_released: hold(true); push 2; pump → 0; hold(false); pump → 2
failed_send_keeps_item: first sendFn returns false → size unchanged, same item retried next pump
rate_never_exceeded_under_burst: push 12 items at t=0; pump every 0.1 s for 10 s, record send times;
  for every 1-second window starting at any send, sends ≤ 2 + 4 (burst); total sent = 12 by t=4.5
```

- [ ] **Step 2: Run** `tests/run.sh queue`. Expected: FAIL.
- [ ] **Step 3: Implement** Queue.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: throttled send queue`.

---

### Task 6: Transport and Comm (essential module "comm")

**Files:**
- Create: `TwizCrew/Comm/Transport.lua`, `TwizCrew/Comm/Comm.lua`, `tests/test_comm.lua`
- Modify: TOC, `tests/wowstub.lua`

**Interfaces:**
- Consumes: Codec, Queue, Modules, Events, Log, `ns.db.crew`, `ns.Config`.
- Adds to the stub: `C_ChatInfo.RegisterAddonMessagePrefix`, `C_ChatInfo.SendAddonMessage(prefix, text, chatType,
  target) → W.state.sendResult or 0` (records into `W.sent`), `Enum.SendAddonMessageResult = { Success = 0 }`,
  `JoinChannelByName(name, password)` (unless `W.state.channelJoinFails`, sets `W.state.channels[name] = 5`),
  `GetChannelName(name) → index or 0`, `ChatFrame_RemoveChannel` (records), `NUM_CHAT_WINDOWS = 10`,
  `_G.ChatFrame1..10` (permissive), `IsInGroup`, `IsInRaid`, `IsInGuild` (from `W.state.inGroup/inRaid/inGuild`),
  `W.state.groupMembers = {}` (names), `UnitInParty(name)`.
- Produces `ns.Transport`: `start()` (after `CHANNEL_JOIN_DELAY` s joins `db.crew.channel` with `db.crew.password`,
  removes it from all chat windows inside `Log.safe("comm")`; if not joined after `CHANNEL_JOIN_TIMEOUT` s, or after
  `CHANNEL_FAILS_BEFORE_FALLBACK` non-success send results, or on `CHAT_MSG_CHANNEL_NOTICE` "WRONG_PASSWORD" for
  our channel, marks the channel failed (logged with the reason; wrong password also prints once
  `TwizCrew: the crew code didn't work. Check it in /tc settings.`)), `destinations() → array of
  { chatType, target }` per mode `db.modules.comm.settings.transport`:
  - `"auto"`: channel joined and not failed → `{ {"CHANNEL", index} }`; else `{ {"PARTY"} or {"RAID"} }` when
    grouped, plus `{"WHISPER", name}` for every known crew name (roster names ∪ `db.crew.extra`) not in the group.
  - `"channel"`: channel only (empty if not joined). `"whisper"`: whispers only. `"group"`: PARTY/RAID only.
    `"guild"`: `{ {"GUILD"} }` if `IsInGuild()`, else falls back like auto.
  `send(text, dest) → bool` (calls `C_ChatInfo.SendAddonMessage`; result `0`/nil/true counts as success),
  `status() → { mode, channel, channelIndex, joined, failed, failReason, lastResult }`, `rejoin()` (used when the crew
  code changes).
- Produces `ns.Comm`: registers essential module `comm` (name "Crew connection"; settings `transport` choice
  `auto|channel|whisper|group|guild`, default `"auto"`; `channel` and `password` text with `store = "crew"`;
  `debug` toggle default false → sets `ns.Log.chatDebug`). `send(msgType, fields)` (encodes; for every message ×
  every destination pushes `{text, dest}` to one queue; a 0.2 s ticker pumps it through `Transport.send`),
  `on(msgType, fn(sender, fields))` (one handler list per type), `start()`. Receive path on `CHAT_MSG_ADDON(prefix,
  text, chatType, sender)`: ignore other prefixes; `sender = Ambiguate(sender, "none")`; ignore when it equals
  `ns.playerName()`; drop exact duplicates of `(sender, text)` within `DEDUPE_WINDOW` s; decode; call handlers in
  `Log.safe("comm")`; log at debug level. `ENCOUNTER_START` → `queue:hold(true)`; `ENCOUNTER_END` and
  `PLAYER_ENTERING_WORLD` → `queue:hold(false)`.

- [ ] **Step 1: Write the failing tests** (`files` = everything up to Comm; each test runs `DB.init`, `Modules.attach`,
  `Comm.start()`, `W:fire("PLAYER_ENTERING_WORLD")`)

```lua
joins_channel_after_delay_and_hides_it: W:advance(4) → no join; W:advance(2) → W.state.channels.TwizCrewHQ == 5,
  ChatFrame_RemoveChannel recorded for 10 frames; Transport.status().joined == true
send_goes_to_channel_when_joined: W:advance(6); Comm.send("PING", {}); W:advance(1)
  A.eq(W.sent[1].chatType, "CHANNEL"); A.eq(W.sent[1].target, 5); A.eq(W.sent[1].prefix, "TwizCrew")
falls_back_to_whispers_when_channel_fails: W.state.channelJoinFails = true; db.crew.extra = {"Ginkan","Frostie"}
  W:advance(16); Comm.send("PING", {}); W:advance(2)
  → two sends, chatType "WHISPER", targets Ginkan and Frostie; status().failed == true; log mentions the reason
fallback_after_bad_send_results: joined; W.state.sendResult = 3; three sends → status().failed; next sends whisper
grouped_fallback_uses_party_and_skips_whisper_to_party_members
holds_during_boss_fight: W:fire("ENCOUNTER_START"); send; advance → nothing sent; W:fire("ENCOUNTER_END"); advance → sent
receive_normalizes_realm_and_ignores_self:
  local got = {}; ns.Comm.on("PING", function(sender) got[#got+1] = sender end)
  W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Ginkan-Realm")
  W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Holybøi-OtherRealm")
  W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Twiz-Realm")
  W:fire("CHAT_MSG_ADDON", "Other", "1^PING^", "CHANNEL", "Ginkan-Realm")
  A.eq(got, { "Ginkan", "Holybøi-OtherRealm" })
receive_dedupes_same_text_within_window: same message via CHANNEL and PARTY → one handler call;
  again after W:advance(3) → second call
garbage_message_is_ignored_quietly: fire "nonsense" → no handler call, no error lines in log
```

- [ ] **Step 2: Run** `tests/run.sh comm`. Expected: FAIL.
- [ ] **Step 3: Implement** Transport and Comm.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: transport with fallbacks and comm pipeline`.

---

### Task 7: Roster

**Files:**
- Create: `TwizCrew/Crew/Roster.lua`, `tests/test_roster.lua`
- Modify: TOC

**Interfaces:**
- Consumes: `ns.Config.OFFLINE_AFTER`, `ns.Tags.decode` is **not** available yet: Roster stores `tg` decoded with
  its own local comma split into a set `{ DEAD = true }` (Task 8's `Tags.decode` must give the same shape).
- Produces `ns.Roster.new(saved) → r` (`saved` is `db.roster`; members found there start offline with
  `name, class, level, zone, subzone, lastSeen`). Member shape: `{ name, class, level, xp, zone, subzone, status,
  tags = set, layerKey, inInstance = bool, version, online = bool, lastHeard (session clock), lastSeen (wallclock) }`.
  - `r:apply(name, fields, now, wall) → member, changes, events`: maps wire keys to member fields (`lv`/`xp` to
    numbers; `ins` "1" → true; `lk` "" → nil); `changes` is a set of member field names whose value changed;
    `events` array may hold `"new"` (first time this name is seen at all), `"online"` (was offline or new),
    `"died"` (only if the member was already known with a tags value that lacked DEAD, and now has DEAD).
    Writes `name, class, level, zone, subzone, lastSeen` to `saved`.
  - `r:heard(name, now, wall) → events` (PING: marks online, `"online"` event if it was offline; unknown names are
    ignored; returns empty), `r:gone(name)` (BYE: offline now), `r:tick(now) → array of names that just went offline`
    (`now - lastHeard > OFFLINE_AFTER`), `r:get(name)`, `r:names() → array`, `r:members() → array`,
    `r:onlineCount() → online, total`, `r:sorted(mode, relationOf) → array` with modes `"name"` (A–Z, case-insensitive),
    `"level"` (high first, then name), `"online"` (online first, then name), `"layer"` (`relationOf(name) == "same"`
    first, then other online, then name); in every mode offline members come after online ones.

- [ ] **Step 1: Write the failing tests** (`files = Init, Util, Roster`)

```lua
apply_new_member: local m, ch, ev = r:apply("Ginkan", { cl="WARRIOR", lv="14", zn="Elwynn Forest", tg="" }, 10, 1000)
  A.eq(m.level, 14); A.ok(m.online); A.eq(ev, { "new", "online" }); A.eq(saved.Ginkan.level, 14)
apply_reports_only_changes: second apply with lv="14", zn="Westfall" → ch == { zone = true }, ev == {}
died_only_on_transition: apply tg="" then tg="DEAD" → ev contains "died"
  first-ever apply with tg="DEAD" → no "died"; apply tg="DEAD" again → no "died"
offline_after_timeout: apply at now=0; r:tick(179) → {}; r:tick(181) → {"Ginkan"}; m.online == false
  r:heard("Ginkan", 200, 2000) → {"online"}
saved_members_start_offline: Roster.new({ Stabz = { class="ROGUE", level=9, lastSeen=500 } }):get("Stabz").online == false
sort_modes: three online (Zed 10, amy 20, Bob 15) + offline Cat 60
  "name" → amy, Bob, Zed, Cat; "level" → amy, Bob, Zed, Cat; "layer" with Zed "same" → Zed, amy, Bob, Cat
heard_unknown_name_is_ignored
```

- [ ] **Step 2: Run** `tests/run.sh roster`. Expected: FAIL.
- [ ] **Step 3: Implement** Roster.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: roster`.

---

### Task 8: Tags, own state and crew glue (HELLO/STATE/UPDATE/PING/BYE)

**Files:**
- Create: `TwizCrew/Tags/Tags.lua`, `TwizCrew/Crew/SelfState.lua`, `TwizCrew/Crew/Crew.lua`, `tests/test_crew.lua`
- Modify: TOC (keep the file-map order; SelfState reaches `ns.Tags` and `ns.LayerSensor` only at call time, never
  at load time), `tests/wowstub.lua`

**Interfaces:**
- Adds to the stub: `UnitClass("player") → "Warrior", W.state.class`, `UnitLevel`, `UnitXP`, `UnitXPMax`,
  `GetRealZoneText`, `GetSubZoneText`, `IsInInstance() → W.state.inInstance, W.state.instanceType`,
  `UnitAffectingCombat`, `UnitIsDeadOrGhost`, `UnitOnTaxi`, `UnitIsAFK` (all from `W.state`). Defaults: class
  "WARRIOR", level 10, xp 0, xpMax 100, zone "Elwynn Forest", subzone "Goldshire", inInstance false, instanceType
  "none", the four flags false.
- Produces `ns.Tags`: `ORDER = {"DEAD","LAYER","COMBAT","DUNGEON","TAXI","AFK"}`, `LABEL = { DEAD="DEAD",
  LAYER="OTHER LAYER", COMBAT="FIGHTING", DUNGEON="DUNGEON", TAXI="FLYING", AFK="AFK" }`, `COLOR` (hex from the
  mockup: LAYER `b3261e`, COMBAT `c46a00`, DEAD `555555`, DUNGEON `2a4fc9`, TAXI `1f7a6a`, AFK `333333`), `INFO` (one
  plain sentence per tag, for tooltips), `detectSelf() → set` (never LAYER; COMBAT from `UnitAffectingCombat`, DEAD
  from `UnitIsDeadOrGhost`, DUNGEON when `IsInInstance()` type is `party` or `raid`, TAXI from `UnitOnTaxi`, AFK from
  `UnitIsAFK`), `encode(set) → string` (ORDER order, comma-separated), `decode(str) → set` (unknown ids dropped),
  `ordered(set) → array`. Registers module `tags` (name "Activity tags", no settings; display only).
- Produces `ns.Self`: `gather() → fields` (all wire keys; `xp` = floor(XP / max × 100), 0 when max is 0; `sz` =
  `"On a flight path"` while on a taxi; `st` = `db.myStatus`; `tg` = `Tags.encode(Tags.detectSelf())`; `lk` =
  `ns.LayerSensor and ns.LayerSensor.current() or ""`; `ins` "1"/"0"; `ver` = `ns.VERSION`),
  `diff(old, new) → changedFields` (pure: keys whose string values differ; keys missing in old count as changed),
  `refresh(reason)` (marks dirty; at most one flush scheduled `SELF_FLUSH_DELAY` s later; the flush gathers, diffs
  against the last sent fields, sends `UPDATE` with only the changes if any, fires `SELF_UPDATED(changes)`),
  `fullState() → fields` (also becomes the new "last sent"), `setStatus(text)` (trim, `truncateUTF8(STATUS_MAX)`,
  saves `db.myStatus`, refresh), `start()` (events: `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED`,
  `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED_INDOORS`, `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE`, `PLAYER_FLAGS_CHANGED`,
  `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`,
  `PLAYER_CONTROL_LOST`, `PLAYER_CONTROL_GAINED` → `refresh(event)`), `lastSent() → fields`.
  XP changes are only sent when the whole-number percent changes (falls out of `diff` on the floored value).
- Produces `ns.Crew` (feature id `comm`): `start()` creates `ns.roster = ns.Roster.new(db.roster)`; on login sends
  `HELLO {ver}` then `STATE` (fullState); on `HELLO` from someone: apply their `ver`, and reply `STATE` after a
  random delay between `HELLO_JITTER_MIN` and `HELLO_JITTER_MAX` s; on `STATE`/`UPDATE`: `roster:apply`, fire
  `MEMBER_UPDATED(name, changes)`, plus `MEMBER_ONLINE` / `MEMBER_DIED(name, zone, subzone)` from `events`; on
  `PING`: `roster:heard` (+ `MEMBER_ONLINE`); a `PING` from an unknown name → send our `HELLO` (so we learn them);
  on `BYE`: `roster:gone`, `MEMBER_OFFLINE`; ticker every `PING_INTERVAL` s sends `PING`; ticker every `OFFLINE_TICK`
  s runs `roster:tick` and fires `MEMBER_OFFLINE` for each; `PLAYER_LOGOUT` sends `BYE` best effort (direct
  `Transport.send`, no queue). Every received `ver` goes to `ns.Version.seen(name, ver)` if `ns.Version` exists.

- [ ] **Step 1: Write the failing tests** (`files = "toc"` from now on. Boot comes in Task 13, so each test does the
  start-up by hand: `ns.db = DB.init(nil, Modules.list())`, `Modules.attach(ns.db)`, `Comm.start()`, `Crew.start()`,
  `Self.start()`, `W:fire("PLAYER_ENTERING_WORLD")`, `W:advance(6)`)

```lua
tags_detect_and_encode: W.state.dead = true; W.state.afk = true
  A.eq(ns.Tags.encode(ns.Tags.detectSelf()), "DEAD,AFK"); A.eq(ns.Tags.decode("AFK,BOGUS,DEAD"), { AFK = true, DEAD = true })
  W.state.inInstance = true; W.state.instanceType = "party" → detectSelf().DUNGEON
self_diff_only_changes: A.eq(ns.Self.diff({ zn = "A", lv = "10" }, { zn = "B", lv = "10", st = "" }), { zn = "B", st = "" })
xp_sends_on_whole_percent_only: W.state.xp = 10 (10%) flush; W.state.xp = 10.4 → no UPDATE; 11 → UPDATE with xp=11
zone_change_sends_one_update: W.state.zone = "Westfall"; fire ZONE_CHANGED_NEW_AREA and ZONE_CHANGED; W:advance(2)
  → exactly one UPDATE in W.sent, decoded fields == { zn = "Westfall" } (subzone unchanged)
setStatus_trims_and_caps: ns.Self.setStatus("  " .. string.rep("é", 50) .. "  ") → db.myStatus is 40 letters
hello_gets_jittered_state_reply: W:fire CHAT_MSG_ADDON HELLO from "Ginkan" → nothing sent at once; within 5 s one STATE
state_from_friend_fills_roster_and_fires: STATE {cl=MAGE, lv=12, zn="Elwynn Forest", tg=""} from Frostie
  → ns.roster:get("Frostie").class == "MAGE"; MEMBER_UPDATED and MEMBER_ONLINE fired
friend_death_fires_MEMBER_DIED_with_place: UPDATE tg="DEAD" after STATE tg="" → MEMBER_DIED("Frostie", "Elwynn Forest", <sz>)
ping_from_stranger_triggers_hello
silence_marks_offline: STATE at t, W:advance(200) → MEMBER_OFFLINE("Frostie")
bye_marks_offline_now
```

- [ ] **Step 2: Run** `tests/run.sh crew`. Expected: FAIL.
- [ ] **Step 3: Implement** Tags, SelfState, Crew.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: tags, own state and crew messages`.

---

### Task 9: Version check (essential module "version")

**Files:**
- Create: `TwizCrew/Core/Version.lua`, `tests/test_version.lua`
- Modify: TOC

**Interfaces:**
- Consumes: `ns.Util.compareVersions`, `ns.VERSION`, Modules, Bus.
- Produces `ns.Version`: registers essential `version` (name "Version check"; setting `chatNotice` toggle, default
  true, info: tells you in chat when a friend has a newer version). `seen(name, ver)`: if `ver` is newer than ours
  and newer than the best seen so far, remember `{name, ver}` and fire `VERSION_NEWER`; the first time per session
  (and only if `chatNotice`) print exactly `TwizCrew: <name> has v<ver>, you have v<ours>. Update in WowUp.`
  `summary() → string`: `"everyone up to date"` or `"<name> has v<ver>, you have v<ours>. Update in WowUp."`.

- [ ] **Step 1: Write the failing tests**

```lua
older_or_same_is_quiet: seen("Ginkan", "0.1.0"); seen("Frostie", "0.0.9") → no print; summary() == "everyone up to date"
newer_prints_once_and_summarizes: seen("Ginkan", "0.2.0"); seen("Frostie", "0.3.0")
  → exactly one print "TwizCrew: Ginkan has v0.2.0, you have v0.1.0. Update in WowUp."
  summary() == "Frostie has v0.3.0, you have v0.1.0. Update in WowUp."
chatNotice_off_still_summarizes
```

- [ ] **Step 2: Run** `tests/run.sh version`. Expected: FAIL.
- [ ] **Step 3: Implement** Version.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: version check`.

---

### Task 10: Layer key, sensor and layer module

**Files:**
- Create: `TwizCrew/Layer/LayerKey.lua`, `TwizCrew/Layer/LayerSensor.lua`, `TwizCrew/Layer/Layer.lua`,
  `tests/test_layer.lua`
- Modify: TOC, `tests/wowstub.lua`

**Interfaces:**
- Adds to the stub: `UnitGUID(unit) → W.state.guids[unit]`, `issecretvalue(v) → W.state.secret[v] == true`.
- Produces `ns.LayerKey` (pure):
  - `fromGUID(guid) → zoneUID string | nil`: split on `-`; type (part 1) must be `Creature` or `Vehicle`; returns
    part 5 if it is all digits and not `"0"`; otherwise nil (players, pets, nil, malformed).
  - `newTracker(confirmations, staleAfter) → tr`: `tr:observe(zoneUID, now) → changed (bool)` (a new value becomes
    current only after `confirmations` observations of it in a row; observations of the current value refresh its
    time), `tr:current(now) → zoneUID | nil` (nil after `staleAfter` s without an observation of the current value),
    `tr:reset()`, `tr:info(now) → { key, age, pending }`.
  - `relation(me, them) → "same"|"different"|"unknown"`, both `{ lk, zn, ins, online }` (member-shaped tables:
    `layerKey`/`zone`/`inInstance`/`online` are accepted under these names: the caller passes
    `{ lk = m.layerKey, zn = m.zone, ins = m.inInstance, online = m.online }`): unknown if `them.online` is false,
    either `lk` is nil or "", either is in an instance, or zones differ or are missing; else same/different by `lk`.
- Produces `ns.LayerSensor` (feature id `comm`, always runs because sharing is essential): `start()` listens to
  `UPDATE_MOUSEOVER_UNIT` ("mouseover"), `PLAYER_TARGET_CHANGED` ("target"), `NAME_PLATE_UNIT_ADDED(unit)`; skips a
  GUID when `issecretvalue` exists and says it is secret; feeds `LayerKey.fromGUID` into a tracker made with
  `LAYER_CONFIRMATIONS`, `LAYER_STALE_AFTER`; on change → `Self.refresh("layer")`. Resets (then `Self.refresh`) on
  `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, and on `GROUP_ROSTER_UPDATE` when `IsInGroup()` flipped. A
  `LAYER_TICK` ticker refreshes when the key went stale. `current() → key | nil`, `info() → { key, age, pending,
  observations, secretSkipped }`.
- Produces `ns.Layer` (module `layer`, name "Layer tracker", no settings): keeps the last relation per name;
  recomputes for all members on `MEMBER_UPDATED`, `MEMBER_ONLINE`, `MEMBER_OFFLINE`, `SELF_UPDATED`; fires
  `LAYER_RELATION(name, old, new)` on change (first computed value counts as a change from "unknown").
  `relationOf(name) → relation` ("unknown" when the module is off). My own side for `relation` is
  `{ lk = LayerSensor.current(), zn = GetRealZoneText(), ins = select(1, IsInInstance()), online = true }`.

- [ ] **Step 1: Write the failing tests**

```lua
fromGUID_cases: A.eq(ns.LayerKey.fromGUID("Creature-0-4372-0-2345-299-0000ABCDEF"), "2345")
  A.eq(ns.LayerKey.fromGUID("Vehicle-0-4372-0-17-555-0000AB"), "17")
  A.no(ns.LayerKey.fromGUID("Player-4372-0ABCDEF")); A.no(ns.LayerKey.fromGUID("Pet-0-4372-0-2345-299-01"))
  A.no(ns.LayerKey.fromGUID("Creature-0-4372-0-0-299-01")); A.no(ns.LayerKey.fromGUID(nil)); A.no(ns.LayerKey.fromGUID("junk"))
tracker_needs_two_in_a_row: tr = newTracker(2, 600); observe("1", 0) → false, current nil
  observe("1", 1) → true, current "1"; observe("2", 2) → false, current "1"; observe("1", 3); observe("2", 4) → false
  observe("2", 5) → true, current "2"
tracker_goes_stale: current("2") at 5; tr:current(606) → nil
relation_rules: same zone & key → "same"; different key → "different"; them.online false → "unknown";
  zones differ → "unknown"; my lk nil → "unknown"; them.ins true → "unknown"
sensor_reads_mouseover_and_skips_secret: W.state.guids.mouseover = "Creature-0-1-0-111-299-01"
  fire UPDATE_MOUSEOVER_UNIT twice → LayerSensor.current() == "111"
  W.state.secret[W.state.guids.mouseover] = true; change guid to zone 222 and fire twice → still "111"; info().secretSkipped == 2
sensor_resets_on_zone_change: fire ZONE_CHANGED_NEW_AREA → current() nil
friend_on_other_layer_fires_relation: my key "111" in "Elwynn Forest"; STATE from Frostie lk=222 zn="Elwynn Forest"
  → LAYER_RELATION("Frostie", "unknown", "different"); then UPDATE lk=111 → LAYER_RELATION("Frostie", "different", "same")
layer_module_off_means_unknown: Modules.setEnabled("layer", false) → relationOf("Frostie") == "unknown"
```

- [ ] **Step 2: Run** `tests/run.sh layer`. Expected: FAIL.
- [ ] **Step 3: Implement** LayerKey, LayerSensor, Layer.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: layer tracker`.

---

### Task 11: Theme, widgets, class icon and the Crew panel (module "panel")

**Files:**
- Create: `TwizCrew/UI/Theme.lua`, `TwizCrew/UI/Widgets.lua`, `TwizCrew/UI/ClassIcon.lua`,
  `TwizCrew/UI/PanelLogic.lua`, `TwizCrew/UI/Panel.lua`, `tests/test_panel.lua`
- Modify: TOC, `tests/wowstub.lua`

**Interfaces:**
- Adds to the stub: `C_Texture.GetAtlasInfo(name) → W.state.atlases[name]`, `CLASS_ICON_TCOORDS` (WARRIOR, MAGE),
  `C_ClassColor.GetClassColor(classFile) → { r, g, b, GenerateHexColor = fn }`, `RAID_CLASS_COLORS`.
- Produces `ns.Theme` (from the mockups): backdrop color `0d0d12`, border `6b5a33`, title gold `ffd100`, muted
  `9a8f70`, text `f0e6c8`, XP bar `8a3fd1`; font objects `GameFontNormal`, `GameFontHighlightSmall`.
- Produces `ns.Widgets`: `infoButton(parent, title, text) → button` (small "(i)"; hover shows `GameTooltip` with
  title and wrapped text; click pins/unpins the same tooltip), `toggle(parent, label, info, get, set) → frame`,
  `slider(parent, label, info, min, max, step, get, set, fmt) → frame`, `choice(parent, label, info, choices, get,
  set) → frame` (button shows current label; click cycles; right-click cycles back), `text(parent, label, info, get,
  set) → frame` (edit box; saves on Enter or focus lost), `menu(anchor, items) ` (items `{ label, checked = fn|nil,
  onClick = fn }`; own small frame; closes on click outside or Escape), `tagPill(parent) → pill` with
  `pill:SetTag(tagId)` (label, color from `ns.Tags`, tooltip `ns.Tags.INFO`). Every widget takes `info` and builds
  its own `infoButton`.
- Produces `ns.ClassIcon`: `apply(texture, classFile) → method` tries atlas `"classicon-" .. lower(classFile)`
  (`C_Texture.GetAtlasInfo`), then `Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES` +
  `CLASS_ICON_TCOORDS[classFile]`, then hides the texture; returns `"atlas"|"texture"|"none"`; `method() →` the last
  method used (for the report); logs the method once per session.
- Produces `ns.PanelLogic` (pure):
  - `rows(members, settings, relationOf, tagsOn, now, wall) → array of row models { name, class, level, zoneText,
    status, xp, tags = array of tag ids, offline = bool, offlineText }`. `members` is already sorted. Drops offline
    members when `showOffline` is false. `zoneText` = `"Zone, Subzone"` (or just zone). `offlineText` =
    `"Offline, last seen " .. Util.ago(wall - lastSeen)`. `tags`: the member's tags (only if `tagsOn`, the tags
    module) plus `LAYER` when `relationOf(name) == "different"`, each filtered by `settings["tag_" .. id]`, ordered by
    `Tags.ORDER`. `name`, `zoneText`, `status` pass through `Util.safeText`.
  - `visible(settings, ctx) → bool` with `ctx = { inCombat, inInstance, onlineCount }`: false when
    `hideInCombat and inCombat`, `hideInInstance and inInstance`, `hideWhenAlone and onlineCount == 0`.
  - `window(rowCount, offset, maxRows) → first, last` (scroll window; offset clamped to valid range).
- Produces module `panel` (name "Crew panel", default enabled; hiding = turning it off). Defaults and settings, each
  with its own info text, in this order: `scale` 1.0 (slider 0.5–2.0 step 0.05), `bgAlpha` 0.8 (0–1 step 0.05),
  `rowStyle` "full" (choice full "Full" / compact "Compact" / tiny "Tiny"), `showZone` true, `showStatus` true,
  `showXP` true, `fadeOut` false, `fadeAlpha` 0.3 (slider 0.1–1, parent `fadeOut`), `locked` false, `grow` "down"
  (choice down/up), `hideInCombat` false, `hideInInstance` false, `hideWhenAlone` false, `showOffline` true, `sort`
  "online" (choice name/level/online/layer, labels "Name", "Level", "Online first", "Same layer first"),
  `showSelf` false, `tag_DEAD`, `tag_LAYER`, `tag_COMBAT`, `tag_DUNGEON`, `tag_TAXI`, `tag_AFK` all true;
  `position = { point = "LEFT", x = 40, y = 100 }` (no UI row). Row looks: Full = icon, name in class color, level,
  zone line, status line (in quotes, italic), XP bar; Compact = icon, name, level, tags; Tiny = icon, name, tags.
  Tags sit as pills on the frame's top-right corner. Header "TwizCrew" plus `"<online> of <total> online"`.
  Draggable when not locked (saves `position`); mouse wheel scrolls past `PANEL_MAX_ROWS`; right-click on the
  header opens `Widgets.menu` with: Show offline friends, Lock position, Row style (cycles), Hide during fights,
  Open settings, Hide panel. Redraw on `MEMBER_*`, `SELF_UPDATED`, `LAYER_RELATION`, `SETTING_CHANGED`,
  `SETTINGS_RESET`, `MODULE_TOGGLED`, `PLAYER_REGEN_*`, `PLAYER_ENTERING_WORLD`, and a 30 s ticker (for "last seen").
  `showSelf` adds my own row built from `Self.lastSent()`.

- [ ] **Step 1: Write the failing tests** (`files = "toc"`)

```lua
rows_full_model: members Ginkan (online, zone "Elwynn Forest", subzone "Goldshire", status "LF |cffDeadmines", tags {})
  → rows[1].zoneText == "Elwynn Forest, Goldshire"; rows[1].status == "LF ||cffDeadmines"
rows_add_layer_tag_and_filter: relationOf → "different", tags { COMBAT = true }
  → tags == { "LAYER", "COMBAT" }; with settings.tag_COMBAT = false → { "LAYER" }; with tagsOn false → { "LAYER" }
rows_hide_offline_when_off: offline Stabz lastSeen = wall - 7200 → offlineText "Offline, last seen 2h ago";
  showOffline false → not in rows
visible_rules: hideInCombat & inCombat → false; hideWhenAlone & onlineCount 0 → false; defaults → true
rows_scroll_past_max: window(12, 0, 8) → 1, 8; window(12, 10, 8) → 5, 12; window(5, 3, 8) → 1, 5
class_icon_fallbacks: atlas present → "atlas"; atlas missing → "texture"; unknown class and no atlas → "none"
panel_loads_and_draws_without_errors: full start-up by hand (as in Task 8) + Modules.startAll();
  feed 12 STATE messages; fire PLAYER_REGEN_DISABLED; Modules.set("panel", "rowStyle", "tiny"); resetAll()
  → ns.Log.errors(10) is empty
```

- [ ] **Step 2: Run** `tests/run.sh panel`. Expected: FAIL.
- [ ] **Step 3: Implement** Theme, Widgets, ClassIcon, PanelLogic, Panel.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: crew panel with widgets and class icons`.

---

### Task 12: Pop-ups (module "popups") and extras placeholders

**Files:**
- Create: `TwizCrew/UI/PopupLogic.lua`, `TwizCrew/UI/Popups.lua`, `TwizCrew/UI/Extras.lua`, `tests/test_popups.lua`
- Modify: TOC, `tests/wowstub.lua`

**Interfaces:**
- Adds to the stub: `C_PartyInfo.InviteUnit(name)` (records into `W.invites`), `PlaySound(id)` (records),
  `SOUNDKIT = { RAID_WARNING = 8959 }`.
- Produces `ns.PopupLogic` (pure):
  - `new({ combineWindow, quietUntil }) → pl`; `pl:push(kind, name, now, extra)` with kind `"layer_diff"`,
    `"layer_same"`, `"death"` (`extra = { zone, subzone }`); during quiet (`now < quietUntil`) every push is dropped.
  - `pl:due(now) → array of popups { kind, names, extra, invite }`: a death is due at once, one popup each; layer
    pushes of the same kind are combined, due `combineWindow` s after the first one of the batch; a name pushed as
    `layer_diff` then `layer_same` inside one batch cancels out. `invite` = names for `layer_diff`, nil otherwise.
  - `pl:endQuiet(differentNames) → popup | nil` (one combined `layer_diff` when the list is non-empty).
  - `PopupLogic.text(kind, names, extra, colorName) → text, subtext` with exact copy:
    - layer_diff: 1 → `"%s is on a different layer"`; 2 → `"%s and %s are on a different layer"`; 3+ →
      `"%d friends are on a different layer"`; subtext `"Click to invite them to your group"`.
    - layer_same: `"%s is back on your layer"`, `"%s and %s are back on your layer"`, `"%d friends are back on your
      layer"`; no subtext.
    - death: `"%s died"`; subtext `"Zone, Subzone"` (or zone alone; none when both missing).
    `colorName(name)` wraps a name (class color) and defaults to identity.
- Produces module `popups` (name "Pop-ups"). Defaults/settings: `layerDiff` true ("Layer changes"), `layerSame` true
  ("Back on my layer"), `death` true ("Deaths"), `sound` **false** ("Play a sound"), `seconds` 5 (slider 2–15 step 1,
  "How long they stay"). Listens to `LAYER_RELATION`
  (`same`/`unknown` → `different` pushes `layer_diff`; `different` → `same` pushes `layer_same`; filtered by settings)
  and `MEMBER_DIED`. `quietUntil` = time of `PLAYER_LOGIN` + `LOGIN_QUIET`; at the end of quiet calls `endQuiet` with
  every name whose `Layer.relationOf` is "different". A 0.5 s ticker shows due pop-ups: up to `POPUP_MAX` frames
  stacked down from the top centre, each `seconds` long, then a 0.5 s fade. Layout per the mockup (dark box, coloured
  left edge: layer red `b3261e`, back green `3fd34a`, death grey `888888`). Click on a `layer_diff` pop-up →
  `C_PartyInfo.InviteUnit(name)` for each name not already in the group (fallback global `InviteUnit`), then closes
  it. Sound (when on): `PlaySound(SOUNDKIT.RAID_WARNING)` once per shown pop-up batch.
- Produces `UI/Extras.lua`: registers extras `pokes` ("Pokes & soundboard") and `races` ("Group races"), both
  `comingSoon = true`, `defaultEnabled = false`, info text saying they are coming later.

- [ ] **Step 1: Write the failing tests**

```lua
text_copy: A.eq(PopupLogic.text("layer_diff", {"Frostie"}), "Frostie is on a different layer")
  A.eq(select(2, PopupLogic.text("layer_diff", {"Frostie"})), "Click to invite them to your group")
  A.eq(PopupLogic.text("layer_diff", {"A","B"}), "A and B are on a different layer")
  A.eq(PopupLogic.text("layer_same", {"A","B","C"}), "3 friends are back on your layer")
  A.eq({ PopupLogic.text("death", {"Holyboi"}, { zone = "Westfall", subzone = "Jangolode Mine" }) },
       { "Holyboi died", "Westfall, Jangolode Mine" })
combines_within_window: push diff A at 0, diff B at 1 → due(2) == {}; due(3) → one popup names {A, B}, invite {A, B}
diff_then_same_cancels: push diff A at 0, same A at 1 → due(4) == {}
deaths_are_immediate_and_separate: two deaths → due(now) gives two popups
quiet_drops_then_summarizes: quietUntil 30; pushes at 5 → dropped; endQuiet({"A","B","C"}) → names {A,B,C}
popups_end_to_end: full start-up, login, W:advance(31); friend relation goes different → after 3 s a popup frame
  is shown (Popups.visibleCount() == 1); click it (Popups.clickForTest(1)) → W.invites == {"Frostie"}
sound_off_by_default: after a popup, no PlaySound recorded; set sound true → recorded
setting_off_suppresses: Modules.set("popups", "death", false) → MEMBER_DIED shows nothing
```

`Popups.visibleCount()` and `Popups.clickForTest(i)` are small test hooks on `ns.Popups`.

- [ ] **Step 2: Run** `tests/run.sh popups`. Expected: FAIL.
- [ ] **Step 3: Implement** PopupLogic, Popups, Extras.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `feat: pop-ups for layer changes and deaths`.

---

### Task 13: Settings window, report, commands, boot, two-copy simulation, install and test checklist

**Files:**
- Create: `TwizCrew/UI/Settings.lua`, `TwizCrew/UI/Report.lua`, `TwizCrew/UI/Commands.lua`, `TwizCrew/Core/Boot.lua`,
  `tests/test_ui.lua`, `tests/test_sim.lua`, `docs/TESTING.md`
- Modify: TOC, `tests/wowstub.lua`, `tests/run.lua` (multi-client helper), `PROJECT.md`

**Interfaces:**
- Adds to the stub: `Settings.RegisterCanvasLayoutCategory(frame, name) → category`,
  `Settings.RegisterAddOnCategory(category)` (both recorded; `W.state.noSettingsAPI` removes them).
- Produces `ns.Settings` (feature id `settings`, part of the essentials, not a registered module): `open()`,
  `close()`, `toggle()`, `confirmReset()`, `rebuild()`. Window "TwizCrewSettings" per the mockup: header "TwizCrew",
  `"v" .. ns.VERSION .. " · " .. ns.Version.summary()`; sections in order **Essentials** ("always on, these make the
  rest work"; each module shows "always on" instead of a switch), **Modules** ("turn on or off"; a switch per
  module), **Extras** ("fun stuff, added over time"; grayed switch, "coming later"). Each module and each setting
  shows its (i) button; a setting with `parent` is indented and greyed while the parent toggle is off; `store =
  "crew"` settings read/write `ns.db.crew` and on change call `Transport.rejoin()`. Scrolls when taller than the
  screen. Footer: Close; **Reset everything to defaults** → inline confirm `"Reset all TwizCrew settings and the panel
  position?"` Yes / No → `Modules.resetAll()`. Rebuilds on `SETTINGS_RESET`, `MODULE_TOGGLED`, `VERSION_NEWER`.
  Options → AddOns: a canvas with the text `"TwizCrew has its own settings window."`, a button `"Open TwizCrew
  settings"` and `"Or type /tc"`, registered inside `Log.safe("settings")` (skipped and logged if the API is missing).
- Produces `ns.Report`: `lines() → array of strings` with, in order: `"TwizCrew v<ver>, interface <n>"`,
  `"Connection: <mode> (channel <name> joined|not joined|failed: <reason>)"`, `"Layer: key <key|none>, seen <ago>,
  <secretSkipped> hidden values skipped"`, `"Class icons: <method>"`, `"Turned off after errors: <ids|none>"`, one line
  per crew member `"<name>: <online|offline>, heard <ago>, v<ver>"`, then `"Recent errors:"` and the last 10 error
  lines (or `"none"`). `show()` opens a copy box (multi-line edit box with the text selected, "Press Ctrl+C to copy").
- Produces `ns.Commands`: `parse(msg) → cmd, rest` (cmd lowercased first word, rest trimmed, case kept). Registers
  `SLASH_TWIZCREW1 = "/tc"`, `SLASH_TWIZCREW2 = "/twizcrew"`. Commands: `""` → `Settings.toggle()`; `show` / `hide` →
  `Modules.setEnabled("panel", true|false)`; `status <text>` → `Self.setStatus(text)` + `TwizCrew: status set to
  "<text>"`; `status` alone → clears + `TwizCrew: status cleared`; `reset` → `Settings.open()` +
  `Settings.confirmReset()`; `report` → `Report.show()`; `debug` → toggles `comm.debug` + prints on/off; `add <name>`
  / `remove <name>` → `db.crew.extra` (for the whisper fallback) + confirmation; anything else or `help` → a short
  list of commands, one line each, plain words.
- Produces `ns.Boot`: on `ADDON_LOADED` for "TwizCrew": `DB.init`, `Log.attach`, `Modules.attach`,
  `C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)`; on `PLAYER_LOGIN`: `Comm.start`, `Crew.start`, `Self.start`,
  `LayerSensor.start`, `Modules.startAll`, then one chat line `TwizCrew v<ver> loaded. Type /tc for settings.`.
- Produces in `tests/run.lua`: `H.client(name) → W, ns` (a full TOC load in its own stub, `W.state.player = name`),
  `H.link(...)` (every `SendAddonMessage` of one client is delivered as `CHAT_MSG_ADDON(prefix, text, chatType,
  sender .. "-Realm")` to the others when the chat type is CHANNEL, PARTY/RAID or a WHISPER to that client),
  `H.advance(seconds)` (advances all clients together).

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/test_ui.lua (files = "toc", after a Boot start-up: fire ADDON_LOADED "TwizCrew", PLAYER_LOGIN)
parse_commands: A.eq({ ns.Commands.parse("  Status  LF Deadmines ") }, { "status", "LF Deadmines" }); A.eq({ ns.Commands.parse("") }, { "", "" })
slash_registered_without_twiz: W.env.SLASH_TWIZCREW1 == "/tc"; no global SLASH_* equals "/twiz"
status_command_sets_and_clears: SlashCmdList.TWIZCREW("status brb food") → db.myStatus == "brb food"; "status" → ""
hide_show_panel: "/tc hide" → not isEnabled("panel"); "/tc show" → isEnabled
report_lines_cover_health: Report.lines() first line "TwizCrew v0.1.0, interface 16001"; contains "Connection:",
  "Layer:", "Class icons:", "Turned off after errors: none", "Recent errors:"
settings_builds_and_resets_without_errors: Settings.open(); Modules.set("panel","scale",1.5); Settings.confirmReset()
  then the Yes action → setting("panel","scale") == 1; ns.Log.errors(10) empty
missing_settings_api_is_logged_not_fatal: W.state.noSettingsAPI = true → start-up completes, a warn/error line mentions "settings"
login_line_printed: W.printed contains "TwizCrew v0.1.0 loaded. Type /tc for settings."
```

```lua
-- tests/test_sim.lua (two or three clients with H.client / H.link)
two_friends_see_each_other: Twiz and Frostie log in; H.advance(10) → Twiz's roster has Frostie (class, level, zone)
  and Frostie's has Twiz; both panels report "1 of 1 online" (PanelLogic over roster)
zone_change_reaches_friend: Frostie's W.state.zone = "Westfall" + ZONE_CHANGED_NEW_AREA; H.advance(2) → Twiz sees "Westfall"
other_layer_tag_and_popup: both in "Elwynn Forest"; Twiz mouseovers "Creature-0-1-0-111-…" twice, Frostie "…-222-…"
  twice; H.advance(35) → Twiz: Layer.relationOf("Frostie") == "different"; a layer pop-up was shown;
  then Frostie sees 111 twice → H.advance(5) → relation "same", "back on your layer" pop-up shown
death_popup: Frostie W.state.dead = true + PLAYER_DEAD; H.advance(3) → Twiz shows "Frostie died"
status_with_odd_characters_arrives_intact: Frostie /tc status "50% ^_^ |Tx|t" → Twiz roster status equals it exactly;
  panel row status is the safeText version
channel_failure_falls_back_to_whispers: both with channelJoinFails; each has the other in db.crew.extra;
  H.advance(20) → they still see each other; Report.lines() says the channel failed and gives the reason
newer_version_is_announced: third client "Pewpew" with W.state.version = "0.2.0" → Twiz printed
  "TwizCrew: Pewpew has v0.2.0, you have v0.1.0. Update in WowUp."
no_errors_anywhere: after all of the above, every client's ns.Log.errors(50) is empty
```

- [ ] **Step 2: Run** `tests/run.sh "ui|sim"`. Expected: FAIL.
- [ ] **Step 3: Implement** Settings, Report, Commands, Boot and the multi-client helper.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: `ALL PASSED`.
- [ ] **Step 5: Link the addon into the game.**
  `ln -s /home/yaboytwiz/Documents/GitHub/twizcrew/TwizCrew "/home/yaboytwiz/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/TwizCrew"`.
  Then check that Lutris (a Flatpak) can see the target:
  `flatpak info --show-permissions net.lutris.Lutris | grep -i filesystems`. If `~/Documents` (or `home`) is not
  listed, **stop and ask the owner** before changing anything; the two options are
  `flatpak override --user --filesystem=/home/yaboytwiz/Documents/GitHub/twizcrew:ro net.lutris.Lutris`, or a small
  `tools/sync.sh` that copies `TwizCrew/` into the AddOns folder instead of a link. Expected: `ls -la` on the AddOns
  folder shows `TwizCrew` and its `TwizCrew.toc` is readable through the link.
- [ ] **Step 6: Write `docs/TESTING.md`** for the owner, in plain words: how to check the interface number, what to
  try alone (panel shows, `/tc`, settings, (i) buttons, reset, `/tc status`, `/tc report`), what to try with one
  friend (they appear, zone updates, OTHER LAYER after both mouse over a few NPCs in the same zone, pop-ups,
  invite-click pulls them over, death pop-up, a boss fight doesn't break anything), and what to send back: "type
  `/reload`, then tell Claude", because the log is in
  `…/_forever_/WTF/Account/*/SavedVariables/TwizCrew.lua`; friends paste `/tc report`.
- [ ] **Step 7: Update `PROJECT.md`**: "Where we are" (v1 built, not yet tested in game, not published), the log
  file path above, the link or sync method chosen, and that testing with friends needs the owner's go-ahead to
  publish (and the final name).
- [ ] **Step 8: Run** `tests/run.sh` once more. Expected: `ALL PASSED`.
- [ ] **Step 9: Commit** `feat: settings window, report, commands, boot; simulation tests; in-game checklist`.

## Changes during build

- **Login messages wait for the connection.** The hidden channel is joined 5 s after start, so the `HELLO`/`STATE`
  sent at login had nowhere to go and were lost. Now, while the connection is still being set up, messages are
  kept and sent as soon as the channel is joined (or the whisper fallback is chosen).
- **Lint check for `/twiz`** runs on the source with comments removed but strings kept (with strings removed it
  could never find anything).
- **Pop-up quiet time after login** starts when the pop-ups module is switched on at login, instead of on a
  `PLAYER_LOGIN` listener that is registered too late to hear the event.
- **Test stub** exposes `_G` (addon code looks up `ChatFrame1..10` through it).
- **No "player not found" spam when whispering.** In the whisper fallback, whispering a friend who is offline makes the
  game print "No player named X is currently playing." in chat. TwizCrew now remembers who it whispered in the last 10
  seconds and hides that one line for those names. Other system messages are untouched.
