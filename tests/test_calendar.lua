-- Crew calendar: the pure rules (CalendarLogic), the diary and its swaps (Diary), and the window (CalendarUI).

local function start(ns, W)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  ns.Crew.start()
  ns.Self.start()
  ns.LayerSensor.start()
  ns.Modules.startAll()
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
  return db
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {}, msgType == "CALP" and { repeatKeys = { "i" } } or nil)) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function sent(ns, W, msgType, from)
  local out = {}
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then out[#out + 1] = { fields = msg.fields, target = W.sent[i].target } end
  end
  return out
end

-- A mask with slots from..to-1 on.
local function maskOf(L, from, to)
  local m = L.EMPTY
  for i = from, to - 1 do m = L.set(m, i) end
  return m
end

-- The raw texts of msgType sent since W.sent[from], each once (a message to everyone goes to several places).
local function textsOf(W, msgType, from)
  local out, seen = {}, {}
  for i = (from or 0) + 1, #W.sent do
    local text = W.sent[i].text
    if text:find("^%d+%^" .. msgType .. "%^") and not seen[text] then seen[text] = true; out[#out + 1] = text end
  end
  return out
end

-- Every text arrives at this copy as a whisper from `sender`.
local function hear(W, sender, list)
  for _, text in ipairs(list) do W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "WHISPER", sender) end
end

-- Copies of the addon (one per name), linked and logged in, in the game's real state (the channel delivers nothing:
-- everything travels by whisper). Returns { { W =, ns = }, ... } in the order of names.
local function crewOf(H, names)
  local list, ws = {}, {}
  for i, name in ipairs(names) do
    local W, ns = H.client(name, { class = "MAGE" })
    ns.Comm.echoCount = W.realEchoCount
    list[i], ws[i] = { W = W, ns = ns }, W
  end
  H.link(unpack(ws))
  for _, c in ipairs(list) do
    c.W:fire("ADDON_LOADED", "TwizCrew"); c.W:fire("PLAYER_LOGIN"); c.W:fire("PLAYER_ENTERING_WORLD")
  end
  return list
end

-- The same `count` notes (each with a comment) written straight into every copy's saved data.
local function sameNotes(list, count)
  local L = list[1].ns.CalendarLogic
  local today = math.floor(list[1].ns.Diary.now() / 86400)
  for _, c in ipairs(list) do
    for i = 1, count do
      local key = "auth" .. (i % 4) .. "x-" .. (1790000000 + i)
      c.ns.db.calendar.notes[key] = { d = c.ns.Notes.dateKey(L.civil(today + i % 20)), t = "Note " .. i, i = 1,
        b = "Frostie", u = 1000 + i }
      c.ns.db.calendar.replies[key .. "|c|gink4567-" .. (2000 + i)] = { n = key, v = "ok", b = "Ginkan", u = 2000 + i }
    end
  end
end

