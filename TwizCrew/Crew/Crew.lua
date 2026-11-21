-- Crew glue: HELLO / STATE / UPDATE / PING / BYE in and out, roster updates, online/offline tickers.
local _, ns = ...

local Crew = {}
ns.Crew = Crew

local FEATURE = "crew"
-- seconds between HELLOs triggered by pings from unknown names (and none this soon after our own HELLO)
local STRANGER_HELLO_GAP = 30

local replyPending = {}  -- name -> true while our answer to their HELLO waits (one per newcomer)
local helloAt = {}       -- name -> time we last said HELLO because of their PING
local lastStrangerHello  -- time of the last HELLO sent because of any stranger's PING
local started = false
local helloKept = false -- the login HELLO waits in Comm's kept messages for the guild answer (TRANSPORT_READY)
local saidHelloAt       -- when our HELLO went to the guild (their answers are on the way for a few seconds)
local mismatches = {}  -- name -> PINGs in a row whose digest differed from what we hold
local sreqAt = {}      -- name -> time we last asked for their state
local answeredAt = {}  -- name -> time we last answered their SREQ

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

-- A newcomer gets our STATE as a whisper (only a STATE: a HELLO back would make them answer every copy in the guild),
-- after a random 0 to HELLO_REPLY_JITTER seconds so that, with many copies online, the answers do not land at once.
local function onHello(sender, fields)
  -- A HELLO starts a new play session for them: what we knew about their layer, dungeon and tags is old.
  -- No rs = an older copy: forget the rs it may have sent before (when it was a newer copy).
  local cleared = ns.roster:clearSession(sender)
  -- A STATE always follows a HELLO: what they sent before no longer counts for the digest.
  local m = ns.roster:get(sender)
  if m then m.raw = {} end
  onState(sender, { ver = fields.ver, rs = fields.rs or "" }, cleared)
  if replyPending[sender] then return end
  replyPending[sender] = true
  C_Timer.After(math.random() * ns.Config.HELLO_REPLY_JITTER, function()
    ns.Log.safe(FEATURE, function()
      replyPending[sender] = nil
      local state = ns.Self.stateFor()
      if not ns.Comm.sendTo(sender, "STATE", state) then ns.Comm.send("STATE", state) end
    end)
  end)
end

local function onPing(sender, fields)
  if not ns.roster:get(sender) then
    local now = ns.now()
    -- we just said HELLO to the guild: their answer is probably on its way, a PING may simply have overtaken it
    if saidHelloAt and now - saidHelloAt < STRANGER_HELLO_GAP then return end
    local nameOk = not helloAt[sender] or now - helloAt[sender] >= STRANGER_HELLO_GAP
    local globalOk = not lastStrangerHello or now - lastStrangerHello >= STRANGER_HELLO_GAP
    if nameOk and globalOk then
      helloAt[sender] = now
      lastStrangerHello = now
      -- only to them: a HELLO to the whole guild would make every copy answer. Not whisperable yet (the guild list
      -- has not loaded): their next PING tries again.
      if ns.Comm.sendTo(sender, "HELLO", hello()) then
        ns.Comm.sendTo(sender, "STATE", ns.Self.stateFor())
      else
        helloAt[sender], lastStrangerHello = nil, nil
      end
    end
    return
  end
  for _, e in ipairs(ns.roster:heard(sender, ns.now(), ns.wallclock())) do
    if e == "online" then ns.Bus.fire("MEMBER_ONLINE", sender) end
  end
  -- The digest shows a lost message: two PINGs in a row that disagree (one may just have passed an update in
  -- flight) make us ask for their whole state, at most once per ping interval. No "h" = an old copy: never a mismatch.
  local h = type(fields) == "table" and fields.h
  if type(h) ~= "string" then return end
  if h == ns.roster:digest(sender) then mismatches[sender] = nil; return end
  mismatches[sender] = (mismatches[sender] or 0) + 1
  if mismatches[sender] < 2 then return end
  local now = ns.now()
  if sreqAt[sender] and now - sreqAt[sender] < ns.Config.PING_INTERVAL then return end
  if ns.Comm.sendTo(sender, "SREQ", {}) then -- not whisperable yet (guild list not loaded): the next PING asks
    mismatches[sender] = nil
    sreqAt[sender] = now
    ns.Log.count("sent SREQ")
  end
end

