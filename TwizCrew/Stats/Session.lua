-- The shared crew session ("tonight's game"). Always runs, like the layer sensor: feature id "session".
-- Waits SESSION_DECIDE_AFTER s after start to hear the crew, then joins the best session or starts one;
-- afterwards every session heard from a friend may move us (SessionLogic.switch).
-- Fires SESSION_CHANGED(new, old, keep) on the bus; ns.Self reads Session.wire() for the sid/sst fields.
local _, ns = ...

local Session = {}
ns.Session = Session

local FEATURE = "session"
local Logic = ns.SessionLogic

local current          -- { id, start, manual } or nil
local isDecided = false
local started = false
local heard = {}       -- sender -> { sid = ..., sst = ... } as merged from their STATE / UPDATE pieces (HELLO forgets)
local RESHARE_GAP = 30 -- seconds between re-sends of our sid/sst to a friend in another session or coming back
local lastReshare      -- session clock of the last re-send
local previous         -- { id, lastActive } of the session saved before login (read at the decision)

local function copy(s)
  if s == nil then return nil end
  return { id = s.id, start = s.start, manual = s.manual and true or false }
end

local function savedTable()
  if not ns.db then return nil end
  if type(ns.db.stats) ~= "table" then ns.db.stats = { chars = {}, crew = {}, session = {} } end
  return ns.db.stats
end

local function save()
  local stats = savedTable()
  if not stats or not current then return end
  stats.session = { id = current.id, start = current.start, manual = current.manual, lastActive = ns.wallclock() }
end

local function saveActive()
  local stats = savedTable()
  if not stats or not current or type(stats.session) ~= "table" then return end
  stats.session.lastActive = ns.wallclock()
end

local function change(new, old, keep, why)
  current = copy(new)
  save()
  ns.Log.add("info", "session %s (%s): %s", tostring(current.id),
    current.manual and "started by hand" or "automatic", why)
  ns.Bus.fire("SESSION_CHANGED", copy(current), copy(old), keep and true or false)
  ns.Self.refresh("session")
end

local function sessionOf(name)
  local h = heard[name]
  if not h then return nil end
  return Logic.fromWire(h.sid, h.sst)
end

local function decide()
  if isDecided then return end
  isDecided = true
  local list = {}
  for name in pairs(heard) do
    local m = ns.roster and ns.roster:get(name)
    local s = m and m.online and sessionOf(name)
    if s then list[#list + 1] = s end
  end
  table.sort(list, function(a, b) return a.id < b.id end) -- same answer whatever order pairs() gives
  local stats = savedTable()
  local own = stats and stats.session
  if type(own) == "table" and type(own.id) == "string" and type(own.lastActive) == "number" then
    previous = { id = own.id, lastActive = own.lastActive } -- change() overwrites it
  end
  local wall = ns.wallclock()
  local resume = ns.Config.SESSION_RESUME
  local s, keep = Logic.atLogin(own, list, wall, ns.playerName(), resume)
  local old = Logic.resumable(own, wall, resume) and copy(own) or nil
  local fromCrew = false
  for _, x in ipairs(list) do if x == s then fromCrew = true end end
  local why
  if old and s.id == old.id then
    why = "continued after a short break"
  elseif fromCrew then
    why = "joined the crew's session"
  else
    why = "nobody online was in one, started a new one"
  end
  change(s, old, keep, why)
end

-- sid/sst only travel in UPDATEs when they change, so one lost message could leave a friend in another session:
-- tell the crew ours again (at most once per RESHARE_GAP seconds).
local function reshare(name)
  if ns.isTestName(name) or not isDecided or not current then return end -- a fake (test tools) never makes us send
  local now = ns.now()
  if lastReshare and now - lastReshare < RESHARE_GAP then return end
  lastReshare = now
  local sid, sst = Logic.toWire(current)
  ns.Comm.send("UPDATE", { sid = sid, sst = sst })
end

local function onFields(sender, fields)
  if ns.isTestName(sender) then return end -- fakes (test tools) have no say in the crew session
  if type(fields) ~= "table" or (fields.sid == nil and fields.sst == nil) then return end
  local h = heard[sender]
  if not h then h = {}; heard[sender] = h end
  if fields.sid ~= nil then h.sid = fields.sid end
  if fields.sst ~= nil then h.sst = fields.sst end
  if not isDecided then return end
  local theirs = sessionOf(sender)
  local s, changed, keep = Logic.switch(current, theirs)
  if changed then
    change(s, current, keep, "heard from " .. tostring(sender)
      .. (s.manual and " (started by hand, counts start over)" or " (older session, counts kept)"))
  elseif theirs and current and theirs.id ~= current.id then
    reshare() -- ours wins: make sure they hear it
  end
end

local function forget(sender) heard[sender] = nil end

-- Registered once at file load (ns.Comm loads earlier); the handlers only merge until the decision is made.
-- Offline friends keep their fields (the decision only looks at online ones); a HELLO means a new login.
ns.Comm.on("STATE", function(sender, fields) ns.Log.safe(FEATURE, onFields, sender, fields) end)
ns.Comm.on("UPDATE", function(sender, fields) ns.Log.safe(FEATURE, onFields, sender, fields) end)
ns.Comm.on("HELLO", function(sender) ns.Log.safe(FEATURE, forget, sender) end)

function Session.current() return copy(current) end
function Session.decided() return isDecided end
function Session.wire() return Logic.toWire(current) end
-- When I was last active in session sid, if it is the one saved before this login; else nil.
function Session.previousLastActive(sid)
  if previous and previous.id == sid then return previous.lastActive end
  return nil
end

-- "/tc session new": a hand-started session from me, now (even before the decision). Counts start over.
-- Its start is later than every hand-started session we know of, so it wins even when a friend's PC clock is
-- ahead of ours (and two quick restarts never share an id).
function Session.newByHand()
  isDecided = true
  local old = current
  local start = ns.wallclock()
  if current and current.manual and current.start + 1 > start then start = current.start + 1 end
  for name in pairs(heard) do
    local s = sessionOf(name)
    if s and s.manual and s.start + 1 > start then start = s.start + 1 end
  end
  change(Logic.newSession(ns.playerName(), start, true), old, false, "started by hand")
  return copy(current)
end

-- Name of whoever started session s ("Twiz-1700000000" -> "Twiz").
function Session.starter(s)
  local id = type(s) == "table" and s.id or s
  if type(id) ~= "string" then return nil end
  return id:match("^(.*)%-%d+$") or id
end

function Session.start()
  if started then return end
  started = true
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", reshare) -- a friend coming back hears our session even if nothing changes
  ns.Events.on(FEATURE, "PLAYER_LOGOUT", saveActive)
  C_Timer.After(ns.Config.SESSION_DECIDE_AFTER, function() ns.Log.safe(FEATURE, decide) end)
  C_Timer.NewTicker(ns.Config.SESSION_ACTIVE_TICK, function() ns.Log.safe(FEATURE, saveActive) end)
end

Session.forTest = { decideNow = function() decide() end }
