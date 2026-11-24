-- Colors and fonts from the mockups, plus small drawing helpers (plain textures; a backdrop when the frame has one).
local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.COLOR = {
  backdrop = "0d0d12", border = "6b5a33", title = "ffd100", muted = "9a8f70", text = "f0e6c8", xp = "8a3fd1",
  row = "15151b", rowBorder = "444444", zone = "b8ad8c", status = "dddddd", xpBack = "222222",
  -- XP bar: gold that brightens as it fills (the bar's tip goes from xpLow at 0% to xpHigh at 100%)
  xpDark = "4a2c05", xpLow = "9a6212", xpHigh = "ffe680", xpBackTop = "1c1c1c",
  switchOn = "2a5a2a", knobOn = "ccffcc", switchOff = "3a3a3a", knobOff = "999999", button = "2a2a30",
  buttonBorder = "666666", pillBorder = "000000", white = "ffffff",
  danger = "5a1010", dangerBorder = "aa3333", line = "3a3322", confirm = "1a0d0d",
}

-- Our text is the game's own two fonts made a little bigger (easier to read; owner, 2026-11-08). TEXT_GROW points
-- are added to each; when the game can't make a font, the game's own is used as it is.
Theme.TEXT_GROW = 1.5
local function bigger(name, base)
  local ok, made = pcall(function()
    local from = _G[base]
    if type(CreateFont) ~= "function" or type(from) ~= "table" or not from.GetFont then return nil end
    local path, size, flags = from:GetFont()
    if type(path) ~= "string" or type(size) ~= "number" then return nil end
    local f = _G[name] or CreateFont(name)
    f:CopyFontObject(from)
    f:SetFont(path, size + Theme.TEXT_GROW, flags or "")
    return name
  end)
  return (ok and made) or base
end
Theme.FONT = { normal = bigger("TwizCrewFontNormal", "GameFontNormal"),
  small = bigger("TwizCrewFontSmall", "GameFontHighlightSmall") }

-- Icons are drawn ICON_SCALE times the size they were first made at: Theme.icon(16) = 19.
Theme.ICON_SCALE = 1.2
function Theme.icon(n) return math.floor(n * Theme.ICON_SCALE + 0.5) end

Theme.WHITE = "Interface\\Buttons\\WHITE8X8"

-- "ffd100" -> 1, 0.82, 0 (anything odd -> white)
function Theme.rgb(hex)
  if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return 1, 1, 1 end
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function Theme.color(tex, hex, alpha)
  local r, g, b = Theme.rgb(hex)
  if tex.SetColorTexture then
    tex:SetColorTexture(r, g, b, alpha or 1)
  else
    tex:SetTexture(Theme.WHITE)
    tex:SetVertexColor(r, g, b, alpha or 1)
  end
end

-- A two-color fade on a texture. orientation "HORIZONTAL" goes left (a) -> right (b), "VERTICAL" bottom (a) -> top
-- (b). Uses the modern SetGradient(ColorMixin) when there is one, the older forms otherwise, else plain color b.
function Theme.gradient(tex, orientation, hexA, hexB, alphaA, alphaB)
  local r1, g1, b1 = Theme.rgb(hexA)
  local r2, g2, b2 = Theme.rgb(hexB)
  alphaA, alphaB = alphaA or 1, alphaB or 1
  if tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) else tex:SetTexture(Theme.WHITE) end
  if type(CreateColor) == "function" and tex.SetGradient then
    local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(r1, g1, b1, alphaA), CreateColor(r2, g2, b2, alphaB))
    if ok then return end
  end
  if tex.SetGradientAlpha then
    local ok = pcall(tex.SetGradientAlpha, tex, orientation, r1, g1, b1, alphaA, r2, g2, b2, alphaB)
    if ok then return end
  end
  Theme.color(tex, hexB, alphaB)
end

-- The color part way (t = 0..1) from hex a to hex b, as hex.
function Theme.mix(a, b, t)
  local r1, g1, b1 = Theme.rgb(a)
  local r2, g2, b2 = Theme.rgb(b)
  t = math.max(0, math.min(1, t or 0))
  local function c(x, y) return math.floor((x + (y - x) * t) * 255 + 0.5) end
  return string.format("%02x%02x%02x", c(r1, r2), c(g1, g2), c(b1, b2))
