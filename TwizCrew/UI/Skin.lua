-- Draws the look (Classic; data: UI/Themes.lua). Every skinned thing registers a painter once (Theme.track);
-- Theme.apply runs every painter again and repaints every inked text. Nothing here runs per frame; every texture call
-- is guarded, and a file the game cannot load never raises an error.
--   Theme.skin(frame, kind, opts)    a window's frame and background; kind = panel | card | popup | window | menu |
--                                    tab (the tucked tab); opts = { alpha, plate = "panel" | "card" }
--   Theme.skinButton(b, variant)     Widgets.button and the row buttons (variant "mock" | "congrats")
--   Theme.skinTab(b, fixedRole)      a tab on a tab bar (b.label, b:SetActive(on), b.tcHot)
--   Theme.skinKeep(bar)              the panel's Keep open switch
--   Theme.divider(tex)               a heading's divider (the caller places it; the look sets its colour)
local _, ns = ...

local T = ns.Theme
local FEATURE = "theme"

local tracked = setmetatable({}, { __mode = "k" }) -- object -> painter(object, look)

local function themeOf() return T.active() end
T.themeOf = themeOf

-- Registers a painter and runs it now.
function T.track(obj, painter)
  tracked[obj] = painter
  ns.Log.safe(FEATURE, painter, obj, themeOf(obj))
  return obj
end

