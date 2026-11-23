-- The pure rules of the "While you were away" card (UI/AwayLogic.lua).

local H12 = 12 * 3600
local NOW = 1700000000

local function m(key, level, extra)
  local e = { key = key, full = key .. " Surname", level = level, class = "MAGE", name = key }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

local function texts(lines)
  local out = {}
  for i, l in ipairs(lines) do out[i] = l.text end
  return out
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "UI/AwayLogic.lua" },
  tests = {
    levelled_joined_left = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ m("Irek", 27), m("Frostie", 20), m("Chaos", 30) }, NOW - 3 * 86400, "Crew")
      local now = { m("Irek", 30), m("Chaos", 30), m("Sneakz", 8) }
      local d = L.diff(snap, now, { now = NOW, guild = "Crew", whole = true })
      A.eq(d.gone, 3 * 86400)
      A.eq(d.levels, { { key = "Irek", name = "Irek", from = 27, to = 30 } })
      A.eq(d.joined, { { key = "Sneakz", name = "Sneakz", level = 8, class = "MAGE" } })
      A.eq(d.left, { { key = "Frostie", name = "Frostie" } })
      A.eq(texts(L.lines(d, 0, {})), { "Sneakz joined the guild", "Frostie left the guild", "Irek 27 -> 30" })
    end,
    nothing_changed_gives_no_lines = function(ns, A)
      local L = ns.AwayLogic
      local list = { m("Irek", 27), m("Frostie", 20) }
      local d = L.diff(L.snapshot(list, NOW - 2 * H12, "Crew"), list, { now = NOW, guild = "Crew", whole = true })
      A.ok(d, "compared")
      A.eq(L.lines(d, 0, {}), {}, "no lines: no card")
    end,
    snapshot_too_recent = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ m("Irek", 27) }, NOW - H12 + 60, "Crew")
      A.eq(L.diff(snap, { m("Irek", 30) }, { now = NOW, guild = "Crew", whole = true }), nil, "under 12 hours")
      A.ok(L.diff(snap, { m("Irek", 30) }, { now = NOW + 60, guild = "Crew", whole = true }), "12 hours exactly")
      A.eq(L.diff(nil, { m("Irek", 30) }, { now = NOW, guild = "Crew" }), nil, "no snapshot")
      A.eq(L.diff({ members = {} }, {}, { now = NOW, guild = "Crew" }), nil, "no time")
    end,
    another_guilds_snapshot_is_never_used = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ m("Irek", 27) }, NOW - 3 * H12, "Other Guild")
      A.eq(L.diff(snap, { m("Irek", 30) }, { now = NOW, guild = "Crew", whole = true }), nil)
    end,
    list_not_whole_has_no_left_lines = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ m("Irek", 27), m("Frostie", 20) }, NOW - 3 * H12, "Crew")
      local d = L.diff(snap, { m("Irek", 28), m("Sneakz", 5) }, { now = NOW, guild = "Crew", whole = false })
      A.eq(d.left, {}, "Frostie may just be offline")
      A.eq(#d.levels, 1)
      A.eq(#d.joined, 1, "someone listed now and not before has joined")
    end,
    namesakes_use_the_guild_keys = function(ns, A)
      local L = ns.AwayLogic
      local a = { key = "Chaos", full = "Chaos Deathbringr", level = 20, name = "Chaos Deathbringr" }
      local b = { key = "Chaos Other", full = "Chaos Other", level = 10, name = "Chaos Other" }
      local snap = L.snapshot({ a, b }, NOW - 3 * H12, "Crew")
      A.ok(snap.members.Chaos and snap.members["Chaos Other"], "kept by key")
      local now = { { key = "Chaos", full = "Chaos Deathbringr", level = 20, name = "Chaos Deathbringr" },
        { key = "Chaos Other", full = "Chaos Other", level = 14, name = "Chaos Other" } }
      local d = L.diff(snap, now, { now = NOW, guild = "Crew", whole = true })
      A.eq(texts(L.lines(d, 0, {})), { "Chaos Other 10 -> 14" }, "the right Chaos levelled")
    end,
    a_member_whose_key_changed_is_the_same_member = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ { key = "Irek", full = "Irek Foo", level = 27, name = "Irek", guid = "G1" },
        { key = "Bob", full = "Bob Bar", level = 5, name = "Bob" } }, NOW - 3 * H12, "Crew")
      local now = { { key = "Irek Foo", full = "Irek Foo", level = 30, name = "Irek Foo" }, -- matched by full name
        { key = "Bobby", full = "Bobby Bar", level = 6, name = "Bobby", guid = nil } }
      snap.members.Bob.guid = "G2"
      now[2].guid = "G2" -- renamed, same GUID
      local d = L.diff(snap, now, { now = NOW, guild = "Crew", whole = true })
      A.eq(d.joined, {}, "nobody joined")
      A.eq(d.left, {}, "nobody left")
      A.eq(texts(L.lines(d, 0, {})), { "Irek Foo 27 -> 30", "Bobby 5 -> 6" })
    end,
    my_own_characters_are_never_listed = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ m("Twiz", 20), m("Altie", 5) }, NOW - 3 * H12, "Crew")
      local d = L.diff(snap, { m("Twiz", 20), m("Altie", 9), m("Newalt", 1) },
        { now = NOW, guild = "Crew", whole = true, mine = { Altie = true, ["newalt surname"] = true } })
      A.eq(L.lines(d, 0, {}), {})
    end,
    my_characters_by_guid = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({ m("Twiz", 20), m("Altie", 5, { guid = "G-ALT" }) }, NOW - 3 * H12, "Crew")
      local d = L.diff(snap, { m("Twiz", 20), m("Altie", 9, { guid = "G-ALT" }), m("Newalt", 1, { guid = "G-NEW" }) },
        { now = NOW, guild = "Crew", whole = true, mine = { ["G-ALT"] = true, ["G-NEW"] = true } })
      A.eq(L.lines(d, 0, {}), {}, "matched by GUID")
      local gone = L.diff(snap, { m("Twiz", 20) }, { now = NOW, guild = "Crew", whole = true, mine = { ["G-ALT"] = true } })
      A.eq(gone.left, {}, "my alt leaving is not listed either")
    end,
    crowds_of_joins_or_leaves_are_dropped = function(ns, A)
      local L = ns.AwayLogic
      local all, online = {}, {}
      for i = 1, 30 do
        all[i] = m("M" .. string.format("%02d", i), 10)
        if i <= 5 then online[i] = m("M" .. string.format("%02d", i), i == 1 and 12 or 10) end
      end
      -- an online-only list that looked whole: 25 "left" would be a lie
      local d = L.diff(L.snapshot(all, NOW - 3 * H12, "Crew"), online, { now = NOW, guild = "Crew", whole = true })
      A.eq(d.left, {}, "a crowd of leaves: none listed")
      A.eq(#d.levels, 1, "level-ups stay")
      -- and the other way round: a snapshot of only the online members, then the whole list
      d = L.diff(L.snapshot(online, NOW - 3 * H12, "Crew"), all, { now = NOW, guild = "Crew", whole = true })
      A.eq(d.joined, {}, "a crowd of joins: none listed")
      -- a few at a time are real: 3 of 30 left, 3 joined
      local now = {}
      for i = 4, 30 do now[#now + 1] = all[i] end
      for i = 1, 3 do now[#now + 1] = m("New" .. i, 1) end
      d = L.diff(L.snapshot(all, NOW - 3 * H12, "Crew"), now, { now = NOW, guild = "Crew", whole = true })
      A.eq(#d.left, 3, "three left")
      A.eq(#d.joined, 3, "three joined")
      -- in a bigger guild the limit is 10%: 5 of 50
      local big, fewer = {}, {}
      for i = 1, 50 do big[i] = m("B" .. string.format("%02d", i), 10) end
      for i = 6, 50 do fewer[#fewer + 1] = big[i] end
      d = L.diff(L.snapshot(big, NOW - 3 * H12, "Crew"), fewer, { now = NOW, guild = "Crew", whole = true })
      A.eq(#d.left, 5, "5 of 50 is not a crowd")
      table.remove(fewer, 1)
      d = L.diff(L.snapshot(big, NOW - 3 * H12, "Crew"), fewer, { now = NOW, guild = "Crew", whole = true })
      A.eq(d.left, {}, "6 of 50 is")
    end,
    test_fakes_never_hold_a_crown = function(ns, A)
      local L = ns.AwayLogic
      local defs = { { id = "moneypit", name = "Money Pit", tab = "loot" }, { id = "corpse", name = "Professional Corpse",
        tab = "deaths" } }
      local now = L.crowns({ { def = defs[1], winners = { "Bob (test)" } }, { def = defs[2], winners = { "Chaos", "Al (test)" } } })
      A.eq(now, { corpse = { "Chaos" } }, "fakes are left out")
      A.eq(L.crownChanges({ corpse = { "Bob (test)" } }, now, defs), {}, "a fake as the old holder: no line")
      A.eq(L.crownChanges({ moneypit = { "Chaos" } }, { moneypit = { "Bob (test)" } }, defs), {},
        "a fake as the new holder: no line")
    end,
    max_lines_and_more = function(ns, A)
      local L = ns.AwayLogic
      local before, now = {}, {}
      for i = 1, 20 do
        before[i] = m("M" .. string.format("%02d", i), 10)
        now[i] = m("M" .. string.format("%02d", i), 11)
      end
      local d = L.diff(L.snapshot(before, NOW - 3 * H12, "Crew"), now, { now = NOW, guild = "Crew", whole = true })
      local lines = L.cap(L.lines(d, 2, {}))
      A.eq(#lines, 12)
      A.eq(lines[1].text, "2 new calendar notes")
      A.eq(lines[1].kind, "calendar")
      A.eq(lines[12].text, "...and 10 more")
      local few = L.cap({ { text = "a" }, { text = "b" } })
      A.eq(#few, 2, "a short list stays")
    end,
    calendar_words = function(ns, A)
      local L = ns.AwayLogic
      A.eq(texts(L.lines(nil, 1, {})), { "1 new calendar note" })
      A.eq(L.lines(nil, 0, {}), {})
    end,
    crowns_that_changed_hands = function(ns, A)
      local L = ns.AwayLogic
      local defs = { { id = "moneypit", name = "Money Pit", tab = "loot" }, { id = "corpse", name = "Professional Corpse",
        tab = "deaths" }, { id = "fish", name = "Fish", tab = "move" }, { id = "couch", name = "Couch Potato", noSteal = true } }
      local awards = {
        { def = defs[1], winners = { "Chaos" }, empty = false },
        { def = defs[2], winners = { "Frostie", "Irek" }, empty = false },
        { def = defs[3], winners = {}, empty = true },
        { def = defs[4], winners = { "Bob" }, empty = false },
      }
      local now = L.crowns(awards)
      A.eq(now, { moneypit = { "Chaos" }, corpse = { "Frostie", "Irek" } }, "rates and empty awards are left out")
      local before = { moneypit = { "Frostie" }, corpse = { "Irek" }, fish = { "Bob" } }
      local changes = L.crownChanges(before, now, defs)
      A.eq(#changes, 1, "a tie with the old holder is not a steal; a crown nobody holds now is not either")
      A.eq(changes[1].tab, "loot")
      local lines = L.lines(nil, 0, changes, function(k) return k == "Chaos" and "Chaos D" or k end)
      A.eq(texts(lines), { "Chaos D took Money Pit from Frostie" })
      A.eq(lines[1].kind, "crown")
      A.eq(lines[1].tab, "loot")
      A.eq(L.crownChanges(nil, now, defs), {}, "no crowns saved at logout")
    end,
    merge_keeps_the_offline_members = function(ns, A)
      local L = ns.AwayLogic
      local old = L.snapshot({ m("Irek", 27), m("Frostie", 20) }, NOW - 86400, "Crew")
      old.crowns = { moneypit = { "Chaos" } }
      local merged = L.merge(old, { m("Irek", 29), m("Sneakz", 3) }, NOW, "Crew")
      A.eq(merged.at, NOW)
      A.eq(merged.members.Irek.level, 29, "listed: updated")
      A.eq(merged.members.Frostie.level, 20, "not listed (offline): kept")
      A.eq(merged.members.Sneakz.level, 3, "new: added")
      A.eq(merged.crowns, old.crowns)
      A.eq(L.merge(old, {}, NOW, "Other"), nil, "another guild's snapshot is not merged")
      A.eq(L.merge(nil, {}, NOW, "Crew"), nil)
    end,
    gone_words = function(ns, A)
      local L = ns.AwayLogic
      A.eq(L.goneText(14 * 3600 + 100), "You were gone 14 hours")
      A.eq(L.goneText(35 * 3600), "You were gone 35 hours")
      A.eq(L.goneText(3 * 86400 + 5), "You were gone 3 days")
    end,
    names_are_made_safe = function(ns, A)
      local L = ns.AwayLogic
      local snap = L.snapshot({}, NOW - 3 * H12, "Crew")
      local d = L.diff(snap, { { key = "A|b", full = "A|b C", name = "A|b", level = 3 } },
        { now = NOW, guild = "Crew", whole = true })
      A.eq(texts(L.lines(d, 0, {})), { "A||b joined the guild" })
    end,
  },
}
