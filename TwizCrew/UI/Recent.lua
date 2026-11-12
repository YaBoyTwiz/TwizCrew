-- The Recent window: the activity feed as a list, newest first, with a class icon (or a picture of the kind of
-- event), how long ago, and the line. The mouse wheel scrolls. Opened by the missed counter on the minimized
-- panel's bar, /tc recent, the wrench menu and the settings. The frame is built the first time it is opened, and
-- not in combat (it then says so and does not open).
local _, ns = ...

local Recent = {}
ns.Recent = Recent

local FEATURE = "activity"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local I = "Interface\\Icons\\"

local WIDTH, ROW_H, VISIBLE, PAD, HEAD = 440, 24, 10, 12, 44
local KIND_ICON = {
  online = I .. "Ability_Warrior_BattleShout", offline = I .. "Ability_Stealth",
  died = I .. "INV_Misc_Bone_HumanSkull_01", levelup = I .. "Spell_Holy_PowerInfusion",
  congrats = I .. "INV_Misc_Gift_01", mock = I .. "INV_Misc_Bone_HumanSkull_01", roast = I .. "Spell_Fire_Fire",
}

local REFRESH = 30 -- seconds between redraws of the relative times
local frame, rows, emptyText, hint
local offset = 0
local ticker -- refreshes the "5m ago" times while the window is open
local isOpen = false -- our own flag (the frame's IsShown is also false while it is built but hidden)
local function stopTicker()
  if ticker then ticker:Cancel(); ticker = nil end
end

local shownLines = {} -- what the rows show now (test hook): { { line, ago, kind } }

local function inFight()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function plain(s)
  return (tostring(s or ""):gsub("||", "\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\1", "||"))
end

local function newRow(i)
  local r = CreateFrame("Frame", nil, frame)
  r:SetSize(WIDTH - 2 * PAD, ROW_H)
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEAD + (i - 1) * ROW_H))
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(T.icon(18), T.icon(18))
  r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.ago = T.text(r, T.FONT.small, C.muted)
  r.ago:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.ago:SetWidth(64)
  r.ago:SetJustifyH("RIGHT")
  r.text = T.readable(T.text(r, T.FONT.small, C.white))
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.text:SetPoint("RIGHT", r.ago, "LEFT", -6, 0)
  r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  -- hover: the exact clock time and the whole line
  r:EnableMouse(true)
  Widgets.script(r, "OnEnter", function(self)
    local e = rawget(self, "tcEntry")
    if not GameTooltip or not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(plain(ns.Feed.coloredLine(e)), 1, 1, 1, 1, true)
    local clock = type(date) == "function" and select(2, pcall(date, "%H:%M:%S", e.at)) or nil
    if type(clock) == "string" then GameTooltip:AddLine(clock, 0.8, 0.8, 0.8) end
    GameTooltip:Show()
  end, FEATURE)
  Widgets.script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end, FEATURE)
  return r
end

local function build()
  frame = T.frame("Frame", "TwizCrewRecent", UIParent)
  frame:SetSize(WIDTH, HEAD + VISIBLE * ROW_H + 30)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  Widgets.script(frame, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  Widgets.script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end, FEATURE)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewRecent") end -- Escape closes it
  Widgets.script(frame, "OnHide", function() isOpen = false; stopTicker() end, FEATURE)
  if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
  Widgets.script(frame, "OnMouseWheel", function(_, delta) Recent.scroll(delta) end, FEATURE)
  local title = T.readable(T.text(frame, T.FONT.normal, C.title), 3)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("Recent activity")
  local close = Widgets.button(frame, "Close", function() Recent.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -10)
  rows = {}
  for i = 1, VISIBLE do rows[i] = newRow(i) end
  emptyText = T.text(frame, T.FONT.small, C.muted)
  emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -HEAD - 6)
  emptyText:SetText("Nothing yet. Friends coming online, deaths, level-ups, congrats and mocks show up here.")
  hint = T.text(frame, T.FONT.small, C.muted)
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 8)
end

local function draw()
  if not frame then return end
  local list = ns.Feed and ns.Feed.entries() or {}
  local first, last = ns.PanelLogic.window(#list, offset, VISIBLE)
  offset = first - 1
  local wall = ns.wallclock()
  shownLines = {}
  for i = 1, VISIBLE do
    local r, e = rows[i], list[first + i - 1]
    if e and first + i - 1 <= last then
      r.tcEntry = e
      if ns.ClassIcon.apply(r.icon, e.class) == "none" then
        r.icon:SetTexture(KIND_ICON[e.kind] or KIND_ICON.online)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.icon:Show()
      end
      local ago = ns.FeedLogic.ago(e.at, wall)
      r.ago:SetText(ago)
      r.text:SetText(ns.Feed.coloredLine(e))
      r:Show()
      shownLines[#shownLines + 1] = { line = plain(ns.Feed.coloredLine(e)), ago = ago, kind = e.kind }
    else
      r.tcEntry = nil
      r:Hide()
    end
  end
  if #list == 0 then emptyText:Show() else emptyText:Hide() end
  hint:SetText(#list > VISIBLE and ("Scroll for more (" .. first .. "-" .. last .. " of " .. #list .. ")")
    or (#list .. (#list == 1 and " event" or " events")))
end

-- Mouse wheel: delta 1 = up (newer), -1 = down (older).
function Recent.scroll(delta)
  offset = offset - (tonumber(delta) or 0)
  draw()
end

-- Opens the window (built now if this is the first time). Not in a fight: says so instead.
function Recent.open()
  if not frame then
    if inFight() then
      print("TwizCrew: the recent activity window opens after the fight (the game does not let addons make new windows now).")
      return false
    end
    build()
  end
  offset = 0
  draw()
  isOpen = true
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(REFRESH, function() ns.Log.safe(FEATURE, Recent.refresh) end)
  end
  frame:Show()
  ns.Bus.fire("RECENT_OPENED")
  return true
end

function Recent.close()
  isOpen = false
  stopTicker()
  if frame then frame:Hide() end
end

function Recent.toggle()
  if isOpen then Recent.close() return end
  Recent.open()
end

function Recent.isShown() return isOpen end

-- The feed changed: redraw if the window is open.
function Recent.refresh()
  if isOpen then draw() end
end

-- Test hooks.
function Recent.shownForTest() return shownLines end
function Recent.visibleRowsForTest() return VISIBLE end
