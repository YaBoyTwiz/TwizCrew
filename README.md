# TwizCrew

A World of Warcraft: Forever addon for Twiz and friends. See which layer your crew is on and what they're doing,
roast each other with the Hall of Shame, and get told when there's an update.

It only does something when your friends run it too. Everything is shared through hidden addon messages, so other
players never see it.

## Install (once)

1. Install [WowUp](https://wowup.io) and point it at your WoW Forever folder.
2. In WowUp, go to **Get Addons**, click **Install from URL**, and paste:
   `https://github.com/YaBoyTwiz/TwizCrew`
3. Let WowUp update it for you:
   - In **My Addons**, right-click TwizCrew and tick **Auto Update**.
   - In WowUp's **Options**, under **Application**, turn on **Launch WowUp with system** and **Launch WowUp
     minimized** (and **Minimize on Close**, so closing the window keeps it running in the tray).

   Then WowUp starts with your computer and downloads updates before you even open WoW.
4. Start the game, click **AddOns** at character select and make sure **TwizCrew** is ticked.

No WowUp? Download the `TwizCrew-…-forever.zip` from [Releases](https://github.com/YaBoyTwiz/TwizCrew/releases)
and unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, so you get `AddOns/TwizCrew/TwizCrew.toc`.
You'll have to do that again for every update.

## Use

- `/tc` opens the settings. Every setting has an (i) that says what it does.
- `/tc awards` runs the awards show.
- `/tc report` prints a short report to paste to Twiz if something looks broken.

## Updating

Your version number is in the Crew panel's title and on the minimap button's tooltip. When a friend has a newer
TwizCrew, you'll see a gold **!** on the minimap button, a gold **Update available** line on the Crew panel, and a
small window (once per new version) that says what to do:

- **Reload now** button: open WowUp, click **Update**, then press **Reload now**.
- No button: close WoW, open WowUp and click **Update**, then start WoW again.

Lost the window? Click the gold line on the Crew panel to see it again.
