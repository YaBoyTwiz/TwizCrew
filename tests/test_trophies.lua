-- Trophy case, streaks and stolen crowns (Hall of Shame part 2).

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function entry(name, stats) return { name = name, stats = stats } end

return {
  files = "toc",
  tests = {
    a_record_needs_two_people_and_thirty_minutes = function(ns, A)
      local L, S = ns.TrophyLogic, ns.StatsLogic
      local list = { entry("Twiz", { dt = 5, pt = 1900 }), entry("Lurabe", { dt = 2, pt = 600 }),
        entry("Fake (test)", { dt = 50, pt = 5000 }) }
      local r = L.record("Twiz-1000", list, S.awards(list), 1800)
      A.eq(r.sid, "Twiz-1000")
      A.eq(r.start, 1000)
      A.eq(r.people, { "Lurabe", "Twiz" }, "fakes never count")
      A.eq(r.winners.corpse, { "Twiz" })
      A.eq(L.record("Twiz-1000", { list[1] }, S.awards({ list[1] }), 1800), nil, "one person: no trophies")
      local short = { entry("Twiz", { dt = 5, pt = 100 }), entry("Lurabe", { dt = 2, pt = 600 }) }
      A.eq(L.record("Twiz-1000", short, S.awards(short), 1800), nil, "nobody played 30 minutes")
    end,
    summary_counts_and_streaks = function(ns, A)
      local L = ns.TrophyLogic
      local recs = {
        { sid = "a", start = 1, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz" } } },
        { sid = "b", start = 2, people = { "Lurabe" }, winners = { corpse = { "Lurabe" } } }, -- Twiz missed it
        { sid = "c", start = 3, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz" }, bunny = { "Lurabe" } } },
        { sid = "d", start = 4, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz", "Lurabe" } } },
      }
      local s = L.summary(recs)
      A.eq(s.Twiz.total, 3)
      A.eq(s.Twiz.counts.corpse, 3)
      A.eq(s.Twiz.streaks.corpse, 3, "a missed night doesn't break it")
      A.eq(s.Lurabe.counts, { corpse = 2, bunny = 1 })
      A.eq(s.Lurabe.streaks.corpse, 1, "won d, not c")
      A.eq(s.Lurabe.streaks.bunny, nil, "not won in their newest session")
    end,
    records_travel_in_pieces = function(ns, A)
      local L = ns.TrophyLogic
      local r = { sid = "Twiz-1000", start = 1000, people = { "Lurabe", "Twiz" },
        winners = { corpse = { "Twiz" }, bunny = { "Lurabe", "Twiz" } } }
      local f = L.toWire(r)
      A.eq(f.s, "Twiz-1000")
      A.eq(f.k, "2")
      A.eq(f.w_bunny, "Lurabe,Twiz")
      A.eq(L.fromPieces(f), r)
      local part = { s = f.s, t = f.t, p = f.p, k = f.k, w_corpse = f.w_corpse }
      A.eq(L.fromPieces(part), nil, "one award field still missing")
      A.eq(L.fromPieces({ s = "", k = "0", p = "" }), nil)
    end,
    a_session_that_ends_hands_out_trophies = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      W:advance(1900) -- I play 31 minutes
      ns.Stats.count("dt", 3)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "1", s_pt = "1900" })
      A.eq(next(ns.Trophies.records()), nil, "nothing until the session ends")
      ns.Session.newByHand()
      local r = ns.Trophies.records()[sid]
      A.ok(r, "recorded when the session ended")
      A.eq(r.winners.corpse, { "Twiz" })
      A.eq(r.people, { "Lurabe", "Twiz" })
      A.eq(ns.Trophies.summary().Twiz.counts.corpse, 1)
      A.eq(ns.Trophies.summary().Twiz.total, 4, "two people: Twiz wins four awards")
      A.eq(ns.Trophies.lineFor("Twiz"), "4 trophies", "no streak line for single wins")
      A.eq(ns.Trophies.lineFor("Nobody"), nil)
      A.eq(ns.Log.errors(10), {})
    end,
    a_short_session_hands_out_nothing = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      ns.Stats.count("dt", 3)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "1", s_pt = "60" })
      ns.Session.newByHand()
      A.eq(ns.Trophies.records()[sid], nil)
    end,
    a_friend_who_missed_it_gets_the_record = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local r = { sid = "Lurabe-500", start = 500, people = { "Lurabe", "Twiz" }, winners = { bunny = { "Twiz" } } }
      local mark = #W.sent
      receive(W, ns, "Lurabe", "TRD", { r = "Lurabe-500" })
      W:advance(3) -- the queue sends it
      local asked
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "TRQ" then asked = msg.fields.s end
      end
      A.eq(asked, "Lurabe-500", "we ask for the one we don't have")
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire(r))
      A.eq(ns.Trophies.records()["Lurabe-500"], r)
      -- asked by someone else: we answer with our copy
      mark = #W.sent
      receive(W, ns, "Lurabe", "TRQ", { s = "Lurabe-500" })
      W:advance(3)
      local sentRecord = false
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "TRP" and msg.fields.s == "Lurabe-500" then sentRecord = true end
      end
      A.ok(sentRecord)
      -- a second, different record for the same session is ignored
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire({ sid = "Lurabe-500", start = 500,
        people = { "Lurabe", "Twiz" }, winners = { bunny = { "Lurabe" } } }))
      A.eq(ns.Trophies.records()["Lurabe-500"].winners.bunny, { "Twiz" }, "the first one is kept")
    end,
    the_summary_is_cached_until_a_record_is_added = function(ns, A, W)
      boot(W)
      local recs = ns.Trophies.records()
      recs.a = { sid = "a", start = 1, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Twiz" } } }
      A.eq(ns.Trophies.lineFor("Twiz"), "1 trophy")
      recs.b = { sid = "b", start = 2, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Twiz" } } }
      ns.Trophies.sessionEnded("zzz") -- nothing to record; also must not break
      A.eq(ns.Trophies.lineFor("Twiz"), "1 trophy", "cached until a record is added")
    end,
  },
}
