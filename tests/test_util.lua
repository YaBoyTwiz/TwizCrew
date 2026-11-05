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
    init_reads_version_and_player = function(ns, A)
      A.eq(ns.VERSION, "0.1.0")
      A.eq(ns.playerName(), "Twiz")
      A.eq(ns.Config.PREFIX, "TwizCrew")
    end,
  },
}
