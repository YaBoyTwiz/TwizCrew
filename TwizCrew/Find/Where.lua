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

local function secret(v)
  if v == nil or type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return not ok or s and true or false
end

-- A number we may do math on, else nil.
local function num(v)
  if v == nil or secret(v) then return nil end
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
  if type(v) ~= "table" or secret(v) then return nil end
  local x, y
  if type(v.GetXY) == "function" then x, y = call(v.GetXY, v) else x, y = v.x, v.y end
  return num(x), num(y)
end

local function inInstance()
  local inside = call(IsInInstance)
  return inside and not secret(inside) and true or false
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

-- Where a world position sits on a map (0..1 inside it), or nil.
function Where.toMap(mapID, c, x, y)
  mapID, c, x, y = num(mapID), num(c), num(x), num(y)
  if not mapID or c == nil or not x or not y then return nil end
  local _, pos = call(mapApi("GetMapPosFromWorldPos"), c, vector(x, y), mapID)
  local mx, my = xy(pos)
  if not mx or not my then return nil end
  return mx, my
end

function Where.mapName(mapID)
  local info = call(mapApi("GetMapInfo"), mapID)
  if type(info) ~= "table" or type(info.name) ~= "string" or secret(info.name) or info.name == "" then return nil end
  return info.name
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

function Where.inGroup()
  return (call(IsInGroup) or call(IsInRaid)) and true or false
end

local function unitName(unit)
  local n = call(UnitName, unit)
  if type(n) ~= "string" or secret(n) or n == "" then return nil end
  return ns.shortName(n)
end

-- The party / raid unit token of a group member by short name, or nil.
function Where.unitFor(name)
  if type(name) ~= "string" then return nil end
  local want = name:lower()
  if call(IsInRaid) then
    for i = 1, 40 do
      local u = "raid" .. i
      local n = unitName(u)
      if n and n:lower() == want and not ns.isMe(n) then return u end
    end
  elseif call(IsInGroup) then
    for i = 1, 4 do
      local u = "party" .. i
      local n = unitName(u)
      if n and n:lower() == want and not ns.isMe(n) then return u end
    end
  end
  return nil
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
    if yes and not secret(yes) then return true end
  end
  return Where.unitFor(name) ~= nil
end
