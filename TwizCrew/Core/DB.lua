-- Saved data: build, repair and reset (TwizCrewDB).
local ADDON, ns = ...

local DB = {}
ns.DB = DB

-- Module ids that no longer exist: their saved settings are deleted. Any other unknown id is kept (a file that
-- failed to load must not cost its module's settings).
local REMOVED = { spellhelp = true }

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
    problems = {}, -- the ERROR and WARN lines, kept apart from the rolling log
    myStatus = "",
    myMocks = {}, -- your own roasts for the Mock button (kept by Reset everything)
    stats = { chars = {}, crew = {}, session = {} },
    feed = {}, -- the activity feed: the newest FeedLogic.MAX events (kept by Reset everything)
    update = {}, -- the newest version a friend told us about (Update reminders); not a setting
    updateNotice = {}, -- { shown = newest version an update pop-up was shown for }: once per version; not a setting
  })
  for _, def in ipairs(defs or {}) do
    local e = db.modules[def.id]
    if type(e) ~= "table" then e = {}; db.modules[def.id] = e end
    ns.Util.mergeDefaults(e, moduleDefaults(def))
  end
  for id in pairs(REMOVED) do db.modules[id] = nil end
  return db
end

-- Rebuilds db.modules from defaults only; crew, roster, status and log are untouched.
function DB.resetSettings(db, defs)
  db.modules = {}
  for _, def in ipairs(defs or {}) do db.modules[def.id] = moduleDefaults(def) end
end
