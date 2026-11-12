-- Stats sharing (stats Task 6): STATS / STATSREQ in and out, the "off" announcement, friends' saved numbers and
-- StatsStore.entries (what the Hall of Shame and the awards show read). Full TOC boot.

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W.env.TwizCrewDB.modules.tags.settings.autoAway = false -- no mouse in the fake game: not idle-away after 3 minutes
  W:fire("PLAYER_ENTERING_WORLD")
end

local function receive(W, sender, msgType, fields, ns)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- Boots with a stand-in ns.Roasts and lets the session be decided (that sends the first STATS).
local function start(ns, W)
  ns.Roasts = { send = function() end }
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

-- Decoded STATS messages in W.sent after index `from` (fields tables).
local function statsSince(ns, W, from)
  local out = {}
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == "STATS" then out[#out + 1] = msg.fields end
  end
  return out
end

local function countType(ns, W, from, msgType)
  local n = 0
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then n = n + 1 end
  end
  return n
end

local function hasNumbers(fields)
  for k in pairs(fields) do
    if k:match("^[sa]_") then return true end
  end
  return false
end

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.name end
  table.sort(out)
  return out
end

local function find(list, name)
  for _, e in ipairs(list) do if e.name == name then return e end end
end

-- A snapshot's STATS pieces, as a copy sends them (one text per piece).
local function pieces(ns, snap)
  return ns.Codec.encode("STATS", ns.StatsLogic.toWire(snap), { repeatKeys = { "sid", "q", "off" } })
end

local function fireText(W, sender, text) W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender) end

-- Every award's leaders on the board, both views: "session:<id>" / "all:<id>" -> names.
local function leadersOf(ns, sid)
  local out = {}
  for _, view in ipairs({ "session", "all" }) do
    local list = ns.StatsLogic.awards(ns.StatsStore.entries(view, sid))
    for id, names in pairs(ns.TrophyLogic.leaders(list)) do out[view .. ":" .. id] = names end
  end
  return out
end

-- Every number of every key: base + i in both views (gold carried is the same in both).
local function bigSnap(ns, sid, q, base)
  local s, a = {}, {}
  for i, key in ipairs(ns.StatsDefs.KEYS) do
    s[key] = base + i
    a[key] = key == "gn" and s[key] or 10 * (base + i)
  end
  return { sid = sid, q = q, s = s, a = a }
end

