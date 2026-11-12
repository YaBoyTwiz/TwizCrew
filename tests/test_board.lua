-- Hall of Shame tab and award titles (stats Task 8): BoardLogic (pure model), PanelLogic row titles, the tabs in
-- the Crew panel, the board drawn inside it, and titles following the stats "titles" setting. Full TOC boot.
local WALL = 1700000000

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- Boots and lets the session be decided.
local function start(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function hello(W, ns, name, class)
  receive(W, ns, name, "STATE", { ver = "0.1.0", cl = class or "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
    lk = "", ins = "0" })
end

local function countType(ns, W, from, msgType)
  local n = 0
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then n = n + 1 end
  end
  return n
end

local function rowById(model, id)
  for _, r in ipairs(model.rows) do if r.id == id then return r end end
end

local function modelByName(models, name)
  for _, m in ipairs(models) do if m.name == name then return m end end
end

local function entryMap(list)
  local map = {}
  for _, e in ipairs(list) do map[e.name] = e end
  return map
end

local function ctxFor(ns, list, extra)
  local ctx = { session = { id = "Twiz-" .. WALL, start = WALL, manual = false }, starter = "Twiz",
    timeText = "9:02 pm", wipeLine = true, entries = entryMap(list), online = function() return true end,
    wall = WALL }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return ctx
end

local function model(ns, view, list, extra)
  return ns.BoardLogic.model(view, ns.StatsLogic.awards(list), ctxFor(ns, list, extra))
end

return {
  files = "toc",
  tests = {
    title_on_row_model = function(ns, A)
      local members = {
        { name = "Ginkan", class = "WARRIOR", online = true, tags = {} },
        { name = "Frostie", class = "MAGE", online = true, tags = {} },
        { name = "Holy|boi", class = "PRIEST", online = true, tags = {} },
        { name = "Stabz", class = "ROGUE", online = false, lastSeen = WALL - 60, tags = {} },
      }
      local titles = { Ginkan = "Professional Corpse", ["Holy|boi"] = "A|B", Stabz = "Fish" }
      local rows = ns.PanelLogic.rows(members, {}, nil, true, 0, WALL, function(n) return titles[n] end)
      A.eq(rows[1].title, "Professional Corpse")
      A.eq(rows[2].title, nil)
      A.eq(rows[3].title, "A||B", "plain text")
      A.eq(rows[4].title, nil, "no title on an offline row")
      rows = ns.PanelLogic.rows(members, {}, nil, true, 0, WALL)
      A.eq(rows[1].title, nil, "no titleOf: no titles")
    end,

    tabs_show_one_category_at_a_time = function(ns, A)
      local list = { { name = "Twiz", stats = { dt = 3, gn = 14, pt = 1800 } } }
      local m = model(ns, "session", list)
      A.eq(#m.tabs, 6)
      A.eq(m.tabs[1], { id = "deaths", label = "Deaths", active = true })
      A.eq(#m.rows, 6, "Deaths has six awards")
      A.ok(rowById(m, "corpse"))
      A.eq(rowById(m, "pauper"), nil, "Pauper is on another tab")
      A.eq(m.subtitle, "Deaths: session started 9:02 pm by Twiz")
      m = model(ns, "session", list, { tab = "loot" })
      A.ok(m.tabs[3].active)
      A.eq(rowById(m, "pauper").text, "14c")
      A.eq(m.subtitle, "Money & Loot: session started 9:02 pm by Twiz")
      m = model(ns, "all", list, { tab = "nope" })
      A.ok(m.tabs[1].active, "an unknown tab falls back to the first")
      A.eq(m.subtitle, "Deaths: all time")
    end,
    the_trophies_tab = function(ns, A)
      local summary = {
        Twiz = { total = 7, counts = { corpse = 6, bunny = 1 }, streaks = { corpse = 3 } },
        Lurabe = { total = 2, counts = { fish = 2 }, streaks = {} },
      }
      local m = model(ns, "session", {}, { tab = "trophies", trophies = summary,
        entries = { Twiz = { name = "Twiz", class = "WARRIOR" } } })
      A.eq(#m.tabs, 6)
      A.eq(m.tabs[6], { id = "trophies", label = "Trophies", active = true })
      A.eq(m.subtitle, "Trophies: from every session the crew played")
      A.eq(#m.rows, 2)
      A.eq(m.rows[1].name, "Twiz", "most trophies first")
      A.eq(m.rows[1].text, "7 trophies")
      A.eq(m.rows[1].winners, { "Professional Corpse x6, Bunny Hopper x1" })
      A.eq(m.rows[1].classes, { false }, "award names: plain text colour, not the class colour")
      A.contains(table.concat(m.rows[1].tip, "\n"), "Professional Corpse: 6 (3 sessions in a row)")
      local empty = model(ns, "session", {}, { tab = "trophies", trophies = {} })
      A.eq(#empty.rows, 1)
      A.ok(empty.rows[1].empty)
      A.eq(empty.rows[1].name, "No trophies yet")
    end,
    the_tab_is_remembered = function(ns, A, W)
      start(ns, W)
      ns.Board.setTab("oops")
      A.eq(ns.Board.tab(), "oops")
      A.eq(ns.Modules.setting("stats", "boardTab"), "oops")
      ns.Board.setTab("bogus")
      A.eq(ns.Board.tab(), "oops", "unknown tabs are ignored")
    end,

    board_rows_model = function(ns, A)
      local list = {
        { name = "Twiz", class = "WARRIOR", stats = { dt = 7 }, mine = true, online = true, at = WALL },
        { name = "Holy|bøi", class = "PRIEST", stats = { dt = 9, ds = 300 }, mine = false, online = true, at = WALL },
      }
      local m = model(ns, "session", list)
      A.eq(m.subtitle, "Deaths: session started 9:02 pm by Twiz")
      A.eq(#m.rows, 6, "one row per award on the Deaths tab")
      A.eq(m.rows[1].id, "corpse")
      local corpse = rowById(m, "corpse")
      A.eq(corpse.name, "Professional Corpse")
      A.eq(corpse.icon, ns.StatsDefs.AWARDS[1].icon)
      A.eq(corpse.winners, { "Holy||bøi" })
      A.eq(corpse.classes, { "PRIEST" })
      A.eq(corpse.text, "9 deaths")
      A.eq(corpse.empty, false)
      A.eq(corpse.tip[1], ns.StatsDefs.AWARDS[1].info)
      A.eq(corpse.tip[2], "1. Holy||bøi: 9 deaths")
      A.eq(corpse.tip[3], "Time dead: 5m")
      A.eq(corpse.tip[4], "2. Twiz: 7 deaths")
      A.eq(#corpse.tip, 4)
      local gravity = rowById(m, "gravity")
      A.eq(gravity.empty, true)
      A.eq(gravity.text, "nobody yet")
      A.eq(gravity.winners, {})
      A.eq(gravity.tip, { ns.StatsDefs.AWARDS[2].info })
      A.eq(model(ns, "all", list).subtitle, "Deaths: all time")
      A.eq(model(ns, "session", list, { session = false }).subtitle, "Deaths: waiting for the crew session to start")
      A.eq(model(ns, "session", list, { starter = "Ho|ly" }).subtitle, "Deaths: session started 9:02 pm by Ho||ly")
    end,

    board_ties_and_top_three = function(ns, A)
      local list = {}
      for i, name in ipairs({ "Axel", "Bubbles", "Cora", "Dax" }) do
        list[i] = { name = name, stats = { jp = i <= 2 and 10 or i }, mine = false, online = true, at = WALL }
      end
      local bunny = rowById(model(ns, "all", list, { tab = "move" }), "bunny")
      A.eq(bunny.winners, { "Axel", "Bubbles" }, "ties show every name")
      A.eq(bunny.classes, { false, false }, "unknown class")
      A.eq(#bunny.tip, 4, "info + top 3")
      A.eq(bunny.tip[4], "3. Dax: 4 jumps")
    end,

    board_many_ties_shortened_with_full_tip = function(ns, A)
      local list = {}
      for i, name in ipairs({ "Axel", "Bubbles", "Cora", "Da|x" }) do
        list[i] = { name = name, stats = { jp = 10 }, mine = false, online = true, at = WALL }
      end
      local bunny = rowById(model(ns, "all", list, { tab = "move" }), "bunny")
      A.eq(bunny.winners, { "Axel", "Bubbles", "Cora", "Da||x" }, "every tied name in the model")
      A.eq(bunny.more, 2, "two more than shown")
      A.eq(bunny.tip[#bunny.tip], "Tied: Axel, Bubbles, Cora, Da||x")
      local two = rowById(model(ns, "all", { list[1], list[2] }, { tab = "move" }), "bunny")
      A.eq(two.more, 0)
      A.no(two.tip[#two.tip]:find("^Tied"), "two names fit: no Tied line")
    end,

    board_rows_have_room = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      for _, name in ipairs({ "Axel", "Bubbles", "Cora", "Dax" }) do
        hello(W, ns, name)
        receive(W, ns, name, "STATS", { sid = S, q = "1", s_jp = "10", s_mt = "3000", s_st = "1440", s_dw = "1",
          s_ld = "3", s_pt = "3600" })
      end
      ns.Panel.setTab("shame")
      ns.Board.setTab("move")
      W:advance(1)
      local L = ns.Board.layoutForTest()
      A.ok(L.width <= 320, "board at most 320 px wide")
      local byName = {}
      for _, r in ipairs(L.rows) do byName[r.name] = r end
      local bunny = byName["Bunny Hopper"]
      A.eq(bunny.number, "10 jumps")
      A.contains(bunny.winners, "Axel")
      A.contains(bunny.winners, "Bubbles")
      A.no(bunny.winners:find("Cora", 1, true), "only two names on the row")
      A.contains(bunny.winners, " +2")
      A.eq(bunny.height, 35, "two lines")
      A.eq(byName["Fish"].height, 21, "nobody yet: one line")
      A.ok(L.numberWidth >= 160, "room for the longest numbers: " .. L.numberWidth)
      A.ok(L.winnersWidth >= 280, "winners use the full row: " .. L.winnersWidth)
      A.eq(byName["Never Walks"].number, "rides 2.5x more than walks")
      ns.Board.setTab("deaths")
      W:advance(1)
      byName = {}
      for _, r in ipairs(ns.Board.layoutForTest().rows) do byName[r.name] = r end
      A.eq(byName["Died to a Weakling"].number, "1 death (lvl 3 mob)")
      A.eq(ns.Log.errors(10), {})
    end,

    a_broken_board_never_turns_the_panel_off = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      hello(W, ns, "Frostie")
      receive(W, ns, "Frostie", "STATS", { sid = S, q = "1", s_dt = "3", a_dt = "3" })
      W:advance(1)
      ns.StatsStore.entries = function() error("entries broke") end
      for _ = 1, 6 do
        ns.Bus.fire("STATS_CHANGED")
        W:advance(0.1)
      end
      A.ok(ns.Modules.isEnabled("panel"), "the Crew panel stays on")
      A.ok(ns.Panel.isShown())
      A.ok(ns.Panel.rowCountForTest() > 0, "crew rows still drawn")
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, nil, "no titles")
      ns.Panel.setTab("shame")
      for _ = 1, 6 do
        ns.Panel.refresh()
        W:advance(0.1)
      end
      A.ok(ns.Modules.isEnabled("panel"), "still on after the board failed to draw")
      A.ok(ns.Panel.isShown())
      A.eq(ns.Panel.noteForTest(), "Hall of Shame unavailable right now")
      local boardErrors, panelErrors = 0, 0
      for _, line in ipairs(ns.Log.errors(50)) do
        if line:find("ERROR board: ", 1, true) then boardErrors = boardErrors + 1 end
        if line:find("ERROR panel: ", 1, true) then panelErrors = panelErrors + 1 end
      end
      A.ok(boardErrors >= 2, "logged under board")
      A.eq(panelErrors, 0, "nothing charged to the panel")
      ns.Panel.setTab("crew")
      W:advance(0.1)
      A.eq(ns.Panel.noteForTest(), nil, "the note goes away")
      A.ok(ns.Panel.rowCountForTest() > 0)
    end,

    titles_cached_until_stats_change = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      hello(W, ns, "Frostie")
      hello(W, ns, "Ginkan", "WARRIOR")
      receive(W, ns, "Frostie", "STATS", { sid = S, q = "1", s_dt = "3", a_dt = "3" })
      W:advance(ns.Config.STATS_CHANGED_GAP) -- a friend's numbers redraw like my own changes (throttled)
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, "Professional Corpse")
      local real, calls = ns.StatsStore.entries, 0
      ns.StatsStore.entries = function(...) calls = calls + 1; return real(...) end
      for _ = 1, 5 do
        ns.Panel.refresh()
        W:advance(0.1)
      end
      A.eq(calls, 0, "redraws without changes reuse the titles")
      receive(W, ns, "Ginkan", "STATS", { sid = S, q = "1", s_dt = "9", a_dt = "9" }) -- fires STATS_CHANGED
      W:advance(ns.Config.STATS_CHANGED_GAP)
      A.eq(modelByName(ns.Panel.models(), "Ginkan").title, "Professional Corpse", "updated after STATS_CHANGED")
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, nil)
      ns.Modules.set("stats", "titles", "all")
      W:advance(0.1)
      A.eq(modelByName(ns.Panel.models(), "Ginkan").title, "Professional Corpse")
      ns.Modules.set("stats", "titles", "session")
      ns.Session.newByHand() -- fires SESSION_CHANGED
      W:advance(0.1)
      A.eq(modelByName(ns.Panel.models(), "Ginkan").title, nil, "a new session: titles follow")
      -- my own numbers reset by hand: my title goes too
      ns.Modules.set("panel", "showSelf", true)
      ns.Stats.count("jp", 5)
      W:advance(6)
      A.eq(modelByName(ns.Panel.models(), "Twiz").title, "Bunny Hopper")
      W.env.SlashCmdList.TWIZCREW("stats reset yes")
      W:advance(0.1)
      A.eq(modelByName(ns.Panel.models(), "Twiz").title, nil, "after /tc stats reset yes")
      A.eq(ns.Log.errors(10), {})
    end,

    scroll_does_nothing_on_the_hall_of_shame = function(ns, A, W)
      start(ns, W)
      for i = 1, 12 do hello(W, ns, "Friend" .. string.char(64 + i)) end
      W:advance(1)
      ns.Panel.scroll(-1)
      W:advance(0.1)
      A.eq(ns.Panel.firstRowForTest(), 2, "the crew tab scrolls")
      ns.Panel.scroll(1)
      W:advance(0.1)
      ns.Panel.setTab("shame")
      W:advance(0.1)
      local redraws = ns.Panel.redrawCountForTest()
      ns.Panel.scroll(-3)
      W:advance(0.1)
      A.eq(ns.Panel.redrawCountForTest(), redraws, "no redraw")
      ns.Panel.setTab("crew")
      W:advance(0.1)
      A.eq(ns.Panel.firstRowForTest(), 1, "the crew list did not move while hidden")
    end,

    offline_friend_tip_says_when = function(ns, A)
      local list = {
        { name = "Frostie", stats = { dt = 3 }, mine = false, online = false, at = WALL - 7200 },
        { name = "Twiz", stats = { dt = 2 }, mine = true, online = true, at = WALL },
        { name = "Twizalt", stats = { dt = 1 }, mine = true, online = false },
      }
      local corpse = rowById(model(ns, "all", list, { online = function(n) return n == "Twiz" end }), "corpse")
      A.eq(corpse.tip[2], "1. Frostie: 3 deaths (updated 2h ago)")
      A.eq(corpse.tip[3], "2. Twiz: 2 deaths")
      A.eq(corpse.tip[4], "3. Twizalt: 1 death", "my other character: no time")
    end,

    board_footer = function(ns, A)
      local list = {
        { name = "Twiz", stats = { wp = 2 }, mine = true, online = true, at = WALL },
        { name = "Frostie", stats = { wp = 1 }, mine = false, online = true, at = WALL },
      }
      A.eq(model(ns, "session", list).footer, "Wipe Squad: 2 wipes tonight")
      A.eq(model(ns, "all", list).footer, "Wipe Squad: 2 wipes")
      A.eq(model(ns, "session", list, { wipeLine = false }).footer, nil)
      list[1].stats.wp = 0
      A.eq(model(ns, "session", list).footer, "Wipe Squad: 1 wipe tonight")
      list[2].stats.wp = 0
      A.eq(model(ns, "session", list).footer, nil)
      A.eq(model(ns, "session", {}).footer, nil)
    end,

    time_text = function(ns, A, W)
      local asked
      W.env.date = function(fmt, t) asked = { fmt, t }; return "09:02 PM" end
      A.eq(ns.BoardLogic.timeText(WALL), "9:02 pm")
      A.eq(asked, { "%I:%M %p", WALL })
      W.env.date = function() return "12:30 AM" end
      A.eq(ns.BoardLogic.timeText(WALL), "12:30 am")
      A.eq(ns.BoardLogic.timeText(nil), "")
    end,

    tabs_switch_and_request = function(ns, A, W)
      start(ns, W)
      hello(W, ns, "Frostie")
      W:advance(1)
      A.eq(ns.Panel.tab(), "crew")
      A.ok(ns.Panel.rowCountForTest() > 0)
      A.eq(ns.Board.modelForTest(), nil, "not drawn yet")
      local mark = #W.sent
      ns.Panel.setTab("shame")
      W:advance(2)
      A.eq(ns.Panel.tab(), "shame")
      A.eq(countType(ns, W, mark, "STATSREQ"), 1, "opening the tab asks for fresh numbers")
      local m = ns.Board.modelForTest()
      A.ok(m ~= nil)
      A.eq(m.subtitle:sub(1, 24), "Deaths: session started ")
      A.eq(ns.Panel.rowCountForTest(), 0, "crew rows hidden")
      A.eq(ns.Board.view(), "session")
      ns.Board.setView("all")
      W:advance(1)
      A.eq(ns.Board.view(), "all")
      A.eq(ns.Board.modelForTest().subtitle, "Deaths: all time")
      ns.Panel.setTab("crew")
      W:advance(1)
      A.eq(ns.Panel.tab(), "crew")
      A.ok(ns.Panel.rowCountForTest() > 0, "rows back")
      ns.Panel.setTab("shame")
      W:advance(1)
      ns.Modules.setEnabled("stats", false)
      A.eq(ns.Panel.tab(), "crew", "stats off: back to crew")
      W:advance(1)
      A.ok(ns.Panel.rowCountForTest() > 0)
      ns.Panel.setTab("shame")
      W:advance(1)
      A.eq(ns.Panel.tab(), "crew", "no Hall of Shame while stats is off")
      ns.Modules.setEnabled("stats", true)
      W:advance(1)
      A.eq(ns.Panel.tab(), "crew", "comes back on the crew tab")
      A.eq(ns.Log.errors(10), {})
    end,

    titles_follow_setting = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      hello(W, ns, "Frostie")
      receive(W, ns, "Frostie", "STATS", { sid = S, q = "1", s_dt = "3", a_dt = "3" })
      receive(W, ns, "Ginkan", "STATS", { sid = "Ginkan-5", q = "1", s_dt = "50", a_dt = "50" })
      hello(W, ns, "Ginkan", "WARRIOR")
      ns.Stats.count("jp", 5)
      ns.Modules.set("panel", "showSelf", true)
      W:advance(ns.Config.STATS_CHANGED_GAP) -- friends' numbers redraw like my own changes (throttled)
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, "Professional Corpse")
      A.eq(modelByName(ns.Panel.models(), "Ginkan").title, nil, "other session")
      A.eq(modelByName(ns.Panel.models(), "Twiz").title, "Bunny Hopper", "my own row too")
      ns.Modules.set("stats", "titles", "all")
      W:advance(1)
      A.eq(modelByName(ns.Panel.models(), "Ginkan").title, "Professional Corpse")
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, nil)
      ns.Modules.set("stats", "titles", "off")
      W:advance(1)
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, nil)
      A.eq(modelByName(ns.Panel.models(), "Ginkan").title, nil)
      A.eq(modelByName(ns.Panel.models(), "Twiz").title, nil)
      ns.Modules.set("stats", "titles", "session")
      ns.Modules.setEnabled("stats", false)
      W:advance(1)
      A.eq(modelByName(ns.Panel.models(), "Frostie").title, nil, "stats off: no titles")
      for _, style in ipairs({ "full", "compact", "tiny" }) do
        ns.Modules.setEnabled("stats", true)
        ns.Modules.set("panel", "rowStyle", style)
        W:advance(1)
      end
      A.eq(ns.Log.errors(10), {})
    end,

    redraws_on_stats_and_session_changes = function(ns, A, W)
      start(ns, W)
      W:advance(1)
      local before = ns.Panel.redrawCountForTest()
      ns.Bus.fire("STATS_CHANGED")
      W:advance(0.01)
      A.eq(ns.Panel.redrawCountForTest(), before + 1)
      ns.Bus.fire("SESSION_CHANGED", ns.Session.current(), nil, false)
      W:advance(0.01)
      A.eq(ns.Panel.redrawCountForTest(), before + 2)
    end,

    board_draws_without_errors = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      local names = { "Ginkan", "Frostie", "Holyboi", "Pewpew", "Stabz", "Moonie", "Bubbles", "Axel", "Zapp",
        "Nimble", "Grum|py", "Holybøi" }
      for i, name in ipairs(names) do
        hello(W, ns, name, i % 2 == 0 and "MAGE" or "WARRIOR")
        receive(W, ns, name, "STATS", { sid = S, q = "1", s_dt = tostring(i), a_dt = tostring(i * 3),
          s_wp = tostring(i % 3), a_wp = tostring(i % 3), s_jp = tostring(i * 7), s_ds = tostring(i * 60),
          s_pt = "4000", s_st = "9000", a_rp = tostring(i * 1234), s_dw = "1", s_ld = tostring(i) })
      end
      ns.Stats.count("dt", 2)
      ns.Panel.setTab("shame")
      W:advance(1)
      local m = ns.Board.modelForTest()
      A.eq(#m.rows, 6, "the Deaths tab")
      A.eq(rowById(m, "corpse").winners, { "Holybøi" })
      A.eq(m.footer, "Wipe Squad: 2 wipes tonight")
      ns.Board.setView("all")
      W:advance(1)
      A.eq(ns.Board.modelForTest().footer, "Wipe Squad: 2 wipes")
      ns.Board.setView("session")
      ns.Bus.fire("STATS_CHANGED")
      W:advance(1)
      ns.Modules.set("stats", "wipeLine", false)
      W:advance(1)
      A.eq(ns.Board.modelForTest().footer, nil)
      ns.Modules.resetAll()
      W:advance(31)
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
