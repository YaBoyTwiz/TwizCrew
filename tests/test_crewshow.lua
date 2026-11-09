-- The awards show on the crew's screens (Hall of Shame part 3): the pure show rules, the presenter's messages.
-- Full TOC boot.

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- Boots and lets the session be decided.
local function start(ns, W)
  W.state.zone = nil -- no zone read: the Tourist card (zones visited) would join every show
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function hello(W, ns, name, class)
  receive(W, ns, name, "STATE", { ver = "0.1.0", cl = class or "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
    lk = "", ins = "0" })
end

-- The decoded messages of this type sent since mark (their fields, in order). The send queue lets out 2 a second
-- (a friend's hello and numbers go first), so tests let it drain before reading.
local function sentOf(ns, W, from, msgType)
  local out = {}
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then out[#out + 1] = msg.fields end
  end
  return out
end

local function state(ns) return ns.AwardsShow.stateForTest() end

-- Booted, Frostie 2 rezzes, me 7 deaths: cards Corpse (me), Medic (Frostie), end.
local function crewNight(ns, W)
  start(ns, W)
  local S = ns.Session.current().id
  hello(W, ns, "Frostie")
  receive(W, ns, "Frostie", "STATS", { sid = S, q = "1", s_rz = "2", a_rz = "2" })
  ns.Stats.count("dt", 7)
  return S
end

-- Booted with Frostie (a priest) online; Frostie starts a show. Returns the show id.
local function frostieShow(ns, W, v)
  start(ns, W)
  hello(W, ns, "Frostie", "PRIEST")
  receive(W, ns, "Frostie", "AWS", { id = "Frostie-1", v = v or "session" })
  return "Frostie-1"
end

local function card(W, ns, sender, fields)
  receive(W, ns, sender or "Frostie", "AWC", fields)
end

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

    presenter_sends_each_card = function(ns, A, W)
      crewNight(ns, W)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(4)
      A.eq(#sentOf(ns, W, mark, "AWS"), 0, "nothing sent while loading")
      W:advance(1)
      local built = ns.wallclock()
      A.eq(state(ns).phase, "badge")
      W:advance(0.6 + 1.5 + 3) -- the reveal on its own timer, then a few seconds for the send queue
      A.eq(state(ns).phase, "reveal")
      local starts = sentOf(ns, W, mark, "AWS")
      A.eq(#starts, 1)
      local id = starts[1].id
      A.eq(id, "Twiz-" .. built, "show id = presenter and wall clock")
      A.eq(starts[1].v, "session")
      local cards = sentOf(ns, W, mark, "AWC")
      A.eq(#cards, 1, "card 1 as it starts; the reveal on its own timer sends nothing")
      A.eq(cards[1], { id = id, i = "1", k = "award", a = "corpse", w = "Twiz", x = "7 deaths" })
      ns.AwardsShow.next() -- Medic
      A.eq(state(ns).phase, "badge")
      ns.AwardsShow.next() -- a click during the badge: straight to the reveal
      ns.AwardsShow.next() -- the end card
      W:advance(3)
      cards = sentOf(ns, W, mark, "AWC")
      A.eq(#cards, 4)
      A.eq(cards[2], { id = id, i = "2", k = "award", a = "medic", w = "Frostie", x = "2 rezzes" })
      A.eq(cards[3], { id = id, i = "2", k = "award", a = "medic", w = "Frostie", x = "2 rezzes", r = "1" },
        "the jump is sent again with r")
      A.eq(cards[4], { id = id, i = "3", k = "end" })
      A.eq(#sentOf(ns, W, mark, "AWX"), 0)
      ns.AwardsShow.next() -- closes
      A.no(ns.AwardsShow.isOpen())
      W:advance(3)
      A.eq(sentOf(ns, W, mark, "AWX"), { { id = id } }, "closing sends AWX")
      A.eq(#sentOf(ns, W, mark, "AWS"), 1)
      A.eq(ns.Log.errors(10), {})
    end,

    drumroll_click_jumps_all_time_show = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      ns.Stats.count("dt", 3)
      ns.AwardsShow.start("all")
      W:advance(5 + 0.6)
      A.eq(state(ns).phase, "drum")
      ns.AwardsShow.next()
      A.eq(state(ns).phase, "reveal")
      W:advance(3)
      A.eq(sentOf(ns, W, mark, "AWS")[1].v, "all")
      local cards = sentOf(ns, W, mark, "AWC")
      A.eq(#cards, 2)
      A.eq(cards[2].r, "1", "a click during the drumroll")
      A.eq(cards[2].i, "1")
      ns.AwardsShow.close()
      ns.AwardsShow.close()
      W:advance(3)
      A.eq(#sentOf(ns, W, mark, "AWX"), 1, "one AWX")
    end,

    closing_while_loading_sends_nothing = function(ns, A, W)
      start(ns, W)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(1)
      ns.AwardsShow.close()
      W:advance(10)
      A.eq(#sentOf(ns, W, mark, "AWS"), 0)
      A.eq(#sentOf(ns, W, mark, "AWX"), 0, "no AWX without an AWS")
    end,

    nobody_card_is_sent = function(ns, A, W)
      W.state.missing.GetMoney = true -- nothing is counted, so nobody has won
      start(ns, W)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(5)
      A.eq(state(ns).phase, "nobody")
      W:advance(3)
      local id = sentOf(ns, W, mark, "AWS")[1].id
      A.eq(sentOf(ns, W, mark, "AWC"), { { id = id, i = "1", k = "nobody" } })
    end,

    streak_on_the_card = function(ns, A, W)
      crewNight(ns, W)
      local t = ns.Trophies.records() -- ns.db.stats.trophies (made on first use)
      t["Twiz-100"] = { sid = "Twiz-100", start = 100, people = { "Frostie", "Twiz" }, winners = { corpse = { "Twiz" } } }
      t["Twiz-200"] = { sid = "Twiz-200", start = 200, people = { "Frostie", "Twiz" },
        winners = { corpse = { "Twiz" }, medic = { "Frostie", "Twiz" } } }
      ns.Bus.fire("TROPHIES_CHANGED", "Twiz-200")
      A.eq(ns.Trophies.summary().Twiz.streaks.corpse, 2)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(5 + 2.1)
      A.eq(state(ns).phase, "reveal")
      A.eq(state(ns).streak, "and for the 3rd session in a row")
      ns.AwardsShow.next()
      W:advance(3)
      local cards = sentOf(ns, W, mark, "AWC")
      A.eq(cards[1].a, "corpse")
      A.eq(cards[1].s, "3", "two saved wins + tonight")
      cards = sentOf(ns, W, mark, "AWC")
      A.eq(cards[2].a, "medic")
      A.eq(cards[2].s, "2", "a shared win counts: Frostie's 1 + tonight")
      ns.AwardsShow.close()
      mark = #W.sent
      ns.AwardsShow.start("all")
      W:advance(5 + 2.1)
      A.eq(state(ns).phase, "reveal")
      A.eq(state(ns).streak, nil)
      W:advance(3)
      cards = sentOf(ns, W, mark, "AWC")
      A.eq(cards[1].a, "corpse")
      A.eq(cards[1].s, nil, "no streaks in the all-time show")
      A.eq(ns.Log.errors(10), {})
    end,

    no_streak_for_shared_winners = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      hello(W, ns, "Frostie")
      receive(W, ns, "Frostie", "STATS", { sid = S, q = "1", s_dt = "7", a_dt = "7" })
      ns.Stats.count("dt", 7)
      local t = ns.Trophies.records() -- ns.db.stats.trophies (made on first use)
      t["Twiz-100"] = { sid = "Twiz-100", start = 100, people = { "Frostie", "Twiz" }, winners = { corpse = { "Twiz" } } }
      ns.Bus.fire("TROPHIES_CHANGED", "Twiz-100")
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(5 + 3)
      local cards = sentOf(ns, W, mark, "AWC")
      A.eq(cards[1].w, "Frostie,Twiz")
      A.eq(cards[1].s, nil, "two winners: no streak")
    end,

    starting_again_closes_the_old_show = function(ns, A, W)
      crewNight(ns, W)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(5)
      ns.AwardsShow.start("all")
      W:advance(5 + 3)
      local starts, ends = sentOf(ns, W, mark, "AWS"), sentOf(ns, W, mark, "AWX")
      A.eq(#starts, 2)
      A.eq(ends, { { id = starts[1].id } }, "the first show is closed for the crew")
    end,

    idle_show_closes = function(ns, A, W)
      crewNight(ns, W)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      W:advance(5 + 59)
      A.ok(ns.AwardsShow.isOpen(), "59 s on the first card")
      ns.AwardsShow.next() -- Medic: the clock starts again
      W:advance(59)
      A.ok(ns.AwardsShow.isOpen(), "a card change restarts the clock")
      W:advance(2)
      A.no(ns.AwardsShow.isOpen(), "61 s with no card change: closed")
      W:advance(3)
      A.eq(#sentOf(ns, W, mark, "AWX"), 1, "the presenter tells the crew")
      A.eq(ns.Log.errors(10), {})
    end,

    viewer_follows_the_show = function(ns, A, W)
      local mark = #W.sent
      local id = frostieShow(ns, W)
      A.ok(ns.AwardsShow.isOpen(), "Frostie's AWS opens the show")
      local st = state(ns)
      A.eq(st.role, "viewer"); A.eq(st.phase, "loading")
      A.eq(st.header, "TwizCrew Awards: Frostie's show")
      A.eq(st.hint, "Frostie is presenting")
      card(W, ns, "Frostie", { id = id, i = "1", k = "award", a = "corpse", w = "Twiz,Frostie", x = "7 deaths" })
      A.eq(state(ns).phase, "badge")
      A.eq(state(ns).title, "Professional Corpse")
      ns.AwardsShow.next() -- a viewer's click does nothing mid-show
      A.eq(state(ns).phase, "badge")
      W:advance(0.6)
      A.eq(state(ns).phase, "drum")
      W:advance(1.5)
      st = state(ns)
      A.eq(st.phase, "reveal")
      A.eq(st.winners, { "Twiz", "Frostie" })
      A.eq(st.text, "7 deaths")
      A.eq(st.streak, nil)
      A.ok(st.line:find("Frostie", 1, true), "the winners are drawn")
      ns.AwardsShow.next()
      A.eq(state(ns).index, 1, "a click at the reveal does nothing either")
      card(W, ns, "Frostie", { id = id, i = "2", k = "award", a = "medic", w = "Frostie", x = "2 rezzes", s = "3" })
      A.eq(state(ns).phase, "badge")
      card(W, ns, "Frostie", { id = id, i = "2", k = "award", a = "medic", w = "Frostie", x = "2 rezzes", s = "3",
        r = "1" })
      st = state(ns)
      A.eq(st.phase, "reveal", "r = 1 jumps to the reveal")
      A.eq(st.index, 2)
      A.eq(st.streak, "and for the 3rd session in a row")
      card(W, ns, "Frostie", { id = id, i = "3", k = "end" })
      st = state(ns)
      A.eq(st.phase, "end"); A.eq(st.hint, "Click or press Space to close")
      ns.AwardsShow.next()
      A.no(ns.AwardsShow.isOpen(), "a click at the end card closes it")
      W:advance(5)
      A.eq(#sentOf(ns, W, mark, "AWX"), 0, "a viewer never sends")
      A.eq(#sentOf(ns, W, mark, "AWC"), 0)
      card(W, ns, "Frostie", { id = id, i = "3", k = "end" })
      A.no(ns.AwardsShow.isOpen(), "a card after closing does not open it again")
      A.eq(ns.Log.errors(10), {})
    end,

    viewer_nobody_card_and_all_time_header = function(ns, A, W)
      local id = frostieShow(ns, W, "all")
      A.eq(state(ns).header, "TwizCrew Awards: all time")
      card(W, ns, "Frostie", { id = id, i = "1", k = "nobody" })
      A.eq(state(ns).phase, "nobody")
      A.eq(state(ns).hint, "Frostie is presenting")
    end,

    presenter_closing_closes_viewers = function(ns, A, W)
      local mark = #W.sent
      local id = frostieShow(ns, W)
      card(W, ns, "Frostie", { id = id, i = "1", k = "nobody" })
      receive(W, ns, "Frostie", "AWX", { id = "Other-1" })
      A.ok(ns.AwardsShow.isOpen(), "another show's AWX")
      receive(W, ns, "Frostie", "AWX", { id = id })
      A.no(ns.AwardsShow.isOpen())
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-2", v = "session" })
      A.ok(ns.AwardsShow.isOpen(), "a new show opens")
      ns.AwardsShow.close() -- Escape: closes only my window
      W:advance(5)
      A.eq(#sentOf(ns, W, mark, "AWX"), 0, "Escape sends nothing")
    end,

    viewer_setting_off_or_stats_off = function(ns, A, W)
      start(ns, W)
      hello(W, ns, "Frostie")
      ns.Modules.set("stats", "crewShow", false)
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-1", v = "session" })
      A.no(ns.AwardsShow.isOpen(), "setting off")
      ns.Modules.set("stats", "crewShow", true)
      ns.Modules.setEnabled("stats", false)
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-2", v = "session" })
      A.no(ns.AwardsShow.isOpen(), "stats off")
      ns.Modules.setEnabled("stats", true)
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-3", v = "session" })
      A.ok(ns.AwardsShow.isOpen(), "both on")
    end,

    viewer_ignores_strangers_and_fakes = function(ns, A, W)
      start(ns, W)
      receive(W, ns, "Stranger", "AWS", { id = "Stranger-1", v = "session" })
      A.no(ns.AwardsShow.isOpen(), "not in the crew")
      for _, text in ipairs(ns.Codec.encode("AWS", { id = "Bob (test)-1", v = "session" })) do
        ns.Comm.inject("Bob (test)", text)
      end
      A.no(ns.AwardsShow.isOpen(), "a fake crew member")
    end,

    viewer_in_a_fight_catches_up = function(ns, A, W)
      start(ns, W)
      hello(W, ns, "Frostie")
      W.state.combat = true
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-1", v = "session" })
      A.no(ns.AwardsShow.isOpen(), "not opened in a fight")
      card(W, ns, "Frostie", { id = "Frostie-1", i = "1", k = "award", a = "corpse", w = "Frostie", x = "7 deaths" })
      card(W, ns, "Frostie", { id = "Frostie-1", i = "2", k = "award", a = "medic", w = "Frostie", x = "2 rezzes" })
      A.no(ns.AwardsShow.isOpen())
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      local st = state(ns)
      A.ok(ns.AwardsShow.isOpen(), "the fight is over")
      A.eq(st.role, "viewer"); A.eq(st.index, 2); A.eq(st.phase, "reveal", "straight to the latest card's reveal")
      A.eq(st.title, "Medic")
      ns.AwardsShow.close()
      -- the show closed during the fight: nothing opens afterwards
      W.state.combat = true
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-2", v = "session" })
      receive(W, ns, "Frostie", "AWX", { id = "Frostie-2" })
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.no(ns.AwardsShow.isOpen(), "AWX during the fight")
      -- only the start seen: it opens loading
      W.state.combat = true
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-3", v = "session" })
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.ok(ns.AwardsShow.isOpen())
      A.eq(state(ns).phase, "loading")
      A.eq(ns.Log.errors(10), {})
    end,

    viewer_idle_show_closes = function(ns, A, W)
      local id = frostieShow(ns, W)
      card(W, ns, "Frostie", { id = id, i = "1", k = "nobody" })
      W:advance(59)
      A.ok(ns.AwardsShow.isOpen())
      card(W, ns, "Frostie", { id = id, i = "2", k = "end" })
      W:advance(59)
      A.ok(ns.AwardsShow.isOpen(), "a card restarts the clock")
      W:advance(2)
      A.no(ns.AwardsShow.isOpen(), "61 s of silence")
      -- waiting in a fight also gives up after 60 s
      W.state.combat = true
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-2", v = "session" })
      W:advance(61)
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.no(ns.AwardsShow.isOpen(), "the presenter went quiet during the fight")
    end,

    second_show_is_ignored = function(ns, A, W)
      local id = frostieShow(ns, W)
      hello(W, ns, "Lurabe", "ROGUE")
      receive(W, ns, "Lurabe", "AWS", { id = "Lurabe-1", v = "all" })
      card(W, ns, "Lurabe", { id = "Lurabe-1", i = "1", k = "nobody" })
      card(W, ns, "Lurabe", { id = id, i = "1", k = "nobody" })
      local st = state(ns)
      A.eq(st.header, "TwizCrew Awards: Frostie's show")
      A.eq(st.phase, "loading", "only Frostie's cards for Frostie's show")
    end,

    presenter_ignores_other_shows = function(ns, A, W)
      crewNight(ns, W)
      ns.AwardsShow.start("session")
      W:advance(5)
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-1", v = "session" })
      card(W, ns, "Frostie", { id = "Frostie-1", i = "1", k = "nobody" })
      local st = state(ns)
      A.eq(st.role, "presenter")
      A.eq(st.phase, "badge")
      A.eq(st.header, "TwizCrew Awards: this session")
    end,

    starting_again_restarts_the_idle_clock = function(ns, A, W)
      crewNight(ns, W)
      ns.AwardsShow.start("session")
      W:advance(5 + 57) -- the first card's idle clock ends 3 s from now
      ns.AwardsShow.start("all")
      W:advance(4) -- still loading the new show
      A.ok(ns.AwardsShow.isOpen(), "the old show's clock does not close the new one")
    end,

    many_tied_winners_fit_one_message = function(ns, A, W)
      start(ns, W)
      local L = ns.ShowLogic
      local winners = {}
      for i = 1, 20 do winners[i] = "Longername" .. string.char(96 + i) .. "xx" end
      winners[21] = "Bob (test)"
      local def = ns.StatsDefs.AWARDS[1]
      local c = { kind = "award", award = { def = def, winners = winners, text = "8 deaths" } }
      local f = L.cardToWire("Twiz-1700000000", 7, c, nil, true)
      local pieces = ns.Codec.encode("AWC", f, { repeatKeys = { "id", "i" } })
      A.eq(#pieces, 1, "one piece")
      local got = ns.Codec.decode(pieces[1]).fields
      A.eq(got.w, f.w, "w is not cut")
      A.eq(got.x, "8 deaths"); A.eq(got.r, "1")
      local sent = L.cardFromWire(got)
      A.ok(#sent.winners < 20)
      A.eq(#sent.winners + tonumber(got.m), 20, "the rest are counted; the fake one is left out")
      A.eq(sent.more, tonumber(got.m))
      for i, name in ipairs(sent.winners) do A.eq(name, winners[i]) end
      -- few winners: no m
      f = L.cardToWire("Twiz-1", 1, { kind = "award", award = { def = def, winners = { "Twiz", "Bob (test)" },
        text = "1 death" } })
      A.eq(f.w, "Twiz", "fake crew members are never sent"); A.eq(f.m, nil)
      -- the viewer shows "and N more"
      hello(W, ns, "Frostie")
      receive(W, ns, "Frostie", "AWS", { id = "Frostie-1", v = "session" })
      got.id = "Frostie-1"
      card(W, ns, "Frostie", got)
      local st = state(ns)
      A.eq(st.phase, "reveal")
      A.eq(st.more, tonumber(got.m))
      A.ok(st.line:find("and " .. got.m .. " more", 1, true), st.line)
    end,

    streak_must_be_a_number = function(ns, A)
      local L = ns.ShowLogic
      local c = { kind = "award", award = { def = ns.StatsDefs.AWARDS[1], winners = { "Twiz" }, text = "1" } }
      A.eq(L.cardToWire("Twiz-1", 1, c, "3").s, "3")
      A.eq(L.cardToWire("Twiz-1", 1, c, "nope").s, nil)
      A.eq(L.cardToWire("Twiz-1", 1, c, {}).s, nil)
    end,

    viewer_names_escaped_once = function(ns, A, W)
      local id = frostieShow(ns, W)
      card(W, ns, "Frostie", { id = id, i = "1", k = "award", a = "corpse", w = "Fro|stie", x = "a|b", r = "1" })
      local st = state(ns)
      A.eq(st.winners, { "Fro||stie" })
      A.ok(st.line:find("Fro||stie", 1, true) and not st.line:find("Fro||||stie", 1, true), st.line)
      A.eq(st.number, "a||b")
    end,
  },
}
