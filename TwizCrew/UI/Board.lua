-- The Hall of Shame tab, drawn inside the Crew panel (ns.Panel hosts it below its header): a "This session" /
-- "All time" switch, five category tabs under the switch (TABS; only the chosen tab's awards are listed), the subtitle, one row per award, a tooltip with the (i) text and the top 3, and the Wipe
-- Squad line. An award row has two lines: badge, award name and the number on the first; the winners (class
-- colours, at most two names then "+N") under the name on the second. "nobody yet" rows are one greyed line.
-- Every script runs under the feature id "board" (not a module): a broken board is only logged and never turns
-- the Crew panel off. The panel also calls Board.draw inside ns.Log.safe("board", ...).
local _, ns = ...

local Board = {}
ns.Board = Board

local FEATURE = "board"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR

local PAD = 8          -- the panel's own padding (left edge of the board)
local SWITCH_HEIGHT, LINE, ICON = 18, 15, 19
local ROW_ONE, ROW_TWO = 21, 35 -- an empty award (one line), an award with winners (two lines)
local NAME_WIDTH = 130
local INDENT = ICON + 4         -- the award name and the winners start here
local EMPTY_ALPHA = 0.45

local view = "session"
local frame, sessionButton, allButton, subtitle, footer, tabButtons
local rows = {}         -- pool, one per award at most
local lastModel, lastLayout

local function script(f, name, fn, featureId) Widgets.script(f, name, fn, featureId or FEATURE) end

-- A small text button: gold while active, muted otherwise. Also used by the panel for its tabs (featureId "panel").
function Board.textButton(parent, label, onClick, featureId)
  local b = CreateFrame("Button", nil, parent)
  b.label = T.text(b, T.FONT.small, C.muted)
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(label)
  local w = b.label:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = #label * 6 end
  b:SetSize(w + 10, SWITCH_HEIGHT)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  T.color(hl, C.white, 0.08)
  script(b, "OnClick", function() onClick() end, featureId)
  function b.SetActive(self, on) T.textColor(self.label, on and C.title or C.muted) end
  return b
end

---------------------------------------------------------------------------------------------------------- model
local function entryMap(list)
  local map = {}
  for _, e in ipairs(list) do map[e.name] = e end
  return map
end

local function buildModel()
  local session = ns.Session and ns.Session.current() or nil
  local list = ns.StatsStore.entries(view, session and session.id)
  local map = entryMap(list)
  local ctx = {
    session = session,
    starter = session and ns.Session.starter(session) or nil,
    timeText = session and ns.BoardLogic.timeText(session.start) or "",
    wipeLine = ns.Modules.setting("stats", "wipeLine") and true or false,
    tab = Board.tab(),
    trophies = ns.Trophies and ns.Trophies.summary() or {},
    entries = map,
    online = function(name)
      local e = map[name]
      if e and e.mine then return true end
      local m = ns.roster and ns.roster:get(name)
      return (m and m.online) and true or false
    end,
    wall = ns.wallclock(),
  }
  return ns.BoardLogic.model(view, ns.StatsLogic.awards(list), ctx)
end

---------------------------------------------------------------------------------------------------------- frames
local function hex(r, g, b)
  local function byte(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- Names are already plain text (safeText), so they can sit inside colour codes. "A, B +2" for four tied winners.
local function winnersText(row)
  local parts = {}
  for i, name in ipairs(row.winners) do
    if i > ns.BoardLogic.SHOWN_WINNERS then break end
    parts[i] = "|cff" .. hex(T.classColor(row.classes[i] or nil)) .. name .. "|r"
  end
  local text = table.concat(parts, ", ")
  if (row.more or 0) > 0 then text = text .. " +" .. row.more end
  return text
end

local function showTip(r)
  local tip = r.tip
  if not GameTooltip or type(tip) ~= "table" or #tip == 0 then return end
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  local tr, tg, tb = T.rgb(C.title)
  GameTooltip:SetText(tip[1], tr, tg, tb, 1, true)
  local lr, lg, lb = T.rgb(C.text)
  for i = 2, #tip do GameTooltip:AddLine(tip[i], lr, lg, lb, true) end
  GameTooltip:Show()
end

local function noWrap(fs, justify)
  fs:SetJustifyH(justify)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
end

local function createRow()
  local r = CreateFrame("Frame", nil, frame)
  r:SetHeight(ROW_TWO)
  r:EnableMouse(true)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ICON, ICON)
  r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
  r.name = T.text(r, T.FONT.small, C.title)
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", INDENT, -2)
  r.name:SetWidth(NAME_WIDTH)
  noWrap(r.name, "LEFT")
  r.number = T.text(r, T.FONT.small, C.text)
  r.number:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -2)
  noWrap(r.number, "RIGHT")
  r.winners = T.text(r, T.FONT.small, C.text)
  r.winners:SetPoint("TOPLEFT", r, "TOPLEFT", INDENT, -(2 + LINE + 2))
  noWrap(r.winners, "LEFT")
  script(r, "OnEnter", showTip)
  script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return r
