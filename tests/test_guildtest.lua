-- /tc guildtest: the probe, its answer, the report's Guild line. Full TOC boot, clients in one guild.
local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function printed(W, sub)
  for _, l in ipairs(W.printed) do if l:find(sub, 1, true) then return l end end
end

local function sentOfType(ns, W, msgType, chatType)
  local n = 0
  for _, m in ipairs(W.sent) do
    local msg = ns.Codec.decode(m.text)
    if msg and msg.type == msgType and (not chatType or m.chatType == chatType) then n = n + 1 end
  end
  return n
end

local function pair(H, formA)
  local a, nsA = H.client("Chaos Deathbringr", { senderForm = formA })
  local b, nsB = H.client("Ginkan Pebble")
  H.guild("Test Guild", a, b)
  H.link(a, b)
  boot(a); boot(b)
  return a, nsA, b, nsB
end

return {
  files = "toc",
  tests = {
    probe_reports_echo_and_answer = function(_, A, _, H)
      local a, nsA, b, nsB = pair(H, "full")
      a.printed = {}
      tc(a, "guildtest")
      A.ok(printed(a, "You are in the guild Test Guild: 2 members, 2 online"), "line 1")
      A.ok(printed(a, "A guild list name looks like \"Ginkan Pebble\", and zones are given"), "line 2")
      H.advance(3.5)
      A.ok(printed(a, "accepted; my own copy heard it back, sender shown as \"Chaos Deathbringr\""),
        "line 3")
      H.advance(5)
      A.ok(printed(a, "These answered: Ginkan in "), "line 4")
      A.ok(printed(a, "whisper sender shown as \"Ginkan Pebble-Realm\""), "whisper form")
      A.ok(printed(a, "does not have InChatMessagingLockdown"), "line 5")
      local f = nsA.GuildTest.facts()
      A.ok(f.echo and f.accepted and #f.answers == 1)
      A.eq(f.answers[1].key, "Ginkan")
      A.eq(f.echoForm, "Chaos Deathbringr")
      A.eq(sentOfType(nsA, a, "GPROBE", "GUILD"), 1, "one guild message")
      A.eq(sentOfType(nsB, b, "GPONG", "WHISPER"), 1, "one whisper back")
    end,

    guildtest_tells_the_guild_name_and_the_row_counts = function(_, A, _, H)
      local a = H.client("Chaos Deathbringr")
      H.guild("Test Guild", a, { { name = "Ginkan Pebble" } })
      H.link(a)
      boot(a)
      a.printed = {}
      tc(a, "guildtest")
      A.ok(printed(a, "The game names the guild \"Test Guild\"."))
      A.ok(printed(a, "Guild list: 2 counted, 2 readable, offline members included: yes."))
      local b = H.client("Ginkan Pebble", { guildNameHidden = true })
      H.guild("Test Guild", b)
      H.link(b)
      boot(b)
      b.printed = {}
      tc(b, "guildtest")
      A.ok(printed(b, "The game gives no guild name."))
    end,
    -- The guild list line says whether the game includes offline members: yes / no / cannot tell.
    guildtest_tells_whether_offline_members_are_included = function(_, A, _, H)
      local a = H.client("Chaos Deathbringr")
      H.guild("Test Guild", a, { { name = "Ginkan Pebble" }, { name = "Frostie Snow" } })
      H.link(a)
      boot(a)
      a.printed = {}
      tc(a, "guildtest")
      A.ok(printed(a, "Guild list: 3 counted, 3 readable, offline members included: yes."))
      H.advance(11)
      a.state.guildOnlineOnly = true -- the box in the guild window is not ticked
      a.printed = {}
      tc(a, "guildtest")
      A.ok(printed(a, "Guild list: 3 counted, 1 readable, offline members included: no."))
      H.advance(11)
      a.env.GetGuildRosterInfo = function() return a.secret() end
      a.printed = {}
      tc(a, "guildtest")
      A.ok(printed(a, "Guild list: 3 counted, 0 readable, offline members included: cannot tell."))
    end,

    -- While TwizCrew is not using this guild's data the probe says why first, still sends, and never claims that
    -- nobody answered (answers are not taken in then); the member count is read live, never "not loaded yet".
    guildtest_says_why_while_quiet = function(_, A, _, H)
      local a, nsA = H.client("Chaos Deathbringr")
      local b = H.client("Ginkan Pebble")
      H.guild("Test Guild", a, b)
      a.env.TwizCrewDB = { guild = { name = "Other Guild" } }
      H.link(a, b)
      boot(a); boot(b)
      A.eq(nsA.Guild.quietReason(), "reload")
      a.printed = {}
      tc(a, "guildtest")
      A.eq(a.printed[1], "TwizCrew: TwizCrew is not using this guild's data: the saved data in use is another"
        .. " guild's. Type /reload to switch.", "the reason comes first")
      A.ok(printed(a, "You are in the guild Test Guild: 2 members, 2 online"), "counted live")
      A.no(printed(a, "not loaded yet"))
      H.advance(9)
      A.ok(printed(a, "Guild send: accepted"), "the send test still ran")
      A.ok(printed(a, "Answers cannot be counted while TwizCrew is not using this guild's data. See /tc guild."))
      A.no(printed(a, "Nobody answered"))
    end,

    guildtest_reason_lines_by_state = function(_, A, _, H)
      -- older data that a whole list does not fit
      local a, nsA = H.client("Chaos Deathbringr")
      H.guild("Test Guild", a, { { name = "Ginkan Pebble" } })
      a.env.TwizCrewDB = { roster = { Zed = { name = "Zed" }, Yan = { name = "Yan" } } }
      H.link(a)
      boot(a); H.advance(20)
      A.eq(nsA.Guild.quietReason(), "choose")
      a.printed = {}
      tc(a, "guildtest")
      A.eq(a.printed[1], "TwizCrew: TwizCrew is not using this guild's data yet: it has older saved data. Type"
        .. " /tc guild to choose what to do with it.")
      -- the same, and a list that may lack the offline members
      local b, nsB = H.client("Frostie Snow", { guildOnlineOnly = true })
      H.guild("Test Guild", b, { { name = "Ginkan Pebble" }, { name = "Zed Zed" } })
      b.env.TwizCrewDB = { roster = { Zed = { name = "Zed" }, Yan = { name = "Yan" }, Ginkan = { name = "Ginkan" } } }
      H.link(b)
      boot(b); H.advance(20)
      A.eq(nsB.Guild.quietReason(), "partial")
      b.printed = {}
      tc(b, "guildtest")
      A.eq(b.printed[1], "TwizCrew: TwizCrew is not using this guild's data yet: it waits for the full guild list."
        .. " If this stays, open the guild window and tick Show Offline Members.")
      -- still finding out (the game has not named the guild yet)
      local c, nsC = H.client("Lurabe Moon", { guildNameHidden = true })
      H.guild("Test Guild", c)
      c.env.TwizCrewDB = { guild = { name = "Test Guild", named = true } }
      H.link(c)
      boot(c)
      A.eq(nsC.Guild.quietReason(), "loading")
      c.printed = {}
      tc(c, "guildtest")
      A.eq(c.printed[1], "TwizCrew: TwizCrew is not using this guild's data yet: it is still loading. Try again in"
        .. " a few seconds.")
    end,

    -- A member whose key is their full name (a namesake holds the first word) still gets a pong and is counted.
    a_namesake_with_a_full_name_key_answers_and_is_answered = function(_, A, _, H)
      local a, nsA = H.client("Ginkan Pebble")
      local b, nsB = H.client("Chaos Other")
      H.guild("Test Guild", a, b, { { name = "Chaos Abel" } })
      H.link(a, b)
      boot(a); boot(b)
      A.eq(nsA.Guild.keyOf("Chaos Other"), "Chaos Other", "Abel holds \"Chaos\"")
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "These answered: Chaos Other in "), "counted under the full-name key")
      A.eq(nsA.GuildTest.facts().answers[1].key, "Chaos Other")
      H.advance(11)
      tc(b, "guildtest")
      H.advance(9)
      A.ok(printed(b, "These answered: Ginkan in "), "and answered when it asks")
      A.eq(sentOfType(nsA, a, "GPONG", "WHISPER"), 1)
    end,

    probe_alone_says_nobody_answered = function(_, A, _, H)
      local a, nsA = H.client("Chaos Deathbringr")
      H.guild("Test Guild", a)
      H.link(a)
      boot(a)
      a.printed = {}
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "The guild list has nobody but you"))
      A.ok(printed(a, "Nobody answered (nobody else online with TwizCrew, or guild messages are not delivered)."))
      A.ok(printed(a, "heard it back"), "my own echo still arrives")
      A.eq(#nsA.GuildTest.facts().answers, 0)
    end,

    probe_outside_a_guild_says_so_and_sends_nothing = function(_, A, W, H)
      local a, nsA = H.client("Chaos Deathbringr")
      boot(a)
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "You are not in a guild"))
      A.eq(sentOfType(nsA, a, "GPROBE"), 0)
      A.no(nsA.GuildTest.facts().inGuild)
    end,

    lockdown_reads_show_in_the_last_line = function(_, A, _, H)
      local a = pair(H, "full")
      a.env.C_ChatInfo.InChatMessagingLockdown = function() return false end
      a.env.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
      a.printed = {}
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "has InChatMessagingLockdown, and addon chat is restricted right now"))
    end,

    a_first_name_sender_gets_a_whisper_to_the_full_name = function(_, A, _, H)
      local a, nsA = pair(H, "first")
      a.printed = {}
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "sender shown as \"Chaos\""), "the form the echo came with")
      A.ok(printed(a, "These answered: Ginkan"), "the list gives the full name to whisper")
      A.eq(nsA.GuildTest.facts().answers[1].key, "Ginkan")
    end,

    a_first_name_not_in_the_list_cannot_be_answered = function(_, A, _, H)
      local a, _, _, nsB = pair(H, "first")
      nsB.Guild.keyOf = function() return nil end -- Ginkan's list does not know "Chaos"
      a.printed = {}
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "Nobody answered. If a friend with TwizCrew is online, replies may not be reaching you: the"
        .. " game gave only a first name."))
    end,

    -- Round 5 item 10: a hidden send result is never turned into text; the first-name line needs a readable echo.
    a_hidden_send_result_shows_as_hidden = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      local send = a.env.C_ChatInfo.SendAddonMessage
      a.env.C_ChatInfo.SendAddonMessage = function(...) send(...); return a.secret() end
      a.printed = {}
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "Guild send: hidden"), "the result shows as hidden")
      A.eq(#nsA.Log.errors(5), 0)
    end,

    an_unknown_or_hidden_echo_never_claims_a_first_name = function(_, A, _, H)
      for _, form in ipairs({ "unknown", "hidden" }) do
        local a, nsA = H.client("Chaos Deathbringr") -- not linked: its own copy is not heard back by itself
        H.guild("Test Guild", a)
        boot(a)
        a.printed = {}
        tc(a, "guildtest")
        local probe = nsA.Codec.encode("GPROBE", { n = nsA.GuildTest.forTest.nonce() })[1]
        local raw = a.secret() -- not a string: "unknown"
        if form == "hidden" then raw = "Chaos"; a.state.secret[raw] = true end -- a hidden one-word string
        nsA.GuildTest.forTest.raw(probe, "GUILD", raw)
        H.advance(9)
        A.eq(nsA.GuildTest.facts().echoForm, form)
        A.no(printed(a, "the game gave only a first name"), form)
        A.ok(printed(a, "Nobody answered (nobody else online with TwizCrew, or guild messages are not delivered)."))
      end
    end,

    unclaimed_unnamed_pongs_are_dropped_after_15_seconds = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      nsA.Guild.loaded = function() return false end -- before the list loads a whisper cannot be checked
      local pong = function(n) return nsA.Codec.encode("GPONG", { n = n })[1] end
      nsA.GuildTest.forTest.raw(pong("77"), "WHISPER", a.secret())
      A.ok(nsA.GuildTest.forTest.pongRaw()["?77"], "kept for its answer")
      H.advance(16)
      nsA.GuildTest.forTest.raw(pong("78"), "WHISPER", a.secret())
      A.eq(nsA.GuildTest.forTest.pongRaw()["?77"], nil, "gone after 15 s")
      A.ok(nsA.GuildTest.forTest.pongRaw()["?78"])
    end,

    a_strangers_pong_whisper_is_not_remembered = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      tc(a, "guildtest")
      local text = nsA.Codec.encode("GPONG", { n = "1", z = "Nowhere" })[1]
      a:fire("CHAT_MSG_ADDON", "TwizCrew", text, "WHISPER", "Ghost Stranger-Realm")
      A.eq(nsA.GuildTest.forTest.pongRaw()["Ghost"], nil, "not a guild member: not an answer")
    end,

    answers_are_rate_limited_per_sender = function(_, A, _, H)
      local _, nsA, b, nsB = pair(H, "full")
      local text = nsA.Codec.encode("GPROBE", { n = "55" })[1]
      for _ = 1, 2 do
        b:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Chaos Deathbringr")
        H.advance(1)
      end
      A.eq(sentOfType(nsB, b, "GPONG", "WHISPER"), 1, "second probe within 10 s is not answered")
      H.advance(10)
      b:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Chaos Deathbringr")
      H.advance(1)
      A.eq(sentOfType(nsB, b, "GPONG", "WHISPER"), 2)
    end,

    a_second_run_within_ten_seconds_only_asks_to_wait = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      tc(a, "guildtest"); H.advance(2)
      a.printed = {}
      tc(a, "guildtest")
      A.eq(#a.printed, 1)
      A.ok(printed(a, "Wait 8 seconds before testing again."))
      A.eq(sentOfType(nsA, a, "GPROBE", "GUILD"), 1, "nothing more sent")
      H.advance(9)
      tc(a, "guildtest")
      A.eq(sentOfType(nsA, a, "GPROBE", "GUILD"), 2)
    end,

    send_outcomes_are_told_apart = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      local function run(set)
        for k, v in pairs(set) do a.state[k] = v end
        H.advance(11)
        a.printed = {}
        tc(a, "guildtest"); H.advance(4)
      end
      run({ sendNil = true })
      A.ok(printed(a, "Guild send: accepted (the game gave no result code);"), "nil is accepted")
      A.ok(nsA.GuildTest.facts().accepted)
      A.ok(nsA.Report.lines()[1] and (function()
        for _, l in ipairs(nsA.Report.lines()) do
          if l:find("send accepted (the game gave no result code)", 1, true) then return true end
        end
      end)(), "the report uses the same wording")
      run({ sendNil = false, sendRaises = true })
      A.ok(printed(a, "Guild send: the call failed (SendAddonMessage: boom"), "an error is a failed call")
      A.no(nsA.GuildTest.facts().accepted)
      run({ sendRaises = false, sendResult = 4 })
      A.ok(printed(a, "refused (result code 4)"))
      run({ sendResult = 0 })
      A.ok(printed(a, "Guild send: accepted;"))
    end,

    an_unloaded_guild_list_is_not_zero_members = function(_, A, _, H)
      local a, nsA = H.client("Chaos Deathbringr")
      a.state.guild = { name = "Test Guild", members = {} }
      boot(a)
      a.state.guild = nil
      a.state.inGuild = true -- the game says guild, but no list rows have loaded
      a.printed = {}
      -- force the module back to "not loaded"
      local real = nsA.Guild.loaded
      nsA.Guild.loaded = function() return false end
      local asked = 0
      nsA.Guild.refresh = function() asked = asked + 1 end
      H.link(a)
      tc(a, "guildtest")
      A.ok(printed(a, "the guild list has not loaded yet"))
      A.no(printed(a, "0 members"))
      A.no(printed(a, "nobody but you"))
      A.eq(asked, 1, "asked for the list")
      H.advance(4)
      A.ok(printed(a, "Guild send: accepted"), "the send test still ran")
      local found
      for _, l in ipairs(nsA.Report.lines()) do
        if l:find("^Guild: in .-the guild list has not loaded yet") then found = true end
      end
      A.ok(found, "the report says it too")
      nsA.Guild.loaded = real
    end,

    a_pong_that_did_not_come_by_whisper_is_not_an_answer = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      H.clients[2].state.sendRaises = false
      tc(a, "guildtest")
      local n = nsA.GuildTest.facts()
      local nonce
      for _, m in ipairs(a.sent) do
        local msg = nsA.Codec.decode(m.text)
        if msg and msg.type == "GPROBE" then nonce = msg.fields.n end
      end
      local pong = nsA.Codec.encode("GPONG", { n = nonce })[1]
      a:fire("CHAT_MSG_ADDON", "TwizCrew", pong, "GUILD", "Ginkan Pebble")
      A.eq(#nsA.GuildTest.facts().answers, 0)
    end,

    report_has_a_guild_section = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      local function line()
        for _, l in ipairs(nsA.Report.lines()) do if l:find("^Guild:") then return l end end
      end
      A.eq(line(), "Guild: in Test Guild, 2 members, 2 online; guild test not run (type /tc guildtest)")
      tc(a, "guildtest"); H.advance(9)
      A.eq(line(), "Guild: in Test Guild, 2 members, 2 online; guild test: send accepted, own echo yes as "
        .. "\"Chaos Deathbringr\", answered by Ginkan")
    end,

    old_copy_ignores_gprobe = function(ns, A, W)
      boot(W)
      local text = ns.Codec.encode("GPROBE", { n = "123" })[1]
      W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Someone")
      W:advance(1)
      A.eq(#ns.Log.errors(5), 0)
      -- and a raw hook sees my own echo while the handlers never do
      local seen
      ns.Comm.onRaw(function(t, chatType, raw) seen = { chatType, raw } end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", W.state.player)
      A.eq(seen, { "GUILD", W.state.player })
    end,

    help_lists_guildtest = function(ns, A, W)
      boot(W)
      tc(W, "help")
      A.ok(printed(W, "/tc guildtest - "))
    end,
  },
}
