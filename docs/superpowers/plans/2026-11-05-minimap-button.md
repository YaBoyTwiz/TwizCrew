# TwizCrew: minimap button — Implementation Plan

**Goal (owner):** "create a button ui that stays on the minimap so people can edit it without needing to do the /tc
command". A round TwizCrew button on the edge of the minimap: left-click opens the `/tc` settings window, right-click
shows or hides the Crew panel, hover shows "TwizCrew", the click hints and how many crew are online. Players drag it
around the minimap edge. A "Show minimap button" setting (on by default) hides it; `/tc minimap` brings it back. The
same clicks are in the game's addon compartment (the AddOns list on the minimap) when the client has one.

Builds on v1 (`docs/superpowers/specs/2026-11-05-crew-panel-design.md`; its section 3 listed "a minimap button" as a
later extra) and the three earlier plans; their Global Constraints and "Changes during build" still hold.

## Global Constraints

- Everything in the v1 plan's Global Constraints (Lua 5.1, `/tc` only, every module and setting has `info`, every
  handler inside `ns.Log.safe`, local commits only, plain words).
- `tests/run.sh` must end with `ALL PASSED`, including all 431 earlier tests.
- Plain frames only (no secure templates), no libraries (no LibDBIcon, no LibStub).
- **Release note for Claude:** this adds two files and three `.toc` lines, so the release that ships it must set
  `RESTART_SINCE` (in `TwizCrew/Core/Init.lua`) to the new version and say "restart the game" in the release notes.
  Versions are not bumped here.

## Design notes (Claude's calls; the owner can overrule)

1. **Tier: Essentials**, as "Minimap button" (always on) with one switch under it, **Show minimap button**. Why: it
   is a way into the settings, like the settings window itself, which is an essential. An essential module is never
   switched off after errors, so its own switch is the only thing that hides it. Cost if wrong: none for players; it
   would only move to the Modules list.
2. **Reset to defaults** shows the button again and puts it back at the default angle (both are module defaults,
   so the existing reset handles them).
3. **Default angle 190°** (left edge, just below the middle; 0° = right, counter-clockwise). Questie and
   DungeonJournal sit at 225° and What's Training? at about 304° on this PC. Cost if wrong: it covers a game icon
   until dragged once.
4. **Icon:** `Interface\Icons\Ability_Warrior_BattleShout` ("rally the crew"), an icon from the original game that
   modern clients still have. One constant, `ns.Config.MINIMAP_ICON`; the `.toc`'s `## IconTexture` (used by the
   addon compartment) must say the same, a test checks it. If the game says the picture is missing, the button uses
   the question-mark icon and `/tc report` says so. Cost if wrong: a question mark until the constant changes.
5. **Look:** the game's own minimap-button pieces (`MiniMap-TrackingBorder` ring, `UI-Minimap-Background`,
   `UI-Minimap-ZoomButton-Highlight`), the same as other Forever addons on this PC use.
6. **Round and square minimaps:** `GetMinimapShape()` (set by minimap addons; missing = round). Round parts of the
   minimap put the button on the circle; square parts put it on the square's edge (corners included). All the
   usual shape names are known; an unknown name counts as round.
7. **Drag** moves the button live; the angle is saved once, when the drag ends. An error while dragging ends the
   drag instead of repeating every frame.
8. **Clicks:** left-click = `/tc` (opens, or closes when open). Right-click = `/tc show` / `/tc hide`, without the
   chat line (the panel appearing or vanishing is the answer; the "turned off after errors" line still shows).
   The settings window is a plain frame, so it opens during fights; if opening fails, one short chat line.
9. **`/tc minimap`** turns the button on or off and says which, so a player who hid it can bring it back.
10. **Addon compartment:** `## AddonCompartmentFunc`, `...FuncOnEnter`, `...FuncOnLeave` in the `.toc`, pointing at
    three global functions with the same clicks and tooltip. Clients without the compartment ignore those lines and
    never call the functions; the code never touches the compartment itself.
11. **`/tc report`** gets one last line: `Minimap button: shown at 190°, icon ok` (older lines keep their places).

## File map

```
TwizCrew/Core/Init.lua          + ns.Config.MINIMAP_ICON, MINIMAP_ANGLE
TwizCrew/UI/MinimapLogic.lua    pure: angle clean-up, angle -> x/y (round / square / mixed shapes), cursor -> angle,
                                tooltip lines
TwizCrew/UI/MinimapButton.lua   essential "minimap": the button, drag, clicks, tooltip, compartment globals
TwizCrew/UI/Commands.lua        + /tc minimap, help line, Commands.setPanel(on, quiet)
TwizCrew/UI/Report.lua          + last line
TwizCrew/TwizCrew.toc           + the two files (before UI\Commands.lua), IconTexture, AddonCompartmentFunc lines
tests/wowstub.lua               + Minimap, GetCursorPosition, GetMinimapShape (hideable)
tests/test_minimaplogic.lua     pure rules
tests/test_minimap.lua          module, button, drag, clicks, compartment, /tc minimap, reset, .toc lines
```

## Tasks

1. Pure logic (`MinimapLogic`) with tests first.
2. Fake game: `Minimap`, `GetCursorPosition`, `GetMinimapShape`.
3. `MinimapButton.lua` + `.toc` + `/tc minimap` + report line, tests first.
4. Docs: `docs/TESTING.md` (riskiest first), one line in `PROJECT.md`.

## Changes during build

(filled in while building)
