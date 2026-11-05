-- Saved numbers (db.stats): my counts per character (this session and all time); crew records come in Task 6.
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
