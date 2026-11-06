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

local function filterFor(W, event)
  for _, f in ipairs(W.messageFilters) do if f.event == event then return f.fn end end
end

local function joinsOf(W, name)
  local n = 0
  for _, j in ipairs(W.joins) do if j.name == name then n = n + 1 end end
  return n
end

local function countLog(ns, text)
  local n = 0
  for _, line in ipairs(ns.Log.lines()) do if line:find(text, 1, true) then n = n + 1 end end
  return n
end

-- Times (W.clock) of every JoinChannelByName call, recorded from now on.
local function recordJoinTimes(W)
  local times = {}
  local join = W.env.JoinChannelByName
  W.env.JoinChannelByName = function(...)
    times[#times + 1] = W.clock
    return join(...)
  end
  return times
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
      W:advance(6 + 10) -- joined, and past the moment right after joining when refusals are only waited out
      W.state.sendResult = 7 -- InvalidChannel: a real refusal
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(3)
      A.ok(ns.Transport.status().failed)
      A.eq(ns.Transport.status().lastResult, 7)
      W.state.sendResult = 0
      ns.Comm.send("PING", {})
      W:advance(1)
      local last = W.sent[#W.sent]
      A.eq(last.chatType, "WHISPER"); A.eq(last.target, "Ginkan")
    end,
    throttled_send_is_retried_and_does_not_fail_channel = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W.state.sendResult = 3 -- AddonMessageThrottle: "try again later"
      for i = 1, 3 do ns.Comm.send("PING", { n = tostring(i) }) end
      W:advance(4)
      A.no(ns.Transport.status().failed, "throttle is not a channel failure")
      A.ok(#W.sent >= 2, "the throttled send was tried again")
      for _, s in ipairs(W.sent) do A.contains(s.text, "n=1", "nothing skipped past the throttled message") end
      W.state.sendResult = 8 -- ChannelThrottle
      W:advance(4)
      A.no(ns.Transport.status().failed)
      W.state.sendResult = 0
      local before = #W.sent
      W:advance(3)
      local got = {}
      for i = before + 1, #W.sent do got[#got + 1] = W.sent[i].text:match("n=(%d)") end
      A.eq(got, { "1", "2", "3" })
      A.eq(W.sent[#W.sent].chatType, "CHANNEL")
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
    -- Found in game: grouped with a friend, both copies on the channel, yet neither heard the other. In auto mode a
    -- group always gets the message too (the receiver drops the second copy), so grouped friends always connect.
    auto_mode_in_group_sends_to_channel_and_group = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      A.eq(ns.Transport.destinations(), { { chatType = "CHANNEL", target = 5 } })
      W.state.inGroup = true
      A.eq(ns.Transport.destinations(), { { chatType = "CHANNEL", target = 5 }, { chatType = "PARTY" } })
      W.state.inRaid = true
      A.eq(ns.Transport.destinations(), { { chatType = "CHANNEL", target = 5 }, { chatType = "RAID" } })
    end,
    group_copy_of_a_channel_message_is_dropped = function(ns, A, W)
      boot(ns, W)
      local got = 0
      ns.Comm.on("PING", function() got = got + 1 end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Ginkan")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "PARTY", "Ginkan")
      A.eq(got, 1)
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
      -- Since the first in-game test: names always lose their realm (the crew is same-realm; WoW Forever sends
      -- "Name Realm" for party and whisper senders, which made our own messages look like a friend's).
      A.eq(got, { "Ginkan", "Holybøi" })
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
      local f = filterFor(W, "CHAT_MSG_SYSTEM")
      A.ok(f, "a CHAT_MSG_SYSTEM filter")
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Ginkan' is currently playing."), true)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Stranger' is currently playing."), false)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", nil), false)
      W:advance(11)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Ginkan' is currently playing."), false)
    end,
    changing_only_the_code_leaves_and_joins_again = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      A.ok(ns.Transport.status().joined)
      A.eq(joinsOf(W, "TwizCrewHQ"), 1)
      ns.Modules.set("comm", "password", "newcode")
      A.eq(W.leaves, { "TwizCrewHQ" })
      A.no(ns.Transport.status().joined)
      A.ok(ns.Transport.isPending())
      ns.Comm.send("PING", {})
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "5. TwizCrewHQ", "", "", 0, 5, "TwizCrewHQ")
      W:advance(3)
      A.eq(joinsOf(W, "TwizCrewHQ"), 2, "joined once more, and our own leave notice did not start another join")
      A.eq(W.joins[#W.joins].password, "newcode")
      A.ok(ns.Transport.status().joined)
      A.eq(W.sent[#W.sent].chatType, "CHANNEL")
      W:advance(15)
      A.eq(joinsOf(W, "TwizCrewHQ"), 2)
      noErrors(ns, A)
    end,
    destinations_follow_a_new_channel_number = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W.state.channels.TwizCrewHQ = 7
      A.eq(ns.Transport.destinations(), { { chatType = "CHANNEL", target = 7 } })
      A.eq(ns.Transport.status().channelIndex, 7)
    end,
    lost_channel_number_rejoins_and_sends_wait = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W.state.channels.TwizCrewHQ = nil
      local before = #W.sent
      ns.Comm.send("PING", {})
      A.no(ns.Transport.status().joined, "a missing channel number means not joined")
      A.ok(ns.Transport.isPending())
      W:advance(0.5)
      A.eq(#W.sent, before, "the message waits for the channel")
      W:advance(4)
      A.ok(ns.Transport.status().joined)
      A.eq(joinsOf(W, "TwizCrewHQ"), 2)
      A.eq(#W.sent, before + 1)
      A.eq(W.sent[#W.sent].chatType, "CHANNEL")
      -- lost again right away: the next join waits until 10 s after the last one
      W.state.channels.TwizCrewHQ = nil
      ns.Comm.send("PING", {})
      W:advance(4)
      A.eq(joinsOf(W, "TwizCrewHQ"), 2, "no second join within 10 s")
      W:advance(8)
      A.eq(joinsOf(W, "TwizCrewHQ"), 3)
      A.ok(ns.Transport.status().joined)
      noErrors(ns, A)
    end,
    you_left_notice_rejoins = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      W.state.channels.TwizCrewHQ = nil
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "5. TwizCrewHQ", "", "", 0, 5, "TwizCrewHQ")
      A.no(ns.Transport.status().joined)
      local before = #W.sent
      ns.Comm.send("PING", {})
      W:advance(0.5)
      A.eq(#W.sent, before)
      W:advance(4)
      A.ok(ns.Transport.status().joined)
      A.eq(#W.sent, before + 1)
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "6. Other", "", "", 0, 6, "Other")
      A.ok(ns.Transport.status().joined, "another channel's notice changes nothing")
    end,
    our_channel_lines_are_hidden_from_chat = function(ns, A, W)
      boot(ns, W)
      for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL",
        "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        local f = filterFor(W, event)
        A.ok(f, "filter for " .. event)
        A.eq(f(nil, event, "YOU_JOINED", "", "", "5. TwizCrewHQ", "", "", 0, 5, "TwizCrewHQ"), true)
        A.eq(f(nil, event, "hi", "Ginkan", "", "5. twizcrewhq", "", "", 0, 5, ""), true, "arg4 without arg9")
        A.eq(f(nil, event, "hi", "Ginkan", "", "TwizCrewHQ"), true)
        A.eq(f(nil, event, "hi", "Ginkan", "", "6. TwizCrewHQ2", "", "", 0, 6, "TwizCrewHQ2"), false)
        A.eq(f(nil, event, "hi", "Ginkan", "", "2. Trade - City", "", "", 0, 2, "Trade - City"), false)
        A.eq(f(nil, event), false)
        A.eq(f(nil, event, 1, 2, 3, {}, 5, 6, 7, 8, {}), false)
      end
      local general = filterFor(W, "CHAT_MSG_CHANNEL")
      ns.Modules.set("comm", "channel", "OtherHQ")
      A.eq(general(nil, "CHAT_MSG_CHANNEL", "hi", "Ginkan", "", "5. OtherHQ", "", "", 0, 5, "OtherHQ"), true)
      noErrors(ns, A)
    end,
    channel_removed_with_newer_api = function(ns, A, W)
      W.env.ChatFrame_RemoveChannel = nil
      local calls = {}
      W.env.ChatFrameUtil = { RemoveChannel = function(frame, name) calls[#calls + 1] = name end }
      boot(ns, W)
      W:advance(6)
      A.eq(#calls, 10)
      A.eq(calls[1], "TwizCrewHQ")
      A.eq(#W.removedChannels, 0)
    end,
    channel_removed_with_frame_method = function(ns, A, W)
      W.env.ChatFrame_RemoveChannel = nil
      local calls = {}
      for i = 1, 10 do
        W.env["ChatFrame" .. i] = { RemoveChannel = function(self, name) calls[#calls + 1] = { self, name } end }
      end
      boot(ns, W)
      W:advance(6)
      A.eq(#calls, 10)
      A.eq(calls[3][1], W.env.ChatFrame3)
      A.eq(calls[3][2], "TwizCrewHQ")
    end,
    no_way_to_remove_channel_is_logged = function(ns, A, W)
      W.env.ChatFrame_RemoveChannel = nil
      for i = 1, 10 do W.env["ChatFrame" .. i] = {} end
      boot(ns, W)
      W:advance(6)
      A.ok(ns.Transport.status().joined)
      A.ok(ns.Transport.status().hideFailed)
      A.ok(logHas(ns, "WARN could not take the channel TwizCrewHQ out of the chat windows"))
      noErrors(ns, A)
    end,
    receive_same_route_resend_is_not_dropped = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "WHISPER", "Ginkan")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "WHISPER", "Ginkan")
      A.eq(n, 2)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "PARTY", "Ginkan")
      A.eq(n, 2, "the same message by another route is a duplicate")
    end,
    own_channel_echoes_are_counted = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Twiz-Realm")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^a", "CHANNEL", "Twiz")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "PARTY", "Twiz")
      A.eq(n, 0)
      A.eq(ns.Comm.echoCount(), 2)
    end,
    -- The owner's first login: the channel joined, and the sends in that same second were refused (result 7).
    refusals_right_after_join_are_waited_out = function(ns, A, W)
      boot(ns, W)
      W.state.channelReadyAfter = 2 -- the game refuses channel sends for 2 s after the join
      ns.Comm.send("HELLO", { ver = "1" })
      ns.Comm.send("STATE", { lv = "10" })
      ns.Comm.send("UPDATE", { zn = "Elwynn Forest" })
      W:advance(5.3)
      A.ok(ns.Transport.status().joined)
      A.eq(W.sent[1].result, 7, "refused like in the game")
      W:advance(10)
      local st = ns.Transport.status()
      A.no(st.failed, "refusals right after joining do not count")
      A.ok(st.joined)
      local good = {}
      for _, m in ipairs(W.sent) do
        if m.result == 0 then good[#good + 1] = m.chatType .. " " .. m.text:match("^%d+%^(%u+)%^") end
      end
      A.eq(good, { "CHANNEL HELLO", "CHANNEL STATE", "CHANNEL UPDATE" }, "all three went out on the channel, in order")
      A.ok(#W.sent <= 3 + 3, "the refused message was tried about once a second, not more")
      A.eq(countLog(ns, "refused a send right after joining (result 7)"), 1)
      A.eq(countLog(ns, "has to wait"), 1, "one line for the message that waited")
      A.eq(countLog(ns, "channel failed"), 0)
      A.eq(joinsOf(W, "TwizCrewHQ"), 1)
      noErrors(ns, A)
    end,
    refusals_after_a_rejoin_are_waited_out_too = function(ns, A, W)
      boot(ns, W)
      W:advance(20)
      ns.Modules.set("comm", "password", "newcode") -- leaves and joins again: a new channel for the game
      W.state.channelReadyAfter = 2
      W:advance(2.1)
      ns.Comm.send("PING", {})
      W:advance(5)
      A.no(ns.Transport.status().failed)
      A.eq(W.sent[#W.sent].result, 0)
      A.eq(W.sent[#W.sent].chatType, "CHANNEL")
    end,
    channel_that_keeps_refusing_is_tried_again_at_a_slow_pace = function(ns, A, W)
      local db = boot(ns, W)
      db.crew.extra = { "Ginkan" }
      W.state.channelSendResult = 7 -- every channel send refused, whispers fine
      local joinTimes = recordJoinTimes(W)
      local ticker = W.env.C_Timer.NewTicker(20, function() ns.Comm.send("PING", {}) end) -- some traffic
      W:advance(5 + 10 + 3 * 20 + 10) -- three refused PINGs after the grace, then one more PING
      local st = ns.Transport.status()
      A.ok(st.failed, "gave up on the channel for now")
      A.eq(st.failReason, "sends to the channel were refused (result 7)")
      A.ok(st.nextRetryIn and st.nextRetryIn > 0 and st.nextRetryIn <= 60, "a try is planned")
      A.eq(W.sent[#W.sent].chatType, "WHISPER", "the fallback carries the messages")
      local logStart = #ns.Log.lines()
      local sentStart = #W.sent
      W:advance(3600)
      ticker:Cancel()
      -- tries: 60 s, then 120, 240 and 300 s apart (plus the time the channel needs to fail again each time)
      A.ok(#joinTimes >= 8 and #joinTimes <= 16, "tries in an hour: " .. #joinTimes)
      local gaps = {}
      for i = 2, #joinTimes do gaps[#gaps + 1] = joinTimes[i] - joinTimes[i - 1] end
      A.ok(gaps[1] >= 60 and gaps[1] < 120, "first gap " .. tostring(gaps[1]))
      for i, g in ipairs(gaps) do A.ok(g >= 60 and g <= 300 + 10 + 3 * 20 + 1, "gap " .. i .. ": " .. g) end
      A.ok(gaps[#gaps] >= 300, "the pace settles at about 5 minutes")
      -- nothing spams: per try, the waiting message is tried about once a second while the channel is new, then
      -- the refusals count; everything else goes out as whispers at the normal pace.
      local channelSends = 0
      for i = sentStart + 1, #W.sent do if W.sent[i].chatType == "CHANNEL" then channelSends = channelSends + 1 end end
      A.ok(channelSends <= #joinTimes * 15, "channel sends in an hour: " .. channelSends)
      -- no endless log flood: the first tries are logged, then only every sixth
      local channelLines = 0
      local lines = ns.Log.lines()
      for i = logStart + 1, #lines do
        if lines[i]:find("channel", 1, true) and not lines[i]:find("DEBUG", 1, true) then
          channelLines = channelLines + 1
        end
      end
      A.ok(channelLines <= 20, "channel lines in an hour: " .. channelLines)
      A.ok(countLog(ns, "trying channel TwizCrewHQ again (try 1)") == 1)
      A.ok(ns.Transport.status().failed)
      noErrors(ns, A)
    end,
    channel_comes_back_after_refusals = function(ns, A, W)
      local db = boot(ns, W)
      db.crew.extra = { "Ginkan" }
      local back = 0
      ns.Bus.on("test", "CHANNEL_BACK", function() back = back + 1 end)
      W:advance(16)
      W.state.channelSendResult = 7
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(2)
      A.ok(ns.Transport.status().failed)
      A.ok(logHas(ns, "using the fallback, trying the channel again in 60 s"))
      W.state.channelSendResult = nil -- the game takes channel messages again
      W:advance(57)
      A.ok(ns.Transport.status().failed, "not before the minute is up")
      A.eq(back, 0)
      W:advance(2)
      A.ok(ns.Transport.status().joined)
      A.no(ns.Transport.status().failed)
      A.eq(back, 1, "CHANNEL_BACK fired once")
      A.ok(logHas(ns, "trying channel TwizCrewHQ again (try 1)"))
      A.ok(logHas(ns, "channel TwizCrewHQ joined again as 5 (try 1)"))
      ns.Comm.send("PING", {})
      W:advance(1)
      A.eq(W.sent[#W.sent].chatType, "CHANNEL")
      A.eq(W.sent[#W.sent].result, 0)
      A.ok(logHas(ns, "channel TwizCrewHQ works again"))
      noErrors(ns, A)
    end,
    refusals_right_after_coming_back_are_waited_out = function(ns, A, W)
      boot(ns, W)
      W:advance(16)
      W.state.channelSendResult = 7
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(2)
      A.ok(ns.Transport.status().failed)
      ns.Bus.on("test", "CHANNEL_BACK", function()
        ns.Comm.send("HELLO", {}); ns.Comm.send("STATE", {}); ns.Comm.send("PING", {})
        W.env.C_Timer.After(2, function() W.state.channelSendResult = nil end) -- the game is ready 2 s later
      end)
      W:advance(70)
      local st = ns.Transport.status()
      A.ok(st.joined); A.no(st.failed, "refusals right after joining again do not count either")
      local good = {}
      for _, m in ipairs(W.sent) do
        if m.result == 0 and m.chatType == "CHANNEL" then good[#good + 1] = m.text:match("^%d+%^(%u+)%^") end
      end
      A.eq(good, { "HELLO", "STATE", "PING" })
      noErrors(ns, A)
    end,
    wrong_code_during_a_try_stops_the_tries = function(ns, A, W)
      boot(ns, W)
      W:advance(16)
      W.state.channelSendResult = 7
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(2)
      W.state.channels.TwizCrewHQ = nil       -- we are out of the channel, and joining it again fails
      W.state.channelJoinFails = true
      W:advance(59)                           -- the try starts and waits for the channel number
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "TwizCrewHQ")
      A.eq(ns.Transport.status().failReason, "wrong crew code")
      local joins = joinsOf(W, "TwizCrewHQ")
      W:advance(1200)
      A.eq(joinsOf(W, "TwizCrewHQ"), joins, "no more tries")
      A.eq(ns.Transport.status().nextRetryIn, nil)
    end,
    tries_start_slow_again_after_the_channel_worked = function(ns, A, W)
      boot(ns, W)
      W:advance(16)
      local function failNow()
        W.state.channelSendResult = 7
        for _ = 1, 3 do ns.Comm.send("PING", {}) end
        W:advance(2)
        A.ok(ns.Transport.status().failed)
      end
      failNow()
      W.state.channelSendResult = nil
      W:advance(61)
      ns.Comm.send("PING", {})
      W:advance(1)
      A.eq(ns.Transport.status().retries, 0, "a good send ends the tries")
      W:advance(15)
      failNow()
      A.ok(ns.Transport.status().nextRetryIn <= 60, "the next failure waits a minute again, not longer")
    end,
    wrong_code_while_trying_again_stops_the_tries = function(ns, A, W)
      boot(ns, W)
      W:advance(16)
      W.state.channelSendResult = 7
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(2)
      A.ok(ns.Transport.status().nextRetryIn)
      W:fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "TwizCrewHQ")
      A.eq(ns.Transport.status().failReason, "wrong crew code")
      A.eq(ns.Transport.status().nextRetryIn, nil)
      local joins = joinsOf(W, "TwizCrewHQ")
      W:advance(1200)
      A.eq(joinsOf(W, "TwizCrewHQ"), joins, "no more tries")
    end,
    join_timeout_is_not_tried_again = function(ns, A, W)
      boot(ns, W, function(w) w.state.channelJoinFails = true end)
      W:advance(16)
      A.ok(ns.Transport.status().failed)
      A.eq(ns.Transport.status().nextRetryIn, nil)
      W:advance(1200)
      A.eq(joinsOf(W, "TwizCrewHQ"), 1)
    end,
    changing_the_code_while_trying_again_starts_over = function(ns, A, W)
      boot(ns, W)
      W:advance(16)
      W.state.channelSendResult = 7
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(2)
      W.state.channelSendResult = nil
      ns.Modules.set("comm", "password", "newcode")
      W:advance(3)
      local st = ns.Transport.status()
      A.ok(st.joined); A.no(st.failed); A.eq(st.retries, 0)
      local joins = joinsOf(W, "TwizCrewHQ")
      W:advance(120)
      A.eq(joinsOf(W, "TwizCrewHQ"), joins, "the old planned try does nothing")
      noErrors(ns, A)
    end,
    sends_are_logged_for_debugging = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      ns.Comm.send("PING", {})
      W:advance(1)
      A.ok(logHas(ns, "DEBUG send PING via CHANNEL to 5"))
    end,
    changing_crew_code_rejoins = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      A.ok(ns.Transport.status().joined)
      ns.Modules.set("comm", "channel", "OtherHQ")
      A.eq(W.leaves, { "TwizCrewHQ" })
      W:advance(3)
      A.eq(W.state.channels.OtherHQ, 5)
      A.eq(ns.Transport.status().channel, "OtherHQ")
      A.ok(ns.Transport.status().joined)
    end,
  },
}
