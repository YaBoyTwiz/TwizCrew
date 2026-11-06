-- Theme, widgets, class icons, pure panel logic and the Crew panel (module "panel").
local WALL = 1700000000

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
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function member(t)
  local m = { name = "Ginkan", class = "WARRIOR", level = 14, xp = 62, zone = "Elwynn Forest", subzone = "Goldshire",
    status = "", tags = {}, online = true, lastSeen = WALL }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

-- Frames made from now on remember their text, record a few calls, and are listed by name.
local function recordingFrames(W)
  local byName, calls = {}, {}
  local create = W.env.CreateFrame
  W.env.CreateFrame = function(kind, name, ...)
    local f = create(kind, name, ...)
    if name then byName[name] = f end
    rawset(f, "SetText", function(self, t) rawset(self, "tcText", t) end)
    rawset(f, "GetText", function(self) return rawget(self, "tcText") or "" end)
    for _, method in ipairs({ "SetDontSavePosition", "SetUserPlaced", "SetMaxLetters", "StopMovingOrSizing",
      "StartMoving" }) do
      rawset(f, method, function(self, v) calls[#calls + 1] = { frame = self, method = method, value = v } end)
    end
    return f
  end
  return byName, calls
end

local function callsOf(calls, frame, method)
  local out = {}
  for _, c in ipairs(calls) do if c.frame == frame and c.method == method then out[#out + 1] = c.value end end
  return out
end

local function never() return "unknown" end
local function different() return "different" end

local NAMES = { "Ginkan", "Frostie", "Holyboi", "Pewpew", "Stabz", "Moonie", "Bubbles", "Axel", "Zapp", "Nimble",
  "Grumpy", "Holybøi" }

local function feedTwelve(ns, W)
  for i, name in ipairs(NAMES) do
    receive(ns, W, name, "STATE", { cl = i % 2 == 0 and "MAGE" or "WARRIOR", lv = tostring(10 + i), xp = "35",
      zn = "Elwynn Forest", sz = "Goldshire", st = "LF |cffDeadmines", tg = i % 3 == 0 and "COMBAT,AFK" or "",
      lk = "", ins = "0", ver = "0.1.0" })
  end
end

return {
  files = "toc",
  tests = {
    rows_full_model = function(ns, A)
      local rows = ns.PanelLogic.rows({ member({ status = "LF |cffDeadmines" }) }, {}, never, true, 0, WALL)
      A.eq(#rows, 1)
      A.eq(rows[1].name, "Ginkan")
      A.eq(rows[1].class, "WARRIOR")
      A.eq(rows[1].level, 14)
      A.eq(rows[1].zoneText, "Elwynn Forest, Goldshire")
      A.eq(rows[1].status, "LF ||cffDeadmines")
      A.eq(rows[1].xp, 62)
      A.eq(rows[1].tags, {})
      A.eq(rows[1].offline, false)
      local only = ns.PanelLogic.rows({ member({ subzone = "" }) }, {}, never, true, 0, WALL)
      A.eq(only[1].zoneText, "Elwynn Forest")
    end,
    rows_add_layer_tag_and_filter = function(ns, A)
      local m = { member({ tags = { COMBAT = true } }) }
      A.eq(ns.PanelLogic.rows(m, {}, different, true, 0, WALL)[1].tags, { "LAYER", "COMBAT" })
      A.eq(ns.PanelLogic.rows(m, { tag_COMBAT = false }, different, true, 0, WALL)[1].tags, { "LAYER" })
      A.eq(ns.PanelLogic.rows(m, {}, different, false, 0, WALL)[1].tags, { "LAYER" })
      A.eq(ns.PanelLogic.rows(m, { tag_LAYER = false }, different, true, 0, WALL)[1].tags, { "COMBAT" })
      A.eq(ns.PanelLogic.rows(m, {}, never, true, 0, WALL)[1].tags, { "COMBAT" })
    end,
    rows_clamp_xp_and_ignore_peer_layer_tag = function(ns, A)
      local noXP = member({ name = "C" })
      noXP.xp = nil
      local rows = ns.PanelLogic.rows({ member({ name = "A|cff", xp = 250, tags = { LAYER = true, AFK = true } }),
        member({ name = "B", xp = -5 }), noXP }, {}, never, true, 0, WALL)
      A.eq(rows[1].name, "A||cff")
      A.eq(rows[1].xp, 100)
      A.eq(rows[1].tags, { "AFK" }, "a friend cannot send OTHER LAYER")
      A.eq(rows[2].xp, 0)
      A.eq(rows[3].xp, nil)
    end,
    rows_hide_offline_when_off = function(ns, A)
      local list = { member(), member({ name = "Stabz", online = false, lastSeen = WALL - 7200, tags = { COMBAT = true } }) }
      local rows = ns.PanelLogic.rows(list, { showOffline = true }, never, true, 0, WALL)
      A.eq(#rows, 2)
      A.eq(rows[2].offline, true)
      A.eq(rows[2].offlineText, "Offline, last seen 2h ago")
      A.eq(rows[2].tags, {}, "no activity tags on offline friends")
      rows = ns.PanelLogic.rows(list, { showOffline = false }, never, true, 0, WALL)
      A.eq(#rows, 1); A.eq(rows[1].name, "Ginkan")
    end,
    xp_text_fits_each_row_style = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.xpText("full", 12, 63, false), "Lv 12 \194\183 63%")
      A.eq(L.xpText("compact", 12, 63, false), "Lv 12 \194\183 63%")
      A.eq(L.xpText("tiny", 12, 63, false), "63%")
      A.eq(L.xpText("full", 60, 0, true), "Lv 60 \194\183 max level")
      A.eq(L.xpText("compact", 60, 0, true), "Lv 60 \194\183 max")
      A.eq(L.xpText("tiny", 60, 0, true), "max")
      A.eq(L.xpText("full", nil, 40, false), "40%")
      A.eq(L.xpText("full", 12, nil, false), nil, "XP unknown: no text")
      A.eq(L.xpText("tiny", 60, nil, true), "max")
    end,
    max_level_from_need_or_level = function(ns, A)
      local L = ns.PanelLogic
      A.ok(L.isMaxLevel({ level = 30, xpMax = 0 }, 60))
      A.ok(L.isMaxLevel({ level = 60 }, 60), "an older copy sends no xm")
      A.no(L.isMaxLevel({ level = 30, xpMax = 1000 }, 60))
      A.no(L.isMaxLevel({ level = 30 }, nil))
    end,
    thousands_and_durations = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.thousands(1234), "1,234"); A.eq(L.thousands(999), "999"); A.eq(L.thousands(1234567), "1,234,567")
      A.eq(L.thousands(0), "0"); A.eq(L.thousands(12.7), "12")
      A.eq(L.durationText(30), "About 1 min to level")
      A.eq(L.durationText(25 * 60 + 10), "About 25 min to level")
      A.eq(L.durationText(80 * 60), "About 1 h 20 min to level")
      A.eq(L.durationText(120 * 60 + 20), "About 2 h to level")
    end,
    time_to_level_only_with_a_real_pace = function(ns, A)
      local L = ns.PanelLogic
      local t = { first = 0, lastGain = 600, earned = 6000, active = 600, gains = 5 } -- 10 XP a second
      A.eq(L.timeToLevel(t, 1500, 700), 150)
      A.eq(L.timeToLevel(nil, 1500, 700), nil, "no pace yet")
      A.eq(L.timeToLevel(t, 0, 700), nil, "nothing left")
      A.eq(L.timeToLevel({ first = 0, lastGain = 60, earned = 600, active = 60, gains = 1 }, 1500, 70), nil,
        "one gain is not a pace")
      A.eq(L.timeToLevel({ first = 0, lastGain = 120, earned = 600, active = 120, gains = 3 }, 1500, 130), nil,
        "under 3 minutes of playing")
      A.eq(L.timeToLevel(t, 1500, 600 + ns.Config.XP_IDLE_AFTER + 1), nil, "idle: last gain too old")
      A.eq(L.timeToLevel({ first = 0, lastGain = 600, earned = 10, active = 600, gains = 2 }, 100000, 700), nil,
        "over 12 hours is a wild guess")
    end,
    tooltip_lines_for_a_friend = function(ns, A)
      local L = ns.PanelLogic
      local m = member({ level = 12, xp = 63, xpCur = 637, xpMax = 1871, rested = 2000,
        xpTrack = { first = 0, lastGain = 600, earned = 6000, active = 600, gains = 5 } })
      A.eq(L.tooltipLines(m, 700, 60), { "Level 12 \194\183 63%", "1,234 XP to level 13", "Rested: 2,000 XP",
        "About 2 min to level" })
      m.rested, m.xpTrack = 0, nil
      A.eq(L.tooltipLines(m, 700, 60), { "Level 12 \194\183 63%", "1,234 XP to level 13" })
      A.eq(L.tooltipLines(member({ level = 60, xp = 0, xpCur = 0, xpMax = 0, rested = 50 }), 700, 60),
        { "Level 60", "Max level" })
      local old = member({ level = 12, xp = 63 })   -- an older copy: no exact numbers
      A.eq(L.tooltipLines(old, 700, 60), { "Level 12 \194\183 63%" })
      A.eq(L.tooltipLines(member({ online = false, xpCur = 5, xpMax = 10 }), 700, 60), { "Level 14" },
        "offline: just the level")
    end,
    rows_carry_xp_text_and_tooltip = function(ns, A)
      local L = ns.PanelLogic
      local list = { member({ xpCur = 620, xpMax = 1000 }), member({ name = "Stabz", online = false }),
        member({ name = "Maxi", level = 60, xp = 0, xpMax = 0 }) }
      local rows = L.rows(list, { rowStyle = "compact" }, never, true, 0, WALL, nil, 60)
      A.eq(rows[1].xpText, "Lv 14 \194\183 62%")
      A.eq(rows[1].tip, { "Level 14 \194\183 62%", "380 XP to level 15" })
      A.eq(rows[2].xpText, nil, "offline rows keep today's look")
      A.eq(rows[2].tip, { "Level 14" })
      A.eq(rows[3].xpText, "Lv 60 \194\183 max"); A.ok(rows[3].atMax)
      rows = L.rows(list, { rowStyle = "tiny", xpText = false, xpTooltip = false }, never, true, 0, WALL, nil, 60)
      A.eq(rows[1].xpText, nil, "numbers switched off")
      A.eq(rows[1].tip, nil, "hover detail switched off")
      A.eq(L.rows(list, {}, never, true, 0, WALL)[1].xpText, "Lv 14 \194\183 62%", "full is the default style")
    end,
    self_member_carries_xp_numbers = function(ns, A)
      local m = ns.PanelLogic.selfMember("Twiz", { lv = "10", xp = "37", xc = "370", xm = "1000", rx = "40" })
      A.eq({ m.xpCur, m.xpMax, m.rested }, { 370, 1000, 40 })
    end,
    title_version_fits_the_row_style = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.titleVersion("full", "0.1.1"), "v0.1.1")
      A.eq(L.titleVersion("compact", "0.1.1"), "v0.1.1")
      A.eq(L.titleVersion("tiny", "0.1.1"), "", "tiny is too narrow")
      A.eq(L.titleVersion("full", nil), "")
      A.eq(L.titleVersion("full", "1|r"), "v1||r", "shown as plain text")
    end,
    visible_rules = function(ns, A)
      local v = ns.PanelLogic.visible
      A.eq(v({ hideInCombat = true }, { inCombat = true, onlineCount = 2 }), false)
      A.eq(v({ hideInCombat = false }, { inCombat = true, onlineCount = 2 }), true)
      A.eq(v({ hideWhenAlone = true }, { onlineCount = 0 }), false)
      A.eq(v({ hideWhenAlone = true }, { onlineCount = 1 }), true)
      A.eq(v({ hideInInstance = true }, { inInstance = true, onlineCount = 1 }), false)
      local defaults = ns.Modules.get("panel").defaults
      A.eq(v(defaults, { inCombat = true, inInstance = true, onlineCount = 0 }), true)
    end,
    rows_scroll_past_max = function(ns, A)
      local w = ns.PanelLogic.window
      A.eq({ w(12, 0, 8) }, { 1, 8 })
      A.eq({ w(12, 10, 8) }, { 5, 12 })
      A.eq({ w(5, 3, 8) }, { 1, 5 })
      A.eq({ w(12, -3, 8) }, { 1, 8 })
      A.eq({ w(0, 0, 8) }, { 1, 0 })
    end,
    class_icon_fallbacks = function(ns, A, W)
      local tex = W.env.CreateFrame("Frame"):CreateTexture()
      W.state.atlases["classicon-warrior"] = { width = 64, height = 64 }
      A.eq(ns.ClassIcon.apply(tex, "WARRIOR"), "atlas")
      A.eq(ns.ClassIcon.method(), "atlas")
      W.state.atlases["classicon-warrior"] = nil
      A.eq(ns.ClassIcon.apply(tex, "WARRIOR"), "texture")
      A.eq(ns.ClassIcon.method(), "texture")
      A.eq(ns.ClassIcon.apply(tex, "DRUIDX"), "none")
      A.eq(ns.ClassIcon.apply(tex, nil), "none")
      W.env.C_Texture = nil
      A.eq(ns.ClassIcon.apply(tex, "MAGE"), "texture")
      A.eq(ns.Log.errors(10), {})
    end,
    panel_module_settings_in_order = function(ns, A)
      local d = ns.Modules.get("panel")
      A.ok(d); A.eq(d.name, "Crew panel"); A.eq(d.tier, "module"); A.eq(d.defaultEnabled, true)
      local keys = {}
      for i, s in ipairs(d.settings) do keys[i] = s.key end
      A.eq(keys, { "scale", "bgAlpha", "rowStyle", "showZone", "showStatus", "showXP", "xpText", "xpTooltip",
        "fadeOut", "fadeAlpha", "locked", "grow", "hideInCombat", "hideInInstance", "hideWhenAlone", "showOffline", "sort", "showSelf", "tag_DEAD",
        "tag_LAYER", "tag_COMBAT", "tag_DUNGEON", "tag_TAXI", "tag_AFK" })
      A.eq(d.defaults.position, { point = "LEFT", x = 40, y = 100 })
      A.eq(d.defaults.scale, 1.0); A.eq(d.defaults.bgAlpha, 0.8); A.eq(d.defaults.rowStyle, "full")
      A.eq(d.defaults.fadeAlpha, 0.3); A.eq(d.defaults.grow, "down"); A.eq(d.defaults.sort, "online")
      local sort
      for _, s in ipairs(d.settings) do if s.key == "sort" then sort = s end end
      A.eq(sort.choices, { { "name", "Name" }, { "level", "Level" }, { "online", "Online first" },
        { "layer", "Same layer first" } })
    end,
    panel_loads_and_draws_without_errors = function(ns, A, W)
      start(ns, W)
      feedTwelve(ns, W)
      W:advance(1)
      A.eq(ns.Panel.isShown(), true)
      A.eq(ns.Panel.headerText(), "12 of 12 online")
      A.eq(#ns.Panel.models(), 12)
      A.eq(ns.Panel.rowCountForTest(), ns.Config.PANEL_MAX_ROWS)
      ns.Panel.scroll(-10)
      W:advance(1)
      A.eq(ns.Panel.firstRowForTest(), 5)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(1)
      ns.Modules.set("panel", "rowStyle", "tiny")
      ns.Modules.set("panel", "showSelf", true)
      ns.Modules.set("panel", "grow", "up")
      W:advance(1)
      A.eq(#ns.Panel.models(), 13)
      A.eq(ns.Panel.models()[1].name, "Twiz")
      ns.Modules.resetAll()
      W:advance(31)
      A.eq(#ns.Panel.models(), 12)
      A.eq(ns.Log.errors(10), {})
    end,
    panel_draws_level_progress_in_every_style = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Ginkan", "STATE", { cl = "MAGE", lv = "12", xp = "63", xc = "637", xm = "1871", rx = "2000",
        zn = "Elwynn Forest", ver = "0.1.0" })
      W:advance(1)
      local DOT = "\194\183"
      A.eq(ns.Panel.rowTextsForTest(1), { bar = "Lv 12 " .. DOT .. " 63%" }, "full: next to the bar, no corner")
      ns.Modules.set("panel", "rowStyle", "compact"); W:advance(1)
      A.eq(ns.Panel.rowTextsForTest(1), { corner = "Lv 12 " .. DOT .. " 63%" })
      ns.Modules.set("panel", "rowStyle", "tiny"); W:advance(1)
      A.eq(ns.Panel.rowTextsForTest(1), { corner = "63%" })
      ns.Modules.set("panel", "xpText", false); W:advance(1)
      A.eq(ns.Panel.rowTextsForTest(1), {}, "tiny without numbers: as before")
      ns.Modules.set("panel", "rowStyle", "compact"); W:advance(1)
      A.eq(ns.Panel.rowTextsForTest(1), { corner = "12" }, "compact without numbers: the level, as before")
      ns.Modules.set("panel", "rowStyle", "full"); W:advance(1)
      A.eq(ns.Panel.rowTextsForTest(1), { corner = "12" }, "full without numbers: as before")
      ns.Modules.resetAll(); W:advance(1)
      A.eq(ns.Modules.setting("panel", "xpText"), true)
      receive(ns, W, "Ginkan", "UPDATE", { lv = "60", xm = "0", xc = "0", xp = "0" }); W:advance(1)
      A.eq(ns.Panel.rowTextsForTest(1), { bar = "Lv 60 " .. DOT .. " max level" })
      A.eq(ns.Log.errors(10), {})
    end,
    row_tooltip_shows_xp_detail = function(ns, A, W)
      local tip = { lines = {}, shown = false }
      W.env.GameTooltip = {
        SetOwner = function(_, owner) tip.owner = owner; tip.lines = {} end,
        SetText = function(_, t) tip.lines[#tip.lines + 1] = t end,
        AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end,
        Show = function() tip.shown = true end,
        Hide = function() tip.shown = false end,
        IsOwned = function(_, f) return tip.owner == f end,
        IsShown = function() return tip.shown end,
      }
      start(ns, W)
      receive(ns, W, "Ginkan", "STATE", { cl = "MAGE", lv = "12", xp = "63", xc = "637", xm = "1871", rx = "2000",
        zn = "Elwynn Forest", ver = "0.1.0" })
      W:advance(1)
      local r = ns.Panel.rowFrameForTest(1)
      r._scripts.OnEnter(r)
      A.ok(tip.shown)
      A.eq(tip.lines, { "Ginkan", "Level 12 \194\183 63%", "1,234 XP to level 13", "Rested: 2,000 XP" })
      -- new numbers while the mouse is on the row: the tooltip follows
      receive(ns, W, "Ginkan", "UPDATE", { xc = "871", xp = "46" })
      W:advance(1)
      A.eq(tip.lines[3], "1,000 XP to level 13")
      r._scripts.OnLeave(r)
      A.no(tip.shown)
      ns.Modules.set("panel", "xpTooltip", false); W:advance(1)
      r._scripts.OnEnter(r)
      A.no(tip.shown, "hover detail switched off")
      A.eq(ns.Log.errors(10), {})
    end,
    panel_title_shows_the_version = function(ns, A, W)
      start(ns, W)
      W:advance(1)
      A.eq(ns.Panel.titleVersionForTest(), "v0.1.0")
      ns.Modules.set("panel", "rowStyle", "tiny")
      W:advance(1)
      A.eq(ns.Panel.titleVersionForTest(), "", "tiny: no room")
      ns.Modules.set("panel", "rowStyle", "compact")
      W:advance(1)
      A.eq(ns.Panel.titleVersionForTest(), "v0.1.0")
    end,
    panel_shows_a_gold_update_line = function(ns, A, W)
      start(ns, W)
      W:advance(1)
      A.eq(ns.Panel.updateLineForTest(), nil, "up to date: no line")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", ver = "0.2.0", rs = "0.1.0" })
      W:advance(1)
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.2.0")
      A.eq(#ns.Panel.models(), 1, "rows still drawn")
      local b = ns.Panel.updateLineButtonForTest()
      b._scripts.OnClick(b, "LeftButton")
      A.eq(ns.Updates.promptForTest().title, "Update available: v0.2.0", "a click shows how to update")
      ns.Modules.setEnabled("updates", false)
      W:advance(1)
      A.eq(ns.Panel.updateLineForTest(), nil, "Update reminders off: no line")
      A.eq(ns.Panel.titleVersionForTest(), "v0.1.0", "the version stays")
      ns.Modules.setEnabled("updates", true)
      W:advance(1)
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.2.0")
      ns.Modules.set("panel", "rowStyle", "tiny")
      W:advance(1)
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.2.0", "in every row style")
      A.eq(ns.Log.errors(10), {})
    end,
    a_broken_update_check_never_breaks_the_panel = function(ns, A, W)
      start(ns, W)
      ns.Updates.available = function() error("boom") end
      feedTwelve(ns, W)
      W:advance(1)
      A.eq(ns.Panel.isShown(), true)
      A.eq(#ns.Panel.models(), 12)
      A.eq(ns.Panel.updateLineForTest(), nil)
      A.ok(ns.Modules.isEnabled("panel"))
      for _, e in ipairs(ns.Log.errors(10)) do A.contains(e, "ERROR updates: ") end
    end,
    panel_redraws_once_per_frame = function(ns, A, W)
      start(ns, W)
      W:advance(1)
      local before = ns.Panel.redrawCountForTest()
      feedTwelve(ns, W)
      A.eq(ns.Panel.redrawCountForTest(), before, "no redraw until the next frame")
      W:advance(0.01)
      A.eq(ns.Panel.redrawCountForTest(), before + 1)
    end,
    panel_hides_in_fights_and_comes_back = function(ns, A, W)
      start(ns, W)
      feedTwelve(ns, W)
      ns.Modules.set("panel", "hideInCombat", true)
      W:advance(1)
      A.eq(ns.Panel.isShown(), true)
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(1)
      A.eq(ns.Panel.isShown(), false)
      W:fire("PLAYER_REGEN_ENABLED"); W:advance(1)
      A.eq(ns.Panel.isShown(), true)
    end,
    panel_hides_when_alone_if_asked = function(ns, A, W)
      start(ns, W)
      W:advance(1)
      A.eq(ns.Panel.isShown(), true)
      A.eq(ns.Panel.headerText(), "0 of 0 online")
      ns.Modules.set("panel", "hideWhenAlone", true); W:advance(1)
      A.eq(ns.Panel.isShown(), false)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12" }); W:advance(1)
      A.eq(ns.Panel.isShown(), true)
    end,
    panel_menu_items_work = function(ns, A, W)
      start(ns, W)
      feedTwelve(ns, W)
      W:advance(1)
      local items = ns.Panel.menuItems()
      local labels = {}
      for i, item in ipairs(items) do labels[i] = item.label end
      A.eq(labels, { "Show offline friends", "Lock position", "Row style: Full", "Hide during fights", "Set my status",
        "Open settings", "Hide panel" })
      A.eq(items[1].checked(), true)
      items[1].onClick(); A.eq(ns.Modules.setting("panel", "showOffline"), false)
      items[2].onClick(); A.eq(ns.Modules.setting("panel", "locked"), true)
      items[3].onClick(); A.eq(ns.Modules.setting("panel", "rowStyle"), "compact")
      items[4].onClick(); A.eq(ns.Modules.setting("panel", "hideInCombat"), true)
      items[5].onClick()
      items[6].onClick()
      items[7].onClick(); A.eq(ns.Modules.isEnabled("panel"), false)
      W:advance(1)
      A.eq(ns.Panel.isShown(), false)
      ns.Modules.setEnabled("panel", true); W:advance(1)
      A.eq(ns.Panel.isShown(), true)
      ns.Widgets.menu(W.env.UIParent, items)
      A.eq(ns.Log.errors(10), {})
    end,
    set_my_status_saves_once = function(ns, A, W)
      local frames, calls = recordingFrames(W)
      start(ns, W)
      ns.db.myStatus = "brb"
      local saves = {}
      local setStatus = ns.Self.setStatus
      ns.Self.setStatus = function(text) saves[#saves + 1] = text; setStatus(text) end
      local item
      for _, it in ipairs(ns.Panel.menuItems()) do if it.label == "Set my status" then item = it end end
      item.onClick()
      local box = frames.TwizCrewStatus
      A.ok(box, "our own status frame")
      local edit = box.edit
      A.eq(edit:GetText(), "brb", "prefilled with the current status")
      A.eq(callsOf(calls, edit, "SetMaxLetters"), { ns.Config.STATUS_MAX })
      edit:SetText("LF Deadmines")
      edit:GetScript("OnEnterPressed")(edit)
      edit:GetScript("OnEnterPressed")(edit)
      if edit:GetScript("OnEditFocusLost") then edit:GetScript("OnEditFocusLost")(edit) end
      A.eq(saves, { "LF Deadmines" }, "saved exactly once")
      A.eq(ns.db.myStatus, "LF Deadmines")
      -- Escape cancels
      item.onClick()
      A.eq(edit:GetText(), "LF Deadmines")
      edit:SetText("never saved")
      edit:GetScript("OnEscapePressed")(edit)
      A.eq(#saves, 1)
      A.eq(ns.db.myStatus, "LF Deadmines")
      -- empty text clears
      item.onClick()
      edit:SetText("")
      edit:GetScript("OnEnterPressed")(edit)
      A.eq(saves, { "LF Deadmines", "" })
      A.eq(ns.db.myStatus, "")
      A.eq(ns.Log.errors(10), {})
    end,
    panel_position_is_ours_and_drag_cannot_stick = function(ns, A, W)
      local frames, calls = recordingFrames(W)
      start(ns, W)
      W:advance(1)
      local root = frames.TwizCrewPanel
      A.ok(root)
      A.eq(callsOf(calls, root, "SetDontSavePosition"), { true }, "the game does not save the panel position")
      root:GetScript("OnDragStart")(root)
      A.ok(ns.Panel.isMovingForTest())
      root:GetScript("OnDragStop")(root)
      A.no(ns.Panel.isMovingForTest())
      A.eq(callsOf(calls, root, "SetUserPlaced"), { false })
      -- hidden in the middle of a drag: the drag ends
      root:GetScript("OnDragStart")(root)
      ns.Modules.setEnabled("panel", false)
      A.no(ns.Panel.isMovingForTest(), "hiding ends the drag")
      ns.Modules.setEnabled("panel", true)
      root:GetScript("OnDragStart")(root)
      root:GetScript("OnHide")(root)
      A.no(ns.Panel.isMovingForTest(), "OnHide ends the drag")
      local stops = 0
      for _, c in ipairs(calls) do if c.frame == root and c.method == "StopMovingOrSizing" then stops = stops + 1 end end
      A.eq(stops, 3)
      A.eq(ns.Log.errors(10), {})
    end,
    widgets_build_without_errors = function(ns, A, W)
      local value = { t = false, s = 1, c = "a", x = "hi" }
      local p = W.env.UIParent
      local t = ns.Widgets.toggle(p, "Toggle", "Info", function() return value.t end, function(v) value.t = v end)
      t.control:GetScript("OnClick")(t.control, "LeftButton")
      A.eq(value.t, true)
      local c = ns.Widgets.choice(p, "Choice", "Info", { { "a", "A" }, { "b", "B" }, { "c", "C" } },
        function() return value.c end, function(v) value.c = v end)
      c.control:GetScript("OnClick")(c.control, "LeftButton"); A.eq(value.c, "b")
      c.control:GetScript("OnClick")(c.control, "RightButton"); A.eq(value.c, "a")
      c.control:GetScript("OnClick")(c.control, "RightButton"); A.eq(value.c, "c")
      local s = ns.Widgets.slider(p, "Slider", "Info", 0.5, 2, 0.05, function() return value.s end,
        function(v) value.s = v end, ns.Widgets.percent)
      s.control:GetScript("OnValueChanged")(s.control, 1.2345)
      A.eq(value.s, 1.25)
      A.eq(ns.Widgets.percent(1.25), "125%")
      local x = ns.Widgets.text(p, "Text", "Info", function() return value.x end, function(v) value.x = v end)
      A.ok(x.control)
      local secret
      local create = W.env.CreateFrame
      W.env.CreateFrame = function(...)
        local f = create(...)
        rawset(f, "SetPassword", function(_, on) secret = on end)
        return f
      end
      ns.Widgets.text(p, "Code", "Info", function() return "x" end, function() end, true)
      A.eq(secret, true)
      W.env.CreateFrame = create
      local pill = ns.Widgets.tagPill(p)
      pill:SetTag("LAYER")
      A.eq(pill.tag, "LAYER")
      local info = ns.Widgets.infoButton(p, "Title", "Some text")
      info:GetScript("OnEnter")(info); info:GetScript("OnClick")(info); info:GetScript("OnLeave")(info)
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
