-- Trophy case (Hall of Shame part 2): when a crew session ends, each award's winners get a trophy. Records live in
-- db.stats.trophies[sid] (kept forever) and are swapped pull-only, like the calendar's diaries:
--   TRD  digest: r = my newest session ids, newest first, "<sid>" for a full record and "<sid>*<e>" for a late one
--        (saved at a login from the numbers I had; e = how fresh they are). Always one piece: the oldest are left out.
--        Sent to everyone now and then, and to a friend coming online.
--   TRQ  "send me session s" (to one friend whose digest has a record that would replace mine, see below)
--   TRP  one session's record (TrophyLogic.toWire), in pieces merged per sender and session until complete.
-- Which record of a session is kept (TrophyLogic.better): full beats late regardless of people; late never beats
-- full; two late ones: the higher e wins; otherwise strictly more people wins (a tie keeps mine). A digest asks
-- only for records that would win, so copies never ask each other in a loop.
-- Runs under the feature id "trophies" (not a module): it follows the stats module (no records while it is off).
local _, ns = ...

local Trophies = {}
ns.Trophies = Trophies

local FEATURE = "trophies"
local L = ns.TrophyLogic

local DIGEST_SIZE = 10
local DIGEST_EVERY = 600 -- seconds between digests to everyone
local FIRST_DIGEST = 25  -- after login
local ASK_GAP = 120      -- seconds before asking for the same session again
local ASKS_PER_DIGEST = 3 -- the next digest asks for the rest
local SEND_GAP = 30      -- seconds before sending the same record to the same friend again
local PIECE_LIFE = 60    -- seconds an incomplete record waits for its other pieces

local askedAt, sentAt, pending = {}, {}, {}
local cache
local started = false

local function store()
  if not ns.db then return nil end
  if type(ns.db.stats) ~= "table" then ns.db.stats = {} end
  if type(ns.db.stats.trophies) ~= "table" then ns.db.stats.trophies = {} end
  return ns.db.stats.trophies
end

local function on() return ns.Modules.isEnabled("stats") end

function Trophies.records() return store() or {} end

