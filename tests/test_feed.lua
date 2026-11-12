-- The activity feed (module "activity"): the pure rules in FeedLogic (lines, sanitising, the 50 cap, the gates, chat
-- switches, the bar's notice queue and missed counter, the pop-up suppression decision), then the feed fed by the real
-- events (friends coming and going, deaths, level-ups, congrats, mocks, roasts), its chat lines, saving, the Recent
-- window and the test tools.

local function boot(W, before, wait)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(wait or 6)
end

-- Booted and past the login quiet time.
local function ready(W)
  boot(W, nil, 40)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function friend(W, ns, name, extra)
  local f = { cl = "MAGE", lv = "12", zn = "Elwynn Forest", sz = "Goldshire", tg = "", ins = "0", ver = "0.1.0" }
  for k, v in pairs(extra or {}) do f[k] = v end
  receive(W, ns, name, "STATE", f)
end

local function lines(ns)
  local out = {}
  for i, e in ipairs(ns.Feed.entries()) do out[i] = e.line end
  return out
end

local function printedLike(W, text)
  for _, line in ipairs(W.printed) do if line:find(text, 1, true) then return true end end
  return false
end

local function fakeEntry(kind, n, dir)
  return { kind = kind, who = "F" .. tostring(n), at = 1000 + n, line = "line " .. tostring(n), dir = dir }
end

return {
  files = "toc",
  tests = {
    -------------------------------------------------------------------------------------------------- pure rules
    line_text_per_kind = function(ns, A)
      local L = ns.FeedLogic.line
      A.eq(L("online", "Frostie", { zone = "Elwynn Forest" }), "Frostie came online in Elwynn Forest")
      A.eq(L("online", "Frostie", {}), "Frostie came online")
      A.eq(L("offline", "Frostie"), "Frostie went offline")
      A.eq(L("died", "Frostie", { zone = "Westfall", subzone = "Moonbrook" }), "Frostie died in Westfall, Moonbrook")
      A.eq(L("died", "Frostie", { zone = "Westfall" }), "Frostie died in Westfall")
      A.eq(L("died", "Frostie", {}), "Frostie died")
      A.eq(L("levelup", "Frostie", { level = 13 }), "Frostie reached level 13")
      A.eq(L("levelup", "Frostie", {}), "Frostie leveled up")
      A.eq(L("congrats", "Frostie", { dir = "out", words = "Grats!" }), 'You congratulated Frostie: "Grats!"')
      A.eq(L("congrats", "Frostie", { dir = "in", words = "Grats!" }), 'Frostie congratulated you: "Grats!"')
      A.eq(L("congrats", "Frostie", { dir = "seen", other = "Ginkan", words = "Grats!" }),
        'Frostie congratulated Ginkan: "Grats!"')
      A.eq(L("congrats", "Frostie", { dir = "in" }), "Frostie congratulated you")
      A.eq(L("mock", "Frostie", { dir = "out", words = "Oops" }), 'You mocked Frostie: "Oops"')
      A.eq(L("mock", "Frostie", { dir = "in", words = "Oops" }), 'Frostie mocked you: "Oops"')
      A.eq(L("roast", "Frostie", { text = "Frostie forgot gravity exists." }), "Frostie forgot gravity exists.")
      A.eq(L("online", "Frostie", {}, function(n) return "<" .. n .. ">" end), "<Frostie> came online")
    end,

    entry_is_plain_safe_and_capped_in_length = function(ns, A, W)
      local e = ns.FeedLogic.entry("mock", "Frostie", { dir = "in", words = "|cffff0000red|r\1 hi" }, 1700000000, "MAGE")
      A.eq(e.words, "||cffff0000red||r  hi", "pipes doubled, control characters gone")
      A.eq(e.line, 'Frostie mocked you: "||cffff0000red||r  hi"')
      A.eq(e.class, "MAGE"); A.eq(e.at, 1700000000)
      local long = string.rep("a", 300)
      A.eq(#ns.FeedLogic.entry("congrats", "F", { dir = "in", words = long }, 1).words, ns.FeedLogic.WORDS_MAX)
      A.no(ns.FeedLogic.entry("nonsense", "F", {}, 1), "unknown kind")
      -- a roast line arrives already safe: not escaped twice
      local r = ns.FeedLogic.entry("roast", "F", { text = "F ate a ||cff pipe" }, 1)
      A.eq(r.text, "F ate a ||cff pipe")
      -- a secret value (combat rules) becomes empty text, never an error
      local hidden = W.secret()
      A.eq(ns.FeedLogic.clean(hidden), "")
      A.eq(ns.FeedLogic.clean(42), "")
      A.eq(ns.FeedLogic.entry("congrats", "F", { dir = "in", words = hidden }, 1).line, "F congratulated you")
    end,

    list_keeps_the_newest_fifty = function(ns, A)
      local list = {}
      for i = 1, 60 do ns.FeedLogic.add(list, fakeEntry("online", i)) end
      A.eq(#list, 50)
      A.eq(list[1].who, "F11", "the 10 oldest are gone")
      A.eq(list[50].who, "F60")
      local first = ns.FeedLogic.newestFirst(list)
      A.eq(first[1].who, "F60"); A.eq(first[50].who, "F11")
      A.eq(list[50].who, "F60", "the list itself keeps its order")
    end,

    repair_keeps_only_good_entries = function(ns, A)
      local list = { fakeEntry("online", 1), "junk", { kind = "nonsense", who = "x", at = 1, line = "x" },
        { kind = "online", who = "x", at = "soon", line = "x" }, fakeEntry("died", 2) }
      ns.FeedLogic.repair(list)
      A.eq(#list, 2); A.eq(list[2].kind, "died")
      A.eq(ns.FeedLogic.repair(nil), {})
      local big = {}
      for i = 1, 80 do big[i] = fakeEntry("online", i) end
      A.eq(#ns.FeedLogic.repair(big), 50)
    end,

    gate_uses_the_popup_rules = function(ns, A)
      local g = ns.FeedLogic.newGate(30)
      A.no(g:allow("online", "A", 10), "login quiet time: no online")
      A.no(g:allow("died", "A", 10)); A.no(g:allow("levelup", "A", 10)); A.no(g:allow("offline", "A", 10))
      A.ok(g:allow("congrats", "A", 10), "a congrats is not noise")
      A.ok(g:allow("mock", "A", 10)); A.ok(g:allow("roast", "A", 10))
      A.ok(g:allow("died", "A", 31), "past the quiet time")
      -- back online within two minutes of going offline is a /reload
      g:noteOffline("B", 100)
      A.no(g:allow("online", "B", 150), "a quick /reload is not news")
      g:noteOffline("B", 200)
      A.ok(g:allow("online", "B", 200 + ns.FeedLogic.RELOG), "after two minutes it is")
      A.ok(g:allow("online", "C", 150), "never went offline")
      -- a fake counts only when a test button expects it, and then past the quiet time and the reload rule
      A.no(g:allow("online", "X (test)", 150, false))
      g:noteOffline("X (test)", 149)
      A.ok(g:allow("online", "X (test)", 150, true))
      A.ok(ns.FeedLogic.newGate(1e9):allow("died", "X (test)", 5, true))
    end,

    chat_switches_per_kind = function(ns, A)
      local d = ns.Modules.get("activity").defaults
      local want = function(kind, s) return ns.FeedLogic.chatWanted(s or d, kind) end
      A.ok(want("died")); A.ok(want("levelup")); A.ok(want("congrats")); A.ok(want("mock"))
      A.no(want("online"), "the game already prints logins"); A.no(want("offline")); A.no(want("roast"))
      A.no(want("nonsense"))
      local off = {}
      for k, v in pairs(d) do off[k] = v end
      off.chat = false
      for _, kind in ipairs(ns.FeedLogic.KINDS) do A.no(want(kind, off), kind .. " with the master switch off") end
      off.chat = true; off.chatOnline = true; off.chatDied = false
      A.ok(want("online", off)); A.no(want("died", off))
      A.eq(ns.FeedLogic.chatText({ kind = "died", who = "Frostie", zone = "Westfall" }), "TwizCrew: Frostie died in Westfall")
      A.eq(ns.FeedLogic.chatText({ kind = "died", who = "Frostie" }, nil, "ffd100"),
        "|cffffd100TwizCrew:|r Frostie died")
    end,

    which_events_get_a_bar_notice = function(ns, A)
      local N = ns.FeedLogic.isNoticeKind
      A.ok(N({ kind = "online" })); A.ok(N({ kind = "died" })); A.ok(N({ kind = "levelup" }))
      A.ok(N({ kind = "congrats", dir = "in" })); A.ok(N({ kind = "mock", dir = "in" }))
      A.no(N({ kind = "congrats", dir = "out" })); A.no(N({ kind = "mock", dir = "seen" }))
      A.no(N({ kind = "offline" })); A.no(N({ kind = "roast" })); A.no(N(nil))
    end,

    bar_notices_queue_instead_of_overwriting = function(ns, A)
      local bar = ns.FeedLogic.newBar({ seconds = 6, short = 3, max = 8 })
      local a, b, c = fakeEntry("online", 1), fakeEntry("died", 2), fakeEntry("levelup", 3)
      A.ok(bar:push(a, 100), "a free bar shows it at once")
      A.eq(bar:current(), a)
      A.no(bar:push(b, 101), "the second waits")
      A.eq(bar:current(), a, "not overwritten"); A.eq(bar:waiting(), 1)
      A.eq(bar:tick(105.9), a, "still its 6 s")
      local cur, changed = bar:tick(106)
      A.eq(cur, b); A.ok(changed, "the next one takes over when the first is done")
      A.eq(bar:waiting(), 0)
      A.eq(bar:tick(111.9), b)
      A.eq(bar:tick(112), nil, "and then the bar is free again")
      A.ok(bar:push(c, 200), "free again")
    end,

    bar_shortens_notices_when_several_wait = function(ns, A)
      local bar = ns.FeedLogic.newBar({ seconds = 6, short = 3, max = 8 })
      bar:push(fakeEntry("online", 1), 0)
      bar:push(fakeEntry("online", 2), 0)
      bar:push(fakeEntry("online", 3), 0)
      A.eq(bar:waiting(), 2)
      A.eq(bar:current().who, "F1")
      bar:tick(2.9); A.eq(bar:current().who, "F1")
      bar:tick(3); A.eq(bar:current().who, "F2", "two waiting: 3 s each")
      A.eq(bar:waiting(), 1)
      bar:tick(8.9); A.eq(bar:current().who, "F2", "one waiting: the normal 6 s")
      bar:tick(9); A.eq(bar:current().who, "F3")
      -- a late tick does not stretch the queue
      local late = ns.FeedLogic.newBar({ seconds = 6, short = 3, max = 8 })
      late:push(fakeEntry("online", 1), 0); late:push(fakeEntry("online", 2), 0)
      late:tick(100)
      A.eq(late:current(), nil, "both have run out")
    end,

    bar_queue_is_capped_and_dismiss_moves_on = function(ns, A)
      local bar = ns.FeedLogic.newBar({ seconds = 6, short = 3, max = 3 })
      for i = 1, 10 do bar:push(fakeEntry("online", i), 0) end
      A.eq(bar:waiting(), 3)
      A.eq(bar:current().who, "F1")
      A.eq(bar:dismiss(1).who, "F8", "the oldest waiting ones were dropped")
      bar:clear()
      A.eq(bar:current(), nil); A.eq(bar:waiting(), 0)
      A.eq(bar:dismiss(2), nil)
    end,

    missed_counter = function(ns, A)
      local bar = ns.FeedLogic.newBar()
      A.eq(bar.missed, 0)
      bar:addMissed(); bar:addMissed(); bar:addMissed()
      A.eq(bar.missed, 3)
      bar:clearMissed()
      A.eq(bar.missed, 0)
      A.eq(ns.PanelLogic.missedText(0), ""); A.eq(ns.PanelLogic.missedText(3), "3"); A.eq(ns.PanelLogic.missedText(12), "9+")
    end,

    suppress_popups_only_when_the_bar_shows_them = function(ns, A)
      local S = ns.FeedLogic.suppressesPopup
      local on = { minimized = true, barShown = true, setting = true, feedTakes = true }
      A.ok(S("online", on)); A.ok(S("death", on)); A.ok(S("levelup", on))
      A.no(S("layer_diff", on), "layer pop-ups are not on the bar")
      A.no(S("roast", on)); A.no(S("meet", on)); A.no(S("qshare", on))
      A.no(S("death", { minimized = false, barShown = true, setting = true }), "not minimized: pop-ups as today")
      A.no(S("death", { minimized = true, barShown = false, setting = true }), "the bar is not on screen")
      A.no(S("death", { minimized = true, barShown = true, setting = false }), "the player wants both")
      A.no(S("death", { minimized = true, barShown = true, setting = true, feedTakes = false }),
        "the feed will not take it (quiet time, switched off), so the pop-up stays")
      A.no(S("death", nil))
    end,

    -------------------------------------------------------------------------------------------------- the real feed
    online_offline_died_levelup_with_the_popup_gates = function(ns, A, W)
      boot(W)
      friend(W, ns, "Frostie")
      A.eq(#ns.Feed.entries(), 0, "login quiet time: nothing yet")
      W:advance(40)
      friend(W, ns, "Ginkan")
      A.eq(lines(ns), { "Ginkan came online in Elwynn Forest" })
      receive(W, ns, "Ginkan", "UPDATE", { lv = "13" })
      receive(W, ns, "Ginkan", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "Moonbrook" })
      receive(W, ns, "Ginkan", "BYE", {})
      A.eq(lines(ns), { "Ginkan went offline", "Ginkan died in Westfall, Moonbrook", "Ginkan reached level 13",
        "Ginkan came online in Elwynn Forest" })
      -- a quick /reload (back within two minutes) is not "online" news, like the pop-up
      W:advance(30)
      friend(W, ns, "Ginkan")
      A.eq(#ns.Feed.entries(), 4, "back after 30 s: not news")
      receive(W, ns, "Ginkan", "BYE", {})
      W:advance(200)
      friend(W, ns, "Ginkan")
      A.eq(lines(ns)[1], "Ginkan came online in Elwynn Forest", "back after a while: news")
      A.eq(ns.Log.errors(10), {})
    end,

    entries_have_time_kind_who_class = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      local e = ns.Feed.entries()[1]
      A.eq(e.kind, "online"); A.eq(e.who, "Frostie"); A.eq(e.class, "MAGE"); A.eq(e.at, ns.wallclock())
      A.eq(e.line, "Frostie came online in Elwynn Forest")
      A.ok(ns.Feed.coloredLine(e):find("|cff", 1, true), "the name is in the class colour")
      A.eq(ns.Feed.plainLine(e), e.line)
    end,

    congrats_and_mocks_with_their_words = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      friend(W, ns, "Ginkan")
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats on the level, Twiz!", k = "g" })
      A.eq(lines(ns)[1], 'Frostie congratulated you: "Grats on the level, Twiz!"')
      A.eq(ns.Feed.entries()[1].dir, "in")
      W:advance(4)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Nice death, Twiz." })
      A.eq(lines(ns)[1], 'Frostie mocked you: "Nice death, Twiz."')
      W:advance(4)
      receive(W, ns, "Ginkan", "MOCK", { t = "Frostie", x = "Rest in pieces, Frostie." })
      A.eq(lines(ns)[1], 'Ginkan mocked Frostie: "Rest in pieces, Frostie."', "about someone else: still seen here")
      A.eq(ns.Feed.entries()[1].dir, "seen")
      -- mine
      W:advance(11)
      local said = ns.Roasts.cheer("Frostie")
      A.ok(said)
      A.eq(lines(ns)[1], 'You congratulated Frostie: "' .. said .. '"')
      A.eq(ns.Feed.entries()[1].dir, "out")
      W:advance(11)
      local mocked = ns.Roasts.mock("Frostie")
      A.ok(mocked)
      A.eq(lines(ns)[1], 'You mocked Frostie: "' .. mocked .. '"')
      A.eq(ns.Log.errors(10), {})
    end,

    mocks_and_congrats_off_in_roasts_are_not_recorded = function(ns, A, W)
      ready(W)
      ns.Modules.set("roasts", "cheers", false)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats!", k = "g" })
      A.eq(#ns.Feed.entries(), 0, "the viewer's own switch decides what is seen, so what is logged")
    end,

    roasts_shown_here_are_recorded = function(ns, A, W)
      ready(W)
      receive(W, ns, "Frostie", "ROAST", { k = "fall", v = "", x = "", n = "1" })
      A.eq(#ns.Feed.entries(), 1)
      local e = ns.Feed.entries()[1]
      A.eq(e.kind, "roast"); A.eq(e.who, "Frostie")
      A.eq(e.line, ns.Roasts.text("fall", 1, "Frostie"))
    end,

    mock_words_are_made_safe = function(ns, A, W)
      ready(W)
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "|cffff0000red|r you", k = "g" })
      A.eq(lines(ns)[1], 'Frostie congratulated you: "||cffff0000red||r you"')
    end,

    -------------------------------------------------------------------------------------------------- chat
    chat_lines_follow_the_switches = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      A.no(printedLike(W, "came online"), "online is off by default (the game prints logins)")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      A.ok(printedLike(W, "TwizCrew:|r "), "the addon's prefix")
      A.ok(printedLike(W, "reached level 13"))
      receive(W, ns, "Frostie", "UPDATE", { tg = "DEAD", zn = "Westfall", sz = "" })
      A.ok(printedLike(W, "died in Westfall"))
      receive(W, ns, "Frostie", "MOCK", { t = "Twiz", x = "Grats!", k = "g" })
      A.ok(printedLike(W, 'congratulated you: "Grats!"'))
      -- local only: nothing was typed into chat for anyone
      for _, m in ipairs(W.sent) do A.no(m.chatType == "SAY" or m.chatType == "YELL", "no SendChatMessage") end
      -- a roast: off by default
      W:advance(11)
      receive(W, ns, "Frostie", "ROAST", { k = "fall", v = "", x = "", n = "1" })
      A.no(printedLike(W, "forgot gravity"))
      ns.Modules.set("activity", "chatRoast", true)
      W:advance(11)
      receive(W, ns, "Frostie", "ROAST", { k = "fall", v = "", x = "", n = "2" })
      A.ok(printedLike(W, ns.Roasts.text("fall", 2, "Frostie")))
      ns.Modules.set("activity", "chatOnline", true)
      receive(W, ns, "Frostie", "BYE", {}); W:advance(200)
      friend(W, ns, "Frostie")
      A.ok(printedLike(W, "Frostie") and printedLike(W, "came online"))
      -- master switch
      local before = #W.printed
      ns.Modules.set("activity", "chat", false)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      A.eq(#W.printed, before, "master off: no chat line")
      A.eq(lines(ns)[1], "Frostie reached level 13", "but it is still in the list")
    end,

    chat_prints_whether_or_not_the_panel_is_minimized = function(ns, A, W)
      ready(W)
      ns.Modules.set("panel", "minimized", true)
      friend(W, ns, "Frostie")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      A.ok(printedLike(W, "reached level 13"))
    end,

    chat_goes_to_the_default_chat_frame_when_there_is_one = function(ns, A, W)
      ready(W)
      local got = {}
      W.env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) got[#got + 1] = text end }
      friend(W, ns, "Frostie")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      A.eq(#got, 1)
      A.ok(got[1]:find("reached level 13", 1, true))
    end,

    -------------------------------------------------------------------------------------------------- saved
    feed_is_saved_capped_and_survives_a_reload = function(ns, A, W, H)
      ready(W)
      friend(W, ns, "Frostie")
      for i = 1, 60 do receive(W, ns, "Frostie", "UPDATE", { lv = tostring(12 + i) }) end
      A.eq(#ns.db.feed, 50, "the newest 50 are saved")
      W:fire("PLAYER_LOGOUT")
      local saved = ns.Util.copy(W.env.TwizCrewDB)
      local W2, ns2 = H.client("Twiz")
      W2.env.TwizCrewDB = saved
      boot(W2)
      A.eq(#ns2.Feed.entries(), 50)
      A.eq(ns2.Feed.entries()[1].line, "Frostie reached level 72")
    end,

    broken_saved_feed_is_repaired = function(ns, A, W, H)
      local W2, ns2 = H.client("Twiz")
      W2.env.TwizCrewDB = { feed = { "junk", 7, { kind = "died", who = "A", at = 5, line = "A died" } } }
      boot(W2)
      A.eq(#ns2.Feed.entries(), 1)
      A.eq(ns2.Feed.entries()[1].line, "A died")
      local W3, ns3 = H.client("Twiz")
      W3.env.TwizCrewDB = { feed = "oops" }
      boot(W3)
      A.eq(ns3.Feed.entries(), {})
    end,

    reset_to_defaults_covers_the_new_switches_and_keeps_the_list = function(ns, A, W)
      ready(W)
      ns.Modules.set("activity", "chat", false)
      ns.Modules.set("activity", "chatOnline", true)
      ns.Modules.set("panel", "peek", false)
      ns.Modules.set("panel", "peekSeconds", 9)
      ns.Modules.set("panel", "barHover", true)
      ns.Modules.set("panel", "barInstead", false)
      ns.Modules.set("panel", "minimized", true)
      friend(W, ns, "Frostie")
      ns.Modules.resetAll()
      local d = ns.Modules.get("activity").defaults
      for key, value in pairs(d) do A.eq(ns.Modules.setting("activity", key), value, "activity." .. key) end
      A.eq(ns.Modules.setting("panel", "peek"), true); A.eq(ns.Modules.setting("panel", "peekSeconds"), 5)
      A.eq(ns.Modules.setting("panel", "barHover"), false); A.eq(ns.Modules.setting("panel", "barInstead"), false, "pop-ups keep showing unless it is on")
      A.eq(ns.Modules.setting("panel", "minimized"), false)
      A.eq(#ns.Feed.entries(), 1, "the list is data, not a setting")
    end,

    every_new_setting_has_info_text = function(ns, A)
      for _, id in ipairs({ "activity", "panel" }) do
        for _, s in ipairs(ns.Modules.get(id).settings) do
          A.ok(type(s.info) == "string" and #s.info > 20, id .. "." .. s.key .. " needs an (i) text")
        end
      end
    end,

    -------------------------------------------------------------------------------------------------- Recent window
    recent_window_lists_newest_first_and_scrolls = function(ns, A, W)
      ready(W)
      friend(W, ns, "Frostie")
      for i = 1, 14 do receive(W, ns, "Frostie", "UPDATE", { lv = tostring(12 + i) }) end
      A.ok(ns.Recent.open())
      A.ok(ns.Recent.isShown())
      local shown = ns.Recent.shownForTest()
      A.eq(#shown, ns.Recent.visibleRowsForTest())
      A.eq(shown[1].line, "Frostie reached level 26", "newest first")
      A.eq(shown[1].ago, "just now")
      A.eq(shown[1].kind, "levelup")
      ns.Recent.scroll(-1)
      A.eq(ns.Recent.shownForTest()[1].line, "Frostie reached level 25", "the wheel moves one down")
      ns.Recent.scroll(1)
      A.eq(ns.Recent.shownForTest()[1].line, "Frostie reached level 26")
      ns.Recent.scroll(1)
      A.eq(ns.Recent.shownForTest()[1].line, "Frostie reached level 26", "not above the newest")
      for _ = 1, 20 do ns.Recent.scroll(-1) end
      A.eq(ns.Recent.shownForTest()[#ns.Recent.shownForTest()].line, "Frostie came online in Elwynn Forest",
        "not past the oldest")
      -- a new event shows while it is open
      ns.Recent.scroll(100)
      receive(W, ns, "Frostie", "UPDATE", { lv = "27" })
      A.eq(ns.Recent.shownForTest()[1].line, "Frostie reached level 27")
      ns.Recent.toggle()
      A.no(ns.Recent.isShown())
      A.eq(ns.Log.errors(10), {})
    end,

    recent_window_is_built_in_a_fight_too = function(ns, A, W)
      ready(W)
      W.env.InCombatLockdown = function() return true end
      A.ok(ns.Recent.open(), "a plain frame: fine to build in a fight")
      A.ok(ns.Recent.isShown())
      ns.Recent.close()
      A.ok(ns.Recent.open(), "and to open again")
      A.eq(ns.Log.errors(10), {})
    end,

    recent_command_and_menu_entry = function(ns, A, W)
      ready(W)
      tc(W, "recent")
      A.ok(ns.Recent.isShown())
      tc(W, "recent")
      A.no(ns.Recent.isShown())
      local found
      for _, item in ipairs(ns.Panel.toolItems()) do if item.label == "Recent activity" then found = item end end
      A.ok(found, "the wrench menu lists it")
      found.onClick()
      A.ok(ns.Recent.isShown())
    end,

    empty_recent_window_says_so = function(ns, A, W)
      ready(W)
      ns.Recent.open()
      A.eq(ns.Recent.shownForTest(), {})
    end,

    -------------------------------------------------------------------------------------------------- test tools
    test_tools_run_through_the_feed = function(ns, A, W)
      ready(W)
      tc(W, "test fake")
      A.eq(#ns.Feed.entries(), 0, "fakes arriving are not events")
      tc(W, "test ding")
      A.eq(lines(ns)[1], "Testbuddy (test) reached level 13")
      A.ok(printedLike(W, "Testbuddy (test)") and printedLike(W, "reached level 13"), "the chat line")
      tc(W, "test death")
      A.eq(lines(ns)[1], "Testbuddy (test) died in Hillsbrad Foothills, Southshore")
      tc(W, "test online")
      A.eq(lines(ns)[1], "Offbuddy (test) came online in Darkshore")
      tc(W, "test congrats in")
      A.contains(lines(ns)[1], "Testbuddy (test) congratulated you:")
      A.eq(ns.Log.errors(10), {})
    end,

    test_fakes_are_never_saved_and_clear_removes_them = function(ns, A, W)
      ready(W)
      tc(W, "test ding"); tc(W, "test online")
      A.eq(#ns.Feed.entries(), 2)
      A.eq(#ns.db.feed, 0, "not in the saved list")
      tc(W, "test clear")
      A.eq(#ns.Feed.entries(), 0)
      tc(W, "test ding")
      W:fire("PLAYER_LOGOUT")
      A.eq(#ns.Feed.entries(), 0)
    end,

    test_fakes_that_no_button_expects_are_dropped = function(ns, A, W)
      ready(W)
      tc(W, "test fake")
      for _, text in ipairs(ns.Codec.encode("UPDATE", { lv = "13" })) do ns.Comm.inject("Testbuddy (test)", text) end
      A.eq(ns.roster:get("Testbuddy (test)").level, 13)
      A.eq(#ns.Feed.entries(), 0)
    end,

    -------------------------------------------------------------------------------------------------- module off
    module_off_records_nothing = function(ns, A, W)
      ready(W)
      ns.Modules.setEnabled("activity", false)
      friend(W, ns, "Frostie")
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      A.eq(#ns.Feed.entries(), 0)
      ns.Modules.setEnabled("activity", true)
      receive(W, ns, "Frostie", "UPDATE", { lv = "14" })
      A.eq(#ns.Feed.entries(), 1)
    end,
  },
}
