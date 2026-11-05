-- Crew session: pure rules (SessionLogic) and the always-running runtime (Session).
-- One suite with the full TOC: the pure tests only use ns.SessionLogic, the runtime tests boot the addon.

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function receive(W, sender, msgType, fields, ns)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- decoded messages sent since index `from`
local function sentSince(ns, W, from)
  local out = {}
  for i = from + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg then out[#out + 1] = msg end
  end
  return out
end

local function auto(id, start) return { id = id, start = start, manual = false } end
local function manual(id, start) return { id = id, start = start, manual = true } end

-- Boots, lets the 20 s decision happen alone, and records every SESSION_CHANGED.
local function bootDecided(ns, W)
  local changes = {}
  boot(W)
  ns.Bus.on("test", "SESSION_CHANGED", function(new, old, keep)
    changes[#changes + 1] = { new = new, old = old, keep = keep }
  end)
  W:advance(21)
  return changes
end

return {
  files = "toc",
  tests = {
    wire_roundtrip = function(ns, A)
      local S = ns.SessionLogic
      A.eq({ S.toWire({ id = "Twiz-100", start = 100, manual = true }) }, { "Twiz-100", "100m" })
      A.eq({ S.toWire({ id = "Twiz-100", start = 100, manual = false }) }, { "Twiz-100", "100" })
      A.eq({ S.toWire(nil) }, { "", "" })
      A.eq(S.fromWire("Twiz-100", "100m"), { id = "Twiz-100", start = 100, manual = true })
      A.eq(S.fromWire("Twiz-100", "100"), { id = "Twiz-100", start = 100, manual = false })
      A.eq(S.fromWire("", "1"), nil)
      A.eq(S.fromWire("a", "x"), nil)
      A.eq(S.fromWire(nil, "1"), nil)
      A.eq(S.fromWire(5, "1"), nil)
      A.eq(S.fromWire("a", ""), nil)
      A.eq(S.fromWire("a", nil), nil)
      A.eq(S.fromWire("a", "-4"), nil)
      A.eq(S.fromWire("a", "1e999"), nil)
      A.eq(S.fromWire("a", "1mm"), nil)
      A.eq(S.fromWire("a", string.rep("9", 300)), nil)
    end,

    better_rules = function(ns, A)
      local S = ns.SessionLogic
      local a100, a200 = auto("A-100", 100), auto("B-200", 200)
      local m200, m300 = manual("C-200", 200), manual("D-300", 300)
      A.eq(S.better(m200, a100), m200)
      A.eq(S.better(a100, m200), m200)
      A.eq(S.better(m300, m200), m300)
      A.eq(S.better(m200, m300), m300)
      A.eq(S.better(a100, a200), a100)
      A.eq(S.better(a200, a100), a100)
      A.eq(S.better(nil, a100), a100)
      A.eq(S.better(a100, nil), a100)
      A.eq(S.better(nil, nil), nil)
      local x, y = auto("X-5", 5), auto("Y-5", 5)
      A.ok(S.better(x, y) == x and S.better(y, x) == x, "equal start: smaller id wins")
    end,

    new_session_and_starter = function(ns, A)
      local S = ns.SessionLogic
      A.eq(S.newSession("Twiz", 123, false), { id = "Twiz-123", start = 123, manual = false })
      A.eq(S.newSession("Twiz", 123, true), { id = "Twiz-123", start = 123, manual = true })
      A.eq(ns.Session.starter({ id = "Holy-bøi-123" }), "Holy-bøi")
      A.eq(ns.Session.starter({ id = "Twiz-1700000000" }), "Twiz")
      A.eq(ns.Session.starter(nil), nil)
    end,

    at_login_cases = function(ns, A)
      local S = ns.SessionLogic
      local s, keep = S.atLogin(nil, {}, 10000, "Twiz", 1800)
      A.eq(s, { id = "Twiz-10000", start = 10000, manual = false }); A.eq(keep, false)

      local own = { id = "Twiz-9000", start = 9000, lastActive = 9500 }
      s, keep = S.atLogin(own, {}, 10000, "Twiz", 1800)
      A.eq(s.id, "Twiz-9000"); A.eq(keep, true)

      s, keep = S.atLogin({ id = "Twiz-6000", start = 6000, lastActive = 7000 }, {}, 10000, "Twiz", 1800)
      A.eq(s, { id = "Twiz-10000", start = 10000, manual = false }); A.eq(keep, false)

      s, keep = S.atLogin(own, { auto("Frostie-9800", 9800) }, 10000, "Twiz", 1800)
      A.eq(s.id, "Twiz-9000"); A.eq(keep, true)

      s, keep = S.atLogin(own, { auto("Frostie-8000", 8000) }, 10000, "Twiz", 1800)
      A.eq(s.id, "Frostie-8000"); A.eq(keep, true)

      s, keep = S.atLogin(own, { manual("Frostie-9900", 9900) }, 10000, "Twiz", 1800)
      A.eq(s.id, "Frostie-9900"); A.eq(keep, false)

      -- nothing of mine to continue: joining a friend's session starts my counts fresh
      s, keep = S.atLogin(nil, { auto("Frostie-8000", 8000) }, 10000, "Twiz", 1800)
      A.eq(s.id, "Frostie-8000"); A.eq(keep, false)

      -- my own hand-started session continues with its counts
      s, keep = S.atLogin({ id = "Twiz-9000", start = 9000, manual = true, lastActive = 9500 },
        { auto("Frostie-8000", 8000) }, 10000, "Twiz", 1800)
      A.eq(s.id, "Twiz-9000"); A.eq(keep, true)

      -- broken saved data is ignored
      s, keep = S.atLogin({ id = "Twiz-9000", start = 9000, lastActive = "soon" }, {}, 10000, "Twiz", 1800)
      A.eq(s.id, "Twiz-10000"); A.eq(keep, false)
    end,

    switch_rules = function(ns, A)
      local S = ns.SessionLogic
      local A100, B50 = auto("A-100", 100), auto("B-50", 50)
      local s, changed, keep = S.switch(A100, B50)
      A.eq(s, B50); A.eq(changed, true); A.eq(keep, true)
      s, changed = S.switch(B50, A100)
      A.eq(s, B50); A.eq(changed, false)

      local M10 = manual("M-10", 10)
      s, changed, keep = S.switch(A100, M10)
      A.eq(s, M10); A.eq(changed, true); A.eq(keep, false)

      local M20 = manual("N-20", 20)
      s, changed, keep = S.switch(M10, M20)
      A.eq(s, M20); A.eq(changed, true); A.eq(keep, false)

      s, changed = S.switch(A100, auto("A-100", 100))
      A.eq(s, A100); A.eq(changed, false)
      s, changed = S.switch(A100, nil)
      A.eq(s, A100); A.eq(changed, false)
    end,

    first_login_alone_starts_session = function(ns, A, W)
      boot(W)
      local loginWall = ns.wallclock()
      W:advance(19)
      A.eq(ns.Session.current(), nil)
      A.no(ns.Session.decided())
      A.eq({ ns.Session.wire() }, { "", "" })
      local n = #W.sent
      W:advance(2)
      A.ok(ns.Session.decided())
      local s = ns.Session.current()
      local id = "Twiz-" .. (loginWall + 20)
      A.eq(s, { id = id, start = loginWall + 20, manual = false })
      W:advance(1) -- the 1 s self flush plus the send queue's pump
      local found = false
      for _, m in ipairs(sentSince(ns, W, n)) do
        if m.type == "UPDATE" and m.fields.sid == id and m.fields.sst == tostring(loginWall + 20) then found = true end
      end
      A.ok(found, "an UPDATE with sid and sst went out")
      A.eq(ns.db.stats.session.id, id)
      A.eq(ns.db.stats.session.start, loginWall + 20)
      A.eq(ns.db.stats.session.manual, false)
      A.eq(type(ns.db.stats.session.lastActive), "number")
      A.eq(ns.Log.errors(10), {})
      for _, line in ipairs(W.printed) do A.no(line:find(id, 1, true), "session id never shows in chat") end
    end,

    joins_friend_session_heard_at_login = function(ns, A, W)
      boot(W)
      W:advance(3)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", sid = "Frostie-123", sst = "123" }, ns)
      W:advance(18)
      A.eq(ns.Session.current(), { id = "Frostie-123", start = 123, manual = false })
      A.eq({ ns.Session.wire() }, { "Frostie-123", "123" })
      A.eq(ns.Session.starter(ns.Session.current()), "Frostie")
    end,

    offline_friends_do_not_count_at_login = function(ns, A, W)
      boot(W)
      W:advance(3)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", sid = "Frostie-123", sst = "123" }, ns)
      receive(W, "Frostie", "BYE", {}, ns)
      W:advance(18)
      A.eq(ns.Session.current().id, "Twiz-" .. ns.Session.current().start)
    end,

    hello_forgets_their_session = function(ns, A, W)
      boot(W)
      W:advance(3)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", sid = "Frostie-123", sst = "123" }, ns)
      W:advance(1)
      receive(W, "Frostie", "HELLO", { ver = "0.1.0" }, ns)
      W:advance(17)
      A.eq(ns.Session.starter(ns.Session.current()), "Twiz")
    end,

    two_auto_sessions_converge_to_older = function(ns, A, W)
      local changes = bootDecided(ns, W)
      local mine = ns.Session.current()
      A.eq(ns.Session.starter(mine), "Twiz")
      A.eq(#changes, 1)
      A.eq(changes[1].new.id, mine.id); A.eq(changes[1].old, nil); A.eq(changes[1].keep, false)
      local n = #W.sent
      receive(W, "Frostie", "UPDATE", { sid = "Frostie-1", sst = "1" }, ns)
      A.eq(ns.Session.current(), { id = "Frostie-1", start = 1, manual = false })
      A.eq(#changes, 2)
      A.eq(changes[2].new.id, "Frostie-1"); A.eq(changes[2].old.id, mine.id); A.eq(changes[2].keep, true)
      A.eq(ns.db.stats.session.id, "Frostie-1")
      W:advance(2)
      local found = false
      for _, m in ipairs(sentSince(ns, W, n)) do
        if m.type == "UPDATE" and m.fields.sid == "Frostie-1" and m.fields.sst == "1" then found = true end
      end
      A.ok(found, "we tell the crew we moved")
      -- hearing the same session again changes nothing
      receive(W, "Frostie", "UPDATE", { sid = "Frostie-1", sst = "1", st = "x" }, ns)
      A.eq(#changes, 2)
    end,

    manual_session_wins_and_resets = function(ns, A, W)
      local changes = bootDecided(ns, W)
      local before = ns.Session.current()
      local s = ns.Session.newByHand()
      A.eq(s.manual, true)
      A.eq(ns.Session.current(), s)
      A.eq(ns.Session.starter(s), "Twiz")
      A.eq(changes[#changes].old.id, before.id); A.eq(changes[#changes].keep, false)
      A.eq(ns.db.stats.session.manual, true)
      A.eq(select(2, ns.Session.wire()), tostring(s.start) .. "m")
      local count = #changes
      receive(W, "Frostie", "UPDATE", { sid = "Frostie-1", sst = "1" }, ns)
      A.eq(ns.Session.current().id, s.id)
      A.eq(#changes, count)
      receive(W, "Frostie", "UPDATE", { sid = "Frostie-9999999999", sst = "9999999999m" }, ns)
      A.eq(ns.Session.current(), { id = "Frostie-9999999999", start = 9999999999, manual = true })
      A.eq(#changes, count + 1)
      A.eq(changes[#changes].keep, false)
    end,

    by_hand_before_the_decision = function(ns, A, W)
      local changes = {}
      boot(W)
      ns.Bus.on("test", "SESSION_CHANGED", function(new, old, keep)
        changes[#changes + 1] = { new = new, old = old, keep = keep }
      end)
      W:advance(5)
      local s = ns.Session.newByHand()
      A.ok(ns.Session.decided())
      A.eq(#changes, 1); A.eq(changes[1].old, nil); A.eq(changes[1].keep, false)
      W:advance(20)
      A.eq(#changes, 1, "the timer does nothing once decided")
      A.eq(ns.Session.current(), s)
    end,

    split_fields_merge = function(ns, A, W)
      local changes = bootDecided(ns, W)
      local mine = ns.Session.current()
      receive(W, "Frostie", "UPDATE", { sid = "Frostie-5" }, ns)
      A.eq(ns.Session.current().id, mine.id)
      receive(W, "Frostie", "UPDATE", { sst = "5" }, ns)
      A.eq(ns.Session.current(), { id = "Frostie-5", start = 5, manual = false })
      A.eq(#changes, 2)
    end,

    garbage_session_fields_are_ignored = function(ns, A, W)
      local changes = bootDecided(ns, W)
      local mine = ns.Session.current()
      for _, f in ipairs({ { sid = "", sst = "1" }, { sid = "Frostie-1", sst = "abc" }, { sst = "-4" },
        { sst = "1e999" }, { sst = string.rep("9", 200) } }) do
        receive(W, "Frostie", "UPDATE", f, ns)
      end
      A.eq(ns.Session.current().id, mine.id)
      A.eq(#changes, 1)
      A.eq(ns.Log.errors(10), {})
    end,

    resume_after_reload = function(ns, A, W)
      local changes = {}
      boot(W, function()
        ns.db.stats.session = { id = "Twiz-1", start = 1, manual = true, lastActive = ns.wallclock() - 600 }
        ns.Bus.on("test", "SESSION_CHANGED", function(new, old, keep)
          changes[#changes + 1] = { new = new, old = old, keep = keep }
        end)
      end)
      W:advance(21)
      A.eq(ns.Session.current(), { id = "Twiz-1", start = 1, manual = true })
      A.eq(#changes, 1)
      A.eq(changes[1].old.id, "Twiz-1"); A.eq(changes[1].keep, true)
      A.ok(ns.db.stats.session.lastActive >= ns.wallclock() - 1)
    end,

    stale_saved_session_starts_new = function(ns, A, W)
      boot(W, function()
        ns.db.stats.session = { id = "Twiz-1", start = 1, manual = true, lastActive = ns.wallclock() - 4000 }
      end)
      W:advance(21)
      A.ok(ns.Session.current().id ~= "Twiz-1")
      A.eq(ns.Session.current().manual, false)
    end,

    active_time_is_saved = function(ns, A, W)
      bootDecided(ns, W)
      local t0 = ns.db.stats.session.lastActive
      W:advance(61)
      A.ok(ns.db.stats.session.lastActive > t0, "ticker saves lastActive")
      W:advance(10)
      W:fire("PLAYER_LOGOUT")
      A.eq(ns.db.stats.session.lastActive, ns.wallclock())
    end,

    start_is_idempotent = function(ns, A, W)
      local changes = bootDecided(ns, W)
      ns.Session.start()
      W:advance(30)
      A.eq(#changes, 1)
      ns.Session.forTest.decideNow()
      A.eq(#changes, 1, "deciding again does nothing")
    end,
  },
}
