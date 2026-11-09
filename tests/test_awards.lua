-- Awards show (stats Task 9): /tc awards window, its cards and phases, the fight and stats-off refusals, sounds.
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
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function hello(W, ns, name, class)
  receive(W, ns, name, "STATE", { ver = "0.1.0", cl = class or "MAGE", lv = "20", zn = "Elwynn Forest", sz = "",
    lk = "", ins = "0" })
end

local function countType(ns, W, from, msgType)
  local n = 0
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then n = n + 1 end
  end
  return n
end

local function printedLine(W, text)
  for _, line in ipairs(W.printed) do if line == text then return true end end
  return false
end

local function state(ns) return ns.AwardsShow.stateForTest() end

return {
  files = "toc",
  tests = {
    show_walks_through_cards = function(ns, A, W)
      start(ns, W)
      local S = ns.Session.current().id
      hello(W, ns, "Frostie")
      receive(W, ns, "Frostie", "STATS", { sid = S, q = "1", s_rz = "2", a_rz = "2" })
      ns.Stats.count("dt", 7)
      local mark = #W.sent
      ns.AwardsShow.start("session")
      A.ok(ns.AwardsShow.isOpen())
      A.eq(state(ns).phase, "loading")
      A.eq(state(ns).title, "Getting the latest numbers…")
      W:advance(1)
      A.eq(countType(ns, W, mark, "STATSREQ"), 1, "asks the crew for fresh numbers")
      ns.AwardsShow.next()
      A.eq(state(ns).phase, "loading", "next() does nothing while loading")
      W:advance(4)
      local s = state(ns)
      A.eq(s.phase, "badge")
      A.eq(s.title, "Professional Corpse")
      A.eq(s.index, 1)
      A.eq(s.count, 4, "three awards (Pauper: my gold) and the end card")
      W:advance(0.6)
      A.eq(state(ns).phase, "drum")
      A.eq(state(ns).text, "and the award goes to…")
      W:advance(1.5)
      s = state(ns)
      A.eq(s.phase, "reveal")
      A.eq(s.winners, { "Twiz" })
      A.eq(s.text, "7 deaths")
      ns.AwardsShow.next()
      s = state(ns)
      A.eq(s.phase, "badge")
      A.eq(s.title, "Pauper", "my gold carried makes the Pauper card")
      ns.AwardsShow.next()
      A.eq(state(ns).phase, "reveal")
      A.eq(state(ns).winners, { "Twiz" })
      ns.AwardsShow.next()
      s = state(ns)
      A.eq(s.phase, "badge")
      A.eq(s.title, "Medic", "medic last")
      ns.AwardsShow.next()
      s = state(ns)
      A.eq(s.phase, "reveal", "next() before the reveal jumps to it")
      A.eq(s.winners, { "Frostie" })
      A.eq(s.text, "2 rezzes")
      W:advance(5)
      A.eq(state(ns).phase, "reveal", "old timers do nothing after a jump")
      A.eq(state(ns).title, "Medic")
      ns.AwardsShow.next()
      s = state(ns)
      A.eq(s.phase, "end")
      A.eq(s.text, "That's the show. GG crew.")
      A.eq(s.index, 4)
      ns.AwardsShow.next()
      A.no(ns.AwardsShow.isOpen(), "next() on the end card closes")
      A.eq(ns.Log.errors(10), {})
    end,

    show_skips_empty_and_handles_nobody = function(ns, A, W)
      start(ns, W)
      ns.AwardsShow.start("session")
      W:advance(5)
      local s = state(ns)
      A.eq(s.phase, "badge", "the only card is Pauper: my gold is counted from the start")
      A.eq(s.title, "Pauper")
      A.eq(s.count, 2)
      ns.AwardsShow.next()
      ns.AwardsShow.next()
      A.eq(state(ns).phase, "end")
      ns.AwardsShow.close()
      A.no(ns.AwardsShow.isOpen())
      W:advance(10)
      A.no(ns.AwardsShow.isOpen(), "closing stops the timers")
      A.eq(ns.Log.errors(10), {})
    end,

    show_refuses_in_fight_and_when_off = function(ns, A, W)
      start(ns, W)
      W.state.combat = true
      ns.AwardsShow.start("session")
      A.ok(printedLine(W, "TwizCrew: the awards show waits until the fight is over."))
      A.no(ns.AwardsShow.isOpen())
      W.state.combat = false
      W.env.InCombatLockdown = function() return true end
      ns.AwardsShow.start("session")
      A.no(ns.AwardsShow.isOpen(), "combat lockdown also refuses")
      W.env.InCombatLockdown = function() return false end
      ns.Modules.setEnabled("stats", false)
      ns.AwardsShow.start("all")
      A.ok(printedLine(W, "TwizCrew: turn on Stats & Hall of Shame in /tc first."))
      A.no(ns.AwardsShow.isOpen())
      ns.Modules.setEnabled("stats", true)
      ns.AwardsShow.start("all")
      A.ok(ns.AwardsShow.isOpen())
    end,

    show_all_time_uses_all_numbers = function(ns, A, W)
      start(ns, W)
      hello(W, ns, "Frostie")
      receive(W, ns, "Frostie", "STATS", { sid = "Frostie-123", q = "1", s_dt = "9", a_dt = "9" })
      ns.Stats.count("dt", 7)
      ns.AwardsShow.start("all")
      W:advance(5 + 0.6 + 1.5)
      local s = state(ns)
      A.eq(s.phase, "reveal")
      A.eq(s.title, "Professional Corpse")
      A.eq(s.winners, { "Frostie" })
      A.eq(s.text, "9 deaths")
      ns.AwardsShow.close()
      ns.AwardsShow.start("session")
      W:advance(5 + 0.6 + 1.5)
      A.eq(state(ns).winners, { "Twiz" }, "Frostie is in another session")
    end,

    sounds_follow_setting = function(ns, A, W)
      start(ns, W)
      ns.Stats.count("dt", 1)
      local before = #W.sounds
      ns.AwardsShow.start("session")
      W:advance(5)
      A.eq(W.sounds[#W.sounds], 8960, "badge sound (no READY_CHECK kit here: the id)")
      W:advance(2.1)
      A.eq(state(ns).phase, "reveal")
      A.eq(W.sounds[#W.sounds], 8959, "reveal sound from SOUNDKIT")
      A.eq(#W.sounds - before, 2)
      ns.AwardsShow.close()
      ns.Modules.set("stats", "showSound", false)
      before = #W.sounds
      ns.AwardsShow.start("session")
      W:advance(10)
      A.eq(state(ns).phase, "reveal")
      A.eq(#W.sounds, before, "no sounds with the setting off")
    end,

    key_in_combat_lockdown_closes_the_show = function(ns, A, W)
      local named = {}
      local create = W.env.CreateFrame
      W.env.CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name then named[name] = f end
        return f
      end
      start(ns, W)
      ns.Stats.count("dt", 1)
      ns.AwardsShow.start("session")
      W:advance(5)
      local f = named.TwizCrewAwards
      local propagate, hidden = {}, 0
      rawset(f, "SetPropagateKeyboardInput", function(_, on) propagate[#propagate + 1] = on end)
      local hide = f.Hide
      rawset(f, "Hide", function(self) hidden = hidden + 1; return hide(self) end)
      -- the keyboard is still ours (PLAYER_REGEN_DISABLED not seen yet) when the lockdown starts
      W.env.InCombatLockdown = function() return true end
      f._scripts.OnKeyDown(f, "SPACE")
      A.no(ns.AwardsShow.isOpen(), "the show closed")
      A.eq(hidden, 1, "the window was hidden")
      A.eq(propagate, {}, "keyboard propagation never touched in lockdown")
      W.env.InCombatLockdown = function() return false end
      A.eq(ns.Log.errors(10), {})
    end,

    keyboard_and_names_are_safe = function(ns, A, W)
      local named = {}
      local create = W.env.CreateFrame
      W.env.CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name then named[name] = f end
        return f
      end
      start(ns, W)
      local S = ns.Session.current().id
      hello(W, ns, "Ho|ly")
      receive(W, ns, "Ho|ly", "STATS", { sid = S, q = "1", s_dt = "4", a_dt = "4" })
      ns.AwardsShow.start("session")
      W:advance(5)
      local f = named.TwizCrewAwards
      A.ok(f ~= nil, "named window")
      local special = false
      for _, n in ipairs(W.env.UISpecialFrames) do if n == "TwizCrewAwards" then special = true end end
      A.ok(special, "Escape closes it")
      local propagate = {}
      rawset(f, "SetPropagateKeyboardInput", function(_, on) propagate[#propagate + 1] = on end)
      f._scripts.OnKeyDown(f, "SPACE")
      A.eq(state(ns).phase, "reveal", "Space jumps to the reveal")
      A.eq(state(ns).winners, { "Ho|ly" })
      f._scripts.OnKeyDown(f, "ESCAPE")
      A.eq(propagate, { false, true }, "only Space is kept")
      A.eq(state(ns).phase, "reveal")
      local keyboard
      rawset(f, "EnableKeyboard", function(_, on) keyboard = on end)
      W:fire("PLAYER_REGEN_DISABLED")
      A.eq(keyboard, false, "a fight gives the keyboard back")
      W:fire("PLAYER_REGEN_ENABLED")
      A.eq(keyboard, true)
      f._scripts.OnMouseDown(f, "LeftButton")
      f._scripts.OnMouseUp(f, "LeftButton")
      A.eq(state(ns).phase, "badge", "a click goes to the next card (Pauper)")
      f._scripts.OnHide(f)
      A.no(ns.AwardsShow.isOpen(), "Escape (hide) closes")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
