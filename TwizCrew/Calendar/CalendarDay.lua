-- Crew calendar, a day's timeline: one bar per friend (AFK lighter, their times written on it, hover for who was on
-- at that moment), the timed notes under it, that day's notes and the button to add one. Part of the calendar
-- window (Calendar/CalendarUI.lua); shared names live on ns.Calendar._ (P).
local _, ns = ...

local Calendar = ns.Calendar
local P = Calendar._

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic
local I, ICON_NOTES, PREV_TEX, NEXT_TEX = P.I, P.ICON_NOTES, P.PREV_TEX, P.NEXT_TEX
local WIDTH, HEIGHT, PAD, TOP = P.WIDTH, P.HEIGHT, P.PAD, P.TOP
local script, classHex, colored, people, altsText = P.script, P.classHex, P.colored, P.people, P.altsText
local dateKeyOf, iconTexture, arrowButton = P.dateKeyOf, P.iconTexture, P.arrowButton

local ICON_TIME = I .. "INV_Misc_PocketWatch_01"
local AXIS_X, BAR_W, ROW_H, DAY_ROWS = 160, 500, 22, 9
local NOTE_ROWS = 5
local dayRows, noteRows = {}, {}
local markers = {}
-------------------------------------------------------------------------------------------------------- day
-- Where the mouse is on the timeline, in minutes after midnight (snapped to 15), or nil.
local function cursorMinutes()
  if type(GetCursorPosition) ~= "function" then return nil end
  local x = GetCursorPosition()
  local scale = tonumber(P.dayPane:GetEffectiveScale())
  local left = tonumber(P.dayPane:GetLeft())
  if not tonumber(x) or not scale or scale <= 0 or not left then return nil end
  local m = (x / scale - left - AXIS_X) / BAR_W * 1440
  m = math.floor(m / 15 + 0.5) * 15
  return math.max(0, math.min(1425, m))
end

-- The menu for a time on the timeline: add a note at that time.
function Calendar.timeMenuItems(minutes)
  if not minutes then return {} end
  return {
    { label = "Create a note at " .. L.clock(minutes), icon = ICON_TIME,
      onClick = function() Calendar.openMaker({ day = P.shownDay, minutes = minutes }) end },
  }
end

-- The day view's tooltip: the person under the mouse (if any), then who was on at the mouse's time. It follows
-- the mouse (redrawn when the time under it changes).
local function slotUnderMouse()
  local m = cursorMinutes()
  if not m then return nil end
  return math.max(0, math.min(L.SLOTS_PER_DAY - 1, math.floor(m / 15)))
end

-- "At 8:15pm: Frostie, Ginkan (AFK)" for local slot j of the day shown.
function Calendar.whoAtText(j)
  local who = L.whoAt(Calendar.lastDay, j)
  if #who == 0 then return "At " .. L.clock(j * 15) .. ": nobody on" end
  local names = {}
  for i, w in ipairs(who) do names[i] = colored(w.name, w.class) .. (w.afk and " |cff999999(AFK)|r" or "") end
  return "At " .. L.clock(j * 15) .. ", " .. #who .. " on: " .. table.concat(names, ", ")
end

