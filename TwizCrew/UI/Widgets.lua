-- Shared widgets: (i) button, toggle, slider, choice, text box, plain button, small menu, tag pill.
-- Every widget takes an info text and builds its own (i) button. Every script runs inside ns.Log.safe.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local T = ns.Theme
local C = T.COLOR
local FEATURE = "widgets"
local ROW_WIDTH, ROW_HEIGHT = 320, 24

-- Sets a script handler that can never put a Lua error on screen.
function Widgets.script(frame, name, fn, featureId)
  local id = featureId or FEATURE
  frame:SetScript(name, function(...) ns.Log.safe(id, fn, ...) end)
end
local script = Widgets.script

function Widgets.percent(v)
  return math.floor((tonumber(v) or 0) * 100 + 0.5) .. "%"
end

---------------------------------------------------------------------------------------------------------- (i) button
local pinned -- the (i) button whose tooltip was clicked to stay open

local function showTip(owner, title, text)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(title or "", T.rgb(C.title))
  if text and text ~= "" then
    local r, g, b = T.rgb(C.text)
    GameTooltip:AddLine(text, r, g, b, true)
  end
  GameTooltip:Show()
end

local function tipIsFor(owner)
  if not GameTooltip or not GameTooltip:IsShown() then return false end
  if GameTooltip.IsOwned then return GameTooltip:IsOwned(owner) and true or false end
  return true
end

function Widgets.infoButton(parent, title, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 16)
  local fs = T.text(b, T.FONT.small, C.muted)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetText("(i)")
  b.title, b.text = title, text
  script(b, "OnEnter", function(self) showTip(self, self.title, self.text) end)
  script(b, "OnLeave", function(self)
    if pinned == self then return end
    if pinned then showTip(pinned, pinned.title, pinned.text) elseif GameTooltip then GameTooltip:Hide() end
  end)
  script(b, "OnClick", function(self)
    if pinned == self and tipIsFor(self) then
      pinned = nil
      if GameTooltip then GameTooltip:Hide() end
    else
      pinned = self
      showTip(self, self.title, self.text)
    end
  end)
  script(b, "OnHide", function(self)
    if pinned == self then
      pinned = nil
      if GameTooltip then GameTooltip:Hide() end
    end
  end)
  return b
end

--------------------------------------------------------------------------------------------------- setting rows
-- A row: label on the left, its (i) button after it, the control on the right.
local function settingRow(parent, label, info)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(ROW_WIDTH, ROW_HEIGHT)
  f.label = T.text(f, T.FONT.small, C.text)
  f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.label:SetText(label or "")
  f.info = Widgets.infoButton(f, label, info)
  f.info:SetPoint("LEFT", f.label, "RIGHT", 2, 0)
  f.Refresh = function() end
  -- Greys the row out and stops clicks (for a setting whose parent switch is off).
  f.SetActive = function(self, on)
    self:SetAlpha(on and 1 or 0.45)
    if self.control then
      if self.control.EnableMouse then self.control:EnableMouse(on and true or false) end
      if not on and self.control.ClearFocus then self.control:ClearFocus() end
    end
  end
  return f
end

local function boxed(frame, bgHex, borderHex)
  T.paint(frame, bgHex or C.button, 1, borderHex or C.buttonBorder, 1)
end

function Widgets.toggle(parent, label, info, get, set)
  local f = settingRow(parent, label, info)
  local sw = CreateFrame("Button", nil, f)
  sw:SetSize(34, 18)
  sw:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  local track = sw:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(sw)
  local knob = sw:CreateTexture(nil, "ARTWORK")
  knob:SetSize(14, 14)
  f.control = sw
  f.Refresh = function()
    local on = get() and true or false
    T.color(track, on and C.switchOn or C.switchOff, 1)
    T.color(knob, on and C.knobOn or C.knobOff, 1)
    knob:ClearAllPoints()
    if on then knob:SetPoint("RIGHT", sw, "RIGHT", -2, 0) else knob:SetPoint("LEFT", sw, "LEFT", 2, 0) end
  end
  script(sw, "OnClick", function()
    set(not get())
    f.Refresh()
  end)
  f.Refresh()
  return f
