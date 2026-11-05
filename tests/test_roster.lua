return {
  files = { "Core/Init.lua", "Core/Util.lua", "Crew/Roster.lua" },
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
      local r = ns.Roster.new({ Stabz = { class = "ROGUE", level = 9, lastSeen = 500 }, junk = 5, [3] = {} })
      local m = r:get("Stabz")
      A.eq(m.online, false); A.eq(m.class, "ROGUE"); A.eq(m.level, 9); A.eq(m.lastSeen, 500); A.eq(m.name, "Stabz")
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
  },
}
