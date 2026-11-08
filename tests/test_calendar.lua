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
    notes_checksums_trigger_a_swap = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      ns.Notes.add("2026-11-20", "Raid night", 3)
      local before = #W.sent
      receive(ns, W, "Frostie", "CALD", { nh = "12345" })
      W:advance(1)
      local asks = sent(ns, W, "CALQ", before)
      A.eq(#asks, 1); A.eq(asks[1].fields.n, "1", "different notes: ask for theirs")
      before = #W.sent
      receive(ns, W, "Frostie", "CALQ", { n = "1" })
      W:advance(3)
      A.eq(#sent(ns, W, "CALN", before), 1, "they asked: all my notes go to them")
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
      -- a note from the day view, with a picked icon
      ns.Calendar.openDay(day)
      ns.Calendar.pickIcon(5)
      ns.Calendar.typeNoteForTest("Healer needed tonight")
      A.eq(#ns.Calendar.lastNotes, 1)
      A.eq(ns.Calendar.lastNotes[1].i, 5)
      A.eq(ns.Calendar.lastNotes[1].t, "Healer needed tonight")
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
