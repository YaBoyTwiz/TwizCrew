-- "My mocks" window (part of module "roasts"): write your own mocks for the Mock button, try them on yourself in
-- the 3D mock show, delete old ones. Opened by /tc mock, the My mocks button in the settings, or MockEditor.open().
local _, ns = ...

local MockEditor = {}
ns.MockEditor = MockEditor

local FEATURE = "roasts"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, PAD = 440, 14
local ROW_H = 24
local LIST_ROWS = 9

local frame, edit, list, rows, countText, ownOnly
local offset = 0 -- first row shown (scrolling)

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function me() return ns.playerName() end

-- Shows a line on yourself in the mock show (or tells you why not).
local function try(line)
  line = ns.Util.trim(tostring(line or ""))
  if line == "" then print("TwizCrew: type a mock first.") return end
  local text = ns.Roasts.mockText(line, me(), me(), ns.Roasts.mockInfo(me()))
  local _, class = UnitClass("player")
  ns.MockShow.show(me(), text, { mode = "live", unit = "player", class = class,
    look = ns.MockShow.decodeLook(ns.MockShow.myLook()) })
end

local function add(typed)
  local text = typed or edit:GetText()
  if ns.Roasts.addMock(text) then
    edit:SetText("")
    edit:ClearFocus()
    offset = math.max(0, #ns.Roasts.myMocks() - LIST_ROWS) -- show the new one at the bottom
    MockEditor.refresh()
  else
    print("TwizCrew: type a mock first, like: {name} tripped over a flower in {zone}.")
  end
end

local function newRow(i)
  local r = CreateFrame("Frame", nil, list)
  r:SetSize(WIDTH - 2 * PAD, ROW_H)
  r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
  local bg = r:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(r)
  T.color(bg, i % 2 == 0 and C.row or C.backdrop, 0.9)
  r.text = T.text(r, T.FONT.small, C.text)
  r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -96, 0)
  r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  r.del = Widgets.button(r, "X", function() MockEditor.remove(r.index) end, "danger", FEATURE)
  r.del:SetSize(24, 18)
  r.del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
  r.try = Widgets.button(r, "Try", function() try(ns.Roasts.myMocks()[r.index]) end, nil, FEATURE)
  r.try:SetSize(52, 18)
  r.try:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
  r:EnableMouse(true)
  script(r, "OnEnter", function(self)
    if not GameTooltip or not self.index then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.Util.safeText(ns.Roasts.myMocks()[self.index] or ""), 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return r
end

local function build()
  frame = T.frame("Frame", "TwizCrewMockEditor", UIParent)
  frame:SetSize(WIDTH, 150 + LIST_ROWS * ROW_H + 40)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  script(frame, "OnDragStart", function(self) self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewMockEditor") end -- Escape

  local title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("My mocks")
  local close = Widgets.button(frame, "Close", function() MockEditor.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -8)

  local help = T.text(frame, T.FONT.small, C.muted)
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  help:SetWidth(WIDTH - 2 * PAD)
  help:SetJustifyH("LEFT")
  if help.SetWordWrap then help:SetWordWrap(true) end
  help:SetText("Write what the Mock button says when a friend dies. Placeholders: " .. ns.Roasts.MOCK_HELP
    .. ". Your mocks join the built-in ones (or replace them: the switch below).")

  edit = T.frame("EditBox", nil, frame)
  edit:SetSize(WIDTH - 2 * PAD - 120, 24)
  edit:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
  T.paint(edit, C.row, 1, C.rowBorder, 1)
  edit:SetAutoFocus(false)
  if edit.SetFontObject then edit:SetFontObject(T.FONT.small) end
  if edit.SetTextInsets then edit:SetTextInsets(6, 6, 0, 0) end
  if edit.SetMaxLetters then edit:SetMaxLetters(120) end
  script(edit, "OnEnterPressed", function() add() end)
  script(edit, "OnEscapePressed", function(self) self:ClearFocus() end)
  local addButton = Widgets.button(frame, "Add", function() add() end, nil, FEATURE)
  addButton:SetSize(54, 22)
  addButton:SetPoint("LEFT", edit, "RIGHT", 6, 0)
  local tryButton = Widgets.button(frame, "Try", function() try(edit:GetText()) end, nil, FEATURE)
  tryButton:SetSize(54, 22)
  tryButton:SetPoint("LEFT", addButton, "RIGHT", 4, 0)

  ownOnly = Widgets.toggle(frame, "Only use my own mocks", "The Mock button picks only from your mocks (once you "
    .. "have at least one), not the built-in ones.",
    function() return ns.Modules.setting(FEATURE, "ownOnly") end,
    function(v) ns.Modules.set(FEATURE, "ownOnly", v) MockEditor.refresh() end)
  ownOnly:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -8)
  ownOnly:SetWidth(WIDTH - 2 * PAD)

  list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", ownOnly, "BOTTOMLEFT", 0, -8)
  list:SetSize(WIDTH - 2 * PAD, LIST_ROWS * ROW_H)
  if list.EnableMouseWheel then list:EnableMouseWheel(true) end
  script(list, "OnMouseWheel", function(_, delta)
    local most = math.max(0, #ns.Roasts.myMocks() - LIST_ROWS)
    offset = math.max(0, math.min(most, offset - (tonumber(delta) or 0)))
    MockEditor.refresh()
  end)
  rows = {}
  for i = 1, LIST_ROWS do rows[i] = newRow(i) end
  list.empty = T.text(list, T.FONT.small, C.muted)
  list.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6)
  list.empty:SetText("No mocks of your own yet. Write one above and press Add.")

  countText = T.text(frame, T.FONT.small, C.muted)
  countText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 12)
  frame:Hide()
end

function MockEditor.refresh()
  if not frame then return end
  local mine = ns.Roasts.myMocks()
  offset = math.max(0, math.min(offset, math.max(0, #mine - LIST_ROWS)))
  for i, r in ipairs(rows) do
    local n = offset + i
    if mine[n] then
      r.index = n
      r.text:SetText(n .. ". " .. ns.Util.safeText(mine[n]))
      r:Show()
    else
      r.index = nil
      r:Hide()
    end
  end
  if #mine == 0 then list.empty:Show() else list.empty:Hide() end
  if ownOnly and ownOnly.Refresh then ownOnly.Refresh() end
  local more = #mine > LIST_ROWS and "  (scroll for more)" or ""
  countText:SetText("Built-in mocks: " .. #ns.Roasts.MOCK_LINES .. "   Yours: " .. #mine .. more)
end

function MockEditor.remove(n)
  local gone = n and ns.Roasts.removeMock(n)
  if gone then print('TwizCrew: removed "' .. ns.Util.safeText(gone) .. '".') end
  MockEditor.refresh()
end

function MockEditor.open()
  if not frame then build() end
  MockEditor.refresh()
  frame:Show()
end

function MockEditor.close()
  if frame then frame:Hide() end
end

function MockEditor.isOpen() return frame ~= nil and frame:IsShown() and true or false end

-- Test hooks.
function MockEditor.addForTest(text) if not frame then build() end add(text) end
function MockEditor.tryForTest(text) try(text) end
function MockEditor.rowTextForTest(i) return rows and rows[i] and rows[i].index and ns.Roasts.myMocks()[rows[i].index] end
