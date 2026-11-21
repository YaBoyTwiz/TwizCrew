-- The guild list: who is in the guild, what is their key, what is their full name. The one answer for the rest of the
-- addon (ns.Guild). Reads only what the game's guild functions give, every value through ns.Util.plain.
--
-- Key of a member: the first word of the name, unless another member already holds that word (saved keys count, and
-- so does the current list); then the full name. Keys are saved in ns.db.guild.keys[lower(full)] the first time a
-- member is seen and never change.
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
local announced              -- nil until known, then true / false: what GUILD_STATE last said
local seenIn                 -- what the game last said about being in a guild (nil: nothing usable yet)
local absentSince            -- ns.now() when the game first said "no guild" (nil while it says yes)
local lastRefresh, lastRead
local watched = false
local pendingRead = false
local started = false
local ticker
local signature = ""
local fallbackKeys = {}      -- used while saved data is not attached (tests, very early)

local function savedKeys()
  local g = ns.db and ns.db.guild
  if type(g) == "table" and type(g.keys) == "table" then return g.keys end
  return fallbackKeys
end

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

-- Gives every entry its key (entries are sorted A-Z by full name).
local function assignKeys(entries)
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
      if not groups[lw] then groups[lw] = {}; order[#order + 1] = lw end
      groups[lw][#groups[lw] + 1] = e
    end
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
      e.key = (e == winner) and e.first or e.full
      saved[e.full:lower()] = e.key
    end
    if winner then holder[lw] = winner.full:lower() end
  end
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

-- Reads the game's list. A list that cannot be read (secret values, nothing yet) changes nothing.
local function read()
  lastRead = ns.now()
  local total = plain(GetNumGuildMembers)
  if type(total) ~= "number" or total <= 0 then return end
  if total > MAX_MEMBERS then total = MAX_MEMBERS end
  local entries, seen = {}, {}
  for i = 1, total do
    local e = readRow(i)
    if e and not seen[e.full:lower()] then
      seen[e.full:lower()] = true
      entries[#entries + 1] = e
    end
  end
  if #entries == 0 then return end
  table.sort(entries, function(a, b)
    local x, y = a.full:lower(), b.full:lower()
    if x ~= y then return x < y end
    return a.full < b.full
  end)
  assignKeys(entries)
  local sig = sigOf(entries)
  local first = not loaded
  local changed = sig ~= signature
  install(entries)
  loaded = true
  signature = sig
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

-- Membership: true at once, false only after the grace time of the game saying so.
local function checkState()
  local now = plain(IsInGuild)
  if now == nil then return end
  seenIn = now == true
  if seenIn then
    absentSince = nil
    if announced ~= true then
      announced = true
      ns.Bus.fire("GUILD_STATE", true)
    end
    return
  end
  absentSince = absentSince or ns.now()
  if announced ~= false and ns.now() - absentSince >= ns.Config.GUILD_ABSENT_GRACE then
    announced = false
    local had = loaded or #members > 0
    loaded, signature = false, ""
    install({})
    if had then ns.Bus.fire("GUILD_LIST") end
    ns.Bus.fire("GUILD_STATE", false)
  end
end

function Guild.inGuild() return announced == true end
function Guild.loaded() return loaded end

-- Asks the game for a fresh list, at most once per GUILD_REFRESH_MIN seconds. Returns true when it asked.
function Guild.refresh()
  if plain(IsInGuild) ~= true then return false end
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
  local e = byFull[l]
  if e then return e end
  local suffix = realmSuffix()
  if suffix and #l > #suffix and l:sub(-#suffix) == suffix then
    l = l:sub(1, #l - #suffix)
    e = byFull[l]
    if e then return e end
  end
  if not l:find(" ", 1, true) then
    e = byKey[l]
    if e then return e end
    local same = byFirst[l]
    if same and #same == 1 then return same[1] end
  end
  return nil
end

function Guild.keyOf(raw)
  local e = lookup(raw)
  return e and e.key or nil
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

function Guild.myKey()
  local e = myEntry()
  return e and e.key or nil
end

function Guild.isMe(raw)
  local name = clean(raw)
  if not name then return false end
  local e = myEntry()
  local mine = e and e.full or clean(plain(UnitName, "player"))
  if not mine then return false end
  local l, m = name:lower(), mine:lower()
  local suffix = realmSuffix()
  if suffix and #l > #suffix and l:sub(-#suffix) == suffix then l = l:sub(1, #l - #suffix) end
  if e and l:find(" ", 1, true) then return l == m end
  return firstWord(l) == firstWord(m)
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
  read()
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
