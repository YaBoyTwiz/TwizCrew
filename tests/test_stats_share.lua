-- Stats sharing (stats Task 6): STATS / STATSREQ in and out, the "off" announcement, friends' saved numbers and
-- StatsStore.entries (what the Hall of Shame and the awards show read). Full TOC boot.

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
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
      A.eq(rec.a, { dt = 10 })
      A.eq(rec.s, {})
      -- off: numbers kept but marked
      receive(W, "Frostie", "STATS", { sid = S, q = "3", off = "1" }, ns)
      rec = ns.db.stats.crew.Frostie
      A.eq(rec.off, true)
      A.eq(rec.a, { dt = 10 }, "kept while off")
      receive(W, "Frostie", "STATS", { sid = S, q = "4", a_dt = "11" }, ns)
      A.eq(ns.db.stats.crew.Frostie.off, nil, "back on")
      A.eq(ns.db.stats.crew.Frostie.a, { dt = 11 })
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
