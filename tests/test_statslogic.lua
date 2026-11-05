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
    formatting = function(ns, A)
      local L = ns.StatsLogic
      A.eq(L.number(12403.7), "12,403")
      A.eq(L.number(5), "5")
      A.eq(L.number(1234567), "1,234,567")
      A.eq(L.duration(7800), "2h 10m")
      A.eq(L.duration(2700), "45m")
      A.eq(L.duration(30), "30s")
      A.eq(L.money(32005), "3g 20s 5c")
      A.eq(L.money(30000), "3g")
      A.eq(L.money(0), "0c")
    end,
    awards_defs_shape = function(ns, A)
      local D = ns.StatsDefs
      A.eq(#D.AWARDS, 18)
      A.eq(D.AWARDS[1].id, "corpse")
      A.eq(D.AWARDS[18].id, "medic")
      A.ok(D.AWARDS[18].last)
      A.ok(D.AWARDS[9].id == "couch" and D.AWARDS[9].lowest and not D.AWARDS[10].lowest)
      for _, d in ipairs(D.AWARDS) do
        A.ok(d.name and d.unit and d.icon and d.info and d.joke, d.id)
        A.ok(d.key or d.value, d.id)
      end
      A.eq(D.SOUNDS.badge.id, 8960)
      A.eq(D.SOUNDS.reveal.kit, "RAID_WARNING")
      A.eq(D.ICON_FALLBACK, "Interface\\Icons\\INV_Misc_QuestionMark")
    end,
    award_winners_and_ties = function(ns, A)
      local L = ns.StatsLogic
      local e = { { name = "Twiz", stats = { dt = 7, st = 12403, pt = 3600 } },
                  { name = "Frostie", stats = { dt = 7, jp = 3 } },
                  { name = "Ginkan", stats = { dt = 2, pt = 600, st = 90000 } } }
      local list = L.awards(e)
      local by = {}
      for _, a in ipairs(list) do by[a.def.id] = a end
      A.eq(by.corpse.winners, { "Frostie", "Twiz" })
      A.eq(by.corpse.text, "7 deaths")
      A.eq(by.marathon.winners, { "Ginkan" })
      A.eq(by.marathon.text, "90,000 steps")
      A.ok(by.gravity.empty)
      A.eq(by.couch.winners, { "Twiz" })
      A.eq(by.corpse.top[1].value, 7)
      A.eq(#by.corpse.top, 3)
      A.eq(by.corpse.top[3].name, "Ginkan")
      A.eq(list[#list].def.id, "medic")
      A.eq(#list, 18)
    end,
    weakling_shows_mob_level = function(ns, A)
      local L = ns.StatsLogic
      local list = L.awards({ { name = "Twiz", stats = { dw = 2, ld = 4 } } })
      local w
      for _, a in ipairs(list) do if a.def.id == "weakling" then w = a end end
      A.eq(w.text, "2 deaths (lvl 4 mob)")
    end,
    never_walks_ratio_and_minimum = function(ns, A)
      local L = ns.StatsLogic
      local function nw(stats)
        for _, a in ipairs(L.awards({ { name = "X", stats = stats } })) do
          if a.def.id == "neverwalks" then return a end
        end
      end
      local a = nw({ mt = 5000, st = 480 })
      A.eq(a.winners, { "X" })
      A.eq(a.text, "rides 12.5x more than walks")
      A.ok(nw({ mt = 500, st = 120 }).empty)
    end,
    awards_formats_and_edges = function(ns, A)
      local L = ns.StatsLogic
      local by = {}
      for _, a in ipairs(L.awards({ { name = "X", stats = { af = 7800, rp = 32005, st = 7200, pt = 7200, dt = 1 } },
                                    { name = "Y", stats = { dt = 0 } } })) do by[a.def.id] = a end
      A.eq(by.furniture.text, "2h 10m AFK")
      A.eq(by.broke.text, "3g 20s 5c")
      A.eq(by.couch.text, "3,600 steps per hour")
      A.eq(by.corpse.text, "1 death")
      A.eq(by.corpse.winners, { "X" })
      A.eq(#by.corpse.top, 1)
      A.ok(by.bunny.empty)
      A.eq(by.bunny.winners, {})
      -- lowest: only the people who take part
      local c = L.awards({ { name = "A", stats = { st = 0, pt = 3600 } }, { name = "B", stats = { st = 5000, pt = 3600 } } })
      for _, a in ipairs(c) do
        if a.def.id == "couch" then A.eq(a.winners, { "A" }); A.ok(not a.empty) end
      end
    end,
    titles_first_award_wins = function(ns, A)
      local L = ns.StatsLogic
      local list = L.awards({ { name = "Twiz", stats = { dt = 5, jp = 9 } }, { name = "Frostie", stats = { dt = 1 } } })
      local t = L.titles(list)
      A.eq(t.Twiz, "Professional Corpse")
      A.eq(t.Frostie, nil)
    end,
    wire_roundtrip = function(ns, A)
      local L = ns.StatsLogic
      local w = L.toWire({ sid = "T-1", q = "1-1", s = { dt = 3, st = 10.7, jp = 0, zz = 4 }, a = { st = 12403.2 } })
      A.eq(w, { sid = "T-1", q = "1-1", s_dt = "3", s_st = "10", a_st = "12403" })
      local back = L.fromWire(w)
      A.eq(back.s, { dt = 3, st = 10 })
      A.eq(back.a, { st = 12403 })
      A.eq(back.sid, "T-1")
      A.eq(back.q, "1-1")
      local off = L.toWire({ sid = "T-1", q = "2", off = true, s = { dt = 3 } })
      A.eq(off, { sid = "T-1", q = "2", off = "1" })
      A.eq(L.fromWire(off).off, true)
    end,
    wire_rejects_garbage = function(ns, A)
      local L = ns.StatsLogic
      A.eq(L.fromWire({}), nil)
      local r = L.fromWire({ sid = "T", s_dt = "-4", a_st = "abc", a_jp = "1e999", s_zz = "5", a_dt = "2.9", x = "1" })
      A.eq(r.s, {})
      A.eq(r.a, { dt = 2 })
    end,
    show_cards_medic_last = function(ns, A)
      local L = ns.StatsLogic
      local list = L.awards({ { name = "Twiz", stats = { dt = 3, rz = 2 } } })
      local cards = L.showCards(list)
      local ids = {}
      for _, c in ipairs(cards) do ids[#ids + 1] = c.kind .. ":" .. (c.award and c.award.def.id or "") end
      A.eq(ids, { "award:corpse", "award:medic", "end:" })
    end,
  },
}
