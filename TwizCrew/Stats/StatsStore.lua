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
  -- zones seen (names -> true): this session and all time, for "zv" (Tourist)
  if type(rec.zs) ~= "table" then rec.zs = {} end
  if type(rec.za) ~= "table" then rec.za = {} end
  return rec
end

function Store.add(key, n)
  if not KNOWN[key] or not isNumber(n) or n <= 0 then return end
  local rec = Store.mine()
  if not rec then return end
  local s, a = rec.s, rec.a -- both views, written out (no table per call)
  local cur
  if Defs.MIN_KEYS[key] then
    cur = s[key]
    if not isNumber(cur) or cur <= 0 or n < cur then s[key] = n end
    cur = a[key]
    if not isNumber(cur) or cur <= 0 or n < cur then a[key] = n end
  else
    cur = s[key]
    s[key] = (isNumber(cur) and cur or 0) + n
    cur = a[key]
    a[key] = (isNumber(cur) and cur or 0) + n
  end
  if not Defs.TIME_KEYS[key] then isDirty = true end
end

-- A set key (Defs.SET_KEYS): the number now, the same in both views. Returns true when it changed.
function Store.set(key, value)
  if not Defs.SET_KEYS[key] or not isNumber(value) or value < 0 then return false end
  local rec = Store.mine()
  if not rec then return false end
  if rec.s[key] == value and rec.a[key] == value then return false end
  rec.s[key], rec.a[key] = value, value
  isDirty = true
  return true
end

-- A zone visited: "zv" goes up by one in each view where it is new. Returns true when it was new anywhere.
function Store.addZone(zone)
  if type(zone) ~= "string" or zone == "" then return false end
  local rec = Store.mine()
  if not rec then return false end
  local added = false
  for _, pair in ipairs({ { rec.zs, rec.s }, { rec.za, rec.a } }) do
    local seen, t = pair[1], pair[2]
    if not seen[zone] then
      seen[zone] = true
      t.zv = (isNumber(t.zv) and t.zv or 0) + 1
      added = true
    end
  end
  if added then isDirty = true end
  return added
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
  if not (keep and fromId ~= nil and rec.sid == fromId) then
    rec.s, rec.zs = {}, {}
    -- A set key (gold carried) is the same number in both views, so it carries into the new session.
    for key in pairs(Defs.SET_KEYS) do rec.s[key] = rec.a[key] end
  end
  rec.sid = newId
  isDirty = true
end

function Store.resetMine()
  local rec = Store.mine()
  if not rec then return end
  rec.s, rec.a, rec.zs, rec.za = {}, {}, {}, {}
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

-- q is "<sender's wallclock>-<counter>" (every copy, v0.1.23 too): is a older than b? Unreadable ones never are.
local function older(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local ta, ca = a:match("^(%d+)%-(%d+)$")
  local tb, cb = b:match("^(%d+)%-(%d+)$")
  if not ta or not tb then return false end
  ta, ca, tb, cb = tonumber(ta), tonumber(ca), tonumber(tb), tonumber(cb)
  return ta < tb or (ta == tb and ca < cb)
end

-- Per friend, this login only: got = the keys of snapshot q received so far ("s_dt" -> true), at = ns.now() of
-- their last piece (Steals waits for a whole snapshot).
local heard = {}

local function lay(into, from, got, prefix)
  for key, v in pairs(from) do
    into[key] = v
    got[prefix .. key] = true
  end
end

-- Drops what snapshot got (complete by now) did not carry: a number that went back to 0 (a reset) is not sent.
local function prune(t, got, prefix)
  for key in pairs(t) do
    if not got[prefix .. key] then t[key] = nil end
  end
end

-- A friend's STATS piece (decoded fields). A snapshot older than the saved one (by q) is ignored. A new snapshot's
-- pieces are laid over the saved numbers (no zeros while the rest is on its way); when the next snapshot starts,
-- what the last one did not carry is dropped. A new sid starts the session numbers fresh and keeps the old
-- session's in rec.prev (their STATS can arrive before the UPDATE that ends my session); all-time numbers are
-- always laid over. "off" keeps their numbers but hides them until a new snapshot comes. Returns true when saved.
function Store.applyWire(name, fields, wall)
  local snap = ns.StatsLogic.fromWire(fields)
  if not snap or type(name) ~= "string" or name == "" then return false end
  local stats = root()
  if not stats then return false end
  local rec = stats.crew[name]
  if type(rec) ~= "table" then rec = nil end
  if rec and older(snap.q, rec.q) then return false end
  local h = heard[name]
  if snap.off then
    if not rec then rec = { sid = snap.sid, s = {}, a = {} } end
    rec.off = true
  else
    if rec then rec.s, rec.a = clean(rec.s), clean(rec.a) else rec = { sid = snap.sid, s = {}, a = {} } end
    if rec.sid ~= snap.sid or rec.q ~= snap.q then -- a new snapshot (a later piece stays hidden if off came first)
      if h and h.q ~= nil and h.q == rec.q then
        prune(rec.s, h.got, "s_")
        prune(rec.a, h.got, "a_")
      end
      if rec.sid ~= snap.sid then
        if not rec.off then rec.prev = { sid = rec.sid, s = rec.s, at = rec.at } end
        rec.s = {}
      end
      rec.sid, rec.q, rec.off = snap.sid, snap.q, nil
      h = { q = snap.q, got = {} }
      heard[name] = h
    end
    if not h then h = { got = {} }; heard[name] = h end -- snapshot begun before this login: nothing to drop later
    lay(rec.s, snap.s, h.got, "s_")
    lay(rec.a, snap.a, h.got, "a_")
  end
  if not h then h = { got = {} }; heard[name] = h end
  h.at = ns.now()
  rec.at = wall
  stats.crew[name] = rec
  return true
end

-- Seconds since a friend's last STATS piece arrived (nil: none this login).
function Store.heardAgo(name)
  local h = heard[name]
  return h and h.at and ns.now() - h.at or nil
end

-- Drops a friend's saved numbers (they were forgotten, or expired).
function Store.forgetCrew(name)
  heard[name] = nil
  local stats = root()
  if stats and stats.crew then stats.crew[name] = nil end
end

local function statsOn()
  return ns.Modules.isEnabled("stats")
end

-- view: "session" | "all". Array of { name, class, stats, mine, at, online }, sorted by name: my characters (this
-- one only while the stats module is on) and every crew record that is not off and not one of mine. "session"
-- keeps only records of sessionId (nobody when it is nil) and shows their session numbers; a friend who already
-- moved on is listed with their numbers from that session (rec.prev).
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
    if type(rec) == "table" and session and rec.sid ~= sessionId and type(rec.prev) == "table"
      and rec.prev.sid == sessionId then
      rec = { sid = sessionId, s = rec.prev.s, at = rec.prev.at, off = rec.off }
    end
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
