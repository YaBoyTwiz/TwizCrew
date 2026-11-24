-- A friend's quests in a small window (opened by "Their quests" on their row's menu and by the group heads-up):
-- their quests under the headings of their quest log (the zone they are in), the zone I'm in first; a check box beside
-- each quest I can get, greyed lines with the reason for the others; "Tick this zone" on each heading; "Only this zone"
-- at the top; one button at the bottom asks for all the ticked ones at once (Crew/QuestAsk.lua). A list from an older
-- copy has no headings: one list, no "Only this zone". The mouse wheel scrolls (a full log is about 30 lines).
-- A plain frame (not a secure one): fine to build, show and hide in a fight. Escape closes it.
local _, ns = ...

local QuestWindow = {}
ns.QuestWindow = QuestWindow

local FEATURE = "quest"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR

local WIDTH, ROW_H, VISIBLE, PAD = 380, 22, 14, 12
local TOP = 62           -- the list starts this far below the top
local BUTTON_W, ZONE_W = 150, 116
local CHECK = "Interface\\Buttons\\UI-CheckBox-"

local frame, rows, title, onlyBox, onlyLabel, askButton, statusText, hintText
local friend             -- whose quests the window shows
local ticks = {}         -- quest ID -> true: ticked (forgotten when the window shows someone else)
local onlyHere = false   -- "Only this zone" (not saved: off again after a /reload)
local offset = 0
local isOpen = false

local function safe(s) return ns.Util.safeText(tostring(s or "")) end

local function plain(s)
  return (tostring(s or ""):gsub("||", "\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\1", "||"))
end

-- The game's own check box look.
local function checkBox(parent)
  local b = CreateFrame("CheckButton", nil, parent)
  b:SetSize(20, 20)
  b:SetNormalTexture(CHECK .. "Up")
  b:SetPushedTexture(CHECK .. "Down")
  b:SetHighlightTexture(CHECK .. "Highlight", "ADD")
  b:SetCheckedTexture(CHECK .. "Check")
  b:SetDisabledCheckedTexture(CHECK .. "Check-Disabled")
  return b
end

-------------------------------------------------------------------------------------------------- what it shows
local function questText(q)
  local t = safe(q.title)
  if q.can then return t end
  if q.status == "have" then return t .. " (you both have)" end
  return "Can't share: " .. t .. " (" .. ns.QuestList.why(q) .. ")"
end

local function note(text) return { kind = "note", text = text } end

