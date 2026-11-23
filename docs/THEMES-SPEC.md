# Themes and icons: build spec

Owner's choice (2026-11-23): three themes ship. These are **Classic** (game art only), **Crowned crew**, which is the
default, and **Tavern night**. A shared icon set comes with them.

Crowned crew falls back to Classic when its frame texture does not load: `tex:SetTexture(path)` returns false or nil.

Mock-ups: `looks.html` (L1 = Classic, A1 = Crowned crew, A2 = Tavern night, the Icons / Icons in use / Themes
sections). Art files: `TwizCrew/Art/`. All sizes below are UI units at Scale 100% unless they say "texels".

## 0. Files

| File | Size (texels) | Bytes | What |
|---|---|---|---|
| `Art/CrownedCrew/Frame.tga` | 256 x 512 | 524,332 | 9-slice frame (panel, cards, pop-ups, settings, tab-less windows) |
| `Art/CrownedCrew/Banner.tga` | 64 x 256 | 65,580 | tucked tab skin (24 x 86), both sides |
| `Art/CrownedCrew/Crest.tga` | 64 x 64 | 16,428 | crew emblem (panel edge, cards, minimap) |
| `Art/CrownedCrew/Divider.tga` | 256 x 32 | 32,812 | gold scroll divider (section headings, "Rarely needed") |
| `Art/TavernNight/Frame.tga` | 128 x 256 | 131,116 | 9-slice frame |
| `Art/TavernNight/Oak.tga` | 256 x 256 | 262,188 | background tile, seamless |
| `Art/TavernNight/Chalk.tga` | 128 x 128 | 65,580 | Keep open bar tile, seamless |
| `Art/TavernNight/Sign.tga` | 64 x 256 | 65,580 | tucked tab skin (24 x 86), both sides |
| `Art/TavernNight/Tankards.tga` | 64 x 64 | 16,428 | crew emblem |
| `Art/Icons/Icons.tga` | 512 x 512 | 1,048,620 | icon atlas, 8 x 8 cells of 64, 55 used |
| **Total** | | **2,228,664** | |

Format (all files):
- TGA image type 2, uncompressed (no RLE), 32 bits per pixel, 8 alpha bits.
- Bottom-left origin (descriptor 0x08). This is the TGA default, so every loader reads it the right way up.
- Straight (not premultiplied) alpha. The colour under transparent and near-transparent pixels is bled from their
  neighbours, so scaled edges get no dark fringe.
- Every side is a power of two. The largest is 512.
- The paths in code need the extension, e.g. `Interface\\AddOns\\TwizCrew\\Art\\CrownedCrew\\Frame.tga`.
- Classic needs no file.

Not verified in the game (check on first load):
- that WoW Forever loads these TGAs at all;
- that none shows upside down (if one does, the origin is the cause: tell Claude, who re-exports top-left);
- that `SetTexture` returns false for a missing file.

New files reach the game after a `/reload` (the `.toc` is unchanged).

## 1. Theme system

- **Setting:** `panel.theme` = `"crowned"` (default) | `"classic"` | `"tavern"`. It applies at once (no reload) and is
  saved per account like the other Panel settings.
- **A theme changes:** frame and border, panel background, header band, tab bar and button skin, the tucked tab
  skin, the crew emblem (panel edge, card watermark, minimap button), the accent colour, and the title and heading
  font.
- **The same in every theme:**
  - layout, sizes and order;
  - the icon set;
  - class colours, tag colours and tag icons;
  - body text (Friz Quadrata via `Theme.FONT`) and its sizes;
  - sounds;
  - the see-through (`idleAlpha`) and background (`bgAlpha`) settings.
- **Fallback:** if a theme's `Frame.tga` fails to load, draw Classic for that session and log one line
  (`theme art missing, using Classic`).
- **Frames that take the theme:**
  - the panel (`TwizCrewPanel`) and the tucked tab;
  - the pop-ups and cards (`AwayCard.newCard`, Welcome, Recap, Report);
  - the settings window, the Recent window, the calendar window, the About and Changelog windows;
  - the menu (`TwizCrewMenu`).
