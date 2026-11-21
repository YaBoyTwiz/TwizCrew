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
      A.ok(printed(a, "accepted (result code 0) and my own copy heard it back, sender shown as \"Chaos Deathbringr\""),
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

    a_short_sender_form_cannot_be_whispered_back = function(_, A, _, H)
      local a, nsA, b = pair(H, "first")
      a.printed = {}
      tc(a, "guildtest")
      H.advance(9)
      A.ok(printed(a, "sender shown as \"Chaos\""), "the form the echo came with")
      A.ok(printed(a, "Nobody answered"), "a whisper to \"Chaos\" does not arrive")
    end,

    answers_are_rate_limited_per_sender = function(_, A, _, H)
      local a, nsA, b, nsB = pair(H, "full")
      tc(a, "guildtest"); H.advance(1)
      tc(a, "guildtest"); H.advance(1)
      A.eq(sentOfType(nsB, b, "GPONG", "WHISPER"), 1, "second probe within 10 s is not answered")
      H.advance(10)
      tc(a, "guildtest"); H.advance(1)
      A.eq(sentOfType(nsB, b, "GPONG", "WHISPER"), 2)
    end,

    report_has_a_guild_section = function(_, A, _, H)
      local a, nsA = pair(H, "full")
      local function line()
        for _, l in ipairs(nsA.Report.lines()) do if l:find("^Guild:") then return l end end
      end
      A.eq(line(), "Guild: in Test Guild, 2 members, 2 online; guild test not run (type /tc guildtest)")
      tc(a, "guildtest"); H.advance(9)
      A.eq(line(), "Guild: in Test Guild, 2 members, 2 online; guild test: send accepted (0), own echo yes as "
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
