-- Find the crew with three copies talking: Twiz and Frostie in one party, Ginkan outside it. Positions only reach
-- the group; a party meet-up only the party; an "everyone" meet-up the whole crew.

local function login(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function party(W, names)
  W.state.inGroup = true
  W.state.groupMembers = names
  for i, n in ipairs(names) do W.state.units["party" .. i] = { name = n, player = true } end
  W:fire("GROUP_ROSTER_UPDATE")
end

local function shown(ns, text)
  for _, t in ipairs(ns.Popups.shownForTest()) do if t:find(text, 1, true) then return true end end
  return false
end

local function three(H)
  local tw, twNs = H.client("Twiz")
  local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12 })
  local gi, giNs = H.client("Ginkan", { class = "ROGUE", level = 11 })
  H.link(tw, fr, gi)
  login(tw); login(fr); login(gi)
  H.advance(12)
  party(tw, { "Frostie" })
  party(fr, { "Twiz" })
  return { tw = tw, twNs = twNs, fr = fr, frNs = frNs, gi = gi, giNs = giNs }
end

return {
  tests = {
    a_party_member_walking_away_gets_an_arrow_and_outsiders_get_nothing = function(ns, A, W, H)
      local c = three(H)
      c.fr.state.map = { id = 1429, x = 0.5, y = 0.45 } -- 100 yards north of Twiz
      H.advance(5)
      local a = c.twNs.Find.arrowFor("Frostie")
      A.ok(a, "Twiz has an arrow to Frostie")
      A.eq(a.text, "100 yd")
      A.eq(c.giNs.Find.forTest.positions().Frostie, nil, "Ginkan is not in the party: no position kept")
      A.eq(c.giNs.Find.arrowFor("Frostie"), nil)
      c.fr.state.map.y = 0.4 -- walks on: 200 yards
      H.advance(5)
      A.eq(c.twNs.Find.arrowFor("Frostie").text, "200 yd")
      for _, ns2 in ipairs({ c.twNs, c.frNs, c.giNs }) do A.eq(ns2.Log.errors(20), {}) end
    end,

    meetups_reach_the_party_or_everyone = function(ns, A, W, H)
      local c = three(H)
      A.ok(c.twNs.Find.placeMeet(1429, 0.3, 0.3, "party"))
      H.advance(2)
      A.ok(c.frNs.Find.meet(), "Frostie got the party meet-up")
      A.ok(shown(c.frNs, "Twiz wants to meet up"))
      A.eq(c.giNs.Find.meet(), nil, "Ginkan did not")
      A.ok(c.twNs.Find.placeMeet(1429, 0.6, 0.6, "all"))
      H.advance(2)
      A.ok(c.giNs.Find.meet(), "an everyone meet-up reaches Ginkan")
      A.eq(c.giNs.Find.meet().id, c.frNs.Find.meet().id, "the newest one everywhere")
      c.giNs.Find.clearMeet()
      H.advance(2)
      A.eq(c.twNs.Find.meet(), nil, "Ginkan cleared it for everyone")
      A.eq(c.frNs.Find.meet(), nil)
      for _, ns2 in ipairs({ c.twNs, c.frNs, c.giNs }) do A.eq(ns2.Log.errors(20), {}) end
    end,
  },
}
