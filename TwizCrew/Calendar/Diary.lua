-- Crew calendar, the data (module "calendar"): each copy keeps a diary of its own play time (which 15-minute
-- slots you were online, and AFK, per day) and swaps diaries with the crew, passing on what it heard about others
-- too, so you see a friend's evening even when you weren't online. A person = a WoW account (its saved data is
-- shared by all its characters), so alts count as one person.
--
-- Messages (all small; each day travels as its own field, so long diaries split cleanly into several pieces):
--   CALD  digest: p<id> = slots I know for that person over the last KEEP_DAYS days (to everyone every few
--         minutes, and to a friend who just came online); di = my id and d<utcDay> = on[:afk] = my own slots
--         today and yesterday (v0.1.23 ignores both), so friends see my evening without asking for my diary
--   CALQ  "send me person i" (to one friend whose digest shows more than I know; only ever pulled, never pushed);
--         n=1 = "send me your notes" (b = only these buckets: see Notes.lua)
--   CALP  one person's diary: i = id, n = name, c = class, a = alts "Name:CLASS,...", d<utcDay> = on[:afk]
-- Merging only ever adds slots (masks are OR-ed), so the order things arrive in never matters.
local _, ns = ...

local Diary = {}
ns.Diary = Diary

local FEATURE = "calendar"
local L = ns.CalendarLogic
local KEEP_DAYS = 30
local TICK = 60            -- seconds between marks of "I'm online now"
local DIGEST_EVERY = 600   -- seconds between digests to everyone
local FIRST_DIGEST = 20    -- after login
local SEND_GAP = 120       -- seconds before the same person's diary goes to the same friend again
local ASK_GAP = 120
local ALTS_BYTES = 150     -- a diary's alts list, as it travels (so the codec never cuts it)

local enabled = false
local ticker, digestTicker
local notesPrunedDay -- the UTC day the notes were last pruned (once a day while logged in)
local sentAt, askedAt = {}, {}

local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function now()
  if type(GetServerTime) == "function" then
    local ok, t = pcall(GetServerTime)
    if ok and type(t) == "number" and t > 0 then return t end
  end
  return time()
end
Diary.now = now

