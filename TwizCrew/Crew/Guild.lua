-- The guild list: who is in the guild, what is their key, what is their full name. The one answer for the rest of the
-- addon (ns.Guild). Reads only what the game's guild functions give, every value through ns.Util.plain.
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
--   nothing is saved (unnamed data: or nothing saved is about anyone else, aboutNobody), else when a complete list
--   fits it (rosterFits). A whole list (whole: it surely holds the offline members) that does not fit: TwizCrew is
--   quiet this session, says once how to choose, reads the list again at most once a minute (and on a roster
--   update), and byChar is cleared so the next login moves nothing. A complete list that may lack the offline members
--   and does not fit: it keeps waiting quietly the same way, with no choice line. The player chooses: /tc guild use
--   (only when the list fits, or "use yes"), /tc guild new (a fresh set at the next login), /tc guild load <number> (a
--   set shown this session, at the next login). use, new and load wait while the guild is changing. Unnamed data
--   taken by a guild pins its old crew once (pinOldCrew; a load request of it: Core/DB.lua).
-- * Old friends are forgotten only on a whole list, while the saved friends fit it or the set fitted this guild
--   before (mayForget, guild.fitIn; Crew's forgetOld).
-- * The game never names the guild (no name after GUILD_NAME_WAIT, and this account never read a real guild name,
--   db.guild.named): unnamed data that fits becomes "?", and "?" data is used in any guild (one shared set). use and
--   load work and name the chosen set "?"; new needs yes (the set is shared by every character): with unnamed data
--   on top it makes a fresh "?" set, with "?" in use it starts that set fresh (the current one is parked). A readable
--   name later renames "?" data only when the list fits (like unnamed data).
-- * A gap in the names (none now, but this account has read one): nothing is adopted; only load works, and the
--   chosen set becomes the shared "?" set.
--
-- ns.Guild is four files, in this .toc order: Crew/GuildNames.lua (reading the rows, keys and names, the loaded
-- list), Crew/GuildIdentity.lua (whose saved data is on top, the fit rule), this file (membership, the guild's name,
-- active(), when the list is read, the events) and Crew/GuildCommands.lua (/tc guild use, new, load). They share
-- private helpers through Guild._.
local _, ns = ...

local FEATURE = "guild"
local Guild = ns.Guild
local P = Guild._
local L = P.list -- the loaded list (Crew/GuildNames.lua): members, byFull, byKey, byFirst, byGuid, loaded ...

local plain = ns.Util.plain
local saved, readList, anyOffline, byFullName = P.saved, P.readList, P.anyOffline, P.byFullName
local assignKeys, saveSpelling, sigOf, install, rememberMyKey = P.assignKeys, P.saveSpelling, P.sigOf, P.install,
  P.rememberMyKey
local PLACEHOLDER, dataGuild, isReal, hasSet, rememberGuild = P.PLACEHOLDER, P.dataGuild, P.isReal, P.hasSet,
  P.rememberGuild
local dataEmpty, aboutNobody, rosterFits, nameData = P.dataEmpty, P.aboutNobody, P.rosterFits, P.nameData
local COALESCE = 1       -- s: roster events closer than this are read once, after the gap
local TICK = 1           -- s: the ticker that checks membership and asks for refreshes
local STABLE_GAP, STABLE_READS = 5, 3 -- this many reads this far apart with one readable count: the list is complete
local ADOPT_RETRY = 60   -- s: unnamed or "?" data that did not fit a complete list: read again this often at most

local complete = false       -- the last read gave as many readable rows as the game said there are (or was stable)
local whole = false          -- and it surely holds the offline members too (see Guild.whole)
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
local quietAt                -- ns.now() of the last whole read that unnamed or "?" data did not fit (nil: none)
local partialAt              -- ns.now() of the last complete but not whole read that it did not fit (nil: none)
local lastComplete = false   -- the last read in "adopt" mode was complete (then re-reads wait ADOPT_RETRY s)

-- This character's guild name as the game gives it (nil when it gives none, or a secret). The guild's identity is
-- its name alone (a realm the game gives now and then would make it flip).
local function guildId()
  local name = plain(GetGuildInfo, "player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- Says a line once per session.
local function tell(id, text)
  if told[id] then return end
  told[id] = true
  print(text)
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

-- Reads the game's list (see readMode). A list that cannot be read (secret values, nothing yet) changes nothing.
-- A partial read (fewer readable rows than the game counts, unless the same counts came back on STABLE_READS reads
-- STABLE_GAP s apart) updates the members it did read, keeps the others as they were and gives out no new keys;
-- complete() tells which one the last read was, whole() whether it surely holds the offline members too (exact, or
-- an offline member is listed: a stable short list of online members only is complete, never whole).
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
  local isWhole = readable == count or (isComplete and anyOffline(entries))
  if mode == "adopt" then
    lastComplete = isComplete
    if not isComplete then return end -- whose data it is waits for a complete list
    if not (rosterFits(entries) and nameData(here())) then
      -- read again at most every ADOPT_RETRY s (and on a roster update). Only a whole list may refuse the data (the
      -- quiet state and the choice line); a list that may lack the offline members keeps waiting quietly.
      if isWhole then
        quietAt, partialAt = now, nil
        tellChoice()
      else
        partialAt = now
      end
      return
    end
    partialAt = nil
  end
  table.sort(entries, byFullName) -- keys are given out A-Z
  assignKeys(entries, isComplete)
  if isComplete then for _, e in ipairs(entries) do if e.key then saveSpelling(e) end end end
  local kept = {}
  for _, e in ipairs(entries) do if e.key then kept[#kept + 1] = e end end
  if not isComplete then -- members this read could not see stay as they were
    for _, e in ipairs(L.members) do
      if not seen[e.full:lower()] then kept[#kept + 1] = e end
    end
  end
  if #kept == 0 then return end
  table.sort(kept, byFullName)
  local sig = sigOf(kept)
  local first = not L.loaded
  local nowWhole = isComplete and isWhole
  local changed = sig ~= signature or (isComplete and not complete) or (nowWhole and not whole)
  install(kept)
  L.loaded, complete, whole = true, isComplete, nowWhole
  signature = sig
  rememberMyKey()
  if isReal(curId) and dataGuild() == curId and Guild.listFits() then saved().fitIn = curId end -- (see mayForget)
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
  local had = L.loaded or #L.members > 0
  L.loaded, complete, whole, signature = false, false, false, ""
  stableKey, stableN, stableAt = nil, 0, nil
  quietAt, partialAt, lastComplete = nil, nil, false
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
  -- nothing saved yet, or unnamed data about nobody else (aboutNobody): this guild's
  if (dg == nil and aboutNobody()) or (dg == PLACEHOLDER and dataEmpty()) then nameData(id) end
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
    -- a complete list that did not fit: once a minute; a list still settling (or changed): every STABLE_GAP s
    local gap = (quietAt or partialAt) and lastComplete and ADOPT_RETRY or STABLE_GAP
    if not lastRead or ns.now() - lastRead >= gap then read() end
  end
  updateActive()
end

-- The game's answer: is this character in a guild (any guild)?
function Guild.inGuild() return announced == true end
function Guild.known() return announced ~= nil end
function Guild.loaded() return L.loaded end
function Guild.complete() return L.loaded and complete end
-- The list surely holds every member, offline ones too: the last read was exact (as many readable rows as the game
-- counts), or complete and it lists at least one offline member. (If the guild window's "Show Offline Members" box
-- is not ticked the game may give only the online members.) Only a whole list hides saved friends who are missing
-- from it (Roster:syncGuild), lets the 60-day rule run (mayForget) and refuses unnamed data that does not fit.
function Guild.whole() return L.loaded and complete and whole end

-- This session's guild name (sticky; nil while the game names none); the guild the saved data on top belongs to
-- (nil: unnamed, from before guilds; "?": taken while the game named no guild).
Guild.name = guildId
function Guild.id() return curId end
Guild.dataGuild = dataGuild
Guild.PLACEHOLDER = PLACEHOLDER
Guild.dataEmpty = dataEmpty

-- The last read: rows the game counted and rows it gave readably (nil before any read).
function Guild.readStats() return counted, readableRows end

-- The game's list as it is now, read or not (for /tc guildtest, also while TwizCrew is quiet): { counted (rows the
-- game counts, nil when unreadable), readable (rows it gives readably), online (its count of online members, nil
-- when unreadable), entries (the readable rows: full, online, zone ...; no keys, nothing is kept) }.
function Guild.peek()
  local entries, count, readable = readList()
  local _, online = plain(GetNumGuildMembers)
  return { counted = type(count) == "number" and count or nil, readable = readable or 0,
    online = type(online) == "number" and online or nil, entries = entries }
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
-- name not given yet, or unnamed / "?" data waiting for a complete list (or a whole one: partial). (Quiet but not
-- deciding: the data is another guild's, or a whole list did not fit.)
function Guild.deciding()
  if not Guild.inGuild() or Guild.active() then return false end
  if settling() or (curId == nil and not nameless()) then return true end
  return readMode() == "adopt" and quietAt == nil
end

-- Why TwizCrew is not using this guild's data (nil while it is, Guild.active): "noguild" (the game said so, after
-- the grace time), "reload" (another guild's data is on top, or this guild has its own parked set: /reload),
-- "choose" (unnamed or "?" data that a whole list does not fit: /tc guild), "partial" (it waits for a list that
-- surely holds the offline members), "noname" (the game gives no guild name now and this account has seen names:
-- only /tc guild load works), or "loading" (still finding out: the game has not answered, a guild change, the list).
function Guild.quietReason()
  if Guild.active() then return nil end
  if announced == false then return "noguild" end
  if not Guild.inGuild() or settling() then return "loading" end
  if Guild.needsReload() then return "reload" end
  local mode = readMode()
  if mode == "adopt" and quietAt then return "choose" end
  if mode == "adopt" and partialAt then return "partial" end
  if nameless() and not here() then return "noname" end
  return "loading"
end

-- A guild switch or "no guild" is pending (the game has not settled yet).
Guild.settling = settling

-- The guild list is complete and the saved friends on top fit it (rosterFits).
function Guild.listFits() return L.loaded and complete and (rosterFits(L.members)) end

-- May Crew forget friends not seen for 60 days? Only while active, on a whole list, and when the saved friends fit it
-- (listFits) or this set has fitted this very guild before (guild.fitIn, written in read: over half the friends may
-- have left since, and the friends who left are the very rows the 60-day rule removes). A set taken by a wrong guild
-- (use yes, load) carries another guild's fitIn or none, and a "?" or nameless session has no real guild id: those
-- forget only while their own list fits (listFits), never through fitIn.
function Guild.mayForget()
  if not Guild.active() or not Guild.whole() then return false end
  if Guild.listFits() then return true end
  local fitIn = saved().fitIn
  return isReal(curId) and fitIn == curId
end

-- May this character write to the per-guild saved data (my session, my calendar marks)? Only while active: a
-- character in no guild or in another guild leaves the data on top as it is.
function Guild.writable() return Guild.active() end

-- For Crew/GuildCommands.lua (/tc guild use, new, load).
P.settling, P.nameless, P.here, P.updateActive = settling, nameless, here, updateActive
function P.clearQuiet() quietAt = nil end

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
