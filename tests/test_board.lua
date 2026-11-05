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

    board_rows_model = function(ns, A)
      local list = {
        { name = "Twiz", class = "WARRIOR", stats = { dt = 7 }, mine = true, online = true, at = WALL },
        { name = "Holy|bøi", class = "PRIEST", stats = { dt = 9, ds = 300 }, mine = false, online = true, at = WALL },
      }
      local m = model(ns, "session", list)
      A.eq(m.subtitle, "Session started 9:02 pm by Twiz")
      A.eq(#m.rows, #ns.StatsDefs.AWARDS, "one row per award")
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
      A.eq(model(ns, "all", list).subtitle, "All time")
      A.eq(model(ns, "session", list, { session = false }).subtitle, "Waiting for the crew session to start")
      A.eq(model(ns, "session", list, { starter = "Ho|ly" }).subtitle, "Session started 9:02 pm by Ho||ly")
    end,

    board_ties_and_top_three = function(ns, A)
      local list = {}
      for i, name in ipairs({ "Axel", "Bubbles", "Cora", "Dax" }) do
        list[i] = { name = name, stats = { jp = i <= 2 and 10 or i }, mine = false, online = true, at = WALL }
      end
      local bunny = rowById(model(ns, "all", list), "bunny")
      A.eq(bunny.winners, { "Axel", "Bubbles" }, "ties show every name")
      A.eq(bunny.classes, { false, false }, "unknown class")
      A.eq(#bunny.tip, 4, "info + top 3")
      A.eq(bunny.tip[4], "3. Dax: 4 jumps")
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
      A.eq(m.subtitle:sub(1, 16), "Session started ")
      A.eq(ns.Panel.rowCountForTest(), 0, "crew rows hidden")
      A.eq(ns.Board.view(), "session")
      ns.Board.setView("all")
      W:advance(1)
      A.eq(ns.Board.view(), "all")
      A.eq(ns.Board.modelForTest().subtitle, "All time")
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
      W:advance(1)
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
      A.eq(#m.rows, #ns.StatsDefs.AWARDS)
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
