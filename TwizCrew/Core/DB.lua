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
-- data from before guilds had names, or a fresh install, until a guild adopts it or the player chooses with /tc
-- guild; "?": taken while the game named no guild); other guilds' data is parked in db.guilds[name], with the same
-- shape. db.guilds[""] holds unnamed (v0.1.24) data parked by /tc guild new, until the player picks it up again.
-- db.guild.byChar[character] = that character's guild in its last session decides, at login, which set is on top
-- (DB.useGuildOf); a guild without a parked set gets the unnamed set (or a "?" set) back so it can never be stranded,
-- unless /tc guild new asked for a fresh one (db.guild.fresh[name], used once). Parked data is never deleted; broken
-- parked values go to db.guilds_bad; fields of a set that are not in GUILD_PATHS ride along in db.guild.extra while
-- it is on top.
local GUILD_PATHS = { "roster", "feed", "calendar", "pins", "stats.crew", "stats.session", "stats.trophies",
  "stats.clown", "stats.clownBySid", "guild.keys", "guild.mine", "guild.spell" }
DB.GUILD_PATHS = GUILD_PATHS
local UNNAMED = ""      -- the parked slot of unnamed (v0.1.24) data
local PLACEHOLDER = "?" -- data taken while the game named no guild (Crew/Guild.lua)

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
    -- on that character, spell[lower(full name)] = the full name as the game spells it (see Crew/Guild.lua); name,
    -- byChar, fresh: see above and DB.useGuildOf
    guild = { keys = {}, mine = {}, spell = {}, byChar = {} },
    guilds = {},
    stats = { crew = {}, session = {} },
    feed = {}, -- the activity feed: the newest FeedLogic.MAX events (kept by Reset everything)
  })
end

-- The per-guild data on the top level as a set of the same shape (references; nothing is cleared).
local function topSet(db)
  local set = {}
  for _, path in ipairs(GUILD_PATHS) do
    local parent, key = split(path)
    local from = parent and db[parent] or db
    if type(from) == "table" and from[key] ~= nil then
      local to = set
      if parent then set[parent] = set[parent] or {}; to = set[parent] end
      to[key] = from[key]
    end
  end
  return set
end

-- Fields of a parked set that are not in GUILD_PATHS (a newer or broken copy's), so they stay with their guild.
local function extraOf(set)
  local known, knownIn = {}, {}
  for _, path in ipairs(GUILD_PATHS) do
    local parent, key = split(path)
    if parent then knownIn[parent] = knownIn[parent] or {}; knownIn[parent][key] = true else known[key] = true end
  end
  local extra = {}
  for k, v in pairs(set) do
    if knownIn[k] and type(v) == "table" then
      for sk, sv in pairs(v) do
        if not knownIn[k][sk] then extra[k] = extra[k] or {}; extra[k][sk] = sv end
      end
    elseif not known[k] and not knownIn[k] then
      extra[k] = v
    end
  end
  return next(extra) and extra or nil
end

-- Lays b's fields into a (one level deep; a's own values win).
local function mergeInto(a, b)
  for k, v in pairs(b or {}) do
    if type(v) == "table" and type(a[k]) == "table" then
      for sk, sv in pairs(v) do if a[k][sk] == nil then a[k][sk] = sv end end
    elseif a[k] == nil then
      a[k] = v
    end
  end
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

