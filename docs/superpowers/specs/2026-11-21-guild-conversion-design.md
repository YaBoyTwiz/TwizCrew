# Guild conversion (part 1 of 3): design

Date: 2026-11-21. Owner approved the direction in conversation; everything marked **(Claude's call)** was decided by
Claude and can be changed.

## Why

The owner is now guild master of a guild made of gaming buddies and regulars of the owner's live stream. It is small
and may grow a little. TwizCrew was built for about 5 friends with no guild: it finds copies through a hidden chat
channel (which WoW Forever never delivers messages on) and sends every message as one whisper per friend. Nothing
checks who a sender is, so anyone on the realm who installs the addon can appear in the panel and put words on a
streamed screen.

A guild fixes both: one `GUILD` addon message reaches every online member, and guild membership (which the guild
master controls) says who is trusted.

Owner's words: "make it guild only"; everyone has the same powers ("its fine for now"); the panel shows "by default
just the ones in your party, but have a drop down tab just like we have with offline where we can see the others and
maybe a way to click to add them to the main view or remove them".

## The three parts (owner agreed to this order: "do it")

1. **Guild conversion (this document).** Messages through the guild, only guild members trusted, the new panel
   layout. Own release.
2. **The Guild Board** (later, own design): looking-for-group cards, planned runs saved as game calendar guild events
   with sign-ups (the game's own sign-up first, copies passing cards on as a backup), automatic matches from shared
   quests, one-click posting, a "Tell guild chat" button, a pinned guild master message.
3. **Guild-wide Hall of Shame and guild news** (later, own design): weekly crowns, a news column.

A website tie-in may come after that. Nothing in part 1 should make it harder (keep member data keyed in a way that
could be exported), but nothing is built for it.

## Goals

- One send reaches the guild: broadcasts use the `GUILD` addon channel.
- Only guild members are trusted. A message from anyone else is dropped.
- The panel works for a guild of up to about 50 online members without clutter: party and pinned people in view,
  everyone else one click away.
- Guild members without the addon are visible (dimmed), from the game's guild list.
- Everything that works today (tags, layers, stats, awards show, calendar notes, mocks, congrats, find the crew,
  quest shares, update notices, minimize, activity feed, test tools) keeps working, now across the guild.

## Not in this part

- The board, planned runs, calendar guild events, guild news, weekly crowns (parts 2 and 3).
- Rank-based permissions (owner: fine for now).
- Friends outside the guild, alts outside the guild (owner: guild only).
- Posting anything in real guild chat.

## Must never happen

- A message from someone outside the guild changes anything on screen or in saved data.
- A guild member loses their saved stats, trophies or calendar notes because of the conversion.
- The addon throws errors or spams when the character is not in a guild.
- More sends than today in a normal session.

## What the game allows (research 2026-11-21, other addon makers, not tried by us)

- `C_ChatInfo.SendAddonMessage(prefix, text, "GUILD")` is delivered on Forever 1.60.1 (result 0, received, also by
  the sender).
- `AreOutgoingAddonChatMessagesRestricted()` is true in the open world although guild and whisper addon messages go
  through. Do not hold the queue on it. Hold on `InChatMessagingLockdown()` (when the function exists) and on a
  lockdown or throttle send result.
- Guild list names come "with spaces, without a realm" (Forever names are "First Last"). Each entry has GUID, class,
  level, rank name and index, note, online, last online. Zone was not confirmed.
- Addons cannot write officer notes or the guild info text.
- Trial and veteran accounts cannot send addon messages: such a member looks like "no addon".
- Custom channels never deliver addon messages (seen by us and by others).

**Because none of this was tried by us, the first thing built is a check the owner runs in the game** (see "Proving
it in the game").

## Design

### 1. Sending

| Message kind | Today | New |
|---|---|---|
| To everyone (`Comm.send`) | group + one whisper per friend + channel copy | one `GUILD` message |
| To one person (`Comm.sendTo`) | whisper | whisper, only to a guild member |
| To the group (`Comm.sendGroup`) | `PARTY` / `RAID` | unchanged |

- The hidden channel is gone: no join, no member list, no retry machine. On the first start after the update the
  addon leaves the old channel once so it disappears from chat windows. **(Claude's call)**
- The "Connection" setting (Automatic / Hidden channel / Whispers / Group chat / Guild chat) is removed.
  **(Claude's call)**
- Group-only messages (positions for Find the crew) stay on `PARTY` / `RAID`, and are accepted only from guild
  members like everything else.
- The queue (about 2 sends a second, bulk lane, retry cap, "send failed" counter) stays, and its existing "has to
  wait" path is reused: it pauses during a chat lockdown (`InChatMessagingLockdown()`, when that function exists) and
  on a lockdown or throttle send result (`Enum.SendAddonMessageResult`, as `Transport.send` reads today), and carries
  on afterwards. When the function does not exist, only the send results hold it.
- A message goes one way only: `Comm.send` sends the `GUILD` copy and nothing else (no extra party copy), so a member
  who is in my party and my guild never gets the same message twice.
- A plain "Guild chat" connection mode already exists in `Transport.destinations`; the new sending replaces all the
  modes. A saved "Connection" choice is ignored and removed.
- Replies that used to be one whisper back per listener stay whispers (a login gets a HELLO and STATE whisper from
  each online copy). With many members online, each copy waits a random 0 to 5 seconds before answering a newcomer so
  the replies do not arrive in one burst. **(Claude's call)**
- Pairwise swaps (calendar notes, trophy records, state repair) stay whispers in the bulk lane.

### 2. Who is trusted

- A message that arrives on `GUILD` is from a guild member by definition: accepted.
- A message that arrives by whisper, `PARTY` or `RAID` is accepted only when the sender is in the guild list.
- Until the guild list has loaded for the first time, whisper and group messages are dropped (the state repair that
  already exists fixes anything missed within about two minutes). **(Claude's call)**
- Dropped messages are counted in `/tc report` ("recv not in guild"), not logged one by one.
- The "stranger says hello, answer them" path only answers guild members.

### 3. The guild list (new piece)

One new module reads the game's guild list and is the single source for "who is in the guild":

- Asks the game to refresh the list at login, then every 30 seconds while the panel is shown and every 2 minutes
  otherwise (the game allows one request per 10 seconds), and listens for the game's roster update event.
  **(Claude's call on the numbers)**
- Gives the rest of the addon: is this name in the guild; and per member: name as the game writes it, class, level,
  zone (if the game gives it), rank, online, last online.
- Every game read goes through `ns.Util.plain` (the dungeon rule).
- When the character is in no guild: the list is empty, nothing is sent, and the panel shows one line: "TwizCrew
  works inside a guild. Join one and it starts by itself." The test tools still work.

**Names and identity.** Today a friend is stored under the first word of their name ("Chaos" for "Chaos
Deathbringr"), and "is this me?" (`ns.isMe`) also compares first words only. In a guild two members can share a first
name, and one sharing mine would have every message dropped. **(Claude's calls, revised while planning: the first
word stays the normal key, because it is the one thing that is the same however the game writes a name on a guild
message, a whisper, a party message and in the guild list, and because it needs no change to saved data)**:

- A member's key is the first word of their name, as today, unless another guild member already holds that first
  word: then the later one's key is their full name. A key, once given, is remembered (saved per full name), so it
  never changes when someone else joins. Existing v0.1.24 data therefore carries over untouched.
- When two members share a first word and the saved data has that first word: the one whose class matches the saved
  class keeps it; otherwise the first in A-Z order of full names.
- "Is this me?" compares full names when my own full name is known (my entry in the guild list) and the other name
  has more than one word; otherwise first words, as today.
- A name inside a message (a mock's target, a vote) is the key. An old copy that sends a first word still matches,
  unless it is the full-name-keyed one of two namesakes.
- Rows show the first name; two members on the panel with the same first name both show their full name.
- No identity is put inside messages: the chat sender is the identity. A whisper needs the full name, which comes
  from the guild list.
- Requirement either way: two members with the same first name both show up and their data never mixes.

**Timing at login.** `IsInGuild()` may be false for a moment while the game loads. The first HELLO goes out as soon as
the character is known to be in a guild (it does not wait for the full list); nothing is sent before that. "Not in a
guild" is only shown after 10 seconds of the game saying so. **(Claude's call)**

### 4. Who is on the panel

Four sections, top to bottom (mockup shown to the owner 2026-11-21, owner: "yes"):

1. **My party**: guild members in my party or raid. No heading when I am not in a group.
2. **Pinned**: members I pinned, online ones only (a pinned member who is offline sits in Offline, with the star).
3. **Guild online (N)** bar, closed by default: every other online member. Click to open or close; remembered.
4. **Offline (N)** bar, closed by default, as today: every offline member, "last seen" from the addon's own record,
   else from the guild list's last-online time.

- **Pinning:** a green "+" on a row in the Guild online or Offline list pins that member; a gold star on a pinned row
  unpins. Also in the row's right-click menu ("Pin to main view" / "Unpin"). Pins are saved per account.
  **(Claude's call: per account)**
- **Members without the addon** are shown dimmed with name, class, level and zone from the guild list, and the words
  "no addon". No tags, no layer, no Congrats button. Setting "Show guild members without the addon", default on.
  **(Claude's idea; owner saw it in the mockup)**
- A party member who is not in the guild is not shown, and their Find the crew positions and other group messages
  are ignored (guild only).
- The header count becomes "3 here · 14 online": people in the main view, and guild members online.
- Sorting inside each section follows the existing sort setting.
- Existing row sizes (normal, compact, tiny), minimize, peek, the missed number and the row menu keep working.
- With no pins and no party, the main view would be empty: then the Guild online list starts open.
  **(Claude's call)**

### 5. Noise

With 15 or more members, "X is online" for every one of them is too much. Pop-ups, bar notices and chat lines for
coming online, going offline, level-ups and deaths fire for **party and pinned members** by default. One setting,
"Tell me about: my party and pinned / everyone in the guild". The Recent activity list records everyone either way.
Mocks, congrats and roasts aimed at me always show. **(Claude's call)**

### 6. Moving over saved data

- Friends in saved data who are in the guild: kept, with stats, trophies, notes.
- Friends who are not in the guild once the guild list has loaded: hidden at once, and their saved data is dropped
  after 30 days out of the guild (so a kick by mistake or a guild hop does not wipe history). **(Claude's call)**
- A member who leaves the guild later is treated the same way.
- The 30 days count from the first time a successfully loaded guild list did not contain them (saved per member).
  Nothing is hidden or dropped before the guild list has loaded at least once in that session.
- "Forget a friend" (`/tc forget`, the row menu) stays for offline members' saved data.
- Nobody is pinned after the update. The existing "Show offline friends" choice carries over to the Offline bar.

### 7. Old and new versions together

Old copies (v0.1.24 and before) do not look at how a message arrived, so they should still hear a new copy's guild
messages, and a new copy accepts an old copy's whispers when the sender is in the guild. So a half-updated guild
should mostly keep working, but this is not designed for and not tested: the message format number is not raised,
and the release notes tell everyone to update. **(Claude's call)**

### 8. Words on screen

The addon keeps calling the people "the crew". "Tell crew to update", "Offline friends" and similar labels stay
unless they are wrong for a guild; the builder adjusts those that read oddly. Version: **0.2.0**. The release needs
`RESTART_SINCE` (files added and removed).

## Proving it in the game

Before the rest is trusted, the owner runs one command with one other member online, `/tc guildtest`
**(Claude's call)**. It prints, in plain words:

- whether a guild addon message was accepted, and whether my own copy heard it back;
- whether another copy answered (who, how long it took);
- what a guild list name looks like, what a sender's name looks like on a guild message and on a whisper, and
  whether a whisper to a full name arrives;
- whether the list gives zones;
- whether the chat-lockdown check exists in this game.

`/tc report` gets the same facts under a "Guild" heading. If guild messages turn out not to be delivered, the
conversion is not released and we go back to the owner.

## Tests outside the game

The test stub gets a guild: a guild list, the `GUILD` chat type delivering to every stub copy in the guild, and
copies outside the guild. Required cases (the builder adds the rest):

- A broadcast is one send, whatever the guild size.
- A whisper, party or guild-channel message from a non-member changes nothing.
- A whisper from a member before the guild list loads is dropped, and the state is repaired afterwards.
- Not in a guild: no sends, no errors, the "works inside a guild" line.
- Two members with the same first name both appear and keep separate data.
- Panel sections: party, pinned, guild online, offline; pin and unpin; the open-by-default rule; members without the
  addon; the notice rule for party and pinned only.
- Saved data from v0.1.24 loads: members kept, non-members hidden and dropped after 30 days.
- The five-copy simulations that exist today still pass, now over the guild.
- `tests/run.sh` ends with `ALL PASSED`.

## Left to the builder

- How member data is keyed (see Names).
- Which parts of `Comm/Transport.lua` survive; it is expected to shrink a lot.
- File layout for the guild list module and the panel sections.
- Exact wording of labels and settings, in the addon's plain style.
- The 78 older tests that assume the hidden channel delivers: rewrite or remove them as the channel goes away.
