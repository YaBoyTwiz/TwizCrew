-- The pure rules of the welcome card (UI/WelcomeLogic.lua): who just joined, the start card's once-only flag, who is
-- online near my level, and the words.

local function m(name, extra)
  local e = { key = name:match("^(%S+)"), full = name, level = 10, class = "MAGE", name = name:match("^(%S+)"),
    online = true }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.full end
  return out
end

local BASE = { m("Twiz Main"), m("Frostie Snow"), m("Chaos Deathbringr") }

local function plus(...)
  local out = {}
  for i, e in ipairs(BASE) do out[i] = e end
  for _, e in ipairs({ ... }) do out[#out + 1] = e end
  return out
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Calendar/CalendarLogic.lua", "UI/WelcomeLogic.lua" },
  tests = {
    first_list_of_a_session_welcomes_nobody = function(ns, A)
      local L = ns.WelcomeLogic
      local s = L.new()
      A.eq(L.joins(s, plus(m("Sneakz Rogue")), { whole = true, now = 0 }), {}, "the first list")
      A.eq(names(L.joins(s, plus(m("Sneakz Rogue"), m("Newbie One")), { whole = true, now = 5 })), { "Newbie One" })
    end,
    nothing_before_a_whole_list = function(ns, A)
      local L = ns.WelcomeLogic
      local s = L.new()
      A.eq(L.joins(s, BASE, { whole = false, now = 0 }), {}, "not whole: no baseline yet")
      A.eq(L.joins(s, plus(m("Sneakz Rogue")), { whole = false, now = 1 }), {}, "still no whole list before")
      A.eq(L.joins(s, plus(m("Sneakz Rogue")), { whole = true, now = 2 }), {}, "the first whole list sets it")
      A.eq(names(L.joins(s, plus(m("Sneakz Rogue"), m("Newbie One")), { whole = false, now = 3 })), { "Newbie One" },
        "a list that may lack the offline members can still show who is new")
    end,
    own_alts_snapshot_and_welcomed_are_skipped = function(ns, A)
      local L = ns.WelcomeLogic
      local s = L.new()
      L.joins(s, BASE, { whole = true, now = 0 })
      local list = plus(m("Altie Mine"), m("Oldie Known"), m("Done Before"), m("Fresh Face"), m("Fake (test)"))
      local got = L.joins(s, list, { whole = true, now = 1, mine = { Altie = true },
        baseline = { ["oldie known"] = true }, welcomed = { ["done before"] = true } })
      A.eq(names(got), { "Fresh Face" })
      A.eq(L.joins(s, list, { whole = true, now = 2 }), {}, "the next list has them all")
    end,
    rate_limit = function(ns, A)
      local L = ns.WelcomeLogic
      local s = L.new()
      L.joins(s, BASE, { whole = true, now = 0 })
      local got = L.joins(s, plus(m("A One"), m("B Two"), m("C Three"), m("D Four")), { whole = true, now = 10 })
      A.eq(names(got), { "A One", "B Two", "C Three" }, "at most 3 a minute; the rest are dropped")
      A.eq(L.joins(s, plus(m("A One"), m("B Two"), m("C Three"), m("D Four"), m("E Five")), { whole = true, now = 30 }),
        {}, "still inside the minute")
      A.eq(names(L.joins(s, plus(m("A One"), m("B Two"), m("C Three"), m("D Four"), m("E Five"), m("F Six")),
        { whole = true, now = 71 })), { "F Six" }, "a minute later")
    end,
    start_card_once_only = function(ns, A)
      local L = ns.WelcomeLogic
      local store = {}
      L.markStart(store, true)
      A.ok(L.startDue(store), "fresh: due")
      L.markStart(store, false)
      A.ok(L.startDue(store), "still due until shown (a later login is not fresh any more)")
      L.startShown(store)
      A.no(L.startDue(store), "shown: never twice")
      L.markStart(store, true)
      A.no(L.startDue(store))
      local old = {}
      L.markStart(old, false)
      A.no(L.startDue(old), "an existing user (or adopted old data): not due")
      L.markStart(old, true)
      A.no(L.startDue(old), "and never later")
      A.no(L.startDue(nil))
    end,
    near_your_level = function(ns, A)
      local L = ns.WelcomeLogic
      local list = { m("Me Myself", { level = 25 }), m("A A", { level = 24 }), m("B B", { level = 26 }),
        m("C C", { level = 30 }), m("D D", { level = 31 }), m("E E", { level = 20 }), m("F F", { level = 25 }),
        m("G G", { level = 25, online = false }), m("H H", { level = 19 }) }
      local function isMe(e) return e.full == "Me Myself" end
      local near = L.nearLevel(list, 25, isMe)
      A.eq(names(near), { "F F", "A A", "B B", "E E", "C C" }, "nearest first (then lower), at most 5, online only, not me")
      A.eq(L.nearText({ near[1], near[2] }), "Online near your level: F (25), A (24)")
      A.eq(L.nearText({}), "Nobody near your level is on right now")
      A.eq(L.nearLevel(list, nil, isMe), {})
    end,
    best_time_words = function(ns, A)
      local L = ns.WelcomeLogic
      A.eq(L.bestText({ weekday = 2, from = 20, to = 23 }), "The crew usually plays: Tue 8pm-11pm")
      A.eq(L.bestText(nil), nil)
    end,
    popup_and_greeting_words = function(ns, A)
      local L = ns.WelcomeLogic
      local title, sub = L.popupText("Sneakz", 8, "Mage")
      A.eq(title, "Say hi to Sneakz")
      A.eq(sub, "Level 8 Mage just joined the guild - click to say hello")
      local _, bare = L.popupText("Sneakz")
      A.eq(bare, "Just joined the guild - click to say hello")
      A.eq(L.greeting("Sneakz", 1), "Welcome to the guild, Sneakz!")
      A.eq(L.greeting("Sne|kz", 99), "Welcome to the guild, Snekz!", "no pipe goes to chat")
      for i = 1, #L.GREETINGS do
        local line = L.greeting("Sneakz", i)
        A.ok(line:find("Sneakz", 1, true), "the name is in line " .. i)
        A.no(line:find("\226\128\148", 1, true), "no em dash")
      end
    end,
  },
}