end

-- A soft shine over the top half of a frame or texture (white fading to nothing toward the middle).
function Theme.gloss(frame, anchor, strength, layer)
  anchor = anchor or frame
  local t = frame:CreateTexture(nil, layer or "OVERLAY", nil, 7)
  t:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  t:SetPoint("BOTTOMRIGHT", anchor, "RIGHT", 0, 0)
  Theme.gradient(t, "VERTICAL", "ffffff", "ffffff", 0, strength or 0.18)
  return t
end

-- Text that stays readable on colored rows: the same font with a black outline and a drop shadow.
-- grow: points added to the size (0 = same size).
function Theme.readable(fs, grow)
  if fs.GetFont and fs.SetFont then
    local path, size = fs:GetFont()
    if type(path) == "string" and type(size) == "number" and size > 0 then
      pcall(fs.SetFont, fs, path, size + (grow or 0), "OUTLINE")
    end
  end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
  if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
  return fs
end

function Theme.textColor(fontString, hex)
  local r, g, b = Theme.rgb(hex)
  fontString:SetTextColor(r, g, b)
end

-- Class color as r, g, b (C_ClassColor, then RAID_CLASS_COLORS, then the normal text color).
function Theme.classColor(classFile)
  if type(classFile) == "string" then
    if C_ClassColor and C_ClassColor.GetClassColor then
      local ok, c = pcall(C_ClassColor.GetClassColor, classFile)
      if ok and type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    end
    local c = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile]
    if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
  end
  return Theme.rgb(Theme.COLOR.text)
end

