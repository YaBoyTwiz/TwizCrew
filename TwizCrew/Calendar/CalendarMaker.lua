-- Crew calendar, "Create a note": the window to add a note (a day, a time or none, a note, a dungeon or a raid, an
-- icon and the words) and its dungeon picker. Part of the calendar window (Calendar/CalendarUI.lua); shared names
-- live on ns.Calendar._ (P).
local _, ns = ...

local Calendar = ns.Calendar
local P = Calendar._

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic
local I, ICON_NOTES, PREV_TEX, NEXT_TEX = P.I, P.ICON_NOTES, P.PREV_TEX, P.NEXT_TEX
local script, dateKeyOf, setArt, zoneName = P.script, P.dateKeyOf, P.setArt, P.zoneName
local iconTexture, arrowButton = P.iconTexture, P.arrowButton

----------------------------------------------------------------------------------------------- "Create a note"
-- A small window: the day, a time (or none), what it is (a note, a dungeon, a raid), an icon and the words.
-- Save puts it on its day. A timed note is stored in one shared time (UTC), so every friend sees it at their own
-- local time and date (what their computer's clock says, not the server's).
local maker
local mk = { day = 0, minutes = nil, kind = "note", dungeon = nil, icon = 1 }
local KINDS = { { id = "note", label = "Note" }, { id = "dungeon", label = "Dungeon" }, { id = "raid", label = "Raid" } }

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

local drawMaker -- (below)
local LIST_ROWS = 8
local LIST_ROW_H = 22
local listOffset = 0
local ARROW_UP = "Interface\\Buttons\\Arrow-Up-Up"
local ARROW_DOWN = "Interface\\Buttons\\Arrow-Down-Up"

-- The dungeon (or raid) list: lowest levels first, each with its level range in a color for your level (green:
-- your range, grey: too easy, red: too high yet), its icon, and "new" for Forever's own dungeons.
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
    local size = (dg.raid and ("  |cffaaaaaa" .. (dg.size or 40) .. "-man|r") or "") .. (dg.new and "  |cff3fa9f5new|r" or "")
    items[#items + 1] = { key = dg.key, label = "|cff" .. FIT_COLOR[fit] .. "[" .. ns.Notes.levelText(dg) .. "]|r  " .. dg.name .. size,
      icon = dungeonIcon(dg), onClick = function() mk.dungeon = dg.key; drawMaker() end }
  end
  return items
end

-- The time arrows: "hour" +-1, "minute" +-15 (stays in its hour), "ampm" flips morning and evening. With no time
-- set yet, the first press starts at 8pm.
function Calendar.stepTime(what, delta)
  if not mk.minutes then mk.minutes = 20 * 60 end
  local h, m = math.floor(mk.minutes / 60), mk.minutes % 60
  delta = tonumber(delta) or 0
  if what == "hour" then h = (h + delta) % 24
  elseif what == "minute" then m = (m + 15 * delta) % 60
  elseif what == "ampm" then h = (h + 12) % 24 end
  mk.minutes = h * 60 + m
  drawMaker()
end