-- Repaints everything.
function T.apply()
  local list = {}
  for obj, painter in pairs(tracked) do list[#list + 1] = { obj, painter } end
  for _, e in ipairs(list) do ns.Log.safe(FEATURE, e[2], e[1], themeOf(e[1])) end
  local texts = {}
  for fs in pairs(T.inked) do texts[#texts + 1] = fs end
  for _, fs in ipairs(texts) do ns.Log.safe(FEATURE, T.paintInk, fs) end
  if ns.Bus then ns.Bus.fire("THEME_CHANGED") end
end

function T.trackedCountForTest()
  local n = 0
  for _ in pairs(tracked) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------------------------------------- helpers
local function rgba(c, a) return c[1], c[2], c[3], a or c[4] or 1 end

local function solid(tex, c, a)
  if tex.SetColorTexture then
    tex:SetColorTexture(rgba(c, a))
  else
    T.setTexture(tex, T.WHITE)
    tex:SetVertexColor(rgba(c, a))
  end
end

-- A two-colour fade (bottom/left c1 -> top/right c2), the modern way when there is one, else plain c2.
local function fade(tex, orientation, c1, c2)
  T.gradient(tex, orientation, "ffffff", "ffffff", 1, 1)
  if type(CreateColor) == "function" and tex.SetGradient then
    local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(rgba(c1)), CreateColor(rgba(c2)))
    if ok then return end
  end
  if tex.SetGradientAlpha then
    local r1, g1, b1, a1 = rgba(c1)
    local r2, g2, b2, a2 = rgba(c2)
    if pcall(tex.SetGradientAlpha, tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then return end
  end
  solid(tex, c2)
end

local function vertex(tex, r, g, b, a)
  if tex.SetVertexColor then tex:SetVertexColor(r, g, b, a or 1) end
end

-- A named texture kept on a skin record (made once, reused by every repaint).
local function part(owner, rec, name, layer, sub)
  local tex = rec.parts[name]
  if not tex then
    tex = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    rec.parts[name] = tex
  end
  tex:ClearAllPoints()
  vertex(tex, 1, 1, 1, 1)
  if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
  if tex.SetAlpha then tex:SetAlpha(1) end
  tex:Show()
  return tex
end

local function hideParts(rec)
  for _, tex in pairs(rec.parts) do tex:Hide() end
end

-- Four 1-px (edge-px) lines around a frame.
local function edges(owner, rec, prefix, c, edge)
  edge = edge or 1
  local sides = {
    { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
    { "TOPLEFT", "BOTTOMLEFT", "w" }, { "TOPRIGHT", "BOTTOMRIGHT", "w" },
  }
  for i, s in ipairs(sides) do
    local tex = part(owner, rec, prefix .. i, "BORDER", -8)
    tex:SetPoint(s[1], owner, s[1], 0, 0)
    tex:SetPoint(s[2], owner, s[2], 0, 0)
    if s[3] == "h" then tex:SetHeight(edge) else tex:SetWidth(edge) end
    solid(tex, c)
  end
end

-- An edge (a backdrop's edge size, a button's cap) is never more than half the frame's smaller side, or the pieces
-- would overlap (a frame whose size is not known yet keeps the edge as it is).
function T.clampEdge(edge, w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 0 or h <= 0 then return edge end
  return math.max(0, math.min(edge, math.floor(math.min(w, h) / 2)))
end

---------------------------------------------------------------------------------------------------------- frames
local LEGACY = { bg = { T.rgb(T.COLOR.backdrop) }, border = { T.rgb(T.COLOR.border) }, edge = 2 } -- the old flat look
local PLATE = { panel = { w = 140, h = 35, x = 2, y = 10 }, card = { share = 0.62, h = 48, x = 6, y = 12 } }
-- How far the panel's skin reaches outside the frame (the title plate above; nothing below): the tucked panel's
-- clipping holder is this much taller (UI/PanelTab.lua), so nothing is cut off.
T.PANEL_OVERHANG = { top = PLATE.panel.y, bottom = 0 }

-- The background alpha of a skinned frame (the panel's Background darkness; cards and pop-ups fixed).
local function skinAlpha(frame, rec)
  local spec = rec.spec
  if not spec then return end
  local a = spec.alpha or rec.alpha or 1
  if rec.mode == "backdrop" then
    if frame.SetBackdropColor then pcall(frame.SetBackdropColor, frame, 1, 1, 1, a) end
  elseif rec.mode == "legacy" then
    if rec.parts.flatBg then solid(rec.parts.flatBg, LEGACY.bg, a) end
  end
end
T.skinAlpha = skinAlpha

-- The old flat look, for a game without backdrops.
local function flat(frame, rec)
  local bg = part(frame, rec, "flatBg", "BACKGROUND", -8)
  bg:SetAllPoints(frame)
  solid(bg, LEGACY.bg)
  edges(frame, rec, "flatEdge", LEGACY.border, LEGACY.edge)
end

local function refit(frame)
  local rec = rawget(frame, "tcSkin")
  if not rec or not rec.spec then return end
  local w, h = frame:GetWidth(), frame:GetHeight()
  local plate = rec.parts.plate
  if plate and plate:IsShown() and rec.opts.plate == "card" then
    plate:SetWidth(math.max(40, math.floor((w or 0) * PLATE.card.share)))
  end
  -- a size change that changes the clamped edge: draw the frame again (paintFrame calls refit; no loop, it matches then)
  if rec.edge and rec.mode == "backdrop" and rec.wantEdge
    and T.clampEdge(rec.wantEdge, w, h) ~= rec.edge and T.paintFrame then
    T.paintFrame(frame, T.themeOf(frame))
  end
end
T.refit = refit

local function paintFrame(frame, t)
  local rec = frame.tcSkin
  local spec = t.frames[rec.kind] or t.frames.window
  hideParts(rec)
  if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
  rec.spec, rec.mode = spec, nil
  local opts = rec.opts
  local bd = spec.backdrop
  rec.wantEdge = bd.edgeSize
  local edge = T.clampEdge(rec.wantEdge, frame:GetWidth(), frame:GetHeight())
  rec.edge = edge
  if edge ~= bd.edgeSize then
    local inset = math.floor(bd.insets.left * edge / bd.edgeSize + 0.5)
    bd = { bgFile = bd.bgFile, edgeFile = bd.edgeFile, tile = bd.tile, tileSize = bd.tileSize,
      edgeSize = edge, insets = { left = inset, right = inset, top = inset, bottom = inset } }
  end
  local ok = frame.SetBackdrop and pcall(frame.SetBackdrop, frame, bd)
  if ok then
    rec.mode = "backdrop"
    if frame.SetBackdropBorderColor then pcall(frame.SetBackdropBorderColor, frame, 1, 1, 1, 1) end
  else
    rec.mode = "legacy"
    flat(frame, rec)
  end
  -- the title plate behind the grip and title
  if opts.plate and t.plate then
    local g = PLATE[opts.plate] or PLATE.panel
    local tex = part(frame, rec, "plate", "ARTWORK", -8)
    T.setTexture(tex, t.plate.file)
    T.setCoords(tex, 0, 1, 0, 1)
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", g.x, g.y)
    tex:SetSize(g.w or 140, g.h)
  end
  refit(frame)
  skinAlpha(frame, rec)
end
T.paintFrame = paintFrame

function T.skin(frame, kind, opts)
  if type(frame) ~= "table" then return frame end
  opts = opts or {}
  local rec = rawget(frame, "tcSkin")
  if not rec then
    rec = { parts = {} }
    frame.tcSkin = rec
    if frame.HookScript then
      frame:HookScript("OnSizeChanged", function(self) ns.Log.safe(FEATURE, refit, self) end)
    end
  end
  rec.kind, rec.opts = kind or "window", opts
  rec.alpha = opts.alpha or rec.alpha or 1
  frame.tcPaint = nil
  return T.track(frame, paintFrame)
end

---------------------------------------------------------------------------------------------------------- buttons
-- Three pieces (left cap, stretched middle, right cap) of one file.
local function threePieces(owner, rec, prefix, file, coords, cap, layer, sub)
  cap = T.clampEdge(cap, owner:GetWidth(), owner:GetWidth()) -- (two caps never wider than the button)
  local list = {}
  for i = 1, 3 do
    local tex = part(owner, rec, prefix .. i, layer, sub)
    local c = coords[i]
    T.setTexture(tex, file)
    T.setCoords(tex, c[1], c[2], c[3], c[4])
    list[i] = tex
  end
  list[1]:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
  list[1]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
  list[1]:SetWidth(cap)
  list[3]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
  list[3]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
  list[3]:SetWidth(cap)
  list[2]:SetPoint("TOPLEFT", list[1], "TOPRIGHT", 0, 0)
  list[2]:SetPoint("BOTTOMRIGHT", list[3], "BOTTOMLEFT", 0, 0)
  return list
end

-- The game's red button; Congrats tinted green.
local function paintButton(b, t)
  local rec = b.tcButton
  local spec = t.button
  hideParts(rec)
  if b.SetBackdrop then pcall(b.SetBackdrop, b, nil) end
  local list = threePieces(b, rec, "piece", rec.down and spec.down or spec.up, spec.coords, spec.cap, "BACKGROUND", 0)
  if rec.variant == "congrats" then
    for _, tex in ipairs(list) do vertex(tex, spec.congrats[1], spec.congrats[2], spec.congrats[3], 1) end
  end
  local glow = threePieces(b, rec, "glow", spec.hl, spec.coords, spec.cap, "HIGHLIGHT", 0)
  for _, tex in ipairs(glow) do if tex.SetBlendMode then tex:SetBlendMode("ADD") end end
  local hl = rawget(b, "hl")
  if hl then hl:SetAlpha(0) end
  local text = rawget(b, "text")
  if text and not rec.variant then T.ink(text, "button") end
end

local function pressButton(b, down)
  local rec = rawget(b, "tcButton")
  if not rec then return end
  rec.down = down and true or false
  local file = rec.down and themeOf(b).button.down or themeOf(b).button.up
  for i = 1, 3 do if rec.parts["piece" .. i] then T.setTexture(rec.parts["piece" .. i], file) end end
end

function T.skinButton(b, variant)
  if type(b) ~= "table" then return b end
  b.tcButton = { parts = {}, variant = variant }
  if b.HookScript then
    -- a button sized after it was made (0 x 0 at first in the game): its caps follow the new size
    b:HookScript("OnSizeChanged", function(self) ns.Log.safe(FEATURE, paintButton, self, themeOf(self)) end)
    b:HookScript("OnMouseDown", function(self) ns.Log.safe(FEATURE, pressButton, self, true) end)
    b:HookScript("OnMouseUp", function(self) ns.Log.safe(FEATURE, pressButton, self, false) end)
    b:HookScript("OnHide", function(self) ns.Log.safe(FEATURE, pressButton, self, false) end)
  end
  return T.track(b, paintButton)
end

---------------------------------------------------------------------------------------------------------- tabs
-- The game's character tabs (selected or not), its highlight on hover.
local function paintTab(b, t)
  local rec = b.tcTab
  local spec = t.tabs
  hideParts(rec)
  threePieces(b, rec, "piece", rec.active and spec.active or spec.normal, spec.coords, spec.cap, "BACKGROUND", -8)
  local hl = rawget(b, "hl")
  if hl then
    T.setTexture(hl, spec.hover)
    T.setCoords(hl, 0, 1, 0, 1)
    vertex(hl, 1, 1, 1, 1)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    hl:SetAlpha(spec.hoverAlpha)
  end
  local role = rec.fixedRole or (rec.active and "tabTextSel") or (rawget(b, "tcHot") and "tabTextHot") or "tabText"
  if b.label then T.ink(b.label, role) end
  rec.hot = rawget(b, "tcHot") and true or false
end
T.paintTab = paintTab

-- A tab on a tab bar: b.label, b.hl (its HIGHLIGHT texture); b:SetActive(on) marks the selected one, b.tcHot = true
-- lights the label (the Calendar button while it has something new). fixedRole: a label colour that never changes
-- (the "?").
function T.skinTab(b, fixedRole)
  if type(b) ~= "table" then return b end
  b.tcTab = { parts = {}, active = false, fixedRole = fixedRole }
  if b.HookScript then -- (a new word changes the width: the caps follow)
    b:HookScript("OnSizeChanged", function(self) ns.Log.safe(FEATURE, paintTab, self, themeOf(self)) end)
  end
  b.SetActive = function(self, on)
    on = on and true or false
    local rec = self.tcTab
    local hot = rawget(self, "tcHot") and true or false
    if rec.active == on and rec.hot == hot then return end
    rec.active = on
    ns.Log.safe(FEATURE, paintTab, self, themeOf(self))
  end
  return T.track(b, paintTab)
end

---------------------------------------------------------------------------------------------------------- Keep open
-- The Keep open switch: the game button, lit while on. bar.tcOn: on or off.
local function paintKeep(bar, t)
  local rec = bar.tcKeep
  hideParts(rec)
  if bar.SetBackdrop then pcall(bar.SetBackdrop, bar, nil) end
  local on = rawget(bar, "tcOn") and true or false
  local b = t.button
  threePieces(bar, rec, "piece", b.up, b.coords, b.cap, "BACKGROUND", 0)
  if on then
    local lit = threePieces(bar, rec, "lit", b.hl, b.coords, b.cap, "BORDER", 0)
    for _, tex in ipairs(lit) do
      if tex.SetBlendMode then tex:SetBlendMode("ADD") end
      tex:SetAlpha(0.5)
    end
  end
  local glow = rawget(bar, "glow")
  if glow then glow:SetAlpha(0) end
  if bar.text then T.ink(bar.text, on and "keepOn" or "keep") end
  if bar.dot then bar.dot:SetAlpha(on and 1 or 0.35) end
end

function T.skinKeep(bar)
  if type(bar) ~= "table" then return bar end
  bar.tcKeep = { parts = {} }
  if bar.HookScript then
    bar:HookScript("OnSizeChanged", function(self) ns.Log.safe(FEATURE, paintKeep, self, themeOf(self)) end)
  end
  return T.track(bar, paintKeep)
end

function T.setKeep(bar, on)
  if type(bar) ~= "table" or not rawget(bar, "tcKeep") then return end
  on = on and true or false
  if bar.tcOn == on then return end
  bar.tcOn = on
  ns.Log.safe(FEATURE, paintKeep, bar, themeOf(bar))
end

---------------------------------------------------------------------------------------------------------- dividers
-- A heading's divider (the caller places it, left to right): a 1 px line fading out.
local function paintDivider(tex, t)
  local c = t.divider
  if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
  vertex(tex, 1, 1, 1, 1)
  T.setCoords(tex, 0, 1, 0, 1)
  fade(tex, "HORIZONTAL", c, { c[1], c[2], c[3], 0 })
  tex:SetHeight(1)
end

function T.divider(tex)
  if type(tex) ~= "table" then return tex end
  return T.track(tex, paintDivider)
end
