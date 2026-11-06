-- Layer module: "same / different / unknown" per friend. Unknown is never shown as different.
local _, ns = ...

local Layer = {}
ns.Layer = Layer

local FEATURE = "layer"
local relations = {} -- name -> last computed relation

local function mySide()
  local zone, inInstance
  if type(GetRealZoneText) == "function" then zone = GetRealZoneText() end
  if type(IsInInstance) == "function" then inInstance = select(1, IsInInstance()) end
  return {
    lk = ns.LayerSensor and ns.LayerSensor.current() or nil,
    zn = zone, ins = inInstance and true or false, online = true,
  }
end

local function compute(m, me)
  -- test tools: a fake's layer is whatever the Layer pop-up button says
  if m.online and ns.isTestName(m.name) and ns.TestTools then
    local forced = ns.TestTools.layerOf(m.name)
    if forced then return forced end
  end
  return ns.LayerKey.relation(me, { lk = m.layerKey, zn = m.zone, ins = m.inInstance, online = m.online })
end

local function recompute()
  if not ns.roster then return end
  local me = mySide()
  for _, m in ipairs(ns.roster:members(true)) do -- fakes too (test tools: OTHER LAYER tag, layer pop-up)
    local old = relations[m.name] or "unknown"
    local new = compute(m, me)
    relations[m.name] = new
    if new ~= old then
      ns.Log.add("info", "layer %s: %s -> %s (mine %s in %s, theirs %s in %s)", m.name, old, new,
        tostring(me.lk or "none"), tostring(me.zn or "?"), tostring(m.layerKey or "none"), tostring(m.zone or "?"))
      ns.Bus.fire("LAYER_RELATION", m.name, old, new)
    end
  end
end

function Layer.relationOf(name)
  if not ns.Modules.isEnabled(FEATURE) or not ns.roster then return "unknown" end
  local m = ns.roster:get(name)
  if not m then return "unknown" end
  return compute(m, mySide())
end

ns.Modules.register({
  id = "layer", name = "Layer tracker", tier = "module",
  info = "Works out which layer you are on and tells you when a friend is on a different one.",
  onEnable = function()
    for _, event in ipairs({ "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED" }) do
      ns.Bus.on(FEATURE, event, recompute)
    end
    recompute()
  end,
  onDisable = function()
    relations = {}
  end,
})
