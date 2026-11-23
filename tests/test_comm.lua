-- Comm and Transport: every broadcast is one GUILD message, a whisper goes only to a guild member, and anything from
-- someone outside the guild is dropped before it is decoded.

-- The guild list for these tests: me (Twiz) and two friends, all online. `more` adds that many online members.
local function guildOf(W, more)
  local members = {
    { name = "Twiz", online = true, guid = "Player-1-0001" },
    { name = "Ginkan Pebble", class = "PRIEST", online = true },
    { name = "Frostie Snow", class = "MAGE", online = true },
  }
  for i = 1, more or 0 do members[#members + 1] = { name = "Member" .. i .. " Extra", online = true } end
  W.state.guild = { name = "Test Guild", members = members }
end

-- mutate(W) runs before anything starts (W.state.guild = nil: not in a guild).
local function boot(ns, W, mutate, saved)
  W.state.player = "Twiz"
  guildOf(W)
  if mutate then mutate(W) end
  local db = ns.DB.init(saved, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  ns.Guild.start()
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

local function countLog(ns, text)
  local n = 0
  for _, line in ipairs(ns.Log.lines()) do if line:find(text, 1, true) then n = n + 1 end end
  return n
end

local function addon(W, text, chatType, sender)
  W:fire("CHAT_MSG_ADDON", "TwizCrew", text, chatType, sender)
end

-- Senders heard by PING handlers.
local function pingSenders(ns)
  local got = {}
  ns.Comm.on("PING", function(sender) got[#got + 1] = sender end)
  return got
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/Log.lua", "Core/Events.lua", "Core/Modules.lua", "Core/DB.lua",
    "Crew/GuildNames.lua", "Crew/GuildIdentity.lua", "Crew/Guild.lua", "Crew/GuildCommands.lua",
    "Comm/Codec.lua", "Comm/Queue.lua", "Comm/Transport.lua", "Comm/Comm.lua" },
  tests = {
    ------------------------------------------------------------------------------------------------ sending
    broadcast_is_one_guild_send = function(ns, A, W)
      boot(ns, W, function(w) w.state.guild.members = { w.state.guild.members[1], w.state.guild.members[2] } end)
      for _, size in ipairs({ 2, 10, 50 }) do
        local members = { { name = "Twiz", online = true, guid = "Player-1-0001" } }
        for i = 2, size do members[i] = { name = "Member" .. i .. " Extra", online = true } end
        W.state.guild.members = members
        W:fire("GUILD_ROSTER_UPDATE")
        W:advance(2)
        local online, total = ns.Guild.count()
        A.eq({ online, total }, { size, size }, "the list has " .. size)
        A.eq(ns.Transport.destinations(), { { chatType = "GUILD" } })
        local before = #W.sent
        ns.Comm.send("UPDATE", { zn = "Westfall" })
        W:advance(2)
        A.eq(#W.sent - before, 1, size .. " members: one send")
        A.eq(W.sent[#W.sent].chatType, "GUILD")
        A.eq(W.sent[#W.sent].target, nil)
      end
      noErrors(ns, A)
    end,
    sends_wait_until_the_game_says_whether_we_are_in_a_guild = function(ns, A, W)
      local inGuild = false
      boot(ns, W, function(w)
        w.state.guild.name = "Late Guild"
        w.env.IsInGuild = function() return inGuild end -- the game has not loaded the guild yet
      end)
      A.ok(ns.Transport.isPending())
      local ready = 0
      ns.Bus.on("test", "TRANSPORT_READY", function() ready = ready + 1 end)
      ns.Comm.send("HELLO", { ver = "1" })
      ns.Comm.send("PING", {})
      W:advance(3)
      A.eq(#W.sent, 0)
      inGuild = true
      W:advance(2)
      A.no(ns.Transport.isPending())
      A.eq(ready, 1)
      A.eq(#W.sent, 2, "the kept messages went out, in order")
      A.contains(W.sent[1].text, "HELLO")
      A.contains(W.sent[2].text, "PING")
      A.eq(W.sent[1].chatType, "GUILD")
      A.eq(ns.Transport.status(), { mode = "guild", pending = false, waitingList = false, guild = "Late Guild", lockdown = false,
        lastResult = 0, reload = false, dataGuild = "Late Guild", guildId = "Late Guild", notOurs = false,
        deciding = false })
    end,
    not_in_a_guild_settles_after_the_grace_and_sends_nothing = function(ns, A, W)
      boot(ns, W, function(w) w.state.guild = nil end)
      A.ok(ns.Transport.isPending())
      ns.Comm.send("HELLO", { ver = "1" })
      W:advance(ns.Config.GUILD_ABSENT_GRACE + 2)
      A.no(ns.Transport.isPending(), "settled: not in a guild")
      A.eq(ns.Transport.destinations(), {})
      A.eq(ns.Transport.destinationFor("Frostie"), nil)
      local done = 0
      ns.Comm.send("PING", {}, { onSent = function() done = done + 1 end })
      A.eq(done, 1, "nothing to send: done at once")
      A.no(ns.Comm.sendTo("Frostie", "SREQ", {}))
      W:advance(60)
      A.eq(#W.sent, 0)
      A.eq(ns.Transport.status().mode, "none")
      noErrors(ns, A)
    end,
    messages_still_queued_when_we_leave_the_guild_are_dropped = function(ns, A, W)
      boot(ns, W)
      W:advance(6)
      for _ = 1, 10 do ns.Comm.send("PING", {}) end
      ns.Comm.sendTo("Frostie", "SREQ", {})
      W:advance(0.2)
      A.eq(#W.sent, 4, "the first ones went out")
      W.state.guild = nil -- kicked
      W:advance(30)
      A.eq(#W.sent, 4, "the rest never reach the game")
      A.eq(ns.Transport.destinations(), {}, "at once, before the guild module says so")
      noErrors(ns, A)
    end,
    asks_within_the_window_are_answered_once = function(ns, A, W)
      boot(ns, W)
      local answers = {}
      local function answer(to) answers[#answers + 1] = to or "guild" end
      ns.Comm.answerAsk("x", "Frostie", answer)
      ns.Comm.answerAsk("x", "Ginkan", answer)
      ns.Comm.answerAsk("x", "Ginkan", answer)
      ns.Comm.answerAsk("y", "Lurabe", answer)
      W:advance(ns.Config.ASK_COLLECT - 0.5)
      A.eq(answers, {}, "collecting")
      W:advance(1)
      table.sort(answers)
      A.eq(answers, { "Lurabe", "guild" }, "two askers: one guild answer; one asker: a whisper")
      ns.Comm.answerAsk("x", "Frostie", answer, 10)
      W:advance(9)
      A.eq(#answers, 2)
      W:advance(2)
      A.eq(answers[3], "Frostie", "a window of its own")
      -- two copies asking for x again and again: one guild answer per ASK_ANSWER_GAP
      for _ = 1, 5 do
        ns.Comm.answerAsk("x", "Frostie", answer)
        ns.Comm.answerAsk("x", "Ginkan", answer)
        W:advance(ns.Config.ASK_COLLECT + 1)
      end
      A.eq(#answers, 3, "inside the gap of the first guild answer: ignored")
      W:advance(ns.Config.ASK_ANSWER_GAP)
      ns.Comm.answerAsk("x", "Frostie", answer)
      ns.Comm.answerAsk("x", "Ginkan", answer)
      W:advance(ns.Config.ASK_COLLECT + 1)
      A.eq(answers[4], "guild", "answered again after the gap")
    end,
    whispers_go_to_guild_members_only_by_full_name = function(ns, A, W)
      boot(ns, W)
      A.eq(ns.Transport.destinationFor("Frostie"), { chatType = "WHISPER", target = "Frostie Snow" })
      A.eq(ns.Transport.destinationFor("ginkan pebble"), { chatType = "WHISPER", target = "Ginkan Pebble" })
      A.eq(ns.Transport.destinationFor("Twiz"), nil, "never ourselves")
      A.eq(ns.Transport.destinationFor("Stranger"), nil, "not in the guild")
      A.eq(ns.Transport.fullName("Frostie"), "Frostie Snow")
      A.eq(ns.Transport.fullName("Stranger-Realm"), "Stranger", "unknown: the short name")
      A.ok(ns.Comm.sendTo("Frostie", "SREQ", {}))
      A.no(ns.Comm.sendTo("Stranger", "SREQ", {}))
      W:advance(1)
      A.eq(#W.sent, 1)
      A.eq(W.sent[1].chatType, "WHISPER")
      A.eq(W.sent[1].target, "Frostie Snow")
    end,
    -- A one-word member "Frost" gets "Frost (2)" when "Frost Bite" already holds "Frost": a whisper to the key "Frost"
    -- goes to Frost Bite, not to the member whose full name is "Frost".
    a_whisper_to_a_key_goes_to_its_holder_not_to_a_member_named_like_it = function(ns, A, W)
      boot(ns, W, function(w)
        local list = w.state.guild.members
        list[#list + 1] = { name = "Frost Bite", online = true, guid = "Player-1-0901" }
        list[#list + 1] = { name = "Frost", online = true, guid = "Player-1-0902" }
      end, { guild = { name = "Test Guild", keys = { ["frost bite"] = "Frost" } } })
      A.eq(ns.Guild.get("Frost").full, "Frost Bite")
      A.eq(ns.Guild.get("Frost (2)").full, "Frost")
      A.eq(ns.Transport.destinationFor("Frost"), { chatType = "WHISPER", target = "Frost Bite" })
      A.eq(ns.Transport.destinationFor("Frost (2)"), { chatType = "WHISPER", target = "Frost" })
      A.eq(ns.Transport.fullName("Frost"), "Frost Bite")
    end,
    no_whisper_before_the_list_loads = function(ns, A, W)
      local rows = 0
      boot(ns, W, function(w)
        local real = w.env.GetNumGuildMembers
        w.env.GetNumGuildMembers = function() if rows == 0 then return 0, 0, 0 end return real() end
      end)
      A.ok(ns.Transport.isPending(), "in a guild: sends wait for the list (answers to a HELLO need it)")
      ns.Comm.send("HELLO", { ver = "1" })
      W:advance(3)
      A.eq(#W.sent, 0)
      A.eq(ns.Transport.destinationFor("Frostie"), nil, "who is Frostie? the list has not loaded")
      rows = 3
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(1)
      A.no(ns.Transport.isPending(), "the list is in")
      A.eq(#W.sent, 1, "the kept HELLO went out")
      A.eq(ns.Transport.destinationFor("Frostie"), { chatType = "WHISPER", target = "Frostie Snow" })
    end,
    a_list_that_never_comes_stops_holding_sends_after_the_wait = function(ns, A, W)
      boot(ns, W, function(w) w.env.GetNumGuildMembers = function() return 0, 0, 0 end end)
      ns.Comm.send("HELLO", { ver = "1" })
      W:advance(ns.Config.GUILD_LIST_WAIT - 1)
      A.ok(ns.Transport.isPending())
      A.eq(#W.sent, 0)
      W:advance(2)
      A.no(ns.Transport.isPending(), "waited GUILD_LIST_WAIT s")
      A.eq(#W.sent, 1)
      A.eq(W.sent[1].chatType, "GUILD")
    end,
    group_send_goes_to_the_group_only = function(ns, A, W)
      boot(ns, W)
      A.no(ns.Comm.sendGroup("POS", { c = "0", x = "1", y = "2" }), "not grouped: nothing")
      W:advance(1)
      A.eq(#W.sent, 0)
      W.state.inGroup = true
      W.state.groupMembers = { "Frostie" }
      A.ok(ns.Comm.sendGroup("POS", { c = "0", x = "1", y = "2" }, { replace = "POS" }))
      A.ok(ns.Comm.sendGroup("POS", { c = "0", x = "5", y = "6" }, { replace = "POS" }))
      W:advance(1)
      A.eq(#W.sent, 1, "the newer position replaced the waiting one")
      A.eq(W.sent[1].chatType, "PARTY")
      A.contains(W.sent[1].text, "x=5")
      W.state.inRaid = true
      ns.Comm.sendGroup("MEET", { id = "a" })
      W:advance(1)
      A.eq(W.sent[2].chatType, "RAID")
      A.eq(ns.Codec.decode(W.sent[1].text).type, "POS")
      A.eq(ns.Codec.decode(W.sent[2].text).type, "MEET")
      noErrors(ns, A)
    end,
    a_broadcast_never_gets_a_party_copy = function(ns, A, W)
      boot(ns, W, function(w)
        w.state.inGroup = true
        w.state.groupMembers = { "Frostie" }
      end)
      A.eq(ns.Transport.destinations(), { { chatType = "GUILD" } })
      W.state.inRaid = true
      A.eq(ns.Transport.destinations(), { { chatType = "GUILD" } })
      A.eq(ns.Transport.groupDestination(), { chatType = "RAID" })
    end,
    send_replace_keeps_one_waiting_copy = function(ns, A, W)
      boot(ns, W)
      for _ = 1, 6 do ns.Comm.send("PING", {}) end -- fill the bucket so the rest has to wait
      W:advance(0.2)
      local mark = #W.sent
      ns.Comm.send("AWC", { id = "s", i = "1" }, { replace = "s" })
      ns.Comm.send("AWC", { id = "s", i = "2" }, { replace = "s" })
      ns.Comm.send("AWC", { id = "other", i = "1" }, { replace = "other" })
      ns.Comm.send("AWS", { id = "s" })
      ns.Comm.send("AWS", { id = "s" })
      W:advance(30)
      local awc, aws = {}, 0
      for i = mark + 1, #W.sent do
        local m = ns.Codec.decode(W.sent[i].text)
        if m.type == "AWC" then awc[#awc + 1] = m.fields.id .. m.fields.i end
        if m.type == "AWS" then aws = aws + 1 end
      end
      table.sort(awc)
      A.eq(awc, { "other1", "s2" }, "only the latest card of a show")
      A.eq(aws, 2, "other types are never replaced")
      noErrors(ns, A)
    end,
    send_on_sent_runs_when_the_copy_left = function(ns, A, W)
      boot(ns, W)
      for _ = 1, 6 do ns.Comm.send("PING", {}) end
      local doneAt, calls = nil, 0
      ns.Comm.send("AWV", { id = "s" }, { onSent = function() calls = calls + 1; doneAt = #W.sent end })
      A.eq(calls, 0, "still waiting")
      W:advance(30)
      A.eq(calls, 1)
      A.eq(ns.Codec.decode(W.sent[doneAt].text).type, "AWV", "right after it went out")
      noErrors(ns, A)
    end,
    throttled_send_is_retried = function(ns, A, W)
      boot(ns, W)
      W.state.sendResult = 3 -- AddonMessageThrottle: "try again later"
      for i = 1, 3 do ns.Comm.send("PING", { n = tostring(i) }) end
      W:advance(4)
      A.ok(#W.sent >= 2, "the throttled send was tried again")
      for _, s in ipairs(W.sent) do A.contains(s.text, "n=1", "nothing skipped past the throttled message") end
      W.state.sendResult = 8 -- ChannelThrottle
      W:advance(4)
      W.state.sendResult = 0
      local before = #W.sent
      W:advance(3)
      local got = {}
      for i = before + 1, #W.sent do got[#got + 1] = W.sent[i].text:match("n=(%d)") end
      A.eq(got, { "1", "2", "3" })
    end,
    queue_holds_during_chat_lockdown_and_resumes = function(ns, A, W)
      local locked = true
      boot(ns, W, function(w) w.env.InChatMessagingLockdown = function() return locked end end)
      ns.Comm.send("PING", { n = "1" })
      ns.Comm.send("PING", { n = "2" })
      W:advance(5)
      A.eq(#W.sent, 0, "nothing goes out during a chat lockdown")
      A.ok(ns.Transport.status().lockdown)
      locked = false
      W:advance(1)
      A.eq(#W.sent, 2, "both went out once it ended")
      A.no(ns.Transport.status().lockdown)
      -- the function may live in C_ChatInfo instead, and may answer a secret value (treated as "no lockdown")
      W.env.InChatMessagingLockdown = nil
      W.env.C_ChatInfo.InChatMessagingLockdown = function() return true end
      ns.Comm.send("PING", { n = "3" })
      W:advance(3)
      A.eq(#W.sent, 2)
      W.env.C_ChatInfo.InChatMessagingLockdown = function() return W.secret() end
      W:advance(1)
      A.eq(#W.sent, 3)
      noErrors(ns, A)
    end,
    a_lockdown_send_result_waits_and_tries_again = function(ns, A, W)
      boot(ns, W)
      W.state.sendResult = 11 -- AddOnMessageLockdown
      ns.Comm.send("PING", { n = "1" })
      W:advance(3)
      A.ok(#W.sent >= 2, "tried again")
      A.eq(ns.Log.counts()["send failed"], nil, "not counted as failed while it waits")
      W.state.sendResult = 0
      W:advance(2)
      A.eq(W.sent[#W.sent].result, 0)
      A.contains(W.sent[#W.sent].text, "n=1")
    end,
    holds_during_boss_fight = function(ns, A, W)
      boot(ns, W)
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
    sends_are_logged_for_debugging = function(ns, A, W)
      boot(ns, W)
      ns.Log.chatDebug = true
      ns.Comm.send("PING", {})
      W:advance(1)
      A.ok(logHas(ns, "DEBUG send PING via GUILD to -"))
    end,
    refused_send_is_counted = function(ns, A, W)
      boot(ns, W)
      W.state.sendResult = 7
      ns.Comm.send("PING", {})
      W:advance(5)
      A.ok(ns.Log.counts()["send failed"] >= 1)
      A.eq(ns.Transport.status().lastResult, 7)
    end,
    -- In a dungeon IsInGuild may answer a secret value for minutes: Guild.active() still holds, so sends go on.
    sends_go_on_while_IsInGuild_is_unreadable = function(ns, A, W)
      boot(ns, W)
      W:advance(2)
      A.ok(ns.Guild.active())
      local real = W.env.IsInGuild
      W.env.IsInGuild = function() return W.secret() end
      for minute = 1, 4 do
        local before = #W.sent
        ns.Comm.send("UPDATE", { zn = "Deadmines " .. minute })
        W:advance(60)
        A.eq(#W.sent - before, 1, "minute " .. minute .. ": the guild message went out")
        A.eq(W.sent[#W.sent].chatType, "GUILD")
      end
      A.eq(ns.Transport.destinations(), { { chatType = "GUILD" } })
      W.env.IsInGuild = real
      noErrors(ns, A)
    end,
    a_refused_send_is_given_up_after_the_retry_cap = function(ns, A, W)
      boot(ns, W)
      W.state.sendResult = 3 -- "try again later", for good
      local done = 0
      ns.Comm.send("PING", { n = "1" }, { onSent = function() done = done + 1 end })
      ns.Comm.send("PING", { n = "2" })
      W:advance(8)
      A.eq(countLog(ns, "given up"), 0, "still trying")
      W:advance(45)
      A.eq(countLog(ns, "send to GUILD given up after " .. ns.Config.SEND_RETRY_MAX .. " tries"), 2,
        "one line per dropped message")
      A.eq(done, 1, "the sent callback ran for the dropped message")
      W.state.sendResult = 0
      local n = #W.sent
      ns.Comm.send("PING", { n = "3" })
      W:advance(2)
      A.eq(#W.sent, n + 1, "the queue moved on")
      A.contains(W.sent[#W.sent].text, "n=3")
    end,
    hides_not_found_line_for_whispered_names = function(ns, A, W)
      boot(ns, W)
      ns.Comm.sendTo("Ginkan", "SREQ", {})
      W:advance(1)
      local f
      for _, x in ipairs(W.messageFilters) do if x.event == "CHAT_MSG_SYSTEM" then f = x.fn end end
      A.ok(f, "a CHAT_MSG_SYSTEM filter")
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Ginkan Pebble' is currently playing."), true)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Stranger' is currently playing."), false)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", nil), false)
      W:advance(11)
      A.eq(f(nil, "CHAT_MSG_SYSTEM", "No player named 'Ginkan Pebble' is currently playing."), false)
    end,

    ------------------------------------------------------------------------------------------------ receiving
    whisper_from_a_stranger_is_dropped_and_counted = function(ns, A, W)
      boot(ns, W)
      local got = pingSenders(ns)
      addon(W, "1^PING^", "WHISPER", "Stranger Danger-Realm")
      addon(W, "1^PING^", "WHISPER", "Stranger")
      A.eq(got, {})
      A.eq(ns.Log.counts()["recv not in guild"], 2)
      A.eq(ns.Log.counts()["recv PING"], nil, "not even decoded")
      addon(W, "1^PING^", "WHISPER", "Frostie Snow-Realm")
      addon(W, "1^PING^a", "WHISPER", "Ginkan")
      A.eq(got, { "Frostie", "Ginkan" }, "members are heard under their key")
      noErrors(ns, A)
    end,
    party_message_from_a_stranger_is_dropped = function(ns, A, W)
      boot(ns, W)
      local got = pingSenders(ns)
      addon(W, "1^PING^", "PARTY", "Stranger Danger")
      addon(W, "1^PING^", "RAID", "Stranger Danger")
      addon(W, "1^PING^", "CHANNEL", "Stranger Danger")
      A.eq(got, {})
      A.eq(ns.Log.counts()["recv not in guild"], 3)
      addon(W, "1^PING^", "PARTY", "Frostie Snow")
      A.eq(got, { "Frostie" })
    end,
    guild_message_before_the_list_loads_is_accepted = function(ns, A, W)
      local rows = 0
      boot(ns, W, function(w)
        local real = w.env.GetNumGuildMembers
        w.env.GetNumGuildMembers = function() if rows == 0 then return 0, 0, 0 end return real() end
      end)
      A.no(ns.Guild.loaded())
      local got = pingSenders(ns)
      addon(W, "1^PING^", "GUILD", "Frostie Snow")
      A.eq(got, { "Frostie" }, "a guild message is from a member: provisional key")
      addon(W, "1^PING^a", "WHISPER", "Frostie Snow")
      addon(W, "1^PING^b", "PARTY", "Ginkan Pebble")
      A.eq(got, { "Frostie" }, "whispers and party messages wait for the list")
      A.eq(ns.Log.counts()["recv not in guild"], 2)
      rows = 3
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(2)
      addon(W, "1^PING^c", "WHISPER", "Frostie Snow")
      A.eq(got, { "Frostie", "Frostie" })
    end,
    -- An alt in guild B logs in with guild A's data on top; the game does not answer IsInGuild yet (the guild state is
    -- not known): nothing is accepted until TwizCrew uses this guild's data.
    nothing_is_accepted_while_the_guild_state_is_not_known = function(ns, A, W)
      local answer = false
      local db = boot(ns, W, function(w)
        local real = w.env.IsInGuild
        w.env.IsInGuild = function() if not answer then return nil end return real() end
      end, { guild = { name = "Guild A" } })
      A.no(ns.Guild.known(), "the game has not said yet")
      local got = pingSenders(ns)
      addon(W, "1^PING^", "GUILD", "Frostie Snow")
      addon(W, "1^PING^", "WHISPER", "Ginkan Pebble")
      A.eq(got, {}, "nothing accepted while not known")
      A.eq(ns.Log.counts()["recv not in guild"], 2)
      answer = true
      W:advance(2)
      A.ok(ns.Guild.inGuild()); A.no(ns.Guild.active(), "guild A's data, guild B")
      addon(W, "1^PING^a", "GUILD", "Frostie Snow")
      A.eq(got, {}, "another guild's data: still nothing")
      db.guild.name = "Test Guild" -- (as if this guild's data were on top)
      W:advance(2)
      A.ok(ns.Guild.active())
      addon(W, "1^PING^b", "GUILD", "Frostie Snow")
      A.eq(got, { "Frostie" }, "this guild's data in use: accepted")
    end,
    guild_message_before_the_list_loads_uses_the_saved_key = function(ns, A, W)
      local rows = 0
      boot(ns, W, function(w)
        local real = w.env.GetNumGuildMembers
        w.env.GetNumGuildMembers = function() if rows == 0 then return 0, 0, 0 end return real() end
      end, { guild = { name = "Test Guild", keys = { ["frostie pebble"] = "Frostie", ["frostie snow"] = "Frostie Snow",
        ["ginkan pebble"] = "Ginkan" } } })
      A.no(ns.Guild.loaded())
      local got = pingSenders(ns)
      addon(W, "1^PING^", "GUILD", "Frostie Snow")
      addon(W, "1^PING^", "GUILD", "Frostie Pebble-Realm")
      addon(W, "1^PING^", "GUILD", "Ginkan Pebble")
      addon(W, "1^PING^", "GUILD", "Frostie Newbie") -- never listed, and "Frostie" is Pebble's
      addon(W, "1^PING^", "GUILD", "Lurabe Moon")    -- never listed, nobody's word
      A.eq(got, { "Frostie Snow", "Frostie", "Ginkan", "Frostie Newbie", "Lurabe" })
    end,
    guild_message_from_someone_the_list_does_not_have_yet = function(ns, A, W)
      boot(ns, W)
      local got = pingSenders(ns)
      local asked = W.guildRosterCalls
      W:advance(11)
      addon(W, "1^PING^", "GUILD", "Newbie Joined")
      A.eq(got, { "Newbie" }, "a guild message: their first word, until the list knows them")
      A.ok(W.guildRosterCalls > asked, "and the list is asked again")
      -- a newcomer whose first word is already a member's key never takes that key
      addon(W, "1^PING^a", "GUILD", "Frostie Other")
      A.eq(got[2], "Frostie Other")
      addon(W, "1^PING^b", "GUILD", "Twiz Somebody")
      A.eq(got[3], "Twiz Somebody", "nor mine")
    end,
    receive_ignores_self_in_every_form = function(ns, A, W)
      boot(ns, W)
      local got = pingSenders(ns)
      addon(W, "1^PING^", "GUILD", "Twiz")
      addon(W, "1^PING^a", "GUILD", "Twiz-Realm")
      addon(W, "1^PING^b", "PARTY", "Twiz")
      addon(W, "1^PING^c", "WHISPER", "Twiz-Realm")
      addon(W, "1^PING^", "GUILD", "Ginkan-Realm")
      addon(W, "1^PING^", "WHISPER", "Holybøi-OtherRealm")
      W:fire("CHAT_MSG_ADDON", "Other", "1^PING^", "GUILD", "Ginkan-Realm")
      A.eq(got, { "Ginkan" })
      A.eq(ns.Log.counts()["recv not in guild"], 1, "Holybøi is not in the guild")
    end,
    -- In a dungeon UnitName / UnitGUID("player") may turn secret after login: my own guild echo is still mine.
    my_own_echo_stays_mine_when_my_name_turns_secret = function(ns, A, W)
      boot(ns, W)
      W:advance(2)
      A.eq(ns.Guild.myKey(), "Twiz")
      local got = pingSenders(ns)
      W.env.UnitName = function() return W.secret() end
      W.env.UnitGUID = function() return W.secret() end
      addon(W, "1^PING^", "GUILD", "Twiz")
      addon(W, "1^PING^a", "GUILD", "Twiz-Realm")
      A.eq(got, {}, "my own echo is never someone else's message")
      A.ok(ns.Guild.isMe("Twiz")); A.eq(ns.Guild.myKey(), "Twiz")
      addon(W, "1^PING^b", "GUILD", "Ginkan Pebble")
      A.eq(got, { "Ginkan" })
      noErrors(ns, A)
    end,
    raw_hook_sees_everything_first = function(ns, A, W)
      boot(ns, W)
      local raw = {}
      ns.Comm.onRaw(function(text, chatType, sender) raw[#raw + 1] = chatType .. " " .. sender end)
      addon(W, "1^PING^", "GUILD", "Twiz")
      addon(W, "1^PING^", "WHISPER", "Stranger")
      A.eq(raw, { "GUILD Twiz", "WHISPER Stranger" })
    end,
    receive_passes_fields_to_handlers = function(ns, A, W)
      boot(ns, W)
      local seen
      ns.Comm.on("HELLO", function(sender, fields) seen = { sender, fields.zn } end)
      local texts = ns.Codec.encode("HELLO", { zn = "Elwynn Forest" })
      addon(W, texts[1], "WHISPER", "Ginkan Pebble")
      A.eq(seen, { "Ginkan", "Elwynn Forest" })
    end,
    receive_ignores_a_newer_protocol = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      addon(W, "2^PING^", "GUILD", "Ginkan")
      addon(W, "99^PING^", "WHISPER", "Frostie")
      A.eq(n, 0, "a newer protocol is not handled")
      A.eq(ns.Log.counts()["recv newer protocol"], 2)
      A.no(ns.Log.counts()["recv PING"], "not counted as a PING")
      addon(W, "1^PING^", "GUILD", "Ginkan")
      A.eq(n, 1, "the current protocol still works")
    end,
    -- An old copy (v0.1.24) in my party and guild whispers and sends to the party: the second route is a duplicate.
    receive_dedupes_the_same_text_by_another_route = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      addon(W, "1^PING^", "WHISPER", "Ginkan")
      addon(W, "1^PING^", "PARTY", "Ginkan")
      A.eq(n, 1)
      addon(W, "1^PING^", "WHISPER", "Ginkan")
      A.eq(n, 2, "the same route twice is a resend")
      W:advance(3)
      addon(W, "1^PING^", "PARTY", "Ginkan")
      A.eq(n, 3)
    end,
    dedupe_table_does_not_grow_forever = function(ns, A, W)
      boot(ns, W)
      for i = 1, 300 do
        addon(W, "1^PING^x" .. i, "GUILD", "Ginkan")
        W:advance(1)
      end
      A.ok(ns.Comm.dedupeSize() < 20, "dedupe size " .. ns.Comm.dedupeSize())
    end,
    garbage_message_is_ignored_quietly = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() n = n + 1 end)
      addon(W, "nonsense", "GUILD", "Ginkan")
      addon(W, "", "GUILD", "Ginkan")
      A.eq(n, 0)
      noErrors(ns, A)
    end,
    a_failing_handler_does_not_stop_others = function(ns, A, W)
      boot(ns, W)
      local n = 0
      ns.Comm.on("PING", function() error("boom") end)
      ns.Comm.on("PING", function() n = n + 1 end)
      addon(W, "1^PING^", "GUILD", "Ginkan")
      A.eq(n, 1)
    end,
    chatter_is_counted_not_logged_while_debug_is_off = function(ns, A, W)
      boot(ns, W)
      addon(W, "1^PING^", "WHISPER", "Ginkan Pebble") -- first sight of a name form logs once
      local before = #ns.Log.lines()
      for _ = 2, 50 do addon(W, "1^PING^", "WHISPER", "Ginkan Pebble") end
      A.eq(ns.Log.counts()["recv PING"], 50)
      A.eq(#ns.Log.lines(), before, "no log line for received messages")
      ns.Comm.send("PING", {})
      W:advance(2)
      A.ok(ns.Log.counts()["send PING"] >= 1)
      for _, line in ipairs(ns.Log.lines()) do A.no(line:find("send PING", 1, true)) end
    end,

    ------------------------------------------------------------------------------------------------ module
    debug_setting_controls_chat_debug = function(ns, A, W)
      boot(ns, W)
      A.eq(ns.Log.chatDebug, false)
      ns.Modules.set("comm", "debug", true)
      A.eq(ns.Log.chatDebug, true)
      ns.Modules.set("comm", "debug", false)
      A.eq(ns.Log.chatDebug, false)
    end,
    comm_is_an_essential_module_with_only_the_debug_setting = function(ns, A)
      local d = ns.Modules.get("comm")
      A.eq(d.tier, "essential")
      A.eq(d.name, "Crew connection")
      A.eq(d.defaults, { debug = false })
      A.eq(#d.settings, 1)
      A.eq(d.settings[1].key, "debug")
    end,
    old_channel_settings_are_cleared_on_upgrade = function(ns, A, W)
      local db = boot(ns, W, function(w) w.state.channels.TwizCrewHQ = 6 end, {
        crew = { channel = "TwizCrewHQ", password = "goldshire", extra = { "Frostie" } },
        modules = { comm = { enabled = true, settings = { transport = "whisper", debug = false } } },
      })
      A.eq(db.crew, { channel = "TwizCrewHQ" }, "only the channel name stays, until we are out of it")
      A.eq(db.modules.comm.settings, { debug = false })
      A.eq(W.leaves, {}, "the game may not have rejoined it yet")
      W:advance(6)
      A.eq(W.leaves, { "TwizCrewHQ" }, "left once")
      A.ok(logHas(ns, "left the old v0.1.24 channel TwizCrewHQ"))
      W:advance(3)
      A.eq(db.crew, nil, "out of it: the name goes too")
      W:fire("PLAYER_ENTERING_WORLD")
      W:advance(60)
      A.eq(W.leaves, { "TwizCrewHQ" })
      noErrors(ns, A)
    end,
    old_channel_is_left_again_until_it_is_really_gone = function(ns, A, W)
      local db = boot(ns, W, function(w)
        w.state.channels.TwizCrewHQ = 6
        w.state.leaveFails = true -- the game ignores the first leaves
      end, { crew = { channel = "TwizCrewHQ" } })
      W:advance(10)
      A.eq(W.leaves, { "TwizCrewHQ" })
      A.eq(db.crew, { channel = "TwizCrewHQ" }, "still in it: the marker stays")
      W:fire("PLAYER_ENTERING_WORLD") -- a loading screen: try again
      W.state.leaveFails = false
      W:advance(10)
      A.eq(W.leaves, { "TwizCrewHQ", "TwizCrewHQ" })
      A.eq(db.crew, nil, "gone now")
      A.ok(logHas(ns, "the old v0.1.24 channel TwizCrewHQ is gone"))
    end,
    -- The game may rejoin saved channels later than our first look: "not there" once is not "gone".
    old_channel_joined_after_the_first_check_is_still_left = function(ns, A, W)
      local db = boot(ns, W, nil, { crew = { channel = "TwizCrewHQ", password = "goldshire" } })
      W:advance(10)
      A.eq(W.leaves, {}, "not there yet: nothing to leave")
      A.eq(db.crew, { channel = "TwizCrewHQ", zeroLogins = 1 }, "the marker stays")
      W.state.channels.TwizCrewHQ = 6 -- the game rejoins it now
      W:fire("PLAYER_ENTERING_WORLD")
      W:advance(10)
      A.eq(W.leaves, { "TwizCrewHQ" })
      A.eq(db.crew, nil, "seen, left, gone")
      A.ok(logHas(ns, "the old v0.1.24 channel TwizCrewHQ is gone (left)"))
    end,
    nothing_left_of_the_channel = function(ns, A, W)
      boot(ns, W)
      for _, name in ipairs({ "members", "rejoin", "heardFrom", "forget", "parseList" }) do
        A.eq(ns.Transport[name], nil, "Transport." .. name)
      end
      A.eq(ns.Comm.echoCount, nil)
      A.eq(ns.Config.DEFAULT_CHANNEL, nil)
      A.eq(ns.Config.DEFAULT_PASSWORD, nil)
      W:advance(30)
      A.eq(W.joins, {}, "no channel is joined")
      for _, f in ipairs(W.messageFilters) do A.eq(f.event, "CHAT_MSG_SYSTEM", "no channel line filters") end
    end,
  },
}
