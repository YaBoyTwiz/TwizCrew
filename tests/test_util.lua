return {
  files = { "Core/Init.lua", "Core/Util.lua" },
  tests = {
    split_keeps_empty_fields = function(ns, A)
      A.eq(ns.Util.split("a^^b", "^"), { "a", "", "b" })
      A.eq(ns.Util.split("", "^"), { "" })
    end,
    mergeDefaults_fills_and_repairs = function(ns, A)
      local t = { a = 5, b = "wrong", nested = { x = 1 } }
      ns.Util.mergeDefaults(t, { a = 1, b = true, c = 3, nested = { x = 9, y = 2 } })
      A.eq(t, { a = 5, b = true, c = 3, nested = { x = 1, y = 2 } })
    end,
    compareVersions_numeric = function(ns, A)
      A.eq(ns.Util.compareVersions("1.10.0", "1.2.0"), 1)
      A.eq(ns.Util.compareVersions("1.2", "1.2.0"), 0)
      A.eq(ns.Util.compareVersions("0.9", "1.0"), -1)
      A.eq(ns.Util.compareVersions("abc", "0"), 0)
    end,
    compareVersions_handles_release_formats = function(ns, A)
      A.eq(ns.Util.compareVersions("1.2.10", "1.2.9"), 1)
      A.eq(ns.Util.compareVersions("1.2.9", "1.2.10"), -1)
      A.eq(ns.Util.compareVersions("1.2.10", "1.2.10"), 0)
      A.eq(ns.Util.compareVersions("0.10.0", "0.9.9"), 1)
      A.eq(ns.Util.compareVersions("2.0", "1.99.99"), 1)
      A.eq(ns.Util.compareVersions("v1.2.10", "1.2.10"), 0, "a leading v is ignored")
      A.eq(ns.Util.compareVersions("1.2.3-beta", "1.2.3"), 0, "text after the number is ignored")
      A.eq(ns.Util.compareVersions(nil, "0.1.0"), -1)
    end,
    isVersion_accepts_only_plain_numbers = function(ns, A)
      A.ok(ns.Util.isVersion("0.1.0")); A.ok(ns.Util.isVersion("1.2.10")); A.ok(ns.Util.isVersion("3"))
      A.no(ns.Util.isVersion("")); A.no(ns.Util.isVersion("1..2")); A.no(ns.Util.isVersion("1.2.")); A.no(ns.Util.isVersion("v1.2"))
      A.no(ns.Util.isVersion("1.2|r")); A.no(ns.Util.isVersion(nil)); A.no(ns.Util.isVersion(12))
      A.no(ns.Util.isVersion(string.rep("1.", 20) .. "1"), "absurdly long")
    end,
    truncateUTF8_keeps_letters_whole = function(ns, A)
      A.eq(ns.Util.truncateUTF8("Holybøi rocks", 6), "Holybø")
      A.eq(ns.Util.truncateUTF8("abc", 40), "abc")
    end,
    safeText_escapes_pipes = function(ns, A)
      A.eq(ns.Util.safeText("hi |TInterface\\x:0|t |cffff0000red"), "hi ||TInterface\\x:0||t ||cffff0000red")
    end,
    ago_buckets = function(ns, A)
      A.eq(ns.Util.ago(30), "just now")
      A.eq(ns.Util.ago(300), "5m ago")
      A.eq(ns.Util.ago(7200), "2h ago")
      A.eq(ns.Util.ago(3 * 86400), "3d ago")
    end,
    plain_passes_results_through_in_position = function(ns, A)
      local function f(...) return ... end
      A.eq(select("#", ns.Util.plain(f, 1, "a", true, nil)), 4)
      local a, b, c, d = ns.Util.plain(f, 1, "a", true, nil)
      A.eq({ a, b, c, d }, { 1, "a", true, nil })
      A.eq(select("#", ns.Util.plain(f, 1, nil, 3)), 3, "a nil in the middle survives")
      A.eq(select(3, ns.Util.plain(f, 1, nil, 3)), 3)
    end,
    plain_replaces_secret_results_with_nil = function(ns, A, W)
      local hidden = W.secret()
      local x, y, z = ns.Util.plain(function() return 1, hidden, 3 end)
      A.eq({ x, y, z }, { 1, nil, 3 })
      A.eq(select("#", ns.Util.plain(function() return 1, hidden, 3 end)), 3)
    end,
    plain_returns_nothing_when_fn_raises_or_is_missing = function(ns, A)
      A.eq(select("#", ns.Util.plain(function() error("boom") end)), 0)
      A.eq(select("#", ns.Util.plain(nil)), 0)
      A.eq(select("#", ns.Util.plain("x")), 0)
    end,
    isSecret_follows_issecretvalue = function(ns, A, W)
      local hidden = W.secret()
      A.eq(ns.Util.isSecret(hidden), true)
      A.eq(ns.Util.isSecret(5), false)
      A.eq(ns.Util.isSecret(nil), false)
      W.env.issecretvalue = nil
      A.eq(ns.Util.isSecret(5), false, "no issecretvalue in the game")
      A.eq(ns.Util.isSecret(hidden), false)
    end,
    plain_without_issecretvalue_passes_everything = function(ns, A, W)
      W.env.issecretvalue = nil
      A.eq(ns.Util.plain(function() return 7 end), 7)
    end,
    init_reads_version_and_player = function(ns, A)
      A.eq(ns.VERSION, "0.1.0")
      A.eq(ns.playerName(), "Twiz")
      A.eq(ns.Config.PREFIX, "TwizCrew")
    end,
  },
}
