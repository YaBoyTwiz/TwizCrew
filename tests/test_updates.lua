-- "Tell crew to update": the button, the request, the pop-up window, fights, the line after a reload,
-- the version list in the settings window and the module switch.

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function receive(W, sender, msgType, fields, ns)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- Frostie is in the crew (heard a STATE) with version `ver`.
local function friend(W, ns, name, ver)
  receive(W, name, "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", ver = ver }, ns)
end

local function ask(W, ns, name, ver, rs)
  receive(W, name, "UPDREQ", { ver = ver, rs = rs }, ns)
end

local function count(W, text)
  local n = 0
  for _, line in ipairs(W.printed) do if line == text then n = n + 1 end end
  return n
end

local function sentOfType(W, msgType)
  local out = {}
  for _, m in ipairs(W.sent) do
    if m.text:match("^%d+%^(%u+)%^") == msgType then out[#out + 1] = m end
  end
  return out
end

local function click(b) b._scripts.OnClick(b, "LeftButton") end

local function has(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end

-- Frostie is in the crew with version `ver` and RESTART_SINCE `rs` (nil = an older copy that sends none).
local function newerFriend(W, ns, name, ver, rs)
  receive(W, name, "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", ver = ver, rs = rs }, ns)
end

local NOTICE_RELOAD = "Frostie has it. Open WowUp and click Update, then press Reload now."
local NOTICE_RESTART = "Frostie has it. Close WoW, open WowUp and click Update, then start WoW again."

local RELOAD_NOTE = "If nothing changed, open WowUp and click Update first"
local STILL_OLD = "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then /reload"

return {
  files = "toc",
  tests = {
    registered_where_the_registry_says = function(ns, A)
      local d = ns.Modules.get("updates")
      A.ok(d); A.eq(d.name, "Update reminders"); A.eq(d.tier, "module"); A.eq(d.defaultEnabled, true)
      A.ok(#d.info > 20)
      local v = ns.Modules.get("version")
      local kinds = {}
      for _, s in ipairs(v.settings) do kinds[s.key] = s.kind; A.ok(#s.info > 20, s.key .. " has an info text") end
      A.eq(kinds.tellCrew, "button")
      A.eq(kinds.versions, "list")
    end,

    button_sends_request_with_cooldown = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.0.9")
      W.sent = {}
      A.ok(ns.Updates.tellCrew())
      W:advance(1)
      local sent = sentOfType(W, "UPDREQ")
      A.eq(#sent, 1)
      A.eq(ns.Codec.decode(sent[1].text).fields, { ver = "0.1.0", rs = "0.1.0" })
      A.eq(count(W, "TwizCrew: told your crew that v0.1.0 is out. 1 friend online is on an older version."), 1)
      W:advance(10)
      A.no(ns.Updates.tellCrew(), "cooling down")
      A.eq(count(W, "TwizCrew: already sent. You can send it again in 19 s."), 1)
      W:advance(1)
      A.eq(#sentOfType(W, "UPDREQ"), 1)
      W:advance(20)
      A.ok(ns.Updates.tellCrew())
      W:advance(1)
      A.eq(#sentOfType(W, "UPDREQ"), 2)
      A.eq(ns.Log.errors(10), {})
    end,

    button_works_from_the_settings_row = function(ns, A, W)
      boot(W)
      W.sent = {}
      ns.Settings.open()
      local b = ns.Settings.rowForTest("version", "tellCrew").button
      click(b)
      W:advance(1)
      A.eq(#sentOfType(W, "UPDREQ"), 1)
      A.eq(count(W, "TwizCrew: told your crew that v0.1.0 is out. Nobody online is known to be on an older version."), 1)
    end,

    request_from_newer_friend_shows_reload = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest(), { title = "Frostie says v0.2.0 is out", note = RELOAD_NOTE, reload = true })
      A.eq(ns.db.update.told, "0.2.0")
      A.eq(ns.db.update.by, "Frostie")
      A.eq(ns.db.update.rs, "0.1.0")
      local reloads = 0
      W.env.ReloadUI = function() reloads = reloads + 1 end
      click(ns.Updates.reloadButtonForTest())
      A.eq(reloads, 1)
      A.eq(ns.Log.errors(10), {})
    end,

    restart_needed_has_no_reload_button = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.3.0")
      ask(W, ns, "Frostie", "0.3.0", "0.3.0")
      A.eq(ns.Updates.promptForTest(), { title = "Frostie says v0.3.0 is out",
        note = "Close and restart the game to load it", reload = false })
      local reloads = 0
      W.env.ReloadUI = function() reloads = reloads + 1 end
      local b = ns.Updates.reloadButtonForTest()
      if b then click(b) end
      A.eq(reloads, 0, "no reload when a restart is needed")
    end,

    names_are_shown_as_plain_text = function(ns, A, W)
      boot(W)
      friend(W, ns, "Bad|cffff0000", "0.2.0")
      ask(W, ns, "Bad|cffff0000", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest().title, "Bad||cffff0000 says v0.2.0 is out")
    end,

    reload_is_refused_in_a_fight = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      local reloads = 0
      W.env.ReloadUI = function() reloads = reloads + 1 end
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      click(ns.Updates.reloadButtonForTest())
      A.eq(reloads, 0)
      A.eq(count(W, "TwizCrew: not during a fight. Click Reload now again when the fight is over."), 1)
      W.env.InCombatLockdown = function() return true end
      W.state.combat = false
      click(ns.Updates.reloadButtonForTest())
      A.eq(reloads, 0, "combat lockdown also refuses")
      W.env.InCombatLockdown = function() return false end
      W:fire("PLAYER_REGEN_ENABLED")
      click(ns.Updates.reloadButtonForTest())
      A.eq(reloads, 1)
    end,

    request_in_a_fight_waits_for_the_end = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.2.0")
      W.state.combat = true
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest(), nil)
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.2.0 is out")
    end,

    ignored_requests = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.1.0")
      ask(W, ns, "Frostie", "0.1.0", "0.1.0")
      A.eq(ns.Updates.promptForTest(), nil, "same version")
      ask(W, ns, "Frostie", "0.0.5", "0.0.1")
      A.eq(ns.Updates.promptForTest(), nil, "older")
      ask(W, ns, "Stranger", "0.9.0", "0.1.0")
      A.eq(ns.Updates.promptForTest(), nil, "not in the crew list")
      ask(W, ns, "Frostie", "junk", "0.1.0")
      A.eq(ns.Updates.promptForTest(), nil, "junk version")
      A.eq(ns.db.update, {})
      A.eq(ns.Log.errors(10), {})
    end,

    same_version_again_is_ignored_for_a_while = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.2.0")
      friend(W, ns, "Ginkan", "0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      ns.Updates.closeForTest()
      A.eq(ns.Updates.promptForTest(), nil)
      W:advance(60)
      ask(W, ns, "Ginkan", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest(), nil, "repeat of the same version")
      ask(W, ns, "Ginkan", "0.2.1", "0.1.0")
      A.eq(ns.Updates.promptForTest().title, "Ginkan says v0.2.1 is out", "a newer one shows")
      ns.Updates.closeForTest()
      W:advance(600)
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.2.0 is out", "after 10 minutes")
      A.eq(ns.db.update.told, "0.2.1", "the newest one is remembered")
    end,

    an_older_request_does_not_replace_a_newer_window = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.3.0")
      friend(W, ns, "Ginkan", "0.2.0")
      ask(W, ns, "Frostie", "0.3.0", "0.1.0")
      ask(W, ns, "Ginkan", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.3.0 is out")
    end,

    module_off_ignores_requests_and_hides_the_window = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.ok(ns.Updates.promptForTest())
      ns.Modules.setEnabled("updates", false)
      A.eq(ns.Updates.promptForTest(), nil, "hidden")
      ask(W, ns, "Frostie", "0.2.5", "0.1.0")
      A.eq(ns.Updates.promptForTest(), nil, "ignored while off")
      ns.Modules.resetAll()
      A.ok(ns.Modules.isEnabled("updates"), "reset to defaults turns update reminders back on")
      ask(W, ns, "Frostie", "0.2.6", "0.1.0")
      A.ok(ns.Updates.promptForTest())
      A.eq(ns.Log.errors(10), {})
    end,

    line_after_reload_when_still_old = function(ns, A, W)
      W.env.TwizCrewDB = { update = { told = "0.2.0", by = "Frostie", rs = "0.1.0", at = 1 } }
      boot(W)
      A.eq(count(W, STILL_OLD), 1)
      A.eq(ns.db.update, {}, "said once, then forgotten")
    end,

    line_after_reload_says_restart_when_needed = function(ns, A, W)
      W.env.TwizCrewDB = { update = { told = "0.3.0", rs = "0.3.0" } }
      boot(W)
      A.eq(count(W, "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then restart the game"), 1)
    end,

    no_line_when_updated_or_off = function(ns, A, W)
      W.env.TwizCrewDB = { update = { told = "0.1.0" } }
      boot(W)
      for _, line in ipairs(W.printed) do A.no(line:find("Still on", 1, true), line) end
      A.eq(ns.db.update, {})
    end,

    no_line_when_reminders_are_off = function(ns, A, W)
      W.env.TwizCrewDB = { update = { told = "0.2.0" }, modules = { updates = { enabled = false } } }
      boot(W)
      for _, line in ipairs(W.printed) do A.no(line:find("Still on", 1, true), line) end
    end,

    a_request_at_login_is_not_mixed_up_with_the_old_one = function(ns, A, W)
      W.env.TwizCrewDB = { update = { told = "0.1.0" } }
      W:fire("ADDON_LOADED", "TwizCrew")
      W:fire("PLAYER_LOGIN")
      W:fire("PLAYER_ENTERING_WORLD")
      friend(W, ns, "Frostie", "0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(6)
      A.ok(ns.Updates.promptForTest(), "the window shows")
      for _, line in ipairs(W.printed) do A.no(line:find("Still on", 1, true), "no 'still on' line right away") end
      A.eq(ns.db.update.told, "0.2.0", "kept for the next login")
    end,

    old_game_file_list_says_restart = function(ns, A, W)
      ns.TOC_VERSION = "0.0.9"
      boot(W)
      A.eq(count(W, "TwizCrew: TwizCrew v0.1.0 added new files. Close and restart the game to finish the update."),
        1)
    end,

    settings_window_lists_versions = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.2.0")
      friend(W, ns, "Ginkan", "0.1.0")
      ns.Settings.open()
      local d = ns.Settings.describeForTest()
      A.ok(has(d, "setting:version:tellCrew"))
      A.ok(has(d, "setting:version:versions"))
      local OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
      local OLD = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"
      A.eq(ns.Version.lines(), {
        OLD .. " Twiz (you)  v0.1.0",
        OK .. " Frostie  v0.2.0",
        OLD .. " Ginkan  v0.1.0",
      })
      A.eq(ns.Settings.rowForTest("version", "versions").shownLines, ns.Version.lines())
      receive(W, "Frostie", "BYE", {}, ns)
      A.eq(ns.Settings.rowForTest("version", "versions").shownLines[3], "    Frostie  ?",
        "offline: ? (redrawn while the window is open)")
      friend(W, ns, "Newbie", "0.1.0")
      A.eq(#ns.Settings.rowForTest("version", "versions").shownLines, 4, "a new friend gets a line")
      A.eq(ns.Log.errors(10), {})
    end,

    versions_list_relaid_after_reopening = function(ns, A, W)
      boot(W)
      ns.Settings.open()
      ns.Settings.close()
      local before = ns.Settings.layoutCountForTest()
      friend(W, ns, "Frostie", "0.1.0")
      friend(W, ns, "Ginkan", "0.0.9")
      ns.Settings.open()
      A.eq(ns.Settings.layoutCountForTest(), before + 1, "laid out again: the list grew while closed")
      A.eq(#ns.Settings.rowForTest("version", "versions").shownLines, 3)
    end,

    stranger_request_does_not_touch_the_version_check = function(ns, A, W)
      boot(W)
      ask(W, ns, "Stranger", "9.9.9", "0.1.0")
      A.eq(ns.Version.summary(), "everyone up to date")
      for _, line in ipairs(W.printed) do A.no(line:find("9.9.9", 1, true), line) end
    end,

    older_request_in_a_fight_does_not_replace_a_newer_one = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie", "0.3.0")
      friend(W, ns, "Ginkan", "0.2.0")
      W.state.combat = true
      ask(W, ns, "Frostie", "0.3.0", "0.1.0")
      ask(W, ns, "Ginkan", "0.2.0", "0.1.0")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.3.0 is out")
    end,

    ---------------------------------------------------------------------------------------- update notice
    notice_shows_once_after_a_short_wait = function(ns, A, W)
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.eq(ns.Updates.available(), { name = "Frostie", ver = "0.2.0", rs = "0.1.0" })
      W:advance(29)
      A.eq(ns.Updates.promptForTest(), nil, "waits, so Tell crew to update can win")
      W:advance(2)
      A.eq(ns.Updates.promptForTest(), { title = "Update available: v0.2.0", note = NOTICE_RELOAD, reload = true })
      A.eq(ns.db.updateNotice.shown, "0.2.0", "saved: once per version")
      A.eq(ns.db.update.told, "0.2.0", "remembered for the line after a reload")
      A.eq(ns.db.update.rs, "0.1.0")
      local reloads = 0
      W.env.ReloadUI = function() reloads = reloads + 1 end
      click(ns.Updates.reloadButtonForTest())
      A.eq(reloads, 1)
      ns.Updates.closeForTest()
      newerFriend(W, ns, "Ginkan", "0.2.0", "0.1.0")
      W:advance(61)
      A.eq(ns.Updates.promptForTest(), nil, "the same version never pops up again")
      A.ok(ns.Updates.available(), "but the update is still known (badge, panel line)")
      A.eq(ns.Log.errors(10), {})
    end,

    notice_says_restart_when_needed_or_unknown = function(ns, A, W)
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.2.0")
      W:advance(31)
      A.eq(ns.Updates.promptForTest(), { title = "Update available: v0.2.0", note = NOTICE_RESTART, reload = false })
      ns.Updates.closeForTest()
      receive(W, "Frostie", "HELLO", { ver = "0.3.0" }, ns) -- an older-style copy that sends no rs
      newerFriend(W, ns, "Frostie", "0.3.0", nil)
      W:advance(31)
      A.eq(ns.Updates.promptForTest(), { title = "Update available: v0.3.0", note = NOTICE_RESTART, reload = false })
      A.eq(ns.db.update.rs, "0.3.0", "unknown counts as restart for the line after a reload too")
      local reloads = 0
      W.env.ReloadUI = function() reloads = reloads + 1 end
      click(ns.Updates.reloadButtonForTest())
      A.eq(reloads, 0, "no reload when a restart is needed")
    end,

    notice_not_again_after_a_reload = function(ns, A, W)
      W.env.TwizCrewDB = { updateNotice = { shown = "0.2.0" } }
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(31)
      A.eq(ns.Updates.promptForTest(), nil)
      A.ok(ns.Updates.available())
      newerFriend(W, ns, "Frostie", "0.2.1", "0.1.0")
      W:advance(31)
      A.eq(ns.Updates.promptForTest().title, "Update available: v0.2.1", "a newer version shows again")
    end,

    notice_follows_update_reminders = function(ns, A, W)
      W.env.TwizCrewDB = { modules = { updates = { enabled = false } } }
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(31)
      A.eq(ns.Updates.promptForTest(), nil, "off: no pop-up")
      A.eq(ns.Updates.available(), nil, "off: no badge, no panel line")
      A.eq(ns.Updates.showHowTo(), false)
      ns.Modules.setEnabled("updates", true)
      A.ok(ns.Updates.available())
      W:advance(31)
      A.eq(ns.Updates.promptForTest().title, "Update available: v0.2.0", "turned on: the pop-up comes")
    end,

    tell_crew_wins_over_the_notice = function(ns, A, W)
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(5)
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.2.0 is out")
      A.eq(ns.db.updateNotice.shown, "0.2.0", "the request counts as shown")
      W:advance(31)
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.2.0 is out", "no notice on top")
      ns.Updates.closeForTest()
      W:advance(31)
      A.eq(ns.Updates.promptForTest(), nil)
    end,

    tell_crew_takes_over_an_open_notice = function(ns, A, W)
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.2.0")
      W:advance(31)
      A.eq(ns.Updates.promptForTest().title, "Update available: v0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.2.0")
      A.eq(ns.Updates.promptForTest(), { title = "Frostie says v0.2.0 is out",
        note = "Close and restart the game to load it", reload = false }, "same window, Tell crew words")
    end,

    tell_crew_still_works_after_the_notice_was_closed = function(ns, A, W)
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(31)
      ns.Updates.closeForTest()
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      A.eq(ns.Updates.promptForTest().title, "Frostie says v0.2.0 is out", "as before")
    end,

    notice_in_a_fight_waits_for_the_end = function(ns, A, W)
      boot(W)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W.state.combat = true
      W:advance(31)
      A.eq(ns.Updates.promptForTest(), nil)
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.eq(ns.Updates.promptForTest().title, "Update available: v0.2.0")
    end,

    how_to_window_on_demand = function(ns, A, W)
      boot(W)
      A.eq(ns.Updates.showHowTo(), false, "nothing to update")
      A.eq(ns.Updates.promptForTest(), nil)
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(31)
      ns.Updates.closeForTest()
      A.eq(ns.Updates.showHowTo(), true, "again, even after the once-only pop-up")
      A.eq(ns.Updates.promptForTest(), { title = "Update available: v0.2.0", note = NOTICE_RELOAD, reload = true })
    end,

    a_broken_notice_never_breaks_comms = function(ns, A, W)
      boot(W)
      ns.UpdateLogic.showNotice = function() error("boom") end
      newerFriend(W, ns, "Frostie", "0.2.0", "0.1.0")
      W:advance(31)
      A.ok(ns.roster:get("Frostie").online, "the friend still arrived")
      A.eq(ns.Updates.promptForTest(), nil)
      local errors = ns.Log.errors(10)
      A.ok(#errors >= 1, "logged")
      for _, e in ipairs(errors) do A.contains(e, "ERROR updates: ", "charged to Update reminders only") end
    end,

    report_says_versions = function(ns, A, W)
      boot(W)
      ns.TOC_VERSION = "0.0.9"
      local found
      for _, line in ipairs(ns.Report.lines()) do
        if line:find("^Update: ") then found = line end
      end
      A.eq(found, "Update: addon list says v0.0.9, restart needed since v0.1.0, last request heard: none, "
        .. "newest heard: none, pop-up shown for: none")
      friend(W, ns, "Frostie", "0.2.0")
      ask(W, ns, "Frostie", "0.2.0", "0.1.0")
      for _, line in ipairs(ns.Report.lines()) do
        if line:find("^Update: ") then found = line end
      end
      A.contains(found, "last request heard: v0.2.0 from Frostie")
      A.contains(found, "newest heard: v0.2.0 from Frostie (restart since v0.1.0), pop-up shown for: v0.2.0")
    end,
  },
}
