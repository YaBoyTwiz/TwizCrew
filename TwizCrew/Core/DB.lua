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

-- Saved data is of two kinds. Account-wide: module settings, my status and mocks, my own characters' stats
-- (stats.chars), the log, update notices and other one-time flags. Per guild: everything about other people or
-- shared with them (GUILD_PATHS). The top level always holds the per-guild data of ONE guild, db.guild.name (nil:
-- data from before guilds had names, or a fresh install, until a guild adopts it); other guilds' data is parked in
-- db.guilds[name], with the same shape. db.guilds[""] holds unnamed (v0.1.24) data parked until its guild shows up.
-- db.guild.byChar[character] = that character's guild in its last session decides, at login, which set is on top
-- (DB.useGuildOf). Parked data is never deleted.
local GUILD_PATHS = { "roster", "feed", "calendar", "pins", "stats.crew", "stats.session", "stats.trophies",
  "stats.clown", "stats.clownBySid", "guild.keys", "guild.mine" }
DB.GUILD_PATHS = GUILD_PATHS
local UNNAMED = ""

local function split(path)
  local parent, key = path:match("^(%w+)%.(%w+)$")
  if parent then return parent, key end
  return nil, path
end

-- The per-guild defaults (a fresh set fills in from these).
local function guildDefaults(db)
  ns.Util.mergeDefaults(db, {
    roster = {},
    -- keys[lower(full name)] = the key a guild member was given the first time (never changed), mine[GUID] = my key
    -- on that character (see Crew/Guild.lua); name, byChar, notLegacy: see above and DB.useGuildOf
    guild = { keys = {}, mine = {}, byChar = {}, notLegacy = {} },
    guilds = {},
    stats = { crew = {}, session = {} },
    feed = {}, -- the activity feed: the newest FeedLogic.MAX events (kept by Reset everything)
  })
end

-- Takes the per-guild data off the top level; returns it as a set of the same shape.
local function takeSet(db)
  local set = {}
  for _, path in ipairs(GUILD_PATHS) do
    local parent, key = split(path)
    local from = parent and db[parent] or db
    if type(from) == "table" and from[key] ~= nil then
      local to = set
      if parent then set[parent] = set[parent] or {}; to = set[parent] end
      to[key] = from[key]
      from[key] = nil
    end
  end
  return set
end

-- Puts a set's per-guild data on the top level (anything missing becomes a default).
local function putSet(db, set)
  for _, path in ipairs(GUILD_PATHS) do
    local parent, key = split(path)
    local from = parent and set[parent] or set
    local to = db
    if parent then
      if type(db[parent]) ~= "table" then db[parent] = {} end
      to = db[parent]
    end
    to[key] = type(from) == "table" and from[key] or nil
  end
  guildDefaults(db)
end

-- This character's id for db.guild.byChar: its GUID, else its name.
function DB.charId()
  local id = ns.Util.plain(UnitGUID, "player")
  if type(id) == "string" and id ~= "" then return id end
  id = ns.Util.plain(UnitName, "player")
  return type(id) == "string" and id ~= "" and id or nil
end

-- At login, before any module reads per-guild data: when this character's guild (byChar, from its last session)
-- is not the one whose data is on top, the top set is parked under its name and that guild's set (a parked one,
-- the unnamed v0.1.24 set unless that guild already turned it down, or a fresh one) comes up. A character with no
-- known guild leaves everything as it is. Returns true when it swapped.
function DB.useGuildOf(db, charId)
  local g = db.guild
  local want = charId and g.byChar[charId]
  if type(want) ~= "string" or want == "" or want == g.name then return false end
  local here = g.name or UNNAMED
  if db.guilds[here] ~= nil then
    ns.Log.add("warn", "saved data for %s is parked twice: nothing swapped", here == UNNAMED and "(unnamed)" or here)
    return false
  end
  db.guilds[here] = takeSet(db)
  local set, name = db.guilds[want], want
  db.guilds[want] = nil
  if set == nil and db.guilds[UNNAMED] ~= nil and not g.notLegacy[want] then
    set, name = db.guilds[UNNAMED], nil -- maybe this guild's data from before: its member list decides (Guild)
    db.guilds[UNNAMED] = nil
  end
  putSet(db, set or {})
  g.name = name
  ns.Log.add("info", "saved data of %s is in use", name or "(unnamed, from an older version)")
  return true
end

-- Accepts nil or any type; returns a repaired table.
function DB.init(saved, defs)
  local db = type(saved) == "table" and saved or {}
  guildDefaults(db)
  ns.Util.mergeDefaults(db, {
    schema = 1,
    modules = {},
    log = {},
    problems = {}, -- the ERROR and WARN lines, kept apart from the rolling log
    myStatus = "",
    myMocks = {}, -- your own roasts for the Mock button (kept by Reset everything)
    stats = { chars = {} },
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
