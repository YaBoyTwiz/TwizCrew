-- Mock show (UI/MockShow.lua): the shared look, which picture is picked, and mocks about me going to the show.

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function start(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function logHas(ns, text)
  for _, line in ipairs(ns.Log.lines()) do if line:find(text, 1, true) then return true end end
  return false
end

return {
  files = "toc",
  tests = {
    look_round_trip = function(ns, A)
      local M = ns.MockShow
      local s = M.encodeLook(1, 3, { [1] = 1234, [5] = 5678, [2] = 999, [16] = 25 })
      A.eq(s, "1.3.1-1234.5-5678.16-25", "neck (slot 2) is not visible, so not sent")
      A.eq(M.decodeLook(s), { race = 1, sex = 3, items = { [1] = 1234, [5] = 5678, [16] = 25 } })
      A.eq(M.encodeLook(nil, 2, {}), "")
      A.no(M.decodeLook("")); A.no(M.decodeLook("junk")); A.no(M.decodeLook(nil))
      A.eq(M.decodeLook("4.2.99-5.3-0.3-7"), { race = 4, sex = 2, items = { [3] = 7 } }, "odd slots and ids dropped")
    end,
    my_race_and_gender_are_shared = function(ns, A, W)
      W.env.UnitRace = function() return "Night Elf", "NightElf", 4 end
      W.env.UnitSex = function() return 3 end
      start(ns, W)
      W:advance(2)
      A.eq(ns.Self.lastSent().lo, "4.3", "no gear any more")
    end,
    friend_look_is_kept_in_the_roster = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lo = "1.2.1-100.16-200" })
      A.eq(ns.roster:get("Frostie").look, "1.2.1-100.16-200")
    end,
    picks_the_best_picture = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      A.eq(ns.MockShow.pick("Frostie"), "icon", "nothing known")
      receive(ns, W, "Frostie", "UPDATE", { lo = "1.2" })
      A.eq(ns.MockShow.pick("Frostie"), "icon", "knowing their race doesn't change the picture")
      W.state.units.party1 = { name = "Frostie", player = true, visible = true }
      A.eq(ns.MockShow.pick("Frostie"), "live", "near me and visible")
      W:advance(6) -- the look-around tick remembers her
      A.ok(ns.MockShow.isRemembered("Frostie"))
      A.ok(logHas(ns, "mock show: remembered how Frostie looks"))
      W.state.units.party1.visible = false
      A.eq(ns.MockShow.pick("Frostie"), "remembered", "walked away: the remembered look")
    end,
    nameplate_counts_as_near = function(ns, A, W)
      start(ns, W)
      W.state.units.nameplate4 = { name = "Ginkan", player = true }
      A.eq(ns.MockShow.liveUnit("Ginkan"), "nameplate4")
    end,
    a_mock_about_me_opens_the_show = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lo = "1.2.1-100" })
      receive(ns, W, "Frostie", "MOCK", { t = "Twiz", x = "Rest in pieces, Twiz." })
      A.ok(ns.MockShow.isShown())
      A.ok(logHas(ns, "mock show: Frostie (icon)"))
      local s = ns.Roasts.forTest.shown()
      A.eq(s[#s], "Frostie: Rest in pieces, Twiz.")
      W:advance(8)
      A.eq(ns.Log.errors(10), {})
    end,
    a_mock_about_someone_else_stays_a_line = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "MOCK", { t = "Ginkan", x = "Rest in pieces, Ginkan." })
      A.no(ns.MockShow.isShown())
    end,
    the_3d_switch_off_means_the_plain_line = function(ns, A, W)
      start(ns, W)
      ns.Modules.set("roasts", "mockModel", false)
      receive(ns, W, "Frostie", "MOCK", { t = "Twiz", x = "Rest in pieces, Twiz." })
      A.no(ns.MockShow.isShown())
      local s = ns.Roasts.forTest.shown()
      A.eq(s[#s], "Frostie: Rest in pieces, Twiz.")
    end,
    try_a_mock_buttons = function(ns, A, W)
      start(ns, W)
      for _, what in ipairs({ "mock live", "mock icon" }) do
        W.env.SlashCmdList.TWIZCREW("test " .. what)
        A.ok(ns.MockShow.isShown(), what)
      end
      A.ok(logHas(ns, "mock show: Twiz (live)"))
      A.ok(logHas(ns, "mock show: Twiz (icon)"))
      A.eq(ns.Log.errors(10), {})
    end,
    laugh_sound_matches_race_and_gender = function(ns, A, W)
      A.eq(ns.MockShow.laughSound(3, 2), 539883, "dwarf male")
      A.eq(ns.MockShow.laughSound(4, 3), 540877, "night elf female")
      A.eq(ns.MockShow.laughSound(99, 2), nil)
      local played = {}
      W.env.PlaySoundFile = function(file, channel) played[#played + 1] = { file, channel } end
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lo = "7.3.1-100" })
      receive(ns, W, "Frostie", "MOCK", { t = "Twiz", x = "Rest in pieces, Twiz." })
      A.eq(played, { { 540268, "Master" } }, "a gnome female laugh for Frostie (from her shared race)")
      ns.MockShow.hide()
      ns.Modules.set("roasts", "mockSound", false)
      W:advance(5)
      receive(ns, W, "Frostie", "MOCK", { t = "Twiz", x = "Again." })
      A.eq(#played, 1, "sound off: quiet")
    end,
    sits_beside_the_middle_of_the_screen = function(ns, A, W)
      start(ns, W)
      W.env.TwizCrewPanel = { IsShown = function() return true end, GetRight = function() return 1900 end }
      W.env.SlashCmdList.TWIZCREW("test mock icon")
      A.eq(ns.MockShow.place(), "beside center", "the same spot wherever the crew panel is")
      ns.MockShow.hide()
    end,
    dragging_moves_it_and_it_remembers = function(ns, A, W)
      start(ns, W)
      W.env.SlashCmdList.TWIZCREW("test mock icon")
      -- the stub's frames have no real position: pretend it was dropped 100 right, 50 down from the middle
      ns.db.mockShowPos = { point = "CENTER", x = 100, y = -50 }
      A.eq(ns.MockShow.place(), "where you put it")
      W.env.SlashCmdList.TWIZCREW("mock spot")
      A.eq(ns.db.mockShowPos, nil)
      A.eq(ns.MockShow.place(), "beside center")
      ns.db.mockShowPos = { point = "CENTER", x = 1, y = 2 }
      ns.Modules.resetAll()
      A.eq(ns.db.mockShowPos, nil, "Reset everything puts it back too")
      ns.MockShow.hide()
      A.eq(ns.Log.errors(10), {})
    end,
    drag_stop_saves_the_spot_without_an_error = function(ns, A, W)
      start(ns, W)
      W.env.SlashCmdList.TWIZCREW("test mock icon")
      local f
      for _, fr in ipairs(W.frames) do if fr._name == "TwizCrewMockShow" then f = fr end end
      A.ok(f and f._scripts.OnDragStop, "the show has a drag handler")
      -- the stub's frames have no real position: say where the show and the screen's center are
      rawset(f, "GetCenter", function() return 1060, 490 end)
      rawset(W.env.UIParent, "GetCenter", function() return 960, 540 end)
      f._scripts.OnDragStop(f)
      A.eq(ns.Log.errors(10), {}, "no error logged")
      A.eq(ns.db.mockShowPos, { point = "CENTER", x = 100, y = -50 })
      ns.MockShow.hide()
    end,
    show_goes_away_by_itself = function(ns, A, W)
      start(ns, W)
      W.env.SlashCmdList.TWIZCREW("test mock icon")
      A.ok(ns.MockShow.isShown())
      local f = W.env.TwizCrewMockShow
      if f and f._scripts and f._scripts.OnUpdate then
        W:advance(7)
        f._scripts.OnUpdate(f, 0.1)
        A.no(ns.MockShow.isShown(), "hidden after the time is up")
      end
      ns.MockShow.hide()
      A.no(ns.MockShow.isShown())
    end,
  },
}
