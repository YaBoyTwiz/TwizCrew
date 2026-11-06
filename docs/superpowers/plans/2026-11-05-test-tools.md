# TwizCrew: test tools ("Try it out") — Plan

**Owner's request (after v0.1.2):** the riskiest untested things were a ding firing once on a real level-up,
"Lv 12 · 63%" fitting on the rows, and XP numbers matching the friend's own XP bar. The owner: "those things most
likely to break, can we test them, in the addon add a way to test". The owner usually tests alone.

Builds on the earlier plans; their Global Constraints and "Changes during build" still hold.

## Global Constraints

- Lua 5.1, every action inside `ns.Log.safe("testtools", ...)`, TDD, local commits only, no version bump.
- **No new addon files and no `.toc` change**, so a `/reload` is enough for anyone on v0.1.2.
- **Fake data is never sent and never saved.** Nothing goes over Comm, no whisper, channel or party message and
  no party invite is caused by a test entry; nothing fake lands in `db.roster`, the stats store, session data,
  `db.update` or `db.updateNotice`. The version list and "Tell crew to update" ignore fakes.
- Test tools failing must never break the real addon.

## Design (Claude's calls; the owner can overrule)

1. **Fake names can never be real names.** Every fake name ends in " (test)" (`ns.isTestName`). Real character
   names have no spaces or brackets, and every real sender goes through `ns.shortName`, which keeps only what comes
   before the first space, so a real friend can never land on a fake row. The "(test)" shows on the row, in the
   tooltip and in pop-ups.
2. **Fakes live in the real roster, marked by their name**, so the panel, tooltip, layer tag and pop-ups use the
   real code. `Roster:apply` never writes a fake into the saved list; `Roster:members()` and `Roster:names()` leave
   fakes out unless asked (`members(true)`), so every sending, saving, stats and version path stays fake-free by
   default. Only the panel (`sorted`, `onlineCount`) and the layer tracker ask for fakes.
3. **The real receive path.** Fake messages are built with `Codec.encode`, then handed to `Comm.inject(name,
   text)`, which decodes them and calls the same handlers friends' messages go through (it only accepts fake
   names, and skips the transport and the duplicate check). Handlers that would answer or save ignore fake senders:
   the crew session (no reshare, no session data), the stats detectors (pulls, wipes).
