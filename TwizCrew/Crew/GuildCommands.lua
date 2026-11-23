-- /tc guild use, new and load: what each does to the saved data (part of ns.Guild, see Crew/Guild.lua; UI/Commands.lua
-- says the answers to the player).
local _, ns = ...

local Guild = ns.Guild
local P = Guild._

local PLACEHOLDER, dataGuild, isReal, hasSet, rememberGuild = P.PLACEHOLDER, P.dataGuild, P.isReal, P.hasSet,
  P.rememberGuild
local dataEmpty, savedRows, rosterFits, pinOldCrew = P.dataEmpty, P.savedRows, P.rosterFits, P.pinOldCrew
local readList = P.readList
local settling, nameless, here, updateActive = P.settling, P.nameless, P.here, P.updateActive

local previewed = {}         -- /tc guild load <n> shown this session: n -> the set it showed (from .. key)

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
  if type(g.requestResults) == "table" and r.char then g.requestResults[r.char] = nil end
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
  P.clearQuiet()
  ns.Log.add("info", "/tc guild use%s: the saved data is %s's", yes and " yes" or "", ns.Util.safeText(id))
  updateActive()
  return true
end

-- /tc guild new [yes]: this guild gets a fresh set of its own at the next login (a one-shot request DB.useGuildOf
-- carries out; the unnamed or "?" data on top is parked, nothing is deleted). On a game that never names guilds the
-- set is shared by every character, so it needs yes; with the shared "?" set in use, new yes starts it fresh (the
-- current one is parked). Returns true, or false and why: commandGuild's, "inuse", "parked" / "parkedShared" (this
-- guild has a set: never a second one), "named" (another guild's data is on top: /reload first), "shared" (yes
-- needed), "sharedInUse" (the shared set is in use: yes starts it fresh).
function Guild.newHere(yes)
  local id, why = commandGuild()
  if not id then return false, why end
  local dg = dataGuild()
  if dg == id and id == PLACEHOLDER then
    if not yes then return false, "sharedInUse" end
    request({ kind = "new", guild = id })
    ns.Log.add("info", "/tc guild new yes: the shared set starts fresh at the next login")
    return true
  end
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
