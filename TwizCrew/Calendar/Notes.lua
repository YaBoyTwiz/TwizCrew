-- Crew calendar notes (part of module "calendar"): click a day, type a note, pick an icon. Notes are shared with
-- the crew and swapped like the play-time diaries, so everyone sees them on that date. Only the author can delete
-- a note (a deleted note stays as a small "deleted" marker for a while, so the deletion reaches everyone).
--
-- A note: key = "<author id>-<created>", d = "2026-11-08" (the author's local date), t = text, i = icon (1-16),
-- b = author's character name, c = class, u = last change (server time), x = true when deleted,
-- at = a time (UTC seconds) for a timed note ("4:30pm"): everyone sees it at their own local time, on their own
-- local date (which can be a different day than the author's).
-- Messages: CALN = one note (to everyone when you add or delete one; to one friend when asked). The CALD digest
-- carries nh = a checksum of all notes; a different checksum means "ask for theirs" (CALQ n=1).
local _, ns = ...

local Notes = {}
ns.Notes = Notes

local FEATURE = "calendar"
local MAX_TEXT = 120
local MAX_NOTES = 300
local KEEP_DAYS = 90     -- past notes (and deletion markers) are kept this long
local SEND_ALL_GAP = 60  -- seconds between "all my notes" to the same friend

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

local sentAllAt = {}

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

local function clean(text)
  text = ns.Util.trim(tostring(text or "")):gsub("[%c]", " ")
  if text == "" then return nil end
  return ns.Util.truncateUTF8(text, MAX_TEXT)
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

-- A checksum of every note (and deletion), so two copies can tell whether they have the same notes.
function Notes.hash()
  local keys = {}
  for key, n in pairs(store() or {}) do keys[#keys + 1] = key .. ":" .. tostring(n.u or 0) end
  for key, r in pairs(Notes.replyStore() or {}) do keys[#keys + 1] = key .. ":" .. tostring(r.u or 0) end
  if #keys == 0 then return nil end
  table.sort(keys)
  local h = 0
  local s = table.concat(keys, ";")
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return tostring(h)
end

---------------------------------------------------------------------------------------------------- sending
local function fields(key, n)
  return { k = key, d = n.d, t = n.x and "" or n.t, i = tostring(n.i or 1), b = n.b, c = n.c,
    u = tostring(n.u or 0), x = n.x and "1" or nil, a = type(n.at) == "number" and tostring(n.at) or nil,
    g = n.g }
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

function Notes.sendAll(to)
  local t = ns.now()
  if sentAllAt[to] and t - sentAllAt[to] < SEND_ALL_GAP then return end
  sentAllAt[to] = t
  for key in pairs(store() or {}) do send(key, to) end
  for key in pairs(Notes.replyStore() or {}) do Notes.sendReply(key, to) end
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
  return { r = key, n = r.n, v = r.x and "" or r.v, b = r.b, c = r.c, u = tostring(r.u or 0), x = r.x and "1" or nil }
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

function Notes.comment(noteKey, text)
  text = clean(text)
  if not text then return nil end
  local s, key, r = myReply(noteKey, "c", "-" .. ns.Diary.now())
  if not s then return nil end
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
  if type(f) ~= "table" or type(f.r) ~= "string" or #f.r > 80 then return end
  local noteKey, letter = f.r:match("^(%w+%-%d+)|(%a)|%w+")
  if not noteKey or noteKey ~= f.n or not LETTER_KIND[letter] then return end
  local u = tonumber(f.u)
  if not u then return end
  local s = Notes.replyStore()
  if not s then return end
  local old = s[f.r]
  if old and (old.u or 0) >= u then return end
  local deleted = f.x == "1"
  local v = deleted and "" or f.v
  if not deleted then
    if letter == "r" and not RSVP[v] then return end
    if letter == "c" then v = clean(v); if not v then return end end
    if letter == "s" then v = "1" end
  end
  s[f.r] = { n = noteKey, v = v, b = type(f.b) == "string" and ns.Util.truncateUTF8(ns.Util.safeText(f.b), 24) or "?",
    c = type(f.c) == "string" and f.c:match("^%u+$") and f.c or nil, u = u, x = deleted or nil }
  ns.Bus.fire("CALENDAR_CHANGED")
end

---------------------------------------------------------------------------------------------------- changes
-- Adds a note on a date for me (at: a time in UTC seconds, for a timed note; dungeon: a Notes.DUNGEONS key, its
-- name is the text when none was typed). Returns its key, or nil.
function Notes.add(dateKey, text, icon, at, dungeon)
  if not DUNGEON[dungeon] then dungeon = nil end
  text = clean(text) or (dungeon and DUNGEON[dungeon].name) or nil
  if not text or not dayOfKey(dateKey) then return nil end
  local s = store()
  if not s then return nil end
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
  if type(key) ~= "string" or not key:match("^%w+%-%d+$") or #key > 40 then return end
  if not dayOfKey(f.d) then return end
  local u = tonumber(f.u)
  if not u then return end
  local s = store()
  if not s then return end
  local old = s[key]
  if old and (old.u or 0) >= u then return end
  local deleted = f.x == "1"
  local text = deleted and "" or clean(f.t)
  if not deleted and not text then return end
  local class = type(f.c) == "string" and f.c:match("^%u+$") and f.c or nil
  local at = tonumber(f.a)
  if at and math.abs(at - ns.Diary.now()) > 10 * 365 * 86400 then at = nil end -- nonsense times are dropped
  s[key] = { d = f.d, t = text, i = math.max(1, math.min(#Notes.ICONS, tonumber(f.i) or 1)),
    b = type(f.b) == "string" and ns.Util.truncateUTF8(ns.Util.safeText(f.b), 24) or "?", c = class, u = u,
    x = deleted or nil, at = at, g = DUNGEON[f.g] and f.g or nil }
  ns.Bus.fire("CALENDAR_CHANGED")
end

-- Old notes and old deletion markers go away (with their replies); never more than MAX_NOTES.
function Notes.prune(today)
  local s = store()
  if not s then return end
  local rs = Notes.replyStore() or {}
  local count = 0
  for key, n in pairs(s) do
    local day = type(n) == "table" and dayOfKey(n.d)
    if not day or day < today - KEEP_DAYS then s[key] = nil else count = count + 1 end
  end
  if count > MAX_NOTES then
    local list = {}
    for key, n in pairs(s) do list[#list + 1] = { key = key, day = dayOfKey(n.d) } end
    table.sort(list, function(a, b) return a.day < b.day end)
    for i = 1, count - MAX_NOTES do s[list[i].key] = nil end
  end
  for key, r in pairs(rs) do if type(r) ~= "table" or not s[r.n] then rs[key] = nil end end
end