local function add(r)
  local t = store()
  if not t or type(r) ~= "table" then return false end
  local old = t[r.sid]
  if old ~= nil and not L.better(old, r) then return false end
  t[r.sid] = r
  cache = nil
  ns.Log.add("info", "trophies: session %s %s (%d people%s)", r.sid, old ~= nil and "replaced" or "recorded",
    #r.people, r.late and ", late" or "")
  ns.Bus.fire("TROPHIES_CHANGED", r.sid)
  return true
end

-- How fresh a late record's numbers are: the newest of my last moment in that session (saved before this login)
-- and when each friend's numbers were heard. My own entry's at is "now", so it is left out.
local function freshness(sid, entries)
  local e = ns.Session and ns.Session.previousLastActive and ns.Session.previousLastActive(sid) or 0
  for _, x in ipairs(entries) do
    if not x.mine and type(x.at) == "number" and x.at > e then e = x.at end
  end
  return math.floor(e)
end

-- The last Clown of the Night voted in this session (db.stats.clownBySid[sid], saved by the awards show) gets a
-- trophy: only names in the record's people. A later "no clown" clears the title, not this.
local function clownOf(r)
  local by = ns.db and type(ns.db.stats) == "table" and ns.db.stats.clownBySid
  local names = type(by) == "table" and by[r.sid]
  if type(names) ~= "table" then return end
  local people, list = {}, {}
  for _, name in ipairs(r.people) do people[name] = true end
  for _, name in ipairs(names) do
    if people[name] then list[#list + 1] = name; people[name] = nil end
  end
  table.sort(list)
  if #list > 0 then r.winners.clown = list end
end

-- A session just ended (called by Stats before the session numbers are wiped). late: noticed at login, so my
-- numbers may be from when I left; a friend who stayed can send a better record later.
function Trophies.sessionEnded(sid, late)
  if not on() or type(sid) ~= "string" or sid == "" then return end
  local have = Trophies.records()[sid]
  if type(have) == "table" and not have.late then return end -- a full one is never replaced from here
  local entries = ns.StatsStore.entries("session", sid)
  local r = L.record(sid, entries, ns.StatsLogic.awards(entries), ns.Config.COUCH_MIN_PLAYED)
  if r then
    clownOf(r)
    if late then r.late, r.e = true, freshness(sid, entries) end
    add(r)
  end
end

function Trophies.summary()
  if not cache then cache = L.summary(Trophies.records()) end
  return cache
end

local function awardName(id)
  local d = ns.StatsDefs.trophyDef(id)
  return d and d.name or id
end

-- "12 trophies · Professional Corpse streak x3" for the Crew tab's tooltip; nil without trophies.
function Trophies.lineFor(name)
  local p = Trophies.summary()[name]
  if not p or p.total <= 0 then return nil end
  local line = p.total .. (p.total == 1 and " trophy" or " trophies")
  local best, bestN = nil, 1
  local function look(list)
    for _, d in ipairs(list) do
      local n = p.streaks[d.id]
      if n and n > bestN then best, bestN = d.id, n end
    end
  end
  look(ns.StatsDefs.AWARDS)
  look(ns.StatsDefs.EXTRA_TROPHIES)
  if best then line = line .. " · " .. awardName(best) .. " streak x" .. bestN end
  return line
end

---------------------------------------------------------------------------------------------------------- swap
local function newest()
  local list = {}
  for sid, r in pairs(Trophies.records()) do list[#list + 1] = { sid = sid, start = tonumber(r.start) or 0 } end
  table.sort(list, function(a, b)
    if a.start ~= b.start then return a.start > b.start end
    return a.sid > b.sid
  end)
  local out = {}
  for i = 1, math.min(DIGEST_SIZE, #list) do out[i] = list[i].sid end
  return out
end

-- The whole TRD fits one piece, nothing cut (a cut or split digest would be misread).
local function onePiece(fields)
  local out = ns.Codec.encode("TRD", fields)
  local msg = #out == 1 and ns.Codec.decode(out[1])
  return msg and msg.fields.r == fields.r or false
end

-- The digest's fields: newest first, the oldest dropped until it fits one piece. nil when I have none.
function Trophies.digest()
  local recs, items = Trophies.records(), {}
  for _, sid in ipairs(newest()) do items[#items + 1] = L.digestEntry(sid, recs[sid]) end
  while #items > 0 do
    local fields = { r = table.concat(items, ",") }
    if onePiece(fields) then return fields end
    items[#items] = nil
  end
  return nil
end

local function sendTo(name, msgType, fields, opts)
  if name then
    if not ns.Comm.sendTo(name, msgType, fields, opts) then ns.Comm.send(msgType, fields, opts) end
  else
    ns.Comm.send(msgType, fields, opts)
  end
end

function Trophies.sendDigest(to)
  if not on() then return end
  local fields = Trophies.digest()
  if fields then sendTo(to, "TRD", fields) end
end

local function known(sender)
  return type(sender) == "string" and not ns.isMe(sender) and not ns.isTestName(sender) and ns.roster
    and ns.roster:get(sender) ~= nil
end

local function onDigest(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.r) ~= "string" then return end
  local mine = Trophies.records()
  local asks = 0
  for i, x in ipairs(L.parseDigest(f.r)) do -- newest first
    if i > DIGEST_SIZE or asks >= ASKS_PER_DIGEST then break end
    local sid, have = x.sid, mine[x.sid]
    -- only when theirs would replace mine: I lack it, mine is late and theirs full, or both late and theirs fresher
    local want = type(have) ~= "table" or (have.late and (not x.late or x.e > (tonumber(have.e) or 0)))
    if want and (not askedAt[sid] or ns.now() - askedAt[sid] >= ASK_GAP) then
      askedAt[sid] = ns.now()
      asks = asks + 1
      sendTo(sender, "TRQ", { s = sid })
    end
  end
end

local function onAsk(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.s) ~= "string" then return end
  local r = Trophies.records()[f.s]
  if not r then return end
  local key = f.s .. ">" .. sender
  if sentAt[key] and ns.now() - sentAt[key] < SEND_GAP then return end
  sentAt[key] = ns.now()
  sendTo(sender, "TRP", L.toWire(r), { repeatKeys = { "s", "k", "t", "l", "e" }, bulk = true })
end

local function onRecord(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.s) ~= "string" then return end
  local key = sender .. ">" .. f.s
  local p = pending[key]
  if not p or ns.now() - p.at > PIECE_LIFE then p = { at = ns.now(), fields = {} }; pending[key] = p end
  for k, v in pairs(f) do p.fields[k] = v end
  local r = L.fromPieces(p.fields)
  if r then
    pending[key] = nil
    add(r)
  end
end

ns.Comm.on("TRD", function(s, f) ns.Log.safe(FEATURE, onDigest, s, f) end)
ns.Comm.on("TRQ", function(s, f) ns.Log.safe(FEATURE, onAsk, s, f) end)
ns.Comm.on("TRP", function(s, f) ns.Log.safe(FEATURE, onRecord, s, f) end)

-- Started by the stats module (onEnable); the timers do nothing while stats are off.
function Trophies.start()
  if started then return end
  started = true
  ns.Bus.on(FEATURE, "TROPHIES_CHANGED", function() cache = nil end)
  C_Timer.After(FIRST_DIGEST, function() ns.Log.safe(FEATURE, Trophies.sendDigest) end)
  C_Timer.NewTicker(DIGEST_EVERY, function() ns.Log.safe(FEATURE, Trophies.sendDigest) end)
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", function(name)
    if ns.isTestName(name) then return end
    C_Timer.After(5, function() ns.Log.safe(FEATURE, Trophies.sendDigest, name) end)
  end)
end
