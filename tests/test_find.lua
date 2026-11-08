-- Find the crew: safe position reads (ns.Where), the "find" module (positions in and out, meet-ups, /tc meet,
-- report line). Fake world: Elwynn Forest (map 1429) spans world x -8000..-10000 (north..south) and
-- y 0..-2000 (west..east); the player starts at its middle, world (-9000, -1000).

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function near(A, actual, expected, msg)
  A.ok(type(actual) == "number" and math.abs(actual - expected) < 0.01,
    (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

return {
  files = "toc",
  tests = {
    where_reads_my_position_through_the_map = function(ns, A, W)
      local me = ns.Where.me()
      A.ok(me, "a position")
      A.eq(me.c, 0)
      near(A, me.x, -9000, "north")
      near(A, me.y, -1000, "west")
      A.eq(me.map, 1429)
      A.eq(me.zone, "Elwynn Forest")
      near(A, ns.Where.facing(), 0)
    end,

    where_knows_nothing_in_an_instance_or_with_secrets = function(ns, A, W)
      W.state.inInstance = true
      A.eq(ns.Where.me(), nil, "instance")
      W.state.inInstance = false
      W.state.missing["C_Map.GetPlayerMapPosition"] = true
      A.eq(ns.Where.me(), nil, "no map position and no UnitPosition fake position")
      W.state.pos = { y = -9000, x = -1000, instance = 0 } -- UnitPosition: north first (the stub calls it y)
      local me = ns.Where.me()
      A.ok(me, "UnitPosition is the fallback")
      near(A, me.x, -9000)
      near(A, me.y, -1000)
      W.state.secret[-9000] = true
      A.eq(ns.Where.me(), nil, "a secret number is unknown")
      W.state.facing = 1.5
      W.state.secret[1.5] = true
      A.eq(ns.Where.facing(), nil, "secret facing")
      W.state.missing.GetPlayerFacing = true
      A.eq(ns.Where.facing(), nil, "no facing function")
      A.eq(ns.Log.errors(10), {})
    end,

    where_turns_map_points_into_world_points_and_back = function(ns, A, W)
      local c, x, y = ns.Where.toWorld(1429, 0.25, 0.75)
      A.eq(c, 0)
      near(A, x, -9500)
      near(A, y, -500)
      local mx, my = ns.Where.toMap(1429, c, x, y)
      near(A, mx, 0.25)
      near(A, my, 0.75)
      A.eq(ns.Where.toWorld(947, 0.5, 0.5), nil, "the whole world has no world coordinates")
      A.eq(ns.Where.toMap(1438, c, x, y), nil, "Teldrassil is on the other continent")
      A.eq(ns.Where.mapName(1436), "Westfall")
    end,

    where_finds_party_units_by_name = function(ns, A, W)
      W.state.inGroup = true
      W.state.groupMembers = { "Frostie" }
      W.state.units.party1 = { name = "Frostie-Realm", player = true, pos = { y = -8990, x = -1000, instance = 0 } }
      A.eq(ns.Where.unitFor("Frostie"), "party1")
      A.eq(ns.Where.unitFor("Nobody"), nil)
      local p = ns.Where.unit("party1")
      near(A, p.x, -8990)
      near(A, p.y, -1000)
      A.ok(ns.Where.isGroupMember("Frostie"))
      A.no(ns.Where.isGroupMember("Chaos"))
    end,
  },
}
