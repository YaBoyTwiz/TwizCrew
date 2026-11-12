-- Pure rules of the activity feed (module "activity"): the words of every kind of event, which events are worth
-- recording (the same quiet time and "quick /reload is not news" rules the pop-ups use), the capped list, the
-- queue of notices on a minimized panel's bar, the missed counter, and which events print a line in chat.
-- No frames and no game calls here (Feed.lua owns those).
local _, ns = ...

local FeedLogic = {}
ns.FeedLogic = FeedLogic

FeedLogic.MAX = 50       -- entries kept (newest)
FeedLogic.WORDS_MAX = 120 -- letters of someone's words kept in a line (congrats / mock text)
FeedLogic.RELOG = 120    -- seconds: back online sooner than this is a /reload or quick relog (same as the pop-ups)

-- Kinds, in the order the settings list them.
FeedLogic.KINDS = { "online", "offline", "died", "levelup", "congrats", "mock", "roast" }
local KNOWN = {}
for _, k in ipairs(FeedLogic.KINDS) do KNOWN[k] = true end
function FeedLogic.isKind(kind) return KNOWN[kind] == true end

-- The chat switch of each kind (setting keys of module "activity"); "chat" is the master switch.
FeedLogic.CHAT_KEY = { online = "chatOnline", offline = "chatOffline", died = "chatDied", levelup = "chatLevel",
  congrats = "chatCongrats", mock = "chatMock", roast = "chatRoast" }

---------------------------------------------------------------------------------------------------------- text
local function secret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, yes = pcall(issecretvalue, v)
  return not ok or yes == true
end

-- Plain text from anything: "" for a secret value or a non-string; control characters out; at most `max` letters.
-- Not yet escaped (see safe).
function FeedLogic.clean(v, max)
  if type(v) ~= "string" or secret(v) then return "" end
  v = ns.Util.trim((v:gsub("[%z\1-\31]", " ")))
  return ns.Util.truncateUTF8(v, max or FeedLogic.WORDS_MAX)
end

-- clean + the "|" doubled (the way every shown text in the addon is made safe).
function FeedLogic.safe(v, max)
  return ns.Util.safeText(FeedLogic.clean(v, max))
end

-- Text that was already made safe by someone else (a roast line): back to plain, then cleaned again.
function FeedLogic.resafe(v, max)
  if type(v) ~= "string" then return "" end
  return FeedLogic.safe((v:gsub("||", "|")), max)
end

local function identity(name) return name end

local function quoted(words)
  if type(words) ~= "string" or words == "" then return "" end
  return ': "' .. words .. '"'
end

-- The ready-to-show line. kind: one of KINDS. who: the friend it is about (for congrats and mocks: the other
-- person; me = "you"). extra: { zone, subzone, level, words, dir = "out" | "in" | "seen", other (the friend a "seen"
-- one is about), text (roasts: the whole line) }. colorName(name) wraps a name for display (default: as it is).
function FeedLogic.line(kind, who, extra, colorName)
  colorName = colorName or identity
  extra = extra or {}
  who = type(who) == "string" and who or "?"
  if kind == "online" then
    local zone = (type(extra.zone) == "string" and extra.zone ~= "") and extra.zone or nil
    return colorName(who) .. " came online" .. (zone and (" in " .. zone) or "")
  elseif kind == "offline" then
    return colorName(who) .. " went offline"
  elseif kind == "died" then
    local zone = (type(extra.zone) == "string" and extra.zone ~= "") and extra.zone or nil
    local sub = (type(extra.subzone) == "string" and extra.subzone ~= "") and extra.subzone or nil
    local place = zone and sub and (zone .. ", " .. sub) or zone or sub
    return colorName(who) .. " died" .. (place and (" in " .. place) or "")
  elseif kind == "levelup" then
    local lv = tonumber(extra.level)
    if not lv then return colorName(who) .. " leveled up" end
    return colorName(who) .. " reached level " .. math.floor(lv)
  elseif kind == "congrats" or kind == "mock" then
    local verb = kind == "congrats" and "congratulated" or "mocked"
    local words = quoted(extra.words)
    if extra.dir == "out" then return "You " .. verb .. " " .. colorName(who) .. words end
    if extra.dir == "in" then return colorName(who) .. " " .. verb .. " you" .. words end
    local other = type(extra.other) == "string" and extra.other ~= "" and extra.other or nil
    return colorName(who) .. " " .. verb .. " " .. (other and colorName(other) or "a friend") .. words
  elseif kind == "roast" then
    return type(extra.text) == "string" and extra.text or (colorName(who) .. " got roasted")
  end
  return colorName(who)
