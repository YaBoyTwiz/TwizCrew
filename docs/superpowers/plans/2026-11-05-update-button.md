# TwizCrew: "Tell crew to update" button — Implementation Plan

**Goal:** One button in the `/tc` settings window tells every online friend that a newer TwizCrew is out. Friends on
an older version get a small window: "Twiz says v0.2.0 is out", a **Reload now** button and "If nothing changed, open
WowUp and click Update first" (or "Close and restart the game to load it" when the new version added files). After
the reload, a friend who is still old gets one gentle line in chat. The settings window lists every crew member's
version with a tick or a cross.

**Approved description:** `PROJECT.md`, section "Tell crew to update" (owner approved 2026-11-05). Builds on v1
(`docs/superpowers/specs/2026-11-05-crew-panel-design.md`, `docs/superpowers/plans/2026-11-05-crew-panel.md`) and
the stats board plan; their Global Constraints and "Changes during build" still hold.

## Global Constraints

- Everything in the v1 plan's Global Constraints (Lua 5.1, `/tc` only, every module and setting has `info`,
  `ns.Util.safeText` on text from friends, every handler inside `ns.Log.safe`, local commits only, plain words).
- `tests/run.sh` must end with `ALL PASSED`, including all 375 earlier tests.
- `ReloadUI()` is only ever called from a click on **Reload now**, never from a timer or a message, and never while
  the player is in a fight.
- A request is only accepted from someone in your crew list whose version (in the request) is newer than yours.

## Design notes (Claude's calls; the owner can overrule)

1. **The version lives in the Lua code, next to RESTART_SINCE** (`Core/Init.lua`): `ADDON_VERSION` and
   `RESTART_SINCE`. The `## Version` line in `TwizCrew.toc` must say the same (a test checks it). Why: the game
   reads the `.toc` only when it starts (reported), so after a `/reload` the `.toc` version may still be the old
   one while the Lua files are already new. A version read from the `.toc` would then say "Still on v0.1.0" to a
   friend who did update. The `.toc` version is still read (`ns.TOC_VERSION`) and shown in `/tc report`.
   Cost if wrong: none for players; the release maker bumps two lines instead of one (a test catches a mismatch).
2. **Restart check after a reload:** when the `.toc` version the game loaded is older than `RESTART_SINCE`, the game
   is running the new code with an old file list, so new files did not load. TwizCrew prints once: "TwizCrew vX
   added new files. Close and restart the game to finish the update." Cost if wrong: a line that never shows (if
   the game re-reads the `.toc` at `/reload`, both versions always match).
3. **Where things live:** the button and the version list sit under **Version check** (Essentials), so anyone can
   send and see versions. Receiving is the new module **Update reminders** (tier *Modules*, on by default, can be
   turned off): the pop-up and the line after a reload. A module switch controls what *you see* (v1 rule), so
   sending is not part of it. Reset to defaults turns Update reminders back on (it is a normal module).
4. **Message:** a new type `UPDREQ` with `ver` (sender's version) and `rs` (sender's RESTART_SINCE). Old copies
   ignore unknown types. It goes through `ns.Comm.send` (queue, rate limit, boss-fight hold, waits for the channel).
5. **Button cooldown 30 s** (`UPDATE_BUTTON_COOLDOWN`). Pressing it again sooner prints how long to wait. The chat
   line says how many online friends are known to be behind.
6. **Repeats:** the same version is shown at most once every 10 minutes (`UPDATE_REPEAT_GAP = 600`), from anyone.
   A newer version shows at once. Kept for this play session only.
7. **Fights:** a request that arrives during a fight waits and shows when the fight ends. If a fight starts while
   the window is open, **Reload now** is greyed out and a click only prints "Not during a fight. Click Reload now
   again when the fight is over."
8. **Saved:** `db.update = { told = "0.2.0", by = "Twiz", rs = "0.1.0", at = <wallclock> }`, written when the
   pop-up shows. At the next login (5 s after, so it is not lost in the login lines), if our version is still older
   than `told`, print once: "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then /reload" (or "…, then
   restart the game" when a restart is needed). Then it is forgotten either way (one gentle line, not a nag; the
   Version check's own line still says when a friend is newer). Not touched by reset to defaults (it is not a
   setting).
