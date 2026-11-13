-- Crew calendar, the window (part of module "calendar"): Month (who played each day, with class icons and note
-- icons; the tooltip has everyone's times), a day's timeline (one bar per friend, AFK lighter, their times written
-- on it, hover for who was on at that moment) with that day's notes and a box to add one (with an
-- icon), and Usual times (when the crew is usually on, the best time to play together, everyone's habits).
-- Opened by the calendar button on the panel, the wrench menu, /tc cal, or the button in the settings.
-- This file: the window, moving between the views and the helpers they share. Each view, loaded right after it:
-- Calendar/CalendarMonth.lua, Calendar/CalendarDay.lua (the day timeline), Calendar/CalendarUsual.lua (usual times
-- and the real-week grid) and Calendar/CalendarMaker.lua ("+ Create note" and the dungeon picker). What more than
-- one of these files uses lives on ns.Calendar._ (P).
local _, ns = ...

local Calendar = {}
ns.Calendar = Calendar
local P = {}
Calendar._ = P

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic

local I = "Interface\\Icons\\"
local ICON_CAL = I .. "INV_Scroll_03"
local ICON_USUAL = I .. "INV_Misc_PocketWatch_01"
local ICON_NOTES = I .. "INV_Misc_Note_01"
local PREV_TEX = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local NEXT_TEX = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"

local WIDTH, HEIGHT, PAD = 700, 570, 14
local TOP = 80 -- below the title and the tabs
P.I, P.ICON_NOTES, P.PREV_TEX, P.NEXT_TEX = I, ICON_NOTES, PREV_TEX, NEXT_TEX
P.WIDTH, P.HEIGHT, P.PAD, P.TOP = WIDTH, HEIGHT, PAD, TOP

local tabs
local zoneText
-- Shared state (set and read by more than one of the window's files)
-- Functions and constants on P are set once, at load, in this file; later files may copy them into locals; state
-- that changes is always read as P.x.
P.frame = nil
P.view = "month" -- "month" | "day" | "usual"
P.shownYear, P.shownMonth, P.shownDay = nil, nil, nil
P.monthPane, P.dayPane, P.usualPane = nil, nil, nil
P.dayScroll = 0 -- the day view's first row (more people than rows: the mouse wheel scrolls)

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

-- "UTC-5", "UTC+5:30" (off: an offset, default now's)
local function zoneName(off)
  off = tonumber(off) or ns.Diary.offset()
  local sign = off < 0 and "-" or "+"
  off = math.abs(off)
  local h, m = math.floor(off / 3600), math.floor((off % 3600) / 60)
  return "UTC" .. sign .. h .. (m > 0 and string.format(":%02d", m) or "")
end
Calendar.zoneName = zoneName
P.script, P.classHex, P.colored, P.people, P.altsText = script, classHex, colored, people, altsText
P.dateKeyOf, P.setArt, P.zoneName = dateKeyOf, setArt, zoneName

-------------------------------------------------------------------------------------------------- small pieces
-- size: as first designed; drawn a little bigger (Theme.icon).
local function iconTexture(parent, path, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  size = T.icon(size)
  t:SetSize(size, size)
  if path then t:SetTexture(path) end
  t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return t
end
P.iconTexture = iconTexture

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
P.arrowButton = arrowButton

-- A tab: an icon and a word, a gold line under the active one.
local function tabButton(label, icon, id, x)
  local b = CreateFrame("Button", nil, P.frame)
  b:SetSize(140, 26)
  b:SetPoint("TOPLEFT", P.frame, "TOPLEFT", x, -44)
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

local function build()
  P.frame = T.frame("Frame", "TwizCrewCalendar", UIParent)
  P.frame:SetSize(WIDTH, HEIGHT)
  P.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  P.frame:SetFrameStrata("DIALOG")
  P.frame:SetMovable(true)
  P.frame:EnableMouse(true)
  if P.frame.SetClampedToScreen then P.frame:SetClampedToScreen(true) end
  if P.frame.RegisterForDrag then P.frame:RegisterForDrag("LeftButton") end
  script(P.frame, "OnDragStart", function(self) self:StartMoving() end)
  script(P.frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  T.paint(P.frame, C.backdrop, 0.97, C.border, 2)
  T.gloss(P.frame, nil, 0.04, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewCalendar") end
  script(P.frame, "OnHide", function() Calendar.shownFlag = false end)
  local logo = iconTexture(P.frame, ICON_CAL, 26)
  logo:SetPoint("TOPLEFT", P.frame, "TOPLEFT", PAD, -10)
  local title = T.readable(T.text(P.frame, T.FONT.normal, C.title), 3)
  title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  title:SetText("Crew calendar")
  local sub = T.text(P.frame, T.FONT.small, C.muted)
  sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
  sub:SetText("who played when, and notes for the crew")
  local close = Widgets.button(P.frame, "Close", function() Calendar.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", P.frame, "TOPRIGHT", -PAD, -10)
  local create = Widgets.button(P.frame, "+ Create note", function() Calendar.openMaker({}) end, nil, FEATURE)
  create:SetSize(120, 24)
  create:SetPoint("RIGHT", close, "LEFT", -8, 0)
  zoneText = T.text(P.frame, T.FONT.small, C.muted)
  zoneText:SetPoint("TOPRIGHT", P.frame, "TOPRIGHT", -PAD, -52)
  tabs = { month = tabButton("Month", ICON_CAL, "month", PAD), usual = tabButton("Usual times", ICON_USUAL, "usual", PAD + 146) }
  P.buildMonth()
  P.buildDay()
  P.buildUsual()
end

-------------------------------------------------------------------------------------------------------- draw
local function drawTabs()
  for id, b in pairs(tabs) do
    local active = (id == P.view) or (id == "month" and P.view == "day")
    if active then b.line:Show(); b.text:SetTextColor(T.rgb(C.title)) else b.line:Hide(); b.text:SetTextColor(T.rgb(C.text)) end
  end
end

function Calendar.refresh()
  if not P.frame or not Calendar.shownFlag then return end
  P.monthPane:Hide(); P.dayPane:Hide(); P.usualPane:Hide()
  drawTabs()
  zoneText:SetText("Times are in your time zone (" .. zoneName() .. ")")
  if P.view == "day" then P.dayPane:Show(); P.drawDay()
  elseif P.view == "usual" then P.usualPane:Show(); P.drawUsual()
  else P.monthPane:Show(); P.drawMonth() end
end

-------------------------------------------------------------------------------------------------------- public
function Calendar.show(id)
  P.view = (id == "day" or id == "usual") and id or "month"
  Calendar.refresh()
end

function Calendar.moveMonth(delta)
  P.shownMonth = P.shownMonth + delta
  while P.shownMonth < 1 do P.shownMonth, P.shownYear = P.shownMonth + 12, P.shownYear - 1 end
  while P.shownMonth > 12 do P.shownMonth, P.shownYear = P.shownMonth - 12, P.shownYear + 1 end
  Calendar.refresh()
end

function Calendar.openDay(day)
  if not P.frame then Calendar.open() end
  if day ~= P.shownDay then P.dayScroll = 0 end
  P.shownDay = day
  local y, m = L.civil(day)
  P.shownYear, P.shownMonth = y, m
  P.view = "day"
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
  if not P.frame then build() end
  local today = ns.Diary.localToday()
  local y, m = L.civil(today)
  P.shownYear, P.shownMonth, P.shownDay = y, m, today
  P.view = "month"
  P.frame:Show()
  Calendar.shownFlag = true
  Calendar.refresh()
end

function Calendar.close()
  Calendar.shownFlag = false
  if P.frame then P.frame:Hide() end
end

function Calendar.toggle()
  if Calendar.shownFlag then Calendar.close() else Calendar.open() end
end

function Calendar.isShown() return Calendar.shownFlag and true or false end
function Calendar.viewForTest() return P.view, P.shownYear, P.shownMonth, P.shownDay end

-- (Diary's onEnable listens for CALENDAR_CHANGED and calls Calendar.refresh.)
