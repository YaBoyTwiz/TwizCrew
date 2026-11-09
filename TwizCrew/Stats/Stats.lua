-- Module "stats": counting glue between the detectors and the saved numbers, deaths, milestones and the session,
-- and sharing: one bulk STATS rarely (after the session is decided or changes, every STATS_SEND_INTERVAL s when a
-- number changed, at logout, in reply to STATSREQ). Roasts go through ns.Roasts when it exists (call time).
-- Turning the module off stops my own counting and sharing (spec 12b): one STATS with off=1 goes out instead, and
-- again in reply to STATSREQ. Saved numbers are kept. Friends' STATS are saved whether the module is on or off.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

local FEATURE = "stats"
local Logic = ns.StatsLogic
local Store = ns.StatsStore

local SHARE = "stats_share" -- friends' messages run under their own id: a broken one never trips "stats"
local WIRE_OPTS = { repeatKeys = { "sid", "q", "off" } }

local enabled = false
local lastFire       -- when STATS_CHANGED last fired
local trailing = false
local lastSent       -- wallclock of the last STATS we sent (nil = never)
local lastHeard      -- { name, at = wallclock } of the last friend's STATS saved
local lastRequest    -- session clock of our last STATSREQ
local replyPending = false -- one shared, jittered reply to every STATSREQ heard while it waits
local lastReply      -- session clock of our last STATSREQ reply (a broadcast: one per STATSREQ_GAP is enough)
local sendTicker

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

-- A set key (gold carried now): the same number in both views; STATS_CHANGED only when it changed.
function Stats.set(key, value)
  if not enabled then return end
  if Store.set(key, value) then changed() end
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

-- ---------------------------------------------------------------------------------------------
-- Sharing

-- My numbers, or only { sid, q, off = 1 } while the module is off. Through the queue (rate limit, boss-fight hold).
function Stats.send()
  local snap = Store.snapshot(not enabled)
  if not enabled and snap.sid == "" then
    -- a character that never counted has no sid of its own; friends drop a STATS without one
    local cur = ns.Session and ns.Session.current()
    if cur then snap.sid = cur.id end
  end
  ns.Comm.send("STATS", Logic.toWire(snap), WIRE_OPTS)
  if enabled then Store.markSent() end
  lastSent = ns.wallclock()
end

-- STATSREQ (when the Hall of Shame opens or the awards show starts): at most once per STATSREQ_GAP s.
-- My own changed numbers go right after it, so friends' boards match mine without waiting for the regular send.
function Stats.request()
  local now = ns.now()
  if lastRequest and now - lastRequest < ns.Config.STATSREQ_GAP then return false end
  lastRequest = now
  ns.Comm.send("STATSREQ", {})
  if enabled and Store.dirty() then Stats.send() end
  return true
end

function Stats.status()
  return { lastSent = lastSent, lastHeard = lastHeard and { name = lastHeard.name, at = lastHeard.at } or nil }
end

local function onStats(sender, fields)
  local wall = ns.wallclock()
  if not Store.applyWire(sender, fields, wall) then return end
  lastHeard = { name = sender, at = wall }
  fireChanged()
end

local function onRequest()
  if replyPending then return end
  if lastReply and ns.now() - lastReply < ns.Config.STATSREQ_GAP then return end
  replyPending = true
  local c = ns.Config
  local delay = c.STATSREQ_JITTER_MIN + math.random() * (c.STATSREQ_JITTER_MAX - c.STATSREQ_JITTER_MIN)
  C_Timer.After(delay, function()
    ns.Log.safe(SHARE, function()
      replyPending = false
      lastReply = ns.now()
      Stats.send()
    end)
  end)
end

-- Registered once at file load (ns.Comm loads earlier): friends' numbers are kept even while the module is off.
ns.Comm.on("STATS", function(sender, fields) ns.Log.safe(SHARE, onStats, sender, fields) end)
ns.Comm.on("STATSREQ", function(sender) ns.Log.safe(SHARE, onRequest, sender) end)

-- While the module is off (also when it was off at login, so onDisable never ran): one off message per session
-- change, so friends who were offline when it was switched off drop my numbers too. When on, onSession sends.
ns.Bus.on(SHARE, "SESSION_CHANGED", function()
  if not enabled then Stats.send() end
end)

local function sendIfChanged()
  if enabled and Store.dirty() then Stats.send() end
end

-- The queue may never run again at logout: each piece goes straight out, like v1's BYE.
local function sendAtLogout()
  if not enabled or not Store.dirty() then return end
  for _, text in ipairs(ns.Codec.encode("STATS", Logic.toWire(Store.snapshot()), WIRE_OPTS)) do
    for _, dest in ipairs(ns.Transport.destinations()) do
      ns.Transport.send(text, dest)
    end
  end
  Store.markSent()
  lastSent = ns.wallclock()
end

local api = {
  count = function(key, n) Stats.count(key, n) end,
  set = function(key, value) Stats.set(key, value) end,
  died = function() Stats.died() end,
  alive = function() Stats.alive() end,
  wipe = function(zone) Stats.wipe(zone) end,
}

local function onSession(new, old, keep)
  if type(new) ~= "table" then return end
  Store.setSession(new.id, type(old) == "table" and old.id or nil, keep)
  changed(true)
  Stats.send() -- friends see our (new) session quickly
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
    ns.Events.on(FEATURE, "PLAYER_LOGOUT", sendAtLogout)
    sendTicker = C_Timer.NewTicker(ns.Config.STATS_SEND_INTERVAL, function() ns.Log.safe(FEATURE, sendIfChanged) end)
    if cur then Stats.send() end -- turned back on: friends see my numbers again
  end,
  -- Also runs when the error breaker turns the module off: both are announced the same way.
  onDisable = function()
    enabled = false
    ns.Detectors.stopAll()
    if sendTicker then sendTicker:Cancel(); sendTicker = nil end
    Stats.send() -- off = 1
  end,
})
