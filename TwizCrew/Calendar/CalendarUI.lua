-- Crew calendar, the window (part of module "calendar"): Month (who played each day), a day's timeline (one bar per
-- friend, AFK lighter), and Usual times (when the crew is usually on, the best time to play together, everyone's
-- habits). Opened by the wrench button on the panel, /tc cal, or the button in the settings.
-- Made ready for events (dungeon runs and the like): the day cells and the day view have room for them.
local _, ns = ...

local Calendar = {}
ns.Calendar = Calendar

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic

local WIDTH, HEIGHT, PAD = 680, 540, 14
local TOP = 74 -- below the title and the tabs
local CELL_W, CELL_H = 92, 66
local DOTS = 7
local AXIS_X, BAR_W, ROW_H, DAY_ROWS = 150, 500, 22, 16
local HEAT_X, HEAT_W, HEAT_H = 60, 24, 18

local frame, tabs, title, sub
local view = "month" -- "month" | "day" | "usual"
local shownYear, shownMonth, shownDay
local monthPane, dayPane, usualPane
local cells, dayRows, heatCells, habitLines = {}, {}, {}, {}
local texPool = {}

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function offset()
  local t = ns.Diary.now()
  local ok1, loc = pcall(date, "*t", t)
  local ok2, utc = pcall(date, "!*t", t)
  if ok1 and ok2 then return L.offsetFrom(loc, utc) end
  return 0
end

local function localToday() return math.floor((ns.Diary.now() + offset()) / L.DAY) end

local function classHex(class)
  local r, g, b = T.classColor(class)
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function colored(name, class)
  return "|cff" .. classHex(class) .. ns.Util.safeText(tostring(name or "?")) .. "|r"
end

-- Display list of people with names (my own first name stays mine even if I never shared).
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

-------------------------------------------------------------------------------------------------------- build
local function newTexture(parent, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  return t
end

local function tabButton(label, id, x)
  local b = Widgets.button(frame, label, function() Calendar.show(id) end, nil, FEATURE)
  b:SetSize(110, 22)
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -40)
  return b
end