end

-- One saved / shown entry from the facts of an event. Everything in it is plain text or a number (it is saved).
-- at: wall-clock seconds. class: the friend's class token when known.
function FeedLogic.entry(kind, who, extra, at, class)
  if not KNOWN[kind] then return nil end
  extra = extra or {}
  local e = {
    kind = kind, who = FeedLogic.safe(who, 40), at = tonumber(at) or 0, dir = extra.dir,
    zone = extra.zone and FeedLogic.safe(extra.zone, 60) or nil,
    subzone = extra.subzone and FeedLogic.safe(extra.subzone, 60) or nil,
    level = tonumber(extra.level), words = extra.words and FeedLogic.safe(extra.words) or nil,
    other = extra.other and FeedLogic.safe(extra.other, 40) or nil,
    text = extra.text and FeedLogic.resafe(extra.text, 200) or nil,
    class = type(class) == "string" and class ~= "" and FeedLogic.clean(class, 20) or nil,
  }
  if e.dir ~= "out" and e.dir ~= "in" and e.dir ~= "seen" then e.dir = nil end
  e.line = FeedLogic.line(kind, e.who, e)
  return e
end

-- The entry's line with the names coloured (for the bar and chat).
function FeedLogic.coloredLine(e, colorName)
  return FeedLogic.line(e.kind, e.who, e, colorName)
end

-- Words for "when": a relative time, a bit older = "5m ago".
function FeedLogic.ago(at, nowWall)
  at, nowWall = tonumber(at), tonumber(nowWall)
  if not at or not nowWall then return "" end
  return ns.Util.ago(math.max(0, nowWall - at))
end

