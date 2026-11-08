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
local ICON_TIME = I .. "INV_Misc_PocketWatch_01"
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
local cells, dayRows, noteRows, heatCells, habitLines = {}, {}, {}, {}, {}
local markers = {}
local zoneText

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
        local when = ns.Notes.timeText(n, ns.Diary.offset())
        GameTooltip:AddLine("|T" .. ns.Notes.iconTexture(n.i) .. ":14|t " .. (when and (when .. "  ") or "")
          .. ns.Util.safeText(n.t), 1, 0.9, 0.5, true)
      end
      if #(self.tcPeople or {}) == 0 then GameTooltip:AddLine("Nobody played (that we know of).", 0.8, 0.8, 0.8) end
      for _, p in ipairs(self.tcPeople or {}) do
        GameTooltip:AddDoubleLine(colored(p.name, p.class), L.duration(p.minutes), 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddLine("Click for the timeline and notes. Right-click to add a note.", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cells[i] = c
  end
end

-------------------------------------------------------------------------------------------------------- day
-- Where the mouse is on the timeline, in minutes after midnight (snapped to 15), or nil.
local function cursorMinutes()
  if type(GetCursorPosition) ~= "function" then return nil end
  local x = GetCursorPosition()
  local scale = tonumber(dayPane:GetEffectiveScale())
  local left = tonumber(dayPane:GetLeft())
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
      onClick = function() Calendar.openMaker({ day = shownDay, minutes = minutes }) end },
  }
end

local function timelineClick(anchor, button)
  if button ~= "RightButton" then return end
  local m = cursorMinutes()
  if m then Widgets.menu(anchor, Calendar.timeMenuItems(m)) end
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
  -- right-click anywhere on the timeline (also where nobody played) to add a note at that time
  local catcher = CreateFrame("Frame", nil, dayPane)
  catcher:SetPoint("TOPLEFT", dayPane, "TOPLEFT", AXIS_X, -46)
  catcher:SetSize(BAR_W, DAY_ROWS * ROW_H)
  catcher:EnableMouse(true)
  script(catcher, "OnMouseUp", function(self, button) timelineClick(self, button) end)
  script(catcher, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText("Right-click to add a note at that time", 1, 1, 1)
    GameTooltip:Show()
  end)
  script(catcher, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
    script(r, "OnMouseUp", function(self, button) timelineClick(self, button) end)
    dayRows[i] = r
  end

  -- notes for this day
  local notesTop = 50 + DAY_ROWS * ROW_H + 26 -- room for the timed notes' icons under the timeline
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
  local addTop = notesTop + 22 + NOTE_ROWS * 21 + 8
  local create = Widgets.button(dayPane, "Create a note for this day", function()
    Calendar.openMaker({ day = shownDay })
  end, nil, FEATURE)
  create:SetSize(200, 26)
  create:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -addTop)
  local tip = T.text(dayPane, T.FONT.small, C.muted)
  tip:SetPoint("LEFT", create, "RIGHT", 10, 0)
  tip:SetText("or right-click the timeline at a time")
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

----------------------------------------------------------------------------------------------- "Create a note"
-- A small window: the day, a time (or none), what it is (a note, a dungeon, a raid), an icon and the words.
-- Save puts it on its day. A timed note is stored in one shared time (UTC), so every friend sees it at their own
-- local time and date (what their computer's clock says, not the server's).
local maker
local mk = { day = 0, minutes = nil, kind = "note", dungeon = nil, icon = 1 }
local KINDS = { { id = "note", label = "Note" }, { id = "dungeon", label = "Dungeon" }, { id = "raid", label = "Raid" } }

-- Puts a dungeon's artwork on a texture (the first file that exists), else the note's icon. Returns true for art.
local function setArt(tex, key, fallback)
  for _, path in ipairs(ns.Notes.dungeonImages(key)) do
    local ok, res = pcall(tex.SetTexture, tex, path)
    if ok and res ~= false then
      tex:SetTexCoord(0, 1, 0, 1)
      return true
    end
  end
  tex:SetTexture(fallback)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return false
