-- Pure rules of the welcome card (UI/Welcome.lua owns the frames and the timing): who just joined the guild (a
-- "Say hi" pop-up for the members online), the newcomer's own start card (shown once), who is online near my level
-- and the words. No frames and no game calls here.
local _, ns = ...

local WelcomeLogic = {}
ns.WelcomeLogic = WelcomeLogic

WelcomeLogic.MAX_PER_MINUTE = 3 -- "Say hi" pop-ups at most this many a minute (more in one list: none, see joins)
WelcomeLogic.NEAR_LEVELS = 5    -- "near your level": this many levels up or down
WelcomeLogic.NEAR_MAX = 5       -- names on the start card at most

-- The session's state for join detection: prev = the lower-case full names of the last WHOLE guild list this session
-- (nil until there was one), recent = when the last pop-ups were shown (for MAX_PER_MINUTE).
function WelcomeLogic.new() return { prev = nil, recent = {} } end

local function lower(e) return type(e.full) == "string" and e.full:lower() or nil end

-- New guild members to welcome in a guild list that just loaded (members: { key, full, level, class, name, online }).
-- opts: whole (the list surely holds the offline members), now (seconds), baseline (lower-case full names in the
-- snapshot saved at the last logout, or nil), mine (my own characters: GUIDs, keys and lower-case full names), welcomed
-- (lower-case full names already welcomed on this account, ever). Someone is new when the last whole list of this
-- session did not have them: so never on the first list of a session, never before a whole list was seen, never for
-- someone in the saved snapshot (members who joined while I was offline are on the "While you were away" card), my
-- own characters or anyone welcomed before. At most MAX_PER_MINUTE are returned a minute (the rest are dropped). A
-- whole list becomes the new `prev`. More than MAX_PER_MINUTE such new names in one list is a resync, not joins (say,
-- the offline members after a list of only the online ones that looked whole): nobody is returned and the names join
-- `prev`. Returns the entries, A-Z.
function WelcomeLogic.joins(state, members, opts)
  opts = opts or {}
  local cur = {}
  for _, e in ipairs(members or {}) do
    local l = lower(e)
    if l then cur[l] = true end
  end
  local prev = state.prev
  if opts.whole then state.prev = cur end
  if not prev then return {} end
  local mine, welcomed, baseline = opts.mine or {}, opts.welcomed or {}, opts.baseline
  local now = tonumber(opts.now) or 0
  local recent = {}
  for _, t in ipairs(state.recent) do if now - t < 60 then recent[#recent + 1] = t end end
  state.recent = recent
  local found = {}
  for _, e in ipairs(members or {}) do
    local l = lower(e)
    if l and not prev[l] and not (baseline and baseline[l]) and not mine[l] and not (e.key and mine[e.key])
      and not (e.guid and mine[e.guid])
      and not welcomed[l] and not ns.isTestName(e.full) then
      found[#found + 1] = e
    end
  end
  if #found > WelcomeLogic.MAX_PER_MINUTE then
    if not opts.whole then for l in pairs(cur) do prev[l] = true end end -- (a whole list is `prev` already)
    return {}
  end
  table.sort(found, function(a, b) return a.full:lower() < b.full:lower() end)
  local out = {}
  for _, e in ipairs(found) do
    if #state.recent >= WelcomeLogic.MAX_PER_MINUTE then break end
    state.recent[#state.recent + 1] = now
    out[#out + 1] = e
  end
  return out
end

-- The newcomer's start card, once per guild set (store = that guild's saved welcome data, store.start): the first
-- time TwizCrew uses this guild's data on this account, it is owed ("due") when this copy had no saved crew data for
-- the guild at login (fresh: not an old user whose data was just adopted), else never ("no"). Later calls change
-- nothing. A card still owed at logout (a fight or a dungeon all session) shows at the next login.
function WelcomeLogic.markStart(store, fresh)
  if type(store) ~= "table" or store.start ~= nil then return end
  store.start = fresh and "due" or "no"
end

function WelcomeLogic.startDue(store) return type(store) == "table" and store.start == "due" end

function WelcomeLogic.startShown(store) if type(store) == "table" then store.start = "shown" end end

-- Online members near my level: online, not me (isMe(entry)), within NEAR_LEVELS levels; nearest first (then the
-- lower level, then A-Z), at most NEAR_MAX.
function WelcomeLogic.nearLevel(members, myLevel, isMe)
  myLevel = tonumber(myLevel)
  local out = {}
  if not myLevel then return out end
  for _, e in ipairs(members or {}) do
    local lv = tonumber(e.level)
    if e.online and lv and math.abs(lv - myLevel) <= WelcomeLogic.NEAR_LEVELS and not (isMe and isMe(e)) then
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b)
    local da, db = math.abs(a.level - myLevel), math.abs(b.level - myLevel)
    if da ~= db then return da < db end
    if a.level ~= b.level then return a.level < b.level end
    return tostring(a.name or a.key):lower() < tostring(b.name or b.key):lower()
  end)
  while #out > WelcomeLogic.NEAR_MAX do table.remove(out) end
  return out
end

-- "Online near your level: Frostie (24), Chaos (26)", or that nobody is.
function WelcomeLogic.nearText(list)
  if #list == 0 then return "Nobody near your level is on right now" end
  local parts = {}
  for i, e in ipairs(list) do
    parts[i] = ns.Util.safeText(tostring(e.name or e.key)) .. " (" .. math.floor(tonumber(e.level) or 0) .. ")"
  end
  return "Online near your level: " .. table.concat(parts, ", ")
end

-- "The crew usually plays: Tue 8pm-11pm" from CalendarLogic.bestTime; nil without one.
function WelcomeLogic.bestText(best)
  if type(best) ~= "table" or not best.weekday then return nil end
  local L = ns.CalendarLogic
  return "The crew usually plays: " .. L.SHORT_DAYS[best.weekday + 1] .. " " .. L.clock(best.from * 60) .. "-"
    .. L.clock(best.to * 60)
end

-- The "Say hi" pop-up's words: "Say hi to Sneakz", "Level 8 Mage just joined the guild - click to say hello".
-- className: the class as the game names it (nil when unknown).
function WelcomeLogic.popupText(name, level, className)
  local who = {}
  level = tonumber(level)
  if level then who[#who + 1] = "Level " .. math.floor(level) end
  if type(className) == "string" and className ~= "" then who[#who + 1] = className end
  local sub = #who > 0 and (table.concat(who, " ") .. " just joined the guild") or "Just joined the guild"
  return "Say hi to " .. ns.Util.safeText(tostring(name)), sub .. " - click to say hello"
end

-- What a click says in guild chat (one picked at random). Plain words, no colour codes.
WelcomeLogic.GREETINGS = {
  "Welcome to the guild, %s!",
  "Hi %s, welcome to the guild!",
  "Welcome aboard, %s!",
  "Hey %s, glad to have you with us!",
}

-- Greeting `pick` (1..#GREETINGS; out of range: the first) for name. A "|" in a name cannot be sent: it is dropped.
function WelcomeLogic.greeting(name, pick)
  local fmt = WelcomeLogic.GREETINGS[tonumber(pick) or 1] or WelcomeLogic.GREETINGS[1]
  local clean = tostring(name):gsub("[|%c]", "")
  return (fmt:gsub("%%s", function() return clean end))
end
