-- Find the crew: safe reads of where things are (ns.Where). Every game call goes through pcall and every number
-- through issecretvalue: a missing function, an error or a secret value means "unknown" (nil), never an error.
-- World positions are { c = continent (instance id), x = yards north, y = yards west }, as
-- C_Map.GetWorldPosFromMapPos gives them; UnitPosition gives the same two numbers (north first).
local _, ns = ...

local Where = {}
ns.Where = Where

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

-- Asked before anything else is done with a value: a secret one can't even be compared (not with nil either) or
-- tested for true / false.
local function secret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  if not ok then return true end
  return s == true
end

-- A number we may do math on, else nil.
local function num(v)
  if secret(v) or v == nil then return nil end
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function mapApi(name)
  local m = C_Map
  return type(m) == "table" and m[name] or nil
end

local function vector(x, y)
  if type(CreateVector2D) == "function" then
    local v = call(CreateVector2D, x, y)
    if type(v) == "table" then return v end
  end
  return { x = x, y = y }
end

local function xy(v)
  if secret(v) or type(v) ~= "table" then return nil end
  local x, y
  if type(v.GetXY) == "function" then x, y = call(v.GetXY, v) else x, y = v.x, v.y end
  return num(x), num(y)
end

local function inInstance()
  local inside = call(IsInInstance)
  if secret(inside) then return false end
  return inside and true or false
end

