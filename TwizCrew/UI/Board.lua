-- The Hall of Shame tab, drawn inside the Crew panel (ns.Panel hosts it below its header): a "This session" /
-- "All time" switch, the subtitle, one row per award (badge, award name, winners in class colours, their number;
-- greyed "nobody yet" when nobody won it), a tooltip with the (i) text and the top 3, and the Wipe Squad line.
-- Every script runs under the panel's feature id.
local _, ns = ...

local Board = {}
ns.Board = Board

local FEATURE = "panel"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR

local PAD = 8          -- the panel's own padding (left edge of the board)
local SWITCH_HEIGHT, LINE, ROW_HEIGHT, ICON = 16, 13, 20, 16
local NAME_WIDTH, NUMBER_WIDTH = 108, 84
local EMPTY_ALPHA = 0.45

local view = "session"
local frame, sessionButton, allButton, subtitle, footer
local rows = {}         -- pool, one per award at most
local lastModel

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

-- A small text button: gold while active, muted otherwise. Also used by the panel for its tabs.
function Board.textButton(parent, label, onClick)
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
  script(b, "OnClick", function() onClick() end)
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

-- Names are already plain text (safeText), so they can sit inside colour codes.
local function winnersText(row)
  local parts = {}
  for i, name in ipairs(row.winners) do
    parts[i] = "|cff" .. hex(T.classColor(row.classes[i] or nil)) .. name .. "|r"
  end
  return table.concat(parts, ", ")
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
  r:SetHeight(ROW_HEIGHT)
  r:EnableMouse(true)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ICON, ICON)
  r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.name = T.text(r, T.FONT.small, C.title)
  r.name:SetPoint("LEFT", r, "LEFT", ICON + 4, 0)
  r.name:SetWidth(NAME_WIDTH)
  noWrap(r.name, "LEFT")
  r.number = T.text(r, T.FONT.small, C.text)
  r.number:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.number:SetWidth(NUMBER_WIDTH)
  noWrap(r.number, "RIGHT")
  r.winners = T.text(r, T.FONT.small, C.text)
  r.winners:SetPoint("LEFT", r, "LEFT", ICON + 4 + NAME_WIDTH + 4, 0)
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

  local y = SWITCH_HEIGHT + 2
  placeLine(subtitle, m.subtitle, y, width)
  y = y + LINE + 4
  local winnersWidth = width - (ICON + 4 + NAME_WIDTH + 4) - NUMBER_WIDTH - 4
  for i, row in ipairs(m.rows) do
    local r = rows[i]
    if not r then r = createRow(); rows[i] = r end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.icon:SetTexture(row.icon)
    r.name:SetText(row.name)
    r.winners:SetWidth(winnersWidth)
    r.winners:SetText(winnersText(row))
    r.number:SetText(row.text)
    r.tip = row.tip
    r:SetAlpha(row.empty and EMPTY_ALPHA or 1)
    r:Show()
    y = y + ROW_HEIGHT
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

-- "session" | "all": asks the crew for fresh numbers (rate-limited) and redraws the panel.
function Board.setView(v)
  if v ~= "session" and v ~= "all" then return end
  view = v
  if ns.Stats and ns.Modules.isEnabled("stats") then ns.Stats.request() end
  if ns.Panel and ns.Panel.refresh then ns.Panel.refresh() end
end

function Board.modelForTest() return lastModel end
