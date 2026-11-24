-- The look as data: Classic, the game's own dialog art (the one look since 2026-11-23; values from
-- docs/THEMES-SPEC.md). Colours are { r, g, b, a } (0-1). The drawing code is UI/Skin.lua.
local _, ns = ...

local T = ns.Theme
local DLG = "Interface\\DialogFrame\\"
local TABS = "Interface\\PaperDollInfoFrame\\"
local BTN = "Interface\\Buttons\\"

local GOLD = { 1, 0.82, 0, 1 }
local SHADOW = { 0, 0, 0, 1, 1, -1 }  -- the game fonts' own drop shadow

local function backdrop(bg, edge, size, inset)
  return { bgFile = DLG .. bg, edgeFile = DLG .. edge, tile = true, tileSize = 32, edgeSize = size,
    insets = { left = inset, right = inset, top = inset, bottom = inset } }
end

local PANEL = { backdrop = backdrop("UI-DialogBox-Background", "UI-DialogBox-Border", 24, 6) }
local GOLD_FRAME = { backdrop = backdrop("UI-DialogBox-Background-Dark", "UI-DialogBox-Gold-Border", 32, 11) }
-- The tucked tab is 24 wide and a pop-up 50 tall: smaller edges than the spec's 16 and 32, so the border pieces do
-- not overlap (the skin also never lets an edge be more than half a frame's smaller side).
local TAB = { alpha = 0.85, backdrop = backdrop("UI-DialogBox-Background", "UI-DialogBox-Border", 12, 3) }
local POPUP = { backdrop = backdrop("UI-DialogBox-Background-Dark", "UI-DialogBox-Gold-Border", 16, 5) }

local C = T.CLASSIC
-- each window kind's backdrop (border colour white: the file's own colours)
C.frames = { panel = PANEL, card = GOLD_FRAME, popup = POPUP, window = GOLD_FRAME, menu = PANEL, tab = TAB }
C.plate = { file = DLG .. "UI-DialogBox-Header" } -- the title plate behind the panel's and the cards' titles
C.tabs = { normal = TABS .. "UI-Character-InActiveTab", active = TABS .. "UI-Character-ActiveTab",
  hover = TABS .. "UI-Character-Tab-Highlight", hoverAlpha = 0.4, cap = 10,
  coords = { { 0, 0.15625, 1, 0 }, { 0.15625, 0.84375, 1, 0 }, { 0.84375, 1, 1, 0 } } }
C.button = { up = BTN .. "UI-Panel-Button-Up", down = BTN .. "UI-Panel-Button-Down",
  hl = BTN .. "UI-Panel-Button-Highlight", cap = 12, congrats = { 0.45, 1, 0.45 },
  coords = { { 0, 0.09375, 0, 0.6875 }, { 0.09375, 0.53125, 0, 0.6875 }, { 0.53125, 0.625, 0, 0.6875 } } }
C.divider = { 0.54, 0.45, 0.25, 1 } -- a heading's 1 px line, fading out to the right

-- Text styles (Theme.ink roles).
C.ink = {
  title = { color = GOLD, shadow = SHADOW },
  count = { color = { 0.81, 0.81, 0.81, 1 } },
  news = { color = { 1, 1, 1, 1 } },
  heading = { color = GOLD, flags = "OUTLINE" },
  setHeading = { color = GOLD, size = 12, shadow = SHADOW },
  tabText = { color = { 0.78, 0.70, 0.48, 1 }, shadow = SHADOW },
  tabTextSel = { color = GOLD, shadow = SHADOW },
  tabTextHot = { color = { 0.94, 0.90, 0.78, 1 }, shadow = SHADOW },
  button = { color = GOLD, shadow = SHADOW },
  keep = { color = GOLD },
  keepOn = { color = GOLD },
  link = { color = GOLD },
  tuckLetters = { color = GOLD, flags = "", shadow = SHADOW },
  tuckCount = { color = { 1, 1, 1, 1 }, flags = "OUTLINE" },
  cardTitle = { color = GOLD, flags = "OUTLINE", shadow = SHADOW },
  cardText = { color = { 1, 1, 1, 1 }, flags = "OUTLINE", shadow = SHADOW },
  cardLink = { color = GOLD, flags = "OUTLINE", shadow = SHADOW },
  cardMuted = { color = { 0.60, 0.56, 0.44, 1 }, flags = "OUTLINE", shadow = SHADOW },
  popTitle = { color = { 0.94, 0.90, 0.78, 1 }, shadow = SHADOW },
  popSub = { color = { 0.60, 0.56, 0.44, 1 }, shadow = SHADOW },
}