-- The quests I can get, ticked, in the order the window shows them (hidden zones too: a tick stays a tick).
local function tickedIds()
  local out = {}
  if not friend or not ns.QuestList.known(friend) then return out end
  for _, grp in ipairs(ns.QuestList.groups(friend).groups) do
    for _, q in ipairs(grp.quests) do
      if q.can and ticks[q.id] then out[#out + 1] = q.id end
    end
  end
  return out
end

-- The window's lines, top to bottom: { kind = "note", text } | { kind = "head", group, text, tick (the heading's
-- button label, nil when nothing under it can be ticked) } | { kind = "quest", q, text, can, ticked }.
function QuestWindow.entries()
  local out = {}
  if not friend then return out end
  local QL = ns.QuestList
  if not QL.known(friend) then
    return { note("No quest list from them yet (asked just now)"), note("They may have an older TwizCrew") }
  end
  local g = QL.groups(friend)
  local groups = g.groups
  if g.headed and onlyHere then
    local kept = {}
    for _, grp in ipairs(groups) do if grp.here then kept[#kept + 1] = grp end end
    if #kept == 0 then
      return { note(safe(friend) .. " has no quests in " .. (g.zone and safe(g.zone) or "this zone") .. ".") }
    end
    groups = kept
  end
  local any = false
  for _, grp in ipairs(groups) do
    if g.headed then
      local gettable, all = 0, true
      for _, q in ipairs(grp.quests) do
        if q.can then
          gettable = gettable + 1
          if not ticks[q.id] then all = false end
        end
      end
      out[#out + 1] = { kind = "head", group = grp, text = safe(grp.title) .. (grp.here and " (you are here)" or ""),
        tick = gettable > 0 and (all and "Untick this zone" or "Tick this zone") or nil }
    end
    for _, q in ipairs(grp.quests) do
      any = true
      out[#out + 1] = { kind = "quest", q = q, text = questText(q), can = q.can, ticked = q.can and ticks[q.id] == true }
    end
  end
  if not any then return { note("They have no quests (or don't share them)") } end
  return out
end

-- The button at the bottom: its label and whether it can be clicked.
function QuestWindow.buttonState()
  if friend and ns.QuestAsk and ns.QuestAsk.active(friend) then return "Stop asking", true end
  local n = #tickedIds()
  if n == 0 then return "Ask for quests", false end
  return "Ask for " .. (n == 1 and "1 quest" or (n .. " quests")), true
end

local function statusLine()
  local s = friend and ns.QuestAsk and ns.QuestAsk.status(friend)
  if s then return s end
  if not ns.QuestList.inAnyGroup() then return "Sharing only works in a group." end
  return ""
end

---------------------------------------------------------------------------------------------------------- frame
local draw -- (below)

local function fillRow(r, e)
  r.tcEntry = e
  r.check:Hide()
  r.zone:Hide()
  r.text:ClearAllPoints()
  r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  if e.kind == "head" then
    r.text:SetPoint("LEFT", r, "LEFT", 2, 0)
    T.textColor(r.text, C.title)
    if e.tick then
      r.zone.text:SetText(e.tick)
      r.zone:Show()
      r.text:ClearAllPoints()
      r.text:SetPoint("LEFT", r, "LEFT", 2, 0)
      r.text:SetPoint("RIGHT", r.zone, "LEFT", -6, 0)
    end
  elseif e.kind == "quest" then
    r.text:SetPoint("LEFT", r, "LEFT", 32, 0)
    if e.can then
      r.check:SetChecked(e.ticked and true or false)
      r.check:Show()
    end
    T.textColor(r.text, e.can and C.text or C.muted)
  else
    r.text:SetPoint("LEFT", r, "LEFT", 2, 0)
    T.textColor(r.text, C.muted)
  end
  r.text:SetText(e.text)
  r:Show()
end

local function newRow(i)
  local r = CreateFrame("Frame", nil, frame)
  r:SetSize(WIDTH - 2 * PAD, ROW_H)
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + (i - 1) * ROW_H))
  r.check = checkBox(r)
  r.check:SetPoint("LEFT", r, "LEFT", 6, 0)
  Widgets.script(r.check, "OnClick", function()
    local e = rawget(r, "tcEntry")
    if e and e.kind == "quest" then QuestWindow.toggle(e.q.id) end
  end, FEATURE)
  r.zone = Widgets.button(r, "Tick this zone", function()
    local e = rawget(r, "tcEntry")
    if e and e.kind == "head" then QuestWindow.tickZone(e.group) end
  end, nil, FEATURE)
  r.zone:SetSize(ZONE_W, 18)
  r.zone:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.text = T.readable(T.text(r, T.FONT.small, C.text))
  r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  -- a click on the line ticks it too; hover shows the whole line (a long reason is cut short in the row)
  Widgets.script(r, "OnMouseUp", function()
    local e = rawget(r, "tcEntry")
    if e and e.kind == "quest" and e.can then QuestWindow.toggle(e.q.id) end
  end, FEATURE)
  Widgets.addTip(r, function(self)
    local e = rawget(self, "tcEntry")
    if not e or e.kind == "head" then return nil end
    return plain(e.text)
  end, nil, FEATURE)
  if r.EnableMouseWheel then r:EnableMouseWheel(true) end
  Widgets.script(r, "OnMouseWheel", function(_, delta) QuestWindow.scroll(delta) end, FEATURE)
  return r
end

local function build()
  frame = T.frame("Frame", "TwizCrewQuests", UIParent)
  frame:SetSize(WIDTH, TOP + VISIBLE * ROW_H + 62)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  Widgets.script(frame, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  Widgets.script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end, FEATURE)
  T.skin(frame, "window", { alpha = 0.97 }) -- the look's frame (UI/Skin.lua)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewQuests") end -- Escape closes it
  Widgets.script(frame, "OnHide", function() isOpen = false end, FEATURE)
  -- my zone ("you are here", the order, Only this zone) and my group (the line by the button) change while it is open
  for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    ns.Events.on(FEATURE, event, function() QuestWindow.refresh() end)
  end
  if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
  Widgets.script(frame, "OnMouseWheel", function(_, delta) QuestWindow.scroll(delta) end, FEATURE)

  title = T.readable(T.text(frame, T.FONT.normal, C.title), 3)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  local close = Widgets.button(frame, "Close", function() QuestWindow.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -10)

  onlyBox = checkBox(frame)
  onlyBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -34)
  Widgets.script(onlyBox, "OnClick", function() QuestWindow.setOnlyHere(not onlyHere) end, FEATURE)
  Widgets.helpTip(onlyBox, "questOnlyZone", FEATURE)
  onlyLabel = T.text(frame, T.FONT.small, C.text)
  onlyLabel:SetPoint("LEFT", onlyBox, "RIGHT", 4, 0)
  onlyLabel:SetText("Only this zone")

  rows = {}
  for i = 1, VISIBLE do rows[i] = newRow(i) end
  hintText = T.text(frame, T.FONT.small, C.muted)
  hintText:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + VISIBLE * ROW_H + 2))

  askButton = Widgets.button(frame, "Ask for quests", function() QuestWindow.press() end, nil, FEATURE)
  askButton:SetSize(BUTTON_W, 22)
  askButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)
  statusText = T.text(frame, T.FONT.small, C.muted)
  statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 10)
  statusText:SetPoint("RIGHT", askButton, "LEFT", -8, 0)
  statusText:SetJustifyH("LEFT")
end

