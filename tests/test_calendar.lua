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
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
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

-- Copies of the addon (one per name), linked (so in one guild) and logged in. Returns { { W =, ns = }, ... } in the
-- order of names.
local function crewOf(H, names)
  local list, ws = {}, {}
  for i, name in ipairs(names) do
    local W, ns = H.client(name, { class = "MAGE" })
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
    -- Every copy asks a newcomer for the newcomer's diary at once: asks within ASK_COLLECT s get one guild answer;
    -- a single ask is whispered. One CALQ can ask for many diaries (j = more ids).
    asks_for_my_diary_from_many_get_one_guild_answer = function(ns, A, W)
      start(ns, W)
      for _, n in ipairs({ "Frostie", "Ginkan", "Lurabe" }) do receive(ns, W, n, "STATE", { cl = "MAGE" }) end
      W:advance(70) -- a slot of my own play time is marked
      local me = ns.Diary.myId()
      local from = #W.sent
      for _, n in ipairs({ "Frostie", "Ginkan", "Lurabe" }) do receive(ns, W, n, "CALQ", { i = me }) end
      W:advance(ns.Config.ASK_COLLECT + 3)
      local got = {}
      for i = from + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "CALP" then got[#got + 1] = W.sent[i].chatType end
      end
      A.ok(#got >= 1, "answered")
      for _, t in ipairs(got) do A.eq(t, "GUILD", "one answer to the guild, not three whispers") end
      W:advance(130)
      from = #W.sent
      receive(ns, W, "Frostie", "CALQ", { i = me })
      W:advance(ns.Config.ASK_COLLECT + 3)
      local alone = sent(ns, W, "CALP", from)
      A.ok(#alone >= 1, "a single ask is answered")
      A.eq(alone[1].target, "Frostie", "by whisper")
      A.eq(ns.Log.errors(10), {})
    end,
    one_ask_for_many_diaries = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(70)
      local people = ns.Diary.people()
      local L = ns.CalendarLogic
      local today = math.floor(ns.Diary.now() / 86400)
      for _, id in ipairs({ "aaaa1111", "bbbb2222" }) do
        people[id] = { name = id, class = "MAGE", alts = {}, days = { [today] = { on = maskOf(L, 1, 3) } } }
      end
      local from = #W.sent
      receive(ns, W, "Frostie", "CALQ", { i = ns.Diary.myId(), j = "aaaa1111,bbbb2222" })
      W:advance(ns.Config.ASK_COLLECT + 5)
      local ids = {}
      for _, m in ipairs(sent(ns, W, "CALP", from)) do ids[m.fields.i] = true end
      A.ok(ids[ns.Diary.myId()] and ids.aaaa1111 and ids.bbbb2222, "all three diaries")
      -- one ask carries at most ASK_BATCH (20) ids: the rest is ignored
      local many = {}
      for n = 1, 25 do -- (25 ids still fit one message)
        local id = string.format("m%07d", n)
        people[id] = { name = id, class = "MAGE", alts = {}, days = { [today] = { on = maskOf(L, 1, 3) } } }
        many[n] = id
      end
      from = #W.sent
      receive(ns, W, "Ginkan", "STATE", { cl = "MAGE" })
      receive(ns, W, "Ginkan", "CALQ", { i = many[1], j = table.concat(many, ",", 2) })
      W:advance(ns.Config.ASK_COLLECT + 30)
      local answered = {}
      for _, m in ipairs(sent(ns, W, "CALP", from)) do answered[m.fields.i] = true end
      local n = 0
      for _ in pairs(answered) do n = n + 1 end
      local list = {} for id in pairs(answered) do list[#list + 1] = id end table.sort(list)
      A.eq(n, ns.Diary.ASK_BATCH, "20 diaries for an ask of 25: " .. table.concat(list, " "))
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
    a_timed_note_keeps_its_time_after_a_clock_change = function(ns, A, W)
      start(ns, W)
      local L, N, D = ns.CalendarLogic, ns.Notes, ns.Diary
      local today = math.floor(D.now() / 86400)
      -- this computer's clock goes back an hour at 2am local on a day five days ahead (UTC-4 -> UTC-5)
      local change = (today + 5) * 86400 + 6 * 3600
      local function offAt(t) return t < change and -4 * 3600 or -5 * 3600 end
      W.env.date = function(fmt, t)
        t = t or W.env.time()
        if fmt:sub(1, 1) == "!" then return os.date(fmt, t) end
        return os.date("!" .. fmt, t + offAt(t))
      end
      W.env.time = function(tt)
        if type(tt) ~= "table" then return math.floor(W.wall + W.clock) end
        local loc = L.daysFrom(tt.year, tt.month, tt.day) * 86400 + (tt.hour or 12) * 3600 + (tt.min or 0) * 60
        local utc = loc + 5 * 3600
        if offAt(utc) ~= -5 * 3600 then utc = loc + 4 * 3600 end
        return utc
      end
      A.eq(D.offset(), -4 * 3600, "before the change")
      local before, after = D.localToday() + 1, D.localToday() + 6
      -- a friend played 8pm-9pm (local, UTC-4) on the day before the change
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local s = math.floor(((before + 1) * 86400) / L.SLOT) -- 8pm at UTC-4 = midnight UTC
      D.people().frost123 = { name = "Frostie", class = "MAGE", alts = {},
        days = { [before + 1] = { on = maskOf(L, s % 96, s % 96 + 4) } } }
      -- an "8pm" note made now for a day after the change
      ns.Calendar.open()
      ns.Calendar.openMaker({ day = after, minutes = 20 * 60 })
      A.ok(ns.Calendar.saveMaker("Raid"))
      local function shown(day)
        ns.Calendar.openDay(day)
        local n = ns.Calendar.lastNotes[1]
        return n and N.timeText(n, D.offsetOn(day)), ns.Calendar.lastMarkers
      end
      A.eq({ shown(after) }, { "8pm", 1 }, "8pm on that day")
      -- six days later, the clock has changed: still 8pm on that day, and the friend still played at 8pm
      W.wall = W.wall + 6 * 86400
      A.eq(D.offset(), -5 * 3600, "after the change")
      A.eq({ shown(after) }, { "8pm", 1 }, "still 8pm on that day")
      A.eq(#N.forDate(N.dateKey(L.civil(after))), 1, "on that date")
      ns.Calendar.openDay(before)
      A.eq(ns.Calendar.lastDay[1].runs, { { from = 80, to = 84, afk = false } }, "8pm-9pm, that day's own time")
      A.eq(ns.Log.errors(10), {})
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
    five_copies_online_for_an_hour_never_ask_for_diaries_again = function(_, A, _, H)
      local list = crewOf(H, { "Twiz", "Frostie", "Ginkan", "Holly", "Pewpew" })
      H.advance(300) -- the first exchange
      for _, X in ipairs(list) do
        for _, Y in ipairs(list) do
          A.ok(Y.ns.Diary.people()[X.ns.Diary.myId()], Y.ns.playerName() .. " has " .. X.ns.playerName() .. "'s diary")
        end
      end
      local marks = marksOf(list)
      H.advance(3600 - 300 + 15) -- an hour online, just past the last digests
      local asks, diaries = 0, 0
      for _, c in ipairs(list) do
        asks = asks + #textsOf(c.W, "CALQ", marks[c.W])
        diaries = diaries + #textsOf(c.W, "CALP", marks[c.W])
      end
      A.eq(asks, 0, "nobody asks for a diary again")
      A.eq(diaries, 0, "nobody sends one")
      -- and every copy shows every other's last hour (the digests carried it)
      for _, X in ipairs(list) do
        local id = X.ns.Diary.myId()
        local own = X.ns.Diary.people()[id].days
        for _, Y in ipairs(list) do
          if Y ~= X then
            local theirs = Y.ns.Diary.people()[id].days
            for day, d in pairs(own) do
              A.eq(theirs[day] and theirs[day].on, d.on, Y.ns.playerName() .. " sees " .. X.ns.playerName() .. "'s day")
            end
          end
        end
      end
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
      -- my own today and yesterday (in the digest) at their largest: every slot on and AFK
      local me = D.people()[D.myId()]
      for d = today - 1, today do me.days[d] = { on = maskOf(L, 0, 96), afk = maskOf(L, 0, 96) } end
      local before = #W.sent
      D.sendDigest()
      W:advance(5)
      local digests = textsOf(W, "CALD", before)
      A.eq(#digests, 1, "the digest: one piece")
      fits(digests, "the digest")
      local f = ns.Codec.decode(digests[1]).fields
      A.eq(f["d" .. today], maskOf(L, 0, 96) .. ":" .. maskOf(L, 0, 96), "today's slots")
      A.ok(f["d" .. (today - 1)] and f.di == D.myId() and f.nb and f.nh, "yesterday's, whose, the note checksums")
      -- at their largest: a 16-letter id, every bucket checksum and nh as long as they get, and a 16-letter person
      f.di = "abcdefghijklmnoz"
      f["p" .. f.di] = f["p" .. D.myId()]
      f["p" .. D.myId()] = nil
      local sums = {}
      for k = 1, N.BUCKETS do sums[k] = "999999" end
      f.nb = table.concat(sums, ".")
      f.nh = "2147483646"
      local largest = ns.Codec.encode("CALD", f)
      A.eq(#largest, 1, "the largest digest is one piece")
      fits(largest, "the largest digest")
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
      local function key(i) return "a" .. string.format("%03d", i) .. "-" .. (1000 + i) end
      for i = 0, 299 do ns.db.calendar.notes[key(i)] = { d = date, t = "n" .. i, i = 1, b = "Frostie", u = 1000 } end
      local full = N.hash()
      local function note(k, u) return { k = k, d = date, t = "new", i = "1", b = "Frostie", u = tostring(u or 1000) } end
      receive(ns, W, "Frostie", "CALN", note("zzz-5000"))
      A.eq(ns.db.calendar.notes["zzz-5000"], nil, "300 notes: a newer one is refused")
      A.eq(N.hash(), full)
      receive(ns, W, "Frostie", "CALN", note(key(7), 1001))
      A.eq(ns.db.calendar.notes[key(7)].t, "new", "a change to one it has is taken")
      A.eq(N.add(date, "mine", 1), nil, "my own new note is refused too")
      -- a note older than the newest one counted is taken: every copy counts the same (oldest) 300
      receive(ns, W, "Frostie", "CALN", note("a0005-1"))
      A.ok(ns.db.calendar.notes["a0005-1"], "taken")
      local mine = N.hash()
      ns.db.calendar.notes[key(299)] = nil
      A.eq(N.hash(), mine, "the newest note no longer counts")
      ns.db.calendar.notes[key(299)] = { d = date, t = "n299", i = 1, b = "Frostie", u = 1000 }
      ns.Notes.prune()
      A.eq(ns.db.calendar.notes[key(299)], nil, "and pruning drops it")
      A.eq(N.hash(), mine)
      A.eq(ns.Log.errors(10), {})
    end,
    at_the_cap_the_oldest_are_kept_whoever_wrote_them = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L = ns.Notes, ns.CalendarLogic
      local today = math.floor(ns.Diary.now() / 86400)
      local date = N.dateKey(L.civil(today + 1))
      local function rec(t) return { d = date, t = t or "n", i = 1, b = "Frostie", u = 1000 } end
      local function note(k) return { k = k, d = date, t = "new", i = "1", b = "Frostie", u = "1000" } end
      local function fill(extra)
        ns.db.calendar.notes = {}
        for i = 1, 299 do ns.db.calendar.notes["mmm-" .. (1000 + i)] = rec() end
        for k, v in pairs(extra or {}) do ns.db.calendar.notes[k] = v end
      end
      -- copy A: full, with an old note from an author whose id sorts last; a newer note from a low id is refused
      fill({ ["zzz-500"] = rec() })
      receive(ns, W, "Frostie", "CALN", note("aaa-2000"))
      A.eq(ns.db.calendar.notes["aaa-2000"], nil, "the newest is refused, whoever wrote it")
      local hashA = N.hash()
      -- copy B heard them in the other order: it took the new one while it had room, then the old one
      fill()
      receive(ns, W, "Frostie", "CALN", note("aaa-2000"))
      A.ok(ns.db.calendar.notes["aaa-2000"])
      receive(ns, W, "Frostie", "CALN", note("zzz-500"))
      A.ok(ns.db.calendar.notes["zzz-500"], "the old one is taken")
      A.eq(N.hash(), hashA, "both count the oldest 300")
      N.prune()
      A.eq(ns.db.calendar.notes["aaa-2000"], nil, "the newest goes")
      A.ok(ns.db.calendar.notes["zzz-500"])
      -- my own note is never deleted by what arrives later (even an older note that pushes it out of the count)
      local mine = ns.Diary.myId() .. "-1500"
      fill({ [mine] = rec("mine") })
      receive(ns, W, "Frostie", "CALN", note("aaa-3000"))
      A.eq(ns.db.calendar.notes["aaa-3000"], nil, "newer than mine: refused")
      receive(ns, W, "Frostie", "CALN", note("zzz-400"))
      A.ok(ns.db.calendar.notes["zzz-400"], "older than mine: taken")
      N.prune()
      A.ok(ns.db.calendar.notes[mine], "mine is still there")
      A.eq(ns.Log.errors(10), {})
    end,
    numbers_that_cannot_travel_are_refused = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L = ns.Notes, ns.CalendarLogic
      local date = N.dateKey(L.civil(math.floor(ns.Diary.now() / 86400) + 1))
      local bad = "-1.2345678901234e300"
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = date, t = "Raid", i = "1", u = bad })
      A.eq(ns.db.calendar.notes["frost123-1000"], nil, "a note with a nonsense u")
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = date, t = "Raid", i = "1", u = "12345678901" })
      A.eq(ns.db.calendar.notes["frost123-1000"], nil, "11 digits")
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = date, t = "Raid", i = "1.5", u = "1000",
        a = "1790000000.25" })
      local n = ns.db.calendar.notes["frost123-1000"]
      A.ok(n, "a good one")
      A.eq(n.at, nil, "a time that is not a whole number is dropped"); A.eq(n.i, 1)
      receive(ns, W, "Frostie", "CALR", { r = "frost123-1000|c|frost123-1001", n = "frost123-1000", v = "hi", u = bad })
      A.eq(next(ns.db.calendar.replies), nil, "a reply with a nonsense u")
      A.eq(ns.Log.errors(10), {})
    end,
    old_copies_are_not_asked_at_every_digest = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      for i = 1, 3 do ns.Notes.add("2026-11-2" .. i, "Raid " .. i, 3) end
      W:advance(5)
      -- Frostie runs v0.1.23 and keeps one record we don't count: its nh never matches ours, and it asks for
      -- everything at every digest
      local before = #W.sent
      for i = 1, 6 do -- six digests, ten minutes apart
        if i > 1 then W:advance(600) end
        receive(ns, W, "Frostie", "CALD", { nh = "12345" })
        receive(ns, W, "Frostie", "CALQ", { n = "1" })
      end
      W:advance(10)
      A.eq(#sent(ns, W, "CALQ", before), 1, "one full pull from it in an hour")
      A.eq(#sent(ns, W, "CALN", before), 3, "one full answer to it in an hour")
      -- (still inside the hour) it adds a real note: its nh changes, we ask again at its next digest; we take it,
      -- our notes changed, so its next request is answered again
      W:advance(130)
      before = #W.sent
      receive(ns, W, "Frostie", "CALD", { nh = "67890" })
      W:advance(2)
      A.eq(#sent(ns, W, "CALQ", before), 1, "asked again")
      receive(ns, W, "Frostie", "CALN", { k = "frost123-1000", d = "2026-11-25", t = "New", i = "1", b = "Frostie",
        u = "1000" })
      receive(ns, W, "Frostie", "CALQ", { n = "1" })
      W:advance(10)
      A.eq(#sent(ns, W, "CALN", before), 4, "answered again, with its note too")
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
    ------------------------------------------------------------------------------------------- something new
    a_timed_note_shows_its_authors_time_zone = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local L, N, D = ns.CalendarLogic, ns.Notes, ns.Diary
      A.eq(L.zoneLabel(-360, false), "CST")
      A.eq(L.zoneLabel(-360, true), "MDT", "the same offset in summer is another zone")
      A.eq(L.zoneLabel(-300, true), "CDT")
      A.eq(L.zoneLabel(330), "UTC+5:30", "no name here: the offset")
      A.eq(L.zoneLabel(-210, false), "UTC-3:30")
      -- this computer is on US Central time: UTC-6, UTC-5 from April to October
      local function offAt(t)
        local m = os.date("!*t", t).month
        return (m >= 4 and m <= 10) and -5 * 3600 or -6 * 3600
      end
      W.env.date = function(fmt, t)
        t = t or W.env.time()
        if fmt:sub(1, 1) == "!" then return os.date(fmt, t) end
        return os.date("!" .. fmt, t + offAt(t))
      end
      A.eq({ D.zoneAt() }, { -360, false }, "winter")
      A.eq(ns.Calendar.zoneName(), "CST", "named, not UTC-6")
      local july = L.daysFrom(2024, 7, 4) * 86400
      A.eq({ D.zoneAt(july) }, { -300, true }, "summer")
      A.eq(ns.Calendar.zoneName(july), "CDT")
      -- my timed note says where I am: 7pm CST tomorrow
      local today = math.floor(D.now() / 86400)
      local date = N.dateKey(L.civil(today + 1))
      local at = (today + 2) * 86400 + 3600
      local mine = N.add(date, "Raid", 1, at)
      A.eq(ns.db.calendar.notes[mine].z, -360, "my zone is kept with it")
      local travelled = false
      W:advance(5)
      for _, m in ipairs(W.sent) do
        if m.text:find("CALN", 1, true) and m.text:find("z=-360", 1, true) then travelled = true end
      end
      A.ok(travelled, "and travels with it")
      A.eq(N.authorTime(ns.db.calendar.notes[mine], D.offset()), nil, "my own zone: one time is enough")
      A.eq(N.add(date, "No time", 1) and ns.db.calendar.notes[mine].z, -360, "(a note without a time has none)")
      -- a friend on Eastern time
      local function from(key, u, z)
        receive(ns, W, "Frostie", "CALN", { k = key, d = date, t = "Deadmines", i = "1", b = "Frostie", c = "MAGE",
          u = u, a = tostring(at), z = z })
        return ns.db.calendar.notes[key]
      end
      A.eq({ N.authorTime(from("frost123-900", "900", "-300"), D.offset()) }, { "8pm", "EST" })
      A.eq({ N.authorTime(from("frost123-901", "901", "-240d"), D.offset()) }, { "9pm", "EDT" }, "summer time")
      A.eq(N.authorTime(from("frost123-902", "902", "-360"), D.offset()), nil, "on my time: nothing to add")
      A.eq(from("frost123-903", "903", "900").z, nil, "no such zone")
      A.eq(from("frost123-904", "904", "abc").z, nil, "not a zone")
      A.ok(from("frost123-904", "904", "abc").at, "(the note itself is kept)")
      -- first heard through a copy too old to pass the zone on, then from a new one
      A.eq(from("frost123-905", "905", nil).z, nil, "an old copy: no zone")
      A.eq(from("frost123-905", "905", "-300").z, -300, "the same note again, with its zone")
      A.eq(from("frost123-905", "905", "-480").z, -300, "only once")
      -- the note's window and the day's list say both
      ns.Calendar.open()
      ns.NoteView.open("frost123-900")
      A.contains(ns.NoteView.metaForTest(), "7pm CST your time")
      A.contains(ns.NoteView.metaForTest(), "8pm EST for ")
      local _, metaLine = ns.NoteView.metaForTest()
      A.no(metaLine:CanWordWrap(), "one line: a long one never runs into the line under it")
      ns.NoteView.open(mine)
      A.contains(ns.NoteView.metaForTest(), "7pm CST")
      A.no(ns.NoteView.metaForTest():find("your time", 1, true), "mine: one time")
      ns.NoteView.close()
    end,
    days_with_something_planned_are_colored_by_kind = function(ns, A, W)
      start(ns, W)
      local L, N, D = ns.CalendarLogic, ns.Notes, ns.Diary
      local y, m = L.civil(D.localToday())
      local first = L.daysFrom(y, m, 1)
      local function on(d) return N.dateKey(L.civil(first + d)) end
      local raid
      for _, dg in ipairs(N.DUNGEONS) do if dg.raid then raid = dg.key; break end end
      A.ok(raid, "(there is a raid)")
      N.add(on(3), "Bring flasks", 1)
      N.add(on(4), "", 2, nil, "dm")
      N.add(on(5), "A note first", 1)
      N.add(on(5), "", 2, nil, "dm")
      N.add(on(5), "", 3, nil, raid)
      ns.Calendar.open()
      local function kind(d) return ns.Calendar.eventCellForTest(first + d).kind end
      A.eq(kind(2), nil, "an empty day: no color")
      A.eq(kind(3), "note")
      A.eq(kind(4), "dungeon")
      A.eq(kind(5), "raid", "the biggest thing that day wins")
    end,
    the_calendar_is_bigger_and_its_size_is_a_setting = function(ns, A, W)
      start(ns, W)
      ns.Calendar.open()
      A.eq(ns.Calendar._.size, 1.25, "bigger than its design size unless told otherwise")
      ns.Modules.set("calendar", "size", 1.5)
      A.eq(ns.Calendar._.size, 1.5, "the slider works at once")
      ns.Modules.set("calendar", "size", 9)
      A.eq(ns.Calendar._.size, 1.8, "never off the screen")
      -- a short screen: the window is kept to its height
      local f = ns.Calendar._.frame
      rawset(W.env.UIParent, "GetHeight", function() return 768 end)
      ns.Modules.set("calendar", "size", 1.7)
      A.ok(ns.Calendar._.size * ns.Calendar._.HEIGHT <= 768, "fits the screen: " .. ns.Calendar._.size)
      A.ok(ns.Calendar._.size > 1.2, "but as big as fits")
      -- dragged somewhere, then made smaller: its middle stays where it was
      local old = ns.Calendar._.size
      rawset(f, "GetCenter", function() return 400, 300 end)
      ns.Modules.set("calendar", "size", 1)
      local point, rel, relPoint, x, y = f:GetPoint(1)
      A.eq({ point, rel, relPoint }, { "CENTER", W.env.UIParent, "BOTTOMLEFT" })
      A.ok(math.abs(x - 400 * old) < 0.01 and math.abs(y - 300 * old) < 0.01, "the same place on the screen")
      A.eq(f:GetNumPoints(), 1)
    end,
    after_only_a_reload_the_calendar_asks_for_a_restart = function(ns, A, W)
      start(ns, W)
      ns.Calendar._.buildEvents = nil -- a file the game has not loaded (added by the update)
      ns.Calendar.open()
      A.contains(W.printed[#W.printed], "restart the game")
      A.no(ns.Calendar.isShown())
      A.eq(ns.Log.errors(10), {})
    end,
    my_notes_can_be_edited_and_removed_from_a_days_menu = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local L, N, D = ns.CalendarLogic, ns.Notes, ns.Diary
      local day = D.localToday() + 2
      local date = N.dateKey(L.civil(day))
      local function labels(items)
        local out = {}
        for _, it in ipairs(items) do out[#out + 1] = it.label end
        return table.concat(out, " | ")
      end
      local function pick(items, label)
        for _, it in ipairs(items) do if it.label:find(label, 1, true) then it.onClick(); return true end end
        return false
      end
      ns.Calendar.open()
      A.eq(#ns.Calendar.dayMenuItems(day), 2, "an empty day: only the two ways to create")
      local mine = N.add(date, "Raid night at the usual place", 3)
      receive(ns, W, "Frostie", "CALN", { k = "frost123-900", d = date, t = "Deadmines", i = "1", b = "Frostie", u = "900" })
      local menu = labels(ns.Calendar.dayMenuItems(day))
      A.contains(menu, "Edit: Raid night at the us...","mine: edit (long words cut)")
      A.contains(menu, "Remove: Raid night")
      A.contains(menu, "Open: Deadmines", "a friend's: open")
      A.no(menu:find("Edit: Deadmines", 1, true), "never edit a friend's")
      A.eq(labels(ns.Calendar.noteMenuItems(mine)), "Open | Edit | Remove")
      A.eq(labels(ns.Calendar.noteMenuItems("frost123-900")), "Open")
      -- edit: the same window, filled in; saving changes the same note
      A.ok(pick(ns.Calendar.dayMenuItems(day), "Edit: Raid"))
      local mk = ns.Calendar.makerForTest()
      A.eq({ mk.edit, mk.day, mk.icon, mk.kind }, { mine, day, 3, "note" })
      A.eq(ns.Calendar.makerBoxForTest():GetText(), "Raid night at the usual place")
      local before = ns.db.calendar.notes[mine].u
      ns.Calendar.setMakerForTest("day", day + 1)
      ns.Calendar.setMakerForTest("minutes", 20 * 60)
      A.ok(ns.Calendar.saveMaker("Raid night, moved"))
      local n = ns.db.calendar.notes[mine]
      A.eq({ n.t, n.d, n.i }, { "Raid night, moved", N.dateKey(L.civil(day + 1)), 3 })
      A.ok(n.at and n.u > before, "a time now, and newer than before so friends take it")
      A.eq(#N.forDate(date), 1, "gone from the old day")
      A.eq(#N.forDate(N.dateKey(L.civil(day + 1))), 1, "on the new day, once")
      ns.Calendar.openMaker({ day = day })
      A.eq(ns.Calendar.makerForTest().edit, nil, "create again: a new note, not an edit")
      ns.Calendar.openMaker({ edit = "frost123-900" })
      A.eq(ns.Calendar.makerForTest().edit, nil, "a friend's note does not open for editing")
      A.no(N.update("frost123-900", date, "Mine now", 1), "nor change")
      -- remove
      A.ok(pick(ns.Calendar.dayMenuItems(day + 1), "Remove: "))
      A.eq(#N.forDate(N.dateKey(L.civil(day + 1))), 0, "removed")
      -- a note I made on my other computer (another diary id, my character's name and class) is mine too
      receive(ns, W, "Frostie", "CALN", { k = "other999-950", d = date, t = "From my desktop", i = "1",
        b = ns.playerName(), c = W.state.class, u = "950" })
      A.ok(N.isMine({ key = "other999-950" }), "my character wrote it")
      A.no(N.fresh(), "so it is not news")
      A.no(N.isNew("other999-950"), "and never 'new' (I don't mark my own notes seen)")
      A.contains(labels(ns.Calendar.dayMenuItems(day)), "Remove: From my desktop")
      A.ok(N.remove("other999-950"), "and I can remove it")
      -- someone else with my first name but another class is not me
      receive(ns, W, "Frostie", "CALN", { k = "other888-960", d = date, t = "My namesake's", i = "1",
        b = ns.playerName(), c = "MAGE", u = "960" })
      A.no(N.isMine({ key = "other888-960" }), "my name, not my class")
      A.no(labels(ns.Calendar.dayMenuItems(day)):find("Remove: My namesake", 1, true), "no Remove on theirs")
      A.no(N.remove("other888-960"), "and it can't be removed")
      A.ok(N.isNew("other888-960"), "theirs is new to me")
      -- one of my alts: its saved class decides
      ns.Diary.people()[ns.Diary.myId()].alts["Altimus"] = "PRIEST"
      receive(ns, W, "Frostie", "CALN", { k = "other999-970", d = date, t = "Alt note", i = "1", b = "Altimus",
        c = "PRIEST", u = "970" })
      receive(ns, W, "Frostie", "CALN", { k = "other777-980", d = date, t = "Other Altimus", i = "1", b = "Altimus",
        c = "ROGUE", u = "980" })
      A.ok(N.isMine({ key = "other999-970" }), "my alt, its class")
      A.no(N.isMine({ key = "other777-980" }), "my alt's name, another class")
    end,
    fresh_marks_notes_by_others_and_answers_on_mine = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR" })
      local N, L = ns.Notes, ns.CalendarLogic
      local today = math.floor(ns.Diary.now() / 86400)
      local soon, past = N.dateKey(L.civil(today + 2)), N.dateKey(L.civil(today - 5))
      local fired = 0
      ns.Bus.on("calendar", "CALENDAR_FRESH", function() fired = fired + 1 end)
      A.no(N.fresh(), "nothing new at first")
      local mine = N.add(soon, "Raid night", 3)
      A.ok(mine, "(my note)")
      A.no(N.fresh(), "my own note is not news")
      receive(ns, W, "Frostie", "CALN", { k = "frost123-900", d = past, t = "Old run", i = "1", b = "Frostie", u = "900" })
      A.ok(ns.db.calendar.notes["frost123-900"], "(a past note is kept)")
      A.no(N.fresh(), "a note on a past date is not news")
      receive(ns, W, "Frostie", "CALN", { k = "frost123-901", d = soon, t = "", i = "1", b = "Frostie", u = "901", x = "1" })
      A.no(N.fresh(), "a deletion is not news")
      -- answers on a note that is not mine
      ns.db.calendar.notes["gink4567-1000"] = { d = soon, t = "Deadmines", i = 2, b = "Ginkan", u = 1000 }
      receive(ns, W, "Frostie", "CALR", { r = "gink4567-1000|c|frost123-1500", n = "gink4567-1000", v = "I'm in",
        b = "Frostie", u = "1500" })
      A.ok(ns.db.calendar.replies["gink4567-1000|c|frost123-1500"], "(the comment is kept)")
      A.no(N.fresh(), "a comment on someone else's note is not news")
      -- "seen" on mine
      receive(ns, W, "Frostie", "CALR", { r = mine .. "|s|frost123", n = mine, v = "1", b = "Frostie", u = "1600" })
      A.no(N.fresh(), "someone opening my note is not news")
      A.eq(fired, 0, "nothing was announced")
      -- an answer on mine
      receive(ns, W, "Frostie", "CALR", { r = mine .. "|r|frost123", n = mine, v = "yes", b = "Frostie", u = "1700" })
      A.ok(N.fresh(), "Going on my note is news")
      A.eq(fired, 1, "announced once")
      N.clearFresh()
      A.no(N.fresh(), "cleared")
      A.eq(fired, 2, "the clearing is announced")
      N.clearFresh()
      A.eq(fired, 2, "clearing nothing announces nothing")
      receive(ns, W, "Frostie", "CALR", { r = mine .. "|r|frost123", n = mine, v = "yes", b = "Frostie", u = "1700" })
      A.no(N.fresh(), "the same answer again is not news")
      receive(ns, W, "Frostie", "CALR", { r = mine .. "|r|frost123", n = mine, v = "maybe", b = "Frostie", u = "1800" })
      A.ok(N.fresh(), "a changed answer is news")
      N.clearFresh()
      receive(ns, W, "Frostie", "CALR", { r = mine .. "|r|frost123", n = mine, v = "", b = "Frostie", u = "1900", x = "1" })
      A.no(N.fresh(), "an answer taken back is not news")
      -- a comment on mine
      receive(ns, W, "Ginkan", "CALR", { r = mine .. "|c|gink4567-2000", n = mine, v = "Count me in", b = "Ginkan",
        u = "2000" })
      A.ok(N.fresh(), "a comment on my note is news")
      N.clearFresh()
      -- my own answer coming back to me
      local me = ns.Diary.myId()
      receive(ns, W, "Frostie", "CALR", { r = mine .. "|c|" .. me .. "-2100", n = mine, v = "me again", b = "Twiz",
        u = "2100" })
      A.no(N.fresh(), "my own comment is not news")
      -- a note by someone else
      fired = 0
      receive(ns, W, "Frostie", "CALN", { k = "frost123-3000", d = soon, t = "Stockade", i = "2", b = "Frostie", u = "3000" })
      A.ok(N.fresh(), "a new note by someone else is news")
      receive(ns, W, "Ginkan", "CALN", { k = "gink4567-3001", d = soon, t = "Gnomeregan", i = "2", b = "Ginkan", u = "3001" })
      A.eq(fired, 1, "more news while something is new announces nothing more")
      -- opening the calendar clears it; nothing is marked while it is open
      ns.Calendar.open()
      A.no(N.fresh(), "opening the calendar clears it")
      receive(ns, W, "Ginkan", "CALN", { k = "gink4567-3002", d = soon, t = "Uldaman", i = "2", b = "Ginkan", u = "3002" })
      A.ok(ns.db.calendar.notes["gink4567-3002"], "(kept)")
      A.no(N.fresh(), "nothing is news while the calendar is open")
      ns.Calendar.close()
      -- it runs out when its day is past
      ns.db.calendar.fresh = today - 3
      A.no(N.fresh(), "old news is not news")
      N.prune()
      A.eq(ns.db.calendar.fresh, nil, "and the daily clean-up drops it")
      A.eq(ns.Log.errors(10), {})
    end,
    calendar_button_next_to_the_tabs = function(ns, A, W)
      -- (the words alone: without the icon atlas the tabs carry no icons; the icons' room: test_tab.lua)
      W.state.missingArt = { ["Interface\\AddOns\\TwizCrew\\Art\\Icons\\Icons.tga"] = true }
      start(ns, W)
      ns.Modules.set("panel", "keepOpen", true) -- (the button pulses only while the panel is on screen)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      local N, L, PL = ns.Notes, ns.CalendarLogic, ns.PanelLogic
      -- the pulse: a slow wave that never goes dark or solid
      for _, t in ipairs({ 0, 0.2, 0.75, 1.1, 7.3 }) do
        local a = PL.pulseAlpha(t)
        A.ok(a >= 0.1 and a <= 0.6, "alpha stays soft at " .. t)
      end
      A.ok(math.abs(PL.pulseAlpha(0.4) - PL.pulseAlpha(0.4 + PL.PULSE_SECONDS)) < 1e-9, "it repeats")
      A.ok(PL.pulseAlpha(PL.PULSE_SECONDS / 2) > PL.pulseAlpha(0), "brightest half way")
      local t = ns.Panel.tabButtonsForTest()
      A.ok(t.bar and t.bar:IsShown(), "the tab bar shows")
      A.ok(t.cal and t.cal:IsShown(), "with a Calendar button on it")
      A.ok(t.shame:IsShown(), "next to the Hall of Shame")
      local words = t.cal.label:GetText()
      A.ok(words == "Calendar" or words == "Cal", "Calendar (Cal when the bar is full): " .. words)
      A.eq(ns.Panel.headerButtonsForTest().cal, nil, "the small scroll in the header is gone")
      t.cal._scripts.OnClick(t.cal, "LeftButton")
      A.ok(ns.Calendar.isShown(), "it opens the calendar")
      A.eq(ns.Panel.tab(), "crew", "and the panel keeps its tab")
      t.cal._scripts.OnClick(t.cal, "LeftButton")
      A.no(ns.Calendar.isShown(), "and closes it")
      A.no(ns.Panel.calPulseForTest(), "no pulse while nothing is new")
      A.eq(t.cal.glow:GetAlpha(), 0)
      -- something new: it pulses until the calendar is opened
      local today = math.floor(ns.Diary.now() / 86400)
      local soon = N.dateKey(L.civil(today + 2))
      receive(ns, W, "Frostie", "CALN", { k = "frost123-3000", d = soon, t = "Stockade", i = "2", b = "Frostie", u = "3000" })
      W:advance(1)
      A.ok(ns.Panel.calPulseForTest(), "it pulses")
      A.ok(t.cal.glow:GetAlpha() > 0, "the glow is lit")
      -- tucked into the crew tab: nothing pulses behind the closed tab; again while the panel is out
      ns.Modules.set("panel", "keepOpen", false)
      W:advance(1)
      A.no(ns.Panel.calPulseForTest(), "no pulse while the panel is tucked away")
      ns.Panel.openTab("click")
      W:advance(1)
      A.ok(ns.Panel.calPulseForTest(), "it pulses while the panel is slid out")
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(1)
      A.ok(ns.Panel.calPulseForTest(), "and kept open")
      -- the panel hidden: nothing ticks
      ns.Modules.setEnabled("panel", false)
      W:advance(1)
      A.no(ns.Panel.calPulseForTest(), "no pulse while the panel is off")
      ns.Modules.setEnabled("panel", true)
      W:advance(1)
      A.ok(ns.Panel.calPulseForTest())
      t.cal._scripts.OnClick(t.cal, "LeftButton")
      W:advance(1)
      A.no(N.fresh())
      A.no(ns.Panel.calPulseForTest(), "opened: the pulse stops")
      A.eq(t.cal.glow:GetAlpha(), 0)
      ns.Calendar.close()
      -- a narrow panel: the short word
      ns.Modules.set("panel", "rowStyle", "tiny")
      W:advance(1)
      A.eq(t.cal.label:GetText(), "Cal", "tiny rows: the short word fits")
      ns.Modules.set("panel", "rowStyle", "full")
      W:advance(1)
      A.eq(t.cal.label:GetText(), words, "full rows: the word it had")
      ns.Modules.setEnabled("activity", false); W:advance(1)
      A.eq(t.cal.label:GetText(), "Calendar", "room for the whole word")
      ns.Modules.setEnabled("activity", true); W:advance(1)
      -- the bar follows the two modules
      ns.Modules.setEnabled("stats", false)
      W:advance(1)
      A.ok(t.bar:IsShown(), "stats off: the bar stays for the calendar")
      A.no(t.shame:IsShown(), "without the Hall of Shame")
      A.ok(t.cal:IsShown())
      ns.Modules.setEnabled("calendar", false)
      W:advance(1)
      A.ok(t.bar:IsShown() and t.act:IsShown(), "both off: the bar stays for the Activity tab")
      ns.Modules.setEnabled("activity", false); W:advance(1)
      A.no(t.bar:IsShown(), "all three off: no bar")
      ns.Modules.setEnabled("activity", true)
      ns.Modules.setEnabled("stats", true)
      W:advance(1)
      A.ok(t.bar:IsShown() and t.shame:IsShown(), "stats alone: the bar as before")
      A.no(t.cal:IsShown(), "calendar off: no Calendar button")
      ns.Modules.setEnabled("calendar", true)
      W:advance(1)
      A.ok(t.cal:IsShown())
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------- two calendars
    events_and_play_times_are_apart = function(ns, A, W)
      start(ns, W)
      W:advance(70) -- (I have been on: my own play time is in the diary)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local N, L, Cal = ns.Notes, ns.CalendarLogic, ns.Calendar
      Cal.open()
      local _, _, _, today = Cal.viewForTest()
      local function key(day) return N.dateKey(L.civil(day)) end
      -- today: four plain notes, the last by Frostie; tomorrow: Frostie's dungeon run and one more; yesterday: Frostie's
      for i = 1, 3 do A.ok(N.add(key(today), "Mine " .. i, 1)) end
      receive(ns, W, "Frostie", "CALN", { k = "frost123-5000", d = key(today), t = "Bring potions", i = "4", b = "Frostie",
        c = "MAGE", u = "5000" })
      receive(ns, W, "Frostie", "CALN", { k = "frost123-5001", d = key(today + 1), t = "The Deadmines", i = "2",
        b = "Frostie", c = "MAGE", u = "5001", g = "dm" })
      receive(ns, W, "Frostie", "CALN", { k = "frost123-5002", d = key(today + 1), t = "After party", i = "1", b = "Frostie",
        c = "MAGE", u = "5002" })
      receive(ns, W, "Frostie", "CALN", { k = "frost123-5003", d = key(today - 1), t = "Old news", i = "1", b = "Frostie",
        c = "MAGE", u = "5003" })
      -- the Events month: notes only
      Cal.show("events")
      A.eq((Cal.viewForTest()), "events")
      local c = Cal.eventCellForTest(today)
      A.eq(c.notes, 4)
      A.eq(#c.lines, 3, "three lines in a day")
      A.contains(c.lines[1] .. "|" .. c.lines[2], "Mine", "the notes' words")
      A.eq(c.lines[3], "+2 more", "the last line counts the rest")
      A.ok(c.new, "Frostie's unopened note marks the day new")
      local tomorrow = Cal.eventCellForTest(today + 1)
      A.ok(tomorrow.art, "a dungeon run fills its day")
      A.ok(tomorrow.new)
      A.eq(#tomorrow.lines, 0, "no lines over the artwork")
      A.no(Cal.eventCellForTest(today - 1).new, "a past day is never new")
      A.eq(Cal.eventCellForTest(today + 3).notes, 0)
      -- a day's list; opening Frostie's note takes its "new" away
      Cal.openEvents(today)
      A.eq((Cal.viewForTest()), "eventDay")
      A.eq(#Cal.lastNotes, 4)
      local mine, theirs
      for i = 1, 4 do
        local r = Cal.eventRowForTest(i)
        if r.key == "frost123-5000" then theirs = r else mine = r end
      end
      A.ok(theirs and theirs.new, "new in the list")
      A.no(mine.new, "my own note is not new")
      A.ok(ns.NoteView.open("frost123-5000"))
      for i = 1, 4 do A.no(Cal.eventRowForTest(i).new, "opened: no longer new") end
      Cal.show("events")
      A.no(Cal.eventCellForTest(today).new, "nor on the month")
      -- more notes than rows: the wheel scrolls
      for i = 4, 11 do A.ok(N.add(key(today), "Mine " .. i, 1)) end
      Cal.openEvents(today)
      A.eq(#Cal.lastNotes, 12)
      local first = Cal.eventRowForTest(1).key
      Cal.scrollEvents(3)
      A.no(Cal.eventRowForTest(1).key == first, "scrolled")
      Cal.scrollEvents(99)
      A.ok(Cal.eventRowForTest(8), "the last page is full")
      Cal.scrollEvents(-99)
      A.eq(Cal.eventRowForTest(1).key, first, "back to the top")
      -- the Play times month: people only
      Cal.show("month")
      local p = Cal.monthCellForTest(today)
      A.eq(p.people, 1, "me, today")
      A.eq(p.faces, 1)
      A.eq(p.notes, nil, "no notes on the Play times month")
      A.eq(p.art, nil, "and no artwork")
      -- across: a day's events from the timeline, and back
      Cal.openDay(today + 1)
      A.eq((Cal.viewForTest()), "day")
      A.eq(#Cal.lastNotes, 2, "the timeline still knows the day's notes (for its marks)")
      Cal.openEvents(today + 1)
      A.eq((Cal.viewForTest()), "eventDay")
      Cal.show("bogus")
      A.eq((Cal.viewForTest()), "events", "an unknown view is the Events month")
      Cal.close(); Cal.show("usual"); Cal.open()
      A.eq((Cal.viewForTest()), "events", "it always opens on Events")
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------------ the window
    calendar_window = function(ns, A, W)
      start(ns, W)
      W:advance(70)
      W.env.SlashCmdList.TWIZCREW("cal")
      A.ok(ns.Calendar.isShown(), "/tc cal")
      local view, y, m, day = ns.Calendar.viewForTest()
      A.eq(view, "events", "it opens on the Events tab")
      ns.Calendar.show("month")
      A.eq((ns.Calendar.viewForTest()), "month", "the Play times month")
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
      local b = ns.Panel.tabButtonsForTest().cal
      A.ok(b, "a Calendar button next to the panel's tabs")
      b._scripts.OnClick(b, "LeftButton")
      A.ok(ns.Calendar.isShown(), "it opens the calendar")
      -- "Create a note": a plain one for today
      ns.Calendar.openMaker({ day = day })
      ns.Calendar.setMakerForTest("icon", 5)
      A.ok(ns.Calendar.saveMaker("Healer needed tonight"))
      A.eq((ns.Calendar.viewForTest()), "eventDay", "it lands on its day on the Events tab")
      A.eq(#ns.Calendar.lastNotes, 1, "with the note on it")
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
      ns.Calendar.openDay(day)
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
      A.ok(#ns.Calendar.zoneName() >= 3, "a time zone name")
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
