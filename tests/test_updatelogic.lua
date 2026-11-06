-- Pure rules of "Tell crew to update": accept, restart, texts, the line after a reload, the version list.
local function ctx(over)
  local c = { myVersion = "0.1.0", enabled = true, isCrew = true, shown = {}, now = 100, repeatGap = 600 }
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/UpdateLogic.lua" },
  tests = {
    accepts_only_newer_crew = function(ns, A)
      local L = ns.UpdateLogic
      A.eq({ L.accept({ sender = "Twiz", ver = "0.2.0", rs = "0.1.0" }, ctx()) }, { true })
      A.eq({ L.accept({ sender = "Twiz", ver = "0.1.0" }, ctx()) }, { false, "not newer" })
      A.eq({ L.accept({ sender = "Twiz", ver = "0.0.9" }, ctx()) }, { false, "not newer" })
      A.eq({ L.accept({ sender = "Twiz", ver = "1.2.9" }, ctx({ myVersion = "1.2.10" })) }, { false, "not newer" })
      A.eq({ L.accept({ sender = "Twiz", ver = "1.2.10" }, ctx({ myVersion = "1.2.9" })) }, { true })
      A.eq({ L.accept({ sender = "Stranger", ver = "9.0.0" }, ctx({ isCrew = false })) }, { false, "not crew" })
      A.eq({ L.accept({ sender = "Twiz", ver = "0.2.0" }, ctx({ enabled = false })) }, { false, "off" })
    end,

    junk_is_refused = function(ns, A)
      local L = ns.UpdateLogic
      for _, ver in ipairs({ "", "abc", "9.0|r", "v2.0", "1..2" }) do
        A.eq({ L.accept({ sender = "Twiz", ver = ver }, ctx()) }, { false, "bad version" }, ver)
      end
      A.eq({ L.accept({ sender = "Twiz" }, ctx()) }, { false, "bad version" })
      A.eq({ L.accept({ ver = "0.2.0" }, ctx()) }, { false, "not crew" })
      A.eq({ L.accept(nil, ctx()) }, { false, "not crew" })
    end,

    same_version_is_ignored_for_a_while = function(ns, A)
      local L = ns.UpdateLogic
      local c = ctx({ shown = { ["0.2.0"] = 100 } })
      c.now = 300
      A.eq({ L.accept({ sender = "Frostie", ver = "0.2.0" }, c) }, { false, "repeat" }, "from anyone")
      A.eq({ L.accept({ sender = "Twiz", ver = "0.3.0" }, c) }, { true }, "a newer one shows at once")
      c.now = 701
      A.eq({ L.accept({ sender = "Twiz", ver = "0.2.0" }, c) }, { true }, "after the gap")
    end,

    restart_rule = function(ns, A)
      local L = ns.UpdateLogic
      A.eq(L.needsRestart("0.1.0", "0.2.0"), true)
      A.eq(L.needsRestart("0.2.0", "0.2.0"), false)
      A.eq(L.needsRestart("0.2.9", "0.2.10"), true)
      A.eq(L.needsRestart("0.3.0", "0.2.0"), false)
      A.eq(L.needsRestart("0.1.0", nil), false, "an old copy without rs: reload")
      A.eq(L.needsRestart("0.1.0", "junk"), false)
    end,

    prompt_texts = function(ns, A)
      local L = ns.UpdateLogic
      A.eq(L.prompt("Twiz", "0.2.0", false), { title = "Twiz says v0.2.0 is out",
        note = "If nothing changed, open WowUp and click Update first", reload = true })
      A.eq(L.prompt("Twiz", "0.2.0", true), { title = "Twiz says v0.2.0 is out",
        note = "Close and restart the game to load it", reload = false })
    end,

    line_after_login = function(ns, A)
      local L = ns.UpdateLogic
      A.eq(L.afterLogin("0.1.0", { told = "0.2.0", rs = "0.1.0" }),
        { "Still on v0.1.0. Open WowUp, click Update, then /reload" })
      A.eq(L.afterLogin("0.1.0", { told = "0.2.0", rs = "0.2.0" }),
        { "Still on v0.1.0. Open WowUp, click Update, then restart the game" })
      A.eq(L.afterLogin("0.2.0", { told = "0.2.0" }), {}, "updated: nothing to say")
      A.eq(L.afterLogin("0.3.0", { told = "0.2.0" }), {})
      A.eq(L.afterLogin("0.1.0", {}), {})
      A.eq(L.afterLogin("0.1.0", { told = "junk" }), {})
      A.eq(L.afterLogin("0.1.0", nil), {})
    end,

    old_toc_after_reload_says_restart = function(ns, A)
      local L = ns.UpdateLogic
      local line = "TwizCrew v0.3.0 added new files. Close and restart the game to finish the update."
      A.eq(L.afterLogin("0.3.0", {}, "0.2.0", "0.3.0"), { line })
      A.eq(L.afterLogin("0.3.0", {}, "0.2.0", "0.2.0"), {}, "no new files since 0.2.0: the reload was enough")
      A.eq(L.afterLogin("0.3.0", {}, "0.3.0", "0.3.0"), {}, "restarted")
      A.eq(L.afterLogin("0.3.0", {}, nil, "0.3.0"), {}, "unknown .toc version")
    end,

    version_rows = function(ns, A)
      local L = ns.UpdateLogic
      local members = {
        { name = "ginkan", online = true, version = "0.1.0" },
        { name = "Frostie", online = true, version = "0.2.0" },
        { name = "Holyboi", online = false, version = "0.2.0" },
        { name = "Newbie", online = true },
        { name = "Bad", online = true, version = "9|r" },
      }
      A.eq(L.versionRows("Twiz", "0.1.0", members), {
        { name = "Twiz", me = true, version = "0.1.0", mark = "old" },
        { name = "Bad", version = "?", mark = "unknown" },
        { name = "Frostie", version = "0.2.0", mark = "ok" },
        { name = "ginkan", version = "0.1.0", mark = "old" },
        { name = "Newbie", version = "?", mark = "unknown" },
        { name = "Holyboi", version = "?", mark = "unknown" },
      })
      local rows = L.versionRows("Twiz", "0.3.0", members)
      A.eq(rows[1].mark, "ok", "newest is mine")
      A.eq(rows[3].mark, "old")
      A.eq(L.versionRows("Twiz", "0.1.0", {}), { { name = "Twiz", me = true, version = "0.1.0", mark = "ok" } })
    end,

    behind_count = function(ns, A)
      local L = ns.UpdateLogic
      A.eq(L.behind("0.2.0", { { online = true, version = "0.1.0" }, { online = true, version = "0.2.0" },
        { online = false, version = "0.1.0" }, { online = true }, { online = true, version = "0.1.9" } }), 2)
    end,

    -- The update notice (once per new version, badge, panel line).
    update_available = function(ns, A)
      local L = ns.UpdateLogic
      local up = { name = "Frostie", ver = "0.2.0", rs = "0.1.0" }
      A.eq(L.available("0.1.0", up, true), up)
      A.eq(L.available("0.1.0", up, false), nil, "Update reminders off")
      A.eq(L.available("0.2.0", up, true), nil, "on that version")
      A.eq(L.available("0.3.0", up, true), nil, "newer than that")
      A.eq(L.available("0.1.0", nil, true), nil)
      A.eq(L.available("0.1.0", { name = "X", ver = "9|r" }, true), nil, "junk")
      A.eq(L.availableText(up), "Update available: v0.2.0")
      A.eq(L.availableText(up, true), "Update available: v0.2.0 (Frostie has it)")
      A.eq(L.availableText(nil), nil)
    end,

    notice_once_per_version = function(ns, A)
      local L = ns.UpdateLogic
      local up = { name = "Frostie", ver = "0.2.0" }
      local function c(over)
        local t = { myVersion = "0.1.0", enabled = true }
        for k, v in pairs(over or {}) do t[k] = v end
        return t
      end
      A.eq({ L.showNotice(up, c()) }, { true })
      A.eq({ L.showNotice(up, c({ enabled = false })) }, { false, "off" })
      A.eq({ L.showNotice(up, c({ myVersion = "0.2.0" })) }, { false, "not newer" })
      A.eq({ L.showNotice(up, c({ shown = "0.2.0" })) }, { false, "already shown" })
      A.eq({ L.showNotice(up, c({ shown = "0.3.0" })) }, { false, "already shown" })
      A.eq({ L.showNotice(up, c({ shown = "0.1.5" })) }, { true }, "a newer version than the one shown")
      A.eq({ L.showNotice(up, c({ shown = "junk" })) }, { true })
      A.eq({ L.showNotice(up, c({ open = "0.2.0" })) }, { false, "window open" })
      A.eq({ L.showNotice(up, c({ open = "0.1.5" })) }, { true })
      A.eq({ L.showNotice(nil, c()) }, { false, "none" })
      A.eq({ L.showNotice({ name = "X", ver = "1|r" }, c()) }, { false, "none" })
    end,

    notice_texts = function(ns, A)
      local L = ns.UpdateLogic
      local RESTART = "Frostie has it. Close WoW, open WowUp and click Update, then start WoW again."
      local RELOAD = "Frostie has it. Open WowUp and click Update, then press Reload now."
      A.eq(L.notice("Frostie", "0.2.0", "0.1.0", "0.1.0"),
        { title = "Update available: v0.2.0", note = RELOAD, reload = true })
      A.eq(L.notice("Frostie", "0.2.0", "0.1.0", "0.2.0"),
        { title = "Update available: v0.2.0", note = RESTART, reload = false })
      A.eq(L.notice("Frostie", "0.2.0", "0.1.0", nil).reload, false, "older copy, no rs: restart to be safe")
      A.eq(L.notice("Frostie", "0.2.0", "0.1.0", "junk").reload, false)
      A.eq(L.safeRestartSince(nil, "0.2.0"), "0.2.0")
      A.eq(L.safeRestartSince("0.1.0", "0.2.0"), "0.1.0")
    end,

    cooldown = function(ns, A)
      local L = ns.UpdateLogic
      A.eq(L.cooldownLeft(nil, 100, 30), 0)
      A.eq(L.cooldownLeft(100, 110, 30), 20)
      A.eq(L.cooldownLeft(100, 100.2, 30), 30, "rounded up")
      A.eq(L.cooldownLeft(100, 130, 30), 0)
    end,
  },
}
