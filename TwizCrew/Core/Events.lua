-- WoW event dispatcher (ns.Events) and internal bus (ns.Bus). Every handler runs inside ns.Log.safe.
local ADDON, ns = ...

-- A registry of handler lists per key. Dispatch iterates a copy, so handlers may be added or removed meanwhile.
local function newRegistry()
  local R = { lists = {} }
  function R.add(featureId, key, fn)
    local list = R.lists[key]
    if not list then list = {}; R.lists[key] = list end
    list[#list + 1] = { feature = featureId, fn = fn }
    return #list == 1
  end
  function R.remove(featureId) -- returns the keys that no longer have any handler
    local emptied = {}
    for key, list in pairs(R.lists) do
      local kept = {}
      for _, h in ipairs(list) do
        if h.feature == featureId then h.removed = true else kept[#kept + 1] = h end
      end
      if #kept == 0 then R.lists[key] = nil; emptied[#emptied + 1] = key else R.lists[key] = kept end
    end
    return emptied
  end
  function R.dispatch(key, ...)
    local list = R.lists[key]
    if not list then return end
    local copy = {}
    for i, h in ipairs(list) do copy[i] = h end
    for _, h in ipairs(copy) do
      if not h.removed then ns.Log.safe(h.feature, h.fn, ...) end
    end
  end
  return R
end

local Events = {}
ns.Events = Events
local wow = newRegistry()
local frame

local function getFrame()
  if not frame then
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...) wow.dispatch(event, ...) end)
  end
  return frame
end

function Events.on(featureId, event, fn)
  local first = wow.add(featureId, event, fn)
  if first then
    local f = getFrame()
    ns.Log.safe("events", f.RegisterEvent, f, event)
  end
end

function Events.off(featureId)
  for _, event in ipairs(wow.remove(featureId)) do
    if frame then ns.Log.safe("events", frame.UnregisterEvent, frame, event) end
  end
end

local Bus = {}
ns.Bus = Bus
local bus = newRegistry()

function Bus.on(featureId, name, fn) bus.add(featureId, name, fn) end
function Bus.off(featureId) bus.remove(featureId) end
function Bus.fire(name, ...) bus.dispatch(name, ...) end
