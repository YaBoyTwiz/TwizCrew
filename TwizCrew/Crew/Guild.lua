-- The guild list: who is in the guild, what is their key, what is their full name. The one answer for the rest of the
-- addon (ns.Guild). Reads only what the game's guild functions give, every value through ns.Util.plain.
--
-- Key of a member: the first word of the name, unless another member already holds that word (saved keys count, and
-- so does the current list); then the full name. Keys are saved in ns.db.guild.keys[lower(full)] the first time a
-- member is seen (only on a complete read) and never change. Keys, like all data about other people, are kept per
-- guild (Core/DB.lua: the set on top belongs to ns.db.guild.name, the "data guild").
--
-- active(): in a guild and the data on top belongs to it. Only then is the list read (but see readMode), are keys
-- given out, and does the addon send, accept, hide or write anything for the crew; otherwise it acts as if in no
-- guild. GUILD_STATE(active) fires when active() changes; inGuild() stays the game's answer. The guild's identity
-- (guildId: name, plus realm when the game gives one) is sticky for the session. A character whose guild is not the
-- data guild is remembered in ns.db.guild.byChar and told once to /reload (the login swap brings its guild's data).
-- Unnamed data (v0.1.24, or a fresh install) is adopted by the first guild whose complete list fits it (rosterFits,
-- keysFit); a guild it does not fit stays quiet and gets its own fresh data at the next login (ns.db.guild.notLegacy).
-- When the game never names the guild, the list decides after GUILD_NAME_WAIT s (probe; unnamed data becomes "?").
--
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

local members, byFull, byKey, byFirst, byGuid = {}, {}, {}, {}, {}
local loaded = false
local complete = false       -- the last read gave as many readable rows as the game said there are
local announced              -- nil until known, then true / false: is the character in a guild (the game, after grace)
local activeAnnounced        -- nil until known, then what GUILD_STATE last said (in my TwizCrew guild)
local nameWaitSince          -- ns.now() since when we are in a guild that is not (yet) known to be the data guild
local curId                  -- this session's guild identity (guildId), sticky: an unreadable answer keeps it
local otherId, otherSince    -- a different readable identity the game gave, and since when (it counts after grace)
local inSince                -- ns.now() since the game says "in a guild"
local nameless               -- the game names no guild: nil undecided, true the data on top is this guild's, false not
local stableReadable, stableN, stableAt = nil, 0, nil -- the same readable row count on reads >= STABLE_GAP s apart
local counted, readableRows  -- the last read: rows the game counted, rows it gave readably (for /tc guildtest)
local toldReload             -- the /reload line was printed this session
local seenIn                 -- what the game last said about being in a guild (nil: nothing usable yet)
local absentSince            -- ns.now() when the game first said "no guild" (nil while it says yes)
local lastRefresh, lastRead
local watched = false
local pendingRead = false
local started = false
local ticker
local signature = ""
local heldBy = {}            -- lower(key) -> lower(full name) of whoever was ever given that key (saved keys)
local fallback = { keys = {}, mine = {} } -- used while saved data is not attached (tests, very early)

local function saved()
  local db = ns.db
  if type(db) ~= "table" then return fallback end
  if type(db.guild) ~= "table" then db.guild = {} end
  local g = db.guild
  if type(g.keys) ~= "table" then g.keys = {} end
  if type(g.mine) ~= "table" then g.mine = {} end
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

-- The name the game gives for this character's guild (nil when it gives none, or a secret).
local function guildName()
  local name = plain(GetGuildInfo, "player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The guild's identity, the one string that names a guild's saved data: its name, plus "-" and its realm when the
-- game gives a realm (a guild of another realm). nil when the game gives no readable name.
local function guildId()
  local name, _, _, realm = plain(GetGuildInfo, "player")
  if type(name) ~= "string" or name == "" then return nil end
  if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
  return name
end

local PLACEHOLDER = "?" -- the data guild's name while the game never names the guild (see the name-less fallback)

local function dataGuild()
  local g = ns.db and ns.db.guild
  local name = type(g) == "table" and g.name
  return type(name) == "string" and name ~= "" and name or nil
end

local function nonEmpty(t) return type(t) == "table" and next(t) ~= nil end

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
-- one row only when its class is known and equal. An empty roster fits only when nothing else about a crew is saved
-- on top (crew numbers, trophies, notes, feed).
local function rosterFits(entries)
  local rows = savedRows()
  if #rows == 0 then
    local db = ns.db
    local stats = type(db.stats) == "table" and db.stats or {}
    local cal = type(db.calendar) == "table" and db.calendar or {}
    return not (nonEmpty(stats.crew) or nonEmpty(stats.trophies) or nonEmpty(cal.notes) or nonEmpty(db.feed))
  end
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
  if #rows == 1 then return sure == 1 end
  return matches >= 2 and matches * 2 >= #rows
end

-- Are at least half (and at least 2) of the full names in the saved keys in this list?
local function keysFit(entries)
  local listed, total, found = {}, 0, 0
  for _, e in ipairs(entries or {}) do listed[e.full:lower()] = true end
  for lf in pairs(savedKeys()) do
    if type(lf) == "string" then
      total = total + 1
      if listed[lf] then found = found + 1 end
    end
  end
  return found >= 2 and found * 2 >= total
end

-- May unnamed data on top become guild `id`'s? Never when that guild turned it down, or already has parked data.
local function mayAdopt(id)
  local g = ns.db and ns.db.guild
  if type(g) ~= "table" or dataGuild() ~= nil then return false end
  if type(g.notLegacy) == "table" and g.notLegacy[id] then return false end
  if type(ns.db.guilds) == "table" and ns.db.guilds[id] ~= nil then return false end
  return true
end

-- The data on top becomes guild `id`'s when it fits (rosterFits or keysFit). final: a complete list that does not
-- fit turns it down for good (a real id only). Returns true when adopted.
local function tryAdopt(id, entries, final)
  if not mayAdopt(id) then return false end
  if rosterFits(entries) or keysFit(entries) then
    ns.db.guild.name = id
    ns.Log.add("info", "saved data adopted by the guild %s", ns.Util.safeText(id))
    return true
  end
  if final and id ~= PLACEHOLDER then
    ns.db.guild.notLegacy = type(ns.db.guild.notLegacy) == "table" and ns.db.guild.notLegacy or {}
    ns.db.guild.notLegacy[id] = true
    ns.Log.add("info", "saved data is not %s's: TwizCrew stays quiet here until the next login", ns.Util.safeText(id))
  end
  return false
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

-- Why the list may be read now: "active" (the data on top is this guild's), "adopt" (unnamed data, the guild named:
-- does it fit?), "probe" (the game names no guild after GUILD_NAME_WAIT s: is the data on top this guild's?), or nil.
local function readMode()
  if Guild.active() then return "active" end
  if not Guild.inGuild() or not ns.db then return nil end
  if curId then return mayAdopt(curId) and "adopt" or nil end
  if nameless == nil and inSince and ns.now() - inSince >= ns.Config.GUILD_NAME_WAIT then return "probe" end
  return nil
end

-- The game names no guild: the data on top is this guild's when this character's last guild was it, or when the
-- list has at least half of the saved keys' full names; unnamed data is adopted under "?" when it fits. Decided
-- only on a complete list unless it already fits (never writes byChar).
local function probe(entries, isComplete)
  local dg = dataGuild()
  local g = ns.db.guild
  local id = ns.DB.charId()
  if dg then
    if (id and type(g.byChar) == "table" and g.byChar[id] == dg) or keysFit(entries) then nameless = true
    elseif isComplete then nameless = false end
  elseif isComplete then
    nameless = tryAdopt(PLACEHOLDER, entries, false)
  end
  if nameless ~= nil then
    ns.Log.add("info", "the game names no guild: the saved data on top is %s",
      nameless and "taken as this guild's" or "not this guild's (TwizCrew stays quiet)")
  end
end

-- Reads the game's list (see readMode). A list that cannot be read (secret values, nothing yet) changes nothing.
-- A partial read (fewer readable rows than the game counts, unless the readable count stayed the same on
-- STABLE_READS reads STABLE_GAP s apart) updates the members it did read, keeps the others as they were and gives
-- out no new keys; complete() tells which one the last read was.
local function read()
  lastRead = ns.now()
  local mode = readMode()
  if not mode then return end
  local count = plain(GetNumGuildMembers)
  if type(count) ~= "number" or count <= 0 then return end
  local total = math.min(count, MAX_MEMBERS)
  local entries, seen, readable = {}, {}, 0
  for i = 1, total do
    local e = readRow(i)
    if e then
      readable = readable + 1
      if not seen[e.full:lower()] then
        seen[e.full:lower()] = true
        entries[#entries + 1] = e
      end
    end
  end
  counted, readableRows = count, readable
  if #entries == 0 then return end
  local now = ns.now()
  if readable ~= stableReadable then
    stableReadable, stableN, stableAt = readable, 1, now
  elseif now - stableAt >= STABLE_GAP then
    stableN, stableAt = stableN + 1, now
  end
  local isComplete = readable == count or stableN >= STABLE_READS
  if mode == "adopt" then
    if not isComplete then return end -- whose data it is waits for a complete list
    if not tryAdopt(curId, entries, true) then return end
  elseif mode == "probe" then
    probe(entries, isComplete)
    if not Guild.active() then
      if nameless ~= nil then updateActive() end
      return
    end
  end
  table.sort(entries, byFullName) -- keys are given out A-Z
  assignKeys(entries, isComplete)
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
  install({})
  if had then ns.Bus.fire("GUILD_LIST") end
end

-- This session's guild is known and the data on top is another guild's.
local function otherGuild(id)
  return id ~= nil and dataGuild() ~= nil and dataGuild() ~= id
end

-- GUILD_STATE follows active(). While in a guild that is not known to be the data guild yet (no name, unnamed data
-- waiting for a complete list, the name-less fallback still deciding), nothing is said for up to GUILD_ABSENT_GRACE
-- seconds.
updateActive = function()
  if announced == nil then return end
  local now = Guild.active()
  if announced and not now and not otherGuild(curId) and nameless == nil then
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

-- The game named the guild (id is this session's identity now): unnamed or "?" data, byChar, the /reload line.
local function onIdentity(id)
  local g = ns.db and type(ns.db.guild) == "table" and ns.db.guild or nil
  if not g then return end
  if dataGuild() == PLACEHOLDER then -- data taken as this guild's while the game named none: now it has a name
    if type(ns.db.guilds) == "table" and ns.db.guilds[id] ~= nil then
      ns.Log.add("warn", "saved data of %s exists already: the data taken without a name stays \"?\"",
        ns.Util.safeText(id))
    else
      g.name = id
      ns.Log.add("info", "saved data taken without a guild name is %s's", ns.Util.safeText(id))
    end
  end
  if dataGuild() == nil and #savedRows() == 0 then tryAdopt(id, {}, false) end -- an empty roster: maybe at once
  local char = ns.DB.charId()
  if char and type(g.byChar) == "table" then g.byChar[char] = id end
  if otherGuild(id) and not toldReload then
    toldReload = true
    print("TwizCrew keeps separate data for each guild. Type /reload to switch to " .. ns.Util.safeText(id) .. ".")
    ns.Log.add("info", "this character's guild %s uses other saved data than %s", ns.Util.safeText(id),
      ns.Util.safeText(dataGuild()))
  end
end

-- Membership: true at once, false only after the grace time of the game saying so. The guild's identity is sticky
-- for the session: the first readable one counts, an unreadable answer keeps it, and only a different readable one
-- that stays for GUILD_ABSENT_GRACE seconds replaces it.
local function checkState()
  local now = plain(IsInGuild)
  if now == nil then return end
  seenIn = now == true
  local t = ns.now()
  if seenIn then
    absentSince = nil
    announced = true
    inSince = inSince or t
    local id = guildId()
    if id and id ~= curId then
      if not curId then
        curId, otherId = id, nil
      elseif otherId ~= id then
        otherId, otherSince = id, t
      elseif t - otherSince >= ns.Config.GUILD_ABSENT_GRACE then
        curId, otherId, toldReload = id, nil, false
      end
    elseif id then
      otherId = nil
    end
    if curId then onIdentity(curId) end
  else
    absentSince = absentSince or t
    otherId = nil
    if announced ~= false and t - absentSince >= ns.Config.GUILD_ABSENT_GRACE then
      announced, curId, inSince, nameless = false, nil, nil, nil
      local g = ns.db and type(ns.db.guild) == "table" and ns.db.guild or nil
      local char = g and ns.DB.charId()
      if char and type(g.byChar) == "table" then g.byChar[char] = nil end
    end
  end
  if readMode() == "probe" then read() end
  updateActive()
end

-- The game's answer: is this character in a guild (any guild)?
function Guild.inGuild() return announced == true end
function Guild.known() return announced ~= nil end
function Guild.loaded() return loaded end
function Guild.complete() return loaded and complete end

-- The guild's name as the game gives it now (nil: none, or a secret); this session's guild identity (name, plus the
-- realm for a guild of another realm; sticky); the guild the saved data on top belongs to (nil: unnamed, not
-- adopted yet; "?": taken as this guild's while the game named none).
Guild.name = guildName
function Guild.id() return curId end
Guild.dataGuild = dataGuild

-- The last read: rows the game counted and rows it gave readably (nil before any read).
function Guild.readStats() return counted, readableRows end

-- In a guild and the data on top is this guild's (by its sticky identity, or by the name-less fallback): the only
-- state in which the addon reads the list, gives out keys, sends, accepts, hides or writes anything for the crew.
function Guild.active()
  if not Guild.inGuild() then return false end
  local dg = dataGuild()
  if not dg then return false end
  if curId then return curId == dg end
  return nameless == true
end

-- In a guild whose identity is known and not the data guild's: TwizCrew stays quiet until a /reload.
function Guild.needsReload() return Guild.inGuild() and otherGuild(curId) end

-- In a guild, but the data on top is not (known to be) its own: TwizCrew waits (or stays quiet until a /reload).
function Guild.quiet() return Guild.inGuild() and not Guild.active() end

-- May this character write to the per-guild saved data (my session, my calendar marks)? Only while active: a
-- character in no guild or in another guild leaves the data on top as it is.
function Guild.writable() return Guild.active() end

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

-- How a member is named in a message field (a mock's target, a quest share ask, a vote, a winner, a trophy record):
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
  return Guild.keyOfName(plain(UnitName, unit))
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
