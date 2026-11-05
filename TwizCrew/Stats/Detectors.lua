-- Every WoW-facing detector of the stats module, each one guarded on its own, plus the one shared ticker.
-- A detector: { id, label, needs() -> ok, why, start(api), tick(elapsed) }. Its events and bus listeners use the
-- feature id "stats_<id>". A missing API turns it off (logged as warn, once); a Lua error inside it turns it off
-- (logged as error); either way it stays off until /reload and the others keep counting.
-- api = { count(key, n), died(), alive(), wipe(zone) } (the stats module).
local _, ns = ...

local D = {}
ns.Detectors = D

local Logic = ns.StatsLogic
local ctx = {} -- shared: fallingAt, breathRunning, breathStoppedAt, target = { level, name, at }, aliveAt
D.ctx = ctx

local list, byId = {}, {}
local state = {}     -- id -> { on, why, dead }
local running = false
local api
local ticker, lastTick
local hooked = {}    -- hook name -> true (hooks are installed once per session)
local hookFns = {}   -- hook name -> { detector, fn }

local function fid(d) return "stats_" .. d.id end

local function secret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, yes = pcall(issecretvalue, v)
  return (not ok) or (yes and true or false)
end

local function fn(name) return type(_G[name]) == "function" end

-- First missing name in order, as "<name> missing"; nil when all are there.
local function missingOf(...)
  for i = 1, select("#", ...) do
    local name = select(i, ...)
    if not fn(name) then return name .. " missing" end
  end
  return nil
end

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  return f(...)
end

local function turnOff(d, why, level, detail)
  local s = state[d.id]
  s.on, s.why, s.dead = false, why, true
  ns.Events.off(fid(d))
  ns.Bus.off(fid(d))
  ns.Log.add(level, "stats: %s turned off (%s)", d.id, detail or why)
end

local function isLive(d)
  local s = state[d.id]
  return running and s ~= nil and s.on
end

-- Runs f(...) for detector d; an error turns d off. Does nothing while d (or the module) is off.
local function guard(d, f, ...)
  if not isLive(d) then return end
  local args, count = { ... }, select("#", ...)
  local trace
  local ok, err = xpcall(function() return f(unpack(args, 1, count)) end, function(e)
    if type(debugstack) == "function" then trace = debugstack(2) end
    return e
  end)
  if ok then return end
  turnOff(d, "error", "error", tostring(err))
  if trace then ns.Log.add("debug", "stats_%s traceback: %s", d.id, (tostring(trace):gsub("\n", " < "))) end
end

local function onEvent(d, event, f)
  ns.Events.on(fid(d), event, function(...) guard(d, f, ...) end)
end

local function onBus(d, name, f)
  ns.Bus.on(fid(d), name, function(...) guard(d, f, ...) end)
end

-- hooksecurefunc once per session; the hook does nothing while its detector is off.
local function hook(d, tbl, name, f)
  local key = tbl and ("table." .. name) or name
  hookFns[key] = { d = d, fn = f }
  if hooked[key] then return end
  hooked[key] = true
  local function post(...)
    local h = hookFns[key]
    if h then guard(h.d, h.fn, ...) end
  end
  if tbl then hooksecurefunc(tbl, name, post) else hooksecurefunc(name, post) end
end

