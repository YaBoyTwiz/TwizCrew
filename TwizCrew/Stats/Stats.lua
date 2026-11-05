-- Module "stats": counting glue between the detectors and the saved numbers, deaths, milestones and the session.
-- Sharing (STATS / STATSREQ) comes in Task 6. Roasts go through ns.Roasts when it exists (reached at call time).
-- Turning the module off stops my own counting (spec 12b); saved numbers are kept.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

local FEATURE = "stats"
local Logic = ns.StatsLogic
local Store = ns.StatsStore

local enabled = false
local lastFire       -- when STATS_CHANGED last fired
local trailing = false

-- stat key -> milestone kind and the view it is counted in
local MILESTONES = {
  dt = { kind = "deaths", view = "session" },
  st = { kind = "steps", view = "all" },
  jp = { kind = "jumps", view = "all" },
  qa = { kind = "quit", view = "session" },
}

local function fireChanged()
  lastFire = ns.now()
  ns.Bus.fire("STATS_CHANGED")
end

-- STATS_CHANGED at most every STATS_CHANGED_GAP s (with one trailing fire), or at once when forced.
local function changed(force)
  local gap = ns.Config.STATS_CHANGED_GAP
  local now = ns.now()
  if force or not lastFire or now - lastFire >= gap then
    fireChanged()
    return
  end
  if trailing then return end
  trailing = true
  C_Timer.After(gap - (now - lastFire), function()
    ns.Log.safe(FEATURE, function()
      trailing = false
      if enabled then fireChanged() end
    end)
  end)
end

local function roast(kind, v, x)
  local R = ns.Roasts
  if type(R) == "table" and type(R.send) == "function" then ns.Log.safe("roasts", R.send, kind, v, x) end
end

-- Adds n to key; returns the milestone crossed (nil when none). No roast, no STATS_CHANGED.
local function add(key, n)
  local m = MILESTONES[key]
  local old = m and Store.get(m.view, key)
  Store.add(key, n)
  if m then return Logic.milestone(m.kind, old, Store.get(m.view, key)) end
  return nil
end

function Stats.count(key, n)
  if not enabled then return end
  if n == nil then n = 1 end
  local mark = add(key, n)
  if mark then roast(MILESTONES[key].kind, mark) end
  if not ns.StatsDefs.TIME_KEYS[key] then changed() end
end

-- PLAYER_DEAD: what kind of death, then at most one roast (weak > fall > drown > again > deaths milestone).
function Stats.died()
  if not enabled then return end
  local ctx = ns.Detectors.ctx
  local level = type(UnitLevel) == "function" and UnitLevel("player") or nil
  if type(issecretvalue) == "function" then
    local ok, isSecret = pcall(issecretvalue, level)
    if not ok or isSecret then level = nil end
  end
  local r = Logic.classifyDeath({
    now = ns.now(), fallingAt = ctx.fallingAt, breathRunning = ctx.breathRunning,
    breathStoppedAt = ctx.breathStoppedAt, target = ctx.target, myLevel = level, aliveAt = ctx.aliveAt,
  })
  local mark = add("dt", 1)
  if r.fall then add("df", 1) end
  if r.drown then add("dd", 1) end
  if r.weak then
    add("dw", 1)
    add("ld", r.mobLevel)
  end
  if r.again then add("db", 1) end
  if r.weak then roast("weak", r.mobLevel, r.mobName)
  elseif r.fall then roast("fall")
  elseif r.drown then roast("drown")
  elseif r.again then roast("again", r.againSeconds)
  elseif mark then roast("deaths", mark) end
  changed()
end

-- Back to life (the detectors keep the time in Detectors.ctx.aliveAt); nothing to count.
function Stats.alive() end

-- Everyone in the dungeon died within WIPE_WINDOW s (wp is counted by the detector).
function Stats.wipe(zone)
  if not enabled then return end
  roast("wipe", nil, zone)
end

local api = {
  count = function(key, n) Stats.count(key, n) end,
  died = function() Stats.died() end,
  alive = function() Stats.alive() end,
  wipe = function(zone) Stats.wipe(zone) end,
}

local function onSession(new, old, keep)
  if type(new) ~= "table" then return end
  Store.setSession(new.id, type(old) == "table" and old.id or nil, keep)
  changed(true)
end

ns.Modules.register({
  id = FEATURE, name = "Stats & Hall of Shame", tier = "module",
  info = "Counts the funny things you do while playing, like deaths, falls, jumps and steps, for the Hall of Shame "
    .. "and the awards show. Turning it off stops counting and sharing your own numbers; what you already have "
    .. "is kept.",
  defaults = { titles = "session", countSteps = true, wipeLine = true, showSound = true },
  settings = {
    { key = "titles", label = "Award titles on the Crew panel", kind = "choice",
      choices = { { "session", "This session" }, { "all", "All time" }, { "off", "Off" } },
      info = "Shows each award winner's title under their name on the Crew tab, for this session or for all time." },
    { key = "countSteps", label = "Count steps", kind = "toggle",
      info = "Counts how far you walk, ride and swim. Turn it off if you don't want your steps counted." },
    { key = "wipeLine", label = "Show the Wipe Squad line", kind = "toggle",
      info = "Shows how many times the crew wiped in a dungeon at the bottom of the Hall of Shame." },
    { key = "showSound", label = "Sound in the awards show", kind = "toggle",
      info = "Plays a short sound for each award in the awards show." },
  },
  onEnable = function()
    enabled = true
    ns.Bus.on(FEATURE, "SESSION_CHANGED", onSession)
    -- the session may have moved on while counting was off
    local cur = ns.Session and ns.Session.decided() and ns.Session.current()
    if cur then Store.setSession(cur.id, nil, false) end
    ns.Detectors.startAll(api)
  end,
  onDisable = function()
    enabled = false
    ns.Detectors.stopAll()
  end,
})
