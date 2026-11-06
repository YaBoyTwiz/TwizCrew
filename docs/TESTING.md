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

## Alone (riskiest first)

1. **Does it load at all?**
   - On the character screen, open **AddOns**: TwizCrew should be in the list and not marked "out of date".
   - In the game, chat should say `TwizCrew v0.1.0 loaded. Type /tc for settings.` once.
   - Type `/run print((select(4, GetBuildInfo())))`. It should print **16001**. If it prints a different number,
     tell Claude the number.

2. **No red error pop-ups** while you log in, play for a few minutes, fight something and `/reload`.
   Also no "action blocked" or "interface action failed" message during a fight.

3. **The hidden crew channel stays hidden.**
   - About 5 seconds after you log in, TwizCrew joins its own chat channel. You should **not** see a
     "Joined Channel: TwizCrewHQ" line in chat, and nothing from that channel should ever show up in chat.
   - General should still be channel 1 and Trade channel 2 (type `/chatlist` if you're not sure).
   - Type `/tc report`. The second line should say `Connection: auto (channel TwizCrewHQ joined)`.
     If it says `failed: sends to the channel were refused`, wait for the "next try in" time it shows and type
     `/tc report` again: it should say `joined` by then. If it still fails after a few tries, tell Claude.
   - Log out to the character screen and log back in. Check the same things again (the game may join the channel
     on its own at login, before TwizCrew does).

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

Do these **without being in a group** first: that proves the hidden channel works. Pop-ups stay quiet for the
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
5. **Offline friend, no chat spam.** In the settings, set **Connection** to **Whispers**, then have your friend log
   off. For the next two or three minutes you should **not** see "No player named … is currently playing" in chat.
   Set **Connection** back to **Automatic** afterwards.
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

## Update notice and version number

Built, every test outside the game passes (including an old and a new copy talking). **Not tried in the game yet.**
Riskiest first. No restart needed for this part on its own (no new files).

**How to see the notice without waiting for a release:** ask Claude to make your copy pretend to be an older
version (say v0.0.1; Claude changes the number on this PC), then `/reload` while a friend with TwizCrew is online.
Ask Claude to put the number back afterwards.

1. **The gold "!" on the minimap button.** With a friend online on a newer version, a small gold **!** sits at the
   top-right of the button's icon. Tell Claude if it is missing, hidden under the gold ring, far too big, or a box.
2. **The Crew panel's title** says **TwizCrew v…** in small grey after the name. Check it does not run into the
   "x of y online" text on the right, in the **Full** and **Compact** row styles (in **Tiny** the version is left
   out on purpose, the panel is too narrow).
3. **The gold line.** Under the title, a gold **Update available: v…** line. The tabs (Crew / Hall of Shame) and
   the rows must sit below it, not on top of it. Hover it: "Click for how to update". Click it: the small window
   opens.
4. **The pop-up**, about 30 seconds after your friend is heard: "Update available: v…", then "<friend> has it." and
   what to do. Check all the words fit inside the window (none cut off at the bottom or right).
   - With **Reload now**: "Open WowUp and click Update, then press Reload now". Click **Reload now**: the game
     reloads. If it shows "action blocked", tell Claude.
   - Without it: "Close WoW, open WowUp and click Update, then start WoW again", and an **OK** button. (Friends on
     v0.1.1 do not say whether a reload is enough, so you get this one.)
5. **Only once.** `/reload` while still on the older version: no pop-up this time (chat may say "Still on v…" once),
   but the gold **!** and the gold line are still there.
6. **Minimap tooltip.** Hover the button: the first line says **TwizCrew v…**, and the last line, in gold,
   "Update available: v… (<friend> has it)".
7. **Turned off.** In `/tc` → **Modules**, turn off **Update reminders**: the **!** and the gold line go away, the
   version number stays.
8. **Tell crew to update still works.** When your friend is the older one and you press **Tell crew to update**
   within 30 seconds of logging in, they get one window ("<you> says v… is out"), not two.
9. **After updating for real:** no **!**, no gold line, no pop-up.

## What to send back

- `/reload`, then tell Claude what you tried and what looked wrong. Claude reads the log file on this PC.
- From friends: the text from `/tc report` (Ctrl+C in the box, paste in Discord).
