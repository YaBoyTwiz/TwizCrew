return {
  files = { "Core/Init.lua", "Core/Util.lua", "Stats/StatsDefs.lua", "Stats/StatsLogic.lua" },
  tests = {
    defs_shape = function(ns, A)
      local D = ns.StatsDefs
      A.eq(table.concat(D.KEYS, " "), "dt df dd dw db ld pl wp af ds st mt sw jp hs jk rp qa dl dv rz pt")
      A.eq(D.MIN_KEYS, { ld = true })
      A.eq(D.TIME_KEYS, { pt = true })
      A.eq(table.concat(D.ROAST_KINDS, " "), "weak fall drown again deaths wipe steps jumps quit")
      A.eq(D.SPELLS.hearth.ids, { 8690 })
      A.eq(#D.SPELLS.rez.ids, 20)
      A.eq(D.SPELLS.rez.names[4], "Rebirth")
    end,
    motion_rules = function(ns, A)
      local L = ns.StatsLogic
      A.eq(L.motionBucket({}), "foot")
      A.eq(L.motionBucket({ mounted = true }), "mount")
      A.eq(L.motionBucket({ swimming = true }), "swim")
      A.eq(L.motionBucket({ taxi = true, mounted = true }), nil)
      A.eq(L.motionBucket({ dead = true }), nil)
      A.eq(L.speedYards(7, 0.5), 3.5)
      A.eq(L.speedYards(7, 0.5, true), nil)
      A.eq(L.speedYards(nil, 0.5), nil)
      A.eq(L.speedYards(0 / 0, 0.5), nil)
      A.eq(L.speedYards(-1, 0.5), nil)
      A.eq(L.speedYards(500, 0.5), nil)
      A.eq(L.positionYards({ x = 0, y = 0, instance = 0, t = 1 }, { x = 3, y = 4, instance = 0, t = 1.5 }), 5)
      A.eq(L.positionYards({ x = 0, y = 0, instance = 0, t = 1 }, { x = 3, y = 4, instance = 1, t = 1.5 }), nil)
      A.eq(L.positionYards({ x = 0, y = 0, instance = 0, t = 1 }, { x = 300, y = 0, instance = 0, t = 1.5 }), nil)
      A.eq(L.positionYards({ x = 0, y = 0, instance = 0, t = 1 }, { x = 3, y = 4, instance = 0, t = 1 }), nil)
      A.eq(L.positionYards(nil, { x = 3, y = 4, instance = 0, t = 1 }), nil)
      A.eq(L.positionYards({ x = 0, y = 0, instance = 0, t = 1 }, nil), nil)
    end,
    classify_death_cases = function(ns, A)
      local L = ns.StatsLogic
      local function with(extra)
        local i = { now = 100, myLevel = 20 }
        for k, v in pairs(extra) do i[k] = v end
        return L.classifyDeath(i)
      end
      A.ok(with({ fallingAt = 98.5 }).fall)
      A.no(with({ fallingAt = 97 }).fall)
      A.ok(with({ breathRunning = true }).drown)
      A.ok(with({ breathStoppedAt = 99.5 }).drown)
      A.no(with({ breathStoppedAt = 98 }).drown)
      local r = with({ target = { level = 14, name = "Kobold Miner", at = 95 } })
      A.ok(r.weak); A.eq(r.mobLevel, 14); A.eq(r.mobName, "Kobold Miner")
      A.no(with({ target = { level = 16, name = "x", at = 95 } }).weak)
      A.no(with({ target = { level = 14, name = "x", at = 85 } }).weak)
      A.no(with({ target = { level = -1, name = "x", at = 95 } }).weak)
      A.no(with({ target = { level = "14", name = "x", at = 95 } }).weak)
      A.no(with({}).weak)
      r = with({ aliveAt = 60 })
      A.ok(r.again); A.eq(r.againSeconds, 40)
      A.no(with({ aliveAt = 30 }).again)
    end,
    milestone_crossings = function(ns, A)
      local m = ns.StatsLogic.milestone
      A.eq(m("deaths", 4, 5), 5); A.eq(m("deaths", 5, 6), nil); A.eq(m("deaths", 9, 21), 20)
      A.eq(m("steps", 9990, 10002), 10000); A.eq(m("steps", 99000, 100500), 100000)
      A.eq(m("steps", 199999, 200001), 200000); A.eq(m("steps", 150000, 160000), nil)
      A.eq(m("jumps", 999, 1000), 1000); A.eq(m("jumps", 4999, 5000), 5000)
      A.eq(m("jumps", 5000, 9999), nil); A.eq(m("jumps", 9999, 10000), 10000)
      A.eq(m("quit", 2, 3), 3); A.eq(m("quit", 3, 4), nil)
      A.eq(m("bogus", 0, 5), nil)
    end,
    limiter_gap = function(ns, A)
      local l = ns.StatsLogic.newLimiter(10)
      A.eq(l:allow("A", 0), true); A.eq(l:allow("A", 5), false); A.eq(l:allow("B", 5), true)
      A.eq(l:allow("A", 10), true); A.eq(l:allow("A", 15), false)
    end,
    duel_text = function(ns, A)
      local d = ns.StatsLogic.duelResult
      local K, R = "%1$s has defeated %2$s in a duel", "%2$s has fled from %1$s in a duel"
      A.eq(d("Ginkan has defeated Twiz in a duel", "Twiz", K, R), "lost")
      A.eq(d("Twiz has defeated Ginkan in a duel", "Twiz", K, R), "won")
      A.eq(d("Twiz has fled from Ginkan in a duel", "Twiz", K, R), "lost")
      A.eq(d("Ginkan has fled from Twiz in a duel", "Twiz", K, R), "won")
      A.eq(d("Ginkan-Realm has defeated Twiz-Realm in a duel", "Twiz", K, R), "lost")
      A.eq(d("Stabz has defeated Ginkan in a duel", "Twiz", K, R), nil)
      A.eq(d("hello", "Twiz", K, R), nil)
      -- plain %s formats
      A.eq(d("Twiz has defeated Ginkan in a duel", "Twiz", "%s has defeated %s in a duel", "%s fled from %s"), "won")
    end,
    junk_text = function(ns, A)
      local j = ns.StatsLogic.junkCount
      local S, M = "You receive loot: %s.", "You receive loot: %sx%d."
      A.eq(j("You receive loot: |cff9d9d9d|Hitem:2211::::::::1:::::::|h[Broken Fang]|h|r.", S, M), 1)
      A.eq(j("You receive loot: |cff9d9d9d|Hitem:2211|h[Broken Fang]|h|rx3.", S, M), 3)
      A.eq(j("You receive loot: |cffffffff|Hitem:2211|h[Linen Cloth]|h|r.", S, M), 0)
      A.eq(j("Ginkan receives loot: |cff9d9d9d|Hitem:2211|h[Broken Fang]|h|r.", S, M), 0)
      A.eq(j("You receive loot: |CFF9D9D9D|Hitem:2211|h[Broken Fang]|h|r.", S, M), 1)
    end,
    pull_rules = function(ns, A)
      local P = ns.StatsLogic.isPull
      local me = { zone = "The Deadmines", dungeon = true }
      local function m(tags, zone)
        return { { online = true, inInstance = true, zone = zone or "The Deadmines", tags = tags } }
      end
      A.eq(P(me, m({})), true)
      A.eq(P(me, m({ COMBAT = true })), false)
      A.eq(P(me, m({}, "Stormwind")), false)
      A.eq(P(me, {}), false)
      A.eq(P({ zone = "The Deadmines", dungeon = false }, m({})), false)
    end,
    wipe_watch = function(ns, A)
      local w = ns.StatsLogic.newWipeWatch(30)
      local both = { "Twiz", "Frostie" }
      w:dead("Twiz", 0)
      A.eq(w:check(both, 0), false)
      w:dead("Frostie", 20)
      A.eq(w:check(both, 20), true)
      A.eq(w:check(both, 20), false)
      w:alive("Twiz"); w:dead("Twiz", 70)
      A.eq(w:check(both, 70), false)
      A.eq(w:check({ "Twiz" }, 70), false)
    end,
  },
}