-- World position of a point on a map (map x, y from 0 to 1): c, x, y, or nil when the game can't place it
-- (the whole-world map, an instance's map, junk).
function Where.toWorld(mapID, mx, my)
  mapID, mx, my = num(mapID), num(mx), num(my)
  if not mapID or not mx or not my then return nil end
  local c, pos = call(mapApi("GetWorldPosFromMapPos"), mapID, vector(mx, my))
  c = num(c)
  local x, y = xy(pos)
  if c == nil or not x or not y then return nil end
  return c, x, y
end

-- Which continent (instance id) a map is on, or nil. Asked once per map: it never changes.
local continentOf = {}
local function mapContinent(mapID)
  local c = continentOf[mapID]
  if c == nil then
    c = Where.toWorld(mapID, 0.5, 0.5)
    if c ~= nil then continentOf[mapID] = c end
  end
  return c
end

-- Where a world position sits on a map (0..1 inside it), or nil. nil too when the map is on another continent:
-- the game is not asked to place a Kalimdor spot on an Eastern Kingdoms map.
function Where.toMap(mapID, c, x, y)
  mapID, c, x, y = num(mapID), num(c), num(x), num(y)
  if not mapID or c == nil or not x or not y then return nil end
  if mapContinent(mapID) ~= c then return nil end
  local _, pos = call(mapApi("GetMapPosFromWorldPos"), c, vector(x, y), mapID)
  local mx, my = xy(pos)
  if not mx or not my then return nil end
  return mx, my
end

local function infoName(info)
  if type(info) ~= "table" or secret(info.name) or type(info.name) ~= "string" or info.name == "" then return nil end
  return info.name
end

function Where.mapName(mapID)
  return infoName((call(mapApi("GetMapInfo"), mapID)))
end

-- Map types (Enum.UIMapType): world and continent maps are below ZONE, dungeon and micro maps (a cave, a city's
-- floor) above it.
local ZONE, DUNGEON, MICRO = 3, 4, 5

-- The zone a map point is in, by name (as GetRealZoneText says it): on a continent map the zone under the point,
-- on a cave's or a floor's map the zone around it. Falls back to the map's own name.
function Where.placeName(mapID, mx, my)
  local getInfo = mapApi("GetMapInfo")
  local info = call(getInfo, mapID)
  local own = infoName(info)
  if type(info) == "table" and type(info.mapType) == "number" and info.mapType < ZONE then
    local at = call(mapApi("GetMapInfoAtPosition"), mapID, mx, my)
    if type(at) == "table" then info = at end
  end
  for _ = 1, 5 do
    if type(info) ~= "table" or (info.mapType ~= DUNGEON and info.mapType ~= MICRO)
      or type(info.parentMapID) ~= "number" then break end
    local up = call(getInfo, info.parentMapID)
    if type(up) ~= "table" then break end
    info = up
  end
  return infoName(info) or own
end

local function zone()
  local z = call(GetRealZoneText)
  if type(z) ~= "string" or secret(z) then return nil end
  return z
end

-- My position: { c, x, y, map, zone }, or nil (instance, no map position, missing APIs, secret values).
-- The map APIs come first; UnitPosition("player") is the fallback.
function Where.me()
  if inInstance() then return nil end
  local mapID = num((call(mapApi("GetBestMapForUnit"), "player")))
  if mapID then
    local mx, my = xy((call(mapApi("GetPlayerMapPosition"), mapID, "player")))
    if mx and my then
      local c, x, y = Where.toWorld(mapID, mx, my)
      if c ~= nil then return { c = c, x = x, y = y, map = mapID, zone = zone() } end
    end
  end
  local x, y, _, c = call(UnitPosition, "player")
  x, y, c = num(x), num(y), num(c)
  if x and y and c ~= nil then return { c = c, x = x, y = y, map = mapID, zone = zone() } end
  return nil
end

-- Which way I face (radians, counter-clockwise from north), or nil.
function Where.facing()
  return num((call(GetPlayerFacing)))
end

local function yes(v) return not secret(v) and v and true or false end

function Where.inGroup()
  return yes(call(IsInGroup)) or yes(call(IsInRaid))
end

local function unitName(unit)
  local n = call(UnitName, unit)
  if secret(n) or type(n) ~= "string" or n == "" then return nil end
  return ns.shortName(n)
end

-- lower-case short name -> unit token, read from the game at most every UNIT_MAP_AGE seconds (the arrows ask many
-- times a second; a raid would mean 40 name reads per question otherwise). Where.forget() drops it (group changes).
local UNIT_MAP_AGE = 0.5
local unitMap, unitMapAt

local function buildUnitMap()
  local map = {}
  local raid = yes(call(IsInRaid))
  if raid or yes(call(IsInGroup)) then
    for i = 1, raid and 40 or 4 do
      local u = (raid and "raid" or "party") .. i
      local n = unitName(u)
      if n and not ns.isMe(n) then map[n:lower()] = u end
    end
  end
  return map
end

function Where.forget() unitMap = nil end
Where.isSecret = secret

-- The party / raid unit token of a group member by short name, or nil.
function Where.unitFor(name)
  if type(name) ~= "string" then return nil end
  local now = ns.now()
  if not unitMap or not unitMapAt or now - unitMapAt >= UNIT_MAP_AGE or now < unitMapAt then
    unitMap, unitMapAt = buildUnitMap(), now
  end
  return unitMap[name:lower()]
end

-- A unit's live position { c, x, y }, or nil (the game often hides it: secret, instance, too far).
function Where.unit(unit)
  if type(unit) ~= "string" then return nil end
  local x, y, _, c = call(UnitPosition, unit)
  x, y, c = num(x), num(y), num(c)
  if not x or not y or c == nil then return nil end
  return { c = c, x = x, y = y }
end

-- Is this crew member in my group? (Test tools' fakes count when they say so: ns.TestTools.inGroup.)
function Where.isGroupMember(name)
  if type(name) ~= "string" then return false end
  if ns.isTestName(name) then
    return ns.TestTools ~= nil and type(ns.TestTools.inGroup) == "function" and ns.TestTools.inGroup(name) or false
  end
  for _, fn in ipairs({ UnitInParty, UnitInRaid }) do
    local yes = call(fn, name)
    if not secret(yes) and yes then return true end
  end
  return Where.unitFor(name) ~= nil
end
