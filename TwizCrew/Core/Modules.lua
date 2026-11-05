-- Module registry: every feature registers here; the settings window is built from it.
local ADDON, ns = ...

local Modules = {}
ns.Modules = Modules

local TIERS = { essential = true, module = true, extra = true }
local KINDS = { toggle = true, slider = true, choice = true, text = true,
  button = true, -- an action (onClick), holds no value
  list = true }  -- read-only lines (lines() -> { text, ... }), holds no value
local NO_VALUE = { button = true, list = true }

local defs, byId = {}, {}
local db
local broken = {}     -- id -> true (this session only, never saved)
local brokenList = {}
local started = {}    -- id -> true while onEnable has run and onDisable has not

local function isBlank(s) return type(s) ~= "string" or s:match("^%s*$") ~= nil end

function Modules.register(def)
  assert(type(def) == "table", "Modules.register needs a table")
  local id = def.id
  assert(type(id) == "string" and id ~= "", "module needs an id")
  assert(not byId[id], "module id registered twice: " .. id)
  assert(TIERS[def.tier], "module " .. id .. " has an unknown tier")
  assert(not isBlank(def.name), "module " .. id .. " needs a name")
  assert(not isBlank(def.info), "module " .. id .. " needs an info text")
  def.defaults = def.defaults or {}
  def.settings = def.settings or {}
  if def.defaultEnabled == nil then def.defaultEnabled = true end
  for _, s in ipairs(def.settings) do
    assert(type(s.key) == "string", "module " .. id .. " has a setting without a key")
    assert(not isBlank(s.info), "module " .. id .. " setting " .. s.key .. " needs an info text")
    assert(KINDS[s.kind], "module " .. id .. " setting " .. s.key .. " has an unknown kind")
    if s.kind == "button" then
      assert(type(s.onClick) == "function", "module " .. id .. " button " .. s.key .. " needs onClick")
    elseif s.kind == "list" then
      assert(type(s.lines) == "function", "module " .. id .. " list " .. s.key .. " needs lines")
    end
    if s.store ~= "crew" and not NO_VALUE[s.kind] then
      assert(def.defaults[s.key] ~= nil, "module " .. id .. " setting " .. s.key .. " has no default")
    end
  end
  defs[#defs + 1] = def
  byId[id] = def
  return def
end

function Modules.list(tier)
  local out = {}
  for _, d in ipairs(defs) do
    if not tier or d.tier == tier then out[#out + 1] = d end
  end
  return out
end

function Modules.get(id) return byId[id] end

function Modules.attach(saved) db = saved end

local function entry(id)
  return db and db.modules and db.modules[id]
end

function Modules.isEnabled(id)
  local d = byId[id]
  if not d then return false end
  if d.tier == "essential" then return true end
  if d.comingSoon or broken[id] then return false end
  local e = entry(id)
  if e and type(e.enabled) == "boolean" then return e.enabled end
  return d.defaultEnabled
end

local function runHook(d, name, ...)
  if type(d[name]) == "function" then ns.Log.safe(d.id, d[name], ...) end
end

local function stop(d)
  if started[d.id] then
    started[d.id] = nil
    runHook(d, "onDisable")
  end
  ns.Events.off(d.id)
  ns.Bus.off(d.id)
end

local function start(d)
  if not started[d.id] then
    started[d.id] = true
    runHook(d, "onEnable")
  end
end

function Modules.startAll()
  for _, d in ipairs(defs) do
    if Modules.isEnabled(d.id) then start(d) end
  end
end

function Modules.setEnabled(id, on)
  local d = byId[id]
  if not d or d.tier == "essential" or d.comingSoon then return end
  on = on and true or false
  local was = Modules.isEnabled(id)
  local e = entry(id)
  if e then e.enabled = on end
  local now = Modules.isEnabled(id)
  if now == was then return end
  if now then start(d) else stop(d) end
  ns.Bus.fire("MODULE_TOGGLED", id, now)
end

function Modules.setting(id, key)
  local d = byId[id]
  if not d then return nil end
  for _, s in ipairs(d.settings) do
    if s.key == key and s.store == "crew" then return db and db.crew and db.crew[key] end
  end
  local e = entry(id)
  if e and e.settings and e.settings[key] ~= nil then return e.settings[key] end
  return d.defaults[key]
end

local function crewSetting(d, key)
  for _, s in ipairs(d.settings) do
    if s.key == key and s.store == "crew" then return true end
  end
  return false
end

-- Stores a setting. Refuses (logs a warning, returns false) unknown keys and values of the wrong type.
function Modules.set(id, key, value)
  local d = byId[id]
  if not d then
    ns.Log.add("warn", "set: unknown module %s", tostring(id))
    return false
  end
  local isCrew = crewSetting(d, key)
  local current = Modules.setting(id, key)
  if current == nil or type(value) ~= type(current) then
    ns.Log.add("warn", "set: refused %s.%s = %s (expected %s)", id, tostring(key), tostring(value), type(current))
    return false
  end
  if db then
    if isCrew then
      db.crew[key] = value
    else
      local e = entry(id)
      if e then
        e.settings = e.settings or {}
        e.settings[key] = value
      end
    end
  end
  runHook(d, "onSettingChanged", key, value)
  ns.Bus.fire("SETTING_CHANGED", id, key, value)
  return true
end

function Modules.resetAll()
  local before = {}
  for _, d in ipairs(defs) do before[d.id] = Modules.isEnabled(d.id) end
  ns.DB.resetSettings(db, defs)
  for _, d in ipairs(defs) do
    local now = Modules.isEnabled(d.id)
    if now and not before[d.id] then start(d)
    elseif before[d.id] and not now then stop(d) end
  end
  for _, d in ipairs(defs) do
    local keys = {}
    for key in pairs(d.defaults) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do runHook(d, "onSettingChanged", key, Modules.setting(d.id, key)) end
  end
  ns.Bus.fire("SETTINGS_RESET")
end

-- Session only: the saved "enabled" is left alone so the module comes back after /reload.
function Modules.markBroken(id)
  local d = byId[id]
  if not d then return end
  if d.tier == "essential" then
    ns.Log.add("warn", "%s kept running after errors (essential)", id)
    return
  end
  if broken[id] then return end
  broken[id] = true
  brokenList[#brokenList + 1] = id
  stop(d)
  print("TwizCrew: " .. d.name .. " hit a problem and turned itself off. Type /tc report for details.")
  ns.Bus.fire("MODULE_TOGGLED", id, false)
end

function Modules.broken()
  local out = {}
  for i, id in ipairs(brokenList) do out[i] = id end
  return out
end

ns.Log.onBroken = Modules.markBroken