-- Answered at most once per ping interval for each asker.
local function onSreq(sender)
  local now = ns.now()
  if answeredAt[sender] and now - answeredAt[sender] < ns.Config.PING_INTERVAL then return end
  answeredAt[sender] = now
  ns.Comm.sendTo(sender, "STATE", ns.Self.stateFor())
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

-- Saved lists from v0.1.0 can hold "Name-Realm" keys, including a ghost of ourselves: the realm is taken off and the
-- ghost removed. Keys are guild member keys now: a first word, a full name ("Chaos Other") or "Name (2)". A key the
-- guild list gave out (a value in ns.db.guild.keys) is never touched, and no other key loses a later word.
local function tidyNames(list)
  if type(list) ~= "table" then return end
  local given = {}
  local saved = ns.db and type(ns.db.guild) == "table" and ns.db.guild.keys
  if type(saved) == "table" then
    for _, key in pairs(saved) do if type(key) == "string" then given[key] = true end end
  end
  local keys = {}
  for key in pairs(list) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    if type(key) == "string" and not given[key] then
      local base = key:match("^([^%-]+)%-.+$") or key -- "Twiz-Realm" -> "Twiz"
      if ns.isMe(base) then
        list[key] = nil
        ns.Log.add("info", "removed %s from the crew list (that is you)", ns.Util.safeText(key))
      elseif base ~= key then
        local row = list[key]
        list[key] = nil
        if list[base] == nil then
          if type(row) == "table" and row.name ~= nil then row.name = base end
          list[base] = row
        end
      end
    end
  end
end

-- Takes a friend who is offline out of the roster and the saved numbers.
-- Returns true when something was removed; otherwise false and a short reason (never you, never an online friend).
function Crew.forget(name)
  if type(name) ~= "string" or name == "" then return false, "no name" end
  if ns.isMe(name) then return false, "that is you" end
  local low = name:lower()
  local row
  for _, n in ipairs(ns.roster and ns.roster:names() or {}) do
    if n:lower() == low then row = n end
  end
  if row then
    local m = ns.roster:get(row)
    if m and m.online then return false, "online right now" end
  end
  if not (row and ns.roster:forget(row)) then return false, "not on your list" end
  local who = row
  if ns.StatsStore then ns.StatsStore.forgetCrew(who) end
  mismatches[who], sreqAt[who], helloAt[who], answeredAt[who] = nil, nil, nil, nil
  ns.Bus.fire("MEMBER_REMOVED", who)
  return true
end

function Crew.start()
  if started then return end
  started = true
  ns.Log.safe(FEATURE, tidyNames, ns.db.roster)
  if type(ns.db.stats) == "table" then ns.Log.safe(FEATURE, tidyNames, ns.db.stats.crew) end
  ns.roster = ns.Roster.new(ns.db.roster)
  for _, name in ipairs(ns.roster.pruned) do
    if ns.StatsStore then ns.StatsStore.forgetCrew(name) end
  end
  ns.Comm.on("HELLO", onHello)
  ns.Comm.on("STATE", onState)
  ns.Comm.on("UPDATE", onState)
  ns.Comm.on("PING", onPing)
  ns.Comm.on("BYE", onBye)
  ns.Comm.on("SREQ", onSreq)
  ns.Events.on(FEATURE, "PLAYER_LOGOUT", sayGoodbye)
  -- The game said whether we are in a guild, or we joined or left one. The login HELLO was kept for that moment (it
  -- goes out, or is dropped outside a guild); joining a guild later needs a new one.
  ns.Bus.on(FEATURE, "TRANSPORT_READY", function()
    local inGuild = ns.Transport.status().mode == "guild"
    if inGuild then saidHelloAt = ns.now() end
    if helloKept then helloKept = false; return end
    if inGuild then
      ns.Comm.send("HELLO", hello())
      ns.Comm.send("STATE", ns.Self.fullState())
    end
  end)
  C_Timer.NewTicker(ns.Config.PING_INTERVAL, function()
    ns.Log.safe(FEATURE, ns.Comm.send, "PING", { h = ns.Self.digest() })
  end)
  C_Timer.NewTicker(ns.Config.OFFLINE_TICK, function()
    ns.Log.safe(FEATURE, function()
      for _, name in ipairs(ns.roster:tick(ns.now())) do ns.Bus.fire("MEMBER_OFFLINE", name) end
    end)
  end)
  helloKept = ns.Transport.isPending()
  if not helloKept then saidHelloAt = ns.now() end
  ns.Comm.send("HELLO", hello())
  ns.Comm.send("STATE", ns.Self.fullState())
end
