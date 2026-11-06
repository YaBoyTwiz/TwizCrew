# TwizCrew: level progress (XP numbers, hover detail, "Ding!" pop-up) — Plan

**Owner's request:** "a feature that shows how close someone is to level". Claude proposed three parts, the owner
said "all three":

1. **The number on the bar:** each friend's row shows text like "Lv 12 · 63%".
2. **Hover detail:** the row's tooltip shows "1,234 XP to level 13", rested XP, and "About 25 min to level".
3. **"Ding!" pop-up** for the crew when a friend levels up: "Frostie reached level 13!" in the class colour.

Builds on the earlier plans; their Global Constraints and "Changes during build" still hold.

## Global Constraints

- Lua 5.1, every handler inside `ns.Log.safe`, pure logic in tested files, local commits only, no version bump.
- **No new files and no `.toc` change**, so a `/reload` is enough for anyone on v0.1.1.
- **No extra messages.** XP numbers ride on the UPDATE messages that already go out.
- Older copies keep working: the old `xp` percent stays; they ignore the new fields.

## Design (Claude's calls; the owner can overrule)

1. **Wire fields** in STATE / UPDATE: `xc` = current XP, `xm` = XP needed for this level (`0` at max level), `rx` =
   rested XP (`0` when none). Whole numbers. At max level (`UnitXPMax` 0, or level ≥ `GetMaxPlayerLevel()`) the copy
   sends `xm=0`, `xc=0`. A secret value (`issecretvalue`) counts as unknown.
2. **Riding along:** a change in only `xc` / `rx` never sends a message on its own. It waits for the next UPDATE,
   which goes out anyway when the XP percent changes, a fight starts or ends (FIGHTING tag), the zone changes, and so
   on. A level-up changes `lv` and `xm`, so it goes out at once (1 s after, like today).
3. **Codec order:** `lv`, `xm`, `xc`, `rx` follow the zone / layer / session keys at the front of every message,
   so they land in the same piece when a long STATE is split.
4. **Rate on the receiving side** (not a sent XP-per-hour). Why: no extra field that changes all the time, one
   place for the idle rule, and `xc` is an absolute number, so a missed message loses no XP. Each copy keeps, per
   friend and for that friend's current play session, the XP earned and the "playing time" between gains (each
   gap counts at most 10 min, so a long AFK does not drag the pace down). A level-up counts as XP earned (what was
   left of the old level plus the new `xc`). Anything odd (XP going down, two levels at once, XP above the level's
   need) starts the count over. Cost: after **you** log in or `/reload`, the estimate needs a few minutes of the
   friend earning XP before it shows.
5. **No wild guesses:** the estimate shows only after at least 2 gains and 3 minutes of playing time, not when the
   last gain is more than 10 minutes old (idle), and not when it would be over 12 hours.
6. **Row text per style** (setting "Show level and XP numbers"):
   - Full: "Lv 12 · 63%" to the right of the XP bar (the corner level number hides, it would say the same). At max
     level: no bar, "Lv 60 · max level".
   - Compact: "Lv 12 · 63%" in the top-right corner, where the level number was. Max: "Lv 60 · max".
   - Tiny: "63%" in the top-right corner. Max: "max".
   - Offline rows and friends whose XP is unknown keep today's look.
7. **Tooltip** (setting "XP details on hover"): name in class colour, "Level 12 · 63%", "1,234 XP to level 13",
   "Rested: 2,000 XP", "About 25 min to level". Max level: "Max level". Older copies (no `xc`/`xm`): just the
   level line.
8. **Ding:** the roster reports a level-up only when the friend was online before the message, we already got a
   level from them in this play session (a HELLO or going offline forgets it), and the new level is exactly one
   more. The pop-up module shows "Frostie reached level 13!" (gold edge) with a short line under it: "Only 47 to
   go." / "One more to go!" / "Max level. GG!" (max level from `GetMaxPlayerLevel()`, else 60). Login quiet time
   (30 s) applies. Your own level-up shows nothing (the game has its own).
9. **Settings:** Crew panel gets "Show level and XP numbers" and "XP details on hover" (after "Show XP bar").
   Pop-ups gets "Level-ups" and, under it, "Level-up sound" (off). The ding plays only its own sound, not the
   general "Play a sound" one. Reset to defaults restores them (they live in the module defaults).

## Tasks (TDD, one commit each)

1. Self: send `xc`/`xm`/`rx`, ride-along rule; Codec order; longest-STATE test.
2. Roster: store the numbers, XP pace tracking, "levelup" event; Crew fires `MEMBER_LEVELUP`.
3. PanelLogic: row text per style, tooltip lines, time-to-level; Panel draws them, row tooltip; two settings.
4. PopupLogic / Popups: the ding, its fun line, its sound; two settings.
5. Multi-client simulation; docs (TESTING.md, PROJECT.md).

## Changes during build
