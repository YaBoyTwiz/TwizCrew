-- Find the crew, pure rules (no WoW frames): distance and direction, arrow rules, the send rule, meet-up life,
-- minimap placement. World positions are { c = continent, x = yards north, y = yards west }, as the game gives them.

local function near(A, actual, expected, msg, tolerance)
  A.ok(type(actual) == "number" and math.abs(actual - expected) < (tolerance or 0.001),
    (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local PI = math.pi
local CFG = { move = 10, gap = 3, keepAlive = 30 }

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/UpdateLogic.lua", "UI/MinimapLogic.lua", "Find/FindLogic.lua" },
  tests = {
    distance_and_direction = function(ns, A)
      local L = ns.FindLogic
      local me = { c = 0, x = 100, y = 100 }
      local d, b = L.vector(me, { c = 0, x = 130, y = 100 }) -- 30 yards north
      near(A, d, 30, "north distance")
      near(A, b, 0, "north bearing")
      d, b = L.vector(me, { c = 0, x = 100, y = 140 }) -- 40 yards west
      near(A, d, 40, "west distance")
      near(A, b, PI / 2, "west is a quarter turn counter-clockwise")
      local _, east = L.vector(me, { c = 0, x = 100, y = 60 })
      near(A, east, -PI / 2, "east")
      local _, south = L.vector(me, { c = 0, x = 70, y = 100 })
      near(A, math.abs(south), PI, "south")
      d, b = L.vector(me, { c = 0, x = 103, y = 104 })
      near(A, d, 5, "3-4-5")
    end,

    no_direction_across_continents_or_with_junk = function(ns, A)
      local L = ns.FindLogic
      local me = { c = 0, x = 1, y = 1 }
      A.eq(L.vector(me, { c = 1, x = 1, y = 1 }), nil, "other continent")
      A.eq(L.vector(me, { c = 0, x = 0 / 0, y = 1 }), nil, "nan")
      A.eq(L.vector(nil, me), nil)
      A.eq(L.vector(me, { c = 0, x = "3", y = 1 }), nil, "not a number")
    end,

    relative_angle_turns_with_facing = function(ns, A)
      local L = ns.FindLogic
      near(A, L.relative(0, 0), 0, "ahead")
      near(A, L.relative(PI / 2, 0), PI / 2, "left")
      near(A, L.relative(0, PI / 2), -PI / 2, "facing west, north is on the right")
      near(A, L.relative(PI * 0.9, -PI * 0.9), -PI * 0.2, "wraps around")
      near(A, L.relative(PI / 3, nil), PI / 3, "no facing: compass (north up)")
    end,

    distance_text = function(ns, A)
      local L = ns.FindLogic
      A.eq(L.distanceText(0), "0 yd")
      A.eq(L.distanceText(119.6), "120 yd")
      A.eq(L.distanceText(999), "999 yd")
      A.eq(L.distanceText(1000), "1.0k yd")
      A.eq(L.distanceText(1234), "1.2k yd")
      A.eq(L.distanceText(25500), "25.5k yd")
      A.eq(L.distanceText(nil), "")
    end,

    row_arrow_rules = function(ns, A)
      local L = ns.FindLogic
      local opts = { near = 15, staleAfter = 60 }
      local me = { c = 0, x = 0, y = 0, zone = "Elwynn Forest" }
      local them = { c = 0, x = 100, y = 0, zone = "Elwynn Forest", at = 1000 }
      local r = L.rowArrow(me, them, 1010, nil, opts)
      A.ok(r, "same zone")
      A.eq(r.text, "100 yd")
      near(A, r.angle, 0)
      A.no(r.still)
      A.ok(r.compass, "facing was given as nil: compass")
      r = L.rowArrow(me, them, 1010, PI / 2, opts)
      A.no(r.compass)
      near(A, r.angle, -PI / 2, "turned left: north is on the right")
      A.eq(L.rowArrow(me, them, 1061, 0, opts), nil, "stale after 60 s")
      A.eq(L.rowArrow(me, { c = 0, x = 10, y = 0, zone = "Elwynn Forest", at = 1000 }, 1001, 0, opts), nil, "too close")
      A.eq(L.rowArrow(nil, them, 1001, 0, opts), nil, "my position unknown")
      A.eq(L.rowArrow(me, { c = 1, x = 0, y = 0, zone = "Teldrassil", at = 1000 }, 1001, 0, opts), nil, "other continent")
      r = L.rowArrow(me, { c = 0, x = 3000, y = 0, zone = "Westfall", at = 1000 }, 1001, 0, opts)
      A.ok(r and r.still, "another zone on the same continent: a still arrow")
      A.eq(r.text, nil, "no distance on a still arrow")
      A.eq(r.zone, "Westfall")
    end,

    big_arrow_state = function(ns, A)
      local L = ns.FindLogic
      local me = { c = 0, x = 0, y = 0 }
      local s = L.bigArrow(me, { c = 0, x = 0, y = 500 }, 0, 15)
      A.eq(s.text, "500 yd")
      near(A, s.angle, PI / 2)
      A.no(s.arrived)
      s = L.bigArrow(me, { c = 0, x = 3, y = 4 }, 0, 15)
      A.ok(s.arrived, "within 15 yards")
      A.eq(L.bigArrow(me, { c = 1, x = 0, y = 0 }, 0, 15), nil, "other continent")
      A.ok(L.bigArrow(me, { c = 0, x = 50, y = 0 }, nil, 15).compass, "no facing: compass")
    end,

    send_rule = function(ns, A)
      local L = ns.FindLogic
      local last = { c = 0, x = 0, y = 0, at = 100 }
      A.ok(L.shouldSend(nil, { c = 0, x = 0, y = 0 }, 100, CFG), "first one")
      A.no(L.shouldSend(last, { c = 0, x = 2, y = 0 }, 110, CFG), "standing still")
      A.no(L.shouldSend(last, { c = 0, x = 20, y = 0 }, 102, CFG), "moved but too soon")
      A.ok(L.shouldSend(last, { c = 0, x = 20, y = 0 }, 103, CFG), "moved 20 yards, 3 s later")
      A.ok(L.shouldSend(last, { c = 0, x = 0, y = 0 }, 130, CFG), "keep-alive")
      A.ok(L.shouldSend(last, { c = 1, x = 0, y = 0 }, 104, CFG), "other continent counts as moved")
      A.ok(L.shouldSend(last, { c = 0, x = 0, y = 0 }, 101, CFG, true), "forced (group changed)")
      A.no(L.shouldSend(last, { c = 0, x = 0, y = 0 }, 100.5, CFG, true), "forced, but at most once a second")
    end,

    meet_left = function(ns, A)
      local L = ns.FindLogic
      A.eq(L.meetLeft({ expires = 1900 }, 1000), 900)
      A.eq(L.meetLeft({ expires = 1000 }, 1000), 0)
      A.eq(L.meetLeft({ expires = 900 }, 1000), 0)
      A.eq(L.meetLeft(nil, 1000), 0)
    end,

    position_fields_round_trip = function(ns, A)
      local L = ns.FindLogic
      local f = L.posFields({ c = 0, x = -8840.62, y = 489.7 })
      A.eq(f, { c = "0", x = "-8841", y = "490" })
      A.eq(L.posFields(nil), { u = "1" })
      A.eq(L.readPos({ c = "0", x = "-8841", y = "490" }), { c = 0, x = -8841, y = 490 })
      A.eq(L.readPos({ u = "1" }), nil)
      A.eq(L.readPos({ c = "0", x = "abc", y = "1" }), nil)
      A.eq(L.readPos({ c = "0", x = "1e999", y = "1" }), nil, "not finite")
    end,

    minimap_offset = function(ns, A)
      local L = ns.FindLogic
      -- outdoors, zoom 0: 466.67 yards across a 140 px minimap
      local x, y, edge = L.minimapOffset(100, 0, 0, false, 0, false, 140, "ROUND")
      near(A, x, 0, "north: x", 0.01)
      near(A, y, 100 * 140 / (1400 / 3), "north: y", 0.01)
      A.no(edge)
      x, y = L.minimapOffset(100, -PI / 2, 0, false, 0, false, 140, "ROUND")
      A.ok(x > 0 and math.abs(y) < 0.01, "east is on the right")
      x, y = L.minimapOffset(100, 0, PI / 2, true, 0, false, 140, "ROUND")
      A.ok(x > 0 and math.abs(y) < 0.01, "rotating minimap, facing west: north is on the right")
      x, y = L.minimapOffset(100, 0, PI / 2, false, 0, false, 140, "ROUND")
      A.ok(math.abs(x) < 0.01 and y > 0, "not rotating: facing doesn't matter")
      x, y, edge = L.minimapOffset(5000, 0, 0, false, 0, false, 140, "ROUND")
      A.ok(edge, "far away: on the edge")
      near(A, y, 70 - 6, "on the rim", 0.01)
      x, y, edge = L.minimapOffset(50, 0, 0, false, 5, true, 140, "ROUND")
      A.ok(edge, "indoors at the closest zoom 50 yards is off the minimap")
      x, y, edge = L.minimapOffset(5000, PI / 4 + PI, 0, false, 0, false, 140, "SQUARE")
      A.ok(edge)
      near(A, x, 64, "square corner x", 0.01)
      near(A, y, -64, "square corner y", 0.01)
    end,
  },
}
