-- Whose saved data is on top (part of ns.Guild, see Crew/Guild.lua for the whole rule): the data guild's name, the
-- sets parked for other guilds, byChar, whether the saved friends fit a guild list (rosterFits), and unnamed or "?"
-- data becoming a guild's (nameData, pinOldCrew). Reads and writes only saved data, no session state.
local _, ns = ...

local Guild = ns.Guild
local P = Guild._

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
    local marker = path == "guild.pinnedOld" or path == "guild.fitIn" -- (a set's own bookkeeping, not about anyone)
    if not marker and not hollow(v, path == "calendar" and "me" or nil) then return false end
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

-- Nothing saved on top is about anyone else: no real roster row, no crew numbers, no trophy, no calendar note by
-- someone else (a note's key starts with its author's diary id, calendar.me for mine). Only this player's own
-- session, feed, diary and notes: a v0.1.24 user who never had anyone on the panel. Unnamed data like that is taken
-- by a guild at once, like empty data (onIdentity), and pins nobody.
local function aboutNobody()
  if #savedRows() > 0 then return false end
  local db = ns.db
  local stats = type(db.stats) == "table" and db.stats or {}
  for name in pairs(type(stats.crew) == "table" and stats.crew or {}) do
    if type(name) ~= "string" or not ns.isTestName(name) then return false end
  end
  if not hollow(stats.trophies) then return false end
  local cal = type(db.calendar) == "table" and db.calendar or {}
  local mine = type(cal.me) == "string" and cal.me ~= "" and (cal.me .. "-") or nil
  for key in pairs(type(cal.notes) == "table" and cal.notes or {}) do
    if not (mine and type(key) == "string" and key:sub(1, #mine) == mine) then return false end
  end
  return true
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

-- For Crew/Guild.lua and Crew/GuildCommands.lua.
P.PLACEHOLDER, P.dataGuild, P.isReal, P.hasSet, P.rememberGuild = PLACEHOLDER, dataGuild, isReal, hasSet, rememberGuild
P.dataEmpty, P.savedRows, P.aboutNobody, P.rosterFits = dataEmpty, savedRows, aboutNobody, rosterFits
P.pinOldCrew, P.nameData = pinOldCrew, nameData
