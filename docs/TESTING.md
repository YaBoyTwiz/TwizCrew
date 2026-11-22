# Testing TwizCrew in the game

TwizCrew v1 is built, and every test outside the game passes. It has **not been tried in the real game yet**. This
list is what to try, with the riskiest things first. You don't have to do it all at once. If something looks wrong,
stop there and tell Claude.

## Before you start

- **Restart the game fully** (not just `/reload`). The game only finds a brand-new addon folder when it starts.
  TwizCrew is already in your AddOns folder: it is a link to the project folder, so after Claude fixes something,
  `/reload` in the game is enough.
- **Turn on Lua error messages** so you can see if something breaks: type `/console scriptErrors 1`.
  (Type `/console scriptErrors 0` to turn them off again before you stream.)
- **When you're done, or something went wrong:** type `/reload`, then tell Claude. TwizCrew keeps a log of what it
  did, and `/reload` writes it to a file Claude can read on this PC:
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/TwizCrew.lua`
- **Friends** can't send you their file. Ask them to type `/tc report`, press Ctrl+C in the box that opens, and
  paste it in Discord.
- **Many checks work alone** with the test buttons: `/tc`, then scroll to **Try it out** at the bottom (or type
  `/tc test` in chat for the same as commands). They make pretend friends and pop-ups on your screen only. See
  "Test tools" below.

## Alone (riskiest first)

1. **Does it load at all?**
   - On the character screen, open **AddOns**: TwizCrew should be in the list and not marked "out of date".
   - In the game, chat should say `TwizCrew v0.1.0 loaded. Type /tc for settings.` once.
   - Type `/run print((select(4, GetBuildInfo())))`. It should print **16001**. If it prints a different number,
     tell Claude the number.

2. **No red error pop-ups** while you log in, play for a few minutes, fight something and `/reload`.
   Also no "action blocked" or "interface action failed" message during a fight.

3. **The hidden crew channel.** No longer applies since the guild conversion (there is no channel; see "Guild
   conversion" below, step 8).

4. **The crew panel** (the TwizCrew window on the left side of the screen).
   - It shows up with a dark background, a gold border and the title "TwizCrew". With no friends online it says
     "No crew yet".
   - Drag it somewhere else, then `/reload`. It should come back in the new spot.
   - Right-click its title: a small menu opens. Click something in it, then open it again and click somewhere else
     on the screen, then press Escape: each time the menu should close.
   - Right-click its title and pick **Set my status**: a small box opens with your status in it. Type something and
     press Enter: chat says `TwizCrew: status set to "…"`. Open it again and press Escape: nothing changes.
   - Open the settings (`/tc`), turn on **Show myself in the list**: your own row appears with your class icon,
     level, zone and XP bar.

5. **Class icons.** Your row (from step 4) should show your class icon. `/tc report` says
   `Class icons: atlas` or `Class icons: texture` (both are fine; `none` means no icon could be shown).

6. **The settings window.**
   - `/tc` opens and closes it. Escape also closes it.
   - Esc menu → **Options → AddOns → TwizCrew**: you should see "TwizCrew has its own settings window." and a button
     that opens it. Click the button: the TwizCrew window appears in front; Escape closes it.
   - Hover over a few **(i)** buttons: a short explanation appears. Click one: it stays until you click it again.
   - If the window is taller than your screen, the mouse wheel scrolls it.
   - Turn a few things off and on (for example the **Crew panel** switch): the panel hides and comes back.
   - Change the **Scale** slider and the **Row style**: the panel changes right away.
   - Drag the panel somewhere, then click **Reset everything to defaults**. It asks
     "Reset all TwizCrew settings and the panel position?". Click **Yes**: the panel goes back to its first spot.
     `/reload`: it should still be in that first spot.

7. **Chat commands.**
   - `/tc status LF Deadmines` → chat says `TwizCrew: status set to "LF Deadmines"`. `/tc status` clears it.
   - `/tc hide` hides the panel, `/tc show` brings it back.
   - `/tc report` opens a box with the text selected. Press Ctrl+C, paste it somewhere (Discord, Notepad): the text
     should all be there.
   - `/tc help` lists the commands. `/twiz` should still open TwizTracker, not TwizCrew.

8. **What the game tells TwizCrew about you.** Each time, type `/tc report` and look at the line
   "Game says: …" near the bottom:
   - On a flight path → `flying yes`.
   - After typing `/afk` → `away yes` (type `/afk` again to come back).
   - Inside a dungeon → `in a dungeon yes (party)`.
   - In a fight → `fighting yes`; while dead or a ghost → `dead yes`.

## With one friend

Your friend needs TwizCrew too. That means putting it on GitHub for WowUp, which only happens when you say
"publish", and once you've picked the final name (the folder name becomes the addon's name).

Do these **without being in a group** first: that proves guild messages work. Pop-ups stay quiet for the
first 30 seconds after you log in (so logging in doesn't flood you); after that they work normally.

1. **You see each other.** Within about 10 seconds of both being online, each of you is on the other's panel with
   the right class icon, level and zone, and the panel title says "1 of 1 online".
2. **Zone changes.** When your friend goes to another zone, their row updates within a few seconds.
3. **Layers (OTHER LAYER).** Stand in the same zone. Both of you hover your mouse over a few NPCs (or target them).
   - Type `/tc report` on both sides and compare the "Layer: key …" numbers. Different numbers should mean you're on
     different layers (you can't see each other in the world).
   - If they differ, your friend's row gets a red **OTHER LAYER** tag and a pop-up says
     "<friend> is on a different layer". Click the pop-up: it invites them to your group.
   - Joining the group moves one of you to the other's layer. After hovering over a few NPCs again, the tag goes
     away and a pop-up says "<friend> is back on your layer".
   - If the numbers are the same but you really are on different layers (or the other way round), tell Claude:
     the way TwizCrew guesses layers would need changing.
   - **Near a zone border.** Stand next to each other close to the border between two zones, and both hover over
     NPCs on both sides of the border. **OTHER LAYER** should not appear for a friend standing next to you.
   - Have your friend log out and back in while you stay: no "on a different layer" pop-up should come from that.
4. **Death pop-up.** When your friend dies, a pop-up says "<friend> died" with the place.
5. **Offline friend, no chat spam.** Have your friend log off. For the next two or three minutes you should **not**
   see "No player named … is currently playing" in chat. (The **Connection** setting no longer exists since the
   guild conversion.)
6. **A boss fight.** Do a dungeon boss together. Nothing should break. Messages pause during the fight and are sent
   right after, so the panel may lag a little during the fight.
7. **Typed status.** Your friend types `/tc status 50% ^_^ a|b`. You should see exactly that on their row, in quotes
   (including the `|`; if it shows as `||` or looks different in any way, tell Claude).

## Stats, roasts and the awards show

The stats board (Hall of Shame, live roasts, `/tc awards`) is built too, and every test outside the game passes,
including two and three copies talking to each other. It has **not been tried in the game yet**. Do the v1 checks
above first (at least "Does it load at all?"), then these, riskiest first.

Keep Lua errors on while you test (`/console scriptErrors 1`, see "Before you start"), and turn them off again
before you stream.

### Alone

1. **No lag and no errors over a long session.** The counting runs all the time (twice a second), so this matters
   most. Play normally for an hour or more: walk, ride, swim, fight, die, loot, `/reload` once in the middle.
   - No red error pop-ups, no stutter or lower frame rate than without TwizCrew. If you're not sure about the frame
     rate, turn the **Stats & Hall of Shame** switch off in `/tc` for ten minutes and compare.
   - At the end, type `/tc report` and check the line "Turned off after errors: none". If it names something, tell
     Claude what it says.

2. **The `/tc report` lines.** Type `/tc report` and find these three lines:
   - `Stats: on, steps by speed, detectors off: none`. This is the most useful line for Claude:
     - "steps by **speed**" is the good one. "steps by **position**" means the game's speed reading didn't work, so
       steps won't count inside dungeons. "steps by **off**" means steps can't be counted at all. Tell Claude if it
       isn't "speed".
     - "detectors off" lists the things TwizCrew can't count in Forever, each with the reason in brackets, for
       example `jumps (JumpOrAscendStart missing)`. Copy the whole line for Claude if it isn't "none".
   - `Session: Twiz-… started 9:02 pm (automatic)`: about 20 seconds after you log in, this names the crew session
     (your name and a long number) and the time it started. Before that it says "not decided yet".
   - `Stats sent …, heard …`: when your numbers were last sent to the crew, and when you last got a friend's. Alone,
     "heard never" is normal.

3. **Steps.** Open the Crew panel and click the **Hall of Shame** tab at the top, then **This session**.
   - Walk or run for about a minute. **Marathon Runner** should show you with a few hundred steps (about 8 steps per
     second while running). The number updates every few seconds.
   - Take a **flight path**. While you fly, the steps should **not** go up.
   - Die and run back to your body **as a ghost**. The ghost run should **not** add steps.
   - Ride your mount for a while, then swim: riding counts for **Never Walks** (only once you've travelled about
     1,000 yards), swimming for **Fish**.

4. **Deaths that get a roast.** Each one should show an orange pop-up (a "roast") on your own screen for about 6
   seconds, and add a line to the Hall of Shame. Say which ones worked and which didn't, and what the pop-up said.
   - **A fall death:** jump off something high enough that you fall for **well over a second** and die. Expect a
     roast like "Twiz forgot gravity exists." and **Gravity Tester** on the Hall of Shame. (A normal jump never
     counts as a fall.)
   - **Drowning:** swim deep and stay under until the breath bar runs out and you die. Expect "Twiz tried to breathe
     water. It didn't work." (or a similar line) and **Fish Food**. Swimming too far out to sea until the fatigue bar
     runs out should count too.
   - **Death to a weak mob:** **click on (target)** a monster **5 or more levels below you**, and die while it's
     still your target and alive, within about 10 seconds (easiest when you're nearly dead already, for example
     after a fall). Expect "Twiz died to a level 3 Kobold Miner. Embarrassing." (or a similar line, with the
     monster's real level and name) and **Died to a Weakling** showing "1 death (lvl 3 mob)".
   - **Dying again within a minute** of coming back to life: a "back for more" roast and **Back for More**.
   - After every death, **Professional Corpse** goes up by one. Hover over it: the tooltip shows "Time dead".

5. **The little counters.** Do each once and check the Hall of Shame (switch to **All time** too: it should count
   them as well). Tell Claude which ones didn't go up.
   - **Jump** ten times: **Bunny Hopper** shows 10 jumps.
   - Use your **Hearthstone** and let it finish: **Homesick**.
   - **Loot a grey junk item** from a monster: **Trash Collector**.
   - At a vendor with damaged gear, press **Repair All** (repairing one item at a time doesn't count): **Broke**,
     with the gold, silver and copper you paid.
   - **Abandon a quest** from the quest log: **Quitter**. Abandoning three in one session also gives a roast.
   - **Lose a duel** to a friend (or run away from one): **Duel Loser**.
   - If you play a priest, paladin, shaman or druid: **bring someone back to life**: **Medic**.

6. **The Crew panel tabs and the Hall of Shame.**
   - At the top of the Crew panel: two tabs, **Crew** and **Hall of Shame**. Both work, and the Crew tab looks the
     same as before.
   - On the Hall of Shame: a **This session** / **All time** switch. Under it "Session started 9:02 pm by Twiz"
     (or "All time").
   - One row per award, each with a picture (badge), the award's name, the winner's name in their class colour and
     their number in plain words ("7 deaths", "1g 23s 45c", "2h 10m AFK").
   - Awards nobody has won yet are **greyed** and say "nobody yet". There is never a winner with 0.
   - **Hover** a row: a tooltip says what the award is for and shows the top 3 with their numbers.
   - Everything fits inside the panel, nothing overlaps or runs off the edge. Try it with the **Scale** slider and
     the **Row style** in `/tc` too.

7. **Award titles under names.** In `/tc`, turn on **Show myself in the list**. On the **Crew** tab, the name of an
   award you've won (for example "Professional Corpse") shows as a small line under your name. The setting
   **Award titles on the Crew panel** switches between This session, All time and Off.

8. **The awards show: `/tc awards`.** Try it off stream first.
   - A big dark window with a gold glow opens in the middle of the screen. It says "Getting the latest numbers…"
     for about 5 seconds.
   - Then one award at a time: the badge and the award name, then "and the award goes to…", then the winner's name,
     their number and a one-line joke. A short sound plays (setting **Sound in the awards show**).
   - **Space** or a **click** goes to the next one. Check that Space does **not** make your character jump while the
     window is open, and does again after it closes.
   - **Escape** closes it at any time. The window can be dragged somewhere else.
   - Awards nobody won are skipped. **Medic** comes last. The last card says **"That's the show. GG crew."** and the
     next Space or click closes it.
   - `/tc awards all` does the same with all-time numbers.
   - **In a fight**, `/tc awards` doesn't open: chat says "TwizCrew: the awards show waits until the fight is
     over." If a fight starts while it's open, clicking still works.
   - Tell Claude if the sounds are missing or odd (Claude picked the game's ready-check and raid-warning sounds).

9. **`/tc stats reset` asks first.** Type `/tc stats reset`: chat explains and asks you to type
   `/tc stats reset yes`. Nothing changes until you do. With `yes`, all your own numbers (this session and all time)
   go back to 0. Only do this if you don't mind losing them. (The **Reset everything to defaults** button in the
   settings never touches stats.)

### With a friend

Your friend needs TwizCrew too, so this waits until you've said "publish" (see "With one friend" above).

1. **Same session.** Log in, wait about 30 seconds, then both type `/tc report`. The `Session:` line should be
   **exactly the same** on both sides (same name, number and time). If not, wait a minute and try again; if it's
   still different, send Claude both reports.
2. **A roast about a friend.** When your friend falls to their death (or drowns, or dies to a low monster they
   targeted), **both of you** see the same roast line, word for word, with their name. Only one roast per person
   every 10 seconds, so dying twice in a row shows one.
3. **Same awards on both screens.** Both open the Hall of Shame (opening it asks the crew for fresh numbers). After
   a few seconds both boards should show the same winners and numbers. (A friend's numbers otherwise update about
   every 5 minutes, so a board you haven't reopened can be a little behind.)
4. **`/tc session new`** (meant for the start of a stream): one of you types it. Chat says "new session started.
   Everyone's session stats start from 0." Within a few seconds the **This session** numbers are 0 for **both** of
   you, the `Session:` line in `/tc report` is the same on both sides and ends with "(by hand)", and the **All
   time** numbers are untouched.
5. **Turning stats off hides you.** Your friend turns **Stats & Hall of Shame** off in `/tc`. Within a few seconds
   they disappear from your Hall of Shame (both This session and All time), their title goes away, and you see no
   roasts about them. When they turn it back on, they come back with their old numbers.
6. **A wipe in a dungeon.** If your whole group dies in a dungeon within 30 seconds: one "WIPE!" roast for everyone
   and a "Wipe Squad: 1 wipe tonight" line at the bottom of the Hall of Shame.
7. **Leeroy.** In a dungeon, the one who starts a fight while nobody else in the group is fighting gets a point
   for **Leeroy**.

### Things only the game can tell us

Claude built these without being able to check them in Forever. Each one has a fallback, and a broken one should
show up in `/tc report` under "detectors off" instead of breaking the rest. Most are covered by the steps above;
this is the list of what to report:

- **Speed reading** (steps): does "steps by speed" stay, and do steps count **inside a dungeon**?
- **Falling** (fall deaths): does a long fall death give the fall roast?
- **Breath and fatigue bars** (drowning): does drowning, and the fatigue bar far out at sea, give the drowning
  roast?
- **Jumps**: does Bunny Hopper count, and is "jumps" missing from "detectors off"?
- **Hearthstone and resurrection spells**: do Homesick and Medic count?
- **Duel results**: does a lost duel count (and running away from one)?
- **Monster level before death**: does Died to a Weakling work, or does a death to a low monster only count as a
  normal death?
- **Abandoning quests**: does Quitter count when you abandon from the quest log?
- **Sounds**: does the awards show (and a roast, if **Play a sound** is on under **Live roasts**) make a sound?

### Hall of Shame part 1 (new awards, tabs)

1. Cast a spell with too little mana (or rage/energy), and one out of range. `/tc report`: the "errors" detector is
   on. The Hall of Shame, Oops tab: Out of Juice and Too Far Away each show 1 (pressing it 5 times fast still 1).
   If not: copy the exact red text into a note for Claude (the game's wording may differ).
2. In a group, roll Need on an item and win it: Money tab, Ninja shows 1 Need roll won. Greed doesn't count.
   If not: copy the exact "You won" chat line for Claude.
3. Buy or sell something: Money tab shows your exact gold under Pauper (if you're the poorest) and Money Pit moves
   when you end up with less gold than you started with. Pauper needs 30 minutes played.
4. Walk 100+ yards away from a group member who stays put: Oops tab, Wanderer shows 1 run-off; your friend's
   screen shows the running-off warning about you (if theirs is on). Taking a flight away from group members
   counts one run-off per member who was close; hearthstones, portals, summons and releasing your ghost don't
   count.
5. Say something in party chat and do a /dance: Lazy tab, Chatterbox and Emote Spammer count them.
6. Take a flight path and enter a new zone: Moving tab, Frequent Flyer and Tourist count them.
7. Play 30 minutes below max level: Lazy tab, Snail shows XP per hour (lowest wins). Level up once and check the
   number doesn't jump by a whole level.
8. Click each tab: the right awards show, the subtitle starts with the tab's full name, and the tab you picked is
   still picked after /reload.
9. Inside a dungeon: none of the above causes "turned itself off" in chat.

### Hall of Shame part 2 (stolen crowns, trophies)

1. Play 15+ minutes with a friend, then let them pass you in an award (more deaths, more jumps): a pop-up "<Name>
   just stole <Award> from <you>!" appears within about 5 minutes (numbers are shared every few minutes). Click it:
   the Hall of Shame opens at that award's tab. Several at once: one "N crowns changed hands" pop-up.
2. Live roasts > "Stolen crown pop-ups" off: no more steal pop-ups.
3. After 30+ minutes with a friend, type `/tc session new`: the Hall of Shame's Trophies tab lists the winners of
   the session that just ended. Your friend's Trophies tab shows the same.
4. A friend who was offline when that session ended logs in: within a minute their Trophies tab has it too. A
   friend who left early (logged off before the session ended) gets a record at their next login from the numbers
   they had; once someone who stayed to the end is online, it is swapped for the full version within about 10
   minutes. If the crew logs off one by one instead (nobody ends the session), everyone gets a record at their
   next login; once you have been online together, everyone's Trophies tab shows the version of whoever stayed
   latest, within about 10 minutes.
5. Win the same award two sessions in a row: the Trophies tab's tooltip and your row's tooltip on the Crew tab say
   "streak x2".

### Hall of Shame part 3 (shared show, vote)

You need a friend online with this version, both in the same crew session.

1. Type `/tc awards`: the show opens on your friend's screen too ("TwizCrew Awards: <your name>'s show") and
   follows your clicks: each award appears on their screen when you move to it, and a click during the drumroll
   jumps to the winner on both screens. Their clicks do nothing until the end card.
2. Your friend presses **Escape**: only their show closes. Yours keeps going.
3. Your friend starts a fight, then you start the show and click on a card or two. When their fight ends, the show
   opens on their screen at the award you are on now (straight to the winner).
4. After the last award, everyone gets the vote card "Who's the Clown of the Night?": a button for each person in
   the session in their class colour, but no button for yourself. Click one: it shows your pick and the other
   buttons stop working. The "N of M voted" line goes up on every screen as people vote. After 30 seconds (or as
   soon as everyone online has voted) every screen shows the same result, for example "Clown of the Night: Twiz
   (2 votes)", two names joined with "&" for a tie, or "No clown tonight." when nobody voted. When the 30 seconds
   run out, the buttons fade and stop working. Afterwards, the clown's row on the Crew tab says **Clown of the
   Night** under their name, on every screen that watched the result (a friend who closed the show or wasn't on
   doesn't get it), while award titles are on. After `/tc session new` (30+ minutes, 2+ people) the Trophies tab
   lists "Clown of the Night x1".
5. Start the show again and press **Skip** on the vote card: everyone goes straight to the end card, and the
   Clown of the Night title is gone from the Crew tab (no clown until the next show). The trophy from step 4 stays
   (same session).
6. **Click through the show quickly** (several clicks a second, right to the vote): your friend's screen jumps to
   the latest card instead of playing every one, and they still get the full 30 seconds to vote (their countdown
   starts near 30 and your result comes only after theirs reaches 0).
7. Leave the show on one card for more than a minute: it closes on every screen.
8. Your friend turns off "Show the crew's awards show on my screen" (`/tc`, Stats & Hall of Shame): start the show
   again, nothing opens on their screen.

## "Tell crew to update" button

Built too, every test outside the game passes (including an old and a new copy talking). **Not tried in the game
yet.** Riskiest first. Most of it only makes sense once friends have TwizCrew (after publishing), but the first two
checks work alone.

### Alone

1. **Does `/reload` load a new version?** This decides whether "Reload now" is enough. Ask Claude to make a pretend
   new version (Claude changes the version number in the files on this PC). Then, in the game, `/reload` (not a
   restart) and type `/tc report`:
   - The first line should say the **new** number (`TwizCrew v0.1.1`, say).
   - The line starting with `Update:` says what the game's own addon list says ("addon list says v…"). Tell Claude
     whether it shows the old or the new number: if it is the old one, the game only reads the addon's list of
     files when it starts, which is why updates that add files ask for a game restart.
   - Ask Claude to put the number back afterwards.
2. **The settings window** (`/tc`), under **Version check**:
   - A **Tell crew to update** button with an (i) next to it, and a **Crew versions** list with your name, "(you)"
     and your version.
   - Next to your name there should be a small **green tick** picture. If you see an empty square, a question mark
     box or nothing at all, tell Claude (the picture name would need changing).
   - Press **Tell crew to update**: chat says "told your crew that v… is out". Press it again right away: chat says
     to wait a few seconds. No error pop-ups.
3. Under **Modules** there is **Update reminders** with an (i), on. Turn it off, press **Reset everything to
   defaults**: it is on again.

### With a friend (after publishing)

Easiest when you have just released a new version and your friend still has the old one.

1. **Reload now.** Update yourself in WowUp, `/reload`, then press **Tell crew to update**. Your friend gets a small
   window "<you> says v… is out" with **Reload now** and "If nothing changed, open WowUp and click Update first".
   They update in WowUp, then click **Reload now**: the game reloads, and afterwards **Crew versions** shows a
   green tick next to both of you. If clicking **Reload now** does nothing, or shows "action blocked", tell Claude.
2. **Not updated yet.** Your friend clicks **Reload now** *without* updating in WowUp first. About 5 seconds after
   the reload, their chat says once: "Still on v…. Open WowUp, click Update, then /reload".
3. **In a fight.** Your friend starts a fight while the window is open: **Reload now** goes grey, and clicking it
   only says "not during a fight". Press the button again while they are fighting (after 30 seconds): their window
   only appears when the fight is over.
4. **Ticks and crosses.** While your friend is on the older version, **Crew versions** on your screen shows a red
   cross next to them. When they log off, their version becomes "?".
5. **Only newer counts.** Your friend (on the older version) presses **Tell crew to update**: nothing appears on
   your screen.
6. **Updates that add files** (Claude says so when releasing): the window says "Close and restart the game to load
   it" with no Reload button. After a full restart the version is right.
7. **Turned off.** Your friend turns off **Update reminders**: when you press the button, no window for them.

## Minimap button

Built, every test outside the game passes. **Not tried in the game yet.** Riskiest first. **Restart the game fully
first** (this update added files, so `/reload` is not enough).

1. **Is it there, and does it look right?** A round button with a gold ring sits on the left edge of the minimap,
   just below the middle, with a shouting-warrior icon inside. If you see a question mark, a green or black square,
   or no button at all, tell Claude. `/tc report` has a line starting `Minimap button:` that says `icon ok` or
   `icon missing`.
2. **No red error pop-ups** at login, while hovering it, clicking it or dragging it.
3. **Dragging.** Hold the left mouse button on it and move the mouse around the minimap: the button should follow
   the mouse around the edge, on the side the mouse is on. If it jumps to a different spot than your mouse, or
   goes off the edge, tell Claude. Let go, then `/reload`: it stays where you put it.
4. **Clicks.** Left-click: the TwizCrew settings window opens; left-click again: it closes. Right-click: the Crew
   panel disappears; right-click again: it comes back. No chat lines for these.
5. **In a fight.** Start a fight with something and left-click the button: the settings window should still open,
   with no "action blocked" message. Close it and finish the fight.
6. **Hover.** A small box says "TwizCrew", what left- and right-click do, "Drag: move it around the minimap" and
   "Crew online: …" (with friends online it counts them).
7. **The minimap's AddOns list** (only if your minimap has one: a small button on or near the minimap that lists
   addons; Questie's or OpenMap's entries are there too). TwizCrew should be listed, with the same icon. Click it:
   the settings open. Right-click it: the panel hides or shows. Hover it: the same box as above, without the drag
   line. If there is no such list, that is fine: nothing to check.
8. **Hide and bring back.** Open the settings (`/tc`): under **Essentials** there is **Minimap button** (always
   on) with an (i), and a **Show minimap button** switch with an (i). Turn the switch off: the button disappears.
   Type `/tc minimap`: it comes back and chat says "minimap button shown". Type `/tc minimap` again: it hides.
9. **Reset.** Drag the button somewhere else and hide it, then press **Reset everything to defaults** → **Yes**:
   the button comes back, at its starting spot.
10. **Does it cover anything?** If it sits on top of another minimap icon (Questie, the tracking icon, the mail
    icon…), drag it away and tell Claude which icon, so the starting spot can move.

## Test tools ("Try it out")

Pretend friends and pop-ups, so you can check things without waiting for your crew. **Only on your screen:** your
crew never sees them, nothing is saved, and they are gone after **Clear test stuff**, **Reset everything to
defaults** or `/reload`. Pretend names always end in **(test)**. No restart needed (no new files).

1. **Where they are.** `/tc`, scroll to the bottom: a section **Try it out**, a line **Test tools** "only on your
   screen" with an (i), then twelve buttons, each with an (i): **Fake friends**, **Copy of me**, **Ding**, **Death
   pop-up**, **Layer pop-up**, **Roast pop-up**, **Friend comes online**, **Congrats from a friend**, **Update notice (reload)**, **Update notice (restart)**,
   **Walking buddy**, **Clear test stuff**. `/tc test` in chat lists the same as commands (`/tc test fake`,
   `/tc test ding`...).
2. **No chat spam, no invites.** While you use them, chat should never say "No player named … is currently playing",
   and nobody gets a group invite (that would mean TwizCrew tried to reach a pretend friend).
3. **Each button once.** Press each one: a chat line or a pop-up, no red error. If chat says "that test did not
   work", type `/tc report` and tell Claude.
   - **Death pop-up:** "Testbuddy (test) died" with "Hillsbrad Foothills, Southshore" under it, and a red DEAD tag
     on Testbuddy's row for about 15 seconds.
   - **Layer pop-up:** press it a few times: "Testbuddy (test) is back on your layer", then "… is on a different
     layer", taking turns (about 3 seconds after the press). The OTHER LAYER tag comes and goes with it. Click the
     "different layer" pop-up: it closes and invites nobody.
   - **Roast pop-up:** an orange line about Testbuddy, a different one each press. Pressed again within 10 seconds,
     chat says why nothing showed.
4. **Clear test stuff:** every "(test)" row, the gold **!** and the gold line go away; chat says "test stuff
   cleared." Press it again: "nothing to clear." `/tc report` has a line `Test tools: nothing fake`.
5. **Your crew sees nothing** (when a friend is online): ask them whether a "(test)" name, a pop-up about
   Testbuddy or an "Update available" line showed up on their screen. Nothing should.

## Level progress (XP numbers, hover detail, "Ding!" pop-up)

Built, every test outside the game passes (including two copies where one earns XP and levels up). **Not tried in
the game yet.** Riskiest first. No restart needed (no new files). **You can do the first six alone** with the test
buttons (`/tc` → **Try it out**, see "Test tools" above).

1. **One ding on a real level-up (the riskiest).** Press **Copy of me**: a row "My copy (test)" appears. It is you,
   made from what your TwizCrew tells your crew, through the same code a friend's copy uses. Now play until you
   level up for real. Right after the game's own level-up you should get **exactly one** pop-up near the top: "**My
   copy (test) reached level N!**" (gold edge on the left) with a small line under it like "Only 47 to go." That is
   what your friends will see. Tell Claude if there was none, or two, or one while only earning XP.
   - Also press **Fake friends** and leave the game running for about 7 minutes: Testbuddy levels up by itself, and
     you should get exactly one "Testbuddy (test) reached level 13!".
   - **Ding** shows that pop-up at once, even right after you log in (normal pop-ups wait 30 seconds after login;
     test ones don't).
2. **The numbers match your own XP bar.** With **Copy of me** on, hover the "My copy (test)" row, then hover the
   game's own XP bar, and compare:
   - "Level 12 · 63%" with your level and the bar's percent;
   - "3,737 XP to level 13" with the bar's numbers (for "6,363 / 10,100 XP" it should say 10,100 - 6,363 = 3,737);
   - "Rested: 2,500 XP" with the bar's rested number (no rested line when you have none).
   The copy updates when your TwizCrew tells your crew (each whole percent, a level-up, a new zone, a fight
   starting or ending), so after a small kill it can be a little behind the bar until the next percent. Your
   friends see the same. If a number is off, kill one more mob, look again, and tell Claude what both said.
   At max level the tooltip says "Max level".
3. **The text fits in each row style.** Press **Fake friends**: Testbuddy, Maxbuddy and Offbuddy appear. Right-click
   the panel title → Row style, and check each style:
   - **Full:** Testbuddy's row has "Lv 12 · 63%" on the right of the purple XP bar; the bar is a bit shorter,
     nothing overlaps. The zone "Hillsbrad Foothills, Southshore" and the status "testing TwizCrew" fit or are cut,
     never drawn past the edge. Maxbuddy says "Lv 60 · max level" with no bar. Offbuddy is greyed out with "Offline,
     last seen 2h ago".
   - **Compact:** "Lv 12 · 63%" in the top-right corner. The long name "Testbuddy (test)" is cut, not drawn under it.
   - **Tiny:** "63%" in the top-right corner.
   - The tags on the top edge (FIGHTING, AFK, OTHER LAYER) still read fine next to the text.
   - Move the **Scale** slider in `/tc` too, in each style.
4. **The little dot.** "Lv 12 · 63%": the dot in the middle shows as a dot, not a box or a question mark.
5. **Hover Testbuddy:** a tooltip with "Testbuddy (test)" in pink (paladin), "Level 12 · 63%", "3,720 XP to level
   13" and "Rested: 2,500 XP". Testbuddy earns XP every 20 seconds: after about 3 minutes "About N min to level"
   appears, and the number goes down as it earns.
   - Hover a tag pill on the row, then move back onto the row: the row's tooltip comes back (or at least nothing
     sticks on screen).
6. **The level-up sound** (`/tc` → **Pop-ups** → **Level-up sound**, off by default): turn it on and press
   **Ding**: you should hear the game's own level-up sound. Tell Claude if it is silent or a different sound.
7. **Switches:** `/tc` → **Crew panel** → **Show level and XP numbers** and **XP details on hover**, and
   **Pop-ups** → **Level-ups**: each one turns its part off (try them with **Fake friends** and **Ding**; with
   Level-ups off, chat says so instead). **Reset everything to defaults** turns them back on (the sound stays off)
   and removes the pretend friends.
8. **With a friend (later), the real thing:**
   - When your friend levels up, you get one "<friend> reached level N!". Nothing on your friend's own screen (the
     game shows its own).
   - Log in or `/reload` while your friend is already a level higher than last time: no pop-up. Same when your
     friend logs back in after leveling elsewhere.
   - While a friend levels, nobody should see "too many messages" or get disconnected (the XP numbers ride on
     messages TwizCrew already sent).

## Update notice and version number

Built, every test outside the game passes (including an old and a new copy talking). **Not tried in the game yet.**
Riskiest first. No restart needed for this part on its own (no new files).

**Alone, with the test buttons:** press **Update notice (reload)** in `/tc` → **Try it out**. Testbuddy pretends to
have the next version, and the real update notice shows it (nothing is saved and your crew sees nothing). Do checks
1 to 4 and 6 to 7, then press **Update notice (restart)** for the other kind of window, then **Clear test stuff**.

1. **The gold "!" on the minimap button.** A small gold **!** sits at the top-right of the button's icon. Tell
   Claude if it is missing, hidden under the gold ring, far too big, or a box.
2. **The Crew panel's title** says **TwizCrew v…** in small grey after the name. Check it does not run into the
   "x of y online" text on the right, in the **Full** and **Compact** row styles (in **Tiny** the version is left
   out on purpose, the panel is too narrow).
3. **The gold line.** Under the title, a gold **Update available: v…** line. The tabs (Crew / Hall of Shame) and
   the rows must sit below it, not on top of it. Hover it: "Click for how to update". Click it: the small window
   opens.
4. **The pop-up:** "Update available: v…", then "Testbuddy (test) has it." (a friend's name, for real) and what to
   do. Check all the words fit inside the window (none cut off at the bottom or right).
   - **Update notice (reload)**: "Open WowUp and click Update, then press Reload now". Click **Reload now**: the
     game reloads (and the pretend update is gone afterwards). If it shows "action blocked", tell Claude.
   - **Update notice (restart)**: "Close WoW, open WowUp and click Update, then start WoW again", and an **OK**
     button.
   - Close the window and wait a minute: it does not come back by itself.
5. **Only once** (needs a real newer version from a friend): `/reload` while still on the older version: no pop-up
   this time (chat may say "Still on v…" once), but the gold **!** and the gold line are still there.
6. **Minimap tooltip.** Hover the button: the first line says **TwizCrew v…**, and the last line, in gold,
   "Update available: v… (Testbuddy (test) has it)".
7. **Turned off.** In `/tc` → **Modules**, turn off **Update reminders**: the **!** and the gold line go away, the
   version number stays. Turn it back on.
8. **Tell crew to update still works** (with a friend). When your friend is the older one and you press **Tell crew
   to update** within 30 seconds of logging in, they get one window ("<you> says v… is out"), not two.
9. **After updating for real:** no **!**, no gold line, no pop-up.

## Find the crew (arrows and meet-ups)

Built, every test outside the game passes. **Not tried in the game yet.** Riskiest first. **Restart the game fully
first** (this update added files, so `/reload` is not enough). Turn on Lua errors (`/console scriptErrors 1`).

### Alone

1. **Does the game tell TwizCrew where you are?** Type `/tc report` outdoors. The line `Find the crew:` should say
   `position ok (map …)` and `facing ok`. If it says `position unknown` or `facing unknown` outdoors, tell Claude:
   arrows can't work without it (facing unknown alone = the arrows work as a north-up compass with an "N").
2. **Walking buddy.** `/tc` → **Try it out** → **Walking buddy** (or `/tc test walk`). On the Crew panel,
   **Walkbuddy (test)** gets a small arrow and "80 yd" next to its name.
   - **Turn around on the spot:** the arrow should turn with you, like a compass needle that always points at
     Walkbuddy. If it turns the wrong way (you turn left, it turns left too, away from where it should point), or
     points backwards, tell Claude: the arrow picture or the turning direction needs flipping.
   - Walkbuddy walks in a circle around you: the arrow keeps moving slowly.
3. **The meet-up from the same button.** A blue-edged pop-up "Walkbuddy (test) wants to meet up", and the **big
   arrow** (top of the screen, a bit right of the middle) labelled "Meet Walkbuddy (test)" with "120 yd". Walk
   north: the distance goes down; at about 20 yards it says "You're here" and goes away.
4. **QuestMaster's arrow keeps working.** With a quest tracked in QuestMaster, do step 3 again: QuestMaster's own
   arrow and its marker in the world should stay on your quest the whole time. Our big arrow is a different colour,
   with a name under it.
5. **Map icon.** Open the world map while the meet-up is on: a small round TwizCrew icon sits 120 yards north of
   you. Hover it: "Meet-up: Walkbuddy (test)", minutes left. Zoom in and out, switch to the continent: it stays on
   the right spot (or hides on maps it isn't on). Same on **OpenMap's** stitched map.
6. **Minimap icon.** The same icon on the minimap, north of you. Walk far away (or zoom the minimap in): it sits on
   the minimap's edge. If you use a rotating minimap (`/console rotateMinimap 1`), it should stay pointing the right
   way as you turn.
7. **Ctrl + right-click on the world map.** Open the map and Ctrl + right-click a spot in your zone: a small menu
   "Meet here: everyone / Cancel" (with "my party" too when you're in a group). The map should **not** zoom out.
   Pick Cancel. Then check a plain right-click still zooms out as normal, and that OpenMap, Questie and QuestMaster
   map clicks still work. On the whole-world map the click says "pick a spot inside a zone".
8. **Big arrow.** Drag it somewhere else; `/reload`: it stays there. Lock the Crew panel: the big arrow can't be
   dragged either. `/tc` → Extras → **Find the crew** → **Big arrow size** changes it.
9. **Clean up.** Press **Walking buddy** again: Walkbuddy, its arrow, the meet-up and the icons all go.

### With a friend (both on this version)

1. **Group up** in the same zone and walk apart: each of you sees an arrow and the distance on the other's row.
   Leave the group: the arrows go away within a second or two. Out of a group, `/tc report` on both sides says
   `group members with positions: 0`.
2. **Click the row arrow:** the big arrow in their class colour with their name; walk to them: "You're here".
3. **Other zone:** one of you rides into the next zone: the row shows a still, dimmer arrow (no distance); clicking
   it gives the big arrow with "Westfall · 1.2k yd" style text.
4. **Party meet-up:** Ctrl + right-click your map → **Meet here: my party**: your friend gets the pop-up, the big
   arrow and the icons. A third friend who is **not** in the party gets nothing.
5. **Everyone meet-up:** → **Meet here: everyone**: friends outside the party get it too. A friend who logs in
   during the next 15 minutes gets it a few seconds after logging in.
6. **Clearing:** right-click the icon on the map (or `/tc meet clear`): it goes away for everyone.
7. **Dungeon:** go into a dungeon together: no arrows inside, no errors.

## Minimize, activity feed, peek and chat lines

New in the version after 0.1.23 (not released yet). **Needs a game restart** (three new files, a new key binding):
copy the addon in and restart the game, a `/reload` is not enough. Riskiest first. Pretend events (`/tc`, **Try it
out**, or `/tc test ...`) work for most of it without a friend.

1. **Does it still load?** No red errors at login, and the panel looks as before (one more small minus button at the
   far right of the title bar). In **Compact** and **Tiny** row styles the title bar must not overlap: the AFK button
   must not sit on top of "TwizCrew". Tell Claude which style looks cramped.
2. **Minimize.** Click the minus button on the title bar: the panel becomes just the bar (title, "N of M online", a
   plus button), same place, same width, nothing jumps. The What's new line (and the gold update line, if any) are gone.
   Click the plus (or the title) and it is all back. `/tc mini` and the key (Esc > Options > Keybindings > AddOns >
   TwizCrew > "Minimize or restore the crew panel") do the same. Right-click the bar: the menu has "Restore the
   panel". `/reload` while minimized: it comes back minimized.
3. **Minimize with the panel growing up.** Settings > Advanced > Panel > **Grow direction: Up**, drag the panel near
   the bottom of the screen, minimize and restore: the title bar must stay exactly where it was.
4. **Bar notice.** Minimize, then **Try it out > Fake friends**, then **Ding**: for about 6 seconds the bar shows
   "Testbuddy (test) reached level 13" (name in class colour) with a soft gold glow, and a red **1** appears left of
   the plus. Press **Death pop-up**, **Friend comes online** and **Congrats from a friend** quickly one after the
   other: they show one after another, none is skipped. The red number counts up; clicking it opens the **Recent
   activity** window and clears the number. Restoring the panel clears it too.
5. **Peek.** While minimized, the notice above also drops the panel open under the bar with only that friend's row
   (after a Ding it has a **Congrats** button), for 5 seconds, then it closes. Keep the mouse on it: it stays open
   until you move away. Turn **Peek at the friend** off (Basics): no drop-open, the bar notice still shows. Change
   **How long to peek** (Advanced > Panel). **Never in a fight:** press a pretend event while you are fighting
   something: the bar shows the text, but the panel does not open.
6. **Click the notice.** Ding while minimized and click the bar text: same as clicking the level-up pop-up (a
   congrats goes out). A pretend friend is never congratulated or whispered; use a real friend for this check.
7. **No doubling up.** Minimized, press **Ding**, **Death pop-up** and **Friend comes online**: no pop-ups, only the
   bar. Restore the panel and press them again: pop-ups as always. Minimize, turn **Show news on the bar, not as
   pop-ups** off (Advanced > Panel): both show. Layer pop-ups and roasts always still pop up.
8. **Open while my mouse is on the bar.** Turn it on (Advanced > Panel), minimize, hold the mouse on the bar: the whole
   panel opens; move away: it shrinks back. Off by default.
9. **Chat lines.** Press **Ding**, **Death pop-up**, **Congrats from a friend**: each prints one line in your chat
   (`TwizCrew: ...` in gold, the name in class colour; the congrats shows the words in quotes). **Friend comes
   online** prints nothing (off by default). Turn **Write events in my chat** off (Basics): no lines. Turn the
   per-kind switches (Advanced > Panel > Activity feed) on and off. Chat lines should print whether the panel is
   minimized or not. Nobody else ever sees them, and nothing is typed into any channel.
10. **Recent activity.** `/tc recent`, the wrench menu entry and the Activity feed's **Show recent activity** button
    open the list: newest first, class icon, "just now" / "5m ago", the line. Mouse wheel scrolls (more than ten
    lines). **Press Escape** closes it. `/reload`: the list is still there (the pretend ones are not). **Clear test
    stuff** removes the pretend lines. Open it for the first time in a fight: chat says it opens after the fight.
11. **With a real friend** (both on this version): their level-up, death, login and logout show in the list; a
    congrats and a mock they send you show with the words; after you press **Congrats** on their row, the list says
    "You congratulated ...". A friend logging in within two minutes of leaving (a /reload) is not listed. The first
    30 seconds after your login nothing is listed for logins, deaths and level-ups.
12. **Reset to defaults** brings the panel back from minimized and puts all the new switches back (peek on, 5 s,
    mouse-on-bar off, bar-instead-of-pop-ups on, chat on with died / level-up / congrats / mock). The list stays.
13. **Fade, lock, hide in fights** (all in Settings) still work with the panel minimized, and the notices stay fully
    visible when the panel is faded.

## Hardening pass (2026-11-12)

Nothing here is new to look at; these are fixes. None of it has run in the game. Riskiest first.

1. **Does everything still load?** The release adds files, so **restart the game** (not `/reload`). Chat says
   `TwizCrew v… loaded` once, and there is no red error. Open `/tc`, the calendar (`/tc cal`), the Recent window
   (`/tc recent`), the test tools (`/tc test`) and right-click a row and the panel title: every window and menu that
   was there before is still there. (The panel, the calendar and the test tools were split into more files.)
2. **Dungeon:** go into a dungeon with a friend and fight. The panel stays, nothing says "hit a problem and turned
   itself off", and after `/reload` `/tc report` shows no new lines under **Problems**.
3. **`/tc report`:** it has a **Problems** part (empty is good) and a line `Messages this session: …` with counts.
   If `send failed` is in that line with a number that keeps growing, tell Claude (the game may be throttling).
4. **With a friend, both on the new version:** die, then come back to life. The DEAD tag shows and goes on their
   screen. Stand in different zones for a few minutes: each other's zone stays right.
5. **Stats board with a friend:** open the Hall of Shame while they play. Their numbers never jump to 0 and back,
   and no "stole the crown" pop-up shows for a crown they did not really take.
6. **Calendar with a friend:** write a note with accents or emoji that fills the box (it stops at about 100
   letters, fewer with accents). It shows on their screen within a few seconds. Add a comment: same.
7. **Mixed versions:** with one friend still on v0.1.23, you still see each other online, each other's stats and
   notes. Note anything that only breaks in that mix.
8. **Mock show:** `/tc test` → Try a mock, drag the pop-up somewhere, close it, try again: it opens where you left
   it, and Live roasts stay on.
9. **Scale:** `/tc` → change Scale. The panel grows or shrinks in place; its corner does not move.
10. **Forget a friend:** right-click an offline friend → **Forget this friend**. They are gone from the Offline
    list and the all-time board. `/tc forget Name` does the same. (If they log in again they come back.)
11. **A module that broke comes back:** only if you ever see "…hit a problem and turned itself off": five minutes
    later it should be working again without `/reload`. Tell Claude either way.

## Guild conversion (2026-11-21)

TwizCrew now talks through your guild instead of the hidden channel. **None of this has run in the game.** Riskiest
first; stop at the first thing that looks wrong and tell Claude. You need the branch loaded (a `/reload` is enough)
and, for most checks, one guildmate online who also runs this version. Turn on `/console scriptErrors 1` first.

1. **`/tc guildtest`, with one other member online.** Type it once; it takes about 8 seconds. Typing it again within
   10 seconds only says "Wait N seconds before testing again." Lines, in this order:
   - Only while TwizCrew is not using this guild's data, a first line says why, for example `TwizCrew is not using
     this guild's data yet: it waits for the full guild list. If this stays, open the guild window and tick Show
     Offline Members.` or `... it has older saved data. Type /tc guild to choose what to do with it.` Normally there
     is no such line; if there is one, write it down.
   - `The game names the guild "<your guild>".` Bad: `The game gives no guild name.` **Tell Claude** (the addon then
     keeps one shared set of data for all your characters).
   - `Guild list: N counted, M readable, offline members included: yes.` N is how many members the game counted, M
     how many the addon could read. Good: M equals N (or is close) and `yes`. If it says `offline members included:
     no` (M is about the number online): open the guild window, tick **Show Offline Members**, run `/tc guildtest`
     again, and **tell Claude** what it said before and after (TwizCrew hides or forgets nobody, and does not decide
     about old data, until the list holds the offline members). `cannot tell`, or `?`: tell Claude.
   - `You are in the guild <name>: X members, Y online.` Good: plausible numbers. If instead you see
     `You are in the guild <name>, but the guild list has not loaded yet.` followed by `The guild list has not loaded
     yet, so there is no name to show.`, wait a minute and run it again (the addon asked the game for the list).
   - `A guild list name looks like "<First Last>", and zones are given / not given.` Write down what you see.
   - `Guild send: accepted; my own copy heard it back, sender shown as "<name>".` This is the big one: it says guild
     messages are delivered. Bad: `refused (result code ...)` or `did not hear it back`: **tell Claude, the whole
     conversion depends on it.** The name in quotes is how the game writes a sender on a guild message.
   - `These answered: <Name> in 0.4 s (whisper sender shown as "<name>").` Good: your guildmate's name and a short
     time. Bad: `Nobody answered (nobody else online with TwizCrew, or guild messages are not delivered).`, or
     `Nobody answered. If a friend with TwizCrew is online, replies may not be reaching you: the game gave only a first
     name.` while they are online with this version: **tell Claude.** (While TwizCrew is not using this guild's data
     this line reads `Answers cannot be counted while TwizCrew is not using this guild's data. See /tc guild.`)
   - A last line about chat lockdown (whether the game's lockdown check exists). Just report it.
2. **After `/reload`, a member with the addon appears.** Open the panel (`/tc show`). Your guildmate shows up within a
   minute, in the Guild online list (the bar "Guild online (N)": click it to open) or under your party if grouped.
   A friend from your old (v0.1.24) panel is pinned by itself: it has a gold star and sits in the main view (under the heading "Pinned" when a party or other rows are shown too).
3. **The first login after the update: does the old data attach by itself?** Look for your friends, stats, trophies
   and calendar notes from v0.1.24 (the Hall of Shame, `/tc cal`). Two outcomes are fine:
   - It attaches quietly (most of your saved friends are in the guild): everything is there, and **all the old
     friends are pinned** (a star on each row) in the main view.
   - Chat says: `TwizCrew has saved data from before it used guilds. If <your guild> is your crew's guild, type /tc
     guild use. To start fresh for <your guild>, type /tc guild new.` Nothing is lost. Type `/tc guild use`. The
     friend count is in two places: `/tc guild` shows each saved set with its number of friends, and if too few of
     them are in the guild `/tc guild use` answers `Only a of b saved friends are in <guild>. If this really is your
     crew's guild, type /tc guild use yes.` Normally you then type `/tc guild use yes`. After it, friends and stats
     are back and the old friends are pinned. (Do not type `new` here unless you want to start empty.)
   Tell Claude which one happened and the numbers.
4. **A non-member with the addon.** Ask someone not in your guild (same realm) to run the addon. They must not appear
   on your panel, and their mock or update notices must show nothing. (Skip if nobody can.)
5. **Panel look.** Sections top to bottom: my party, pinned, "Guild online (N)" bar, "Offline (N)" bar. Click the
   Guild online bar: it opens and stays as you left it after `/reload`. Click the green **+** on a row to pin it: it
   moves up; click the star to unpin (the row menu also has Pin to main view / Unpin). Members without the addon are
   dimmed with "no addon". A party row has the **+** too (left of it sits the arrow, they must not overlap); pinned,
   that member stays in the main view after the group ends. With no party and no pins the Guild online list starts open. Right-click the title bar:
   "Row style" there switches Full, Compact, Tiny, one step on each click; check all three: the **+** and the star
   must not sit on the Mock or Congrats buttons and must not look cut off. The header reads "N here · M online"
   (with a middle dot; "here" counts you). The star should be the raid-target star.
6. **Notices.** A guildmate who is not pinned and not in your party levels up: no pop-up, but the line is in the
   Recent list (`/tc recent`). Pin them, level up again: the pop-up shows. In `/tc`, the panel setting "Tell me
   about" has two choices, "My party and pinned" (default) and "Everyone in the guild". The Congrats button on a row
   works for anyone.
7. **A dungeon run with a guild party.** Go in, fight, come out. No red errors, and after `/reload` `/tc report` shows
   nothing under **Problems**.
8. **The old hidden channel is gone.** The addon leaves it on the first login (about 5 seconds after login); after
   that `/chatlist` (or the chat window's channel list) no longer shows the old TwizCrew channel, and after a
   `/reload`, `/tc report` shows no line with "comm" under **Problems**.
9. **An alt in another guild, or in no guild.**
   - Another guild: chat says `TwizCrew keeps separate data for each guild. Type /reload to switch to <that guild>.`
     (or `TwizCrew: <guild> has its own saved data. Type /reload to switch to it.`). Type `/reload` once; after it the
     alt has its own data, and the first time chat says `TwizCrew: <guild> starts with new TwizCrew data. You have
     other saved sets: type /tc guild.`
   - No guild: **no chat line**; the panel says `TwizCrew works inside a guild. Join one and it starts by itself.`
   - No red errors either way. Then log the main back in: friends and stats are untouched, and `/tc guild` on the main
     lists the alt's guild as a kept set.
10. **`/tc guild` reads sensibly.** It shows this character's guild, then "saved data" with numbered sets (0 is the
    one in use, with name, how many friends, last seen), and one line on what to type next if anything. Only read it.
    Do **not** try `new` or `load` on your main: they change which data is in use (nothing is deleted, but it is a
    recovery tool). Claude will say if you need them.
11. **Two members with the same first name** (only if your guild has such a pair). Both show on the panel, with
    separate stats; a mock aimed at one does not land on the other. `/tc forget` with the shared first word asks
    "which one?" and wants the full name.
12. **`/tc report`.** Under **Connection** it says "through the guild <name>" (or why nothing is sent); under **Guild**
    one line with your guild, member count and the result of the test (or "guild test not run").
13. **`/tc guild` right after login.** Type it about 10 seconds after logging in on your main (sooner, it may still say it has no guild name yet): the first line is
    `TwizCrew: this character's guild: <your guild>` and set 0 reads `0: <your guild> (in use), N friends ...`.
14. **A dungeon, with a guildmate outside.** Go into a dungeon alone or with a party while a guildmate with the addon
    stays outside. After 4 minutes inside: they still see you online on their panel; your `/tc report` (typed inside)
    says `Connection: through the guild <name>`; and you never appear as a row on your own panel.
15. **A friend who never had anyone on their old panel.** Ask one friend whose v0.1.24 panel was always empty what they
    see at their first login with this version. Good: no chat line about old data, and TwizCrew just works in the
    guild. Bad: `TwizCrew has saved data from before it used guilds...`: tell Claude.
16. **A guild change is noticed at login.** On an alt, leave its guild (or join another) and log out; log back in.
    Within about 10 seconds TwizCrew notices: the `Type /reload to switch to <guild>` line for another guild, or, for
    no guild, the panel line `TwizCrew works inside a guild. Join one and it starts by itself.` (the panel says
    `Waiting for the guild list…` for the first 10 seconds).

**Three things only the game can tell**; please write down what you see (`/tc guildtest` and `/tc report` help):
- What `UnitName` gives for a party member: one word ("Chaos") or two ("Chaos Deathbringr").
- Whether the guild list gives GUIDs (the addon works without, but identifies people more safely with).
- Whether offline members are in the guild list when the game's "Show Offline Members" box is unticked: `/tc
  guildtest` says `offline members included: no` then. TwizCrew depends on it: until the list holds the offline
  members it hides and forgets nobody and does not decide about old data (the panel says `Waiting for the full guild
  list. If this stays, open the guild window and tick Show Offline Members.`).

## Calendar button next to the tabs (2026-11-22)

Restart the game first (the files changed). Alone:

1. **The button is there.** Under the panel's title bar: `Crew`, `Hall of Shame`, `Calendar`. The small scroll icon
   that used to sit in the title bar is gone. No red error.
2. **It opens the calendar.** Click `Calendar`: the calendar window opens and the panel stays on its tab. Click it
   again: the window closes. Hover it: the tooltip says "Crew calendar".
3. **Narrow panel.** `/tc`, set the rows to tiny: the button says `Cal` and nothing overlaps or sticks out of the
   panel. Back to full rows: `Calendar` again.
4. **Stats off.** Turn "Stats & Hall of Shame" off in `/tc`: the bar stays with `Crew` and `Calendar`. Turn the
   calendar off too: the bar is gone. Turn both back on.

With a friend (any version with the calendar; only your copy needs this build, the pulse needs someone else's
note or answer):

5. **A new note pulses.** With your calendar closed, a friend adds a note for today or later. A soft gold glow
   fades in and out behind `Calendar` about every second and a half, and the word is brighter. Tell Claude if it is
   too faint, too strong or too fast.
6. **Opening it stops the pulse.** Open the calendar any way (`/tc cal` too): the glow stops at once.
7. **Answers on your note pulse.** You write a note; the friend clicks Going (or writes a comment) on it: it pulses.
   The friend only opening your note does not.
8. **Not for other people's chat.** Two friends commenting on a note that is not yours: no pulse.
9. **It is remembered.** A friend adds a note, you `/reload` (or log out and in) without opening the calendar: it
   still pulses.
10. **Minimized.** While it pulses, minimize the panel: no bar, no glow. Restore it: it pulses again.

## Calendar: Events and Play times (2026-11-22)

**Restart the game fully** (a file was added; `/reload` is not enough). Alone:

1. **It opens on Events.** Click `Calendar` on the panel (or `/tc cal`): two tabs, `Events` and `Play times`, and
   Events is the one open. The month shows no class icons and no hours. No red error.
2. **Notes on the month.** Add a note for today and two more for a day next week (`+ Create note`, or right-click a
   day). Each shows as a small line on its day: icon, time if it has one, the first words. A fourth note on one day
   makes the last line `+2 more`. Tell Claude if the words are too small or cut off badly.
3. **A dungeon run.** Create a dungeon run: its artwork fills the day, with the time and name on it.
4. **A day's list.** Click a day with notes: tall rows, one per note, with who wrote it. Click a row: the note
   opens as before. `Back to the month` goes back to the Events month. Past days look dimmer than today.
5. **Play times.** Click the `Play times` tab: the month with class icons and hours, and no notes or artwork on it.
   Click a day: the timeline, without a notes list under it. `Month` and `Usual times` next to the tabs switch
   between the month and the usual times, and they do not overlap the time zone text on the right.
6. **Across.** On a timeline, `This day's events` goes to that day on Events; on a day's events, `Who played this
   day` goes to its timeline. A note with a time still shows as a small mark under the timeline.
7. **It always opens on Events.** Leave the window on Play times, close it, open it again: Events.

With a friend:

8. **"new".** A friend adds a note for today or later. On the Events month that day has a gold `new`; in the day's
   list the note says `new`. Open the note: both are gone. Tell Claude if `new` is too easy to miss.

## Calendar: time zones (2026-11-22)

`/reload` is enough if the game was restarted since the Events / Play times change. Alone:

1. **Your zone by name.** Open the calendar: the top right says `Your time zone: CST` (not `UTC-6`). No red error.
2. **A new note.** Create a note with a time and open it: the line under the title says the time with `CST` after
   it. `+ Create note` says `your time (CST)`.
3. **The note from before.** The event you made earlier still shows its time, now with `CST`.

With a friend in another time zone (both on this build):

4. **Both times.** They add a note with a time. Your note window says your time and theirs, like
   `7pm CST your time · 8pm EST for Frostie`; the day's list says `8pm EST their time` after their name. Tell Claude
   if the line is cut off at the edge of the window.

## Calendar: edit and remove notes (2026-11-22)

`/reload` is enough if the game was restarted since the Events / Play times change. Alone:

1. **The note from the other computer.** Right-click the day of the City of Dalaran run (made on your other
   install): the menu has `Edit: ...` and `Remove: ...` for it. No red error.
2. **Edit.** Pick `Edit`: the window says `Edit note` and holds the note's day, time, dungeon and words. Change the
   time, `Save changes`: the same note shows the new time (not a second note).
3. **A day's list.** Click a day with a note of yours: its row has `Edit` and `Remove` buttons; right-click the row
   for the same choices. The buttons do not cover the words.
4. **The note's window.** Open a note of yours: `Edit my note` sits next to `Delete my note`.
5. **Remove.** Add a test note, right-click its day, `Remove: ...`: it is gone.

With a friend:

6. **They see the edit.** Edit a note they can see: their copy changes to the new words and time.

## Calendar size (2026-11-22)

`/reload` is enough if the game was restarted since the Events / Play times change.

1. **Bigger.** Open the calendar: it is clearly bigger than before and all of it is on the screen. Tell Claude if it
   is too big or still too small for a default.
2. **The slider.** Settings, the calendar's part, `Calendar size`: drag it with the calendar open. The window
   changes at once; the words stay sharp.

## Colored event days (2026-11-22)

`/reload` is enough if the game was restarted since the Events / Play times change.

1. **Colors.** On the Events month: a day with a plain note is tinted gold with a gold edge, a dungeon run has a
   blue edge around its artwork, a raid a purple one. Empty days are dark, with no edge.
2. **At a glance.** Look at the month from a step back: the planned days should be the first thing you see. Tell
   Claude if the color is too weak or too strong, and if the note words are still easy to read on the gold.
3. **Today.** Today's square still shows its gold line on top, with or without an event.

## Quest list (2026-11-22)

**Restart the game** (a new file was added; `/reload` is not enough). You need a friend who also has this version;
with a friend on the released version only step 6 can be checked.

1. **The menu.** Hover a friend's row, then right-click it: there is a line "Their quests (N you can get)". The
   first time it may say "(asking...)": close the menu and right-click again a second later.
2. **The list.** Click that line: a second menu opens under the row with "Ask to share: <quest>" for each quest
   you can get, "Can't share: <quest> (why)" for the others, and "N quests you both have" at the bottom. Compare it
   with your friend's real quest log: is anything missing or wrong?
3. **Asking.** In a group with them, click one "Ask to share" line: they get the usual pop-up, they click it, and
   the game offers you the quest. Try one that is not the quest shown on their row.
4. **The tooltip.** Hover their row: a green line "Can share N quests with you".
5. **The heads-up.** Leave the group, then group again: a pop-up "<Name> has N quests you can get" and a chat line,
   once. Click the pop-up: their quests open at the mouse. It should not come back each time they pick up a quest.
6. **A friend on the old version.** Their line stays "Their quests (asking...)", and clicking it says they may
   have an older TwizCrew. "Ask to share" for the quest on their row still works as before.
7. **Keeping up.** While grouped, your friend accepts a new quest: a few seconds later it is in their list on your
   side (right-click again).
8. **Switches.** Settings, Panel: "Tell me what my group can share" off = no pop-up. "Share my quests" off on your
   friend's side = their list is empty on yours.
9. **A refused share (the one to check first without Questie).** Ask a friend for a quest you are too low for (or
   whose earlier quest you have not done). After they click their pop-up, your chat should say "TwizCrew: <Name>
   couldn't share "<quest>": you can't take it yet (too low, or an earlier quest is missing)", and that quest
   should now be a "Can't share" line in their list. On their side the game itself prints a line like "<You> is not
   eligible for that quest": **if nothing arrives on yours, tell Claude the exact words their game printed.**
10. **Tell Claude:** is the count right without Questie (it can count quests you are too low for)? Is the pop-up
   useful or annoying?

## What to send back

- `/reload`, then tell Claude what you tried and what looked wrong. Claude reads the log file on this PC.
- From friends: the text from `/tc report` (Ctrl+C in the box, paste in Discord).
