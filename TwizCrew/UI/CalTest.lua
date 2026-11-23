-- /tc caltest: a test tool (changes no addon behaviour) that checks in the real game whether the game's own guild
-- calendar (C_Calendar, stored by Blizzard's server) can carry a note to guild mates who log on while the author is
-- offline. Shapes from Blizzard's Classic Era calendar code: SetAbsMonth(month, year), then OpenCalendar() asks the
-- server (CALENDAR_UPDATE_EVENT_LIST); GetNumDayEvents(monthOffset, day) / GetDayEvent(monthOffset, day, index) read
-- the month set by SetAbsMonth (offset 0), day and index from 1; creating is Create...Event() -> EventSet...() ->
-- AddEvent() (restricted: the player's own key press or click); deleting is ContextMenuSelectEvent(offset, day, index)
-- -> ContextMenuEventRemove(). Every line goes to chat and the saved log (UI/Probes.lua).
--   /tc caltest          which calendar functions exist, then this month's guild events and any "TCtest" event
--   /tc caltest make     makes a guild event "TCtest <name>" (typed command first, and a button to click)
--   /tc caltest remove   removes the TCtest events this character made
local _, ns = ...

local CalTest = {}
ns.CalTest = CalTest

local P = ns.Probes
local FEATURE = "caltest"
local say = P.sayer("caltest")
local field = P.field

local LIST_WAIT = 5   -- s: how long the server has to send the event list
local ADD_WAIT = 8    -- s: how long the server has to confirm a new event
local REMOVE_WAIT = 4 -- s: how long the server has to send the list after a removal
local BUSY_MAX = 40   -- s: a run older than this no longer blocks a new one
local MAX_LINES = 15  -- events listed at most
local DESCRIPTION = "TwizCrew test event. Safe to ignore; /tc caltest remove takes it away."

local CHECKS = {
  { "C_Calendar", "OpenCalendar" }, { "C_Calendar", "CreateGuildSignUpEvent" },
  { "C_Calendar", "CreateGuildAnnouncementEvent" }, { "C_Calendar", "EventSetTitle" },
  { "C_Calendar", "EventSetDescription" }, { "C_Calendar", "EventSetType" }, { "C_Calendar", "EventSetDate" },
  { "C_Calendar", "EventSetTime" }, { "C_Calendar", "AddEvent" }, { "C_Calendar", "CloseEvent" },
  { "C_Calendar", "GetNumDayEvents" }, { "C_Calendar", "GetDayEvent" }, { "C_Calendar", "GetMonthInfo" },
  { "C_Calendar", "SetAbsMonth" }, { "C_Calendar", "GetMaxCreateDate" }, { "C_Calendar", "ContextMenuSelectEvent" },
  { "C_Calendar", "ContextMenuEventRemove" }, { "C_Calendar", "ContextMenuEventCanRemove" },
  { "C_Calendar", "EventCanEdit" }, { "C_Calendar", "CanAddEvent" }, { "C_Calendar", "GetNumGuildEvents" },
  { "C_DateAndTime", "GetCurrentCalendarTime" },
}

local busySince
local tried = {} -- way ("typed command" / "button") -> what happened

local function cal(name) return P.fn(C_Calendar, name) end

local function busy()
  if busySince and ns.now() - busySince < BUSY_MAX then
    say("A calendar test is still running. Wait a few seconds and try again.")
    return true
  end
  busySince = ns.now()
  return false
end
local function free() busySince = nil end

-- Today by the server's calendar clock: { year, month, day, hour, minute, server = true }, else the computer's clock
-- (server = false), else nil.
local function today()
  local ok, t = P.try(P.fn(C_DateAndTime, "GetCurrentCalendarTime"))
  if ok and type(t) == "table" then
    local y, m, d = field(t, "year"), field(t, "month"), field(t, "monthDay")
    if type(y) == "number" and type(m) == "number" and type(d) == "number" then
      return { year = y, month = m, day = d, hour = tonumber(field(t, "hour")) or 0,
        minute = tonumber(field(t, "minute")) or 0, server = true }
    end
  end
  local okD, d = P.try(date, "*t")
  if okD and type(d) == "table" and type(d.year) == "number" then
    return { year = d.year, month = d.month, day = d.day, hour = d.hour or 0, minute = d.min or 0, server = false }
  end
end

local function numDays(offset)
  local ok, info = P.try(cal("GetMonthInfo"), offset)
  local n = ok and tonumber(field(info, "numDays")) or nil
  if n and n >= 28 and n <= 31 then return n end
  return 31
end

-- Every event the game holds for the month at this offset: { offset, day, index, title, ctype, by, mod, hour,
-- minute }. Second result: an error text when reading failed.
local function readMonth(offset)
  local out = {}
  local numFn, getFn = cal("GetNumDayEvents"), cal("GetDayEvent")
  if not numFn or not getFn then return out, "GetNumDayEvents or GetDayEvent is missing" end
  for day = 1, numDays(offset) do
    local ok, n = P.try(numFn, offset, day)
    if not ok then return out, "GetNumDayEvents failed: " .. tostring(n) end
    for i = 1, math.min(tonumber(n) or 0, 50) do
      local okE, e = P.try(getFn, offset, day, i)
      if okE and type(e) == "table" then
        local start = field(e, "startTime")
        out[#out + 1] = { offset = offset, day = day, index = i, title = field(e, "title"),
          ctype = field(e, "calendarType"), by = field(e, "invitedBy"), mod = field(e, "modStatus"),
          hour = field(start, "hour"), minute = field(start, "minute") }
      end
    end
  end
  return out
end

local function isGuild(ev) return ev.ctype == "GUILD_EVENT" or ev.ctype == "GUILD_ANNOUNCEMENT" end
local function isTest(ev) return type(ev.title) == "string" and ev.title:sub(1, 6) == "TCtest" end

-- "TCtest Yaboytwi": the first 8 letters of the character's name, 31 bytes at most (the game's title limit).
local function myTitle() return P.cut("TCtest " .. P.cut(P.myName(), 8), 31, 31) end

local function mine(ev)
  if ev.mod == "CREATOR" or ev.title == myTitle() then return true end
  local by = type(ev.by) == "string" and ev.by:match("^[^%s%-]+") or nil
  return by ~= nil and by == P.myName()
end

local function describe(ev)
  local when = ev.offset == 0 and ("Day " .. ev.day) or ("Next month, day " .. ev.day)
  local at = (type(ev.hour) == "number" and type(ev.minute) == "number")
    and string.format(" at %02d:%02d", ev.hour, ev.minute) or ""
  local by = ""
  if type(ev.by) == "string" and ev.by ~= "" then by = ", by " .. ev.by end
  if ev.mod == "CREATOR" then by = by .. ", made by you" end
  return when .. ": \"" .. P.text(ev.title) .. "\" (" .. P.text(ev.ctype) .. ")" .. at .. by
end

-- Lists this month's guild events and every TCtest event (this month and next). Returns { guild, tests, mineTests,
-- all }.
local function report()
  local month, err = readMonth(0)
  if err then say("Could not read the month: " .. err .. ".") end
  local nextMonth = readMonth(1)
  local shown, guild, tests, mineTests = {}, 0, 0, 0
  for _, ev in ipairs(month) do
    if isGuild(ev) then guild = guild + 1 end
    if isGuild(ev) or isTest(ev) then shown[#shown + 1] = ev end
  end
  for _, ev in ipairs(nextMonth) do
    if isTest(ev) then shown[#shown + 1] = ev end
  end
  for _, ev in ipairs(shown) do
    if isTest(ev) then
      tests = tests + 1
      if mine(ev) then mineTests = mineTests + 1 end
    end
  end
  say("Events the game holds this month (holidays included): " .. #month .. ".")
  if #shown == 0 then
    say("Nothing came back: no guild events and no TCtest events this month.")
  else
    for i = 1, math.min(#shown, MAX_LINES) do say(describe(shown[i])) end
    if #shown > MAX_LINES then say("... and " .. (#shown - MAX_LINES) .. " more.") end
  end
  say("This month: " .. guild .. " guild events; TCtest events: " .. tests .. " (" .. mineTests .. " made by you).")
  local numGuild = cal("GetNumGuildEvents")
  if numGuild then
    local ok, n = P.try(numGuild)
    if ok and type(n) == "number" then
      local names = {}
      local infoFn = cal("GetGuildEventInfo")
      for i = 1, math.min(n, 30) do
        local okI, info = P.try(infoFn, i)
        local title = okI and field(info, "title")
        if type(title) == "string" and title:sub(1, 6) == "TCtest" then names[#names + 1] = "\"" .. title .. "\"" end
      end
      say("The guild's upcoming-events list holds " .. n .. " events" .. (#names > 0 and ("; TCtest: "
        .. table.concat(names, ", ")) or "") .. ".")
    else
      say("The guild's upcoming-events list could not be read" .. (ok and "" or (": " .. tostring(n))) .. ".")
    end
  end
  return { guild = guild, tests = tests, mineTests = mineTests, all = #month }
end

-- Asks the server for the events (SetAbsMonth to this month, OpenCalendar), waits for its list, then lists.
-- after(summary) with report()'s summary.
local function refreshAndList(after)
  local t = today()
  if t then P.try(cal("SetAbsMonth"), t.month, t.year) end
  local open = cal("OpenCalendar")
  if not open then
    say("OpenCalendar is missing, so the server cannot be asked. Listing what the game already has.")
    after(report())
    return
  end
  local started = ns.now()
  P.wait({ "CALENDAR_UPDATE_EVENT_LIST" }, LIST_WAIT, function(event)
    if event then
      say(string.format("The server sent the event list after %.1f s.", ns.now() - started))
    else
      say("No event list from the server within " .. LIST_WAIT .. " s. Listing what the game has anyway.")
    end
    after(report())
  end, nil, FEATURE)
  local ok, err = P.try(open)
  if not ok then say("OpenCalendar failed: " .. err .. ".") end
end

function CalTest.run()
  if type(C_Calendar) ~= "table" then
    say("The game's calendar (C_Calendar) is not available on this game, so there is nothing to test.")
    say("C_DateAndTime.GetCurrentCalendarTime: " .. (P.fn(C_DateAndTime, "GetCurrentCalendarTime") and "present"
      or "missing") .. ".")
    return
  end
  if busy() then return end
  local have, miss = {}, {}
  for _, c in ipairs(CHECKS) do
    local name = (c[1] == "C_Calendar" and "" or (c[1] .. ".")) .. c[2]
    if P.fn(_G[c[1]], c[2]) then have[#have + 1] = name else miss[#miss + 1] = name end
  end
  say("Calendar functions present (" .. #have .. " of " .. #CHECKS .. "): " .. table.concat(have, ", ") .. ".")
  say("Missing: " .. (#miss > 0 and table.concat(miss, ", ") or "none") .. ".")
  local t = today()
  if t then
    say(string.format("Today is %d-%02d-%02d, %02d:%02d by the %s.", t.year, t.month, t.day, t.hour, t.minute,
      t.server and "server's calendar clock" or "computer's clock (the server's could not be read)"))
  end
  refreshAndList(function()
    free()
    say("Done. Type /tc caltest make to add a test event the whole guild can see.")
  end)
end

-- When to make the test event: an hour from now, on a quarter hour; tomorrow when that is past midnight.
local function whenToMake(t)
  local minutes = t.hour * 60 + t.minute + 60
  minutes = math.ceil(minutes / 15) * 15
  local y, m, d = t.year, t.month, t.day
  if minutes >= 24 * 60 then
    minutes = minutes - 24 * 60
    d = d + 1
    if d > numDays(0) then
      d, m = 1, m + 1
      if m > 12 then m, y = 1, y + 1 end
    end
  end
  return y, m, d, math.floor(minutes / 60), minutes % 60
end

local function summary()
  say("Ways tried so far: typed command: " .. (tried["typed command"] or "not tried") .. "; button: "
    .. (tried["button"] or "not tried") .. ".")
end

-- One try at making the test event. way: "typed command" or "button". after() when done (the list re-read).
local function attempt(way, after)
  local addFn = cal("AddEvent")
  local signUp, announce = cal("CreateGuildSignUpEvent"), cal("CreateGuildAnnouncementEvent")
  if not addFn or (not signUp and not announce) then
    say("Cannot make a test event: " .. (addFn and "both guild event forms are" or "AddEvent is")
      .. " missing on this game.")
    tried[way] = "not possible here"
    after()
    return
  end
  local t = today()
  if not t then
    say("The game gives no date, so no event can be made.")
    tried[way] = "no date"
    after()
    return
  end
  P.try(cal("SetAbsMonth"), t.month, t.year)
  P.try(cal("CloseEvent"))
  local form
  if signUp then
    local ok, err = P.try(signUp)
    say("Sign-up form (CreateGuildSignUpEvent): " .. (ok and "started" or ("failed: " .. err)) .. ".")
    if ok then form = "sign-up" end
  else
    say("CreateGuildSignUpEvent is missing; trying the announcement form.")
  end
  if not form and announce then
    local ok, err = P.try(announce)
    say("Announcement form (CreateGuildAnnouncementEvent): " .. (ok and "started" or ("failed: " .. err)) .. ".")
    if ok then form = "announcement" end
  end
  if not form then
    say("No guild event form could be started, so nothing was made.")
    tried[way] = "no form"
    after()
    return
  end
  local y, m, d, hour, minute = whenToMake(t)
  local title = myTitle()
  local eventType = Enum and type(Enum.CalendarEventType) == "table" and Enum.CalendarEventType.Other or 4
  local steps = {
    { "EventSetTitle", title }, { "EventSetDescription", DESCRIPTION }, { "EventSetType", eventType },
    { "EventSetDate", m, d, y }, { "EventSetTime", hour, minute },
  }
  local results = {}
  for _, s in ipairs(steps) do
    local f = cal(s[1])
    if not f then
      results[#results + 1] = s[1] .. " missing"
    else
      local ok, err = P.try(f, unpack(s, 2))
      results[#results + 1] = s[1] .. (ok and " ok" or (" failed (" .. err .. ")"))
    end
  end
  say(table.concat(results, ", ") .. ".")
  say(string.format("Event: \"%s\", %s form, on %d-%02d-%02d at %02d:%02d.", title, form, y, m, d, hour, minute))
  local maxFn = cal("GetMaxCreateDate")
  if maxFn then
    local ok, latest = P.try(maxFn)
    local ly, lm, ld = field(latest, "year"), field(latest, "month"), field(latest, "monthDay")
    if ok and type(ly) == "number" and type(lm) == "number" and type(ld) == "number" then
      say(string.format("The latest day the game allows: %d-%02d-%02d.", ly, lm, ld))
    end
  end
  if cal("CanAddEvent") then
    local ok, can = P.try(cal("CanAddEvent"))
    say("The game says the event can be added: " .. (ok and P.yesNo(can) or ("unknown (" .. tostring(can) .. ")"))
      .. ".")
  end
  local callError
  P.wait({ "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_ERROR", "CALENDAR_UPDATE_ERROR_WITH_COUNT",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }, ADD_WAIT, function(event, a1, a2)
    local result
    if callError then
      result = "AddEvent raised an error (" .. callError .. ")"
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
      result = "the game blocked AddEvent (it wants a key press or click)"
    elseif event == "CALENDAR_UPDATE_ERROR" or event == "CALENDAR_UPDATE_ERROR_WITH_COUNT" then
      result = "the server refused it (" .. P.text(a1) .. ")"
    elseif event == "CALENDAR_NEW_EVENT" then
      result = "the server confirmed a new event"
    else
      result = "no answer from the server within " .. ADD_WAIT .. " s"
    end
    say("AddEvent from the " .. way .. ": " .. result .. ".")
    refreshAndList(function(found)
      local listed = found.mineTests > 0
      say("Your test event is listed now: " .. (listed and "yes" or "no") .. ".")
      tried[way] = (listed and "worked" or "did not work") .. " (" .. result .. ")"
      summary()
      after()
    end)
  end, function(event, addon)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
      return not ns.Util.isSecret(addon) and addon == ns.ADDON
    end
    return true
  end, FEATURE)
  local ok, err = P.try(addFn)
  if not ok then callError = err end
end

function CalTest.make()
  if type(C_Calendar) ~= "table" then
    say("The game's calendar (C_Calendar) is not available on this game, so no test event can be made.")
    return
  end
  if busy() then return end
  say("Making a guild test event from the typed command (the whole guild can see it).")
  attempt("typed command", function()
    free()
    if tried["typed command"] == "not possible here" then return end
    say("Now click \"Create test event\" in the small window to try the same with a click (it makes a second"
      .. " test event).")
    P.button("caltest", "Create test event", function()
      if busy() then return end
      attempt("button", function()
        free()
        say("Type /tc caltest remove to take your test events away.")
      end)
    end, FEATURE)
  end)
end

function CalTest.remove()
  if type(C_Calendar) ~= "table" then
    say("The game's calendar (C_Calendar) is not available on this game, so there is nothing to remove.")
    return
  end
  local selectFn, removeFn = cal("ContextMenuSelectEvent"), cal("ContextMenuEventRemove")
  if not selectFn or not removeFn then
    say("Removing is not possible here: " .. (selectFn and "ContextMenuEventRemove" or "ContextMenuSelectEvent")
      .. " is missing on this game.")
    return
  end
  if busy() then return end
  refreshAndList(function()
    local list = readMonth(0)
    for _, ev in ipairs(readMonth(1)) do list[#list + 1] = ev end
    local removed, kept = 0, 0
    for i = #list, 1, -1 do -- last first, so a removal cannot move the events still to do
      local ev = list[i]
      if isTest(ev) then
        if not mine(ev) then
          kept = kept + 1
          say(describe(ev) .. ": someone else's, left alone.")
        else
          local okC, can = P.try(cal("ContextMenuEventCanRemove"), ev.offset, ev.day, ev.index)
          if okC and can == false then
            kept = kept + 1
            say(describe(ev) .. ": the game says it cannot be removed.")
          else
            local okS, errS = P.try(selectFn, ev.offset, ev.day, ev.index)
            local okR, errR = P.try(removeFn)
            if okS and okR then removed = removed + 1 end
            say(describe(ev) .. ": " .. ((okS and okR) and "remove asked"
              or ("remove failed (" .. tostring(okS and errR or errS) .. ")")) .. ".")
          end
        end
      end
    end
    if removed == 0 and kept == 0 then say("No TCtest events found, so nothing was removed.") end
    if removed == 0 then free(); return end
    P.wait({ "CALENDAR_UPDATE_EVENT_LIST", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }, REMOVE_WAIT,
      function(event)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
          say("The game blocked the removal (it may want a click).")
        end
        refreshAndList(function(found)
          free()
          say("TCtest events of yours still listed: " .. found.mineTests .. ".")
        end)
      end, function(event, addon)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
          return not ns.Util.isSecret(addon) and addon == ns.ADDON
        end
        return true
      end, FEATURE)
  end)
end

local USAGE = "/tc caltest - check the game's guild calendar; /tc caltest make - add a guild test event (the whole"
  .. " guild sees it); /tc caltest remove - take your test events away."

function CalTest.command(rest)
  local what = ns.Util.trim(tostring(rest or "")):lower()
  if what == "" then CalTest.run()
  elseif what == "make" then CalTest.make()
  elseif what == "remove" then CalTest.remove()
  else say(USAGE) end
end

CalTest.forTest = { reset = function() busySince = nil; tried = {} end, title = myTitle }
