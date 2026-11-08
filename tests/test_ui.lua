-- Settings window, /tc report, chat commands and Boot (ADDON_LOADED / PLAYER_LOGIN start-up).

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function printedLine(W, text)
  for _, line in ipairs(W.printed) do if line == text then return true end end
  return false
end

local function countPrinted(W, text)
  local n = 0
  for _, line in ipairs(W.printed) do if line == text then n = n + 1 end end
  return n
end

local function has(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end

local function indexOf(list, value)
  for i, v in ipairs(list) do if v == value then return i end end
end

local function receive(W, sender, msgType, fields, ns)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

return {
  files = "toc",
  tests = {
    parse_commands = function(ns, A)
      A.eq({ ns.Commands.parse("  Status  LF Deadmines ") }, { "status", "LF Deadmines" })
      A.eq({ ns.Commands.parse("") }, { "", "" })
      A.eq({ ns.Commands.parse(nil) }, { "", "" })
      A.eq({ ns.Commands.parse("REPORT") }, { "report", "" })
    end,

    slash_registered_without_twiz = function(ns, A, W)
      A.eq(W.env.SLASH_TWIZCREW1, "/tc")
      A.eq(W.env.SLASH_TWIZCREW2, "/twizcrew")
      A.eq(type(W.env.SlashCmdList.TWIZCREW), "function")
      for k, v in pairs(W.env) do
        if type(k) == "string" and k:match("^SLASH_") then A.ok(v ~= "/twiz", k .. " registers /twiz") end
      end
    end,

    status_command_sets_and_clears = function(ns, A, W)
      boot(W)
      tc(W, "status brb food")
      A.eq(ns.db.myStatus, "brb food")
      A.ok(printedLine(W, 'TwizCrew: status set to "brb food"'))
      tc(W, "status")
      A.eq(ns.db.myStatus, "")
      A.ok(printedLine(W, "TwizCrew: status cleared"))
    end,

    hide_show_panel = function(ns, A, W)
      boot(W)
      A.ok(ns.Modules.isEnabled("panel"))
      tc(W, "hide")
      A.no(ns.Modules.isEnabled("panel"))
      tc(W, "show")
      A.ok(ns.Modules.isEnabled("panel"))
    end,

    add_and_remove_names = function(ns, A, W)
      boot(W)
      tc(W, "add   frostie ")
      tc(W, "add Holybøi")
      tc(W, "add frostie")   -- already there
      tc(W, "add twiz")      -- yourself
      tc(W, "add    ")       -- empty
      A.eq(ns.db.crew.extra, { "Frostie", "Holybøi" })
      tc(W, "remove FROSTIE")
      A.eq(ns.db.crew.extra, { "Holybøi" })
      A.eq(ns.Log.errors(10), {})
    end,

    debug_toggles = function(ns, A, W)
      boot(W)
      tc(W, "debug")
      A.eq(ns.Modules.setting("comm", "debug"), true)
      A.ok(ns.Log.chatDebug)
      tc(W, "debug")
      A.eq(ns.Modules.setting("comm", "debug"), false)
      A.no(ns.Log.chatDebug)
    end,

    help_lists_commands = function(ns, A, W)
      boot(W)
      local before = #W.printed
      tc(W, "help")
      local helpLines = #W.printed - before
      A.ok(helpLines >= 8, "help should list the commands")
      local text = table.concat(W.printed, "\n")
      for _, cmd in ipairs({ "/tc show", "/tc hide", "/tc status", "/tc reset", "/tc report", "/tc debug",
        "/tc add", "/tc remove" }) do
        A.contains(text, cmd)
      end
      tc(W, "fly me to the moon")
      A.eq(#W.printed - before, 2 * helpLines, "an unknown command shows the same help")
    end,

    slash_empty_toggles_settings = function(ns, A, W)
      boot(W)
      A.no(ns.Settings.isOpen())
      tc(W, "")
      A.ok(ns.Settings.isOpen())
      tc(W, "")
      A.no(ns.Settings.isOpen())
    end,

    reset_command_asks_first = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "scale", 1.5)
      tc(W, "reset")
      A.ok(ns.Settings.isOpen())
      A.ok(ns.Settings.isConfirming())
      A.eq(ns.Modules.setting("panel", "scale"), 1.5, "nothing is reset before Yes")
      ns.Settings.answerReset(false)
      A.no(ns.Settings.isConfirming())
      A.eq(ns.Modules.setting("panel", "scale"), 1.5)
    end,

    report_lines_cover_health = function(ns, A, W)
      boot(W)
      local lines = ns.Report.lines()
      A.eq(lines[1], "TwizCrew v0.1.0, interface 16001")
      local text = table.concat(lines, "\n")
      A.contains(text, "Connection:")
      A.contains(text, "Layer:")
      A.contains(text, "Class icons:")
      A.contains(text, "Turned off after errors: none")
      A.contains(text, "Recent errors:")
      A.eq(lines[2], "Connection: auto (channel TwizCrewHQ joined)")
      A.eq(lines[3], "Layer: key none, seen never, 0 hidden values skipped")
      A.eq(lines[4], "Class icons: none")
      A.eq(lines[5], "Turned off after errors: none")
      local e = indexOf(lines, "Recent errors:")
      A.eq(lines[e + 1], "none")
    end,

    report_lists_crew_layer_and_errors = function(ns, A, W)
      boot(W)
      W.state.guids.mouseover = "Creature-0-1-0-111-299-01"
      W:fire("UPDATE_MOUSEOVER_UNIT"); W:fire("UPDATE_MOUSEOVER_UNIT")
      receive(W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", ver = "0.1.0" }, ns)
      W:advance(120)
      ns.Log.add("error", "panel: something broke")
      ns.Modules.markBroken("popups")
      local lines = ns.Report.lines()
      A.eq(lines[3], "Layer: key 111, seen 2m ago, 0 hidden values skipped")
      A.eq(lines[5], "Turned off after errors: popups")
      A.ok(has(lines, "Frostie: online, heard 2m ago, v0.1.0"))
      local e = indexOf(lines, "Recent errors:")
      A.ok(lines[e + 1]:find("panel: something broke", 1, true))
      ns.Report.show()
      A.eq(ns.Log.errors(10), { lines[e + 1] }, "show() adds no errors")
    end,

    report_counts_echoes_and_never_shows_the_code = function(ns, A, W)
      boot(W)
      ns.Settings.save("comm", "password", "murloc")
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "CHANNEL", "Twiz-Realm")
      local lines = ns.Report.lines()
      A.eq(lines[#lines], "Channel echoes heard: 1")
      local text = table.concat(lines, "\n")
      A.no(text:find("murloc", 1, true), "the crew code is not in the report")
      A.no(text:find("goldshire", 1, true), "the old crew code is not in the report")
    end,

    crew_code_box_hides_its_letters = function(ns, A, W)
      local hidden = {}
      local create = W.env.CreateFrame
      W.env.CreateFrame = function(...)
        local f = create(...)
        rawset(f, "SetPassword", function(self, on) hidden[#hidden + 1] = on end)
        return f
      end
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced")
      A.eq(hidden, { true }, "only the crew code box hides what is typed")
      A.eq(ns.Log.errors(10), {})
    end,

    report_channel_failure_reason = function(ns, A, W)
      boot(W, function() W.state.channelJoinFails = true end)
      W:advance(20)
      local lines = ns.Report.lines()
      A.eq(lines[2], "Connection: auto (channel TwizCrewHQ failed: the channel did not join in time; down for 11 s)")
    end,

    report_says_when_and_why_the_channel_is_down_and_when_it_is_tried_again = function(ns, A, W)
      boot(W)
      W:advance(10)
      W.state.channelSendResult = 7 -- every channel send refused from now on
      for _ = 1, 3 do ns.Comm.send("PING", {}) end
      W:advance(1)
      W:advance(30)
      A.eq(ns.Report.lines()[2], "Connection: auto (channel TwizCrewHQ failed: sends to the channel were refused "
        .. "(result 7); down for 31 s; using whispers, next try in 30 s)")
      W.state.inGroup = true
      W:advance(110)
      A.contains(ns.Report.lines()[2], "down for 2 min; using group chat and whispers, next try in")
    end,

    settings_builds_and_resets_without_errors = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced")
      A.ok(ns.Settings.isOpen())
      ns.Modules.set("panel", "scale", 1.5)
      ns.Settings.confirmReset()
      A.ok(ns.Settings.isConfirming())
      ns.Settings.answerReset(true)
      A.eq(ns.Modules.setting("panel", "scale"), 1)
      A.no(ns.Settings.isConfirming())
      A.eq(ns.Log.errors(10), {})
    end,

    settings_opens_on_a_short_basics_tab = function(ns, A, W)
      boot(W)
      ns.Settings.open()
      A.eq(ns.Settings.tab(), "basic")
      local d = ns.Settings.describeForTest()
      A.ok(has(d, "setting:panel:bgAlpha"), "transparency")
      A.ok(has(d, "setting:panel:scale"))
      A.ok(has(d, "module:panel:switch"))
      A.ok(has(d, "module:popups:switch"))
      A.ok(has(d, "setting:tags:autoAway"))
      A.ok(has(d, "child:tags:awayMinutes"))
      A.ok(has(d, "setting:minimap:show"))
      A.ok(has(d, "note:advanced"))
      A.ok(has(d, "setting:find:rowArrows"), "Find the crew: row arrows")
      A.ok(has(d, "setting:find:meetups"))
      A.ok(has(d, "setting:find:sharePosition"))
      A.no(has(d, "setting:comm:channel"), "no crew channel setup on Basics")
      A.no(has(d, "section:Essentials"))
      A.ok(#d <= 20, "short: " .. #d .. " rows")
      ns.Settings.setTab("advanced")
      d = ns.Settings.describeForTest()
      A.ok(has(d, "setting:comm:channel"), "Advanced has everything")
      ns.Settings.setTab("basic")
      A.no(has(ns.Settings.describeForTest(), "setting:comm:channel"))
      A.eq(ns.Log.errors(10), {})
    end,

    settings_layout_follows_registry = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced")
      local d = ns.Settings.describeForTest()
      local ess, mods, ext = indexOf(d, "section:Essentials"), indexOf(d, "section:Modules"), indexOf(d, "section:Extras")
      A.ok(ess and mods and ext and ess < mods and mods < ext, "sections in order")
      A.ok(has(d, "module:comm:always on"))
      A.ok(has(d, "module:version:always on"))
      A.ok(has(d, "setting:comm:transport"))
      A.ok(has(d, "setting:comm:channel"))
      A.ok(has(d, "module:panel:switch"))
      A.ok(has(d, "setting:panel:scale"))
      A.ok(has(d, "child:panel:fadeAlpha"), "a setting with a parent is indented")
      A.ok(has(d, "module:popups:switch"))
      A.ok(has(d, "module:pokes:coming later"))
      A.ok(has(d, "module:races:coming later"))
      A.ok(indexOf(d, "module:comm:always on") < mods and indexOf(d, "module:panel:switch") > mods)
      A.ok(indexOf(d, "module:pokes:coming later") > ext)
    end,

    settings_shows_broken_module = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced")
      ns.Modules.markBroken("popups")
      local d = ns.Settings.describeForTest()
      A.ok(has(d, "module:popups:broken"), "rebuilt while open")
      A.no(has(d, "module:popups:switch"))
      A.eq(ns.Settings.BROKEN_TEXT, "turned off after errors, /reload to try again")
    end,

    settings_rebuilds_lazily_when_closed = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced")
      ns.Settings.close()
      local before = ns.Settings.layoutCountForTest()
      ns.Modules.setEnabled("panel", false)
      ns.Modules.setEnabled("panel", true)
      ns.Modules.resetAll()
      A.eq(ns.Settings.layoutCountForTest(), before, "no rebuild while closed")
      ns.Settings.open(); ns.Settings.setTab("advanced")
      A.eq(ns.Settings.layoutCountForTest(), before + 1, "one rebuild on the next open")
    end,

    crew_text_settings_save_trimmed_and_rejoin = function(ns, A, W)
      boot(W)
      local joins = {}
      local join = W.env.JoinChannelByName
      W.env.JoinChannelByName = function(name, pw) joins[#joins + 1] = name; join(name, pw) end
      A.ok(ns.Settings.save("comm", "channel", "  CrewTwo "))
      A.eq(ns.db.crew.channel, "CrewTwo")
      W:advance(3) -- leave, then join again after a short wait
      A.eq(joins, { "CrewTwo" }, "rejoined once")
      A.no(ns.Settings.save("comm", "channel", "   "), "a blank channel is refused")
      A.eq(ns.db.crew.channel, "CrewTwo")
      A.no(ns.Settings.save("comm", "channel", "CrewTwo"), "same value: nothing to do")
      A.eq(#joins, 1)
      A.ok(ns.Settings.save("comm", "password", "murloc"))
      A.eq(ns.db.crew.password, "murloc")
      W:advance(3)
      A.eq(#joins, 2)
    end,

    options_entry_registered = function(ns, A, W)
      boot(W)
      A.eq(#W.addOnCategories, 1)
      A.eq(W.addOnCategories[1].name, "TwizCrew")
    end,

    missing_settings_api_is_logged_not_fatal = function(ns, A, W)
      W.state.noSettingsAPI = true
      boot(W)
      A.ok(printedLine(W, "TwizCrew v0.1.0 loaded. Type /tc for settings."), "start-up completed")
      local found = false
      for _, line in ipairs(ns.Log.lines()) do
        if (line:find("WARN", 1, true) or line:find("ERROR", 1, true)) and line:find("settings", 1, true) then
          found = true
        end
      end
      A.ok(found, "a warn line mentions settings")
      A.eq(#W.addOnCategories, 0)
    end,

    login_line_printed = function(ns, A, W)
      boot(W)
      W:fire("PLAYER_LOGIN")
      A.eq(countPrinted(W, "TwizCrew v0.1.0 loaded. Type /tc for settings."), 1)
    end,

    boot_wires_saved_data = function(ns, A, W)
      W.env.TwizCrewDB = { myStatus = "hi", modules = { panel = { enabled = false } } }
      boot(W)
      A.eq(W.env.TwizCrewDB, ns.db, "saved data is the live table")
      A.eq(ns.db.myStatus, "hi")
      A.no(ns.Modules.isEnabled("panel"))
      A.eq(W.state.prefix, "TwizCrew")
      A.ok(#ns.db.log > 0, "log lines go into the saved data")
      W:fire("ADDON_LOADED", "SomeOtherAddon")
      A.eq(W.env.TwizCrewDB, ns.db)
    end,

    -- stats Task 9: new commands and report lines
    session_new_command = function(ns, A, W)
      boot(W)
      W:advance(20)
      local mark = #W.sent
      tc(W, "session new")
      local cur = ns.Session.current()
      A.ok(cur and cur.manual, "a hand-started session")
      A.ok(printedLine(W, "TwizCrew: new session started. Everyone's session stats start from 0."))
      W:advance(3)
      local found = false
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "UPDATE" and msg.fields.sid == cur.id then found = true end
      end
      A.ok(found, "an UPDATE with the new session")
      for _, line in ipairs(W.printed) do A.no(line:find(cur.id, 1, true), "no session id in chat") end
    end,

    stats_reset_asks_first = function(ns, A, W)
      boot(W)
      W:advance(20)
      ns.Stats.count("dt", 3)
      tc(W, "stats reset")
      A.eq(ns.StatsStore.get("session", "dt"), 3, "nothing reset before yes")
      A.eq(ns.StatsStore.get("all", "dt"), 3)
      A.ok(printedLine(W, "TwizCrew: this sets all your own stats (this session and all time) back to 0. "
        .. "Type /tc stats reset yes to do it."))
      local mark = #W.sent
      tc(W, "stats reset yes")
      A.eq(ns.StatsStore.get("session", "dt"), 0)
      A.eq(ns.StatsStore.get("all", "dt"), 0)
      A.ok(printedLine(W, "TwizCrew: your stats are back to 0."))
      W:advance(1)
      local sent = 0
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "STATS" then sent = sent + 1 end
      end
      A.ok(sent >= 1, "friends get the zeros")
    end,

    awards_command_opens_show = function(ns, A, W)
      boot(W)
      W:advance(20)
      tc(W, "awards")
      A.ok(ns.AwardsShow.isOpen())
      ns.AwardsShow.close()
      A.no(ns.AwardsShow.isOpen())
      tc(W, "awards all")
      A.ok(ns.AwardsShow.isOpen())
      W:advance(5)
      A.eq(ns.Log.errors(10), {})
    end,

    help_lists_new_commands = function(ns, A, W)
      boot(W)
      tc(W, "help")
      local text = table.concat(W.printed, "\n")
      for _, cmd in ipairs({ "/tc awards", "/tc awards all", "/tc session new", "/tc stats reset" }) do
        A.contains(text, cmd)
      end
    end,

    report_has_stats_lines = function(ns, A, W)
      boot(W)
      local lines = ns.Report.lines()
      A.eq(lines[6], "Stats: on, steps by speed, detectors off: none")
      A.eq(lines[7], "Session: not decided yet")
      A.eq(lines[8], "Stats sent never, heard never")
      W:advance(20)
      receive(W, "Frostie", "STATS", { sid = ns.Session.current().id, q = "1", s_dt = "1" }, ns)
      W:advance(120)
      lines = ns.Report.lines()
      local cur = ns.Session.current()
      A.eq(lines[7], "Session: " .. cur.id .. " started " .. ns.BoardLogic.timeText(cur.start) .. " (automatic)")
      A.eq(lines[8], "Stats sent 2m ago, heard 2m ago from Frostie")
      A.eq(lines[5], "Turned off after errors: none", "v1 lines stay where they were")
      W.state.missing.JumpOrAscendStart = true
      ns.Modules.setEnabled("stats", false)
      lines = ns.Report.lines()
      A.eq(lines[6]:sub(1, 12), "Stats: off, ")
    end,
  },
}
