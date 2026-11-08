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

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

-- Our messages of one type: { chatType, target, fields } in order.
local function sentOf(ns, W, msgType)
  local out = {}
  for _, m in ipairs(W.sent) do
    local msg = ns.Codec.decode(m.text)
    if msg and msg.type == msgType then
      out[#out + 1] = { chatType = m.chatType, target = m.target, fields = msg.fields }
    end
  end
  return out
end

-- Frostie joins our party (party1).
local function group(W, names)
  W.state.inGroup = true
  W.state.groupMembers = names or { "Frostie" }
  for i, n in ipairs(W.state.groupMembers) do
    W.state.units["party" .. i] = { name = n, player = true }
  end
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

-- Frostie's STATE (class, zone) so the roster knows them.
local function frostie(ns, W, zone)
  hear(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = zone or "Elwynn Forest", sz = "Goldshire",
    ver = "0.1.0" })
end

local function shown(ns, text)
  for _, t in ipairs(ns.Popups.shownForTest()) do if t:find(text, 1, true) then return true end end
  return false
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

    ---------------------------------------------------------------------------------------------- sending
    no_position_goes_out_when_not_in_a_group = function(ns, A, W)
      boot(W)
      W:advance(40)
      A.eq(#sentOf(ns, W, "POS"), 0)
      A.eq(ns.Log.errors(10), {})
    end,

    position_goes_to_the_group_when_moving_and_now_and_then = function(ns, A, W)
      boot(W)
      group(W)
      W:advance(2)
      local pos = sentOf(ns, W, "POS")
      A.eq(#pos, 1, "right after joining a group")
      A.eq(pos[1].chatType, "PARTY")
      A.eq(pos[1].fields, { c = "0", x = "-9000", y = "-1000" })
      for _, m in ipairs(W.sent) do A.ok(m.chatType ~= "WHISPER" or not m.text:find("POS", 1, true), "never whispered") end
      W:advance(10)
      A.eq(#sentOf(ns, W, "POS"), 1, "standing still: nothing")
      W.state.map.x = 0.51 -- 20 yards east
      W:advance(2)
      pos = sentOf(ns, W, "POS")
      A.eq(#pos, 2, "moved")
      A.eq(pos[2].fields.y, "-1020")
      W.state.map.x = 0.5101 -- 0.2 yards: not worth a message
      W:advance(30)
      pos = sentOf(ns, W, "POS")
      A.eq(#pos, 3, "a keep-alive after 30 s")
      W:advance(10)
      A.eq(#sentOf(ns, W, "POS"), 3)
      A.eq(ns.Log.errors(10), {})
    end,

    instance_sends_unknown_once_then_nothing = function(ns, A, W)
      boot(W)
      group(W)
      W:advance(2)
      W.state.inInstance = true
      W:advance(40)
      local pos = sentOf(ns, W, "POS")
      A.eq(#pos, 2)
      A.eq(pos[2].fields, { u = "1" })
      W.state.inInstance = false
      W:advance(2)
      A.eq(#sentOf(ns, W, "POS"), 3, "back outside: a position again")
    end,

    leaving_the_group_stops_positions = function(ns, A, W)
      boot(W)
      group(W)
      W:advance(2)
      ungroup(W)
      W.state.map.x = 0.6
      W:advance(60)
      A.eq(#sentOf(ns, W, "POS"), 1)
      A.eq(ns.Log.errors(10), {})
    end,

    not_sharing_my_position_sends_unknown_then_nothing = function(ns, A, W)
      boot(W)
      group(W)
      W:advance(2)
      ns.Modules.set("find", "sharePosition", false)
      W:advance(2)
      local pos = sentOf(ns, W, "POS")
      A.eq(#pos, 2)
      A.eq(pos[2].fields, { u = "1", off = "1" })
      W.state.map.x = 0.6
      W:advance(60)
      A.eq(#sentOf(ns, W, "POS"), 2)
    end,

    ---------------------------------------------------------------------------------------------- arrows
    a_group_members_position_gives_an_arrow = function(ns, A, W)
      boot(W)
      group(W)
      frostie(ns, W)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8900", y = "-1000" }) -- 100 yards north
      local a = ns.Find.arrowFor("Frostie")
      A.ok(a, "an arrow")
      A.eq(a.text, "100 yd")
      near(A, a.angle, 0, "straight ahead (facing north)")
      W.state.facing = math.pi / 2 -- facing west
      near(A, ns.Find.arrowFor("Frostie").angle, -math.pi / 2, "north is on the right now")
      W:advance(61)
      A.eq(ns.Find.arrowFor("Frostie"), nil, "a minute without news: unknown")
      hear(ns, W, "Frostie", "POS", { u = "1" })
      A.eq(ns.Find.arrowFor("Frostie"), nil, "unknown position")
      A.eq(ns.Log.errors(10), {})
    end,

    positions_from_outside_the_group_are_ignored = function(ns, A, W)
      boot(W)
      hear(ns, W, "Chaos", "STATE", { cl = "ROGUE", lv = "10", zn = "Elwynn Forest", ver = "0.1.0" }, "WHISPER")
      hear(ns, W, "Chaos", "POS", { c = "0", x = "-8900", y = "-1000" }, "WHISPER")
      A.eq(ns.Find.forTest.positions().Chaos, nil)
      A.eq(ns.Find.arrowFor("Chaos"), nil)
    end,

    another_zone_gives_a_still_arrow_and_another_continent_none = function(ns, A, W)
      boot(W)
      group(W)
      frostie(ns, W, "Westfall")
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-11000", y = "-1000" })
      local a = ns.Find.arrowFor("Frostie")
      A.ok(a and a.still, "still arrow")
      A.eq(a.zone, "Westfall")
      hear(ns, W, "Frostie", "POS", { c = "1", x = "10000", y = "1000" })
      A.eq(ns.Find.arrowFor("Frostie"), nil, "Kalimdor")
    end,

    live_party_positions_win_when_the_game_gives_them = function(ns, A, W)
      boot(W)
      group(W)
      frostie(ns, W)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8900", y = "-1000" })
      W.state.units.party1.pos = { y = -8800, x = -1000, instance = 0 } -- UnitPosition: north first
      A.eq(ns.Find.arrowFor("Frostie").text, "200 yd")
      W.state.secret[-8800] = true
      A.eq(ns.Find.arrowFor("Frostie").text, "100 yd", "secret: their last message")
      A.eq(ns.Log.errors(10), {})
    end,

    row_arrows_switch_off = function(ns, A, W)
      boot(W)
      group(W)
      frostie(ns, W)
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8900", y = "-1000" })
      ns.Modules.set("find", "rowArrows", false)
      A.eq(ns.Find.arrowFor("Frostie"), nil)
      ns.Modules.set("find", "rowArrows", true)
      ns.Modules.setEnabled("find", false)
      A.eq(ns.Find.arrowFor("Frostie"), nil, "module off")
    end,

    ---------------------------------------------------------------------------------------------- meet-ups
    a_party_meetup_goes_to_the_group = function(ns, A, W)
      boot(W)
      local ok, why = ns.Find.placeMeet(1429, 0.25, 0.25, "party")
      A.no(ok)
      A.eq(why, "nogroup")
      A.eq(select(2, ns.Find.placeMeet(947, 0.5, 0.5, "all")), "noplace", "the whole-world map")
      group(W)
      A.ok(ns.Find.placeMeet(1429, 0.25, 0.25, "party"))
      W:advance(1)
      local meet = sentOf(ns, W, "MEET")
      A.eq(#meet, 1)
      A.eq(meet[1].chatType, "PARTY")
      A.eq(meet[1].fields.a, "party")
      A.eq(meet[1].fields.p, "Elwynn Forest")
      A.eq(meet[1].fields.x, "-8500")
      A.eq(meet[1].fields.y, "-500")
      A.eq(meet[1].fields.l, "900")
      A.eq(ns.Find.meet().by, "Twiz")
    end,

    an_everyone_meetup_goes_to_the_whole_crew = function(ns, A, W)
      boot(W)
      A.ok(ns.Find.placeMeet(1429, 0.25, 0.25, "all"))
      W:advance(1)
      local meet = sentOf(ns, W, "MEET")
      A.ok(#meet >= 1)
      for _, m in ipairs(meet) do A.ok(m.chatType ~= "PARTY", "not the party only") end
      A.eq(meet[1].fields.a, "all")
    end,

    a_friends_meetup_pops_up_once = function(ns, A, W)
      boot(W)
      group(W)
      frostie(ns, W)
      local fields = { id = "Frostie-1", c = "0", x = "-8500", y = "-500", p = "Elwynn Forest", a = "party", l = "900" }
      hear(ns, W, "Frostie", "MEET", fields)
      W:advance(1)
      A.ok(shown(ns, "Frostie wants to meet up"), "pop-up, even in the login quiet time")
      A.eq(ns.Find.meet().by, "Frostie")
      hear(ns, W, "Frostie", "MEET", fields)
      W:advance(1)
      local n = 0
      for _, t in ipairs(ns.Popups.shownForTest()) do if t:find("wants to meet up", 1, true) then n = n + 1 end end
      A.eq(n, 1, "the same meet-up again: no second pop-up")
      A.eq(ns.Log.errors(10), {})
    end,

    a_party_meetup_from_outside_the_group_is_ignored = function(ns, A, W)
      boot(W)
      hear(ns, W, "Chaos", "MEET", { id = "Chaos-1", c = "0", x = "-8500", y = "-500", p = "Elwynn Forest",
        a = "party", l = "900" }, "WHISPER")
      A.eq(ns.Find.meet(), nil)
      hear(ns, W, "Chaos", "MEET", { id = "Chaos-2", c = "0", x = "-8500", y = "-500", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      A.eq(ns.Find.meet().id, "Chaos-2", "an everyone meet-up is fine")
    end,

    newest_meetup_wins_and_an_old_clear_does_nothing = function(ns, A, W)
      boot(W)
      local base = { c = "0", x = "-8500", y = "-500", p = "Elwynn Forest", a = "all", l = "900" }
      local one, two = {}, {}
      for k, v in pairs(base) do one[k], two[k] = v, v end
      one.id, two.id = "Frostie-1", "Ginkan-1"
      hear(ns, W, "Frostie", "MEET", one, "WHISPER")
      hear(ns, W, "Ginkan", "MEET", two, "WHISPER")
      A.eq(ns.Find.meet().id, "Ginkan-1")
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", clr = "1", a = "all" }, "WHISPER")
      A.eq(ns.Find.meet().id, "Ginkan-1", "clearing the old one leaves the new one")
      hear(ns, W, "Frostie", "MEET", { id = "Ginkan-1", clr = "1", a = "all" }, "WHISPER")
      A.eq(ns.Find.meet(), nil, "anyone it went to can clear it")
    end,

    a_meetup_ends_after_15_minutes = function(ns, A, W)
      boot(W)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-1", c = "0", x = "-8500", y = "-500", p = "Elwynn Forest",
        a = "all", l = "900" }, "WHISPER")
      W:advance(899)
      A.ok(ns.Find.meet())
      W:advance(2)
      A.eq(ns.Find.meet(), nil)
      hear(ns, W, "Frostie", "MEET", { id = "Frostie-2", c = "0", x = "-8500", y = "-500", p = "x", a = "all",
        l = "99999" }, "WHISPER")
      W:advance(901)
      A.eq(ns.Find.meet(), nil, "never longer than 15 minutes")
    end,

    meet_clear_command = function(ns, A, W)
      boot(W)
      tc(W, "meet clear")
      A.eq(W.printed[#W.printed], "TwizCrew: there is no meet-up to clear.")
      ns.Find.placeMeet(1429, 0.25, 0.25, "all")
      W:advance(1)
      tc(W, "meet clear")
      A.eq(W.printed[#W.printed], "TwizCrew: meet-up cleared.")
      W:advance(1)
      local meet = sentOf(ns, W, "MEET")
      A.eq(meet[#meet].fields.clr, "1")
      A.eq(ns.Find.meet(), nil)
      tc(W, "meet")
      A.contains(W.printed[#W.printed], "Ctrl + right-click")
    end,

    everyone_meetup_reaches_a_friend_who_logs_in_later = function(ns, A, W)
      boot(W)
      ns.Find.placeMeet(1429, 0.25, 0.25, "all")
      W:advance(2)
      local before = #sentOf(ns, W, "MEET")
      hear(ns, W, "Frostie", "HELLO", { ver = "0.1.0" }, "WHISPER")
      W:advance(6)
      local meet = sentOf(ns, W, "MEET")
      A.ok(#meet > before, "sent again")
      A.contains(meet[#meet].target, "Frostie", "whispered to Frostie")
    end,

    party_meetup_reaches_who_joins_the_party = function(ns, A, W)
      boot(W)
      group(W)
      ns.Find.placeMeet(1429, 0.25, 0.25, "party")
      W:advance(1)
      group(W, { "Frostie", "Ginkan" })
      W:advance(1)
      local meet = sentOf(ns, W, "MEET")
      A.eq(#meet, 2)
      A.eq(meet[2].chatType, "PARTY")
    end,

    report_line = function(ns, A, W)
      boot(W)
      local line
      for _, l in ipairs(ns.Report.lines()) do if l:find("^Find the crew") then line = l end end
      A.eq(line, "Find the crew: position ok (map 1429), facing ok, group members with positions: 0, meet-up: none")
      ns.Find.placeMeet(1429, 0.25, 0.25, "all")
      for _, l in ipairs(ns.Report.lines()) do if l:find("^Find the crew") then line = l end end
      A.contains(line, "meet-up: Twiz (everyone) in Elwynn Forest, 15 min left")
    end,

    ---------------------------------------------------------------------------------------------- review fixes
    -- The game may answer GetMapPosFromWorldPos for a map on another continent: we never ask it to.
    where_never_places_a_spot_on_another_continents_map = function(ns, A, W)
      local real = W.env.C_Map
      W.env.C_Map = setmetatable({
        GetMapPosFromWorldPos = function(_, _, mapID)
          return mapID, { x = 0.5, y = 0.5, GetXY = function(self) return self.x, self.y end }
        end,
      }, { __index = function(_, k) return real[k] end })
      A.eq(ns.Where.toMap(1438, 0, -9000, -1000), nil, "Teldrassil's map never shows an Elwynn spot")
      local mx = ns.Where.toMap(1429, 0, -9000, -1000)
      near(A, mx, 0.5, "Elwynn's map does")
    end,

    -- A meet-up clicked on the continent map (or a cave's map) is named after its zone, as GetRealZoneText says it.
    a_meetup_is_named_after_its_zone = function(ns, A, W)
      A.eq(ns.Where.placeName(1415, 0.5, 0.5), "Elwynn Forest", "continent map: the zone under the point")
      A.eq(ns.Where.placeName(1415, 0.01, 0.01), "Eastern Kingdoms", "over no zone: the map's own name")
      A.eq(ns.Where.placeName(1430, 0.5, 0.5), "Elwynn Forest", "a mine's map: the zone around it")
      A.eq(ns.Where.placeName(1436, 0.5, 0.5), "Westfall")
      boot(W)
      ns.Find.placeMeet(1415, 0.5, 0.5, "all")
      A.eq(ns.Find.meet().place, "Elwynn Forest")
    end,

    -- A secret answer is never tested for true / false: secret "in a group" counts as not in a group.
    secret_group_answers_count_as_unknown = function(ns, A, W)
      local secret = {}
      W.state.secret[secret] = true
      W.state.inGroup = secret
      A.no(ns.Where.inGroup(), "secret: not known to be in a group")
      W.state.inGroup = true
      W.state.units.party1 = { name = secret, player = true }
      A.eq(ns.Where.unitFor("Frostie"), nil)
      boot(W)
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(2)
      A.eq(ns.Log.errors(10), {})
    end,

    -- An old meet-up sent again (its sender resends it to newcomers) never replaces the newest one, and a cleared one
    -- never comes back.
    an_old_meetup_sent_again_stays_gone = function(ns, A, W)
      boot(W)
      local function meetFrom(name, id)
        hear(ns, W, name, "MEET", { id = id, c = "0", x = "-8500", y = "-500", p = "Elwynn Forest", a = "all",
          l = "900" }, "WHISPER")
      end
      meetFrom("Frostie", "Frostie-1")
      meetFrom("Ginkan", "Ginkan-1")
      W:advance(10)
      meetFrom("Frostie", "Frostie-1")
      A.eq(ns.Find.meet().id, "Ginkan-1", "the newest stays")
      hear(ns, W, "Ginkan", "MEET", { id = "Ginkan-1", clr = "1", a = "all" }, "WHISPER")
      A.eq(ns.Find.meet(), nil)
      W:advance(10)
      meetFrom("Ginkan", "Ginkan-1")
      A.eq(ns.Find.meet(), nil, "cleared stays cleared")
      meetFrom("Ginkan", "Ginkan-2")
      A.eq(ns.Find.meet().id, "Ginkan-2", "a new one is fine")
    end,

    -- "Share my position" off hides us from friends' arrows even where the game gives them our party position.
    not_sharing_hides_the_games_own_party_position_too = function(ns, A, W)
      boot(W)
      group(W)
      frostie(ns, W)
      W.state.units.party1.pos = { y = -8900, x = -1000, instance = 0 } -- the game: 100 yards north
      A.eq(ns.Find.arrowFor("Frostie").text, "100 yd", "live party position")
      hear(ns, W, "Frostie", "POS", { u = "1", off = "1" })
      A.eq(ns.Find.arrowFor("Frostie"), nil, "Frostie doesn't share")
      hear(ns, W, "Frostie", "POS", { u = "1" })
      A.eq(ns.Find.arrowFor("Frostie").text, "100 yd", "plain unknown (an instance, an older copy): live is fine")
      hear(ns, W, "Frostie", "POS", { u = "1", off = "1" })
      hear(ns, W, "Frostie", "POS", { c = "0", x = "-8800", y = "-1000" })
      A.ok(ns.Find.arrowFor("Frostie"), "sharing again")
    end,

    not_sharing_is_told_to_whoever_joins = function(ns, A, W)
      boot(W)
      ns.Modules.set("find", "sharePosition", false)
      W:advance(2)
      A.eq(#sentOf(ns, W, "POS"), 0, "alone: nothing")
      group(W)
      W:advance(2)
      local pos = sentOf(ns, W, "POS")
      A.eq(#pos, 1)
      A.eq(pos[1].fields, { u = "1", off = "1" })
      W:advance(60)
      A.eq(#sentOf(ns, W, "POS"), 1, "once")
      group(W, { "Frostie", "Ginkan" })
      W:advance(2)
      pos = sentOf(ns, W, "POS")
      A.eq(#pos, 2, "again for the newcomer")
      A.eq(pos[2].fields, { u = "1", off = "1" })
      ns.Modules.set("find", "sharePosition", true)
      W:advance(2)
      pos = sentOf(ns, W, "POS")
      A.eq(pos[#pos].fields, { c = "0", x = "-9000", y = "-1000" }, "sharing again: a position right away")
    end,
  },
}