-- Keeps a value aside under db.guilds_bad (never thrown away): name (numbered: name#1), then name#2, name#3 ...
-- Returns the key it went under.
local function keepAside(db, name, value, numbered)
  if type(db.guilds_bad) ~= "table" then db.guilds_bad = {} end
  local n = 1
  local key = numbered and (name .. "#1") or name
  while db.guilds_bad[key] ~= nil do n = n + 1; key = name .. "#" .. n end
  db.guilds_bad[key] = value
  ns.Log.add("warn", "saved data kept aside as guilds_bad[%s]", key)
  return key
end

-- This character's id for db.guild.byChar: its GUID, else its name.
function DB.charId()
  local id = ns.Util.plain(UnitGUID, "player")
  if type(id) == "string" and id ~= "" then return id end
  id = ns.Util.plain(UnitName, "player")
  return type(id) == "string" and id ~= "" and id or nil
end

-- At login, before any module reads per-guild data: when this character's guild (byChar, from its last session)
-- is not the one whose data is on top, the top set is parked under its name and that guild's set comes up: its
-- parked set; else (unless /tc guild new asked for a fresh one) the unnamed set, else the "?" set; else a fresh one.
-- A character with no known guild leaves everything as it is. Everything is checked first: a parked value that is
-- not a usable set (not a table, or its stats / guild part not a table) is kept aside in db.guilds_bad and counts as
-- absent; a guild parked twice keeps the top set (the parked copy goes aside); unnamed top data never overwrites a
-- parked unnamed set (it goes aside instead); an error halfway puts everything back. Returns true when it swapped.
function DB.useGuildOf(db, charId)
  if type(db) ~= "table" or type(db.guild) ~= "table" or type(db.guild.byChar) ~= "table" then return false end
  local g = db.guild
  local want = charId and g.byChar[charId]
  if type(want) ~= "string" or want == "" or want == g.name then return false end
  if type(db.guilds) ~= "table" then
    if db.guilds ~= nil then keepAside(db, "guilds", db.guilds) end
    db.guilds = {}
  end
  local here = type(g.name) == "string" and g.name ~= "" and g.name or UNNAMED
  for _, name in ipairs({ want, here, UNNAMED, PLACEHOLDER }) do
    local v = db.guilds[name]
    if v ~= nil and (type(v) ~= "table" or (rawget(v, "stats") ~= nil and type(rawget(v, "stats")) ~= "table")
      or (rawget(v, "guild") ~= nil and type(rawget(v, "guild")) ~= "table")) then
      keepAside(db, name, v)
      db.guilds[name] = nil
    end
  end
  local topAside = false -- unnamed top data and a parked unnamed set: the top set goes aside
  if db.guilds[here] ~= nil then
    if here == UNNAMED then
      topAside = true
    else -- both the top and a parked set claim this guild: the top one stays
      keepAside(db, here, db.guilds[here], true)
      db.guilds[here] = nil
    end
  end
  local fresh = type(g.fresh) == "table" and g.fresh[want]
  local incoming, from = nil, want
  if not fresh then
    incoming = db.guilds[want]
    if incoming == nil and here ~= UNNAMED and db.guilds[UNNAMED] ~= nil then
      incoming, from = db.guilds[UNNAMED], UNNAMED -- maybe this guild's data from before: its list decides (Guild)
    elseif incoming == nil and here ~= PLACEHOLDER and db.guilds[PLACEHOLDER] ~= nil then
      incoming, from = db.guilds[PLACEHOLDER], PLACEHOLDER
    end
  end
  local outgoing = topSet(db)
  mergeInto(outgoing, type(g.extra) == "table" and g.extra or nil)
  local before = { name = g.name, extra = g.extra }
  local asideKey
  local ok, err = pcall(function()
    local extra = incoming and extraOf(incoming) or nil
    if topAside then asideKey = keepAside(db, here, outgoing, true) else db.guilds[here] = outgoing end
    if incoming ~= nil then db.guilds[from] = nil end
    putSet(db, incoming or {})
    g.extra = extra
    if from == UNNAMED then g.name = nil else g.name = from end
    if fresh then g.fresh[want] = nil end
  end)
  if not ok then
    putSet(db, outgoing) -- everything back as it was
    if asideKey then db.guilds_bad[asideKey] = nil elseif not topAside then db.guilds[here] = nil end
    if incoming ~= nil then db.guilds[from] = incoming end
    g.name, g.extra = before.name, before.extra
    ns.Log.add("error", "switching saved data to %s failed (%s): nothing changed", want, tostring(err))
    return false
  end
  ns.Log.add("info", "saved data of %s is in use", g.name or "(unnamed, from an older version)")
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
  db.guild.notLegacy = nil -- a test build's "this guild turned the old data down": nothing a guess decides is kept
  return db
end

-- Rebuilds db.modules from defaults only; crew, roster, status and log are untouched.
function DB.resetSettings(db, defs)
  db.modules = {}
  for _, def in ipairs(defs or {}) do db.modules[def.id] = moduleDefaults(def) end
end
