# Website and Discord: ideas (on hold)

**Status: on hold (owner, 2026-11-11).** Brainstorm only. Nothing here is approved, designed or built.
Everything below is Claude's pitch unless marked "owner".

## What the owner wants

- TwizCrew tied to a website, and later Discord. Website first; Discord is planning only for now, because the
  owner can't test much.
- The site starts as a subfolder of twizgame.com and later moves to its own domain. It must be built so the
  folder can be moved to a top-level domain and everything just works.
- Rethink the addon's features around what a website makes possible.

## The one big fact

The addon can't reach the internet. It only writes its save file (SavedVariables), and only at logout or
`/reload`.

So the link needs a **small helper program** on a PC:

- It reads the save file and sends it to the site.
- It can put a file from the site into the addon folder; the game reads it at the next login or `/reload`.

What follows:

- **Not live.** The site is "as of the last logout or reload". Good for history, planning and recaps; bad for
  "who is online right now".
- **Only the owner needs the helper at first.** The copies already swap most shared data with each other (stats,
  trophies, play times, notes), so one uploader fills the site. Friends install nothing new. (To check when this
  is picked up: exactly which data one copy holds about the others.)

## What the website is good for

1. **Things done outside the game.** The calendar fits best: make a dungeon night on a phone, friends sign up on
   the site, it appears in everyone's in-game calendar. Also fixes the "note made while nobody else was on" gap.
   This would be calendar step 2 (events, sign-ups, roles, reminders), done web-first.
2. **Permanent history.** Each session becomes a page: awards, Clown of the Night, deaths, steps. Trophy cases and
   all-time records per friend.
3. **Stream pages.** OBS can show a web page, so the Hall of Shame or the current clown can be an overlay (as
   fresh as the last upload).
4. **Site to game.** Custom roasts and custom awards written on the site arrive in the game.
5. **If friends run the helper too:** it can download new pictures and sounds into the addon folder (a `/reload`
   picks up new files in an existing addon folder). Unlocks a crew soundboard and custom pop-up art without a
   release, and could replace WowUp for updates.
6. **Fixing bugs.** The helper uploads the debug log, so a friend's error can be read without them sending files.

## Discord

- **First, no bot:** the website posts into a Discord channel by itself (a webhook). Examples: "Session recap is
  up", "Dungeon night in 1 hour, 4 going", "Frostie stole the Pauper crown".
- **Log in with Discord** on the site, so nobody needs a new password.
- **Later:** a real bot with commands and sign-up buttons.

## Moving to its own domain: rules from day one

- The site is fully self-contained in its folder, with its own data and its own login.
- Every link inside it is relative.
- The site's address lives in exactly one setting, in the site and in the helper.
- It shares nothing with the rest of twizgame.com.

The move is then: copy the folder, change one setting, update the address in the Discord login.

## Concerns

- **Much of the addon is still marked "not tried in game".** The website can be tested fully outside the game
  with a real save file, so it suits the owner's situation.
- **Privacy.** Play times and stats would be online. Suggest crew-only behind login, with only the pages the
  owner picks public for stream.
- **Trust.** Uploads come from a file on a PC that anyone could edit. Fine among friends; each crew member gets
  their own key.
- **Scope.** This is several projects; do them one at a time.

## Suggested order

1. Helper on the owner's PC plus a read-only site: session recaps, Hall of Shame, trophy cases, calendar view.
2. Discord posts from the site.
3. Site to game: events and sign-ups made on the web.
4. Helper for friends: pictures, sounds, updates, debug logs.
5. Discord bot and stream overlays.

## Open questions (ask when this is picked up again)

- What does twizgame.com run on (who hosts it; plain files, or a server and database)? Asked 2026-11-11, not
  answered yet.
- Would friends install a helper program, or should it stay owner-only?
- Which pages may be public for stream?
