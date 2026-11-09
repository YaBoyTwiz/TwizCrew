-- The awards show on the crew's screens (Hall of Shame part 3): the pure show rules, the presenter's messages.
-- Full TOC boot.

return {
  files = "toc",
  tests = {
    show_rules = function(ns, A)
      local L = ns.ShowLogic
      A.eq(L.ordinal(2), "2nd"); A.eq(L.ordinal(3), "3rd"); A.eq(L.ordinal(4), "4th")
      A.eq(L.ordinal(11), "11th"); A.eq(L.ordinal(12), "12th"); A.eq(L.ordinal(13), "13th"); A.eq(L.ordinal(21), "21st")
      A.eq(L.streakLine(1), nil)
      A.eq(L.streakLine(3), "and for the 3rd session in a row")
      local def = ns.StatsDefs.AWARDS[1]
      local card = { kind = "award", award = { def = def, winners = { "Lurabe", "Twiz" }, text = "8 deaths" } }
      local f = L.cardToWire("Twiz-1", 4, card, 3, true)
      A.eq(f, { id = "Twiz-1", i = "4", k = "award", a = def.id, w = "Lurabe,Twiz", x = "8 deaths", s = "3", r = "1" })
      A.eq(L.cardFromWire(f), { i = 4, kind = "award", awardId = def.id, winners = { "Lurabe", "Twiz" },
        text = "8 deaths", streak = 3, jump = true })
      A.eq(L.cardFromWire({ id = "Twiz-1", i = "9", k = "end" }).kind, "end")
      A.eq(L.cardFromWire({ id = "Twiz-1", i = "x", k = "end" }), nil)
      A.eq(L.cardFromWire({ id = "Twiz-1", i = "2", k = "award", a = "nope" }), nil, "unknown award")
      local w, n = L.tally({ Twiz = "Lurabe", Ginkan = "Lurabe", Lurabe = "Twiz", Frostie = "Frostie" },
        { "Twiz", "Lurabe", "Ginkan", "Frostie" })
      A.eq(w, { "Lurabe" }); A.eq(n, 2)
      w, n = L.tally({ Twiz = "Lurabe", Lurabe = "Twiz" }, { "Twiz", "Lurabe" })
      A.eq(w, { "Lurabe", "Twiz" }, "a tie: co-clowns"); A.eq(n, 1)
      w, n = L.tally({}, { "Twiz", "Lurabe" })
      A.eq(w, {}); A.eq(n, 0)
      w, n = L.tally({ Twiz = "Nobody" }, { "Twiz", "Lurabe" })
      A.eq(w, {}, "not a candidate"); A.eq(n, 0)
    end,
  },
}