local function dayTip(self)
  if not GameTooltip then return end
  local j = slotUnderMouse()
  self.tcSlot = j
  local e = self.tcEntry
  GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
  if e then
    GameTooltip:SetText(colored(e.name, e.class))
    GameTooltip:AddLine(L.runText(e.runs), 1, 1, 1, true)
    GameTooltip:AddLine("Played " .. L.duration(e.minutes), 0.8, 0.8, 0.8)
    local afk = 0
    for _, run in ipairs(e.runs) do if run.afk then afk = afk + (run.to - run.from) * 15 end end
    if afk > 0 then GameTooltip:AddLine("Of that, AFK: " .. L.duration(afk) .. " (lighter on the bar)", 0.7, 0.7, 0.7) end
    local alts = altsText(ns.Diary.people()[e.id])
    if alts then GameTooltip:AddLine(alts, 0.7, 0.7, 0.7) end
    if j then GameTooltip:AddLine(" ") end
  else
    GameTooltip:SetText(j and L.clock(j * 15) or "Timeline", 1, 1, 1)
  end
  if j then GameTooltip:AddLine(Calendar.whoAtText(j), 1, 0.85, 0.4, true) end
  if e then GameTooltip:AddLine("Click for " .. ns.Util.safeText(e.name) .. "'s usual times", 0.6, 0.6, 0.6) end
  GameTooltip:AddLine("Right-click to add a note at that time", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function dayTipFollow(self)
  if self.tcHover and slotUnderMouse() ~= self.tcSlot then dayTip(self) end
end

local function hoverable(f)
  script(f, "OnEnter", function(self) self.tcHover = true; dayTip(self) end)
  script(f, "OnLeave", function(self) self.tcHover = nil; if GameTooltip then GameTooltip:Hide() end end)
  script(f, "OnUpdate", dayTipFollow)
end

local function timelineClick(anchor, button)
  if button ~= "RightButton" then return end
  local m = cursorMinutes()
  if m then Widgets.menu(anchor, Calendar.timeMenuItems(m)) end
end

local function buildDay()
  P.dayPane = CreateFrame("Frame", nil, P.frame)
  P.dayPane:SetPoint("TOPLEFT", P.frame, "TOPLEFT", PAD, -TOP)
  P.dayPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local back = Widgets.button(P.dayPane, "Back to the month", function() Calendar.show("month") end, nil, FEATURE)
  back:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, 0)
  local prev = arrowButton(P.dayPane, PREV_TEX, function() Calendar.openDay(P.shownDay - 1) end)
  prev:SetPoint("LEFT", back, "RIGHT", 8, 0)
  local nxt = arrowButton(P.dayPane, NEXT_TEX, function() Calendar.openDay(P.shownDay + 1) end)
  nxt:SetPoint("LEFT", prev, "RIGHT", 2, 0)
  P.dayPane.label = T.readable(T.text(P.dayPane, T.FONT.normal, C.title), 2)
  P.dayPane.label:SetPoint("LEFT", nxt, "RIGHT", 10, 0)
  local weekGrid = Widgets.button(P.dayPane, "This week as a grid", function() Calendar.showWeek(P.shownDay) end, nil, FEATURE)
  weekGrid:SetPoint("TOPRIGHT", P.dayPane, "TOPRIGHT", 0, 0)
  -- the hour axis
  for h = 0, 24, 3 do
    local x = AXIS_X + BAR_W * h / 24
    local t = T.text(P.dayPane, T.FONT.small, C.muted)
    t:SetPoint("TOP", P.dayPane, "TOPLEFT", x, -32)
    t:SetText(L.clock(h * 60))
    local line = P.dayPane:CreateTexture(nil, "BACKGROUND")
    line:SetSize(1, DAY_ROWS * ROW_H + 4)
    line:SetPoint("TOP", P.dayPane, "TOPLEFT", x, -46)
    T.color(line, C.rowBorder, 0.8)
  end
  -- right-click anywhere on the timeline (also where nobody played) to add a note at that time
  local catcher = CreateFrame("Frame", nil, P.dayPane)
  catcher:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", AXIS_X, -46)
  catcher:SetSize(BAR_W, DAY_ROWS * ROW_H)
  catcher:EnableMouse(true)
  script(catcher, "OnMouseUp", function(self, button) timelineClick(self, button) end)
  hoverable(catcher)
  -- more people than rows: the mouse wheel scrolls them
  P.dayPane:EnableMouseWheel(true)
  script(P.dayPane, "OnMouseWheel", function(_, delta) Calendar.scrollDay(-delta) end)
  P.dayPane.more = T.text(P.dayPane, T.FONT.small, C.muted)
  P.dayPane.more:SetPoint("TOPRIGHT", P.dayPane, "TOPLEFT", AXIS_X - 6, -(50 + DAY_ROWS * ROW_H + 2))
  P.dayPane.nowLine = P.dayPane:CreateTexture(nil, "OVERLAY")
  P.dayPane.nowLine:SetSize(2, DAY_ROWS * ROW_H + 4)
  T.color(P.dayPane.nowLine, C.title, 0.9)
  P.dayPane.empty = T.text(P.dayPane, T.FONT.normal, C.muted)
  P.dayPane.empty:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, -64)
  P.dayPane.empty:SetText("Nobody played this day (that we know of).")
  for i = 1, DAY_ROWS do
    local r = CreateFrame("Frame", nil, P.dayPane)
    r:SetSize(WIDTH - 2 * PAD, ROW_H - 2)
    r:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, -(50 + (i - 1) * ROW_H))
    r:EnableMouse(true)
    r.face = r:CreateTexture(nil, "ARTWORK")
    r.face:SetSize(T.icon(16), T.icon(16))
    r.face:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.name = T.readable(T.text(r, T.FONT.small, C.text))
    r.name:SetPoint("LEFT", r.face, "RIGHT", 4, 0)
    r.name:SetWidth(AXIS_X - 70)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.total = T.text(r, T.FONT.small, C.muted)
    r.total:SetPoint("RIGHT", r, "LEFT", AXIS_X - 6, 0)
    r.back = r:CreateTexture(nil, "BACKGROUND")
    r.back:SetPoint("LEFT", r, "LEFT", AXIS_X, 0)
    r.back:SetSize(BAR_W, ROW_H - 8)
    T.color(r.back, C.row, 0.7)
    r.bars, r.labels = {}, {}
    hoverable(r)
    script(r, "OnMouseUp", function(self, button)
      if button == "LeftButton" and self.tcEntry then Calendar.showUsualFor(self.tcEntry.id) else timelineClick(self, button) end
    end)
    dayRows[i] = r
  end

  -- notes for this day
  local notesTop = 50 + DAY_ROWS * ROW_H + 26 -- room for the timed notes' icons under the timeline
  local sep = P.dayPane:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, -(notesTop - 4))
  sep:SetPoint("TOPRIGHT", P.dayPane, "TOPRIGHT", 0, -(notesTop - 4))
  T.color(sep, C.line, 1)
  local nIcon = iconTexture(P.dayPane, ICON_NOTES, 18)
  nIcon:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, -notesTop)
  local nTitle = T.text(P.dayPane, T.FONT.normal, C.title)
  nTitle:SetPoint("LEFT", nIcon, "RIGHT", 6, 0)
  nTitle:SetText("Notes for this day")
  P.dayPane.noNotes = T.text(P.dayPane, T.FONT.small, C.muted)
  P.dayPane.noNotes:SetPoint("LEFT", nTitle, "RIGHT", 10, 0)
  P.dayPane.noNotes:SetText("none yet: add one below (the whole crew sees it)")
  for i = 1, NOTE_ROWS do
    local r = CreateFrame("Frame", nil, P.dayPane)
    r:SetSize(WIDTH - 2 * PAD, 23)
    r:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, -(notesTop + 24 + (i - 1) * 25))
    r.icon = iconTexture(r, nil, 18)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text = T.text(r, T.FONT.small, C.text)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWidth(WIDTH - 2 * PAD - 60)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.del = Widgets.button(r, "X", function() if r.tcKey then ns.Notes.remove(r.tcKey) end end, "danger", FEATURE)
    r.del:SetSize(24, 18)
    r.del:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints(r)
    T.color(r.hl, C.title, 0.08)
    r:EnableMouse(true)
    script(r, "OnMouseUp", function(self, button)
      if button == "LeftButton" and self.tcKey and ns.NoteView then ns.NoteView.open(self.tcKey) end
    end)
    script(r, "OnEnter", function(self)
      if not GameTooltip or not self.tcKey then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Click to open: read it, say if you're going, comment", 1, 1, 1)
      GameTooltip:Show()
    end)
    script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    noteRows[i] = r
  end

  -- one button: "Create a note" for this day (the window has the time, the icon and the rest)
  local addTop = notesTop + 24 + NOTE_ROWS * 25 + 8
  local create = Widgets.button(P.dayPane, "Create a note for this day", function()
    Calendar.openMaker({ day = P.shownDay })
  end, nil, FEATURE)
  create:SetSize(200, 26)
  create:SetPoint("TOPLEFT", P.dayPane, "TOPLEFT", 0, -addTop)
  local tip = T.text(P.dayPane, T.FONT.small, C.muted)
  tip:SetPoint("LEFT", create, "RIGHT", 10, 0)
  tip:SetText("or right-click the timeline at a time")
