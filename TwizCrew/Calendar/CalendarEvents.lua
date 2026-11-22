-- Crew calendar, the Events tab: a month that shows only the crew's notes and events (no play times), and a day's
-- list of them. A dungeon or raid fills its day with its artwork; other notes are short lines (icon, time, the first
-- words). A note by someone else that I have not opened yet, today or later, carries a gold "new". Part of the
-- calendar window (Calendar/CalendarUI.lua); shared names live on ns.Calendar._ (P). Who played when is the other
-- tab: Calendar/CalendarMonth.lua, CalendarDay.lua and CalendarUsual.lua.
local _, ns = ...

local Calendar = ns.Calendar
local P = Calendar._

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic
local PREV_TEX, NEXT_TEX = P.PREV_TEX, P.NEXT_TEX
local WIDTH, HEIGHT, PAD, TOP = P.WIDTH, P.HEIGHT, P.PAD, P.TOP
local script, colored, setArt = P.script, P.colored, P.setArt
local dateKeyOf, iconTexture, arrowButton = P.dateKeyOf, P.iconTexture, P.arrowButton

local CELL_W, CELL_H = 96, 68
local LINES = 3          -- note lines in a day cell (the last one says "+2 more" when there are more)
local ROWS, ROW_H = 8, 46 -- a day's list
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
local WAITING = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t"
local cells, rows = {}, {}
P.eventScroll = 0 -- the day list's first row (more notes than rows: the mouse wheel scrolls)

-- New for me: someone else's note that I have not opened, on a day from today on.
local function isNew(n, day, today)
  return day >= today and ns.Notes.isNew(n.key)
end

-- "8pm Deadmines" for a cell line or a tooltip (the time in gold).
local function lineText(n, off)
  local when = ns.Notes.timeText(n, off)
  return (when and ("|cffffd100" .. when .. "|r ") or "") .. ns.Util.safeText(n.t)
end

-- "  (tick) 3  (dot) 1  2 comments" for a note, "" when nobody answered.
local function countsText(key)
  local rp = ns.Notes.repliesFor(key)
  local out = ""
  if #rp.yes > 0 then out = out .. "  " .. READY .. #rp.yes end
  if #rp.maybe > 0 then out = out .. "  " .. WAITING .. #rp.maybe end
  if #rp.comments > 0 then
    out = out .. "  |cffaaaaaa" .. #rp.comments .. (#rp.comments == 1 and " comment" or " comments") .. "|r"
  end
  return out, rp
end

