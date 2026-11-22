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
local sreqDue = {}     -- name -> true while an SREQ to them waits its random delay
local stateAt = {}     -- name -> time their last STATE (piece) arrived
local helloWaiting = {} -- name -> true while our answer to their HELLO waits for the guild list to know them
local answeredAt = {}  -- name -> time we last answered their SREQ

-- Spreads the reading of a hash (hashNumber is nearly linear in the last letters).
local function mixed(s) return ns.Util.hashNumber(tostring(ns.Util.hashNumber(s)) .. s) end

-- Is this copy one of the about k (RESPONDERS) copies that answer for the crew when `name` comes online (session,
-- digests)? Every copy decides the same way without talking: it ranks the online copies it knows (itself included,
-- `name` left out) by a hash of key .. name and answers when it is among the first k, or when fewer than k others are
-- online. Copies may disagree a little (their rosters differ): then a few more or fewer answer.
function Crew.isResponder(name, k)
  k = k or ns.Config.RESPONDERS
  name = tostring(name)
  local me = ns.myKey()
  local mine = mixed(me .. "|" .. name)
  local rank, others = 1, 0
  for _, m in ipairs(ns.roster and ns.roster:members() or {}) do
    if m.online and m.name ~= name and not ns.isMe(m.name) then
      others = others + 1
      local h = mixed(m.name .. "|" .. name)
      if h < mine or (h == mine and m.name < me) then rank = rank + 1 end
    end
  end
  return others < k or rank <= k
end

local function noteVersion(name, ver, rs)
  if ns.Version and ns.Version.seen and type(ver) == "string" then ns.Version.seen(name, ver, rs) end
end

local function hello() return { ver = ns.VERSION, rs = ns.RESTART_SINCE } end

-- A hidden member (out of the guild: the guild list is behind) tells the rest of the addon nothing.
local function announce(name, m, changes, events)
  if ns.roster:isHidden(name) then return end
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

-- Our STATE to someone who said HELLO, by whisper. False while they cannot be whispered (the guild list does not
-- have them yet).
local function answerHello(name)
  if not ns.Comm.sendTo(name, "STATE", ns.Self.stateFor()) then return false end
  replyPending[name], helloWaiting[name] = nil, nil
  return true
end

-- A newcomer gets our STATE as a whisper (only a STATE: a HELLO back would make them answer every copy in the guild),
-- after a random 0 to HELLO_REPLY_JITTER seconds so that, with many copies online, the answers do not land at once.
-- When the guild list does not have them yet, the answer waits for the next list (at most HELLO_LIST_WAIT s); never
-- a STATE to the whole guild instead (every copy would send one).
local function onHello(sender, fields)
  -- A HELLO starts a new play session for them: what we knew about their layer, dungeon and tags is old.
  -- No rs = an older copy: forget the rs it may have sent before (when it was a newer copy).
  local cleared = ns.roster:clearSession(sender)
  -- A STATE always follows a HELLO: what they sent before no longer counts for the digest.
  local m = ns.roster:row(sender)
  if m then m.raw = {} end
  onState(sender, { ver = fields.ver, rs = fields.rs or "" }, cleared)
  if replyPending[sender] then return end
  replyPending[sender] = true
  C_Timer.After(math.random() * ns.Config.HELLO_REPLY_JITTER, function()
    ns.Log.safe(FEATURE, function()
      if answerHello(sender) then return end
      helloWaiting[sender] = true
      if ns.Guild then ns.Guild.refresh() end
      C_Timer.After(ns.Config.HELLO_LIST_WAIT, function()
        ns.Log.safe(FEATURE, function()
          if helloWaiting[sender] then helloWaiting[sender], replyPending[sender] = nil, nil end -- given up
        end)
      end)
    end)
  end)
end

-- A new guild list (or the transport ready at last): answer the HELLOs that were waiting for it.
local function onGuildList()
  local names = {}
  for name in pairs(helloWaiting) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do answerHello(name) end
end