local function add(d)
  list[#list + 1] = d
  byId[d.id] = d
  return d
end

local function player(f) return call(f, "player") end

local function inDungeon()
  local inside, kind = call(IsInInstance)
  return (inside and (kind == "party" or kind == "raid")) and true or false
end

-- ---------------------------------------------------------------------------------------------
-- Detectors, in this order

local lastPos -- motion: last UnitPosition reading

local function countSteps() return ns.Modules.setting("stats", "countSteps") ~= false end

add({ id = "motion", label = "steps, riding and swimming",
  needs = function()
    if not fn("GetUnitSpeed") and not fn("UnitPosition") then return false, "GetUnitSpeed and UnitPosition missing" end
    local why = missingOf("IsMounted", "IsSwimming", "UnitOnTaxi", "UnitIsDeadOrGhost")
    return why == nil, why
  end,
  start = function() lastPos = nil end,
  tick = function(elapsed)
    if not countSteps() then lastPos = nil; return end
    local bucket = Logic.motionBucket({ taxi = player(UnitOnTaxi), dead = player(UnitIsDeadOrGhost),
      mounted = call(IsMounted), swimming = call(IsSwimming) })
    local yards
    if fn("GetUnitSpeed") then
      local speed = GetUnitSpeed("player")
      yards = Logic.speedYards(speed, elapsed, secret(speed))
    elseif fn("UnitPosition") then
      local y, x, _, instance = UnitPosition("player")
      local reading
      if not (secret(x) or secret(y) or secret(instance)) then
        reading = { x = x, y = y, instance = instance, t = ns.now() }
      end
      yards = Logic.positionYards(lastPos, reading)
      lastPos = reading
    end
    if not bucket or not yards or yards <= 0 then return end
    if bucket == "foot" then api.count("st", yards * ns.Config.STEPS_PER_YARD)
    elseif bucket == "mount" then api.count("mt", yards)
    else api.count("sw", yards) end
  end })

-- IsFalling() is also true during every jump: only a fall seen for at least FALL_MIN s counts as falling.
local FALL_MIN = 1
local fallStart -- when the current fall was first seen (nil = not falling)
add({ id = "fall", label = "falling deaths",
  needs = function() local why = missingOf("IsFalling"); return why == nil, why end,
  start = function() fallStart = nil end,
  tick = function()
    if not IsFalling() then fallStart = nil; return end
    local now = ns.now()
    fallStart = fallStart or now
    if now - fallStart >= FALL_MIN then ctx.fallingAt = now end
  end })

add({ id = "timers", label = "time AFK, dead and played",
  needs = function() return true end,
  tick = function(elapsed)
    api.count("pt", elapsed)
    if player(UnitIsAFK) then api.count("af", elapsed) end
    if player(UnitIsDeadOrGhost) then api.count("ds", elapsed) end
  end })

local readTarget -- set by the target detector, used again at death

local function alive()
  if player(UnitIsDeadOrGhost) then return end
  ctx.aliveAt = ns.now()
  api.alive()
end

add({ id = "death", label = "deaths",
  needs = function() return true end,
  start = function()
    onEvent(byId.death, "PLAYER_DEAD", function()
      if isLive(byId.target) then guard(byId.target, readTarget, true) end
      api.died()
    end)
    onEvent(byId.death, "PLAYER_ALIVE", alive)
    onEvent(byId.death, "PLAYER_UNGHOST", alive)
  end })

local breath = {} -- running mirror timers that drown or tire you
add({ id = "drown", label = "drowning deaths",
  needs = function() return true end,
  start = function()
    local d = byId.drown
    onEvent(d, "MIRROR_TIMER_START", function(timer)
      if timer == "BREATH" or timer == "EXHAUSTION" then
        breath[timer] = true
        ctx.breathRunning = true
      end
    end)
    onEvent(d, "MIRROR_TIMER_STOP", function(timer)
      if breath[timer] then
        breath[timer] = nil
        ctx.breathRunning = next(breath) ~= nil
        ctx.breathStoppedAt = ns.now()
      end
    end)
  end })

-- atDeath: a dead target (a mob you killed earlier) is not what killed you, so it is forgotten.
readTarget = function(atDeath)
  if not UnitExists("target") then return end
  if fn("UnitIsDead") then
    local dead = UnitIsDead("target")
    if secret(dead) or dead then
      if atDeath then ctx.target = nil end
      return
    end
  end
  if UnitIsPlayer("target") or not UnitCanAttack("player", "target") then return end
  local level, name = UnitLevel("target"), UnitName("target")
  if secret(level) or secret(name) or type(level) ~= "number" or type(name) ~= "string" then return end
  ctx.target = { level = level, name = name, at = ns.now() }
end

add({ id = "target", label = "deaths to weak monsters",
  needs = function()
    local why = missingOf("UnitExists", "UnitCanAttack", "UnitIsPlayer", "UnitLevel", "UnitName")
    return why == nil, why
  end,
  start = function() onEvent(byId.target, "PLAYER_TARGET_CHANGED", function() readTarget(false) end) end })

add({ id = "pulls", label = "pulls in dungeons",
  needs = function() return true end,
  start = function()
    onEvent(byId.pulls, "PLAYER_REGEN_DISABLED", function()
      if not ns.roster then return end
      local me = { dungeon = inDungeon(), zone = call(GetRealZoneText) }
      if Logic.isPull(me, ns.roster:members()) then api.count("pl", 1) end
    end)
  end })

local watch -- wipe watch (created at first start, kept across stop/start)
local function crewHere()
  local zone = call(GetRealZoneText)
  local names = { ns.playerName() }
  if not inDungeon() or not ns.roster then return names, zone end
  for _, m in ipairs(ns.roster:members()) do
    if m.online and m.inInstance and m.zone == zone and m.name ~= names[1] then names[#names + 1] = m.name end
  end
  return names, zone
end

local function checkWipe()
  if not inDungeon() then return end
  local names, zone = crewHere()
  if watch:check(names, ns.now()) then
    api.count("wp", 1)
    api.wipe(zone)
  end
end

add({ id = "wipes", label = "wipes",
  needs = function() return true end,
  start = function()
    local d = byId.wipes
    watch = watch or Logic.newWipeWatch(ns.Config.WIPE_WINDOW)
    local function meAlive() if not player(UnitIsDeadOrGhost) then watch:alive(ns.playerName()) end end
    onEvent(d, "PLAYER_DEAD", function()
      watch:dead(ns.playerName(), ns.now())
      checkWipe()
    end)
    onEvent(d, "PLAYER_ALIVE", meAlive)
    onEvent(d, "PLAYER_UNGHOST", meAlive)
    onBus(d, "MEMBER_DIED", function(name)
      watch:dead(name, ns.now())
      checkWipe()
    end)
    onBus(d, "MEMBER_UPDATED", function(name, changes)
      local m = ns.roster and ns.roster:get(name)
      if type(changes) == "table" and changes.tags and m and not (m.tags and m.tags.DEAD) then watch:alive(name) end
    end)
  end })

add({ id = "jumps", label = "jumps",
  needs = function()
    local why = missingOf("JumpOrAscendStart", "hooksecurefunc")
    return why == nil, why
  end,
  start = function() hook(byId.jumps, nil, "JumpOrAscendStart", function() api.count("jp", 1) end) end })

local function spellKind(id, name)
  for kind, def in pairs(ns.StatsDefs.SPELLS) do
    for _, n in ipairs(def.names) do if name == n then return kind end end
    for _, i in ipairs(def.ids) do if id == i then return kind end end
  end
  return nil
end

add({ id = "spells", label = "hearthstones and rezzes",
  needs = function() return true end,
  start = function()
    onEvent(byId.spells, "UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
      if unit ~= "player" or secret(spellID) or type(spellID) ~= "number" then return end
      local name
      if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        name = C_Spell.GetSpellName(spellID)
      elseif fn("GetSpellInfo") then
        name = GetSpellInfo(spellID)
      end
      if secret(name) or type(name) ~= "string" then name = nil end
      local kind = spellKind(spellID, name)
      if kind == "hearth" then api.count("hs", 1) elseif kind == "rez" then api.count("rz", 1) end
    end)
  end })

add({ id = "junk", label = "gray junk looted",
  needs = function()
    if type(LOOT_ITEM_SELF) ~= "string" then return false, "LOOT_ITEM_SELF missing" end
    return true
  end,
  start = function()
    onEvent(byId.junk, "CHAT_MSG_LOOT", function(text)
      if secret(text) then return end
      local n = Logic.junkCount(text, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE)
      if n > 0 then api.count("jk", n) end
    end)
  end })

local merchantOpen, repairCost = false, 0
local function readCost()
  if not merchantOpen then return end
  local cost, can = GetRepairAllCost()
  if secret(cost) or type(cost) ~= "number" or cost ~= cost then return end
  repairCost = (can and cost > 0) and cost or 0
end

add({ id = "repair", label = "money spent on repairs",
  needs = function()
    local why = missingOf("RepairAllItems", "GetRepairAllCost", "hooksecurefunc")
    return why == nil, why
  end,
  start = function()
    local d = byId.repair
    merchantOpen, repairCost = false, 0
    onEvent(d, "MERCHANT_SHOW", function() merchantOpen = true; readCost() end)
    onEvent(d, "MERCHANT_CLOSED", function() merchantOpen, repairCost = false, 0 end)
    onEvent(d, "UPDATE_INVENTORY_DURABILITY", readCost)
    hook(d, nil, "RepairAllItems", function(guild)
      if guild or not merchantOpen or repairCost <= 0 then return end
      api.count("rp", repairCost)
      repairCost = 0
    end)
  end,
  tick = readCost })

local ABANDON_DEDUPE = 1
local lastAbandon
add({ id = "abandon", label = "quests abandoned",
  needs = function()
    if not fn("hooksecurefunc") then return false, "hooksecurefunc missing" end
    if type(C_QuestLog) == "table" and type(C_QuestLog.AbandonQuest) == "function" then return true end
    if fn("AbandonQuest") then return true end
    return false, "AbandonQuest missing"
  end,
  start = function()
    -- The quest log may call the global AbandonQuest, C_QuestLog.AbandonQuest, or one through the other:
    -- every one that exists is hooked, and a second abandon within ABANDON_DEDUPE s is the same one.
    local function count()
      local now = ns.now()
      if lastAbandon and now - lastAbandon < ABANDON_DEDUPE then return end
      lastAbandon = now
      api.count("qa", 1)
    end
    if type(C_QuestLog) == "table" and type(C_QuestLog.AbandonQuest) == "function" then
      hook(byId.abandon, C_QuestLog, "AbandonQuest", count)
    end
    if fn("AbandonQuest") then hook(byId.abandon, nil, "AbandonQuest", count) end
  end })

add({ id = "duel", label = "duels won and lost",
  needs = function()
    if type(DUEL_WINNER_KNOCKOUT) ~= "string" then return false, "DUEL_WINNER_KNOCKOUT missing" end
    return true
  end,
  start = function()
    onEvent(byId.duel, "CHAT_MSG_SYSTEM", function(text)
      if secret(text) then return end
      local r = Logic.duelResult(text, ns.playerName(), DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT)
      if r == "lost" then api.count("dl", 1) elseif r == "won" then api.count("dv", 1) end
    end)
  end })

-- ---------------------------------------------------------------------------------------------

local function tick()
  local now = ns.now()
  local elapsed = math.min(math.max(now - (lastTick or now), 0), 5) -- a loading screen counts as at most 5 s
  lastTick = now
  for _, d in ipairs(list) do
    if d.tick then guard(d, d.tick, elapsed) end
  end
end

function D.startAll(theApi)
  api = theApi
  if running then return end
  running = true
  for _, d in ipairs(list) do
    local s = state[d.id]
    if not s then s = {}; state[d.id] = s end
    if not s.dead then
      local okCall, ok, why = pcall(d.needs)
      if not okCall then
        turnOff(d, "error", "error", tostring(ok))
      elseif not ok then
        turnOff(d, why or "not available", "warn")
      else
        s.on, s.why = true, nil
        if d.start then guard(d, d.start, api) end
      end
    end
  end
  lastTick = ns.now()
  ticker = C_Timer.NewTicker(ns.Config.STATS_TICK, function() ns.Log.safe("stats", tick) end)
end

function D.stopAll()
  if not running then return end
  running = false
  if ticker then ticker:Cancel(); ticker = nil end
  for _, d in ipairs(list) do
    local s = state[d.id]
    if s and not s.dead then s.on = false end
    ns.Events.off(fid(d))
    ns.Bus.off(fid(d))
  end
  for timer in pairs(breath) do breath[timer] = nil end
  ctx.breathRunning = false
  merchantOpen, repairCost, lastPos = false, 0, nil
end

-- { id, on, why } per detector, in order (why is nil while on).
function D.status()
  local out = {}
  for _, d in ipairs(list) do
    local s = state[d.id] or {}
    local on, why = running and s.on and true or false, s.why
    if not s.dead and not running then why = "stats are turned off" end
    if d.id == "motion" and on and not countSteps() then on, why = false, "Count steps is off" end
    out[#out + 1] = { id = d.id, label = d.label, on = on, why = why }
  end
  return out
end

function D.stepsMethod()
  if not isLive(byId.motion) or not countSteps() then return "off" end
  if fn("GetUnitSpeed") then return "speed" end
  if fn("UnitPosition") then return "position" end
  return "off"
end

D.list = list