- **Simplest route:** one function `Theme.skin(frame, kind)` with kind = `panel | card | popup | tab | menu |
  window`. `Theme.paint` callers that draw a whole window move to it. Row boxes, pills and bars keep `Theme.paint`
  with the theme's colours.

### 9-slice

Draw nine textures from one file with `SetTexCoord`. Use `Texture:SetTextureSliceMargins` instead only if it exists
on Forever (check `tex.SetTextureSliceMargins`).

The corners keep their size, the edges stretch along one axis, and the centre stretches both ways.

| Theme | File | Margin (texels, all four sides) | Drawn margin (UI) | u cuts | v cuts |
|---|---|---|---|---|---|
| Crowned crew | `CrownedCrew/Frame.tga` 256x512 | 36 | 12 | 0, 0.140625, 0.859375, 1 | 0, 0.0703125, 0.9296875, 1 |
| Tavern night | `TavernNight/Frame.tga` 128x256 | 13 | 10 | 0, 0.1015625, 0.8984375, 1 | 0, 0.05078125, 0.94921875, 1 |

Piece (col, row) uses `SetTexCoord(u[col], u[col+1], v[row], v[row+1])`. The corners are drawn at margin x margin.

- **Crowned crew:** the centre piece is the background (near-black stone), drawn with vertex alpha = `bgAlpha`.
- **Tavern night:** the centre piece is NOT drawn; `Oak.tga` fills the inside instead (see section 3).

## 2. Classic (game art only; was L1)

| Part | Texture / definition | Confidence | Fallback |
|---|---|---|---|
| Panel backdrop | `{ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } }`, `SetBackdropColor(1,1,1,bgAlpha)`, `SetBackdropBorderColor(1,1,1,1)` | sure (in Classic `Backdrop.lua`) | today's flat look (`Theme.paint`) |
| Cards, pop-ups, settings | same, edgeFile `Interface\\DialogFrame\\UI-DialogBox-Gold-Border`, bgFile `...UI-DialogBox-Background-Dark`, edgeSize 32, insets 11 | sure | grey border tinted (1, 0.82, 0.3) |
| Tucked tab | same as the panel, edgeSize 16, insets 4, bg alpha 0.85 | sure | flat |
| Title plate | `Interface\\DialogFrame\\UI-DialogBox-Header`, whole texture, drawn 140 x 35 behind grip + title. Anchor TOPLEFT of panel (+2, +10): it sticks 10 above the frame. Cards: 62% of card width x 48, TOPLEFT (+6, +12) | sure (file); placement is ours | no plate |
| Keep open bar, Close, Mock buttons | `Interface\\Buttons\\UI-Panel-Button-Up` / `-Down` / `-Highlight` as three pieces: left (0, 0.09375, 0, 0.6875) 12 wide, middle (0.09375, 0.53125, 0, 0.6875) stretched, right (0.53125, 0.625, 0, 0.6875) 12 wide | sure (files); texcoords from memory of `UIPanelButtonTemplate`, check in game | `Widgets.button` look |
| Congrats button | same pieces, vertex colour (0.45, 1, 0.45) | as above | |
| Tabs | `Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab` (normal), `UI-Character-ActiveTab` (selected), three pieces flipped for top tabs: left (0, 0.15625, 1, 0), middle (0.15625, 0.84375, 1, 0), right (0.84375, 1, 1, 0); left and right are 10 wide | sure (files); texcoords from memory of `CharacterFrameTabButtonTemplate` | today's text tabs |
| Tab hover | `Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight`, ADD, alpha 0.4 | likely | WHITE8X8 white alpha 0.08 |
| XP bar | `Interface\\TargetingFrame\\UI-StatusBar`, vertex (1, 0.75, 0.15); back black; 1 px border (0.48, 0.48, 0.48) | sure | today's gradient |
| Class icons | `Interface\\TargetingFrame\\UI-Classes-Circles` + `CLASS_ICON_TCOORDS` | sure | `ClassIcon.apply` as now |
| Guild online / Offline bars | `Interface\\Buttons\\UI-PlusButton-Up` / `UI-MinusButton-Up` (already used) | sure | |
| Emblem | none on the panel and cards; the minimap button keeps `ns.Config.MINIMAP_ICON` | | |

The game files above all appear in Blizzard's Classic Era interface code (the Gethe/wow-ui-source `classic_era`
branch). No file listing of the Forever build itself was available.

