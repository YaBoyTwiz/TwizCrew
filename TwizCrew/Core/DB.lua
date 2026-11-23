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
-- shared with them (GUILD_PATHS). The top level always holds the per-guild data of ONE guild ("the set in use"),
-- named by db.guild.name: a guild's name; nil = unnamed (data from before guilds had names, or a fresh install);
-- "?" = taken while the game named no guild. Other sets are parked in db.guilds[name] with the same shape
-- (db.guilds[""] = a parked unnamed set, db.guilds["?"] = a parked "?" set). The rule all of this serves: no login,
-- reload or command loses, strands, silently reassigns or duplicates a set.
-- * Ownership changes only by the one safe guess (unnamed or "?" data is named for a guild whose complete list fits
--   it: Crew/Guild.lua) or by the player's command (/tc guild use, new, load).
-- * db.guild.byChar[character] decides at login which set comes up (DB.useGuildOf). Crew/GuildIdentity.lua writes it
--   only when that character's guild has a set (in use or parked) or another guild's named set is in use; for unnamed
--   or "?" data the guild has not taken it is cleared, so the next login moves nothing.
-- * db.guild.request = { kind = "new" | "load", guild, char, from, key }: a one-shot /tc guild new or load, used up
--   at the next start-up whoever logs in, carried out only for that character while it still fits (requestPlan).
--   Its outcome, db.guild.requestResults[character] = { kind, done, reason } (one per character, so one character's
--   result never overwrites or lingers for another's), is said once at that character's next login (DB.notes,
--   printed by Core/Boot.lua), and shown by that character's /tc guild until then.
-- * A set steps aside, never away: a set that would share a guild's name goes to "<name> (replaced)"; unnamed or
--   "?" data that would land on a parked set of its kind, and values that are not usable sets, go to db.guilds_bad.
--   Every parked or kept-aside set is listed by /tc guild and can be brought back with /tc guild load.
-- * Old friends are forgotten (Crew's 60-day rule) only on a whole guild list, while the saved friends fit it or the
--   set fitted this guild before (Guild.mayForget, guild.fitIn): a set used in a guild that is not its own forgets
--   nothing.
-- * guild.pinnedOld (per set): unnamed v0.1.24 data taken by a guild pinned its old crew once (Crew/GuildIdentity.lua,
--   or a /tc guild load of that set: carryOut).
-- * guild.fitIn (per set): the real name of the last guild whose list the saved friends fitted (Guild.mayForget:
--   the 60-day rule keeps running there after over half the friends left). nil until then.
-- * Fields of a set that are not in GUILD_PATHS ride along in db.guild.extra while it is in use. db.guild.named:
--   this account has read a real guild name from the game (names of parked sets never count; markNamed).
-- * away (per set, made when first used: UI/AwayCard.lua): { snap = the guild list and crowns at the last logout }.
--   welcome (per set: UI/Welcome.lua): { start = the newcomer's start card "due" / "shown" / "no", welcomed[lower(full
--   name)] = when a "Say hi" pop-up was shown for them }.
local GUILD_PATHS = { "roster", "feed", "calendar", "pins", "stats.crew", "stats.session", "stats.trophies",
  "stats.clown", "stats.clownBySid", "guild.keys", "guild.mine", "guild.spell", "guild.pinnedOld", "guild.fitIn",
  "away", "welcome" }
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
    -- on that character, spell[lower(full name)] = the full name as the game spells it (see Crew/GuildNames.lua); name,
    -- byChar, request, requestResults, named, extra, pinnedOld, fitIn (nil by default): see above
    guild = { keys = {}, mine = {}, spell = {}, byChar = {}, requestResults = {} },
    guilds = {},
    stats = { crew = {}, session = {} },
    pins = {}, -- pins[key] = true: members pinned to the main view of the panel
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

local function isReal(name) return type(name) == "string" and name ~= UNNAMED and name ~= PLACEHOLDER end

-- A parked value that cannot be a set: not a table, or its stats / guild part not a table (rawget: a broken
-- metatable cannot raise here).
local function unusable(v)
  if type(v) ~= "table" then return true end
  local stats, guild = rawget(v, "stats"), rawget(v, "guild")
  return (stats ~= nil and type(stats) ~= "table") or (guild ~= nil and type(guild) ~= "table")
end