end
P.buildDay = buildDay

-------------------------------------------------------------------------------------------------------- draw
local function bar(r, k)
  local b = r.bars[k]
  if not b then
    b = r:CreateTexture(nil, "ARTWORK")
    r.bars[k] = b
  end
  return b
end

local function label(r, k)
  local t = r.labels[k]
  if not t then
    t = T.readable(T.text(r, T.FONT.small, C.white))
    r.labels[k] = t
  end
  return t
end

-- How wide a time label is (the game measures it; a guess when it can't).
local function textWidth(t, text)
  local w = tonumber(t.GetStringWidth and t:GetStringWidth())
  if not w or w <= 0 then w = #text * 5.5 end
  return w
end

-- The little class icon at the start of a stretch (on a dark square, so it reads on any bar color).
local ICON_S = ROW_H - 8
local function badge(r, k)
  r.tcIcons = rawget(r, "tcIcons") or {}
  local f = r.tcIcons[k]
  if not f then
    f = { back = r:CreateTexture(nil, "OVERLAY", nil, 1), tex = r:CreateTexture(nil, "OVERLAY", nil, 2) }
    f.back:SetSize(ICON_S + 2, ICON_S + 2)
    T.color(f.back, "000000", 0.85)
    f.tex:SetSize(ICON_S, ICON_S)
    f.tex:SetPoint("CENTER", f.back, "CENTER", 0, 0)
    r.tcIcons[k] = f
  end
  return f
end

-- Each stretch of play on the row: the person's class icon at its start, then its times (inside the bar when
-- they fit, else just after it, or before it, else left to the tooltip). Returns how many times were written.
local function writeTimes(r, e)
  local spans = L.spans(e.runs)
  local used, shown = AXIS_X, 0
  local function x(slot) return AXIS_X + BAR_W * slot / L.SLOTS_PER_DAY end
  for k, sp in ipairs(spans) do
    local x1, x2 = x(sp.from), x(sp.to)
    -- the icon: at the start of the bar (a short bar: it starts there and pokes out)
    local ic = badge(r, k)
    ic.back:ClearAllPoints()
    ic.back:SetPoint("LEFT", r, "LEFT", x1, 0)
    ns.ClassIcon.apply(ic.tex, e.class)
    ic.back:Show(); ic.tex:Show()
    ic.on = true
    local afterIcon = x1 + ICON_S + 4
    local t = label(r, k)
    local text = L.spanText(sp)
    t:SetText(text)
    t.tcText = text
    t:ClearAllPoints()
    local w = textWidth(t, text)
    local tail = math.max(x2, afterIcon)
    local limit = spans[k + 1] and x(spans[k + 1].from) or (AXIS_X + BAR_W)
    if x2 - afterIcon >= w + 4 then
      t:SetPoint("LEFT", r, "LEFT", afterIcon, 0)
      used = x2
    elseif limit - tail >= w + 6 then
      t:SetPoint("LEFT", r, "LEFT", tail + 3, 0)
      used = tail + 3 + w
    elseif x1 - used >= w + 6 then
      t:SetPoint("RIGHT", r, "LEFT", x1 - 3, 0)
      used = tail
    else
      t:SetText("")
      t.tcText = nil
      used = tail
    end
    t.tcOn = t.tcText ~= nil
    if t.tcOn then shown = shown + 1 end
    t:Show()
  end
  for k = #spans + 1, #r.labels do r.labels[k].tcOn = false; r.labels[k]:Hide() end
  for k = #spans + 1, #(rawget(r, "tcIcons") or {}) do local ic = r.tcIcons[k]; ic.on = false; ic.back:Hide(); ic.tex:Hide() end
  return shown
