-- Crew glue: HELLO / STATE / UPDATE / PING / BYE in and out, roster updates, online/offline tickers.
local _, ns = ...

local Crew = {}
ns.Crew = Crew

local FEATURE = "comm"
local STRANGER_HELLO_GAP = 30 -- seconds between HELLOs triggered by pings from the same unknown name

local replyPending = false -- true while a jittered STATE reply is waiting (one shared reply: a STATE is a broadcast)
local helloAt = {}       -- name -> time we last said HELLO because of their PING
local lastStrangerHello  -- time of the last HELLO sent because of any stranger's PING
local started = false

local function noteVersion(name, ver, rs)
  if ns.Version and ns.Version.seen and type(ver) == "string" then ns.Version.seen(name, ver, rs) end
end

local function hello() return { ver = ns.VERSION, rs = ns.RESTART_SINCE } end

local function announce(name, m, changes, events)
  ns.Bus.fire("MEMBER_UPDATED", name, changes)
  for _, e in ipairs(events) do
    if e == "online" then
      ns.Bus.fire("MEMBER_ONLINE", name)
    elseif e == "died" then
      ns.Bus.fire("MEMBER_DIED", name, m.zone, m.subzone)
    elseif e == "levelup" then
      ns.Bus.fire("MEMBER_LEVELUP", name, m.level)
    end
  end
end

-- cleared: fields already changed before this message (see onHello), reported together with the new ones.
local function onState(sender, fields, cleared)
  local m, changes, events = ns.roster:apply(sender, fields, ns.now(), ns.wallclock())
  for key in pairs(cleared or {}) do changes[key] = true end
  -- ver and rs are read back from the roster: a long STATE may bring them in two pieces
  if fields.ver ~= nil or fields.rs ~= nil then noteVersion(sender, m.version, m.restartSince) end
  announce(sender, m, changes, events)
end

local function onHello(sender, fields)
  -- A HELLO starts a new play session for them: what we knew about their layer, dungeon and tags is old.
  -- No rs = an older copy: forget the rs it may have sent before (when it was a newer copy).
  onState(sender, { ver = fields.ver, rs = fields.rs or "" }, ns.roster:clearSession(sender))
  if replyPending then return end
  replyPending = true
  local c = ns.Config
  local delay = c.HELLO_JITTER_MIN + math.random() * (c.HELLO_JITTER_MAX - c.HELLO_JITTER_MIN)
  C_Timer.After(delay, function()
    ns.Log.safe(FEATURE, function()
      replyPending = false
      ns.Comm.send("STATE", ns.Self.fullState())
    end)
  end)
end

local function onPing(sender)
  if not ns.roster:get(sender) then
    local now = ns.now()
    local nameOk = not helloAt[sender] or now - helloAt[sender] >= STRANGER_HELLO_GAP
    local globalOk = not lastStrangerHello or now - lastStrangerHello >= STRANGER_HELLO_GAP
    if nameOk and globalOk then
      helloAt[sender] = now
      lastStrangerHello = now
      ns.Comm.send("HELLO", hello())
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

-- Saved lists from v0.1.0 can hold "Name Realm" keys, including a ghost of ourselves: fold them into short names.
local function tidyNames(list)
  if type(list) ~= "table" then return end
  local keys = {}
  for key in pairs(list) do keys[#keys + 1] = key end
  for _, key in ipairs(keys) do
    if type(key) == "string" then
      local short = ns.shortName(key)
      if ns.isMe(short) then
        list[key] = nil
        ns.Log.add("info", "removed %s from the crew list (that is you)", ns.Util.safeText(key))
      elseif short ~= key then
        local row = list[key]
        list[key] = nil
        if list[short] == nil then
          if type(row) == "table" and row.name ~= nil then row.name = short end
          list[short] = row
        end
      end
    end
  end
end

function Crew.start()
  if started then return end
  started = true
  ns.Log.safe(FEATURE, tidyNames, ns.db.roster)
  if type(ns.db.stats) == "table" then ns.Log.safe(FEATURE, tidyNames, ns.db.stats.crew) end
  ns.roster = ns.Roster.new(ns.db.roster)
  ns.Comm.on("HELLO", onHello)
  ns.Comm.on("STATE", onState)
  ns.Comm.on("UPDATE", onState)
  ns.Comm.on("PING", onPing)
  ns.Comm.on("BYE", onBye)
  ns.Events.on(FEATURE, "PLAYER_LOGOUT", sayGoodbye)
  -- The channel works again after sends were refused: friends there may never have heard our login HELLO.
  ns.Bus.on(FEATURE, "CHANNEL_BACK", function()
    ns.Comm.send("HELLO", hello())
    ns.Comm.send("STATE", ns.Self.fullState())
  end)
  C_Timer.NewTicker(ns.Config.PING_INTERVAL, function()
    ns.Log.safe(FEATURE, ns.Comm.send, "PING", {})
  end)
  C_Timer.NewTicker(ns.Config.OFFLINE_TICK, function()
    ns.Log.safe(FEATURE, function()
      for _, name in ipairs(ns.roster:tick(ns.now())) do ns.Bus.fire("MEMBER_OFFLINE", name) end
    end)
  end)
  ns.Comm.send("HELLO", hello())
  ns.Comm.send("STATE", ns.Self.fullState())
end
