-- Simpler settings (2026-11-23): the one-time switch-over of saved settings (News in my chat and Sounds take the old
-- switches), the removed keys leaving saved data, an upgrade from v0.3.0 data without errors, the automatic grow
-- direction of the kept-open panel, and "Clear the list" in the Recent window.

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

local function boot(W, saved)
  W.env.TwizCrewDB = saved
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(1)
end

-- Saved settings the way v0.3.0 left them (it wrote every default into saved data), with changes on top.
local function v030(changes)
  local m = {
    panel = { enabled = true, settings = { scale = 1.0, bgAlpha = 0.8, rowStyle = "full", showZone = true,
      showStatus = true, showXP = true, showQuest = true, shareQuest = true, questRequests = true, questHeadsUp = true,
      xpText = true, xpTooltip = true, idleAlpha = 0.4, locked = false, grow = "down", peekSeconds = 5,
      tag_DEAD = true, tag_LAYER = true, tag_COMBAT = true, tag_DUNGEON = true, tag_TAXI = true, tag_AFK = true } },
    activity = { enabled = true, settings = { chat = true, chatOnline = false, chatOffline = false, chatDied = true,
      chatLevel = true, chatCongrats = true, chatMock = true, chatRoast = false } },
    popups = { enabled = true, settings = { online = true, layerDiff = true, layerSame = true, death = true,
      levelUp = true, levelUpSound = false, sound = false, seconds = 5, newMember = true } },
    roasts = { enabled = true, settings = { aboutMe = true, sound = false, mocks = true, mockModel = true,
      mockSound = true, ownOnly = false, addMock = "", cheers = true, stealPopups = true, weak = true, fall = true,
      drown = true, again = true, deaths = true, wipe = true, steps = true, jumps = true, quit = true } },
    stats = { enabled = true, settings = { titles = "session", countSteps = true, wipeLine = true, showSound = true,
      crewShow = true, boardTab = "deaths" } },
    find = { enabled = true, settings = { rowArrows = true, meetups = true, sharePosition = true, meetPopup = true,
      meetArrow = true, meetMinimap = true, runaway = true, arrowScale = 1.0 } },
    version = { enabled = true, settings = { chatNotice = true } },
  }
  for id, set in pairs(changes or {}) do
    for k, v in pairs(set) do m[id].settings[k] = v end
  end
  return { panelSince0112 = true, panelSince0113 = true, fadeOnSince017 = true, panelTabSince = true, myStatus = "",
    newsSeen = "0.3.0", aboutSeen = true, modules = m }
end

