-- Draws the themes (data: UI/Themes.lua). Every themed thing registers a painter once (Theme.track); a theme change
-- (Theme.apply, from the panel setting `theme`) runs every painter again and repaints every inked text, so the new
-- look shows at once, without a /reload. Nothing here runs per frame; every texture call is guarded, and a file the
-- game cannot load never raises an error.
--   Theme.skin(frame, kind, opts)    a window's frame and background; kind = panel | card | popup | window | menu |
--                                    tab (the tucked tab); opts = { alpha, plate = "panel" | "card", band = true,
--                                    emblem = "panel" | "card", margin, edgeSize, tile } (the last three: previews)
--   Theme.skinButton(b, variant)     Widgets.button and the row buttons (variant "mock" | "congrats")
--   Theme.skinTab(b, fixedRole)      a tab on a tab bar (b.label, b:SetActive(on), b.tcHot)
--   Theme.skinKeep(bar)              the panel's Keep open switch
--   Theme.divider(tex)               a heading's divider (the caller places it; the theme sets its look)
--   Theme.emblemFile()               the crew emblem of the drawn theme, or nil
local _, ns = ...

local T = ns.Theme
local FEATURE = "theme"

local tracked = setmetatable({}, { __mode = "k" }) -- object -> painter(object, theme)

local function themeOf(obj) return T.active(rawget(obj, "tcThemeId")) end
T.themeOf = themeOf

-- Registers a painter and runs it now.
function T.track(obj, painter)
  tracked[obj] = painter
  ns.Log.safe(FEATURE, painter, obj, themeOf(obj))
  return obj
end

