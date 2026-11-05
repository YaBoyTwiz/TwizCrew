-- Colors and fonts from the mockups, plus small drawing helpers (plain textures; a backdrop when the frame has one).
local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.COLOR = {
  backdrop = "0d0d12", border = "6b5a33", title = "ffd100", muted = "9a8f70", text = "f0e6c8", xp = "8a3fd1",
  row = "15151b", rowBorder = "444444", zone = "b8ad8c", status = "dddddd", xpBack = "222222",
  switchOn = "2a5a2a", knobOn = "ccffcc", switchOff = "3a3a3a", knobOff = "999999", button = "2a2a30",
  buttonBorder = "666666", pillBorder = "000000", white = "ffffff",
  danger = "5a1010", dangerBorder = "aa3333", line = "3a3322", confirm = "1a0d0d",
}

Theme.FONT = { normal = "GameFontNormal", small = "GameFontHighlightSmall" }

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
