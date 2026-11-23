-- Mouse-over tips and the About page ("How to use TwizCrew"): the words in UI/Help.lua (limits, no em dash, the About
-- lines fit and are true to the commands and tags), a sample of tips shown on hover (the panel's count, a guild member
-- without the addon, a section bar, a Hall of Shame tab, calendar parts, the "?" button), and the About window: /tc about,
-- /tc help, the wrench menu, the settings button, and opening once by itself on a new install only.

local EM_DASH = "\226\128\148"
local TITLE_MAX, TEXT_MAX = 32, 160

local function start(ns, W)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  ns.Crew.start()
  ns.Self.start()
  ns.LayerSensor.start()
  ns.Modules.startAll()
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
  return db
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

-- The game's tooltip, replaced by one that records what it shows.
local function recordTip(W)
  local tip = { lines = {}, shown = false }
  W.env.GameTooltip = {
    SetOwner = function(_, owner, anchor) tip.owner, tip.anchor, tip.lines = owner, anchor, {} end,
    SetText = function(_, t) tip.lines[#tip.lines + 1] = t end,
    AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end,
    AddDoubleLine = function(_, a, b) tip.lines[#tip.lines + 1] = tostring(a) .. " " .. tostring(b) end,
    Show = function() tip.shown = true end,
    Hide = function() tip.shown = false end,
    IsOwned = function(_, f) return tip.owner == f end,
    IsShown = function() return tip.shown end,
  }
  return tip
end

local function hover(f) f._scripts.OnEnter(f) end
local function leave(f) f._scripts.OnLeave(f) end

local function has(list, text)
  for _, l in ipairs(list) do if l == text then return true end end
  return false
end

-- The row frame drawn for this member (nil: no row on screen).
local function rowOf(ns, key)
  for i = 1, ns.Panel.rowCountForTest() do
    local r = ns.Panel.rowFrameForTest(i)
    if r and rawget(r, "tcModel") and r.tcModel.key == key then return r end
  end
end

local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- How many sentences: a full stop, "!" or "?" at the end or before a space.
local function sentences(text)
  local n = 0
  for _ in (text .. " "):gmatch("[%.!?]%s") do n = n + 1 end
  return n
end

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

return {
  files = "toc",
  tests = {
    ---------------------------------------------------------------------------------------------------- the words
    every_tip_has_a_short_title_and_text = function(ns, A)
      local n = 0
      for key, t in pairs(ns.Help.TIPS) do
        n = n + 1
        local title, text = t[1], t[2]
        A.ok(type(title) == "string" and title ~= "", key .. ": a title")
        A.ok(type(text) == "string" and text ~= "", key .. ": a text")
        A.ok(#title <= TITLE_MAX, key .. ": title too long (" .. #title .. ")")
        A.ok(#text <= TEXT_MAX, key .. ": text too long (" .. #text .. "): " .. text)
        A.ok(sentences(text) <= 2, key .. ": at most two sentences: " .. text)
        A.no(title:find(EM_DASH, 1, true) or text:find(EM_DASH, 1, true), key .. ": no em dash")
        A.eq({ ns.Help.tip(key) }, { title, text })
      end
      A.ok(n >= 50, "tips for the things that don't explain themselves: " .. n)
      A.eq(ns.Help.tip("no such tip"), nil)
      for key, line in pairs(ns.Help.LINES) do
        A.ok(type(line) == "string" and line ~= "", key)
        A.no(line:find(EM_DASH, 1, true), key .. ": no em dash")
        A.ok(#plain(line) <= 120, key .. ": short")
      end
    end,
    about_lines_fit_and_end_with_the_closing_sentence = function(ns, A)
      local lines = ns.Help.aboutLines()
      A.ok(#lines >= 20 and #lines <= 60, "about one screen: " .. #lines)
      A.eq(lines[#lines].text, "TwizCrew is still growing. Things may change, and this page is updated with each version.")
      A.eq(lines[1].head, true, "starts with a heading")
      for i, l in ipairs(lines) do
        A.eq(type(l.text), "string", "line " .. i)
        A.ok(#l.text <= ns.Help.ABOUT_WIDTH, "line " .. i .. " fits the window: " .. l.text)
        A.no(l.text:find(EM_DASH, 1, true), "line " .. i .. ": no em dash")
      end
    end,
    about_page_tells_the_truth_about_tags_and_commands = function(ns, A, W)
      local all = {}
      for _, l in ipairs(ns.Help.aboutLines()) do all[#all + 1] = l.text end
      local text = table.concat(all, "\n")
      for id, label in pairs(ns.Tags.LABEL) do A.contains(text, label .. ":", "the " .. id .. " tag is explained") end
      A.contains(text, "Ctrl + right-click a spot on the world map", "the meet-up gesture")
      A.contains(ns.MeetMap and "Ctrl + right-click" or "", "Ctrl + right-click")
      -- every command the page names is in the help list
      W.env.SlashCmdList.TWIZCREW("no-such-command")
      local listed = table.concat(W.printed, "\n")
      for cmd in text:gmatch("/tc ?(%l*)") do
        if cmd ~= "" then A.contains(listed, "/tc " .. cmd .. " -", "a real command: /tc " .. cmd) end
      end
    end,
    -------------------------------------------------------------------------------------------- tips on hover
    header_count_explains_here_and_online = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      W:advance(1)
      local b = ns.Panel.countButtonForTest()
      A.ok(b and b:IsShown(), "a hover area over the count")
      hover(b)
      A.ok(tip.shown)
      A.eq(tip.lines[1], "Here and online")
      A.contains(tip.lines[2], "Here: you")
      leave(b)
      A.no(tip.shown)
      A.eq(ns.Log.errors(10), {})
    end,
    a_guild_member_without_the_addon_has_a_tooltip = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      ns.Modules.set("panel", "showNoAddon", true)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
      W:advance(1)
      local r = rowOf(ns, "Chaos")
      A.ok(r, "Chaos (no addon) has a row")
      hover(r)
      A.ok(tip.shown, "a tooltip, not nothing")
      A.eq(tip.lines[1], "Chaos")
      A.ok(has(tip.lines, ns.Help.LINES.noAddon), "says why so little is known")
      A.eq(tip.lines[#tip.lines], "Right-click for options")
      -- a redraw while the mouse stays keeps it (it used to close a tooltip with info lines and no tip lines)
      W:advance(1)
      ns.Panel.refresh(); W:advance(1)
      A.ok(tip.shown, "still shown after a redraw")
      A.eq(ns.Log.errors(10), {})
    end,
    an_offline_member_shows_when_last_seen = function(ns, A, W)
      table.insert(W.state.guild.members, { name = "Sleepy", online = false, lastOnline = { 0, 0, 2, 0 },
        guid = "Player-1-0099" })
      local tip = recordTip(W)
      start(ns, W)
      ns.Modules.set("panel", "showNoAddon", true)
      ns.Modules.set("panel", "showOffline", true)
      W:advance(1)
      ns.Panel.scroll(-20); W:advance(1) -- (the bottom of the list)
      local r = rowOf(ns, "Sleepy")
      A.ok(r, "an offline row")
      hover(r)
      A.ok(tip.shown)
      A.eq(tip.lines[1], "Sleepy")
      local seen = false
      for _, l in ipairs(tip.lines) do if l:find("^Offline, last seen") then seen = true end end
      A.ok(seen, "when they were last seen")
      A.eq(tip.lines[#tip.lines], "Right-click for options")
    end,
    row_marks_are_explained_in_the_row_tooltip = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      ns.Modules.set("stats", "titles", "off")
      receive(ns, W, "Ginkan", "STATE", { cl = "MAGE", lv = "12", xp = "63", zn = "Elwynn Forest", tg = "AFK",
        qn = "Kobold Camp Cleanup", qc = "1", ver = "0.1.0" })
      W:advance(1)
      local r = rowOf(ns, "Ginkan")
      hover(r)
      A.ok(has(tip.lines, ns.Help.LINES.dimAway), "dimmed, with zzz: away")
      A.ok(has(tip.lines, ns.Help.LINES.xpBar), "the gold bar")
      A.ok(has(tip.lines, ns.Help.LINES.questDone) or has(tip.lines, ns.Help.LINES.questOn), "the quest's mark")
      -- an award title under the name
      r.tcModel.title = "Professional Corpse"
      hover(r)
      A.ok(has(tip.lines, "Title: Professional Corpse - their Hall of Shame award"))
      A.eq(ns.Log.errors(10), {})
    end,
    pin_button_says_what_pinning_does = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
      W:advance(1)
      local r = rowOf(ns, "Frostie")
      hover(r.pin)
      A.eq(tip.lines[1], "Pin to main view")
      A.contains(tip.lines[2], "main view")
      ns.Panel.pin("Frostie"); W:advance(1)
      r = rowOf(ns, "Frostie")
      hover(r.pin)
      A.eq(tip.lines[1], "Unpin")
    end,
    section_bars_and_headings_have_tips = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
      receive(ns, W, "Ginkan", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
      ns.Panel.pin("Frostie")
      W:advance(1)
      local bar = ns.Panel.guildBarForTest()
      A.ok(bar, "the Guild online bar")
      hover(bar)
      A.eq(tip.lines[1], "Guild online")
      local head = ns.Panel.headFrameForTest("Pinned")
      A.ok(head, "the Pinned heading")
      hover(head)
      A.eq(tip.lines[1], "Pinned")
      A.eq(ns.Log.errors(10), {})
    end,
    tabs_and_the_question_mark_button = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      W:advance(1)
      local tabs = ns.Panel.tabButtonsForTest()
      hover(tabs.crew); A.eq(tip.lines[1], "Crew")
      hover(tabs.shame); A.eq(tip.lines[1], "Hall of Shame")
      A.ok(tabs.help and tabs.help:IsShown(), "a ? next to the tabs")
      hover(tabs.help); A.eq(tip.lines[1], "How to use TwizCrew")
      tabs.help._scripts.OnClick(tabs.help, "LeftButton")
      A.ok(ns.About.isShown(), "the ? opens the About page")
      tabs.help._scripts.OnClick(tabs.help, "LeftButton")
      A.no(ns.About.isShown(), "and closes it")
    end,
    hall_of_shame_switch_tabs_and_wipe_line = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      ns.Panel.setTab("shame"); W:advance(1)
      local b = ns.Board.buttonsForTest()
      hover(b.session); A.eq(tip.lines[1], "This session")
      hover(b.all); A.eq(tip.lines[1], "All time")
      local seen = {}
      for _, t in ipairs(b.tabs) do hover(t); seen[#seen + 1] = tip.lines[1] end
      A.eq(seen, { "Deaths", "Moving", "Money", "Oops", "Lazy", "Trophies" })
      hover(b.footer); A.eq(tip.lines[1], "Wipe Squad")
      A.eq(ns.Log.errors(10), {})
    end,
    calendar_parts_have_tips = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      ns.Calendar.open()
      local f = ns.Calendar.tipFramesForTest()
      hover(f.tabs.events); A.eq(tip.lines[1], "Events")
      hover(f.tabs.play); A.eq(tip.lines[1], "Play times")
      hover(f.subs.usual); A.eq(tip.lines[1], "Usual times")
      hover(f.zone); A.eq(tip.lines[1], "Your time zone")
      A.eq(ns.Calendar.legendForTest(), ns.Help.LINES.calLegend, "the colour key under the month")
      ns.Calendar.show("usual")
      local u = ns.Calendar.usualFramesForTest()
      hover(u.habits[1])
      A.eq(tip.lines[1], "Pick a person", "a habit row with a person")
      A.eq(ns.Log.errors(10), {})
    end,
    choice_control_says_right_click_goes_back = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      ns.Settings.open()
      local r = ns.Settings.rowForTest("panel", "rowStyle")
      hover(r.control)
      A.eq(tip.lines[1], "Next choice")
      A.contains(tip.lines[2], "Right-click goes back one")
    end,
    add_tip_keeps_an_existing_on_enter = function(ns, A, W)
      local tip = recordTip(W)
      start(ns, W)
      local f = W.env.CreateFrame("Button")
      local ran = false
      f:SetScript("OnEnter", function() ran = true end)
      ns.Widgets.addTip(f, "Title", function() return "live text" end)
      f._scripts.OnEnter(f)
      A.ok(ran, "the old OnEnter stays")
      f._scripts["hook:OnEnter"](f)
      A.eq(tip.lines, { "Title", "live text" }, "the tip is hooked after it")
      W.env.GameTooltip = nil
      local g = ns.Widgets.helpTip(W.env.CreateFrame("Button"), "about")
      g._scripts.OnEnter(g) -- no tooltip in the game: nothing happens, no error
      A.eq(ns.Log.errors(10), {})
    end,
    -------------------------------------------------------------------------------------------- the About page
    tc_about_opens_it = function(ns, A, W)
      start(ns, W)
      A.no(ns.About.isShown())
      W.env.SlashCmdList.TWIZCREW("about")
      A.ok(ns.About.isShown())
      local shown = ns.About.shownForTest()
      A.eq(shown[1], "What TwizCrew is")
      ns.About.close()
      A.no(ns.About.isShown())
      ns.About.toggle(); A.ok(ns.About.isShown())
      ns.About.toggle(); A.no(ns.About.isShown())
    end,
    tc_help_opens_it_and_prints_the_list = function(ns, A, W)
      start(ns, W)
      local before = #W.printed
      W.env.SlashCmdList.TWIZCREW("help")
      A.ok(ns.About.isShown(), "the page opens")
      A.eq(W.printed[before + 1], "TwizCrew commands:", "and the list is printed")
      local list = table.concat(W.printed, "\n", before + 1)
      A.contains(list, "/tc about -")
      A.contains(list, "/tc help -")
      ns.About.close()
      before = #W.printed
      W.env.SlashCmdList.TWIZCREW("nonsense")
      A.no(ns.About.isShown(), "an unknown word only prints the list")
      A.eq(W.printed[before + 1], "TwizCrew commands:")
    end,
    other_ways_to_open_it = function(ns, A, W)
      start(ns, W)
      local item
      for _, it in ipairs(ns.Panel.toolItems()) do if it.label == "How to use TwizCrew" then item = it end end
      A.ok(item, "in the wrench menu")
      A.eq(type(item.icon), "string")
      item.onClick()
      A.ok(ns.About.isShown())
      ns.About.close()
      local mm
      for _, it in ipairs(ns.MinimapButton.menuItems()) do if it.label == "How to use TwizCrew" then mm = it end end
      A.ok(mm, "in the minimap button's menu (it lists the wrench's tools)")
      local found
      for _, s in ipairs(ns.Modules.get("panel").settings) do if s.key == "about" then found = s end end
      A.ok(found and found.kind == "button", "a button in the settings")
      found.onClick()
      A.ok(ns.About.isShown())
    end,
    opens_once_by_itself_on_a_new_install = function(ns, A, W)
      W.state.guild = nil -- no guild: no welcome card will come, so the page opens by itself
      boot(W) -- no saved data at all
      A.eq(ns.db.aboutSeen, false)
      W:advance(2)
      A.no(ns.About.isShown(), "not at once")
      W:advance(50)
      A.ok(ns.About.isShown(), "after giving the welcome card its chance")
      A.eq(ns.db.aboutSeen, true)
      ns.About.close()
      W:fire("PLAYER_LOGIN")
      W:advance(60)
      A.no(ns.About.isShown(), "only once")
    end,
    in_a_guild_the_welcome_card_offers_the_page_instead = function(ns, A, W)
      boot(W) -- a new install, in a guild: the welcome card comes with a "How to use TwizCrew" button
      W:advance(60)
      A.ok(ns.Welcome.isStartShown(), "the welcome card")
      A.no(ns.About.isShown(), "one window is enough: the page did not open by itself too")
      A.eq(ns.db.aboutSeen, true, "the card offered it")
    end,
    waits_out_a_fight_and_a_dungeon = function(ns, A, W)
      W.state.guild = nil
      W.state.inInstance, W.state.instanceType = true, "party"
      boot(W)
      W:advance(60)
      A.no(ns.About.isShown(), "never in a dungeon")
      W.state.inInstance, W.state.instanceType = false, "none"
      W.state.combat = true
      W:advance(20)
      A.no(ns.About.isShown(), "never in a fight")
      W.state.combat = false
      W:advance(20)
      A.ok(ns.About.isShown(), "afterwards")
    end,
    not_for_existing_users_after_an_update = function(ns, A, W)
      W.env.TwizCrewDB = { modules = {}, roster = {}, myStatus = "" } -- saved by an older version
      boot(W)
      A.eq(ns.db.aboutSeen, true, "set without a word")
      W:advance(30)
      A.no(ns.About.isShown())
    end,
    the_flag_is_account_wide = function(ns, A)
      for _, path in ipairs(ns.DB.GUILD_PATHS) do A.no(path:find("about", 1, true), "not per guild: " .. path) end
      local db = ns.DB.init(nil, ns.Modules.list())
      A.eq(db.aboutSeen, false)
      A.eq(ns.DB.init({ myStatus = "hi" }, ns.Modules.list()).aboutSeen, true)
      A.eq(ns.DB.init({}, ns.Modules.list()).aboutSeen, false, "an empty table is a new install too")
    end,
  },
}
