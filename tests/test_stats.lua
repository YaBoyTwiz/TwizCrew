-- Stats module (counting): saved numbers (StatsStore), guarded detectors (Detectors) and the module glue (Stats).
-- Full TOC boot; ns.Roasts does not exist until a later task, so every test installs a recording stand-in.

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

-- Boots with a recording ns.Roasts and lets the session be decided (that resets session counts once);
-- returns the list of roasts sent ({ kind, v, x } each).
local function start(ns, W, before)
  local roasts = {}
  ns.Roasts = { send = function(kind, v, x) roasts[#roasts + 1] = { kind, v, x } end }
  boot(W, before)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
  return roasts
end

local function get(ns, view, key) return ns.StatsStore.get(view, key) end

local function near(A, actual, expected, tolerance, msg)
  A.ok(math.abs(actual - expected) <= tolerance,
    (msg or "value") .. ": expected about " .. expected .. ", got " .. tostring(actual))
end

local function statusOf(ns, id)
  for _, s in ipairs(ns.Detectors.status()) do
    if s.id == id then return s end
  end
end

local function kinds(roasts, kind)
  local n = 0
  for _, r in ipairs(roasts) do if r[1] == kind then n = n + 1 end end
  return n
end

local function die(W)
  W.state.dead = true
  W:fire("PLAYER_DEAD")
end

local function revive(W)
  W.state.dead = false
  W:fire("PLAYER_ALIVE")
end

local GREY = "You receive loot: |cff9d9d9d|Hitem:2211::::::::1:::::::|h[Broken Fang]|h|r."

return {
  files = "toc",
  tests = {
    set_and_distinct_numbers = function(ns, A, W)
      start(ns, W)
      local S = ns.StatsStore
      S.markSent()
      A.eq(S.set("gn", 500), true)
      A.eq(get(ns, "session", "gn"), 500)
      A.eq(get(ns, "all", "gn"), 500, "the same number in both views")
      A.ok(S.dirty())
      S.markSent()
      A.eq(S.set("gn", 500), false, "no change: not dirty")
      A.no(S.dirty())
      A.eq(S.set("gn", 0), true, "0 gold is a real value")
      A.eq(get(ns, "session", "gn"), 0)
      A.eq(S.set("dt", 9), false, "only set keys can be set")
      -- zones: counted once per view
      A.eq(S.addZone("Elwynn Forest"), true)
      A.eq(S.addZone("Elwynn Forest"), false)
      A.eq(S.addZone("Westfall"), true)
      A.eq(get(ns, "session", "zv"), 2)
      A.eq(get(ns, "all", "zv"), 2)
      A.eq(S.addZone(""), false)
      -- a new session: session zones start over, all time keeps them
      S.setSession("Ginkan-1", nil, false)
      A.eq(get(ns, "session", "zv"), 0)
      A.eq(S.addZone("Westfall"), true, "new this session")
      A.eq(get(ns, "session", "zv"), 1)
      A.eq(get(ns, "all", "zv"), 2, "not new for all time")
      A.eq(get(ns, "session", "gn"), 0, "gold carried is gone until set again")
    end,
    store_rules = function(ns, A, W)
      start(ns, W)
      local S = ns.StatsStore
      local rec = S.mine()
      A.eq(type(rec.s), "table")
      A.ok(ns.db.stats.chars.Twiz == rec, "my record lives under my name")
      S.markSent()
      S.add("nope", 5)
      A.no(S.dirty(), "unknown keys are ignored")
      local pt = S.get("all", "pt")
      S.add("pt", 5)
      A.no(S.dirty(), "time played alone does not make a send due")
      A.eq(S.get("all", "pt"), pt + 5)
      S.add("ld", 7)
      S.add("ld", 3)
      S.add("ld", 9)
      A.eq(S.get("session", "ld"), 3)
      A.eq(S.get("all", "ld"), 3)
      A.ok(S.dirty())
      S.add("dt", 2)
      A.eq(S.get("session", "dt"), 2)
      A.eq(S.get("all", "dt"), 2)
      S.markSent()
      A.no(S.dirty())
      rec.sid = "A-1"
      S.setSession("A-1", nil, false)
      A.eq(S.get("session", "dt"), 2, "same session: nothing happens")
      S.setSession("B-2", "A-1", true)
      A.eq(S.get("session", "dt"), 2, "kept when moving on from my session")
      S.setSession("C-3", "X-9", true)
      A.eq(S.get("session", "dt"), 0, "keep from another session starts over")
      A.eq(S.get("all", "dt"), 2)
      A.eq(S.mine().sid, "C-3")
      local a, b = S.snapshot(), S.snapshot(true)
      A.eq(a.sid, "C-3")
      A.ok(a.q ~= b.q, "every snapshot gets a new q")
      A.eq(a.a.dt, 2)
      A.ok(b.off, "off snapshot")
      S.resetMine()
      A.eq(S.get("all", "dt"), 0)
      A.eq(S.get("session", "ld"), 0)
    end,

    steps_by_speed_split_by_mode = function(ns, A, W)
      start(ns, W)
      local st = W.state
      st.speed = 7
      W:advance(10)
      near(A, get(ns, "all", "st"), 7 * 10 * 1.2, 1.2, "steps")
      near(A, get(ns, "session", "st"), 7 * 10 * 1.2, 1.2, "session steps")
      A.eq(ns.Detectors.stepsMethod(), "speed")
      local steps = get(ns, "all", "st")
      st.mounted = true
      W:advance(10)
      near(A, get(ns, "all", "mt"), 70, 7, "mounted yards")
      A.eq(get(ns, "all", "st"), steps, "no steps while mounted")
      st.mounted, st.swimming = false, true
      W:advance(10)
      near(A, get(ns, "all", "sw"), 70, 7, "swum yards")
      st.swimming, st.taxi = false, true
      local mt, sw = get(ns, "all", "mt"), get(ns, "all", "sw")
      W:advance(10)
      A.eq({ get(ns, "all", "st"), get(ns, "all", "mt"), get(ns, "all", "sw") }, { steps, mt, sw }, "taxi")
      st.taxi = false
      A.ok(ns.Modules.set("stats", "countSteps", false))
      W:advance(10)
      A.eq(get(ns, "all", "st"), steps, "count steps off")
      A.eq(ns.Detectors.stepsMethod(), "off")
      A.ok(ns.Modules.set("stats", "countSteps", true))
      W:advance(2)
      A.ok(get(ns, "all", "st") > steps, "counts again")
      A.eq(ns.Log.errors(10), {})
    end,

    position_fallback = function(ns, A, W)
      start(ns, W, function() W.state.missing.GetUnitSpeed = true end)
      local st = W.state
      st.pos = { x = 100, y = 100, instance = 0 }
      for _ = 1, 20 do
        W:advance(0.5)
        st.pos = { x = st.pos.x + 3, y = 100, instance = 0 }
      end
      A.eq(ns.Detectors.stepsMethod(), "position")
      near(A, get(ns, "all", "st"), 19 * 3 * 1.2, 4, "steps from positions")
      local steps = get(ns, "all", "st")
      st.pos = nil
      W:advance(5)
      A.eq(get(ns, "all", "st"), steps, "no position, no steps")
      A.eq(ns.Log.errors(10), {})
      A.ok(statusOf(ns, "motion").on, "motion still on")
    end,

    timers_count_afk_dead_played = function(ns, A, W)
      start(ns, W)
      local pt0, spt0 = get(ns, "all", "pt"), get(ns, "session", "pt")
      W.state.afk = true
      W:advance(60)
      near(A, get(ns, "all", "af"), 60, 0.6, "afk")
      W.state.afk = false
      W.state.dead = true
      W:advance(10)
      near(A, get(ns, "all", "ds"), 10, 0.6, "dead")
      near(A, get(ns, "all", "af"), 60, 0.6, "afk stopped")
      near(A, get(ns, "all", "pt") - pt0, 70, 0.6, "played")
      near(A, get(ns, "session", "pt") - spt0, 70, 0.6, "played this session")
    end,

    fall_death_counts = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.falling = true
      W:advance(1.5)
      W.state.falling = false
      die(W)
      A.eq(get(ns, "session", "dt"), 1)
      A.eq(get(ns, "session", "df"), 1)
      A.eq(get(ns, "all", "df"), 1)
      A.eq(roasts, { { "fall" } })
    end,

    a_jump_is_not_a_fall = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.falling = true
      W:advance(0.5) -- one jump: seen falling for a single tick
      W.state.falling = false
      die(W)
      A.eq(get(ns, "session", "df"), 0)
      A.eq(roasts, {})
      revive(W)
      W:advance(120)
      W.state.falling = true
      W:advance(1.5)
      W.state.falling = false
      die(W)
      A.eq(get(ns, "session", "df"), 1, "a real fall")
      A.eq(roasts, { { "fall" } })
    end,

    dead_weak_target_is_not_blamed = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.level = 20
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(3)
      W.state.units.target.dead = true -- killed it; still targeted when a patrol kills me
      W:advance(2)
      die(W)
      A.eq(get(ns, "all", "dw"), 0)
      A.eq(get(ns, "all", "ld"), 0)
      A.eq(roasts, {})
      A.eq(ns.Detectors.ctx.target, nil, "forgotten at death")
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, dead = true }
      W:fire("PLAYER_TARGET_CHANGED")
      A.eq(ns.Detectors.ctx.target, nil, "a dead target is never read")
    end,

    abandon_counted_from_either_function = function(ns, A, W)
      start(ns, W)
      W.env.AbandonQuest()
      A.eq(get(ns, "all", "qa"), 1, "only the global called")
      W:advance(2)
      W.env.C_QuestLog.AbandonQuest()
      A.eq(get(ns, "all", "qa"), 2, "only the table one called")
      A.eq(W.abandoned, 2)
    end,

    abandon_wrapper_counts_once = function(ns, A, W)
      start(ns, W, function()
        W.env.AbandonQuest = function() W.env.C_QuestLog.AbandonQuest() end
      end)
      W.env.AbandonQuest()
      A.eq(get(ns, "all", "qa"), 1)
      A.eq(W.abandoned, 1)
    end,

    abandon_with_only_the_global = function(ns, A, W)
      start(ns, W, function() W.state.missing["C_QuestLog.AbandonQuest"] = true end)
      A.ok(statusOf(ns, "abandon").on)
      W.env.AbandonQuest()
      A.eq(get(ns, "all", "qa"), 1)
    end,

    repair_twice_in_one_visit = function(ns, A, W)
      start(ns, W)
      W.state.repairCost = 1000
      W:fire("MERCHANT_SHOW")
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 1000)
      W.env.RepairAllItems() -- nothing left to repair (cost 0 now): nothing counted
      W:advance(1)
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 1000)
      W:fire("MERCHANT_CLOSED")
      W.state.repairCost = 700
      W:fire("MERCHANT_SHOW")
      W.state.repairCost = 0 -- repaired item by item: the cost read earlier is stale
      W:advance(1)
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 1000, "a stale cost is not counted")
    end,

    motion_needs_taxi_and_dead_checks = function(ns, A, W)
      start(ns, W, function() W.env.UnitOnTaxi = nil end) -- a v1 fake: removed, not hidden
      local s = statusOf(ns, "motion")
      A.no(s.on)
      A.eq(s.why, "UnitOnTaxi missing")
      A.eq(ns.Detectors.stepsMethod(), "off")
      A.eq(ns.Log.errors(10), {})
    end,

    weak_mob_death = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.level = 20
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(5)
      die(W)
      A.eq(get(ns, "session", "dw"), 1)
      A.eq(get(ns, "session", "ld"), 3)
      A.eq(get(ns, "all", "dt"), 1)
      A.eq(roasts, { { "weak", 3, "Kobold Miner" } })
    end,

    friendly_or_player_targets_are_not_weak_mobs = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.level = 20
      W.state.units.target = { name = "Ginkan", level = 3, hostile = true, player = true, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      die(W)
      revive(W)
      W:advance(120)
      W.state.units.target = { name = "Stormwind Guard", level = 3, hostile = false, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      die(W)
      A.eq(get(ns, "all", "dw"), 0)
      A.eq(get(ns, "all", "dt"), 2)
      A.eq(roasts, {})
    end,

    drown_and_again = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.mirror = { { name = "BREATH" } }
      W:fire("MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
      die(W)
      W.state.mirror = {}
      W:fire("MIRROR_TIMER_STOP", "BREATH")
      A.eq(get(ns, "session", "dd"), 1)
      W:advance(30)
      revive(W)
      W:advance(40)
      die(W)
      A.eq(get(ns, "session", "dd"), 1, "breath timer stopped long ago")
      A.eq(get(ns, "session", "db"), 1)
      A.eq(get(ns, "session", "dt"), 2)
      A.eq(roasts, { { "drown" }, { "again", 40 } })
    end,

    unghost_counts_as_alive = function(ns, A, W)
      local roasts = start(ns, W)
      die(W)
      W:fire("PLAYER_ALIVE") -- released: still a ghost, not alive
      W:advance(70)
      W.state.dead = false
      W:fire("PLAYER_UNGHOST")
      W:advance(10)
      die(W)
      A.eq(get(ns, "session", "db"), 1)
      A.eq(roasts, { { "again", 10 } })
    end,

    secret_values_are_not_counted = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.speed = 7
      W.state.secret[7] = true
      W:advance(10)
      A.eq(get(ns, "all", "st"), 0, "secret speed")
      W.state.level = 20
      W.state.secret[3] = true
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      die(W)
      A.eq(get(ns, "all", "dw"), 0, "secret target level")
      A.eq(get(ns, "all", "dt"), 1)
      A.eq(roasts, {})
      W.state.secret[8690] = true
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 8690)
      A.eq(get(ns, "all", "hs"), 0, "secret spell id")
      A.eq(ns.Log.errors(10), {})
    end,

    jumps_hearth_rez_junk_repair_abandon_duel = function(ns, A, W)
      start(ns, W)
      local E, st = W.env, W.state
      E.JumpOrAscendStart()
      E.JumpOrAscendStart()
      E.JumpOrAscendStart()
      A.eq(get(ns, "all", "jp"), 3)
      A.eq(W.jumps, 3, "the game's own function still runs")
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 8690)
      A.eq(get(ns, "all", "hs"), 1)
      st.spellNames[999] = "Redemption"
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 999)
      A.eq(get(ns, "all", "rz"), 1)
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "x", 8690)
      A.eq(get(ns, "all", "hs"), 1, "someone else's cast")
      W:fire("CHAT_MSG_LOOT", GREY)
      W:fire("CHAT_MSG_LOOT", GREY)
      W:fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2589|h[Linen Cloth]|h|r.")
      A.eq(get(ns, "all", "jk"), 2)
      W:fire("MERCHANT_SHOW")
      st.repairCost = 32005
      W:advance(1)
      E.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 32005)
      st.repairCost = 500
      W:fire("UPDATE_INVENTORY_DURABILITY")
      E.RepairAllItems(true)
      A.eq(get(ns, "all", "rp"), 32005, "guild repair is free")
      W:fire("MERCHANT_CLOSED")
      E.C_QuestLog.AbandonQuest()
      A.eq(get(ns, "all", "qa"), 1)
      W:fire("CHAT_MSG_SYSTEM", "Ginkan has defeated Twiz in a duel")
      A.eq(get(ns, "all", "dl"), 1)
      W:fire("CHAT_MSG_SYSTEM", "Ginkan has fled from Twiz in a duel")
      A.eq(get(ns, "all", "dv"), 1)
      A.eq(ns.Log.errors(10), {})
    end,

    pulls_need_a_quiet_friend = function(ns, A, W)
      start(ns, W, function()
        W.state.zone, W.state.inInstance, W.state.instanceType = "The Deadmines", true, "party"
      end)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(2.1)
      A.eq(get(ns, "all", "pl"), 0, "alone: not a pull")
      receive(W, "Frostie", "STATE", { ver = "0.1.0", zn = "The Deadmines", ins = "1", tg = "" }, ns)
      W:advance(10)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(1.9)
      A.eq(get(ns, "all", "pl"), 0, "not yet: the crew gets 2 s to join in")
      W:advance(0.2)
      A.eq(get(ns, "all", "pl"), 1, "no friend fighting: a pull")
      receive(W, "Frostie", "UPDATE", { tg = "COMBAT" }, ns)
      W:advance(10)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(2.1)
      A.eq(get(ns, "all", "pl"), 1, "friend already fighting")
    end,

    pull_not_counted_when_a_friend_joins_within_2s = function(ns, A, W)
      start(ns, W, function()
        W.state.zone, W.state.inInstance, W.state.instanceType = "The Deadmines", true, "party"
      end)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", zn = "The Deadmines", ins = "1", tg = "" }, ns)
      W:advance(10)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(1.5)
      receive(W, "Frostie", "UPDATE", { tg = "COMBAT" }, ns) -- their FIGHTING arrives 1.5 s after my start
      W:advance(1)
      A.eq(get(ns, "all", "pl"), 0, "the crew was fighting too")
      -- a friend whose fight ended just before mine (inside the 2 s before my start) was not left behind either
      receive(W, "Frostie", "UPDATE", { tg = "" }, ns)
      W:advance(1)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(2.1)
      A.eq(get(ns, "all", "pl"), 0, "friend fought 1 s before my start")
      -- a long while later, with nobody fighting: a pull
      W:advance(30)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(2.1)
      A.eq(get(ns, "all", "pl"), 1)
      -- out of the dungeon: no check at all
      W.state.inInstance, W.state.instanceType = false, "none"
      W:advance(10)
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(2.1)
      A.eq(get(ns, "all", "pl"), 1)
      A.eq(ns.Log.errors(10), {})
    end,

    weak_mob_must_be_seen_in_combat = function(ns, A, W)
      local roasts = start(ns, W)
      W.state.level = 20
      -- a critter I clicked on, never fighting me, while something else kills me
      W.state.units.target = { name = "Rabbit", level = 1, hostile = true, combat = false }
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(3)
      die(W)
      A.eq(get(ns, "all", "dw"), 0, "an out-of-combat critter is not the killer")
      revive(W)
      W:advance(120)
      -- an in-combat weak mob, last seen fighting 3 s before my death
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(1)
      W.state.units.target.combat = false
      W:advance(3)
      die(W)
      A.eq(get(ns, "all", "dw"), 1, "seen in combat 3 s before death")
      A.eq(roasts[#roasts], { "weak", 3, "Kobold Miner" })
      revive(W)
      W:advance(120)
      -- one last seen in combat 15 s before my death
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(1)
      W.state.units.target.combat = false
      W:advance(15)
      die(W)
      A.eq(get(ns, "all", "dw"), 1, "seen in combat 15 s before death: too long ago")
      revive(W)
      W:advance(120)
      -- a weak mob that joins the fight after I target it is picked up by the 0.5 s tick
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = false }
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(30)
      W.state.units.target.combat = true
      W:advance(1)
      die(W)
      A.eq(get(ns, "all", "dw"), 2, "the tick saw it fighting")
      A.eq(ns.Log.errors(10), {})
    end,

    other_units_casts_skip_the_guard = function(ns, A, W)
      start(ns, W)
      local real, calls = W.env.xpcall, 0
      W.env.xpcall = function(...) calls = calls + 1; return real(...) end
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "raid7", "x", 8690)
      A.eq(calls, 1, "only the event dispatcher's own safe call")
      W.env.xpcall = real
      A.eq(get(ns, "all", "hs"), 0)
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 8690)
      A.eq(get(ns, "all", "hs"), 1, "my own cast still counts")
    end,

    drown_flag_does_not_stick = function(ns, A, W)
      local roasts = start(ns, W)
      -- a breath timer started, then the loading screen ate its stop event
      W:fire("MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
      W:fire("PLAYER_ENTERING_WORLD")
      A.eq(ns.Detectors.ctx.breathRunning, false, "reset by the loading screen")
      W:advance(30)
      die(W)
      A.eq(get(ns, "all", "dd"), 0)
      revive(W)
      W:advance(120)
      -- a loading screen while the game still shows a running breath timer: it is read back
      W.state.mirror = { { name = "UNKNOWN" }, { name = "BREATH", paused = 0 } }
      W:fire("PLAYER_ENTERING_WORLD")
      A.eq(ns.Detectors.ctx.breathRunning, true, "read back from the game")
      W.state.mirror = { { name = "EXHAUSTION", paused = 1 } }
      W:fire("PLAYER_ENTERING_WORLD")
      A.eq(ns.Detectors.ctx.breathRunning, false, "a paused timer is not running")
      -- at death the game is asked: a stop event that never came does not make a drowning
      W:fire("MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
      W.state.mirror = {}
      W:advance(30)
      die(W)
      A.eq(get(ns, "all", "dd"), 0, "no breath timer running at death")
      revive(W)
      W:advance(120)
      W.state.mirror = { { name = "EXHAUSTION", paused = 0 } }
      W:fire("MIRROR_TIMER_START", "EXHAUSTION", 0, 60000, -1, 0, "Fatigue")
      die(W)
      A.eq(get(ns, "all", "dd"), 1, "a real one still counts")
      A.eq(roasts[#roasts], { "drown" })
      A.eq(ns.Log.errors(10), {})
    end,

    drown_without_mirror_info_trusts_the_events = function(ns, A, W)
      start(ns, W, function() W.state.missing.GetMirrorTimerInfo = true end)
      W:fire("MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
      die(W)
      A.eq(get(ns, "all", "dd"), 1)
      W:fire("MIRROR_TIMER_STOP", "BREATH")
      revive(W)
      W:advance(120)
      W:fire("MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
      W:fire("PLAYER_ENTERING_WORLD")
      A.eq(ns.Detectors.ctx.breathRunning, false, "still reset by the loading screen")
      A.eq(ns.Log.errors(10), {})
    end,

    repair_counted_only_when_paid = function(ns, A, W)
      start(ns, W)
      W.state.money = 500
      W.state.repairCost = 1000
      W:fire("MERCHANT_SHOW")
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 0, "could not pay: nothing repaired")
      W:fire("MERCHANT_CLOSED")
      W.state.money = 1500
      W.state.repairCost = 1000
      W:fire("MERCHANT_SHOW")
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 1000, "paid")
      W:fire("MERCHANT_CLOSED")
      -- the money already taken when the hook runs: the amount read before the repair still counts
      W.state.repairCost = 1000
      W:fire("MERCHANT_SHOW")
      W.state.money = 500
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 2000, "money read before the repair")
      W:fire("MERCHANT_CLOSED")
      A.eq(ns.Log.errors(10), {})
    end,

    repair_without_getmoney_still_counts = function(ns, A, W)
      start(ns, W, function() W.state.missing.GetMoney = true end)
      W.state.repairCost = 1000
      W:fire("MERCHANT_SHOW")
      W.env.RepairAllItems()
      A.eq(get(ns, "all", "rp"), 1000)
      A.ok(statusOf(ns, "repair").on)
    end,

    wipe_counts_once = function(ns, A, W)
      local roasts = start(ns, W, function()
        W.state.zone, W.state.inInstance, W.state.instanceType = "The Deadmines", true, "party"
      end)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", zn = "The Deadmines", ins = "1", tg = "" }, ns)
      receive(W, "Frostie", "UPDATE", { tg = "DEAD" }, ns)
      W:advance(10)
      die(W)
      A.eq(get(ns, "session", "wp"), 1)
      A.eq(kinds(roasts, "wipe"), 1)
      A.eq(roasts[#roasts], { "wipe", nil, "The Deadmines" })
      W:fire("PLAYER_ALIVE") -- released (still a ghost)
      W:advance(5)
      die(W)
      A.eq(get(ns, "session", "wp"), 1, "same wipe")
      A.eq(kinds(roasts, "wipe"), 1)
      -- both come back, both die again: a new wipe
      revive(W)
      receive(W, "Frostie", "UPDATE", { tg = "" }, ns)
      W:advance(100)
      die(W)
      receive(W, "Frostie", "UPDATE", { tg = "DEAD" }, ns)
      A.eq(get(ns, "session", "wp"), 2)
      A.eq(kinds(roasts, "wipe"), 2)
    end,

    no_wipe_alone_or_far_apart = function(ns, A, W)
      start(ns, W, function()
        W.state.zone, W.state.inInstance, W.state.instanceType = "The Deadmines", true, "party"
      end)
      die(W)
      A.eq(get(ns, "session", "wp"), 0, "alone")
      revive(W)
      receive(W, "Frostie", "STATE", { ver = "0.1.0", zn = "The Deadmines", ins = "1", tg = "" }, ns)
      receive(W, "Frostie", "UPDATE", { tg = "DEAD" }, ns)
      W:advance(45)
      die(W)
      A.eq(get(ns, "session", "wp"), 0, "45 s apart")
    end,

    milestones_roast = function(ns, A, W)
      local roasts = start(ns, W)
      ns.Stats.count("dt", 4)
      A.eq(roasts, {})
      ns.Stats.count("dt", 1)
      A.eq(roasts, { { "deaths", 5 } })
      ns.Stats.count("jp", 1000)
      A.eq(roasts[2], { "jumps", 1000 })
      ns.Stats.count("qa", 3)
      A.eq(roasts[3], { "quit", 3 })
      ns.Stats.count("st", 10000)
      A.eq(roasts[4], { "steps", 10000 })
      A.eq(#roasts, 4)
    end,

    death_milestone_only_without_other_roast = function(ns, A, W)
      local roasts = start(ns, W)
      ns.Stats.count("dt", 4)
      W.state.falling = true
      W:advance(1.5)
      W.state.falling = false
      die(W)
      A.eq(get(ns, "session", "dt"), 5)
      A.eq(roasts, { { "fall" } }, "one roast per death: fall beats the milestone")
      revive(W)
      W:advance(200)
      ns.Stats.count("dt", 4)
      die(W)
      A.eq(roasts[2], { "deaths", 10 })
    end,

    missing_apis_turn_detectors_off = function(ns, A, W)
      start(ns, W, function()
        for _, name in ipairs({ "JumpOrAscendStart", "RepairAllItems", "AbandonQuest", "C_QuestLog.AbandonQuest",
          "IsFalling", "hooksecurefunc" }) do
          W.state.missing[name] = true
        end
      end)
      local jumps = statusOf(ns, "jumps")
      A.no(jumps.on)
      A.eq(jumps.why, "JumpOrAscendStart missing")
      for _, id in ipairs({ "repair", "abandon", "fall" }) do
        local s = statusOf(ns, id)
        A.no(s.on, id .. " off")
        A.contains(s.why, "missing", id .. " reason")
      end
      A.contains(statusOf(ns, "fall").why, "IsFalling")
      for _, id in ipairs({ "motion", "timers", "death", "spells", "junk", "duel", "wipes" }) do
        A.ok(statusOf(ns, id).on, id .. " still on")
      end
      W.state.speed = 7
      W:advance(5)
      A.ok(get(ns, "all", "st") > 0, "steps still count")
      W:fire("CHAT_MSG_LOOT", GREY)
      A.eq(get(ns, "all", "jk"), 1)
      A.eq(ns.Log.errors(10), {})
      local warned = 0
      for _, line in ipairs(ns.Log.lines()) do
        if line:find("WARN", 1, true) and line:find("JumpOrAscendStart missing", 1, true) then warned = warned + 1 end
      end
      A.eq(warned, 1, "logged once as a warning")
      ns.Modules.setEnabled("stats", false)
      ns.Modules.setEnabled("stats", true)
      A.no(statusOf(ns, "jumps").on, "stays off")
      A.eq(ns.Log.errors(10), {})
    end,

    erroring_detector_turns_off_alone = function(ns, A, W)
      start(ns, W)
      W.env.C_Spell.GetSpellName = function() error("boom") end
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 999)
      local s = statusOf(ns, "spells")
      A.no(s.on)
      A.eq(s.why, "error")
      local errors = ns.Log.errors(10)
      A.eq(#errors, 1)
      A.contains(errors[1], "boom")
      W:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 999)
      A.eq(#ns.Log.errors(10), 1, "off: no more errors")
      W.state.speed = 7
      W:advance(5)
      A.ok(get(ns, "all", "st") > 0, "steps still count")
      A.ok(ns.Modules.isEnabled("stats"), "the stats module keeps running")
    end,

    erroring_tick_turns_off_alone = function(ns, A, W)
      start(ns, W)
      W.env.IsFalling = function() error("bad fall") end
      W.state.speed = 7
      for _ = 1, 20 do W:advance(0.5) end
      A.eq(statusOf(ns, "fall").why, "error")
      A.eq(#ns.Log.errors(10), 1)
      A.ok(get(ns, "all", "st") > 0, "steps still count")
      A.ok(statusOf(ns, "motion").on)
    end,

    module_off_stops_counting = function(ns, A, W)
      start(ns, W)
      local pt = get(ns, "all", "pt")
      ns.Modules.setEnabled("stats", false)
      W.state.speed = 7
      W:advance(10)
      W.env.JumpOrAscendStart()
      W:fire("CHAT_MSG_LOOT", GREY)
      die(W)
      ns.Stats.count("dt", 1)
      A.eq({ get(ns, "all", "st"), get(ns, "all", "jp"), get(ns, "all", "jk"), get(ns, "all", "dt"),
        get(ns, "all", "pt") }, { 0, 0, 0, 0, pt })
      A.eq(ns.Detectors.stepsMethod(), "off")
      revive(W)
      ns.Modules.setEnabled("stats", true)
      W:advance(10)
      W.env.JumpOrAscendStart()
      A.ok(get(ns, "all", "st") > 0, "steps again")
      A.eq(get(ns, "all", "jp"), 1)
      A.eq(ns.Log.errors(10), {})
    end,

    session_change_resets_or_keeps = function(ns, A, W)
      start(ns, W)
      local fired = 0
      ns.Bus.on("test", "STATS_CHANGED", function() fired = fired + 1 end)
      local cur = ns.Session.current()
      A.ok(cur, "session decided")
      A.eq(ns.StatsStore.mine().sid, cur.id)
      ns.Stats.count("dt", 2)
      local before = fired
      ns.Bus.fire("SESSION_CHANGED", { id = "Frostie-5", start = 5, manual = true }, cur, false)
      A.eq(fired, before + 1, "STATS_CHANGED at once")
      A.eq(get(ns, "session", "dt"), 0)
      A.eq(get(ns, "all", "dt"), 2)
      ns.Stats.count("dt", 3)
      ns.Bus.fire("SESSION_CHANGED", { id = "Ginkan-1", start = 1, manual = false },
        { id = "Frostie-5", start = 5, manual = true }, true)
      A.eq(get(ns, "session", "dt"), 3, "kept")
      A.eq(get(ns, "all", "dt"), 5)
    end,

    gold_carried_lost_and_gained = function(ns, A, W)
      W.state.money = 10000
      start(ns, W)
      W:advance(1)
      A.eq(get(ns, "session", "gn"), 10000)
      A.eq(get(ns, "all", "ml"), 0, "the first reading is only where we start")
      W.state.money = 7500
      W:fire("PLAYER_MONEY")
      A.eq(get(ns, "session", "gn"), 7500)
      A.eq(get(ns, "session", "ml"), 2500)
      W.state.money = 8000
      W:advance(1) -- the tick notices too
      A.eq(get(ns, "session", "mg"), 500)
      local hidden = {}
      W.state.secret[hidden] = true
      W.state.money = hidden
      W:advance(1)
      A.eq(get(ns, "session", "gn"), 8000, "a secret amount is skipped")
      A.ok(statusOf(ns, "gold").on, "and never an error")
    end,

    stats_changed_is_rate_limited = function(ns, A, W)
      start(ns, W)
      local fired = 0
      ns.Bus.on("test", "STATS_CHANGED", function() fired = fired + 1 end)
      W:advance(30)
      local base = fired
      ns.Stats.count("jp", 1)
      ns.Stats.count("jp", 1)
      ns.Stats.count("jp", 1)
      A.eq(fired, base + 1)
      W:advance(6)
      A.eq(fired, base + 2, "one trailing fire")
      W:advance(30)
      A.eq(fired, base + 2, "time played alone fires nothing")
    end,

    module_registered_with_settings = function(ns, A, W)
      start(ns, W)
      local d = ns.Modules.get("stats")
      A.eq(d.name, "Stats & Hall of Shame")
      A.eq(d.tier, "module")
      A.contains(d.info, "off")
      A.eq(ns.Modules.setting("stats", "titles"), "session")
      A.eq(ns.Modules.setting("stats", "countSteps"), true)
      A.eq(ns.Modules.setting("stats", "wipeLine"), true)
      A.eq(ns.Modules.setting("stats", "showSound"), true)
      local list = ns.Detectors.status()
      local ids = {}
      for i, s in ipairs(list) do ids[i] = s.id end
      A.eq(ids, { "motion", "fall", "timers", "death", "drown", "target", "pulls", "wipes", "jumps", "spells", "junk",
        "repair", "gold", "abandon", "duel" })
      -- one STATS goes out when the session is decided (inside start); counting after that sends nothing
      A.ok(#W.sent > 0, "the crew messages went out")
      local mark = #W.sent
      W.state.speed = 7
      W.env.JumpOrAscendStart()
      W:advance(30)
      for i = mark + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        A.ok(msg and msg.type ~= "STATS", "counting alone sends nothing")
      end
    end,
  },
}
