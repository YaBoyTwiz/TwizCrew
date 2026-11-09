return {
  files = { "Core/Init.lua", "Core/Util.lua", "Stats/StatsDefs.lua", "Stats/StatsLogic.lua" },
  tests = {
    wire_sends_gold_carried_at_zero = function(ns, A)
      local L = ns.StatsLogic
      local f = L.toWire({ sid = "x", q = "1", s = { gn = 0, dt = 0, ml = 50 }, a = { gn = 0, zv = 3 } })
      A.eq(f.s_gn, "0", "0 gold goes out")
      A.eq(f.s_dt, nil, "other zeros don't")
      A.eq(f.s_ml, "50")
      A.eq(f.a_zv, "3")
      local back = L.fromWire(f)
      A.eq(back.s.gn, 0)
      A.eq(back.a.zv, 3)
    end,
    defs_shape = function(ns, A)
      local D = ns.StatsDefs
      A.eq(table.concat(D.KEYS, " "), "dt df dd dw db ld pl wp af ds st mt sw jp hs jk rp qa dl dv rz pt gn ml mg nj oj tf wd xg xt ch em zv fp")
      A.eq(D.MIN_KEYS, { ld = true })
      A.eq(D.SET_KEYS, { gn = true })
      A.eq(D.TIME_KEYS, { pt = true, xt = true })
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
      A.eq(#D.AWARDS, 29)
      A.eq(D.AWARDS[1].id, "corpse")
      A.eq(D.AWARDS[29].id, "medic")
      A.ok(D.AWARDS[29].last)
      local tabs, perTab = {}, {}
      for _, t in ipairs(D.TABS) do tabs[t.id] = true; perTab[t.id] = 0 end
      A.eq(#D.TABS, 5)
      local lastTab = 1
      for _, d in ipairs(D.AWARDS) do
        A.ok(tabs[d.tab], d.id .. " has a tab")
        perTab[d.tab] = perTab[d.tab] + 1
        local idx
        for i, t in ipairs(D.TABS) do if t.id == d.tab then idx = i end end
        A.ok(idx >= lastTab, d.id .. ": the table runs tab by tab")
        lastTab = idx
      end
      A.eq(perTab, { deaths = 6, move = 7, loot = 5, oops = 6, lazy = 5 })
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
      A.eq(#list, 29)
    end,
    new_awards_pick_the_right_winner = function(ns, A)
      local L = ns.StatsLogic
      local function award(list, id)
        for _, a in ipairs(L.awards(list)) do if a.def.id == id then return a end end
      end
      local list = {
        { name = "Twiz", stats = { gn = 14, ml = 5000, mg = 1000, xg = 3000, xt = 3600, zv = 4, fp = 2 } },
        { name = "Lurabe", stats = { gn = 90000, ml = 100, mg = 900, xg = 9000, xt = 3600 } },
        { name = "Ginkan", stats = { gn = 0, xg = 100, xt = 600 } },
      }
      local p = award(list, "pauper")
      A.eq(p.winners, { "Ginkan" }, "0 gold wins")
      A.eq(p.text, "0c")
      local m = award(list, "moneypit")
      A.eq(m.winners, { "Twiz" })
      A.eq(m.text, "40s", "lost 5000, gained 1000")
      local s = award(list, "snail")
      A.eq(s.winners, { "Twiz" }, "Ginkan played under 30 minutes: not taking part")
      A.eq(s.text, "3,000 XP per hour")
      A.eq(award(list, "tourist").text, "4 zones")
      A.eq(award(list, "flyer").text, "2 flights")
      A.ok(award(list, "ninja").empty, "nobody yet")
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
      -- lowest: only the people who take part (0 steps = Count steps off or never walked: not taking part)
      local c = L.awards({ { name = "A", stats = { st = 0, pt = 3600 } }, { name = "B", stats = { st = 5000, pt = 3600 } } })
      for _, a in ipairs(c) do
        if a.def.id == "couch" then A.eq(a.winners, { "B" }); A.ok(not a.empty) end
      end
    end,
    couch_never_crowns_zero_steps = function(ns, A)
      local L = ns.StatsLogic
      local function couch(entries)
        for _, a in ipairs(L.awards(entries)) do if a.def.id == "couch" then return a end end
      end
      A.ok(couch({ { name = "A", stats = { pt = 7200 } } }).empty, "no st at all")
      A.ok(couch({ { name = "A", stats = { st = 0, pt = 7200 } } }).empty, "st = 0")
      A.ok(couch({ { name = "A", stats = { st = 0, pt = 7200 } }, { name = "B", stats = { pt = 7200 } } }).empty)
      local c = couch({ { name = "A", stats = { st = 0, pt = 7200 } }, { name = "B", stats = { st = 100, pt = 7200 } } })
      A.eq(c.winners, { "B" })
      A.eq(#c.top, 1)
    end,
    wire_rejects_huge_and_negative_zero = function(ns, A)
      local L = ns.StatsLogic
      local r = L.fromWire({ sid = "T", s_dt = "1e300", s_jp = "1000000000001", a_st = "1000000000000", a_dt = "-0",
        s_st = "-0.0" })
      A.eq(r.s, { st = 0 })
      A.eq(r.a, { st = 1000000000000, dt = 0 })
      A.eq(tostring(r.a.dt), "0", "-0 folded to 0")
      A.eq(tostring(r.s.st), "0", "-0.0 folded to 0")
    end,
    titles_first_award_wins = function(ns, A)
      local L = ns.StatsLogic
      local list = L.awards({ { name = "Twiz", stats = { dt = 5, jp = 9 } }, { name = "Frostie", stats = { dt = 1 } } })
      local t = L.titles(list)
      A.eq(t.Twiz, "Professional Corpse")
      A.eq(t.Frostie, nil)
    end,
    red_errors_are_matched_by_the_games_own_text = function(ns, A)
      local L = ns.StatsLogic
      local texts = L.errorTexts({ oj = { "ERR_OUT_OF_MANA", "ERR_NOPE" }, tf = { "ERR_USE_TOO_FAR" } },
        { ERR_OUT_OF_MANA = "Not enough mana", ERR_USE_TOO_FAR = "You are too far away." })
      A.eq(texts, { ["Not enough mana"] = "oj", ["You are too far away."] = "tf" }, "missing names are skipped")
      A.eq(L.errorKey("Not enough mana", texts), "oj")
      A.eq(L.errorKey("You are too far away.", texts), "tf")
      A.eq(L.errorKey("Can't do that while moving", texts), nil)
      A.eq(L.errorKey(nil, texts), nil)
    end,

    need_rolls_won = function(ns, A)
      local L = ns.StatsLogic
      local link = "|cff1eff00|Hitem:1:|h[Sword]|h|r"
      A.ok(L.needWin("You (Need - 87) Won: " .. link, "You (Need - %d) Won: %s", "You won: %s", {}, 10, 300),
        "the client says Need itself")
      local needed = { [link] = 5 }
      A.ok(L.needWin("You won: " .. link, nil, "You won: %s", needed, 10, 300), "we rolled Need on it")
      A.eq(needed[link], nil, "used up")
      A.no(L.needWin("You won: " .. link, nil, "You won: %s", needed, 10, 300), "Greed (not in the list)")
      A.no(L.needWin("You won: " .. link, nil, "You won: %s", { [link] = 1 }, 400, 300), "too long ago")
      A.no(L.needWin("Ginkan won: " .. link, nil, "You won: %s", { [link] = 5 }, 10, 300))
    end,

    xp_gained_across_a_level_up = function(ns, A)
      local L = ns.StatsLogic
      A.eq(L.xpGained({ level = 10, xp = 100, max = 1000 }, { level = 10, xp = 250, max = 1000 }), 150)
      A.eq(L.xpGained({ level = 10, xp = 900, max = 1000 }, { level = 11, xp = 50, max = 1200 }), 150, "the ding")
      A.eq(L.xpGained({ level = 10, xp = 900, max = 1000 }, { level = 10, xp = 100, max = 1000 }), 0, "never minus")
      A.eq(L.xpGained(nil, { level = 10, xp = 1, max = 1000 }), 0, "the first reading")
      -- level and xp read a tick apart: wait, then count once
      local function run(readings)
        local base, total = readings[1], 0
        for i = 2, #readings do
          local g, settled = L.xpGained(base, readings[i])
          total = total + g
          if settled then base = readings[i] end
        end
        return total
      end
      A.eq(run({ { level = 10, xp = 900, max = 1000 }, { level = 11, xp = 900, max = 1200 },
        { level = 11, xp = 50, max = 1200 } }), 150, "level first, xp later")
      A.eq(run({ { level = 10, xp = 900, max = 1000 }, { level = 10, xp = 50, max = 1000 },
        { level = 11, xp = 50, max = 1200 } }), 150, "xp first, level later")
      local _, s1 = L.xpGained({ level = 10, xp = 900, max = 1000 }, { level = 11, xp = 900, max = 1200 })
      local _, s2 = L.xpGained({ level = 10, xp = 900, max = 1000 }, { level = 10, xp = 50, max = 1000 })
      A.no(s1, "unsettled: new level, old xp")
      A.no(s2, "unsettled: xp down, same level")
      A.eq(L.xpGained({ level = 10, xp = 1, max = 1000 }, { level = 13, xp = 1, max = 2000 }), 0, "a jump: unknown")
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