### Classic colours (RGBA 0-1)

| Use | Value |
|---|---|
| Accent (title, selected tab, headings, Keep open text) | 1, 0.82, 0, 1 |
| Header count text | 0.81, 0.81, 0.81, 1 |
| Muted text (version, offline) | 0.60, 0.56, 0.44, 1 |
| Tab text normal / selected | 0.78, 0.70, 0.48, 1 / 1, 0.82, 0, 1 |
| Section heading line | 1 px, (0.54, 0.45, 0.25, 1) fading to alpha 0 at the right (`Theme.gradient` HORIZONTAL) |
| Row background | `Theme.gradient` HORIZONTAL from the class colour x 0.30 at alpha 0.5 to black at alpha 0.45; border 1 px black, inner 1 px white alpha 0.08 |
| Row name | class colour; zone 0.82, 0.78, 0.66; status 1, 1, 1; quest 1, 0.82, 0; award title 0.73, 0.64, 0.42 |
| Row hover | white alpha 0.08, ADD |
| Keep open OFF | button as above, text accent, check mark alpha 0.35 |
| Keep open ON | button as above + `UI-Panel-Button-Highlight` shown at alpha 0.5, text accent, check alpha 1 |
| News line in header | text 1, 1, 1, 1 |
| Pills | as now + inner 1 px (1, 0.84, 0.47, 0.5) |
| Tucked tab letters / count | accent, 1 px black shadow / 1, 1, 1 |

### Fonts

- Body text: everything stays `Theme.FONT.normal` (GameFontNormal + 1.5 = 13.5) and `Theme.FONT.small` (11.5).
- Classic title: `Theme.FONT.normal`.
- Card titles: `Theme.readable(..., 3)` (16.5).
- Fonts only from game files: `Fonts\\FRIZQT__.TTF` and `Fonts\\MORPHEUS.ttf`.

## 3. Crowned crew (default; was A1)

Everything as Classic, except:

