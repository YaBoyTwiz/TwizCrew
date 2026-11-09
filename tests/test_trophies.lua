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

-- Counts stolen crown pop-ups (Popups.notice calls) and keeps the last one.
local function watchNotices(ns)
  local seen = { n = 0 }
  local real = ns.Popups.notice
  ns.Popups.notice = function(icon, title, sub, onClick, seconds)
    seen.n, seen.title, seen.sub, seen.onClick = seen.n + 1, title, sub, onClick
    return real(icon, title, sub, onClick, seconds)
  end
  return seen
end

-- Booted, past the first 15 minutes, Lurabe 2 deaths and 50 jumps, me 3 deaths and 10 jumps: corpse is mine,
-- bunny is hers. Returns the session id.
local function oldSession(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
  local sid = ns.Session.current().id
  receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "2", s_jp = "50" })
  ns.Stats.count("dt", 3)
  ns.Stats.count("jp", 10)
  W:advance(901)
  ns.Steals.check() -- baseline
  return sid
end

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
    a_friend_starting_a_new_session_stays_in_the_old_record = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      for _, name in ipairs({ "Lurabe", "Ginkan" }) do
        receive(W, ns, name, "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
          lk = "", ins = "0" })
      end
      local sid = ns.Session.current().id
      W:advance(1900)
      ns.Stats.count("dt", 3)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "5", s_pt = "1900" })
      receive(W, ns, "Ginkan", "STATS", { sid = sid, q = "1", s_dt = "1", s_pt = "1900" })
      local newId = "Lurabe-" .. (ns.wallclock() + 5)
      -- Lurabe pressed "new": her STATS (new sid, numbers wiped) comes first, her UPDATE after a short delay
      receive(W, ns, "Lurabe", "STATS", { sid = newId, q = "2", s_pt = "0" })
      receive(W, ns, "Lurabe", "STATS", { sid = newId, q = "3", s_pt = "1" }) -- another one before the UPDATE
      A.eq(next(ns.Trophies.records()), nil, "nothing recorded yet")
      receive(W, ns, "Lurabe", "UPDATE", { sid = newId, sst = tostring(ns.wallclock() + 5) .. "m" })
      A.eq(ns.Session.current().id, newId, "my session switched")
      local r = ns.Trophies.records()[sid]
      A.ok(r, "the old session was recorded")
      A.eq(r and r.people, { "Ginkan", "Lurabe", "Twiz" })
      A.eq(r and r.winners.corpse, { "Lurabe" }, "Lurabe keeps her crown")
      A.eq(ns.Log.errors(10), {})
    end,
    a_record_with_more_people_replaces_mine = function(ns, A, W)
      boot(W)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local fired = 0
      ns.Bus.on("test", "TROPHIES_CHANGED", function() fired = fired + 1 end)
      local small = { sid = "Twiz-500", start = 500, people = { "Ginkan", "Twiz" }, winners = { corpse = { "Twiz" } } }
      ns.Trophies.records()["Twiz-500"] = small
      A.eq(ns.Trophies.lineFor("Twiz"), "1 trophy")
      -- same number of people: mine stays
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire({ sid = "Twiz-500", start = 500,
        people = { "Lurabe", "Twiz" }, winners = { corpse = { "Lurabe" } } }))
      A.eq(ns.Trophies.records()["Twiz-500"], small, "a tie keeps mine")
      A.eq(fired, 0)
      -- more people: theirs replaces mine
      local big = { sid = "Twiz-500", start = 500, people = { "Ginkan", "Lurabe", "Twiz" },
        winners = { corpse = { "Lurabe" } } }
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire(big))
      A.eq(ns.Trophies.records()["Twiz-500"], big, "the fuller record wins")
      A.eq(fired, 1)
      A.eq(ns.Trophies.lineFor("Twiz"), nil, "the summary was rebuilt")
      A.eq(ns.Trophies.lineFor("Lurabe"), "1 trophy")
      -- fewer people: mine stays
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire(small))
      A.eq(ns.Trophies.records()["Twiz-500"], big, "fewer people: ignored")
      A.eq(fired, 1)
    end,
    the_digest_stays_short = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local recs = ns.Trophies.records()
      for i = 1, 12 do
        local sid = string.rep("Averyveryverylongcharactername", 1) .. "-" .. (1000000000 + i)
        recs[sid] = { sid = sid, start = 1000000000 + i, people = { "Lurabe", "Twiz" }, winners = {} }
      end
      local mark = #W.sent
      ns.Trophies.sendDigest()
      W:advance(3)
      local r
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "TRD" then r = msg.fields.r end
      end
      A.ok(r, "a digest was sent")
      A.ok(#r <= 200, "at most 200 characters, got " .. #(r or ""))
      A.ok(r:find("Averyveryverylongcharactername-1000000012", 1, true) == 1, "newest first")
      A.no(r:find("1000000001", 1, true), "the oldest are dropped")
      for sid in r:gmatch("[^,]+") do A.ok(recs[sid], "whole ids only: " .. sid) end
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
    the_crew_tooltip_shows_trophies = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local t = ns.db.stats.trophies or {}
      ns.db.stats.trophies = t
      t["a-1"] = { sid = "a-1", start = 1, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Lurabe" } } }
      t["a-2"] = { sid = "a-2", start = 2, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Lurabe" } } }
      ns.Bus.fire("TROPHIES_CHANGED", "a-2")
      W:advance(1)
      local tip
      for _, m in ipairs(ns.Panel.models()) do if m.name == "Lurabe" then tip = m.tip end end
      A.contains(table.concat(tip or {}, "\n"), "2 trophies · Professional Corpse streak x2")
    end,
    unknown_awards_never_count = function(ns, A)
      local L = ns.TrophyLogic
      local recs = {
        { sid = "a", start = 1, people = { "Twiz", "Lurabe" }, winners = { corpse = { "Twiz" }, zzfuture = { "Twiz" } } },
        { sid = "b", start = 2, people = { "Twiz", "Lurabe" }, winners = { zzfuture = { "Twiz", "Lurabe" } } },
      }
      local s = L.summary(recs)
      A.eq(s.Twiz.total, 1, "only the award this copy knows")
      A.eq(s.Twiz.counts, { corpse = 1 })
      A.eq(s.Twiz.streaks, {}, "corpse not won in the newest session; the unknown one never streaks")
      A.eq(s.Lurabe, nil, "nothing known won")
    end,
    a_record_needs_its_start = function(ns, A)
      local L = ns.TrophyLogic
      local f = L.toWire({ sid = "Twiz-1000", start = 1000, people = { "Lurabe", "Twiz" }, winners = {} })
      f.t = nil
      A.eq(L.fromPieces(f), nil, "no t yet: incomplete")
    end,
    late_records_travel_marked = function(ns, A)
      local L = ns.TrophyLogic
      local r = { sid = "Twiz-1000", start = 1000, people = { "Lurabe", "Twiz" }, winners = {}, late = true }
      local f = L.toWire(r)
      A.eq(f.l, "1")
      A.eq(L.fromPieces(f), r)
      r.late = nil
      A.eq(L.toWire(r).l, nil, "a full record has no l")
      A.eq(L.fromPieces(L.toWire(r)).late, nil)
    end,
    a_full_record_replaces_a_late_one = function(ns, A, W)
      boot(W)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local fired = 0
      ns.Bus.on("test", "TROPHIES_CHANGED", function() fired = fired + 1 end)
      local late = { sid = "Twiz-500", start = 500, people = { "Ginkan", "Lurabe", "Twiz" },
        winners = { corpse = { "Twiz" } }, late = true }
      ns.Trophies.records()["Twiz-500"] = late
      A.eq(ns.Trophies.lineFor("Twiz"), "1 trophy")
      -- a full record replaces a late one, even with fewer people
      local full = { sid = "Twiz-500", start = 500, people = { "Lurabe", "Twiz" }, winners = { corpse = { "Lurabe" } } }
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire(full))
      A.eq(ns.Trophies.records()["Twiz-500"], full, "full beats late")
      A.eq(fired, 1)
      A.eq(ns.Trophies.lineFor("Twiz"), nil, "the summary was rebuilt")
      -- a late one never replaces a full one, even with more people
      receive(W, ns, "Lurabe", "TRP", ns.TrophyLogic.toWire({ sid = "Twiz-500", start = 500,
        people = { "Ginkan", "Lurabe", "Twiz" }, winners = { corpse = { "Twiz" } }, late = true }))
      A.eq(ns.Trophies.records()["Twiz-500"], full, "late never beats full")
      A.eq(fired, 1)
    end,
    the_digest_asks_for_a_session_i_only_have_late = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      for _, name in ipairs({ "Lurabe", "Ginkan" }) do
        receive(W, ns, name, "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
          lk = "", ins = "0" })
      end
      local recs = ns.Trophies.records()
      recs["Lurabe-500"] = { sid = "Lurabe-500", start = 500, people = { "Lurabe", "Twiz" }, winners = {}, late = true }
      recs["Lurabe-400"] = { sid = "Lurabe-400", start = 400, people = { "Lurabe", "Twiz" }, winners = {} }
      local function asks(fn)
        local mark = #W.sent
        fn()
        W:advance(3)
        local out = {}
        for i = mark + 1, #W.sent do
          local msg = ns.Codec.decode(W.sent[i].text)
          if msg and msg.type == "TRQ" then out[#out + 1] = msg.fields.s end
        end
        return out
      end
      -- a friend whose copy is late too: no point asking
      A.eq(asks(function() receive(W, ns, "Ginkan", "TRD", { r = "Lurabe-500,Lurabe-400", l = "Lurabe-500" }) end), {})
      A.eq(asks(function() receive(W, ns, "Lurabe", "TRD", { r = "Lurabe-500,Lurabe-400" }) end), { "Lurabe-500" },
        "late: asked; full: not")
      A.eq(asks(function() receive(W, ns, "Lurabe", "TRD", { r = "Lurabe-500,Lurabe-400" }) end), {}, "ask gap")
      -- my digest says which of mine are late
      local mark = #W.sent
      ns.Trophies.sendDigest()
      W:advance(3)
      local l
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "TRD" then l = msg.fields.l end
      end
      A.eq(l, "Lurabe-500")
    end,
    the_digest_asks_for_three_at_a_time = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      receive(W, ns, "Lurabe", "STATE", { ver = "0.1.22", cl = "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
        lk = "", ins = "0" })
      local digest = { r = "Lurabe-5,Lurabe-4,Lurabe-3,Lurabe-2,Lurabe-1" }
      local function asks()
        local mark = #W.sent
        receive(W, ns, "Lurabe", "TRD", digest)
        W:advance(3)
        local out = {}
        for i = mark + 1, #W.sent do
          local msg = ns.Codec.decode(W.sent[i].text)
          if msg and msg.type == "TRQ" then out[#out + 1] = msg.fields.s end
        end
        return out
      end
      A.eq(asks(), { "Lurabe-5", "Lurabe-4", "Lurabe-3" }, "the newest three")
      A.eq(asks(), { "Lurabe-2", "Lurabe-1" }, "the next digest asks for the rest")
    end,
    a_session_that_ended_while_i_was_away_is_recorded_late = function(ns, A, W)
      W:fire("ADDON_LOADED", "TwizCrew")
      local wall = ns.wallclock()
      local old = "Twiz-" .. (wall - 9000)
      ns.db.stats = ns.db.stats or {}
      ns.db.stats.session = { id = old, start = wall - 9000, manual = false,
        lastActive = wall - ns.Config.SESSION_RESUME - 600 }
      ns.db.stats.chars = { Twiz = { sid = old, s = { dt = 3, pt = 1900 }, a = { dt = 3, pt = 1900 } } }
      ns.db.stats.crew = {
        Lurabe = { sid = old, q = "1", s = { dt = 1, pt = 1900 }, a = { dt = 1, pt = 1900 }, at = wall - 2000 },
        Ginkan = { sid = old, q = "1", s = { dt = 9, pt = 1900 }, a = { dt = 9, pt = 1900 }, at = wall - 2000 },
      }
      W:fire("PLAYER_LOGIN")
      W:fire("PLAYER_ENTERING_WORLD")
      W:advance(5)
      -- Ginkan is already in a new session: his first STATS (new sid) arrives before the decision
      receive(W, ns, "Ginkan", "STATS", { sid = "Ginkan-" .. wall, q = "2", s_pt = "1" })
      A.eq(ns.Trophies.records()[old], nil, "nothing before the decision")
      W:advance(ns.Config.SESSION_DECIDE_AFTER)
      A.ok(ns.Session.current().id ~= old, "a new session")
      local r = ns.Trophies.records()[old]
      A.ok(r, "the old session was recorded at login")
      A.eq(r and r.people, { "Ginkan", "Lurabe", "Twiz" }, "the early STATS keeps Ginkan in it")
      A.eq(r and r.winners.corpse, { "Ginkan" })
      A.eq(r and r.late, true, "noticed at login: late")
      A.eq(ns.StatsStore.get("session", "dt"), 0, "then my session numbers were wiped")
      A.eq(ns.Log.errors(10), {})
    end,
    a_kept_session_switch_from_another_sid_still_records = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      W:advance(1900)
      ns.Stats.count("dt", 3)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "1", s_pt = "1900" })
      -- "keep" from a session my numbers are not from: they are wiped, so trophies come first
      ns.Bus.fire("SESSION_CHANGED", { id = "Ginkan-1", start = 1, manual = false },
        { id = "Other-2", start = 2, manual = false }, true)
      A.ok(ns.Trophies.records()[sid], "recorded before the wipe")
      A.eq(ns.StatsStore.get("session", "dt"), 0)
    end,
    steals_need_new_leaders_who_share_nobody = function(ns, A)
      local L, S = ns.TrophyLogic, ns.StatsLogic
      local before = { entry("Twiz", { dt = 7 }), entry("Lurabe", { dt = 8 }) }
      local old = L.leaders(S.awards(before))
      A.eq(old.corpse, { "Lurabe" })
      local after = { entry("Twiz", { dt = 9 }), entry("Lurabe", { dt = 8 }) }
      local list = S.awards(after)
      local st = L.steals(old, list, function(def, name) return name == "Twiz" and "9 deaths" or "8 deaths" end)
      A.eq(#st, 1)
      A.eq(st[1].def.id, "corpse")
      A.eq(st[1].thieves, { "Twiz" })
      A.eq(st[1].victims, { "Lurabe" })
      A.eq(st[1].thiefText, "9 deaths")
      A.eq(st[1].victimText, "8 deaths")
      local tie = { entry("Twiz", { dt = 8 }), entry("Lurabe", { dt = 8 }) }
      A.eq(#L.steals(old, S.awards(tie), function() return "" end), 0, "a tie is not a steal")
      A.eq(#L.steals({}, list, function() return "" end), 0, "nobody held it before")
    end,
    stolen_crown_pop_ups = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
      local sid = ns.Session.current().id
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "1", s_dt = "2" })
      ns.Steals.check()
      ns.Stats.count("dt", 3) -- I take Professional Corpse, but the session is young
      ns.Steals.check()
      ns.Steals.flush()
      A.eq(ns.Steals.lastShown(), nil, "not in the first 15 minutes")
      W:advance(901)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "2", s_dt = "5" })
      ns.Steals.check()
      ns.Steals.flush()
      A.eq(ns.Steals.lastShown(), "Lurabe just stole Professional Corpse from Twiz!")
      -- two at once inside a minute: one pop-up for both
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "3", s_dt = "5", s_jp = "50" })
      ns.Stats.count("jp", 60)
      ns.Stats.count("dt", 4) -- 7 deaths: back to me
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.contains(ns.Steals.lastShown(), "crowns changed hands")
      -- switched off
      local seen = watchNotices(ns)
      ns.Modules.set("roasts", "stealPopups", false)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "4", s_dt = "20", s_jp = "50" })
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 0, "nothing new while off")
      A.eq(ns.Log.errors(10), {})
    end,
    turning_stats_off_steals_nothing = function(ns, A, W)
      local sid = oldSession(ns, W)
      local seen = watchNotices(ns)
      ns.Modules.setEnabled("stats", false) -- I leave the board: corpse "passes" to Lurabe
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 0, "my stats off: no steal")
      ns.Modules.setEnabled("stats", true) -- back: corpse is mine again
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 0, "back on: a silent baseline, not stealing back")
      -- a friend who turns stats off: her bunny "passes" to me, then back to her
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "2", off = "1" })
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 0, "her stats off: no steal")
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "3", s_dt = "2", s_jp = "50" })
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 0, "her stats back on: no steal")
      -- still works after all that
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "4", s_dt = "9", s_jp = "50" })
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 1)
      A.eq(seen.title, "Lurabe just stole Professional Corpse from Twiz!")
      A.eq(ns.Log.errors(10), {})
    end,
    steals_are_merged_per_award = function(ns, A, W)
      local sid = oldSession(ns, W)
      local seen = watchNotices(ns)
      -- stolen and taken back inside the minute: undone, nothing shown
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "2", s_dt = "5", s_jp = "50" })
      ns.Stats.count("dt", 3) -- 6
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 0, "two flips: undone")
      -- a steal that sticks: shown once
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "3", s_dt = "8", s_jp = "50" })
      ns.Steals.check()
      ns.Steals.flush()
      A.eq(seen.n, 1)
      A.eq(seen.title, "Lurabe just stole Professional Corpse from Twiz!")
      -- three flips (me, her, me): one award, shown once, from the first victim
      W:advance(61)
      ns.Stats.count("dt", 3) -- 9
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "4", s_dt = "10", s_jp = "50" })
      ns.Stats.count("dt", 2) -- 11
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 2)
      A.eq(seen.title, "Twiz just stole Professional Corpse from Lurabe!")
      A.eq(seen.sub, "(11 deaths vs 10 deaths)  -  click to see")
      -- two different awards: one pop-up, each listed once
      W:advance(61)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "5", s_dt = "12", s_jp = "50" }) -- corpse is hers
      ns.Stats.count("jp", 41) -- 51: bunny is mine
      ns.Stats.count("dt", 2) -- 13: corpse back to me...
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "6", s_dt = "14", s_jp = "50" }) -- ...and hers again
      ns.Steals.check()
      W:advance(61)
      ns.Steals.flush()
      A.eq(seen.n, 3)
      A.eq(seen.title, "2 crowns changed hands")
      A.eq(seen.sub, "Professional Corpse: Lurabe, Bunny Hopper: Twiz")
      A.eq(ns.Log.errors(10), {})
    end,
    rates_and_right_now_awards_are_never_stolen = function(ns, A)
      local L, S = ns.TrophyLogic, ns.StatsLogic
      local before = { entry("Twiz", { gn = 100, pt = 3600, st = 1000, xt = 3600, xg = 100, mt = 5000 }),
        entry("Lurabe", { gn = 200, pt = 3600, st = 2000, xt = 3600, xg = 200, mt = 2000 }) }
      local after = { entry("Twiz", { gn = 300, pt = 3600, st = 3000, xt = 3600, xg = 300, mt = 1000 }),
        entry("Lurabe", { gn = 200, pt = 3600, st = 2000, xt = 3600, xg = 200, mt = 2000 }) }
      local old, list = L.leaders(S.awards(before)), S.awards(after)
      local now = L.leaders(list)
      for _, id in ipairs({ "pauper", "couch", "snail", "neverwalks" }) do
        A.eq(old[id], { "Twiz" }, id .. " was mine")
        A.eq(now[id], { "Lurabe" }, id .. " is hers now")
      end
      local ids = {}
      for _, s in ipairs(L.steals(old, list, function() return "" end)) do ids[#ids + 1] = s.def.id end
      A.eq(ids, { "marathon" }, "only Marathon Runner was taken by doing something")
    end,
    clicking_a_steal_opens_this_sessions_board = function(ns, A, W)
      local sid = oldSession(ns, W)
      local seen = watchNotices(ns)
      ns.Commands.setPanel(false, true)
      ns.Board.setView("all")
      ns.Board.setTab("lazy")
      W:advance(1)
      A.eq(ns.Panel.isShown(), false)
      receive(W, ns, "Lurabe", "STATS", { sid = sid, q = "2", s_dt = "9", s_jp = "50" })
      ns.Steals.check()
      ns.Steals.flush()
      A.eq(seen.n, 1)
      seen.onClick()
      W:advance(1)
      A.eq(ns.Panel.isShown(), true)
      A.eq(ns.Panel.tab(), "shame")
      A.eq(ns.Board.tab(), "deaths")
      A.eq(ns.Board.view(), "session")
      -- stats off: the click does nothing
      ns.Commands.setPanel(false, true)
      ns.Board.setView("all")
      ns.Modules.setEnabled("stats", false)
      seen.onClick()
      W:advance(1)
      A.eq(ns.Panel.isShown(), false)
      A.eq(ns.Board.view(), "all")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
