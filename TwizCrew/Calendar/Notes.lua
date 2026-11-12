-- Crew calendar notes (part of module "calendar"): click a day, type a note, pick an icon. Notes are shared with
-- the crew and swapped like the play-time diaries, so everyone sees them on that date. Only the author can delete
-- a note (a deleted note stays as a small "deleted" marker for a while, so the deletion reaches everyone).
--
-- A note: key = "<author id>-<created>", d = "2026-11-08" (the author's local date), t = text, i = icon (1-16),
-- b = author's character name, c = class, u = last change (server time), x = true when deleted,
-- at = a time (UTC seconds) for a timed note ("4:30pm"): everyone sees it at their own local time, on their own
-- local date (which can be a different day than the author's).
-- Messages: CALN = one note (to everyone when you add or delete one; to one friend when asked). The CALD digest
-- carries nh = a checksum of all notes (v0.1.23 reads it: a different one means "ask for theirs", CALQ n=1) and
-- nb = BUCKETS short checksums, one per bucket (a note and its replies fall in the bucket its key picks): a copy
-- asks only for the buckets that differ (CALQ n=1 b=3,5) and the answer holds only those buckets.
local _, ns = ...

local Notes = {}
ns.Notes = Notes

local FEATURE = "calendar"
-- Sizes, so a note or a reply always travels as one message (255 bytes) a receiver takes: the words of a note or a
-- comment are counted in bytes as they travel (after the codec's escaping), a name too; keys have a longest length.
Notes.MAX_BYTES = 100
local NAME_BYTES = 24
local MAX_KEY = 24       -- a note's key ("<author id>-<created>": 19 letters as this addon makes them)
local MAX_REPLY_KEY = 50 -- a reply's key ("<note key>|c|<id>-<time>": 41 letters)
local MAX_NOTES = 300    -- live (not deleted) notes counted; deletion markers always count
Notes.MAX_COMMENTS = 30  -- live comments counted per note
local KEEP_DAYS = 90     -- past notes (and deletion markers) are kept this long
local ANSWER_GAP = 60    -- seconds between answers to "send me your notes", whoever asks
Notes.BUCKETS = 8

local B = "Interface\\Icons\\"
Notes.ICONS = {
  { tex = B .. "INV_Misc_Note_01", name = "Note" },
  { tex = B .. "INV_Sword_04", name = "Dungeon" },
  { tex = B .. "INV_Misc_Head_Dragon_01", name = "Raid" },
  { tex = B .. "INV_Shield_06", name = "Tank" },
  { tex = B .. "Spell_Holy_FlashHeal", name = "Healer" },
  { tex = B .. "INV_Misc_Bag_10", name = "Loot" },
  { tex = B .. "INV_Misc_Coin_01", name = "Gold" },
  { tex = B .. "INV_Misc_Map_01", name = "Travel" },
  { tex = B .. "Ability_Mount_RidingHorse", name = "Mount" },
  { tex = B .. "INV_Misc_Gift_01", name = "Fun" },
  { tex = B .. "INV_Drink_05", name = "Chill" },
  { tex = B .. "Spell_Holy_SealOfWisdom", name = "Training" },
  { tex = B .. "Trade_Mining", name = "Professions" },
  { tex = B .. "Ability_Warrior_BattleShout", name = "Crew" },
  { tex = B .. "INV_Misc_PocketWatch_01", name = "Reminder" },
  { tex = B .. "Spell_Shadow_Charm", name = "Important" },
}

-- WoW Forever's dungeons and raids, lowest first. min-max = recommended levels (the nine new dungeons from
-- Blizzard's own data, the classic ones as Forever guides suggest), size = players. ej / lfg = the names the game's
-- artwork files would use (the new dungeons may have none yet: then the note's icon is used).
Notes.DUNGEONS = {
  { key = "rfc", name = "Ragefire Chasm", min = 13, max = 18, ej = "RagefireChasm", lfg = "RagefireChasm" },
  { key = "thanes", name = "Hall of Thanes", min = 13, max = 18, ej = "HallofThanes", lfg = "HallofThanes", new = true },
  { key = "lordaeron", name = "Ruins of Lordaeron", min = 15, max = 20, ej = "RuinsofLordaeron", lfg = "RuinsofLordaeron", new = true },
  { key = "dm", name = "The Deadmines", min = 17, max = 20, ej = "TheDeadmines", lfg = "Deadmines" },
  { key = "wc", name = "Wailing Caverns", min = 18, max = 24, ej = "WailingCaverns", lfg = "WailingCaverns" },
  { key = "sfk", name = "Shadowfang Keep", min = 21, max = 26, ej = "ShadowfangKeep", lfg = "ShadowfangKeep" },
  { key = "bfd", name = "Blackfathom Deeps", min = 23, max = 28, ej = "BlackfathomDeeps", lfg = "BlackfathomDeeps" },
  { key = "excavation", name = "Excavation Site", min = 24, max = 29, ej = "ExcavationSite", lfg = "ExcavationSite", new = true },
  { key = "stocks", name = "The Stockade", min = 25, max = 29, ej = "TheStockade", lfg = "StormwindStockades" },
  { key = "dalaran", name = "City of Dalaran", min = 28, max = 33, ej = "CityofDalaran", lfg = "CityofDalaran", new = true },
  { key = "gnomer", name = "Gnomeregan", min = 29, max = 34, ej = "Gnomeregan", lfg = "Gnomeregan" },
  { key = "rfk", name = "Razorfen Kraul", min = 30, max = 38, ej = "RazorfenKraul", lfg = "RazorfenKraul" },
  { key = "sm", name = "Scarlet Monastery", min = 30, max = 46, ej = "ScarletMonastery", lfg = "ScarletMonastery" },
  { key = "drowned", name = "The Drowned City", min = 35, max = 40, ej = "TheDrownedCity", lfg = "TheDrownedCity", new = true },
  { key = "ulda", name = "Uldaman", min = 37, max = 45, ej = "Uldaman", lfg = "Uldaman" },
  { key = "rfd", name = "Razorfen Downs", min = 37, max = 45, ej = "RazorfenDowns", lfg = "RazorfenDowns" },
  { key = "zf", name = "Zul'Farrak", min = 40, max = 47, ej = "ZulFarrak", lfg = "ZulFarak" },
  { key = "kroldok", name = "Krol'dok Stronghold", min = 40, max = 45, ej = "KroldokStronghold", lfg = "KroldokStronghold", new = true },
  { key = "mara", name = "Maraudon", min = 45, max = 51, ej = "Maraudon", lfg = "Maraudon" },
  { key = "alcaz", name = "Alcaz Prison", min = 48, max = 53, ej = "AlcazPrison", lfg = "AlcazPrison", new = true },
  { key = "st", name = "Sunken Temple", min = 50, max = 55, ej = "TheTempleOfAtalHakkar", lfg = "SunkenTemple" },
  { key = "brd", name = "Blackrock Depths", min = 52, max = 60, ej = "BlackrockDepths", lfg = "BlackrockDepths" },
  { key = "blackmaw", name = "Blackmaw Hold", min = 55, max = 60, ej = "BlackmawHold", lfg = "BlackmawHold", new = true },
  { key = "lbrs", name = "Blackrock Spire", min = 57, max = 60, ej = "BlackrockSpire", lfg = "BlackrockSpire" },
  { key = "shaper", name = "Shaper's Terrace", min = 58, max = 60, ej = "ShapersTerrace", lfg = "ShapersTerrace", new = true },
  { key = "dmaul", name = "Dire Maul", min = 58, max = 60, ej = "DireMaul", lfg = "DireMaul" },
  { key = "strat", name = "Stratholme", min = 58, max = 60, ej = "Stratholme", lfg = "Stratholme" },
  { key = "scholo", name = "Scholomance", min = 58, max = 60, ej = "Scholomance", lfg = "Scholomance" },
  { key = "barrow", name = "Barrow Deeps", min = 60, max = 60, size = 10, ej = "BarrowDeeps", lfg = "BarrowDeeps", raid = true, new = true },
  { key = "hyjal", name = "Hyjal Summit", min = 60, max = 60, size = 20, ej = "HyjalSummit", lfg = "HyjalSummit", raid = true, new = true },
  { key = "ony", name = "Onyxia's Lair", min = 60, max = 60, size = 40, ej = "OnyxiasLair", lfg = "OnyxiasLair", raid = true },
}

-- "17-26" / "60"
function Notes.levelText(d)
  if not d or not d.min then return "" end
  if d.min == d.max then return tostring(d.min) end
  return d.min .. "-" .. d.max
end

-- How a dungeon's levels look for someone at `level`: "low" (too easy), "ok", "high" (too hard yet).
function Notes.levelFit(d, level)
  level = tonumber(level)
  if not d or not d.min or not level then return "ok" end
  if level > d.max + 2 then return "low" end
  if level < d.min - 2 then return "high" end
  return "ok"
end

-- "Level 17-26 · 5 players"
function Notes.dungeonLine(d)
  if not d then return "" end
  return "Level " .. Notes.levelText(d) .. " \194\183 " .. (d.size or 5) .. " players"
end
local DUNGEON = {}
for _, d in ipairs(Notes.DUNGEONS) do DUNGEON[d.key] = d end
function Notes.dungeon(key) return DUNGEON[key] end

-- The small square icon files to try for a dungeon (menus), best first.
function Notes.dungeonIcons(key)
  local d = DUNGEON[key]
  if not d then return {} end
  return { "Interface\\LFGFrame\\LFGIcon-" .. d.lfg }
end

-- The artwork files to try for a dungeon, best first.
function Notes.dungeonImages(key)
  local d = DUNGEON[key]
  if not d then return {} end
  return { "Interface\\EncounterJournal\\UI-EJ-DungeonButton-" .. d.ej, "Interface\\LFGFrame\\LFGIcon-" .. d.lfg,
    "Interface\\Glues\\LoadingScreens\\LoadScreen" .. d.lfg }
end

local answeredAt

local function store()
  local db = ns.db
  if not db then return nil end
  if type(db.calendar) ~= "table" then db.calendar = {} end
  if type(db.calendar.notes) ~= "table" then db.calendar.notes = {} end
  return db.calendar.notes
end

function Notes.dateKey(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end

local function dayOfKey(key)
  local y, m, d = tostring(key):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return nil end
  return ns.CalendarLogic.daysFrom(tonumber(y), tonumber(m), tonumber(d))
end
Notes.dayOfKey = dayOfKey

-- The words of a note or a comment: one line, at most MAX_BYTES as they travel (cut on whole letters); nil if empty.
local function clean(text)
  text = ns.Util.trim(tostring(text or "")):gsub("[%c]", " ")
  if text == "" then return nil end
  return ns.Codec.fit(text, Notes.MAX_BYTES)
end

-- What an edit box may hold: at most MAX_BYTES as it travels.
function Notes.fitWords(text) return ns.Codec.fit(tostring(text or ""), Notes.MAX_BYTES) end

-- A name as it is kept and sent (made safe to show, at most NAME_BYTES as it travels), or nil.
local function cleanName(name)
  if type(name) ~= "string" then return nil end
  return ns.Codec.fit(name, NAME_BYTES)
end

-- A class ("MAGE"), or nil.
local function cleanClass(c)
  if type(c) ~= "string" or #c > 12 or not c:match("^%u+$") then return nil end
  return c
end

function Notes.iconTexture(i)
  local e = Notes.ICONS[tonumber(i) or 1] or Notes.ICONS[1]
  return e.tex
end

function Notes.isMine(note)
  local me = ns.Diary and ns.Diary.myId()
  return type(note) == "table" and type(note.key) == "string" and me ~= nil
    and note.key:sub(1, #me + 1) == me .. "-"
end

-- The notes on a date ("2026-11-08") for someone whose local time is UTC + off seconds: notes without a time
-- first (oldest first), then timed ones by time. Deleted ones are left out.
function Notes.forDate(dateKey, off)
  local day = dayOfKey(dateKey)
  off = tonumber(off) or (ns.Diary and ns.Diary.offset and ns.Diary.offset()) or 0
  local out = {}
  for key, n in pairs(store() or {}) do
    local on
    if type(n.at) == "number" then on = day ~= nil and math.floor((n.at + off) / 86400) == day
    else on = n.d == dateKey end
    if on and not n.x then
      local copy = { key = key }
      for k, v in pairs(n) do copy[k] = v end
      out[#out + 1] = copy
    end
  end
  table.sort(out, function(a, b)
    local ta, tb = type(a.at) == "number", type(b.at) == "number"
    if ta ~= tb then return not ta end
    if ta and a.at ~= b.at then return a.at < b.at end
    return tostring(a.key) < tostring(b.key)
  end)
  return out
end

-- "4:30pm" for a timed note in local time (UTC + off), or nil.
function Notes.timeText(n, off)
  if type(n) ~= "table" or type(n.at) ~= "number" then return nil end
  return ns.CalendarLogic.clock(((n.at + (tonumber(off) or 0)) % 86400) / 60)
end

------------------------------------------------------------------------------------------- what counts
local function utcToday() return math.floor(ns.Diary.now() / ns.CalendarLogic.DAY) end

-- The one rule for what counts (is checksummed, sent, taken and kept): a note whose date is inside the keep window,
-- at most KEEP_DAYS UTC days before today's UTC day (the same day on every copy, wherever it is); a reply whose note
-- counts. today: a UTC day number (default: today).
local function inWindow(dateKey, today)
  local day = dayOfKey(dateKey)
  return day ~= nil and day >= (today or utcToday()) - KEEP_DAYS
end

local function isComment(key) return key:find("|c|", 1, true) ~= nil end

-- Caps: only the first MAX_NOTES live notes count, and the first MAX_COMMENTS live comments of a note, in key order
-- (so every copy picks the same ones, whatever order things arrived in). Deletion markers always count.
local function capped(keys, records, max, out)
  table.sort(keys)
  local live = 0
  for _, key in ipairs(keys) do
    if records[key].x then out[key] = true
    elseif live < max then live = live + 1; out[key] = true end
  end
end

-- The notes and replies that count: two sets { [key] = true }.
local function counted()
  local today = utcToday()
  local s, rs = store() or {}, Notes.replyStore() or {}
  local notes, replies = {}, {}
  local keys = {}
  for key, n in pairs(s) do
    if type(n) == "table" and inWindow(n.d, today) then keys[#keys + 1] = key end
  end
  capped(keys, s, MAX_NOTES, notes)
  local comments = {} -- note key -> its comments' keys
  for key, r in pairs(rs) do
    if type(r) == "table" and notes[r.n] then
      if isComment(key) then
        comments[r.n] = comments[r.n] or {}
        table.insert(comments[r.n], key)
      else
        replies[key] = true
      end
    end
  end
  for _, list in pairs(comments) do capped(list, rs, Notes.MAX_COMMENTS, replies) end
  return notes, replies
end

-- Is there room for a new live record with this key? Fewer than `max` live ones with a lower key are stored among
-- `records` that `same` picks (so it would count everywhere that has what we have).
local function room(records, key, max, same)
  local lower = 0
  for k, r in pairs(records) do
    if type(r) == "table" and not r.x and k < key and same(k, r) then lower = lower + 1 end
  end
  return lower < max
end

local function liveCount(records, same)
  local n = 0
  for k, r in pairs(records) do if type(r) == "table" and not r.x and same(k, r) then n = n + 1 end end
  return n
end

local function noteCounts(_, n) return inWindow(n.d) end
local function commentOf(noteKey) return function(k, r) return r.n == noteKey and isComment(k) end end

-- The bucket (1 .. BUCKETS) of a note and its replies, picked by the note's key.
local function bucketOf(noteKey) return ns.Util.hashNumber(noteKey) % Notes.BUCKETS + 1 end
Notes.bucketOf = bucketOf

-- A checksum of every note (and deletion) and reply that counts, so two copies can tell whether they have the same.
-- (The same sum v0.1.23 makes over what it keeps.)
function Notes.hash()
  local notes, replies = counted()
  local s, rs = store() or {}, Notes.replyStore() or {}
  local keys = {}
  for key in pairs(notes) do keys[#keys + 1] = key .. ":" .. tostring(s[key].u or 0) end
  for key in pairs(replies) do keys[#keys + 1] = key .. ":" .. tostring(rs[key].u or 0) end
  if #keys == 0 then return nil end
  table.sort(keys)
  return tostring(ns.Util.hashNumber(table.concat(keys, ";")))
end

-- One short checksum per bucket, as a list (an empty bucket: "0").
local function bucketSums()
  local notes, replies = counted()
  local s, rs = store() or {}, Notes.replyStore() or {}
  local lists = {}
  for b = 1, Notes.BUCKETS do lists[b] = {} end
  for key in pairs(notes) do table.insert(lists[bucketOf(key)], key .. ":" .. tostring(s[key].u or 0)) end
  for key, _ in pairs(replies) do
    table.insert(lists[bucketOf(rs[key].n)], key .. ":" .. tostring(rs[key].u or 0))
  end
  local out = {}
  for b, list in ipairs(lists) do
    table.sort(list)
    out[b] = #list > 0 and ns.Util.checksum(table.concat(list, ";")) or "0"
  end
  return out
end

-- The digest's notes fields: nh and nb (none when nothing counts).
function Notes.digestFields(f)
  local nh = Notes.hash()
  if not nh then return end
  f.nh = nh
  f.nb = table.concat(bucketSums(), ".")
end

-- What to ask a friend whose digest is f: CALQ fields, or nil when our notes are the same. A digest with nb asks only
-- for the buckets that differ; one without (v0.1.23) is compared by nh and asks for everything.
function Notes.askFor(f)
  if type(f.nb) == "string" then
    local theirs = ns.Util.split(f.nb, ".")
    if #theirs == Notes.BUCKETS then
      local mine, differ = bucketSums(), {}
      for b = 1, Notes.BUCKETS do if theirs[b] ~= mine[b] then differ[#differ + 1] = b end end
      if #differ == 0 then return nil end
      return { n = "1", b = table.concat(differ, ",") }
    end
  end
  if type(f.nh) == "string" and f.nh ~= Notes.hash() then return { n = "1" } end
  return nil
end

-- The buckets a request asks for ({ [b] = true }), or nil for all (no b, as v0.1.23 asks, or nothing readable).
local function asked(b)
  if type(b) ~= "string" then return nil end
  local out, any = {}, false
  for part in b:gmatch("[^,]+") do
    local n = tonumber(part)
    if n and n >= 1 and n <= Notes.BUCKETS and n == math.floor(n) then out[n] = true; any = true end
  end
  return any and out or nil
end

---------------------------------------------------------------------------------------------------- sending
-- A note as it travels: cut again, so a note an older version saved (longer words) still fits one message.
local function fields(key, n)
  return { k = key, d = n.d, t = n.x and "" or (clean(n.t) or ""), i = tostring(n.i or 1), b = cleanName(n.b),
    c = cleanClass(n.c), u = tostring(n.u or 0), x = n.x and "1" or nil,
    a = type(n.at) == "number" and tostring(n.at) or nil, g = DUNGEON[n.g] and n.g or nil }
end

local function send(key, to)
  local n = (store() or {})[key]
  if not n then return end
  local f = fields(key, n)
  if to then
    local o = { bulk = true } -- an answer to a request: behind live messages
    if not ns.Comm.sendTo(to, "CALN", f, o) then ns.Comm.send("CALN", f, o) end
  else
    ns.Comm.send("CALN", f)
  end
end

-- Answers "send me your notes" (CALQ n=1): the notes and replies that count, only those of the buckets in b ("3,5")
-- when it names any. At most one answer per ANSWER_GAP, whoever asks (later askers ask again at a later digest).
function Notes.sendAll(to, b)
  local t = ns.now()
  if answeredAt and t - answeredAt < ANSWER_GAP then return end
  answeredAt = t
  local only = asked(b)
  local notes, replies = counted()
  local rs = Notes.replyStore() or {}
  -- (notes first: a reply is only taken once its note is there)
  for key in pairs(notes) do if not only or only[bucketOf(key)] then send(key, to) end end
  for key in pairs(replies) do if not only or only[bucketOf(rs[key].n)] then Notes.sendReply(key, to) end end
end

------------------------------------------------------------------------------------------- replies to notes
-- What people do with a note: "seen" (opened it), "rsvp" (going / maybe / no), "comment" (a reply).
-- A reply: key = "<note key>|s|<id>" (seen), "<note key>|r|<id>" (rsvp: one per person, the newest wins),
-- "<note key>|c|<id>-<time>" (a comment); n = note key, v = "1" / the status / the words, b = name, c = class,
-- u = last change, x = deleted. Sent as CALR (to everyone on a change; with the notes when asked).
local RSVP = { yes = true, maybe = true, no = true }
local LETTER_KIND = { s = "seen", r = "rsvp", c = "comment" }

function Notes.replyStore()
  local db = ns.db
  if not db then return nil end
  if type(db.calendar) ~= "table" then db.calendar = {} end
  if type(db.calendar.replies) ~= "table" then db.calendar.replies = {} end
  return db.calendar.replies
end

local function replyFields(key, r)
  local v = r.x and "" or r.v
  if not r.x and key:find("|c|", 1, true) then v = clean(v) or "" end
  return { r = key, n = r.n, v = v, b = cleanName(r.b), c = cleanClass(r.c), u = tostring(r.u or 0),
    x = r.x and "1" or nil }
end

function Notes.sendReply(key, to)
  local r = (Notes.replyStore() or {})[key]
  if not r then return end
  local f = replyFields(key, r)
  if to then
    local o = { bulk = true }
    if not ns.Comm.sendTo(to, "CALR", f, o) then ns.Comm.send("CALR", f, o) end
  else
    ns.Comm.send("CALR", f)
  end
end

local function myReply(noteKey, letter, suffix)
  local s = Notes.replyStore()
  local note = (store() or {})[noteKey]
  if not s or not note or note.x then return nil end
  local me = ns.Diary.myId()
  local key = noteKey .. "|" .. letter .. "|" .. me .. (suffix or "")
  local _, class = UnitClass("player")
  return s, key, { n = noteKey, b = ns.playerName(), c = type(class) == "string" and class or nil, u = ns.Diary.now() }
end

local function put(s, key, r)
  local old = s[key]
  if old and (old.u or 0) >= r.u then r.u = old.u + 1 end
  s[key] = r
  Notes.sendReply(key)
  ns.Bus.fire("CALENDAR_CHANGED")
end

-- I opened the note (once).
function Notes.markSeen(noteKey)
  local s, key, r = myReply(noteKey, "s")
  if not s or s[key] then return false end
  r.v = "1"
  put(s, key, r)
  return true
end

-- I'm going ("yes"), "maybe" or can't ("no"); nil takes my answer back.
function Notes.rsvp(noteKey, status)
  local s, key, r = myReply(noteKey, "r")
  if not s then return false end
  if status ~= nil and not RSVP[status] then return false end
  if status == nil then r.x, r.v = true, "" else r.v = status end
  put(s, key, r)
  return true
end

-- Returns the comment's key, or nil (and "full" when the note has MAX_COMMENTS comments).
function Notes.comment(noteKey, text)
  text = clean(text)
  if not text then return nil end
  local s, key, r = myReply(noteKey, "c", "-" .. ns.Diary.now())
  if not s then return nil end
  if liveCount(s, commentOf(noteKey)) >= Notes.MAX_COMMENTS then return nil, "full" end
  while s[key] do key = key .. "x" end
  r.v = text
  put(s, key, r)
  return key
end

function Notes.deleteComment(key)
  local s = Notes.replyStore()
  local r = s and s[key]
  local me = ns.Diary.myId()
  if not r or r.x or not key:find("|c|" .. me .. "-", 1, true) then return false end
  r.x, r.v, r.u = true, "", math.max(ns.Diary.now(), (r.u or 0) + 1)
  Notes.sendReply(key)
  ns.Bus.fire("CALENDAR_CHANGED")
  return true
end

-- Everything people did with a note: { seen = {..}, yes = {..}, maybe = {..}, no = {..}, comments = {..},
-- mine = my rsvp or nil }. People: { name, class, me }; comments: { key, name, class, text, at, mine }.
function Notes.repliesFor(noteKey)
  local out = { seen = {}, yes = {}, maybe = {}, no = {}, comments = {} }
  local me = ns.Diary and ns.Diary.myId()
  for key, r in pairs(Notes.replyStore() or {}) do
    if r.n == noteKey and not r.x then
      local letter, who = key:match("|(%a)|(%w+)")
      local mine = who ~= nil and who == me
      local kind = LETTER_KIND[letter]
      local entry = { name = r.b or "?", class = r.c, me = mine }
      if kind == "seen" then
        out.seen[#out.seen + 1] = entry
      elseif kind == "rsvp" and out[r.v] then
        out[r.v][#out[r.v] + 1] = entry
        if mine then out.mine = r.v end
      elseif kind == "comment" then
        out.comments[#out.comments + 1] = { key = key, name = r.b or "?", class = r.c, text = r.v, at = r.u, mine = mine }
      end
    end
  end
  local function byName(a, b) return tostring(a.name) < tostring(b.name) end
  for _, k in ipairs({ "seen", "yes", "maybe", "no" }) do table.sort(out[k], byName) end
  table.sort(out.comments, function(a, b) return (a.at or 0) < (b.at or 0) end)
  return out
end

function Notes.receiveReply(sender, f)
  if type(f) ~= "table" or type(f.r) ~= "string" or #f.r > MAX_REPLY_KEY then return end
  local noteKey, letter = f.r:match("^(%w+%-%d+)|(%a)|%w+")
  if not noteKey or noteKey ~= f.n or #noteKey > MAX_KEY or not LETTER_KIND[letter] then return end
  local u = tonumber(f.u)
  if not u then return end
  local s = Notes.replyStore()
  if not s then return end
  local note = (store() or {})[noteKey]
  if type(note) ~= "table" or not inWindow(note.d) then return end -- its note is missing or no longer counts
  local old = s[f.r]
  if old and (old.u or 0) >= u then return end
  local deleted = f.x == "1"
  if not old and not deleted and letter == "c" and not room(s, f.r, Notes.MAX_COMMENTS, commentOf(noteKey)) then
    return
  end
  local v = deleted and "" or f.v
  if not deleted then
    if letter == "r" and not RSVP[v] then return end
    if letter == "c" then v = clean(v); if not v then return end end
    if letter == "s" then v = "1" end
  end
  s[f.r] = { n = noteKey, v = v, b = type(f.b) == "string" and cleanName(ns.Util.safeText(f.b)) or "?",
    c = cleanClass(f.c), u = u, x = deleted or nil }
  ns.Bus.fire("CALENDAR_CHANGED")
end

---------------------------------------------------------------------------------------------------- changes
-- Adds a note on a date for me (at: a time in UTC seconds, for a timed note; dungeon: a Notes.DUNGEONS key, its
-- name is the text when none was typed). Returns its key, or nil (and "full" when MAX_NOTES notes are kept).
function Notes.add(dateKey, text, icon, at, dungeon)
  if not DUNGEON[dungeon] then dungeon = nil end
  text = clean(text) or (dungeon and DUNGEON[dungeon].name) or nil
  if not text or not dayOfKey(dateKey) then return nil end
  local s = store()
  if not s then return nil end
  if liveCount(s, noteCounts) >= MAX_NOTES then return nil, "full" end
  local me = ns.Diary.myId()
  local now = ns.Diary.now()
  local key = me .. "-" .. now
  while s[key] do now = now + 1; key = me .. "-" .. now end
  local _, class = UnitClass("player")
  s[key] = { d = dateKey, t = text, i = math.max(1, math.min(#Notes.ICONS, tonumber(icon) or 1)), b = ns.playerName(),
    c = type(class) == "string" and class or nil, u = now, at = tonumber(at), g = dungeon }
  send(key)
  ns.Bus.fire("CALENDAR_CHANGED")
  return key
end

-- Deletes one of my notes. Returns true when it did.
function Notes.remove(key)
  local s = store()
  local n = s and s[key]
  if not n or n.x or not Notes.isMine({ key = key }) then return false end
  n.x, n.t, n.u = true, "", math.max(ns.Diary.now(), (n.u or 0) + 1)
  send(key)
  ns.Bus.fire("CALENDAR_CHANGED")
  return true
end

-- A note from a friend: kept when it's new or newer than ours.
function Notes.receive(sender, f)
  if type(f) ~= "table" then return end
  local key = f.k
  if type(key) ~= "string" or not key:match("^%w+%-%d+$") or #key > MAX_KEY then return end
  if not inWindow(f.d) then return end -- (also: a real date)
  local u = tonumber(f.u)
  if not u then return end
  local s = store()
  if not s then return end
  local old = s[key]
  if old and (old.u or 0) >= u then return end
  local deleted = f.x == "1"
  if not old and not deleted and not room(s, key, MAX_NOTES, noteCounts) then return end
  local text = deleted and "" or clean(f.t)
  if not deleted and not text then return end
  local class = cleanClass(f.c)
  local at = tonumber(f.a)
  if at and math.abs(at - ns.Diary.now()) > 10 * 365 * 86400 then at = nil end -- nonsense times are dropped
  s[key] = { d = f.d, t = text, i = math.max(1, math.min(#Notes.ICONS, tonumber(f.i) or 1)),
    b = type(f.b) == "string" and cleanName(ns.Util.safeText(f.b)) or "?", c = class, u = u,
    x = deleted or nil, at = at, g = DUNGEON[f.g] and f.g or nil }
  ns.Bus.fire("CALENDAR_CHANGED")
end

-- What no longer counts goes away: old notes and old deletion markers, notes and comments past the caps, replies
-- whose note is gone. At login and once a day while logged in.
function Notes.prune()
  local s, rs = store(), Notes.replyStore()
  if not s or not rs then return end
  local notes, replies = counted()
  for key in pairs(s) do if not notes[key] then s[key] = nil end end
  for key in pairs(rs) do if not replies[key] then rs[key] = nil end end
end