9. **Tick and cross:** the game's default font has no ✓ / ✗ letters, so the list uses the game's ready-check
   icons (green tick, red cross) through texture codes. ✓ = same as or newer than the newest version seen (yours
   and every crew member's this session); ✗ = older; offline or unknown = "?". You are listed first ("you").

## File map

```
TwizCrew/Core/Init.lua         ADDON_VERSION, RESTART_SINCE, ns.VERSION, ns.TOC_VERSION, new Config values
TwizCrew/Core/UpdateLogic.lua  pure rules: accept, restart, prompt text, after-login line, version rows, cooldown
TwizCrew/Core/Version.lua      + "Tell crew to update" button row and "Crew versions" list row (with (i))
TwizCrew/Core/Modules.lua      + setting kinds "button" and "list" (no default, never saved)
TwizCrew/Core/DB.lua           + db.update
TwizCrew/Comm/Codec.lua        + UPDREQ
TwizCrew/UI/Settings.lua       + draws "button" and "list" rows; redraws the list when versions change
TwizCrew/UI/Updates.lua        module "updates": UPDREQ in/out, the pop-up window, after-login line
TwizCrew/UI/Report.lua         + .toc version and the last update request in /tc report
tests/test_updates.lua         pure rules, module, window, settings rows
tests/test_sim.lua             old copy + new copy: accepted one way, ignored the other
tests/test_lint.lua            .toc version == ADDON_VERSION
```

## Tasks

1. Version constants, `.toc` lint, `compareVersions` cases (`1.2.10` vs `1.2.9`). Test harness can give a client
   another code version.
2. `UpdateLogic` (pure) with tests.
3. Codec `UPDREQ`, `db.update`, setting kinds `button` / `list`, settings rows.
4. `UI/Updates.lua`: sending, receiving, pop-up, fights, after-login line, report lines.
5. Simulation: old and new copy. In-game checks in `docs/TESTING.md`. `PROJECT.md`.

## Changes during build

- **Version formats:** `Util.compareVersions` ignores a leading `v` and text after a number (`1.2.3-beta` counts as
  `1.2.3`); `1.2.10` is newer than `1.2.9`. A version from a friend is only used when it is plain numbers and dots
  (`Util.isVersion`, at most 20 characters).
- **Settings registry gained two kinds:** `button` (needs `onClick`) and `list` (needs `lines()`). They hold no value,
  need no default and are never saved, so reset has nothing to do for them. A list row is as tall as its lines; the
  settings window lays itself out again while open when a friend comes, goes or changes version.
- **The after-login check runs even when Update reminders is off,** but then only for the "added new files, restart
  the game" line (a half-loaded addon matters more than the switch). The "Still on" line follows the switch.
  `db.update` is read and cleared at login, and the line is printed 5 s later, so a request heard in the first
  seconds after login is kept for the next login instead of being mixed up with the old one.
- **An older request never replaces a newer window** that is still open (e.g. two friends on different new versions).
- **The window's second button** says "Later" (with Reload now) or "OK" (restart case). Escape closes it; it can be
  dragged.
- **`/tc report`** has a new line `Update: addon list says v…, restart needed since v…, last request heard: …`, placed
  after the stats lines so the older lines keep their places.
- **Tests:** in the multi-client helper, `state.version` / `state.restartSince` now stand for another release's code
  (the constants in `Core/Init.lua`); the fake game's addon list reads `state.tocVersion` (falls back to
  `state.version`). No earlier test changed.
- **After the review (one fix wave):**
  - The Crew versions list is laid out again on the next open when a friend came, went or changed version while the
    settings window was closed (before, the rows below it could overlap).
  - A request only feeds the Version check ("X has vY…") when it comes from the crew list with a plain version, so a
    stranger's whisper cannot put a fake version in the settings window.
  - An older request never replaces a newer one held during a fight (same rule as for an open window).
  - The request handler runs under the module's own error guard ("updates"), so repeated errors turn Update
    reminders off instead of repeating inside the essential connection.
  - The window's texts are pinned at their top corners (a `RIGHT` point would also pin the middle and squash them).
    v1's pop-ups and the settings subtitle use the old way; noted for the in-game check, not changed.
  - The `.toc` version also tries the old global `GetAddOnMetadata` when `C_AddOns` is missing.
  - The button's (i) text says that friends who turned Update reminders off, or whose copy is too old, get nothing.