end

Calendar.setArt = setArt

-- A dungeon's small icon for menus: the game's group finder icon when this game version has it, else a sword
-- (dungeon) or a dragon head (raid).
local iconCache, probe = {}, nil
local function dungeonIcon(dg)
  if iconCache[dg.key] then return iconCache[dg.key] end
  local pick = dg.raid and (I .. "INV_Misc_Head_Dragon_01") or (I .. "INV_Sword_04")
  if not probe then probe = UIParent:CreateTexture(nil, "BACKGROUND"); probe:Hide() end
  for _, path in ipairs(ns.Notes.dungeonIcons(dg.key)) do
    local ok, res = pcall(probe.SetTexture, probe, path)
    if ok and res == true then pick = path; break end
  end
  iconCache[dg.key] = pick
  return pick
end

local FIT_COLOR = { low = "9d9d9d", ok = "40ff40", high = "ff4040" }

-- "UTC-5", "UTC+5:30"
local function zoneName()
  local off = ns.Diary.offset()
  local sign = off < 0 and "-" or "+"
  off = math.abs(off)
  local h, m = math.floor(off / 3600), math.floor((off % 3600) / 60)
  return "UTC" .. sign .. h .. (m > 0 and string.format(":%02d", m) or "")
end
Calendar.zoneName = zoneName