local function buildMonth()
  monthPane = CreateFrame("Frame", nil, frame)
  monthPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
  monthPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local prev = Widgets.button(monthPane, "<", function() Calendar.moveMonth(-1) end, nil, FEATURE)
  prev:SetSize(28, 20)
  prev:SetPoint("TOPLEFT", monthPane, "TOPLEFT", 0, 0)
  local nxt = Widgets.button(monthPane, ">", function() Calendar.moveMonth(1) end, nil, FEATURE)
  nxt:SetSize(28, 20)
  nxt:SetPoint("TOPLEFT", monthPane, "TOPLEFT", 7 * CELL_W - 28, 0)
  monthPane.label = T.text(monthPane, T.FONT.normal, C.title)
  monthPane.label:SetPoint("TOP", monthPane, "TOPLEFT", 7 * CELL_W / 2, -3)
  for i = 1, 7 do
    local h = T.text(monthPane, T.FONT.small, C.muted)
    h:SetPoint("TOPLEFT", monthPane, "TOPLEFT", (i - 1) * CELL_W + 4, -26)
    h:SetText(L.SHORT_DAYS[i])
  end
  for i = 1, 42 do
    local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
    local c = CreateFrame("Button", nil, monthPane)
    c:SetSize(CELL_W - 2, CELL_H - 2)
    c:SetPoint("TOPLEFT", monthPane, "TOPLEFT", col * CELL_W, -(42 + row * CELL_H))
    T.paint(c, C.row, 0.85, C.rowBorder, 1)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints(c)
    T.color(c.hl, C.white, 0.06)
    c.num = T.text(c, T.FONT.small, C.text)
    c.num:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -4)
    c.total = T.text(c, T.FONT.small, C.muted)
    c.total:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -5, 4)
    c.today = c:CreateTexture(nil, "OVERLAY")
    c.today:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.today:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    c.today:SetHeight(2)
    T.color(c.today, C.title, 1)
    c.dots = {}
    for k = 1, DOTS do
      local d = c:CreateTexture(nil, "ARTWORK")
      d:SetSize(9, 9)
      d:SetPoint("TOPLEFT", c, "TOPLEFT", 5 + (k - 1) * 12, -24)
      d:Hide()
      c.dots[k] = d
    end
    c.more = T.text(c, T.FONT.small, C.muted)
    c.more:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -38)
    script(c, "OnClick", function(self) if self.tcDay then Calendar.openDay(self.tcDay) end end)
    script(c, "OnEnter", function(self)
      if not GameTooltip or not self.tcPeople then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local y, m, d = L.civil(self.tcDay)
      GameTooltip:SetText(L.WEEKDAYS[L.weekday(self.tcDay) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
      if #self.tcPeople == 0 then GameTooltip:AddLine("Nobody played (that we know of).", 1, 1, 1) end
      for _, p in ipairs(self.tcPeople) do
        GameTooltip:AddDoubleLine(colored(p.name, p.class), L.duration(p.minutes), 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddLine("Click for the timeline", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cells[i] = c
  end
end

local function buildDay()
  dayPane = CreateFrame("Frame", nil, frame)
  dayPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
  dayPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local back = Widgets.button(dayPane, "< Month", function() Calendar.show("month") end, nil, FEATURE)
  back:SetSize(70, 20)
  back:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, 0)
  local prev = Widgets.button(dayPane, "<", function() Calendar.openDay(shownDay - 1) end, nil, FEATURE)
  prev:SetSize(28, 20)
  prev:SetPoint("LEFT", back, "RIGHT", 6, 0)
  local nxt = Widgets.button(dayPane, ">", function() Calendar.openDay(shownDay + 1) end, nil, FEATURE)
  nxt:SetSize(28, 20)
  nxt:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  dayPane.label = T.text(dayPane, T.FONT.normal, C.title)
  dayPane.label:SetPoint("LEFT", nxt, "RIGHT", 10, 0)
  -- the hour axis
  for h = 0, 24, 3 do
    local x = AXIS_X + BAR_W * h / 24
    local t = T.text(dayPane, T.FONT.small, C.muted)
    t:SetPoint("TOP", dayPane, "TOPLEFT", x, -30)
    t:SetText(L.clock(h * 60))
    local line = dayPane:CreateTexture(nil, "BACKGROUND")
    line:SetSize(1, DAY_ROWS * ROW_H + 4)
    line:SetPoint("TOP", dayPane, "TOPLEFT", x, -44)
    T.color(line, C.rowBorder, 0.8)
  end
  dayPane.nowLine = dayPane:CreateTexture(nil, "OVERLAY")
  dayPane.nowLine:SetSize(2, DAY_ROWS * ROW_H + 4)
  T.color(dayPane.nowLine, C.title, 0.9)
  dayPane.empty = T.text(dayPane, T.FONT.normal, C.muted)
  dayPane.empty:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -60)
  dayPane.empty:SetText("Nobody played this day (that we know of).")
  for i = 1, DAY_ROWS do
    local r = CreateFrame("Frame", nil, dayPane)
    r:SetSize(WIDTH - 2 * PAD, ROW_H - 2)
    r:SetPoint("TOPLEFT", dayPane, "TOPLEFT", 0, -(48 + (i - 1) * ROW_H))
    r:EnableMouse(true)
    r.name = T.text(r, T.FONT.small, C.text)
    r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.name:SetWidth(AXIS_X - 50)
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
end

local function buildUsual()
  usualPane = CreateFrame("Frame", nil, frame)
  usualPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
  usualPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  usualPane.best = T.text(usualPane, T.FONT.normal, C.title)
  usualPane.best:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, 0)
  usualPane.best:SetWidth(WIDTH - 2 * PAD)
  usualPane.best:SetJustifyH("LEFT")
  usualPane.note = T.text(usualPane, T.FONT.small, C.muted)
  usualPane.note:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -20)
  usualPane.note:SetText("The last 4 weeks, in your local time. Brighter = more of the crew online.")
  for h = 0, 23, 3 do
    local t = T.text(usualPane, T.FONT.small, C.muted)
    t:SetPoint("BOTTOMLEFT", usualPane, "TOPLEFT", HEAT_X + h * HEAT_W, -54)
    t:SetText(L.clock(h * 60))
  end
  for w = 0, 6 do
    local lab = T.text(usualPane, T.FONT.small, C.muted)
    lab:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -(58 + w * HEAT_H) - 3)
    lab:SetText(L.SHORT_DAYS[w + 1])
    heatCells[w] = {}
    for h = 0, 23 do
      local c = CreateFrame("Frame", nil, usualPane)
      c:SetSize(HEAT_W - 1, HEAT_H - 1)
      c:SetPoint("TOPLEFT", usualPane, "TOPLEFT", HEAT_X + h * HEAT_W, -(58 + w * HEAT_H))
      c.tex = c:CreateTexture(nil, "ARTWORK")
      c.tex:SetAllPoints(c)
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
  usualPane.who = T.text(usualPane, T.FONT.normal, C.title)
  usualPane.who:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -(66 + 7 * HEAT_H))
  usualPane.who:SetText("Everyone's usual times")
  for i = 1, 9 do
    local fs = T.text(usualPane, T.FONT.small, C.text)
    fs:SetPoint("TOPLEFT", usualPane, "TOPLEFT", 0, -(88 + 7 * HEAT_H + (i - 1) * 16))
    fs:SetWidth(WIDTH - 2 * PAD)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    habitLines[i] = fs
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
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewCalendar") end
  script(frame, "OnHide", function() Calendar.shownFlag = false end)
  title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("Crew calendar")
  sub = T.text(frame, T.FONT.small, C.muted)
  sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
  sub:SetText("who played when, in your local time")
  local close = Widgets.button(frame, "Close", function() Calendar.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -8)
  tabs = { month = tabButton("Month", "month", PAD), usual = tabButton("Usual times", "usual", PAD + 116) }
  buildMonth()
  buildDay()
  buildUsual()
