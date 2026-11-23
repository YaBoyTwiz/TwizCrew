-- The welcome card. When someone new joins the guild, every member online gets a pop-up: "Say hi to Sneakz", "Level 8
-- Mage just joined the guild - click to say hello"; the click posts a friendly line in guild chat (it has to happen
-- inside the click: real chat needs a key press or a click). Switch: Pop-ups, "New guild members" (needs that module
-- on; never filtered by "Whose news I get": a brand-new member is in nobody's party or pins).
-- And the newcomer's own start card, once per guild on this account, the first time this copy uses a guild's data
-- with nothing saved for it: who is online near their level, when the crew usually plays (only from data already on
-- this copy), and a button to the About page.
-- The rules are in UI/WelcomeLogic.lua; saved per guild in db.welcome (Core/DB.lua GUILD_PATHS).
local _, ns = ...

local Welcome = {}
ns.Welcome = Welcome

local FEATURE = "welcome"
local Logic = ns.WelcomeLogic
local I = "Interface\\Icons\\"
local START_DELAY, START_CAP = 30, 120 -- s after login: the start card's earliest look, and when to stop waiting
Welcome.START_CAP = START_CAP -- (UI/About.lua waits that long for the card)
local POPUP_SECONDS = 20
local FORGET_AFTER = 400 * 86400 -- s: a welcomed name is kept this long

local state = Logic.new()
local fresh = false   -- this copy had no saved crew data for the guild on top at login
local baseline        -- lower-case full names in the snapshot saved at the last logout, and that snapshot's guild
local baselineGuild
local startedAt
local started = false
local startDecided = false
local card
local lastSaid        -- the last line sent (test hook)

local function store()
  if type(ns.db.welcome) ~= "table" then ns.db.welcome = {} end
  local w = ns.db.welcome
  if type(w.welcomed) ~= "table" then w.welcomed = {} end
  return w
end

local function popupsWanted()
  return ns.Modules.isEnabled("popups") and ns.Modules.setting("popups", "newMember") ~= false
end

local function className(token)
  if type(token) ~= "string" or token == "" then return nil end
  local t = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[token]
  if type(t) == "string" then return t end
  return token:sub(1, 1) .. token:sub(2):lower()
end

-- Posts a hello in guild chat. Runs inside the pop-up's click (a hardware event), never from a timer. If the game
-- refuses, the chat box opens with the line typed; else one chat line says what to type.
local function sayHi(name)
  local line = Logic.greeting(name, math.random(#Logic.GREETINGS))
  lastSaid = line
  local send = (type(SendChatMessage) == "function" and SendChatMessage)
    or (C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" and C_ChatInfo.SendChatMessage) or nil
  if send and pcall(send, line, "GUILD") then return end
  local open = (ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" and ChatFrameUtil.OpenChat)
    or (type(ChatFrame_OpenChat) == "function" and ChatFrame_OpenChat) or nil
  if open and pcall(open, "/g " .. line) then return end
  print("TwizCrew: could not post in guild chat. Type: /g " .. line)
end

local function popup(e)
  local title, sub = Logic.popupText(e.name or e.key, e.level, className(e.class))
  local name = e.name or e.key
  ns.Popups.notice(I .. "INV_Misc_Gift_01", title, sub, function() sayHi(name) end, POPUP_SECONDS)
end

-- A guild list loaded: new members get a "Say hi" pop-up (WelcomeLogic.joins).
local function onList()
  Welcome.maybeStart(false)
  local G = ns.Guild
  if not G.active() or not G.loaded() then return end
  local snapOk = baseline ~= nil and baselineGuild == G.here()
  local w = store()
  local got = Logic.joins(state, ns.AwayCard.memberList(), { whole = G.whole(), now = ns.now(),
    baseline = snapOk and baseline or nil, mine = ns.AwayCard.myCharacters(), welcomed = w.welcomed })
  if #got == 0 or not popupsWanted() or not ns.Popups then return end
  for _, e in ipairs(got) do
    w.welcomed[e.full:lower()] = ns.wallclock()
    popup(e)
    ns.Log.add("info", "welcome pop-up for a new guild member")
  end
end

-- "The crew usually plays": the best time from the play times already on this copy (not mine), when at least two
-- others have some; nil otherwise.
local function bestTime()
  if not ns.Diary or not ns.CalendarLogic then return nil end
  local me = ns.Diary.myId()
  local others = {}
  for id, p in pairs(ns.Diary.people()) do
    if id ~= me and type(p) == "table" and type(p.days) == "table" then
      others[id] = { name = p.name, class = p.class, days = p.days }
    end
  end
  local L = ns.CalendarLogic
  local u = L.usual(others, ns.Diary.localToday(), ns.Diary.offsetOn, 4)
  if u.count < 2 then return nil end
  return Logic.bestText(L.bestTime(u))
end

local function showStart()
  local G = ns.Guild
  if not G.active() or not Logic.startDue(store()) then return end
  Logic.startShown(store())
  local myLevel = ns.Util.plain(UnitLevel, "player")
  local myKey = G.myKey()
  local near = Logic.nearLevel(ns.AwayCard.memberList(), myLevel, function(e)
    return e.key == myKey or G.isMe(e.full)
  end)
  local lines = { { icon = I .. "Ability_Warrior_BattleShout", text = Logic.nearText(near) } }
  local ok, best = ns.Log.safe(FEATURE, bestTime)
  if ok and best then lines[#lines + 1] = { icon = I .. "Spell_Holy_BorrowedTime", text = best } end
  local buttons = {}
  if ns.About and type(ns.About.open) == "function" then
    buttons[#buttons + 1] = { label = "How to use TwizCrew", onClick = function() ns.About.open() end }
  end
  buttons[#buttons + 1] = { label = "Close" }
  if not card then
    card = ns.AwayCard.newCard("TwizCrewWelcomeCard", I .. "INV_Misc_Gift_01", "Welcome to TwizCrew", false, FEATURE)
  end
  local id = G.id()
  card.fill(id and ("You are in " .. ns.Util.safeText(id) .. ".") or nil, lines, buttons)
end

-- The game says this character is in no guild (not just "not known yet").
local function noGuild() return ns.Guild.known() and not ns.Guild.inGuild() end

-- The start card: worked out once, START_DELAY s after login (the list loaded and this guild's data in use), at the
-- latest at START_CAP. In no guild it is not worked out at all: an invite later this session decides it (the next
-- guild list). A new install seen in no guild (nothing saved at login, this account never read a guild's name) is
-- remembered account-wide (db.welcomePending), so the card is still owed when the invite comes after a logout; the
-- first guild that decides uses it up.
function Welcome.maybeStart(final)
  if startDecided or not started or ns.now() - startedAt < START_DELAY - 1 then return end -- (timers run a hair early)
  local G = ns.Guild
  if not G.active() or not G.loaded() then
    if noGuild() then
      local g = ns.db and ns.db.guild
      if fresh and not (type(g) == "table" and g.named) then ns.db.welcomePending = true end
      return
    end
    if final then startDecided = true end
    return
  end
  startDecided = true
  local w = store()
  Logic.markStart(w, fresh or ns.db.welcomePending == true)
  ns.db.welcomePending = nil
  if Logic.startDue(w) then ns.AwayCard.whenFree(showStart, FEATURE) end
end

function Welcome.start()
  if started then return end
  started = true
  startedAt = ns.now()
  fresh = ns.Guild.dataEmpty() and true or false
  local snap = ns.db and type(ns.db.away) == "table" and ns.db.away.snap or nil
  if type(snap) == "table" and type(snap.members) == "table" then
    baseline, baselineGuild = {}, snap.guild
    for _, s in pairs(snap.members) do
      if type(s) == "table" and type(s.full) == "string" then baseline[s.full:lower()] = true end
    end
  end
  local w = ns.db and type(ns.db.welcome) == "table" and ns.db.welcome.welcomed or nil
  local now = ns.wallclock()
  for k, t in pairs(type(w) == "table" and w or {}) do
    if type(t) ~= "number" or now - t > FORGET_AFTER then w[k] = nil end
  end
  ns.Bus.on(FEATURE, "GUILD_LIST", onList)
  ns.Bus.on(FEATURE, "GUILD_STATE", function(active)
    if not active then state = Logic.new() end -- another guild's list must never look like a crowd of newcomers
  end)
  C_Timer.After(START_DELAY, function() ns.Log.safe(FEATURE, Welcome.maybeStart, false) end)
  C_Timer.After(START_CAP, function() ns.Log.safe(FEATURE, Welcome.maybeStart, true) end)
end

-- Is the start card still to come this session (not decided yet for a fresh copy, or owed and waiting for a free
-- moment)? Not while the game says there is no guild. The About page asks, so a new install does not get two windows
-- at once (UI/About.lua).
function Welcome.startOwed()
  local w = ns.db and ns.db.welcome
  local state = type(w) == "table" and w.start or nil
  if state == "shown" or state == "no" then return false end
  if state == "due" then return true end
  if not started or startDecided or noGuild() then return false end
  return fresh or ns.db.welcomePending == true
end

-- Test hooks.
function Welcome.isStartShown() return card ~= nil and card.frame:IsShown() and true or false end
function Welcome.startCardForTest() return card end
function Welcome.lastSaidForTest() return lastSaid end
