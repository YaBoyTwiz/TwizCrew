# TwizCrew: update notice and version number — Implementation Plan

**Goal (owner):** "can we make it so its easy for users to know when there is an update and easy update? also can
we make it show the version number". What Claude told the owner we'd build:

1. **Version number in more places:** the Crew panel title ("TwizCrew v0.1.1") and the minimap button tooltip. The
   settings subtitle and the login line already show it.
2. **Hard-to-miss update notice** whenever a crew member runs a newer version than you (learned from `ver` in
   HELLO / STATE, as today): a small gold "!" on the minimap button, a tooltip line "Update available: vX (Name has
   it)", a gold "Update available: vX" line on the Crew panel, and a small pop-up **once per new version**. Badge and
   line go away once you are on that version or newer. "Update reminders" off = no pop-up, no badge, no line (the
   version number stays).
3. **"How to update" in that pop-up:** HELLO and STATE also carry `rs` (that copy's RESTART_SINCE). Restart needed
   or unknown (older copies send no `rs`): "Close WoW, open WowUp and click Update, then start WoW again." (no
   Reload button). Otherwise: "Open WowUp and click Update, then press Reload now" with **Reload now** (the existing
   reload code: never in a fight, remembers the version so the after-login "Still on vOld" line works).
4. **README:** step 3 becomes WowUp auto-update plus starting WowUp with the computer, minimised.

Builds on the earlier plans (crew panel, stats board, update button, minimap button); their Global Constraints and
"Changes during build" still hold.

## Global Constraints

- Lua 5.1, every handler inside `ns.Log.safe`, plain words, local commits only, no version bump, no release.
- `tests/run.sh` ends with `ALL PASSED`, including the 475 earlier tests.
- A failure in the notice never breaks the panel, comms or the minimap button: they ask `ns.Updates.available()`
  inside `ns.Log.safe("updates", ...)` and treat an error as "no update".
- STATE stays within the codec limits (255 bytes per piece); the long-STATE codec tests keep passing.
- **No new files in the addon and no `.toc` change**, so this alone does not need a game restart. (The minimap button,
  which added files, already shipped in v0.1.1 with `RESTART_SINCE = "0.1.1"`.)

## Design notes (Claude's calls; the owner can overrule)

1. **One pop-up system.** The notice reuses the "Tell crew to update" window (`UI/Updates.lua`): same frame, same
   Reload now / Later / OK buttons, same fight rules. A request carries `kind = "notice"` to pick the words.
2. **Once per version, saved:** `db.updateNotice.shown` = the newest version a pop-up (notice or Tell crew) was shown
   for. A notice only shows for a newer version than that. Not touched by reset to defaults (not a setting).
3. **Tell crew wins:** the notice waits **30 s** after the newer version is first heard (`UPDATE_NOTICE_DELAY`), so a
   quick "Tell crew to update" press shows its window instead, and that counts as shown. A Tell crew request that
   arrives while the notice window is open takes the same window over (never two windows). Tell crew otherwise
   works as before (its own 10-minute repeat rule), even after the notice was closed: the owner pressing the
   button is a deliberate nudge. Cost if wrong: a friend may see the window twice for one version, once from the
   notice and once when the owner presses the button much later.
4. **The newest version** comes from `ns.Version`: a new list of plain-number versions only (`Util.isVersion`), so a
   junk version from a broken copy cannot hide a real one. `rs` is kept per crew member in the roster (a long STATE
   may split `ver` and `rs` into two pieces); `rs` learned later for the same version fills it in.
5. **Unknown `rs` = restart** (owner's rule). It is stored as `rs = ver` for the after-login line, which then says
   "restart the game" too.
6. **Panel:** the version sits after "TwizCrew" in the small grey font. Tiny row style leaves it out (the header
   is only 176 px wide there). The update line is a gold row under the header in every style; clicking it opens
   the how-to window again (the pop-up only comes once on its own).
7. **Minimap:** a gold "!" in the button's top-right corner; the tooltip title becomes "TwizCrew v0.1.1" and its
   last line, in gold, "Update available: v0.2.0 (Frostie has it)". The addon compartment tooltip shows the same.
8. **Chat:** the Version check's own "X has vY, you have vZ. Update in WowUp." line still follows its "Tell me in
   chat" setting and nothing else.
9. **`/tc report`:** the `Update:` line also says the newest version heard and the newest notice shown.

## File map

```
TwizCrew/Core/Init.lua         + UPDATE_NOTICE_DELAY
TwizCrew/Core/DB.lua           + db.updateNotice
TwizCrew/Core/UpdateLogic.lua  + available, availableText, showNotice, notice (pure)
TwizCrew/Core/Version.lua      + plain newest version with rs, Version.newest(), event UPDATE_SEEN
TwizCrew/Crew/Roster.lua       + rs -> member.restartSince
TwizCrew/Crew/Crew.lua         HELLO sends rs; passes ver + rs to Version.seen
TwizCrew/Crew/SelfState.lua    STATE sends rs
TwizCrew/UI/Updates.lua        notice timer, kind = "notice", Updates.available(), Updates.showHowTo(), saved "shown"
TwizCrew/UI/PanelLogic.lua     + titleVersion(style, version)
TwizCrew/UI/Panel.lua          version after the title, gold update line (click = how-to window)
TwizCrew/UI/MinimapLogic.lua   tooltipLines(..., info) with version and update line
TwizCrew/UI/MinimapButton.lua  gold "!" badge, refreshed on UPDATE_SEEN / MODULE_TOGGLED
README.md                      step 3: WowUp auto-update, launch with system, minimized
tests/                         updatelogic, version, crew, updates, panel, minimap(logic), sim (old + new copy)
```

## Tasks

1. Pure logic (`UpdateLogic`, `PanelLogic.titleVersion`, `MinimapLogic.tooltipLines`) with tests first.
2. Wire: `rs` in HELLO / STATE, roster, `Version.newest()`.
3. `Updates.lua`: notice, saved "shown", Tell crew wins, `available()`, `showHowTo()`.
4. Panel and minimap.
5. Simulation: a new copy and an old copy (one pop-up, badge, words for `rs`, nothing again after a /reload).
6. Docs: README, `docs/TESTING.md`, `PROJECT.md`.

## Changes during build

- **The notice's wait starts again with each news** (a newer version heard, or its `rs` learned), instead of one
  timer: a test showed that the timer started when the module turned on at login could cut the 30 s short.
- **`rs` lives in the roster** (`member.restartSince`) and Crew passes the roster's `ver` and `rs` to
  `Version.seen(name, ver, rs)`, because a long STATE can bring them in two pieces. A HELLO without `rs` (an older
  copy) clears it. The longest possible STATE was checked: every piece stays within 255 bytes.
- **Tell crew windows keep their old words** ("If nothing changed, open WowUp and click Update first" / "Close and
  restart the game to load it"); only the notice uses the new how-to words. Why: "works as before", and its
  existing tests stay as they were. Cost if wrong: two slightly different wordings for the same advice.
- **The window is 8 px taller** (112) so the notice's two-line text fits above the buttons.
- **The panel line** is a thin button with a faint gold background; hover says "Click for how to update". It also
  sits above the Hall of Shame tabs when stats are on.
- **`/tc report`'s `Update:` line** ends with `newest heard: v… from … (restart since v… / unknown), pop-up shown
  for: v…` (its test was updated).
- **Two earlier minimap tests changed:** the tooltip title is now "TwizCrew v0.1.0" instead of "TwizCrew".
- **Release note for Claude:** no files were added or removed and the `.toc` did not change, so this work alone does
  not need a game restart. Correction (Claude, at review): the minimap button already shipped in v0.1.1, so the
  next release keeps `RESTART_SINCE = "0.1.1"` and a /reload is enough for anyone on v0.1.1. Friends on v0.1.1 send
  no `rs`; that only matters to copies that are older still.
