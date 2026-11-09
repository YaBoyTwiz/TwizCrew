-- Find the crew on screen: the row arrows on the Crew panel, the big arrow, the world map click (meet-ups), the
-- meet-up icons on the world map and the minimap. The player stands at world (-9000, -1000) in Elwynn Forest.

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function near(A, actual, expected, msg)
  A.ok(type(actual) == "number" and math.abs(actual - expected) < 0.01,
    (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function group(W, names)
  W.state.inGroup = true
  W.state.groupMembers = names or { "Frostie" }
  for i, n in ipairs(W.state.groupMembers) do W.state.units["party" .. i] = { name = n, player = true } end
  W:fire("GROUP_ROSTER_UPDATE")
end

local function ungroup(W)
  W.state.inGroup = false
  W.state.groupMembers = {}
  for i = 1, 4 do W.state.units["party" .. i] = nil end
  W:fire("GROUP_ROSTER_UPDATE")
end

local function hear(ns, W, from, msgType, fields, chatType)
  for _, text in ipairs(ns.Codec.encode(msgType, fields)) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, chatType or "PARTY", from .. "-Realm")
  end
end

local function friend(ns, W, name, zone, chatType)
  hear(ns, W, name, "STATE", { cl = "MAGE", lv = "12", zn = zone or "Elwynn Forest", sz = "Goldshire",
    ver = "0.1.0" }, chatType)
end

local function rowIndex(ns, name)
  for i, m in ipairs(ns.Panel.models()) do if m.name == name then return i end end
end

local function sentOf(ns, W, msgType)
  local out = {}
  for _, m in ipairs(W.sent) do
    local msg = ns.Codec.decode(m.text)
    if msg and msg.type == msgType then out[#out + 1] = { chatType = m.chatType, fields = msg.fields } end
  end
  return out
end

-- Frostie in our party, 100 yards north of us, the panel redrawn.
local function frostieNorth(ns, W)
  boot(W)
  group(W)
  friend(ns, W, "Frostie")
  hear(ns, W, "Frostie", "POS", { c = "0", x = "-8900", y = "-1000" })
  W:advance(1.1)
end

return {
  files = "toc",
  tests = {
    ---------------------------------------------------------------------------------------------- row arrows
    a_party_member_gets_a_row_arrow_that_turns = function(ns, A, W)
      frostieNorth(ns, W)
      local i = rowIndex(ns, "Frostie")
      local a = ns.Panel.rowArrowForTest(i)
      A.ok(a, "row arrow")
      A.eq(a.text, "100 yd")
      near(A, a.angle, 0)
      A.ok(ns.Panel.arrowTickerForTest(), "the arrows turn between redraws")
      W.state.facing = math.pi / 2
      W:advance(0.2)
      near(A, ns.Panel.rowArrowForTest(i).angle, -math.pi / 2, "turned with us")
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8700", y = "-1000" })
      W:advance(0.2)
      A.eq(ns.Panel.rowArrowForTest(i).text, "300 yd")
      A.eq(ns.Log.errors(10), {})
    end,

    friends_outside_the_group_get_no_row_arrow = function(ns, A, W)
      boot(W)
      friend(ns, W, "Chaos", nil, "WHISPER")
      hear(ns, W, "Chaos", "POS", { c = "0", x = "-8900", y = "-1000" }, "WHISPER")
      W:advance(1.1)
      A.eq(ns.Panel.rowArrowForTest(rowIndex(ns, "Chaos")), nil)
      A.no(ns.Panel.arrowTickerForTest(), "no ticker without arrows")
    end,

    another_zone_shows_a_still_arrow_without_distance = function(ns, A, W)
      boot(W)
      group(W)
      friend(ns, W, "Frostie", "Westfall")
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-11000", y = "-1000" })
      W:advance(1.1)
      local a = ns.Panel.rowArrowForTest(rowIndex(ns, "Frostie"))
      A.ok(a and a.still)
      A.eq(a.text, nil)
    end,

    the_row_arrow_goes_when_the_group_breaks_up = function(ns, A, W)
      frostieNorth(ns, W)
      ungroup(W)
      W:advance(1.2)
      A.eq(ns.Panel.rowArrowForTest(rowIndex(ns, "Frostie")), nil)
    end,

    tiny_rows_drop_the_distance = function(ns, A, W)
      frostieNorth(ns, W)
      ns.Modules.set("panel", "rowStyle", "tiny")
      W:advance(0.2)
      local a = ns.Panel.rowArrowForTest(rowIndex(ns, "Frostie"))
      A.ok(a, "the arrow stays")
      A.eq(a.text, nil, "no distance in tiny rows")
    end,

    ---------------------------------------------------------------------------------------------- running off
    running_off_rules = function(ns, A)
      local L = ns.FindLogic
      local opts = { near = 40, far = 100, window = 20 }
      local me = { c = 0, x = 0, y = 0 }
      local tr, alarm = L.runaway(nil, me, { c = 0, x = 10, y = 0 }, 100, opts)
      A.no(alarm, "close")
      tr, alarm = L.runaway(tr, me, { c = 0, x = 60, y = 0 }, 105, opts)
      A.no(alarm, "not far yet")
      tr, alarm = L.runaway(tr, me, { c = 0, x = 130, y = 0 }, 112, opts)
      A.ok(alarm, "close to far within 20 s: running off")
      tr, alarm = L.runaway(tr, me, { c = 0, x = 200, y = 0 }, 113, opts)
      A.no(alarm, "only once until they come back")
      -- slow drift: too long since they were close
      tr = L.runaway(nil, me, { c = 0, x = 10, y = 0 }, 0, opts)
      tr, alarm = L.runaway(tr, me, { c = 0, x = 130, y = 0 }, 60, opts)
      A.no(alarm, "drifted off over a minute: no alarm")
      -- I ran off, they stood still
      tr = L.runaway(nil, me, { c = 0, x = 10, y = 0 }, 0, opts)
      tr, alarm = L.runaway(tr, { c = 0, x = -130, y = 0 }, { c = 0, x = 10, y = 0 }, 10, opts)
      A.no(alarm, "you walked away, not them")
    end,
    a_party_member_running_off_sets_off_the_alarm = function(ns, A, W)
      boot(W)
      group(W)
      friend(ns, W, "Frostie")
      W.state.missing.UnitPosition = nil
      local ran = {}
      ns.Bus.on("test", "RAN_OFF", function(name) ran[#ran + 1] = name end)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" }) -- 10 yards: right next to us
      W:advance(1.1)
      local played = {}
      W.env.PlaySound = function(k) played[#played + 1] = k end
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8860", y = "-1000" }) -- 140 yards away a few seconds later
      W:advance(3)
      A.ok(ns.Find.isRunningOff("Frostie"), "running off")
      A.eq(ran, {}, "RAN_OFF is only for us running off")
      A.eq(played, {}, "no sound (owner 2026-11-08: the flashing and the pop-up are enough)")
      local t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "Frostie is running off!")
      A.eq(t[#t].subtext, "140 yd away: click for the big arrow")
      A.ok(ns.Panel.rowAlarmForTest(rowIndex(ns, "Frostie")), "the row arrow flashes")
      ns.BigArrow.point({ kind = "member", name = "Frostie" })
      A.eq(ns.BigArrow.stateForTest().label, "Frostie is running off!", "the big arrow says so too")
      W:advance(12)
      A.no(ns.Find.isRunningOff("Frostie"), "the alarm runs out")
      A.no(ns.Panel.rowAlarmForTest(rowIndex(ns, "Frostie")))
      A.eq(ns.Log.errors(10), {})
    end,
    running_off_yourself_counts_for_wanderer = function(ns, A, W)
      boot(W)
      W:advance(ns.Config.SESSION_DECIDE_AFTER + 1) -- the stats session decides
      group(W)
      friend(ns, W, "Frostie")
      ns.Modules.set("find", "runaway", false) -- counts even with the alarm off
      local ran = {}
      ns.Bus.on("test", "RAN_OFF", function(name) ran[#ran + 1] = name end)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" }) -- 10 yards: right next to us
      W:advance(1.1)
      W.state.map.y = 0.57 -- we walk 140 yards away; Frostie stays
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" })
      W:advance(3)
      A.eq(ran, { "Frostie" })
      A.eq(ns.StatsStore.get("session", "wd"), 1)
      W:advance(10)
      A.eq(ns.StatsStore.get("session", "wd"), 1, "once, until we're close again")
      A.eq(ns.Log.errors(10), {})
    end,

    walking_away_gives_no_alarm_about_them = function(ns, A, W)
      boot(W)
      group(W)
      friend(ns, W, "Frostie")
      local ran = {}
      ns.Bus.on("test", "RAN_OFF", function(name) ran[#ran + 1] = name end)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" })
      W:advance(1.1)
      local before = #ns.Popups.textsForTest()
      W.state.map.y = 0.57 -- we walk away; Frostie stays
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" })
      W:advance(3)
      A.eq(ran, { "Frostie" })
      A.no(ns.Find.isRunningOff("Frostie"), "we moved, not them")
      local t = ns.Popups.textsForTest()
      for i = before + 1, #t do A.no(tostring(t[i].text):find("is running off!", 1, true), "no pop-up") end
      A.eq(ns.Log.errors(10), {})
    end,

    the_running_off_warning_can_be_switched_off = function(ns, A, W)
      boot(W)
      group(W)
      friend(ns, W, "Frostie")
      ns.Modules.set("find", "runaway", false)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8990", y = "-1000" })
      W:advance(1.1)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8860", y = "-1000" })
      W:advance(3)
      A.no(ns.Find.isRunningOff("Frostie"))
    end,

    ---------------------------------------------------------------------------------------------- big arrow
    clicking_a_row_arrow_opens_the_big_arrow_and_it_stays = function(ns, A, W)
      frostieNorth(ns, W)
      ns.Panel.arrowClicked(ns.Panel.rowFrameForTest(rowIndex(ns, "Frostie")))
      local s = ns.BigArrow.stateForTest()
      A.ok(s.shown)
      A.eq(s.kind, "member")
      A.eq(s.label, "Frostie")
      A.eq(s.text, "100 yd")
      near(A, s.angle, 0)
      A.no(s.compass)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8995", y = "-1000" }) -- 5 yards away
      W:advance(0.2)
      A.eq(ns.BigArrow.stateForTest().text, "Right here")
      W:advance(10)
      A.ok(ns.BigArrow.stateForTest().shown, "stays while you're next to them (a fight together)")
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8900", y = "-1000" }) -- they run off: 100 yards
      W:advance(0.2)
      A.eq(ns.BigArrow.stateForTest().text, "100 yd", "points again")
      A.eq(ns.Log.errors(10), {})
    end,

    clicking_the_row_arrow_again_closes_the_big_arrow = function(ns, A, W)
      frostieNorth(ns, W)
      local r = ns.Panel.rowFrameForTest(rowIndex(ns, "Frostie"))
      ns.Panel.arrowClicked(r)
      A.ok(ns.BigArrow.stateForTest().shown)
      ns.Panel.arrowClicked(r)
      A.no(ns.BigArrow.stateForTest().shown)
    end,

    big_arrow_to_another_zone_names_it = function(ns, A, W)
      boot(W)
      group(W)
      friend(ns, W, "Frostie", "Westfall")
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-10200", y = "-1000" }) -- 1200 yards south
      ns.BigArrow.point({ kind = "member", name = "Frostie" })
      A.eq(ns.BigArrow.stateForTest().text, "Westfall \194\183 1.2k yd")
    end,

    big_arrow_is_a_compass_without_facing = function(ns, A, W)
      frostieNorth(ns, W)
      W.state.missing.GetPlayerFacing = true
      ns.BigArrow.point({ kind = "member", name = "Frostie" })
      A.ok(ns.BigArrow.stateForTest().compass, "north-up with an N")
    end,

    big_arrow_waits_when_they_leave_the_group = function(ns, A, W)
      frostieNorth(ns, W)
      ns.BigArrow.point({ kind = "member", name = "Frostie" })
      ungroup(W)
      W:advance(5)
      local s = ns.BigArrow.stateForTest()
      A.ok(s.shown, "only you close it")
      A.eq(s.text, "not in your group")
      A.eq(s.angle, nil)
      ns.BigArrow.close()
      A.no(ns.BigArrow.stateForTest().shown)
    end,

    a_meetup_turns_on_the_big_arrow_until_you_get_there = function(ns, A, W)
      boot(W)
      friend(ns, W, "Frostie", nil, "WHISPER")
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-1000", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      local s = ns.BigArrow.stateForTest()
      A.ok(s.shown)
      A.eq(s.kind, "meet")
      A.eq(s.label, "Meet Frostie")
      A.eq(s.text, "500 yd")
      W.state.map.y = 0.255 -- 10 yards from the spot
      W:advance(0.2)
      A.eq(ns.BigArrow.stateForTest().text, "You're here")
      W:advance(2)
      A.no(ns.BigArrow.stateForTest().shown)
      A.ok(ns.Find.meet(), "the meet-up stays for the others")
    end,

    no_big_arrow_for_a_meetup_when_switched_off = function(ns, A, W)
      boot(W)
      ns.Modules.set("find", "meetArrow", false)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-1000", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      A.no(ns.BigArrow.stateForTest().shown)
      A.ok(ns.Find.meet())
    end,

    clicking_the_meetup_popup_points_the_way = function(ns, A, W)
      boot(W)
      ns.Modules.set("find", "meetArrow", false)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-1000", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      W:advance(1)
      ns.Popups.clickForTest(1)
      A.eq(ns.BigArrow.stateForTest().kind, "meet")
    end,

    clearing_the_meetup_closes_its_arrow = function(ns, A, W)
      boot(W)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-1000", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", clr = "1", a = "all" }, "WHISPER")
      A.no(ns.BigArrow.stateForTest().shown)
    end,

    ---------------------------------------------------------------------------------------------- map click
    ctrl_right_click_on_the_map_offers_party_or_everyone = function(ns, A, W)
      boot(W)
      A.ok(ns.MeetMap.hookedForTest(), "a click handler on the world map")
      group(W)
      W.state.ctrl = true
      A.ok(W:clickMap("RightButton", 0.25, 0.25), "taken: the map does not zoom out")
      local items = ns.MeetMap.menuForTest()
      A.eq(#items, 3)
      A.eq(items[1].label, "Meet here: my party")
      A.eq(items[2].label, "Meet here: everyone")
      A.eq(items[3].label, "Cancel")
      items[1].onClick()
      W:advance(1)
      local meet = sentOf(ns, W, "MEET")
      A.eq(#meet, 1)
      A.eq(meet[1].chatType, "PARTY")
      A.eq(meet[1].fields.x, "-8500")
      A.eq(meet[1].fields.y, "-500")
      A.eq(W.printed[#W.printed], "TwizCrew: meet-up sent to your party.")
      A.eq(ns.Log.errors(10), {})
    end,

    alone_the_map_menu_only_offers_everyone = function(ns, A, W)
      boot(W)
      W.state.ctrl = true
      W:clickMap("RightButton", 0.25, 0.25)
      local items = ns.MeetMap.menuForTest()
      A.eq(#items, 2)
      A.eq(items[1].label, "Meet here: everyone")
      items[2].onClick() -- Cancel
      W:advance(1)
      A.eq(#sentOf(ns, W, "MEET"), 0)
    end,

    plain_right_click_is_left_to_the_map = function(ns, A, W)
      boot(W)
      A.no(W:clickMap("RightButton", 0.25, 0.25), "no Ctrl: the map zooms out as usual")
      W.state.ctrl = true
      A.no(W:clickMap("LeftButton", 0.25, 0.25), "Ctrl + left-click is not ours")
      A.eq(ns.MeetMap.menuForTest(), nil)
      ns.Modules.set("find", "meetups", false)
      A.no(W:clickMap("RightButton", 0.25, 0.25), "meet-ups off")
    end,

    a_spot_the_game_cannot_place_says_so = function(ns, A, W)
      boot(W)
      W.state.ctrl = true
      W.state.worldMap.mapID = 947 -- the whole world
      A.ok(W:clickMap("RightButton", 0.5, 0.5))
      A.eq(W.printed[#W.printed], "TwizCrew: pick a spot inside a zone for a meet-up.")
      A.eq(ns.MeetMap.menuForTest(), nil)
    end,

    openmap_stitched_map_clicks_and_icon = function(ns, A, W)
      rawset(W.env, "OpenMapAPI", {
        IsStitched = function() return true end,
        CursorPosition = function() return 0.5, 0.5 end,
        MapAt = function() return 1429 end,
        MapFromWorld = function(id, u, v) return 0.25, 0.25 end,
        CanvasFromWorldPos = function(c, x, y) return 0.4, 0.6 end,
        ArtTopLevel = function() return 100 end,
      })
      boot(W)
      W.state.ctrl = true
      W:clickMap("RightButton", 0.9, 0.9) -- the canvas point is ignored on the stitched map
      ns.MeetMap.menuForTest()[1].onClick()
      W:advance(1)
      local meet = sentOf(ns, W, "MEET")
      A.eq(meet[1].fields.x, "-8500")
      A.eq(meet[1].fields.y, "-500")
      W.state.worldMap.shown = true
      W:advance(0.3)
      local v = ns.MeetMap.stateForTest()
      A.ok(v.world)
      near(A, v.worldX, 0.4)
      near(A, v.worldY, 0.6)
    end,

    the_world_map_is_hooked_when_it_loads_later = function(ns, A, W)
      W.state.missing.WorldMapFrame = true
      boot(W)
      A.no(ns.MeetMap.hookedForTest(), "no world map yet")
      W.state.missing.WorldMapFrame = false
      W:fire("ADDON_LOADED", "Blizzard_WorldMap")
      A.ok(ns.MeetMap.hookedForTest(), "hooked once it loaded")
      W:fire("ADDON_LOADED", "Blizzard_WorldMap")
      A.eq(#W.mapClickHandlers, 1, "only once")
    end,

    big_arrow_loses_a_friend_who_goes_quiet = function(ns, A, W)
      frostieNorth(ns, W)
      ns.BigArrow.point({ kind = "member", name = "Frostie" })
      A.eq(ns.BigArrow.stateForTest().text, "100 yd")
      W:advance(61)
      A.eq(ns.BigArrow.stateForTest().text, "position unknown")
    end,

    raid_members_are_found_too = function(ns, A, W)
      boot(W)
      W.state.inGroup, W.state.inRaid = true, true
      W.state.groupMembers = {}
      W.state.units.raid1 = { name = "Twiz", player = true }
      W.state.units.raid7 = { name = "Frostie", player = true, pos = { y = -8900, x = -1000, instance = 0 } }
      W:fire("GROUP_ROSTER_UPDATE")
      friend(ns, W, "Frostie")
      A.eq(ns.Where.unitFor("Frostie"), "raid7")
      A.eq(ns.Where.unitFor("Twiz"), nil, "never ourselves")
      A.eq(ns.Find.arrowFor("Frostie").text, "100 yd", "live raid position")
    end,

    ---------------------------------------------------------------------------------------------- try it out
    walking_buddy_shows_arrows_and_a_meetup_through_the_real_code = function(ns, A, W)
      boot(W)
      W.env.SlashCmdList.TWIZCREW("test walk")
      W:advance(1.1)
      local i = rowIndex(ns, "Walkbuddy (test)")
      A.ok(i, "Walkbuddy is on the panel")
      local a = ns.Panel.rowArrowForTest(i)
      A.ok(a and a.text == "80 yd", "a row arrow 80 yards away: " .. tostring(a and a.text))
      local m = ns.Find.meet()
      A.ok(m, "a pretend meet-up")
      A.eq(m.audience, "party")
      A.eq(ns.BigArrow.stateForTest().label, "Meet Walkbuddy (test)")
      A.eq(ns.BigArrow.stateForTest().text, "120 yd")
      local before = ns.Panel.rowArrowForTest(i).angle
      W:advance(3)
      A.ok(ns.Panel.rowArrowForTest(i).angle ~= before, "it walks")
      W:advance(1)
      A.eq(#W.sent > 0 and (function()
        for _, s in ipairs(W.sent) do
          local msg = ns.Codec.decode(s.text)
          if msg and (msg.type == "MEET" or msg.type == "POS") then return "sent" end
        end
        return "nothing"
      end)() or "nothing", "nothing", "nothing fake is ever sent")
      W.env.SlashCmdList.TWIZCREW("test walk")
      W:advance(0.1)
      A.eq(rowIndex(ns, "Walkbuddy (test)"), nil, "gone")
      A.eq(ns.Find.meet(), nil, "its meet-up too")
      W.env.SlashCmdList.TWIZCREW("test walk")
      A.ok(ns.Find.meet(), "a second Walkbuddy brings a meet-up again (a new id)")
      W.env.SlashCmdList.TWIZCREW("test clear")
      A.eq(ns.roster:get("Walkbuddy (test)"), nil, "clear removes it")
      A.eq(ns.Find.meet(), nil)
      A.eq(ns.Log.errors(10), {})
    end,

    ---------------------------------------------------------------------------------------------- icons
    the_meetup_shows_on_the_world_map_it_belongs_to = function(ns, A, W)
      boot(W)
      W.state.worldMap.shown = true
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-500", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      W:advance(0.3)
      local v = ns.MeetMap.stateForTest()
      A.ok(v.world, "on the Elwynn map")
      near(A, v.worldX, 0.25)
      near(A, v.worldY, 0.25)
      W.state.worldMap.mapID = 1438
      W:advance(0.3)
      A.no(ns.MeetMap.stateForTest().world, "not on Teldrassil's map")
      W.state.worldMap.mapID = 1429
      W.state.worldMap.shown = false
      W:advance(0.3)
      A.no(ns.MeetMap.stateForTest().world, "map closed")
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", clr = "1", a = "all" }, "WHISPER")
      W:advance(0.3)
      A.no(ns.MeetMap.stateForTest().minimap, "cleared: no icon anywhere")
      A.eq(ns.Log.errors(10), {})
    end,

    the_meetup_shows_on_the_minimap = function(ns, A, W)
      boot(W)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8900", y = "-1000", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER") -- 100 yards north
      W:advance(0.3)
      local v = ns.MeetMap.stateForTest()
      A.ok(v.minimap)
      A.ok(math.abs(v.miniX) < 0.01 and v.miniY > 0, "north is up")
      A.no(v.edge)
      ns.Modules.set("find", "meetMinimap", false)
      W:advance(0.3)
      A.no(ns.MeetMap.stateForTest().minimap, "switched off")
      ns.Modules.set("find", "meetMinimap", true)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-2", c = "0", x = "-11000", y = "-1000", p = "Westfall",
        a = "all", l = "900" }, "WHISPER")
      W:advance(0.3)
      A.ok(ns.MeetMap.stateForTest().edge, "far away: on the edge")
    end,

    ---------------------------------------------------------------------------------------------- review fixes
    -- On Blizzard's map the icon sits above the map's own pins and explored-area overlays (their levels come from the
    -- map's frame level manager), not at the canvas's level under them.
    the_world_map_icon_sits_above_the_maps_own_pins = function(ns, A, W)
      rawset(W.env.WorldMapFrame, "GetPinFrameLevelsManager", function()
        return { GetValidFrameLevel = function(_, kind)
          if kind == "PIN_FRAME_LEVEL_AREA_POI" then return 500 end
          if kind == "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" then return 300 end
          error("unknown frame level type " .. tostring(kind))
        end }
      end)
      boot(W)
      W.state.worldMap.shown = true
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-500", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      W:advance(0.3)
      local v = ns.MeetMap.stateForTest()
      A.ok(v.world)
      A.eq(v.worldLevel, 501)
      A.eq(ns.Log.errors(10), {})
    end,

    -- A turning minimap with no facing can't place the icon (it would be off by the turn): hidden. The game's own
    -- view radius sets the scale when it has one.
    the_minimap_icon_needs_facing_on_a_turning_minimap = function(ns, A, W)
      rawset(W.env.Minimap, "GetFrameLevel", function() return 7 end)
      boot(W)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8900", y = "-1000", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER") -- 100 yards north
      W.state.cvars.rotateMinimap = "1"
      W.state.facing = nil
      W:advance(0.3)
      A.no(ns.MeetMap.stateForTest().minimap, "turning, facing unknown: hidden")
      W.state.facing = 0
      W.env.C_Minimap = { GetViewRadius = function() return 200 end }
      W:advance(0.3)
      local v = ns.MeetMap.stateForTest()
      A.ok(v.minimap)
      near(A, v.miniY, 100 * 140 / 400, "400 yards across")
      A.eq(v.miniLevel, 12, "above the minimap's own level")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