end

local function snap(v, min, max, step)
  v = tonumber(v) or min
  if step and step > 0 then v = min + math.floor((v - min) / step + 0.5) * step end
  if v < min then v = min elseif v > max then v = max end
  return tonumber(string.format("%.4f", v))
end

-- fmt: function(value) -> text (default: two decimals)
function Widgets.slider(parent, label, info, min, max, step, get, set, fmt)
  local f = settingRow(parent, label, info)
  local show = type(fmt) == "function" and fmt or function(v) return string.format("%.2f", v) end
  local s = CreateFrame("Slider", nil, f)
  s:SetSize(120, 16)
  s:SetPoint("RIGHT", f, "RIGHT", -44, 0)
  if s.SetOrientation then s:SetOrientation("HORIZONTAL") end
  s:SetMinMaxValues(min, max)
  if s.SetValueStep then s:SetValueStep(step) end
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  if s.EnableMouseWheel then s:EnableMouseWheel(false) end
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetHeight(4)
  track:SetPoint("LEFT", s, "LEFT", 0, 0)
  track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  T.color(track, C.button, 1)
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(8, 14)
  T.color(thumb, C.title, 1)
  if s.SetThumbTexture then s:SetThumbTexture(thumb) end
  local value = T.text(f, T.FONT.small, C.title)
  value:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  value:SetWidth(40)
  value:SetJustifyH("RIGHT")
  f.control = s
  local updating = false
  f.Refresh = function()
    local v = snap(get(), min, max, step)
    updating = true
    s:SetValue(v)
    updating = false
    value:SetText(show(v))
  end
  script(s, "OnValueChanged", function(_, raw)
    if updating then return end
    local v = snap(raw, min, max, step)
    value:SetText(show(v))
    if v ~= get() then set(v) end
  end)
  f.Refresh()
  return f
end

-- choices = { { value, label }, ... }. Click goes to the next one, right-click to the one before.
function Widgets.choice(parent, label, info, choices, get, set)
  local f = settingRow(parent, label, info)
  local b = T.frame("Button", nil, f)
  b:SetSize(130, 20)
  b:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  boxed(b)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  local text = T.text(b, T.FONT.small, C.text)
  text:SetPoint("CENTER", b, "CENTER", 0, 0)
  f.control = b
  local function index()
    local cur = get()
    for i, c in ipairs(choices) do if c[1] == cur then return i end end
    return 0
  end
  f.Refresh = function()
    local i = index()
    text:SetText(choices[i] and choices[i][2] or "")
  end
  script(b, "OnClick", function(_, button)
    local n = #choices
    if n == 0 then return end
    local i = index()
    if i == 0 then i = 1
    elseif button == "RightButton" then i = (i - 2) % n + 1
    else i = i % n + 1 end
    set(choices[i][1])
    f.Refresh()
  end)
  f.Refresh()
  return f
end

-- Saves on Enter or when the box loses focus; Escape puts the saved text back.
-- password: the box shows stars instead of the letters (when the game supports it).
function Widgets.text(parent, label, info, get, set, password)
  local f = settingRow(parent, label, info)
  local e = T.frame("EditBox", nil, f)
  e:SetSize(140, 20)
  e:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  boxed(e, C.backdrop)
  e:SetAutoFocus(false)
  if e.SetFontObject then e:SetFontObject(T.FONT.small) end
  if e.SetTextInsets then e:SetTextInsets(5, 5, 0, 0) end
  if password and e.SetPassword then e:SetPassword(true) end
  f.control = e
  local function save()
    local v = e:GetText()
    if type(v) == "string" and v ~= get() then set(v) end
  end
  f.Refresh = function() e:SetText(tostring(get() or "")) end
  script(e, "OnEnterPressed", function(self) save(); self:ClearFocus() end)
  script(e, "OnEditFocusLost", function() save() end)
  script(e, "OnEscapePressed", function(self) f.Refresh(); self:ClearFocus() end)
  f.Refresh()
  return f
