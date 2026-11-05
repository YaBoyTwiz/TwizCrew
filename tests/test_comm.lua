local function boot(ns, W, mutate)
  W.state.player = "Twiz"
  if mutate then mutate(W) end
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  W:fire("PLAYER_ENTERING_WORLD")
  return db
end

local function logHas(ns, text)
  for _, line in ipairs(ns.Log.lines()) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local function noErrors(ns, A)
  A.eq(ns.Log.errors(10), {})
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/Log.lua", "Core/Events.lua", "Core/Modules.lua", "Core/DB.lua",
    "Comm/Codec.lua", "Comm/Queue.lua", "Comm/Transport.lua", "Comm/Comm.lua" },
  tests = {
    joins_channel_after_delay_and_hides_it = function(ns, A, W)
      boot(ns, W)
      W:advance(4)
      A.eq(W.state.channels.TwizCrewHQ, nil)
      W:advance(2)
      A.eq(W.state.channels.TwizCrewHQ, 5)
      A.eq(#W.removedChannels, 10)
      A.eq(W.removedChannels[1].channel, "TwizCrewHQ")
      A.ok(ns.Transport.status().joined)
      noErrors(ns, A)
    end,
    send_goes_to_channel_when_joined = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      ns.Comm.send("PING", {})
      W:advance(1)
      A.eq(#W.sent, 1)
      A.eq(W.sent[1].chatType, "CHANNEL")
      A.eq(W.sent[1].target, 5)
      A.eq(W.sent[1].prefix, "TwizCrew")
      noErrors(ns, A)
    end,
    send_before_join_is_delivered_after_join = function(ns, A, W)
      boot(ns, W)
      A.ok(ns.Transport.isPending())
      ns.Comm.send("PING", {})
      W:advance(3)
      A.eq(#W.sent, 0)
      W:advance(3)
      A.eq(#W.sent, 1)
      A.eq(W.sent[1].chatType, "CHANNEL")
      A.eq(W.sent[1].target, 5)
      A.no(ns.Transport.isPending())
    end,
    pending_sends_keep_their_order = function(ns, A, W)
      boot(ns, W)
      ns.Comm.send("HELLO", { ver = "1" })
      ns.Comm.send("PING", {})
      W:advance(7)
      A.eq(#W.sent, 2)
      A.contains(W.sent[1].text, "HELLO")
      A.contains(W.sent[2].text, "PING")
    end,
    pending_sends_go_out_as_whispers_when_join_fails = function(ns, A, W)
      local db = boot(ns, W, function(w) w.state.channelJoinFails = true end)
      db.crew.extra = { "Ginkan", "Frostie" }
      ns.Comm.send("PING", {})
      W:advance(14)
      A.eq(#W.sent, 0)
      W:advance(3)
      A.eq(#W.sent, 2)
      A.eq(W.sent[1].chatType, "WHISPER")
      A.eq(W.sent[1].target, "Ginkan")
      A.eq(W.sent[2].target, "Frostie")
      A.ok(ns.Transport.status().failed)
    end,
    falls_back_to_whispers_when_channel_fails = function(ns, A, W)
      local db = boot(ns, W, function(w) w.state.channelJoinFails = true end)
      db.crew.extra = { "Ginkan", "Frostie" }
      W:advance(16)
      ns.Comm.send("PING", {})
      W:advance(2)
      A.eq(#W.sent, 2)
      A.eq(W.sent[1].chatType, "WHISPER"); A.eq(W.sent[1].target, "Ginkan")
      A.eq(W.sent[2].chatType, "WHISPER"); A.eq(W.sent[2].target, "Frostie")
      local st = ns.Transport.status()
      A.ok(st.failed)
      A.ok(st.failReason and st.failReason ~= "")
      A.ok(logHas(ns, st.failReason))
    end,
    never_whispers_yourself = function(ns, A, W)
      local db = boot(ns, W, function(w) w.state.channelJoinFails = true end)
      db.crew.extra = { "Twiz", "Ginkan" }
      W:advance(16)
      A.eq(ns.Transport.destinations(), { { chatType = "WHISPER", target = "Ginkan" } })
    end,
    fallback_after_bad_send_results = function(ns, A, W)
      local db = boot(ns, W)
      db.crew.extra = { "Ginkan" }
      W:advance(6)
      W.state.sendResult = 3
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(3)
      A.ok(ns.Transport.status().failed)
      A.eq(ns.Transport.status().lastResult, 3)
      W.state.sendResult = 0
      ns.Comm.send("PING", {})
      W:advance(1)
      local last = W.sent[#W.sent]
      A.eq(last.chatType, "WHISPER"); A.eq(last.target, "Ginkan")
    end,
    wrong_password_notice_fails_and_prints_once = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "TwizCrewHQ")
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "TwizCrewHQ")
      A.ok(ns.Transport.status().failed)
      local n = 0
      for _, line in ipairs(W.printed) do
        if line == "TwizCrew: the crew code didn't work. Check it in /tc settings." then n = n + 1 end
      end
      A.eq(n, 1)
    end,
    other_channel_notice_is_ignored = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "Trade")
      A.no(ns.Transport.status().failed)
    end,
    grouped_fallback_uses_party_and_skips_whisper_to_party_members = function(ns, A, W)
      local db = boot(ns, W, function(w)
        w.state.channelJoinFails = true
        w.state.inGroup = true
        w.state.groupMembers = { "Ginkan" }
      end)
      db.crew.extra = { "Ginkan", "Frostie" }
      W:advance(16)
      A.eq(ns.Transport.destinations(), { { chatType = "PARTY" }, { chatType = "WHISPER", target = "Frostie" } })
      W.state.inRaid = true
      A.eq(ns.Transport.destinations()[1], { chatType = "RAID" })
    end,
    roster_names_are_used_when_present = function(ns, A, W)
      local db = boot(ns, W, function(w) w.state.channelJoinFails = true end)
      db.crew.extra = { "Frostie" }
      ns.roster = { names = function() return { "Ginkan", "Frostie", "Twiz" } end }
      W:advance(16)
      A.eq(ns.Transport.destinations(), { { chatType = "WHISPER", target = "Ginkan" },
        { chatType = "WHISPER", target = "Frostie" } })
    end,
    modes_pick_their_destinations = function(ns, A, W)
      local db = boot(ns, W)
      db.crew.extra = { "Ginkan" }
      W:advance(6)
      W.state.inGroup = true
      ns.Modules.set("comm", "transport", "whisper")
      A.eq(ns.Transport.destinations(), { { chatType = "WHISPER", target = "Ginkan" } })
      A.no(ns.Transport.isPending())
      ns.Modules.set("comm", "transport", "group")
      A.eq(ns.Transport.destinations(), { { chatType = "PARTY" } })
      ns.Modules.set("comm", "transport", "channel")
      A.eq(ns.Transport.destinations(), { { chatType = "CHANNEL", target = 5 } })
      W.state.inGuild = true
      ns.Modules.set("comm", "transport", "guild")
      A.eq(ns.Transport.destinations(), { { chatType = "GUILD" } })
      W.state.inGuild = false
      ns.Modules.set("comm", "transport", "guild")
      A.eq(ns.Transport.destinations()[1], { chatType = "CHANNEL", target = 5 })
    end,
    whisper_mode_is_not_pending = function(ns, A, W)
      local db = boot(ns, W)
      db.crew.extra = { "Ginkan" }
      ns.Modules.set("comm", "transport", "whisper")
      A.no(ns.Transport.isPending())
      ns.Comm.send("PING", {})
      W:advance(1)
      A.eq(#W.sent, 1)
      A.eq(W.sent[1].chatType, "WHISPER")
    end,
    holds_during_boss_fight = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W:fire("ENCOUNTER_START")
      ns.Comm.send("PING", {})
      W:advance(2)
      A.eq(#W.sent, 0)
      W:fire("ENCOUNTER_END")
      W:advance(1)
      A.eq(#W.sent, 1)
    end,
    entering_world_releases_hold = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W:fire("ENCOUNTER_START")
      ns.Comm.send("PING", {})
      W:fire("PLAYER_ENTERING_WORLD")
      W:advance(1)
      A.eq(#W.sent, 1)
    end,
    rate_is_limited = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      for _ = 1, 10 do ns.Comm.send("PING", {}) end
      W:advance(0.2)
      A.eq(#W.sent, 4)
      W:advance(1)
      A.eq(#W.sent, 6)
    end,
    receive_normalizes_realm_and_ignores_self = function(ns, A, W)
      boot(ns, W)
      local got = {}
      ns.Comm.on("PING", function(sender) got[#got + 1] = sender end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Ginkan-Realm")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Holybøi-OtherRealm")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Twiz-Realm")
      W:fire("CHAT_MSG_ADDON", "Other", "1^PING^", "CHANNEL", "Ginkan-Realm")
      A.eq(got, { "Ginkan", "Holybøi-OtherRealm" })
    end,
    receive_passes_fields_to_handlers = function(ns, A, W)
      boot(ns, W)
      local seen
      ns.Comm.on("HELLO", function(sender, fields) seen = { sender, fields.zn } end)
      local texts = ns.Codec.encode("HELLO", { zn = "Elwynn Forest" })
      W:fire("CHAT_MSG_ADDON", "TwizCrew", texts[1], "WHISPER", "Ginkan")
      A.eq(seen, { "Ginkan", "Elwynn Forest" })
    end,
    receive_dedupes_same_text_within_window = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Ginkan")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "PARTY", "Ginkan")
      A.eq(n, 1)
      W:advance(3)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "PARTY", "Ginkan")
      A.eq(n, 2)
    end,
    dedupe_table_does_not_grow_forever = function(ns, A, W)
      boot(ns, W)
      for i = 1, 300 do
        W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^x" .. i, "CHANNEL", "Ginkan")
        W:advance(1)
      end
      A.ok(ns.Comm.dedupeSize() < 20, "dedupe size " .. ns.Comm.dedupeSize())
    end,
    garbage_message_is_ignored_quietly = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "nonsense", "CHANNEL", "Ginkan")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "", "CHANNEL", "Ginkan")
      A.eq(n, 0)
      noErrors(ns, A)
    end,
    a_failing_handler_does_not_stop_others = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() error("boom") end)
      ns.Comm.on("PING", function() n = n + 1 end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Ginkan")
      A.eq(n, 1)
    end,
    debug_setting_controls_chat_debug = function(ns, A, W)
      boot(ns, W)
      A.eq(ns.Log.chatDebug, false)
      ns.Modules.set("comm", "debug", true)
      A.eq(ns.Log.chatDebug, true)
      ns.Modules.set("comm", "debug", false)
      A.eq(ns.Log.chatDebug, false)
    end,
    comm_is_an_essential_module = function(ns, A, W)
      local d = ns.Modules.get("comm")
      A.eq(d.tier, "essential")
      A.eq(d.name, "Crew connection")
      A.eq(d.defaults.transport, "auto")
    end,
    late_join_after_timeout_is_still_hidden = function(ns, A, W)
      boot(ns, W, function(w) w.state.channelJoinFails = true end)
      W:advance(16)
      A.ok(ns.Transport.status().failed)
      A.eq(#W.removedChannels, 0)
      W.state.channels.TwizCrewHQ = 5
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "TwizCrewHQ")
      A.eq(#W.removedChannels, 10)
      local frames = {}
      for _, r in ipairs(W.removedChannels) do frames[r.frame] = true end
      for i = 1, 10 do A.ok(frames[W.env["ChatFrame" .. i]], "frame " .. i) end
    end,
    hides_not_found_line_for_whispered_names = function(ns, A, W)
      local db = boot(ns, W, function(w) w.state.channelJoinFails = true end)
      db.crew.extra = { "Ginkan" }
      W:advance(16)
      ns.Comm.send("PING", {})
      W:advance(1)
      A.eq(#W.messageFilters, 1)
      A.eq(W.messageFilters[1].event, "CHAT_MSG_SYSTEM")
      local f = W.messageFilters[1].fn
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Ginkan' is currently playing."), true)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Stranger' is currently playing."), false)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", nil), false)
      W:advance(11)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Ginkan' is currently playing."), false)
    end,
    changing_crew_code_rejoins = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      A.ok(ns.Transport.status().joined)
      ns.Modules.set("comm", "channel", "OtherHQ")
      W:advance(1)
      A.eq(W.state.channels.OtherHQ, 5)
      A.eq(ns.Transport.status().channel, "OtherHQ")
      A.ok(ns.Transport.status().joined)
    end,
  },
}
