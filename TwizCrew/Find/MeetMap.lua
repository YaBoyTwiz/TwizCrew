-- Find the crew, the map side (ns.MeetMap): Ctrl + right-click a spot on the world map to send a meet-up (a small
-- menu asks: my party or everyone), and the meet-up's icon on the world map and the minimap.
-- Works on Blizzard's world map and on OpenMap's stitched map (through its public OpenMapAPI). Never uses the game's
-- waypoint: the icons are our own frames, so QuestMaster's and the game's waypoint stay as they are.
local _, ns = ...

local MeetMap = {}
ns.MeetMap = MeetMap

local FEATURE = "find"
local T = ns.Theme
local C = T.COLOR
local CLICK_PRIORITY = 2000 -- before OpenMap's own map clicks (1000); we only take Ctrl + right-click
local TICK = 0.2
local MEET_COLOR = "3fa9f5"

local hooked = false
local anchor           -- an invisible frame at the cursor, for the menu
local worldPin, miniPin
local ticker
local lastMenu         -- the last menu's items (tests)
local view = { world = false, minimap = false }

local function say(text) print("TwizCrew: " .. text) end
local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

local function openMap()
  local api = rawget(_G, "OpenMapAPI")
  if type(api) ~= "table" or type(api.IsStitched) ~= "function" then return nil end
  if not call(api.IsStitched) then return nil end
  return api
end

------------------------------------------------------------------------------------------------------- the click
-- The map point under the cursor: mapID, x, y (0..1 on that map), or nil.
local function pointUnderCursor(map, cx, cy)
  local api = openMap()
  if api then
    local u, v = call(api.CursorPosition)
    if type(u) ~= "number" or type(v) ~= "number" then return nil end
    local mapID = call(api.MapAt, u, v)
    if type(mapID) ~= "number" then return nil end
    local x, y = call(api.MapFromWorld, mapID, u, v)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return mapID, x, y
  end
  local mapID = map and call(map.GetMapID, map)
  if type(mapID) ~= "number" or type(cx) ~= "number" or type(cy) ~= "number" then return nil end
  if cx < 0 or cx > 1 or cy < 0 or cy > 1 then return nil end
  return mapID, cx, cy
end

local function cursorAnchor()
  if not anchor then
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(1, 1)
  end
  local x, y = call(GetCursorPosition)
  local scale = UIParent and call(UIParent.GetEffectiveScale, UIParent)
  if type(x) == "number" and type(y) == "number" and type(scale) == "number" and scale > 0 then
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
  end
  return anchor
end

local function place(mapID, x, y, audience)
  local ok, why = ns.Find.placeMeet(mapID, x, y, audience)
  if ok then
    say("meet-up sent to " .. (audience == "party" and "your party" or "everyone") .. ".")
  elseif why == "nogroup" then
    say("you're not in a party any more. Pick Everyone instead.")
  elseif why == "noplace" then
    say("pick a spot inside a zone for a meet-up.")
  end
end