end

-- Scroll the day view's people by n rows (the mouse wheel).
function Calendar.scrollDay(n)
  local list = Calendar.lastDay or {}
  local top = math.max(0, #list - DAY_ROWS)
  local v = math.max(0, math.min(top, P.dayScroll + (tonumber(n) or 0)))
  if v ~= P.dayScroll then P.dayScroll = v; Calendar.refresh() end
end

function Calendar.dayRowForTest(i)
  local r = dayRows[i]
  if not r or not r.tcEntry then return nil end
  local texts = {}
  for _, t in ipairs(r.labels) do if rawget(t, "tcOn") then texts[#texts + 1] = t.tcText end end
  local icons = 0
  for _, ic in ipairs(rawget(r, "tcIcons") or {}) do if ic.on then icons = icons + 1 end end
  return { name = r.tcEntry.name, times = texts, icons = icons }
end

local function drawDay()
  local off = ns.Diary.offsetOn(P.shownDay) -- this day's own (a clock change moves it)
  local y, m, d = L.civil(P.shownDay)
  P.dayPane.label:SetText(L.WEEKDAYS[L.weekday(P.shownDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d .. ", " .. y)
  local list = L.dayView(people(), P.shownDay, off)
  Calendar.lastDay = list
  if #list == 0 then P.dayPane.empty:Show() else P.dayPane.empty:Hide() end
  P.dayScroll = math.max(0, math.min(P.dayScroll, #list - DAY_ROWS))
  local below = #list - P.dayScroll - DAY_ROWS
  P.dayPane.more:SetText((P.dayScroll > 0 or below > 0)
    and ((P.dayScroll > 0 and (P.dayScroll .. " above, ") or "") .. (below > 0 and (below .. " more, ") or "") .. "scroll")
    or "")
  for i, r in ipairs(dayRows) do
    local e = list[i + P.dayScroll]
    r.tcEntry = e
    for _, b in ipairs(r.bars) do b:Hide() end
    if e then
      ns.ClassIcon.apply(r.face, e.class)
      r.name:SetText(colored(e.name, e.class))
      r.total:SetText(L.duration(e.minutes))
      for k, run in ipairs(e.runs) do
        local b = bar(r, k)
        b:ClearAllPoints()
        b:SetPoint("LEFT", r, "LEFT", AXIS_X + BAR_W * run.from / 96, 0)
        b:SetSize(math.max(2, BAR_W * (run.to - run.from) / 96), ROW_H - 8)
        T.color(b, classHex(e.class), run.afk and 0.35 or 1)
        b:Show()
      end
      writeTimes(r, e)
      r:Show()
    else
      r:Hide()
    end
  end
  if P.shownDay == ns.Diary.localToday() then
    local minutes = ((ns.Diary.now() + ns.Diary.offset()) % L.DAY) / 60
    P.dayPane.nowLine:ClearAllPoints()
    P.dayPane.nowLine:SetPoint("TOP", P.dayPane, "TOPLEFT", AXIS_X + BAR_W * minutes / 1440, -46)
    P.dayPane.nowLine:Show()
  else
    P.dayPane.nowLine:Hide()
  end
  -- notes
  local notes = ns.Notes.forDate(dateKeyOf(P.shownDay))
  Calendar.lastNotes = notes
  if #notes == 0 then P.dayPane.noNotes:Show() else P.dayPane.noNotes:Hide() end
  for i, r in ipairs(noteRows) do
    local n = notes[i]
    r.tcKey = n and n.key or nil
    if n then
      r.icon:SetTexture(ns.Notes.iconTexture(n.i))
      local when = ns.Notes.timeText(n, off)
      local rp = ns.Notes.repliesFor(n.key)
      local counts = ""
      if #rp.yes > 0 then counts = counts .. "  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" .. #rp.yes end
      if #rp.maybe > 0 then counts = counts .. "  |TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t" .. #rp.maybe end
      if #rp.comments > 0 then counts = counts .. "  |cffaaaaaa" .. #rp.comments .. (#rp.comments == 1 and " comment" or " comments") .. "|r" end
      r.text:SetText((when and ("|cffffd100" .. when .. "|r  ") or "") .. ns.Util.safeText(n.t)
        .. "   |cff999999- " .. colored(n.b, n.c) .. "|r" .. counts)
      if ns.Notes.isMine(n) then r.del:Show() else r.del:Hide() end
      r:Show()
    else
      r:Hide()
    end
  end
  -- timed notes: an icon under the timeline at their time, and a faint line up through it
  local k = 0
  for _, n in ipairs(notes) do
    if type(n.at) == "number" then
      k = k + 1
      local mk = markers[k]
      if not mk then
        mk = CreateFrame("Frame", nil, P.dayPane)
        mk:SetSize(T.icon(16), T.icon(16))
        mk.icon = iconTexture(mk, nil, 16)
        mk.icon:SetAllPoints(mk)
        mk.line = P.dayPane:CreateTexture(nil, "ARTWORK")
        mk.line:SetSize(2, DAY_ROWS * ROW_H)
        T.color(mk.line, C.title, 0.45)
        mk:EnableMouse(true)
        script(mk, "OnEnter", function(self)
          local note = self.tcNote
          if not GameTooltip or not note then return end
          GameTooltip:SetOwner(self, "ANCHOR_TOP")
          GameTooltip:SetText(tostring(ns.Notes.timeText(note, ns.Diary.offsetOn(P.shownDay))) .. " (your time)")
          GameTooltip:AddLine(ns.Util.safeText(note.t), 1, 1, 1, true)
          GameTooltip:AddLine("by " .. colored(note.b, note.c), 0.8, 0.8, 0.8)
          GameTooltip:Show()
        end)
        script(mk, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        script(mk, "OnMouseUp", function(self, button)
          if button == "LeftButton" and self.tcNote and ns.NoteView then ns.NoteView.open(self.tcNote.key) end
        end)
        markers[k] = mk
      end
      local minutes = ((n.at + off) % L.DAY) / 60
      local x = AXIS_X + BAR_W * minutes / 1440
      mk.tcNote = n
      mk.icon:SetTexture(ns.Notes.iconTexture(n.i))
      mk:ClearAllPoints()
      mk:SetPoint("TOP", P.dayPane, "TOPLEFT", x, -(48 + DAY_ROWS * ROW_H))
      mk.line:ClearAllPoints()
      mk.line:SetPoint("TOP", P.dayPane, "TOPLEFT", x, -46)
      mk:Show(); mk.line:Show()
    end
  end
  for i = k + 1, #markers do markers[i]:Hide(); markers[i].line:Hide() end
  Calendar.lastMarkers = k
end
P.drawDay = drawDay
