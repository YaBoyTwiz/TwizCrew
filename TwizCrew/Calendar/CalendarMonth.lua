-- Crew calendar, the Month view: who played each day (class icons), the notes (icons, a dungeon's artwork) and the
-- tooltip with everyone's times. Part of the calendar window (Calendar/CalendarUI.lua); shared names live on
-- ns.Calendar._ (P).
local _, ns = ...

local Calendar = ns.Calendar
local P = Calendar._

local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic
local PREV_TEX, NEXT_TEX = P.PREV_TEX, P.NEXT_TEX
local WIDTH, HEIGHT, PAD, TOP = P.WIDTH, P.HEIGHT, P.PAD, P.TOP
local script, colored, people, setArt = P.script, P.colored, P.people, P.setArt
local iconTexture, arrowButton = P.iconTexture, P.arrowButton

local CELL_W, CELL_H = 96, 68
local FACES = 7 -- class icons per day cell
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
    script(c, "OnMouseUp", function(self, button)
      if button == "RightButton" and self.tcDay then Widgets.menu(self, Calendar.dayMenuItems(self.tcDay)) end
    end)
    script(c, "OnEnter", function(self)
      if not GameTooltip or not self.tcDay then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local _, m, d = L.civil(self.tcDay)
      GameTooltip:SetText(L.WEEKDAYS[L.weekday(self.tcDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
      for _, n in ipairs(self.tcNotes or {}) do
        local when = ns.Notes.timeText(n, ns.Diary.offsetOn(self.tcDay))
        GameTooltip:AddLine("|T" .. ns.Notes.iconTexture(n.i) .. ":14|t " .. (when and (when .. "  ") or "")
          .. ns.Util.safeText(n.t), 1, 0.9, 0.5, true)
      end
      if #(self.tcPeople or {}) == 0 then GameTooltip:AddLine("Nobody played (that we know of).", 0.8, 0.8, 0.8) end
      for _, p in ipairs(self.tcPeople or {}) do
        GameTooltip:AddDoubleLine(colored(p.name, p.class), L.runText(p.runs) .. "  |cffaaaaaa(" .. L.duration(p.minutes) .. ")|r",
          1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddLine("Click for the timeline and notes. Right-click to add a note.", 0.7, 0.7, 0.7)
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
    -- a dungeon or raid that day: its artwork fills the day, its time and name on top
    local event
    for _, n in ipairs(notes) do if n.g then event = n; break end end
    c.tcArt = nil
    if event then
      c.tcArt = setArt(c.art, event.g, ns.Notes.iconTexture(event.i)) and "art" or "icon"
      c.art:Show(); c.shade:Show()
      local when = ns.Notes.timeText(event, off)
      local going = #ns.Notes.repliesFor(event.key).yes
      c.artText:SetText((when and ("|cffffd100" .. when .. "|r ") or "") .. ns.Util.safeText(event.t)
        .. (going > 0 and ("\n|cff40ff40" .. going .. " going|r") or ""))
      c.artText:Show()
    else
      c.art:Hide(); c.shade:Hide(); c.artText:Hide()
    end
    local minutes = 0
    for k = 1, FACES do
      local p, f = list[k], c.faces[k]
      if p then ns.ClassIcon.apply(f, p.class); f:Show() else f:Hide() end
    end
    for _, p in ipairs(list) do minutes = minutes + p.minutes end
    c.more:SetText(#list > FACES and ("+" .. (#list - FACES) .. " more") or "")
    c.total:SetText((#list > 0 and not event) and L.duration(minutes) or "")
    c:SetAlpha(cell.inMonth and (cell.day <= today and 1 or 0.6) or 0.3)
    if cell.day == today then c.today:Show(); c.todayLine:Show() else c.today:Hide(); c.todayLine:Hide() end
  end
end
P.drawMonth = drawMonth
