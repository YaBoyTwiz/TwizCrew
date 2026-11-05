-- Saved data: build, repair and reset (TwizCrewDB).
local ADDON, ns = ...

local DB = {}
ns.DB = DB

local function moduleDefaults(def)
  return { enabled = def.defaultEnabled ~= false, settings = ns.Util.copy(def.defaults or {}) }
end

-- Accepts nil or any type; returns a repaired table.
function DB.init(saved, defs)
  local db = type(saved) == "table" and saved or {}
  ns.Util.mergeDefaults(db, {
    schema = 1,
    modules = {},
    crew = { channel = ns.Config.DEFAULT_CHANNEL, password = ns.Config.DEFAULT_PASSWORD, extra = {} },
    roster = {},
    log = {},
    myStatus = "",
    stats = { chars = {}, crew = {}, session = {} },
  })
  local known = {}
  for _, def in ipairs(defs or {}) do
    known[def.id] = true
    local e = db.modules[def.id]
    if type(e) ~= "table" then e = {}; db.modules[def.id] = e end
    ns.Util.mergeDefaults(e, moduleDefaults(def))
  end
  for id in pairs(db.modules) do
    if not known[id] then db.modules[id] = nil end
  end
  return db
end

-- Rebuilds db.modules from defaults only; crew, roster, status and log are untouched.
function DB.resetSettings(db, defs)
  db.modules = {}
  for _, def in ipairs(defs or {}) do db.modules[def.id] = moduleDefaults(def) end
end
