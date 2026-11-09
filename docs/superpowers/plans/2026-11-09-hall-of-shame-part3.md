# Hall of Shame upgrade, part 3 (awards show on everyone's screen, Clown of the Night vote) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/tc awards` plays on every online crew member's screen, following the presenter's clicks; after the last
award the crew votes for Clown of the Night, who gets a title on the Crew tab and a special trophy.

**Architecture:** Pure rules in a new `UI/ShowLogic.lua` (card wire form, streak wording, vote tally). The existing
`UI/AwardsShow.lua` gets two roles: **presenter** (today's show; it now also sends one message per card it reveals,
the vote start, the vote result and a close) and **viewer** (opened by those messages; it shows what the presenter
sends and never advances on its own clicks). The vote card is a new phase of the same window. The clown is saved in
`db.stats.clown` and becomes a Crew-tab title and a `clown` entry in that session's trophy record.

**Tech Stack:** Lua 5.1 WoW addon; tests with `tests/run.lua` / `tests/wowstub.lua`. On Windows:
`tools/lua51/lua5.1.exe tests/run.lua [pattern]` → `ALL PASSED (N tests)`.

**Spec:** `docs/superpowers/specs/2026-11-09-hall-of-shame-upgrade-design.md`, sections 7 and 8.

## Global Constraints

- **The starter is the presenter**: only their clicks move the show; everyone follows. The presenter's copy decides
  the winners and sends **one message per card as it is revealed** (award id, winner names, value text, streak). No
  message per frame or per second.
- A viewer in a fight: their show waits and catches up to the current card when the fight ends.
- Viewers can close it with Escape. Setting (stats module): "Show the crew's awards show on my screen" (on).
- No card change from the presenter for **60 seconds**: the show closes on every screen (presenter included).
- Cards mention streaks: "…and for the 3rd session in a row, Lurabe!" (session view only).
- Vote: after the last award, a vote card on every screen in the show, a button per person who was in the session,
  in class colour; **no voting for yourself**; 30 seconds; while voting only "4 of 6 voted"; reveal "Clown of the
  Night: **Twiz** (4 votes)"; a tie = co-clowns; nobody voted = no clown; the presenter has a **Skip** button.
