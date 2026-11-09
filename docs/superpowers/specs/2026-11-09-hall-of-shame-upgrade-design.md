# TwizCrew: Hall of Shame upgrade (new awards, category tabs, stolen crowns, trophies, shared show, crew vote)

Date: 2026-11-09. Status: **each section approved by the owner** ("yes" to all three); this written version waits
for the owner's review. Builds on the stats board (`docs/superpowers/specs/2026-11-05-stats-board-design.md`, built
and played in game). Read `PROJECT.md` first.

Marked **(owner)** = the owner decided it. Marked **(Claude's call)** = Claude proposed it and the owner approved the
section; the owner can still overrule any of it. Unmarked = left to the builder.

## 1. Intent

**(owner):** the crew "really likes the Hall of Shame" and asked for an award for being the poorest. The owner also
asked Claude to "make it better and improve it, be creative and think of more things to add to it", then picked
every idea offered except predictions and custom awards ("neither for now").

## 2. Build order (Claude's call): three parts, each its own release

1. **New awards + category tabs** (section 3, 4).
2. **Stolen crown pop-ups + trophy case with streaks** (section 5, 6). Both need "who held which award".
3. **Awards show on everyone's screen + crew vote** (section 7, 8). The vote is the end of the shared show.

Each part gets its own implementation plan, is tested outside the game, released, and tried in game before the
next part starts.

## 3. New awards (part 1)

Eleven new awards, all without the combat log (addons can't use it in Forever). Every new detector follows the
stats board rules: counting is local, numbers ride the existing `STATS` message (new keys), each detector has a
fallback, turns itself off on errors, and gets a `/tc report` line. **Every yes/no or number read from the game goes
through `issecretvalue` first** (inside dungeons even `UnitIsAFK` is secret; see PROJECT.md).

| Award | Tab | Counts | Winner |
|---|---|---|---|
| **Pauper** **(owner)** | Money & Loot | gold carried now (`GetMoney`), a snapshot, not a sum | least gold; same value on the session and all-time views; shown exactly ("14c") **(owner)** |
| **Money Pit** **(owner)** | Money & Loot | gold lost and gold gained (every `PLAYER_MONEY` change) | biggest lost − gained; only people who ended up down take part. Trading or mailing gold away counts |
| **Ninja** | Money & Loot | Need rolls won in a group (the game's "You won" loot message after a Need roll) | most |
| **Out of Juice** | Butterfingers | "Not enough mana / rage / energy" red errors | most; repeats less than 2 s apart count once |
| **Too Far Away** | Butterfingers | "Out of range" / "You are too far away" red errors | most; same 2 s rule |
| **Wanderer** | Butterfingers | times you ran off from a group member (see below) | most |
| **Snail** | Lazy & Loud | XP gained per hour played | lowest; needs 30 min played; max-level characters don't take part |
| **Chatterbox** | Lazy & Loud | your own party and raid chat messages | most; only the count is kept, never the words |
| **Emote Spammer** | Lazy & Loud | your own emotes (/dance, /lol…) | most |
| **Tourist** | On the Move | different zones visited | most |
| **Frequent Flyer** | On the Move | flight paths taken (start of each `UnitOnTaxi` ride) | most |

- **Wanderer counting (Claude's call):** your own copy already knows your group's positions, so it runs the
  running-off check from your side: you were within the alarm's "near" distance of a group member, then far away
  within the same window, and **you** moved, not them (the mirror of the alarm's rule). Each such run counts once
  per group member it would alarm, at most once per member per alarm length. Counted locally like any stat: no new
  message. It counts even when the watcher turned their alarm off.
- **Older copies** ignore the new keys: nothing breaks; a friend who hasn't updated just isn't in the new awards.
- Jokes, icons and (i) texts for each new award: one table entry each (`StatsDefs.AWARDS`), like the old ones.

## 4. Category tabs (part 1) **(owner: "Category tabs")**

The Hall of Shame gets small tabs above the award rows. 29 awards, 5–7 per tab, so nothing scrolls:

| Tab | Awards (★ new) |
|---|---|
| **Deaths** | Professional Corpse, Gravity Tester, Fish Food, Died to a Weakling, Back for More, Leeroy |
| **On the Move** | Marathon Runner, Couch Potato, Never Walks, Fish, Bunny Hopper, ★Tourist, ★Frequent Flyer |
| **Money & Loot** | ★Pauper, ★Money Pit, Broke, Trash Collector, ★Ninja |
| **Butterfingers** | ★Out of Juice, ★Too Far Away, ★Wanderer, Quitter, Duel Loser, Homesick |
| **Lazy & Loud** | ★Chatterbox, ★Emote Spammer, Furniture, ★Snail, Medic |

- The This session / All time switch stays and applies to every tab. The last tab picked is remembered.
- The awards show still goes through every award, tab by tab, with Medic last.
- Titles on the Crew tab keep their rule (the most important award in table order).

## 5. Stolen crown pop-ups (part 2) (Claude's call)

- When a new person takes the lead in an award, every copy shows a pop-up: "Twiz just stole **Professional
  Corpse** from Lurabe! (8 deaths vs 7)". Click: the Hall of Shame at that award's tab.
- **This session** numbers only. The new holder must be strictly ahead (a tie is not a steal).
- Not in the first **15 minutes** of a session.
- At most **one steal pop-up a minute**; several together become one ("3 crowns changed hands"; hover lists them).
- A switch under Roasts: "Stolen crown pop-ups" (on by default). Uses the pop-up module's sound switch.
- Steals are noticed when numbers arrive (shared about every 5 minutes), so a pop-up can come up to 5 minutes late.
  Sharing faster is not allowed (message limit, anti-goal of the stats board).

## 6. Trophy case and streaks (part 2) (Claude's call)

- **When a session ends** (someone starts a new one, or the crew was offline 30 minutes), each award's winner gets a
  trophy. A session shorter than 30 minutes, or with only one person, gives no trophies.
- Each copy records the results itself: `{ sid, started, ended, people, winners = { [award] = { names } } }`. Kept
  forever (small).
- **Friends who were offline** at the end get missing results from the crew later, pull-only like the calendar's
  diary swap: a digest of known session ids; whoever lacks one asks once; the first answer for a session id is kept.
- A **Trophies** tab in the Hall of Shame (after the category tabs): one row per person: total trophies, most-won
  awards ("Professional Corpse ×6"), streaks going ("Gravity Tester, 3 sessions in a row").
- **A streak** counts the sessions that person took part in: a missed night doesn't break it.
- Hovering a friend on the Crew tab adds a line: "12 trophies · Professional Corpse streak ×3".

## 7. Awards show on everyone's screen (part 3) (Claude's call)

- `/tc awards` (anyone; meant for the owner) opens the show on every online crew member's screen whose copy has
  this version. **The starter is the presenter**: only their clicks move the show; everyone follows.
- The presenter's copy decides the winners and sends **one message per card as it is revealed** (award id, winner
  names, value, streak). Everyone sees the same results. No message per frame or per second.
- A viewer in a fight: their show waits and catches up to the current card when the fight ends. The boss-fight
  hold of the send queue already applies.
- Viewers can close it with Escape. Setting (Hall of Shame): "Show the crew's awards show on my screen" (on).
- No click from the presenter for **60 seconds** (disconnect, forgot): the show closes on every screen.
- Cards mention streaks: "…and for the 3rd session in a row, Lurabe!".

## 8. Crew vote: Clown of the Night (part 3) (Claude's call)

- After the last award, a **vote card** on every screen in the show: a button per person who was in the session, in
  class colour. **No voting for yourself.** 30 seconds.
- While voting: only "4 of 6 voted" is shown, never who voted for whom. Votes go out as one message each.
- Reveal: "Clown of the Night: **Twiz** (4 votes)". A tie: co-clowns. Nobody voted: no clown.
- The winner gets **"Clown of the Night"** under their name on the Crew tab until the next show, and a special
  trophy in the trophy case.
- The presenter has a **Skip** button on the vote card.

## 9. Not in this upgrade **(owner: "neither for now")**

- Predictions before the show.
- Custom awards handed out by command.

## 10. Testing

- Outside the game: every detector with pretend game events (including secret values), the tab layout, steal
  detection and its limits, trophy recording, the swap for missed sessions, streaks, the shared show with two and
  three simulated copies (presenter, viewer in a fight, presenter gone), and the vote (self-vote blocked, tie, no
  votes).
- In game, per part, riskiest first, added to `docs/TESTING.md`: the red-error and loot-message wording in Forever
  (the detectors depend on the exact text), gold changes, the running-off tally, the shared show's timing.
