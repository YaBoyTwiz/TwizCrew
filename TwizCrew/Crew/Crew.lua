-- Crew glue: HELLO / STATE / UPDATE / PING / BYE in and out, roster updates, online/offline tickers.
local _, ns = ...

local Crew = {}
ns.Crew = Crew

local FEATURE = "comm"
local STRANGER_HELLO_GAP = 30 -- seconds between HELLOs triggered by pings from the same unknown name

local replyPending = {}  -- name -> true while a jittered STATE reply is waiting
local helloAt = {}       -- name -> time we last said HELLO because of their PING
local started = false

local function noteVersion(name, ver)
  if ns.Version and ns.Version.seen and type(ver) == "string" then ns.Version.seen(name, ver) end
end

local function announce(name, m, changes, events)
  ns.Bus.fire("MEMBER_UPDATED", name, changes)
  for _, e in ipairs(events) do
    if e == "online" then
      ns.Bus.fire("MEMBER_ONLINE", name)
    elseif e == "died" then
      ns.Bus.fire("MEMBER_DIED", name, m.zone, m.subzone)
    end
  end
end

local function onState(sender, fields)
  local m, changes, events = ns.roster:apply(sender, fields, ns.now(), ns.wallclock())
  noteVersion(sender, fields.ver)
  announce(sender, m, changes, events)
end

local function onHello(sender, fields)
  onState(sender, { ver = fields.ver })
  if replyPending[sender] then return end
  replyPending[sender] = true
  local c = ns.Config
  local delay = c.HELLO_JITTER_MIN + math.random() * (c.HELLO_JITTER_MAX - c.HELLO_JITTER_MIN)
  C_Timer.After(delay, function()
    ns.Log.safe(FEATURE, function()
      replyPending[sender] = nil
      ns.Comm.send("STATE", ns.Self.fullState())
    end)
  end)
end

local function onPing(sender)
  if not ns.roster:get(sender) then
    local now = ns.now()
    if not helloAt[sender] or now - helloAt[sender] >= STRANGER_HELLO_GAP then
      helloAt[sender] = now
      ns.Comm.send("HELLO", { ver = ns.VERSION })
    end
    return
  end
  for _, e in ipairs(ns.roster:heard(sender, ns.now(), ns.wallclock())) do
    if e == "online" then ns.Bus.fire("MEMBER_ONLINE", sender) end
  end
end

local function onBye(sender)
  local m = ns.roster:get(sender)
  if not m then return end
  local wasOnline = m.online
  ns.roster:gone(sender)
  if wasOnline then ns.Bus.fire("MEMBER_OFFLINE", sender) end
end

local function sayGoodbye()
  for _, text in ipairs(ns.Codec.encode("BYE", {})) do
    for _, dest in ipairs(ns.Transport.destinations()) do
      ns.Transport.send(text, dest)
    end
  end
end

function Crew.start()
  if started then return end
  started = true
  ns.roster = ns.Roster.new(ns.db.roster)
  ns.Comm.on("HELLO", onHello)
  ns.Comm.on("STATE", onState)
  ns.Comm.on("UPDATE", onState)
  ns.Comm.on("PING", onPing)
  ns.Comm.on("BYE", onBye)
  ns.Events.on(FEATURE, "PLAYER_LOGOUT", sayGoodbye)
  C_Timer.NewTicker(ns.Config.PING_INTERVAL, function()
    ns.Log.safe(FEATURE, ns.Comm.send, "PING", {})
  end)
  C_Timer.NewTicker(ns.Config.OFFLINE_TICK, function()
    ns.Log.safe(FEATURE, function()
      for _, name in ipairs(ns.roster:tick(ns.now())) do ns.Bus.fire("MEMBER_OFFLINE", name) end
    end)
  end)
  ns.Comm.send("HELLO", { ver = ns.VERSION })
  ns.Comm.send("STATE", ns.Self.fullState())
end
