-- Find the crew: the big arrow (ns.BigArrow). Shows only when asked: a click on a friend's row arrow, a meet-up
-- (setting) or its pop-up. It points the way in the friend's class colour (the meet-up sender's for a meet-up), with
-- the name and the distance under it, and goes away by itself on arrival. It is our own frame: it never uses the
-- game's waypoint, so QuestMaster's arrow keeps its own target. Movable unless the Crew panel is locked.
local _, ns = ...

local BigArrow = {}
ns.BigArrow = BigArrow

local FEATURE = "find"
local T = ns.Theme
local C = T.COLOR
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow" -- the game's own player arrow, tinted per friend
local SIZE = 56
local ARRIVED_FOR = 1.5 -- seconds "You're here" stays before the arrow goes
local MEET_COLOR = "3fa9f5"

local frame, ticker
local target       -- { kind = "member", name } | { kind = "meet" } | nil
local arrivedAt
local view = { shown = false } -- what it shows now (tests)

local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function locked() return ns.Modules.setting("panel", "locked") == true end

local function classOf(name)
  local m = ns.roster and ns.roster:get(name)
  return m and m.class or nil
end

local function savePosition()
  if not frame or not frame.GetPoint then return end
  local ok, point, _, rel, x, y = pcall(frame.GetPoint, frame, 1)
  if ok and type(point) == "string" and type(x) == "number" and type(y) == "number" then
    ns.Modules.set(FEATURE, "arrowPos", { point = point, rel = type(rel) == "string" and rel or point,
      x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
  end
end

local function applyPosition()
  local p = setting("arrowPos")
  if type(p) ~= "table" or type(p.point) ~= "string" then p = { point = "TOP", x = 230, y = -150 } end
  frame:ClearAllPoints()
  frame:SetPoint(p.point, UIParent, type(p.rel) == "string" and p.rel or p.point, tonumber(p.x) or 0,
    tonumber(p.y) or 0)
end

function BigArrow.applyLook()
  if not frame then return end
  local s = tonumber(setting("arrowScale")) or 1
  if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
  frame:SetScale(s)
end

local function build()
  frame = T.frame("Frame", "TwizCrewBigArrow", UIParent)
  frame:SetSize(SIZE + 60, SIZE + 34)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  ns.Widgets.script(frame, "OnDragStart", function(self)
    if not locked() and self.StartMoving then self:StartMoving() end
  end, FEATURE)
  ns.Widgets.script(frame, "OnDragStop", function(self)
    if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    savePosition()
  end, FEATURE)
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetSize(SIZE, SIZE)
  frame.arrow:SetPoint("TOP", frame, "TOP", 0, 0)
  frame.arrow:SetTexture(ARROW_TEXTURE)
  frame.north = T.text(frame, T.FONT.small, C.title)
  frame.north:SetPoint("BOTTOM", frame.arrow, "TOP", 0, -6)
  frame.north:SetText("N")
  frame.label = T.readable(T.text(frame, T.FONT.normal, C.white), 1)
  frame.label:SetPoint("TOP", frame.arrow, "BOTTOM", 0, 2)
  frame.dist = T.readable(T.text(frame, T.FONT.small, C.white))
  frame.dist:SetPoint("TOP", frame.label, "BOTTOM", 0, -1)
  local close = CreateFrame("Button", nil, frame)
  close:SetSize(14, 14)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  local x = T.text(close, T.FONT.small, C.muted)
  x:SetPoint("CENTER", close, "CENTER", 0, 0)
  x:SetText("x")
  ns.Widgets.script(close, "OnClick", function() BigArrow.close() end, FEATURE)
  ns.Widgets.script(close, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Close the arrow")
    GameTooltip:Show()
  end, FEATURE)
  ns.Widgets.script(close, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end, FEATURE)
  frame.closeButton = close
  frame:Hide()
  BigArrow.applyLook()
end

local function stopTicker()
  if ticker then ticker:Cancel(); ticker = nil end
end

function BigArrow.close()
  target, arrivedAt = nil, nil
  stopTicker()
  if frame then frame:Hide() end
  view = { shown = false }
end

-- Closes it only when it points at that kind of target ("meet" or "member").
function BigArrow.closeIf(kind)
  if target and target.kind == kind then BigArrow.close() end
end

local function color(hex, classFile)
  if classFile then return T.classColor(classFile) end
  return T.rgb(hex)
end

local function show(label, distText, angle, compass, r, g, b)
  frame.label:SetText(label)
  frame.dist:SetText(distText or "")
  frame.arrow:SetVertexColor(r, g, b)
  if angle then
    frame.arrow:SetRotation(angle)
    frame.arrow:Show()
  else
    frame.arrow:Hide()
  end
  if compass and angle then frame.north:Show() else frame.north:Hide() end
  view = { shown = true, kind = target.kind, name = target.name, label = label, text = distText or "",
    angle = angle, compass = compass and angle ~= nil or false }
end

local function update()
  if not target then return BigArrow.close() end
  if not ns.Modules.isEnabled(FEATURE) then return BigArrow.close() end
  local now = ns.now()
  if arrivedAt then
    if now - arrivedAt >= ARRIVED_FOR then BigArrow.close() end
    return
  end
  local me, facing = ns.Where.me(), ns.Where.facing()
  local pos, label, classFile, hex, arrive, zone
  if target.kind == "meet" then
    local m = ns.Find.meet()
    if not m then return BigArrow.close() end
    pos, label, classFile, hex = m, "Meet " .. tostring(m.by), classOf(m.by), MEET_COLOR
    arrive = ns.Config.FIND_ARRIVE_MEET
    if m.place ~= "" and me and me.zone ~= m.place then zone = m.place end
  else
    if not ns.Where.isGroupMember(target.name) then return BigArrow.close() end -- left the group
    pos, label, classFile, hex = ns.Find.positionOf(target.name), target.name, classOf(target.name), C.white
    arrive = ns.Config.FIND_NEAR
    local m = ns.roster and ns.roster:get(target.name)
    if m and type(m.zone) == "string" and m.zone ~= "" and me and me.zone ~= m.zone then zone = m.zone end
  end
  local r, g, b = color(hex, classFile)
  local s = (pos and me) and ns.FindLogic.bigArrow(me, pos, facing, arrive) or nil
  if not s then
    show(label, "position unknown", nil, false, r, g, b)
    return
  end
  if s.arrived then
    arrivedAt = now
    show(label, "You're here", nil, false, r, g, b)
    return
  end
  show(label, (zone and (zone .. " \194\183 ") or "") .. s.text, s.angle, s.compass, r, g, b)
end

-- Points the big arrow at a group member ({ kind = "member", name }) or the meet-up ({ kind = "meet" }).
function BigArrow.point(t)
  if type(t) ~= "table" or (t.kind ~= "meet" and (t.kind ~= "member" or type(t.name) ~= "string")) then return end
  if not ns.Modules.isEnabled(FEATURE) then return end
  if not frame then build() end
  target, arrivedAt = { kind = t.kind, name = t.name }, nil
  applyPosition()
  BigArrow.applyLook()
  frame:Show()
  update()
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(ns.Config.FIND_ARROW_TICK, function() ns.Log.safe(FEATURE, update) end)
  end
end

-- Click on a row arrow: point at that friend, or close the arrow when it already points at them.
function BigArrow.toggle(name)
  if target and target.kind == "member" and target.name == name then BigArrow.close(); return end
  BigArrow.point({ kind = "member", name = name })
end

function BigArrow.stateForTest() return view end
function BigArrow.frameForTest() return frame end
