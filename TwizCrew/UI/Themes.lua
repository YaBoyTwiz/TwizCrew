-- The three themes as data (owner's pick, 2026-11-23; values from docs/THEMES-SPEC.md). Every theme has the same keys
-- (a test checks it); `false` means "this theme has none". Colours are { r, g, b, a } (0-1). The drawing code is
-- UI/Skin.lua; what a theme may change: frames and backgrounds, the header, the tab bar and buttons, the tucked tab,
-- the crew emblem, the accent colour and the title and heading font. Layout, icons, class and tag colours, body
-- text, sounds and the see-through setting are the same in all three.
local _, ns = ...

local T = ns.Theme
local ART = T.ART
local DLG = "Interface\\DialogFrame\\"
local TABS = "Interface\\PaperDollInfoFrame\\"
local BTN = "Interface\\Buttons\\"
local MORPHEUS = T.MORPHEUS

local GOLD = { 1, 0.82, 0, 1 }
local SHADOW = { 0, 0, 0, 1, 1, -1 }  -- the game fonts' own drop shadow
local NO_SHADOW = { 0, 0, 0, 0, 0, 0 }

local function backdrop(bg, edge, size, inset)
  return { bgFile = DLG .. bg, edgeFile = DLG .. edge, tile = true, tileSize = 32, edgeSize = size,
    insets = { left = inset, right = inset, top = inset, bottom = inset } }
end

---------------------------------------------------------------------------------------------------------- shared parts
local CLASSIC_PANEL = { style = "backdrop", border = { 1, 1, 1, 1 },
  backdrop = backdrop("UI-DialogBox-Background", "UI-DialogBox-Border", 24, 6) }
local CLASSIC_GOLD = { style = "backdrop", border = { 1, 1, 1, 1 },
  backdrop = backdrop("UI-DialogBox-Background-Dark", "UI-DialogBox-Gold-Border", 32, 11) }
local CLASSIC_TAB = { style = "backdrop", border = { 1, 1, 1, 1 }, alpha = 0.85,
  backdrop = backdrop("UI-DialogBox-Background", "UI-DialogBox-Border", 16, 4) }

-- 9-slice cuts (texcoords) for a square margin: Crowned crew 36 texels of 256 x 512, Tavern night 13 of 128 x 256.
local CROWN_FILE = ART .. "CrownedCrew\\Frame.tga"
local CROWN_U, CROWN_V = { 0, 0.140625, 0.859375, 1 }, { 0, 0.0703125, 0.9296875, 1 }
local function crowned(alpha)
  return { style = "slice", file = CROWN_FILE, margin = 12, u = CROWN_U, v = CROWN_V, center = true, alpha = alpha }
end
local TAV_FILE = ART .. "TavernNight\\Frame.tga"
local OAK = ART .. "TavernNight\\Oak.tga"
local TAV_U, TAV_V = { 0, 0.1015625, 0.8984375, 1 }, { 0, 0.05078125, 0.94921875, 1 }
-- the oak inside the frame: 35% darker (50% while the kept-open panel is see-through: it goes muddy over bright
-- scenes otherwise)
local TAV_OAK = { file = OAK, tile = 256, inset = 10, shade = 0.65, fadedShade = 0.5 }
local TAVERN = { style = "slice", file = TAV_FILE, margin = 10, u = TAV_U, v = TAV_V, center = false, fill = TAV_OAK }
local PARCHMENT = { style = "flat", bg = { 0.96, 0.92, 0.81, 0.97 }, border = { 0.10, 0.05, 0.02, 1 }, edge = 1,
  alpha = 0.97 }

local GAME_TABS = { style = "game", normal = TABS .. "UI-Character-InActiveTab", active = TABS .. "UI-Character-ActiveTab",
  hover = TABS .. "UI-Character-Tab-Highlight", hoverAlpha = 0.4, cap = 10,
  coords = { { 0, 0.15625, 1, 0 }, { 0.15625, 0.84375, 1, 0 }, { 0.84375, 1, 1, 0 } } }
local GAME_BUTTON = { style = "game", up = BTN .. "UI-Panel-Button-Up", down = BTN .. "UI-Panel-Button-Down",
  hl = BTN .. "UI-Panel-Button-Highlight", cap = 12, congrats = { 0.45, 1, 0.45 },
  coords = { { 0, 0.09375, 0, 0.6875 }, { 0.09375, 0.53125, 0, 0.6875 }, { 0.53125, 0.625, 0, 0.6875 } } }

-- Text styles shared by Classic and Crowned crew (the game's own look).
local function goldInk(tuckLetters, tuckCount)
  return {
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
    tuckLetters = tuckLetters,
    tuckCount = tuckCount,
    cardTitle = { color = GOLD, flags = "OUTLINE", shadow = SHADOW },
    cardText = { color = { 1, 1, 1, 1 }, flags = "OUTLINE", shadow = SHADOW },
    cardLink = { color = GOLD, flags = "OUTLINE", shadow = SHADOW },
    cardMuted = { color = { 0.60, 0.56, 0.44, 1 }, flags = "OUTLINE", shadow = SHADOW },
    popTitle = { color = { 0.94, 0.90, 0.78, 1 }, shadow = SHADOW },
    popSub = { color = { 0.60, 0.56, 0.44, 1 }, shadow = SHADOW },
  }
end

---------------------------------------------------------------------------------------------------------- the themes
T.THEMES.classic = {
  id = "classic", name = "Classic", probe = false,
  accent = GOLD,
  frames = { panel = CLASSIC_PANEL, card = CLASSIC_GOLD, popup = CLASSIC_GOLD, window = CLASSIC_GOLD,
    menu = CLASSIC_PANEL, tab = CLASSIC_TAB },
  plate = { file = DLG .. "UI-DialogBox-Header" },
  band = false,
  emblem = false,
  tabs = GAME_TABS,
  button = GAME_BUTTON,
  keep = { style = "game" },
  divider = { style = "fade", color = { 0.54, 0.45, 0.25, 1 }, height = 1 },
  preview = { edgeSize = 12 },
  ink = goldInk({ color = GOLD, flags = "", shadow = SHADOW }, { color = { 1, 1, 1, 1 }, flags = "OUTLINE" }),
}

T.THEMES.crowned = {
  id = "crowned", name = "Crowned crew", probe = CROWN_FILE,
  accent = GOLD,
  frames = { panel = crowned(), card = crowned(0.97), popup = crowned(0.97), window = crowned(), menu = crowned(),
    tab = { style = "file", file = ART .. "CrownedCrew\\Banner.tga" } },
  plate = { file = DLG .. "UI-DialogBox-Header" },
  band = false,
  emblem = ART .. "CrownedCrew\\Crest.tga",
  tabs = GAME_TABS,
  button = GAME_BUTTON,
  keep = { style = "game" },
  divider = { style = "file", file = ART .. "CrownedCrew\\Divider.tga", height = 9, color = { 0.54, 0.45, 0.25, 1 } },
  preview = { margin = 6 },
  ink = goldInk({ color = { 1, 0.85, 0.42, 1 }, flags = "OUTLINE", shadow = SHADOW },
    { color = { 1, 1, 1, 1 }, flags = "OUTLINE" }),
}

local CREAM = { 0.96, 0.89, 0.69, 1 }
local BROWN = { 0.23, 0.14, 0.06, 1 }
local RED = { 0.48, 0.10, 0.04, 1 }
local AMBER = { 1, 0.82, 0.48, 1 }
T.THEMES.tavern = {
  id = "tavern", name = "Tavern night", probe = TAV_FILE,
  accent = AMBER,
  frames = { panel = TAVERN, card = PARCHMENT, popup = PARCHMENT, window = TAVERN, menu = TAVERN,
    tab = { style = "file", file = ART .. "TavernNight\\Sign.tga" } },
  plate = false,
  -- the header band: oak at 256, lighter, a dark 1 px border and a faint top highlight
  band = { file = OAK, tile = 256, shade = { 1, 0.90, 0.78, 1 }, border = { 0.10, 0.05, 0.02, 1 },
    shine = { 1, 0.86, 0.63, 0.3 } },
  emblem = ART .. "TavernNight\\Tankards.tga",
  tabs = { style = "flat", bg = { 0.80, 0.72, 0.55, 0.75 }, bgSel = { 0.95, 0.89, 0.75, 1 }, hoverAlpha = 0.25,
    shadow = { 0, 0, 0, 0.5 } },
  button = { style = "band", file = OAK, tile = 256, shade = { 1, 0.90, 0.78, 1 }, border = { 0.10, 0.05, 0.02, 1 },
    shine = { 1, 0.86, 0.63, 0.3 },
    mock = { bottom = { 0.42, 0.06, 0.03, 1 }, top = { 0.69, 0.16, 0.10, 1 }, border = { 0.16, 0.02, 0, 1 } },
    congrats = { bottom = { 0.10, 0.30, 0.14, 1 }, top = { 0.18, 0.48, 0.24, 1 }, border = { 0.02, 0.10, 0.04, 1 } } },
  keep = { style = "chalk", file = ART .. "TavernNight\\Chalk.tga", tile = 128, border = { 0.42, 0.26, 0.13, 1 },
    border2 = { 0.10, 0.05, 0.02, 1 } },
  divider = { style = "line", color = { 0.42, 0.26, 0.13, 1 }, height = 1 },
  preview = { margin = 5, tile = 64 },
  ink = {
    title = { font = MORPHEUS, size = 15, color = CREAM, shadow = { 0, 0, 0, 0.7, 0, -1 } },
    count = { color = { 0.95, 0.89, 0.74, 1 } },
    news = { color = { 1, 0.95, 0.84, 1 } },
    heading = { font = MORPHEUS, size = 12, color = AMBER, flags = "", upper = true },
    setHeading = { font = MORPHEUS, size = 12, color = AMBER, upper = true, shadow = SHADOW },
    tabText = { color = BROWN, shadow = NO_SHADOW },
    tabTextSel = { color = RED, shadow = NO_SHADOW },
    tabTextHot = { color = RED, shadow = NO_SHADOW },
    button = { color = CREAM, shadow = SHADOW },
    keep = { color = { 0.91, 0.90, 0.86, 1 } },
    keepOn = { color = { 1, 0.95, 0.60, 1 } },
    link = { color = AMBER },
    tuckLetters = { font = MORPHEUS, size = 11, color = CREAM, flags = "OUTLINE", shadow = SHADOW },
    tuckCount = { size = 14, color = { 1, 1, 1, 1 }, flags = "OUTLINE" },
    cardTitle = { font = MORPHEUS, size = 17, color = RED, flags = "", shadow = NO_SHADOW },
    cardText = { color = BROWN, flags = "", shadow = NO_SHADOW },
    cardLink = { color = RED, flags = "", shadow = NO_SHADOW },
    cardMuted = { color = { 0.38, 0.27, 0.14, 1 }, flags = "", shadow = NO_SHADOW },
    popTitle = { color = BROWN, shadow = NO_SHADOW },
    popSub = { color = { 0.38, 0.27, 0.14, 1 }, shadow = NO_SHADOW },
  },
}