-------------------------------------------------------------------------------------------------------- month
local function buildEvents()
  P.eventsPane = CreateFrame("Frame", nil, P.frame)
  P.eventsPane:SetPoint("TOPLEFT", P.frame, "TOPLEFT", PAD, -TOP)
  P.eventsPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local prev = arrowButton(P.eventsPane, PREV_TEX, function() Calendar.moveMonth(-1) end)
  prev:SetPoint("TOPLEFT", P.eventsPane, "TOPLEFT", 0, 2)
  local nxt = arrowButton(P.eventsPane, NEXT_TEX, function() Calendar.moveMonth(1) end)
  nxt:SetPoint("TOPRIGHT", P.eventsPane, "TOPLEFT", 7 * CELL_W, 2)
  P.eventsPane.label = T.readable(T.text(P.eventsPane, T.FONT.normal, C.title), 3)
  P.eventsPane.label:SetPoint("TOP", P.eventsPane, "TOPLEFT", 7 * CELL_W / 2, -2)
  for i = 1, 7 do
    local h = T.text(P.eventsPane, T.FONT.small, (i == 1 or i == 7) and C.title or C.muted)
    h:SetPoint("TOP", P.eventsPane, "TOPLEFT", (i - 1) * CELL_W + CELL_W / 2, -28)
    h:SetText(L.WEEKDAYS[i])
  end
  for i = 1, 42 do
    local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
    local c = CreateFrame("Button", nil, P.eventsPane)
    c:SetSize(CELL_W - 3, CELL_H - 3)
    c:SetPoint("TOPLEFT", P.eventsPane, "TOPLEFT", col * CELL_W, -(44 + row * CELL_H))
    local weekend = col == 0 or col == 6
    T.paint(c, weekend and C.backdrop or C.row, 0.9, C.rowBorder, 1)
    c.art = c:CreateTexture(nil, "BORDER")
    c.art:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    c.art:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
    c.art:Hide()
    c.shade = c:CreateTexture(nil, "BORDER", nil, 2) -- darker toward the bottom, so the words read on any picture
    c.shade:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    c.shade:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
    T.gradient(c.shade, "VERTICAL", "000000", "000000", 0.85, 0.1)
    c.shade:Hide()
    c.artText = T.readable(T.text(c, T.FONT.small, C.white), 1)
    c.artText:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 4, 4)
    c.artText:SetWidth(CELL_W - 12)
    c.artText:SetJustifyH("LEFT")
    if c.artText.SetShadowOffset then c.artText:SetShadowOffset(2, -2) end
    if c.artText.SetShadowColor then c.artText:SetShadowColor(0, 0, 0, 1) end
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints(c)
    T.color(c.hl, C.title, 0.10)
    c.num = T.readable(T.text(c, T.FONT.normal, C.text))
    c.num:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -4)
    c.fresh = T.readable(T.text(c, T.FONT.small, C.title), 1)
    c.fresh:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, -5)
    c.fresh:SetText("new")
    c.today = c:CreateTexture(nil, "OVERLAY")
    c.today:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.today:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    T.color(c.today, C.title, 0.12)
    c.todayLine = c:CreateTexture(nil, "OVERLAY")
    c.todayLine:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.todayLine:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    c.todayLine:SetHeight(2)
    T.color(c.todayLine, C.title, 1)
    c.lines = {}
    for k = 1, LINES do
      local line = {}
      line.icon = c:CreateTexture(nil, "ARTWORK")
      line.icon:SetSize(11, 11)
      line.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -(21 + (k - 1) * 14))
      line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      line.text = T.readable(T.text(c, T.FONT.small, C.text))
      line.text:SetPoint("LEFT", line.icon, "RIGHT", 3, 0)
      line.text:SetWidth(CELL_W - 24)
      line.text:SetJustifyH("LEFT")
      if line.text.SetWordWrap then line.text:SetWordWrap(false) end
      c.lines[k] = line
    end
    script(c, "OnClick", function(self) if self.tcDay then Calendar.openEvents(self.tcDay) end end)
    script(c, "OnMouseUp", function(self, button)
      if button == "RightButton" and self.tcDay then Widgets.menu(self, Calendar.dayMenuItems(self.tcDay)) end
    end)
    script(c, "OnEnter", function(self)
      if not GameTooltip or not self.tcDay then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local _, m, d = L.civil(self.tcDay)
      GameTooltip:SetText(L.WEEKDAYS[L.weekday(self.tcDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
      local off = ns.Diary.offsetOn(self.tcDay)
      for _, n in ipairs(self.tcNotes or {}) do
        GameTooltip:AddLine("|T" .. ns.Notes.iconTexture(n.i) .. ":14|t " .. lineText(n, off) .. "  |cff999999- "
          .. colored(n.b, n.c) .. "|r" .. (countsText(n.key)), 1, 0.9, 0.5, true)
      end
      if #(self.tcNotes or {}) == 0 then GameTooltip:AddLine("Nothing planned.", 0.8, 0.8, 0.8) end
      GameTooltip:AddLine("Click for this day's notes. Right-click to add one, or to edit or remove yours.", 0.7, 0.7,
        0.7, true)
      GameTooltip:Show()
    end)
    script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cells[i] = c
  end
end
P.buildEvents = buildEvents

local function drawEvents()
  local today = ns.Diary.localToday()
  P.eventsPane.label:SetText(L.MONTHS[P.shownMonth] .. " " .. P.shownYear)
  for i, cell in ipairs(L.monthGrid(P.shownYear, P.shownMonth)) do
    local c = cells[i]
    c.tcDay = cell.day
    c.num:SetText(cell.d)
    local off = ns.Diary.offsetOn(cell.day) -- each day its own (a clock change moves it)
    local notes = ns.Notes.forDate(ns.Notes.dateKey(cell.y, cell.m, cell.d))
    c.tcNotes = notes
    local fresh = false
    for _, n in ipairs(notes) do if isNew(n, cell.day, today) then fresh = true end end
    c.tcNew = fresh
    if fresh then c.fresh:Show() else c.fresh:Hide() end
    -- a dungeon or raid that day: its artwork fills the day, its time and name on top
    local event
    for _, n in ipairs(notes) do if n.g then event = n; break end end
    c.tcArt, c.tcLines = nil, {}
    if event then
      c.tcArt = setArt(c.art, event.g, ns.Notes.iconTexture(event.i)) and "art" or "icon"
      c.art:Show(); c.shade:Show()
      local going = #ns.Notes.repliesFor(event.key).yes
      local others = #notes - 1
      c.artText:SetText(lineText(event, off) .. (going > 0 and ("\n|cff40ff40" .. going .. " going|r") or "")
        .. (others > 0 and ("  |cffcccccc+" .. others .. " more|r") or ""))
      c.artText:Show()
      for _, line in ipairs(c.lines) do line.icon:Hide(); line.text:SetText("") end
    else
      c.art:Hide(); c.shade:Hide(); c.artText:Hide()
      for k, line in ipairs(c.lines) do
        local n = notes[k]
        if n and k == LINES and #notes > LINES then
          line.icon:Hide()
          c.tcLines[k] = "+" .. (#notes - LINES + 1) .. " more"
          line.text:SetText("|cff9a8f70" .. c.tcLines[k] .. "|r")
        elseif n then
          line.icon:SetTexture(ns.Notes.iconTexture(n.i))
          line.icon:Show()
          c.tcLines[k] = lineText(n, off)
          line.text:SetText(c.tcLines[k])
        else
          line.icon:Hide()
          line.text:SetText("")
        end
      end
    end
    -- what is over is dimmer: the eye goes to today and what is coming
    c:SetAlpha(cell.inMonth and (cell.day >= today and 1 or 0.55) or 0.3)
    if cell.day == today then c.today:Show(); c.todayLine:Show() else c.today:Hide(); c.todayLine:Hide() end
  end
end
P.drawEvents = drawEvents

-- Test hook: what the Events month shows for a local day ({ lines, new, art, notes }), or nil when it is not on it.
function Calendar.eventCellForTest(day)
  for _, c in ipairs(cells) do
    if c.tcDay == day then return { lines = c.tcLines, new = c.tcNew, art = c.tcArt, notes = #(c.tcNotes or {}) } end
  end
  return nil
end

-------------------------------------------------------------------------------------------------------- a day
local function buildEventDay()
  P.eventDayPane = CreateFrame("Frame", nil, P.frame)
  P.eventDayPane:SetPoint("TOPLEFT", P.frame, "TOPLEFT", PAD, -TOP)
  P.eventDayPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local back = Widgets.button(P.eventDayPane, "Back to the month", function() Calendar.show("events") end, nil, FEATURE)
  back:SetPoint("TOPLEFT", P.eventDayPane, "TOPLEFT", 0, 0)
  local prev = arrowButton(P.eventDayPane, PREV_TEX, function() Calendar.openEvents(P.shownDay - 1) end)
  prev:SetPoint("LEFT", back, "RIGHT", 8, 0)
  local nxt = arrowButton(P.eventDayPane, NEXT_TEX, function() Calendar.openEvents(P.shownDay + 1) end)
  nxt:SetPoint("LEFT", prev, "RIGHT", 2, 0)
  P.eventDayPane.label = T.readable(T.text(P.eventDayPane, T.FONT.normal, C.title), 2)
  P.eventDayPane.label:SetPoint("LEFT", nxt, "RIGHT", 10, 0)
  local played = Widgets.button(P.eventDayPane, "Who played this day", function() Calendar.openDay(P.shownDay) end, nil,
    FEATURE)
  played:SetPoint("TOPRIGHT", P.eventDayPane, "TOPRIGHT", 0, 0)
  P.eventDayPane.empty = T.text(P.eventDayPane, T.FONT.normal, C.muted)
  P.eventDayPane.empty:SetPoint("TOPLEFT", P.eventDayPane, "TOPLEFT", 0, -44)
  P.eventDayPane.empty:SetText("Nothing planned this day yet. Add a note below: the whole crew sees it.")
  P.eventDayPane:EnableMouseWheel(true)
  script(P.eventDayPane, "OnMouseWheel", function(_, delta) Calendar.scrollEvents(-delta) end)
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, P.eventDayPane)
    r:SetSize(WIDTH - 2 * PAD, ROW_H - 4)
    r:SetPoint("TOPLEFT", P.eventDayPane, "TOPLEFT", 0, -(34 + (i - 1) * ROW_H))
    T.paint(r, C.row, 0.9, C.rowBorder, 1)
    r.icon = iconTexture(r, nil, 30)
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.text = T.readable(T.text(r, T.FONT.normal, C.text))
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.text:SetWidth(WIDTH - 2 * PAD - 180)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.sub = T.text(r, T.FONT.small, C.muted)
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
    r.sub:SetWidth(WIDTH - 2 * PAD - 180)
    r.sub:SetJustifyH("LEFT")
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
    r.del = Widgets.button(r, "Remove", function() if r.tcKey then ns.Notes.remove(r.tcKey) end end, "danger", FEATURE)
    r.del:SetSize(64, 20)
    r.del:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.edit = Widgets.button(r, "Edit", function() if r.tcKey then Calendar.openMaker({ edit = r.tcKey }) end end, nil,
      FEATURE)
    r.edit:SetSize(48, 20)
    r.edit:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints(r)
    T.color(r.hl, C.title, 0.08)
    r:EnableMouse(true)
    script(r, "OnMouseUp", function(self, button)
      if button == "LeftButton" and self.tcKey and ns.NoteView then ns.NoteView.open(self.tcKey) end
      if button == "RightButton" and self.tcKey then Widgets.menu(self, Calendar.noteMenuItems(self.tcKey)) end
    end)
    script(r, "OnEnter", function(self)
      if not GameTooltip or not self.tcKey then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Click to open: read it, say if you're going, comment", 1, 1, 1)
      if ns.Notes.isMine({ key = self.tcKey }) then
        GameTooltip:AddLine("Right-click to edit or remove it.", 0.7, 0.7, 0.7)
      end
      GameTooltip:Show()
    end)
    script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rows[i] = r
  end
  P.eventDayPane.more = T.text(P.eventDayPane, T.FONT.small, C.muted)
  P.eventDayPane.more:SetPoint("TOPRIGHT", P.eventDayPane, "TOPRIGHT", 0, -(34 + ROWS * ROW_H + 8))
  local create = Widgets.button(P.eventDayPane, "Create a note for this day", function()
    Calendar.openMaker({ day = P.shownDay })
  end, nil, FEATURE)
  create:SetSize(200, 26)
  create:SetPoint("TOPLEFT", P.eventDayPane, "TOPLEFT", 0, -(34 + ROWS * ROW_H + 4))
end
P.buildEventDay = buildEventDay

local function drawEventDay()
  local off = ns.Diary.offsetOn(P.shownDay) -- this day's own (a clock change moves it)
  local today = ns.Diary.localToday()
  local y, m, d = L.civil(P.shownDay)
  P.eventDayPane.label:SetText(L.WEEKDAYS[L.weekday(P.shownDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d .. ", " .. y)
  local notes = ns.Notes.forDate(dateKeyOf(P.shownDay))
  Calendar.lastNotes = notes
  if #notes == 0 then P.eventDayPane.empty:Show() else P.eventDayPane.empty:Hide() end
  P.eventScroll = math.max(0, math.min(P.eventScroll, #notes - ROWS))
  local below = #notes - P.eventScroll - ROWS
  P.eventDayPane.more:SetText((P.eventScroll > 0 or below > 0)
    and ((P.eventScroll > 0 and (P.eventScroll .. " above, ") or "") .. (below > 0 and (below .. " more, ") or "") .. "scroll")
    or "")
  for i, r in ipairs(rows) do
    local n = notes[i + P.eventScroll]
    r.tcKey = n and n.key or nil
    r.tcNew = nil
    if n then
      r.icon:SetTexture(ns.Notes.iconTexture(n.i))
      r.tcNew = isNew(n, P.shownDay, today)
      r.text:SetText(lineText(n, off) .. (r.tcNew and "  |cffffd100new|r" or ""))
      local counts, rp = countsText(n.key)
      local theirs, zone = ns.Notes.authorTime(n, off) -- the author's own time, when their zone is not mine
      r.sub:SetText("by " .. colored(n.b, n.c)
        .. (theirs and ("  |cff999999" .. theirs .. " " .. zone .. " their time|r") or "") .. counts
        .. (rp.mine and ("  |cff999999you: " .. (rp.mine == "yes" and "going" or rp.mine == "maybe" and "maybe" or "can't") .. "|r") or ""))
      if ns.Notes.isMine(n) then r.del:Show(); r.edit:Show() else r.del:Hide(); r.edit:Hide() end
      r:Show()
    else
      r:Hide()
    end
  end
end
P.drawEventDay = drawEventDay

-- Scroll the day's notes by n rows (the mouse wheel).
function Calendar.scrollEvents(n)
  local top = math.max(0, #(Calendar.lastNotes or {}) - ROWS)
  local v = math.max(0, math.min(top, P.eventScroll + (tonumber(n) or 0)))
  if v ~= P.eventScroll then P.eventScroll = v; Calendar.refresh() end
end

-- Test hook: row i of the day's list ({ key, new }), or nil when it is empty.
function Calendar.eventRowForTest(i)
  local r = rows[i]
  if not r or not r.tcKey then return nil end
  return { key = r.tcKey, new = r.tcNew == true }
end