-- Repaints everything in the drawn theme (after the setting changed, or the art turned out missing).
function T.apply()
  local list = {}
  for obj, painter in pairs(tracked) do list[#list + 1] = { obj, painter } end
  for _, e in ipairs(list) do ns.Log.safe(FEATURE, e[2], e[1], themeOf(e[1])) end
  local texts = {}
  for fs in pairs(T.inked) do texts[#texts + 1] = fs end
  for _, fs in ipairs(texts) do ns.Log.safe(FEATURE, T.paintInk, fs) end
  if ns.Bus then ns.Bus.fire("THEME_CHANGED", T.chosen(), T.drawnId()) end
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

-- A named texture kept on a skin record (made once, reused by every theme).
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

-- A file drawn with texcoords; our own art goes through the one vertical flip (Theme.flipV).
local function art(tex, file, l, r, t, b, own)
  local loaded = T.setTexture(tex, file)
  if own then t, b = T.flipV(t, b) end
  T.setCoords(tex, l, r, t, b)
  return loaded
end

-- A tiled file: texcoords 0..w/tile, 0..h/tile with the REPEAT wrap mode. color: what the part shows instead when the
-- file did not load (each file is asked once), so a missing picture never leaves a blank or odd-coloured part.
local function tiled(tex, file, w, h, tile, color)
  if color and T.probe(file) == "failed" then
    solid(tex, color)
    T.setCoords(tex, 0, 1, 0, 1)
    return "failed"
  end
  local loaded = T.setTexture(tex, file, "REPEAT", "REPEAT")
  local r = math.max(0.01, (tonumber(w) or tile) / tile)
  local t, b = T.flipV(0, math.max(0.01, (tonumber(h) or tile) / tile))
  T.setCoords(tex, 0, r, t, b)
  return loaded
end

-- Four 1-px (edge-px) lines around a frame.
local function edges(owner, rec, prefix, c, edge, layer, sub, inset)
  edge, inset = edge or 1, inset or 0
  local sides = {
    { "TOPLEFT", "TOPRIGHT", "h", inset, -inset, -inset, -inset },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "h", inset, inset, -inset, inset },
    { "TOPLEFT", "BOTTOMLEFT", "w", inset, -inset, inset, inset },
    { "TOPRIGHT", "BOTTOMRIGHT", "w", -inset, -inset, -inset, inset },
  }
  for i, s in ipairs(sides) do
    local tex = part(owner, rec, prefix .. i, layer or "BORDER", sub or -8)
    tex:SetPoint(s[1], owner, s[1], s[4], s[5])
    tex:SetPoint(s[2], owner, s[2], s[6], s[7])
    if s[3] == "h" then tex:SetHeight(edge) else tex:SetWidth(edge) end
    solid(tex, c)
  end
end

---------------------------------------------------------------------------------------------------------- 9-slice
-- The texcoord cuts for a square margin of m texels in a w x h file: u = { 0, m/w, 1 - m/w, 1 }, v likewise.
function T.sliceCuts(w, h, m)
  return { 0, m / w, 1 - m / w, 1 }, { 0, m / h, 1 - m / h, 1 }
end

-- Piece (col, row), 0-2 each: texcoords l, r, t, b (t and b through the art flip).
function T.sliceCoords(u, v, col, row)
  local t, b = T.flipV(v[row + 1], v[row + 2])
  return u[col + 1], u[col + 2], t, b
end

-- Piece (col, row) drawn with a margin of d: its TOPLEFT goes to point1 (+x1, +y1) of the frame and its BOTTOMRIGHT to
-- point2 (+x2, +y2). Corners stay d x d, edges stretch one way, the centre both ways.
function T.slicePoints(col, row, d)
  local h1 = col == 2 and "RIGHT" or "LEFT"
  local x1 = col == 0 and 0 or (col == 1 and d or -d)
  local v1 = row == 2 and "BOTTOM" or "TOP"
  local y1 = row == 0 and 0 or (row == 1 and -d or d)
  local h2 = col == 0 and "LEFT" or "RIGHT"
  local x2 = col == 0 and d or (col == 1 and -d or 0)
  local v2 = row == 0 and "TOP" or "BOTTOM"
  local y2 = row == 0 and -d or (row == 1 and d or 0)
  return v1 .. h1, x1, y1, v2 .. h2, x2, y2
end

-- An edge (a backdrop's edge size, a 9-slice margin, a button's cap) is never more than half the frame's smaller side,
-- or the pieces would overlap (a frame whose size is not known yet keeps the edge as it is).
function T.clampEdge(edge, w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 0 or h <= 0 then return edge end
  return math.max(0, math.min(edge, math.floor(math.min(w, h) / 2)))
end

local function slice(frame, rec, spec, margin)
  local d = T.clampEdge(margin or spec.margin, frame:GetWidth(), frame:GetHeight())
  rec.edge = d
  local loaded
  for i = 1, 9 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local centre = col == 1 and row == 1
    local tex = part(frame, rec, "slice" .. i, centre and "BACKGROUND" or "BORDER", -8)
    local state = T.setTexture(tex, spec.file)
    if i == 1 then loaded = state end
    T.setCoords(tex, T.sliceCoords(spec.u, spec.v, col, row))
    local p1, x1, y1, p2, x2, y2 = T.slicePoints(col, row, d)
    tex:SetPoint("TOPLEFT", frame, p1, x1, y1)
    tex:SetPoint("BOTTOMRIGHT", frame, p2, x2, y2)
    if centre and not spec.center then tex:Hide() end
  end
  return loaded
end

---------------------------------------------------------------------------------------------------------- frames
local LEGACY = { bg = { T.rgb(T.COLOR.backdrop) }, border = { T.rgb(T.COLOR.border) }, edge = 2 } -- the old flat look
local PLATE = { panel = { w = 140, h = 35, x = 2, y = 10 }, card = { share = 0.62, h = 48, x = 6, y = 12 } }
-- the panel's crest hangs below the bottom edge: its top is 2 above the edge, inside the panel's bottom padding (every
-- layout leaves at least 2 under the last line), so it never covers a row, a bar or a note
local EMBLEM = { panel = 38, panelTop = 2, card = 104, cardAlpha = 0.16 }
-- How far the panel's skin reaches outside the frame (the title plate above, the crest below): the tucked panel's
-- clipping holder is this much taller (UI/PanelTab.lua), so nothing is cut off.
T.PANEL_OVERHANG = { top = PLATE.panel.y, bottom = EMBLEM.panel - EMBLEM.panelTop }
local BAND = { top = -3, height = 20, inset = 8 }

-- The background alpha of a skinned frame (the panel's Background darkness; cards and pop-ups fixed).
local function skinAlpha(frame, rec)
  local spec = rec.spec
  if not spec then return end
  local a = spec.alpha or rec.alpha or 1
  if rec.mode == "backdrop" then
    if frame.SetBackdropColor then pcall(frame.SetBackdropColor, frame, 1, 1, 1, a) end
  elseif rec.mode == "legacy" then
    if rec.parts.flatBg then solid(rec.parts.flatBg, LEGACY.bg, a) end
  elseif rec.mode == "flat" then
    if rec.parts.flatBg then solid(rec.parts.flatBg, spec.bg, a) end
  elseif rec.mode == "slice" and spec.center and rec.parts.slice5 then
    vertex(rec.parts.slice5, 1, 1, 1, a)
  end
  if spec.fill and rec.parts.fill then
    local s = (rec.faded and spec.fill.fadedShade) or spec.fill.shade or 1
    vertex(rec.parts.fill, s, s, s, a)
  end
end
T.skinAlpha = skinAlpha

local function flat(frame, rec, spec)
  local bg = part(frame, rec, "flatBg", "BACKGROUND", -8)
  bg:SetAllPoints(frame)
  solid(bg, spec.bg)
  edges(frame, rec, "flatEdge", spec.border, spec.edge or 1)
end

local function refit(frame)
  local rec = rawget(frame, "tcSkin")
  if not rec or not rec.spec then return end
  local w, h = frame:GetWidth(), frame:GetHeight()
  local fill = rec.spec.fill
  if fill and rec.parts.fill and rec.parts.fill:IsShown() then
    local inset = rec.opts.margin or fill.inset
    tiled(rec.parts.fill, fill.file, (w or 0) - 2 * inset, (h or 0) - 2 * inset, rec.opts.tile or fill.tile, fill.color)
  end
  local band = rec.parts.band
  if band and band:IsShown() and rec.band then
    tiled(band, rec.band.file, (w or 0) - 2 * BAND.inset, BAND.height, rec.band.tile, rec.band.color)
  end
  local plate = rec.parts.plate
  if plate and plate:IsShown() and rec.opts.plate == "card" then
    plate:SetWidth(math.max(40, math.floor((w or 0) * PLATE.card.share)))
  end
  -- a size change that changes the clamped edge: draw the frame again (paintFrame calls refit; no loop, it matches then)
  if rec.edge and (rec.mode == "backdrop" or rec.mode == "slice") and rec.wantEdge
    and T.clampEdge(rec.wantEdge, w, h) ~= rec.edge and T.paintFrame then
    T.paintFrame(frame, T.themeOf(frame))
  end
end
T.refit = refit

local function paintFrame(frame, t)
  local rec = frame.tcSkin
  local spec = t.frames[rec.kind] or t.frames.window
  if spec.style == "file" and T.probe(spec.file) == "failed" then spec = T.THEMES.classic.frames[rec.kind] end
  hideParts(rec)
  if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
  rec.spec, rec.mode, rec.band = spec, nil, nil
  local opts = rec.opts
  rec.edge, rec.wantEdge = nil, nil
  if spec.style == "backdrop" then
    local bd = spec.backdrop
    rec.wantEdge = opts.edgeSize or bd.edgeSize
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
      if frame.SetBackdropBorderColor then pcall(frame.SetBackdropBorderColor, frame, rgba(spec.border)) end
    else
      rec.mode = "legacy"
      flat(frame, rec, LEGACY)
    end
  elseif spec.style == "slice" then
    rec.mode = "slice"
    rec.wantEdge = opts.margin or spec.margin
    slice(frame, rec, spec, opts.margin)
  elseif spec.style == "flat" then
    rec.mode = "flat"
    flat(frame, rec, spec)
  elseif spec.style == "file" then
    rec.mode = "file"
    local tex = part(frame, rec, "file", "BACKGROUND", -8)
    tex:SetAllPoints(frame)
    art(tex, spec.file, 0, 1, 0, 1, true)
  end
  if spec.fill then
    local inset = opts.margin or spec.fill.inset
    local tex = part(frame, rec, "fill", "BACKGROUND", -7)
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  end
  -- the title plate behind the grip and title (Classic, Crowned crew)
  if opts.plate and t.plate then
    local g = PLATE[opts.plate] or PLATE.panel
    local tex = part(frame, rec, "plate", "ARTWORK", -8)
    art(tex, t.plate.file, 0, 1, 0, 1, false)
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", g.x, g.y)
    tex:SetSize(g.w or 140, g.h)
  end
  -- Tavern night's header band (drawn inside the frame; the header row itself does not move)
  if opts.band and t.band then
    rec.band = t.band
    local tex = part(frame, rec, "band", "ARTWORK", -8)
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", BAND.inset, BAND.top)
    tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BAND.inset, BAND.top)
    tex:SetHeight(BAND.height)
    vertex(tex, rgba(t.band.shade))
    for i, s in ipairs({ { "TOPLEFT", "TOPRIGHT", 0 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0 } }) do
      local line = part(frame, rec, "bandLine" .. i, "ARTWORK", -7)
      line:SetPoint(s[1], tex, s[1], 0, s[3])
      line:SetPoint(s[2], tex, s[2], 0, s[3])
      line:SetHeight(1)
      solid(line, t.band.border)
    end
    local shine = part(frame, rec, "bandShine", "ARTWORK", -6)
    shine:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, -1)
    shine:SetPoint("TOPRIGHT", tex, "TOPRIGHT", 0, -1)
    shine:SetHeight(1)
    solid(shine, t.band.shine)
  end
  -- the crew emblem: on the panel's bottom edge (above the rows, mouse-transparent), or a faint mark on a card
  local emblem = T.emblemFile(t)
  if opts.emblem == "panel" then
    local holder = rec.emblemFrame
    if not holder then
      holder = CreateFrame("Frame", nil, frame)
      holder:SetAllPoints(frame)
      if holder.EnableMouse then holder:EnableMouse(false) end
      rec.emblemFrame = holder
    end
    holder:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    if emblem then
      local tex = part(holder, rec, "emblem", "OVERLAY", 0)
      art(tex, emblem, 0, 1, 0, 1, true)
      tex:SetSize(EMBLEM.panel, EMBLEM.panel)
      tex:SetPoint("TOP", frame, "BOTTOM", 0, EMBLEM.panelTop)
    end
  elseif opts.emblem == "card" and emblem then
    local tex = part(frame, rec, "emblem", "BORDER", 7)
    art(tex, emblem, 0, 1, 0, 1, true)
    tex:SetSize(EMBLEM.card, EMBLEM.card)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    tex:SetAlpha(EMBLEM.cardAlpha)
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

-- The kept-open panel is see-through (or solid again): Tavern night's oak goes darker while it is faded. Called when
-- the see-through target changes, never per frame.
function T.setFaded(frame, faded)
  local rec = frame and rawget(frame, "tcSkin")
  if not rec then return end
  faded = faded and true or false
  if rec.faded == faded then return end
  rec.faded = faded
  skinAlpha(frame, rec)
end

-- The drawn theme's crew emblem, or nil (Classic, or the file did not load).
function T.emblemFile(t)
  t = t or T.active()
  if not t or not t.emblem or T.probe(t.emblem) == "failed" then return nil end
  return t.emblem
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

local function paintButton(b, t)
  local rec = b.tcButton
  local spec = t.button
  hideParts(rec)
  if b.SetBackdrop then pcall(b.SetBackdrop, b, nil) end
  local hl = rawget(b, "hl")
  rec.style = spec.style
  if spec.style == "game" then
    local list = threePieces(b, rec, "piece", rec.down and spec.down or spec.up, spec.coords, spec.cap, "BACKGROUND", 0)
    if rec.variant == "congrats" then
      for _, tex in ipairs(list) do vertex(tex, spec.congrats[1], spec.congrats[2], spec.congrats[3], 1) end
    end
    local glow = threePieces(b, rec, "glow", spec.hl, spec.coords, spec.cap, "HIGHLIGHT", 0)
    for _, tex in ipairs(glow) do if tex.SetBlendMode then tex:SetBlendMode("ADD") end end
    if hl then hl:SetAlpha(0) end
  else
    local v = rec.variant and spec[rec.variant]
    local bg = part(b, rec, "bg", "BACKGROUND", 0)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    if v then
      fade(bg, "VERTICAL", v.bottom, v.top)
      edges(b, rec, "edge", v.border, 1, "BORDER", 0)
    else
      tiled(bg, spec.file, b:GetWidth(), b:GetHeight(), spec.tile, spec.color)
      vertex(bg, rgba(spec.shade))
      edges(b, rec, "edge", spec.border, 1, "BORDER", 0)
      local shine = part(b, rec, "shine", "BORDER", 1)
      shine:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
      shine:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
      shine:SetHeight(1)
      solid(shine, spec.shine)
    end
    if hl then hl:SetAlpha(1) end
  end
  local text = rawget(b, "text")
  if text and not rec.variant then T.ink(text, "button") end
end

local function pressButton(b, down)
  local rec = rawget(b, "tcButton")
  if not rec or rec.style ~= "game" then return end
  rec.down = down and true or false
  local file = rec.down and themeOf(b).button.down or themeOf(b).button.up
  for i = 1, 3 do if rec.parts["piece" .. i] then T.setTexture(rec.parts["piece" .. i], file) end end
end

function T.skinButton(b, variant)
  if type(b) ~= "table" then return b end
  b.tcButton = { parts = {}, variant = variant }
  if b.HookScript then
    -- a button sized after it was made (0 x 0 at first in the game): its caps and oak tiling follow the new size
    b:HookScript("OnSizeChanged", function(self) ns.Log.safe(FEATURE, paintButton, self, themeOf(self)) end)
    b:HookScript("OnMouseDown", function(self) ns.Log.safe(FEATURE, pressButton, self, true) end)
    b:HookScript("OnMouseUp", function(self) ns.Log.safe(FEATURE, pressButton, self, false) end)
    b:HookScript("OnHide", function(self) ns.Log.safe(FEATURE, pressButton, self, false) end)
  end
  return T.track(b, paintButton)
end

---------------------------------------------------------------------------------------------------------- tabs
local function paintTab(b, t)
  local rec = b.tcTab
  local spec = t.tabs
  hideParts(rec)
  local hl = rawget(b, "hl")
  if spec.style == "game" then
    threePieces(b, rec, "piece", rec.active and spec.active or spec.normal, spec.coords, spec.cap, "BACKGROUND", -8)
    if hl then
      T.setTexture(hl, spec.hover)
      T.setCoords(hl, 0, 1, 0, 1)
      vertex(hl, 1, 1, 1, 1)
      if hl.SetBlendMode then hl:SetBlendMode("ADD") end
      hl:SetAlpha(spec.hoverAlpha)
    end
  else
    local bg = part(b, rec, "bg", "BACKGROUND", -8)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
    solid(bg, rec.active and spec.bgSel or spec.bg)
    local shadow = part(b, rec, "shadow", "BACKGROUND", -7)
    shadow:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    shadow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    shadow:SetHeight(1)
    solid(shadow, spec.shadow)
    if hl then
      solid(hl, spec.bgSel, spec.hoverAlpha)
      if hl.SetBlendMode then hl:SetBlendMode("BLEND") end
      hl:SetAlpha(1)
    end
  end
  local role = rec.fixedRole or (rec.active and "tabTextSel") or (rawget(b, "tcHot") and "tabTextHot") or "tabText"
  if b.label then T.ink(b.label, role) end
  rec.drawn, rec.hot = t.id, rawget(b, "tcHot") and true or false
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
    if rec.active == on and rec.hot == hot and rec.drawn == T.drawnId(rawget(self, "tcThemeId")) then return end
    rec.active = on
    ns.Log.safe(FEATURE, paintTab, self, themeOf(self))
  end
  return T.track(b, paintTab)
end

---------------------------------------------------------------------------------------------------------- Keep open
-- The Keep open switch: the game button (lit while on) or Tavern night's chalk board. bar.tcOn: on or off.
local function paintKeep(bar, t)
  local rec = bar.tcKeep
  hideParts(rec)
  if bar.SetBackdrop then pcall(bar.SetBackdrop, bar, nil) end
  local on = rawget(bar, "tcOn") and true or false
  local spec = t.keep
  if spec.style == "chalk" then
    local bg = part(bar, rec, "chalk", "BACKGROUND", 0)
    bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -3, 3)
    tiled(bg, spec.file, bar:GetWidth(), bar:GetHeight(), spec.tile, spec.color)
    edges(bar, rec, "frameA", spec.border, 2, "BORDER", 0, 1)
    edges(bar, rec, "frameB", spec.border2, 1, "BORDER", 1, 0)
  else
    local b = t.button
    threePieces(bar, rec, "piece", b.up, b.coords, b.cap, "BACKGROUND", 0)
    if on then
      local lit = threePieces(bar, rec, "lit", b.hl, b.coords, b.cap, "BORDER", 0)
      for _, tex in ipairs(lit) do
        if tex.SetBlendMode then tex:SetBlendMode("ADD") end
        tex:SetAlpha(0.5)
      end
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
  if bar.tcOn == on and bar.tcKeepDrawn == T.drawnId() then return end
  bar.tcOn = on
  bar.tcKeepDrawn = T.drawnId()
  ns.Log.safe(FEATURE, paintKeep, bar, themeOf(bar))
end

---------------------------------------------------------------------------------------------------------- dividers
-- A heading's divider (the caller places it, left to right): Classic a 1 px line fading out, Crowned crew the gold
-- scroll, Tavern night a 1 px line.
local function paintDivider(tex, t)
  local d = t.divider
  if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
  vertex(tex, 1, 1, 1, 1)
  if d.style == "file" and T.probe(d.file) ~= "failed" then
    art(tex, d.file, 0, 1, 0, 1, true)
  elseif d.style == "fade" then
    T.setCoords(tex, 0, 1, 0, 1)
    fade(tex, "HORIZONTAL", d.color, { d.color[1], d.color[2], d.color[3], 0 })
  else
    T.setCoords(tex, 0, 1, 0, 1)
    solid(tex, d.color)
  end
  tex:SetHeight(d.style == "file" and T.probe(d.file) ~= "failed" and d.height or 1)
end

function T.divider(tex)
  if type(tex) ~= "table" then return tex end
  return T.track(tex, paintDivider)
end