local function store()
  local db = ns.db
  if not db then return nil end
  if type(db.calendar) ~= "table" then db.calendar = {} end
  local c = db.calendar
  if type(c.people) ~= "table" then c.people = {} end
  if type(c.me) ~= "string" or not c.me:match("^%w+$") then
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local id = {}
    for i = 1, 8 do local k = math.random(#chars); id[i] = chars:sub(k, k) end
    c.me = table.concat(id)
  end
  return c
end

local function today() return math.floor(now() / L.DAY) end

-- Seconds to add to UTC for this computer's local time at moment t (now: Diary.offset), and today's local day number.
local function offsetAt(t)
  local ok1, loc = pcall(date, "*t", t)
  local ok2, utc = pcall(date, "!*t", t)
  if ok1 and ok2 then return L.offsetFrom(loc, utc) end
  return 0
end
function Diary.offset() return offsetAt(now()) end

-- The local offset on local day `day` (a clock change moves it: a day after the change is shown with its own
-- offset, not today's). Taken at the day's noon, so the evening of the day a clock changes (at night) is right.
-- Cached by day; the cache starts over when this computer's current offset changes.
local offsets, offsetsFor = {}, nil
function Diary.offsetOn(day)
  local cur = Diary.offset()
  if cur ~= offsetsFor then offsets, offsetsFor = {}, cur end
  day = tonumber(day)
  if not day then return cur end
  local off = offsets[day]
  if not off then
    off = offsetAt(day * L.DAY + L.DAY / 2 - cur)
    offsets[day] = off
  end
  return off
end

-- The UTC time of a local date and clock time (minutes after midnight), with that date's own offset.
function Diary.utcOf(day, minutes)
  local y, m, d = L.civil(day)
  local ok, t = pcall(time, { year = y, month = m, day = d, hour = math.floor(minutes / 60), min = minutes % 60 })
  if ok and type(t) == "number" then return t end
  return day * L.DAY + minutes * 60 - Diary.offsetOn(day)
end

function Diary.localToday() return math.floor((now() + Diary.offset()) / L.DAY) end
local function oldest() return today() - KEEP_DAYS + 1 end

local function person(id)
  local c = store()
  if not c or type(id) ~= "string" or not id:match("^%w+$") or #id > 16 then return nil end
  local p = c.people[id]
  if type(p) ~= "table" then p = { days = {}, alts = {} }; c.people[id] = p end
  if type(p.days) ~= "table" then p.days = {} end
  if type(p.alts) ~= "table" then p.alts = {} end
  return p
end

function Diary.myId() local c = store(); return c and c.me end

-- Everyone we know, { [id] = { name, class, alts, days } } (the saved table itself: don't change it).
function Diary.people()
  local c = store()
  return c and c.people or {}
end

------------------------------------------------------------------------------------------------- my own diary
local function iAmAway()
  if ns.Away and ns.Away.isAway and ns.Away.isAway() then return true end
  -- a secret answer (dungeons) can't even be compared: plain makes it nil, which counts as "not away"
  return ns.Util.plain(UnitIsAFK, "player") == true
end

-- Marks "online now" (and AFK) in my diary. t: a time for tests.
function Diary.mark(t)
  t = t or now()
  local p = person(Diary.myId())
  if not p then return end
  local name = ns.playerName()
  local _, class = UnitClass("player")
  if type(name) == "string" and name ~= "" then
    p.name = name
    if type(class) == "string" then p.class = class; p.alts[name] = class end
  end
  local s = math.floor(t / L.SLOT)
  local day, idx = math.floor(s / L.SLOTS_PER_DAY), s % L.SLOTS_PER_DAY
  local d = p.days[day]
  if type(d) ~= "table" then d = {}; p.days[day] = d end
  d.on = L.set(d.on, idx)
  if iAmAway() then d.afk = L.set(d.afk, idx) end
end

-- Old days and people with nothing left go away.
function Diary.prune()
  local c = store()
  if not c then return end
  local from = oldest()
  for id, p in pairs(c.people) do
    if type(p) ~= "table" or type(p.days) ~= "table" then
      c.people[id] = nil
    else
      for day in pairs(p.days) do if type(day) ~= "number" or day < from then p.days[day] = nil end end
      if next(p.days) == nil and id ~= c.me then c.people[id] = nil end
    end
  end
end

------------------------------------------------------------------------------------------------- sharing
local function sharedIds()
  local c = store()
  local out = {}
  if not c then return out end
  for id in pairs(c.people) do
    if id ~= c.me or setting("share") ~= false then out[#out + 1] = id end
  end
  return out
end

-- A day as it travels: "on" or "on:afk".
local function dayText(d) return d.afk and L.clean(d.afk) and (d.on .. ":" .. d.afk) or d.on end

local function digestFields()
  local from, f = oldest(), {}
  for _, id in ipairs(sharedIds()) do
    local n = L.total(Diary.people()[id].days, from)
    if n > 0 then f["p" .. id] = tostring(n) end
  end
  if setting("share") ~= false then
    local me = Diary.people()[Diary.myId()]
    for day = today() - 1, today() do
      local d = me and me.days[day]
      if type(d) == "table" and L.clean(d.on) then f["d" .. day] = dayText(d); f.di = Diary.myId() end
    end
  end
  if ns.Notes then ns.Notes.digestFields(f) end
  return f
end

local function sendTo(name, msgType, fields, opts)
  if name then
    if not ns.Comm.sendTo(name, msgType, fields, opts) then ns.Comm.send(msgType, fields, opts) end
  else
    ns.Comm.send(msgType, fields, opts)
  end
end

function Diary.sendDigest(to)
  if not enabled then return end
  local f = digestFields()
  if next(f) == nil then return end
  sendTo(to, "CALD", f)
end

local function personFields(id)
  local p = Diary.people()[id]
  if type(p) ~= "table" then return nil end
  local f = { i = id, n = p.name, c = p.class }
  local alts = {}
  for name, class in pairs(p.alts or {}) do alts[#alts + 1] = tostring(name) .. ":" .. tostring(class) end
  table.sort(alts)
  -- whole alts only, as many as fit ALTS_BYTES as they travel (the codec would cut one in half)
  local size, keep = 0, {}
  for _, a in ipairs(alts) do
    size = size + ns.Codec.size(a) + (#keep > 0 and 1 or 0)
    if size > ALTS_BYTES then break end
    keep[#keep + 1] = a
  end
  if #keep > 0 then f.a = table.concat(keep, ",") end
  local from = oldest()
  for day, d in pairs(p.days) do
    if day >= from and L.clean(d.on) then f["d" .. day] = dayText(d) end
  end
  return f
end

function Diary.sendPerson(id, to)
  if not enabled then return end
  local c = store()
  if id == c.me and setting("share") == false then return end
  local key = id .. ">" .. tostring(to)
  local t = ns.now()
  if sentAt[key] and t - sentAt[key] < SEND_GAP then return end
  local f = personFields(id)
  if not f then return end
  sentAt[key] = t
  sendTo(to, "CALP", f, { repeatKeys = { "i" }, bulk = true })
end

local function known(sender)
  return type(sender) == "string" and not ns.isMe(sender) and not ns.isTestName(sender) and ns.roster
    and ns.roster:get(sender) ~= nil
end

-- Merges the d<utcDay> = on[:afk] fields of f for days first..last into person p (masks are OR-ed). Returns true
-- when any arrived.
local function mergeDays(p, f, first, last)
  local changed = false
  for k, v in pairs(f) do
    local day = type(k) == "string" and tonumber(k:match("^d(%d+)$"))
    if day and day >= first and day <= last and type(v) == "string" then
      local on, afk = v:match("^([^:]+):?(.*)$")
      on, afk = L.clean(on), L.clean(afk)
      if on then
        local d = p.days[day]
        if type(d) ~= "table" then d = {}; p.days[day] = d end
        d.on = L.merge(d.on, on)
        if afk then d.afk = L.merge(d.afk, afk) end
        changed = true
      end
    end
  end
  return changed
end

-- Slots on in the days of `days` (a { [day] = true } set): in a stored record, or in the d<day> fields of a message.
local function slotsIn(record, days)
  local n = 0
  for day in pairs(days) do local d = record[day]; if type(d) == "table" then n = n + L.count(d.on) end end
  return n
end
local function slotsSent(f, days)
  local n = 0
  for day in pairs(days) do
    local v = f["d" .. day]
    local on = type(v) == "string" and L.clean(v:match("^([^:]+)"))
    if on then n = n + L.count(on) end
  end
  return n
end

local function onDigest(sender, f)
  if not enabled or not known(sender) or type(f) ~= "table" then return end
  local from = oldest()
  local people = Diary.people()
  -- the sender's own slots of today and yesterday: merged at once, and left out of the comparison below, so a friend
  -- who is online (their diary grows every 15 minutes) is not asked for their whole diary at every digest. Only for
  -- someone we already know: a new friend is asked for their diary as before.
  local who = type(f.di) == "string" and f.di ~= Diary.myId() and people[f.di]
  local recent
  if type(who) == "table" and type(who.name) == "string" then
    recent = { [today() - 1] = true, [today()] = true }
    if mergeDays(who, f, today() - 1, today()) then ns.Bus.fire("CALENDAR_CHANGED") end
  end
  -- notes: different checksums mean they have notes (or deletions) we don't: ask for theirs (only the buckets
  -- that differ, when their digest says which)
  local ask = ns.Notes and ns.Notes.askFor(f, sender)
  if ask then
    if not askedAt["notes"] or ns.now() - askedAt["notes"] >= ASK_GAP then
      askedAt["notes"] = ns.now()
      sendTo(sender, "CALQ", ask)
      ns.Notes.asked(sender, f, ask)
    end
  end
  for k, v in pairs(f) do
    local id = type(k) == "string" and k:match("^p(%w+)$")
    local theirs = tonumber(v)
    if id and theirs then
      local mine = people[id] and L.total(people[id].days, from) or 0
      if recent and id == f.di then
        theirs = theirs - slotsSent(f, recent)
        mine = mine - slotsIn(people[id].days, recent)
      end
      -- they know more: ask them (once per person for a while, whoever offers it first). Nobody pushes diaries
      -- unasked, so a friend logging in doesn't get the same diary from everyone at once.
      if theirs > mine and id ~= Diary.myId() then
        if not askedAt[id] or ns.now() - askedAt[id] >= ASK_GAP then
          askedAt[id] = ns.now()
          sendTo(sender, "CALQ", { i = id })
        end
      end
    end
  end
end

local function onAsk(sender, f)
  if not enabled or not known(sender) or type(f) ~= "table" then return end
  if f.n == "1" and ns.Notes then ns.Notes.sendAll(sender, f.b) end
  if type(f.i) == "string" and Diary.people()[f.i] then Diary.sendPerson(f.i, sender) end
end

local function onPerson(sender, f)
  if not enabled or not known(sender) or type(f) ~= "table" then return end
  local id = f.i
  if type(id) ~= "string" or id == Diary.myId() then return end -- my own diary is only ever written by me
  local p = person(id)
  if not p then return end
  if type(f.n) == "string" and f.n ~= "" then p.name = ns.Util.truncateUTF8(ns.Util.safeText(f.n), 24) end
  if type(f.c) == "string" and f.c:match("^%u+$") then p.class = f.c end
  if type(f.a) == "string" then
    for name, class in f.a:gmatch("([^,:]+):(%u+)") do p.alts[ns.Util.truncateUTF8(name, 24)] = class end
  end
  if mergeDays(p, f, oldest(), today() + 1) then ns.Bus.fire("CALENDAR_CHANGED") end
end

ns.Comm.on("CALD", function(s, f) ns.Log.safe(FEATURE, onDigest, s, f) end)
ns.Comm.on("CALQ", function(s, f) ns.Log.safe(FEATURE, onAsk, s, f) end)
ns.Comm.on("CALP", function(s, f) ns.Log.safe(FEATURE, onPerson, s, f) end)
ns.Comm.on("CALN", function(s, f)
  ns.Log.safe(FEATURE, function()
    if enabled and known(s) and ns.Notes then ns.Notes.receive(s, f) end
  end)
end)
ns.Comm.on("CALR", function(s, f)
  ns.Log.safe(FEATURE, function()
    if enabled and known(s) and ns.Notes then ns.Notes.receiveReply(s, f) end
  end)
end)

------------------------------------------------------------------------------------------------- module
local function pruneNotes()
  if not ns.Notes or notesPrunedDay == today() then return end
  notesPrunedDay = today()
  ns.Notes.prune()
end

local function tick()
  Diary.mark()
  ns.Bus.fire("CALENDAR_CHANGED")
end

local function onEnable()
  enabled = true
  store()
  Diary.prune()
  notesPrunedDay = nil
  pruneNotes()
  Diary.mark()
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, tick) end)
    digestTicker = C_Timer.NewTicker(DIGEST_EVERY, function() ns.Log.safe(FEATURE, function()
      Diary.prune()
      pruneNotes()
      Diary.sendDigest()
    end) end)
    C_Timer.After(FIRST_DIGEST, function() ns.Log.safe(FEATURE, Diary.sendDigest) end)
  end
  ns.Bus.on(FEATURE, "CALENDAR_CHANGED", function()
    if ns.Calendar and ns.Calendar.isShown() then ns.Calendar.refresh() end
    if ns.NoteView and ns.NoteView.isShown() then ns.NoteView.refresh() end
  end)
  -- a friend just came online: tell them what we know (a little later, so their copy is ready)
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", function(name)
    if ns.isTestName(name) then return end -- pretend friends (test tools) hear nothing
    if C_Timer and C_Timer.After then
      C_Timer.After(5 + math.random() * 10, function() ns.Log.safe(FEATURE, Diary.sendDigest, name) end)
    end
  end)
end

local function onDisable()
  enabled = false
  if ticker then ticker:Cancel(); ticker = nil end
  if digestTicker then digestTicker:Cancel(); digestTicker = nil end
end

ns.Modules.register({
  id = FEATURE, name = "Crew calendar", tier = "module",
  info = "A calendar of who played when: each copy notes when you're online (in 15-minute steps) and swaps that "
    .. "with the crew, so you can see who was on each day and when most of you usually play. Open it with the "
    .. "wrench button on the panel or /tc cal.",
  defaults = { share = true },
  settings = {
    { key = "open", label = "Open the crew calendar", kind = "button",
      onClick = function() if ns.Calendar then ns.Calendar.open() end end,
      info = "Who played on each day, a day's timeline, and the times most of the crew usually plays." },
    { key = "share", label = "Share my play times", kind = "toggle",
      info = "Lets the crew see when you were online (only the times, never where you were). Off: your copy still "
        .. "keeps your own diary, and you still see your friends'." },
  },
  onEnable = onEnable,
  onDisable = onDisable,
})

-- Test hooks
function Diary.forTest() return { store = store, today = today, oldest = oldest } end
