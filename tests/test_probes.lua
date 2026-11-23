-- /tc caltest and /tc chattest: the server-side storage probes (test tools only). With the game functions missing
-- they say so plainly and raise nothing; with stubbed C_Calendar / C_Club they list what the game holds and give the
-- verdict lines; make / send only report when the game functions raise. Every line also lands in the saved log.
local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function printed(W, sub)
  for _, l in ipairs(W.printed) do if l:find(sub, 1, true) then return l end end
end

local function logged(ns, sub)
  for _, l in ipairs(ns.Log.lines()) do if l:find(sub, 1, true) then return l end end
end

local function noErrors(A, ns)
  A.eq(ns.Log.errors(5), {}, "no Lua errors logged")
end

local function raise() error("boom") end

-- A fake C_Calendar holding `events` (day -> list of CalendarDayEvent-like tables) for November 2026, today the
-- 23rd at 20:10. OpenCalendar sends CALENDAR_UPDATE_EVENT_LIST half a second later; AddEvent stores the event being
-- made and sends CALENDAR_NEW_EVENT; ContextMenuEventRemove removes the selected event.
local function fakeCalendar(W, events)
  local cal = { calls = {}, events = events or {} }
  local making, selected
  local function later(event, ...)
    local args = { n = select("#", ...), ... }
    W.env.C_Timer.After(0.5, function() W:fire(event, unpack(args, 1, args.n)) end)
  end
  local function log(name, ...) cal.calls[#cal.calls + 1] = { name, ... } end
  local C = {}
  C.OpenCalendar = function() log("OpenCalendar"); later("CALENDAR_UPDATE_EVENT_LIST") end
  C.SetAbsMonth = function(m, y) log("SetAbsMonth", m, y) end
  C.GetMonthInfo = function(offset) return { month = 11 + offset, year = 2026, numDays = 30, firstWeekday = 1 } end
  C.GetNumDayEvents = function(offset, day)
    if offset ~= 0 then return 0 end
    return #(cal.events[day] or {})
  end
  C.GetDayEvent = function(offset, day, i) return offset == 0 and cal.events[day][i] or nil end
  C.CreateGuildSignUpEvent = function() log("CreateGuildSignUpEvent"); making = { calendarType = "GUILD_EVENT" } end
  C.CreateGuildAnnouncementEvent = function()
    log("CreateGuildAnnouncementEvent"); making = { calendarType = "GUILD_ANNOUNCEMENT" }
  end
  C.EventSetTitle = function(t) making.title = t end
  C.EventSetDescription = function(d) making.description = d end
  C.EventSetType = function(t) making.eventType = t end
  C.EventSetDate = function(m, d, y) making.month, making.day, making.year = m, d, y end
  C.EventSetTime = function(h, m) making.startTime = { hour = h, minute = m } end
  C.CanAddEvent = function() return true end
  C.EventCanEdit = function() return true end
  C.CloseEvent = function() end
  C.GetMaxCreateDate = function() return { year = 2027, month = 11, monthDay = 23 } end
  C.AddEvent = function()
    log("AddEvent")
    local e = making
    e.modStatus, e.invitedBy = "CREATOR", W.state.player
    cal.events[e.day] = cal.events[e.day] or {}
    table.insert(cal.events[e.day], e)
    later("CALENDAR_NEW_EVENT", false)
  end
  C.ContextMenuEventCanRemove = function() return true end
  C.ContextMenuSelectEvent = function(offset, day, i) selected = { offset, day, i } end
  C.ContextMenuEventRemove = function()
    log("ContextMenuEventRemove", selected[2], selected[3])
    table.remove(cal.events[selected[2]], selected[3])
    later("CALENDAR_UPDATE_EVENT_LIST")
  end
  W.env.C_Calendar = C
  W.env.C_DateAndTime = { GetCurrentCalendarTime = function()
    return { year = 2026, month = 11, monthDay = 23, weekday = 2, hour = 20, minute = 10 }
  end }
  cal.api = C
  return cal
end

local NOW = 1700000000 -- the stub's time() at boot (W.wall + W.clock)

local function msg(seconds, text, position)
  return { messageId = { epoch = seconds * 1000000, position = position or 1 }, content = text,
    author = { name = "Ginkan" } }
end

-- A fake C_Club: one guild club "club1" with a Guild stream "s1" and a General stream "s2". history: messages the
-- server sends when asked for older lines (CLUB_MESSAGE_HISTORY_RECEIVED half a second later, nil = no answer).
local function fakeClub(W, messages, history)
  local club = { stream = messages or {}, history = history, sent = {} }
  local function range(list)
    return { oldestMessageId = list[1].messageId, newestMessageId = list[#list].messageId }
  end
  local C = {}
  C.GetGuildClubId = function() return "club1" end
  C.GetStreams = function()
    return { { streamId = "s2", name = "General", streamType = 0 }, { streamId = "s1", name = "Guild", streamType = 1 } }
  end
  C.GetStreamInfo = function() end
  C.FocusStream = function() return true end
  C.GetClubPrivileges = function() return { canCreateMessage = true, canCreateStream = false } end
  C.GetMessageRanges = function(_, sid)
    if sid ~= "s1" or #club.stream == 0 then return {} end
    return { range(club.stream) }
  end
  C.GetMessagesInRange = function(_, sid) return sid == "s1" and club.stream or {} end
  C.RequestMoreMessagesBefore = function(cid, sid)
    if club.history then
      W.env.C_Timer.After(0.5, function()
        for i = #club.history, 1, -1 do table.insert(club.stream, 1, club.history[i]) end
        club.history = {}
        W:fire("CLUB_MESSAGE_HISTORY_RECEIVED", cid, sid, {}, {})
      end)
    end
    return false
  end
  C.SendMessage = function(cid, sid, text)
    club.sent[#club.sent + 1] = text
    table.insert(club.stream, msg(NOW + 10, text, 99))
    W.env.C_Timer.After(0.2, function() W:fire("CLUB_MESSAGE_ADDED", cid, sid, {}) end)
  end
  W.env.C_Club = C
  club.api = C
  return club
end

return {
  files = "toc",
  tests = {
    caltest_without_the_calendar_says_so = function(ns, A, W)
      boot(W)
      W.printed = {}
      tc(W, "caltest")
      A.ok(printed(W, "The game's calendar (C_Calendar) is not available on this game"), "plain line")
      A.ok(logged(ns, "caltest: The game's calendar (C_Calendar) is not available on this game"), "in the saved log")
      tc(W, "caltest make")
      A.ok(printed(W, "so no test event can be made"))
      tc(W, "caltest remove")
      A.ok(printed(W, "so there is nothing to remove"))
      W:advance(20)
      noErrors(A, ns)
    end,

    chattest_without_clubs_says_so = function(ns, A, W)
      boot(W)
      W.printed = {}
      tc(W, "chattest")
      A.ok(printed(W, "Guild chat channels (C_Club) are not available on this game"), "plain line")
      A.ok(printed(W, "History kept by the server: can't tell; messages written before this login: can't tell."))
      A.ok(logged(ns, "chattest: History kept by the server: can't tell"), "in the saved log")
      tc(W, "chattest send")
      A.ok(printed(W, "so no line can be posted"))
      W:advance(20)
      noErrors(A, ns)
    end,

    chattest_with_an_empty_club_table = function(ns, A, W)
      boot(W)
      W.env.C_Club = {}
      W.printed = {}
      tc(W, "chattest")
      A.ok(printed(W, "C_Club functions present (0 of 12)"))
      A.ok(printed(W, "No guild channels to read: GetGuildClubId is missing."))
      A.ok(printed(W, "History kept by the server: can't tell"))
      tc(W, "chattest send")
      A.ok(printed(W, "SendMessage is missing on this game"))
      W:advance(20)
      noErrors(A, ns)
    end,

    caltest_lists_guild_and_test_events = function(ns, A, W)
      boot(W)
      fakeCalendar(W, {
        [1] = { { title = "Children's Week", calendarType = "HOLIDAY" } },
        [5] = { { title = "Raid night", calendarType = "GUILD_EVENT", invitedBy = "Ginkan",
          startTime = { hour = 20, minute = 0 } } },
        [23] = { { title = "TCtest Twiz", calendarType = "GUILD_ANNOUNCEMENT", modStatus = "CREATOR" } },
      })
      W.printed = {}
      tc(W, "caltest")
      A.ok(printed(W, "Calendar functions present (21 of 22)"), "the count")
      A.ok(printed(W, "Missing: GetNumGuildEvents."), "the missing one")
      A.ok(printed(W, "Today is 2026-11-23, 20:10 by the server's calendar clock."))
      W:advance(1)
      A.ok(printed(W, "The server sent the event list after 0.5 s."))
      A.ok(printed(W, "Events the game holds this month (holidays included): 3."))
      A.ok(printed(W, "Day 5: \"Raid night\" (GUILD_EVENT) at 20:00, by Ginkan"), "guild event")
      A.ok(printed(W, "Day 23: \"TCtest Twiz\" (GUILD_ANNOUNCEMENT), made by you"), "test event")
      A.no(printed(W, "Children's Week"), "holidays are not listed")
      A.ok(printed(W, "This month: 2 guild events; TCtest events: 1 (1 made by you)."))
      A.ok(logged(ns, "caltest: Day 5: \"Raid night\""), "in the saved log")
      noErrors(A, ns)
    end,

    caltest_says_when_nothing_came_back = function(ns, A, W)
      boot(W)
      local cal = fakeCalendar(W, {})
      cal.api.OpenCalendar = function() end -- the server never answers
      W.printed = {}
      tc(W, "caltest")
      W:advance(6)
      A.ok(printed(W, "No event list from the server within 5 s"))
      A.ok(printed(W, "Nothing came back: no guild events and no TCtest events this month."))
      noErrors(A, ns)
    end,

    caltest_make_from_the_command_and_the_button = function(ns, A, W)
      boot(W)
      local cal = fakeCalendar(W, {})
      W.printed = {}
      tc(W, "caltest make")
      A.ok(printed(W, "Sign-up form (CreateGuildSignUpEvent): started."))
      A.ok(printed(W, "EventSetTitle ok, EventSetDescription ok, EventSetType ok, EventSetDate ok, EventSetTime ok."))
      A.ok(printed(W, "Event: \"TCtest Twiz\", sign-up form, on 2026-11-23 at 21:15."))
      A.ok(printed(W, "The game says the event can be added: yes."))
      W:advance(2)
      A.ok(printed(W, "AddEvent from the typed command: the server confirmed a new event."))
      A.ok(printed(W, "Your test event is listed now: yes."))
      A.ok(printed(W, "Ways tried so far: typed command: worked (the server confirmed a new event); button: not tried."))
      local win = ns.Probes.forTest.window("caltest")
      A.ok(win and win:IsShown(), "the button window is up")
      win.go._scripts.OnClick(win.go)
      W:advance(2)
      A.ok(printed(W, "AddEvent from the button: the server confirmed a new event."))
      A.ok(printed(W, "button: worked"))
      A.eq(#cal.events[23], 2, "two test events")
      A.eq(cal.events[23][1].eventType, 4, "type Other")
      W.printed = {}
      tc(W, "caltest remove")
      W:advance(3)
      A.ok(printed(W, ": remove asked."))
      A.ok(printed(W, "TCtest events of yours still listed: 0."))
      A.eq(#cal.events[23], 0, "both removed")
      noErrors(A, ns)
    end,

    caltest_make_late_at_night_uses_tomorrow = function(ns, A, W)
      boot(W)
      fakeCalendar(W, {})
      W.env.C_DateAndTime.GetCurrentCalendarTime = function()
        return { year = 2026, month = 11, monthDay = 30, hour = 23, minute = 20 }
      end
      W.printed = {}
      tc(W, "caltest make")
      A.ok(printed(W, "on 2026-12-01 at 00:30."))
      W:advance(20)
      noErrors(A, ns)
    end,

    caltest_make_only_reports_when_the_game_raises = function(ns, A, W)
      boot(W)
      local cal = fakeCalendar(W, {})
      for name in pairs(cal.api) do
        if name ~= "GetMonthInfo" then cal.api[name] = raise end
      end
      W.printed = {}
      tc(W, "caltest make")
      A.ok(printed(W, "Sign-up form (CreateGuildSignUpEvent): failed: "))
      A.ok(printed(W, "Announcement form (CreateGuildAnnouncementEvent): failed: "))
      A.ok(printed(W, "No guild event form could be started, so nothing was made."))
      W:advance(20)
      noErrors(A, ns)
      -- the forms work but every step and AddEvent raise
      cal = fakeCalendar(W, {})
      for _, name in ipairs({ "EventSetTitle", "EventSetDescription", "EventSetType", "EventSetDate", "EventSetTime",
        "AddEvent", "CanAddEvent" }) do cal.api[name] = raise end
      ns.CalTest.forTest.reset()
      W.printed = {}
      tc(W, "caltest make")
      A.ok(printed(W, "EventSetTitle failed ("), "step failures are reported")
      A.ok(printed(W, "The game says the event can be added: unknown ("))
      W:advance(10)
      A.ok(printed(W, "AddEvent from the typed command: AddEvent raised an error ("))
      A.ok(printed(W, "Your test event is listed now: no."))
      A.ok(printed(W, "typed command: did not work"))
      noErrors(A, ns)
    end,

    caltest_make_without_add_event = function(ns, A, W)
      boot(W)
      local cal = fakeCalendar(W, {})
      cal.api.AddEvent = nil
      W.printed = {}
      tc(W, "caltest make")
      A.ok(printed(W, "Cannot make a test event: AddEvent is missing on this game."))
      W:advance(20)
      noErrors(A, ns)
    end,

    caltest_unknown_word_shows_the_usage = function(ns, A, W)
      boot(W)
      W.printed = {}
      tc(W, "caltest what")
      A.ok(printed(W, "/tc caltest make - add a guild test event"))
      tc(W, "chattest what")
      A.ok(printed(W, "/tc chattest send - post a test line to guild chat (the whole guild sees it)"))
      tc(W, "help")
      A.ok(printed(W, "/tc caltest - "), "help lists caltest")
      A.ok(printed(W, "/tc chattest - "), "help lists chattest")
    end,

    chattest_lists_streams_and_says_history_is_kept = function(ns, A, W)
      boot(W)
      ns.ChatTest.forTest.setLoadedAt(NOW)
      fakeClub(W, { msg(NOW + 5, "hello from this login, a fairly long line of chat text here") },
        { msg(NOW - 2 * 86400, "two days old"), msg(NOW - 3600, "an hour old") })
      W.printed = {}
      tc(W, "chattest")
      A.ok(printed(W, "C_Club functions present (9 of 12)"))
      A.ok(printed(W, "Missing: GetMessageRanges") == nil, "GetMessageRanges is there")
      A.ok(printed(W, "Guild club id: club1."))
      A.ok(printed(W, "You may write lines: yes; make channels: no."))
      A.ok(printed(W, "Channel 1: \"General\", type General, id s2."))
      A.ok(printed(W, "Channel 2: \"Guild\", type Guild, id s1."))
      A.ok(printed(W, "  ranges: 1, messages readable: 1, oldest just now, newest just now: \"hello from this login,"
        .. " a fairly long lin\"; focus: yes."), "stream line")
      W:advance(1)
      A.ok(printed(W, "Asked the server for older lines of \"Guild\": 2 more arrived; now 3 readable, oldest 2d ago."))
      A.ok(printed(W, "History kept by the server: yes; messages written before this login: readable (2)."))
      A.ok(logged(ns, "chattest: History kept by the server: yes"), "in the saved log")
      noErrors(A, ns)
    end,

    chattest_says_no_when_the_server_sends_nothing = function(ns, A, W)
      boot(W)
      ns.ChatTest.forTest.setLoadedAt(NOW)
      fakeClub(W, {}, {})
      W.printed = {}
      tc(W, "chattest")
      W:advance(1)
      A.ok(printed(W, "nothing new arrived; now 0 readable."))
      A.ok(printed(W, "History kept by the server: no (nothing came back; maybe nobody has written there yet);"
        .. " messages written before this login: none."))
      noErrors(A, ns)
    end,

    chattest_cannot_tell_without_an_answer = function(ns, A, W)
      boot(W)
      ns.ChatTest.forTest.setLoadedAt(NOW)
      fakeClub(W, { msg(NOW + 5, "new") }, nil)
      W.printed = {}
      tc(W, "chattest")
      W:advance(6)
      A.ok(printed(W, "Asked the server for older lines: no answer within 5 s."))
      A.ok(printed(W, "History kept by the server: can't tell; messages written before this login: can't tell."))
      noErrors(A, ns)
    end,

    chattest_send_from_the_command_and_the_button = function(ns, A, W)
      boot(W)
      local club = fakeClub(W, {}, {})
      W.printed = {}
      tc(W, "chattest send")
      A.ok(printed(W, "(the whole guild sees it)"), "warns")
      W:advance(1)
      A.ok(printed(W, "SendMessage from the typed command: a new line arrived in the channel; the line \"TCtest "))
      A.ok(printed(W, "shows in the channel: yes."))
      local win = ns.Probes.forTest.window("chattest")
      A.ok(win and win:IsShown(), "the button window is up")
      win.go._scripts.OnClick(win.go)
      W:advance(1)
      A.ok(printed(W, "SendMessage from the button: a new line arrived"))
      A.eq(#club.sent, 2)
      noErrors(A, ns)
    end,

    chattest_send_only_reports_when_the_game_raises = function(ns, A, W)
      boot(W)
      local club = fakeClub(W, {}, {})
      club.api.SendMessage = raise
      W.printed = {}
      tc(W, "chattest send")
      W:advance(6)
      A.ok(printed(W, "SendMessage from the typed command: SendMessage raised an error ("))
      A.ok(printed(W, "shows in the channel: no."))
      A.ok(printed(W, "typed command: did not work"))
      -- every C_Club function raises: run and send only report
      for name in pairs(club.api) do club.api[name] = raise end
      ns.ChatTest.forTest.reset()
      W.printed = {}
      tc(W, "chattest")
      A.ok(printed(W, "No guild channels to read: GetGuildClubId failed: "))
      tc(W, "chattest send")
      A.ok(printed(W, "Cannot post: GetGuildClubId failed: "))
      W:advance(10)
      noErrors(A, ns)
    end,

    chattest_secret_content_is_never_shown = function(ns, A, W)
      boot(W)
      ns.ChatTest.forTest.setLoadedAt(NOW)
      fakeClub(W, { { messageId = { epoch = (NOW - 60) * 1000000, position = 1 }, content = W.secret() } }, {})
      W.printed = {}
      tc(W, "chattest")
      A.ok(printed(W, "newest 1m ago: \"hidden\""))
      W:advance(1)
      A.ok(printed(W, "History kept by the server: yes; messages written before this login: readable (1)."))
      noErrors(A, ns)
    end,
  },
}