-- Ctrl + right-click on the world map. Returns true when we took the click (the map then doesn't zoom out).
local function onMapClick(map, button, cx, cy)
  if button ~= "RightButton" or not call(IsControlKeyDown) then return false end
  if not ns.Modules.isEnabled(FEATURE) or not setting("meetups") then return false end
  local mapID, x, y = pointUnderCursor(map, cx, cy)
  if not mapID or ns.Where.toWorld(mapID, x, y) == nil then
    say("pick a spot inside a zone for a meet-up.")
    return true
  end
  local items = {}
  if ns.Where.inGroup() then
    items[#items + 1] = { label = "Meet here: my party", onClick = function()
      ns.Log.safe(FEATURE, place, mapID, x, y, "party")
    end }
  end
  items[#items + 1] = { label = "Meet here: everyone", onClick = function()
    ns.Log.safe(FEATURE, place, mapID, x, y, "all")
  end }
  items[#items + 1] = { label = "Cancel", onClick = function() end }
  lastMenu = items
  ns.Widgets.menu(cursorAnchor(), items)
  return true
end

local function hookMap()
  if hooked then return end
  local map = rawget(_G, "WorldMapFrame") or WorldMapFrame
  if type(map) ~= "table" or type(map.AddCanvasClickHandler) ~= "function" then return end
  hooked = true
  map:AddCanvasClickHandler(function(m, button, cx, cy)
    local ok, took = ns.Log.safe(FEATURE, onMapClick, m, button, cx, cy)
    return ok and took == true
  end, CLICK_PRIORITY)
end

------------------------------------------------------------------------------------------------------- the icons
local function classOf(name)
  local m = ns.roster and ns.roster:get(name)
  return m and m.class or nil
end

local function tooltip(owner)
  local m = ns.Find.meet()
  if not GameTooltip or not m then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText("Meet-up: " .. tostring(m.by), T.rgb(MEET_COLOR))
  local left = math.ceil(ns.FindLogic.meetLeft(m, ns.now()) / 60)
  GameTooltip:AddLine((m.audience == "party" and "For the party" or "For everyone") .. ", " .. left .. " min left",
    1, 1, 1)
  GameTooltip:AddLine("Click: point the way. Right-click: clear it for everyone.", 1, 1, 1, true)
  GameTooltip:Show()
end

local function onPinClick(_, button)
  if button == "RightButton" then
    if ns.Find.clearMeet() then say("meet-up cleared.") end
  else
    ns.Find.pointToMeet()
  end
end

local function newPin(parent, size)
  local pin = CreateFrame("Button", nil, parent)
  pin:SetSize(size, size)
  if pin.RegisterForClicks then pin:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  pin.ring = pin:CreateTexture(nil, "BACKGROUND")
  pin.ring:SetPoint("TOPLEFT", pin, "TOPLEFT", -3, 3)
  pin.ring:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 3, -3)
  pin.ring:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetAllPoints(pin)
  pin.icon:SetTexture(ns.Config.MINIMAP_ICON)
  pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ns.Widgets.script(pin, "OnClick", onPinClick, FEATURE)
  ns.Widgets.script(pin, "OnEnter", function(self) tooltip(self) end, FEATURE)
  ns.Widgets.script(pin, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end, FEATURE)
  pin:Hide()
  return pin
end

local function tint(pin, m)
  local by = classOf(m.by)
  local r, g, b
  if by then r, g, b = T.classColor(by) else r, g, b = T.rgb(MEET_COLOR) end
  pin.ring:SetVertexColor(r, g, b)
end

local function hideWorld()
  if worldPin then worldPin:Hide() end
  view.world, view.worldX, view.worldY = false, nil, nil
end

local function hideMini()
  if miniPin then miniPin:Hide() end
  view.minimap, view.miniX, view.miniY, view.edge = false, nil, nil, nil
end

local function placeWorld(m)
  local map = rawget(_G, "WorldMapFrame") or WorldMapFrame
  if type(map) ~= "table" or not call(map.IsVisible, map) then return hideWorld() end
  local canvas = call(map.GetCanvas, map)
  if type(canvas) ~= "table" then return hideWorld() end
  local x, y
  local api = openMap()
  if api then
    x, y = call(api.CanvasFromWorldPos, m.c, m.x, m.y)
  else
    x, y = ns.Where.toMap(call(map.GetMapID, map), m.c, m.x, m.y)
    if x and (x < 0 or x > 1 or y < 0 or y > 1) then x = nil end
  end
  if type(x) ~= "number" or type(y) ~= "number" then return hideWorld() end
  if not worldPin then worldPin = newPin(canvas, 22) end
  local w, h = call(canvas.GetWidth, canvas), call(canvas.GetHeight, canvas)
  if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return hideWorld() end
  local scale = call(map.GetCanvasScale, map)
  if type(scale) == "number" and scale > 0 then worldPin:SetScale(1 / scale) else scale = 1 end
  worldPin:ClearAllPoints()
  worldPin:SetPoint("CENTER", canvas, "TOPLEFT", x * w * scale, -y * h * scale)
  local level = api and call(api.ArtTopLevel)
  if type(level) == "number" then worldPin:SetFrameLevel(level + 20) end
  tint(worldPin, m)
  worldPin:Show()
  view.world, view.worldX, view.worldY = true, x, y
end

local function placeMini(m)
  local mm = rawget(_G, "Minimap") or Minimap
  if not setting("meetMinimap") or type(mm) ~= "table" then return hideMini() end
  local me = ns.Where.me()
  local dist, bearing = ns.FindLogic.vector(me, m)
  if not dist then return hideMini() end
  local rotate = call(GetCVar, "rotateMinimap") == "1"
  local zoom = call(mm.GetZoom, mm)
  local width = call(mm.GetWidth, mm)
  local shape = call(GetMinimapShape)
  local x, y, edge = ns.FindLogic.minimapOffset(dist, bearing, ns.Where.facing(), rotate, zoom,
    call(IsIndoors) and true or false, width, shape)
  if not miniPin then miniPin = newPin(mm, 14) end
  miniPin:ClearAllPoints()
  miniPin:SetPoint("CENTER", mm, "CENTER", x, y)
  miniPin:SetAlpha(edge and 0.75 or 1)
  tint(miniPin, m)
  miniPin:Show()
  view.minimap, view.miniX, view.miniY, view.edge = true, x, y, edge
end

local function refresh()
  local m = ns.Modules.isEnabled(FEATURE) and ns.Find.meet() or nil
  if not m then
    hideWorld(); hideMini()
    if ticker then ticker:Cancel(); ticker = nil end
    return
  end
  placeWorld(m)
  placeMini(m)
end

local function onChanged()
  refresh()
  if ns.Find.meet() and not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, refresh) end)
  end
end

function MeetMap.start()
  hookMap()
  ns.Bus.on(FEATURE, "FIND_CHANGED", onChanged)
  ns.Bus.on(FEATURE, "SETTING_CHANGED", function(id) if id == FEATURE then refresh() end end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() hookMap(); refresh() end)
  onChanged()
end

function MeetMap.stop()
  if ticker then ticker:Cancel(); ticker = nil end
  hideWorld(); hideMini()
end

function MeetMap.stateForTest() return view end
function MeetMap.menuForTest() return lastMenu end
function MeetMap.hookedForTest() return hooked end
function MeetMap.pinsForTest() return worldPin, miniPin end