---------------------------------------------------------------------------------------------------------- list
-- Newest entries are last in the saved array. add() keeps the newest MAX. Returns the entry.
function FeedLogic.add(list, e)
  list[#list + 1] = e
  local extra = #list - FeedLogic.MAX
  if extra > 0 then
    for i = 1, #list - extra do list[i] = list[i + extra] end
    for i = #list, #list - extra + 1, -1 do list[i] = nil end
  end
  return e
end

-- Newest first, as a new array.
function FeedLogic.newestFirst(list)
  local out = {}
  for i = #list, 1, -1 do out[#out + 1] = list[i] end
  return out
end

-- Saved data from an old or broken file: only well-formed entries stay, at most MAX of them.
function FeedLogic.repair(list)
  if type(list) ~= "table" then return {} end
  local kept = {}
  for i = 1, table.maxn(list) do
    local e = list[i]
    if type(e) == "table" and KNOWN[e.kind] and type(e.line) == "string" and tonumber(e.at) and type(e.who) == "string" then
      kept[#kept + 1] = e
    end
  end
  for k in pairs(list) do list[k] = nil end
  for _, e in ipairs(kept) do FeedLogic.add(list, e) end
  return list
end

---------------------------------------------------------------------------------------------------------- gate
-- Which events are recorded: the same rules the pop-ups use. Quiet time after login (online, offline, died,
-- level-up are dropped), and a friend back online within RELOG s of going offline is a /reload, not news.
-- A test tools' fake ("(test)") counts only when a test button expects it, and then past both rules.
local Gate = {}
Gate.__index = Gate

function FeedLogic.newGate(quietUntil)
  return setmetatable({ quietUntil = tonumber(quietUntil) or 0, offlineAt = {} }, Gate)
end

local QUIET_KINDS = { online = true, offline = true, died = true, levelup = true }

function Gate:noteOffline(name, now) self.offlineAt[name] = now end

-- Would allow() say yes? (Changes nothing.)
function Gate:wouldAllow(kind, name, now, testWanted)
  if testWanted ~= nil then return testWanted == true end
  if QUIET_KINDS[kind] and now < self.quietUntil then return false end
  if kind == "online" then
    local gone = self.offlineAt[name]
    if gone and now - gone < FeedLogic.RELOG then return false end
  end
  return true
end

-- testWanted: nil = a real friend; true / false = a fake, and whether a test button expects this event.
function Gate:allow(kind, name, now, testWanted)
  if testWanted ~= nil then
    if kind == "online" then self.offlineAt[name] = nil end
    return testWanted == true
  end
  if kind == "online" then
    local gone = self.offlineAt[name]
    self.offlineAt[name] = nil
    if now < self.quietUntil then return false end
    if gone and now - gone < FeedLogic.RELOG then return false end
    return true
  end
  if QUIET_KINDS[kind] and now < self.quietUntil then return false end
  return true
end

---------------------------------------------------------------------------------------------------------- chat
-- Does this kind print a line in chat? settings: the activity module's settings.
function FeedLogic.chatWanted(settings, kind)
  settings = settings or {}
  local key = FeedLogic.CHAT_KEY[kind]
  if not key then return false end
  return settings.chat == true and settings[key] == true
end

-- "TwizCrew: " then the coloured line. The prefix colour is a plain hex like "ffd100".
function FeedLogic.chatText(e, colorName, prefixHex)
  local prefix = prefixHex and ("|cff" .. prefixHex .. "TwizCrew:|r ") or "TwizCrew: "
  return prefix .. FeedLogic.coloredLine(e, colorName)
end

---------------------------------------------------------------------------------------------------------- bar notices
-- The events a minimized panel's bar shows: online, died, level-up, and congrats / mocks that came to ME.
function FeedLogic.isNoticeKind(e)
  if type(e) ~= "table" then return false end
  local k = e.kind
  if k == "online" or k == "died" or k == "levelup" then return true end
  return (k == "congrats" or k == "mock") and e.dir == "in"
end

-- Is the pop-up of this kind (the pop-ups module's own names) replaced by the bar right now?
-- ctx: { minimized, barShown (the bar is on screen and shows notices), setting (the "show these on the bar instead
-- of pop-ups" switch), feedTakes (the activity feed will record this event, so the bar will have it) }. Only the pop-ups the bar shows (online, death, levelup) are suppressed.
local POPUP_FEED = { online = "online", death = "died", levelup = "levelup" }
function FeedLogic.suppressesPopup(popupKind, ctx)
  ctx = ctx or {}
  if not POPUP_FEED[popupKind] then return false end
  return ctx.minimized == true and ctx.barShown == true and ctx.setting == true and ctx.feedTakes == true
end
FeedLogic.POPUP_FEED = POPUP_FEED

-- The notice queue and the "missed" counter of a minimized bar.
-- opts: seconds (a notice stays), short (it stays only this long when several wait behind it), max (waiting at most;
-- the oldest waiting one is dropped past that).
local Bar = {}
Bar.__index = Bar

function FeedLogic.newBar(opts)
  opts = opts or {}
  return setmetatable({
    seconds = opts.seconds or 6, short = opts.short or 3, max = opts.max or 8,
    queue = {}, active = nil, missed = 0,
  }, Bar)
end

local function start(self, entry, now)
  self.active = { entry = entry, from = now, flashFrom = now }
end

function Bar:endsAt()
  local a = self.active
  if not a then return nil end
  local len = #self.queue >= 2 and math.min(self.seconds, self.short) or self.seconds
  return a.from + len
end

-- A new notice: shows at once when the bar is free, else waits its turn. Returns whether it started now, and the
-- waiting notice that took over (if any) while the bar caught up with the clock first.
function Bar:push(entry, now)
  local took, moved = self:tick(now)
  local promoted = moved and took or nil
  if not self.active then
    start(self, entry, now)
    return true, promoted
  end
  self.queue[#self.queue + 1] = entry
  while #self.queue > self.max do table.remove(self.queue, 1) end
  return false, promoted
end

-- Holds the shown notice for `seconds` (the mouse is on the peeked row): its time does not run out meanwhile.
function Bar:delay(seconds)
  if self.active then self.active.from = self.active.from + (tonumber(seconds) or 0) end
end

-- Moves on when the shown notice has had its time. Returns the notice now shown (an entry) or nil, and whether it
-- changed since the last call.
function Bar:tick(now)
  local changed = false
  while self.active and now >= self:endsAt() do
    changed = true
    local endAt = self:endsAt()
    local nextEntry = table.remove(self.queue, 1)
    -- the next one starts when the last one ended, not later (a late tick must not stretch the queue)
    if nextEntry then start(self, nextEntry, endAt) else self.active = nil end
  end
  return self.active and self.active.entry or nil, changed
end

-- A click on the shown notice: it is done with; the next one (if any) starts now. Returns the one shown now (or nil).
function Bar:dismiss(now)
  if not self.active then return nil end
  local nextEntry = table.remove(self.queue, 1)
  if nextEntry then start(self, nextEntry, now) else self.active = nil end
  return self.active and self.active.entry or nil
end

function Bar:current() return self.active and self.active.entry or nil end
function Bar:waiting() return #self.queue end
function Bar:flashAge(now) return self.active and (now - self.active.flashFrom) or nil end
function Bar:addMissed() self.missed = self.missed + 1 end
function Bar:clearMissed() self.missed = 0 end
function Bar:clear() self.queue, self.active = {}, nil end
