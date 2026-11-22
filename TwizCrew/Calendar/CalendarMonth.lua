-- Crew calendar, the Play times month: who played each day (class icons, the hours together) and the tooltip
-- with everyone's times. No notes here: they have their own tab (Calendar/CalendarEvents.lua). Part of the calendar
-- window (Calendar/CalendarUI.lua); shared names live on ns.Calendar._ (P).
local _, ns = ...

local Calendar = ns.Calendar
local P = Calendar._

local T = ns.Theme
local C = T.COLOR
local L = ns.CalendarLogic
local PREV_TEX, NEXT_TEX = P.PREV_TEX, P.NEXT_TEX
local WIDTH, HEIGHT, PAD, TOP = P.WIDTH, P.HEIGHT, P.PAD, P.TOP
local script, colored, people = P.script, P.colored, P.people
local arrowButton = P.arrowButton

local CELL_W, CELL_H = 96, 68
local FACES, FACES_ROW = 14, 7 -- class icons per day cell, in two rows
local cells = {}
-------------------------------------------------------------------------------------------------------- month
local function buildMonth()
  P.monthPane = CreateFrame("Frame", nil, P.frame)
  P.monthPane:SetPoint("TOPLEFT", P.frame, "TOPLEFT", PAD, -TOP)
  P.monthPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local prev = arrowButton(P.monthPane, PREV_TEX, function() Calendar.moveMonth(-1) end)
  prev:SetPoint("TOPLEFT", P.monthPane, "TOPLEFT", 0, 2)
  local nxt = arrowButton(P.monthPane, NEXT_TEX, function() Calendar.moveMonth(1) end)
  nxt:SetPoint("TOPRIGHT", P.monthPane, "TOPLEFT", 7 * CELL_W, 2)
  P.monthPane.label = T.readable(T.text(P.monthPane, T.FONT.normal, C.title), 3)
  P.monthPane.label:SetPoint("TOP", P.monthPane, "TOPLEFT", 7 * CELL_W / 2, -2)
  for i = 1, 7 do
    local h = T.text(P.monthPane, T.FONT.small, (i == 1 or i == 7) and C.title or C.muted)
    h:SetPoint("TOP", P.monthPane, "TOPLEFT", (i - 1) * CELL_W + CELL_W / 2, -28)
    h:SetText(L.WEEKDAYS[i])
  end
  for i = 1, 42 do
    local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
    local c = CreateFrame("Button", nil, P.monthPane)
    c:SetSize(CELL_W - 3, CELL_H - 3)
    c:SetPoint("TOPLEFT", P.monthPane, "TOPLEFT", col * CELL_W, -(44 + row * CELL_H))
    local weekend = col == 0 or col == 6
    T.paint(c, weekend and C.backdrop or C.row, 0.9, C.rowBorder, 1)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints(c)
    T.color(c.hl, C.title, 0.10)
    c.num = T.readable(T.text(c, T.FONT.normal, C.text))
    c.num:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -4)
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
      f:SetPoint("TOPLEFT", c, "TOPLEFT", 5 + ((k - 1) % FACES_ROW) * 13, -(22 + math.floor((k - 1) / FACES_ROW) * 14))
      f:Hide()
      c.faces[k] = f
    end
    c.more = T.text(c, T.FONT.small, C.muted)
    c.more:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 5, 4)
    script(c, "OnClick", function(self) if self.tcDay then Calendar.openDay(self.tcDay) end end)
    script(c, "OnEnter", function(self)
      if not GameTooltip or not self.tcDay then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local _, m, d = L.civil(self.tcDay)
      GameTooltip:SetText(L.WEEKDAYS[L.weekday(self.tcDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
      if #(self.tcPeople or {}) == 0 then GameTooltip:AddLine("Nobody played (that we know of).", 0.8, 0.8, 0.8) end
      for _, p in ipairs(self.tcPeople or {}) do
        GameTooltip:AddDoubleLine(colored(p.name, p.class), L.runText(p.runs) .. "  |cffaaaaaa(" .. L.duration(p.minutes) .. ")|r",
          1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddLine("Click for the timeline.", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cells[i] = c
  end
end
P.buildMonth = buildMonth

-------------------------------------------------------------------------------------------------------- draw
local function drawMonth()
  local today = ns.Diary.localToday()
  P.monthPane.label:SetText(L.MONTHS[P.shownMonth] .. " " .. P.shownYear)
  local everyone = people()
  for i, cell in ipairs(L.monthGrid(P.shownYear, P.shownMonth)) do
    local c = cells[i]
    c.tcDay = cell.day
    c.num:SetText(cell.d)
    local off = ns.Diary.offsetOn(cell.day) -- each day its own (a clock change moves it)
    local list = cell.day <= today and L.dayView(everyone, cell.day, off) or {}
    c.tcPeople = list
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
P.drawMonth = drawMonth

-- Test hook: what the Play times month shows for a local day ({ people, faces }), or nil when it is not on it.
function Calendar.monthCellForTest(day)
  for _, c in ipairs(cells) do
    if c.tcDay == day then
      local faces = 0
      for _, f in ipairs(c.faces) do if f:IsShown() then faces = faces + 1 end end
      return { people = #(c.tcPeople or {}), faces = faces, notes = c.tcNotes, art = c.art }
    end
  end
  return nil
end
