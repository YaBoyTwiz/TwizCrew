return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/Log.lua", "Core/Events.lua" },
  tests = {
    log_keeps_newest_LOG_MAX = function(ns, A)
      for i = 1, 510 do ns.Log.add("info", "n%d", i) end
      A.eq(#ns.Log.lines(), 500)
      A.contains(ns.Log.lines()[500], "n510")
      A.contains(ns.Log.lines()[1], "n11")
    end,
    log_attach_moves_early_lines = function(ns, A)
      ns.Log.add("info", "early")
      local saved = {}
      ns.Log.attach(saved)
      A.contains(saved[1], "early")
      ns.Log.add("warn", "later")
      A.contains(saved[2], "WARN later")
    end,
    log_attach_drops_lines_that_are_not_text = function(ns, A)
      local saved = { "[10:00:00] INFO one", 5, {}, "[10:00:01] WARN two" }
      saved[7] = "after a hole"
      saved.junk = true
      ns.Log.attach(saved)
      A.eq(saved, { "[10:00:00] INFO one", "[10:00:01] WARN two", "after a hole" })
      A.eq(ns.Log.errors(5), {})
    end,
    safe_passes_args_and_results = function(ns, A)
      local ok, a, b, c = ns.Log.safe("f", function(x, y, z) return z, y, x end, 1, nil, 3)
      A.ok(ok); A.eq(a, 3); A.eq(b, nil); A.eq(c, 1)
    end,
    safe_catches_and_logs = function(ns, A)
      local ok = ns.Log.safe("layer", function() error("boom") end)
      A.no(ok)
      A.contains(ns.Log.errors(1)[1], "layer")
      A.contains(ns.Log.errors(1)[1], "boom")
    end,
    safe_breaks_after_three_in_window = function(ns, A)
      local broken = {}
      ns.Log.onBroken = function(id) broken[#broken + 1] = id end
      for i = 1, 3 do ns.Log.safe("panel", error, "x") end
      A.eq(broken, { "panel" })
      ns.Log.safe("panel", error, "x")
      A.eq(#broken, 1)
    end,
    safe_errors_spread_out_do_not_break = function(ns, A, W)
      local broken = {}
      ns.Log.onBroken = function(id) broken[#broken + 1] = id end
      for i = 1, 3 do ns.Log.safe("panel", error, "x"); W:advance(61) end
      A.eq(broken, {})
    end,
    events_dispatch_and_off = function(ns, A, W)
      local count = 0
      ns.Events.on("a", "PLAYER_LOGIN", function() count = count + 1 end)
      W:fire("PLAYER_LOGIN")
      A.eq(count, 1)
      ns.Events.off("a")
      W:fire("PLAYER_LOGIN")
      A.eq(count, 1)
    end,
    events_pass_args = function(ns, A, W)
      local got
      ns.Events.on("a", "CHAT_MSG_ADDON", function(...) got = { ... } end)
      W:fire("CHAT_MSG_ADDON", "p", "m")
      A.eq(got, { "p", "m" })
    end,
    events_handler_error_does_not_stop_others = function(ns, A, W)
      local ran = false
      ns.Events.on("a", "PLAYER_LOGIN", function() error("bad") end)
      ns.Events.on("b", "PLAYER_LOGIN", function() ran = true end)
      W:fire("PLAYER_LOGIN")
      A.ok(ran)
    end,
    events_off_during_dispatch_is_safe = function(ns, A, W)
      local ran = {}
      ns.Events.on("a", "PLAYER_LOGIN", function() ran[#ran + 1] = "a"; ns.Events.off("b") end)
      ns.Events.on("b", "PLAYER_LOGIN", function() ran[#ran + 1] = "b" end)
      ns.Events.on("c", "PLAYER_LOGIN", function() ran[#ran + 1] = "c"; ns.Events.on("d", "PLAYER_LOGIN", function() end) end)
      W:fire("PLAYER_LOGIN")
      A.eq(ran, { "a", "c" })
    end,
    bus_fire_reaches_listeners_and_off_removes = function(ns, A)
      local called = 0
      ns.Bus.on("x", "SETTINGS_RESET", function() called = called + 1 end)
      ns.Bus.fire("SETTINGS_RESET")
      A.eq(called, 1)
      ns.Bus.off("x")
      ns.Bus.fire("SETTINGS_RESET")
      A.eq(called, 1)
    end,
    bus_passes_args_and_survives_errors = function(ns, A)
      local got
      ns.Bus.on("x", "MEMBER_ONLINE", function() error("bad") end)
      ns.Bus.on("y", "MEMBER_ONLINE", function(name) got = name end)
      ns.Bus.fire("MEMBER_ONLINE", "Bob")
      A.eq(got, "Bob")
    end,
  },
}
