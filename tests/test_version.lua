local function start(ns)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  return db
end

return {
  files = "toc",
  tests = {
    older_or_same_is_quiet = function(ns, A, W)
      start(ns)
      ns.Version.seen("Ginkan", "0.1.0")
      ns.Version.seen("Frostie", "0.0.9")
      A.eq(W.printed, {})
      A.eq(ns.Version.summary(), "everyone up to date")
    end,
    newer_prints_once_and_summarizes = function(ns, A, W)
      start(ns)
      local fired = {}
      ns.Bus.on("test", "VERSION_NEWER", function(n, v) fired[#fired + 1] = n .. v end)
      ns.Version.seen("Ginkan", "0.2.0")
      ns.Version.seen("Frostie", "0.3.0")
      ns.Version.seen("Ginkan", "0.2.0")
      A.eq(W.printed, { "TwizCrew: Ginkan has v0.2.0, you have v0.1.0. Update in WowUp." })
      A.eq(ns.Version.summary(), "Frostie has v0.3.0, you have v0.1.0. Update in WowUp.")
      A.eq(fired, { "Ginkan0.2.0", "Frostie0.3.0" })
    end,
    chatNotice_off_still_summarizes = function(ns, A, W)
      start(ns)
      ns.Modules.set("version", "chatNotice", false)
      ns.Version.seen("Ginkan", "0.2.0")
      A.eq(W.printed, {})
      A.eq(ns.Version.summary(), "Ginkan has v0.2.0, you have v0.1.0. Update in WowUp.")
    end,
    junk_is_tolerated_and_escaped = function(ns, A, W)
      start(ns)
      ns.Version.seen(nil, "0.5.0")
      ns.Version.seen("A", nil)
      ns.Version.seen("A", "")
      ns.Version.seen("A", 7)
      ns.Version.seen("A", {})
      ns.Version.seen(nil, nil)
      ns.Version.seen("Bad|cffff0000", "9.0|r")
      A.ok(ns.Version.summary():find("Bad||cffff0000", 1, true))
      A.ok(ns.Version.summary():find("v9.0||r", 1, true))
      A.ok(W.printed[#W.printed]:find("Bad||cffff0000", 1, true))
      A.eq(ns.Log.errors(10), {})
    end,
    version_module_is_registered = function(ns, A)
      local d = ns.Modules.get("version")
      A.ok(d); A.eq(d.name, "Version check"); A.eq(d.tier, "essential")
      A.eq(d.defaults.chatNotice, true)
    end,
  },
}
