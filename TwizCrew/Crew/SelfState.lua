-- Your own state: gather what we share, diff against what we last sent, flush changes as UPDATE (ns.Self).
-- ns.Tags, ns.LayerSensor and ns.Session are reached only at call time (they load after this file).
local _, ns = ...

local Self = {}
ns.Self = Self

local FEATURE = "self"
local EVENTS = {
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "PLAYER_FLAGS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
  "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_EQUIPMENT_CHANGED",
}

local last = {}        -- fields as last sent
local scheduled = false

-- Calls a game function that might be missing, fail or answer with a secret value: nil results then.
local plain = ns.Util.plain

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- A number we may do math on (the value came through plain, so it is not secret): nil when missing or not a real number.
local function readable(v)
  if v == nil then return nil end
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

-- xp (percent), xc (current XP), xm (XP needed for this level; "0" at max level), rx (rested XP; "0" if none).
-- Unreadable numbers keep what was last sent, so a secret value never shows as a drop to 0.
local function xpFields(level)
  local xp, xpMax = readable((plain(UnitXP, "player"))), readable((plain(UnitXPMax, "player")))
  if xp == nil or xpMax == nil then
    return { xp = last.xp or "0", xc = last.xc or "", xm = last.xm or "", rx = last.rx or "0" }
  end
  local maxLevel = readable((plain(GetMaxPlayerLevel)))
  if xpMax <= 0 or (maxLevel and maxLevel > 0 and level >= maxLevel) then
    return { xp = "0", xc = "0", xm = "0", rx = "0" }
  end
  local rested = readable((plain(GetXPExhaustion))) or 0
  return {
    xp = tostring(math.floor(xp / xpMax * 100)),
    xc = tostring(math.floor(math.max(0, xp))),
    xm = tostring(math.floor(xpMax)),
    rx = tostring(math.floor(math.max(0, rested))),
  }
end

function Self.gather()
  local _, class = plain(UnitClass, "player")
  local level = tonumber((plain(UnitLevel, "player"))) or 0
  local x = xpFields(level)
  local inInstance = plain(IsInInstance)
  local onTaxi = plain(UnitOnTaxi, "player")
  local subzone = plain(GetSubZoneText) or ""
  if onTaxi then subzone = "On a flight path" end
  local tags = ns.Tags and ns.Tags.encode(ns.Tags.detectSelf()) or ""
  local layerKey = ns.LayerSensor and ns.LayerSensor.current() or ""
  local q = ns.Quest and ns.Quest.wire() or {}
  local sid, sst = "", ""
  if ns.Session then sid, sst = ns.Session.wire() end
  return {
    cl = tostring(class or ""),
    lv = tostring(level),
    xp = x.xp,
    xc = x.xc, -- level progress: raw numbers for the tooltip and the time-to-level estimate
    xm = x.xm,
    rx = x.rx,
    zn = tostring(plain(GetRealZoneText) or ""),
    sz = tostring(subzone),
    st = tostring(ns.db and ns.db.myStatus or ""),
    tg = tags,
    lk = tostring(layerKey or ""),
    ins = inInstance and "1" or "0",
    sid = tostring(sid or ""),
    sst = tostring(sst or ""),
    ver = tostring(ns.VERSION),
    rs = tostring(ns.RESTART_SINCE), -- a newer copy than a friend's tells it whether a /reload is enough
    qn = tostring(q.qn or ""), -- the quest I'm on, its objectives, "1" = ready to turn in (Quest.wire)
    qo = tostring(q.qo or ""),
    qc = tostring(q.qc or ""),
    qi = tostring(q.qi or ""), -- its quest ID and whether it can be shared (friends see if they can get it)
    qs = tostring(q.qs or ""),
    lo = ns.MockShow and ns.MockShow.myLook() or "", -- race, gender and visible gear (the mock show's stand-in)
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

-- Keys that never send a message on their own: they wait for the next UPDATE that goes out anyway (the XP
-- percent, a fight starting or ending, a zone change...), so earning XP adds no messages.
local RIDE_ALONG = { xc = true, rx = true }

local function onlyRideAlong(changes)
  for key in pairs(changes) do
    if not RIDE_ALONG[key] then return false end
  end
  return true
end

local function flush()
  scheduled = false
  local now = Self.gather()
  local changes = Self.diff(last, now)
  if next(changes) == nil or onlyRideAlong(changes) then return end -- "last" keeps the old xc / rx: they stay changed
  last = now
  ns.Comm.send("UPDATE", changes)
  ns.Bus.fire("SELF_UPDATED", changes)
end

function Self.refresh(reason)
  if scheduled then return end
  scheduled = true
  C_Timer.After(ns.Config.SELF_FLUSH_DELAY, function() ns.Log.safe(FEATURE, flush) end)
end

-- Everything we share; also becomes the new "last sent" (and tells the rest of the addon what changed).
function Self.fullState()
  local now = Self.gather()
  local changes = Self.diff(last, now)
  last = now
  if next(changes) ~= nil then ns.Bus.fire("SELF_UPDATED", changes) end
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
