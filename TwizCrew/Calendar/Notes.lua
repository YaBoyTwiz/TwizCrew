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

-- Dungeons and raids a note can be about (its picture fills the day on the month view). ej / lfg / ls: the names
-- the game's own artwork files use (Encounter Journal button, group finder icon, loading screen); the window tries
-- them in that order and falls back to the note's icon when none exists in this game version.
Notes.DUNGEONS = {
  { key = "rfc", name = "Ragefire Chasm", ej = "RagefireChasm", lfg = "RagefireChasm" },
  { key = "wc", name = "Wailing Caverns", ej = "WailingCaverns", lfg = "WailingCaverns" },
  { key = "dm", name = "The Deadmines", ej = "TheDeadmines", lfg = "Deadmines" },
  { key = "sfk", name = "Shadowfang Keep", ej = "ShadowfangKeep", lfg = "ShadowfangKeep" },
  { key = "bfd", name = "Blackfathom Deeps", ej = "BlackfathomDeeps", lfg = "BlackfathomDeeps" },
  { key = "stocks", name = "The Stockade", ej = "TheStockade", lfg = "StormwindStockades" },
  { key = "gnomer", name = "Gnomeregan", ej = "Gnomeregan", lfg = "Gnomeregan" },
  { key = "rfk", name = "Razorfen Kraul", ej = "RazorfenKraul", lfg = "RazorfenKraul" },
  { key = "sm", name = "Scarlet Monastery", ej = "ScarletMonastery", lfg = "ScarletMonastery" },
  { key = "rfd", name = "Razorfen Downs", ej = "RazorfenDowns", lfg = "RazorfenDowns" },
  { key = "ulda", name = "Uldaman", ej = "Uldaman", lfg = "Uldaman" },
  { key = "zf", name = "Zul'Farrak", ej = "ZulFarrak", lfg = "ZulFarak" },
  { key = "mara", name = "Maraudon", ej = "Maraudon", lfg = "Maraudon" },
  { key = "st", name = "Sunken Temple", ej = "TheTempleOfAtalHakkar", lfg = "SunkenTemple" },
  { key = "brd", name = "Blackrock Depths", ej = "BlackrockDepths", lfg = "BlackrockDepths" },
  { key = "lbrs", name = "Blackrock Spire", ej = "BlackrockSpire", lfg = "BlackrockSpire" },
  { key = "dmaul", name = "Dire Maul", ej = "DireMaul", lfg = "DireMaul" },
  { key = "strat", name = "Stratholme", ej = "Stratholme", lfg = "Stratholme" },
  { key = "scholo", name = "Scholomance", ej = "Scholomance", lfg = "Scholomance" },
  { key = "mc", name = "Molten Core", ej = "MoltenCore", lfg = "MoltenCore", raid = true },
  { key = "ony", name = "Onyxia's Lair", ej = "OnyxiasLair", lfg = "OnyxiasLair", raid = true },
  { key = "zg", name = "Zul'Gurub", ej = "ZulGurub", lfg = "ZulGurub", raid = true },
  { key = "bwl", name = "Blackwing Lair", ej = "BlackwingLair", lfg = "BlackwingLair", raid = true },
  { key = "aq20", name = "Ruins of Ahn'Qiraj", ej = "RuinsofAhnQiraj", lfg = "AhnQirajRuins", raid = true },
  { key = "aq40", name = "Temple of Ahn'Qiraj", ej = "TempleofAhnQiraj", lfg = "AhnQirajTemple", raid = true },
  { key = "naxx", name = "Naxxramas", ej = "Naxxramas", lfg = "Naxxramas", raid = true },
}
local DUNGEON = {}
for _, d in ipairs(Notes.DUNGEONS) do DUNGEON[d.key] = d end
function Notes.dungeon(key) return DUNGEON[key] end

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
    if not ns.Comm.sendTo(to, "CALN", f) then ns.Comm.send("CALN", f) end
  else
    ns.Comm.send("CALN", f)
  end
end

function Notes.sendAll(to)
  local t = ns.now()
  if sentAllAt[to] and t - sentAllAt[to] < SEND_ALL_GAP then return end
  sentAllAt[to] = t
  for key in pairs(store() or {}) do send(key, to) end
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

-- Old notes and old deletion markers go away; never more than MAX_NOTES.
function Notes.prune(today)
  local s = store()
  if not s then return end
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
end
