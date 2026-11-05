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

## What to send back

- `/reload`, then tell Claude what you tried and what looked wrong. Claude reads the log file on this PC.
- From friends: the text from `/tc report` (Ctrl+C in the box, paste in Discord).
