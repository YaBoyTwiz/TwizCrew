-- The guild list: who is in the guild, what is their key, what is their full name. The one answer for the rest of the
-- addon (ns.Guild). Reads only what the game's guild functions give, every value through ns.Util.plain.
--
-- Key of a member: the first word of the name, unless another member already holds that word (saved keys count, and
-- so does the current list); then the full name. Keys are saved in ns.db.guild.keys[lower(full)] the first time a
-- member is seen (only on a complete read) and never change. Keys, like all data about other people, are kept per
-- guild (Core/DB.lua: the set on top belongs to ns.db.guild.name, the "data guild").
--
-- active(): in a guild and the data on top belongs to it. Only then is the list read, are keys given out, and does
-- the addon send, accept or hide anyone; otherwise it acts as if in no guild. GUILD_STATE(active) fires when active()
-- changes; inGuild() stays the game's answer. A character whose guild (known and stable) is not the data guild is
-- remembered in ns.db.guild.byChar and told once to /reload (the login swap then brings its guild's data).
-- Unnamed data (v0.1.24, or a fresh install) is adopted by the first guild whose complete list has someone from the
-- saved roster (first-word match), or at once when that roster is empty; a guild that matches nobody stays quiet and
-- gets its own fresh data at the next login (ns.db.guild.notLegacy).
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

local members, byFull, byKey, byFirst, byGuid = {}, {}, {}, {}, {}
local loaded = false
local complete = false       -- the last read gave as many readable rows as the game said there are
local announced              -- nil until known, then true / false: is the character in a guild (the game, after grace)
local activeAnnounced        -- nil until known, then what GUILD_STATE last said (in my TwizCrew guild)
local nameWaitSince          -- ns.now() since when we are in a guild that is not (yet) known to be the data guild
local lastName, stableName   -- the guild name the game gave at the last check; the same name two checks in a row
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

local function guildName()
  local name = plain(GetGuildInfo, "player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

local function dataGuild()
  local g = ns.db and ns.db.guild
  local name = type(g) == "table" and g.name
  return type(name) == "string" and name ~= "" and name or nil
end

-- Does the unnamed saved roster know someone in this list (first words, any case)? An empty roster fits any guild.
local function legacyFits(entries)
  local roster = ns.db and ns.db.roster
  local firsts, any = {}, false
  for name in pairs(type(roster) == "table" and roster or {}) do
    if type(name) == "string" and not ns.isTestName(name) then
      any = true
      firsts[(name:match("^(%S+)") or name):lower()] = true
    end
  end
  if not any then return true end
  for _, e in ipairs(entries or {}) do
    if firsts[e.first:lower()] then return true end
  end
  return false
end

-- The data on top becomes this guild's.
local function adopt(name)
  ns.db.guild.name = name
  ns.Log.add("info", "saved data adopted by the guild %s", ns.Util.safeText(name))
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

-- Reads the game's list (only while active, or to see whether unnamed data is this guild's). A list that cannot be
-- read (secret values, nothing yet) changes nothing. A partial read (fewer readable rows than the game counts)
-- updates the members it did read, keeps the others as they were and gives out no new keys; complete() tells which
-- one the last read was.
local function read()
  lastRead = ns.now()
  local adopting = Guild.inGuild() and ns.db ~= nil and dataGuild() == nil and guildName() ~= nil
    and not (ns.db.guild.notLegacy or {})[guildName()]
  if not Guild.active() and not adopting then return end
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
  if #entries == 0 then return end
  local isComplete = readable == count
  if adopting then
    if not isComplete then return end -- whose data it is waits for a complete list
    local name = guildName()
    if not legacyFits(entries) then
      ns.db.guild.notLegacy = ns.db.guild.notLegacy or {}
      ns.db.guild.notLegacy[name] = true
      ns.Log.add("info", "saved data is not %s's: TwizCrew stays quiet here until the next login",
        ns.Util.safeText(name))
      return
    end
    adopt(name)
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
  if adopting then updateActive() end
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

-- Drops the list (left the guild, or this is not my TwizCrew guild).
local function dropList()
  local had = loaded or #members > 0
  loaded, complete, signature = false, false, ""
  install({})
  if had then ns.Bus.fire("GUILD_LIST") end
end

-- The data on top is another guild's (both names known): remember this character's guild for the next login and
-- say once how to switch.
local function otherGuild(name)
  return name ~= nil and dataGuild() ~= nil and dataGuild() ~= name
end

-- GUILD_STATE follows active(). While in a guild that is not known to be the data guild yet (no stable name, or
-- unnamed data waiting for a complete list), nothing is said for up to GUILD_ABSENT_GRACE seconds.
updateActive = function()
  if announced == nil then return end
  local now = Guild.active()
  if announced and not now and not otherGuild(stableName) then
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

-- Membership: true at once, false only after the grace time of the game saying so. The guild's name counts once
-- the game gave the same one twice in a row.
local function checkState()
  local now = plain(IsInGuild)
  if now == nil then return end
  seenIn = now == true
  local g = ns.db and type(ns.db.guild) == "table" and ns.db.guild or nil
  local id = g and ns.DB.charId()
  if seenIn then
    absentSince = nil
    announced = true
    local name = guildName()
    if name and name == lastName then stableName = name end
    lastName = name
    if name and g and dataGuild() == nil and legacyFits(nil) then adopt(name) end -- an empty roster fits any guild
    if stableName and g then
      if id and type(g.byChar) == "table" then g.byChar[id] = stableName end
      if otherGuild(stableName) and not toldReload then
        toldReload = true
        print("TwizCrew keeps separate data for each guild. Type /reload to switch to "
          .. ns.Util.safeText(stableName) .. ".")
        ns.Log.add("info", "this character's guild %s uses other saved data than %s", ns.Util.safeText(stableName),
          ns.Util.safeText(dataGuild()))
      end
    end
  else
    absentSince = absentSince or ns.now()
    lastName, stableName = nil, nil
    if announced ~= false and ns.now() - absentSince >= ns.Config.GUILD_ABSENT_GRACE then
      announced = false
      if g and id and type(g.byChar) == "table" then g.byChar[id] = nil end
    end
  end
  updateActive()
end

-- The game's answer: is this character in a guild (any guild)?
function Guild.inGuild() return announced == true end
function Guild.loaded() return loaded end
function Guild.complete() return loaded and complete end

-- The current guild's name (nil when not in a guild or not known yet); the guild the saved data on top belongs to
-- (nil: unnamed data not adopted yet).
Guild.name = guildName
Guild.dataGuild = dataGuild

-- True when the character is in a guild whose name is known and the data on top is that guild's: the only state in
-- which the addon reads the list, gives out keys, sends, accepts or hides anyone.
function Guild.active()
  if not Guild.inGuild() then return false end
  local name = guildName()
  return name ~= nil and name == dataGuild()
end

-- In a guild whose (stable) name is not the data guild's: TwizCrew stays quiet until a /reload.
function Guild.needsReload() return Guild.inGuild() and otherGuild(stableName) end

-- In a guild, but the data on top is not (known to be) its own: TwizCrew waits (or stays quiet until a /reload).
function Guild.quiet() return Guild.inGuild() and not Guild.active() end

-- May this character write to the per-guild saved data (my session, my calendar marks)? Only while active: a
-- character in no guild or in another guild leaves the data on top as it is.
function Guild.writable() return Guild.active() end

-- Asks the game for a fresh list, at most once per GUILD_REFRESH_MIN seconds. Returns true when it asked.
function Guild.refresh()
  if plain(IsInGuild) ~= true then return false end
  if otherGuild(guildName()) then return false end -- another guild's data is in use
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

-- The key of the member a name taken from a message field (a mock's target, a vote) or typed by the player stands
-- for: an exact key (what new copies send), else an exact full name, else (one word) the first word of exactly one
-- current member. Unlike keyOf (names the game gives: a sender, a unit), a key comes first, and a first word is not
-- kept for a member who has left: typed, or sent by an old copy, it means the one member who has that word now.
-- typed: an exact full name first, and a single word that two members start with is "which one?" even when it is
-- one of their keys (the panel shows both full names). Returns nil (and "ambiguous" when two members share the word) for anyone else, an
-- unreadable name, or while the list is not loaded.
function Guild.resolve(raw, typed)
  if not loaded then return nil end
  local l = lowerFull(raw)
  if not l then return nil end
  local oneWord = not l:find(" ", 1, true)
  local same = oneWord and byFirst[l] or nil
  if typed then
    if byFull[l] then return byFull[l].key end -- exactly a name the panel shows
    if same and #same > 1 then return nil, "ambiguous" end
  end
  local e = byKey[l] or byFull[l]
  if e then return e.key end
  if same and #same == 1 then return same[1].key end
  if same then return nil, "ambiguous" end
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