-- How many notes messages (a notes request, a note, a reply) each copy sent since `marks` ({ [W] = #W.sent }).
local function notesTraffic(list, marks)
  local total, asks = 0, {}
  for _, c in ipairs(list) do
    for i = marks[c.W] + 1, #c.W.sent do
      local msg = c.ns.Codec.decode(c.W.sent[i].text)
      if msg and (msg.type == "CALN" or msg.type == "CALR" or (msg.type == "CALQ" and msg.fields.n)) then
        total = total + 1
        if msg.type == "CALQ" then asks[#asks + 1] = msg.fields end
      end
    end
  end
  return total, asks
end

local function marksOf(list)
  local m = {}
  for _, c in ipairs(list) do m[c.W] = #c.W.sent end
  return m
end

-- Words far longer than a note may be: "é" (2 bytes), "~" (3 bytes once escaped) and an emoji (4 bytes), with the
-- bytes one letter takes as it travels.
local LONG_WORDS = {
  { text = string.rep("\195\169", 150), size = 2 },
  { text = string.rep("~", 150), size = 3 },
  { text = string.rep("\240\159\152\128", 80), size = 4 },
}

return {
  files = "toc",
  tests = {
    ------------------------------------------------------------------------------------------------ pure rules
    masks = function(ns, A)
      local L = ns.CalendarLogic
      A.eq(#L.EMPTY, 16)
      local m = L.set(L.EMPTY, 0)
      m = L.set(m, 95)
      A.ok(L.has(m, 0)); A.ok(L.has(m, 95)); A.no(L.has(m, 1))
      A.eq(L.count(m), 2)
      A.eq(L.set(m, 0), m, "setting twice changes nothing")
      local both = L.merge(maskOf(L, 0, 4), maskOf(L, 2, 8))
      A.eq(L.count(both), 8, "merging adds, never removes")
      A.eq(L.merge(nil, m), m)
      A.eq(L.clean("short"), nil); A.eq(L.clean(m), m); A.eq(L.clean(string.rep("!", 16)), nil)
    end,
    dates_and_words = function(ns, A)
      local L = ns.CalendarLogic
      A.eq({ L.civil(0) }, { 1970, 1, 1 })
      A.eq(L.weekday(0), 4, "1970-01-01 was a Thursday")
      local d = L.daysFrom(2026, 11, 8)
      A.eq({ L.civil(d) }, { 2026, 11, 8 })
      A.eq(L.weekday(d), 0, "2026-11-08 is a Sunday")
      A.eq(L.monthLength(2024, 2), 29); A.eq(L.monthLength(2026, 2), 28); A.eq(L.monthLength(2026, 12), 31)
      A.eq(L.clock(0), "12am"); A.eq(L.clock(19 * 60 + 15), "7:15pm"); A.eq(L.clock(12 * 60), "12pm")
      A.eq(L.duration(45), "45m"); A.eq(L.duration(255), "4h 15m"); A.eq(L.duration(360), "6h")
      A.eq(L.offsetFrom({ year = 2026, yday = 312, hour = 14, min = 0 }, { year = 2026, yday = 312, hour = 19, min = 0 }),
        -5 * 3600, "5 hours behind UTC")
      A.eq(L.offsetFrom({ year = 2026, yday = 1, hour = 1, min = 0 }, { year = 2025, yday = 365, hour = 23, min = 0 }),
        2 * 3600, "over new year")
      local grid = L.monthGrid(2026, 11)
      A.eq(#grid, 42)
      A.eq(grid[1].d, 1, "November 2026 starts on a Sunday"); A.ok(grid[1].inMonth)
      A.eq(grid[30].d, 30); A.no(grid[31].inMonth)
    end,
    a_day_in_local_time = function(ns, A)
      local L = ns.CalendarLogic
      local day = L.daysFrom(2026, 11, 3) -- a Tuesday
      -- played 01:00-04:00 UTC on Wednesday = 8pm-11pm Tuesday at UTC-5; the last half hour AFK
      local on = maskOf(L, 4, 16)
      local afk = maskOf(L, 14, 16)
      local people = { abc = { name = "Twiz", class = "DRUID", days = { [day + 1] = { on = on, afk = afk } } } }
      local v = L.dayView(people, day, -5 * 3600)
      A.eq(#v, 1)
      A.eq(v[1].minutes, 180)
      A.eq(v[1].runs, { { from = 80, to = 90, afk = false }, { from = 90, to = 92, afk = true } })
      A.eq(L.runText(v[1].runs), "8pm-11pm")
      A.eq(#L.dayView(people, day, 0), 0, "in UTC it was Wednesday")
    end,
    who_was_on_when = function(ns, A)
      local L = ns.CalendarLogic
      local runs = { { from = 80, to = 90, afk = false }, { from = 90, to = 92, afk = true }, { from = 94, to = 96, afk = false } }
      A.eq(L.spans(runs), { { from = 80, to = 92 }, { from = 94, to = 96 } })
      A.eq(L.spanText({ from = 80, to = 92 }), "8pm-11pm")
      local list = {
        { name = "Frostie", class = "MAGE", runs = runs },
        { name = "Ginkan", class = "WARRIOR", runs = { { from = 88, to = 96, afk = false } } },
      }
      A.eq(L.whoAt(list, 85), { { name = "Frostie", class = "MAGE", afk = false } })
      A.eq(L.whoAt(list, 91), { { name = "Frostie", class = "MAGE", afk = true }, { name = "Ginkan", class = "WARRIOR", afk = false } })
      A.eq(L.whoAt(list, 93), { { name = "Ginkan", class = "WARRIOR", afk = false } })
      A.eq(L.whoAt(list, 10), {})
    end,
    day_view_writes_everyones_times = function(ns, A, W)
      start(ns, W)
      local L = ns.CalendarLogic
      ns.Calendar.open()
      local _, _, _, today = ns.Calendar.viewForTest()
      local off = ns.Diary.offset()
      -- 12 friends on yesterday (more than the rows): friend k from hour 11 + k local for two hours (friend 1 at noon)
      local day = today - 1
      local people = ns.Diary.people()
      for k = 1, 12 do
        local days = {}
        for j = (11 + k) * 4, (13 + k) * 4 - 1 do
          if j < 96 then
            local s = math.floor((day * L.DAY + j * L.SLOT - off) / L.SLOT)
            local uday, idx = math.floor(s / L.SLOTS_PER_DAY), s % L.SLOTS_PER_DAY
            days[uday] = days[uday] or { on = L.EMPTY }
            days[uday].on = L.set(days[uday].on, idx)
          end
        end
        people["acct" .. k] = { name = "Friend" .. string.format("%02d", k), class = "MAGE", days = days }
      end
      ns.Calendar.openDay(day)
      A.eq(#ns.Calendar.lastDay, 12)
      local row = ns.Calendar.dayRowForTest(1)
      A.ok(row, "a row")
      A.eq(#row.times, 1, "their time written on the row")
      A.contains(row.times[1], "pm-")
      A.eq(row.icons, 1, "their class icon on the bar")
      -- who was on at 8:15pm: friends 8 (7-9pm) and 9 (8-10pm)
      local text = ns.Calendar.whoAtText(81)
      A.contains(text, "At 8:15pm, 2 on")
      A.contains(text, "Friend08"); A.contains(text, "Friend09")
      A.contains(ns.Calendar.whoAtText(20), "nobody on")
      -- the mouse wheel scrolls the rest into view
      local first = ns.Calendar.dayRowForTest(1).name
      ns.Calendar.scrollDay(5)
      A.no(ns.Calendar.dayRowForTest(1).name == first, "scrolled")
      ns.Calendar.scrollDay(-10)
      A.eq(ns.Calendar.dayRowForTest(1).name, first, "back to the top")
      -- Usual times for one person: the same grid, only their hours (Friend08 played 7-9pm yesterday)
      ns.Calendar.showUsualFor("acct8")
      local one = ns.Calendar.lastUsualOne
      A.ok(one, "a grid for one person")
      local wd = L.weekday(day)
      A.eq(one.grid[wd][19], 0.25, "1 of the last 4 weeks at 7pm")
      A.eq(one.grid[wd][20], 0.25)
      A.eq(one.grid[wd][21], 0, "not at 9pm")
      A.eq(one.grid[wd][12], 0, "Friend01's noon isn't in it")
      A.eq(one.people[1].name, "Friend08")
      -- several people: Friend08 (7-9pm) and Friend09 (8-10pm): both at 8pm, their best time together
      ns.Calendar.toggleUsual("acct9")
      A.eq(ns.Calendar.lastUsualOne, nil, "not one person any more")
      A.eq(#ns.Calendar.lastUsualPick, 2)
      A.eq(ns.Calendar.lastUsual.grid ~= nil, true)
      local both = ns.CalendarLogic.usual({ acct8 = ns.Diary.people().acct8, acct9 = ns.Diary.people().acct9 },
        ns.Diary.localToday(), ns.Diary.offset(), 4)
      A.eq(both.grid[wd][20], 0.5, "both of them at 8pm")
      A.eq(ns.Calendar.lastUsualPick[2].grid[wd][21], 0.25, "each one's own hours for the tooltip")
      ns.Calendar.toggleUsual("acct8")
      A.eq(ns.Calendar.lastUsualOne.people[1].name, "Friend09", "taken off: one left")
      ns.Calendar.toggleUsual("acct9")
      A.eq(ns.Calendar.lastUsualPick, nil, "nobody picked: everyone")
      ns.Calendar.showUsualFor(nil)
      A.eq(ns.Calendar.lastUsualOne, nil, "back to everyone")
      -- a real week: who was really on, on those dates
      ns.Calendar.showWeek(day)
      local wk = ns.Calendar.lastWeek
      A.ok(wk, "the week grid")
      A.eq(wk.first, day - L.weekday(day), "from its Sunday")
      A.ok(wk.count >= 12, "everyone who played that week (and me, if today is in it)")
      A.eq(wk.grid[wd][19], 2, "Friend07 (6-8pm) and Friend08 (7-9pm) at 7pm")
      ns.Calendar.toggleUsual("acct8")
      A.eq(ns.Calendar.lastWeek.count, 1, "only the people picked")
      A.eq(ns.Calendar.lastWeek.people[1].grid[wd][19], 1, "the whole hour")
      ns.Calendar.moveWeek(-1)
      A.eq(ns.Calendar.lastWeek.count, 0, "nobody the week before")
      ns.Calendar.moveWeek(1)
      ns.Calendar.showUsualFor(nil)
      ns.Calendar.showWeek(nil)
      A.eq(ns.Calendar.lastWeek, nil, "back to usual times")
      A.eq(ns.Log.errors(10), {})
      A.ok(ns.Calendar.lastUsual.grid[wd][12] > 0, "everyone's grid has all of them")
      A.eq(ns.Log.errors(10), {})
    end,
    usual_times_and_the_best_time = function(ns, A)
      local L = ns.CalendarLogic
      local today = L.daysFrom(2026, 11, 8)
      local people = { a = { name = "A", class = "MAGE", days = {} }, b = { name = "B", class = "ROGUE", days = {} } }
      -- both play 8pm-11pm (UTC, offset 0) on the last four Tuesdays; A also on Saturdays 2pm-3pm
      for week = 0, 3 do
        local tue = today - 5 - week * 7
        people.a.days[tue] = { on = maskOf(L, 80, 92) }
        people.b.days[tue] = { on = maskOf(L, 80, 92) }
        people.a.days[tue + 4] = { on = maskOf(L, 56, 60) }
      end
      local u = L.usual(people, today, 0, 4)
      A.eq(u.count, 2)
      A.eq(u.grid[2][20], 2, "Tuesday 8pm: both, every week")
      local best = L.bestTime(u)
      A.eq(best.weekday, 2); A.eq(best.from, 20); A.eq(best.to, 23)
      A.eq(L.bestTimeText(best, 2), "Best time to play together: Tue 8pm-11pm (usually 2 of 2 on)")
      local a
      for _, p in ipairs(u.people) do if p.name == "A" then a = p end end
      A.eq(a.perWeek, 240)
      A.contains(L.habit(a), "usually 8pm-11pm")
      A.eq(L.bestTime(L.usual({}, today, 0, 4)), nil)
      A.contains(L.bestTimeText(nil), "Not enough")
    end,
    ------------------------------------------------------------------------------------------------ the diary
    my_play_time_is_written_down = function(ns, A, W)
      local db = start(ns, W)
      local me = ns.Diary.myId()
      A.ok(me and #me == 8, "an id for this account")
      W:advance(200)
      local p = ns.Diary.people()[me]
      A.eq(p.name, "Twiz")
      local slots = ns.CalendarLogic.total(p.days)
      A.ok(slots >= 1, "online slots marked")
      ns.Away.toggle()
      W:advance(61)
      local afk = 0
      for _, d in pairs(p.days) do if d.afk then afk = afk + ns.CalendarLogic.count(d.afk) end end
      A.ok(afk >= 1, "AFK marked too")
      A.eq(db.calendar.me, me, "kept in the saved data")
      A.eq(ns.Log.errors(10), {})
    end,
    digests_ask_and_answer = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local L = ns.CalendarLogic
      local day = math.floor(ns.Diary.now() / 86400)
      -- Frostie knows 12 slots of someone we've never heard of: we ask for them
      local before = #W.sent
      receive(ns, W, "Frostie", "CALD", { pxyz12345 = "12" })
      W:advance(1)
      local asks = sent(ns, W, "CALQ", before)
      A.eq(#asks, 1); A.eq(asks[1].fields.i, "xyz12345")
      -- their diary arrives: merged
      receive(ns, W, "Frostie", "CALP", { i = "xyz12345", n = "Holly", c = "PRIEST", a = "Holly:PRIEST,Hollyalt:WARLOCK",
        ["d" .. day] = maskOf(L, 70, 82) })
      local p = ns.Diary.people().xyz12345
      A.eq(p.name, "Holly"); A.eq(p.class, "PRIEST"); A.eq(p.alts.Hollyalt, "WARLOCK")
      A.eq(L.count(p.days[day].on), 12)
      -- Frostie offers Holly again: we don't ask twice
      before = #W.sent
      receive(ns, W, "Frostie", "CALD", { pxyz12345 = "20" })
      W:advance(1)
      A.eq(#sent(ns, W, "CALQ", before), 0, "asked recently")
      -- Ginkan asks us for Holly and for me: we send both (passing on what we heard)
      receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR" })
      W:advance(70)
      before = #W.sent
      receive(ns, W, "Ginkan", "CALQ", { i = "xyz12345" })
      receive(ns, W, "Ginkan", "CALQ", { i = ns.Diary.myId() })
      W:advance(5)
      local ids = {}
      for _, m in ipairs(sent(ns, W, "CALP", before)) do ids[m.fields.i] = true end
      A.ok(ids.xyz12345, "Holly's diary passed on")
      A.ok(ids[ns.Diary.myId()], "and mine")
      -- nobody can write my own diary, and strangers are ignored
      receive(ns, W, "Frostie", "CALP", { i = ns.Diary.myId(), n = "Fake", ["d" .. day] = maskOf(L, 0, 96) })
      A.eq(ns.Diary.people()[ns.Diary.myId()].name, "Twiz")
      receive(ns, W, "Stranger", "CALP", { i = "zzz", n = "Nope", ["d" .. day] = maskOf(L, 0, 4) })
      A.eq(ns.Diary.people().zzz, nil)
      A.eq(ns.Log.errors(10), {})
    end,
    share_off_keeps_me_out = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(70)
      ns.Modules.set("calendar", "share", false)
      local before = #W.sent
      ns.Diary.sendDigest()
      ns.Diary.sendPerson(ns.Diary.myId(), "Frostie")
      W:advance(3)
      for _, m in ipairs(sent(ns, W, "CALD", before)) do A.eq(m.fields["p" .. ns.Diary.myId()], nil) end
      A.eq(#sent(ns, W, "CALP", before), 0)
    end,
    two_copies_swap_diaries = function(ns, A, W, H)
      local tw, twNs = H.client("Twiz", { class = "DRUID" })
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(tw, fr)
      for _, X in ipairs({ tw, fr }) do
        X:fire("ADDON_LOADED", "TwizCrew"); X:fire("PLAYER_LOGIN"); X:fire("PLAYER_ENTERING_WORLD")
      end
      H.advance(90)
      local twId, frId = twNs.Diary.myId(), frNs.Diary.myId()
      A.ok(twId ~= frId)
      local p = frNs.Diary.people()[twId]
      A.ok(p, "Frostie has Twiz's diary")
      A.eq(p.name, "Twiz")
      A.ok(twNs.Diary.people()[frId], "and Twiz has Frostie's")
    end,
    ------------------------------------------------------------------------------------------------ notes
    notes_add_delete_and_swap = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N = ns.Notes
      local before = #W.sent
      local key = N.add("2026-11-14", "Deadmines at 8, bring potions", 2)
      A.ok(key, "added")
      A.eq(N.forDate("2026-11-14")[1].t, "Deadmines at 8, bring potions")
      A.eq(N.forDate("2026-11-14")[1].i, 2)
      W:advance(2)
      local sentNote = sent(ns, W, "CALN", before)
      A.eq(#sentNote, 1, "the crew hears about it at once")
      A.eq(sentNote[1].fields.t, "Deadmines at 8, bring potions")
      A.eq(N.add("2026-11-14", "   ", 1), nil, "no empty notes")
      A.eq(N.add("someday", "x", 1), nil, "a real date only")
      -- a friend's note arrives; I can't delete it
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = "2026-11-14", t = "I'll tank", i = "4", b = "Frostie",
        c = "MAGE", u = "1000" })
      A.eq(#N.forDate("2026-11-14"), 2)
      A.no(N.remove("frost123-1000"), "not mine")
      -- an older copy of it changes nothing; their deletion does
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = "2026-11-14", t = "old", i = "1", u = "900" })
      A.eq(N.forDate("2026-11-14")[1].t ~= "old" and N.forDate("2026-11-14")[2].t ~= "old", true)
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = "2026-11-14", t = "", i = "4", u = "1001", x = "1" })
      A.eq(#N.forDate("2026-11-14"), 1, "deleted by its author")
      A.ok(N.remove(key), "my own one")
      A.eq(#N.forDate("2026-11-14"), 0)
      -- a stranger's note is ignored
      receive(ns, W, "Stranger", "CALN", { k = "zz-1", d = "2026-11-14", t = "spam", i = "1", u = "5" })
      A.eq(#N.forDate("2026-11-14"), 0)
      A.eq(ns.Log.errors(10), {})
    end,
    timed_notes_follow_your_time_zone = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L = ns.Notes, ns.CalendarLogic
      -- 4:30pm on Nov 14 for someone at UTC-5 = 21:30 UTC
      local day = L.daysFrom(2026, 11, 14)
      local at = day * 86400 + (16 * 60 + 30) * 60 + 5 * 3600
      local key = N.add("2026-11-14", "Deadmines", 2, at)
      A.ok(key)
      local east = N.forDate("2026-11-14", -5 * 3600)
      A.eq(#east, 1); A.eq(N.timeText(east[1], -5 * 3600), "4:30pm", "the author's time")
      A.eq(N.timeText(east[1], -8 * 3600), "1:30pm", "three hours behind")
      A.eq(#N.forDate("2026-11-14", 9 * 3600), 0, "far east of it, that's already the next day")
      local japan = N.forDate("2026-11-15", 9 * 3600)
      A.eq(#japan, 1); A.eq(N.timeText(japan[1], 9 * 3600), "6:30am")
      -- the time goes out with the note and comes back from a friend
      W:advance(2)
      local f = sent(ns, W, "CALN")[1].fields
      A.eq(tonumber(f.a), at)
      receive(ns, W, "Frostie", "CALN", { k = "frost123-2000", d = "2026-11-14", t = "Raid", i = "3", u = "2000",
        a = tostring(at + 3600) })
      local list = N.forDate("2026-11-14", -5 * 3600)
      A.eq(#list, 2); A.eq(list[2].t, "Raid", "sorted by time")
      A.eq(N.timeText(list[2], -5 * 3600), "5:30pm")
    end,
    open_a_note_answer_and_comment = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR" })
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = "2026-11-14", t = "Deadmines run", i = "2", b = "Frostie",
        c = "MAGE", u = "1000", g = "dm", a = "1790000000" })
      local before = #W.sent
      A.ok(ns.NoteView.open("frost123-1000"))
      W:advance(2)
      local seen = sent(ns, W, "CALR", before)
      A.eq(#seen, 1, "opening it tells the crew I've seen it")
      A.eq(seen[1].fields.v, "1")
      local r = ns.NoteView.lastReplies
      A.eq(#r.seen, 1); A.eq(r.seen[1].name, "Twiz")
      -- going, then take it back, then maybe
      ns.NoteView.answer("yes")
      A.eq(ns.NoteView.lastReplies.mine, "yes")
      A.eq(#ns.NoteView.lastReplies.yes, 1)
      ns.NoteView.answer("yes")
      A.eq(ns.NoteView.lastReplies.mine, nil, "clicking it again takes it back")
      ns.NoteView.answer("maybe")
      A.eq(ns.NoteView.lastReplies.mine, "maybe")
      -- a comment, and deleting it
      ns.NoteView.commentForTest("I'll bring the potions")
      local cm = ns.NoteView.lastReplies.comments
      A.eq(#cm, 1); A.eq(cm[1].text, "I'll bring the potions"); A.ok(cm[1].mine)
      A.ok(ns.Notes.deleteComment(cm[1].key))
      A.eq(#ns.NoteView.lastReplies.comments, 0)
      -- Ginkan answers and comments: it arrives
      receive(ns, W, "Ginkan", "CALR", { r = "frost123-1000|r|gink4567", n = "frost123-1000", v = "yes", b = "Ginkan",
        c = "WARRIOR", u = "2000" })
      receive(ns, W, "Ginkan", "CALR", { r = "frost123-1000|c|gink4567-2001", n = "frost123-1000", v = "On my way",
        b = "Ginkan", c = "WARRIOR", u = "2001" })
      r = ns.NoteView.lastReplies
      A.eq(#r.yes, 1); A.eq(r.yes[1].name, "Ginkan")
      A.eq(r.comments[1].text, "On my way")
      A.no(ns.Notes.deleteComment("frost123-1000|c|gink4567-2001"), "not my comment")
      -- nonsense is ignored
      receive(ns, W, "Ginkan", "CALR", { r = "frost123-1000|r|gink4567", n = "frost123-1000", v = "sure", u = "3000" })
      A.eq(ns.Notes.repliesFor("frost123-1000").yes[1].name, "Ginkan", "only going / maybe / no")
      -- the checksum covers answers, so they swap too
      local h1 = ns.Notes.hash()
      ns.Notes.rsvp("frost123-1000", "no")
      A.ok(ns.Notes.hash() ~= h1)
      ns.NoteView.close()
      A.no(ns.NoteView.isShown())
      A.eq(ns.Log.errors(10), {})
    end,
    dungeon_levels = function(ns, A)
      local N = ns.Notes
      local dm = N.dungeon("dm")
      A.eq(N.levelText(dm), "17-20"); A.eq(N.levelText(N.dungeon("hyjal")), "60")
      A.eq(N.levelFit(dm, 20), "ok"); A.eq(N.levelFit(dm, 40), "low"); A.eq(N.levelFit(dm, 10), "high")
      A.contains(N.dungeonLine(N.dungeon("hyjal")), "20 players"); A.contains(N.dungeonLine(N.dungeon("barrow")), "10 players")
      local last = 0
      for _, d in ipairs(N.DUNGEONS) do A.ok(d.min >= last, "lowest first: " .. d.name); last = d.min end
    end,
    notes_checksums_trigger_a_swap = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR" })
      local buckets = {}
      for i = 1, 8 do buckets[ns.Notes.bucketOf(ns.Notes.add("2026-11-2" .. i, "Raid night " .. i, 3))] = true end
      A.ok(next(buckets, next(buckets)), "notes in several buckets")
      W:advance(5)
      -- a v0.1.23 digest (nh only): the old exchange, everything
      local before = #W.sent
      receive(ns, W, "Frostie", "CALD", { nh = "12345" })
      W:advance(1)
      local asks = sent(ns, W, "CALQ", before)
      A.eq(#asks, 1); A.eq(asks[1].fields.n, "1", "different notes: ask for theirs")
      A.eq(asks[1].fields.b, nil, "everything (v0.1.23 reads no buckets)")
      before = #W.sent
      receive(ns, W, "Frostie", "CALQ", { n = "1" })
      W:advance(10)
      A.eq(#sent(ns, W, "CALN", before), 8, "they asked: all my notes go to them")
      -- one answer a minute, whoever asks
      before = #W.sent
      receive(ns, W, "Ginkan", "CALQ", { n = "1" })
      W:advance(10)
      A.eq(#sent(ns, W, "CALN", before), 0, "Ginkan asks again at a later digest")
      W:advance(45)
      receive(ns, W, "Ginkan", "CALQ", { n = "1" })
      W:advance(10)
      A.eq(#sent(ns, W, "CALN", before), 8)
      -- a digest from a new copy: only the buckets that differ
      W:advance(130)
      local mine = {}
      before = #W.sent
      ns.Diary.sendDigest()
      W:advance(2)
      local nb = sent(ns, W, "CALD", before)[1].fields.nb
      local parts = ns.Util.split(nb, ".")
      A.eq(#parts, 8, "one checksum per bucket")
      for i, p in ipairs(parts) do mine[i] = p end
      local b = next(buckets) -- a bucket with notes in it
      mine[b] = "1"
      before = #W.sent
      receive(ns, W, "Frostie", "CALD", { nh = "12345", nb = table.concat(mine, ".") })
      W:advance(1)
      asks = sent(ns, W, "CALQ", before)
      A.eq(#asks, 1); A.eq(asks[1].fields.b, tostring(b), "one bucket")
      A.eq(asks[1].fields.n, "1", "(v0.1.23 would answer with everything)")
      before = #W.sent
      receive(ns, W, "Frostie", "CALQ", { n = "1", b = tostring(b) })
      W:advance(10)
      local want = 0
      for key in pairs(ns.db.calendar.notes) do if ns.Notes.bucketOf(key) == b then want = want + 1 end end
      local got = sent(ns, W, "CALN", before)
      A.ok(want >= 1)
      A.eq(#got, want, "only that bucket's notes")
      for _, m in ipairs(got) do A.eq(ns.Notes.bucketOf(m.fields.k), b) end
      A.eq(ns.Log.errors(10), {})
    end,
    two_copies_differing_by_one_note_swap_one_bucket = function(_, A, _, H)
      local list = crewOf(H, { "Twiz", "Frostie" })
      H.advance(120)
      sameNotes(list, 24)
      local tw, fr = list[1], list[2]
      local extra = "frost123-1790000500"
      fr.ns.db.calendar.notes[extra] = { d = tw.ns.db.calendar.notes["auth1x-1790000001"].d, t = "Extra", i = 1,
        b = "Frostie", u = 5000 }
      local b = fr.ns.Notes.bucketOf(extra)
      local marks = marksOf(list)
      H.advance(700) -- a digest each way
      local _, asks = notesTraffic(list, marks)
      A.ok(#asks >= 1, "a request")
      for _, f in ipairs(asks) do A.eq(f.b, tostring(b), "exactly the one bucket that differs") end
      for _, c in ipairs(list) do
        for i = marks[c.W] + 1, #c.W.sent do
          local msg = c.ns.Codec.decode(c.W.sent[i].text)
          if msg.type == "CALN" then A.eq(c.ns.Notes.bucketOf(msg.fields.k), b, "only that bucket's notes") end
          if msg.type == "CALR" then A.eq(c.ns.Notes.bucketOf(msg.fields.n), b, "and its replies") end
        end
      end
      A.ok(tw.ns.db.calendar.notes[extra], "Twiz has the note now")
      A.eq(tw.ns.Notes.hash(), fr.ns.Notes.hash())
      A.eq(tw.ns.Log.errors(10), {}); A.eq(fr.ns.Log.errors(10), {})
    end,
    five_copies_repair_one_missing_note_with_few_sends = function(_, A, _, H)
      local list = crewOf(H, { "Twiz", "Frostie", "Ginkan", "Holly", "Pewpew" })
      H.advance(120)
      sameNotes(list, 40)
      local last = list[5]
      local missing = "auth3x-1790000007"
      last.ns.db.calendar.notes[missing] = nil
      last.ns.db.calendar.replies[missing .. "|c|gink4567-2007"] = nil
      local marks = marksOf(list)
      H.advance(1300) -- two rounds of digests
      local total = notesTraffic(list, marks)
      A.ok(last.ns.db.calendar.notes[missing], "the missing note arrived")
      for _, c in ipairs(list) do A.eq(c.ns.Notes.hash(), list[1].ns.Notes.hash(), "everyone agrees") end
      A.ok(total < 40, "few sends: " .. total)
      for _, c in ipairs(list) do A.eq(c.ns.Log.errors(10), {}) end
    end,
    every_calendar_message_fits_one_piece = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L, D = ns.Notes, ns.CalendarLogic, ns.Diary
      local MAX = ns.Config.MAX_MESSAGE
      local today = math.floor(D.now() / 86400)
      local date = N.dateKey(L.civil(today + 3))
      local function fits(list, what)
        for _, text in ipairs(list) do A.ok(#text <= MAX, what .. " is " .. #text .. " bytes") end
      end
      for wi, w in ipairs(LONG_WORDS) do
        W:advance(61) -- (a friend gets all my notes at most once a minute)
        local name = ns.Util.truncateUTF8(w.text, 24)
        -- the largest note and replies the code keeps, as an older version may have saved them
        local nk = "abcdefghijklm-" .. (1790000000 + wi)                      -- 24 letters
        local who = "abcdefghijkl"                                            -- a 12-letter id
        local ck = nk .. "|c|" .. who .. "-1790000001"                         -- 50 letters
        local big = { b = name, c = "ABCDEFGHIJKL", u = 1790000000 }
        local function rec(t) for k, v in pairs(big) do t[k] = t[k] or v end; return t end
        ns.db.calendar.notes = { [nk] = rec({ d = date, t = w.text, i = 16, at = 1790000000, g = "excavation" }) }
        ns.db.calendar.replies = {
          [nk .. "|s|" .. who] = rec({ n = nk, v = "1" }),
          [nk .. "|r|" .. who] = rec({ n = nk, v = "maybe" }),
          [ck] = rec({ n = nk, v = w.text }),
        }
        local before = #W.sent
        receive(ns, W, "Frostie", "CALQ", { n = "1" })
        W:advance(5)
        local notes, replies = textsOf(W, "CALN", before), textsOf(W, "CALR", before)
        A.eq(#notes, 1, "one note, one piece")
        A.eq(#replies, 3, "three replies (seen, going, a comment), one piece each")
        fits(notes, "the note"); fits(replies, "a reply")
        -- what arrives is taken (words cut to whole letters, at most MAX_BYTES as they travel)
        ns.db.calendar.notes, ns.db.calendar.replies = {}, {}
        hear(W, "Frostie", notes); hear(W, "Frostie", replies)
        local n = ns.db.calendar.notes[nk]
        A.ok(n, "the note is taken")
        A.eq(n.t, w.text:sub(1, #n.t), "the start of the words")
        A.eq(#n.t % (w.size == 3 and 1 or w.size), 0, "whole letters")
        local travel = #n.t / (w.size == 3 and 1 or w.size) * w.size
        A.ok(travel <= N.MAX_BYTES and travel > N.MAX_BYTES - w.size, "as many letters as fit: " .. travel)
        A.eq(n.g, "excavation"); A.eq(n.at, 1790000000); A.eq(n.c, "ABCDEFGHIJKL")
        local s = ns.db.calendar.replies
        A.ok(s[nk .. "|s|" .. who] and s[nk .. "|r|" .. who], "seen and going are taken")
        A.ok(s[ck] and s[ck].v == n.t, "the comment is taken, cut like the note")
      end
      -- the diaries: a person with a 16-letter id, a long name, many alts and 30 full days (on and AFK)
      local id = "abcdefghijklmnop"
      local w = LONG_WORDS[3].text
      local p = { name = ns.Util.truncateUTF8(w, 24), class = "ABCDEFGHIJKL", alts = {}, days = {} }
      for k = 1, 12 do p.alts[k .. ns.Util.truncateUTF8(w, 22)] = "ABCDEFGHIJKL" end
      for d = today - 29, today do p.days[d] = { on = maskOf(L, 0, 96), afk = maskOf(L, 0, 96) } end
      D.people()[id] = p
      local before = #W.sent
      D.sendDigest()
      W:advance(5)
      local digests = textsOf(W, "CALD", before)
      A.eq(#digests, 1, "the digest: one piece")
      fits(digests, "the digest")
      -- it arrives at a copy that never heard of that person: it asks
      D.people()[id] = nil
      before = #W.sent
      hear(W, "Frostie", digests)
      W:advance(2)
      local asks = textsOf(W, "CALQ", before)
      A.eq(#asks, 1); fits(asks, "the question")
      A.eq(ns.Codec.decode(asks[1]).fields.i, id)
      D.people()[id] = p
      before = #W.sent
      hear(W, "Frostie", asks)
      W:advance(30)
      local pieces = textsOf(W, "CALP", before)
      A.ok(#pieces > 1, "30 days take several pieces")
      fits(pieces, "a diary piece")
      for _, text in ipairs(pieces) do A.eq(ns.Codec.decode(text).fields.i, id, "every piece says whose") end
      D.people()[id] = nil
      hear(W, "Frostie", pieces)
      local got = D.people()[id]
      A.ok(got, "the diary is taken")
      A.eq(got.name, p.name)
      A.eq(L.total(got.days), 30 * 96, "every day arrived")
      local alts = 0
      for altName, class in pairs(got.alts) do
        alts = alts + 1
        A.eq(p.alts[altName], class, "a whole alt, never half of one")
      end
      A.ok(alts >= 1, "alts arrive")
      A.eq(ns.Log.errors(10), {})
    end,
    a_pruned_note_stays_pruned_and_checksums_agree = function(_, A, _, H)
      local tw, twNs = H.client("Twiz", { class = "DRUID" })
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      twNs.Comm.echoCount, frNs.Comm.echoCount = tw.realEchoCount, fr.realEchoCount
      H.link(tw, fr)
      for _, X in ipairs({ tw, fr }) do
        X:fire("ADDON_LOADED", "TwizCrew"); X:fire("PLAYER_LOGIN"); X:fire("PLAYER_ENTERING_WORLD")
      end
      H.advance(90)
      local L = twNs.CalendarLogic
      local today = math.floor(twNs.Diary.now() / 86400)
      local key = twNs.Notes.add(twNs.Notes.dateKey(L.civil(today + 2)), "Raid night", 3)
      H.advance(5)
      A.ok(frNs.db.calendar.notes[key], "Frostie has the note")
      -- Twiz's copy pruned a 91-day-old note (and its comment); Frostie's still has them
      local old = "frost123-1000"
      local note = { d = twNs.Notes.dateKey(L.civil(today - 91)), t = "Long ago", i = 1, b = "Frostie", u = 1000 }
      frNs.db.calendar.notes[old] = note
      frNs.db.calendar.replies[old .. "|c|frost123-1001"] = { n = old, v = "old words", b = "Frostie", u = 1001 }
      A.eq(twNs.Notes.hash(), frNs.Notes.hash(), "the same checksum: neither counts what is outside")
      local before = { [tw] = #tw.sent, [fr] = #fr.sent }
      H.advance(700) -- a digest each way
      local digests = #textsOf(tw, "CALD", before[tw]) + #textsOf(fr, "CALD", before[fr])
      A.ok(digests >= 2, "digests went both ways")
      local asks = 0
      for _, X in ipairs({ tw, fr }) do
        for _, text in ipairs(textsOf(X, "CALQ", before[X])) do
          if twNs.Codec.decode(text).fields.n then asks = asks + 1 end
        end
      end
      A.eq(asks, 0, "nobody asks for notes")
      -- Frostie (an older version, say) sends it anyway: Twiz's copy does not take it back
      local NoteFields = { k = old, d = note.d, t = note.t, i = "1", b = "Frostie", u = "1000" }
      for _, text in ipairs(frNs.Codec.encode("CALN", NoteFields)) do
        tw:fire("CHAT_MSG_ADDON", "TwizCrew", text, "WHISPER", "Frostie-" .. fr.state.realm)
      end
      for _, text in ipairs(frNs.Codec.encode("CALR", { r = old .. "|c|frost123-1001", n = old, v = "old words",
        b = "Frostie", u = "1001" })) do
        tw:fire("CHAT_MSG_ADDON", "TwizCrew", text, "WHISPER", "Frostie-" .. fr.state.realm)
      end
      A.eq(twNs.db.calendar.notes[old], nil, "not taken back")
      A.eq(next(twNs.db.calendar.replies), nil, "nor its comment")
      A.eq(twNs.Log.errors(10), {}); A.eq(frNs.Log.errors(10), {})
    end,
    comments_past_the_cap_do_not_split_checksums = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L = ns.Notes, ns.CalendarLogic
      A.eq(N.MAX_COMMENTS, 30)
      local today = math.floor(ns.Diary.now() / 86400)
      local nk = "frost123-1000"
      ns.db.calendar.notes[nk] = { d = N.dateKey(L.civil(today + 1)), t = "Raid", i = 3, b = "Frostie", u = 1000 }
      local function comment(k) -- comment k (01 .. 32), keys in that order
        return { r = nk .. "|c|gink4567-" .. (2000 + k), n = nk, v = "words " .. k, b = "Ginkan", c = "WARRIOR",
          u = tostring(2000 + k) }
      end
      -- copy A (an older version) holds 31 comments on the note
      for k = 1, 31 do
        local f = comment(k)
        ns.db.calendar.replies[f.r] = { n = nk, v = f.v, b = "Ginkan", u = 2000 + k }
      end
      local hashA = N.hash()
      -- copy B hears them one by one, the lowest key last: it applies the cap
      ns.db.calendar.replies = {}
      receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR" })
      for k = 2, 31 do receive(ns, W, "Ginkan", "CALR", comment(k)) end
      A.eq(#N.repliesFor(nk).comments, 30, "30 taken")
      receive(ns, W, "Ginkan", "CALR", comment(32))
      A.eq(#N.repliesFor(nk).comments, 30, "a 31st is refused")
      receive(ns, W, "Ginkan", "CALR", comment(1))
      A.eq(N.hash(), hashA, "the same 30 count on both copies (the lowest keys)")
      A.eq(N.comment(nk, "me too"), nil, "my own 31st is refused too")
      A.eq(N.hash(), hashA)
      A.ok(ns.NoteView.open(nk))
      ns.NoteView.commentForTest("me too")
      A.contains(W.printed[#W.printed], "the most it can take", "and the window says why")
      ns.NoteView.close()
      -- an update to a comment it has is still taken (its author deletes two; 31 were kept): room again
      for _, k in ipairs({ 5, 6 }) do
        local f = comment(k)
        f.x, f.v, f.u = "1", "", "3000"
        receive(ns, W, "Ginkan", "CALR", f)
        A.ok(ns.db.calendar.replies[f.r].x, "the deletion is taken")
      end
      A.ok(N.comment(nk, "me too"), "room for mine")
      A.eq(ns.Log.errors(10), {})
    end,
    notes_past_the_cap_do_not_split_checksums = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L = ns.Notes, ns.CalendarLogic
      local today = math.floor(ns.Diary.now() / 86400)
      local date = N.dateKey(L.civil(today + 1))
      local function key(i) return "a" .. string.format("%03d", i) .. "-1000" end
      for i = 0, 299 do ns.db.calendar.notes[key(i)] = { d = date, t = "n" .. i, i = 1, b = "Frostie", u = 1000 } end
      local full = N.hash()
      local function note(k, u) return { k = k, d = date, t = "new", i = "1", b = "Frostie", u = tostring(u or 1000) } end
      receive(ns, W, "Frostie", "CALN", note("zzz-1"))
      A.eq(ns.db.calendar.notes["zzz-1"], nil, "300 notes: a new one is refused")
      A.eq(N.hash(), full)
      receive(ns, W, "Frostie", "CALN", note(key(7), 1001))
      A.eq(ns.db.calendar.notes[key(7)].t, "new", "a change to one it has is taken")
      A.eq(N.add(date, "mine", 1), nil, "my own new note is refused too")
      -- a new note with a lower key than the last one counted is taken: every copy counts the same 300
      receive(ns, W, "Frostie", "CALN", note("a0005-1"))
      A.ok(ns.db.calendar.notes["a0005-1"], "taken")
      local mine = N.hash()
      ns.db.calendar.notes[key(299)] = nil
      A.eq(N.hash(), mine, "the note with the highest key no longer counts")
      ns.db.calendar.notes[key(299)] = { d = date, t = "n299", i = 1, b = "Frostie", u = 1000 }
      ns.Notes.prune()
      A.eq(ns.db.calendar.notes[key(299)], nil, "and pruning drops it")
      A.eq(N.hash(), mine)
      A.eq(ns.Log.errors(10), {})
    end,
    notes_are_pruned_once_a_day_while_logged_in = function(ns, A, W)
      start(ns, W)
      local N, L = ns.Notes, ns.CalendarLogic
      local today = math.floor(ns.Diary.now() / 86400)
      ns.db.calendar.notes["frost123-1000"] = { d = N.dateKey(L.civil(today - 90)), t = "Edge", i = 1, u = 1000 }
      ns.db.calendar.replies["frost123-1000|s|gink4567"] = { n = "frost123-1000", v = "1", u = 1001 }
      ns.db.calendar.replies["zzz-1|s|gink4567"] = { n = "zzz-1", v = "1", u = 1001 } -- its note is missing
      A.ok(N.hash(), "90 days old still counts")
      local h = N.hash()
      ns.db.calendar.replies["zzz-1|s|gink4567"] = nil
      A.eq(N.hash(), h, "a reply without its note does not count")
      ns.db.calendar.replies["zzz-1|s|gink4567"] = { n = "zzz-1", v = "1", u = 1001 }
      local untilMidnight = (today + 1) * 86400 - ns.Diary.now()
      W:advance(untilMidnight + 700) -- past UTC midnight and the next digest
      A.eq(ns.db.calendar.notes["frost123-1000"], nil, "91 days old now: gone without logging out")
      A.eq(next(ns.db.calendar.replies), nil, "with its replies (and the one without a note)")
      A.eq(N.hash(), nil)
      A.eq(ns.Log.errors(10), {})
    end,
    edit_boxes_stop_at_the_limit = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N = ns.Notes
      ns.Calendar.open()
      local _, _, _, day = ns.Calendar.viewForTest()
      ns.Calendar.openMaker({ day = day })
      local box = ns.Calendar.makerBoxForTest()
      box:SetText(string.rep("~", 60))
      box._scripts.OnTextChanged(box, true)
      A.eq(box:GetText(), string.rep("~", 33), "33 of them take 99 bytes as they travel")
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = N.dateKey(ns.CalendarLogic.civil(day)), t = "Run",
        i = "2", b = "Frostie", c = "MAGE", u = "1000" })
      A.ok(ns.NoteView.open("frost123-1000"))
      box = ns.NoteView.boxForTest()
      box:SetText(string.rep("\195\169", 70))
      box._scripts.OnTextChanged(box, true)
      A.eq(box:GetText(), string.rep("\195\169", 50))
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------------ the window
    calendar_window = function(ns, A, W)
      start(ns, W)
      W:advance(70)
      W.env.SlashCmdList.TWIZCREW("cal")
      A.ok(ns.Calendar.isShown(), "/tc cal")
      local view, y, m, day = ns.Calendar.viewForTest()
      A.eq(view, "month")
      ns.Calendar.openDay(day)
      A.eq((ns.Calendar.viewForTest()), "day")
      A.eq(#ns.Calendar.lastDay, 1, "me, today")
      A.eq(ns.Calendar.lastDay[1].name, "Twiz")
      ns.Calendar.show("usual")
      A.eq(ns.Calendar.lastUsual.count, 1)
      ns.Calendar.moveMonth(-1); ns.Calendar.moveMonth(13)
      ns.Calendar.show("month")
      ns.Calendar.toggle()
      A.no(ns.Calendar.isShown())
      local labels = {}
      for _, it in ipairs(ns.Panel.toolItems()) do labels[#labels + 1] = it.label end
      local found
      for _, l in ipairs(labels) do if l == "Crew calendar" then found = true end end
      A.ok(found, "in the wrench menu")
      local b = ns.Panel.calendarButtonForTest()
      A.ok(b, "a calendar button in the panel's header")
      b._scripts.OnClick(b, "LeftButton")
      A.ok(ns.Calendar.isShown(), "it opens the calendar")
      -- "Create a note": a plain one for today
      ns.Calendar.openMaker({ day = day })
      ns.Calendar.setMakerForTest("icon", 5)
      A.ok(ns.Calendar.saveMaker("Healer needed tonight"))
      A.eq(#ns.Calendar.lastNotes, 1, "it lands on its day (the day view opens)")
      A.eq(ns.Calendar.lastNotes[1].i, 5)
      A.eq(ns.Calendar.lastNotes[1].t, "Healer needed tonight")
      -- right-click the timeline at 4:30pm: the window opens with that time; a dungeon, no words needed
      local items = ns.Calendar.timeMenuItems(990)
      A.eq(items[1].label, "Create a note at 4:30pm")
      items[1].onClick()
      A.eq(ns.Calendar.makerForTest().minutes, 990)
      ns.Calendar.setMakerForTest("kind", "dungeon")
      A.eq(ns.Calendar.saveMaker(""), nil, "a dungeon needs picking first")
      local places = ns.Calendar.placeItems()
      A.ok(#places >= 15, "the dungeons")
      A.contains(places[1].label, "[13-18]", "lowest levels first")
      local names = {}
      for _, it in ipairs(places) do names[#names + 1] = it.label end
      local all = table.concat(names, "|")
      for _, want in ipairs({ "Hall of Thanes", "Ruins of Lordaeron", "Excavation Site", "City of Dalaran",
        "The Drowned City", "Krol'dok Stronghold", "Alcaz Prison", "Blackmaw Hold", "Shaper's Terrace" }) do
        A.contains(all, want, "Forever's new dungeons are there")
      end
      A.eq(#places, 28, "all 28 of Forever's dungeons")
      for _, it in ipairs(places) do if it.label:find("The Deadmines", 1, true) then it.onClick() end end
      A.ok(ns.Calendar.saveMaker(""))
      local timed
      for _, n in ipairs(ns.Calendar.lastNotes) do if n.g == "dm" then timed = n end end
      A.ok(timed and timed.at, "a timed dungeon note")
      A.eq(timed.t, "The Deadmines", "its name when no words were typed")
      A.eq(ns.Notes.timeText(timed, ns.Diary.offset()), "4:30pm")
      A.eq(ns.Calendar.lastMarkers, 1, "its icon on the timeline")
      -- the hour and minute menus, the time zone, the month art
      ns.Calendar.openMaker({ day = day })
      A.eq(ns.Calendar.makerForTest().minutes, nil, "no time yet")
      ns.Calendar.stepTime("minute", 2)
      A.eq(ns.Calendar.makerForTest().minutes, 20 * 60 + 30, "the first press starts at 8pm: 8:30pm")
      ns.Calendar.stepTime("hour", 1)
      ns.Calendar.stepTime("minute", 3)
      A.eq(ns.Calendar.makerForTest().minutes, 21 * 60 + 15, "minutes stay in their hour: 9:15pm")
      ns.Calendar.stepTime("ampm", 0)
      A.eq(ns.Calendar.makerForTest().minutes, 9 * 60 + 15, "AM / PM: 9:15am")
      ns.Calendar.stepTime("hour", -10)
      A.eq(ns.Calendar.makerForTest().minutes, 23 * 60 + 15, "round the clock: 11:15pm")
      ns.Calendar.setMakerForTest("kind", "dungeon")
      ns.Calendar.scrollList(5); ns.Calendar.scrollList(99); ns.Calendar.scrollList(-99)
      A.contains(ns.Calendar.zoneName(), "UTC")
      A.eq(ns.Calendar.dayMenuItems(day)[1].label, "Create a note on this day")
      ns.Calendar.show("month")
      -- icons on the menus
      for _, it in ipairs(ns.Panel.menuItems()) do A.eq(type(it.icon), "string", "menu icon: " .. it.label) end
      for _, it in ipairs(ns.Panel.rowMenu({ name = "Frostie", tags = {} })) do
        A.eq(type(it.icon), "string", "row menu icon: " .. it.label)
      end
      A.eq(ns.Log.errors(10), {})
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