- The winner gets **"Clown of the Night"** under their name on the Crew tab until the next show, and a special trophy.
- Older copies ignore the new message types (they're simply not in their codec list): nothing breaks.
- Never test a game value before `issecretvalue`; fake crew members (`ns.isTestName`) never vote, are never
  candidates, never send.
- Plain words in everything a player reads. New file goes in the TOC (`UI\ShowLogic.lua` before `UI\AwardsShow.lua`);
  the release must set `RESTART_SINCE`.
- Commit after each task; messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions made while planning (Claude's call)

- **Messages** (add all to `KNOWN_TYPES` in `TwizCrew/Comm/Codec.lua`):
  - `AWS` show starts: `id` (show id = "<presenter>-<wallclock>"), `v` ("session" | "all").
  - `AWC` a card: `id`, `i` (card number), `k` ("award" | "nobody" | "end"), for awards `a` (award id), `w` (winner
    names, comma), `x` (value text), `s` (streak number, only when ≥ 2), `r = "1"` when it jumps straight to the
    reveal (the presenter clicked during the drumroll), `m` (how many winners were left out of `w` so the card fits
    one message; shown as "and N more"). repeatKeys: `id`, `i`.
  - `AWV` vote starts: `id`, `c` (candidate names, comma), `t` (seconds, "30").
  - `AWB` a vote: `id`, `c` (the name voted for). Sent to everyone so every screen can count "N voted".
  - `AWR` vote result: `id`, `w` (clown names, comma; empty = nobody), `n` (votes), or `k = "skip"`.
  - `AWX` the presenter closed the show: `id`.
- Messages are accepted only from known crew members (like the calendar's `known(sender)`), and a viewer follows only
  the show it opened (same `id`); a second `AWS` from someone else while one is open is ignored.
- **Streak** shown on a card = the winner's current streak for that award from `Trophies.summary()` + 1 (this
  session isn't recorded yet). Shown only when that makes 2 or more, only in the session view, only for a single
  winner. Wording: "…and for the 2nd/3rd/4th… session in a row".
- **Vote count**: the presenter counts the votes it receives (one per voter, the first counts) plus its own; the
  result in `AWR` is the presenter's count, so every screen shows the same reveal. Voters = candidates (people in the
  session) except the person voting. "N of M voted": M = number of candidates. The presenter sends `AWR` after 30 s
  or as soon as every candidate who is online has voted.
- **Candidates** = the real names in `StatsStore.entries("session", sid)` (session view) — for an all-time show,
  there is no vote (the show ends after the last award).
- **Clown saved** on every screen that saw `AWR`: `db.stats.clown = { names = {...}, sid = <session id>, at = wall }`.
  Crew-tab title: a clown's title is "Clown of the Night" (overrides award titles) until a later `AWR` replaces it.
  Trophy: `Trophies.sessionEnded(sid)` adds `winners.clown = names` (only names in that record's people) when
  `db.stats.clown.sid == sid`. The special trophy is defined in `StatsDefs.EXTRA_TROPHIES = { { id = "clown", name =
  "Clown of the Night", icon = "Interface\\Icons\\INV_Misc_Bandana_03" } }`; every lookup that turns an award id into
  a name/icon (TrophyLogic known ids, BoardLogic trophy rows, Trophies.lineFor) checks `EXTRA_TROPHIES` too.

## File map

- Create `TwizCrew/UI/ShowLogic.lua` — Task 1.
- Modify `TwizCrew/UI/AwardsShow.lua` — Tasks 2-4.
- Modify `TwizCrew/Comm/Codec.lua` (`KNOWN_TYPES`) — Task 2.
- Modify `TwizCrew/Stats/Stats.lua` (setting `crewShow`) — Task 3.
- Modify `TwizCrew/Stats/StatsDefs.lua` (`EXTRA_TROPHIES`), `TwizCrew/Stats/TrophyLogic.lua`,
  `TwizCrew/Stats/Trophies.lua`, `TwizCrew/UI/BoardLogic.lua`, `TwizCrew/UI/Panel.lua` (clown title) — Task 4.
- Tests: new `tests/test_crewshow.lua`; `tests/test_awards.lua` stays passing.
- Docs — Task 5.

---

### Task 1: Show rules (pure)

**Files:** Create `TwizCrew/UI/ShowLogic.lua`; TOC line `UI\ShowLogic.lua` before `UI\AwardsShow.lua`; test
`tests/test_crewshow.lua` (new, `files = "toc"`).

**Interfaces (produces `ns.ShowLogic`):**
- `L.cardToWire(id, i, card, streak, jump) -> fields`; `L.cardFromWire(f) -> { i, kind, awardId, winners, text,
  streak, jump } | nil`.
- `L.ordinal(n) -> "2nd" | "3rd" | "4th" | "11th" | "21st"…`
- `L.streakLine(n) -> "and for the 3rd session in a row" | nil` (nil when n < 2).
- `L.tally(votes, candidates) -> winners (sorted), count` — `votes = { [voter] = choice }`; only choices that are
  candidates and not the voter count; winners = the names with the most votes (ties: all); count = their votes; no
  valid votes → `{}`, 0.

- [ ] **Step 1: Tests** (in `tests/test_crewshow.lua`):

```lua
    show_rules = function(ns, A)
      local L = ns.ShowLogic
      A.eq(L.ordinal(2), "2nd"); A.eq(L.ordinal(3), "3rd"); A.eq(L.ordinal(4), "4th")
      A.eq(L.ordinal(11), "11th"); A.eq(L.ordinal(12), "12th"); A.eq(L.ordinal(13), "13th"); A.eq(L.ordinal(21), "21st")
      A.eq(L.streakLine(1), nil)
      A.eq(L.streakLine(3), "and for the 3rd session in a row")
      local def = ns.StatsDefs.AWARDS[1]
      local card = { kind = "award", award = { def = def, winners = { "Lurabe", "Twiz" }, text = "8 deaths" } }
      local f = L.cardToWire("Twiz-1", 4, card, 3, true)
      A.eq(f, { id = "Twiz-1", i = "4", k = "award", a = def.id, w = "Lurabe,Twiz", x = "8 deaths", s = "3", r = "1" })
      A.eq(L.cardFromWire(f), { i = 4, kind = "award", awardId = def.id, winners = { "Lurabe", "Twiz" },
        text = "8 deaths", streak = 3, jump = true })
      A.eq(L.cardFromWire({ id = "Twiz-1", i = "9", k = "end" }).kind, "end")
      A.eq(L.cardFromWire({ id = "Twiz-1", i = "x", k = "end" }), nil)
      A.eq(L.cardFromWire({ id = "Twiz-1", i = "2", k = "award", a = "nope" }), nil, "unknown award")
      local w, n = L.tally({ Twiz = "Lurabe", Ginkan = "Lurabe", Lurabe = "Twiz", Frostie = "Frostie" },
        { "Twiz", "Lurabe", "Ginkan", "Frostie" })
      A.eq(w, { "Lurabe" }); A.eq(n, 2)
      w, n = L.tally({ Twiz = "Lurabe", Lurabe = "Twiz" }, { "Twiz", "Lurabe" })
      A.eq(w, { "Lurabe", "Twiz" }, "a tie: co-clowns"); A.eq(n, 1)
      w, n = L.tally({}, { "Twiz", "Lurabe" })
      A.eq(w, {}); A.eq(n, 0)
      w, n = L.tally({ Twiz = "Nobody" }, { "Twiz", "Lurabe" })
      A.eq(w, {}, "not a candidate"); A.eq(n, 0)
    end,
```

- [ ] **Step 2**: run, see it fail. **Step 3**: implement `ShowLogic.lua` (pure; names cleaned with
  `ns.Util.safeText` + `truncateUTF8(…, 24)` and test names dropped when parsed; unknown award ids → nil; `i` must be a
  positive integer ≤ 100). **Step 4**: pass + full suite. **Step 5**: commit `feat(show): shared-show rules (pure)`.

---

### Task 2: The presenter sends the show

**Files:** `TwizCrew/UI/AwardsShow.lua`, `TwizCrew/Comm/Codec.lua`, tests in `tests/test_crewshow.lua`.

Behaviour:
- `Show.start(v)` as today; when the cards are built (after `SHOW_WAIT`), make the show id
  `ns.playerName() .. "-" .. ns.wallclock()` and send `AWS { id, v }`, then `AWC` for card 1 as it starts.
- Every time the presenter moves to a new card (`showCard`), send `AWC` for it (`k = "award" | "nobody" | "end"`,
  award fields, streak per Decisions). When the presenter clicks during badge/drumroll (jump to reveal), send `AWC`
  again for the same card with `r = "1"`.
- `Show.close()` by the presenter sends `AWX { id }` (only if `AWS` was sent).
- Idle: if 60 s pass with no card change, close (presenter and viewers alike). Use the existing `generation` timer
  pattern (`after(60, …)` started on every card change).
- Add the six types to `KNOWN_TYPES`.
- `/tc awards all`: works as today and is sent too (`v = "all"`), with no vote at the end.

Tests (two-step: presenter side only, by reading `W.sent` and decoding): start a show with a friend's numbers →
after `SHOW_WAIT`: one `AWS`, one `AWC i=1`; `ns.AwardsShow.next()` through the cards → one `AWC` per card, with
`k="end"` last; a click during the drumroll sends a second `AWC` for that card with `r="1"`; a streak: put two
records in `ns.db.stats.trophies` where Twiz won `corpse` in both, Twiz leads corpse now → its `AWC` has `s="3"`;
closing sends `AWX`; 61 s idle on a card → the show closes. `tests/test_awards.lua` keeps passing.

Commit: `feat(show): the presenter sends each card to the crew`.

---

### Task 3: Viewers follow the show

**Files:** `TwizCrew/UI/AwardsShow.lua`, `TwizCrew/Stats/Stats.lua` (setting), tests.

Behaviour:
- Setting in the stats module: `crewShow` (default true), label "Show the crew's awards show on my screen", info:
  "When a friend starts the awards show (/tc awards), it plays on your screen too and follows their clicks. Escape
  closes it for you."
- On `AWS` from a known crew member (not me, not a test name) while no show is open and `crewShow` is on and the
  stats module is on: open the window in **viewer** role for that `id` (header "TwizCrew Awards: <presenter>'s
  show", or "…: all time"), phase "loading".
- On `AWC` for that `id`: build the card from the wire (`ShowLogic.cardFromWire` + the award def from `StatsDefs`)
  and show it: award cards play badge → drum → reveal with the same timers, or straight to reveal when `jump`;
  "nobody" and "end" as today. The reveal shows the winners (class colours from the roster when known), the text,
  the joke, and the streak line when present. Viewers' clicks and Space do nothing except at the "end" card (close);
  the hint reads "<Presenter> is presenting" (end card: "Click or press Space to close").
- A viewer in a fight (`InCombatLockdown()` or `UnitAffectingCombat("player")`, read safely): don't open/redraw;
  remember the latest card; on `PLAYER_REGEN_ENABLED`, open (if the show is still running) at that latest card,
  straight to its reveal.
- `AWX` for that `id`: close. Escape closes the viewer's window only (no message).
- Idle 60 s without an `AWC`/`AWV`/`AWR`: close (same rule as Task 2).
- An `AWS` with a different `id` while a viewer show is open: ignored. The presenter role ignores all incoming
  `AWS`/`AWC`.

Tests: receive `AWS` + `AWC`s from a known friend → window open in viewer role, `stateForTest()` shows the card,
phases advance by timers; `ns.AwardsShow.next()` does nothing mid-show; `r="1"` jumps to reveal; `AWX` closes;
setting off → nothing opens; unknown sender or test name → nothing; in combat → nothing until `PLAYER_REGEN_ENABLED`,
then the latest card's reveal; 61 s silence → closed; a second `AWS` from someone else is ignored. Extend
`stateForTest()` with `role` ("presenter" | "viewer") and `streak` (the line, or nil).

Commit: `feat(show): the crew watches the awards show live`.

---

### Task 4: Clown of the Night vote, title and trophy

**Files:** `TwizCrew/UI/AwardsShow.lua`, `TwizCrew/Stats/StatsDefs.lua`, `TwizCrew/Stats/TrophyLogic.lua`,
`TwizCrew/Stats/Trophies.lua`, `TwizCrew/UI/BoardLogic.lua`, `TwizCrew/UI/Panel.lua`, tests.

Behaviour:
- Session-view shows only: after the last award card, before "end", the presenter starts the vote if there are at
  least 2 candidates: sends `AWV { id, c, t = "30" }` and shows the **vote** phase. Viewers show it on `AWV`.
- Vote card (every screen): title "Who's the Clown of the Night?", one button per candidate except yourself (class
  colour; up to 8 buttons in two columns; more candidates: the first 8 by name — note it), a line "N of M voted", a
  countdown. Clicking a button: send `AWB { id, c = name }` once (buttons then show your pick and stop responding).
  Every screen counts `AWB`s it hears (one per sender, first counts) for the "N of M" line. The presenter's own click
  counts directly (and is also sent). The presenter also has a **Skip** button → sends `AWR { id, k = "skip" }`.
- The presenter ends the vote after 30 s, or once every online candidate except nobody has voted (all candidates who
  are online — check `ns.roster` online state; I'm online), and sends `AWR { id, w, n }` from
  `ShowLogic.tally(votes, candidates)`.
- Reveal phase (every screen, on `AWR` or locally for the presenter): "Clown of the Night: <names> (<n> votes)"
  (`1 vote` singular; co-clowns joined with " & "), or "No clown tonight." when nobody voted, or straight to the end
  card on skip. A click (presenter) goes to the end card (sends `AWC k="end"`).
- On every screen that shows a non-skip `AWR` with names: save `ns.db.stats.clown = { names, sid = current session
  id, at = ns.wallclock() }`; fire the bus event `CLOWN_CHANGED`.
- Crew-tab title: in `TwizCrew/UI/Panel.lua` `titleOf`, a name in `db.stats.clown.names` gets the title "Clown of
  the Night" (overrides award titles; shown even when the titles setting is off? — no: only when titles are on, like
  other titles). Redraw on `CLOWN_CHANGED`.
- Trophy: `StatsDefs.EXTRA_TROPHIES` (see Decisions). In `Trophies.sessionEnded(sid)`, after `L.record`, when
  `db.stats.clown` has that `sid`, set `r.winners.clown` to the clown names that are in `r.people` (skip when none).
  Make the id→name/icon lookups (TrophyLogic known ids, BoardLogic trophy rows, Trophies.lineFor) include
  `EXTRA_TROPHIES`.

Tests: presenter with 2 friends in the session → after the last award, `AWV` sent with the three candidates; the
presenter can't vote for themselves (no own button); `AWB`s received update "2 of 3 voted"; after 30 s `AWR` with the
tally; a tie → co-clowns; nobody votes → `AWR` with empty `w` and "No clown tonight."; Skip → `AWR k=skip`, end card;
viewer side: `AWV` shows the vote card with buttons for everyone but me, clicking sends one `AWB`, a second click
sends nothing; `AWR` shows the reveal and saves `db.stats.clown`; the Crew tab title of the clown is "Clown of the
Night"; a session that ends after a show records `winners.clown`; the Trophies tab lists "Clown of the Night x1".
An all-time show has no vote.

Commit: `feat(show): Clown of the Night vote, title and trophy`.

---

### Task 5: Docs

`docs/TESTING.md` — "Hall of Shame part 3 (shared show, vote)": 1) a friend online with this version: `/tc awards`
→ the show opens on their screen and follows your clicks; 2) they press Escape → only theirs closes; 3) a friend in a
fight sees it after the fight, at the current award; 4) after the last award, everyone gets the vote card (no button
for yourself), "N of M voted", the reveal is the same on every screen, the clown's Crew-tab title says "Clown of the
Night"; 5) Skip works; 6) leave it on one card for over a minute → it closes everywhere; 7) the setting "Show the
crew's awards show on my screen" off → nothing opens. `PROJECT.md`: part 3 built line (plan path, not tried in game,
new file → RESTART_SINCE). Commit `docs: in-game checks for Hall of Shame part 3`.
