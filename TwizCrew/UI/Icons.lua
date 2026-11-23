-- TwizCrew's own icons: one atlas (Art/Icons/Icons.tga, 512 x 512, 8 x 8 cells of 64, 55 used), the same in every
-- theme. The texcoords are used exactly as they are (each icon has its own margin and outline, and the cells are inset
-- half a texel): never the 0.08 / 0.92 trim of the game's icons. When the atlas does not load, every place falls back
-- to the picture it showed before (Icons.set's fallback), so there is never an empty square.
--   Icons.set(tex, name, fallback)  draws icon `name` (or the fallback texture path, trimmed like before); returns
--                                   "atlas", "game" or "none"
--   Icons.award(id), Icons.category(id), Icons.recent(kind), Icons.popup(kind), Icons.news(kind), Icons.tab(id),
--   Icons.page(id), Icons.card(id)  the icon name for one of the addon's real keys (nil: keep the game's icon)
local _, ns = ...

local Icons = {}
ns.Icons = Icons

local T = ns.Theme
Icons.ATLAS = T.ART .. "Icons\\Icons.tga"

-- name = { row, col, left, right, top, bottom } (docs/THEMES-SPEC.md section 5)
Icons.CELLS = {
  tab_crew          = { 0, 0, 0.000977, 0.124023, 0.000977, 0.124023 },
  tab_shame         = { 0, 1, 0.125977, 0.249023, 0.000977, 0.124023 },
  tab_activity      = { 0, 2, 0.250977, 0.374023, 0.000977, 0.124023 },
  tab_calendar      = { 0, 3, 0.375977, 0.499023, 0.000977, 0.124023 },
  mock              = { 0, 4, 0.500977, 0.624023, 0.000977, 0.124023 },
  congrats          = { 0, 5, 0.625977, 0.749023, 0.000977, 0.124023 },
  mock_back         = { 0, 6, 0.750977, 0.874023, 0.000977, 0.124023 },
  online            = { 0, 7, 0.875977, 0.999023, 0.000977, 0.124023 },
  offline           = { 1, 0, 0.000977, 0.124023, 0.125977, 0.249023 },
  died              = { 1, 1, 0.125977, 0.249023, 0.125977, 0.249023 },
  levelup           = { 1, 2, 0.250977, 0.374023, 0.125977, 0.249023 },
  crown_stolen      = { 1, 3, 0.375977, 0.499023, 0.125977, 0.249023 },
  new_member        = { 1, 4, 0.500977, 0.624023, 0.125977, 0.249023 },
  ran_off           = { 1, 5, 0.625977, 0.749023, 0.125977, 0.249023 },
  cat_move          = { 1, 6, 0.750977, 0.874023, 0.125977, 0.249023 },
  cat_loot          = { 1, 7, 0.875977, 0.999023, 0.125977, 0.249023 },
  cat_oops          = { 2, 0, 0.000977, 0.124023, 0.250977, 0.374023 },
  cat_lazy          = { 2, 1, 0.125977, 0.249023, 0.250977, 0.374023 },
  clown             = { 2, 2, 0.250977, 0.374023, 0.250977, 0.374023 },
  crown             = { 2, 3, 0.375977, 0.499023, 0.250977, 0.374023 },
  award_corpse      = { 2, 4, 0.500977, 0.624023, 0.250977, 0.374023 },
  award_gravity     = { 2, 5, 0.625977, 0.749023, 0.250977, 0.374023 },
  award_fishfood    = { 2, 6, 0.750977, 0.874023, 0.250977, 0.374023 },
  award_weakling    = { 2, 7, 0.875977, 0.999023, 0.250977, 0.374023 },
  award_again       = { 3, 0, 0.000977, 0.124023, 0.375977, 0.499023 },
  award_leeroy      = { 3, 1, 0.125977, 0.249023, 0.375977, 0.499023 },
  award_marathon    = { 3, 2, 0.250977, 0.374023, 0.375977, 0.499023 },
  award_couch       = { 3, 3, 0.375977, 0.499023, 0.375977, 0.499023 },
  award_neverwalks  = { 3, 4, 0.500977, 0.624023, 0.375977, 0.499023 },
  award_fish        = { 3, 5, 0.625977, 0.749023, 0.375977, 0.499023 },
  award_bunny       = { 3, 6, 0.750977, 0.874023, 0.375977, 0.499023 },
  award_tourist     = { 3, 7, 0.875977, 0.999023, 0.375977, 0.499023 },
  award_flyer       = { 4, 0, 0.000977, 0.124023, 0.500977, 0.624023 },
  award_moneypit    = { 4, 1, 0.125977, 0.249023, 0.500977, 0.624023 },
  award_broke       = { 4, 2, 0.250977, 0.374023, 0.500977, 0.624023 },
  award_trash       = { 4, 3, 0.375977, 0.499023, 0.500977, 0.624023 },
  award_ninja       = { 4, 4, 0.500977, 0.624023, 0.500977, 0.624023 },
  award_juice       = { 4, 5, 0.625977, 0.749023, 0.500977, 0.624023 },
  award_toofar      = { 4, 6, 0.750977, 0.874023, 0.500977, 0.624023 },
  award_wanderer    = { 4, 7, 0.875977, 0.999023, 0.500977, 0.624023 },
  award_quitter     = { 5, 0, 0.000977, 0.124023, 0.625977, 0.749023 },
  award_duel        = { 5, 1, 0.125977, 0.249023, 0.625977, 0.749023 },
  award_homesick    = { 5, 2, 0.250977, 0.374023, 0.625977, 0.749023 },
  award_chatter     = { 5, 3, 0.375977, 0.499023, 0.625977, 0.749023 },
  award_emotes      = { 5, 4, 0.500977, 0.624023, 0.625977, 0.749023 },
  award_furniture   = { 5, 5, 0.625977, 0.749023, 0.625977, 0.749023 },
  award_snail       = { 5, 6, 0.750977, 0.874023, 0.625977, 0.749023 },
  award_medic       = { 5, 7, 0.875977, 0.999023, 0.625977, 0.749023 },
  card_away         = { 6, 0, 0.000977, 0.124023, 0.750977, 0.874023 },
  trophy            = { 6, 1, 0.125977, 0.249023, 0.750977, 0.874023 },
  page_basic        = { 6, 2, 0.250977, 0.374023, 0.750977, 0.874023 },
  page_panel        = { 6, 3, 0.375977, 0.499023, 0.750977, 0.874023 },
  page_alerts       = { 6, 4, 0.500977, 0.624023, 0.750977, 0.874023 },
  page_find         = { 6, 5, 0.625977, 0.749023, 0.750977, 0.874023 },
  page_more         = { 6, 6, 0.750977, 0.874023, 0.750977, 0.874023 },
}
-- other names for the same cell
Icons.ALIASES = { cat_deaths = "died", award_pauper = "cat_loot", page_fun = "clown", roast = "mock",
  card_welcome = "online", card_recap = "tab_activity" }

