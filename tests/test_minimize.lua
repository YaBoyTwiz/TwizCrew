-- Minimizing the crew panel: PanelLogic.view and the position helpers, then the panel as a bar, the notices on it, the
-- peek, "open while my mouse is on the bar", the pop-ups it replaces, and the command, key binding and menu entries.

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- Frames made from now on remember their size and whether they were shown.
local function recordFrames(W)
  local create = W.env.CreateFrame
  W.env.CreateFrame = function(...)
    local f = create(...)
    rawset(f, "SetSize", function(self, w, h) rawset(self, "tcW", w); rawset(self, "tcH", h) end)
    rawset(f, "SetHeight", function(self, h) rawset(self, "tcH", h) end)
    rawset(f, "Show", function(self) rawset(self, "tcVis", true) end)
    rawset(f, "Hide", function(self) rawset(self, "tcVis", false) end)
    rawset(f, "SetText", function(self, t) rawset(self, "tcText", t) end)
    rawset(f, "SetAlpha", function(self, a) rawset(self, "tcAlpha", a) end)
    return f
  end
end

-- Boots with the login quiet time over. Frames are recorded; W.state.mouse says whether the mouse is on the panel.
local function ready(W, before)
  recordFrames(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(40)
end

local function root(ns) return ns.Panel.rootForTest() end

local function mouse(W, ns, on)
  W.state.mouse = on
  rawset(root(ns), "IsMouseOver", function() return W.state.mouse == true end)
end

local function friend(W, ns, name, extra)
  local f = { cl = "MAGE", lv = "12", zn = "Elwynn Forest", sz = "Goldshire", tg = "", ins = "0", ver = "0.1.0" }
  for k, v in pairs(extra or {}) do f[k] = v end
  receive(W, ns, name, "STATE", f)
end

local function popupTexts(ns)
  return ns.Popups.shownForTest()
end

local function hasPopup(ns, part)
  for _, t in ipairs(popupTexts(ns)) do if t:find(part, 1, true) then return true end end
  return false
end

return {
  files = "toc",
  tests = {
    -------------------------------------------------------------------------------------------------- pure
    view_decides_bar_peek_or_full = function(ns, A)
      local V = ns.PanelLogic.view
      A.eq(V({}), "full"); A.eq(V({ minimized = false, peek = true, hover = true }), "full")
      A.eq(V({ minimized = true }), "mini")
      A.eq(V({ minimized = true, peek = true }), "peek")
      A.eq(V({ minimized = true, peek = true, inCombat = true }), "mini", "never a peek in a fight")
      A.eq(V({ minimized = true, hover = true }), "full", "the mouse on the bar opens it")
      A.eq(V({ minimized = true, hover = true, peek = true }), "full")
      A.eq(V(nil), "full")
    end,

    grow_up_keeps_the_bar_still = function(ns, A)
      local L = ns.PanelLogic
      -- a full panel 300 tall saved at bottom y = 100: its bar is the top 24
      local barY = L.yAfterMinimize(100, 300, 24)
      A.eq(barY, 376, "the bar-sized panel's bottom is where the bar's bottom was")
      A.eq(L.yAfterRestore(barY, 300, 24), 100, "and back")
      -- a 120 tall peek under that bar hangs down: its bottom is lower by the extra height
      A.eq(L.barFixedY(barY, 120, 24), 376 - 96)
      A.eq(L.barFixedY(barY, 24, 24), 376, "the bar alone: where it was saved")
      A.eq(L.barSavedY(376 - 96, 120, 24), 376, "reading it back from a peek gives the saved y")
      A.eq(L.barFixedY(50, 10, 24), 50, "never lifted")
    end,

    bar_text_and_labels = function(ns, A)
      local L = ns.PanelLogic
      A.eq(L.barText(nil, "2 of 3 online"), "2 of 3 online")
      A.eq(L.barText("", "2 of 3 online"), "2 of 3 online")
      A.eq(L.barText("Frostie died", "2 of 3 online"), "Frostie died")
      A.eq(L.miniLabel(false), "Minimize the panel"); A.eq(L.miniLabel(true), "Restore the panel")
    end,

    -------------------------------------------------------------------------------------------------- the bar
    minimizing_shrinks_to_the_header_and_keeps_width = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(1)
      local full = root(ns)
      local width, height = full.tcW, full.tcH
      A.ok(height > 60, "a normal panel is taller than the bar")
      A.eq(ns.Panel.viewForTest(), "full")
      A.ok(ns.Panel.newsLineForTest(), "the What's new line is there")
      tc(W, "mini")
      W:advance(1)
      A.eq(ns.Modules.setting("panel", "minimized"), true)
      A.eq(ns.Panel.viewForTest(), "mini")
      A.eq(full.tcH, 24, "just the header bar")
      A.eq(full.tcW, width, "same width")
      A.eq(ns.Panel.rowCountForTest(), 0)
      A.eq(ns.Panel.newsLineForTest(), nil, "the What's new line is hidden")
      A.eq(ns.Panel.updateLineForTest(), nil, "and the update line")
      A.ok(ns.Panel.isShown())
      A.eq(ns.Panel.barTextForTest(), "1 of 1 online", "the title bar keeps the online count")
      tc(W, "mini")
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "full")
      A.eq(full.tcH, height, "back to the same size")
      A.ok(ns.Panel.newsLineForTest())
      A.eq(ns.Log.errors(10), {})
    end,

    minimized_state_survives_a_reload = function(ns, A, W, H)
      ready(W)
      ns.Panel.toggleMinimized()
      W:fire("PLAYER_LOGOUT")
      local saved = ns.Util.copy(W.env.TwizCrewDB)
      local W2, ns2 = H.client("Twiz")
      W2.env.TwizCrewDB = saved
      recordFrames(W2)
      W2:fire("ADDON_LOADED", "TwizCrew"); W2:fire("PLAYER_LOGIN"); W2:fire("PLAYER_ENTERING_WORLD"); W2:advance(6)
      A.eq(ns2.Panel.viewForTest(), "mini")
      A.eq(ns2.Panel.rootForTest().tcH, 24)
    end,

    button_title_command_binding_and_menu_all_toggle = function(ns, A, W)
      ready(W)
      ns.Panel.miniButtonForTest()._scripts.OnClick()
      A.eq(ns.Modules.setting("panel", "minimized"), true, "the button on the bar")
      ns.Panel.miniButtonForTest()._scripts.OnClick()
      A.eq(ns.Modules.setting("panel", "minimized"), false)
      W.env.TwizCrew_Binding("mini")
      A.eq(ns.Modules.setting("panel", "minimized"), true, "the key binding")
      tc(W, "mini")
      A.eq(ns.Modules.setting("panel", "minimized"), false, "/tc mini")
      tc(W, "minimize")
      A.eq(ns.Modules.setting("panel", "minimized"), true)
      -- minimized, a click on the title brings it back instead of opening What's new
      local opened = false
      local old = ns.Changelog.toggle
      ns.Changelog.toggle = function() opened = true end
      ns.Panel.titleButtonForTest()._scripts.OnClick()
      A.no(opened, "not What's new")
      A.eq(ns.Modules.setting("panel", "minimized"), false, "the title restores it")
      ns.Panel.titleButtonForTest()._scripts.OnClick()
      A.ok(opened, "restored: the title is What's new again")
      ns.Changelog.toggle = old
      -- the header's menu
      ns.Panel.toggleMinimized()
      local labels = {}
      for i, item in ipairs(ns.Panel.menuItems()) do labels[i] = item.label end
      A.eq(labels[3], "Restore the panel")
    end,

    hidden_panel_is_shown_not_toggled = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized()
      ns.Modules.setEnabled("panel", false)
      W.env.TwizCrew_Binding("mini")
      A.eq(ns.Modules.isEnabled("panel"), true, "hidden: the key shows the panel")
      A.eq(ns.Modules.setting("panel", "minimized"), true, "as it was left")
    end,

    reset_to_defaults_restores_the_panel = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized()
      W:advance(1)
      ns.Modules.resetAll()
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "full")
    end,

    lock_fade_fight_and_panel_off_still_work_minimized = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized(); W:advance(1)
      -- hide during fights
      ns.Modules.set("panel", "hideInCombat", true)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(1)
      A.no(ns.Panel.isShown(), "hidden in a fight while minimized")
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED"); W:advance(1)
      A.ok(ns.Panel.isShown()); A.eq(ns.Panel.viewForTest(), "mini")
      -- lock
      ns.Modules.set("panel", "locked", true)
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "mini")
      -- row styles: the bar fits in every one
      for _, style in ipairs({ "compact", "tiny", "full" }) do
        ns.Modules.set("panel", "rowStyle", style); W:advance(1)
        A.eq(ns.Panel.viewForTest(), "mini", style)
        A.eq(root(ns).tcH, 24, style)
      end
      ns.Modules.set("panel", "rowStyle", "tiny"); W:advance(1)
      A.eq(ns.Panel.titleVersionForTest(), "", "tiny: no version on the bar")
      A.ok(ns.Panel.barTextForTest() == "0 of 0 online" or ns.Panel.barTextForTest() == "0/0")
      -- fade: no error, and the bar keeps working
      ns.Modules.set("panel", "fadeOut", true); W:advance(1)
      -- panel off and on
      ns.Modules.setEnabled("panel", false); W:advance(1)
      A.no(ns.Panel.isShown())
      ns.Modules.setEnabled("panel", true); W:advance(1)
      A.ok(ns.Panel.isShown()); A.eq(ns.Panel.viewForTest(), "mini")
      A.eq(ns.Log.errors(10), {})
    end,

    -------------------------------------------------------------------------------------------------- notices
    notice_shows_in_place_of_the_count_then_goes_back = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.2)
      local e = ns.Panel.noticeForTest()
      A.ok(e, "a notice is on the bar"); A.eq(e.kind, "levelup")
      A.contains(ns.Panel.barTextForTest(), "reached level 13")
      A.contains(ns.Panel.barTextForTest(), "|cff", "the friend's name is in class colour")
      A.ok(ns.Panel.noticeButtonForTest().tcVis, "clickable")
      A.ok(ns.Panel.rootForTest().tcH == 24 or ns.Panel.viewForTest() == "peek")
      W:advance(5)
      A.ok(ns.Panel.noticeForTest(), "still there before 6 s")
      W:advance(1.5)
      A.eq(ns.Panel.noticeForTest(), nil, "gone after about 6 s")
      A.eq(ns.Panel.barTextForTest(), "1 of 1 online", "the count is back")
      A.eq(ns.Log.errors(10), {})
    end,

    notices_queue_when_events_come_close_together = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      receive(W, ns, "Ginkan", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      W:advance(0.2)
      A.eq(ns.Panel.noticeForTest().who, "Frostie", "the first is not overwritten")
      A.eq(ns.Panel.barForTest():waiting(), 1)
      W:advance(6)
      A.eq(ns.Panel.noticeForTest().who, "Ginkan", "then the second")
      A.contains(ns.Panel.barTextForTest(), "died in Westfall")
      W:advance(7)
      A.eq(ns.Panel.noticeForTest(), nil)
    end,

    missed_counter_counts_and_restoring_clears_it = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      A.no(ns.Panel.missedButtonForTest().tcVis, "nothing missed yet")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats", k = "g" })
      W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 3)
      A.ok(ns.Panel.missedButtonForTest().tcVis)
      W:advance(30)
      A.eq(ns.Panel.barForTest().missed, 3, "it stays until you look")
      tc(W, "mini"); W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 0, "restoring clears it")
      A.no(ns.Panel.missedButtonForTest().tcVis)
      tc(W, "mini"); W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 0)
    end,

    clicking_the_missed_number_opens_the_recent_list = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      ns.Panel.missedButtonForTest()._scripts.OnClick()
      A.ok(ns.Recent.isShown())
      A.eq(ns.Panel.barForTest().missed, 0, "seen")
    end,

    only_the_right_kinds_get_notices = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "BYE", {})            -- offline: no
      W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 0)
      friend(W, ns, "Ginkan")                          -- online: yes
      W:advance(1)
      A.eq(ns.Panel.noticeForTest().kind, "online")
      W:advance(10)
      receive(W, ns, "Ginkan", "ROAST", { k = "fall", v = "", x = "", n = "1" }) -- roast: no
      W:advance(1)
      A.eq(ns.Panel.barForTest().missed, 1)
      A.eq(ns.Panel.noticeForTest(), nil)
      receive(W, ns, "Ginkan", "MOCK", { t = "Twiz", x = "ha", k = "g" })        -- congrats to me: yes
      W:advance(0.2)
      A.eq(ns.Panel.noticeForTest().kind, "congrats")
      A.contains(ns.Panel.barTextForTest(), "congratulated you")
      W:advance(10)
      receive(W, ns, "Ginkan", "MOCK", { t = "Frostie", x = "ha" })               -- a mock about someone else: no
      W:advance(0.2)
      A.eq(ns.Panel.noticeForTest(), nil)
    end,

    pop_up_switches_decide_which_news_the_bar_shows = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Modules.set("popups", "death", false)
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      W:advance(0.2)
      A.eq(ns.Panel.noticeForTest(), nil, "deaths are off in the pop-up settings")
      A.eq(ns.Panel.barForTest().missed, 0)
    end,

    not_minimized_means_no_notices_and_no_missed = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.eq(ns.Panel.noticeForTest(), nil); A.eq(ns.Panel.barForTest().missed, 0)
      A.eq(ns.Panel.viewForTest(), "full")
    end,

    clicking_a_level_up_notice_congratulates = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      local cheered
      ns.Roasts.cheer = function(name) cheered = name; return "Grats" end
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.2)
      ns.Panel.noticeButtonForTest()._scripts.OnClick()
      A.eq(cheered, "Frostie", "the same as clicking the level-up pop-up")
      W:advance(0.2)
      A.eq(ns.Panel.noticeForTest(), nil, "and the notice is done")
    end,

    clicking_an_online_notice_whispers = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized(); W:advance(1)
      local told
      W.env.ChatFrame_SendTell = function(name) told = name end
      friend(W, ns, "Frostie")
      W:advance(0.2)
      ns.Panel.noticeButtonForTest()._scripts.OnClick()
      A.eq(told, "Frostie")
    end,

    -------------------------------------------------------------------------------------------------- peek
    peek_opens_the_friends_row_then_closes = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      ns.Panel.toggleMinimized(); W:advance(1)
      A.eq(ns.Modules.setting("panel", "peek"), true, "on by default")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.peekForTest().name, "Frostie")
      A.eq(ns.Panel.viewForTest(), "peek")
      A.eq(ns.Panel.rowCountForTest(), 1, "only that friend's row")
      A.eq(ns.Panel.models()[1].name, "Frostie")
      A.ok(root(ns).tcH > 24, "dropped open below the bar")
      A.ok(ns.Panel.rowCheerShownForTest(1), "the Congrats button is on the peeked row")
      W:advance(5)
      A.eq(ns.Panel.viewForTest(), "mini", "closed again after 5 s")
      A.eq(root(ns).tcH, 24)
      A.eq(ns.Panel.peekForTest(), nil)
    end,

    peek_seconds_and_switch = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Modules.set("panel", "peekSeconds", 2)
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(1.5)
      A.eq(ns.Panel.viewForTest(), "mini", "2 s is enough when that is what was set")
      ns.Modules.set("panel", "peek", false)
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "mini", "no peek when it is off")
      A.ok(ns.Panel.noticeForTest(), "but the bar notice still shows")
    end,

    peek_waits_for_the_mouse = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      mouse(W, ns, true)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(20)
      A.eq(ns.Panel.viewForTest(), "peek", "the mouse keeps it open")
      mouse(W, ns, false)
      W:advance(0.5)
      A.eq(ns.Panel.viewForTest(), "mini", "closes when the mouse leaves")
    end,

    no_peek_in_a_fight = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      W.state.combat = true
      W:fire("PLAYER_REGEN_DISABLED")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.peekForTest(), nil)
      A.eq(ns.Panel.viewForTest(), "mini")
      A.ok(ns.Panel.noticeForTest(), "the bar notice is plain text and still shows")
      -- a fight that starts during a peek closes it
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(10)
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "mini")
    end,

    peek_follows_the_next_notice = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie"); friend(W, ns, "Ginkan")
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      receive(W, ns, "Ginkan", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.peekForTest().name, "Frostie")
      W:advance(6)
      A.eq(ns.Panel.peekForTest().name, "Ginkan", "the second notice, the second friend")
    end,

    peek_does_not_move_my_scroll = function(ns, A, W)
      ready(W)
      for i = 1, 12 do friend(W, ns, "Friend" .. string.char(64 + i)) end
      W:advance(1)
      ns.Panel.scroll(-1); W:advance(1)
      local first = ns.Panel.firstRowForTest()
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "FriendA", "UPDATE", { lv = "13" })
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(6)
      tc(W, "mini"); W:advance(1)
      A.eq(ns.Panel.firstRowForTest(), first)
    end,

    -------------------------------------------------------------------------------------------------- hover
    mouse_on_the_bar_opens_the_panel_when_allowed = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      ns.Panel.toggleMinimized(); W:advance(1)
      mouse(W, ns, true)
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "mini", "off by default")
      ns.Modules.set("panel", "barHover", true)
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "full", "the mouse is on the bar")
      A.ok(ns.Panel.rowCountForTest() >= 1)
      mouse(W, ns, false)
      W:advance(0.3)
      A.eq(ns.Panel.viewForTest(), "mini", "shrinks when the mouse leaves")
      ns.Modules.set("panel", "barHover", false)
      mouse(W, ns, true)
      W:advance(1)
      A.eq(ns.Panel.viewForTest(), "mini")
    end,

    -------------------------------------------------------------------------------------------------- pop-ups
    minimized_panel_replaces_online_died_levelup_popups = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized(); W:advance(1)
      friend(W, ns, "Frostie")
      W:advance(4)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      receive(W, ns, "Frostie", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      W:advance(4)
      A.eq(ns.Popups.shownForTest(), {}, "no pop-ups: the bar shows them")
      A.ok(ns.Panel.barForTest().missed >= 3)
    end,

    popups_are_as_before_when_not_minimized = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      W:advance(4)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      receive(W, ns, "Frostie", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      W:advance(1)
      A.ok(hasPopup(ns, "Frostie is online"))
      A.ok(hasPopup(ns, "reached level 13"))
      A.ok(hasPopup(ns, "Frostie died"))
    end,

    both_when_the_switch_is_off = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "barInstead", false)
      ns.Panel.toggleMinimized(); W:advance(1)
      friend(W, ns, "Frostie")
      W:advance(4)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.ok(hasPopup(ns, "Frostie is online"))
      A.ok(hasPopup(ns, "reached level 13"))
      A.ok(ns.Panel.noticeForTest() or ns.Panel.barForTest().missed > 0, "and the bar too")
    end,

    popups_return_when_the_panel_is_hidden = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized(); W:advance(1)
      ns.Modules.setEnabled("panel", false)
      friend(W, ns, "Frostie")
      W:advance(4)
      A.ok(hasPopup(ns, "Frostie is online"), "no bar on screen, so the pop-up is not dropped")
    end,

    popups_return_when_the_activity_feed_is_off = function(ns, A, W)
      ready(W)
      ns.Modules.setEnabled("activity", false)
      ns.Panel.toggleMinimized(); W:advance(1)
      friend(W, ns, "Frostie")
      W:advance(4)
      A.ok(hasPopup(ns, "Frostie is online"), "the bar has nothing to show without the feed")
    end,

    layer_popups_and_roasts_still_show_minimized = function(ns, A, W)
      ready(W)
      ns.Panel.toggleMinimized(); W:advance(1)
      receive(W, ns, "Frostie", "ROAST", { k = "fall", v = "", x = "", n = "1" })
      W:advance(1)
      A.ok(ns.Popups.visibleCount() >= 1, "roast pop-ups are not replaced")
    end,

    -------------------------------------------------------------------------------------------------- test tools
    test_tools_show_a_notice_and_a_peek_alone = function(ns, A, W)
      ready(W)
      tc(W, "test fake"); W:advance(1)
      ns.Panel.toggleMinimized(); W:advance(1)
      tc(W, "test ding"); W:advance(0.3)
      A.contains(ns.Panel.barTextForTest(), "Testbuddy (test)")
      A.contains(ns.Panel.barTextForTest(), "reached level 13")
      A.eq(ns.Panel.viewForTest(), "peek")
      W:advance(8)
      tc(W, "test online"); W:advance(0.3)
      A.contains((ns.Panel.barTextForTest():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "Offbuddy (test) came online")
      W:advance(8)
      tc(W, "test death"); W:advance(0.3)
      A.contains(ns.Panel.barTextForTest(), "died")
      A.eq(ns.Log.errors(10), {})
    end,

    -------------------------------------------------------------------------------------------------- misc
    key_binding_is_declared = function(ns, A)
      local f = assert(io.open("TwizCrew/Bindings.xml"))
      local xml = f:read("*a"); f:close()
      A.contains(xml, 'name="TWIZCREW_MINI"')
      A.contains(xml, 'TwizCrew_Binding("mini")')
    end,

    new_files_are_in_the_toc_in_load_order = function(ns, A)
      local f = assert(io.open("TwizCrew/TwizCrew.toc"))
      local toc = f:read("*a"); f:close()
      local function at(name) return toc:find(name, 1, true) end
      A.ok(at("UI\\FeedLogic.lua") and at("UI\\Feed.lua") and at("UI\\Recent.lua"))
      A.ok(at("UI\\FeedLogic.lua") < at("UI\\Panel.lua"), "the rules before the panel")
      A.ok(at("UI\\Popups.lua") < at("UI\\Feed.lua"), "the feed after the pop-ups")
      A.ok(at("UI\\Feed.lua") < at("UI\\Recent.lua"))
      A.ok(at("UI\\Recent.lua") < at("UI\\Settings.lua"))
    end,

    grow_up_minimize_keeps_the_bar_where_it_was = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "grow", "up")
      ns.Modules.set("panel", "position", { point = "BOTTOMLEFT", x = 40, y = 100 })
      friend(W, ns, "Frostie"); W:advance(1)
      local fullHeight = root(ns).tcH
      ns.Panel.toggleMinimized(); W:advance(1)
      local p = ns.Modules.setting("panel", "position")
      A.eq(p.point, "BOTTOMLEFT")
      A.eq(p.y, 100 + fullHeight - 24, "the bar's bottom is where the bar's bottom was")
      ns.Panel.toggleMinimized(); W:advance(1)
      A.eq(ns.Modules.setting("panel", "position").y, 100, "restored: the panel's bottom is back")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
