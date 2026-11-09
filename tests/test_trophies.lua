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
  },
}