| Part | Value |
|---|---|
| Panel, cards, pop-ups, settings, menu frame | `CrownedCrew/Frame.tga` 9-slice, margin 36 texels drawn 12. No backdrop. Centre vertex alpha `bgAlpha` (cards and pop-ups 0.97) |
| Content insets | unchanged (PAD 8). The frame's gold line sits about 5 in from the edge; the inner 4 of the 12 are plain dark, so rows at 8 do not cover the gold. Card text inset 16 left and right, 14 top |
| Header | as Classic (title plate behind grip + title). The header row starts at y 0 over the frame's top edge (as in the mock) |
| Section headings ("My party", "Pinned", "Rarely needed") | text accent, then `Divider.tga` from 6 after the text to the row's right edge, height 9 (texcoords full; the width stretches) |
| Tucked tab | `CrownedCrew/Banner.tga` drawn 24 x 86, texcoords full, no backdrop, same file both sides (the art is symmetric). Letters accent (1, 0.85, 0.42) with outline; count white with outline. Badge and marks unchanged |
| Emblem on the panel | `Crest.tga` 38 x 38, CENTER on the panel's BOTTOM (+0, +2), frame level above the rows. Mouse-transparent |
| Emblem on cards | `Crest.tga` 104 x 104, BOTTOMRIGHT (-12, +10), alpha 0.16, under the text |
| Minimap button | `Crest.tga` replaces the icon texture (same 17-unit size and offset as `MinimapButton.lua`'s icon), texcoords full |
| Accent | 1, 0.82, 0, 1 (as Classic) |

At 40% see-through the frame stays readable. Nothing to change.

## 4. Tavern night (was A2)

| Part | Value |
|---|---|
| Panel, settings, menu frame | `TavernNight/Frame.tga` 9-slice, margin 13 texels drawn 10. Centre piece not drawn |
| Panel background | `TavernNight/Oak.tga` inside the frame (inset 10), tiled at 256 UI units (`SetHorizTile(true)`, `SetVertTile(true)`, or texcoords `0..w/256`, `0..h/256`). Vertex colour 0.65, 0.65, 0.65, `bgAlpha` (35% darker) |
| Header band | 25 tall, from y -7 to y -32 (the row moves down 7; the band is drawn inside the frame). Band = `Oak.tga` at 256, vertex 1, 0.90, 0.78, 1; 1 px border (0.10, 0.05, 0.02); top highlight 1 px (1, 0.86, 0.63, 0.3) |
| Title | `Fonts\\MORPHEUS.ttf` size 15, colour 0.96, 0.89, 0.69, 1, shadow (0,0,0,0.7) offset (0,-1) |
| Header count | 0.95, 0.89, 0.74, 1 |
| Keep open bar | `Chalk.tga` tiled at 128, 2 px border (0.42, 0.26, 0.13) + 1 px (0.10, 0.05, 0.02). Text 0.91, 0.90, 0.86. Check white, alpha 0.35 off / 1 on. ON: text 1, 0.95, 0.60 |
| Tabs | flat rectangles. Normal: bg 0.80, 0.72, 0.55, 0.75, text 0.23, 0.14, 0.06. Selected: bg 0.95, 0.89, 0.75, 1, text 0.48, 0.10, 0.04. Hover: bg alpha 1. 1 px shadow under each (0,0,0,0.5). No rotation |
| Section headings | `Fonts\\MORPHEUS.ttf` 12, upper case, colour 1, 0.82, 0.48 |
| Rows | bg 0.08, 0.04, 0.01, 0.6; border 1 px 0.08, 0.035, 0.01; top highlight 1 px 1, 0.82, 0.55, 0.12. Name class colour; zone 0.85, 0.77, 0.60; status 1, 0.95, 0.84; quest 1, 0.82, 0.48; award title 0.88, 0.66, 0.35 |
| Row hover | 1, 0.82, 0.55, 0.10, ADD |
| XP bar | back 0, 0, 0, 0.6, border 1 px black; fill HORIZONTAL gradient 0.82, 0.54, 0.10 to 1, 0.85, 0.42; spark (the existing `UI-CastingBar-Spark`) |
| Mock button | VERTICAL gradient 0.42, 0.06, 0.03 to 0.69, 0.16, 0.10; border 1 px 0.16, 0.02, 0; text white |
| Congrats button | VERTICAL gradient 0.10, 0.30, 0.14 to 0.18, 0.48, 0.24 |
| Pills | bg 0.95, 0.89, 0.75, 1; text = tag colour x 0.7; no outline; icon kept |
| Guild online / Offline bars | bg 0, 0, 0, 0.35; text 0.91, 0.83, 0.65; plus / minus vertex 1, 0.82, 0.48 |
| Dividers | 1 px 0.42, 0.26, 0.13 |
| Tucked tab | `TavernNight/Sign.tga` drawn 24 x 86, texcoords full, same file both sides. Letters Morpheus 11, colour 0.96, 0.89, 0.69, outline. Count white 14, outline |
| Emblem | `Tankards.tga`, same three places and sizes as Crowned crew |
| Cards and pop-ups | parchment card. bg 0.96, 0.92, 0.81, 0.97; 1 px border 0.10, 0.05, 0.02; text 0.23, 0.14, 0.06; title Morpheus 17, colour 0.48, 0.10, 0.04; clickable lines 0.48, 0.10, 0.04; Close button = header band style with text 0.96, 0.89, 0.69. Pop-up coloured edge kept |
| Settings window | the panel's frame and oak; text as rows |
| Accent | 1, 0.82, 0.48, 1 |

At 40% see-through the oak goes muddy over bright scenes. If testers say so, draw the oak at vertex 0.5 (50% darker)
while the panel is faded (the `fadeAlpha` path), and 0.65 when it is not.

## 5. Icon atlas

`Art/Icons/Icons.tga`: 512 x 512, cells of 64, row-major. Each icon has its own transparent margin and dark
outline.

Rules:
- Use the texcoords below **as they are**. Do not add the 0.08 / 0.92 trim used for game icons.
- The texcoords are inset half a texel so neighbours never bleed in.
- Tint none.
- Entry format: name = { row, col, left, right, top, bottom }.

```lua
TwizCrewIcons = { -- Interface\AddOns\TwizCrew\Art\Icons\Icons.tga
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
-- aliases (same cell): cat_deaths = died, award_pauper = cat_loot, page_fun = clown, roast = mock,
-- card_welcome = online, card_recap = tab_activity
```

### Map to the addon's real keys

| Code key (where) | Icon |
|---|---|
| Panel tabs (`Panel.setTab`): `"crew"`, `"shame"`, `"activity"`; the Calendar button (`calTab`) | tab_crew, tab_shame, tab_activity, tab_calendar |
| Hall of Shame categories (`StatsDefs` TABS ids): `deaths`, `move`, `loot`, `oops`, `lazy` | died, cat_move, cat_loot, cat_oops, cat_lazy |
| Awards (`StatsDefs` AWARDS `id`): corpse, gravity, fishfood, weakling, again, leeroy, marathon, couch, neverwalks, fish, bunny, tourist, flyer, moneypit, broke, trash, ninja, juice, toofar, wanderer, quitter, duel, homesick, chatter, emotes, furniture, snail, medic | `award_<id>`; `pauper` uses cat_loot |
| Clown of the Night (`StatsDefs` id `clown`, Board, AwardsShow, row title) | clown |
| Crown holder mark (Board winner line, row award title) | crown |
| Recent / Activity `KIND_ICON` (`UI/Recent.lua`) and the tab's news line: online, offline, died, levelup, congrats, mock, roast | online, offline, died, levelup, congrats, mock, mock |
| Feed kinds `runaway`, `calnote`, `calreply`, `fight` (summary) | ran_off, tab_calendar, tab_calendar, tab_activity |
| Popups `KIND_ICON` (`UI/Popups.lua`): death, roast, levelup, online, runaway | died, mock, levelup, online, ran_off |
| `Popups.notice` for a stolen crown (`Stats`/`TrophyLogic`) / new guild member (`Welcome`) | crown_stolen / new_member |
| Row buttons (`PanelRows.lua`): `r.mock.icon` ("Mock" / "Mock back"), `r.cheer.icon` | mock / mock_back, congrats |
| Cards: AwayCard logo, Welcome start card, Recap, AwardsShow header | card_away, online, tab_activity, trophy |
| Settings pages: `basic`, `panel`, `alerts`, `fun`, `find`, `more` | page_basic, page_panel, page_alerts, clown, page_find, page_more |

### Places, sizes, positions

| Place | Priority | Size | Position |
|---|---|---|---|
| Board award rows | must | 19 (`Board.lua` ICON) | replaces the award `icon` texture; same anchor |
| Board category buttons | must | 14 | LEFT of the label, 3 in; label starts at 3 + 14 + 3 |
| Clown line on the board | must | 26 | LEFT of "Clown of the Night: name" |
| AwardsShow award and winner cards | must | as now (replace texture) | as now |
| Row Mock / Mock back / Congrats | must | `T.icon(14)` = 17 (as now) | replace texture, no trim |
| Pop-up icon | must | `T.icon(28)` = 34 (as now) | replace texture via `KIND_ICON` |
| Recent window and Activity tab rows | must | as now (`Recent.newRow`) | replace texture via `KIND_ICON` |
| News line in the header (tab slid out) | must | 16 | new texture LEFT of the news text, 4 gap |
| Minimap button | must | as the current icon | theme emblem (Crowned: Crest, Tavern: Tankards, Classic: unchanged) |
| Panel tab bar | nice | 14 | LEFT of each label (Crew, Hall of Shame, Activity, Calendar), 2 gap. `drawTabs` adds 16 per icon to each width before choosing a `TAB_STEPS` step. The "?" gets no icon |
| Row award title line | nice | 13 | LEFT of the title text, 3 gap (crown, or clown for Clown of the Night) |
| Card header logos | nice | `T.icon(26)` = 31 (as now) | replace texture |
| Settings tabs | nice | 13 | LEFT of each label, 2 gap |
| Calendar note kinds "Fun", "Crew" | nice (only these two) | as now | congrats, tab_crew |

### Keep the game's icon here

| Place | Game texture (unchanged) |
|---|---|
| Row tags DEAD, OTHER LAYER, FIGHTING, DUNGEON, FLYING, AFK | `Tags.ICON` as now |
| Layer news and pop-ups (`otherlayer`, `samelayer`, `layer_diff`, `layer_same`) | `Interface\\Icons\\Spell_Arcane_Blink` |
| Quest share (`qshare`, row share marks, quest ! ?) | `Spell_ChargePositive`, `Interface\\RaidFrame\\ReadyCheck-*`, `Interface\\GossipFrame\\*QuestIcon` |
| Meet-up pop-up | `Interface\\Icons\\INV_Misc_Map_01` |
| Pin (+ / star) | `UI-PlusButton-Up` / `UI-RaidTargetingIcon_1` |
| Header buttons (AFK, tools, settings) | `Spell_Nature_Sleep`, `INV_Misc_Wrench_01`, `UI-OptionsButton` |
| Tucked tab marks | `UI-TargetingFrame-Skull`, the portal icon |
| Calendar note kinds (14 of 16) | `Notes.ICONS` as now |
| `MODULE_ICONS` / `SETTING_ICONS` in settings rows | remove from rows (words only), or keep as now; do not use the atlas |

No icons on: the Keep open switch, any settings row, section headings, the About text, the tucked tab's letters.

## 6. Settings window layout

The window is 400 wide, PAD 14, and takes the theme frame.

1. **Title:** "TwizCrew settings", Friz 16.5, accent, TOPLEFT (14, -12). Version line under it: small, muted.
2. **Two links:** on the title line, right-aligned to x = 386: "How to use TwizCrew" · "What's new".
   - Friz 11.5, accent; the separator " · " is muted.
   - Hover: white text and a 1 px line under the word.
   - Click: `About.toggle` / `Changelog.toggle`.
   - They replace the two Help buttons in Basics.
3. **Tab row:** one row of six tabs, y -50, height 22: Basics, Panel, Alerts, Fun, Find, More.
   - Each tab: 4 padding, icon 13, 2 gap, label Friz 11.5, 4 padding; 2 between tabs.
   - Skin: the theme's tab style (Classic / Crowned: character tabs; Tavern: cream notes).
   - If the measured total is wider than 372, drop the icons (not the words).
4. **Basics page:** each control row is 24 tall, then a grey explanation line under it.
   - Grey line: Friz 10.5, colour 0.62, 0.62, 0.62, 1, width 372, wraps.
   - Row height grows by 13 per line + 3.
   - The text is the control's existing (i) tip, shortened to one line where possible.
5. **Headings** ("The panel", "News", "Me"): accent, Friz 12; the note after it is muted small; height 26.
6. **"Rarely needed" heading:**
   - 10 above it: the theme's divider, full width 372 (Classic / Tavern: 1 px line in the divider colour; Crowned:
     `Divider.tga`, 372 x 9).
   - "Rarely needed": Friz 12, muted (0.60, 0.56, 0.44); then 6 gap and "most people never change these" in small,
     0.50, 0.50, 0.50.
   - Height 26.
