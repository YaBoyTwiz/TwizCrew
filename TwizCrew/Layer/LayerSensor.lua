-- Own layer key from the NPCs you look at. Always runs (sharing is essential): feature id "comm".
local _, ns = ...

local Sensor = {}
ns.LayerSensor = Sensor

local FEATURE = "comm"
local tracker
local observations, secretSkipped = 0, 0
local lastGroup = false
local lastReported -- the key we last told SelfState about, to notice it going stale
local started = false

local function refresh()
  lastReported = Sensor.current()
  ns.Self.refresh("layer")
end

local function zone()
  if type(GetRealZoneText) ~= "function" then return "?" end
  local ok, z = pcall(GetRealZoneText)
  return ok and tostring(z or "?") or "?"
end

local function look(unit)
  if type(UnitGUID) ~= "function" then return end
  local guid = UnitGUID(unit)
  -- A secret value may not even be compared, so this check comes before anything else touches it.
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, guid)
    if not ok or secret then
      secretSkipped = secretSkipped + 1
      return
    end
  end
  if guid == nil then return end
  local key = ns.LayerKey.fromGUID(guid)
  if not key then return end
  observations = observations + 1
  if tracker:observe(key, ns.now()) then
    ns.Log.add("info", "layer key %s confirmed in %s (%s)", key, zone(), tostring(unit))
    refresh()
  end
end

local function reset(reason)
  ns.Log.add("info", "layer key reset in %s (%s)", zone(), reason)
  tracker:reset()
  refresh()
end

function Sensor.current()
  return tracker and tracker:current(ns.now()) or nil
end

function Sensor.info()
  local i = tracker and tracker:info(ns.now()) or {}
  return { key = i.key, age = i.age, pending = i.pending, observations = observations, secretSkipped = secretSkipped }
end

function Sensor.start()
  if started then return end
  started = true
  tracker = ns.LayerKey.newTracker(ns.Config.LAYER_CONFIRMATIONS, ns.Config.LAYER_STALE_AFTER)
  lastGroup = IsInGroup and IsInGroup() or false
  ns.Events.on(FEATURE, "UPDATE_MOUSEOVER_UNIT", function() look("mouseover") end)
  ns.Events.on(FEATURE, "PLAYER_TARGET_CHANGED", function() look("target") end)
  ns.Events.on(FEATURE, "NAME_PLATE_UNIT_ADDED", function(unit) look(unit) end)
  ns.Events.on(FEATURE, "ZONE_CHANGED_NEW_AREA", function() reset("zone change") end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() reset("loading screen") end)
  ns.Events.on(FEATURE, "GROUP_ROSTER_UPDATE", function()
    local now = IsInGroup and IsInGroup() or false
    if now ~= lastGroup then
      lastGroup = now
      reset(now and "joined a group" or "left the group")
    end
  end)
  C_Timer.NewTicker(ns.Config.LAYER_TICK, function()
    ns.Log.safe(FEATURE, function()
      local current = Sensor.current()
      if current ~= lastReported then
        if current == nil then
          ns.Log.add("info", "layer key reset in %s (key %s not seen for a while)", zone(), tostring(lastReported))
        end
        refresh()
      end
    end)
  end)
end
