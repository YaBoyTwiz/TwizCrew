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
local X_MAX = 40      -- letters of extra text (mob or place name) sent and shown at most
local V_MAX = 1e9     -- a number above this is not a real count
local SHOWN_MAX = 20  -- texts kept for forTest.shown()

-- Placeholders: {name} the person (the sender), {v} a number, {x} a mob or place name. The first line of each kind
-- is the spec's. Plain and playful, about the game only: these show live on stream.
Roasts.LINES = {
  weak = {
    "{name} died to a level {v} {x}. Embarrassing.",
    "A level {v} {x} just took down {name}. Someone write this down.",
    "{name} vs a level {v} {x}. {name} lost.",
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
    "Everybody is dead. Score one for {x}.",
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
  return type(v) == "number" and v == v and v >= 0 and v <= V_MAX
end

-- Extra text (mob or place name), sent or received: no control characters, at most X_MAX letters. nil when empty.
local function cleanX(x)
  if type(x) ~= "string" then return nil end
  x = ns.Util.truncateUTF8((x:gsub("[%z\1-\31]", "")), X_MAX)
  if x == "" then return nil end
  return x
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
  local text = Roasts.text(kind, f.n, sender, v, cleanX(f.x))
  shown[#shown + 1] = text
  if #shown > SHOWN_MAX then table.remove(shown, 1) end
  if ns.Popups and ns.Popups.showRoast then ns.Popups.showRoast(text, ns.Config.ROAST_SECONDS) end
  if setting("sound") and type(PlaySound) == "function" and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING) end
  ns.Log.add("info", "roast shown: %s about %s", kind, sender)
  ns.Bus.fire("ROAST_SHOWN", sender, text) -- the activity feed records it (text is already safe to show)
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
  x = cleanX(x)
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

------------------------------------------------------------------------------------------------------------- mocks
-- The Mock button on a dead friend's row: one click sends a roast from the rotation (built-in lines plus your own)
-- as a MOCK message (t = who it's about, x = the finished text). Every crew copy, yours too, shows it as a roast
-- pop-up "Twiz: <text>". At most one mock about the same friend every MOCK_GAP s.
local MOCK_GAP = 10
local MOCK_MAX = 120  -- letters of a roast line
Roasts.MOCK_LINES = {
  "{name}, the spirit healer has you on speed dial.",
  "Rest in pieces, {name}.",
  "{name} has left the chat. And the land of the living.",
  "Press F to pay respects to {name}. Or don't.",
  "{name} died. In other news, water is wet.",
  "Somebody get {name} a map. The graveyard is that way.",
  "{name} took a little nap. On the floor. Forever.",
  "{name}, that was not the plan, was it?",
  "Don't worry {name}, your gear needed the durability loss.",
  "{name} is now a ghost. Spooky and useless.",
  "Great job {name}, the mobs are proud of you.",
  "{name} is speedrunning the run back.",
  "Breaking news: {name} is still bad at this.",
  "{me} saw that, {name}. Everyone saw that.",
  "{name}, have you tried not dying?",
  "{name} died in {zone}. {zone} wins this round.",
  "Level {level} and still can't stay alive. Classic {name}.",
  "Even the {class} trainer is embarrassed, {name}.",
  "{name} just donated a corpse to {zone}.",
  "{name}, the floor in {zone} is not a bed.",
  "Who had {name} dying first on their bingo card? Everyone.",
  "{name} has entered ghost mode. Achievement unlocked: nothing.",
  "Pull more, they said. {name} did. {name} died.",
  "{name} has been nerfed. By the ground.",
  "Reminder: health bars go down, {name}. That's the bad direction.",
  "{name} rolled Need on a dirt nap.",
  "{name}'s repair bill just leveled up.",
  "Somewhere, a murloc is laughing at {name}.",
  "{name} found the respawn button the hard way.",
  "{me} would have carried you, {name}. Probably.",
  "{name} is taking the scenic route to the graveyard.",
  "New personal best, {name}! Fastest death yet.",
  "The spirit healer just offered {name} a loyalty card.",
  "{name}, your armor is now mostly decorative.",
  "Plot twist: {name} was the loot.",
  "Dying is a {class} skill now? {name} maxed it.",
  "{name} looked at the mob. The mob looked back. The mob won.",
  "That wasn't a wipe, that was just {name}.",
  "{name} pressed the wrong button. All of them.",
  "Tell the guild {name} died bravely. We'll lie for you.",
}
-- Placeholders a roast can use (built-in and your own). {zone}, {level} and {class} come from what the dead friend
-- shares; a line that needs one we don't know is skipped for that mock.
Roasts.MOCK_HELP = "{name} = who died, {me} = you, {zone} = where they died, {level} = their level, "
  .. "{class} = their class"
local mockLimit = ns.StatsLogic.newLimiter(MOCK_GAP)
local mockShowLimit = ns.StatsLogic.newLimiter(3)
local bag = {} -- line numbers not used yet this round (no repeats until every line had a turn)

local function cleanLine(text)
  if type(text) ~= "string" then return nil end
  text = ns.Util.trim((text:gsub("[%z\1-\31]", "")))
  if text == "" then return nil end
  return ns.Util.truncateUTF8(text, MOCK_MAX)
end

-- Your own roasts (saved on this account).
function Roasts.myMocks()
  if not ns.db then return {} end
  if type(ns.db.myMocks) ~= "table" then ns.db.myMocks = {} end
  return ns.db.myMocks
end

function Roasts.addMock(text)
  local line = cleanLine(text)
  if not line then return false end
  local mine = Roasts.myMocks()
  mine[#mine + 1] = line
  bag = {}
  if ns.Settings and ns.Settings.rebuild then ns.Settings.rebuild() end
  if ns.MockEditor then ns.MockEditor.refresh() end
  return true
end

function Roasts.removeMock(n)
  local mine = Roasts.myMocks()
  n = tonumber(n)
  if not n or not mine[n] then return nil end
  local gone = table.remove(mine, n)
  bag = {}
  if ns.Settings and ns.Settings.rebuild then ns.Settings.rebuild() end
  if ns.MockEditor then ns.MockEditor.refresh() end
  return gone
end

-- Every line in the rotation: built-in first, then yours ("only my own" leaves out the built-in ones once you
-- have some).
function Roasts.rotation()
  local list = {}
  local mine = Roasts.myMocks()
  if not (setting("ownOnly") and #mine > 0) then
    for _, l in ipairs(Roasts.MOCK_LINES) do list[#list + 1] = l end
  end
  for _, l in ipairs(mine) do list[#list + 1] = l end
  return list
end

-- The finished text of a line (pure): {name} the dead friend, {me} you.
-- info (optional): { zone =, level =, class = } about the dead friend. Unknown placeholders stay as "{key}".
function Roasts.mockText(line, target, me, info)
  info = info or {}
  local subs = { name = ns.Util.safeText(tostring(target or "")), me = ns.Util.safeText(tostring(me or "")) }
  for _, key in ipairs({ "zone", "level", "class" }) do
    local v = info[key]
    if v ~= nil and tostring(v) ~= "" then subs[key] = ns.Util.safeText(tostring(v)) end
  end
  return (tostring(line):gsub("{(%a+)}", function(key) return subs[key] or ("{" .. key .. "}") end))
end

-- What the roast can say about a crew member: { zone, level, class } from what they share.
function Roasts.mockInfo(name)
  local m = ns.roster and ns.roster:get(name)
  if not m then return {} end
  local class
  if type(m.class) == "string" and m.class ~= "" then
    local names = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE or {}
    class = names[m.class] or (m.class:sub(1, 1) .. m.class:sub(2):lower())
  end
  return { zone = m.zone ~= "" and m.zone or nil, level = tonumber(m.level), class = class }
end

local function nextLine()
  local list = Roasts.rotation()
  if #list == 0 then return nil end
  if #bag == 0 or bag.size ~= #list then
    bag = { size = #list }
    for i = 1, #list do bag[#bag + 1] = i end
  end
  local pick = table.remove(bag, math.random(#bag))
  return list[pick]
end

local function showMock(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  local text = cleanLine(f.x)
  if not text then return end
  local cheer = f.k == "g"
  if not ns.Modules.isEnabled(FEATURE) then return end
  if cheer then
    if setting("cheers") == false then return end
  elseif not setting("mocks") then
    return
  end
  if not mockShowLimit:allow(sender, ns.now()) then return end
  -- the activity feed records it: who sent it, who it is about, the words (plain), congrats or mock
  ns.Bus.fire("MOCK_SEEN", sender, type(f.t) == "string" and f.t or "", text, cheer)
  -- about ME from a friend: their character laughs at me (a mock) or cheers for me (congrats), if that's on
  if ns.MockShow and f.t and ns.isMe(f.t) and not ns.isMe(sender) and setting("mockModel") ~= false then
    shown[#shown + 1] = ns.Util.safeText(sender) .. ": " .. ns.Util.safeText(text)
    if #shown > SHOWN_MAX then table.remove(shown, 1) end
    ns.MockShow.show(sender, text, cheer and { cheer = true } or nil)
    ns.Bus.fire("ABOUT_ME", cheer and "cheer" or "mock", sender)
    ns.Log.add("info", "mock shown from %s (3D)", sender)
    return
  end
  text = ns.Util.safeText(sender) .. ": " .. ns.Util.safeText(text)
  shown[#shown + 1] = text
  if #shown > SHOWN_MAX then table.remove(shown, 1) end
  if ns.Popups and ns.Popups.showRoast then ns.Popups.showRoast(text, ns.Config.ROAST_SECONDS) end
  if setting("sound") and type(PlaySound) == "function" and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING) end
  ns.Log.add("info", "mock shown from %s", sender)
end

-- May the Mock button show for this friend? (the panel also checks they're dead)
function Roasts.canMock(target)
  return ns.Modules.isEnabled(FEATURE) and setting("mocks") and type(target) == "string" and target ~= ""
    and target ~= ns.playerName() and true or false
end

-- The Mock button: returns the text sent, or nil (too soon, nothing in the rotation, or not allowed).
function Roasts.mock(target)
  if not Roasts.canMock(target) then return nil end
  if not mockLimit:ready(target, ns.now()) then return nil end
  local info = Roasts.mockInfo(target)
  local text
  for _ = 1, #Roasts.rotation() do -- skip lines that need something we don't know about them
    local line = nextLine()
    if not line then break end
    local t = cleanLine(Roasts.mockText(line, target, ns.playerName(), info))
    if t and not t:find("{%a+}") then text = t break end
  end
  if not text then -- "only my own" left nothing usable: a built-in line instead
    local lines = Roasts.MOCK_LINES
    local start = math.random(#lines)
    for i = 0, #lines - 1 do
      local t = cleanLine(Roasts.mockText(lines[(start + i - 1) % #lines + 1], target, ns.playerName(), info))
      if t and not t:find("{%a+}") then text = t break end
    end
  end
  if not text then return nil end
  mockLimit:allow(target, ns.now()) -- the 10 s wait starts only now that a line was found
  local fields = { t = target, x = text }
  ns.Comm.send("MOCK", fields)
  showMock(ns.playerName(), fields)
  return text
end

------------------------------------------------------------------------------------------------- congrats
-- The Congrats button (on a friend's row for a few minutes after they level up): an encouraging line the crew sees.
-- It rides on the MOCK message with k = "g", so older copies still show it (as a plain line). The friend it's about
-- sees the sender's character cheer for them, with the level-up fanfare.
Roasts.CHEER_LINES = { -- cheering, with a poke at them (smartass on purpose)
  "Level {level}, {name}! Only took you forever. Proud of you, I guess.",
  "Ding! {name} hit {level}. The mobs of {zone} will never recover. Probably.",
  "GG {name}! Level {level}. Now you can die to slightly bigger things.",
  "Look at {name}, level {level}! Get the camera. Actually don't, it's embarrassing.",
  "Level {level}! {name} is now officially less useless. Grats!",
  "{name} hit {level}! I'd say I'm impressed, but I've watched you play.",
  "Congrats on {level}, {name}! Your corpse runs are getting shorter. Growth!",
  "{name} reached {level}! Somewhere a trainer is warming up to take all your gold.",
  "GZ {name}! Level {level} {class}. Still a {class}, but a taller one!",
  "Level {level}! {name}, you've almost earned the right to complain about the grind.",
  "Wow, {name} hit {level}. Did someone else play your account? Kidding. Mostly.",
  "Ding {level}! {name} can now lose to elites instead of normal mobs. Progress!",
  "{name} leveled up! The spirit healer will miss you. For about ten minutes.",
  "Level {level}, {name}! Quick, buy all your new ranks and be broke again.",
  "Congrats {name}! Level {level}. Your talent tree called, it's confused too.",
  "Level {level}! {name} trained hard for this moment. Mostly by dying.",
  "GG {name}, level {level}! The murlocs of Azeroth are filing a complaint.",
  "{name} dinged {level}! Took so long I aged three years. Grats though!",
  "Level {level}! {name} is a legend now. A small, local, slightly lost legend.",
  "Big grats, {name}! Level {level}. Don't let it go to your head. Too late?",
  "{name} hit {level}! Every boar in {zone} breathes a sigh of relief.",
  "Level {level}, {name}! One step closer to max level, two steps from a wall.",
  "Ding! {name} is level {level}. Achievement unlocked: the bare minimum, but faster.",
  "Grats {name}! At level {level} you can almost afford to repair.",
  "Level {level}! {name}, your {class} trainer just felt a disturbance and smiled.",
  "{name} reached level {level}! I was rooting for you. Quietly. With low expectations.",
  "Congrats on {level}, {name}! New level, same terrible pulls.",
  "Level {level}! {name} has officially out-leveled their own common sense.",
  "Woo, {name}! Level {level}! Now go stand in the fire at a higher level.",
  "GG {name}! Level {level}. The quest givers of {zone} talk about you. Mostly complaints.",
  "{name} is level {level}! Proof that if you die enough times, you level up anyway.",
  "Ding {level}, {name}! Your hearthstone is proud. It did most of the traveling.",
  "Grats {name}! Level {level}. Remember us little people when you hit max.",
  "Level {level}! {name}, that's a whole number higher than before. Math checks out.",
  "{name} hit {level}! Should I start calling you sir? No? Cool. Grats, nerd.",
  "Level {level}, {name}! Bags full, gold gone, but your heart is level {level}.",
  "Congrats {name}! Level {level}, and gravity only won a few times on the way.",
  "{me} salutes {name} for hitting level {level}. Slow clap. Very slow. Still clapping.",
  "Level {level}! {name} can now wear slightly shinier things to die in.",
  "GG {name}! Level {level}. The bar between 'new' and 'menace' just moved. Barely.",
  "{name} dinged {level}! Quick, someone tell the guards, {name} is armed and confusing.",
  "Grats on {level}, {name}! Now you're strong enough to pull way too much at once.",
  "Level {level}! {name}, the XP bar finally gave up. It respects your stubbornness.",
  "{name} is level {level}! A true hero. A hero who still runs from squirrels, but a hero.",
  "Ding {level}! {name} leveled up faster than {me} expected. The bar was on the floor.",
}
local cheerLimit = ns.StatsLogic.newLimiter(MOCK_GAP)
local cheerBag = {}

local function nextCheer()
  local list = Roasts.CHEER_LINES
  if #cheerBag == 0 then for i = 1, #list do cheerBag[#cheerBag + 1] = i end end
  return list[table.remove(cheerBag, math.random(#cheerBag))]
end

-- May the Congrats button show for this friend? (the panel also checks they just leveled up)
function Roasts.canCheer(target)
  return ns.Modules.isEnabled(FEATURE) and setting("cheers") ~= false and type(target) == "string" and target ~= ""
    and not ns.isMe(target) and true or false
end

-- The Congrats button: returns the text sent, or nil (too soon or not allowed).
function Roasts.cheer(target)
  if not Roasts.canCheer(target) then return nil end
  if not cheerLimit:allow(target, ns.now()) then return nil end
  local info = Roasts.mockInfo(target)
  local text
  for _ = 1, #Roasts.CHEER_LINES do -- skip lines that need something we don't know about them
    local t = cleanLine(Roasts.mockText(nextCheer(), target, ns.playerName(), info))
    if t and not t:find("{%a+}") then text = t break end
  end
  if not text then text = "Grats on the level, " .. target .. "!" end
  local fields = { t = target, x = text, k = "g" }
  ns.Comm.send("MOCK", fields)
  showMock(ns.playerName(), fields)
  return text
end

ns.Comm.on("MOCK", function(sender, fields) ns.Log.safe(FEATURE, showMock, sender, fields) end)

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

local defaults = { aboutMe = true, sound = false, mocks = true, mockModel = true, mockSound = true, ownOnly = false,
  addMock = "", cheers = true, stealPopups = true }
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
settings[#settings + 1] = { key = "mocks", label = "Mock button roasts", kind = "toggle",
  info = "When a friend dies, a Mock button shows on their row. Click it to roast them in front of the crew. "
    .. "This switch also decides whether you see the mocks your friends send." }
settings[#settings + 1] = { key = "cheers", label = "Congrats button", kind = "toggle",
  info = "For a few minutes after a friend levels up, a Congrats button shows on their row (and clicking the "
    .. "level-up pop-up does the same). It sends an encouraging line the crew sees; your friend sees your character "
    .. "cheer for them in 3D with the level-up fanfare. This switch also decides whether you see congrats." }
settings[#settings + 1] = { key = "stealPopups", label = "Stolen crown pop-ups", kind = "toggle",
  info = "A pop-up when someone takes the lead in a Hall of Shame award this session, like \"Twiz just stole "
    .. "Professional Corpse from Lurabe!\". Not in the first 15 minutes of a session, and at most one a minute." }
settings[#settings + 1] = { key = "mockModel", label = "Show who mocked me (3D)", kind = "toggle", parent = "mocks",
  info = "When a friend mocks you, their character laughs at you with the roast in a speech bubble: their real "
    .. "character if they're near you (or were earlier this session), otherwise their class icon. Off: the plain "
    .. "orange roast line. Try it with the Try a mock buttons on the Test tab." }
settings[#settings + 1] = { key = "mockSound", label = "Their laugh sound", kind = "toggle", parent = "mocks",
  info = "Plays the laugh of the mocker's race and gender with the 3D mock." }
settings[#settings + 1] = { key = "editMocks", label = "My mocks", kind = "button", parent = "mocks",
  onClick = function() if ns.MockEditor then ns.MockEditor.open() end end,
  info = "Opens a window to write your own mocks, try them out and delete old ones. Also: /tc mock." }
settings[#settings + 1] = { key = "ownOnly", label = "Only use my own roasts", kind = "toggle", parent = "mocks",
  info = "The Mock button picks only from the roasts you added below (once you have at least one)." }
settings[#settings + 1] = { key = "addMock", label = "Add a roast", kind = "text", parent = "mocks",
  onSave = function(v)
    if Roasts.addMock(v) then print("TwizCrew: roast added. It's in the rotation now.") end
  end,
  info = "Type a roast and press Enter to add it to the Mock button's rotation, like \"{name} tripped over a "
    .. "flower in {zone}.\" " .. Roasts.MOCK_HELP .. ". Also: /tc mock add <text>." }
settings[#settings + 1] = { key = "myMocks", label = "My roasts", kind = "list", parent = "mocks",
  lines = function()
    local out = {}
    for i, l in ipairs(Roasts.myMocks()) do out[#out + 1] = i .. ". " .. l end
    if #out == 0 then out[1] = "None yet. Add one above." end
    return out
  end,
  info = "The roasts you added. Remove one with /tc mock remove <number>." }

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
