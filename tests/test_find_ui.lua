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

    ---------------------------------------------------------------------------------------------- big arrow
    clicking_a_row_arrow_opens_the_big_arrow_and_arrival_closes_it = function(ns, A, W)
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
      A.eq(ns.BigArrow.stateForTest().text, "You're here")
      W:advance(2)
      A.no(ns.BigArrow.stateForTest().shown, "gone after arriving")
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

    big_arrow_closes_when_they_leave_the_group = function(ns, A, W)
      frostieNorth(ns, W)
      ns.BigArrow.point({ kind = "member", name = "Frostie" })
      ungroup(W)
      W:advance(0.2)
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
  },
}