local function onPing(sender, fields)
  if not ns.roster:row(sender) then
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
    if e == "online" and not ns.roster:isHidden(sender) then ns.Bus.fire("MEMBER_ONLINE", sender) end
  end
  -- The digest shows a lost message: two PINGs in a row that disagree (one may just have passed an update in
  -- flight) make us ask for their whole state, at most once per ping interval. No "h" = an old copy: never a mismatch.
  local h = type(fields) == "table" and fields.h
  if type(h) ~= "string" then return end
  if h == ns.roster:digest(sender) then mismatches[sender] = nil; return end
  mismatches[sender] = (mismatches[sender] or 0) + 1
  if mismatches[sender] < 2 then return end
  local now = ns.now()
  if sreqDue[sender] or (sreqAt[sender] and now - sreqAt[sender] < ns.Config.PING_INTERVAL) then return end
  -- wait a random moment (many copies may notice the same loss at once); their STATE meanwhile settles it
  sreqDue[sender] = true
  C_Timer.After(math.random() * ns.Config.SREQ_JITTER, function()
    ns.Log.safe(FEATURE, function()
      sreqDue[sender] = nil
      if stateAt[sender] and stateAt[sender] > now then mismatches[sender] = nil; return end
      if ns.Comm.sendTo(sender, "SREQ", {}) then -- not whisperable yet (guild list not loaded): the next PING asks
        mismatches[sender] = nil
        sreqAt[sender] = ns.now()
        ns.Log.count("sent SREQ")
      end
    end)
  end)
end

-- Answered at most once per ping interval for each asker. Several asks within SREQ_COLLECT seconds (many copies lost
-- the same message) get one STATE to the guild; a single one a whisper.
local function onSreq(sender)
  local now = ns.now()
  if answeredAt[sender] and now - answeredAt[sender] < ns.Config.PING_INTERVAL then return end
  answeredAt[sender] = now
  ns.Comm.answerAsk("STATE", sender, function(to)
    local state = ns.Self.stateFor()
    if not (to and ns.Comm.sendTo(to, "STATE", state)) then ns.Comm.send("STATE", state, { replace = "SREQ" }) end
  end, ns.Config.SREQ_COLLECT)
end

local function onBye(sender)
  local m = ns.roster:row(sender)
  if not m then return end
  local wasOnline = m.online
  ns.roster:gone(sender)
  if wasOnline and not ns.roster:isHidden(sender) then ns.Bus.fire("MEMBER_OFFLINE", sender) end
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
  local given = {}        -- keys the guild list gave out
  local givenOther = {}   -- lower(key) -> true when a saved full name other than mine holds it
  local uname = ns.Util.plain(UnitName, "player")
  uname = type(uname) == "string" and uname:lower() or nil
  local first = ns.playerName():lower()
  local saved = ns.db and type(ns.db.guild) == "table" and ns.db.guild.keys
  if type(saved) == "table" then
    for full, key in pairs(saved) do
      if type(key) == "string" then
        given[key] = true
        if type(full) == "string" and full ~= uname then givenOther[key:lower()] = true end
      end
    end
  end
  -- "that is me" here, before the guild list can tell: exactly my game name, or a single word that is my first word
  -- and nobody else's saved key. A key of several words is never mine on a first-word match.
  local function mine(key)
    local l = key:lower()
    if l == uname then return true end
    return not l:find(" ", 1, true) and l == first and not givenOther[l]
  end
  local keys = {}
  for key in pairs(list) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    if type(key) == "string" and not given[key] then
      local base = key:match("^([^%-]+)%-.+$") or key -- "Twiz-Realm" -> "Twiz"
      if mine(base) then
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

-- Takes the roster row `key` (exactly: the row menu, the 30-day rule) out of the roster and the saved numbers when
-- that friend is offline. Returns true, or false and a short reason.
function Crew.forgetRow(key)
  local m = ns.roster and type(key) == "string" and ns.roster:row(key)
  if not m then return false, "not on your list" end
  if m.online then return false, "online right now" end
  if not ns.roster:forget(key) then return false, "not on your list" end
  if ns.StatsStore then ns.StatsStore.forgetCrew(key) end
  mismatches[key], sreqAt[key], helloAt[key], answeredAt[key], stateAt[key] = nil, nil, nil, nil, nil
  sreqDue[key], helloWaiting[key], replyPending[key] = nil, nil, nil
  ns.Bus.fire("MEMBER_REMOVED", key)
  return true
end

