-- The activity feed (module "activity"): a list of the recent things this copy knows about (a friend came online,
-- went offline, died, reached a level, a congrats or a mock sent or received with its words, a roast shown here),
-- saved in the saved variables (newest 50). Each event also prints one line in the player's own chat window when
-- its switch is on, and is announced on the bus as FEED_ADDED so the panel's bar can show it while minimized.
-- It listens to what the pop-ups listen to (the roster's MEMBER_* events) and to MOCK_SEEN / ROAST_SHOWN, which
-- the roasts module fires when a mock, a congrats or a roast is shown on this screen. Nothing is sent to anyone.
-- The rules (words, gates, chat switches) are in FeedLogic.
local _, ns = ...

local FEATURE = "activity"
local FL = ns.FeedLogic
local T = ns.Theme

local Feed = {}
ns.Feed = Feed

local mem = {} -- the test tools' fakes: shown with the real ones, never saved (the saved list is ns.db.feed)
local loadedAt = ns.now() -- the login quiet time counts from here, not from whenever the module is switched on
local gate

local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function settings()
  local out = {}
  for key in pairs(ns.Modules.get(FEATURE).defaults) do out[key] = setting(key) end
  return out
end

-- The saved list (a table in the saved variables), repaired once.
local function list()
  if not ns.db then return nil end
  if type(ns.db.feed) ~= "table" then ns.db.feed = {} end
  return ns.db.feed
end

---------------------------------------------------------------------------------------------------------- names
-- A name in its class colour (the roster's class, else the one saved with the entry). `plainName` is an entry's
-- name, already escaped for display.
local function colorWrap(plainName, entryClass)
  local raw = (plainName:gsub("||", "|"))
  local m = ns.roster and ns.roster:get(raw)
  local class = m and type(m.class) == "string" and m.class or entryClass
  if type(class) == "string" and class ~= "" then
    local r, g, b = T.classColor(class)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
      math.floor(b * 255 + 0.5), plainName)
  end
  return plainName
end

-- The entry's line with the friend's name (and the other one's) in class colour.
function Feed.coloredLine(e)
  return FL.coloredLine(e, function(name) return colorWrap(name, name == e.who and e.class or nil) end)
end

-- The entry's line with no colour codes.
function Feed.plainLine(e) return e.line end

---------------------------------------------------------------------------------------------------------- chat
local function say(text)
  local frame = type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME or nil
  if frame and type(frame.AddMessage) == "function" then
    if pcall(frame.AddMessage, frame, text) then return end
  end
  print(text) -- the game's print writes to the same chat window; also the way the tests read it
end

local function toChat(e)
  if not FL.chatWanted(settings(), e.kind) then return end
  local hex = T.COLOR and T.COLOR.title
  say(FL.chatText(e, function(name) return colorWrap(name, name == e.who and e.class or nil) end,
    type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") and hex or nil))
end

---------------------------------------------------------------------------------------------------------- record
-- The test tools' kind names for the pop-ups they expect: the feed uses them too.
local TEST_KIND = { died = "death" }

-- nil for a real friend; for a fake, whether a test button expects this event.
local function testState(kind, name)
  if not ns.isTestName(name) then return nil end
  if kind == "roast" then return true end -- the Roast pop-up button asked for it
  return ns.TestTools ~= nil and ns.TestTools.wants(TEST_KIND[kind] or kind, name) and true or false
end

-- Adds one event if it passes the gate. gateName: whose fake-ness decides (nil: never a fake, e.g. what I did).
-- Returns the entry, or nil when it was dropped.
function Feed.record(kind, who, extra, gateName)
  local feed = list()
  if not feed or not gate or type(who) ~= "string" or who == "" then return nil end
  local state
  if gateName then state = testState(kind, gateName) end -- (nil for a real friend, else true / false)
  if not gate:allow(kind, who, ns.now(), state) then return nil end
  local m = ns.roster and ns.roster:get(who)
  local e = FL.entry(kind, who, extra, ns.wallclock(), m and m.class or nil)
  if not e then return nil end
  FL.add((ns.isTestName(e.who) or ns.isTestName(e.other)) and mem or feed, e)
  ns.Log.safe(FEATURE, toChat, e)
  ns.Bus.fire("FEED_ADDED", e)
  return e
end

-- Will the feed take this event (the pop-ups module's kind: online, death, levelup)? The minimized panel's bar shows
-- what the feed records, so a pop-up is replaced only when this is true.
function Feed.willTake(popupKind, name)
  local kind = FL.POPUP_FEED[popupKind]
  if not gate or not kind or type(name) ~= "string" then return false end
  local state = testState(kind, name)
  return gate:wouldAllow(kind, name, ns.now(), state)
end

local function onOnline(name)
  local m = ns.roster and ns.roster:get(name)
  Feed.record("online", name, { zone = m and m.zone }, name)
end

local function onOffline(name)
  if gate then gate:noteOffline(name, ns.now()) end
  Feed.record("offline", name, nil, name)
end

local function onDied(name, zone, subzone)
  Feed.record("died", name, { zone = zone, subzone = subzone }, name)
end

local function onLevelUp(name, level)
  Feed.record("levelup", name, { level = level }, name)
end

-- A mock or a congrats shown on this screen (the roasts module fires it): sender, who it is about, the words.
local function onMock(sender, target, words, cheer)
  if type(sender) ~= "string" or type(target) ~= "string" then return end
  local kind = cheer and "congrats" or "mock"
  if ns.isMe(sender) then
    Feed.record(kind, target, { dir = "out", words = words }, nil)
  elseif ns.isMe(target) then
    Feed.record(kind, sender, { dir = "in", words = words }, sender)
  else
    Feed.record(kind, sender, { dir = "seen", other = target, words = words }, sender)
  end
end

-- A roast shown on this screen (the roasts module fires it with the finished line; "sender" is who it is about).
local function onRoast(sender, text)
  if type(sender) ~= "string" then return end
  Feed.record("roast", sender, { text = text }, sender)
end

---------------------------------------------------------------------------------------------------------- public
-- Newest first (the saved events and any test fakes together, at most MAX). Each entry: { kind, who, at, line, dir,
-- zone, subzone, level, words, other, class }.
function Feed.entries()
  local feed = list()
  if not feed then return {} end
  if #mem == 0 then return FL.newestFirst(feed) end
  local all = {}
  for _, e in ipairs(feed) do all[#all + 1] = { e = e, n = #all } end
  for _, e in ipairs(mem) do all[#all + 1] = { e = e, n = #all } end
  table.sort(all, function(x, y)
    if x.e.at ~= y.e.at then return x.e.at < y.e.at end
    return x.n < y.n
  end)
  local merged = {}
  for _, x in ipairs(all) do FL.add(merged, x.e) end
  return FL.newestFirst(merged)
end

function Feed.count() return #Feed.entries() end

function Feed.clear()
  local feed = list()
  if not feed then return end
  for i = #feed, 1, -1 do feed[i] = nil end
  mem = {}
  ns.Bus.fire("FEED_CHANGED")
end

-- The test tools' fakes are never saved (they live in `mem`): Clear test stuff and the logout scrub drop them.
function Feed.removeFakes()
  if #mem == 0 then return false end
  mem = {}
  ns.Bus.fire("FEED_CHANGED")
  return true
end

local function onEnable()
  gate = FL.newGate(loadedAt + ns.Config.LOGIN_QUIET)
  if ns.db then ns.db.feed = FL.repair(ns.db.feed) end
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", onOnline)
  ns.Bus.on(FEATURE, "MEMBER_OFFLINE", onOffline)
  ns.Bus.on(FEATURE, "MEMBER_DIED", onDied)
  ns.Bus.on(FEATURE, "MEMBER_LEVELUP", onLevelUp)
  ns.Bus.on(FEATURE, "MOCK_SEEN", onMock)
  ns.Bus.on(FEATURE, "ROAST_SHOWN", onRoast)
  local function refresh() if ns.Recent then ns.Recent.refresh() end end
  ns.Bus.on(FEATURE, "FEED_ADDED", refresh)
  ns.Bus.on(FEATURE, "FEED_CHANGED", refresh)
end

local function onDisable()
  gate = nil
end

local function chatSetting(key, label, info)
  return { key = key, label = label, kind = "toggle", parent = "chat", info = info }
end

ns.Modules.register({
  id = FEATURE, name = "Activity feed", tier = "module",
  info = "Keeps a list of what happened lately with your crew: who came online or went offline, who died, who "
    .. "reached a level, the congrats and mocks (with the words) and the roasts you saw. Open it with /tc recent. "
    .. "It can also write each event in your chat window, and it is what the minimized panel shows on its bar. "
    .. "It stays on your computer: nothing is sent to anyone.",
  defaults = { chat = true, chatOnline = false, chatOffline = false, chatDied = true, chatLevel = true,
    chatCongrats = true, chatMock = true, chatRoast = false },
  settings = {
    { key = "chat", label = "Write events in my chat", kind = "toggle",
      info = "Writes one line in your own chat window for each event below, like \"TwizCrew: Frostie reached "
        .. "level 13\" or what someone said in a congrats. Only you see these lines, nobody else, and nothing is "
        .. "typed for you. It works whether the panel is minimized or not. Turn it off to keep chat clean." },
    chatSetting("chatDied", "Deaths in chat", "Writes a line when a friend dies, with the place."),
    chatSetting("chatLevel", "Level-ups in chat", "Writes a line when a friend reaches a new level."),
    chatSetting("chatCongrats", "Congrats in chat", "Writes a line for every congrats you send or get, with the "
      .. "words that were said."),
    chatSetting("chatMock", "Mocks in chat", "Writes a line for every mock you send or get, with the words that "
      .. "were said."),
    chatSetting("chatOnline", "Friends coming online in chat", "Writes a line when a friend starts playing. Off by "
      .. "default because the game already tells you when your friends log in."),
    chatSetting("chatOffline", "Friends going offline in chat", "Writes a line when a friend stops playing. Off by "
      .. "default so chat stays quiet."),
    chatSetting("chatRoast", "Roasts in chat", "Writes a line for every roast that pops up on your screen (like "
      .. "someone dying to a very low level mob). Off by default because there can be a lot of them."),
    { key = "openRecent", label = "Show recent activity", kind = "button",
      onClick = function() if ns.Recent then ns.Recent.open() end end,
      info = "Opens a small window with the list of recent events, newest first. Also: /tc recent, or the wrench "
        .. "menu on the panel, or the number on the minimized panel's bar." },
    { key = "clearRecent", label = "Clear the list", kind = "button", onClick = function() Feed.clear() end,
      info = "Empties the list of recent events." },
  },
  onEnable = onEnable,
  onDisable = onDisable,
})

-- Test hooks.
Feed.forTest = {
  gate = function() return gate end,
  colorWrap = colorWrap,
}
