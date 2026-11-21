-- The guild list: who is in the guild, what is their key, what is their full name. The one answer for the rest of the
-- addon (ns.Guild). Reads only what the game's guild functions give, every value through ns.Util.plain.
--
-- Key of a member: the first word of the name, unless another member already holds that word (saved keys count, and
-- so does the current list); then the full name. Keys are saved in ns.db.guild.keys[lower(full)] the first time a
-- member is seen (only on a complete read) and never change; they belong to one guild (ns.db.guild.keysFor) and are
-- cleared when keys are about to be given out in another one.
--
-- Home guild: one TwizCrew guild per account (ns.db.guild.home), set the first time a GUILD message from another
-- member is heard while it is unset (Comm calls Guild.setHome), or by /tc home here. On a character in another guild
-- the addon acts as if it were in no guild: active() is false, no list is read, nothing is keyed, sent or accepted.
-- GUILD_STATE(active) fires when active() changes; inGuild() stays the game's answer.
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
local nameWaitSince          -- ns.now() since when we are in a guild, home is set and the guild name is not known
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

local function install(entries)
  members, byFull, byKey, byFirst, byGuid = entries, {}, {}, {}, {}
  for _, e in ipairs(entries) do
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

-- Saved keys (and my saved keys per GUID) belong to the guild they were given out in: in another guild they go.
-- Returns true when they were cleared.
local function keysForGuild(name)
  if not name then return false end
  local g = saved()
  if g.keysFor == nil then g.keysFor = name; return false end -- keys from before this was saved: adopted
  if g.keysFor == name then return false end
  ns.Log.add("info", "guild keys cleared: they were for another guild")
  for k in pairs(g.keys) do g.keys[k] = nil end
  for k in pairs(g.mine) do g.mine[k] = nil end
  g.keysFor = name
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

-- Reads the game's list (only in my TwizCrew guild). A list that cannot be read (secret values, nothing yet) changes
-- nothing. A partial read (fewer readable rows than the game counts) updates the members it did read, keeps the
-- others as they were and gives out no new keys; complete() tells which one the last read was.
local function read()
  lastRead = ns.now()
  if not Guild.active() then return end
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
  local cleared = keysForGuild(guildName())
  table.sort(entries, byFullName) -- keys are given out A-Z
  assignKeys(entries, isComplete)
  local kept = {}
  for _, e in ipairs(entries) do if e.key then kept[#kept + 1] = e end end
  if not isComplete and not cleared then -- members this read could not see stay as they were
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

-- GUILD_STATE follows active(): true once in my TwizCrew guild, false otherwise. While in a guild with a home set and
-- the guild name not known yet, nothing is said for up to GUILD_ABSENT_GRACE seconds (the game may name it late).
local function updateActive()
  if announced == nil then return end
  local now = Guild.active()
  if announced and not now and Guild.home() and not guildName() then
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
    if announced then ns.Log.add("info", "this guild is not your TwizCrew guild: TwizCrew stays quiet here") end
    dropList()
    ns.Bus.fire("GUILD_STATE", false)
  end
end

-- Membership: true at once, false only after the grace time of the game saying so.
local function checkState()
  local now = plain(IsInGuild)
  if now == nil then return end
  seenIn = now == true
  if seenIn then
    absentSince = nil
    announced = true
  else
    absentSince = absentSince or ns.now()
    if announced ~= false and ns.now() - absentSince >= ns.Config.GUILD_ABSENT_GRACE then announced = false end
  end
  updateActive()
end

-- The game's answer: is this character in a guild (any guild)?
function Guild.inGuild() return announced == true end
function Guild.loaded() return loaded end
function Guild.complete() return loaded and complete end

-- The current guild's name (nil when not in a guild or not known yet), my TwizCrew guild's name (nil while unset).
Guild.name = guildName
function Guild.home()
  local h = ns.db and type(ns.db.guild) == "table" and ns.db.guild.home
  return type(h) == "string" and h ~= "" and h or nil
end

-- True while no home is set, or the current guild is it; false while the guild name is not known and home is set.
function Guild.isHome()
  local home = Guild.home()
  if not home then return true end
  return guildName() == home
end

-- In a guild, and it is my TwizCrew guild: the only state in which the addon reads the list, keys, sends or accepts.
function Guild.active() return Guild.inGuild() and Guild.isHome() end

-- Makes the current guild my TwizCrew guild. Returns its name, or nil when not in a guild or its name is not known.
function Guild.setHome()
  local name = plain(IsInGuild) == true and guildName() or nil
  if not name or not ns.db then return nil end
  if type(ns.db.guild) ~= "table" then ns.db.guild = {} end
  if ns.db.guild.home ~= name then
    ns.db.guild.home = name
    ns.Log.add("info", "TwizCrew guild set to %s", ns.Util.safeText(name))
  end
  if started then updateActive() end
  return name
end

-- Asks the game for a fresh list, at most once per GUILD_REFRESH_MIN seconds. Returns true when it asked.
function Guild.refresh()
  if plain(IsInGuild) ~= true then return false end
  if Guild.inGuild() and not Guild.isHome() then return false end -- not my TwizCrew guild
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
