# Guild Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TwizCrew talks through the guild: one `GUILD` addon message per broadcast, only guild members trusted, and a panel with party, pinned, "Guild online" and "Offline" sections.

**Architecture:** A new module `ns.Guild` reads the game's guild list and is the single answer to "who is in the guild, what is their key, what is their full name". `Comm/Transport.lua` loses the hidden channel and the whisper fan-out and becomes a thin router (GUILD / WHISPER to a member / PARTY-RAID). `Comm.lua` drops anything from a non-member before it is decoded. The roster keeps its first-word keys; the panel groups its rows into sections.

**Tech Stack:** Lua 5.1 (WoW Forever, interface 16001). Tests: `tests/run.sh` (plain Lua 5.1 against `tests/wowstub.lua`). No libraries.

**Spec:** `docs/superpowers/specs/2026-11-21-guild-conversion-design.md` (binding). Game limits: `PROJECT.md`, sections "What an addon can and cannot do in WoW Forever" and the 2026-11-21 research note under "The crew".

## Global Constraints

- Lua 5.1 only: no `goto`, no `//`, no bit operators, no `require`, `io` or `os` in addon files. No new globals.
- One addon message is at most 255 bytes (`ns.Config.MAX_MESSAGE`). Never more sends than today in a normal session.
- Every yes/no, number or string from a `Unit*`, `Is*`, `Get*`, `C_*` game call goes through `ns.Util.plain(fn, ...)` before it is tested (`tests/test_lint.lua` enforces a list; add the guild functions to it).
- Never create, show, hide, move or resize a secure/protected frame in combat. Plain frames are allowed.
- Every handler that the game or a timer calls runs inside `ns.Log.safe(featureId, fn, ...)`.
- Text shown to players is plain, short English. Every new setting needs an `info` text.
- A message from a non-member never changes the screen or saved data. A guild member's saved stats, trophies and notes survive the conversion.
- Not in a guild: no sends, no errors.
- The message format number (`ns.Config.PROTOCOL`) is not raised. No field of an existing message changes meaning.
- Do **not** bump `ADDON_VERSION`, `## Version`, `RESTART_SINCE`, or add a `Changelog.lua` entry. Do not push, tag or release. Commit on the branch `guild-conversion` only.
- New files are added to `TwizCrew/TwizCrew.toc` in load order; removed files are taken out.
- `tests/run.sh` must end with `ALL PASSED` before every commit. One file: `tests/run.sh <pattern>`.
- Commit messages end with the line `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` (or the implementing model's own name if the harness says so).
- Never write the owner's WoW account folder name into the repository.

## Review Focus

- A whisper or party message from someone outside the guild (including one that looks like a valid MOCK, CAL note or "update" notice): nothing changes, one counter goes up (Task 3).
- Two guild members whose names start with the same word, one of them possibly sharing my first word: both appear, data never mixes, my own messages are still recognised as mine and theirs are not (Tasks 1, 3, 4).
- The game writes a name differently on a guild message, a whisper, a party message and in the guild list ("Chaos", "Chaos Deathbringr", "Chaos Deathbringr-Realm"): all resolve to the same member (Task 1).
- The guild list is empty or late at login, or the character is in no guild, or leaves the guild mid-session: no errors, no sends, nothing wiped (Tasks 1, 3, 4).
- 50 members online: a login costs a bounded number of sends and the panel stays usable (Tasks 3, 5).

---

### Task 1: Guild list module and a guild in the test stub

**Files:**
- Create: `TwizCrew/Crew/Guild.lua` (in the `.toc` right after `Core\DB.lua`, before `Comm\Codec.lua`)
- Modify: `tests/wowstub.lua`, `tests/run.lua` (harness: clients share one guild), `tests/test_lint.lua`, `TwizCrew/Core/DB.lua` (default `guild = { keys = {} }`)
- Test: `tests/test_guild.lua` (new)

**Interfaces:**
- Consumes: `ns.Util.plain`, `ns.Events.on`, `ns.Bus`, `ns.Log`, `ns.shortName`, `ns.db.guild.keys`.
- Produces (`ns.Guild`):
  - `Guild.start()`: registers `GUILD_ROSTER_UPDATE`, `PLAYER_GUILD_UPDATE`; asks for the list; ticker for refreshes.
  - `Guild.inGuild() -> boolean`; `Guild.loaded() -> boolean` (a non-empty list was read at least once this session).
  - `Guild.refresh()`: asks the game for a fresh list, at most once per `ns.Config.GUILD_REFRESH_MIN` (10) seconds. `Guild.setWatched(on)`: refresh every `GUILD_REFRESH_SHOWN` (30) s when on, `GUILD_REFRESH_HIDDEN` (120) s when off.
  - `Guild.members() -> array` of entries `{ key, full, first, class (file token, e.g. "DRUID"), level, zone, rank, rankIndex, online, lastOnline (wall-clock seconds or nil), guid }`, me included. `Guild.get(key) -> entry | nil`. `Guild.count() -> online, total`.
  - `Guild.keyOf(rawName) -> key | nil`: the member a raw game name belongs to (any form: first word, full name, with or without `-Realm`); nil when not a member or the list is not loaded.
  - `Guild.isMember(rawName) -> boolean`; `Guild.fullName(key) -> string | nil` (what a whisper needs); `Guild.display(key) -> string` (first word, or full name while another listed member shares the first word).
  - `Guild.myKey() -> key | nil`; `Guild.isMe(rawName) -> boolean` (full names when mine is known and the other has several words, else first words).
  - Bus events: `GUILD_LIST` (after every read that changed anything, and after the first read), `GUILD_STATE (inGuild)` when membership flips. "Not in a guild" is only announced after `ns.Config.GUILD_ABSENT_GRACE` (10) seconds of the game saying so.
- Stub (`W.state.guild`): `{ name = "Test Guild", members = { { name = "Chaos Deathbringr", class = "WARRIOR", level = 31, zone = "Stonetalon", rank = "Member", rankIndex = 2, online = true, guid = "Player-1-0001", lastOnline = { 0, 0, 3, 5 } }, ... } }`; `IsInGuild`, `GetNumGuildMembers`, `GetGuildRosterInfo(i)` (retail return order, GUID 17th), `GetGuildRosterLastOnline(i)`, `C_GuildInfo.GuildRoster()` (counts calls, fires `GUILD_ROSTER_UPDATE`), `GetGuildInfo("player")`, `UnitGUID("player")`. `SendAddonMessage(..., "GUILD")` outside a guild is recorded with a non-success result. In the multi-client harness a `GUILD` send is delivered to every client in the same guild including the sender, with the sender's name in the form `W.state.senderForm` chooses ("full" default, "first", "realm").

**Key rule** (spec, "Names and identity"): key = first word, unless `ns.db.guild.keys` or the current list already gives that first word (case-insensitive) to a different full name; then key = full name. `ns.db.guild.keys[lower(full)] = key` is written the first time a member is seen and never changed. Tie when two namesakes are first seen in the same read and saved roster data has that first word: the one whose class equals `ns.db.roster[first].class` gets the first word, else the A-Z first full name.

- [ ] **Step 1: Extend the stub and harness**, with tests in `tests/test_stub.lua` for: guild list calls return what `W.state.guild` holds; a `GUILD` send reaches every client in the guild and nobody outside it; the three sender forms.
- [ ] **Step 2: Write failing tests** in `tests/test_guild.lua`:
  - `members_come_from_the_game_list`, `not_in_a_guild_is_empty_and_quiet` (no error, `inGuild()` false, `GUILD_STATE` only after 10 s).
  - `key_is_first_word`, `namesakes_get_full_name_key`, `key_never_changes_when_a_namesake_joins_later`, `saved_class_decides_who_keeps_the_first_word`.
  - `keyOf_accepts_every_name_form`: "Chaos", "chaos deathbringr", "Chaos Deathbringr-Realm" → same key; a stranger → nil; before the first read → nil.
  - `isMe_with_a_namesake`: I am "Chaos Deathbringr", member "Chaos Other" exists: `isMe("Chaos Other")` false, `isMe("Chaos Deathbringr")` true, `isMe("Chaos")` true.
  - `refresh_is_throttled` (two calls within 10 s = one request), `watched_refreshes_every_30s`, `secret_values_do_not_raise` (list functions returning `W.secret()`), `last_online_becomes_wall_seconds`.
- [ ] **Step 3: Run them, see them fail.** `tests/run.sh test_guild`
- [ ] **Step 4: Implement `Crew/Guild.lua`**; register module id `guild` (tier essential, name "Guild list") so the breaker and `/tc report` know it. Add the guild functions to the lint rule's list.
- [ ] **Step 5:** `tests/run.sh` → `ALL PASSED`. Commit: `feat: guild list module and a guild in the test stub`.

### Task 2: `/tc guildtest` and the report's Guild section

**Files:**
- Create: `TwizCrew/UI/GuildTest.lua` (in the `.toc` after `UI\Report.lua`'s line or next to the other command helpers)
- Modify: `TwizCrew/UI/Commands.lua` (command `guildtest`, help line), `TwizCrew/UI/Report.lua`, `TwizCrew/Comm/Comm.lua` (a hook so the probe sees raw sender names: `Comm.onRaw(fn)` called with `prefix-matched (text, chatType, rawSender)` before any filtering)
- Test: `tests/test_guildtest.lua` (new)

**Interfaces:**
- Consumes: `ns.Guild` (Task 1), `ns.Comm.on`, `ns.Comm.send`, `ns.Comm.sendTo`.
- Produces: message types `GPROBE { n = nonce }` (to the guild) and `GPONG { n = nonce }` (whisper back to the sender); `ns.GuildTest.run()`, `ns.GuildTest.facts() -> table` (last results, for the report). Both types are harmless to old copies (unknown types are ignored).

Printed lines, in this order, each one sentence (exact wording is the implementer's, plain English):
1. In a guild or not; guild name; members total / online.
2. What a guild list name looks like (first entry that is not me) and whether zones are given.
3. Whether the guild send was accepted (result code) and whether my own copy heard it back within 3 s, with the sender form it saw.
4. After 8 s: who answered (key, seconds), the sender form on their whisper; or "nobody answered (nobody else online with TwizCrew, or guild messages are not delivered)".
5. Whether `InChatMessagingLockdown` exists; what `AreOutgoingAddonChatMessagesRestricted()` says right now.

- [ ] **Step 1: Failing tests:** `probe_reports_echo_and_answer` (two clients in a guild), `probe_alone_says_nobody_answered`, `probe_outside_a_guild_says_so_and_sends_nothing`, `report_has_a_guild_section`, `old_copy_ignores_gprobe` (no error from an unknown type).
- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement.** GPONG answers are rate limited to one per sender per 10 s.
- [ ] **Step 4:** `tests/run.sh` → `ALL PASSED`. Commit: `feat: /tc guildtest probe and Guild section in /tc report`.

### Task 3: Sending through the guild, and trusting only members

**Files:**
- Modify: `TwizCrew/Comm/Transport.lua` (rewrite; expected to shrink to roughly 150 lines), `TwizCrew/Comm/Comm.lua`, `TwizCrew/Comm/Queue.lua` (only if the hold needs it), `TwizCrew/Core/Init.lua` (`ns.isMe` delegates to `ns.Guild.isMe` when the guild module is loaded; config numbers), `TwizCrew/Core/DB.lua` (drop `crew.channel` / `crew.password` defaults; keep `crew.extra` only if still used), `TwizCrew/Crew/Crew.lua` (hello / ping / reply paths), `TwizCrew/UI/Report.lua`, any file that calls `Transport.members`, `Transport.rejoin`, `Transport.heardFrom`, `Transport.status`, `Comm.echoCount`
- Test: `tests/test_comm.lua`, `tests/test_crew.lua`, `tests/test_sim.lua`, `tests/test_sim_stats.lua`, `tests/test_sim_find.lua`, `tests/run.lua` (remove the forced `echoCount`), every test that set up the hidden channel

**Interfaces:**
- Consumes: `ns.Guild.inGuild / loaded / keyOf / isMember / fullName / isMe` (Task 1).
- Produces:
  - `Transport.destinations(msgType) -> { { chatType = "GUILD" } }` in a guild, `{}` otherwise.
  - `Transport.destinationFor(name) -> { chatType = "WHISPER", target = Guild.fullName(key) } | nil` (nil for a non-member, for me, or when the list is not loaded).
  - `Transport.groupDestination()` unchanged. `Transport.fullName(name)` now answers from `ns.Guild`.
  - `Transport.isPending() -> boolean`: true only while the game has not yet said whether the character is in a guild (the first `GUILD_ABSENT_GRACE` seconds at most); `TRANSPORT_READY` fires when that settles.
  - `Transport.send(text, dest) -> sent, retryLater`: unchanged contract; retryLater also for a lockdown result.
  - `Transport.status() -> { mode = "guild" | "none", guild = name, lockdown = boolean }`.
  - Removed: every channel function, `Transport.members`, `Transport.rejoin`, `Transport.heardFrom`, `Transport.forget`, `Comm.echoCount`, the `transport`, `channel` and `password` settings.
  - `Comm` receive rule, applied before decoding: sender is me (`ns.Guild.isMe`) → ignore; `chatType == "GUILD"` → accept, sender key = `Guild.keyOf(raw)` or, when the list has not loaded yet, `ns.shortName(raw)`; any other chat type → accept only when `Guild.keyOf(raw)` is not nil, else `ns.Log.count("recv not in guild")` and drop. Handlers receive the key as `sender`.
  - `Comm.sendTo(name, ...)` returns false when `destinationFor` is nil (callers already fall back to a broadcast).
- Behaviour:
  - First start after the update: if the saved `crew.channel` exists, `LeaveChannelByName` it once, then clear `ns.db.crew.channel` and `ns.db.crew.password`; delete the saved `transport` setting.
  - The queue holds while `InChatMessagingLockdown()` is true (when the function exists, read through `ns.Util.plain`), checked each pump; the existing encounter hold stays.
  - HELLO goes out when `TRANSPORT_READY` fires in a guild. Answering a newcomer's HELLO (whisper HELLO + STATE) waits a random 0 to `ns.Config.HELLO_REPLY_JITTER` (5) seconds; one pending answer per newcomer.
  - PING (the once-a-minute digest) is one `GUILD` message; the "PING to every roster name in fallback mode" path is deleted.
  - The dedupe by route in `Comm.onAddon` stays (a message could still arrive twice from an old copy).

- [ ] **Step 1: Failing tests** (new or rewritten):
  - `broadcast_is_one_guild_send` with 2, 10 and 50 stub members.
  - `whisper_from_a_stranger_is_dropped_and_counted`, `party_message_from_a_stranger_is_dropped`, `whisper_from_a_member_before_the_list_loads_is_dropped_then_repaired` (state repaired through PING / SREQ within 130 s of simulated time), `guild_message_before_the_list_loads_is_accepted`.
  - `stranger_mock_calendar_note_and_update_notice_change_nothing` (inject each as a whisper from a non-member: no pop-up, no saved note, no update record).
  - `not_in_a_guild_sends_nothing_and_raises_nothing` (a full session start plus 5 minutes of ticks).
  - `leaving_the_guild_mid_session_stops_sends`, `joining_a_guild_mid_session_says_hello`.
  - `old_channel_is_left_once_on_upgrade`.
  - `queue_holds_during_chat_lockdown_and_resumes`.
  - `namesake_of_me_is_heard` (member "Chaos Other" while I am "Chaos Deathbringr": their STATE is applied under their own key).
  - `login_with_50_members_online_costs_bounded_sends`: each existing copy sends at most 2 whispers to the newcomer; the newcomer sends at most 3 messages in its first 10 s.
  - The existing two-, three- and five-copy simulations run over the guild with the real (non-forced) channel state.
- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement.** Rewrite or delete the older tests that assumed the hidden channel delivers; each deleted test's behaviour must either be gone from the addon or covered by a guild test (say which in the report).
- [ ] **Step 4:** `tests/run.sh` → `ALL PASSED`. Commit: `feat: messages go through the guild, only guild members are trusted`.

### Task 4: Roster follows the guild

**Files:**
- Modify: `TwizCrew/Crew/Roster.lua`, `TwizCrew/Crew/Crew.lua`, `TwizCrew/UI/Commands.lua` (`/tc forget`, `/tc remove` wording), any module that resolves a name from a message field (`Stats/Roasts.lua`, `UI/AwardsShow.lua`, `Stats/Trophies.lua`, `Calendar/Diary.lua`, `Crew/Quest.lua`, `UI/Feed.lua`, `Find/Where.lua`, `Find/Find.lua`, `Layer/Layer.lua`, `UI/MockShow.lua`, `UI/PanelMenus.lua`, `Stats/Detectors.lua`)
- Test: `tests/test_roster.lua`, `tests/test_crew.lua`, `tests/test_guild.lua`, the module tests touched

**Interfaces:**
- Consumes: `ns.Guild` (Task 1); `Crew.forget(name)` (exists: drops a friend's saved roster, stats and extras).
- Produces:
  - `Roster:setGuild(guild)`; a roster member gains `inGuild` (boolean) and `outSince` (wall seconds, saved) fields. `Roster:members()`, `:names()`, `:sorted()`, `:onlineCount()` return only members with `inGuild` true (plus fakes where they did before). A member not in a successfully loaded guild list gets `inGuild = false` and, the first time, `outSince = now`; back in the list clears both.
  - `Roster:tick` (or `Crew`'s own tick): a real member whose `outSince` is older than `ns.Config.OUT_OF_GUILD_DAYS` (30) days is forgotten through `Crew.forget`. Nothing is marked or forgotten before `Guild.loaded()`.
  - `ns.Guild.resolve(name) -> key | nil`: for a name taken from a message field or typed by the player: a key, a full name or a first word that exactly one member has. Every place that compares a payload name (`f.t`, vote targets, winners) or a typed name with a roster name or with me goes through it or through `ns.isMe`.
  - Unit name helpers that return `ns.shortName(UnitName(unit))` for group members (`Layer`, `Find/Where`, `MockShow`, `Find`) return the member's key instead (`Guild.keyOf(full unit name) or shortName`), so a namesake in my party maps to the right row.
- [ ] **Step 1: Failing tests:** `saved_friend_not_in_guild_is_hidden_after_first_list_load_only`, `saved_friend_in_guild_keeps_stats_trophies_notes`, `out_of_guild_30_days_is_forgotten_29_is_not`, `rejoining_clears_out_since`, `nothing_is_hidden_when_the_list_never_loads`, `mock_aimed_at_my_namesake_is_not_shown_as_mine`, `vote_for_a_namesake_counts_for_the_right_one`, `party_namesake_gets_the_right_row` (positions / layer), `tc_forget_accepts_first_word_or_full_name`.
- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `tests/run.sh` → `ALL PASSED`. Commit: `feat: the roster follows the guild list; names resolve through it`.

### Task 5: Panel sections and pins

**Files:**
- Modify: `TwizCrew/UI/PanelLogic.lua`, `TwizCrew/UI/PanelRows.lua`, `TwizCrew/UI/PanelHeader.lua`, `TwizCrew/UI/PanelMenus.lua`, `TwizCrew/UI/Panel.lua`, `TwizCrew/UI/PanelMini.lua` (count text only), `TwizCrew/Core/DB.lua` (default `pins = {}`), `TwizCrew/UI/TestTools.lua` if a fake needs a section
- Test: `tests/test_panel.lua`, `tests/test_ui.lua`, `tests/test_minimize.lua`

**Interfaces:**
- Consumes: `ns.Guild.members / get / display / count` (Task 1), roster members with `inGuild` (Task 4), `ns.db.pins`.
- Produces:
  - `ns.db.pins[key] = true` (account-wide). `ns.Panel.pin(key)`, `ns.Panel.unpin(key)`, `ns.Panel.isPinned(key)`.
  - Panel settings (module `panel`): `showGuildOnline` (boolean, remembered open / closed state of the bar, default false), `showNoAddon` ("Show guild members without the addon", default true). `showOffline` keeps its meaning for the Offline bar.
  - `PanelLogic.rows(...)` gains rows for guild members with no roster record or never heard this session: `{ name, class, level, zoneText, noAddon = true, offline, offlineText }` built from the guild list entry. Row models gain `key`, `section` ("party" | "pinned" | "guild" | "offline"), `pinned`, and `name` = `Guild.display(key)`.
  - `PanelLogic.entries(rows, opts) -> array` where `opts = { inGroup, guildOpen, offlineOpen, hiddenOffline }`, top to bottom: `{ head = "My party" }` + party rows (only when grouped and there is at least one); `{ head = "Pinned" }` + pinned online rows (heading only when there is a party section above or rows below); `{ bar = "guild", count, open }` + its rows when open; `{ bar = "offline", count, open }` + its rows when open. When there is no party row and no pinned online row, the guild bar is treated as open whatever `guildOpen` says.
  - `PanelLogic.headerCount(here, online) -> "3 here · 14 online"` (and the existing shorter forms for compact and tiny).
  - Offline `last seen`: the roster's `lastSeen` when it has one, else the guild list's `lastOnline`.
- UI: section headings as thin rows; the two bars click to open / close and save the state; a green "+" button on rows in the guild and offline lists (tooltip "Pin to main view"), a gold star on pinned rows (tooltip "Unpin"); the row menu gets "Pin to main view" / "Unpin". No-addon rows are drawn at reduced alpha with "no addon" as their second line, and their menu only offers whisper, invite and pin. Not in a guild: the body is one line, "TwizCrew works inside a guild. Join one and it starts by itself." New frames are plain and are made outside combat like the existing rows; no secure frame work in combat.
- `Guild.setWatched(true)` while the panel is shown and not minimized.

- [ ] **Step 1: Failing tests:** `sections_in_order_party_pinned_guild_offline`, `no_party_no_heading`, `pinned_offline_member_sits_in_offline_with_star`, `guild_bar_closed_by_default_hides_its_rows`, `empty_main_view_opens_the_guild_list`, `pin_then_unpin_moves_the_row`, `pins_survive_a_reload` (saved), `no_addon_member_row_from_guild_list`, `show_no_addon_off_hides_them_and_the_counts_follow`, `namesakes_show_full_names`, `header_says_here_and_online`, `not_in_a_guild_shows_the_one_line`, `party_member_outside_the_guild_is_not_shown`, `offline_last_seen_falls_back_to_guild_list`, `fifty_online_members_scroll_and_do_not_error`, and the minimize / peek tests still pass (a peek shows the one friend's row whatever section they are in).
- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement** (logic first, then frames).
- [ ] **Step 4:** `tests/run.sh` → `ALL PASSED`. Commit: `feat: panel sections (party, pinned, guild online, offline) and pins`.

### Task 6: Notices only for party and pinned by default

**Files:**
- Modify: `TwizCrew/UI/Popups.lua`, `TwizCrew/UI/Feed.lua`, `TwizCrew/UI/PanelMini.lua` (bar notices, peek), `TwizCrew/UI/FeedLogic.lua` if the rule is pure
- Test: `tests/test_popups.lua`, `tests/test_feed.lua`, `tests/test_minimize.lua`

**Interfaces:**
- Consumes: `ns.Panel.isPinned(key)` (Task 5), the group check the panel uses for the party section.
- Produces: `ns.Panel.isClose(key) -> boolean` (in my party / raid, or pinned). Setting on the `panel` module: `noticeScope`, choices `{ "close", "My party and pinned" }, { "guild", "Everyone in the guild" }`, default `"close"`, with an `info` text.
- Rule: pop-ups, bar notices, peeks and chat lines for coming online, going offline, level-up and death fire only when `noticeScope == "guild"` or `isClose(key)`. The Recent list stores the event either way. Mocks, congrats and roasts aimed at me, layer pop-ups, meet-ups, quest shares, stolen crowns and the awards show are unchanged. Test-tool fakes always count as close.

- [ ] **Step 1: Failing tests:** `guildmate_level_up_is_recorded_but_not_popped`, `pinned_level_up_pops`, `party_death_pops`, `scope_guild_pops_everyone`, `mock_at_me_from_a_non_pinned_member_still_shows`, `fake_friend_events_still_show`.
- [ ] **Step 2: Run, fail.** **Step 3: Implement.**
- [ ] **Step 4:** `tests/run.sh` → `ALL PASSED`. Commit: `feat: online, level-up and death notices only for party and pinned by default`.

### Task 7: Words, settings and documents

**Files:**
- Modify: settings and help text wherever "channel", "crew code", "whisper", "Connection" or "friends list" wording is now wrong (`Comm/Comm.lua` module info, `UI/Commands.lua` help, `UI/Updates.lua`, `UI/Report.lua`, `README.md`), `PROJECT.md`, `docs/TESTING.md`
- Test: `tests/test_ui.lua`, `tests/test_lint.lua` (a rule: no player-facing string mentions "hidden channel" or "crew code")

- [ ] **Step 1:** Add the lint rule, see it fail, fix the strings. `/tc remove` and `/tc forget` help says what they do in a guild.
- [ ] **Step 2: `PROJECT.md`:** a section "Guild conversion (2026-11-21)": what changed, the owner's decisions with quotes, Claude's calls, what was removed, what is unproven until `/tc guildtest` runs. Update "Where we are", the comm description and the "one message is several sends" limit (now one send). Remove or correct statements the conversion makes wrong (one place per fact).
- [ ] **Step 3: `docs/TESTING.md`:** a section "Guild conversion", riskiest first: 1. `/tc guildtest` with one member online and what each line should say; 2. a member appears on the panel after `/reload`; 3. a non-member with the addon does not appear; 4. sections, pin, unpin; 5. a member without the addon is dimmed; 6. notices scope; 7. dungeon run with a guild party (no errors); 8. the old channel is gone from chat windows; 9. two members with the same first name, if the guild has any.
- [ ] **Step 4: `README.md`:** friends join the guild; no channel or code.
- [ ] **Step 5:** `tests/run.sh` → `ALL PASSED`. Commit: `docs: guild conversion in PROJECT.md, in-game checks, wording`.
