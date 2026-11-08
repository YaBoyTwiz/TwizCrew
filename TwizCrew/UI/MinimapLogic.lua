-- Pure minimap-button rules (no WoW frames): angle clean-up, where on the minimap's edge an angle is, the angle the
-- cursor points at while dragging, and the tooltip lines. Angles are degrees: 0 = right, counter-clockwise.
local _, ns = ...

local MinimapLogic = {}
ns.MinimapLogic = MinimapLogic

local EDGE = 5             -- the button's centre sits this far outside the minimap's rim
local FALLBACK_SIZE = 140  -- the normal minimap size, used when the game cannot tell

-- Which quarters of the minimap are round, for each answer GetMinimapShape() can give (minimap addons set it).
-- Quarters: tr = top-right, tl = top-left, bl = bottom-left, br = bottom-right. Unknown or missing = all round.
local SHAPES = {
  ROUND = { tr = true, tl = true, bl = true, br = true },
  SQUARE = {},
  ["CORNER-TOPLEFT"] = { tl = true },
  ["CORNER-TOPRIGHT"] = { tr = true },
  ["CORNER-BOTTOMLEFT"] = { bl = true },
  ["CORNER-BOTTOMRIGHT"] = { br = true },
  ["SIDE-LEFT"] = { tl = true, bl = true },
  ["SIDE-RIGHT"] = { tr = true, br = true },
  ["SIDE-TOP"] = { tl = true, tr = true },
  ["SIDE-BOTTOM"] = { bl = true, br = true },
  ["TRICORNER-TOPLEFT"] = { tl = true, tr = true, bl = true },
  ["TRICORNER-TOPRIGHT"] = { tl = true, tr = true, br = true },
  ["TRICORNER-BOTTOMLEFT"] = { tl = true, bl = true, br = true },
  ["TRICORNER-BOTTOMRIGHT"] = { tr = true, bl = true, br = true },
}

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Any number -> the same direction in [0, 360), to a tenth of a degree. Anything else -> nil.
function MinimapLogic.normalize(angle)
  if not finite(angle) then return nil end
  local a = math.floor((angle % 360) * 10 + 0.5) / 10
  if a >= 360 then a = a - 360 end
  return a
end

function MinimapLogic.angleOrDefault(angle)
  return MinimapLogic.normalize(angle) or ns.Config.MINIMAP_ANGLE
end

local function quarter(cos, sin)
  if sin >= 0 then return cos >= 0 and "tr" or "tl" end
  return cos >= 0 and "br" or "bl"
end

function MinimapLogic.isRound(shape, angle)
  local r = math.rad(MinimapLogic.angleOrDefault(angle))
  local quarters = SHAPES[shape] or SHAPES.ROUND
  return quarters[quarter(math.cos(r), math.sin(r))] == true
end

local function size(v)
  if finite(v) and v > 0 then return v end
  return FALLBACK_SIZE
end

-- Where the button's centre goes, from the minimap's centre: x, y. Round quarters put it on the circle, square
-- quarters on the square's edge (so it follows the corner).
function MinimapLogic.offset(angle, shape, width, height)
  local r = math.rad(MinimapLogic.angleOrDefault(angle))
  local cos, sin = math.cos(r), math.sin(r)
  local w, h = size(width) / 2 + EDGE, size(height) / 2 + EDGE
  local quarters = SHAPES[shape] or SHAPES.ROUND
  if quarters[quarter(cos, sin)] then return cos * w, sin * h end
  local stretch = 1 / math.max(math.abs(cos), math.abs(sin)) -- reach the edge of the square, not the circle
  return cos * stretch * w, sin * stretch * h
end

-- The angle from the minimap's centre to the cursor. GetCursorPosition() gives screen pixels; divided by the
-- minimap's effective scale they match Minimap:GetCenter(). Junk (or a minimap without a centre yet) -> nil.
function MinimapLogic.angleFromCursor(cursorX, cursorY, scale, centerX, centerY)
  if not (finite(cursorX) and finite(cursorY) and finite(scale) and finite(centerX) and finite(centerY)) then
    return nil
  end
  if scale <= 0 then return nil end
  return MinimapLogic.normalize(math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)))
end

-- Tooltip text, title first. withDrag: the minimap button (the addon compartment entry cannot be dragged).
-- info (optional) = { version = mine, update = { name, ver } or nil }. With an update the last line says so and
-- lines.attention is its index (shown in gold).
function MinimapLogic.tooltipLines(online, total, panelShown, withDrag, info)
  info = type(info) == "table" and info or {}
  local title = "TwizCrew"
  if type(info.version) == "string" and info.version ~= "" then
    title = title .. " v" .. ns.Util.safeText(info.version)
  end
  local lines = {
    title,
    "Left-click: open settings",
    withDrag and "Right-click: menu (crew panel, calendar, tools)"
      or ("Right-click: " .. (panelShown and "hide" or "show") .. " the Crew panel"),
  }
  if withDrag then lines[#lines + 1] = "Drag: move it around the minimap" end
  online, total = tonumber(online) or 0, tonumber(total) or 0
  if total > 0 then
    lines[#lines + 1] = "Crew online: " .. online .. " of " .. total
  else
    lines[#lines + 1] = "Crew online: none seen yet"
  end
  local update = ns.UpdateLogic.availableText(info.update, true)
  if update then
    lines[#lines + 1] = ns.Util.safeText(update)
    lines.attention = #lines
  end
  return lines
end