function Calendar.scrollList(delta)
  local items = maker and maker.items or {}
  listOffset = math.max(0, math.min(math.max(0, #items - LIST_ROWS), listOffset + (tonumber(delta) or 0)))
  drawMaker()
end

drawMaker = function()
  if not maker then return end
  local _, m, d = L.civil(mk.day)
  maker.dayText:SetText(L.WEEKDAYS[L.weekday(mk.day) + 1] .. ", " .. L.MONTHS[m] .. " " .. d)
  -- time
  if mk.minutes then
    local h, mm = math.floor(mk.minutes / 60), mk.minutes % 60
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    maker.hourText:SetText(tostring(h12))
    maker.minText:SetText(string.format("%02d", mm))
    maker.ampm.text:SetText(h < 12 and "AM" or "PM")
    maker.timeBox:SetAlpha(1)
    maker.noTime.text:SetText("No time")
    T.color(maker.noTime.fill, C.button, 1)
  else
    maker.hourText:SetText("--")
    maker.minText:SetText("--")
    maker.ampm.text:SetText("--")
    maker.timeBox:SetAlpha(0.45)
    maker.noTime.text:SetText("No time")
    T.color(maker.noTime.fill, C.title, 0.35)
  end
  maker.zone:SetText("your time (" .. zoneName() .. "); friends see it in theirs")
  for _, k in ipairs(KINDS) do
    local b = maker.kinds[k.id]
    if mk.kind == k.id then T.color(b.fill, C.title, 0.35) else T.color(b.fill, C.button, 1) end
  end
  -- the dungeon list (inside this window: nothing pops up over it)
  if mk.kind ~= "note" then
    local items = Calendar.placeItems()
    maker.items = items
    listOffset = math.max(0, math.min(math.max(0, #items - LIST_ROWS), listOffset))
    for i, row in ipairs(maker.rows) do
      local it = items[listOffset + i]
      row.tcItem = it
      if it then
        row.icon:SetTexture(it.icon)
        row.text:SetText(it.label)
        if it.key == mk.dungeon then row.sel:Show() else row.sel:Hide() end
        row:Show()
      else
        row:Hide()
      end
    end
    maker.listTitle:SetText((mk.kind == "raid" and "Pick a raid" or "Pick a dungeon") .. "  |cff777777(scroll for more)|r")
    maker.list:Show()
    maker.plain:Hide()
    local dg = mk.dungeon and ns.Notes.dungeon(mk.dungeon)
    if dg then
      setArt(maker.preview, dg.key, ns.Notes.iconTexture(mk.icon))
      maker.preview:Show()
      local fit = ns.Notes.levelFit(dg, UnitLevel and UnitLevel("player"))
      maker.placeLine:SetText(dg.name .. "\n|cff" .. FIT_COLOR[fit] .. ns.Notes.dungeonLine(dg) .. "|r")
      maker.placeLine:Show()
    else
      maker.preview:Hide()
      maker.placeLine:SetText("|cff777777Nothing picked yet|r")
      maker.placeLine:Show()
    end
  else
    maker.list:Hide()
    maker.preview:Hide()
    maker.placeLine:Hide()
    maker.plain:Show()
  end
  for i, b in ipairs(maker.picks) do
    if i == mk.icon then b.border:Show(); b:SetAlpha(1) else b.border:Hide(); b:SetAlpha(0.6) end
  end
end

local function smallButton(parent, label, w, onClick)
  local b = Widgets.button(parent, label, onClick, nil, FEATURE)
  b:SetSize(w, 22)
  b.fill = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  return b
end

-- A small up or down arrow button.
local function stepButton(parent, tex, onClick)
  local b = arrowButton(parent, tex, onClick)
  b:SetSize(18, 18)
  return b
end

local function buildMaker()
  local W, PADM = 540, 14
  maker = T.frame("Frame", "TwizCrewNoteMaker", UIParent)
  maker:SetSize(W, 480)
  maker:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  maker:SetFrameStrata("FULLSCREEN_DIALOG")
  maker:SetMovable(true)
  maker:EnableMouse(true)
  if maker.SetToplevel then maker:SetToplevel(true) end
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
  local function line(y)
    local t = maker:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", maker, "TOPLEFT", PADM, -y)
    t:SetPoint("TOPRIGHT", maker, "TOPRIGHT", -PADM, -y)
    T.color(t, C.line, 0.6)
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
  line(72)

  -- time: hour and minutes, each with an up and a down arrow (the mouse wheel works on them too), AM / PM
  label("Time", 86)
  maker.timeBox = CreateFrame("Frame", nil, maker)
  maker.timeBox:SetSize(230, 40)
  maker.timeBox:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -78)
  local function number(x, what)
    local box = CreateFrame("Frame", nil, maker.timeBox)
    box:SetSize(44, 34)
    box:SetPoint("LEFT", maker.timeBox, "LEFT", x, 0)
    T.paint(box, C.row, 1, C.rowBorder, 1)
    local fs = T.readable(T.text(box, T.FONT.normal, C.white), 6)
    fs:SetPoint("CENTER", box, "CENTER", 0, 0)
    box:EnableMouse(true)
    if box.EnableMouseWheel then box:EnableMouseWheel(true) end
    script(box, "OnMouseWheel", function(_, delta) Calendar.stepTime(what, delta > 0 and 1 or -1) end)
    local up = stepButton(maker.timeBox, ARROW_UP, function() Calendar.stepTime(what, 1) end)
    up:SetPoint("BOTTOMLEFT", box, "RIGHT", 2, 1)
    local down = stepButton(maker.timeBox, ARROW_DOWN, function() Calendar.stepTime(what, -1) end)
    down:SetPoint("TOPLEFT", box, "RIGHT", 2, -1)
    return fs
  end
  maker.hourText = number(0, "hour")
  local colon = T.readable(T.text(maker.timeBox, T.FONT.normal, C.white), 6)
  colon:SetPoint("LEFT", maker.timeBox, "LEFT", 66, 0)
  colon:SetText(":")
  maker.minText = number(78, "minute")
  maker.ampm = smallButton(maker, "PM", 50, function() Calendar.stepTime("ampm", 0) end)
  maker.ampm:SetPoint("LEFT", maker.timeBox, "LEFT", 150, 0)
  maker.noTime = smallButton(maker, "No time", 80, function() mk.minutes = nil; drawMaker() end)
  maker.noTime:SetPoint("LEFT", maker.ampm, "RIGHT", 6, 0)
  maker.zone = T.text(maker, T.FONT.small, C.muted)
  maker.zone:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -122)
  line(140)

  -- what it is
  label("What", 150)
  maker.kinds = {}
  local kx = X
  for _, k in ipairs(KINDS) do
    local b = smallButton(maker, k.label, 80, function()
      mk.kind = k.id
      listOffset = 0
      if k.id == "note" then mk.dungeon = nil
      elseif mk.dungeon and ((ns.Notes.dungeon(mk.dungeon).raid == true) ~= (k.id == "raid")) then mk.dungeon = nil end
      drawMaker()
    end)
    b:SetPoint("TOPLEFT", maker, "TOPLEFT", kx, -148)
    maker.kinds[k.id] = b
    kx = kx + 84
  end

  -- the dungeon list: rows you click, the mouse wheel scrolls
  local LIST_W = 300
  maker.list = CreateFrame("Frame", nil, maker)
  maker.list:SetSize(LIST_W, 20 + LIST_ROWS * LIST_ROW_H)
  maker.list:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -176)
  maker.list:EnableMouse(true)
  if maker.list.EnableMouseWheel then maker.list:EnableMouseWheel(true) end
  script(maker.list, "OnMouseWheel", function(_, delta) Calendar.scrollList(delta > 0 and -1 or 1) end)
  maker.listTitle = T.text(maker.list, T.FONT.small, C.muted)
  maker.listTitle:SetPoint("TOPLEFT", maker.list, "TOPLEFT", 0, 0)
  local lup = stepButton(maker.list, ARROW_UP, function() Calendar.scrollList(-3) end)
  lup:SetPoint("TOPRIGHT", maker.list, "TOPRIGHT", 0, 2)
  local ldown = stepButton(maker.list, ARROW_DOWN, function() Calendar.scrollList(3) end)
  ldown:SetPoint("RIGHT", lup, "LEFT", -2, 0)
  maker.rows = {}
  for i = 1, LIST_ROWS do
    local r = CreateFrame("Button", nil, maker.list)
    r:SetSize(LIST_W, LIST_ROW_H - 2)
    r:SetPoint("TOPLEFT", maker.list, "TOPLEFT", 0, -(18 + (i - 1) * LIST_ROW_H))
    T.paint(r, i % 2 == 0 and C.row or C.backdrop, 0.9, C.rowBorder, 1)
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetPoint("TOPLEFT", r, "TOPLEFT", 1, -1)
    r.sel:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -1, 1)
    T.color(r.sel, C.title, 0.35)
    r.sel:Hide()
    r.icon = iconTexture(r, nil, 18)
    r.icon:SetPoint("LEFT", r, "LEFT", 3, 0)
    r.text = T.text(r, T.FONT.small, C.white)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWidth(LIST_W - 32)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(r)
    T.color(hl, C.white, 0.1)
    script(r, "OnClick", function(self) if self.tcItem then self.tcItem.onClick() end end)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    script(r, "OnMouseWheel", function(_, delta) Calendar.scrollList(delta > 0 and -1 or 1) end)
    maker.rows[i] = r
  end
  maker.preview = maker:CreateTexture(nil, "ARTWORK")
  maker.preview:SetSize(140, 80)
  maker.preview:SetPoint("TOPLEFT", maker.list, "TOPRIGHT", 12, -18)
  maker.placeLine = T.text(maker, T.FONT.small, C.white)
  maker.placeLine:SetPoint("TOPLEFT", maker.preview, "BOTTOMLEFT", 0, -6)
  maker.placeLine:SetWidth(W - X - LIST_W - 12 - PADM)
  maker.placeLine:SetJustifyH("LEFT")
  maker.plain = T.text(maker, T.FONT.small, C.muted)
  maker.plain:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -184)
  maker.plain:SetWidth(W - X - PADM)
  maker.plain:SetJustifyH("LEFT")
  maker.plain:SetText("A plain note. Pick Dungeon or Raid above for a run with its picture on the calendar.")
  line(364)

  -- icon
  label("Icon", 374)
  maker.picks = {}
  for i, e in ipairs(ns.Notes.ICONS) do
    local b = CreateFrame("Button", nil, maker)
    b:SetSize(22, 22)
    b:SetPoint("TOPLEFT", maker, "TOPLEFT", X + (i - 1) * 26, -372)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    T.color(b.border, C.title, 1)
    local ic = iconTexture(b, e.tex, 18) -- fills its 22 square button
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
  label("Words", 408)
  maker.box = T.frame("EditBox", nil, maker)
  maker.box:SetSize(W - X - PADM, 24)
  maker.box:SetPoint("TOPLEFT", maker, "TOPLEFT", X, -406)
  T.paint(maker.box, C.row, 1, C.rowBorder, 1)
  maker.box:SetAutoFocus(false)
  if maker.box.SetFontObject then maker.box:SetFontObject(T.FONT.small) end
  if maker.box.SetTextInsets then maker.box:SetTextInsets(6, 6, 0, 0) end
  script(maker.box, "OnTextChanged", function(self) -- stops at what one message can carry
    local text = self:GetText()
    local fit = ns.Notes.fitWords(text)
    if fit ~= text then self:SetText(fit) end
  end)
  script(maker.box, "OnEnterPressed", function() Calendar.saveMaker() end)
  script(maker.box, "OnEscapePressed", function(self) self:ClearFocus() end)
  local hint = T.text(maker, T.FONT.small, C.muted)
  hint:SetPoint("TOPLEFT", maker, "TOPLEFT", PADM, -444)
  hint:SetWidth(W - 2 * PADM - 210)
  hint:SetJustifyH("LEFT")
  hint:SetText("For a dungeon or raid the words can stay empty. The whole crew sees the note.")
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
  mk.day = tonumber(opts.day) or (P.view == "day" and P.shownDay) or ns.Diary.localToday()
  mk.minutes = tonumber(opts.minutes)
  mk.kind = opts.kind or "note"
  mk.dungeon = opts.dungeon
  mk.icon = 1
  listOffset = 0
  maker.box:SetText("")
  drawMaker()
  maker:Show()
  if maker.Raise then maker:Raise() end
  if maker.box.SetFocus then maker.box:SetFocus() end
end

-- Saves the note from "Create a note" and shows its day.
function Calendar.saveMaker(text)
  if not maker then return end
  text = text or maker.box:GetText()
  if mk.kind ~= "note" and not mk.dungeon then print("TwizCrew: pick the " .. mk.kind .. " first."); return end
  local at = mk.minutes and ns.Diary.utcOf(mk.day, mk.minutes) or nil -- (with that date's own offset)
  local icon = mk.icon
  if mk.kind ~= "note" and icon == 1 then icon = mk.kind == "raid" and 3 or 2 end
  local key, why = ns.Notes.add(dateKeyOf(mk.day), text, icon, at, mk.dungeon)
  if not key then
    print(why == "full" and "TwizCrew: the calendar is full (300 notes). Old notes go after 90 days."
      or "TwizCrew: type a few words for the note first.")
    return
  end
  maker:Hide()
  if Calendar.shownFlag then Calendar.openDay(mk.day) else Calendar.open(); Calendar.openDay(mk.day) end
  return true
end

function Calendar.makerForTest() return mk end
function Calendar.makerBoxForTest() return maker and maker.box end
function Calendar.setMakerForTest(k, v) mk[k] = v; drawMaker() end