end

-------------------------------------------------------------------------------------------------------- draw
local function drawMonth()
  local off = offset()
  local today = localToday()
  monthPane.label:SetText(L.MONTHS[shownMonth] .. " " .. shownYear)
  local everyone = people()
  for i, cell in ipairs(L.monthGrid(shownYear, shownMonth)) do
    local c = cells[i]
    c.tcDay = cell.day
    c.num:SetText(cell.d)
    local list = cell.day <= today and L.dayView(everyone, cell.day, off) or {}
    c.tcPeople = list
    local minutes = 0
    for k = 1, DOTS do
      local p = list[k]
      if p then T.color(c.dots[k], classHex(p.class), 1); c.dots[k]:Show() else c.dots[k]:Hide() end
    end
    for _, p in ipairs(list) do minutes = minutes + p.minutes end
    c.more:SetText(#list > DOTS and ("+" .. (#list - DOTS) .. " more") or "")
    c.total:SetText(#list > 0 and (#list .. " on, " .. L.duration(minutes)) or "")
    c:SetAlpha(cell.inMonth and (cell.day <= today and 1 or 0.45) or 0.3)
    if cell.day == today then c.today:Show() else c.today:Hide() end
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
  local off = offset()
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
  if shownDay == localToday() then
    local minutes = ((ns.Diary.now() + off) % L.DAY) / 60
    dayPane.nowLine:ClearAllPoints()
    dayPane.nowLine:SetPoint("TOP", dayPane, "TOPLEFT", AXIS_X + BAR_W * minutes / 1440, -44)
    dayPane.nowLine:Show()
  else
    dayPane.nowLine:Hide()
  end
end

local function drawUsual()
  local u = L.usual(people(), localToday(), offset(), 4)
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
    end
  end
  for i, fs in ipairs(habitLines) do
    local p = u.people[i]
    if p then
      local alts = altsText(ns.Diary.people()[p.id])
      fs:SetText(colored(p.name, p.class) .. ":  about " .. L.duration(p.perWeek) .. " a week, " .. L.habit(p)
        .. (alts and ("  (" .. alts .. ")") or ""))
    else
      fs:SetText(i == 1 and "Nobody yet. Play times show up here as the crew plays with this version." or "")
    end
  end
end

function Calendar.refresh()
  if not frame or not Calendar.shownFlag then return end
  monthPane:Hide(); dayPane:Hide(); usualPane:Hide()
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
  if shownMonth < 1 then shownMonth, shownYear = 12, shownYear - 1 end
  if shownMonth > 12 then shownMonth, shownYear = 1, shownYear + 1 end
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

function Calendar.open()
  if not frame then build() end
  local y, m = L.civil(localToday())
  shownYear, shownMonth, shownDay = y, m, localToday()
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
