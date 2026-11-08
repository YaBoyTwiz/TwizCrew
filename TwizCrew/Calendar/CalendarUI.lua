-- Crew calendar, the window (part of module "calendar"): Month (who played each day, with class icons and note
-- icons), a day's timeline (one bar per friend, AFK lighter) with that day's notes and a box to add one (with an
-- icon), and Usual times (when the crew is usually on, the best time to play together, everyone's habits).
-- Opened by the calendar button on the panel, the wrench menu, /tc cal, or the button in the settings.
local _, ns = ...

local Calendar = {}
ns.Calendar = Calendar

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic

local I = "Interface\\Icons\\"
local ICON_CAL = I .. "INV_Scroll_03"
local ICON_USUAL = I .. "INV_Misc_PocketWatch_01"
local ICON_BEST = I .. "Spell_Holy_BorrowedTime"
local ICON_NOTES = I .. "INV_Misc_Note_01"
local PREV_TEX = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local NEXT_TEX = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"

local WIDTH, HEIGHT, PAD = 700, 570, 14
local TOP = 80 -- below the title and the tabs
local CELL_W, CELL_H = 96, 68
local FACES = 7 -- class icons per day cell
local AXIS_X, BAR_W, ROW_H, DAY_ROWS = 160, 500, 22, 9
local NOTE_ROWS = 5
local HEAT_X, HEAT_W, HEAT_H = 60, 25, 18

local frame, tabs
local view = "month" -- "month" | "day" | "usual"
local shownYear, shownMonth, shownDay
local monthPane, dayPane, usualPane
local cells, dayRows, noteRows, pickButtons, heatCells, habitLines = {}, {}, {}, {}, {}, {}
local pickedIcon = 1
local noteBox

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function classHex(class)
  local r, g, b = T.classColor(class)
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function colored(name, class)
  return "|cff" .. classHex(class) .. ns.Util.safeText(tostring(name or "?")) .. "|r"
end

local function people()
  local out = {}
  for id, p in pairs(ns.Diary.people()) do
    if type(p) == "table" and type(p.days) == "table" then
      out[id] = { name = p.name or "?", class = p.class, days = p.days, alts = p.alts }
    end
  end
  return out
end

local function altsText(p)
  local list = {}
  for name in pairs(p and p.alts or {}) do if name ~= p.name then list[#list + 1] = name end end
  table.sort(list)
  if #list == 0 then return nil end
  return "also plays " .. table.concat(list, ", ")
end

local function dateKeyOf(day)
  local y, m, d = L.civil(day)
  return ns.Notes.dateKey(y, m, d)
end

-------------------------------------------------------------------------------------------------- small pieces
local function iconTexture(parent, path, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetSize(size, size)
  if path then t:SetTexture(path) end
  t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return t
end

-- A button that is only a picture (the month arrows).
local function arrowButton(parent, tex, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints(b)
  t:SetTexture(tex)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  T.color(hl, C.white, 0.15)
  script(b, "OnClick", onClick)
  return b
end

-- A tab: an icon and a word, a gold line under the active one.
local function tabButton(label, icon, id, x)
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(140, 26)
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -44)
  T.paint(b, C.button, 1, C.buttonBorder, 1)
  b.icon = iconTexture(b, icon, 18)
  b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
  b.text = T.text(b, T.FONT.normal, C.text)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetText(label)
  b.line = b:CreateTexture(nil, "OVERLAY")
  b.line:SetHeight(2)
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  T.color(b.line, C.title, 1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  T.color(hl, C.white, 0.08)
  script(b, "OnClick", function() Calendar.show(id) end)
  return b
end

-------------------------------------------------------------------------------------------------------- month
local function buildMonth()
  monthPane = CreateFrame("Frame", nil, frame)
  monthPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
  monthPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local prev = arrowButton(monthPane, PREV_TEX, function() Calendar.moveMonth(-1) end)
  prev:SetPoint("TOPLEFT", monthPane, "TOPLEFT", 0, 2)
  local nxt = arrowButton(monthPane, NEXT_TEX, function() Calendar.moveMonth(1) end)
  nxt:SetPoint("TOPRIGHT", monthPane, "TOPLEFT", 7 * CELL_W, 2)
  monthPane.label = T.readable(T.text(monthPane, T.FONT.normal, C.title), 3)
  monthPane.label:SetPoint("TOP", monthPane, "TOPLEFT", 7 * CELL_W / 2, -2)
  for i = 1, 7 do
    local h = T.text(monthPane, T.FONT.small, (i == 1 or i == 7) and C.title or C.muted)
    h:SetPoint("TOP", monthPane, "TOPLEFT", (i - 1) * CELL_W + CELL_W / 2, -28)
    h:SetText(L.WEEKDAYS[i])
  end
  for i = 1, 42 do
    local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
    local c = CreateFrame("Button", nil, monthPane)
    c:SetSize(CELL_W - 3, CELL_H - 3)
    c:SetPoint("TOPLEFT", monthPane, "TOPLEFT", col * CELL_W, -(44 + row * CELL_H))
    local weekend = col == 0 or col == 6
    T.paint(c, weekend and C.backdrop or C.row, 0.9, C.rowBorder, 1)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints(c)
    T.color(c.hl, C.title, 0.10)
    c.num = T.readable(T.text(c, T.FONT.normal, C.text))
    c.num:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -4)
    c.note = iconTexture(c, nil, 16, "OVERLAY")
    c.note:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, -4)
    c.noteCount = T.readable(T.text(c, T.FONT.small, C.white))
    c.noteCount:SetPoint("RIGHT", c.note, "LEFT", -1, 0)
    c.total = T.text(c, T.FONT.small, C.muted)
    c.total:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -5, 4)
    c.today = c:CreateTexture(nil, "OVERLAY")
    c.today:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.today:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    T.color(c.today, C.title, 0.12)
    c.todayLine = c:CreateTexture(nil, "OVERLAY")
    c.todayLine:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.todayLine:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    c.todayLine:SetHeight(2)
    T.color(c.todayLine, C.title, 1)
    c.faces = {}
    for k = 1, FACES do
      local f = c:CreateTexture(nil, "ARTWORK")
      f:SetSize(12, 12)
      f:SetPoint("TOPLEFT", c, "TOPLEFT", 5 + (k - 1) * 13, -26)
      f:Hide()
      c.faces[k] = f
    end
    c.more = T.text(c, T.FONT.small, C.muted)
    c.more:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -40)
    script(c, "OnClick", function(self) if self.tcDay then Calendar.openDay(self.tcDay) end end)
    script(c, "OnEnter", function(self)
      if not GameTooltip or not self.tcDay then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local _, m, d = L.civil(self.tcDay)
      GameTooltip:SetText(L.WEEKDAYS[L.weekday(self.tcDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
      for _, n in ipairs(self.tcNotes or {}) do
        GameTooltip:AddLine("|T" .. ns.Notes.iconTexture(n.i) .. ":14|t " .. ns.Util.safeText(n.t), 1, 0.9, 0.5, true)
      end
      if #(self.tcPeople or {}) == 0 then GameTooltip:AddLine("Nobody played (that we know of).", 0.8, 0.8, 0.8) end
      for _, p in ipairs(self.tcPeople or {}) do
        GameTooltip:AddDoubleLine(colored(p.name, p.class), L.duration(p.minutes), 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddLine("Click for the timeline and notes", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cells[i] = c
  end
end

-------------------------------------------------------------------------------------------------------- day
local function addNote()
  if not noteBox then return end
  local text = noteBox:GetText()
  if ns.Notes.add(dateKeyOf(shownDay), text, pickedIcon) then
    noteBox:SetText("")
    noteBox:ClearFocus()
  else
    print("TwizCrew: type a note first.")
  end
end

local function buildDay()
  dayPane = CreateFrame("Frame", nil, frame)
  dayPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
  dayPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local back = Widgets.button(dayPane, "Back to the month", function() Calendar.show("month") end, nil, FEATURE)
  back:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, 0)
  local prev = arrowButton(dayPane, PREV_TEX, function() Calendar.openDay(shownDay - 1) end)
  prev:SetPoint("LEFT", back, "RIGHT", 8, 0)
  local nxt = arrowButton(dayPane, NEXT_TEX, function() Calendar.openDay(shownDay + 1) end)
  nxt:SetPoint("LEFT", prev, "RIGHT", 2, 0)
  dayPane.label = T.readable(T.text(dayPane, T.FONT.normal, C.title), 2)
  dayPane.label:SetPoint("LEFT", nxt, "RIGHT", 10, 0)
  -- the hour axis
  for h = 0, 24, 3 do
    local x = AXIS_X + BAR_W * h / 24
    local t = T.text(dayPane, T.FONT.small, C.muted)
    t:SetPoint("TOP", dayPane, "TOPLEFT", x, -32)
    t:SetText(L.clock(h * 60))
    local line = dayPane:CreateTexture(nil, "BACKGROUND")
    line:SetSize(1, DAY_ROWS * ROW_H + 4)
    line:SetPoint("TOP", dayPane, "TOPLEFT", x, -46)
    T.color(line, C.rowBorder, 0.8)
  end
  dayPane.nowLine = dayPane:CreateTexture(nil, "OVERLAY")
  dayPane.nowLine:SetSize(2, DAY_ROWS * ROW_H + 4)
  T.color(dayPane.nowLine, C.title, 0.9)
  dayPane.empty = T.text(dayPane, T.FONT.normal, C.muted)
  dayPane.empty:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -64)
  dayPane.empty:SetText("Nobody played this day (that we know of).")
  for i = 1, DAY_ROWS do
    local r = CreateFrame("Frame", nil, dayPane)
    r:SetSize(WIDTH - 2 * PAD, ROW_H - 2)
    r:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -(50 + (i - 1) * ROW_H))
    r:EnableMouse(true)
    r.face = r:CreateTexture(nil, "ARTWORK")
    r.face:SetSize(16, 16)
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
    r.bars = {}
    script(r, "OnEnter", function(self)
      local e = self.tcEntry
      if not GameTooltip or not e then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      GameTooltip:SetText(colored(e.name, e.class))
      GameTooltip:AddLine(L.runText(e.runs), 1, 1, 1, true)
      GameTooltip:AddLine("Played " .. L.duration(e.minutes), 0.8, 0.8, 0.8)
      local afk = 0
      for _, run in ipairs(e.runs) do if run.afk then afk = afk + (run.to - run.from) * 15 end end
      if afk > 0 then GameTooltip:AddLine("Of that, AFK: " .. L.duration(afk) .. " (lighter on the bar)", 0.7, 0.7, 0.7) end
      local alts = altsText(ns.Diary.people()[e.id])
      if alts then GameTooltip:AddLine(alts, 0.7, 0.7, 0.7) end
      GameTooltip:Show()
    end)
    script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    dayRows[i] = r
  end

  -- notes for this day
  local notesTop = 50 + DAY_ROWS * ROW_H + 12
  local sep = dayPane:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -(notesTop - 4))
  sep:SetPoint("TOPRIGHT", dayPane, "TOPRIGHT", 0, -(notesTop - 4))
  T.color(sep, C.line, 1)
  local nIcon = iconTexture(dayPane, ICON_NOTES, 18)
  nIcon:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -notesTop)
  local nTitle = T.text(dayPane, T.FONT.normal, C.title)
  nTitle:SetPoint("LEFT", nIcon, "RIGHT", 6, 0)
  nTitle:SetText("Notes for this day")
  dayPane.noNotes = T.text(dayPane, T.FONT.small, C.muted)
  dayPane.noNotes:SetPoint("LEFT", nTitle, "RIGHT", 10, 0)
  dayPane.noNotes:SetText("none yet: add one below (the whole crew sees it)")
  for i = 1, NOTE_ROWS do
    local r = CreateFrame("Frame", nil, dayPane)
    r:SetSize(WIDTH - 2 * PAD, 20)
    r:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -(notesTop + 22 + (i - 1) * 21))
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
    noteRows[i] = r
  end

  -- add a note: pick an icon, type, Add
  local addTop = notesTop + 22 + NOTE_ROWS * 21 + 6
  local pickLabel = T.text(dayPane, T.FONT.small, C.muted)
  pickLabel:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -(addTop + 5))
  pickLabel:SetText("Icon:")
  for i, e in ipairs(ns.Notes.ICONS) do
    local b = CreateFrame("Button", nil, dayPane)
    b:SetSize(22, 22)
    b:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 36 + (i - 1) * 25, -addTop)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    T.color(b.border, C.title, 1)
    b.icon = iconTexture(b, e.tex, 22)
    b.icon:SetAllPoints(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    T.color(hl, C.white, 0.2)
    script(b, "OnClick", function() Calendar.pickIcon(i) end)
    script(b, "OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(e.name)
      GameTooltip:Show()
    end)
    script(b, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pickButtons[i] = b
  end
  noteBox = T.frame("EditBox", nil, dayPane)
  noteBox:SetSize(WIDTH - 2 * PAD - 110, 24)
  noteBox:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -(addTop + 30))
  T.paint(noteBox, C.row, 1, C.rowBorder, 1)
  noteBox:SetAutoFocus(false)
  if noteBox.SetFontObject then noteBox:SetFontObject(T.FONT.small) end
  if noteBox.SetTextInsets then noteBox:SetTextInsets(6, 6, 0, 0) end
  if noteBox.SetMaxLetters then noteBox:SetMaxLetters(120) end
  script(noteBox, "OnEnterPressed", function() addNote() end)
  script(noteBox, "OnEscapePressed", function(self) self:ClearFocus() end)
  local add = Widgets.button(dayPane, "Add note", function() addNote() end, nil, FEATURE)
  add:SetSize(96, 24)
  add:SetPoint("LEFT", noteBox, "RIGHT", 8, 0)
end

-------------------------------------------------------------------------------------------------------- usual
local function buildUsual()
  usualPane = CreateFrame("Frame", nil, frame)
  usualPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
  usualPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local star = iconTexture(usualPane, ICON_BEST, 22)
  star:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, 0)
  usualPane.best = T.readable(T.text(usualPane, T.FONT.normal, C.title), 1)
  usualPane.best:SetPoint("LEFT", star, "RIGHT", 8, 0)
  usualPane.best:SetWidth(WIDTH - 2 * PAD - 30)
  usualPane.best:SetJustifyH("LEFT")
  usualPane.note = T.text(usualPane, T.FONT.small, C.muted)
  usualPane.note:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -28)
  usualPane.note:SetText("The last 4 weeks, in your local time. Brighter = more of the crew online. Hover a square.")
  for h = 0, 23, 3 do
    local t = T.text(usualPane, T.FONT.small, C.muted)
    t:SetPoint("BOTTOMLEFT", usualPane, "TOPLEFT", HEAT_X + h * HEAT_W, -60)
    t:SetText(L.clock(h * 60))
  end
  for w = 0, 6 do
    local lab = T.text(usualPane, T.FONT.small, (w == 0 or w == 6) and C.title or C.muted)
    lab:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -(64 + w * HEAT_H) - 3)
    lab:SetText(L.SHORT_DAYS[w + 1])
    heatCells[w] = {}
    for h = 0, 23 do
      local c = CreateFrame("Frame", nil, usualPane)
      c:SetSize(HEAT_W - 1, HEAT_H - 1)
      c:SetPoint("TOPLEFT", usualPane, "TOPLEFT", HEAT_X + h * HEAT_W, -(64 + w * HEAT_H))
      c.tex = c:CreateTexture(nil, "ARTWORK")
      c.tex:SetAllPoints(c)
      c.mark = c:CreateTexture(nil, "OVERLAY")
      c.mark:SetAllPoints(c)
      T.color(c.mark, C.title, 0.55)
      c.mark:Hide()
      c:EnableMouse(true)
      script(c, "OnEnter", function(self)
        if not GameTooltip or not self.tcValue then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.WEEKDAYS[w + 1] .. " " .. L.clock(h * 60) .. "-" .. L.clock((h + 1) * 60))
        GameTooltip:AddLine(string.format("About %.1f of the crew online", self.tcValue), 1, 1, 1)
        GameTooltip:Show()
      end)
      script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      heatCells[w][h] = c
    end
  end
  local whoTop = 72 + 7 * HEAT_H
  local who = T.text(usualPane, T.FONT.normal, C.title)
  who:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -whoTop)
  who:SetText("Everyone's usual times")
  for i = 1, 10 do
    local r = CreateFrame("Frame", nil, usualPane)
    r:SetSize(WIDTH - 2 * PAD, 18)
    r:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -(whoTop + 22 + (i - 1) * 19))
    r.face = r:CreateTexture(nil, "ARTWORK")
    r.face:SetSize(16, 16)
    r.face:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text = T.text(r, T.FONT.small, C.text)
    r.text:SetPoint("LEFT", r.face, "RIGHT", 6, 0)
    r.text:SetWidth(WIDTH - 2 * PAD - 24)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    habitLines[i] = r
  end
