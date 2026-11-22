-- The guild list: who is in the guild, what is their key, what is their full name. The one answer for the rest of the
-- addon (ns.Guild). Reads only what the game's guild functions give, every value through ns.Util.plain.
--
-- Key of a member: the first word of the name, unless another member already holds that word (saved keys count, and
-- so does the current list); then the full name. Keys are saved in ns.db.guild.keys[lower(full)] the first time a
-- member is seen (only on a complete read) and never change. Keys, like all data about other people, are kept per
-- guild (Core/DB.lua: the set on top belongs to ns.db.guild.name, the "data guild").
--
-- active(): in a guild, nothing pending, and the data on top belongs to it. Only then is the list read (but see
-- readMode), are keys given out, and does the addon send, accept, hide or write anything for the crew; otherwise it
-- acts as if in no guild. GUILD_STATE(active) fires when active() changes; inGuild() stays the game's answer. The
-- guild's identity is its name, sticky for the session; a change (or "no guild") counts only after the grace time
-- (settling), and one the game takes back reads the list again at once.
-- Whose data is on top (Core/DB.lua has the whole rule: nothing may strand, reassign or duplicate a set):
-- * Another guild's named set on top, or this guild has its own parked set: quiet, told once to /reload; byChar
--   (rememberGuild) makes the next login bring this guild's set up (or, for a guild without one, the unnamed set,
--   else the "?" set, else a fresh one).
-- * Unnamed or "?" data on top and this guild has no set: the one safe guess. It becomes this guild's at once when
--   nothing is saved, else when a complete list fits it (rosterFits). Otherwise TwizCrew is quiet this session, says
--   once how to choose, reads the list again at most once a minute (and on a roster update), and byChar is cleared so
--   the next login moves nothing. The player chooses: /tc guild use (only when the list fits, or "use yes"), /tc guild
--   new (a fresh set at the next login), /tc guild load <number> (a set shown this session, at the next login). use,
--   new and load wait while the guild is changing. Unnamed data taken by a guild pins its old crew once (pinOldCrew).
-- * Old friends are forgotten only while the saved friends fit the complete list (listFits, Crew's tidy).
-- * The game never names the guild (no name after GUILD_NAME_WAIT, and this account never read a real guild name,
--   db.guild.named): unnamed data that fits becomes "?", and "?" data is used in any guild (one shared set); use,
--   new (with yes: the set is shared) and load work and name the chosen set "?". A readable name later renames "?"
--   data only when the list fits (like unnamed data).
-- * A gap in the names (none now, but this account has read one): nothing is adopted; only load works, and the
--   chosen set becomes the shared "?" set.
-- My own key is saved per character GUID (ns.db.guild.mine) so myKey() can answer before the list loads.
local _, ns = ...

local FEATURE = "guild"
local Guild = {}
ns.Guild = Guild

local plain = ns.Util.plain
local COALESCE = 1       -- s: roster events closer than this are read once, after the gap
local TICK = 1           -- s: the ticker that checks membership and asks for refreshes
local MAX_MEMBERS = 2000 -- never read more rows than this
local STABLE_GAP, STABLE_READS = 5, 3 -- this many reads this far apart with one readable count: the list is whole
local ADOPT_RETRY = 60   -- s: unnamed or "?" data that did not fit a complete list: read again this often at most

local members, byFull, byKey, byFirst, byGuid = {}, {}, {}, {}, {}
local loaded = false
local complete = false       -- the last read gave as many readable rows as the game said there are
local announced              -- nil until known, then true / false: is the character in a guild (the game, after grace)
local activeAnnounced        -- nil until known, then what GUILD_STATE last said (in my TwizCrew guild)
local nameWaitSince          -- ns.now() since when we are in a guild that is not (yet) known to be the data guild
local curId                  -- this session's guild name, sticky: an unreadable answer keeps it
local otherId, otherSince    -- a different readable name the game gave, and since when (it counts after grace)
local inSince                -- ns.now() since the game says "in a guild"
local stableKey, stableN, stableAt = nil, 0, nil -- the same (counted, readable) on reads >= STABLE_GAP s apart
local counted, readableRows  -- the last read: rows the game counted, rows it gave readably
local told = {}              -- chat lines already printed this session (each at most once)
local seenIn                 -- what the game last said about being in a guild (nil: nothing usable yet)
local absentSince            -- ns.now() when the game first said "no guild" (nil while it says yes)
local lastRefresh, lastRead
local watched = false
local pendingRead = false
local started = false
local ticker
local signature = ""
local heldBy = {}            -- lower(key) -> lower(full name) of whoever was ever given that key (saved keys)
local quietAt                -- ns.now() of the last complete read that unnamed or "?" data did not fit (nil: none)
local previewed = {}         -- /tc guild load <n> shown this session: n -> the set it showed (from .. key)
local fallback = { keys = {}, mine = {}, spell = {} } -- used while saved data is not attached (tests, very early)

local function saved()
  local db = ns.db
  if type(db) ~= "table" then return fallback end
  if type(db.guild) ~= "table" then db.guild = {} end
  local g = db.guild
  if type(g.keys) ~= "table" then g.keys = {} end
  if type(g.mine) ~= "table" then g.mine = {} end
  if type(g.spell) ~= "table" then g.spell = {} end
  return g
end

local function savedKeys() return saved().keys end

-- "Chaos Deathbringr-Realm" / "Chaos Deathbringr" -> "Chaos Deathbringr"; nil when there is no usable name.
local function clean(raw)
  if type(raw) ~= "string" or ns.Util.isSecret(raw) then return nil end
  local name = raw
  local ok, amb = pcall(Ambiguate, name, "none")
  if ok and type(amb) == "string" and amb ~= "" then name = amb end
  name = name:match("^([^%-]*)") or name
  name = ns.Util.trim(name)
  if name == "" then return nil end
  return name
end

local function firstWord(full) return full:match("^(%S+)") or full end

local function realmSuffix()
  local realm = plain(GetRealmName)
  if type(realm) == "string" and realm ~= "" then return " " .. realm:lower() end
end

-- Seconds before now from GetGuildRosterLastOnline's years, months, days, hours (30-day months, 365-day years).
local function offlineSeconds(y, mo, d, h)
  if type(y) ~= "number" and type(mo) ~= "number" and type(d) ~= "number" and type(h) ~= "number" then return nil end
  y, mo, d, h = tonumber(y) or 0, tonumber(mo) or 0, tonumber(d) or 0, tonumber(h) or 0
  return ((y * 365 + mo * 30 + d) * 24 + h) * 3600
end

-- One list row from the game, or nil.
local function readRow(i)
  local r = { plain(GetGuildRosterInfo, i) }
  local full = clean(r[1])
  if not full then return nil end
  local e = { full = full, first = firstWord(full) }
  e.rank = type(r[2]) == "string" and r[2] or ""
  e.rankIndex = type(r[3]) == "number" and r[3] or nil
  e.level = type(r[4]) == "number" and r[4] or nil
  e.zone = type(r[6]) == "string" and r[6] or ""
  e.online = r[9] == true
  e.class = type(r[11]) == "string" and r[11] or nil
  e.guid = type(r[17]) == "string" and r[17] or nil
  if not e.online then
    local y, mo, d, h = plain(GetGuildRosterLastOnline, i)
    local secs = offlineSeconds(y, mo, d, h)
    e.lastOnlineRaw = secs
    e.lastOnline = secs and (ns.wallclock() - secs) or nil
  end
  return e
end

local function savedClassOf(first)
  local roster = ns.db and ns.db.roster
  if type(roster) ~= "table" then return nil end
  local row = roster[first]
  if type(row) ~= "table" then
    local lower = first:lower()
    for name, r in pairs(roster) do
      if type(name) == "string" and name:lower() == lower then row = r; break end
    end
  end
  return type(row) == "table" and type(row.class) == "string" and row.class or nil
end

-- The full name as the game spells it (guild.spell[lower(full)]), for lasting records (recordName).
local function saveSpelling(e) saved().spell[e.full:lower()] = e.full end

-- Gives every entry its key (entries are sorted A-Z by full name). allowNew false (a partial read): only saved keys,
-- an entry without one gets none.
local function assignKeys(entries, allowNew)
  local saved = savedKeys()
  local holder = {} -- lower(key) -> lower(full name) of the member who has it
  for lf, key in pairs(saved) do
    if type(lf) == "string" and type(key) == "string" and key ~= "" then holder[key:lower()] = lf end
  end
  local groups, order = {}, {}
  for _, e in ipairs(entries) do
    local lf = e.full:lower()
    local key = saved[lf]
    if type(key) == "string" and key ~= "" then
      e.key = key
    else
      local lw = e.first:lower()
      if allowNew then
        if not groups[lw] then groups[lw] = {}; order[#order + 1] = lw end
        groups[lw][#groups[lw] + 1] = e
      end
    end
  end
  -- a key no other full name holds (case-insensitive): the wanted one, else "Name (2)", "Name (3)"...
  local function free(wanted, lf)
    local key, n = wanted, 1
    while holder[key:lower()] and holder[key:lower()] ~= lf do
      n = n + 1
      key = wanted .. " (" .. n .. ")"
    end
    holder[key:lower()] = lf
    return key
  end
  for _, lw in ipairs(order) do
    local group = groups[lw]
    local winner
    if not holder[lw] then
      for _, e in ipairs(group) do -- a one-word name is its own first word
        if e.full:lower() == lw then winner = e; break end
      end
      if not winner and #group == 1 then winner = group[1] end
      if not winner then
        local class = savedClassOf(group[1].first)
        if class then
          for _, e in ipairs(group) do
            if e.class == class then winner = e; break end
          end
        end
        winner = winner or group[1]
      end
    end
    for _, e in ipairs(group) do
      e.key = free((e == winner) and e.first or e.full, e.full:lower())
      saved[e.full:lower()] = e.key
      saveSpelling(e)
    end
  end
  heldBy = holder
end

local function sigOf(entries)
  local parts = {}
  for i, e in ipairs(entries) do
    parts[i] = table.concat({ e.key, e.full, e.class or "", e.level or "", e.zone, e.rank, e.rankIndex or "",
      e.online and "1" or "0", e.lastOnlineRaw or "", e.guid or "" }, "\1")
  end
  return table.concat(parts, "\2")
end

local guidsComplete = false -- every listed member has a GUID (then a unit whose GUID is not listed is no member)

local function install(entries)
  members, byFull, byKey, byFirst, byGuid = entries, {}, {}, {}, {}
  guidsComplete = #entries > 0
  for _, e in ipairs(entries) do
    if not e.guid then guidsComplete = false end
    byFull[e.full:lower()] = e
    byKey[e.key:lower()] = e
    local lw = e.first:lower()
    byFirst[lw] = byFirst[lw] or {}
    byFirst[lw][#byFirst[lw] + 1] = e
    if e.guid then byGuid[e.guid] = e end
  end
end

-- This character's guild name as the game gives it (nil when it gives none, or a secret). The guild's identity is
-- its name alone (a realm the game gives now and then would make it flip).
local function guildId()
  local name = plain(GetGuildInfo, "player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

local PLACEHOLDER = "?" -- the data guild's name when the game never named the guild (single-guild mode)

local function dataGuild()
  local g = ns.db and ns.db.guild
  local name = type(g) == "table" and g.name
  return type(name) == "string" and name ~= "" and name or nil
end

local function isReal(name) return type(name) == "string" and name ~= "" and name ~= PLACEHOLDER end

-- Guild `name` has a parked set (db.guilds[name]).
local function hasSet(name)
  local guilds = ns.db and ns.db.guilds
  return type(guilds) == "table" and guilds[name] ~= nil
end

-- db.guild.byChar[this character] decides which set the next login puts on top (DB.useGuildOf). It names this
-- character's guild `id` only when that guild has a set (on top, or parked), or when another guild's named set is on
-- top (the next login parks that one under its own name). Never for unnamed or "?" data the guild has not taken:
-- then it is cleared, and the next login changes nothing.
local function rememberGuild(id)
  local g = ns.db and ns.db.guild
  local char = ns.DB.charId()
  if type(g) ~= "table" or type(g.byChar) ~= "table" or not char or not isReal(id) then return end
  local dg = dataGuild()
  if dg == id or hasSet(id) or isReal(dg) then g.byChar[char] = id else g.byChar[char] = nil end
end

-- Is v empty: nil, or a table holding only empty tables (skip: a field to leave out, e.g. the calendar's own id)?
local function hollow(v, skip)
  if v == nil then return true end
  if type(v) ~= "table" then return false end
  for k, x in pairs(v) do
    if k ~= skip and not hollow(x) then return false end
  end
  return true
end

-- Nothing at all is saved on top for a crew: every per-guild field of DB.GUILD_PATHS is missing or empty (the
-- calendar's "me", this account's own diary id made when the calendar is first used, is not about anyone).
local function dataEmpty()
  local db = ns.db
  for _, path in ipairs(ns.DB.GUILD_PATHS) do
    local parent, key = path:match("^(%w+)%.(%w+)$")
    local from = parent and db[parent] or db
    local v = type(from) == "table" and from[key or path] or nil
    if path ~= "guild.pinnedOld" and not hollow(v, path == "calendar" and "me" or nil) then return false end
  end
  return true
end

-- Real (not test) rows of the saved roster: { name, row }.
local function savedRows()
  local out = {}
  local roster = ns.db and ns.db.roster
  for name, row in pairs(type(roster) == "table" and roster or {}) do
    if type(name) == "string" and type(row) == "table" and not ns.isTestName(name) then
      out[#out + 1] = { name = name, row = row }
    end
  end
  return out
end

-- Does the saved roster on top belong to the guild of this list? Rows whose first word a listed member has (and,
-- when both sides know a class, the same class) count: at least 2 of them and at least half of the rows; a roster of
-- one row only when its class is known and equal. An empty roster fits only when nothing at all is saved (dataEmpty).
-- Returns fits, then how many saved rows matched and how many there are.
local function rosterFits(entries)
  local rows = savedRows()
  if #rows == 0 then return dataEmpty(), 0, 0 end
  local byF = {}
  for _, e in ipairs(entries or {}) do
    local lw = e.first:lower()
    byF[lw] = byF[lw] or {}
    byF[lw][#byF[lw] + 1] = e
  end
  local matches, sure = 0, 0
  for _, r in ipairs(rows) do
    local class = type(r.row.class) == "string" and r.row.class ~= "" and r.row.class or nil
    for _, e in ipairs(byF[(r.name:match("^(%S+)") or r.name):lower()] or {}) do
      if not class or not e.class or class == e.class then
        matches = matches + 1
        if class and e.class then sure = sure + 1 end
        break
      end
    end
  end
  if #rows == 1 then return sure == 1, matches, 1 end
  return matches >= 2 and matches * 2 >= #rows, matches, #rows
end

-- Says a line once per session.
local function tell(id, text)
  if told[id] then return end
  told[id] = true
  print(text)
end

-- Unnamed (v0.1.24) data taken by a guild: every saved friend is pinned to the panel's main view, once per set
-- (guild.pinnedOld): the old crew were people the player chose, so they stay in view with their notices.
local function pinOldCrew()
  local db = ns.db
  if type(db.guild) ~= "table" or db.guild.pinnedOld then return end
  db.guild.pinnedOld = true
  if type(db.pins) ~= "table" then db.pins = {} end
  for _, r in ipairs(savedRows()) do db.pins[r.name] = true end
end

-- Unnamed data on top becomes guild `name`'s (a real name, or "?" without one), unless that guild has a parked set.
-- Returns true when it did.
local function nameData(name)
  local g = ns.db and ns.db.guild
  if type(g) ~= "table" or dataGuild() ~= nil and dataGuild() ~= PLACEHOLDER then return false end
  if hasSet(name) then return false end
  if dataGuild() == nil then pinOldCrew() end
  g.name = name
  rememberGuild(name)
  ns.Log.add("info", "saved data now belongs to %s", name == PLACEHOLDER and "a guild the game does not name"
    or ns.Util.safeText(name))
  return true
end

local function byFullName(a, b)
  local x, y = a.full:lower(), b.full:lower()
  if x ~= y then return x < y end
  return a.full < b.full
end

-- Saves my key for this character (ns.db.guild.mine[GUID]) once the list has me.
local function rememberMyKey()
  local guid = plain(UnitGUID, "player")
  if type(guid) ~= "string" then return end
  local e = byGuid[guid]
  if not e then
    local mine = clean(plain(UnitName, "player"))
    e = mine and byFull[mine:lower()]
  end
  if e then saved().mine[guid] = e.key end
end

local updateActive -- (below)

-- A guild switch or "no guild" is pending: nothing counts until the game settles.
local function settling() return otherId ~= nil or (absentSince ~= nil and announced ~= false) end

-- The game has not named the guild for GUILD_NAME_WAIT s since we are in it.
local function nameless()
  return curId == nil and inSince ~= nil and ns.now() - inSince >= ns.Config.GUILD_NAME_WAIT
end

-- This account has read a real guild name from the game (db.guild.named; then a missing name is a passing gap, not a
-- game that never names guilds). Names of parked sets never count.
local function namesSeen()
  local g = ns.db and ns.db.guild
  return type(g) == "table" and g.named == true
end

-- The name this character's guild's data goes under: its readable name; on a game that never names guilds (no name
-- after GUILD_NAME_WAIT s, and none ever seen on this account) "?"; else nil (not known now).
local function here()
  if curId then return curId end
  if nameless() and not namesSeen() then return PLACEHOLDER end
  return nil
end

-- Why the list may be read now: "active" (the data on top is this guild's), "adopt" (unnamed data, or "?" data and
-- a readable name: does it fit this guild?), or nil (another guild's data, this guild has its own set, a switch
-- pending, not in a guild).
local function readMode()
  if not Guild.inGuild() or settling() or not ns.db then return nil end
  if Guild.active() then return "active" end
  local dg, id = dataGuild(), here()
  if dg == nil and id and not hasSet(id) then return "adopt" end
  if dg == PLACEHOLDER and curId and not hasSet(curId) then return "adopt" end
  return nil
end

local NO_NAMES = "This game does not tell addons the guild's name, so TwizCrew uses one shared set of saved data."

-- Unnamed or "?" data and a complete list that does not fit it: quiet this session, and the player is told how to
-- choose (only commands that work here).
local function tellChoice()
  local safe = ns.Util.safeText
  if curId then
    local what = dataGuild() == PLACEHOLDER and "TwizCrew has saved data taken while the game did not name the guild."
      or "TwizCrew has saved data from before it used guilds."
    tell("legacy", what .. " If " .. safe(curId) .. " is your crew's guild, type /tc guild use. To start fresh for "
      .. safe(curId) .. ", type /tc guild new.")
  else
    tell("legacy", NO_NAMES .. " The friends saved in it are not in this guild. If it is your crew's data, type /tc"
      .. " guild use.")
  end
end

-- The game's list as it is now: entries (one per full name), the count the game gives, readable rows, and the set of
-- lower-case full names read.
local function readList()
  local count = plain(GetNumGuildMembers)
  if type(count) ~= "number" or count <= 0 then return {}, count, 0, {} end
  local entries, seen, readable = {}, {}, 0
  for i = 1, math.min(count, MAX_MEMBERS) do
    local e = readRow(i)
    if e then
      readable = readable + 1
      if not seen[e.full:lower()] then
        seen[e.full:lower()] = true
        entries[#entries + 1] = e
      end
    end
  end
  return entries, count, readable, seen
end

-- Reads the game's list (see readMode). A list that cannot be read (secret values, nothing yet) changes nothing.
-- A partial read (fewer readable rows than the game counts, unless the same counts came back on STABLE_READS reads
-- STABLE_GAP s apart) updates the members it did read, keeps the others as they were and gives out no new keys;
-- complete() tells which one the last read was.
local function read()
  lastRead = ns.now()
  local mode = readMode()
  if not mode then return end
  local entries, count, readable, seen = readList()
  if type(count) ~= "number" or count <= 0 then return end
  counted, readableRows = count, readable
  if #entries == 0 then return end
  local now, key = ns.now(), count .. "/" .. readable
  if key ~= stableKey then
    stableKey, stableN, stableAt = key, 1, now
  elseif now - stableAt >= STABLE_GAP then
    stableN, stableAt = stableN + 1, now
  end
  local isComplete = readable == count or stableN >= STABLE_READS
  if mode == "adopt" then
    if not isComplete then return end -- whose data it is waits for a complete list
    if not (rosterFits(entries) and nameData(here())) then
      quietAt = now -- read again at most every ADOPT_RETRY s (and on a roster update)
      tellChoice()
      return
    end
  end
  table.sort(entries, byFullName) -- keys are given out A-Z
  assignKeys(entries, isComplete)
  if isComplete then for _, e in ipairs(entries) do if e.key then saveSpelling(e) end end end
  local kept = {}
  for _, e in ipairs(entries) do if e.key then kept[#kept + 1] = e end end
  if not isComplete then -- members this read could not see stay as they were
    for _, e in ipairs(members) do
      if not seen[e.full:lower()] then kept[#kept + 1] = e end
    end
  end
  if #kept == 0 then return end
  table.sort(kept, byFullName)
  local sig = sigOf(kept)
  local first = not loaded
  local changed = sig ~= signature or (isComplete and not complete)
  install(kept)
  loaded, complete = true, isComplete
  signature = sig
  rememberMyKey()
  if first or changed then ns.Bus.fire("GUILD_LIST") end
  if mode ~= "active" then updateActive() end
end

local function readSoon()
  if lastRead and ns.now() - lastRead < COALESCE then
    if not pendingRead then
      pendingRead = true
      C_Timer.After(COALESCE, function()
        pendingRead = false
        ns.Log.safe(FEATURE, read)
      end)
    end
    return
  end
  read()
end

-- Drops the list (left the guild, or the data on top is not this guild's).
local function dropList()
  local had = loaded or #members > 0
  loaded, complete, signature = false, false, ""
  stableKey, stableN, stableAt = nil, 0, nil
  quietAt = nil
  install({})
  if had then ns.Bus.fire("GUILD_LIST") end
end

-- This session's guild is known and the data on top is another guild's (a real name).
local function otherGuild(id)
  local dg = dataGuild()
  return id ~= nil and dg ~= nil and dg ~= PLACEHOLDER and dg ~= id
end

-- GUILD_STATE follows active(). While the guild is not known to be the data guild yet (no name, unnamed data
-- waiting for a complete list), nothing is said for up to GUILD_ABSENT_GRACE seconds; while a switch or "no guild"
-- is pending, a true already said stays said (nothing is sent meanwhile: active() is false).
updateActive = function()
  if announced == nil then return end
  local now = Guild.active()
  if not now and settling() and activeAnnounced == true then return end
  if announced and not now and not otherGuild(curId) then
    nameWaitSince = nameWaitSince or ns.now()
    if activeAnnounced == nil and ns.now() - nameWaitSince < ns.Config.GUILD_ABSENT_GRACE then return end
  else
    nameWaitSince = nil
  end
  if now == activeAnnounced then return end
  activeAnnounced = now
  if now then
    ns.Bus.fire("GUILD_STATE", true)
    read()
    Guild.refresh()
  else
    dropList()
    ns.Bus.fire("GUILD_STATE", false)
  end
end

-- The game named the guild, or named another one (curId changed): byChar (rememberGuild), the lines. Unnamed or
-- "?" data is this guild's at once only when nothing is saved; otherwise its complete list decides (readMode
-- "adopt", read at once).
local function onIdentity(id)
  local g = ns.db and type(ns.db.guild) == "table" and ns.db.guild or nil
  if not g then return end
  local safe = ns.Util.safeText
  dropList()
  g.named = true -- this account has seen a readable guild name (see here)
  local dg = dataGuild()
  if (dg == nil or dg == PLACEHOLDER) and dataEmpty() then nameData(id) end -- nothing saved yet: this guild's
  rememberGuild(id)
  dg = dataGuild()
  if dg == id then return end
  if isReal(dg) then
    tell("reload:" .. id, "TwizCrew keeps separate data for each guild. Type /reload to switch to " .. safe(id) .. ".")
    ns.Log.add("info", "this character's guild %s uses other saved data than %s", safe(id), safe(dg))
  elseif hasSet(id) then
    if dg == PLACEHOLDER then
      ns.Log.add("warn", "%s has its own saved data: the data in use keeps no guild name (\"?\")", safe(id))
    end
    tell("reload:" .. id, "TwizCrew: " .. safe(id) .. " has its own saved data. Type /reload to switch to it.")
  elseif readMode() == "adopt" then
    read()
  end
end

-- Membership: true at once, false only after the grace time of the game saying so. The guild's name is sticky for
-- the session: the first readable one counts, an unreadable answer keeps it, and only a different readable one that
-- stays for GUILD_ABSENT_GRACE seconds replaces it. While a switch or "no guild" is pending nothing is read or sent.
local function checkState()
  local now = plain(IsInGuild)
  if now == nil then return end
  local wasSettling = settling()
  seenIn = now == true
  local t = ns.now()
  if seenIn then
    absentSince = nil
    announced = true
    inSince = inSince or t
    local id = guildId()
    local changed
    if id and id ~= curId then
      if not curId then
        curId, otherId, changed = id, nil, true
      elseif otherId ~= id then
        otherId, otherSince = id, t
        dropList()
      elseif t - otherSince >= ns.Config.GUILD_ABSENT_GRACE then
        curId, otherId, changed = id, nil, true
      end
    elseif id then
      otherId = nil
    end
    if changed then onIdentity(curId) end
    if here() == PLACEHOLDER and dataGuild() == nil and dataEmpty() then nameData(PLACEHOLDER) end
    if nameless() and not here() and not Guild.active() then -- a gap in the names: only load works here (loadHere)
      local dg = dataGuild()
      tell("nameless", "TwizCrew cannot read this guild's name right now, " .. (isReal(dg) and ("and the saved data in"
        .. " use is " .. ns.Util.safeText(dg) .. "'s, ") or "") .. "so it waits. Type /tc guild to see your saved"
        .. " sets; /tc guild load <number> uses one here.")
    end
  else
    if not absentSince then -- any "no guild" answer: nothing counts until the game settles
      absentSince = t
      otherId = nil
      dropList()
    end
    if announced ~= false and t - absentSince >= ns.Config.GUILD_ABSENT_GRACE then
      announced, curId, inSince = false, nil, nil
      local g = ns.db and type(ns.db.guild) == "table" and ns.db.guild or nil
      local char = g and ns.DB.charId()
      if char and type(g.byChar) == "table" then g.byChar[char] = nil end
    end
  end
  if wasSettling and not settling() and Guild.inGuild() then
    read() -- the game took the change back: the list was dropped, read it again now (not at the next refresh)
  elseif readMode() == "adopt" then
    local gap = quietAt and ADOPT_RETRY or STABLE_GAP -- (a list that did not fit: once a minute)
    if not lastRead or ns.now() - lastRead >= gap then read() end
  end
  updateActive()
end

-- The game's answer: is this character in a guild (any guild)?
function Guild.inGuild() return announced == true end
function Guild.known() return announced ~= nil end
function Guild.loaded() return loaded end
function Guild.complete() return loaded and complete end

-- This session's guild name (sticky; nil while the game names none); the guild the saved data on top belongs to
-- (nil: unnamed, from before guilds; "?": taken while the game named no guild).
Guild.name = guildId
function Guild.id() return curId end
Guild.dataGuild = dataGuild
Guild.PLACEHOLDER = PLACEHOLDER
Guild.dataEmpty = dataEmpty

-- The last read: rows the game counted and rows it gave readably (nil before any read).
function Guild.readStats() return counted, readableRows end

-- Counts the guild list's rows now, read or not (for /tc guildtest, also while TwizCrew is quiet).
function Guild.countRows()
  local count = plain(GetNumGuildMembers)
  if type(count) ~= "number" or count <= 0 then return count, 0 end
  local readable = 0
  for i = 1, math.min(count, MAX_MEMBERS) do if readRow(i) then readable = readable + 1 end end
  return count, readable
end

-- In a guild, nothing pending, and the data on top is this guild's: by its name; without a readable name (after
-- GUILD_NAME_WAIT s), "?" data always, real-named data when this character's last guild was it (byChar). The only
-- state in which the addon reads the list, gives out keys, sends, accepts, hides or writes anything for the crew.
function Guild.active()
  if not Guild.inGuild() or settling() then return false end
  local dg = dataGuild()
  if not dg then return false end
  if curId then return curId == dg end
  if not nameless() then return false end
  if dg == PLACEHOLDER then return true end
  local char = ns.DB.charId()
  local by = ns.db.guild.byChar
  return char ~= nil and type(by) == "table" and by[char] == dg
end

-- In a guild whose name is known, and the data on top is another guild's, or this guild has its own parked set:
-- TwizCrew stays quiet until a /reload (byChar says which set the next login brings up).
function Guild.needsReload()
  if not Guild.inGuild() then return false end
  return otherGuild(curId) or (curId ~= nil and dataGuild() ~= curId and hasSet(curId))
end

-- In a guild, but the data on top is not (known to be) its own: TwizCrew waits (or stays quiet).
function Guild.quiet() return Guild.inGuild() and not Guild.active() end

-- In a guild and TwizCrew is still finding out whether the data on top is this guild's: a guild change pending, the
-- name not given yet, or unnamed / "?" data waiting for a complete list. (Quiet but not deciding: the data is
-- another guild's, or the list did not fit.)
function Guild.deciding()
  if not Guild.inGuild() or Guild.active() then return false end
  if settling() or (curId == nil and not nameless()) then return true end
  return readMode() == "adopt" and quietAt == nil
end

-- A guild switch or "no guild" is pending (the game has not settled yet).
Guild.settling = settling

-- The guild list is complete and the saved friends on top fit it (rosterFits). Only then does Crew's tidy forget
-- friends not seen for 60 days: a set used in a guild it does not fit (use yes, load, a nameless gap, "?" on an alt)
-- forgets nothing.
function Guild.listFits() return loaded and complete and (rosterFits(members)) end

-- May this character write to the per-guild saved data (my session, my calendar marks)? Only while active: a
-- character in no guild or in another guild leaves the data on top as it is.
function Guild.writable() return Guild.active() end

-- The checks use, new and load share: in a guild, nothing pending, this guild's name known (here). Returns the name,
-- or nil and why: "noguild", "changing", "noname". forLoad: in a gap in the names (an account that has read guild
-- names, none now) load still works, and the chosen set becomes the shared "?" set.
local function commandGuild(forLoad)
  if not Guild.inGuild() then return nil, "noguild" end
  if settling() then return nil, "changing" end
  local id = here()
  if not id and forLoad and nameless() then id = PLACEHOLDER end
  if not id then return nil, "noname" end
  return id
end

-- This guild has a parked set: "parked" (byChar written: the next login brings it up), or "parkedShared" for the
-- "?" set (no byChar without a readable name: /tc guild load brings it up).
local function parked(id)
  if id == PLACEHOLDER then return "parkedShared" end
  rememberGuild(id)
  return "parked"
end

-- Records a one-shot request for DB.useGuildOf; an older result for this character is not said any more.
local function request(r)
  local g = ns.db.guild
  r.char = ns.DB.charId()
  g.request = r
  if type(g.requestResult) == "table" and g.requestResult.char == r.char then g.requestResult = nil end
end

-- /tc guild use [yes]: the data on top (unnamed or "?") becomes this guild's, at once, when the saved friends fit
-- this guild's list (rosterFits) or nothing is saved; with yes also when they do not. Unnamed data taken this way
-- pins the old crew (pinOldCrew). Cancels a /tc guild new or load request. Returns true, or false and why:
-- commandGuild's, "inuse" (it is already), "parked" / "parkedShared" (see parked), "named" (another guild's data is
-- on top: /reload), "noroster" (no friend list to check), "nolist" (the list is not in yet), "nofit" (with the number
-- of saved friends in this guild, and of saved friends).
function Guild.useHere(yes)
  local id, why = commandGuild()
  if not id then return false, why end
  local dg = dataGuild()
  if dg == id then return false, "inuse" end
  if hasSet(id) then return false, parked(id) end
  if isReal(dg) then return false, "named" end
  if not dataEmpty() and not yes then
    if #savedRows() == 0 then return false, "noroster" end
    local entries = readList()
    if #entries == 0 then return false, "nolist" end
    local fits, matches, rows = rosterFits(entries)
    if not fits then return false, "nofit", matches, rows end
  end
  local g = ns.db.guild
  if dg == nil then pinOldCrew() end
  g.name = id
  g.request = nil
  rememberGuild(id)
  quietAt = nil
  ns.Log.add("info", "/tc guild use%s: the saved data is %s's", yes and " yes" or "", ns.Util.safeText(id))
  updateActive()
  return true
end

-- /tc guild new [yes]: this guild gets a fresh set of its own at the next login (a one-shot request DB.useGuildOf
-- carries out; the unnamed or "?" data on top is parked, nothing is deleted). On a game that never names guilds the
-- set is shared by every character, so it needs yes. Returns true, or false and why: commandGuild's, "inuse",
-- "parked" / "parkedShared" (this guild has a set: never a second one), "named" (another guild's data is on top:
-- /reload first), "shared" (yes needed).
function Guild.newHere(yes)
  local id, why = commandGuild()
  if not id then return false, why end
  local dg = dataGuild()
  if dg == id then return false, "inuse" end
  if hasSet(id) then return false, parked(id) end
  if isReal(dg) then return false, "named" end
  if id == PLACEHOLDER and not yes then return false, "shared" end
  request({ kind = "new", guild = id })
  ns.Log.add("info", "/tc guild new: %s gets fresh saved data at the next login", ns.Util.safeText(id))
  return true
end

-- /tc guild load <number> [yes]: set <number> of ns.DB.sets becomes this guild's data at the next login. Without yes
-- it only remembers which set <number> showed; yes records a one-shot request DB.useGuildOf carries out (the set in
-- use is parked, nothing is deleted or merged), and only for the set shown this session under that number. Returns
-- true and the set, or false and why: commandGuild(true)'s, "nonumber" (no such set), "inuse" (set 0), "nopreview".
function Guild.loadHere(number, yes)
  local id, why = commandGuild(true)
  if not id then return false, why end
  local entry = type(number) == "number" and ns.DB.sets(ns.db)[number + 1] or nil
  if not entry then return false, "nonumber" end
  if entry.from == "top" then return false, "inuse", entry end
  local shown = entry.from .. ":" .. entry.key
  if not yes then
    previewed[number] = shown
    return true, entry
  end
  if previewed[number] ~= shown then return false, "nopreview", entry end
  request({ kind = "load", guild = id, from = entry.from, key = entry.key })
  ns.Log.add("info", "/tc guild load: set %s becomes %s's at the next login", tostring(number), ns.Util.safeText(id))
  return true, entry
end

-- The name the commands speak of for this character's guild ("?" on a game that never names guilds).
Guild.here = here

-- Asks the game for a fresh list, at most once per GUILD_REFRESH_MIN seconds. Returns true when it asked.
function Guild.refresh()
  if plain(IsInGuild) ~= true then return false end
  if otherGuild(curId) then return false end -- another guild's data is in use
  local now = ns.now()
  if lastRefresh and now - lastRefresh < ns.Config.GUILD_REFRESH_MIN then return false end
  local fn = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
  if type(fn) ~= "function" then return false end
  lastRefresh = now
  plain(fn)
  return true
end

function Guild.setWatched(on) watched = on and true or false end

local function interval()
  return watched and ns.Config.GUILD_REFRESH_SHOWN or ns.Config.GUILD_REFRESH_HIDDEN
end

local function tick()
  checkState()
  if seenIn and (not lastRefresh or ns.now() - lastRefresh >= interval()) then Guild.refresh() end
end

-- The entries are shared tables: callers must not change them.
function Guild.members()
  local out = {}
  for i, e in ipairs(members) do out[i] = e end
  return out
end

function Guild.get(key)
  if type(key) ~= "string" then return nil end
  local e = byKey[key:lower()]
  if e and e.key == key then return e end
  return nil
end

function Guild.count()
  local online = 0
  for _, e in ipairs(members) do if e.online then online = online + 1 end end
  return online, #members
end

-- The member a raw game name belongs to, in any form: the first word, the full name, with or without "-Realm" (or the
-- space form " Realm"). nil for a stranger, an unreadable name, or while the list is not loaded.
local function lookup(raw)
  if not loaded then return nil end
  local name = clean(raw)
  if not name then return nil end
  local l = name:lower()
  local suffix = realmSuffix()
  if suffix and #l > #suffix and l:sub(-#suffix) == suffix and not byFull[l] then
    l = l:sub(1, #l - #suffix)
  end
  -- order: an exact full name, then an exact key, then (one word only) the first-word fallback; unless the word
  -- was once given to someone else (then it is theirs, even while they are away)
  local e = byFull[l] or byKey[l]
  if e then return e end
  if not l:find(" ", 1, true) then
    local same = byFirst[l]
    if same and #same == 1 and (not heldBy[l] or heldBy[l] == same[1].full:lower()) then return same[1] end
  end
  return nil
end

-- "Chaos Deathbringr-Realm" -> "Chaos Deathbringr" (nil when there is no usable name). The one place names are cleaned.
Guild.cleanName = clean

-- lower(full name) of a raw name, with our realm taken off in the " Realm" form too.
local function lowerFull(raw)
  local name = clean(raw)
  if not name then return nil end
  local l = name:lower()
  local suffix = realmSuffix()
  if suffix and #l > #suffix and l:sub(-#suffix) == suffix and not byFull[l] then l = l:sub(1, #l - #suffix) end
  return l
end

-- The key saved for this member the first time the guild list showed them (any name form, any case), also while the
-- list is not loaded; nil when they were never listed.
function Guild.savedKeyOf(raw)
  local l = lowerFull(raw)
  local key = l and savedKeys()[l]
  return type(key) == "string" and key ~= "" and key or nil
end

-- True when the saved keys or the current list give `key` (any case) to someone other than `raw`.
function Guild.keyTakenByOther(key, raw)
  if type(key) ~= "string" then return false end
  local lk, l = key:lower(), lowerFull(raw)
  for lf, k in pairs(savedKeys()) do
    if type(k) == "string" and k:lower() == lk and lf ~= l then return true end
  end
  local e = byKey[lk]
  return e ~= nil and e.full:lower() ~= l
end

function Guild.keyOf(raw)
  local e = lookup(raw)
  return e and e.key or nil
end

-- How a member is named in a short-lived message field (a mock's target, a quest share ask, a vote, an award card's
-- winners; trophy records hold full names instead, see recordName):
-- their first word when no other current member starts with it (any case), else their full name; a key the list
-- does not have, as it is. Keys are this copy's own (another copy may have given a namesake pair the opposite keys),
-- names are the same for every copy: fromWire reads them back.
function Guild.wireName(key)
  local e = Guild.get(key)
  if not e then return key end
  local same = byFirst[e.first:lower()]
  if same and #same > 1 then return e.full end
  return e.first
end

-- My key for the member a name from a message field stands for: an exact full name among current members, else a
-- first word exactly one current member has (an old copy's first word too). Never a key. nil for anyone else, a
-- first word two members share, an unreadable name, or while the list is not loaded.
function Guild.fromWire(raw)
  if not loaded then return nil end
  local l = lowerFull(raw)
  if not l then return nil end
  local e = byFull[l]
  if e then return e.key end
  if not l:find(" ", 1, true) then
    local same = byFirst[l]
    if same and #same == 1 then return same[1].key end
  end
  return nil
end

-- The full name to write into a lasting record (a trophy record) for a member key: from the list, else the spelling
-- saved for them (guild.spell), else (last resort) the lower-case saved key name with each word's capital rebuilt,
-- else the key as it is.
function Guild.recordName(key)
  if type(key) ~= "string" or ns.isTestName(key) then return key end
  local e = Guild.get(key)
  if e then return e.full end
  local spell = saved().spell
  for lf, k in pairs(savedKeys()) do
    if k == key and type(lf) == "string" then
      if type(spell[lf]) == "string" then return spell[lf] end
      return (lf:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b end))
    end
  end
  return key
end

-- My key for a name read from a lasting record: an exact full name in the list or in the saved keys; a single
-- first word: whoever was given that word as key (the saved keys), even if they left, never whoever has that word
-- alone today. nil otherwise (shown as plain text).
function Guild.fromRecord(raw)
  local l = lowerFull(raw)
  if not l then return nil end
  local e = loaded and byFull[l]
  if e then return e.key end
  local keys = savedKeys()
  if type(keys[l]) == "string" and keys[l] ~= "" then return keys[l] end
  if not l:find(" ", 1, true) then
    for _, key in pairs(keys) do
      if type(key) == "string" and key:lower() == l then return key end
    end
  end
  return nil
end

-- A name the player typed: an exact full name (what the panel shows), else a single word: "which one?" when two
-- current members start with it, else an exact key, else the first word of exactly one member. Returns the key, or
-- nil (and "ambiguous" for a shared first word); nil while the list is not loaded.
function Guild.resolveTyped(raw)
  if not loaded then return nil end
  local l = lowerFull(raw)
  if not l then return nil end
  if byFull[l] then return byFull[l].key end
  local same = not l:find(" ", 1, true) and byFirst[l] or nil
  if same and #same > 1 then return nil, "ambiguous" end
  if byKey[l] then return byKey[l].key end
  if same and #same == 1 then return same[1].key end
  return nil
end

function Guild.isMember(raw) return lookup(raw) ~= nil end

-- What someone who is not a member is called: their cleaned name, but never a member's key (nil then), so a
-- stranger "Chaos" never lands on member Chaos's row.
local function outsider(name)
  if not name or byKey[name:lower()] then return nil end
  return name
end

-- The member key for a name the game gives (a unit's name: one word or the full name, maybe with a realm); for
-- someone the loaded list does not have, their cleaned name (never a member's key); before the list loads, the first
-- word, as before the guild.
function Guild.keyOfName(raw)
  local key = Guild.keyOf(raw)
  if key then return key end
  if loaded then return outsider(clean(raw)) end
  return type(raw) == "string" and not ns.Util.isSecret(raw) and ns.shortName(raw) or nil
end

-- The member key of the player behind a unit token ("party2", "target", "nameplate4"): by GUID first, then by name
-- (keyOfName rules). nil when the game will not say.
function Guild.keyOfUnit(unit)
  local guid = plain(UnitGUID, unit)
  if loaded and type(guid) == "string" then
    local e = byGuid[guid]
    if e then return e.key end
    if guidsComplete then return outsider(clean(plain(UnitName, unit))) end -- not a member, whatever the name
  end
  local raw = plain(UnitName, unit)
  local key = Guild.keyOf(raw)
  local e = key and Guild.get(key)
  if e and e.guid and type(guid) == "string" and e.guid ~= guid then -- the name fits a member, the GUID is not theirs
    return outsider(clean(raw))
  end
  return Guild.keyOfName(raw)
end

function Guild.fullName(key)
  local e = Guild.get(key)
  return e and e.full or nil
end

function Guild.display(key)
  local e = Guild.get(key)
  if not e then return key end
  local same = byFirst[e.first:lower()]
  if same and #same > 1 then return e.full end
  return e.first
end

-- My own entry in the list: by GUID, else by the name the game gives me.
local function myEntry()
  if not loaded then return nil end
  local guid = plain(UnitGUID, "player")
  if type(guid) == "string" and byGuid[guid] then return byGuid[guid] end
  local mine = clean(plain(UnitName, "player"))
  return mine and byFull[mine:lower()] or nil
end

-- My key: from the list, else the one saved for this character (any guild list read before), else nil.
function Guild.myKey()
  local e = myEntry()
  if e then return e.key end
  local guid = plain(UnitGUID, "player")
  local key = type(guid) == "string" and saved().mine[guid]
  return type(key) == "string" and key ~= "" and key or nil
end

-- My full name: the listed member whose GUID is mine, else UnitName when it has several words, else unknown (nil).
-- (On Forever UnitName may give only the first word, so a one-word UnitName alone proves nothing.)
local function myFull()
  if loaded then
    local guid = plain(UnitGUID, "player")
    local e = type(guid) == "string" and byGuid[guid]
    if e then return e.full end
  end
  local name = clean(plain(UnitName, "player"))
  if name and name:find(" ", 1, true) then return name end
  return nil
end

function Guild.isMe(raw)
  local name = clean(raw)
  if not name then return false end
  local l = name:lower()
  local suffix = realmSuffix()
  if suffix and #l > #suffix and l:sub(-#suffix) == suffix then l = l:sub(1, #l - #suffix) end
  local full = myFull()
  full = full and full:lower()
  if l == full then return true end
  local uname = clean(plain(UnitName, "player"))
  local mine = full or (uname and uname:lower())
  if not mine then return false end
  if l:find(" ", 1, true) then
    if full then return false end
    return firstWord(l) == firstWord(mine)
  end
  local other = byFull[l]
  if other and other.full:lower() ~= mine then return false end -- a listed member who is not me has this exact name
  return l == firstWord(mine)
end

function Guild.start()
  if started then return end
  started = true
  ns.Events.on(FEATURE, "GUILD_ROSTER_UPDATE", readSoon)
  ns.Events.on(FEATURE, "PLAYER_GUILD_UPDATE", function()
    checkState()
    Guild.refresh()
  end)
  checkState()
  if not activeAnnounced then read() end -- (updateActive already read when it became active)
  Guild.refresh()
  ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, tick) end)
end

local function stop()
  started = false
  if ticker then ticker:Cancel(); ticker = nil end
end

ns.Modules.register({
  id = "guild", name = "Guild list", tier = "essential",
  info = "Reads your guild's member list: who is in the guild, their class, level and zone. TwizCrew only trusts guild members.",
  defaults = {},
  onEnable = function() Guild.start() end,
  onDisable = stop,
})
