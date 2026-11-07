-- Stats board (stats Task 10): two and three copies of TwizCrew counting, sharing and roasting through the fake
-- game (H.client / H.link / H.advance). Same helper style as test_sim.lua (v1), which stays unchanged.

local function login(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function noErrors(A, ...)
  for _, ns in ipairs({ ... }) do A.eq(ns.Log.errors(50), {}, "errors on " .. ns.playerName()) end
end

local function die(W)
  W.state.dead = true
  W:fire("PLAYER_DEAD")
end

local function revive(W)
  W.state.dead = false
  W:fire("PLAYER_ALIVE")
end

local function sessionId(ns)
  local s = ns.Session.current()
  return s and s.id
end

local function reportLine(ns, start)
  for _, line in ipairs(ns.Report.lines()) do
    if line:sub(1, #start) == start then return line end
  end
end

local function entryOf(ns, view, name)
  for _, e in ipairs(ns.StatsStore.entries(view, sessionId(ns))) do
    if e.name == name then return e end
  end
end

-- The award results a client computes, reduced to what both screens must agree on: id -> { winners, value, text }.
local function awardsOf(ns, view)
  local out = {}
  for _, a in ipairs(ns.StatsLogic.awards(ns.StatsStore.entries(view or "session", sessionId(ns)))) do
    if not a.empty then out[a.def.id] = { winners = a.winners, value = a.value, text = a.text } end
  end
  return out
end

local function roastsShown(ns) return ns.Roasts.forTest.shown() end

-- Twiz (warrior 10) and Frostie (mage 12) in Elwynn Forest, linked and logged in, past the session decision.
local function twoFriends(H, wait)
  local tw, twNs = H.client("Twiz")
  local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire" })
  H.link(tw, fr)
  login(tw)
  login(fr)
  H.advance(wait or 25)
  return { tw = tw, twNs = twNs, fr = fr, frNs = frNs }
end

local GREY = "You receive loot: |cff9d9d9d|Hitem:2211::::::::1:::::::|h[Broken Fang]|h|r."

return {
  files = {},
  tests = {
    same_session_on_both = function(_, A, _, H)
      local c = twoFriends(H)
      A.ok(c.twNs.Session.decided() and c.frNs.Session.decided(), "both decided")
      local id = sessionId(c.twNs)
      A.ok(type(id) == "string" and id ~= "", "Twiz is in a session")
      A.eq(sessionId(c.frNs), id, "same session on both")
      A.no(c.twNs.Session.current().manual, "started automatically")
      -- what the owner compares in game: the "Session:" line of /tc report is the same on both sides
      local line = reportLine(c.twNs, "Session: ")
      A.ok(line and line:find(id, 1, true), "Session line names the session")
      A.contains(line, "(automatic)")
      A.eq(reportLine(c.frNs, "Session: "), line)
      A.contains(reportLine(c.twNs, "Stats: "), "Stats: on, steps by speed, detectors off: none")
      noErrors(A, c.twNs, c.frNs)
    end,

    weak_mob_roast_on_both_screens = function(_, A, _, H)
      local c = twoFriends(H)
      local fr = c.fr
      fr.state.level = 20
      fr.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      fr:fire("PLAYER_TARGET_CHANGED")
      H.advance(4)
      die(fr)
      H.advance(3)
      local want = "Frostie"
      local frShown, twShown = roastsShown(c.frNs), roastsShown(c.twNs)
      A.eq(#frShown, 1, "one roast on Frostie's screen")
      A.eq(#twShown, 1, "one roast on Twiz's screen")
      A.eq(twShown[1], frShown[1], "the same line on both screens")
      A.contains(twShown[1], want)
      A.contains(twShown[1], "Kobold Miner")
      A.contains(twShown[1], "level 3")
      A.eq(c.frNs.StatsStore.get("session", "dw"), 1)
      A.eq(c.frNs.StatsStore.get("session", "ld"), 3)
      -- Twiz opens the Hall of Shame: Frostie's numbers arrive, Died to a Weakling goes to Frostie
      c.twNs.Panel.setTab("shame")
      H.advance(6)
      local weak = awardsOf(c.twNs).weakling
      A.ok(weak, "Died to a Weakling has a winner on Twiz's board")
      A.eq(weak.winners, { "Frostie" })
      A.eq(awardsOf(c.twNs).corpse.winners, { "Frostie" })
      local found = false
      for _, r in ipairs(c.twNs.Board.modelForTest().rows) do
        if r.id == "weakling" then
          found = true
          A.eq(r.winners, { "Frostie" })
          A.no(r.empty)
        end
      end
      A.ok(found, "the Hall of Shame was drawn with a Died to a Weakling row")
      revive(fr)
      noErrors(A, c.twNs, c.frNs)
    end,

    session_new_resets_both = function(_, A, _, H)
      local c = twoFriends(H)
      die(c.tw); die(c.fr)
      H.advance(2)
      revive(c.tw); revive(c.fr)
      H.advance(2)
      for _, ns in ipairs({ c.twNs, c.frNs }) do
        A.eq(ns.StatsStore.get("session", "dt"), 1, "counted on " .. ns.playerName())
      end
      tc(c.tw, "session new")
      local s = c.twNs.Session.current()
      A.ok(s.manual, "started by hand")
      A.eq(c.twNs.Session.starter(s), "Twiz")
      H.advance(5)
      A.eq(c.frNs.Session.current(), s, "Frostie moved to Twiz's new session")
      for _, ns in ipairs({ c.twNs, c.frNs }) do
        A.eq(ns.StatsStore.get("session", "dt"), 0, "session deaths reset on " .. ns.playerName())
        A.eq(ns.StatsStore.get("all", "dt"), 1, "all-time deaths kept on " .. ns.playerName())
      end
      -- the boards agree: in the new session nobody has died yet, all time both have one
      A.eq(awardsOf(c.twNs).corpse, nil)
      A.eq(awardsOf(c.frNs).corpse, nil)
      A.eq(reportLine(c.frNs, "Session: "), reportLine(c.twNs, "Session: "))
      A.contains(reportLine(c.twNs, "Session: "), "(by hand)")
      noErrors(A, c.twNs, c.frNs)
    end,

    session_new_while_a_friend_is_still_deciding = function(_, A, _, H)
      local c = twoFriends(H)
      local pw, pwNs = H.client("Pewpew", { class = "MAGE" })
      H.link(pw)
      login(pw)
      H.advance(8)                  -- Pewpew is still listening (decides 20 s after starting)
      A.no(pwNs.Session.decided())
      tc(c.tw, "session new")
      local s = c.twNs.Session.current()
      H.advance(20)
      A.ok(pwNs.Session.decided())
      for _, ns in ipairs({ c.frNs, pwNs }) do
        A.eq(ns.Session.current(), s, ns.playerName() .. " is in Twiz's new session")
      end
      noErrors(A, c.twNs, c.frNs, pwNs)
    end,

    awards_same_on_both = function(_, A, _, H)
      local c = twoFriends(H)
      local tw, fr = c.tw, c.fr
      -- Twiz: one death, three jumps, a repair. Frostie: one death, two grey junk items, a hearthstone, a lost duel.
      die(tw); die(fr)
      H.advance(2)
      revive(tw); revive(fr)
      for _ = 1, 3 do tw.env.JumpOrAscendStart() end
      tw:fire("MERCHANT_SHOW")
      tw.state.repairCost = 12345
      H.advance(1)
      tw.env.RepairAllItems()
      tw:fire("MERCHANT_CLOSED")
      fr:fire("CHAT_MSG_LOOT", GREY)
      fr:fire("CHAT_MSG_LOOT", GREY)
      fr:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 8690)
      fr:fire("CHAT_MSG_SYSTEM", "Twiz has defeated Frostie in a duel")
      H.advance(2)
      -- only Twiz opens the Hall of Shame: the request carries Twiz's own changed numbers, and Frostie answers it,
      -- so both boards agree without waiting for the regular send
      c.twNs.Panel.setTab("shame")
      H.advance(6)
      local tA, fA = awardsOf(c.twNs), awardsOf(c.frNs)
      A.eq(tA, fA, "the same winners and numbers on both screens")
      A.eq(tA.corpse.winners, { "Frostie", "Twiz" }, "a tie shows both")
      A.eq(tA.bunny.winners, { "Twiz" })
      A.eq(tA.broke.winners, { "Twiz" })
      A.eq(tA.trash.winners, { "Frostie" })
      A.eq(tA.homesick.winners, { "Frostie" })
      A.eq(tA.duel.winners, { "Frostie" })
      A.eq(tA.medic, nil, "never a winner with 0")
      A.eq(c.twNs.StatsLogic.titles(c.twNs.StatsLogic.awards(c.twNs.StatsStore.entries("session", sessionId(c.twNs)))),
        c.frNs.StatsLogic.titles(c.frNs.StatsLogic.awards(c.frNs.StatsStore.entries("session", sessionId(c.frNs)))),
        "the same titles under the names")
      -- all time too
      A.eq(awardsOf(c.twNs, "all"), awardsOf(c.frNs, "all"))
      noErrors(A, c.twNs, c.frNs)
    end,

    numbers_agree_after_the_regular_send = function(_, A, _, H)
      local c = twoFriends(H)
      for _ = 1, 4 do c.tw.env.JumpOrAscendStart() end
      c.fr.env.AbandonQuest()
      H.advance(2)
      A.eq((entryOf(c.frNs, "session", "Twiz").stats.jp or 0), 0, "not shared at once (no message per event)")
      H.advance(c.twNs.Config.STATS_SEND_INTERVAL)
      A.eq(entryOf(c.frNs, "session", "Twiz").stats.jp, 4, "shared by the regular send")
      A.eq(entryOf(c.twNs, "session", "Frostie").stats.qa, 1)
      A.eq(awardsOf(c.twNs), awardsOf(c.frNs))
      noErrors(A, c.twNs, c.frNs)
    end,

    three_friends_one_session_same_awards = function(_, A, _, H)
      local c = twoFriends(H)
      local pw, pwNs = H.client("Pewpew", { class = "MAGE" })
      H.link(pw)
      login(pw)
      H.advance(25)
      local id = sessionId(c.twNs)
      A.eq(sessionId(pwNs), id, "a late friend joins the crew's session")
      A.eq(sessionId(c.frNs), id)
      die(pw); H.advance(2); revive(pw)
      pw:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 2006) -- Resurrection rank 1 (by spell id)
      for _ = 1, 2 do c.fr.env.JumpOrAscendStart() end
      H.advance(2)
      for _, ns in ipairs({ c.twNs, c.frNs, pwNs }) do ns.Panel.setTab("shame") end
      H.advance(6)
      local tA = awardsOf(c.twNs)
      A.eq(awardsOf(c.frNs), tA)
      A.eq(awardsOf(pwNs), tA)
      A.eq(tA.medic.winners, { "Pewpew" })
      A.eq(tA.corpse.winners, { "Pewpew" })
      A.eq(tA.bunny.winners, { "Frostie" })
      noErrors(A, c.twNs, c.frNs, pwNs)
    end,

    stats_off_hides_me_for_friends = function(_, A, _, H)
      local c = twoFriends(H)
      die(c.fr); H.advance(2); revive(c.fr)
      c.twNs.Panel.setTab("shame")
      H.advance(6)
      A.ok(entryOf(c.twNs, "session", "Frostie"), "Frostie is on Twiz's board")
      A.eq(awardsOf(c.twNs).corpse.winners, { "Frostie" })
      c.frNs.Modules.setEnabled("stats", false)
      A.eq(c.frNs.Modules.isEnabled("stats"), false, "Frostie's stats module is off")
      H.advance(3)
      A.eq(entryOf(c.twNs, "session", "Frostie"), nil, "session: hidden")
      A.eq(entryOf(c.twNs, "all", "Frostie"), nil, "all time: hidden")
      A.eq(awardsOf(c.twNs).corpse, nil, "no award for a hidden friend")
      -- no counting and no roasts about Frostie while off
      c.fr.state.level = 20
      c.fr.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      c.fr:fire("PLAYER_TARGET_CHANGED")
      H.advance(11) -- past the roast gap
      die(c.fr)
      H.advance(3)
      A.eq(#c.twNs.Roasts.forTest.shown(), 0, "no roast about Frostie")
      A.eq(c.frNs.StatsStore.get("all", "dt"), 1, "not counted while off")
      revive(c.fr)
      -- Twiz asking again gets the off answer, still hidden
      H.advance(61)
      c.twNs.Panel.setTab("crew")
      c.twNs.Panel.setTab("shame")
      H.advance(6)
      A.eq(entryOf(c.twNs, "session", "Frostie"), nil, "still hidden after asking again")
      -- back on: Frostie shows again with the numbers kept
      c.frNs.Modules.setEnabled("stats", true)
      H.advance(3)
      local e = entryOf(c.twNs, "session", "Frostie")
      A.ok(e, "back on Twiz's board")
      A.eq(e.stats.dt, 1)
      noErrors(A, c.twNs, c.frNs)
    end,

    no_errors_with_stats = function(_, A, _, H)
      local c = twoFriends(H, 1)
      local tw, fr = c.tw, c.fr
      -- v1's sequence: other layer, zone change, death, odd status, report
      local function seeNpc(W, guid)
        W.state.guids.mouseover = guid
        W:fire("UPDATE_MOUSEOVER_UNIT")
        W:fire("UPDATE_MOUSEOVER_UNIT")
      end
      seeNpc(tw, "Creature-0-1-0-111-299-0000ABCDEF")
      seeNpc(fr, "Creature-0-1-0-222-299-0000ABCDEF")
      tw.state.pos = { x = 0, y = 0, instance = 1 }  -- Frostie next to Twiz on the map, hidden by the game
      tw.state.units.party1 = { name = "Frostie", player = true, visible = false, pos = { x = 10, y = 0, instance = 1 } }
      H.advance(35)
      A.eq(c.twNs.Layer.relationOf("Frostie"), "different")
      fr.state.zone, fr.state.subzone = "Westfall", "Sentinel Hill"
      fr:fire("ZONE_CHANGED_NEW_AREA")
      H.advance(2)
      fr.state.zone, fr.state.subzone = "Elwynn Forest", "Northshire"
      fr:fire("ZONE_CHANGED_NEW_AREA")
      H.advance(2)
      tc(fr, "status 50% ^_^ |Tx|t")
      -- moving around, falling to death (a fall roast), jumps, junk, a duel
      tw.state.speed = 7
      H.advance(10)
      tw.state.speed = 0
      fr.state.falling = true
      H.advance(1.5)
      fr.state.falling = false
      die(fr)
      H.advance(3)
      A.eq(#c.twNs.Roasts.forTest.shown(), 1, "the fall roast reached Twiz")
      A.eq(c.twNs.Roasts.forTest.shown()[1], c.frNs.Roasts.forTest.shown()[1])
      revive(fr)
      tw.env.JumpOrAscendStart()
      fr:fire("CHAT_MSG_LOOT", GREY)
      tw:fire("CHAT_MSG_SYSTEM", "Frostie has defeated Twiz in a duel")
      tc(tw, "report")
      tc(fr, "report")
      tc(tw, "stats reset")      -- only asks
      A.ok(c.twNs.StatsStore.get("all", "dl") == 1, "stats reset asks first")
      -- the awards show, walked to the end
      tc(tw, "awards")
      A.ok(c.twNs.AwardsShow.isOpen())
      H.advance(6)
      local steps = 0
      while c.twNs.AwardsShow.isOpen() and steps < 100 do
        H.advance(2.2)
        c.twNs.AwardsShow.next()
        steps = steps + 1
      end
      A.no(c.twNs.AwardsShow.isOpen(), "the show reached the end and closed")
      tc(fr, "awards all")
      H.advance(6)
      tc(fr, "session new")
      H.advance(320)            -- the regular sends, pings, ticks
      A.eq(sessionId(c.twNs), sessionId(c.frNs))
      local tAll, fAll = awardsOf(c.twNs, "all"), awardsOf(c.frNs, "all")
      for id, a in pairs(tAll) do
        A.ok(fAll[id], id .. " on both")
        A.eq(fAll[id].winners, a.winners, id .. " winners") -- (steps are fractional locally, whole on the wire)
      end
      noErrors(A, c.twNs, c.frNs)
    end,
  },
}
