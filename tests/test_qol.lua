-- v0.1.12 quality of life: What's new (UI/Changelog.lua), online friends only with the "Offline (N)" bar, my own row
-- and a lighter fade by default, the one-time switch for older saved settings, and the "came online" pop-up.

local function start(ns, W, saved)
  local db = ns.DB.init(saved, ns.Modules.list())
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

local function names(models)
  local out = {}
  for i, m in ipairs(models) do out[i] = m.bar and ("[Offline " .. m.count .. (m.open and " open]" or "]")) or m.name end
  return out
end

-- Friends the roster knows from saved data (offline) plus the ones that talk to us (online).
local function crew(ns, W)
  receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
  receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR", lv = "14", zn = "Westfall" })
  receive(ns, W, "Oldpal", "STATE", { cl = "ROGUE", lv = "9" })
  receive(ns, W, "Oldpal", "BYE", {})
  W:advance(1)
end

return {
  files = "toc",
  tests = {
    ----------------------------------------------------------------------------------------------------- What's new
    history_is_newest_first_and_starts_with_this_version = function(ns, A, W)
      local H = ns.Changelog.HISTORY
      A.ok(#H >= 13)
      for i = 2, #H do
        A.eq(ns.Util.compareVersions(H[i - 1].ver, H[i].ver), 1, "newest first: " .. H[i - 1].ver .. " > " .. H[i].ver)
        A.ok(#H[i].lines > 0)
      end
      local f = io.open("TwizCrew/Core/Init.lua") or io.open("../TwizCrew/Core/Init.lua")
      local src = f and f:read("*a") or ""
      if f then f:close() end
      local real = src:match('ADDON_VERSION = "([%d%.]+)"')
      if real then A.eq(H[1].ver, real, "a history entry for the version in Init.lua") end
      local lines = ns.Changelog.lines()
      A.eq(lines[1].head, true)
      A.contains(lines[1].text, "v" .. H[1].ver)
    end,
    whats_new_opens_from_command_settings_and_title = function(ns, A, W)
      start(ns, W)
      W.env.SlashCmdList.TWIZCREW("new")
      A.eq(ns.Log.errors(10), {}); A.ok(ns.Changelog.isShown(), "/tc new")
      ns.Changelog.close()
      ns.Changelog.toggle()
      A.ok(ns.Changelog.isShown())
      ns.Changelog.toggle()
      A.no(ns.Changelog.isShown())
      local button
      for _, s in ipairs(ns.Modules.get("panel").settings) do if s.key == "whatsNew" then button = s end end
      A.eq(button.kind, "button")
      button.onClick()
      A.ok(ns.Changelog.isShown(), "the What's new button in the settings")
      ns.Changelog.scroll(5); ns.Changelog.scroll(-50); ns.Changelog.scroll(9999)
      A.eq(ns.Log.errors(10), {})
    end,
    a_new_install_shows_no_news_line = function(ns, A, W)
      local db = start(ns, W)
      W:advance(1)
      A.eq(db.newsSeen, ns.VERSION)
      A.eq(ns.Panel.newsLineForTest(), nil)
    end,
    an_update_shows_the_news_line_until_seen = function(ns, A, W)
      local db = start(ns, W, { fadeOnSince017 = true })
      W:advance(1)
      A.eq(ns.Panel.newsLineForTest(), "New in v" .. ns.VERSION .. "! Click to see what changed")
      W.env.SlashCmdList.TWIZCREW("new")
      W:advance(1)
      A.eq(db.newsSeen, ns.VERSION)
      A.eq(ns.Panel.newsLineForTest(), nil, "gone once the window was opened")
    end,
    ------------------------------------------------------------------------------------------- online friends only
    offline_friends_wait_behind_the_offline_bar = function(ns, A, W)
      start(ns, W)
      crew(ns, W)
      A.eq(names(ns.Panel.entriesForTest()), { "Twiz", "Frostie", "Ginkan", "[Offline 1]" },
        "me first, online friends, then the closed bar")
      A.ok(ns.Panel.offlineBarForTest(), "the bar is drawn")
      ns.Panel.toggleOffline(); W:advance(1)
      A.eq(ns.Modules.setting("panel", "showOffline"), true, "remembered")
      A.eq(names(ns.Panel.entriesForTest()), { "Twiz", "Frostie", "Ginkan", "[Offline 1 open]", "Oldpal" })
      local bar = ns.Panel.offlineBarForTest()
      bar._scripts.OnClick(bar, "LeftButton"); W:advance(1)
      A.eq(names(ns.Panel.entriesForTest()), { "Twiz", "Frostie", "Ginkan", "[Offline 1]" }, "a click closes it")
      receive(ns, W, "Oldpal", "STATE", { cl = "ROGUE", lv = "9" }); W:advance(1)
      A.eq(names(ns.Panel.entriesForTest()), { "Twiz", "Frostie", "Ginkan", "Oldpal" }, "nobody offline: no bar")
      A.eq(ns.Panel.offlineBarForTest(), nil)
      A.eq(ns.Log.errors(10), {})
    end,
    entries_rules = function(ns, A)
      local L = ns.PanelLogic
      local rows = { { name = "A" }, { name = "Z", offline = true }, { name = "B" } }
      A.eq(names(L.entries(rows, 0, true)), { "A", "B", "[Offline 1 open]", "Z" }, "offline after the bar")
      A.eq(names(L.entries({ { name = "A" } }, 3, false)), { "A", "[Offline 3]" })
      A.eq(names(L.entries({ { name = "A" } }, 0, false)), { "A" })
      A.eq(L.offlineBarText(3, false), "Offline (3)  -  click to show")
      A.eq(L.offlineBarText(3, true), "Offline (3)  -  click to hide")
      local _, hidden = L.rows({ { name = "X", online = false }, { name = "Y", online = true } }, { showOffline = false })
      A.eq(hidden, 1)
    end,
    older_saved_settings_switch_once = function(ns, A, W)
      local saved = { fadeOnSince017 = true,
        modules = { panel = { enabled = true, settings = { showOffline = true, showSelf = false, fadeAlpha = 0.35 } } } }
      local db = start(ns, W, saved)
      A.eq(ns.Modules.setting("panel", "showOffline"), false)
      A.eq(ns.Modules.setting("panel", "showSelf"), true)
      A.eq(ns.Modules.setting("panel", "fadeAlpha"), 0.5)
      A.eq(db.panelSince0112, true)
      -- the owner changes them back: they stay
      ns.Modules.set("panel", "showOffline", true)
      ns.Modules.set("panel", "fadeAlpha", 0.35)
      ns.Modules.setEnabled("panel", false); ns.Modules.setEnabled("panel", true)
      A.eq(ns.Modules.setting("panel", "showOffline"), true)
      A.eq(ns.Modules.setting("panel", "fadeAlpha"), 0.35)
    end,
    ------------------------------------------------------------------------------------------- came online pop-up
    a_friend_coming_online_pops_up = function(ns, A, W)
      start(ns, W)
      W:advance(31) -- past the login quiet time
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
      W:advance(4)
      local t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "Frostie is online")
      A.eq(t[#t].subtext, "Level 12 Mage in Elwynn Forest")
      local told
      W.env.ChatFrame_SendTell = function(n) told = n end
      ns.Popups.clickForTest(#t)
      A.eq(told, "Frostie", "a click whispers them")
      A.eq(ns.Log.errors(10), {})
    end,
    a_quick_reload_is_not_news = function(ns, A, W)
      start(ns, W)
      W:advance(31)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(4)
      local before = #ns.Popups.shownForTest()
      receive(ns, W, "Frostie", "BYE", {})
      W:advance(10)
      receive(ns, W, "Frostie", "HELLO", { ver = "0.1.0" })
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(4)
      A.eq(#ns.Popups.shownForTest(), before, "back after 10 s: no pop-up")
      receive(ns, W, "Frostie", "BYE", {})
      W:advance(300)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(4)
      local s = ns.Popups.shownForTest()
      A.eq(s[#s], "Frostie is online", "back after 5 minutes: news again")
    end,
    nobody_pops_up_at_login_and_several_share_one = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(31)
      A.eq(#ns.Popups.shownForTest(), 0, "already online when I logged in: quiet")
      for _, n in ipairs({ "Ginkan", "Holly", "Ivo" }) do receive(ns, W, n, "STATE", { cl = "PRIEST" }) end
      W:advance(4)
      local t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "3 friends are online")
      A.eq(t[#t].subtext, "Ginkan, Holly, Ivo")
      ns.Modules.set("popups", "online", false)
      receive(ns, W, "Jo", "STATE", { cl = "PRIEST" })
      W:advance(4)
      A.eq(#ns.Popups.shownForTest(), 1, "switched off")
    end,
  },
}
