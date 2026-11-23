-- The guild list's rows and names (part of ns.Guild, see Crew/Guild.lua): reading the rows, giving out keys, the
-- loaded list, and every way a name is turned into a member key (and back).
--
-- Key of a member: the first word of the name, unless another member already holds that word (saved keys count, and
-- so does the current list); then the full name. Keys are saved in ns.db.guild.keys[lower(full)] the first time a
-- member is seen (only on a complete read) and never change. Keys, like all data about other people, are kept per
-- guild (Core/DB.lua: the set on top belongs to ns.db.guild.name, the "data guild").
-- My own key is saved per character GUID (ns.db.guild.mine) so myKey() can answer before the list loads.
--
-- ns.Guild is made here (the first of the Guild*.lua files in the .toc). Guild._ is private to those files: the
-- helpers they share, and Guild._.list, the one loaded list (only Crew/Guild.lua's read and dropList change it).
local _, ns = ...

local Guild = {}
ns.Guild = Guild
local P = {}
Guild._ = P

local plain = ns.Util.plain
local MAX_MEMBERS = 2000 -- never read more rows than this

local L = {
  members = {}, byFull = {}, byKey = {}, byFirst = {}, byGuid = {},
  loaded = false,
  heldBy = {},             -- lower(key) -> lower(full name) of whoever was ever given that key (saved keys)
  guidsComplete = false,   -- every listed member has a GUID (then a unit whose GUID is not listed is no member)
}
P.list = L
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

-- A lower-case name without our realm in the " Realm" space form ("chaos deathbringr realm" -> "chaos deathbringr"),
-- but only when what is left is a full name known(rest) accepts; otherwise the name as it is. So a stranger called
-- "Chaos Realm" stays "chaos realm" and never becomes member Chaos Deathbringr's first word.
local function withoutRealm(l, known)
  if known(l) then return l end
  local suffix = realmSuffix()
  if suffix and #l > #suffix and l:sub(-#suffix) == suffix then
    local rest = l:sub(1, #l - #suffix)
    if known(rest) then return rest end
  end
  return l
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
  L.heldBy = holder
end

local function sigOf(entries)
  local parts = {}
  for i, e in ipairs(entries) do
    parts[i] = table.concat({ e.key, e.full, e.class or "", e.level or "", e.zone, e.rank, e.rankIndex or "",
      e.online and "1" or "0", e.lastOnlineRaw or "", e.guid or "" }, "\1")
  end
  return table.concat(parts, "\2")
end

local function install(entries)
  L.members, L.byFull, L.byKey, L.byFirst, L.byGuid = entries, {}, {}, {}, {}
  L.guidsComplete = #entries > 0
  for _, e in ipairs(entries) do
    if not e.guid then L.guidsComplete = false end
    L.byFull[e.full:lower()] = e
    L.byKey[e.key:lower()] = e
    local lw = e.first:lower()
    L.byFirst[lw] = L.byFirst[lw] or {}
    L.byFirst[lw][#L.byFirst[lw] + 1] = e
    if e.guid then L.byGuid[e.guid] = e end
  end
end

local function byFullName(a, b)
  local x, y = a.full:lower(), b.full:lower()
  if x ~= y then return x < y end
  return a.full < b.full
end

-- My GUID and my (cleaned) name as the game gave them at the first good read, kept for the session: inside a dungeon
-- UnitGUID / UnitName("player") may turn unreadable, and my own guild echo must still be mine (never a roster row).
local myGuidSeen, myNameSeen
local function myGuid()
  local guid = plain(UnitGUID, "player")
  if type(guid) == "string" and guid ~= "" then myGuidSeen = guid end
  return myGuidSeen
end
local function myName()
  local name = clean(plain(UnitName, "player"))
  if name then myNameSeen = name end
  return myNameSeen
end

-- Saves my key for this character (ns.db.guild.mine[GUID]) once the list has me.
local function rememberMyKey()
  local guid = myGuid()
  if type(guid) ~= "string" then return end
  local e = L.byGuid[guid]
  if not e then
    local mine = myName()
    e = mine and L.byFull[mine:lower()]
  end
  if e then saved().mine[guid] = e.key end
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

local function anyOffline(entries)
  for _, e in ipairs(entries) do if not e.online then return true end end
  return false
end

-- The entries are shared tables: callers must not change them.
function Guild.members()
  local out = {}
  for i, e in ipairs(L.members) do out[i] = e end
  return out
end

function Guild.get(key)
  if type(key) ~= "string" then return nil end
  local e = L.byKey[key:lower()]
  if e and e.key == key then return e end
  return nil
end

function Guild.count()
  local online = 0
  for _, e in ipairs(L.members) do if e.online then online = online + 1 end end
  return online, #L.members
end

local function listedFull(l) return L.byFull[l] ~= nil end

-- The member a raw game name belongs to, in any form: the first word, the full name, with or without "-Realm" (the
-- space form " Realm" only after a listed full name). nil for a stranger, an unreadable name, or while the list is
-- not loaded.
local function lookup(raw)
  if not L.loaded then return nil end
  local name = clean(raw)
  if not name then return nil end
  local l = withoutRealm(name:lower(), listedFull)
  -- order: an exact full name, then an exact key, then (one word only) the first-word fallback; unless the word
  -- was once given to someone else (then it is theirs, even while they are away)
  local e = L.byFull[l] or L.byKey[l]
  if e then return e end
  if not l:find(" ", 1, true) then
    local same = L.byFirst[l]
    if same and #same == 1 and (not L.heldBy[l] or L.heldBy[l] == same[1].full:lower()) then return same[1] end
  end
  return nil
end

-- "Chaos Deathbringr-Realm" -> "Chaos Deathbringr" (nil when there is no usable name). The one place names are cleaned.
Guild.cleanName = clean

-- A full name the list gives now, or one it gave before (the saved keys: also while the list is not loaded).
local function knownFull(l)
  if L.byFull[l] then return true end
  local key = savedKeys()[l]
  return type(key) == "string" and key ~= ""
end

-- lower(full name) of a raw name, with our realm taken off in the " Realm" form too (only after a known full name).
local function lowerFull(raw)
  local name = clean(raw)
  if not name then return nil end
  return withoutRealm(name:lower(), knownFull)
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
  local e = L.byKey[lk]
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
  local same = L.byFirst[e.first:lower()]
  if same and #same > 1 then return e.full end
  return e.first
end

-- My key for the member a name from a message field stands for: an exact full name among current members, else a
-- first word exactly one current member has (an old copy's first word too). Never a key. nil for anyone else, a
-- first word two members share, an unreadable name, or while the list is not loaded.
function Guild.fromWire(raw)
  if not L.loaded then return nil end
  local l = lowerFull(raw)
  if not l then return nil end
  local e = L.byFull[l]
  if e then return e.key end
  if not l:find(" ", 1, true) then
    local same = L.byFirst[l]
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
  local e = L.loaded and L.byFull[l]
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
  if not L.loaded then return nil end
  local l = lowerFull(raw)
  if not l then return nil end
  if L.byFull[l] then return L.byFull[l].key end
  local same = not l:find(" ", 1, true) and L.byFirst[l] or nil
  if same and #same > 1 then return nil, "ambiguous" end
  if L.byKey[l] then return L.byKey[l].key end
  if same and #same == 1 then return same[1].key end
  return nil
end

function Guild.isMember(raw) return lookup(raw) ~= nil end

-- What someone who is not a member is called: their cleaned name, but never a member's key (nil then), so a
-- stranger "Chaos" never lands on member Chaos's row.
local function outsider(name)
  if not name or L.byKey[name:lower()] then return nil end
  return name
end

-- The member key for a name the game gives (a unit's name: one word or the full name, maybe with a realm); for
-- someone the loaded list does not have, their cleaned name (never a member's key); before the list loads, the first
-- word, as before the guild.
function Guild.keyOfName(raw)
  local key = Guild.keyOf(raw)
  if key then return key end
  if L.loaded then return outsider(clean(raw)) end
  return type(raw) == "string" and not ns.Util.isSecret(raw) and ns.shortName(raw) or nil
end

-- The member key of the player behind a unit token ("party2", "target", "nameplate4"): by GUID first, then by name
-- (keyOfName rules). nil when the game will not say.
function Guild.keyOfUnit(unit)
  local guid = plain(UnitGUID, unit)
  if L.loaded and type(guid) == "string" then
    local e = L.byGuid[guid]
    if e then return e.key end
    if L.guidsComplete then return outsider(clean(plain(UnitName, unit))) end -- not a member, whatever the name
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
  local same = L.byFirst[e.first:lower()]
  if same and #same > 1 then return e.full end
  return e.first
end

-- My own entry in the list: by GUID, else by the name the game gives me.
local function myEntry()
  if not L.loaded then return nil end
  local guid = myGuid()
  if type(guid) == "string" and L.byGuid[guid] then return L.byGuid[guid] end
  local mine = myName()
  return mine and L.byFull[mine:lower()] or nil
end

-- My key: from the list, else the one saved for this character (any guild list read before), else nil.
function Guild.myKey()
  local e = myEntry()
  if e then return e.key end
  local guid = myGuid()
  local key = type(guid) == "string" and saved().mine[guid]
  return type(key) == "string" and key ~= "" and key or nil
end

-- My full name: the listed member whose GUID is mine, else UnitName when it has several words, else unknown (nil).
-- (On Forever UnitName may give only the first word, so a one-word UnitName alone proves nothing.)
local function myFull()
  if L.loaded then
    local guid = myGuid()
    local e = type(guid) == "string" and L.byGuid[guid]
    if e then return e.full end
  end
  local name = myName()
  if name and name:find(" ", 1, true) then return name end
  return nil
end

function Guild.isMe(raw)
  local name = clean(raw)
  if not name then return false end
  local full = myFull()
  full = full and full:lower()
  local l = withoutRealm(name:lower(), function(x) return x == full end) -- the space form only after my full name
  if l == full then return true end
  local uname = myName()
  local mine = full or (uname and uname:lower())
  if not mine then return false end
  if l:find(" ", 1, true) then
    if full then return false end
    return firstWord(l) == firstWord(mine)
  end
  local other = L.byFull[l]
  if other and other.full:lower() ~= mine then return false end -- a listed member who is not me has this exact name
  return l == firstWord(mine)
end

-- For Crew/Guild.lua and Crew/GuildCommands.lua.
P.saved, P.readList, P.anyOffline, P.byFullName = saved, readList, anyOffline, byFullName
P.assignKeys, P.saveSpelling, P.sigOf, P.install, P.rememberMyKey = assignKeys, saveSpelling, sigOf, install,
  rememberMyKey