-- The row a typed name means, in this order (any case): a current member's exact full name, a current member's
-- exact key, a saved row's exact name (hidden rows too), and only then a first word exactly one row or member has.
-- Returns the row (or nil), the member's key (or nil), and "which one" plus the names when the first word fits
-- several.
local function rowFor(name)
  local G = ns.Guild
  local low = ns.Util.trim(name):lower()
  local rows = ns.roster:allNames()
  local function rowOf(key)
    for _, n in ipairs(rows) do if n:lower() == key:lower() then return n end end
    return nil
  end
  if G and G.loaded() then
    for _, e in ipairs(G.members()) do
      if e.full:lower() == low then return rowOf(e.key), e.key end
    end
    for _, e in ipairs(G.members()) do
      if e.key:lower() == low then return rowOf(e.key), e.key end
    end
  end
  local exact = rowOf(low)
  if exact then return exact, nil end
  if low:find(" ", 1, true) then return nil, nil end
  local found, list = {}, {}
  local function add(key, shown)
    if not found[key] then found[key] = true; list[#list + 1] = { key = key, shown = shown } end
  end
  for _, n in ipairs(rows) do
    if (n:match("^(%S+)") or n):lower() == low then add(n, n) end
  end
  if G and G.loaded() then
    for _, e in ipairs(G.members()) do
      if e.first:lower() == low then add(e.key, e.full) end
    end
  end
  if #list == 1 then return rowOf(list[1].key), list[1].key end
  if #list > 1 then
    local names = {}
    for i, x in ipairs(list) do names[i] = x.shown end
    table.sort(names)
    return nil, nil, "which one", names
  end
  return nil, nil
end

-- Takes a friend who is offline out of the roster and the saved numbers, by a typed name (first word or full name,
-- any case). Returns true and the row's key when something was removed; otherwise false and a short reason (never
-- you, never an online friend, "which one" for a first word two members share).
function Crew.forget(name)
  if type(name) ~= "string" or name == "" then return false, "no name" end
  if not ns.roster then return false, "not on your list" end
  local row, key, why, names = rowFor(name)
  if why then return false, why, names end
  if ns.isMe(key or row or name) then return false, "that is you" end
  if not row then return false, "not on your list" end
  local ok, reason = Crew.forgetRow(row)
  if not ok then return false, reason end
  return true, row
end

local tidied = false -- the saved rows were tidied this session (only once they are known to be this guild's)

-- Once a session, when the guild says the data in use is its own: old "Name-Realm" keys and my own ghost go
-- (tidyNames), and friends not seen for FORGET_AFTER_DAYS go, unless they are on the guild list now; that last step
-- only while the saved friends fit the guild's complete list (Guild.listFits), so a set used in a guild that is not
-- its own forgets nothing.
local function tidy()
  tidied = true
  local before = ns.Util.copy(ns.roster:allNames())
  ns.Log.safe(FEATURE, tidyNames, ns.db.roster)
  if type(ns.db.stats) == "table" then ns.Log.safe(FEATURE, tidyNames, ns.db.stats.crew) end
  ns.roster:reload()
  for _, name in ipairs(before) do
    if not ns.roster:row(name) then ns.Bus.fire("MEMBER_REMOVED", name) end
  end
  if not ns.Guild.listFits() then return end
  local onList = function(name) return ns.Guild.get(name) ~= nil end
  for _, name in ipairs(ns.roster:pruneOld(ns.wallclock(), onList)) do
    if ns.StatsStore then ns.StatsStore.forgetCrew(name) end
    ns.Bus.fire("MEMBER_REMOVED", name)
  end
end

-- The guild list loaded or changed: who is hidden (out of the guild) and who is shown again. Nothing is deleted for
-- that (see tidy).
local function followGuild()
  if not tidied and ns.Guild and ns.Guild.writable() and ns.Guild.complete() then tidy() end
  for _, name in ipairs(ns.roster:syncGuild()) do
    local m = ns.roster:row(name)
    ns.Bus.fire("MEMBER_UPDATED", name, { inGuild = m and m.inGuild or false })
  end
end

function Crew.start()
  if started then return end
  started = true
  ns.roster = ns.Roster.new(ns.db.roster)
  ns.roster:setGuild(ns.Guild)
  ns.Log.safe(FEATURE, followGuild)
  ns.Comm.on("HELLO", onHello)
  ns.Comm.on("STATE", function(sender, fields)
    stateAt[sender] = ns.now()
    onState(sender, fields)
  end)
  ns.Comm.on("UPDATE", onState)
  ns.Comm.on("PING", onPing)
  ns.Comm.on("BYE", onBye)
  ns.Comm.on("SREQ", onSreq)
  ns.Events.on(FEATURE, "PLAYER_LOGOUT", sayGoodbye)
  ns.Bus.on(FEATURE, "GUILD_LIST", function()
    followGuild()
    onGuildList()
  end)
  -- The game said whether we are in a guild, or we joined or left one. The login HELLO was kept for that moment (it
  -- goes out, or is dropped outside a guild); joining a guild later needs a new one.
  ns.Bus.on(FEATURE, "TRANSPORT_READY", function()
    onGuildList()
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
      for _, name in ipairs(ns.roster:tick(ns.now())) do
        if not ns.roster:isHidden(name) then ns.Bus.fire("MEMBER_OFFLINE", name) end
      end
    end)
  end)
  helloKept = ns.Transport.isPending()
  if not helloKept then saidHelloAt = ns.now() end
  ns.Comm.send("HELLO", hello())
  ns.Comm.send("STATE", ns.Self.fullState())
end
