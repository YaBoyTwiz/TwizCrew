-- Live roasts (module "roasts"): the copy of the person something happened to sends one small ROAST message
-- (k kind, v number, x extra text, n line number); every crew copy, including the sender's, shows the same line
-- as an orange pop-up. Stats.lua calls Roasts.send.
-- Who decides what (spec 12b): the sender's copy sends only while its stats module and "Roasts about me" are on;
-- the viewer's roasts module and per-kind switches only decide what that viewer sees.
-- No flood: at most one roast about the same person every ROAST_GAP s (on the sender and on every receiver), and
-- one wipe roast per WIPE_ROAST_DEDUPE s (whoever's copy is first; the others stay quiet).
local _, ns = ...

local FEATURE = "roasts"
local Roasts = {}
ns.Roasts = Roasts

local WIPE_WAIT = 2   -- a wipe roast waits a random 0..WIPE_WAIT s, so one copy is usually first
local X_MAX = 60      -- letters of extra text (mob or place name) sent at most
local SHOWN_MAX = 20  -- texts kept for forTest.shown()

-- Placeholders: {name} the person (the sender), {v} a number, {x} a mob or place name. The first line of each kind
-- is the spec's. Plain and playful, about the game only: these show live on stream.
Roasts.LINES = {
  weak = {
    "{name} died to a level {v} {x}. Embarrassing.",
    "A level {v} {x} just took down {name}. Someone write this down.",
    "{name} vs a level {v} {x}. The {x} won.",
    "{name} lost a fight to a level {v} {x}. Maybe try a lower level next time.",
  },
  fall = {
    "{name} forgot gravity exists.",
    "{name} took the fast way down.",
    "{name} tried to fly. {name} cannot fly.",
    "The ground wins again. Sorry, {name}.",
  },
  drown = {
    "{name} tried to breathe water. It didn't work.",
    "{name} forgot to come up for air.",
    "{name} found out the breath bar is not a suggestion.",
    "{name} has gone to live with the murlocs.",
  },
  again = {
    "{name} is back for more. Dead again in {v} seconds.",
    "{name} lasted {v} seconds this time. A new record?",
    "Run back, die again. {name} did it in {v} seconds.",
  },
  deaths = {
    "That's death #{v} tonight for {name}.",
    "{name} has died {v} times tonight. The spirit healer knows them by name.",
    "{v} deaths tonight for {name}. The repair bill is crying.",
  },
  wipe = {
    "WIPE! Everybody down in {x}.",
    "Total wipe in {x}. Time for the long run back.",
    "{x} wins this round. Everybody is dead.",
    "WIPE in {x}! Who pulled that?",
  },
  steps = {
    "{name} just passed {v} steps. Still lost.",
    "{v} steps for {name}. Ever heard of a mount?",
    "{name} has walked {v} steps and still can't find the quest giver.",
  },
  jumps = {
    "{name} has jumped {v} times. Why.",
    "{name} just hit {v} jumps. Bunny hop champion.",
    "{name} has jumped {v} times. Walking is also allowed.",
  },
  quit = {
    "{name} gave up on another quest. That's {v} tonight.",
    "{name} dropped quest number {v} tonight. The quest givers are disappointed.",
    "Another quest abandoned by {name}. {v} tonight and counting.",
  },
}
local LINES = Roasts.LINES

-- Kinds whose lines show {v}: a roast of these kinds without a usable number is not sent and not shown.
local NEEDS_V = { weak = true, again = true, deaths = true, steps = true, jumps = true, quit = true }
local DEFAULT_X = { weak = "mob", wipe = "a dungeon" }

local senderLimit = ns.StatsLogic.newLimiter(ns.Config.ROAST_GAP)  -- roasts I send (keyed by my name)
local showLimit = ns.StatsLogic.newLimiter(ns.Config.ROAST_GAP)    -- roasts I show (keyed by who it is about)
local lastWipe        -- when the last wipe roast was sent or accepted (nil: none yet)
local shown = {}      -- texts shown, oldest first (test hook)

local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function usableNumber(v)
  return type(v) == "number" and v == v and v ~= math.huge and v >= 0
end

local function wipeRecent(now)
  return lastWipe ~= nil and now - lastWipe < ns.Config.WIPE_ROAST_DEDUPE
end

-- The text of line n of a kind (pure). n out of range or not a whole number: line 1. name and x are made safe.
function Roasts.text(kind, n, name, v, x)
  local lines = LINES[kind]
  if not lines then return nil end
  n = tonumber(n)
  if not n or n ~= math.floor(n) or n < 1 or n > #lines then n = 1 end
  if x == nil or x == "" then x = DEFAULT_X[kind] or "" end
  local subs = {
    name = ns.Util.safeText(tostring(name or "")),
    v = ns.StatsLogic.number(tonumber(v)),
    x = ns.Util.safeText(tostring(x)),
  }
  return (lines[n]:gsub("{(%a+)}", function(key) return subs[key] end))
end

-- One roast arriving (from a friend, or my own through the same path with own = true).
local function handle(sender, f, own)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  local kind = f.k
  if type(kind) ~= "string" or not LINES[kind] then return end
  local v
  if NEEDS_V[kind] then
    v = tonumber(f.v)
    if not usableNumber(v) then return end
  end
  local now = ns.now()
  -- Wipe roasts are counted as seen even when this viewer does not show them, so this copy stays quiet too.
  if kind == "wipe" then
    if not own and wipeRecent(now) then return end
    lastWipe = now
  end
  if not ns.Modules.isEnabled(FEATURE) or not setting(kind) then return end
  if kind ~= "wipe" and not showLimit:allow(sender, now) then return end
  local x = type(f.x) == "string" and f.x or nil
  local text = Roasts.text(kind, f.n, sender, v, x)
  shown[#shown + 1] = text
  if #shown > SHOWN_MAX then table.remove(shown, 1) end
  if ns.Popups and ns.Popups.showRoast then ns.Popups.showRoast(text, ns.Config.ROAST_SECONDS) end
  if setting("sound") and type(PlaySound) == "function" and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING) end
  ns.Log.add("info", "roast shown: %s about %s", kind, sender)
end

local function maySend()
  return ns.Modules.isEnabled("stats") and setting("aboutMe") and true or false
end

local function transmit(kind, v, x)
  local fields = {
    k = kind,
    v = v and string.format("%.0f", math.floor(v)) or "",
    x = x or "",
    n = tostring(math.random(#LINES[kind])),
  }
  ns.Comm.send("ROAST", fields)
  handle(ns.playerName(), fields, true)
end

-- Something roast-worthy happened to me: tell the crew (and show it here). Dropped when it may not be sent.
function Roasts.send(kind, v, x)
  if type(kind) ~= "string" or not LINES[kind] or not maySend() then return end
  v = tonumber(v)
  if not usableNumber(v) then v = nil end
  if NEEDS_V[kind] and not v then return end
  if type(x) ~= "string" or x == "" then x = nil else x = ns.Util.truncateUTF8(x, X_MAX) end
  if kind == "wipe" then
    if wipeRecent(ns.now()) then return end
    local function later()
      if not maySend() or wipeRecent(ns.now()) then return end
      transmit(kind, v, x)
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(math.random() * WIPE_WAIT, function() ns.Log.safe(FEATURE, later) end)
    else
      later()
    end
    return
  end
  if not senderLimit:allow(ns.playerName(), ns.now()) then return end
  transmit(kind, v, x)
end

ns.Comm.on("ROAST", function(sender, fields) ns.Log.safe(FEATURE, handle, sender, fields, false) end)

local KIND_SETTINGS = {
  { "weak", "Died to a weak mob", "Shows a roast when someone dies to a mob far below their level." },
  { "fall", "Fall deaths", "Shows a roast when someone falls to their death." },
  { "drown", "Drowning", "Shows a roast when someone drowns or swims too far out." },
  { "again", "Died again right away", "Shows a roast when someone dies again soon after coming back to life." },
  { "deaths", "Death count milestones", "Shows a roast when someone reaches 5, 10, 20 or 50 deaths in a session." },
  { "wipe", "Wipes", "Shows a roast when the whole group dies in a dungeon." },
  { "steps", "Step milestones", "Shows a roast when someone passes a big number of steps walked." },
  { "jumps", "Jump milestones", "Shows a roast when someone passes a big number of jumps." },
  { "quit", "Quests given up", "Shows a roast when someone gives up their third quest in a session." },
}

local defaults = { aboutMe = true, sound = false }
local settings = {}
for _, s in ipairs(KIND_SETTINGS) do
  defaults[s[1]] = true
  settings[#settings + 1] = { key = s[1], label = s[2], kind = "toggle", info = s[3] }
end
settings[#settings + 1] = { key = "aboutMe", label = "Roasts about me", kind = "toggle",
  info = "Turning this off stops your copy from sending roasts about you. Your stats still count, and you "
    .. "still see roasts about your friends." }
settings[#settings + 1] = { key = "sound", label = "Play a sound", kind = "toggle",
  info = "Plays a short sound when a roast appears. Off by default so streams stay quiet." }

ns.Modules.register({
  id = FEATURE, name = "Live roasts", tier = "module",
  info = "Short funny pop-ups for everyone in the crew when someone does something silly in the game, like "
    .. "falling off a cliff or dying to a very low level mob. The switches below choose which ones you see.",
  defaults = defaults,
  settings = settings,
})

-- Test hooks.
Roasts.forTest = {
  shown = function() return shown end,
}
