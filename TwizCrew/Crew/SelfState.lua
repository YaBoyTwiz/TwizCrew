-- Your own state: gather what we share, diff against what we last sent, flush changes as UPDATE (ns.Self).
-- ns.Tags and ns.LayerSensor are reached only at call time (they load after this file).
local _, ns = ...

local Self = {}
ns.Self = Self

local FEATURE = "comm"
local EVENTS = {
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "PLAYER_FLAGS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
  "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
}

local last = {}        -- fields as last sent
local scheduled = false

-- Calls a game function that might be missing or fail; returns its first two results or nil.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function Self.gather()
  local _, class = try(UnitClass, "player")
  local level = tonumber(try(UnitLevel, "player")) or 0
  local xp, xpMax = tonumber(try(UnitXP, "player")) or 0, tonumber(try(UnitXPMax, "player")) or 0
  local percent = 0
  if xpMax > 0 then percent = math.floor(xp / xpMax * 100) end
  local inInstance = try(IsInInstance)
  local onTaxi = try(UnitOnTaxi, "player")
  local subzone = try(GetSubZoneText) or ""
  if onTaxi then subzone = "On a flight path" end
  local tags = ns.Tags and ns.Tags.encode(ns.Tags.detectSelf()) or ""
  local layerKey = ns.LayerSensor and ns.LayerSensor.current() or ""
  return {
    cl = tostring(class or ""),
    lv = tostring(level),
    xp = tostring(percent),
    zn = tostring(try(GetRealZoneText) or ""),
    sz = tostring(subzone),
    st = tostring(ns.db and ns.db.myStatus or ""),
    tg = tags,
    lk = tostring(layerKey or ""),
    ins = inInstance and "1" or "0",
    ver = tostring(ns.VERSION),
  }
end

-- Keys of `new` whose string value differs from `old` (a key missing in old counts as changed).
function Self.diff(old, new)
  local changes = {}
  for key, value in pairs(new) do
    if old[key] == nil or tostring(old[key]) ~= tostring(value) then changes[key] = value end
  end
  return changes
end

local function flush()
  scheduled = false
  local now = Self.gather()
  local changes = Self.diff(last, now)
  last = now
  if next(changes) == nil then return end
  ns.Comm.send("UPDATE", changes)
  ns.Bus.fire("SELF_UPDATED", changes)
end

function Self.refresh(reason)
  if scheduled then return end
  scheduled = true
  C_Timer.After(ns.Config.SELF_FLUSH_DELAY, function() ns.Log.safe(FEATURE, flush) end)
end

-- Everything we share; also becomes the new "last sent".
function Self.fullState()
  last = Self.gather()
  return copy(last)
end

function Self.lastSent() return copy(last) end

function Self.setStatus(text)
  local clean = ns.Util.truncateUTF8(ns.Util.trim(tostring(text or "")), ns.Config.STATUS_MAX)
  if ns.db then ns.db.myStatus = clean end
  Self.refresh("status")
end

function Self.start()
  for _, event in ipairs(EVENTS) do
    ns.Events.on(FEATURE, event, function() Self.refresh(event) end)
  end
end