return {
  files = "toc",
  tests = {
    ------------------------------------------------------------------------------------------------- the mapping
    news_in_my_chat_from_the_old_switches = function(ns, A)
      local f = ns.DB.chatNewsFrom
      A.eq(f(nil), nil, "nothing saved: the default stays")
      A.eq(f({}), nil, "a new install has none of the old keys")
      A.eq(f({ chat = false, chatOnline = true }), "off", "the master switch off wins")
      A.eq(f({ chat = true, chatOnline = true }), "all", "any of the quiet kinds on: Everything")
      A.eq(f({ chat = true, chatOffline = true }), "all")
      A.eq(f({ chat = true, chatRoast = true }), "all")
      A.eq(f({ chat = true, chatDied = false, chatLevel = true }), "important", "the old defaults or fewer: Important")
      A.eq(f({ chat = true }), "important")
    end,

    sounds_from_the_five_old_switches = function(ns, A)
      local f = ns.DB.soundsFrom
      A.eq(f(nil, nil, nil), nil, "nothing saved: the default stays")
      A.eq(f({ online = true }, {}, {}), nil, "none of the sound keys")
      A.eq(f({ sound = false, levelUpSound = false }, { sound = false, mockSound = true }, { showSound = true }), "shows",
        "the old defaults: Shows only")
      A.eq(f({ sound = true }, {}, {}), "all", "pop-up sound on: All")
      A.eq(f({ levelUpSound = true }, {}, {}), "all", "level-up sound on: All")
      A.eq(f({}, { sound = true, mockSound = false }, {}), "all", "a roast sound on wins over a laugh off")
      A.eq(f({}, { mockSound = false }, {}), "off", "the mock laugh turned off: Off")
      A.eq(f({}, {}, { showSound = false }), "off", "the awards show sound turned off: Off")
      A.eq(f("junk", 7, {}), nil, "junk is tolerated")
    end,

    ---------------------------------------------------------------------------------------- an upgrade from v0.3.0
    upgrade_keeps_the_choices_that_map_and_drops_the_old_keys = function(ns, A, W)
      boot(W, v030({
        activity = { chatOnline = true },
        popups = { levelUpSound = true, seconds = 9, layerSame = false },
        roasts = { fall = false, mockSound = true },
        stats = { wipeLine = false },
        panel = { showZone = false, grow = "up", tag_AFK = false, peekSeconds = 9, questRequests = false, scale = 1.3 },
        find = { meetArrow = false },
        version = { chatNotice = false },
      }))
      local db = W.env.TwizCrewDB
      A.eq(db.simpleSettings, true)
      A.eq(db.modules.activity.settings.chatNews, "all", "online lines were on: Everything")
      A.eq(db.modules.popups.settings.sounds, "all", "the level-up sound was on: All")
      A.eq(ns.Modules.setting("panel", "scale"), 1.3, "a setting that stays keeps its value")
      for id, keys in pairs(ns.DB.REMOVED_KEYS) do
        local saved = db.modules[id] and db.modules[id].settings or {}
        for _, key in ipairs(keys) do A.eq(saved[key], nil, id .. "." .. key .. " left saved data") end
      end
      A.eq(db.modules.roasts.settings.ownOnly, false, "kept: the My mocks window switches it")
      A.eq(db.modules.panel.settings.showOffline, false, "kept: the Offline bar switches it")
      A.eq(ns.Log.errors(10), {})
    end,

    upgrade_with_the_old_defaults_gets_the_new_defaults = function(ns, A, W)
      boot(W, v030())
      A.eq(ns.Modules.setting("activity", "chatNews"), "important")
      A.eq(ns.Modules.setting("popups", "sounds"), "shows")
      A.eq(ns.Log.errors(10), {})
    end,

    upgrade_with_chat_and_laugh_off_gets_off = function(ns, A, W)
      boot(W, v030({ activity = { chat = false, chatRoast = true }, roasts = { mockSound = false } }))
      A.eq(ns.Modules.setting("activity", "chatNews"), "off")
      A.eq(ns.Modules.setting("popups", "sounds"), "off")
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(40)
      local before = #W.printed
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      for i = before + 1, #W.printed do A.no(W.printed[i]:find("reached level", 1, true), "no chat line: " .. W.printed[i]) end
    end,

    the_switch_over_runs_once = function(ns, A, W)
      boot(W, v030({ activity = { chatOnline = true } }))
      A.eq(ns.Modules.setting("activity", "chatNews"), "all")
      ns.Modules.set("activity", "chatNews", "off") -- the player's own choice afterwards
      -- an older copy (rolled back) wrote its old keys back; the new copy starts again
      local saved = W.env.TwizCrewDB
      saved.modules.activity.settings.chat, saved.modules.activity.settings.chatOnline = true, true
      saved.modules.popups.settings.sound = true
      local db = ns.DB.init(saved, ns.Modules.list())
      A.eq(db.modules.activity.settings.chatNews, "off", "never mapped twice: the later choice stays")
      A.eq(db.modules.popups.settings.sounds, "shows")
      A.eq(db.modules.activity.settings.chat, nil, "the old keys leave again")
      A.eq(db.modules.popups.settings.sound, nil)
    end,

    a_new_install_gets_the_defaults = function(ns, A, W)
      boot(W, nil)
      local db = W.env.TwizCrewDB
      A.eq(db.simpleSettings, true)
      A.eq(db.modules.activity.settings, { chatNews = "important" })
      A.eq(db.modules.popups.settings.sounds, "shows")
      A.eq(ns.Log.errors(10), {})
    end,

    broken_saved_modules_do_not_stop_the_start = function(ns, A, W)
      local saved = v030()
      saved.modules.activity.settings = "junk"
      saved.modules.popups = 7
      boot(W, saved)
      A.eq(ns.Modules.setting("activity", "chatNews"), "important")
      A.eq(ns.Modules.setting("popups", "sounds"), "shows")
      A.eq(ns.Log.errors(10), {})
    end,

    -------------------------------------------------------------------------------------------- grow direction
    grow_direction_follows_the_half_of_the_screen = function(ns, A)
      local up = ns.PanelLogic.growsUp
      A.eq(up(900, 600, 1, 1080, 1), false, "middle at 750 of 1080: top half, grows down")
      A.eq(up(400, 100, 1, 1080, 1), true, "middle at 250: bottom half, grows up")
      A.eq(up(400, 100, 2, 1080, 1), true, "scaled: middle at 500 screen units, still below 540")
      A.eq(up(400, 300, 2, 1080, 1), false, "scaled: middle at 700 screen units, top half")
      A.eq(up(nil, 100, 1, 1080, 1), false, "unsure: down, as before")
      A.eq(up(400, 100, 0, 1080, 1), false)
    end,

    the_kept_open_panel_grows_away_from_the_nearer_edge = function(ns, A, W)
      boot(W, nil)
      W:advance(40)
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(0.3)
      local root = ns.Panel.rootForTest()
      rawset(W.env.UIParent, "GetTop", function() return 1080 end)
      local function dropAt(top, bottom)
        rawset(root, "GetLeft", function() return 50 end)
        rawset(root, "GetTop", function() return top end)
        rawset(root, "GetBottom", function() return bottom end)
        root._scripts.OnDragStart(root)
        root._scripts.OnDragStop(root)
        return ns.Modules.setting("panel", "position")
      end
      local p = dropAt(300, 100)
      A.eq({ p.point, p.x, p.y }, { "BOTTOMLEFT", 50, 100 }, "dropped low: anchored at the bottom, grows up")
      p = dropAt(1000, 800)
      A.eq({ p.point, p.x, p.y }, { "TOPLEFT", 50, -80 }, "dropped high: anchored at the top, grows down")
      W:advance(1)
      p = ns.Modules.setting("panel", "position")
      A.eq(p.point, "TOPLEFT", "a redraw keeps the corner the player dropped it at")
      A.eq(ns.Modules.get("panel").defaults.grow, nil, "no Grow direction setting any more")
      A.eq(ns.Log.errors(10), {})
    end,

    ----------------------------------------------------------------------------------------------- clear the list
    clear_the_list_lives_in_the_recent_window = function(ns, A, W)
      boot(W, nil)
      W:advance(40)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(1)
      receive(W, ns, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.ok(#ns.Feed.entries() > 0)
      ns.Recent.open()
      local b = ns.Recent.clearButtonForTest()
      A.ok(b, "a Clear the list button in the window")
      b._scripts.OnClick(b, "LeftButton")
      A.eq(ns.Feed.entries(), {})
      A.eq(ns.Recent.shownForTest(), {}, "the window shows the empty list")
      local inSettings = false
      for _, s in ipairs(ns.Modules.get("activity").settings) do if s.key == "clearRecent" then inSettings = true end end
      A.no(inSettings, "not a settings button any more")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