local function drawMaker()
  if not maker then return end
  local _, m, d = L.civil(mk.day)
  maker.dayText:SetText(L.WEEKDAYS[L.weekday(mk.day) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
  if mk.minutes then
    maker.hour.text:SetText(L.clock(math.floor(mk.minutes / 60) * 60))
    maker.minute.text:SetText(string.format(":%02d", mk.minutes % 60))
    maker.minute:Show()
    maker.noTime.text:SetText("No time")
  else
    maker.hour.text:SetText("Pick a time")
    maker.minute:Hide()
    maker.noTime.text:SetText("No time (set)")
  end
  maker.zone:SetText("your time (" .. zoneName() .. "); friends see it in theirs")
  for _, k in ipairs(KINDS) do
    local b = maker.kinds[k.id]
    if mk.kind == k.id then T.color(b.fill, C.title, 0.35) else T.color(b.fill, C.button, 1) end
  end
  local wantsPlace = mk.kind ~= "note"
  if wantsPlace then
    local dg = mk.dungeon and ns.Notes.dungeon(mk.dungeon)
    maker.place.text:SetText(dg and dg.name or (mk.kind == "raid" and "Pick a raid" or "Pick a dungeon"))
    maker.place:Show()
    if dg then
      local fit = ns.Notes.levelFit(dg, UnitLevel and UnitLevel("player"))
      maker.placeLine:SetText("|cff" .. FIT_COLOR[fit] .. ns.Notes.dungeonLine(dg) .. "|r")
      maker.placeLine:Show()
    else
      maker.placeLine:Hide()
    end
    if dg then setArt(maker.preview, dg.key, ns.Notes.iconTexture(mk.icon)); maker.preview:Show() else maker.preview:Hide() end
  else
    maker.place:Hide()
    maker.preview:Hide()
    maker.placeLine:Hide()
  end
  for i, b in ipairs(maker.picks) do
    if i == mk.icon then b.border:Show(); b:SetAlpha(1) else b.border:Hide(); b:SetAlpha(0.6) end
  end
end

function Calendar.hourItems()
  local items = {}
  for h = 0, 23 do
    items[#items + 1] = { label = L.clock(h * 60), icon = ICON_TIME, onClick = function()
      mk.minutes = h * 60 + ((mk.minutes or 0) % 60)
      drawMaker()
    end }
  end
  return items
end

function Calendar.minuteItems()
  local items = {}
  for _, q in ipairs({ 0, 15, 30, 45 }) do
    items[#items + 1] = { label = string.format(":%02d", q), icon = ICON_TIME, onClick = function()
      mk.minutes = math.floor((mk.minutes or 0) / 60) * 60 + q
      drawMaker()
    end }
  end
  return items
end

-- The dungeon (or raid) picker: lowest levels first, each with its level range in a color for your level
-- (green: your range, grey: too easy, red: too high yet) and its icon.
function Calendar.placeItems()
  local list = {}
  for _, dg in ipairs(ns.Notes.DUNGEONS) do
    if (mk.kind == "raid") == (dg.raid == true) then list[#list + 1] = dg end
  end
  table.sort(list, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    if a.max ~= b.max then return a.max < b.max end
    return a.name < b.name
  end)
  local me = UnitLevel and UnitLevel("player")
  local items = {}
  for _, dg in ipairs(list) do
    local fit = ns.Notes.levelFit(dg, me)
    local size = dg.raid and ("  |cffaaaaaa" .. (dg.size or 40) .. "-man|r") or ""
    items[#items + 1] = { label = "|cff" .. FIT_COLOR[fit] .. "[" .. ns.Notes.levelText(dg) .. "]|r  " .. dg.name .. size,
      icon = dungeonIcon(dg), onClick = function() mk.dungeon = dg.key; drawMaker() end }
  end
  return items
end

local function smallButton(parent, label, w, onClick)
  local b = Widgets.button(parent, label, onClick, nil, FEATURE)
  b:SetSize(w, 22)
  b.fill = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  return b
end

local function buildMaker()
  local W, PADM = 470, 14
  maker = T.frame("Frame", "TwizCrewNoteMaker", UIParent)
  maker:SetSize(W, 330)
  maker:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  maker:SetFrameStrata("FULLSCREEN_DIALOG")
  maker:SetMovable(true)
  maker:EnableMouse(true)
  if maker.SetClampedToScreen then maker:SetClampedToScreen(true) end
  if maker.RegisterForDrag then maker:RegisterForDrag("LeftButton") end
  script(maker, "OnDragStart", function(self) self:StartMoving() end)
  script(maker, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  T.paint(maker, C.backdrop, 0.98, C.title, 2)
  T.gloss(maker, nil, 0.05, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewNoteMaker") end
  local logo = iconTexture(maker, ICON_NOTES, 22)
  logo:SetPoint("TOPLEFT", maker, "TOPLEFT", PADM, -10)
  local title = T.readable(T.text(maker, T.FONT.normal, C.title), 2)
  title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  title:SetText("Create a note")

  local function label(text, y)
    local fs = T.text(maker, T.FONT.small, C.muted)
    fs:SetPoint("TOPLEFT", maker, "TOPLEFT", PADM, -y - 5)
    fs:SetText(text)
    return fs
  end
  local X = PADM + 56
  -- day
  label("Day", 44)
  local prev = arrowButton(maker, PREV_TEX, function() mk.day = mk.day - 1; drawMaker() end)
  prev:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -42)
  maker.dayText = T.readable(T.text(maker, T.FONT.normal, C.text))
  maker.dayText:SetPoint("LEFT", prev, "RIGHT", 6, 0)
  maker.dayText:SetWidth(210)
  local nxt = arrowButton(maker, NEXT_TEX, function() mk.day = mk.day + 1; drawMaker() end)
  nxt:SetPoint("LEFT", maker.dayText, "RIGHT", 4, 0)
  local today = smallButton(maker, "Today", 60, function() mk.day = ns.Diary.localToday(); drawMaker() end)
  today:SetPoint("LEFT", nxt, "RIGHT", 6, 0)
  -- time
  label("Time", 76)
  maker.hour = smallButton(maker, "Pick a time", 100, function() Widgets.menu(maker.hour, Calendar.hourItems()) end)
  maker.hour:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -74)
  maker.minute = smallButton(maker, ":00", 50, function() Widgets.menu(maker.minute, Calendar.minuteItems()) end)
  maker.minute:SetPoint("LEFT", maker.hour, "RIGHT", 4, 0)
  maker.noTime = smallButton(maker, "No time", 100, function() mk.minutes = nil; drawMaker() end)
  maker.noTime:SetPoint("LEFT", maker.minute, "RIGHT", 4, 0)
  maker.zone = T.text(maker, T.FONT.small, C.muted)
  maker.zone:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -100)
  -- what it is
  label("What", 120)
  maker.kinds = {}
  local kx = X
  for _, k in ipairs(KINDS) do
    local b = smallButton(maker, k.label, 80, function()
      mk.kind = k.id
      if k.id == "note" then mk.dungeon = nil
      elseif mk.dungeon and ((ns.Notes.dungeon(mk.dungeon).raid == true) ~= (k.id == "raid")) then mk.dungeon = nil end
      drawMaker()
    end)
    b:SetPoint("TOPLEFT", maker, "TOPLEFT", kx, -118)
    maker.kinds[k.id] = b
    kx = kx + 84
  end
  maker.place = smallButton(maker, "Pick a dungeon", 170, function() Widgets.menu(maker.place, Calendar.placeItems()) end)
  maker.place:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -146)
  maker.placeLine = T.text(maker, T.FONT.small, C.text)
  maker.placeLine:SetPoint("LEFT", maker.place, "RIGHT", 8, 0)
  maker.preview = maker:CreateTexture(nil, "ARTWORK")
  maker.preview:SetSize(120, 68)
  maker.preview:SetPoint("TOPRIGHT", maker, "TOPRIGHT", -PADM, -40)
  -- thin lines between the parts, so it reads as a form
  for _, y in ipairs({ 68, 112, 172, 206 }) do
    local line = maker:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", maker, "TOPLEFT", PADM, -y)
    line:SetPoint("TOPRIGHT", maker, "TOPRIGHT", -PADM, -y)
    T.color(line, C.line, 0.6)
  end
  -- icon
  label("Icon", 180)
  maker.picks = {}
  for i, e in ipairs(ns.Notes.ICONS) do
    local b = CreateFrame("Button", nil, maker)
    b:SetSize(20, 20)
    b:SetPoint("TOPLEFT", maker, "TOPLEFT", X + (i - 1) * 23, -178)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    T.color(b.border, C.title, 1)
    local ic = iconTexture(b, e.tex, 20)
    ic:SetAllPoints(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    T.color(hl, C.white, 0.2)
    script(b, "OnClick", function() mk.icon = i; drawMaker() end)
    script(b, "OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(e.name)
      GameTooltip:Show()
    end)
    script(b, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    maker.picks[i] = b
  end
  -- words
  label("Words", 214)
  maker.box = T.frame("EditBox", nil, maker)
  maker.box:SetSize(W - X - PADM, 24)
  maker.box:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -212)
  T.paint(maker.box, C.row, 1, C.rowBorder, 1)
  maker.box:SetAutoFocus(false)
  if maker.box.SetFontObject then maker.box:SetFontObject(T.FONT.small) end
  if maker.box.SetTextInsets then maker.box:SetTextInsets(6, 6, 0, 0) end
  if maker.box.SetMaxLetters then maker.box:SetMaxLetters(120) end
  script(maker.box, "OnEnterPressed", function() Calendar.saveMaker() end)
  script(maker.box, "OnEscapePressed", function(self) self:ClearFocus() end)
  local hint = T.text(maker, T.FONT.small, C.muted)
  hint:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -242)
  hint:SetWidth(W - X - PADM)
  hint:SetJustifyH("LEFT")
  hint:SetText("For a dungeon or raid the words can stay empty: its name is used. The whole crew sees the note.")
  local save = Widgets.button(maker, "Save note", function() Calendar.saveMaker() end, nil, FEATURE)
  save:SetSize(110, 26)
  save:SetPoint("BOTTOMRIGHT", maker, "BOTTOMRIGHT", -PADM, 12)
  local cancel = Widgets.button(maker, "Cancel", function() maker:Hide() end, nil, FEATURE)
  cancel:SetSize(80, 26)
  cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
  maker:Hide()
end

-- Opens "Create a note". opts: { day = local day number, minutes = time (local), kind =, dungeon = }.
function Calendar.openMaker(opts)
  opts = opts or {}
  if not maker then buildMaker() end
  mk.day = tonumber(opts.day) or (view == "day" and shownDay) or ns.Diary.localToday()
  mk.minutes = tonumber(opts.minutes)
  mk.kind = opts.kind or "note"
  mk.dungeon = opts.dungeon
  mk.icon = 1
  maker.box:SetText("")
  drawMaker()
  maker:Show()
  if maker.box.SetFocus then maker.box:SetFocus() end
end

-- Saves the note from "Create a note" and shows its day.
function Calendar.saveMaker(text)
  if not maker then return end
  text = text or maker.box:GetText()
  if mk.kind ~= "note" and not mk.dungeon then print("TwizCrew: pick the " .. mk.kind .. " first."); return end
  local at = mk.minutes and (mk.day * L.DAY + mk.minutes * 60 - ns.Diary.offset()) or nil
  local icon = mk.icon
  if mk.kind ~= "note" and icon == 1 then icon = mk.kind == "raid" and 3 or 2 end
  if not ns.Notes.add(dateKeyOf(mk.day), text, icon, at, mk.dungeon) then
    print("TwizCrew: type a few words for the note first.")
    return
  end
  maker:Hide()
  if Calendar.shownFlag then Calendar.openDay(mk.day) else Calendar.open(); Calendar.openDay(mk.day) end
  return true
end

function Calendar.makerForTest() return mk end
function Calendar.setMakerForTest(k, v) mk[k] = v; drawMaker() end

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
  sub:SetText("who played when, and notes for the crew")
  local close = Widgets.button(frame, "Close", function() Calendar.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -10)
  local create = Widgets.button(frame, "+ Create note", function() Calendar.openMaker({}) end, nil, FEATURE)
  create:SetSize(120, 24)
  create:SetPoint("RIGHT", close, "LEFT", -8, 0)
  zoneText = T.text(frame, T.FONT.small, C.muted)
  zoneText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -52)
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
        mk = CreateFrame("Frame", nil, dayPane)
        mk:SetSize(16, 16)
        mk.icon = iconTexture(mk, nil, 16)
        mk.icon:SetAllPoints(mk)
        mk.line = dayPane:CreateTexture(nil, "ARTWORK")
        mk.line:SetSize(2, DAY_ROWS * ROW_H)
        T.color(mk.line, C.title, 0.45)
        mk:EnableMouse(true)
        script(mk, "OnEnter", function(self)
          local note = self.tcNote
          if not GameTooltip or not note then return end
          GameTooltip:SetOwner(self, "ANCHOR_TOP")
          GameTooltip:SetText(tostring(ns.Notes.timeText(note, ns.Diary.offset())) .. " (your time)")
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
      mk:SetPoint("TOP", dayPane, "TOPLEFT", x, -(48 + DAY_ROWS * ROW_H))
      mk.line:ClearAllPoints()
      mk.line:SetPoint("TOP", dayPane, "TOPLEFT", x, -46)
      mk:Show(); mk.line:Show()
    end
  end
  for i = k + 1, #markers do markers[i]:Hide(); markers[i].line:Hide() end
  Calendar.lastMarkers = k
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
  zoneText:SetText("Times are in your time zone (" .. zoneName() .. ")")
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

-- The menu when you right-click a day on the month.
function Calendar.dayMenuItems(day)
  return {
    { label = "Create a note on this day", icon = ICON_NOTES, onClick = function() Calendar.openMaker({ day = day }) end },
    { label = "Create a dungeon run on this day", icon = I .. "INV_Sword_04",
      onClick = function() Calendar.openMaker({ day = day, kind = "dungeon", minutes = 20 * 60 }) end },
  }
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

-- (Diary's onEnable listens for CALENDAR_CHANGED and calls Calendar.refresh.)
