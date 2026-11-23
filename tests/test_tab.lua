-- The crew tab (2026-11-23, replaces the minimized title bar): the pure rules (PanelLogic: view, hover, the tab's
-- place, marks, how long news stays, the slide; FeedLogic: news-only kinds, the queue's own lengths), then the panel
-- tucked into its tab: hover and click, the slide, news sliding out (plain 5 s, with a button 12 s), the mouse holding
-- it, the missed count and glow, scope, fights, layer / run-off / calendar news, the pop-ups it may replace, the Keep
-- open switch and its other ways in, dragging the tab, the right edge, scale and Hall of Shame width, and the first run
-- for an existing user.

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

-- Boots with the login quiet time over (a new install: tucked into the tab, the default).
local function ready(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W.env.TwizCrewDB.modules.panel.settings.noticeScope = "guild" -- these tests are about the tab, not who it is for
  W.env.TwizCrewDB.modules.panel.settings.showNoAddon = false -- friends who talk, not "no addon" rows
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(40)
end

local function root(ns) return ns.Panel.rootForTest() end
local function tabFrame(ns) return ns.Panel.tabForTest() end

-- The mouse on the tab / on the panel (the stub's frames answer IsMouseOver false unless told).
local function mouseTab(ns, on)
  local t = tabFrame(ns)
  rawset(t, "IsMouseOver", function() return on == true end)
  if on then t._scripts.OnEnter(t) end
end
local function mousePanel(ns, on)
  rawset(root(ns), "IsMouseOver", function() return on == true end)
end

local function friend(W, ns, name, extra)
  local f = { cl = "MAGE", lv = "12", zn = "Elwynn Forest", sz = "Goldshire", tg = "", ins = "0", ver = "0.1.0" }
  for k, v in pairs(extra or {}) do f[k] = v end
  receive(W, ns, name, "STATE", f)
end

local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function barText(ns) return plain(ns.Panel.barTextForTest()) end

local function hasPopup(ns, part)
  for _, t in ipairs(ns.Popups.shownForTest()) do if t:find(part, 1, true) then return true end end
  return false
end

-- Slides out by resting the mouse on the tab, slide finished.
local function hoverOpen(W, ns)
  mouseTab(ns, true)
  W:advance(0.6)
  ns.Panel.finishSlideForTest()
end

return {
  files = "toc",
  tests = {
    -------------------------------------------------------------------------------------------------- pure
    view_decides_tab_peek_or_full = function(ns, A)
      local V = ns.PanelLogic.view
      A.eq(V({}), "tab", "tucked away by default")
      A.eq(V({ keepOpen = true, news = true }), "full", "kept open: everything, as before")
      A.eq(V({ open = true }), "full", "the mouse or a click opened it")
      A.eq(V({ news = true }), "peek")
      A.eq(V({ news = true, inCombat = true }), "tab", "never news sliding out in a fight")
      A.eq(V({ open = true, inCombat = true }), "full", "a click opens it in a fight too")
      A.eq(V(nil), "tab")
    end,

    hover_opens_after_the_pause_and_not_while_busy = function(ns, A)
      local H = ns.PanelLogic.hoverOpens
      local ok = { setting = true, restedFor = 0.35, delay = 0.3 }
      A.ok(H(ok))
      A.no(H({ setting = true, restedFor = 0.2, delay = 0.3 }), "sweeping past the tab does not open it")
      for _, k in ipairs({ "mouselook", "button", "inCombat", "inDungeon" }) do
        local c = { setting = true, restedFor = 5, delay = 0.3 }
        c[k] = true
        A.no(H(c), k)
      end
      A.no(H({ setting = false, restedFor = 5 }), "the setting is off: only a click")
    end,

    tab_count_place_and_snap = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.tabCount(3), "3"); A.eq(L.tabCount(0), "0"); A.eq(L.tabCount(nil), "0"); A.eq(L.tabCount(150), "99+")
      A.eq(L.clampTabY(100, 1080, 86, 1), 100)
      A.eq(L.clampTabY(900, 1080, 86, 1), 497, "kept on the screen")
      A.eq(L.clampTabY(-900, 1080, 86, 1), -497)
      A.eq(L.clampTabY(900, 1080, 86, 2), 227, "in the tab's own scaled units")
      A.eq(L.clampTabY(900, nil, 86, 1), 900, "screen unknown: as it is")
      local side, y = L.tabSnap(1800, 540 + 100, 1920, 1080, 86, 1)
      A.eq({ side, y }, { "right", 100 }, "dropped on the right half: the right edge")
      side, y = L.tabSnap(100, 2000, 1920, 1080, 86, 1)
      A.eq({ side, y }, { "left", 497 }, "a drop off the top is kept on screen")
      A.eq(L.tabSnap(nil, 1, 1920, 1080, 86, 1), nil)
    end,

    tab_from_the_old_panel_position = function(ns, A)
      local L = ns.PanelLogic
      local side, y = L.tabFromPosition({ point = "LEFT", x = 40, y = 100 }, 1920, 1080, 246, 300, 86, 1)
      A.eq(side, "left", "the default spot")
      A.eq(y, 190, "about the panel's height (a little under its top)")
      side = L.tabFromPosition({ point = "TOPLEFT", x = 1500, y = -200 }, 1920, 1080, 246, 300, 86, 1)
      A.eq(side, "right")
      side = L.tabFromPosition({ point = "BOTTOMLEFT", x = 1600, y = 50 }, 1920, 1080, 246, 300, 86, 1)
      A.eq(side, "right", "a grow-up panel")
      side = L.tabFromPosition({ point = "CENTER", x = -300, y = 0 }, 1920, 1080, 246, 300, 86, 1)
      A.eq(side, "left")
      A.eq({ L.tabFromPosition(nil, 1920, 1080) }, { "left", 100 }, "nothing saved: the default")
      A.eq({ L.tabFromPosition({ point = "LEFT" }, nil, nil) }, { "left", 100 }, "screen unknown")
    end,

    tab_marks_only_for_party_and_pinned = function(ns, A)
      local M = ns.PanelLogic.tabMarks
      A.eq(M({ { section = "party", tags = { "DEAD" } } }), { dead = true, layer = false })
      A.eq(M({ { section = "pinned", tags = { "LAYER", "AFK" } } }), { dead = false, layer = true })
      A.eq(M({ { section = "guild", tags = { "DEAD", "LAYER" } } }), { dead = false, layer = false }, "not the guild")
      A.eq(M({ { section = "pinned", offline = true, tags = { "DEAD" } } }), { dead = false, layer = false })
      A.eq(M(nil), { dead = false, layer = false })
    end,

    reactable_news_stays_longer = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.REACT_SECONDS, 12)
      A.ok(L.newsReactable("levelup", nil, { cheer = true }))
      A.no(L.newsReactable("levelup", nil, { cheer = false, mock = true }), "already congratulated")
      A.ok(L.newsReactable("died", nil, { mock = true }))
      A.ok(L.newsReactable("mock", "in", { mock = true }), "a mock aimed at me: mock back")
      A.ok(L.newsReactable("congrats", "in", { mock = true }))
      A.no(L.newsReactable("mock", "seen", { mock = true }))
      A.no(L.newsReactable("online", nil, { cheer = true, mock = true }))
      A.eq({ L.newsSeconds(true, 5, 3) }, { 12, 5 })
      A.eq({ L.newsSeconds(false, 5, 3) }, { 5, 3 })
      A.eq({ L.newsSeconds(false, 2, 3) }, { 2, 2 })
    end,

    slide_eases_and_ends = function(ns, A)
      local S = ns.PanelLogic.slideWidth
      A.eq({ S(0, 200, 10, 0.2, 10) }, { 0, false })
      local mid = S(0, 200, 10, 0.2, 10.1)
      A.ok(mid > 100 and mid < 200, "eased out: past half way at half the time: " .. mid)
      A.eq({ S(0, 200, 10, 0.2, 10.2) }, { 200, true })
      A.eq({ S(200, 0, 10, 0.2, 11) }, { 0, true })
      A.eq({ S(0, 50, 10, 0, 10) }, { 50, true }, "no time: at once")
    end,

    labels = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.keepLabel(false), "Keep open"); A.eq(L.keepLabel(true), "Tuck away")
      A.eq(L.keepSwitchText(false, "full"), "Keep open: OFF"); A.eq(L.keepSwitchText(true, "compact"), "Keep open: ON")
      A.eq(L.keepSwitchText(true, "tiny"), "Keep: ON"); A.eq(L.keepSwitchText(false, "tiny"), "Keep: OFF")
      A.eq(L.barText(nil, "2 here"), "2 here"); A.eq(L.barText("Frostie died", "2 here"), "Frostie died")
      A.eq(L.noticeClickText("calnote"), "Click to open the calendar")
      A.eq(L.noticeClickText("died"), "Click to open the recent activity list")
      local x, y = L.rescalePosition(600, -300, 1.0, 1.5)
      A.eq({ x, y }, { 400, -200 })
    end,

    news_only_kinds_and_the_queue = function(ns, A)
      local FL = ns.FeedLogic
      A.eq(FL.newsEntry("otherlayer", "Frostie").line, "Frostie is on another layer")
      A.eq(FL.newsEntry("samelayer", "Frostie").line, "Frostie is back on your layer")
      A.eq(FL.newsEntry("runaway", "Frostie", { zone = "140 yd" }).line, "Frostie is running off (140 yd)")
      A.eq(FL.newsEntry("calnote", "Frostie").line, "New calendar note from Frostie")
      A.eq(FL.newsEntry("calreply", "Frostie").line, "Frostie answered your calendar note")
      A.eq(FL.newsEntry("died", "Frostie"), nil, "recorded kinds come from the feed")
      A.no(FL.isKind("calnote"), "never in the Recent list")
      A.ok(FL.isNoticeKind(FL.newsEntry("calnote", "Frostie")))
      local bar = FL.newBar({ seconds = 5, short = 3, lengths = function(e) return e.len, e.busy end })
      bar:push({ kind = "levelup", len = 12, busy = 5 }, 100)
      A.eq(bar:endsAt(), 112, "its own length")
      bar:push({ kind = "online", len = 5, busy = 3 }, 101)
      bar:push({ kind = "online", len = 5, busy = 3 }, 101)
      A.eq(bar:endsAt(), 105, "two waiting: the busy length")
      A.ok(bar:has("online")); A.no(bar:has("calnote"))
      local b2 = FL.newBar({ seconds = 5 })
      b2:push({ kind = "x" }, 0)
      A.eq(b2:endsAt(), 5)
      b2:endAfter(4.8, 0.6)
      A.ok(math.abs(b2:endsAt() - 5.4) < 1e-9, "the mouse just left: a moment longer")
      b2:endAfter(1, 0.6)
      A.ok(math.abs(b2:endsAt() - 1.6) < 1e-9, "held news goes soon after the mouse leaves")
    end,

    -------------------------------------------------------------------------------------------------- the tab
    tucked_by_default_with_the_panel_laid_out_behind = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8) -- (after the news that Frostie came online)
      A.eq(ns.Modules.setting("panel", "keepOpen"), false, "the tab is the default")
      A.eq(ns.Panel.viewForTest(), "tab")
      local st = ns.Panel.tabStateForTest()
      A.ok(st.shown, "the tab is on screen")
      A.eq(st.count, "1", "here: me (nobody in my party or pinned)")
      A.eq(st.side, "left")
      A.no(ns.Panel.holderForTest():IsShown(), "the panel is tucked away")
      A.ok(ns.Panel.isShown())
      A.ok(ns.Panel.rowCountForTest() >= 1, "laid out behind the closed holder, ready to slide out")
      A.ok(root(ns):GetParent() == ns.Panel.holderForTest(), "the panel hangs in the holder")
      ns.Panel.pin("Frostie"); W:advance(1)
      A.eq(ns.Panel.tabStateForTest().count, "2", "a pinned friend online counts")
      A.eq(ns.Log.errors(10), {})
    end,

    hover_rests_then_the_panel_slides_out_and_back = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      mouseTab(ns, true)
      W:advance(0.2)
      A.eq(ns.Panel.viewForTest(), "tab", "a short pause first")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "full", "the mouse rested on the tab")
      A.ok(ns.Panel.holderForTest():IsShown())
      A.ok(ns.Panel.slideForTest(), "sliding")
      A.ok(ns.Panel.holderWidthForTest() < root(ns):GetWidth(), "not all at once")
      W:advance(0.3)
      A.eq(ns.Panel.slideForTest(), nil, "the slide is over")
      A.eq(ns.Panel.holderWidthForTest(), root(ns):GetWidth(), "the whole panel is out")
      A.eq(ns.Panel.openForTest().by, "hover")
      -- the mouse moves from the tab onto the panel: stays out
      mouseTab(ns, false); mousePanel(ns, true)
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "full")
      mousePanel(ns, false)
      W:advance(0.6)
      A.eq(ns.Panel.viewForTest(), "full", "it waits about a second")
      W:advance(0.6)
      A.eq(ns.Panel.viewForTest(), "tab", "then slides back")
      A.ok(ns.Panel.holderForTest():IsShown(), "sliding back in")
      W:advance(0.3)
      A.no(ns.Panel.holderForTest():IsShown(), "tucked away")
      A.eq(ns.Log.errors(10), {})
    end,

    a_menu_from_the_panel_keeps_it_out = function(ns, A, W)
      ready(W)
      hoverOpen(W, ns)
      mouseTab(ns, false)
      local menu = ns.Panel.tabMenuItems and ns.Widgets.menu(tabFrame(ns), ns.Panel.tabMenuItems())
      ns.Panel._.menuAnchor = tabFrame(ns)
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "full", "its right-click menu is open")
      menu:Hide()
      W:advance(1.5)
      A.eq(ns.Panel.viewForTest(), "tab")
    end,

    no_hover_while_turning_the_camera_in_a_fight_or_a_dungeon = function(ns, A, W)
      ready(W)
      W.state.mouselook = true
      mouseTab(ns, true)
      W:advance(2)
      A.eq(ns.Panel.viewForTest(), "tab", "turning the camera")
      W.state.mouselook = false
      W:advance(0.2)
      A.eq(ns.Panel.viewForTest(), "tab", "the pause starts again")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "full")
      mouseTab(ns, false); W:advance(2); ns.Panel.finishSlideForTest()
      W.state.mouseDown.RightButton = true
      mouseTab(ns, true); W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "a mouse button held")
      W.state.mouseDown.RightButton = false
      mouseTab(ns, false); W:advance(0.2)
      -- a fight: hover does not open, a click does
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      mouseTab(ns, true); W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "no hover in a fight")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton")
      W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "full", "a click opens it in a fight")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton")
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "a click closes it")
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "and it does not slide right back out under the resting mouse")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      mouseTab(ns, false); W:advance(0.2)
      -- a dungeon: the same
      W.state.inInstance, W.state.instanceType = true, "party"
      mouseTab(ns, true); W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "no hover in a dungeon")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(ns.Log.errors(10), {})
    end,

    hover_setting_off_only_a_click_opens = function(ns, A, W)
      ready(W)
      A.eq(ns.Modules.setting("panel", "barHover"), true, "on by default")
      ns.Modules.set("panel", "barHover", false)
      mouseTab(ns, true); W:advance(2)
      A.eq(ns.Panel.viewForTest(), "tab")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(ns.Panel.openForTest().by, "click")
    end,

    nobody_here_the_tab_still_opens = function(ns, A, W)
      W.state.guild.members = { W.state.guild.members[1] }
      ready(W)
      A.eq(ns.Panel.tabStateForTest().count, "1")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(ns.Log.errors(10), {})
    end,

    -------------------------------------------------------------------------------------------------- news
    plain_news_slides_out_for_five_seconds = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek", "the news slid out")
      A.eq(ns.Panel.noticeForTest().kind, "online")
      A.contains(barText(ns), "Frostie came online")
      A.eq(ns.Panel.rowCountForTest(), 1, "with that friend's row")
      A.eq(ns.Panel.models()[1].key, "Frostie")
      A.ok(ns.Panel.holderForTest():IsShown())
      W:advance(4)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(1.2)
      A.eq(ns.Panel.viewForTest(), "tab", "back after about 5 s")
      W:advance(0.5)
      A.no(ns.Panel.holderForTest():IsShown())
      A.eq(ns.Log.errors(10), {})
    end,

    news_with_a_button_stays_twelve_seconds = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      W:advance(12)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.noticeForTest().kind, "levelup")
      A.ok(ns.Panel.rowCheerShownForTest(1), "the Congrats button is on the row")
      W:advance(8)
      A.eq(ns.Panel.viewForTest(), "peek", "still out after 8 s")
      W:advance(4.5)
      A.eq(ns.Panel.viewForTest(), "tab", "gone after about 12 s")
      W:advance(1)
      receive(W, ns, "Ginkan", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      W:advance(0.3)
      A.eq(ns.Panel.noticeForTest().kind, "died")
      A.ok(ns.Panel.rowMockShownForTest(1), "Mock after a death")
      W:advance(8)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(5)
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "lol" })
      W:advance(0.3)
      A.eq(ns.Panel.noticeForTest().kind, "mock")
      A.ok(ns.Panel.rowMockShownForTest(1), "Mock back on a mock aimed at me")
      A.eq(ns.Panel.rowFrameForTest(1).mock.text:GetText(), "Mock", "(Ginkan is still dead: plain Mock)")
      A.eq(ns.Log.errors(10), {})
    end,

    mock_back_and_clicking_congrats_on_the_news_row = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(12)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats", k = "g" })
      W:advance(0.3)
      A.eq(ns.Panel.noticeForTest().kind, "congrats")
      A.eq(ns.Panel.rowFrameForTest(1).mock.text:GetText(), "Mock back")
      local mocked
      ns.Roasts.mock = function(name) mocked = name; return "ha" end
      local r = ns.Panel.rowFrameForTest(1)
      r.mock._scripts.OnClick(r.mock)
      A.eq(mocked, "Frostie")
      W:advance(13)
      local cheered
      ns.Roasts.cheer = function(name) cheered = name; return "Grats" end
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      r = ns.Panel.rowFrameForTest(1)
      r.cheer._scripts.OnClick(r.cheer)
      A.eq(cheered, "Frostie", "the Congrats button on the slid-out row works")
    end,

    the_mouse_holds_news_and_it_leaves_shortly_after = function(ns, A, W)
      ready(W)
      mousePanel(ns, true)
      friend(W, ns, "Frostie")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(20)
      A.eq(ns.Panel.viewForTest(), "peek", "the mouse keeps it out")
      mousePanel(ns, false)
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek", "a moment longer")
      W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "tab", "then it leaves")
    end,

    right_click_menu_keeps_the_news_out = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(0.3)
      local r = ns.Panel.rowFrameForTest(1)
      r._scripts.OnMouseUp(r, "RightButton")
      W:advance(10)
      A.eq(ns.Panel.viewForTest(), "peek", "its row menu is open")
      ns.Widgets.menuFrame():Hide()
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab")
    end,

    news_queues_one_after_the_other = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      W:advance(0.2)
      A.eq(ns.Panel.noticeForTest().who, "Frostie")
      A.eq(ns.Panel.barForTest():waiting(), 1)
      W:advance(5.2)
      A.eq(ns.Panel.noticeForTest().who, "Ginkan", "then the second")
      A.eq(ns.Panel.models()[1].key, "Ginkan")
    end,

    missed_count_glow_and_opening_clears_them = function(ns, A, W)
      ready(W)
      A.no(ns.Panel.tabStateForTest().badge)
      A.eq(ns.Panel.tabStateForTest().glow, 0)
      friend(W, ns, "Frostie")
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats", k = "g" })
      W:advance(3)
      local st = ns.Panel.tabStateForTest()
      A.eq(st.missed, 2); A.ok(st.badge, "the red number")
      A.ok(st.glow >= 0.35, "the tab glows")
      W:advance(60)
      A.eq(ns.Panel.tabStateForTest().missed, 2, "it stays until you look")
      A.ok(ns.Panel.tabStateForTest().glow >= 0.35)
      hoverOpen(W, ns)
      A.eq(ns.Panel.tabStateForTest().missed, 0, "opening the panel counts as seen")
      A.eq(ns.Panel.tabStateForTest().glow, 0)
      -- the tab's menu reaches the Recent list
      mouseTab(ns, false); W:advance(2)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Again", k = "g" })
      W:advance(1)
      local item
      for _, it in ipairs(ns.Panel.tabMenuItems()) do if it.label:find("^Recent activity") then item = it end end
      A.eq(item.label, "Recent activity (1 new)")
      item.onClick()
      A.ok(ns.Recent.isShown())
      A.eq(ns.Panel.tabStateForTest().missed, 0)
    end,

    scope_is_party_and_pinned_by_default = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      ns.db.modules.panel.settings.noticeScope = nil -- the default
      ns.Panel.barForTest():clearMissed()
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 0, "a guildmate who is not close: nothing")
      A.eq(ns.Panel.viewForTest(), "tab")
      ns.Panel.pin("Frostie")
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 1, "pinned: news")
      A.eq(ns.Panel.viewForTest(), "peek")
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "Grats", k = "g" })
      W:advance(0.2)
      A.eq(ns.Panel.barForTest().missed, 2, "a mock at me always counts")
    end,

    a_fight_counts_but_slides_nothing = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      ns.Panel.barForTest():clearMissed()
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "tab", "nothing slides out in a fight")
      A.eq(ns.Panel.barForTest().missed, 1, "but it is counted")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "tab", "and it is not replayed after")
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "tab", "a fight takes news back in")
    end,

    slide_out_off_counts_only = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "peek", false)
      friend(W, ns, "Frostie")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "tab")
      A.eq(ns.Panel.barForTest().missed, 1)
      ns.Modules.set("panel", "peek", true)
      ns.Modules.set("panel", "peekSeconds", 2)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats", k = "g", })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
    end,

    layer_news_and_its_popups = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      ns.Bus.fire("LAYER_RELATION", "Frostie", "unknown", "different")
      W:advance(1)
      A.eq(ns.Panel.noticeForTest().kind, "otherlayer")
      A.contains(barText(ns), "Frostie is on another layer")
      A.ok(hasPopup(ns, "Frostie"), "the layer pop-up still shows (the switch is off)")
      W:advance(8)
      ns.Bus.fire("LAYER_RELATION", "Frostie", "unknown", "different")
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "said once")
      ns.Bus.fire("LAYER_RELATION", "Frostie", "different", "same")
      W:advance(0.3)
      A.contains(barText(ns), "Frostie is back on your layer")
      -- "show news on the tab, not as pop-ups": the layer pop-up is not made
      W:advance(8)
      ns.Modules.set("panel", "barInstead", true)
      local before = #ns.Popups.shownForTest()
      ns.Bus.fire("LAYER_RELATION", "Frostie", "same", "different")
      W:advance(1)
      A.eq(#ns.Popups.shownForTest(), before, "no pop-up")
      A.eq(ns.Panel.noticeForTest().kind, "otherlayer", "the tab has it")
      -- clicking a layer line opens the whole panel
      ns.Panel.noticeClicked()
      W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(ns.Log.errors(10), {})
    end,

    running_off_news = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      ns.Bus.fire("RUNNING_OFF", "Frostie", 140)
      W:advance(0.3)
      A.eq(ns.Panel.noticeForTest().kind, "runaway")
      A.contains(barText(ns), "Frostie is running off")
      local pointed
      ns.BigArrow.point = function(t) pointed = t.name end
      ns.Panel.noticeClicked()
      A.eq(pointed, "Frostie", "a click: the big arrow")
    end,

    a_new_calendar_note_slides_out_once = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      local today = math.floor(ns.Diary.now() / 86400)
      local soon = ns.Notes.dateKey(ns.CalendarLogic.civil(today + 2))
      receive(W, ns, "Frostie", "CALN", { k = "frost123-3000", d = soon, t = "Stockade", i = "2", b = "Frostie", u = "3000" })
      receive(W, ns, "Frostie", "CALN", { k = "frost123-3001", d = soon, t = "Deadmines", i = "2", b = "Frostie", u = "3001" })
      W:advance(0.3)
      A.eq(ns.Panel.noticeForTest().kind, "calnote")
      A.contains(barText(ns), "New calendar note from Frostie")
      A.eq(ns.Panel.rowCountForTest(), 0, "no row: just the line")
      A.eq(ns.Panel.barForTest():waiting(), 0, "a sync of many notes says it once")
      ns.Panel.noticeClicked()
      A.ok(ns.Calendar.isShown(), "a click opens the calendar")
      A.eq(ns.Log.errors(10), {})
    end,

    -------------------------------------------------------------------------------------------------- pop-ups
    popups_as_before_unless_the_switch_is_on = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(4)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.ok(hasPopup(ns, "Frostie is online")); A.ok(hasPopup(ns, "reached level 13"))
      A.ok(ns.Panel.barForTest().missed >= 2, "and the tab too")
    end,

    the_switch_replaces_online_died_levelup_popups = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "barInstead", true)
      friend(W, ns, "Frostie")
      W:advance(4)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      receive(W, ns, "Frostie", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      W:advance(4)
      A.eq(ns.Popups.shownForTest(), {}, "no pop-ups: the tab shows them")
      A.ok(ns.Panel.barForTest().missed >= 3)
    end,

    popups_return_when_kept_open_hidden_or_the_feed_is_off = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "barInstead", true)
      ns.Modules.set("panel", "keepOpen", true)
      friend(W, ns, "Frostie")
      W:advance(4)
      A.ok(hasPopup(ns, "Frostie is online"), "kept open: pop-ups as always")
      ns.Modules.set("panel", "keepOpen", false)
      ns.Modules.set("panel", "peek", false)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.ok(hasPopup(ns, "reached level 13"), "nothing slides out of the tab: the pop-up stays")
      ns.Modules.set("panel", "peek", true)
      ns.Modules.setEnabled("activity", false)
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      W:advance(1)
      A.ok(hasPopup(ns, "reached level 14"), "no feed, no news on the tab")
      ns.Modules.setEnabled("activity", true)
      ns.Modules.setEnabled("panel", false)
      receive(W, ns, "Frostie", "UPDATE", { lv = "15" })
      W:advance(1)
      A.ok(hasPopup(ns, "reached level 15"), "no tab on screen")
    end,

    -------------------------------------------------------------------------------------------------- keep open
    keep_open_switch_at_the_top = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      hoverOpen(W, ns)
      local keep = ns.Panel.keepSwitchForTest()
      A.ok(keep:IsShown(), "the Keep open switch is on the slid-out panel")
      A.eq(ns.Panel.keepTextForTest(), "Keep open: OFF")
      keep._scripts.OnClick(keep)
      W:advance(0.2)
      A.eq(ns.Modules.setting("panel", "keepOpen"), true)
      A.eq(ns.Panel.viewForTest(), "full")
      A.no(ns.Panel.tabStateForTest().shown, "the tab is hidden")
      A.ok(root(ns):GetParent() == W.env.UIParent, "an ordinary window again")
      A.eq(ns.Panel.keepTextForTest(), "Keep open: ON")
      A.ok(keep:IsShown(), "and the switch is still there to tuck it away")
      ns.Modules.set("panel", "rowStyle", "tiny"); W:advance(0.2)
      A.eq(ns.Panel.keepTextForTest(), "Keep: ON")
      keep._scripts.OnClick(keep)
      W:advance(0.2)
      A.eq(ns.Modules.setting("panel", "keepOpen"), false)
      A.ok(ns.Panel.tabStateForTest().shown)
      A.eq(ns.Panel.keepTextForTest(), "Keep: OFF")
      -- the panel is dragged only while kept open; the fade only then too
      A.eq(root(ns)._scripts.OnUpdate, nil, "no fade while tucked")
      ns.Modules.set("panel", "keepOpen", true); W:advance(0.2)
      A.eq(type(root(ns)._scripts.OnUpdate), "function", "the fade with Keep open")
      A.eq(ns.Log.errors(10), {})
    end,

    keep_open_tip_and_the_other_ways_in = function(ns, A, W)
      ready(W)
      A.eq((ns.Help.tip("keepOpen")), "Keep open")
      A.no(select(2, ns.Help.tip("keepOpen")):lower():find("pin"), "never called a pin")
      tc(W, "mini")
      A.eq(ns.Modules.setting("panel", "keepOpen"), true, "/tc mini")
      tc(W, "minimize")
      A.eq(ns.Modules.setting("panel", "keepOpen"), false, "the old word too")
      W.env.TwizCrew_Binding("mini")
      A.eq(ns.Modules.setting("panel", "keepOpen"), true, "the key binding")
      local labels = {}
      for i, item in ipairs(ns.Panel.menuItems()) do labels[i] = item.label end
      A.eq(labels[3], "Tuck away", "the title bar's menu")
      local mm
      for _, it in ipairs(ns.MinimapButton.menuItems()) do if it.label == "Tuck away" then mm = it end end
      A.ok(mm, "the minimap button's menu")
      mm.onClick()
      A.eq(ns.Modules.setting("panel", "keepOpen"), false)
      A.eq(ns.Panel.tabMenuItems()[1].label, "Keep open", "the tab's menu")
      -- hidden: the key shows it as it was left
      ns.Modules.setEnabled("panel", false)
      A.no(ns.Panel.tabStateForTest().shown, "no tab while the panel is hidden")
      W.env.TwizCrew_Binding("mini")
      A.ok(ns.Modules.isEnabled("panel"))
      A.eq(ns.Modules.setting("panel", "keepOpen"), false)
      ns.Modules.set("panel", "keepOpen", true)
      ns.Modules.resetAll(); W:advance(1)
      A.eq(ns.Modules.setting("panel", "keepOpen"), false, "Reset to defaults: the tab")
      A.eq(ns.Panel.viewForTest(), "tab")
    end,

    hide_rules_hide_the_tab_too = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "hideInCombat", true)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(1)
      A.no(ns.Panel.isShown())
      A.no(ns.Panel.tabStateForTest().shown, "hidden in a fight")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED"); W:advance(1)
      A.ok(ns.Panel.tabStateForTest().shown)
      ns.Modules.set("panel", "hideInInstance", true)
      W.state.inInstance, W.state.instanceType = true, "raid"
      W:fire("PLAYER_ENTERING_WORLD"); W:advance(1)
      A.no(ns.Panel.tabStateForTest().shown, "hidden in a raid")
      A.eq(ns.Log.errors(10), {})
    end,

    -------------------------------------------------------------------------------------------------- the tab's place
    drag_the_tab_along_and_across = function(ns, A, W)
      ready(W)
      rawset(W.env.UIParent, "GetWidth", function() return 1920 end)
      rawset(W.env.UIParent, "GetHeight", function() return 1080 end)
      local t = tabFrame(ns)
      rawset(t, "GetCenter", function() return 1850, 740 end)
      t._scripts.OnDragStart(t)
      t._scripts.OnDragStop(t)
      A.eq(ns.Modules.setting("panel", "tabSide"), "right", "dropped near the right edge")
      A.eq(ns.Modules.setting("panel", "tabY"), 200)
      local p = { t:GetPoint(1) }
      A.eq({ p[1], p[3], p[5] }, { "RIGHT", "RIGHT", 200 })
      t._scripts.OnClick(t, "LeftButton")
      A.eq(ns.Panel.openForTest(), nil, "the drop is not a click")
      -- locked: no drag
      ns.Modules.set("panel", "locked", true)
      rawset(t, "GetCenter", function() return 30, 540 end)
      t._scripts.OnDragStart(t)
      t._scripts.OnDragStop(t)
      A.eq(ns.Modules.setting("panel", "tabSide"), "right", "Lock position stops the tab too")
      -- a smaller screen: the saved height is kept on it
      ns.Modules.set("panel", "tabY", 900)
      p = { t:GetPoint(1) }
      A.eq(p[5], 497, "never off the screen")
      A.eq(ns.Log.errors(10), {})
    end,

    right_edge_tips_and_menus_open_toward_the_middle = function(ns, A, W)
      local tip = { }
      ready(W)
      friend(W, ns, "Frostie"); W:advance(1)
      W.env.GameTooltip = {
        SetOwner = function(_, owner, anchor) tip.anchor = anchor end, SetText = function() end, AddLine = function() end,
        Show = function() end, Hide = function() end, IsOwned = function() return true end,
      }
      local r = ns.Panel.rowFrameForTest(1)
      ns.Panel.showRowTip(r)
      A.eq(tip.anchor, "ANCHOR_RIGHT", "the tab on the left: tooltips on the right")
      ns.Modules.set("panel", "tabSide", "right")
      ns.Panel.showRowTip(r)
      A.eq(tip.anchor, "ANCHOR_LEFT", "on the right edge: toward the middle")
      r._scripts.OnMouseUp(r, "RightButton")
      local p = { ns.Widgets.menuFrame():GetPoint(1) }
      A.eq({ p[1], p[3] }, { "TOPRIGHT", "BOTTOMRIGHT" }, "the menu opens to the left")
      local h = { ns.Panel.holderForTest():GetPoint(1) }
      A.eq({ h[1], h[3] }, { "TOPRIGHT", "TOPLEFT" }, "the panel slides out to the left of the tab")
    end,

    scale_and_hall_of_shame_width_are_slid = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "scale", 1.5)
      hoverOpen(W, ns)
      A.eq(ns.Panel.holderWidthForTest(), root(ns):GetWidth() * 1.5, "the scaled width")
      ns.Panel.setTab("shame"); W:advance(0.5)
      ns.Panel.finishSlideForTest()
      A.eq(root(ns):GetWidth(), 336, "the Hall of Shame is wider")
      A.eq(ns.Panel.holderWidthForTest(), 336 * 1.5)
      A.eq(ns.Log.errors(10), {})
    end,

    without_clipping_it_shows_at_once = function(ns, A, W)
      local create = W.env.CreateFrame
      W.env.CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name == "TwizCrewPanelHolder" then rawset(f, "SetClipsChildren", false) end
        return f
      end
      ready(W)
      mouseTab(ns, true); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(ns.Panel.slideForTest(), nil, "no slide")
      A.eq(ns.Panel.holderWidthForTest(), root(ns):GetWidth())
    end,

    marks_and_the_update_mark_on_the_tab = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(8)
      ns.Panel.pin("Frostie")
      receive(W, ns, "Frostie", "UPDATE", { tg = "DEAD" })
      W:advance(1)
      A.ok(ns.Panel.tabStateForTest().dead, "a pinned friend is dead")
      A.no(ns.Panel.tabStateForTest().layer)
      receive(W, ns, "Frostie", "UPDATE", { tg = "" })
      W:advance(1)
      A.no(ns.Panel.tabStateForTest().dead)
      A.no(ns.Panel.tabStateForTest().hint)
      receive(W, ns, "Frostie", "HELLO", { ver = "9.9.9", rs = "0.1.0" })
      W:advance(1)
      ns.Panel.refresh(); W:advance(0.2)
      A.ok(ns.Panel.tabStateForTest().hint, "the gold ! of a waiting update")
    end,

    -------------------------------------------------------------------------------------------------- first run
    an_existing_user_gets_the_tab_and_a_note = function(ns, A, W)
      rawset(W.env.UIParent, "GetWidth", function() return 1920 end)
      rawset(W.env.UIParent, "GetHeight", function() return 1080 end)
      W.env.TwizCrewDB = { panelSince0112 = true, panelSince0113 = true, fadeOnSince017 = true, myStatus = "",
        modules = { panel = { enabled = true, settings = { minimized = false, barHover = false,
          position = { point = "TOPLEFT", x = 1500, y = -200 } } } } }
      W:fire("ADDON_LOADED", "TwizCrew"); W:fire("PLAYER_LOGIN"); W:fire("PLAYER_ENTERING_WORLD")
      W:advance(1)
      local s = W.env.TwizCrewDB.modules.panel.settings
      A.eq(s.keepOpen, false, "not minimized before: the tab too")
      A.eq(s.minimized, nil, "the old switch is gone")
      A.eq(s.barHover, true, "resting the mouse on the tab opens it")
      A.eq(s.tabSide, "right", "the edge nearest to where the panel was")
      A.eq(s.position.x, 1500, "their panel's place is kept for Keep open")
      A.eq(ns.Panel.viewForTest(), "tab")
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(12)
      A.no(hasPopup(ns, "tucks away"), "never in a fight")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(6)
      A.ok(hasPopup(ns, "TwizCrew now tucks away into a small tab"))
      local said = false
      for _, l in ipairs(W.printed) do if l:find("Click Keep open at the top of the panel", 1, true) then said = true end end
      A.ok(said, "and a chat line")
      -- once
      W:fire("PLAYER_LOGOUT")
      local saved = ns.Util.copy(W.env.TwizCrewDB)
      A.eq(saved.tabNoteDue, nil)
      A.eq(saved.panelTabSince, true)
    end,

    a_minimized_grow_up_user_keeps_their_panel_place = function(ns, A, W)
      W.env.TwizCrewDB = { panelSince0112 = true, panelSince0113 = true, fadeOnSince017 = true, myStatus = "",
        panelFullHeight = 300,
        modules = { panel = { enabled = true, settings = { minimized = true, grow = "up",
          position = { point = "BOTTOMLEFT", x = 40, y = 376, mini = true } } } } }
      W:fire("ADDON_LOADED", "TwizCrew"); W:fire("PLAYER_LOGIN"); W:fire("PLAYER_ENTERING_WORLD")
      W:advance(1)
      local s = W.env.TwizCrewDB.modules.panel.settings
      A.eq(s.keepOpen, false)
      A.eq({ s.position.y, s.position.mini }, { 100, nil }, "the bar's y is the panel's again")
      ns.Modules.set("panel", "keepOpen", true); W:advance(0.2)
      local p = { root(ns):GetPoint(1) }
      A.eq({ p[1], p[4], p[5] }, { "BOTTOMLEFT", 40, 100 }, "Keep open puts it back where it was")
    end,

    a_new_install_gets_no_note = function(ns, A, W)
      ready(W)
      W:advance(30)
      A.no(hasPopup(ns, "tucks away"))
      A.eq(ns.db.panelTabSince, true)
    end,

    -------------------------------------------------------------------------------------------------- review fixes
    the_tab_follows_scale_when_dragged_and_reaches_the_edges = function(ns, A, W)
      ready(W)
      rawset(W.env.UIParent, "GetWidth", function() return 1920 end)
      rawset(W.env.UIParent, "GetHeight", function() return 1080 end)
      ns.Modules.set("panel", "scale", 1.5)
      local t = tabFrame(ns)
      A.eq(t:GetScale(), 1.5, "the tab is scaled with the panel")
      -- the game answers GetCenter in the frame's own (scaled) units
      local function dropAt(x, y)
        rawset(t, "GetCenter", function(self) local s = self:GetEffectiveScale(); return x / s, y / s end)
        t._scripts.OnDragStart(t)
        t._scripts.OnDragStop(t)
      end
      dropAt(1850, 740)
      A.eq(ns.Modules.setting("panel", "tabSide"), "right")
      A.eq(ns.Modules.setting("panel", "tabY"), 133.3, "200 above the middle, in the tab's own units")
      local p = { t:GetPoint(1) }
      A.eq(p[5] * t:GetEffectiveScale(), 133.3 * 1.5, "it stays where it was dropped")
      dropAt(100, 1300)
      p = { t:GetPoint(1) }
      A.eq((p[5] + ns.Panel._.TAB_HEIGHT / 2) * t:GetEffectiveScale(), 540, "it reaches the top of the screen")
      dropAt(100, -300)
      p = { t:GetPoint(1) }
      A.eq((p[5] - ns.Panel._.TAB_HEIGHT / 2) * t:GetEffectiveScale(), -540, "and the bottom")
      -- changing Scale keeps it where it is on screen
      local before = p[5] * t:GetEffectiveScale()
      ns.Modules.set("panel", "scale", 1.0)
      p = { t:GetPoint(1) }
      A.eq(t:GetScale(), 1.0)
      A.eq(p[5] * t:GetEffectiveScale(), before)
      A.eq(ns.Log.errors(10), {})
    end,

    hidden_in_a_fight_the_open_panel_does_not_slide_out_after = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "hideInCombat", true)
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full")
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(1)
      A.no(ns.Panel.isShown())
      A.eq(ns.Panel.openForTest(), nil, "hiding closes it")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED"); W:advance(1)
      A.ok(ns.Panel.tabStateForTest().shown)
      A.eq(ns.Panel.viewForTest(), "tab", "back as the tab, not the whole panel")
    end,

    the_switch_does_not_swallow_news_in_a_fight = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "barInstead", true)
      friend(W, ns, "Frostie")
      W:advance(8)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.ok(hasPopup(ns, "reached level 13"), "in a fight nothing slides out, so the pop-up shows")
      A.eq(ns.Panel.viewForTest(), "tab")
    end,

    a_click_right_after_a_hover_open_keeps_it_open = function(ns, A, W)
      ready(W)
      hoverOpen(W, ns)
      A.eq(ns.Panel.openForTest().by, "hover")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "full", "not closed: the click came right after it slid out")
      A.eq(ns.Panel.openForTest().by, "click")
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "full", "the mouse is still on the tab")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "tab", "a later click closes it")
    end,

    a_right_click_in_the_hover_wait_stops_the_hover_open = function(ns, A, W)
      ready(W)
      mouseTab(ns, true); W:advance(0.1)
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "RightButton")
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "the menu opens alone")
      mouseTab(ns, false); W:advance(0.2)
      mouseTab(ns, true); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full", "after the mouse left, hover works again")
    end,

    the_notes_popup_opens_the_panel_long_enough = function(ns, A, W)
      W.env.TwizCrewDB = { panelSince0112 = true, panelSince0113 = true, fadeOnSince017 = true, myStatus = "",
        modules = { panel = { enabled = true, settings = {} } } }
      W:fire("ADDON_LOADED", "TwizCrew"); W:fire("PLAYER_LOGIN"); W:fire("PLAYER_ENTERING_WORLD")
      W:advance(11)
      local i
      for n, t in ipairs(ns.Popups.textsForTest()) do if t.text:find("tucks away", 1, true) then i = n end end
      A.ok(i, "the note's pop-up")
      A.eq(ns.Popups.textsForTest()[i].subtext, "Mouse over the tab, or click it, to see everything.")
      ns.Popups.clickForTest(i)
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "full", "the mouse was on the pop-up: the panel waits for it")
      mousePanel(ns, true); W:advance(1)
      mousePanel(ns, false); W:advance(1.2)
      A.eq(ns.Panel.viewForTest(), "tab", "it was looked at and the mouse left: the normal rule")
      W:advance(1)
      -- the mouse never comes: it still goes after a while
      ns.Panel.openTab("note"); W:advance(5)
      A.eq(ns.Panel.viewForTest(), "full")
      W:advance(2.5)
      A.eq(ns.Panel.viewForTest(), "tab")
    end,

    the_note_waits_for_a_dungeon_to_end = function(ns, A, W)
      W.env.TwizCrewDB = { panelSince0112 = true, panelSince0113 = true, fadeOnSince017 = true, myStatus = "",
        modules = { panel = { enabled = true, settings = {} } } }
      W.state.inInstance, W.state.instanceType = true, "party"
      W:fire("ADDON_LOADED", "TwizCrew"); W:fire("PLAYER_LOGIN"); W:fire("PLAYER_ENTERING_WORLD")
      W:advance(30)
      A.no(hasPopup(ns, "tucks away"), "not inside a dungeon")
      W.state.inInstance, W.state.instanceType = false, "none"
      W:advance(6)
      A.ok(hasPopup(ns, "tucks away"))
      local said
      for _, l in ipairs(W.printed) do if l:find("Mouse over the tab, or click it, to see everything.", 1, true) then said = true end end
      A.ok(said, "the chat line says a click works too")
    end,

    reactable_news_never_shorter_than_plain = function(ns, A)
      local L = ns.PanelLogic
      A.eq({ L.newsSeconds(true, 15, 3) }, { 15, 15 }, "a long setting: at least as long as plain news")
      A.eq({ L.newsSeconds(false, 15, 3) }, { 15, 3 })
      A.eq({ L.newsSeconds(true, 5, 3) }, { 12, 5 })
      A.eq({ L.newsSeconds(true, 2, 3) }, { 12, 3 })
    end,

    hover_needs_the_mouse_focus_on_the_tab_or_panel = function(ns, A, W)
      ready(W)
      local bag = W.env.CreateFrame("Frame", "ContainerFrame1", W.env.UIParent)
      W.state.mouseFoci = { bag }
      mouseTab(ns, true); W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "a bag lies over the tab: no hover-open")
      W.state.mouseFoci = { tabFrame(ns) } -- (the bag closed: the tab gets the mouse, and its OnEnter)
      mouseTab(ns, true); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full")
      ns.Panel.finishSlideForTest()
      mouseTab(ns, false); mousePanel(ns, true)
      W.state.mouseFoci = { ns.Panel.keepSwitchForTest() }
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "full", "the mouse on a child of the panel keeps it out")
      W.state.mouseFoci = { bag }
      W:advance(1.5)
      A.eq(ns.Panel.viewForTest(), "tab", "an action bar over the panel does not keep it out")
      -- an older client: GetMouseFocus only
      mousePanel(ns, false); W:advance(1)
      W.state.missing.GetMouseFoci = true
      W.state.mouseFoci = nil
      W.state.mouseFocus = bag
      mouseTab(ns, true); W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab")
      W.state.mouseFocus = tabFrame(ns)
      mouseTab(ns, true); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full")
      -- neither: the mouse position alone
      mouseTab(ns, false); W:advance(2)
      W.state.missing.GetMouseFocus = true
      mouseTab(ns, true); W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(ns.Log.errors(10), {})
    end,

    the_tabs_tooltip_goes_when_the_panel_slides_out = function(ns, A, W)
      ready(W)
      local tip = { shown = false }
      W.env.GameTooltip = {
        SetOwner = function(_, owner) tip.owner = owner end, GetOwner = function() return tip.owner end,
        SetText = function() end, AddLine = function() end,
        Show = function() tip.shown = true end, Hide = function() tip.shown = false; tip.owner = nil end,
        IsOwned = function(_, f) return tip.owner == f end,
      }
      mouseTab(ns, true)
      A.ok(tip.shown, "the tab's tooltip")
      W:advance(0.6)
      A.eq(ns.Panel.viewForTest(), "full")
      A.no(tip.shown, "hidden as the panel slides out")
    end,

    the_hall_of_shame_is_not_drawn_while_tucked = function(ns, A, W)
      ready(W)
      hoverOpen(W, ns)
      ns.Panel.setTab("shame"); W:advance(0.5)
      ns.Panel.finishSlideForTest()
      mouseTab(ns, false); W:advance(2); ns.Panel.finishSlideForTest(); W:advance(0.2)
      A.eq(ns.Panel.viewForTest(), "tab")
      local draws, draw = 0, ns.Board.draw
      ns.Board.draw = function(...) draws = draws + 1; return draw(...) end
      ns.Panel.refresh(); W:advance(0.2)
      ns.Panel.refresh(); W:advance(0.2)
      A.eq(draws, 0, "nobody sees it behind the closed holder")
      tabFrame(ns)._scripts.OnClick(tabFrame(ns), "LeftButton"); W:advance(0.1)
      A.ok(draws >= 1, "drawn when the panel slides out")
      A.eq(root(ns):GetWidth(), 336)
      ns.Board.draw = draw
    end,

    clicking_an_online_notice_whispers = function(ns, A, W)
      ready(W)
      local told
      W.env.ChatFrame_SendTell = function(name) told = name end
      friend(W, ns, "Frostie")
      W:advance(0.2)
      ns.Panel.noticeButtonForTest()._scripts.OnClick()
      A.eq(told, "Frostie")
    end,

    online_notice_whisper_uses_the_full_name = function(ns, A, W)
      ready(W)
      local told
      W.env.ChatFrameUtil = { SendTell = function(name) told = name end }
      ns.Transport.fullName = function(n) return n .. " Stormwind" end
      friend(W, ns, "Frostie")
      W:advance(0.2)
      ns.Panel.noticeButtonForTest()._scripts.OnClick()
      A.eq(told, "Frostie Stormwind", "only ChatFrameUtil.SendTell exists: used with the full name")
      A.eq(ns.Log.errors(10), {})
    end,

    clicking_a_notice_that_is_no_longer_the_one_drawn_does_nothing = function(ns, A, W)
      ready(W)
      local told
      W.env.ChatFrame_SendTell = function(name) told = name end
      friend(W, ns, "Frostie")
      W:advance(0.2)
      local drawn = ns.Panel.noticeForTest()
      A.ok(drawn, "a notice is drawn")
      -- the queue moved on to news that has not been drawn yet
      ns.Panel.barForTest():dismiss(ns.now())
      friend(W, ns, "Ginkan")
      ns.Panel.noticeClicked()
      A.eq(told, nil, "no action")
      A.ok(ns.Panel.noticeForTest() == drawn, "and nothing dismissed")
      A.eq(ns.Log.errors(10), {})
    end,

    toggle_mini_shows_a_hidden_panel_instead = function(ns, A, W)
      ready(W)
      ns.Modules.setEnabled("panel", false)
      ns.Commands.toggleMini(true)
      A.ok(ns.Modules.isEnabled("panel"), "hidden: shown")
      A.eq(ns.Modules.setting("panel", "keepOpen"), false, "as it was left, not switched")
      W:advance(1)
      A.ok(ns.Panel.tabStateForTest().shown)
    end,

    keep_open_survives_a_reload = function(ns, A, W, H)
      ready(W)
      ns.Modules.set("panel", "keepOpen", true)
      W:fire("PLAYER_LOGOUT")
      local saved = ns.Util.copy(W.env.TwizCrewDB)
      local W2, ns2 = H.client("Twiz")
      W2.env.TwizCrewDB = saved
      W2:fire("ADDON_LOADED", "TwizCrew"); W2:fire("PLAYER_LOGIN"); W2:fire("PLAYER_ENTERING_WORLD"); W2:advance(6)
      A.eq(ns2.Panel.viewForTest(), "full")
      A.no(ns2.Panel.tabStateForTest().shown)
      A.ok(ns2.Panel.rootForTest():GetParent() == W2.env.UIParent)
    end,

    changing_the_scale_keeps_the_kept_open_panel_corner_in_place = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "keepOpen", true)
      ns.Modules.set("panel", "position", { point = "TOPLEFT", x = 600, y = -300 })
      ns.Modules.set("panel", "scale", 1.5)
      local p = ns.Modules.setting("panel", "position")
      A.eq({ p.point, p.x, p.y }, { "TOPLEFT", 400, -200 })
      ns.Modules.set("panel", "scale", 1.5)
      p = ns.Modules.setting("panel", "position")
      A.eq({ p.x, p.y }, { 400, -200 }, "same scale: unchanged")
      local pt = { root(ns):GetPoint(1) }
      A.eq({ pt[1], pt[4], pt[5] }, { "TOPLEFT", 400, -200 })
      A.eq(ns.Log.errors(10), {})
    end,

    fade_enters_the_safe_wrapper_once_per_step_only = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "keepOpen", true); W:advance(0.2)
      local h = root(ns)._scripts.OnUpdate
      A.eq(type(h), "function", "fade is on by default with Keep open")
      local calls, safe = 0, ns.Log.safe
      ns.Log.safe = function(...) calls = calls + 1; return safe(...) end
      for _ = 1, 9 do h(root(ns), 0.01) end
      A.eq(calls, 0, "frames inside the step cost no safe call")
      h(root(ns), 0.02)
      A.eq(calls, 1)
      ns.Log.safe = safe
    end,

    slid_out_news_does_not_move_my_scroll = function(ns, A, W)
      ready(W)
      for i = 1, 12 do friend(W, ns, "Friend" .. string.char(64 + i)) end
      W:advance(70) -- (the online news has gone by)
      ns.Panel.scroll(-1); W:advance(1)
      local first = ns.Panel.firstRowForTest()
      A.ok(first > 1, "scrolled")
      receive(W, ns, "FriendA", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(13)
      A.eq(ns.Panel.viewForTest(), "tab")
      A.eq(ns.Panel.firstRowForTest(), first)
    end,

    news_row_finds_the_friend_in_any_section_with_the_guild_bar_closed = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      W:advance(12)
      ns.Panel.pin("Ginkan"); W:advance(1)
      hoverOpen(W, ns)
      A.ok(ns.Panel.guildBarForTest() ~= nil, "the Guild online bar is there, closed (Ginkan is pinned)")
      A.eq(ns.Modules.setting("panel", "showGuildOnline"), false)
      mouseTab(ns, false); W:advance(2); ns.Panel.finishSlideForTest()
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      A.eq(ns.Panel.rowCountForTest(), 1, "only that friend's row, though his section is closed")
      A.eq(ns.Panel.models()[1].key, "Frostie")
      A.eq(ns.Panel.guildBarForTest(), nil, "no bars in a slid-out row")
      W:advance(13)
      receive(W, ns, "Ginkan", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.models()[1].key, "Ginkan", "a pinned friend too")
      A.eq(ns.Log.errors(10), {})
    end,

    the_fast_ticker_stops_when_the_tab_is_idle = function(ns, A, W)
      ready(W)
      A.no(ns.Panel.barTickerForTest(), "nothing going on: no ticker")
      mouseTab(ns, true)
      A.ok(ns.Panel.barTickerForTest(), "the mouse on the tab: ticking")
      W:advance(0.6)
      mouseTab(ns, false); W:advance(2); ns.Panel.finishSlideForTest(); W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "tab")
      A.no(ns.Panel.barTickerForTest(), "tucked and quiet: stopped")
      friend(W, ns, "Frostie"); W:advance(0.2)
      A.ok(ns.Panel.barTickerForTest(), "news: ticking")
      W:advance(8)
      A.no(ns.Panel.barTickerForTest(), "the news has gone: stopped")
    end,

    -------------------------------------------------------------------------------------------------- after a fight
    after_fight_decides_none_one_or_a_summary = function(ns, A)
      local F = ns.FeedLogic.afterFight
      local ok = { peek = true, sinceLogin = 100 }
      local function e(kind, who, extra)
        local x = { kind = kind, who = who, inScope = true }
        for k, v in pairs(extra or {}) do x[k] = v end
        return x
      end
      A.eq(F({}, ok), "none", "nothing happened")
      A.eq(F(nil, ok), "none")
      local one = e("calnote", "Frostie")
      local act, got = F({ one }, ok)
      A.eq(act, "push"); A.ok(got == one, "one thing: it slides out as it is")
      local items = { e("died", "Frostie"), e("levelup", "Irek", { level = 28 }), e("online", "Ginkan") }
      act, got = F(items, ok)
      A.eq(act, "push")
      A.eq(got.kind, "fight"); A.eq(got.count, 3)
      A.eq(got.line, "3 things happened in that fight")
      A.eq(got.summary, "Frostie died \194\183 Irek reached 28 +1 more")
      A.eq(got.show, nil, "nothing to react to: the text summary")
      act, got = F({ e("died", "Frostie"), e("online", "Ginkan") }, ok)
      A.eq(got.summary, "Frostie died \194\183 Ginkan came online", "two: no \"more\"")
      -- one of them has a button: its row, with the count in the title line
      items = { e("online", "Ginkan"), e("died", "Frostie", { reactable = true }), e("levelup", "Irek", { reactable = true }) }
      act, got = F(items, ok)
      A.eq(got.kind, "fight"); A.eq(got.count, 3)
      A.ok(got.show == items[2], "the first one with a button")
      A.eq(got.who, "Frostie")
      -- left out: out of scope, already shown as a pop-up
      act, got = F({ e("died", "Frostie", { inScope = false }), e("online", "Ginkan", { popup = true }) }, ok)
      A.eq(act, "none", "out of scope and a pop-up already said it")
      act, got = F({ e("died", "Frostie", { popup = true }), e("calnote", "Irek") }, ok)
      A.eq(act, "push"); A.eq(got.kind, "calnote", "one left: as it is")
      -- a second fight started before the 3 s: wait for its end
      A.eq(F({ one }, { peek = true, sinceLogin = 100, inCombat = true }), "wait")
      A.eq(F({ one }, { peek = false, sinceLogin = 100 }), "none", "Slide out news is off")
      A.eq(F({ one }, { peek = true, sinceLogin = 2 }), "none", "never in the 3 s after login")
    end,

    short_lines_for_the_summary = function(ns, A)
      local S = ns.FeedLogic.shortLine
      A.eq(S({ kind = "died", who = "Frostie" }), "Frostie died")
      A.eq(S({ kind = "levelup", who = "Irek", level = 28 }), "Irek reached 28")
      A.eq(S({ kind = "levelup", who = "Irek" }), "Irek leveled up")
      A.eq(S({ kind = "online", who = "Ginkan" }), "Ginkan came online")
      A.eq(S({ kind = "mock", who = "Ginkan", dir = "in" }), "Ginkan mocked you")
      A.eq(S({ kind = "congrats", who = "Ginkan", dir = "in" }), "Ginkan congratulated you")
      A.eq(S({ kind = "otherlayer", who = "Ginkan" }), "Ginkan changed layer")
      A.eq(S({ kind = "samelayer", who = "Ginkan" }), "Ginkan is back on your layer")
      A.eq(S({ kind = "runaway", who = "Ginkan" }), "Ginkan ran off")
      A.eq(S({ kind = "calnote", who = "Ginkan" }), "Calendar note from Ginkan")
      A.eq(S({ kind = "calreply", who = "Ginkan" }), "Ginkan answered your note")
    end,

    after_a_fight_one_thing_slides_out_as_usual = function(ns, A, W)
      ready(W)
      friend(W, ns, "Ginkan")
      W:advance(12)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "lol" })
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "tab", "nothing slides out in the fight")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(2.5)
      A.eq(ns.Panel.viewForTest(), "tab", "it waits about 3 seconds")
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "peek")
      A.eq(ns.Panel.noticeForTest().kind, "mock")
      A.eq(ns.Panel.rowFrameForTest(1).mock.text:GetText(), "Mock back", "with its button")
      W:advance(10)
      A.eq(ns.Panel.viewForTest(), "peek", "the 12 s rule")
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "tab")
      A.eq(ns.Log.errors(10), {})
    end,

    after_a_fight_several_things_make_one_summary = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(12)
      ns.Modules.setEnabled("popups", false) -- (no pop-ups: the running-off news is not shown in the fight)
      ns.Modules.set("roasts", "mocks", false) -- (no Mock back: a congrats for me is plain news)
      ns.Panel.barForTest():clearMissed()
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      ns.Bus.fire("RUNNING_OFF", "Frostie", 140)
      ns.Bus.fire("CALENDAR_NEWS", "note", "Frostie")
      ns.Bus.fire("CALENDAR_NEWS", "note", "Frostie") -- (a sync of many notes says it once)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats", k = "g" })
      W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 3, "counted on the tab")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(3.2)
      A.eq(ns.Panel.viewForTest(), "peek")
      A.eq(ns.Panel.noticeForTest().kind, "fight")
      A.eq(barText(ns), "3 things happened in that fight")
      A.eq(ns.Panel.rowCountForTest(), 0, "no friend's row")
      A.eq(ns.Panel.noteForTest(), "Frostie ran off \194\183 Calendar note from Frostie +1 more")
      A.eq(ns.Panel.barForTest().missed, 3, "the count on the tab is unchanged")
      W:advance(11)
      A.eq(ns.Panel.viewForTest(), "peek", "it stays the 12 s")
      ns.Panel.noticeClicked()
      W:advance(0.1)
      A.eq(ns.Panel.viewForTest(), "full", "a click opens the panel")
      A.eq(ns.Log.errors(10), {})
    end,

    after_a_fight_a_thing_to_react_to_shows_its_row = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      W:advance(12)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" }) -- (its pop-up shows in the fight: not repeated)
      ns.Bus.fire("CALENDAR_NEWS", "note", "Frostie")
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "lol" })
      W:advance(1)
      A.ok(hasPopup(ns, "reached level 13"), "the level-up pop-up showed in the fight")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(3.2)
      A.eq(ns.Panel.noticeForTest().kind, "fight")
      A.eq(barText(ns), "2 things happened in that fight", "the level-up is left out")
      A.eq(ns.Panel.rowCountForTest(), 1, "the row of the thing to react to")
      A.eq(ns.Panel.models()[1].key, "Ginkan")
      A.eq(ns.Panel.rowFrameForTest(1).mock.text:GetText(), "Mock back")
      A.eq(ns.Panel.noteForTest(), nil)
    end,

    after_a_fight_a_new_fight_waits_and_death_still_shows = function(ns, A, W)
      ready(W)
      friend(W, ns, "Ginkan"); friend(W, ns, "Frostie")
      W:advance(12)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "lol" })
      W:advance(0.5)
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(1)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED") -- a second fight before the 3 s
      W:advance(3)
      A.eq(ns.Panel.viewForTest(), "tab", "not in the new fight")
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats", k = "g" })
      W:advance(0.5)
      -- I die: the fight ends
      W.state.dead, W.state.combat = true, false
      W:fire("PLAYER_DEAD")
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(3.2)
      A.eq(ns.Panel.noticeForTest().kind, "fight", "both fights' news together, dead or not")
      A.eq(barText(ns), "2 things happened in that fight")
      A.eq(ns.Log.errors(10), {})
    end,

    after_a_fight_nothing_slides_when_slide_out_is_off = function(ns, A, W)
      ready(W)
      friend(W, ns, "Ginkan")
      W:advance(12)
      ns.Modules.set("panel", "peek", false)
      ns.Panel.barForTest():clearMissed()
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "lol" })
      W:advance(0.5)
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(4)
      A.eq(ns.Panel.viewForTest(), "tab")
      A.eq(ns.Panel.barForTest().missed, 1, "counted as before")
    end,

    -------------------------------------------------------------------------------------------------- misc
    test_tools_news_slides_out = function(ns, A, W)
      ready(W)
      tc(W, "test fake"); W:advance(8)
      tc(W, "test ding"); W:advance(0.3)
      A.contains(barText(ns), "Testbuddy (test) reached level 13")
      A.eq(ns.Panel.viewForTest(), "peek")
      A.eq(ns.Log.errors(10), {})
    end,

    key_binding_is_declared = function(ns, A)
      local f = assert(io.open("TwizCrew/Bindings.xml"))
      local xml = f:read("*a"); f:close()
      A.contains(xml, 'name="TWIZCREW_MINI"')
      A.contains(xml, 'TwizCrew_Binding("mini")')
    end,

    files_are_in_the_toc_in_load_order = function(ns, A)
      local f = assert(io.open("TwizCrew/TwizCrew.toc"))
      local toc = f:read("*a"); f:close()
      local function at(name) return toc:find(name, 1, true) end
      A.ok(at("UI\\FeedLogic.lua") < at("UI\\Panel.lua"), "the rules before the panel")
      A.ok(at("UI\\PanelMenus.lua") < at("UI\\PanelTab.lua"), "the tab last of the panel's files")
      A.no(at("UI\\PanelMini.lua"), "the minimized bar's file is gone")
      A.ok(at("UI\\Popups.lua") < at("UI\\Feed.lua"))
    end,
  },
}
