-- Layer key logic (pure): read a zone id from an NPC GUID, confirm it over several looks, compare two players.
local _, ns = ...

local LayerKey = {}
ns.LayerKey = LayerKey

-- "Creature-0-4372-0-2345-299-0000ABCDEF" -> "2345". Players, pets and anything odd give nil.
function LayerKey.fromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, zoneUID = guid:match("^([^-]+)%-([^-]*)%-([^-]*)%-([^-]*)%-([^-]*)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  if not zoneUID or not zoneUID:match("^%d+$") or zoneUID == "0" then return nil end
  return zoneUID
end

local Tracker = {}
Tracker.__index = Tracker

-- A new value becomes current only after `confirmations` looks in a row; the current value goes stale
-- after `staleAfter` seconds without being seen again.
function LayerKey.newTracker(confirmations, staleAfter)
  return setmetatable({ need = confirmations, staleAfter = staleAfter, count = 0 }, Tracker)
end

function Tracker:observe(zoneUID, now)
  if zoneUID == self.key then
    self.seenAt = now
    self.pending, self.count = nil, 0
    return false
  end
  if zoneUID == self.pending then
    self.count = self.count + 1
  else
    self.pending, self.count = zoneUID, 1
  end
  if self.count >= self.need then
    self.key, self.seenAt = zoneUID, now
    self.pending, self.count = nil, 0
    return true
  end
  return false
end

function Tracker:current(now)
  if self.key and now - self.seenAt > self.staleAfter then return nil end
  return self.key
end

function Tracker:reset()
  self.key, self.seenAt, self.pending, self.count = nil, nil, nil, 0
end

function Tracker:info(now)
  local key = self:current(now)
  return { key = key, age = key and (now - self.seenAt) or nil, pending = self.pending }
end

-- me / them: { lk, zn, ins, online }. Anything doubtful is "unknown", never "different".
function LayerKey.relation(me, them)
  if not me or not them or them.online == false then return "unknown" end
  if not me.lk or me.lk == "" or not them.lk or them.lk == "" then return "unknown" end
  if me.ins or them.ins then return "unknown" end
  if not me.zn or me.zn == "" or not them.zn or them.zn == "" or me.zn ~= them.zn then return "unknown" end
  return me.lk == them.lk and "same" or "different"
end