7. **Theme picker row:** in Basics under "The panel", and first on the Panel page.
   - Label "Theme" + (i).
   - Under it, three previews 64 x 80 with 8 gaps, the name under each (small).
   - Selected: 2 px accent outline + name in accent.
   - A click applies at once.
   - The previews are drawn live (no files): a 64 x 64 box with the theme's own frame drawn small:
     - Classic: backdrop edgeSize 12;
     - Crowned: Frame 9-slice drawn margin 6;
     - Tavern: Frame drawn margin 5 + Oak at 64.
   - Inside each: a 1 px accent line under a 10-tall title bar, three 6-tall bars in class colours (0.98, 0.49, 0.04),
     (0.25, 0.78, 0.92), (0.96, 0.55, 0.73) at alpha 0.7, and the emblem 16 x 16 at the bottom centre (none for
     Classic).
8. **Activity tab "Clear" button:** theme button style, 50 x 18, right of "Scroll for more", 4 gap.

## 7. Check in game (add to docs/TESTING.md when built)

- Each TGA shows, the right way up, with no dark edge, at Scale 100% and 150%.
- The 9-slice has no seams at the cuts.
- The tucked tab skins look right on both edges.
- Crowned crew falls back to Classic when `Art/` is renamed.
- Icons are crisp at 13 to 19 (no neighbour bleed).
- 40% see-through for all three themes, over a bright zone (Barrens) and a dark one (a dungeon).