end

-- An action row: a button with its (i) button after it (settings kind "button").
function Widgets.action(parent, label, info, onClick, featureId)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(ROW_WIDTH, ROW_HEIGHT)
  f.button = Widgets.button(f, label, onClick, nil, featureId)
  f.button:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.info = Widgets.infoButton(f, label, info)
  f.info:SetPoint("LEFT", f.button, "RIGHT", 4, 0)
  f.control = f.button
  f.Refresh = function() end
  f.SetActive = function(self, on) self:SetAlpha(on and 1 or 0.45) end
  return f
end

-- A read-only list: a label with its (i) button, then one line of text per entry (settings kind "list").
-- getLines() -> { text, ... } (already safe to show). f:Height() is the height the lines need.
local LIST_LINE = 16
function Widgets.lines(parent, label, info, getLines)
  local f = settingRow(parent, label, info)
  f.label:ClearAllPoints()
  f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -5)
  local texts = {}
  f.control = false
  f.shownLines = {}
  f.Height = function() return ROW_HEIGHT + #f.shownLines * LIST_LINE end
  f.Refresh = function()
    local ok, lines = pcall(getLines)
    if not ok or type(lines) ~= "table" then lines = {} end
    f.shownLines = lines
    for i, line in ipairs(lines) do
      local fs = texts[i]
      if not fs then
        fs = T.text(f, T.FONT.small, C.text)
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -ROW_HEIGHT - (i - 1) * LIST_LINE)
        fs:SetJustifyH("LEFT")
        texts[i] = fs
      end
      fs:SetText(tostring(line))
      fs:Show()
    end
    for i = #lines + 1, #texts do texts[i]:Hide() end
    f:SetHeight(f.Height())
  end
  f.Refresh()
  return f
end

---------------------------------------------------------------------------------------------------------- button
-- A plain button with a label. kind "danger" is the red one (reset).
function Widgets.button(parent, label, onClick, kind, featureId)
  local b = T.frame("Button", nil, parent)
  if kind == "danger" then boxed(b, C.danger, C.dangerBorder) else boxed(b) end
  b.text = T.text(b, T.FONT.small, C.white)
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText(label or "")
  local w = b.text:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = #(label or "") * 6 end
  b:SetSize(math.max(60, w + 20), 22)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  T.color(hl, C.white, 0.08)
  script(b, "OnClick", function() onClick() end, featureId)
  return b
end

---------------------------------------------------------------------------------------------------------- menu
local menu, catcher
local menuButtons = {}

local function closeMenu()
  if menu then menu:Hide() end
end
Widgets.closeMenu = closeMenu

