local function setup(ns)
  local calls = { enable = 0, disable = 0, changed = {} }
  ns.Modules.register({ id = "core1", name = "Core One", tier = "essential", info = "Core.", defaults = { debug = false },
    settings = { { key = "debug", label = "Debug", info = "Debug.", kind = "toggle" },
                 { key = "channel", label = "Channel", info = "Channel.", kind = "text", store = "crew" } } })
  ns.Modules.register({ id = "m1", name = "Module One", tier = "module", info = "Mod.",
    defaults = { scale = 1, position = { point = "LEFT", x = 40, y = 100 } },
    settings = { { key = "scale", label = "Scale", info = "Scale.", kind = "slider", min = 0.5, max = 2, step = 0.1 } },
    onEnable = function() calls.enable = calls.enable + 1 end,
    onDisable = function() calls.disable = calls.disable + 1 end,
    onSettingChanged = function(k, v) calls.changed[#calls.changed + 1] = k .. "=" .. tostring(v) end })
  ns.Modules.register({ id = "soon", name = "Soon", tier = "extra", info = "Later.", comingSoon = true })
  return calls
end

local function attached(ns)
  local calls = setup(ns)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  return db, calls
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/Log.lua", "Core/Events.lua", "Core/Modules.lua", "Core/DB.lua" },
  tests = {
    register_requires_info_everywhere = function(ns, A)
      A.errors(function() ns.Modules.register({ id = "x", name = "X", tier = "module", info = "" }) end, "info")
      A.errors(function() ns.Modules.register({ id = "y", name = "Y", tier = "module", info = "ok", defaults = { a = 1 },
        settings = { { key = "a", label = "A", kind = "toggle" } } }) end, "info")
      A.errors(function() ns.Modules.register({ id = "z", name = "Z", tier = "module", info = "ok",
        settings = { { key = "a", label = "A", info = "i", kind = "toggle" } } }) end, "default")
    end,
    register_rejects_duplicate_id = function(ns, A)
      setup(ns)
      A.errors(function() ns.Modules.register({ id = "m1", name = "Again", tier = "module", info = "x" }) end, "twice")
      A.eq(#ns.Modules.list(), 3)
      A.eq(#ns.Modules.list("module"), 1)
      A.eq(ns.Modules.list()[1].id, "core1")
    end,
    init_from_nil_builds_defaults = function(ns, A)
      setup(ns)
      local db = ns.DB.init(nil, ns.Modules.list())
      A.eq(db.modules.m1.settings.scale, 1); A.eq(db.modules.m1.enabled, true)
      A.eq(db.crew.channel, "TwizCrewHQ"); A.eq(db.crew.password, "goldshire"); A.eq(db.crew.extra, {})
      A.eq(db.schema, 1); A.eq(db.myStatus, "")
    end,
    init_repairs_broken_saved_data = function(ns, A)
      setup(ns)
      A.eq(ns.DB.init(42, ns.Modules.list()).schema, 1)
      local db = ns.DB.init({ modules = { m1 = { enabled = "yes", settings = { scale = "big", position = 5 } }, gone = {} } }, ns.Modules.list())
      A.eq(db.modules.m1.settings.scale, 1); A.eq(type(db.modules.m1.enabled), "boolean"); A.no(db.modules.gone)
      A.eq(db.modules.m1.settings.position.x, 40)
      A.eq(ns.DB.init({ modules = 7, crew = "x", log = 3 }, ns.Modules.list()).crew.channel, "TwizCrewHQ")
    end,
    essentials_cannot_be_disabled = function(ns, A)
      attached(ns)
      ns.Modules.setEnabled("core1", false)
      A.ok(ns.Modules.isEnabled("core1"))
      A.no(ns.Modules.isEnabled("soon"))
      ns.Modules.setEnabled("soon", true)
      A.no(ns.Modules.isEnabled("soon"))
    end,
    setEnabled_calls_hooks_and_fires_bus = function(ns, A)
      local db, calls = attached(ns)
      local fired = {}
      ns.Bus.on("t", "MODULE_TOGGLED", function(id, on) fired[#fired + 1] = id .. tostring(on) end)
      ns.Modules.startAll()
      A.eq(calls.enable, 1)
      ns.Bus.on("m1", "X", function() fired[#fired + 1] = "leak" end)
      ns.Modules.setEnabled("m1", false)
      A.eq(calls.disable, 1); A.no(ns.Modules.isEnabled("m1")); A.eq(db.modules.m1.enabled, false)
      ns.Bus.fire("X"); A.eq(fired, { "m1false" })
      ns.Modules.setEnabled("m1", true)
      A.eq(calls.enable, 2); A.eq(fired, { "m1false", "m1true" })
    end,
    set_stores_validates_and_notifies = function(ns, A)
      local db, calls = attached(ns)
      local fired = {}
      ns.Bus.on("t", "SETTING_CHANGED", function(id, k, v) fired[#fired + 1] = id .. k .. tostring(v) end)
      A.ok(ns.Modules.set("m1", "scale", 1.5))
      A.eq(ns.Modules.setting("m1", "scale"), 1.5); A.eq(calls.changed, { "scale=1.5" }); A.eq(fired, { "m1scale1.5" })
      A.no(ns.Modules.set("m1", "scale", "big"))
      A.no(ns.Modules.set("m1", "nokey", 1))
      A.eq(db.modules.m1.settings.scale, 1.5)
      A.contains(ns.Log.lines()[#ns.Log.lines()], "WARN")
      A.ok(ns.Modules.set("core1", "channel", "Secret"))
      A.eq(db.crew.channel, "Secret"); A.eq(ns.Modules.setting("core1", "channel"), "Secret")
      A.no(ns.Modules.set("core1", "channel", 5))
    end,
    reset_restores_settings_keeps_crew_data = function(ns, A)
      local db = attached(ns)
      db.modules.m1.settings.scale = 2; db.modules.m1.settings.position.x = 999; db.modules.m1.enabled = false
      db.crew.channel = "Secret"; db.roster.Ginkan = { level = 14 }; db.myStatus = "brb"; db.log[1] = "x"
      ns.Modules.resetAll()
      A.eq(db.modules.m1.settings.scale, 1); A.eq(db.modules.m1.settings.position.x, 40); A.ok(db.modules.m1.enabled)
      A.eq(db.crew.channel, "Secret"); A.eq(db.roster.Ginkan.level, 14); A.eq(db.myStatus, "brb"); A.eq(#db.log, 1)
    end,
    reset_fires_SETTINGS_RESET_and_onSettingChanged = function(ns, A)
      local db, calls = attached(ns)
      local n = 0
      ns.Bus.on("t", "SETTINGS_RESET", function() n = n + 1 end)
      db.modules.m1.enabled = false
      ns.Modules.resetAll()
      A.eq(n, 1); A.eq(calls.enable, 1)
      local seen = {}
      for _, c in ipairs(calls.changed) do seen[c] = true end
      A.ok(seen["scale=1"]); A.eq(#calls.changed, 2)
    end,
    markBroken_disables_and_prints_once = function(ns, A, W)
      local db, calls = attached(ns)
      ns.Modules.startAll()
      ns.Modules.markBroken("m1"); ns.Modules.markBroken("m1")
      A.eq(#W.printed, 1); A.contains(W.printed[1], "/tc report"); A.contains(W.printed[1], "Module One")
      A.no(ns.Modules.isEnabled("m1")); A.eq(calls.disable, 1)
      A.eq(db.modules.m1.enabled, true) -- session only, not saved
      A.eq(ns.Modules.broken(), { "m1" })
      ns.Modules.markBroken("core1")
      A.ok(ns.Modules.isEnabled("core1")); A.eq(#W.printed, 1); A.eq(ns.Modules.broken(), { "m1" })
    end,
    errors_in_a_module_turn_it_off_via_Log = function(ns, A, W)
      attached(ns)
      for _ = 1, 3 do ns.Log.safe("m1", function() error("boom") end) end
      A.no(ns.Modules.isEnabled("m1"))
    end,
    init_builds_update_memory_and_reset_keeps_it = function(ns, A)
      setup(ns)
      local db = ns.DB.init(nil, ns.Modules.list())
      A.eq(db.update, {})
      A.eq(ns.DB.init({ update = "x" }, ns.Modules.list()).update, {})
      db.update.told = "0.2.0"
      ns.db = db; ns.Modules.attach(db); ns.Modules.resetAll()
      A.eq(db.update.told, "0.2.0")
    end,
    button_and_list_settings_need_no_default_and_are_never_saved = function(ns, A)
      attached(ns)
      local clicks = 0
      ns.Modules.register({ id = "acts", name = "Acts", tier = "essential", info = "Has actions.",
        settings = {
          { key = "go", label = "Go", kind = "button", info = "Does it.", onClick = function() clicks = clicks + 1 end },
          { key = "who", label = "Who", kind = "list", info = "Lists.", lines = function() return { "a" } end },
        } })
      A.eq(ns.Modules.setting("acts", "go"), nil)
      A.no(ns.Modules.set("acts", "go", true), "a button holds no value")
      A.errors(function()
        ns.Modules.register({ id = "acts2", name = "A", tier = "module", info = "x",
          settings = { { key = "go", label = "Go", kind = "button", info = "x" } } })
      end, "onClick")
      A.errors(function()
        ns.Modules.register({ id = "acts3", name = "A", tier = "module", info = "x",
          settings = { { key = "who", label = "Who", kind = "list", info = "x" } } })
      end, "lines")
      A.errors(function()
        ns.Modules.register({ id = "acts4", name = "A", tier = "module", info = "x",
          settings = { { key = "go", label = "Go", kind = "button", onClick = function() end } } })
      end, "info")
    end,
    init_builds_problems_ring = function(ns, A)
      setup(ns)
      A.eq(ns.DB.init(nil, ns.Modules.list()).problems, {})
    end,
    breaker_switches_module_back_on_after_rearm_time = function(ns, A, W)
      local db, calls = attached(ns)
      ns.Modules.startAll()
      A.eq(calls.enable, 1)
      local fired = {}
      ns.Bus.on("t", "MODULE_TOGGLED", function(id, on) fired[#fired + 1] = id .. tostring(on) end)
      for i = 1, 3 do ns.Log.safe("m1", error, "x") end
      A.no(ns.Modules.isEnabled("m1"))
      A.eq(ns.Modules.broken(), { "m1" })
      A.eq(calls.disable, 1)
      W:advance(299)
      A.no(ns.Modules.isEnabled("m1"))
      W:advance(2)
      A.ok(ns.Modules.isEnabled("m1"))
      A.eq(calls.enable, 2)
      A.eq(ns.Modules.broken(), {})
      A.eq(fired, { "m1false", "m1true" })
      local last = ns.Log.lines()[#ns.Log.lines()]
      A.contains(last, "INFO m1 switched back on")
      -- the second break takes twice as long
      for i = 1, 3 do ns.Log.safe("m1", error, "x") end
      A.no(ns.Modules.isEnabled("m1"))
      W:advance(599)
      A.no(ns.Modules.isEnabled("m1"))
      W:advance(2)
      A.ok(ns.Modules.isEnabled("m1"))
      A.eq(calls.enable, 3)
    end,
    rearm_leaves_a_module_the_owner_switched_off_alone = function(ns, A, W)
      local db, calls = attached(ns)
      ns.Modules.startAll()
      for i = 1, 3 do ns.Log.safe("m1", error, "x") end
      ns.Modules.setEnabled("m1", false)
      W:advance(301)
      A.no(ns.Modules.isEnabled("m1"))
      A.eq(calls.enable, 1)
    end,
    errors_under_a_part_id_do_not_switch_modules_off = function(ns, A)
      attached(ns)
      ns.Modules.register({ id = "roasts", name = "Roasts", tier = "module", info = "R." })
      ns.Modules.startAll()
      for i = 1, 3 do ns.Log.safe("mockshow", error, "x") end
      for i = 1, 3 do ns.Log.safe("mockshow", error, "x") end
      A.ok(ns.Modules.isEnabled("roasts"))
      A.eq(ns.Modules.broken(), {})
      local warns = 0
      for _, l in ipairs(ns.Log.lines()) do if l:find("WARN mockshow", 1, true) then warns = warns + 1 end end
      A.eq(warns, 1)
    end,
    init_builds_stats_and_reset_keeps_it = function(ns, A)
      setup(ns)
      local db = ns.DB.init(nil, ns.Modules.list())
      A.eq(db.stats, { chars = {}, crew = {}, session = {} })
      A.eq(ns.DB.init({ stats = 5 }, ns.Modules.list()).stats.chars, {})
      db.stats.chars.Twiz = { sid = "x", s = { dt = 1 }, a = { dt = 4 } }
      ns.db = db; ns.Modules.attach(db); ns.Modules.resetAll()
      A.eq(db.stats.chars.Twiz.a.dt, 4)
    end,
  },
}
