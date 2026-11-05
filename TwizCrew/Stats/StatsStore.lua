-- Saved numbers (db.stats): my counts per character (this session and all time) and the last numbers each crew
-- member shared (STATS). entries() is what the Hall of Shame and the awards show read.
-- Needs ns.db (after ADDON_LOADED); before that every call is a quiet no-op.
local _, ns = ...

local Store = {}
ns.StatsStore = Store

local Defs = ns.StatsDefs
local KNOWN = {}
for _, key in ipairs(Defs.KEYS) do KNOWN[key] = true end

local isDirty = false -- a number other than time played changed since the last send
local counter = 0     -- makes every snapshot's q different

local function isNumber(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function root()
  if not ns.db then return nil end
  local stats = ns.db.stats
  if type(stats) ~= "table" then stats = {}; ns.db.stats = stats end
  if type(stats.chars) ~= "table" then stats.chars = {} end
  if type(stats.crew) ~= "table" then stats.crew = {} end
  if type(stats.session) ~= "table" then stats.session = {} end
  return stats
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- My record: { sid = "", s = {}, a = {} } (repaired when broken). nil before saved data is loaded.
function Store.mine()
  local stats = root()
  if not stats then return nil end
  local me = ns.playerName()
  local rec = stats.chars[me]
  if type(rec) ~= "table" then rec = {}; stats.chars[me] = rec end
  if type(rec.sid) ~= "string" then rec.sid = "" end
  if type(rec.s) ~= "table" then rec.s = {} end
  if type(rec.a) ~= "table" then rec.a = {} end
  return rec
end

function Store.add(key, n)
  if not KNOWN[key] or not isNumber(n) or n <= 0 then return end
  local rec = Store.mine()
  if not rec then return end
  for _, t in ipairs({ rec.s, rec.a }) do
    local cur = t[key]
    if Defs.MIN_KEYS[key] then
      if not isNumber(cur) or cur <= 0 or n < cur then t[key] = n end
    else
      t[key] = (isNumber(cur) and cur or 0) + n
    end
  end
  if not Defs.TIME_KEYS[key] then isDirty = true end
end

-- view: "session" | "all"
function Store.get(view, key)
  local rec = Store.mine()
  if not rec then return 0 end
  local v = (view == "all" and rec.a or rec.s)[key]
  return isNumber(v) and v or 0
end

-- The session moved from fromId to newId: session counts are kept only when asked and they belong to fromId.
function Store.setSession(newId, fromId, keep)
  local rec = Store.mine()
  if not rec or type(newId) ~= "string" or rec.sid == newId then return end
  if not (keep and fromId ~= nil and rec.sid == fromId) then rec.s = {} end
  rec.sid = newId
  isDirty = true
end

function Store.resetMine()
  local rec = Store.mine()
  if not rec then return end
  rec.s, rec.a = {}, {}
  isDirty = true
end

function Store.dirty() return isDirty end
function Store.markSent() isDirty = false end

-- A copy of my numbers for sending: { sid, q, off, s, a }.
function Store.snapshot(off)
  local rec = Store.mine() or { sid = "", s = {}, a = {} }
  counter = counter + 1
  return {
    sid = rec.sid, q = tostring(ns.wallclock()) .. "-" .. counter, off = off and true or nil,
    s = copy(rec.s), a = copy(rec.a),
  }
end

-- Only known keys with sane numbers (saved data may have been edited or written by a broken copy).
local function clean(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for _, key in ipairs(Defs.KEYS) do
    local v = t[key]
    if isNumber(v) and v >= 0 then out[key] = v end
  end
  return out
end

-- A friend's STATS piece (decoded fields). A new (sid, q) replaces their record, the same (sid, q) merges the
-- piece in; "off" keeps their numbers but hides them until a new snapshot comes. Returns true when saved.
function Store.applyWire(name, fields, wall)
  local snap = ns.StatsLogic.fromWire(fields)
  if not snap or type(name) ~= "string" or name == "" then return false end
  local stats = root()
  if not stats then return false end
  local rec = stats.crew[name]
  if type(rec) ~= "table" then rec = nil end
  if snap.off then
    if not rec then rec = { sid = snap.sid, s = {}, a = {} } end
    rec.off = true
  elseif rec and rec.sid == snap.sid and rec.q == snap.q then -- a later piece (stays hidden if off came first)
    rec.s, rec.a = clean(rec.s), clean(rec.a)
    for key, v in pairs(snap.s) do rec.s[key] = v end
    for key, v in pairs(snap.a) do rec.a[key] = v end
  else
    rec = { sid = snap.sid, q = snap.q, s = snap.s, a = snap.a }
  end
  rec.at = wall
  stats.crew[name] = rec
  return true
end

local function statsOn()
  return ns.Modules.isEnabled("stats")
end

-- view: "session" | "all". Array of { name, class, stats, mine, at, online }, sorted by name: my characters (this
-- one only while the stats module is on) and every crew record that is not off and not one of mine. "session"
-- keeps only records of sessionId (nobody when it is nil) and shows their session numbers.
function Store.entries(view, sessionId)
  local stats = root()
  local out = {}
  if not stats then return out end
  local session = view == "session"
  if session and sessionId == nil then return out end
  local function wanted(rec)
    return type(rec) == "table" and (not session or rec.sid == sessionId)
  end
  local function numbers(rec) return clean(session and rec.s or rec.a) end
  local me = ns.playerName()
  for name, rec in pairs(stats.chars) do
    if type(name) == "string" and wanted(rec) and (name ~= me or statsOn()) then
      local isMe = name == me
      out[#out + 1] = {
        name = name, stats = numbers(rec), mine = true, online = isMe,
        class = isMe and select(2, UnitClass("player")) or nil, at = isMe and ns.wallclock() or nil,
      }
    end
  end
  for name, rec in pairs(stats.crew) do
    if type(name) == "string" and wanted(rec) and not rec.off and stats.chars[name] == nil then
      local m = ns.roster and ns.roster:get(name)
      out[#out + 1] = {
        name = name, stats = numbers(rec), mine = false, online = (m and m.online) and true or false,
        class = m and m.class or nil, at = isNumber(rec.at) and rec.at or nil,
      }
    end
  end
  table.sort(out, function(x, y) return x.name < y.name end)
  return out
end
