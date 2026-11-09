-- Trophy case (Hall of Shame part 2): when a crew session ends, each award's winners get a trophy. Records live in
-- db.stats.trophies[sid] (kept forever) and are swapped pull-only, like the calendar's diaries:
--   TRD  digest: r = the DIGEST_SIZE newest session ids I have (to everyone now and then, and to a friend coming online),
--        l = those of them whose record is late (saved at a login, maybe from numbers of someone who left early)
--   TRQ  "send me session s" (to one friend whose digest has a session I lack, or have only late and they don't)
--   TRP  one session's record (TrophyLogic.toWire), in pieces merged per sender and session until complete;
--        the first record of a session is kept unless one with more people comes, or it is late and the new one isn't
-- Runs under the feature id "trophies" (not a module): it follows the stats module (no records while it is off).
local _, ns = ...

local Trophies = {}
ns.Trophies = Trophies

local FEATURE = "trophies"
local L = ns.TrophyLogic

local DIGEST_SIZE = 10
local DIGEST_CHARS = 200 -- the digest's r is never longer
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
  if old ~= nil then
    -- a full record beats a late one; a late one never beats a full one; otherwise more people wins
    local better
    if type(old) ~= "table" then better = true
    elseif old.late and not r.late then better = true
    elseif r.late and not old.late then better = false
    else better = type(old.people) == "table" and #r.people > #old.people end
    if not better then return false end
  end
  t[r.sid] = r
  cache = nil
  ns.Log.add("info", "trophies: session %s %s (%d people%s)", r.sid, old ~= nil and "replaced" or "recorded",
    #r.people, r.late and ", late" or "")
  ns.Bus.fire("TROPHIES_CHANGED", r.sid)
  return true
end

-- A session just ended (called by Stats before the session numbers are wiped). late: noticed at login, so my
-- numbers may be from when I left; a friend who stayed can send the full record later.
function Trophies.sessionEnded(sid, late)
  if not on() or type(sid) ~= "string" or sid == "" then return end
  local have = Trophies.records()[sid]
  if have and not (type(have) == "table" and have.late and not late) then return end
  local entries = ns.StatsStore.entries("session", sid)
  local r = L.record(sid, entries, ns.StatsLogic.awards(entries), ns.Config.COUCH_MIN_PLAYED)
  if r then
    r.late = late and true or nil
    add(r)
  end
end

function Trophies.summary()
  if not cache then cache = L.summary(Trophies.records()) end
  return cache
end

local function awardName(id)
  for _, d in ipairs(ns.StatsDefs.AWARDS) do if d.id == id then return d.name end end
  return id
end

-- "12 trophies · Professional Corpse streak x3" for the Crew tab's tooltip; nil without trophies.
function Trophies.lineFor(name)
  local p = Trophies.summary()[name]
  if not p or p.total <= 0 then return nil end
  local line = p.total .. (p.total == 1 and " trophy" or " trophies")
  local best, bestN = nil, 1
  for _, d in ipairs(ns.StatsDefs.AWARDS) do
    local n = p.streaks[d.id]
    if n and n > bestN then best, bestN = d.id, n end
  end
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
  -- newest first; the oldest are left out when the list would grow past DIGEST_CHARS
  local out, len = {}, -1
  for i = 1, math.min(DIGEST_SIZE, #list) do
    len = len + 1 + #list[i].sid
    if len > DIGEST_CHARS then break end
    out[i] = list[i].sid
  end
  return out
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
  local ids = newest()
  if #ids == 0 then return end
  local recs, late = Trophies.records(), {}
  for _, sid in ipairs(ids) do
    if type(recs[sid]) == "table" and recs[sid].late then late[#late + 1] = sid end
  end
  sendTo(to, "TRD", { r = table.concat(ids, ","), l = #late > 0 and table.concat(late, ",") or nil })
end

local function known(sender)
  return type(sender) == "string" and not ns.isMe(sender) and not ns.isTestName(sender) and ns.roster
    and ns.roster:get(sender) ~= nil
end

local function onDigest(sender, f)
  if not on() or not known(sender) or type(f) ~= "table" or type(f.r) ~= "string" then return end
  local mine = Trophies.records()
  local theirLate = {}
  if type(f.l) == "string" then for sid in f.l:gmatch("[^,]+") do theirLate[sid] = true end end
  local count, asks = 0, 0
  for sid in f.r:gmatch("[^,]+") do -- newest first
    count = count + 1
    if count > DIGEST_SIZE or asks >= ASKS_PER_DIGEST then break end
    local have = mine[sid]
    -- one I lack, or have only late while theirs is full
    local want = have == nil or (type(have) == "table" and have.late and not theirLate[sid])
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
  sendTo(sender, "TRP", L.toWire(r), { repeatKeys = { "s", "k", "t", "l" } })
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