end

local function build(parent)
  frame = CreateFrame("Frame", nil, parent)
  sessionButton = Board.textButton(frame, "This session", function() Board.setView("session") end)
  sessionButton:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 0)
  allButton = Board.textButton(frame, "All time", function() Board.setView("all") end)
  allButton:SetPoint("LEFT", sessionButton, "RIGHT", 4, 0)
  tabButtons = {}
  local prev
  local tabList = {}
  for _, t in ipairs(ns.StatsDefs.TABS) do tabList[#tabList + 1] = t end
  tabList[#tabList + 1] = ns.BoardLogic.TROPHY_TAB
  for _, t in ipairs(tabList) do
    local id = t.id
    local b = Board.textButton(frame, t.label, function() Board.setTab(id) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, -(SWITCH_HEIGHT + 2)) end
    tabButtons[#tabButtons + 1] = b
    prev = b
  end
  subtitle = T.text(frame, T.FONT.small, C.muted)
  noWrap(subtitle, "LEFT")
  footer = T.text(frame, T.FONT.small, C.muted)
  noWrap(footer, "LEFT")
end

local function placeLine(fs, text, y, width)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
  fs:SetWidth(width)
  fs:SetText(text)
  fs:Show()
end

---------------------------------------------------------------------------------------------------------- public
-- Draws the board inside parent, `top` px below its top edge, `width` px wide. Returns the height used.
function Board.draw(parent, top, width)
  if not frame then build(parent) end
  local m = buildModel()
  lastModel = m
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -top)
  frame:SetWidth(width)
  sessionButton:SetActive(view == "session")
  allButton:SetActive(view == "all")
  for i, t in ipairs(m.tabs) do
    if tabButtons[i] then tabButtons[i]:SetActive(t.active) end
  end

  local y = 2 * (SWITCH_HEIGHT + 2)
  placeLine(subtitle, m.subtitle, y, width)
  y = y + LINE + 4
  local numberWidth = width - INDENT - NAME_WIDTH - 4
  local winnersWidth = width - INDENT
  lastLayout = { width = width, numberWidth = numberWidth, winnersWidth = winnersWidth, rows = {} }
  for i, row in ipairs(m.rows) do
    local r = rows[i]
    if not r then r = createRow(); rows[i] = r end
    local height = row.empty and ROW_ONE or ROW_TWO
    local winners = row.empty and "" or winnersText(row)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r:SetHeight(height)
    r.icon:SetTexture(row.icon)
    r.name:SetText(row.name)
    r.number:SetWidth(numberWidth)
    r.number:SetText(row.text)
    r.winners:SetWidth(winnersWidth)
    r.winners:SetText(winners)
    if row.empty then r.winners:Hide() else r.winners:Show() end
    r.tip = row.tip
    r:SetAlpha(row.empty and EMPTY_ALPHA or 1)
    r:Show()
    lastLayout.rows[i] = { name = row.name, number = row.text, winners = winners, height = height }
    y = y + height
  end
  for i = #m.rows + 1, #rows do rows[i]:Hide() end
  if m.footer then
    placeLine(footer, m.footer, y + 4, width)
    y = y + 4 + LINE
  else
    footer:Hide()
  end
  frame:SetHeight(y)
  frame:Show()
  return y
end

function Board.hide()
  if frame then frame:Hide() end
end

function Board.view() return view end

local function tabKnown(id)
  if id == ns.BoardLogic.TROPHY_TAB.id then return true end
  for _, t in ipairs(ns.StatsDefs.TABS) do if t.id == id then return true end end
  return false
end

-- The chosen tab (remembered in the stats setting "boardTab").
function Board.tab()
  local id = ns.Modules.setting("stats", "boardTab")
  if tabKnown(id) then return id end
  return ns.StatsDefs.TABS[1].id
end

function Board.setTab(id)
  if not tabKnown(id) then return end
  ns.Modules.set("stats", "boardTab", id)
  if ns.Panel and ns.Panel.refresh then ns.Panel.refresh() end
end

-- "session" | "all": asks the crew for fresh numbers (rate-limited) and redraws the panel.
function Board.setView(v)
  if v ~= "session" and v ~= "all" then return end
  view = v
  if ns.Stats and ns.Modules.isEnabled("stats") then ns.Stats.request() end
  if ns.Panel and ns.Panel.refresh then ns.Panel.refresh() end
end

function Board.modelForTest() return lastModel end
function Board.layoutForTest() return lastLayout end