local function buildMenu()
  -- A see-through frame over the whole screen: a click anywhere outside the menu closes it.
  catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("TOOLTIP") -- above every window (also TwizCrew's own dialogs), just under the menu
  catcher:SetFrameLevel(1)
  catcher:EnableMouse(true)
  catcher:Hide()
  script(catcher, "OnMouseDown", closeMenu)
  menu = T.frame("Frame", "TwizCrewMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP")
  menu:SetFrameLevel(20)
  if menu.SetToplevel then menu:SetToplevel(true) end
  if menu.SetClampedToScreen then menu:SetClampedToScreen(true) end
  menu:EnableMouse(true)
  T.paint(menu, C.backdrop, 0.95, C.border, 2)
  menu:Hide()
  script(menu, "OnHide", function() catcher:Hide() end)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewMenu") end -- Escape closes it
end

local function menuButton(i)
  local b = menuButtons[i]
  if b then return b end
  b = CreateFrame("Button", nil, menu)
  b:SetHeight(18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(b)
  T.color(b.hl, C.border, 0.5)
  b.check = b:CreateTexture(nil, "ARTWORK")
  b.check:SetSize(14, 14)
  b.check:SetPoint("LEFT", b, "LEFT", 4, 0)
  b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.icon = b:CreateTexture(nil, "ARTWORK") -- an item's own picture (optional), right of the check
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("LEFT", b, "LEFT", 21, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon:Hide()
  b.label = T.text(b, T.FONT.small, C.text)
  b.label:SetPoint("LEFT", b, "LEFT", 22, 0)
  b.label:SetJustifyH("LEFT")
  script(b, "OnClick", function(self)
    closeMenu()
    if self.item and type(self.item.onClick) == "function" then self.item.onClick() end
  end)
  menuButtons[i] = b
  return b
end

-- items = { { label, checked = fn|nil, onClick = fn, icon = texture path|nil } }. Opens under `anchor`.
function Widgets.menu(anchor, items)
  if not menu then buildMenu() end
  local width = 160
  for i, item in ipairs(items) do
    local b = menuButton(i)
    b.item = item
    b.label:SetText(item.label or "")
    local left = 22
    if type(item.icon) == "string" then
      b.icon:SetTexture(item.icon)
      b.icon:Show()
      left = 39
    else
      b.icon:Hide()
    end
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", left, 0)
    local w = b.label:GetStringWidth()
    if type(w) == "number" and w + left + 12 > width then width = w + left + 12 end
    local checked = type(item.checked) == "function" and item.checked()
    if checked then b.check:Show() else b.check:Hide() end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 18)
    b:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
    b:Show()
  end
  for i = #items + 1, #menuButtons do menuButtons[i]:Hide() end
  menu:SetSize(width, #items * 18 + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  catcher:Show()
  menu:Show()
  if menu.Raise then menu:Raise() end
  return menu
end

---------------------------------------------------------------------------------------------------------- tag pill
local function setTag(pill, tagId)
  pill.tag = tagId
  local label = ns.Tags.LABEL[tagId] or tostring(tagId)
  pill.text:SetText(label)
  local p = pill.tcPaint
  if p then p.bg = ns.Tags.COLOR[tagId] or C.button end
  T.setBackgroundAlpha(pill, 1)
  T.textColor(pill.text, tagId == "AFK" and "cccccc" or C.white)
  local icon = ns.Tags.ICON and ns.Tags.ICON[tagId]
  local iconRoom = 0
  if icon then
    pill.icon:SetTexture(icon)
    -- square game icons have a dark frame: trim it (the skull is a plain picture, keep it whole)
    if icon:find("Interface\\Icons\\", 1, true) then pill.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else pill.icon:SetTexCoord(0, 1, 0, 1) end
    pill.icon:Show()
    iconRoom = 17
  else
    pill.icon:Hide()
  end
  pill.text:ClearAllPoints()
  pill.text:SetPoint("CENTER", pill, "CENTER", iconRoom / 2, 0)
  local w = pill.text:GetStringWidth()
  pill:SetWidth((type(w) == "number" and w > 0 and w or #label * 6) + 10 + iconRoom)
end

function Widgets.tagPill(parent)
  local pill = T.frame("Frame", nil, parent)
  pill:SetHeight(18)
  T.paint(pill, C.button, 1, C.pillBorder, 1)
  pill.icon = pill:CreateTexture(nil, "ARTWORK")
  pill.icon:SetSize(16, 16)
  pill.icon:SetPoint("LEFT", pill, "LEFT", 2, 0)
  pill.shine = T.gloss(pill, nil, 0.25, "ARTWORK") -- under the label, so the text stays crisp
  pill.text = T.readable(T.text(pill, T.FONT.small, C.white))
  pill.text:SetPoint("CENTER", pill, "CENTER", 0, 0)
  pill:EnableMouse(true)
  pill.SetTag = setTag
  script(pill, "OnEnter", function(self)
    showTip(self, ns.Tags.LABEL[self.tag] or "", ns.Tags.INFO[self.tag])
  end)
  script(pill, "OnLeave", function()
    if pinned then showTip(pinned, pinned.title, pinned.text) elseif GameTooltip then GameTooltip:Hide() end
  end)
  return pill
end
