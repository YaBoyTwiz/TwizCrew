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

-- Can two friends be compared at all? me / them: { zn, ins, online }. Same zone, both outside instances, online.
function LayerKey.comparable(me, them)
  if not me or not them or them.online == false then return false end
  if me.ins or them.ins then return false end
  if not me.zn or me.zn == "" or not them.zn or them.zn == "" then return false end
  return me.zn == them.zn
end

-- Same / different from what the game shows us, not from layer keys. On WoW Forever two clients on the SAME layer
-- can read different keys from NPCs (seen in game 2026-11-07: "1" vs "11" while together in Darkshore), so keys
-- never decide anything. What does decide:
--   * the friend is visible to us (party unit or nameplate)              -> "same"
--   * the friend is close by map position but the game hides them, for
--     `hiddenFor` seconds in a row                                         -> "different"
--   * otherwise the last verdict stands while both stay in the same zone; never seen -> "unknown".
-- mem: per-friend table kept by the caller. ev: { comparable, visible, dist, connected }.
function LayerKey.judge(mem, ev, now, near, hiddenFor)
  if not ev.comparable then
    mem.verdict, mem.hiddenSince = nil, nil
    return "unknown"
  end
  if ev.visible then
    mem.verdict, mem.hiddenSince = "same", nil
    return "same"
  end
  if ev.visible == false and ev.connected ~= false and type(ev.dist) == "number" and ev.dist <= near then
    mem.hiddenSince = mem.hiddenSince or now
    if now - mem.hiddenSince >= hiddenFor then mem.verdict = "different" end
  else
    mem.hiddenSince = nil
  end
  return mem.verdict or "unknown"
end
