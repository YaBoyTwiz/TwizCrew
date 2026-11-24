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
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
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

    -- Only guild members are friends now, so there is no list of names to whisper: /tc add is gone (it shows the help)
    -- and /tc remove is another name for /tc forget.
    add_is_gone_and_remove_forgets = function(ns, A, W)
      boot(W)
      W.printed = {}
      tc(W, "add frostie")
      A.ok(printedLine(W, "TwizCrew commands:"), "an unknown command shows the help")
      A.eq(ns.db.crew, nil)
      for _, line in ipairs(W.printed) do A.no(line:find("/tc add", 1, true), line) end
      ns.db.roster.Frostie = { name = "Frostie", level = 5, lastSeen = ns.wallclock() }
      ns.roster = ns.Roster.new(ns.db.roster)
      tc(W, "remove FROSTIE")
      A.eq(ns.roster:get("Frostie"), nil)
      A.eq(ns.Log.errors(10), {})
    end,

    forget_command_drops_an_offline_friend = function(ns, A, W)
      boot(W)
      ns.db.roster.Frostie = { name = "Frostie", level = 5, lastSeen = ns.wallclock() }
      ns.roster = ns.Roster.new(ns.db.roster)
      tc(W, "forget frostie")
      A.eq(ns.roster:get("Frostie"), nil)
      A.eq(ns.db.roster.Frostie, nil)
      ns.roster:apply("Ginkan", {}, 1, 1)
      tc(W, "forget Ginkan")
      A.ok(ns.roster:get("Ginkan"), "online: kept")
      tc(W, "forget twiz")
      A.eq(ns.Log.errors(10), {})
    end,

    -- /tc forget matches, any case: a member's full name, a member's key, a saved row's name (hidden rows too), and
    -- only then a first word one row or member has; several: "which one?" with the names.
    tc_forget_accepts_first_word_or_full_name = function(ns, A, W)
      local list = {}
      for i, name in ipairs({ "Twiz", "Ginkan Pebble", "Lurabe Moon", "Chaos Deathbringr", "Chaos Other", "Frost Bite",
        "Frost Nova", "Pewpew Zed" }) do
        list[i] = { name = name, online = i == 1, guid = string.format("Player-1-%04d", i), lastOnline = { 0, 0, 1, 0 } }
      end
      W.state.guild = { name = "Test Guild", members = list }
      W.env.TwizCrewDB = { guild = { name = "Test Guild", keys = { ["chaos deathbringr"] = "Chaos",
        ["lurabe sun"] = "Lurabe", ["frost old"] = "Frost" } }, roster = {} }
      for _, key in ipairs({ "Ginkan", "Lurabe", "Lurabe Moon", "Chaos", "Chaos Other", "Frost Bite", "Frost Nova",
        "Pewpew" }) do
        W.env.TwizCrewDB.roster[key] = { name = key, level = 5 }
      end
      boot(W)
      A.ok(ns.roster:isHidden("Lurabe"), "the departed Lurabe Sun's row is hidden")
      tc(W, "forget ginkan pebble")
      A.eq(ns.db.roster.Ginkan, nil, "full name")
      A.ok(printedLine(W, "TwizCrew: forgot Ginkan."))
      tc(W, "forget lurabe")
      A.eq(ns.db.roster.Lurabe, nil, "the saved row of that name (hidden), not Lurabe Moon")
      A.ok(ns.db.roster["Lurabe Moon"])
      tc(W, "forget LURABE")
      A.eq(ns.db.roster["Lurabe Moon"], nil, "now the first word only Lurabe Moon has")
      tc(W, "forget chaos")
      A.eq(ns.db.roster.Chaos, nil, "an exact key: its holder")
      A.ok(ns.db.roster["Chaos Other"])
      W.printed = {}
      tc(W, "forget frost")
      A.ok(ns.db.roster["Frost Bite"] and ns.db.roster["Frost Nova"], "two start with it: nobody")
      A.ok(printedLine(W, "TwizCrew: which one? Frost Bite, Frost Nova. Type the full name."))
      tc(W, "forget pewpew zed")
      A.eq(ns.db.roster.Pewpew, nil)
      tc(W, "remove Chaos Other")
      A.eq(ns.db.roster["Chaos Other"], nil)
      W.printed = {}
      tc(W, "forget twiz")
      A.ok(printedLine(W, "TwizCrew: that's you."))
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
      tc(W, "help more")
      local text = table.concat(W.printed, "\n")
      for _, cmd in ipairs({ "/tc show", "/tc hide", "/tc status", "/tc reset", "/tc report", "/tc debug",
        "/tc forget", "/tc remove" }) do
        A.contains(text, cmd)
      end
      A.no(text:find("/tc add", 1, true), "no list of names to add any more")
      local mark = #W.printed
      tc(W, "fly me to the moon")
      A.eq(#W.printed - mark, helpLines, "an unknown command shows the everyday help")
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

    report_survives_a_failing_section_and_lists_problems_and_messages = function(ns, A, W)
      boot(W)
      ns.Updates.reportLine = function() error("kaboom") end
      W:fire("CHAT_MSG_ADDON", "TwizCrew", "1^PING^", "WHISPER", "Ginkan")
      for i = 1, 7 do ns.Log.add("warn", "problem %d", i) end
      local text = table.concat(ns.Report.lines(), "\n")
      A.contains(text, "Updates: failed (")
      A.contains(text, "kaboom")
      A.contains(text, "Class icons:")
      A.contains(text, "Guild: ")
      A.contains(text, "Messages this session: ")
      A.contains(text, "recv PING 1")
      A.contains(text, "WARN problem 7")
      A.contains(text, "WARN problem 3")
      A.no(text:find("WARN problem 2", 1, true))
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
      A.eq(lines[2], "Connection: through the guild Test Guild")
      A.eq(lines[3], "Layer: key none, seen never, 0 hidden values skipped")
      A.contains(lines[4], "Class icons: ")
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

    report_says_when_there_is_no_guild_and_when_chat_is_held = function(ns, A, W)
      W.state.guild = nil
      W:fire("ADDON_LOADED", "TwizCrew")
      W:fire("PLAYER_LOGIN")
      A.eq(ns.Report.lines()[2], "Connection: waiting for the game to say whether you are in a guild")
      W:advance(13)
      A.eq(ns.Report.lines()[2], "Connection: not in a guild, so nothing is sent")
      W.state.guild = { name = "Night Owls", members = { { name = "Twiz", online = true } } }
      W.state.guildListDelay = 30
      W:advance(2)
      A.eq(ns.Report.lines()[2], "Connection: waiting for the guild list")
      W.state.guildListDelay = nil
      W:fire("GUILD_ROSTER_UPDATE")
      W.state.guild = { name = "Night Owls", members = { { name = "Twiz", online = true } } }
      W.env.InChatMessagingLockdown = function() return true end
      W:advance(2)
      A.eq(ns.Report.lines()[2],
        "Connection: through the guild Night Owls; the game is holding chat messages back right now")
      local text = table.concat(ns.Report.lines(), "\n")
      A.no(text:find("hannel", 1, true), "nothing about a channel any more")
      A.no(text:find("goldshire", 1, true), "the old crew code is not in the report")
      A.eq(ns.Log.errors(10), {})
    end,

    settings_builds_and_resets_without_errors = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("panel")
      A.ok(ns.Settings.isOpen())
      ns.Modules.set("panel", "scale", 1.5)
      ns.Settings.confirmReset()
      A.ok(ns.Settings.isConfirming())
      ns.Settings.answerReset(true)
      A.eq(ns.Modules.setting("panel", "scale"), 1)
      A.no(ns.Settings.isConfirming())
      for _, st in ipairs({ "panel", "alerts", "fun", "find", "more", "basic" }) do ns.Settings.setTab(st) end
      A.eq(ns.Log.errors(10), {})
    end,

    settings_opens_on_a_short_basics_tab = function(ns, A, W)
      boot(W)
      ns.Settings.open()
      A.eq(ns.Settings.tab(), "basic")
      local d = ns.Settings.describeForTest()
      local controls = {}
      for _, v in ipairs(d) do
        if v:find("^setting:") or v:find("^child:") or v:find("^module:") then controls[#controls + 1] = v end
      end
      A.eq(controls, { "setting:panel:keepOpen", "setting:panel:scale", "setting:panel:idleAlpha",
        "setting:panel:noticeScope", "module:popups:switch", "setting:activity:chatNews", "setting:popups:sounds",
        "setting:tags:autoAway" }, "the 8 everyday controls (the two help buttons are links at the top now)")
      A.eq(d[1], "section:The panel", "The panel heading first")
      A.eq(d[2], "setting:panel:keepOpen", "then Keep the panel open (no theme picker since 2026-11-23)")
      for _, c in ipairs(controls) do
        local key = c:gsub("^setting:", ""):gsub("^module:(%w+):switch$", "module:%1")
        A.eq(d[indexOf(d, c) + 1], "grey:" .. key, c .. ": a grey line under it")
        A.ok(ns.Help.SETTING_LINES[key], key .. ": its words are in UI/Help.lua")
      end
      A.no(has(d, "note:advanced"), "no Advanced tab any more")
      A.no(has(d, "setting:comm:debug"), "no technical switch on Basics")
      local links = ns.Settings.linksForTest()
      A.eq(links.about.text:GetText(), "How to use TwizCrew")
      A.eq(links.new.text:GetText(), "What's new")
      links.about._scripts.OnClick(links.about)
      A.ok(ns.About.isShown(), "the link opens How to use TwizCrew")
      links.new._scripts.OnClick(links.new)
      A.ok(ns.Changelog.isShown(), "the link opens What's new")
      A.eq(ns.Log.errors(10), {})
    end,

    six_tabs_in_one_row = function(ns, A, W)
      boot(W)
      ns.Settings.open()
      local ids = {}
      for _, pg in ipairs(ns.Settings.PAGES) do ids[#ids + 1] = pg.id end
      A.eq(ids, { "basic", "panel", "alerts", "fun", "find", "more" })
      ns.Settings.setTab("panel")
      A.eq(ns.Settings.tab(), "panel")
      local d = ns.Settings.describeForTest()
      A.eq(d[1], "module:panel:switch", "the part's switch first (no theme picker since 2026-11-23)")
      A.no(has(d, "setting:panel:scale"), "Panel size is on Basics only")
      A.no(has(d, "setting:tags:autoAway"), "Mark me AFK is on Basics only")
      A.ok(indexOf(d, "section:Rarely needed") > indexOf(d, "setting:panel:hideInCombat"), "rarely needed come last")
      A.ok(indexOf(d, "setting:panel:showSelf") > indexOf(d, "section:Rarely needed"))
      A.ok(indexOf(d, "module:layer:switch") > indexOf(d, "section:Rarely needed"))
      ns.Settings.setTab("alerts")
      d = ns.Settings.describeForTest()
      A.ok(has(d, "setting:popups:online")); A.ok(has(d, "setting:panel:questHeadsUp")); A.ok(has(d, "module:activity:switch"))
      A.no(has(d, "module:popups:switch"), "the Pop-ups switch is on Basics"); A.no(has(d, "setting:panel:scale"))
      ns.Settings.setTab("fun")
      d = ns.Settings.describeForTest()
      A.ok(has(d, "setting:roasts:mocks")); A.ok(has(d, "module:stats:switch")); A.ok(has(d, "child:roasts:editMocks"))
      ns.Settings.setTab("find")
      d = ns.Settings.describeForTest()
      A.ok(has(d, "module:find:switch"), "Find the crew has a real switch")
      A.ok(has(d, "setting:find:rowArrows"))
      ns.Settings.setTab("more")
      d = ns.Settings.describeForTest()
      A.ok(has(d, "module:calendar:switch")); A.ok(has(d, "module:updates:switch")); A.ok(has(d, "setting:minimap:show"))
      A.ok(has(d, "setting:version:versions")); A.ok(has(d, "button:tryit"))
      ns.Settings.setTab("advanced", "fun")
      A.eq(ns.Settings.tab(), "fun", "(\"advanced\", page) from before still shows that page")
      ns.Settings.setTab("nonsense")
      A.eq(ns.Settings.tab(), "fun", "an unknown tab changes nothing")
      for _, gone in ipairs({ "advanced", "all", "test", "roasts", "popups", "crew", "tools" }) do
        ns.Settings.setTab(gone)
        A.ok(ns.Settings.tab() == "fun" or (gone == "advanced" and ns.Settings.tab() == "panel"), "no " .. gone .. " tab")
        ns.Settings.setTab("fun")
      end
      -- the tabs: the theme's tab look, the icons when the row fits
      local tabs = ns.Settings.tabButtonsForTest()
      A.ok(ns.Settings.tabIconsForTest(), "six tabs with icons fit in 372")
      local used = -2
      for _, pg in ipairs(ns.Settings.PAGES) do used = used + tabs[pg.id]:GetWidth() + 2 end
      A.ok(used <= 372, "the row fits: " .. used)
      A.eq(tabs.fun.icon._texture, "Interface\\AddOns\\TwizCrew\\Art\\Icons\\Icons.tga")
      A.eq(tabs.fun.tcTab.active, true, "the shown tab is drawn selected")
      A.eq(tabs.basic.tcTab.active, false)
      A.eq(ns.Log.errors(10), {})
    end,

    every_setting_and_switch_has_a_place = function(ns, A, W)
      boot(W)
      ns.Settings.open()
      local seen = {}
      for _, pg in ipairs(ns.Settings.PAGES) do
        ns.Settings.setTab(pg.id)
        for _, v in ipairs(ns.Settings.describeForTest()) do seen[v] = (seen[v] or 0) + 1 end
      end
      local function placed(id, key)
        return (seen["setting:" .. id .. ":" .. key] or 0) + (seen["child:" .. id .. ":" .. key] or 0)
      end
      for _, def in ipairs(ns.Modules.list()) do
        if def.id ~= "testtools" then -- (its buttons are in their own window)
          for _, sdef in ipairs(def.settings) do
            local where = def.id .. ":" .. sdef.key
            if ns.Settings.LINKED[where] then
              A.eq(placed(def.id, sdef.key), 0, where .. ": a link at the top of the window, not a row")
            else
              A.eq(placed(def.id, sdef.key), 1, where .. " is on exactly one page")
            end
          end
          if def.tier ~= "essential" and not def.comingSoon then
            A.eq(seen["module:" .. def.id .. ":switch"], 1, def.id .. " has its switch on exactly one page")
          end
        end
      end
      A.no(seen["module:comm:always on"], "no 'always on' rows")
      A.no(seen["module:pokes:coming later"], "no 'coming later' rows")
      A.no(seen["setting:comm:debug"], "the technical switch is /tc debug only")
      for v in pairs(seen) do A.no(v:find("^picker:"), "no theme picker (" .. v .. ")") end
    end,

    a_new_module_lands_on_more = function(ns, A, W)
      ns.Modules.register({ id = "newpart", name = "New part", tier = "extra", info = "A test module.",
        defaults = { loud = true }, settings = { { key = "loud", label = "Loud", kind = "toggle", info = "A test." } } })
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("more")
      local d = ns.Settings.describeForTest()
      A.ok(indexOf(d, "module:newpart:switch") > indexOf(d, "button:tryit"), "at the end of More")
      A.ok(indexOf(d, "setting:newpart:loud") > indexOf(d, "module:newpart:switch"))
    end,

    settings_shows_broken_module = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("basic")
      ns.Modules.markBroken("popups")
      local d = ns.Settings.describeForTest()
      A.ok(has(d, "module:popups:broken"), "rebuilt while open")
      A.no(has(d, "module:popups:switch"))
      A.eq(ns.Settings.BROKEN_TEXT, "turned off after errors, /reload to try again")
    end,

    settings_rebuilds_lazily_when_closed = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("panel")
      ns.Settings.close()
      local before = ns.Settings.layoutCountForTest()
      ns.Modules.setEnabled("panel", false)
      ns.Modules.setEnabled("panel", true)
      ns.Modules.resetAll()
      A.eq(ns.Settings.layoutCountForTest(), before, "no rebuild while closed")
      ns.Settings.open(); ns.Settings.setTab("panel")
      A.eq(ns.Settings.layoutCountForTest(), before + 1, "one rebuild on the next open")
    end,

    text_settings_save_trimmed = function(ns, A, W)
      ns.Modules.register({ id = "texttest", name = "Text test", tier = "module", info = "A test module.",
        defaults = { title = "Old" },
        settings = { { key = "title", label = "Title", kind = "text", info = "A test text." } } })
      boot(W)
      local changed = {}
      ns.Bus.on("test", "SETTING_CHANGED", function(id, key, v) if id == "texttest" then changed[#changed + 1] = v end end)
      A.ok(ns.Settings.save("texttest", "title", "  New one "))
      A.eq(ns.Modules.setting("texttest", "title"), "New one")
      A.no(ns.Settings.save("texttest", "title", "   "), "a blank text is refused")
      A.no(ns.Settings.save("texttest", "title", "New one"), "same value: nothing to do")
      A.eq(changed, { "New one" })
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
      tc(W, "help"); tc(W, "help more")
      local text = table.concat(W.printed, "\n")
      for _, cmd in ipairs({ "/tc awards", "/tc awards all", "/tc session new", "/tc stats reset", "/tc guild ", "/tc forget" }) do
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