-- Repairs the bookkeeping of the sets: db.guild.byChar maps names to guild names, db.guild.name is a name or nil,
-- db.guild.request a table or nil, db.guilds holds usable sets under string names and db.guilds_bad has string
-- keys. Anything else that held data is kept aside in db.guilds_bad, never thrown away.
local function repairGuilds(db)
  local g = db.guild
  if type(g.byChar) ~= "table" then g.byChar = {} end
  for k, v in pairs(g.byChar) do -- (setting a field that is there to nil while walking is allowed)
    if type(k) ~= "string" or type(v) ~= "string" or v == "" then g.byChar[k] = nil end
  end
  if g.name ~= nil and (type(g.name) ~= "string" or g.name == "") then g.name = nil end
  if g.request ~= nil and type(g.request) ~= "table" then g.request = nil end
  if type(g.requestResults) ~= "table" then g.requestResults = {} end
  for k, v in pairs(g.requestResults) do
    if type(k) ~= "string" or type(v) ~= "table" then g.requestResults[k] = nil end
  end
  if g.fitIn ~= nil and (type(g.fitIn) ~= "string" or g.fitIn == "") then g.fitIn = nil end
  if db.guilds_bad ~= nil and type(db.guilds_bad) ~= "table" then db.guilds_bad = { guilds_bad = db.guilds_bad } end
  local odd = {}
  for k in pairs(type(db.guilds_bad) == "table" and db.guilds_bad or {}) do
    if type(k) ~= "string" then odd[#odd + 1] = k end
  end
  for _, k in ipairs(odd) do
    local v = db.guilds_bad[k]
    db.guilds_bad[k] = nil
    keepAside(db, tostring(k), v)
  end
  if type(db.guilds) ~= "table" then
    if db.guilds ~= nil then keepAside(db, "guilds", db.guilds) end
    db.guilds = {}
  end
  odd = {}
  for k, v in pairs(db.guilds) do if type(k) ~= "string" or unusable(v) then odd[#odd + 1] = k end end
  for _, k in ipairs(odd) do
    local v = db.guilds[k]
    db.guilds[k] = nil
    keepAside(db, tostring(k), v)
  end
end

local function byName(a, b)
  local x, y = a:lower(), b:lower()
  if x ~= y then return x < y end
  return a < b
end

-- Every set of per-guild data, numbered as /tc guild shows them: number 0 is the data in use (from "top", name =
-- db.guild.name or "" for unnamed), then the parked sets (from "guilds") A-Z by name, then the sets kept aside (from
-- "bad", tables only) A-Z. Each: { number, from, key (its name in db.guilds / db.guilds_bad), name, set }.
function DB.sets(db)
  local g = type(db.guild) == "table" and db.guild or {}
  local out = { { number = 0, from = "top", name = isReal(g.name) and g.name or g.name == PLACEHOLDER and PLACEHOLDER
    or UNNAMED, set = topSet(db) } }
  for _, from in ipairs({ "guilds", "bad" }) do
    local tbl = from == "guilds" and db.guilds or db.guilds_bad
    local keys = {}
    for k, v in pairs(type(tbl) == "table" and tbl or {}) do
      if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end
    end
    table.sort(keys, byName)
    for _, k in ipairs(keys) do out[#out + 1] = { number = #out, from = from, key = k, name = k, set = tbl[k] } end
  end
  return out
end

-- The first free name for a set that steps aside for its guild: "<name> (replaced)", then "<name> (replaced 2)" ...
local function replacedName(db, name)
  local key, n = name .. " (replaced)", 1
  while db.guilds[key] ~= nil do n = n + 1; key = name .. " (replaced " .. n .. ")" end
  return key
end

-- Why a /tc guild request was not carried out, as said to the player.
local REASONS = {
  char = "another character logged in first", guild = "your guild changed", gone = "that set is gone",
  hasSet = "this guild already has a set", named = "another guild's data is in use",
  odd = "it could not be read", error = "something went wrong",
}

-- What the login swap does, as a plan: incoming = the set that comes up (nil: a fresh one), taken from
-- fromTbl[fromKey]; name = the name it has on top (nil: unnamed); setChar: byChar[character] becomes that name.
-- From a /tc guild request (one shot): only for the character that made it, while the game does not name another
-- guild; "new" only while unnamed or "?" data is on top and that guild has no set (or, on a game that names no
-- guild, to start the shared "?" set in use fresh: it is parked as "? (replaced)"); "load" while the chosen set is
-- still there.
local function requestPlan(db, req, charId)
  if type(req.guild) ~= "string" or req.guild == "" then return nil, "odd" end
  if req.char ~= charId then return nil, "char" end
  local g, want = db.guild, req.guild
  local now = ns.Util.plain(GetGuildInfo, "player")
  if isReal(want) and type(now) == "string" and now ~= "" and now ~= want then return nil, "guild" end
  if req.kind == "new" then
    local restart = want == PLACEHOLDER and g.name == PLACEHOLDER -- the shared set starts fresh (carryOut parks it)
    if not restart and (g.name == want or db.guilds[want] ~= nil) then return nil, "hasSet" end
    if isReal(g.name) then return nil, "named" end
    return { name = want, setChar = true }
  elseif req.kind == "load" then
    local tbl = (req.from == "bad" and db.guilds_bad) or (req.from == "guilds" and db.guilds) or nil
    local set = type(tbl) == "table" and type(req.key) == "string" and tbl[req.key] or nil
    if type(set) ~= "table" then return nil, "gone" end
    -- the unnamed (v0.1.24) set: parked as "", or kept aside as "#1", "#2" ... (keepAside of "")
    local unnamed = (req.from == "guilds" and req.key == UNNAMED)
      or (req.from == "bad" and req.key:find("^#%d+$") ~= nil)
    return { incoming = set, fromTbl = tbl, fromKey = req.key, name = want, setChar = true, pinOld = unnamed }
  end
  return nil, "odd"
end

-- From byChar (this character's guild in its last session): that guild's parked set. A guild without a set gets
-- one only while another guild's named set is on top: the unnamed set (its list decides in the game), else the "?"
-- set, else a fresh one. Unnamed or "?" data on top is never moved for a guild without a set.
local function loginPlan(db, charId)
  local g = db.guild
  local want = charId and g.byChar[charId]
  if type(want) ~= "string" or want == "" or want == g.name then return nil end
  if db.guilds[want] ~= nil then
    return { incoming = db.guilds[want], fromTbl = db.guilds, fromKey = want, name = want }
  end
  if not isReal(g.name) or not isReal(want) then return nil end
  for _, slot in ipairs({ UNNAMED, PLACEHOLDER }) do
    if db.guilds[slot] ~= nil then
      return { incoming = db.guilds[slot], fromTbl = db.guilds, fromKey = slot, name = slot ~= UNNAMED and slot or nil }
    end
  end
  return { name = want }
end

local function copyOf(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function refill(t, from)
  for k in pairs(t) do t[k] = nil end
  for k, v in pairs(from) do t[k] = v end
end

-- The unnamed (v0.1.24) set brought up by a request is taken by a guild without its list deciding: like a guild
-- that takes it in the game (Crew/GuildIdentity.lua), it pins its old crew to the panel once (guild.pinnedOld).
local function pinOldCrew(db)
  if db.guild.pinnedOld then return end
  db.guild.pinnedOld = true
  for name, row in pairs(db.roster) do
    if type(name) == "string" and type(row) == "table" and not ns.isTestName(name) then db.pins[name] = true end
  end
end

-- Carries a plan out. The set on top is parked under its own name ("" unnamed, "?"); when the incoming set takes
-- that same name, under "<name> (replaced)". A parked set of the name the incoming set takes steps aside the same way
-- (never two sets for one guild). Unnamed or "?" data never overwrites a parked set of its kind (it goes aside); a
-- guild parked twice keeps the top set (the older parked copy goes aside). An error halfway puts everything back.
local function carryOut(db, plan, charId)
  local g = db.guild
  local outgoing = topSet(db)
  mergeInto(outgoing, type(g.extra) == "table" and g.extra or nil)
  local before = { name = g.name, extra = g.extra, guilds = copyOf(db.guilds), char = g.byChar[charId],
    bad = type(db.guilds_bad) == "table" and copyOf(db.guilds_bad) or nil, hadBad = db.guilds_bad ~= nil }
  local outName = g.name or UNNAMED
  local ok, err = pcall(function()
    if plan.fromTbl then plan.fromTbl[plan.fromKey] = nil end
    if plan.name and db.guilds[plan.name] ~= nil then
      local other = db.guilds[plan.name]
      db.guilds[plan.name] = nil
      db.guilds[replacedName(db, plan.name)] = other
    end
    if outName == plan.name then
      db.guilds[replacedName(db, outName)] = outgoing
    elseif db.guilds[outName] == nil then
      db.guilds[outName] = outgoing
    elseif outName == UNNAMED or outName == PLACEHOLDER then
      keepAside(db, outName, outgoing, true)
    else
      keepAside(db, outName, db.guilds[outName], true)
      db.guilds[outName] = outgoing
    end
    local extra = plan.incoming and extraOf(plan.incoming) or nil
    putSet(db, plan.incoming or {})
    g.extra = extra
    g.name = plan.name
    if plan.setChar and charId then g.byChar[charId] = isReal(plan.name) and plan.name or nil end
    if plan.pinOld then pinOldCrew(db) end
  end)
  if not ok then -- everything back as it was
    putSet(db, outgoing)
    g.name, g.extra = before.name, before.extra
    refill(db.guilds, before.guilds)
    if before.bad then refill(db.guilds_bad, before.bad) elseif not before.hadBad then db.guilds_bad = nil end
    if charId then g.byChar[charId] = before.char end
    ns.Log.add("error", "switching saved data failed (%s): nothing changed", tostring(err))
    return false
  end
  ns.Log.add("info", "saved data of %s is in use", g.name or "(unnamed, from an older version)")
  return true
end

-- A set (parked or kept aside) other than the one in use that holds at least one real friend.
local function otherFriends(db)
  for _, tbl in ipairs({ db.guilds, db.guilds_bad }) do
    for k, set in pairs(type(tbl) == "table" and tbl or {}) do
      local roster = type(k) == "string" and type(set) == "table" and rawget(set, "roster")
      for name in pairs(type(roster) == "table" and roster or {}) do
        if type(name) == "string" and not ns.isTestName(name) then return true end
      end
    end
  end
  return false
end

-- The result of a /tc guild request for character `char`'s next login: said there once (DB.notes), then cleared.
local function sayResult(db, charId)
  local results = db.guild.requestResults
  local r = charId ~= nil and type(results) == "table" and results[charId] or nil
  if type(r) ~= "table" then return end
  results[charId] = nil
  DB.notes[#DB.notes + 1] = r.done and "TwizCrew: Your /tc guild request was carried out."
    or ("TwizCrew: Your /tc guild request was not carried out: " .. tostring(r.reason) .. ". Type /tc guild.")
end

-- At login, before any module reads per-guild data: uses up a /tc guild new or load request (carried out or not; its
-- result is kept in db.guild.requestResults for the character that made it, and said at that character's login),
-- else brings up this character's guild's set (see loginPlan, carryOut). DB.notes: the chat lines for this login
-- (Core/Boot.lua prints them): a request's result, and "<guild> starts with new TwizCrew data" when a guild got a
-- fresh set by itself while other sets hold friends. Returns true when it swapped.
function DB.useGuildOf(db, charId)
  DB.notes = {}
  if type(db) ~= "table" or type(db.guild) ~= "table" then return false end
  local g = db.guild
  local req = g.request
  local result
  local ok, plan, why = pcall(function()
    g.request = nil -- one shot: used up here whatever happens next
    if type(req) == "table" then result = { kind = req.kind, done = false } end
    repairGuilds(db)
    sayResult(db, charId) -- an earlier request's result for this character
    if not result then return nil end
    return requestPlan(db, req, charId)
  end)
  g.request = nil
  local failure
  if not ok then failure, plan = plan, nil end
  if result and not plan then
    result.reason = REASONS[ok and why or "error"] or REASONS.odd
    ns.Log.add("info", "a /tc guild %s request was not carried out: %s", tostring(result.kind), result.reason)
  end
  local swapped, fresh = false, false
  if ok then
    local fromRequest = plan ~= nil
    if not plan then
      local fine, p = pcall(loginPlan, db, charId)
      plan = fine and p or nil
    end
    if plan then
      swapped = carryOut(db, plan, charId)
      fresh = swapped and not fromRequest and plan.incoming == nil
    end
    if result and fromRequest then
      result.done = swapped
      if not swapped then result.reason = REASONS.error end
    end
  else
    ns.Log.add("error", "the login swap of saved data failed (%s): nothing changed", tostring(failure))
  end
  if result and type(req.char) == "string" then
    if type(g.requestResults) ~= "table" then g.requestResults = {} end
    g.requestResults[req.char] = result
    sayResult(db, charId)
  end
  if fresh and otherFriends(db) then
    DB.notes[#DB.notes + 1] = "TwizCrew: " .. ns.Util.safeText(tostring(g.name)) .. " starts with new TwizCrew data."
      .. " You have other saved sets: type /tc guild."
  end
  return swapped
end

-- db.guild.named: this account has read a real guild name from the game (set by Crew/Guild.lua). Data saved before
-- that flag existed counts when its set in use has a real guild name (never a "(replaced)" or kept-aside label).
local function markNamed(g)
  local n = g.name
  if isReal(n) and not n:find(" %(replaced[ %d]*%)$") and not n:find("#%d+$") then g.named = true end
end

-- Accepts nil or any type; returns a repaired table.
function DB.init(saved, defs)
  local fresh = type(saved) ~= "table" or next(saved) == nil -- a new install: no saved TwizCrew data at all
  local db = type(saved) == "table" and saved or {}
  if db.guilds ~= nil and type(db.guilds) ~= "table" then keepAside(db, "guilds", db.guilds); db.guilds = {} end
  guildDefaults(db)
  repairGuilds(db)
  markNamed(db.guild)
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
  -- the About page opens once by itself on a new install (UI/About.lua); data from an older version: never
  if fresh then db.aboutSeen = false elseif db.aboutSeen == nil then db.aboutSeen = true end
  return db
end

-- Rebuilds db.modules from defaults only; crew, roster, status and log are untouched.
function DB.resetSettings(db, defs)
  db.modules = {}
  for _, def in ipairs(defs or {}) do db.modules[def.id] = moduleDefaults(def) end
end