---------------------------------------------------------------------------------------------------------- real keys
local CATEGORY = { deaths = "died", move = "cat_move", loot = "cat_loot", oops = "cat_oops", lazy = "cat_lazy" }
local RECENT = { online = "online", offline = "offline", died = "died", levelup = "levelup", congrats = "congrats",
  mock = "mock", roast = "mock" }
local POPUP = { death = "died", roast = "mock", levelup = "levelup", online = "online", runaway = "ran_off",
  crown = "crown_stolen", member = "new_member" }
local NEWS = { runaway = "ran_off", calnote = "tab_calendar", calreply = "tab_calendar", fight = "tab_activity" }
for k, v in pairs(RECENT) do NEWS[k] = v end
local TAB = { crew = "tab_crew", shame = "tab_shame", activity = "tab_activity", calendar = "tab_calendar" }
local PAGE = { basic = "page_basic", panel = "page_panel", alerts = "page_alerts", fun = "clown", find = "page_find",
  more = "page_more" }
local CARD = { away = "card_away", welcome = "online", recap = "tab_activity", awards = "trophy" }
Icons.MAPS = { category = CATEGORY, recent = RECENT, popup = POPUP, news = NEWS, tab = TAB, page = PAGE, card = CARD }

-- The cell of a name (aliases followed), or nil.
function Icons.cell(name)
  if type(name) ~= "string" then return nil end
  return Icons.CELLS[name] or Icons.CELLS[Icons.ALIASES[name] or ""]
end

function Icons.award(id)
  if id == "clown" then return "clown" end
  if type(id) ~= "string" then return nil end
  local name = "award_" .. id
  return Icons.cell(name) and name or nil
end
function Icons.category(id) return CATEGORY[id] end
function Icons.recent(kind) return RECENT[kind] end
function Icons.popup(kind) return POPUP[kind] end
function Icons.news(kind) return NEWS[kind] end
function Icons.tab(id) return TAB[id] end
function Icons.page(id) return PAGE[id] end
function Icons.card(id) return CARD[id] end

---------------------------------------------------------------------------------------------------------- drawing
-- Did the atlas load? (false only when the game said no; no answer counts as loaded)
function Icons.ok() return T.probe(Icons.ATLAS) ~= "failed" end

-- Draws icon `name` on tex. Without the atlas (or for an unknown name) draws `fallback` (a game texture path,
-- trimmed with 0.08 / 0.92 when it is a square game icon, as before), else hides tex. Returns "atlas", "game" or
-- "none".
function Icons.set(tex, name, fallback)
  if type(tex) ~= "table" then return "none" end
  local c = Icons.cell(name)
  if c and Icons.ok() and T.setTexture(tex, Icons.ATLAS) ~= "failed" then
    local top, bottom = T.flipV(c[5], c[6])
    T.setCoords(tex, c[3], c[4], top, bottom)
    if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
    tex:Show()
    return "atlas"
  end
  if type(fallback) == "string" and fallback ~= "" then
    T.setTexture(tex, fallback)
    if fallback:find("Interface\\Icons\\", 1, true) then T.setCoords(tex, 0.08, 0.92, 0.08, 0.92)
    else T.setCoords(tex, 0, 1, 0, 1) end
    tex:Show()
    return "game"
  end
  tex:Hide()
  return "none"
end
