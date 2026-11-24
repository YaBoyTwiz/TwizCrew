# Themes and icons: build spec

**Cut down on 2026-11-23, after v0.4.0.** The owner first picked three themes (Classic, Crowned crew as the default,
Tavern night) and an icon set; right after the release he decided: "For crew let's use Classic as the default and
remove the other themes." Crowned crew, Tavern night, their art files, the theme picker and the `panel.theme` setting
are gone, and their sections of this spec were deleted (git history has them). What is left: **Classic** (game art
only) and the **icon set**, which stays as built.

Mock-ups: `looks.html` (L1 = Classic, the Icons / Icons in use sections). All sizes below are UI units at Scale 100%
unless they say "texels".

## 0. Files

| File | Size (texels) | Bytes | What |
|---|---|---|---|
| `Art/Icons/Icons.tga` | 512 x 512 | 1,048,620 | icon atlas, 8 x 8 cells of 64, 55 used |

Format: TGA image type 2, uncompressed (no RLE), 32 bits per pixel, 8 alpha bits; bottom-left origin (descriptor
0x08, the TGA default); straight (not premultiplied) alpha, the colour under transparent pixels bled from their
neighbours so scaled edges get no dark fringe. The path in code needs the extension:
`Interface\\AddOns\\TwizCrew\\Art\\Icons\\Icons.tga`. Classic needs no file.

Not verified in the game (check on first load): that WoW Forever loads the TGA at all; that it does not show upside
down (if it does: `Theme.FLIP_ART`, or re-export top-left); that `SetTexture` returns false for a missing file. When
the atlas does not load, every place draws the game icon it drew before.

## 1. Classic (game art only; was L1)

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
- Fonts only from game files: `Fonts\\FRIZQT__.TTF`.

## 2. Icon atlas

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
| Minimap button | must | as the current icon | unchanged (Classic has no emblem) |
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

## 3. Settings window layout

The window is 400 wide, PAD 14, and takes the Classic window frame.

1. **Title:** "TwizCrew settings", Friz 16.5, accent, TOPLEFT (14, -12). Version line under it: small, muted.
2. **Two links:** on the title line, right-aligned to x = 386: "How to use TwizCrew" · "What's new".
   - Friz 11.5, accent; the separator " · " is muted.
   - Hover: white text and a 1 px line under the word.
   - Click: `About.toggle` / `Changelog.toggle`.
   - They replace the two Help buttons in Basics.
3. **Tab row:** one row of six tabs, y -50, height 22: Basics, Panel, Alerts, Fun, Find, More.
   - Each tab: 4 padding, icon 13, 2 gap, label Friz 11.5, 4 padding; 2 between tabs.
   - Skin: the game's character tabs.
   - If the measured total is wider than 372, drop the icons (not the words).
4. **Basics page:** each control row is 24 tall, then a grey explanation line under it.
   - Grey line: Friz 10.5, colour 0.62, 0.62, 0.62, 1, width 372, wraps.
   - Row height grows by 13 per line + 3.
   - The text is the control's existing (i) tip, shortened to one line where possible.
5. **Headings** ("The panel", "News", "Me"): accent, Friz 12; the note after it is muted small; height 26.
6. **"Rarely needed" heading:**
   - 10 above it: a 1 px line in the divider colour, full width 372, fading out.
   - "Rarely needed": Friz 12, muted (0.60, 0.56, 0.44); then 6 gap and "most people never change these" in small,
     0.50, 0.50, 0.50.
   - Height 26.
7. **Theme picker row:** removed (2026-11-23, after v0.4.0): Classic is the only look.
8. **Activity tab "Clear" button:** game button style, 50 x 18, right of "Scroll for more", 4 gap.

## 4. Check in game (also in docs/TESTING.md)

- The icon atlas shows, the right way up, with no dark edge, at Scale 100% and 150%.
- Icons are crisp at 13 to 19 (no neighbour bleed).
- With `Art/` renamed, every place shows its old game icon and nothing errors.
- 40% see-through over a bright zone (Barrens) and a dark one (a dungeon): the panel stays readable.