return {
  files = "toc",
  tests = {
    sends_after_session_and_only_when_changed = function(ns, A, W)
      ns.Roasts = { send = function() end }
      boot(W)
      W:advance(21)
      local sent = statsSince(ns, W, 0)
      A.eq(#sent, 1, "one STATS once the session is decided")
      A.eq(sent[1].sid, ns.Session.current().id)
      A.ok(sent[1].q ~= nil, "a snapshot token")
      local mark = #W.sent
      W:advance(300)
      A.eq(#statsSince(ns, W, mark), 0, "nothing counted: nothing sent")
      ns.Stats.count("jp", 1)
      mark = #W.sent
      W:advance(300)
      sent = statsSince(ns, W, mark)
      A.eq(#sent, 1)
      A.eq(sent[1].s_jp, "1")
      A.eq(sent[1].a_jp, "1")
      A.ok(ns.Stats.status().lastSent ~= nil, "remembers when it sent")
    end,

    played_time_alone_does_not_send = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      local pt = ns.StatsStore.get("all", "pt")
      W:advance(600)
      A.ok(ns.StatsStore.get("all", "pt") > pt, "time played still grows")
      A.eq(#statsSince(ns, W, mark), 0)
    end,

    statsreq_gets_one_jittered_reply = function(ns, A, W)
      start(ns, W)
      ns.Stats.count("dt", 2)
      local mark = #W.sent
      receive(W, "Frostie", "STATSREQ", {}, ns)
      A.eq(#statsSince(ns, W, mark), 0, "not at once")
      W:advance(0.5)
      receive(W, "Ginkan", "STATSREQ", {}, ns)
      W:advance(5)
      local sent = statsSince(ns, W, mark)
      A.eq(#sent, 1, "one shared reply")
      A.eq(sent[1].s_dt, "2")
      W:advance(20)
      A.eq(#statsSince(ns, W, mark), 1, "no second reply")
      A.eq(ns.Log.errors(10), {})
    end,

    statsreq_reply_within_2s = function(ns, A, W)
      start(ns, W)
      A.eq(ns.Config.STATSREQ_JITTER_MIN, 0.2)
      A.eq(ns.Config.STATSREQ_JITTER_MAX, 2)
      for i = 1, 12 do
        W:advance(61) -- past the reply gap
        local mark = #W.sent
        receive(W, i % 2 == 0 and "Frostie" or "Ginkan", "STATSREQ", {}, ns)
        W:advance(0.15)
        A.eq(#statsSince(ns, W, mark), 0, "not at once (" .. i .. ")")
        W:advance(1.85)
        A.eq(#statsSince(ns, W, mark), 1, "replied within 2 s (" .. i .. ")")
      end
      A.eq(ns.Log.errors(10), {})
    end,

    request_sends_my_changed_numbers = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      ns.Stats.count("jp", 3)
      A.eq(ns.Stats.request(), true)
      W:advance(1)
      A.eq(countType(ns, W, mark, "STATSREQ"), 1)
      local sent = statsSince(ns, W, mark)
      A.eq(#sent, 1, "my own numbers go out with the request")
      A.eq(sent[1].s_jp, "3")
      A.no(ns.StatsStore.dirty(), "marked as sent")
      -- nothing new: only the request
      W:advance(61)
      mark = #W.sent
      A.eq(ns.Stats.request(), true)
      W:advance(1)
      A.eq(countType(ns, W, mark, "STATSREQ"), 1)
      A.eq(#statsSince(ns, W, mark), 0, "nothing changed: no STATS")
      -- module off: the request sends no numbers either
      ns.Modules.setEnabled("stats", false)
      W:advance(61)
      mark = #W.sent
      ns.Stats.request()
      W:advance(1)
      A.eq(#statsSince(ns, W, mark), 0)
    end,

    request_is_rate_limited = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      A.eq(ns.Stats.request(), true)
      A.eq(ns.Stats.request(), false)
      W:advance(30)
      A.eq(ns.Stats.request(), false, "still inside the gap")
      A.eq(countType(ns, W, mark, "STATSREQ"), 1)
      W:advance(31)
      A.eq(ns.Stats.request(), true)
      W:advance(1)
      A.eq(countType(ns, W, mark, "STATSREQ"), 2)
    end,

    off_is_announced_and_hides_me = function(ns, A, W)
      start(ns, W)
      ns.Stats.count("dt", 3)
      A.ok(find(ns.StatsStore.entries("all"), "Twiz"), "on: I am on the board")
      local mark = #W.sent
      ns.Modules.setEnabled("stats", false)
      W:advance(1)
      local sent = statsSince(ns, W, mark)
      A.eq(#sent, 1, "one off message")
      A.eq(sent[1].off, "1")
      A.no(hasNumbers(sent[1]), "no numbers while off")
      A.eq(sent[1].sid, ns.Session.current().id)
      A.no(find(ns.StatsStore.entries("all"), "Twiz"), "off: not on my own board")
      mark = #W.sent
      receive(W, "Frostie", "STATSREQ", {}, ns)
      W:advance(6)
      sent = statsSince(ns, W, mark)
      A.eq(#sent, 1)
      A.eq(sent[1].off, "1")
      A.no(hasNumbers(sent[1]))
      mark = #W.sent
      W:advance(600)
      W:fire("PLAYER_LOGOUT")
      A.eq(#statsSince(ns, W, mark), 0, "off: no timed or logout sends")
      ns.Modules.setEnabled("stats", true)
      W:advance(1)
      sent = statsSince(ns, W, mark)
      A.eq(#sent, 1, "back on: numbers again")
      A.eq(sent[1].a_dt, "3")
      A.eq(sent[1].off, nil)
      A.eq(ns.Log.errors(10), {})
    end,

    off_at_login_is_announced = function(ns, A, W)
      ns.Roasts = { send = function() end }
      boot(W, function() ns.db.modules.stats.enabled = false end)
      A.no(ns.Modules.isEnabled("stats"))
      W:advance(21)
      local sent = statsSince(ns, W, 0)
      A.eq(#sent, 1, "one off message once the session is decided")
      A.eq(sent[1].off, "1")
      A.no(hasNumbers(sent[1]))
      A.eq(sent[1].sid, ns.Session.current().id, "a fresh character uses the session id, so friends keep it")
      local mark = #W.sent
      W:advance(600)
      A.eq(#statsSince(ns, W, mark), 0, "nothing more while nothing happens")
      ns.Bus.fire("SESSION_CHANGED", { id = "Frostie-5", start = 5, manual = true }, ns.Session.current(), false)
      W:advance(1)
      sent = statsSince(ns, W, mark)
      A.eq(#sent, 1, "again on a session change")
      A.eq(sent[1].off, "1")
      A.eq(ns.Log.errors(10), {})
    end,

    new_session_stats_carry_gold_carried = function(ns, A, W)
      W.state.money = 12345
      start(ns, W)
      W:advance(30)
      A.eq(ns.StatsStore.get("session", "gn"), 12345, "gold is read before the session change")
      local mark = #W.sent
      ns.Bus.fire("SESSION_CHANGED", { id = "Frostie-5", start = 5, manual = true }, ns.Session.current(), false)
      A.eq(ns.StatsStore.get("session", "gn"), 12345, "still the gold I carry right after the change")
      W:advance(1)
      local sent = statsSince(ns, W, mark)
      A.eq(#sent, 1)
      A.eq(sent[1].a_gn, "12345")
      A.eq(sent[1].s_gn, sent[1].a_gn, "the new session's first STATS has the gold too")
      A.eq(ns.Log.errors(10), {})
    end,

    statsreq_replies_at_most_once_a_minute = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      receive(W, "Frostie", "STATSREQ", {}, ns)
      W:advance(6)
      A.eq(#statsSince(ns, W, mark), 1, "first reply")
      receive(W, "Ginkan", "STATSREQ", {}, ns)
      W:advance(10)
      receive(W, "Frostie", "STATSREQ", {}, ns)
      W:advance(10)
      A.eq(#statsSince(ns, W, mark), 1, "inside the gap: the last reply already reached everyone")
      W:advance(41)
      receive(W, "Ginkan", "STATSREQ", {}, ns)
      W:advance(6)
      A.eq(#statsSince(ns, W, mark), 2, "after the gap: a second reply")
    end,

    friend_numbers_saved_and_replaced = function(ns, A, W)
      start(ns, W)
      W:advance(ns.Config.STATS_CHANGED_GAP) -- past the redraw gap of the session start
      local fired = 0
      ns.Bus.on("test", "STATS_CHANGED", function() fired = fired + 1 end)
      local S = "Frostie-1700000000"
      receive(W, "Frostie", "STATS", { sid = S, q = "1", s_dt = "3", a_dt = "9" }, ns)
      A.eq(fired, 1, "STATS_CHANGED after a friend's numbers")
      receive(W, "Frostie", "STATS", { sid = S, q = "1", a_jp = "4" }, ns)
      local rec = ns.db.stats.crew.Frostie
      A.eq(rec.s.dt, 3)
      A.eq(rec.a.jp, 4)
      A.eq(rec.a.dt, 9)
      A.eq(rec.sid, S)
      A.eq(rec.at, ns.wallclock())
      local st = ns.Stats.status()
      A.eq(st.lastHeard.name, "Frostie")
      A.eq(st.lastHeard.at, ns.wallclock())
      receive(W, "Frostie", "STATS", { sid = S, q = "2", a_dt = "10" }, ns)
      rec = ns.db.stats.crew.Frostie
      A.eq(rec.a, { dt = 10, jp = 4 }, "a new snapshot is laid over the saved numbers")
      A.eq(rec.s, { dt = 3 })
      -- off: numbers kept but marked
      receive(W, "Frostie", "STATS", { sid = S, q = "3", off = "1" }, ns)
      rec = ns.db.stats.crew.Frostie
      A.eq(rec.off, true)
      A.eq(rec.a, { dt = 10, jp = 4 }, "kept while off")
      receive(W, "Frostie", "STATS", { sid = S, q = "4", a_dt = "11" }, ns)
      A.eq(ns.db.stats.crew.Frostie.off, nil, "back on")
      A.eq(ns.db.stats.crew.Frostie.a, { dt = 11, jp = 4 }, "laid over: what a piece does not carry stays")
    end,

    entries_filter_session_and_off = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      ns.Stats.count("dt", 2)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", cl = "MAGE" }, ns)
      receive(W, "Frostie", "STATS", { sid = S, q = "1", s_dt = "3", a_dt = "9" }, ns)
      receive(W, "Ginkan", "STATS", { sid = "Ginkan-5", q = "1", s_jp = "7", a_jp = "70" }, ns)
      ns.db.stats.chars.Twizalt = { sid = "Twiz-1", s = { dt = 1 }, a = { dt = 4 } }
      ns.db.stats.crew.Twizalt = { sid = S, q = "1", s = { dt = 99 }, a = { dt = 99 }, at = 1 }

      local session = ns.StatsStore.entries("session", S)
      A.eq(names(session), { "Frostie", "Twiz" })
      A.eq(find(session, "Frostie").stats, { dt = 3 })
      local me = find(session, "Twiz")
      A.eq(me.mine, true)
      A.eq(me.class, "WARRIOR")
      A.eq(me.online, true)
      A.eq(me.stats.dt, 2)
      local frostie = find(session, "Frostie")
      A.eq(frostie.mine, false)
      A.eq(frostie.class, "MAGE")
      A.eq(frostie.online, true)
      A.eq(frostie.at, ns.wallclock())

      local all = ns.StatsStore.entries("all")
      A.eq(names(all), { "Frostie", "Ginkan", "Twiz", "Twizalt" })
      A.eq(find(all, "Frostie").stats, { dt = 9 })
      A.eq(find(all, "Ginkan").stats, { jp = 70 })
      A.eq(find(all, "Ginkan").class, nil)
      A.eq(find(all, "Ginkan").online, false)
      local alt = find(all, "Twizalt")
      A.eq(alt.mine, true)
      A.eq(alt.stats, { dt = 4 }, "my other character, not the crew record with the same name")
      A.eq(alt.class, nil)
      A.eq(alt.online, false)

      A.eq(ns.StatsStore.entries("session", nil), {}, "no session: nobody")

      receive(W, "Ginkan", "STATS", { sid = "Ginkan-5", q = "2", off = "1" }, ns)
      A.no(find(ns.StatsStore.entries("all"), "Ginkan"), "off: hidden")
      A.no(find(ns.StatsStore.entries("session", "Ginkan-5"), "Ginkan"))
    end,

    a_friends_new_session_keeps_their_old_numbers = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      receive(W, "Frostie", "STATS", { sid = S, q = "1", s_dt = "3", a_dt = "9" }, ns)
      receive(W, "Frostie", "STATS", { sid = "Frostie-9", q = "2", s_dt = "1", a_dt = "10" }, ns)
      receive(W, "Frostie", "STATS", { sid = "Frostie-9", q = "3", s_dt = "2", a_dt = "11" }, ns)
      local old = ns.StatsStore.entries("session", S)
      A.eq(names(old), { "Frostie", "Twiz" }, "still listed in the old session, once")
      A.eq(find(old, "Frostie").stats, { dt = 3 }, "with the old numbers")
      local new = ns.StatsStore.entries("session", "Frostie-9")
      A.eq(names(new), { "Frostie" })
      A.eq(find(new, "Frostie").stats, { dt = 2 })
      A.eq(find(ns.StatsStore.entries("all"), "Frostie").stats, { dt = 11 }, "all time: just the newest")
      A.eq(#ns.StatsStore.entries("all"), 2)
      -- broken saved numbers are cleaned
      ns.db.stats.crew.Frostie.prev.s = { dt = "x", jp = 4 }
      A.eq(find(ns.StatsStore.entries("session", S), "Frostie").stats, { jp = 4 })
    end,

    stats_from_broken_copy_is_tamed = function(ns, A, W)
      start(ns, W)
      local fired = 0
      ns.Bus.on("test", "STATS_CHANGED", function() fired = fired + 1 end)
      receive(W, "Frostie", "STATS", { q = "1", s_dt = "3" }, ns)
      A.eq(ns.db.stats.crew.Frostie, nil, "no sid: ignored")
      A.eq(fired, 0)
      receive(W, "Frostie", "STATS", { sid = "Frostie-1", q = "x", s_dt = "-4", a_st = "abc", a_jp = "1e999",
        s_zz = "5", a_dt = "nan" }, ns)
      local rec = ns.db.stats.crew.Frostie
      A.eq(rec.s, {})
      A.eq(rec.a, {})
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^STATS^", "CHANNEL", "Ginkan")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^STATS^sid", "CHANNEL", "Ginkan")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^STATSREQ^junk=%7", "CHANNEL", "Ginkan")
      -- broken saved data never reaches the board
      ns.db.stats.crew.Bad = { sid = "x", s = "nope", a = { dt = "7", jp = 2 } }
      ns.db.stats.crew[5] = "junk"
      local all = ns.StatsStore.entries("all")
      A.eq(find(all, "Bad").stats, { jp = 2 })
      A.eq(find(all, "Frostie").stats, {})
      A.eq(ns.StatsStore.entries("session", "x")[1].stats, {})
      W:advance(10)
      A.eq(ns.Log.errors(10), {})
    end,

    logout_sends_stats_directly = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      W:fire("PLAYER_LOGOUT")
      A.eq(#statsSince(ns, W, mark), 0, "nothing new: no send at logout")
      ns.Stats.count("jp", 1)
      mark = #W.sent
      W:fire("PLAYER_LOGOUT")
      local sent = statsSince(ns, W, mark)
      A.ok(#sent >= 1, "a STATS right away")
      A.eq(sent[1].a_jp, "1")
      A.eq(sent[1].sid, ns.Session.current().id)
      A.no(ns.StatsStore.dirty(), "marked as sent")
    end,

    a_piece_is_laid_over_the_stored_numbers = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      ns.Stats.count("dt", 300)
      ns.Stats.count("jp", 5000)
      for _, text in ipairs(pieces(ns, bigSnap(ns, S, "1731100000-1", 100))) do fireText(W, "Frostie", text) end
      local before = leadersOf(ns, S)
      A.ok(next(before) ~= nil, "the board has leaders")
      local newer = bigSnap(ns, S, "1731100300-2", 110)
      local texts = pieces(ns, newer)
      A.ok(#texts >= 3, "the snapshot travels in pieces (" .. #texts .. ")")
      fireText(W, "Frostie", texts[1])
      A.eq(leadersOf(ns, S), before, "one piece moves no crown")
      for i = 2, #texts do fireText(W, "Frostie", texts[i]) end
      local rec = ns.db.stats.crew.Frostie
      A.eq(rec.s, newer.s, "complete: the session numbers are the new snapshot")
      A.eq(rec.a, newer.a, "complete: the all-time numbers are the new snapshot")
      -- a new session starts the session view fresh; all time is still laid over
      local T = "Frostie-1731100400"
      receive(W, "Frostie", "STATS", { sid = T, q = "1731100400-3", s_dt = "1", a_dt = "2000" }, ns)
      rec = ns.db.stats.crew.Frostie
      A.eq(rec.s, { dt = 1 }, "new session: only its own numbers")
      A.eq(rec.a.dt, 2000)
      A.eq(rec.a.jp, newer.a.jp, "all time keeps what the piece did not carry")
      A.eq(rec.prev.s, newer.s, "the old session's numbers are kept for its board")
      A.eq(ns.Log.errors(10), {})
    end,

    a_lost_piece_sends_no_number_to_zero = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      for _, text in ipairs(pieces(ns, bigSnap(ns, S, "1731100000-1", 100))) do fireText(W, "Frostie", text) end
      local second = pieces(ns, bigSnap(ns, S, "1731100300-2", 110))
      A.ok(#second >= 3)
      for i, text in ipairs(second) do
        if i ~= 2 then fireText(W, "Frostie", text) end -- piece 2 is lost on the way
      end
      local rec = ns.db.stats.crew.Frostie
      local before = { s = ns.Util.copy(rec.s), a = ns.Util.copy(rec.a) }
      fireText(W, "Frostie", pieces(ns, bigSnap(ns, S, "1731100600-3", 120))[1]) -- the next snapshot starts
      rec = ns.db.stats.crew.Frostie
      for _, view in ipairs({ "s", "a" }) do
        for key, v in pairs(before[view]) do
          A.ok(type(rec[view][key]) == "number" and rec[view][key] >= v, view .. "_" .. key .. " kept, not zeroed")
        end
      end
    end,

    a_reset_reaches_friends_as_zeros = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      local function sendAs(name) -- my next snapshot, fired back in as if a friend sent it; returns its fields
        local mark = #W.sent
        ns.Stats.send()
        W:advance(5)
        local merged = {}
        for i = mark + 1, #W.sent do
          local msg = ns.Codec.decode(W.sent[i].text)
          if msg and msg.type == "STATS" then
            fireText(W, name, W.sent[i].text)
            for k, v in pairs(msg.fields) do merged[k] = v end
          end
        end
        return merged
      end
      ns.Stats.count("dt", 30)
      ns.Stats.count("jp", 4)
      sendAs("Frostie")
      A.eq(ns.db.stats.crew.Frostie.s.dt, 30)
      W.env.SlashCmdList.TWIZCREW("stats reset yes")
      local f = sendAs("Frostie")
      A.eq(f.s_dt, "0", "the cleared numbers go out as 0")
      A.eq(f.a_jp, "0")
      local rec = ns.db.stats.crew.Frostie
      A.eq(rec.s.dt, 0, "the friend shows the zeros")
      A.eq(rec.s.jp, 0)
      A.eq(rec.a.dt, 0)
      A.eq(rec.a.jp, 0)
      local corpse = ns.TrophyLogic.leaders(ns.StatsLogic.awards(ns.StatsStore.entries("session", S))).corpse
      A.no(corpse and corpse[1] == "Frostie", "0 deaths wins nothing")
      ns.Stats.count("jp", 2)
      f = sendAs("Frostie")
      A.eq(f.s_dt, "0", "every snapshot of this session still carries them")
      A.eq(f.s_jp, "2")
      ns.Session.newByHand()
      f = sendAs("Frostie")
      A.eq(f.s_dt, nil, "a new session: no more zeros")
      A.eq(f.a_dt, nil)
      A.eq(ns.Log.errors(10), {})
    end,

    an_older_snapshot_loses = function(ns, A, W)
      start(ns, W)
      local S = "Frostie-1731100000"
      receive(W, "Frostie", "STATS", { sid = S, q = "1731100300-2", s_dt = "8", a_dt = "20" }, ns)
      receive(W, "Frostie", "STATS", { sid = S, q = "1731100000-1", s_dt = "3", a_dt = "15" }, ns)
      local rec = ns.db.stats.crew.Frostie
      A.eq(rec.s, { dt = 8 }, "the late, older snapshot is ignored")
      A.eq(rec.a, { dt = 20 })
      A.eq(rec.q, "1731100300-2")
      -- the same second: the counter decides (as numbers, 12 after 3)
      receive(W, "Frostie", "STATS", { sid = S, q = "1731100300-12", s_dt = "9" }, ns)
      receive(W, "Frostie", "STATS", { sid = S, q = "1731100300-3", s_dt = "1" }, ns)
      A.eq(ns.db.stats.crew.Frostie.s.dt, 9)
      -- an older one from another session loses too
      receive(W, "Frostie", "STATS", { sid = "Frostie-1", q = "1731100200-1", s_dt = "50" }, ns)
      A.eq(ns.db.stats.crew.Frostie.sid, S)
      A.eq(ns.db.stats.crew.Frostie.s.dt, 9)
      -- only inside the window: after it, the "older" one is taken (her clock may have gone back)
      W:advance(ns.Config.STATS_OLDER_WINDOW + 1)
      receive(W, "Frostie", "STATS", { sid = S, q = "1731100000-1", s_dt = "4" }, ns)
      A.eq(ns.db.stats.crew.Frostie.s.dt, 4, "taken after the window")
      A.eq(ns.db.stats.crew.Frostie.q, "1731100000-1")
      -- a saved q far in the future blocks only inside the window
      ns.db.stats.crew.Ginkan = { sid = S, q = "99999999999-1", s = { dt = 1 }, a = {}, at = ns.wallclock() }
      receive(W, "Ginkan", "STATS", { sid = S, q = "1731100000-1", s_dt = "6" }, ns)
      A.eq(ns.db.stats.crew.Ginkan.s.dt, 1, "inside the window")
      W:advance(ns.Config.STATS_OLDER_WINDOW + 1)
      receive(W, "Ginkan", "STATS", { sid = S, q = "1731100000-2", s_dt = "7" }, ns)
      A.eq(ns.db.stats.crew.Ginkan.s.dt, 7, "a bad saved q does not block her for good")
      -- a saved record with no receive time never blocks
      ns.db.stats.crew.Lurabe = { sid = S, q = "99999999999-1", s = { dt = 1 }, a = {} }
      receive(W, "Lurabe", "STATS", { sid = S, q = "1731100000-1", s_dt = "8" }, ns)
      A.eq(ns.db.stats.crew.Lurabe.s.dt, 8)
    end,

    pieces_redraw_like_local_changes = function(ns, A, W)
      start(ns, W)
      W:advance(ns.Config.STATS_CHANGED_GAP + 1)
      local fired = 0
      ns.Bus.on("test", "STATS_CHANGED", function() fired = fired + 1 end)
      local S = ns.Session.current().id
      for i = 1, 20 do
        receive(W, "Frostie", "STATS", { sid = S, q = "1731100000-" .. i, s_dt = tostring(i) }, ns)
        W:advance(0.05)
      end
      W:advance(ns.Config.STATS_CHANGED_GAP + 1)
      A.ok(fired >= 1 and fired <= 2, "STATS_CHANGED fired " .. fired .. " times for 20 pieces")
      A.eq(find(ns.StatsStore.entries("session", S), "Frostie").stats, { dt = 20 }, "the last numbers are shown")
      -- also while my own counting is off (friends' numbers are still shown)
      ns.Modules.setEnabled("stats", false)
      W:advance(ns.Config.STATS_CHANGED_GAP + 1)
      fired = 0
      for i = 21, 30 do
        receive(W, "Frostie", "STATS", { sid = S, q = "1731100000-" .. i, s_dt = tostring(i) }, ns)
        W:advance(0.05)
      end
      W:advance(ns.Config.STATS_CHANGED_GAP + 1)
      A.eq(fired, 2, "one at once, one after the gap")
      A.eq(ns.Log.errors(10), {})
    end,

    big_snapshot_arrives_in_pieces = function(ns, A, W)
      start(ns, W)
      for i, key in ipairs(ns.StatsDefs.KEYS) do
        if key ~= "ld" then ns.Stats.count(key, 1000000 + i) end
      end
      local want = {}
      for _, key in ipairs(ns.StatsDefs.KEYS) do want[key] = math.floor(ns.StatsStore.get("all", key)) end
      local mark = #W.sent
      ns.Stats.send()
      W:advance(5)
      local texts = {}
      for i = mark + 1, #W.sent do texts[#texts + 1] = W.sent[i].text end
      A.ok(#texts > 1, "more than one piece")
      -- fired back in as if Frostie sent them: every piece is merged into one record
      for _, text in ipairs(texts) do W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", "Frostie") end
      local rec = ns.db.stats.crew.Frostie
      for _, key in ipairs(ns.StatsDefs.KEYS) do
        if key ~= "ld" then A.eq(rec.a[key], want[key], key) end
      end
    end,
  },
}
