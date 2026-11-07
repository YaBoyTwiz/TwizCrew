-- Layer module: "same / different / unknown" per friend. Unknown is never shown as different.
-- Decided by what the game shows us (is the friend visible? are they close by?), see LayerKey.judge.
local _, ns = ...

local Layer = {}
ns.Layer = Layer

local FEATURE = "layer"
local relations = {} -- name -> last computed relation
local memory = {}    -- name -> { verdict, hiddenSince, scope } kept by LayerKey.judge
local ticker

-- A value the game hides from addons (a "secret") counts as not known.
local function readable(v)
  if v == nil then return false end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return false end
  end
  return true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function unitName(unit)
  local name = call(UnitName, unit)
  if not readable(name) or type(name) ~= "string" or name == "" then return nil end
  return ns.shortName(name)
end

-- The group unit ("party2", "raid7") of a friend, or nil.
local function groupUnitOf(name)
  if call(IsInRaid) then
    for i = 1, 40 do
      local u = "raid" .. i
      if unitName(u) == name then return u end
    end
  else -- party units simply don't exist outside a group
    for i = 1, 4 do
      local u = "party" .. i
      if unitName(u) == name then return u end
    end
  end
  return nil
end

-- Names of players whose nameplate is up right now (the game only shows plates of players on our layer).
local function nameplateNames()
  local names = {}
  for i = 1, 40 do
    local u = "nameplate" .. i
    if call(UnitExists, u) and call(UnitIsPlayer, u) then
      local n = unitName(u)
      if n then names[n] = true end
    end
  end
  return names
end

local function position(unit)
  local y, x, _, instance = call(UnitPosition, unit)
  if not readable(y) or not readable(x) or type(y) ~= "number" or type(x) ~= "number" then return nil end
  return x, y, readable(instance) and instance or nil
end

local function distanceTo(unit)
  local x1, y1, i1 = position("player")
  local x2, y2, i2 = position(unit)
  if not x1 or not x2 then return nil end
  if i1 ~= nil and i2 ~= nil and i1 ~= i2 then return nil end
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function mySide()
  local zone, inInstance
  if type(GetRealZoneText) == "function" then zone = GetRealZoneText() end
  if type(IsInInstance) == "function" then inInstance = select(1, IsInInstance()) end
  return { zn = zone, ins = inInstance and true or false, online = true }
end

-- What the game shows about one friend right now.
local function evidence(m, me, plates)
  local them = { zn = m.zone, ins = m.inInstance, online = m.online }
  local ev = { comparable = ns.LayerKey.comparable(me, them) }
  if not ev.comparable then return ev end
  local unit = groupUnitOf(m.name)
  if plates[m.name] then
    ev.visible = true
  elseif unit then
    local visible = call(UnitIsVisible, unit)
    if readable(visible) then ev.visible = visible and true or false end
    local connected = call(UnitIsConnected, unit)
    if readable(connected) then ev.connected = connected and true or false end
    -- ghosts and the living can't see each other even on one layer: being hidden then proves nothing
    local theyGhost, meGhost = call(UnitIsGhost, unit), call(UnitIsGhost, "player")
    if (readable(theyGhost) and theyGhost) or (readable(meGhost) and meGhost) then ev.connected = false end
    ev.dist = distanceTo(unit)
  end
  return ev, unit
end

local function judge(m, me, plates, now)
  -- test tools: a fake's layer is whatever the Layer pop-up button says
  if m.online and ns.isTestName(m.name) and ns.TestTools then
    local forced = ns.TestTools.layerOf(m.name)
    if forced then return forced end
  end
  local mem = memory[m.name]
  if not mem then mem = {}; memory[m.name] = mem end
  local scope = tostring(me.zn) .. "|" .. tostring(m.zone)
  if mem.scope ~= scope then mem.scope, mem.verdict, mem.hiddenSince = scope, nil, nil end
  local ev, unit = evidence(m, me, plates)
  local relation = ns.LayerKey.judge(mem, ev, now, ns.Config.LAYER_NEAR, ns.Config.LAYER_HIDDEN_FOR)
  return relation, ev, unit
end

local function describe(ev, unit)
  if not ev.comparable then return "not comparable" end
  local parts = { unit or "not grouped" }
  if ev.visible ~= nil then parts[#parts + 1] = ev.visible and "visible" or "hidden" end
  if ev.dist then parts[#parts + 1] = math.floor(ev.dist + 0.5) .. " yd" end
  if ev.connected == false then parts[#parts + 1] = "offline or ghost" end
  return table.concat(parts, ", ")
end

local function recompute()
  if not ns.roster then return end
  local me, plates, now = mySide(), nameplateNames(), ns.now()
  for _, m in ipairs(ns.roster:members(true)) do -- fakes too (test tools: OTHER LAYER tag, layer pop-up)
    local old = relations[m.name] or "unknown"
    local new, ev, unit = judge(m, me, plates, now)
    relations[m.name] = new
    if new ~= old then
      ns.Log.add("info", "layer %s: %s -> %s (%s; zones %s / %s)", m.name, old, new,
        ev and describe(ev, unit) or "test tools", tostring(me.zn or "?"), tostring(m.zone or "?"))
      ns.Bus.fire("LAYER_RELATION", m.name, old, new)
    end
  end
end

-- After a loading screen or joining / leaving a group, we may be on another layer: start over.
local function forget(reason)
  if next(memory) then ns.Log.add("info", "layer memory cleared (%s)", reason) end
  memory = {}
  recompute()
end

function Layer.relationOf(name)
  if not ns.Modules.isEnabled(FEATURE) or not ns.roster then return "unknown" end
  local m = ns.roster:get(name)
  if not m then return "unknown" end
  if m.online and ns.isTestName(name) and ns.TestTools then
    local forced = ns.TestTools.layerOf(name)
    if forced then return forced end
  end
  return relations[name] or "unknown"
end

ns.Modules.register({
  id = "layer", name = "Layer tracker", tier = "module",
  info = "Tells you when a friend is on a different layer (they are close by on the map but the game hides them).",
  onEnable = function()
    for _, event in ipairs({ "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED" }) do
      ns.Bus.on(FEATURE, event, recompute)
    end
    local grouped = call(IsInGroup) and true or false
    ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() forget("loading screen") end)
    ns.Events.on(FEATURE, "GROUP_ROSTER_UPDATE", function()
      local now = call(IsInGroup) and true or false
      if now ~= grouped then
        grouped = now
        forget(now and "joined a group" or "left the group")
      else
        recompute()
      end
    end)
    ns.Events.on(FEATURE, "NAME_PLATE_UNIT_ADDED", recompute)
    if C_Timer and C_Timer.NewTicker then
      ticker = C_Timer.NewTicker(ns.Config.LAYER_LOOK_TICK, function() ns.Log.safe(FEATURE, recompute) end)
    end
    recompute()
  end,
  onDisable = function()
    if ticker then ticker:Cancel(); ticker = nil end
    relations, memory = {}, {}
  end,
})
