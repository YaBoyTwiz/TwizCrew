return {
  files = { "Core/Init.lua", "Core/Util.lua", "Crew/Roster.lua", "Crew/SelfState.lua" },
  tests = {
    apply_new_member = function(ns, A)
      local saved = {}
      local r = ns.Roster.new(saved)
      local m, ch, ev = r:apply("Ginkan", { cl = "WARRIOR", lv = "14", zn = "Elwynn Forest", tg = "" }, 10, 1000)
      A.eq(m.level, 14); A.ok(m.online); A.eq(ev, { "new", "online" }); A.eq(saved.Ginkan.level, 14)
      A.eq(m.class, "WARRIOR"); A.eq(m.zone, "Elwynn Forest"); A.eq(m.tags, {}); A.ok(ch.level)
      A.eq(saved.Ginkan.lastSeen, 1000); A.eq(m.lastHeard, 10)
    end,
    apply_reports_only_changes = function(ns, A)
      local r = ns.Roster.new({})
      r:apply("Ginkan", { cl = "WARRIOR", lv = "14", zn = "Elwynn Forest", tg = "" }, 10, 1000)
      local _, ch, ev = r:apply("Ginkan", { cl = "WARRIOR", lv = "14", zn = "Westfall", tg = "" }, 11, 1001)
      A.eq(ch, { zone = true }); A.eq(ev, {})
    end,
    wire_mapping = function(ns, A)
      local r = ns.Roster.new({})
      local m = r:apply("Zed", { xp = "42", ins = "1", lk = "", st = "hi", ver = "0.1.0", sz = "Inn", tg = "DEAD,AFK", lk2 = "x" }, 1, 1)
      A.eq(m.xp, 42); A.eq(m.inInstance, true); A.eq(m.layerKey, nil); A.eq(m.status, "hi")
      A.eq(m.version, "0.1.0"); A.eq(m.subzone, "Inn"); A.eq(m.tags, { DEAD = true, AFK = true })
      r:apply("Zed", { ins = "0", lk = "123" }, 2, 2)
      A.eq(m.inInstance, false); A.eq(m.layerKey, "123")
    end,
    xp_numbers_are_kept = function(ns, A)
      local r = ns.Roster.new({})
      local m, ch = r:apply("Zed", { lv = "12", xc = "637", xm = "1000", rx = "500" }, 1, 1)
      A.eq({ m.xpCur, m.xpMax, m.rested }, { 637, 1000, 500 })
      A.ok(ch.xpCur and ch.xpMax and ch.rested)
      r:apply("Zed", { xc = "", xm = "abc" }, 2, 2)
      A.eq({ m.xpCur, m.xpMax }, { 637, 1000 }, "junk keeps the old numbers")
      A.eq(r.saved.Zed.xpCur, nil, "XP numbers are not saved")
    end,
    level_up_only_when_seen_at_the_level_before = function(ns, A)
      local r = ns.Roster.new({})
      local _, _, ev = r:apply("Ginkan", { lv = "12" }, 1, 1)
      A.eq(ev, { "new", "online" })
      _, _, ev = r:apply("Ginkan", { lv = "13" }, 2, 2)
      A.eq(ev, { "levelup" })
      _, _, ev = r:apply("Ginkan", { lv = "13" }, 3, 3)
      A.eq(ev, {}, "same level again")
      _, _, ev = r:apply("Ginkan", { lv = "15" }, 4, 4)
      A.eq(ev, {}, "two levels at once is not a ding")
      _, _, ev = r:apply("Ginkan", { lv = "14" }, 5, 5)
      A.eq(ev, {}, "going down is not a ding")
      _, _, ev = r:apply("Ginkan", { zn = "Westfall" }, 6, 6)
      _, _, ev = r:apply("Ginkan", { lv = "15" }, 7, 7)
      A.eq(ev, { "levelup" })
    end,
    no_level_up_from_saved_data_or_after_offline = function(ns, A)
      local r = ns.Roster.new({ Ginkan = { name = "Ginkan", level = 12 } })
      local _, _, ev = r:apply("Ginkan", { lv = "13" }, 1, 1)
      A.eq(ev, { "online" }, "first message after our login")
      -- offline for a while, back one level up
      r:tick(1 + ns.Config.OFFLINE_AFTER + 1)
      _, _, ev = r:apply("Ginkan", { lv = "14" }, 400, 400)
      A.eq(ev, { "online" })
      -- logged out with a goodbye
      r:gone("Ginkan")
      _, _, ev = r:apply("Ginkan", { lv = "15" }, 500, 500)
      A.eq(ev, { "online" })
      -- a /reload (HELLO): the level from before it does not count, the next one does
      r:clearSession("Ginkan")
      _, _, ev = r:apply("Ginkan", { ver = "0.1.0" }, 501, 501)
      A.eq(ev, {})
      _, _, ev = r:apply("Ginkan", { lv = "16" }, 502, 502)
      A.eq(ev, {}, "first state after a HELLO")
      _, _, ev = r:apply("Ginkan", { lv = "17" }, 503, 503)
      A.eq(ev, { "levelup" })
    end,
    xp_pace_counts_gains_and_level_ups = function(ns, A)
      local r = ns.Roster.new({})
      local m = r:apply("Zed", { lv = "10", xm = "1000", xc = "100" }, 0, 0)
      A.eq({ m.xpTrack.earned, m.xpTrack.active, m.xpTrack.gains, m.xpTrack.lastGain }, { 0, 0, 0, 0 })
      r:apply("Zed", { xc = "300" }, 60, 60)
      r:apply("Zed", { tg = "COMBAT" }, 70, 70)  -- no xc: not a sample
      r:apply("Zed", { xc = "300" }, 90, 90)     -- no gain: nothing counted
      r:apply("Zed", { xc = "900" }, 120, 120)
      A.eq({ m.xpTrack.earned, m.xpTrack.active, m.xpTrack.gains, m.xpTrack.lastGain }, { 800, 120, 2, 120 })
      -- a level-up, split over two pieces: level and need first, then the XP
      r:apply("Zed", { lv = "11", xm = "1200" }, 180, 180)
      r:apply("Zed", { xc = "50" }, 180, 180)
      A.eq({ m.xpTrack.earned, m.xpTrack.gains }, { 950, 3 }, "100 left of level 10 plus 50")
      -- a long break counts as at most XP_IDLE_AFTER of playing time
      r:apply("Zed", { xc = "250" }, 180 + 5000, 5180)
      A.eq(m.xpTrack.active, 180 + ns.Config.XP_IDLE_AFTER)
    end,
    xp_pace_starts_over_when_odd = function(ns, A)
      local r = ns.Roster.new({})
      local m = r:apply("Zed", { lv = "10", xm = "1000", xc = "100" }, 0, 0)
      r:apply("Zed", { xc = "300" }, 60, 60)
      r:apply("Zed", { xc = "200" }, 90, 90)       -- XP went down
      A.eq({ m.xpTrack.earned, m.xpTrack.gains, m.xpTrack.first }, { 0, 0, 90 })
      r:apply("Zed", { xc = "400" }, 120, 120)
      r:apply("Zed", { lv = "12", xm = "1400", xc = "10" }, 150, 150) -- two levels at once
      A.eq({ m.xpTrack.earned, m.xpTrack.first }, { 0, 150 })
      r:apply("Zed", { xc = "5000" }, 160, 160)    -- more than the level needs: ignored
      A.eq({ m.xpTrack.earned, m.xpTrack.xc }, { 0, 10 })
      r:apply("Zed", { lv = "60", xm = "0", xc = "0" }, 170, 170)   -- max level: nothing to track
      A.eq(m.xpTrack, nil)
      r:apply("Zed", { lv = "59", xm = "1000", xc = "10" }, 180, 180)
      A.ok(m.xpTrack)
      r:clearSession("Zed")
      A.eq(m.xpTrack, nil, "a new play session starts over")
    end,
    apply_tolerates_junk = function(ns, A)
      local r = ns.Roster.new({})
      local m = r:apply("Zed", { lv = "10", xp = "5" }, 1, 1)
      r:apply("Zed", { lv = "abc", xp = "", cl = 5, zn = {} }, 2, 2)
      A.eq(m.level, 10); A.eq(m.xp, 5)
      local m2 = r:apply("New", { lv = "x" }, 1, 1)
      A.eq(m2.level, nil)
      A.ok(r:apply("Odd", nil, 1, 1))
    end,
    died_only_on_transition = function(ns, A)
      local r = ns.Roster.new({})
      r:apply("Ginkan", { tg = "" }, 1, 1)
      local _, _, ev = r:apply("Ginkan", { tg = "DEAD" }, 2, 2)
      A.eq(ev, { "died" })
      local _, _, ev2 = r:apply("Ginkan", { tg = "DEAD" }, 3, 3)
      A.eq(ev2, {})
      local _, _, ev3 = r:apply("Fresh", { tg = "DEAD" }, 3, 3)
      A.eq(ev3, { "new", "online" })
    end,
    offline_after_timeout = function(ns, A)
      local r = ns.Roster.new({})
      local m = r:apply("Ginkan", { lv = "5" }, 0, 100)
      A.eq(r:tick(179), {}); A.ok(m.online)
      A.eq(r:tick(181), { "Ginkan" }); A.eq(m.online, false)
      A.eq(r:tick(200), {})
      A.eq(r:heard("Ginkan", 200, 2000), { "online" })
      A.eq(m.lastSeen, 2000); A.eq(r:heard("Ginkan", 201, 2001), {})
    end,
    gone_marks_offline = function(ns, A)
      local r = ns.Roster.new({})
      r:apply("Ginkan", {}, 0, 100)
      r:gone("Ginkan"); A.eq(r:get("Ginkan").online, false)
      r:gone("Nobody")
    end,
    going_offline_forgets_session_data = function(ns, A)
      local r = ns.Roster.new({})
      local m = r:apply("Ginkan", { lk = "111", ins = "1", tg = "AFK", zn = "Elwynn Forest", lv = "5" }, 0, 100)
      A.eq(m.layerKey, "111"); A.eq(m.inInstance, true); A.eq(m.tags, { AFK = true })
      r:gone("Ginkan")
      A.eq(m.layerKey, nil); A.eq(m.inInstance, false); A.eq(m.tags, nil)
      A.eq(m.zone, "Elwynn Forest"); A.eq(m.level, 5)
      r:apply("Ginkan", { lk = "222", ins = "1", tg = "COMBAT" }, 1, 101)
      A.eq(r:tick(500), { "Ginkan" })
      A.eq(m.layerKey, nil); A.eq(m.inInstance, false); A.eq(m.tags, nil)
    end,
    clear_session_reports_changes = function(ns, A)
      local r = ns.Roster.new({})
      r:apply("Ginkan", { lk = "111", tg = "" }, 0, 100)
      A.eq(r:clearSession("Ginkan"), { layerKey = true, tags = true })
      A.eq(r:clearSession("Ginkan"), {})
      A.eq(r:clearSession("Nobody"), {})
    end,
    saved_members_start_offline = function(ns, A)
      local r = ns.Roster.new({ Stabz = { class = "ROGUE", level = 9, lastSeen = ns.wallclock() - 500 }, junk = 5, [3] = {} })
      local m = r:get("Stabz")
      A.eq(m.online, false); A.eq(m.class, "ROGUE"); A.eq(m.level, 9); A.eq(m.lastSeen, ns.wallclock() - 500); A.eq(m.name, "Stabz")
      A.eq(r:names(), { "Stabz" })
      local _, _, ev = r:apply("Stabz", { lv = "10" }, 1, 600)
      A.eq(ev, { "online" })
    end,
    heard_unknown_name_is_ignored = function(ns, A)
      local r = ns.Roster.new({})
      A.eq(r:heard("Nobody", 1, 1), {}); A.eq(r:get("Nobody"), nil); A.eq(r:names(), {})
    end,
    counts_and_lists = function(ns, A)
      local r = ns.Roster.new({ Old = { level = 1 } })
      r:apply("b", {}, 0, 1); r:apply("A", {}, 0, 1)
      A.eq(r:names(), { "A", "Old", "b" })
      local on, total = r:onlineCount(); A.eq(on, 2); A.eq(total, 3)
      A.eq(#r:members(), 3)
    end,
    sort_modes = function(ns, A)
      local r = ns.Roster.new({ Cat = { level = 60 } })
      r:apply("Zed", { lv = "10" }, 0, 1); r:apply("amy", { lv = "20" }, 0, 1); r:apply("Bob", { lv = "15" }, 0, 1)
      local function names(list) local o = {}; for i, m in ipairs(list) do o[i] = m.name end; return o end
      A.eq(names(r:sorted("name")), { "amy", "Bob", "Cat", "Zed" }, "pure A-Z, offline mixed in")
      A.eq(names(r:sorted("level")), { "amy", "Bob", "Zed", "Cat" })
      A.eq(names(r:sorted("online")), { "amy", "Bob", "Zed", "Cat" })
      local rel = function(n) return n == "Zed" and "same" or "other" end
      A.eq(names(r:sorted("layer", rel)), { "Zed", "amy", "Bob", "Cat" })
    end,
    -- test tools: fake names end in " (test)"; they are never saved and only shown when asked for
    fake_names_are_never_real_names = function(ns, A)
      A.ok(ns.isTestName("Testbuddy (test)"))
      A.no(ns.isTestName("Testbuddy"))
      A.no(ns.isTestName("Testbuddy-Realm"))
      A.no(ns.isTestName(nil))
      A.eq(ns.shortName("Testbuddy (test)"), "Testbuddy", "a real sender name can never keep the mark")
    end,
    fakes_are_never_saved = function(ns, A)
      local saved = {}
      local r = ns.Roster.new(saved)
      local m, _, ev = r:apply("Testbuddy (test)", { cl = "PALADIN", lv = "12" }, 1, 1)
      A.eq(m.level, 12); A.eq(ev, { "new", "online" })
      A.eq(saved, {}, "nothing saved")
      r:heard("Testbuddy (test)", 2, 2)
      A.eq(saved, {})
      local r2 = ns.Roster.new({ ["Old (test)"] = { level = 3 }, Real = { level = 4 } })
      A.eq(r2:names(true), { "Real" }, "a fake in old saved data is never loaded")
    end,
    fakes_left_out_unless_asked = function(ns, A)
      local r = ns.Roster.new({})
      r:apply("Ginkan", { lv = "14" }, 1, 1)
      r:apply("Testbuddy (test)", { lv = "12" }, 1, 1)
      A.eq(r:names(), { "Ginkan" })
      A.eq(#r:members(), 1)
      A.eq(r:names(true), { "Ginkan", "Testbuddy (test)" })
      A.eq(#r:members(true), 2)
      A.eq(#r:sorted("online"), 2, "the panel shows fakes")
      local on, total = r:onlineCount(); A.eq(on, 2); A.eq(total, 2)
      A.eq(r:testNames(), { "Testbuddy (test)" })
      A.ok(r:get("Testbuddy (test)"))
    end,
    only_fakes_can_be_removed = function(ns, A)
      local saved = {}
      local r = ns.Roster.new(saved)
      r:apply("Ginkan", { lv = "14" }, 1, 1)
      r:apply("Testbuddy (test)", { lv = "12" }, 1, 1)
      A.no(r:remove("Ginkan")); A.ok(r:get("Ginkan")); A.ok(saved.Ginkan)
      A.ok(r:remove("Testbuddy (test)")); A.eq(r:get("Testbuddy (test)"), nil)
      A.eq(r:names(true), { "Ginkan" })
    end,
    digest_follows_what_was_received_not_the_ride_along_keys = function(ns, A)
      local r = ns.Roster.new({})
      r:apply("Ginkan", { zn = "A", lv = "5", xc = "10" }, 1, 1)
      A.eq(r:digest("Ginkan"), ns.Self.digestOf({ zn = "A", lv = "5", xc = "99", lk = "7" }))
      r:apply("Ginkan", { zn = "B" }, 2, 2)
      A.eq(r:digest("Ginkan"), ns.Self.digestOf({ zn = "B", lv = "5" }))
      A.eq(r:digest("Nobody"), ns.Self.digestOf({}))
    end,
    forget_takes_out_offline_rows_only = function(ns, A)
      local saved = {}
      local r = ns.Roster.new(saved)
      r:apply("Ginkan", { lv = "5" }, 1, 1)
      A.no(r:forget("Ginkan"), "online")
      r:gone("Ginkan")
      A.ok(r:forget("Ginkan"))
      A.eq(r:get("Ginkan"), nil); A.eq(saved.Ginkan, nil)
      A.no(r:forget("Ginkan"))
    end,
    load_prunes_rows_older_than_the_forget_limit = function(ns, A)
      local now, day = ns.wallclock(), 86400
      local limit = ns.Config.FORGET_AFTER_DAYS
      local saved = { Old = { lastSeen = now - (limit + 1) * day }, Edge = { lastSeen = now - (limit - 1) * day },
        Undated = {} }
      local r = ns.Roster.new(saved)
      A.eq(r:names(), { "Edge", "Undated" })
      A.eq(r.pruned, { "Old" })
      A.eq(saved.Old, nil)
      A.eq(saved.Undated.lastSeen, now)
    end,
  },
}