draw = function()
  if not frame or not friend then return end
  title:SetText(safe(friend) .. "'s quests")
  -- a tick on a quest I can no longer get (I took it, say) is dropped
  if ns.QuestList.known(friend) then
    local can = {}
    for _, q in ipairs(ns.QuestList.all(friend)) do if q.can then can[q.id] = true end end
    for id in pairs(ticks) do if not can[id] then ticks[id] = nil end end
  end
  local headed = ns.QuestList.known(friend) and ns.QuestList.groups(friend).headed
  if headed then
    onlyBox:SetChecked(onlyHere)
    onlyBox:Show()
    onlyLabel:Show()
  else
    onlyBox:Hide()
    onlyLabel:Hide()
  end
  local list = QuestWindow.entries()
  local first, last = ns.PanelLogic.window(#list, offset, VISIBLE)
  offset = first - 1
  for i = 1, VISIBLE do
    local r, e = rows[i], list[first + i - 1]
    if e and first + i - 1 <= last then
      fillRow(r, e)
    else
      r.tcEntry = nil
      r:Hide()
    end
  end
  hintText:SetText(#list > VISIBLE and ("Scroll for more (" .. first .. "-" .. last .. " of " .. #list .. ")") or "")
  local label, enabled = QuestWindow.buttonState()
  askButton.text:SetText(label)
  askButton:SetEnabled(enabled)
  askButton:SetAlpha(enabled and 1 or 0.5)
  statusText:SetText(statusLine())
end

-------------------------------------------------------------------------------------------------------- actions
local function gettable(id)
  if not friend then return false end
  for _, q in ipairs(ns.QuestList.all(friend)) do
    if q.id == id then return q.can end
  end
  return false
end

local function full()
  if #tickedIds() < ns.QuestAsk.ASK_MAX then return false end
  print("TwizCrew: you can ask for up to " .. ns.QuestAsk.ASK_MAX .. " quests at once.")
  return true
end

-- Ticks or unticks one quest (only one I can get).
function QuestWindow.toggle(id)
  if not gettable(id) then draw(); return false end
  if ticks[id] then
    ticks[id] = nil
  elseif not full() then
    ticks[id] = true
  end
  draw()
  return true
end

-- "Tick this zone": ticks every quest I can get under that heading, or unticks them all when they all are.
function QuestWindow.tickZone(grp)
  if type(grp) ~= "table" or type(grp.quests) ~= "table" then return end
  local ids, all = {}, true
  for _, q in ipairs(grp.quests) do
    if q.can then
      ids[#ids + 1] = q.id
      if not ticks[q.id] then all = false end
    end
  end
  for _, id in ipairs(ids) do
    if all then ticks[id] = nil elseif not ticks[id] and not full() then ticks[id] = true end
  end
  draw()
end

function QuestWindow.setOnlyHere(on)
  onlyHere = on and true or false
  offset = 0
  draw()
end

-- The button: ask for the ticked quests, or stop the ask that is going on.
function QuestWindow.press()
  if not friend then return false end
  if ns.QuestAsk.active(friend) then
    ns.QuestAsk.cancel(friend)
    draw()
    return true
  end
  local ids = tickedIds()
  if #ids == 0 then return false end
  -- the ticks stay: a quest I take, or one that is refused for good, drops out by itself; the rest can be asked again
  local ok = ns.QuestAsk.ask(friend, ids)
  draw()
  return ok
end

-- Mouse wheel: delta 1 = up, -1 = down.
function QuestWindow.scroll(delta)
  offset = offset - (tonumber(delta) or 0)
  draw()
end

-- Opens the window on `name`'s quests (built now if this is the first time).
function QuestWindow.open(name)
  if type(name) ~= "string" or name == "" then return false end
  if friend ~= name then ticks, offset, friend = {}, 0, name end
  if not frame then build() end
  isOpen = true
  draw()
  frame:Show()
  if frame.Raise then frame:Raise() end
  return true
end

function QuestWindow.close()
  isOpen = false
  if frame then frame:Hide() end
end

function QuestWindow.isShown() return isOpen end

-- Something changed (their list came, my ask moved on, I took a quest): redraw when open (on `name`, when given).
function QuestWindow.refresh(name)
  if isOpen and (name == nil or name == friend) then draw() end
end

-- Test hooks: every line as a short text ("# heading [Tick this zone]", "[x] ticked", "[ ] not ticked", "- greyed",
-- a note as it is); the visible row frames; the button; the status line; the "Only this zone" box.
function QuestWindow.linesForTest()
  local out = {}
  for i, e in ipairs(QuestWindow.entries()) do
    local text = plain(e.text)
    if e.kind == "head" then out[i] = "# " .. text .. (e.tick and (" [" .. e.tick .. "]") or "")
    elseif e.kind == "quest" then out[i] = (e.can and (e.ticked and "[x] " or "[ ] ") or "- ") .. text
    else out[i] = text end
  end
  return out
end
function QuestWindow.rowForTest(i) return rows and rows[i] end
function QuestWindow.buttonForTest()
  if not askButton then return nil end
  return askButton.text:GetText(), askButton:IsEnabled()
end
function QuestWindow.statusForTest() return statusText and plain(statusText:GetText()) end
function QuestWindow.onlyBoxForTest() return onlyBox end
function QuestWindow.hintForTest() return hintText and hintText:GetText() end
function QuestWindow.friendForTest() return friend end