-- A frame that can take a backdrop if this game version has BackdropTemplate.
function Theme.frame(kind, name, parent)
  return CreateFrame(kind or "Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end

-- Background and border. Uses SetBackdrop if the frame has it, otherwise five textures.
function Theme.paint(frame, bgHex, alpha, borderHex, edge)
  edge = edge or 1
  local p = { bg = bgHex, border = borderHex }
  frame.tcPaint = p
  if frame.SetBackdrop then
    p.backdrop = true
    frame:SetBackdrop({ bgFile = Theme.WHITE, edgeFile = Theme.WHITE, edgeSize = edge })
    local br, bg, bb = Theme.rgb(borderHex)
    frame:SetBackdropBorderColor(br, bg, bb, 1)
  else
    p.tex = frame:CreateTexture(nil, "BACKGROUND")
    p.tex:SetAllPoints(frame)
    local sides = {
      { "TOPLEFT", "TOPRIGHT", "height" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
      { "TOPLEFT", "BOTTOMLEFT", "width" }, { "TOPRIGHT", "BOTTOMRIGHT", "width" },
    }
    for _, s in ipairs(sides) do
      local t = frame:CreateTexture(nil, "BORDER")
      t:SetPoint(s[1], frame, s[1], 0, 0)
      t:SetPoint(s[2], frame, s[2], 0, 0)
      if s[3] == "height" then t:SetHeight(edge) else t:SetWidth(edge) end
      Theme.color(t, borderHex, 1)
    end
  end
  Theme.setBackgroundAlpha(frame, alpha)
end

function Theme.setBackgroundAlpha(frame, alpha)
  local skin = rawget(frame, "tcSkin")
  if skin then -- a skinned frame (UI/Skin.lua)
    skin.alpha = alpha
    if Theme.skinAlpha then Theme.skinAlpha(frame, skin) end
    return
  end
  local p = frame.tcPaint
  if not p then return end
  if p.backdrop then
    local r, g, b = Theme.rgb(p.bg)
    frame:SetBackdropColor(r, g, b, alpha or 1)
  elseif p.tex then
    Theme.color(p.tex, p.bg, alpha)
  end
end

function Theme.text(parent, font, hex, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", font or Theme.FONT.normal)
  if hex then Theme.textColor(fs, hex) end
  return fs
end

---------------------------------------------------------------------------------------------------------- the look
-- One look since 2026-11-23 (owner: "use Classic as the default and remove the other themes"): Classic, the game's
-- own dialog art. Its values are data in UI/Themes.lua; the drawing is in UI/Skin.lua. Our only picture file is the
-- icon atlas (UI/Icons.lua).
Theme.ART = "Interface\\AddOns\\TwizCrew\\Art\\"
Theme.CLASSIC = {} -- filled by UI/Themes.lua

-- Our art file (the icon atlas) is a TGA stored bottom row first. If the game shows it upside down, set FLIP_ART to
-- true: every texcoord on our own art goes through Theme.flipV, and nothing else needs to change.
Theme.FLIP_ART = false
function Theme.flipV(top, bottom)
  if Theme.FLIP_ART then return 1 - top, 1 - bottom end
  return top, bottom
end

-- SetTexture that never raises. Returns "loaded" (the game said true), "failed" (false, or an error) or "unknown"
-- (no answer: older clients return nothing, so no answer is not a failure).
function Theme.setTexture(tex, path, ...)
  if type(tex) ~= "table" or type(tex.SetTexture) ~= "function" then return "failed" end
  local ok, r = pcall(tex.SetTexture, tex, path, ...)
  if not ok or r == false then return "failed" end
  if r == true then return "loaded" end
  return "unknown"
end

-- Texcoords that never raise.
function Theme.setCoords(tex, l, r, t, b)
  if type(tex) == "table" and type(tex.SetTexCoord) == "function" then pcall(tex.SetTexCoord, tex, l, r, t, b) end
end

-- Does a file load? Asked once per path with a hidden texture; "loaded", "failed" or "unknown".
local probes = {}
local probeFrame
function Theme.probe(path)
  local known = probes[path]
  if known then return known end
  local result = "unknown"
  pcall(function()
    if type(CreateFrame) ~= "function" then return end
    probeFrame = probeFrame or CreateFrame("Frame", nil, UIParent)
    probeFrame:Hide()
    result = Theme.setTexture(probeFrame:CreateTexture(nil, "BACKGROUND"), path)
  end)
  probes[path] = result
  return result
end
function Theme.forgetProbesForTest() probes = {} end

-- The look (always Classic).
function Theme.active() return Theme.CLASSIC end

-- One line for /tc report: whether TwizCrew's icons loaded (else every place shows the game's icon it had before).
function Theme.reportLine()
  local state = "not built"
  if ns.Icons and ns.Icons.ATLAS then
    local p = Theme.probe(ns.Icons.ATLAS)
    state = p == "failed" and "missing (the game's icons are shown instead)"
      or p == "loaded" and "loaded" or "loaded (the game gave no answer)"
  end
  return "Look: Classic (the game's own art); TwizCrew icons " .. state
end

-- Text styles of the look (colour, outline, shadow, sometimes a size): Theme.ink(fontString, role). The role's values
-- come from the `ink` table in UI/Themes.lua; Theme.apply repaints every inked text.
local inked = setmetatable({}, { __mode = "k" })
Theme.inked = inked

function Theme.paintInk(fs)
  local t = Theme.active()
  local r = t and t.ink and t.ink[fs.tcRole]
  if not r then return end
  local base = fs.tcBaseFont
  if base and fs.SetFont then
    pcall(fs.SetFont, fs, base[1], r.size or (base[2] + (r.grow or 0)), r.flags or base[3])
  end
  if r.color and fs.SetTextColor then fs:SetTextColor(r.color[1], r.color[2], r.color[3], r.color[4] or 1) end
  if r.shadow then
    local s = r.shadow
    if fs.SetShadowColor then fs:SetShadowColor(s[1], s[2], s[3], s[4]) end
    if fs.SetShadowOffset then fs:SetShadowOffset(s[5] or 0, s[6] or 0) end
  end
end

function Theme.ink(fs, role)
  if type(fs) ~= "table" then return fs end
  fs.tcRole = role
  if rawget(fs, "tcBaseFont") == nil then
    local ok, path, size, flags = pcall(function() return fs:GetFont() end)
    fs.tcBaseFont = (ok and type(path) == "string" and type(size) == "number" and size > 0)
      and { path, size, flags or "" } or false
  end
  inked[fs] = true
  Theme.paintInk(fs)
  return fs
end