4. **Pop-ups for fakes only when a button asks.** A fake's events (it appearing, its XP ticking) show no pop-ups
   unless a test button expects one (and Testbuddy's own level-up while XP ticks, which is the "one ding" check).
   Expected test pop-ups skip the 30 s login quiet time. Clicking a fake's layer pop-up invites nobody.
5. **Where it lives:** `UI/Report.lua` (with `/tc report`, the other "is it working?" tool), registered as a new
   settings tier **"tools"**, shown as the last section **"Try it out"**: always there (not a switch), but it can
   turn itself off after errors like a module. Why not a module: there is nothing to switch off when no button is
   pressed. Why not under Essentials: it is not needed for the rest to work.
6. **Buttons** (each with an (i)), and matching `/tc test …` commands:
   - **Fake friends** (`/tc test fake`): Testbuddy (paladin, level 12, 63%, rested XP, Hillsbrad Foothills, a
     status, FIGHTING + AFK + OTHER LAYER tags), Maxbuddy (rogue, max level) and Offbuddy (druid, offline, last seen
     2 hours ago). Testbuddy earns XP every 20 s, so "About N min to level" shows after about 3 minutes, and it
     levels up by itself after about 7 minutes (one ding). Pressing again starts them over.
   - **Copy of me** (`/tc test copy`): "My copy (test)", built from `Self.gather()` → `Codec.encode` → `Comm.inject`;
     it follows every UPDATE you send (`SELF_UPDATED`), so it shows what friends see. Press again to remove it.
   - **Ding** (`/tc test ding`): Testbuddy goes up one level through the real path; the real ding pop-up shows.
   - **Death pop-up**, **Layer pop-up** (alternates "back on your layer" / "on a different layer"), **Roast pop-up**
     (a different roast each press) (`/tc test death|layer|roast`).
   - **Update notice (reload)** / **Update notice (restart)** (`/tc test update reload|restart`): Testbuddy says it
     has the next version; the gold "!", the gold panel line and the how-to window show through the real code.
     The pretend version is kept apart from real ones (`Version`'s test overlay) and the "shown" mark stays in memory.
   - **Clear test stuff** (`/tc test clear`): removes every fake row, the pretend update (badge, line, window) and
     stops the timers. Reset to defaults and `/reload` clear too.
7. **`/tc report`** gets one line, `Test tools: …`, saying what fake things are on, so a report never confuses a
   fake for a friend.

## Tasks

1. Roster: fake names, never saved, left out of `members()` / `names()` by default, `remove`.
2. `Comm.inject`; Session, Detectors and Popups ignore or limit fakes; Version test overlay; Updates in-memory mark.
3. The tools (fixtures, XP ticker, copy follower, pop-up buttons, update buttons, clear), the "tools" tier and the
   "Try it out" section, `/tc test` and its help, the report line.
4. Tests: nothing fake reaches `W.sent` or the saved data (also after clear and logout), every button through the
   real code, the panel in every row style, the copy's numbers, one ding in the quiet time.
5. `docs/TESTING.md` rewritten so the owner can do the risky checks alone; PROJECT.md line.

## Changes during build

- **"My copy" pops up like a friend would** (added; not in the brief): while it is on, your real level-ups and
  deaths give "My copy (test) reached level N!" / "My copy (test) died". Why: that makes the riskiest check (one
  ding on a real level-up) doable alone, through the same path a friend's copy uses. Cost if wrong: a pop-up about
  yourself on stream while the copy is on.
- **The copy is called "My copy (test)", not "<your name> (test)":** `ns.shortName` of the latter is your own name,
  so `ns.isMe` would take the fake for you.
- **Fake friends makes three** (the optional two included): Testbuddy, Maxbuddy (max level) and Offbuddy (offline,
  "last seen 2h ago"). Maxbuddy carries version 0.0.9, so a test proves the version list and "Tell crew to update"
  do not count fakes.
- **Fakes count as online on the panel** ("2 of 3 online") and in the minimap tooltip's "Crew online", because both
  read `Roster:onlineCount`. Cost: a test row counts as a friend there while it is on.
- **The debug log keeps test lines** ("test tools: fake pressed", "layer Testbuddy (test): unknown -> different"):
  the log is the one saved place a fake name can appear, on purpose, so Claude can tell test actions apart when
  reading it. Cost if wrong: one more place to clean.
- **Logout scrub:** at logout the tools also remove any fake name from `db.roster` and the stats lists, whatever
  happened (nothing should be there).
- **The Roast button tells why nothing showed** (roasts off, or one about Testbuddy less than 10 s ago) by looking at
  `Roasts.forTest.shown()` (a hook that was only used by tests).
- **Pop-up buttons say when a switch hides them** ("Level-ups pop-ups are off…", "Update reminders is turned off…",
  "the Crew panel is hidden…") instead of doing nothing silently.
- **A pretend update over a real one:** the pretend version is the next one after ours or after the newest real one
  heard, so it always shows; Clear brings the real notice back. Pressing an update button while a real update
  window is open replaces that window (the real one comes back at the next notice or a click on the gold line).
- **Tests:** `tests/test_testtools.lua` (29 tests, including two copies where the friend never hears about fakes, a
  logout, and a reload from the saved data) and 4 roster tests. Each guard (session reshare, session fields, roster
  save, roster lists, invite, update "told", update "shown", pop-up gate) was removed once to check a test catches
  it; the whisper test was made stricter after that showed a gap (the transport shortens "Testbuddy (test)" to
  "Testbuddy", a real player's name). No earlier test changed.
- **Release note for Claude:** no files added, `.toc` unchanged: a `/reload` is enough after the next release
  (`RESTART_SINCE` stays `0.1.1`). The owner's own copy (the AddOns link) needs only a `/reload`.