end

local function build()
  frame = T.frame("Frame", "TwizCrewCalendar", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  script(frame, "OnDragStart", function(self) self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  T.gloss(frame, nil, 0.04, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewCalendar") end
  script(frame, "OnHide", function() Calendar.shownFlag = false end)
  local logo = iconTexture(frame, ICON_CAL, 26)
  logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
  local title = T.readable(T.text(frame, T.FONT.normal, C.title), 3)
  title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  title:SetText("Crew calendar")
  local sub = T.text(frame, T.FONT.small, C.muted)
  sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
  sub:SetText("who played when, notes for the crew, in your local time")
  local close = Widgets.button(frame, "Close", function() Calendar.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -10)
  tabs = { month = tabButton("Month", ICON_CAL, "month", PAD), usual = tabButton("Usual times", ICON_USUAL, "usual", PAD + 146) }
  buildMonth()
  buildDay()
  buildUsual()
end

-------------------------------------------------------------------------------------------------------- draw
local function drawTabs()
  for id, b in pairs(tabs) do
    local active = (id == view) or (id == "month" and view == "day")
    if active then b.line:Show(); b.text:SetTextColor(T.rgb(C.title)) else b.line:Hide(); b.text:SetTextColor(T.rgb(C.text)) end
  end
end

local function drawMonth()
  local off = ns.Diary.offset()
  local today = ns.Diary.localToday()
  monthPane.label:SetText(L.MONTHS[shownMonth] .. " " .. shownYear)
  local everyone = people()
  for i, cell in ipairs(L.monthGrid(shownYear, shownMonth)) do
    local c = cells[i]
    c.tcDay = cell.day
    c.num:SetText(cell.d)
    local list = cell.day <= today and L.dayView(everyone, cell.day, off) or {}
    c.tcPeople = list
    local notes = ns.Notes.forDate(ns.Notes.dateKey(cell.y, cell.m, cell.d))
    c.tcNotes = notes
    if #notes > 0 then
      c.note:SetTexture(ns.Notes.iconTexture(notes[1].i))
      c.note:Show()
      c.noteCount:SetText(#notes > 1 and tostring(#notes) or "")
    else
      c.note:Hide()
      c.noteCount:SetText("")
    end
    local minutes = 0
    for k = 1, FACES do
      local p, f = list[k], c.faces[k]
      if p then ns.ClassIcon.apply(f, p.class); f:Show() else f:Hide() end
    end
    for _, p in ipairs(list) do minutes = minutes + p.minutes end
    c.more:SetText(#list > FACES and ("+" .. (#list - FACES) .. " more") or "")
    c.total:SetText(#list > 0 and L.duration(minutes) or "")
    c:SetAlpha(cell.inMonth and (cell.day <= today and 1 or 0.6) or 0.3)
    if cell.day == today then c.today:Show(); c.todayLine:Show() else c.today:Hide(); c.todayLine:Hide() end
  end
end

local function bar(r, k)
  local b = r.bars[k]
  if not b then
    b = r:CreateTexture(nil, "ARTWORK")
    r.bars[k] = b
  end
  return b
end

local function drawDay()
  local off = ns.Diary.offset()
  local y, m, d = L.civil(shownDay)
  dayPane.label:SetText(L.WEEKDAYS[L.weekday(shownDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d .. ", " .. y)
  local list = L.dayView(people(), shownDay, off)
  Calendar.lastDay = list
  if #list == 0 then dayPane.empty:Show() else dayPane.empty:Hide() end
  for i, r in ipairs(dayRows) do
    local e = list[i]
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
      r:Show()
    else
      r:Hide()
    end
  end
  if shownDay == ns.Diary.localToday() then
    local minutes = ((ns.Diary.now() + off) % L.DAY) / 60
    dayPane.nowLine:ClearAllPoints()
    dayPane.nowLine:SetPoint("TOP", dayPane, "TOPLEFT", AXIS_X + BAR_W * minutes / 1440, -46)
    dayPane.nowLine:Show()
  else
    dayPane.nowLine:Hide()
  end
  -- notes
  local notes = ns.Notes.forDate(dateKeyOf(shownDay))
  Calendar.lastNotes = notes
  if #notes == 0 then dayPane.noNotes:Show() else dayPane.noNotes:Hide() end
  for i, r in ipairs(noteRows) do
    local n = notes[i]
    r.tcKey = n and n.key or nil
    if n then
      r.icon:SetTexture(ns.Notes.iconTexture(n.i))
      r.text:SetText(ns.Util.safeText(n.t) .. "   |cff999999- " .. colored(n.b, n.c) .. "|r")
      if ns.Notes.isMine(n) then r.del:Show() else r.del:Hide() end
      r:Show()
    else
      r:Hide()
    end
  end
  for i, b in ipairs(pickButtons) do
    if i == pickedIcon then b.border:Show(); b:SetAlpha(1) else b.border:Hide(); b:SetAlpha(0.65) end
  end
end

local function drawUsual()
  local u = L.usual(people(), ns.Diary.localToday(), ns.Diary.offset(), 4)
  Calendar.lastUsual = u
  local best = L.bestTime(u)
  usualPane.best:SetText(L.bestTimeText(best, u.count))
  local top = 0
  for w = 0, 6 do for h = 0, 23 do if u.grid[w][h] > top then top = u.grid[w][h] end end end
  for w = 0, 6 do
    for h = 0, 23 do
      local v = u.grid[w][h]
      local c = heatCells[w][h]
      c.tcValue = v
      if v > 0 and top > 0 then T.color(c.tex, "33cc66", 0.15 + 0.85 * v / top) else T.color(c.tex, C.row, 0.6) end
      local inBest = best and best.weekday == w and h >= best.from and h < best.to
      if inBest then c.mark:Show() else c.mark:Hide() end
    end
  end
  for i, r in ipairs(habitLines) do
    local p = u.people[i]
    if p then
      ns.ClassIcon.apply(r.face, p.class)
      r.face:Show()
      local alts = altsText(ns.Diary.people()[p.id])
      r.text:SetText(colored(p.name, p.class) .. ":  about " .. L.duration(p.perWeek) .. " a week, " .. L.habit(p)
        .. (alts and ("  (" .. alts .. ")") or ""))
      r:Show()
    elseif i == 1 then
      r.face:Hide()
      r.text:SetText("Nobody yet. Play times show up here as the crew plays with this version.")
      r:Show()
    else
      r:Hide()
    end
  end
end

function Calendar.refresh()
  if not frame or not Calendar.shownFlag then return end
  monthPane:Hide(); dayPane:Hide(); usualPane:Hide()
  drawTabs()
  if view == "day" then dayPane:Show(); drawDay()
  elseif view == "usual" then usualPane:Show(); drawUsual()
  else monthPane:Show(); drawMonth() end
end

-------------------------------------------------------------------------------------------------------- public
function Calendar.show(id)
  view = (id == "day" or id == "usual") and id or "month"
  Calendar.refresh()
end

function Calendar.moveMonth(delta)
  shownMonth = shownMonth + delta
  while shownMonth < 1 do shownMonth, shownYear = shownMonth + 12, shownYear - 1 end
  while shownMonth > 12 do shownMonth, shownYear = shownMonth - 12, shownYear + 1 end
  Calendar.refresh()
end

function Calendar.openDay(day)
  if not frame then Calendar.open() end
  shownDay = day
  local y, m = L.civil(day)
  shownYear, shownMonth = y, m
  view = "day"
  Calendar.refresh()
end

function Calendar.pickIcon(i)
  pickedIcon = math.max(1, math.min(#ns.Notes.ICONS, tonumber(i) or 1))
  Calendar.refresh()
end

function Calendar.open()
  if not frame then build() end
  local today = ns.Diary.localToday()
  local y, m = L.civil(today)
  shownYear, shownMonth, shownDay = y, m, today
  view = "month"
  frame:Show()
  Calendar.shownFlag = true
  Calendar.refresh()
end

function Calendar.close()
  Calendar.shownFlag = false
  if frame then frame:Hide() end
end

function Calendar.toggle()
  if Calendar.shownFlag then Calendar.close() else Calendar.open() end
end

function Calendar.isShown() return Calendar.shownFlag and true or false end
function Calendar.viewForTest() return view, shownYear, shownMonth, shownDay end

-- Test hook: type a note in the box and press Enter.
function Calendar.typeNoteForTest(text)
  if not noteBox then return end
  rawset(noteBox, "GetText", function() return text end)
  addNote()
end

-- (Diary's onEnable listens for CALENDAR_CHANGED and calls Calendar.refresh.)
