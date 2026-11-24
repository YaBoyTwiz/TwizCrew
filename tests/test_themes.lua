-- The look and the icons. Since 2026-11-23 Classic (the game's own art) is the only look: its table is complete, the
-- windows are drawn with it, Theme.apply repaints without making anything new, a v0.4.0 saved `theme` is dropped,
-- the report line, the vertical flip of our own art (the icon atlas), and the icons with their fallback.

local ATLAS = "Interface\\AddOns\\TwizCrew\\Art\\Icons\\Icons.tga"

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

local function keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- A frame's skin record (UI/Skin.lua).
local function skin(frame) return rawget(frame, "tcSkin") end

-- Every role name the code inks with: the literal words on T.ink / Theme.ink lines, and the ones UI/Skin.lua picks.
local function rolesInCode()
  local roles = { tabText = true, tabTextSel = true, tabTextHot = true, keep = true, keepOn = true, button = true }
  local toc = assert(io.open("TwizCrew/TwizCrew.toc", "r"))
  for line in toc:lines() do
    line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 2) ~= "##" then
      local f = io.open("TwizCrew/" .. line:gsub("\\", "/"), "r")
      if f then
        for code in f:lines() do
          if code:find("T%.ink%(") or code:find("Theme%.ink%(") then
            for word in code:gmatch('"(%a+)"') do roles[word] = true end
          end
        end
        f:close()
      end
    end
  end
  toc:close()
  return roles
end

return {
  files = "toc",
  tests = {
    ---------------------------------------------------------------------------------------------------- the data
    classic_is_the_only_look = function(ns, A)
      local T = ns.Theme
      A.eq(T.THEMES, nil, "no theme list")
      A.eq(T.active(), T.CLASSIC)
      local C = T.CLASSIC
      for _, kind in ipairs({ "panel", "card", "popup", "window", "menu", "tab" }) do
        local f = C.frames[kind]
        A.ok(f and f.backdrop and f.backdrop.edgeFile and f.backdrop.insets, kind .. ": a game backdrop")
        A.ok(f.backdrop.edgeFile:find("^Interface\\DialogFrame\\"), kind .. ": the game's own file")
      end
      A.eq(C.frames.panel.backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border")
      A.eq(C.frames.card.backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Gold-Border")
      A.eq(C.plate.file, "Interface\\DialogFrame\\UI-DialogBox-Header")
      for role, r in pairs(C.ink) do A.ok(r.color and #r.color >= 3, "ink." .. role .. " has a colour") end
      for _, gone in ipairs({ "chosen", "drawnId", "artLoaded", "emblemFile", "setFaded", "sliceCuts", "ORDER",
        "DEFAULT", "MORPHEUS" }) do
        A.eq(T[gone], nil, "Theme." .. gone .. " is gone with the other themes")
      end
    end,

    every_role_the_code_uses_is_in_the_look = function(ns, A)
      local roles = rolesInCode()
      A.ok(roles.cardTitle and roles.title and roles.heading, "the scan finds the roles")
      for role in pairs(roles) do A.ok(ns.Theme.CLASSIC.ink[role], "no ink." .. role) end
    end,

    the_vertical_flip_is_one_switch = function(ns, A)
      local T = ns.Theme
      A.eq({ T.flipV(0.25, 0.5) }, { 0.25, 0.5 }, "off: as stored")
      T.FLIP_ART = true
      A.eq({ T.flipV(0.25, 0.5) }, { 0.75, 0.5 })
      local tex = ns.Theme.frame("Frame", nil, UIParent):CreateTexture()
      A.eq(ns.Icons.set(tex, "tab_crew"), "atlas")
      A.eq(tex._coords, { 0.000977, 0.124023, 1 - 0.000977, 1 - 0.124023 }, "the atlas cell flips")
      T.FLIP_ART = false
    end,

    ---------------------------------------------------------------------------------------------------- drawing
    the_panel_is_drawn_classic = function(ns, A, W)
      boot(W)
      local root = ns.Panel.rootForTest()
      local s = skin(root)
      A.eq(s.mode, "backdrop")
      A.eq(root._backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border")
      A.ok(s.parts.plate:IsShown(), "the title plate")
      A.eq(s.parts.plate._texture, "Interface\\DialogFrame\\UI-DialogBox-Header")
      A.eq(s.parts.emblem, nil, "no crest under the panel")
      A.eq(ns.Theme.PANEL_OVERHANG.bottom, 0, "nothing hangs below the panel")
      A.eq(ns.Theme.PANEL_OVERHANG.top, 10, "the plate sticks 10 above it")
      A.eq(skin(ns.Panel.tabForTest()).mode, "backdrop", "the tucked tab: a small dialog box")
      ns.Modules.set("panel", "bgAlpha", 0.5)
      A.eq(s.alpha, 0.5, "Background darkness still works")
      A.eq(ns.Log.errors(10), {})
    end,

    apply_repaints_and_makes_nothing_new = function(ns, A, W)
      boot(W)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(1)
      ns.Settings.open(); ns.About.open(); ns.Recent.open(); ns.Changelog.open()
      tc(W, "report")
      ns.Popups.notice("Interface\\Icons\\INV_Misc_Gift_01", "Hello", "there", nil, nil, "new_member")
      W:advance(1)
      local before = ns.Theme.trackedCountForTest()
      local fired = 0
      ns.Bus.on("test", "THEME_CHANGED", function() fired = fired + 1 end)
      ns.Theme.apply()
      W:advance(0.2)
      A.eq(fired, 1, "THEME_CHANGED once")
      A.eq(skin(ns.Panel.rootForTest()).mode, "backdrop")
      A.eq(W.env.TwizCrewSettings._backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Gold-Border")
      A.ok(skin(W.env.TwizCrewChangelog), "the What's new window is skinned")
      A.eq(ns.Theme.trackedCountForTest(), before, "a repaint makes nothing new")
      A.eq(ns.Log.errors(10), {})
    end,

    apply_with_every_module_off_and_on = function(ns, A, W)
      boot(W)
      local ids = {}
      for _, d in ipairs(ns.Modules.list()) do ids[#ids + 1] = d.id end
      for _, id in ipairs(ids) do ns.Modules.setEnabled(id, false) end
      W:advance(1)
      ns.Theme.apply(); W:advance(0.2)
      A.eq(ns.Log.errors(10), {}, "every module off")
      for _, id in ipairs(ids) do ns.Modules.setEnabled(id, true) end
      W:advance(1)
      ns.Settings.open()
      ns.Theme.apply(); W:advance(0.2)
      A.eq(ns.Log.errors(10), {}, "every module on")
    end,

    texts_take_the_look = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(0.5)
      local count = ns.Panel._.countText
      A.eq(count.tcRole, "count")
      A.eq(count._textColor, { 0.81, 0.81, 0.81, 1 }, "the header count in light grey")
      local tab = ns.Panel.tabForTest()
      A.eq(tab.label.tcRole, "tuckLetters")
      A.eq(tab.label._textColor, { 1, 0.82, 0, 1 }, "the tab's letters in gold")
      ns.AwayCard.newCard("TwizCrewThemeTestCard", "Interface\\Icons\\INV_Misc_Gift_01", "A card", true, nil,
        "card_away").fill("sub", { { icon = "Interface\\Icons\\INV_Misc_Gift_01", text = "a line" } }, {})
      local card = W.env.TwizCrewThemeTestCard
      A.eq(skin(card).mode, "backdrop", "a card: the gold-bordered dialog box")
      A.eq(card._backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Gold-Border")
      A.ok(skin(card).parts.plate:IsShown(), "with its title plate")
      A.eq(skin(card).parts.emblem, nil, "and no crest")
      ns.Theme.apply(); W:advance(0.2)
      A.eq(count._textColor, { 0.81, 0.81, 0.81, 1 }, "the same after a repaint")
      A.eq(ns.Log.errors(10), {})
    end,

    the_minimap_button_keeps_its_icon_after_a_repaint = function(ns, A, W)
      boot(W)
      ns.Theme.apply(); W:advance(0.2)
      A.contains(ns.MinimapButton.reportLine(), "icon ok")
      A.eq(ns.Log.errors(10), {})
    end,

    ---------------------------------------------------------------------------------------------------- saved data
    a_saved_theme_from_v040_is_dropped = function(ns, A, W)
      for _, old in ipairs({ "crowned", "tavern", "classic", "neon" }) do
        W.env.TwizCrewDB = { schema = 1, aboutSeen = true, panelSince0112 = true, fadeOnSince017 = true,
          simpleSettings = true,
          modules = { panel = { enabled = true, settings = { scale = 1.2, bgAlpha = 0.8, keepOpen = true,
            theme = old } } } }
        ns.DB.init(W.env.TwizCrewDB, ns.Modules.list())
        local saved = W.env.TwizCrewDB.modules.panel.settings
        A.eq(saved.theme, nil, old .. ": deleted at start")
        A.eq(saved.scale, 1.2, old .. ": the other settings stay")
      end
    end,

    a_v040_upgrade_boots_classic_without_errors = function(ns, A, W)
      W.env.TwizCrewDB = { schema = 1, aboutSeen = true, panelSince0112 = true, fadeOnSince017 = true,
        simpleSettings = true, newsSeen = "0.4.0",
        modules = { panel = { enabled = true, settings = { scale = 1, bgAlpha = 0.8, keepOpen = true,
          theme = "tavern" } } } }
      boot(W)
      A.eq(W.env.TwizCrewDB.modules.panel.settings.theme, nil, "the old choice is gone")
      A.eq(ns.Modules.setting("panel", "theme"), nil)
      A.eq(ns.Modules.set("panel", "theme", "crowned"), false, "and cannot be set again")
      A.eq(skin(ns.Panel.rootForTest()).mode, "backdrop", "drawn Classic")
      ns.Modules.resetAll()
      A.eq(W.env.TwizCrewDB.modules.panel.settings.theme, nil, "Reset everything does not bring it back")
      A.eq(ns.Log.errors(10), {})
    end,

    ---------------------------------------------------------------------------------------------------- art missing
    missing_art_changes_only_the_icons = function(ns, A, W)
      W.state.missingArt = true
      boot(W)
      local root = ns.Panel.rootForTest()
      A.eq(skin(root).mode, "backdrop", "the frame needs no file of ours")
      A.no(ns.Icons.ok(), "the icons fall back")
      A.contains(ns.Theme.reportLine(), "icons missing")
      A.eq(ns.Log.errors(10), {}, "a missing file never raises an error")
    end,

    the_report_says_whether_the_icons_loaded = function(ns, A, W)
      boot(W)
      A.eq(ns.Theme.reportLine(), "Look: Classic (the game's own art); TwizCrew icons loaded (the game gave no answer)")
      local found = false
      for _, l in ipairs(ns.Report.lines()) do if l:find("^Look: Classic") then found = true end end
      A.ok(found, "/tc report has the line")
    end,

    ---------------------------------------------------------------------------------------------------- icons
    the_atlas_table_is_the_spec = function(ns, A)
      local I = ns.Icons
      local n = 0
      for name, c in pairs(I.CELLS) do
        n = n + 1
        local row, col = c[1], c[2]
        -- each cell is 64 texels of 512, inset half a texel: exactly as the spec, never the 0.08 / 0.92 trim
        local function near(x, y) return math.abs(x - y) < 0.000002 end
        A.ok(near(c[3], (col * 64 + 0.5) / 512) and near(c[4], (col * 64 + 63.5) / 512), name .. " u")
        A.ok(near(c[5], (row * 64 + 0.5) / 512) and near(c[6], (row * 64 + 63.5) / 512), name .. " v")
      end
      A.eq(n, 55, "55 icons")
      for alias, target in pairs(I.ALIASES) do A.ok(I.CELLS[target], alias .. " -> " .. target) end
      local tex = ns.Theme.frame("Frame", nil, UIParent):CreateTexture()
      A.eq(I.set(tex, "award_medic"), "atlas")
      A.eq(tex._texture, ATLAS)
      A.eq(tex._coords, { 0.875977, 0.999023, 0.625977, 0.749023 }, "the texcoords as they are")
      A.eq(I.set(tex, "roast"), "atlas", "an alias")
      A.eq(tex._coords, { 0.500977, 0.624023, 0.000977, 0.124023 }, "roast is the mock cell")
    end,

    every_real_key_has_an_icon_or_a_fallback = function(ns, A)
      local I = ns.Icons
      for _, d in ipairs(ns.StatsDefs.AWARDS) do
        A.ok(I.award(d.id) and I.cell(I.award(d.id)), "award " .. d.id .. " has an icon")
        A.ok(d.icon or ns.StatsDefs.ICON_FALLBACK, "award " .. d.id .. " has a game icon to fall back to")
      end
      A.eq(I.award("pauper"), "award_pauper"); A.ok(I.cell("award_pauper"), "pauper uses the loot bag")
      A.eq(I.award("clown"), "clown")
      A.eq(I.award("nobody"), nil, "an unknown id keeps the game icon")
      for _, t in ipairs(ns.StatsDefs.TABS) do A.ok(I.cell(I.category(t.id)), "category " .. t.id) end
      for _, kind in ipairs(ns.FeedLogic.KINDS) do
        A.ok(I.cell(I.recent(kind)), "Recent / Activity kind " .. kind)
        A.ok(I.cell(I.news(kind)), "news line kind " .. kind)
      end
      for _, kind in ipairs({ "runaway", "calnote", "calreply", "fight" }) do A.ok(I.cell(I.news(kind)), "news " .. kind) end
      A.eq(I.news("otherlayer"), nil, "layer news keeps the game's blink")
      A.eq(I.news("samelayer"), nil)
      for _, kind in ipairs({ "death", "roast", "levelup", "online", "runaway" }) do
        A.ok(I.cell(I.popup(kind)), "pop-up " .. kind)
      end
      A.eq(I.popup("layer_diff"), nil, "layer pop-ups keep the game icon")
      A.eq(I.popup("qshare"), nil, "quest share keeps the game icon")
      A.eq(I.popup("meet"), nil, "the meet-up keeps the map")
      for _, id in ipairs({ "crew", "shame", "activity", "calendar" }) do A.ok(I.cell(I.tab(id)), "tab " .. id) end
      for _, id in ipairs({ "basic", "panel", "alerts", "fun", "find", "more" }) do A.ok(I.cell(I.page(id)), "page " .. id) end
      for _, id in ipairs({ "away", "welcome", "recap", "awards" }) do A.ok(I.cell(I.card(id)), "card " .. id) end
      for _, name in ipairs({ "mock", "mock_back", "congrats", "crown", "clown", "crown_stolen", "new_member" }) do
        A.ok(I.cell(name), name)
      end
    end,

    icons_show_in_their_places = function(ns, A, W)
      boot(W)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12", tg = "DEAD" })
      ns.Panel.pin("Frostie") -- (so the row is in the main view)
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(1)
      local tabs = ns.Panel.tabButtonsForTest()
      A.ok(tabs.crew.icon:IsShown() or not tabs.crew.tcIconShown, "the Crew tab's icon follows the fit")
      A.eq(tabs.crew.icon._texture, ATLAS)
      A.no(rawget(tabs.help, "icon"), "the ? gets no icon")
      local row = ns.Panel.firstRowForTest and ns.Panel._.rowFrames[1]
      A.ok(row and row.mock:IsShown(), "a dead friend's row has its Mock button")
      A.eq(row.mock.icon._texture, ATLAS, "the Mock button's icon")
      A.eq(row.mock.icon._coords, { 0.500977, 0.624023, 0.000977, 0.124023 })
      A.eq(row.cheer.icon._texture, ATLAS, "the Congrats button's icon")
      ns.Popups.notice("Interface\\Icons\\INV_Misc_Gift_01", "Hi", "there", nil, nil, "new_member")
      W:advance(0.6)
      A.eq(ns.Log.errors(10), {})
    end,

    without_the_atlas_every_place_shows_what_it_showed = function(ns, A, W)
      W.state.missingArt = { [ATLAS] = true }
      boot(W)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12", tg = "DEAD" })
      ns.Panel.pin("Frostie") -- (so the row is in the main view)
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(1)
      A.no(ns.Icons.ok())
      local tabs = ns.Panel.tabButtonsForTest()
      A.no(tabs.crew.tcIconOn, "no tab icons")
      A.no(tabs.crew.icon:IsShown(), "and no empty square")
      local row = ns.Panel._.rowFrames[1]
      A.eq(row.mock.icon._texture, ns.Tags.ICON.DEAD, "Mock: the skull, as before")
      A.eq(row.cheer.icon._texture, "Interface\\Icons\\INV_Misc_Gift_01", "Congrats: the gift, as before")
      A.eq(row.cheer.icon._coords, { 0.08, 0.92, 0.08, 0.92 }, "trimmed like a game icon")
      A.eq(rawget(ns.Panel.rootForTest(), "tcSkin").mode, "backdrop", "the panel's frame is the game's own")
      local tex = ns.Theme.frame("Frame", nil, UIParent):CreateTexture()
      A.eq(ns.Icons.set(tex, "award_medic", "Interface\\Icons\\Spell_Holy_Resurrection", true), "game")
      A.eq(tex._coords, { 0, 1, 0, 1 }, "a place that drew it whole stays whole")
      A.eq(ns.Icons.set(tex, "award_medic"), "none")
      A.no(tex:IsShown(), "no fallback: hidden, never an empty square")
      A.eq(ns.Log.errors(10), {})
    end,

    tab_icons_count_in_the_fit = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(1)
      local tabs = ns.Panel.tabButtonsForTest()
      local root = ns.Panel.rootForTest()
      for _, style in ipairs({ "full", "compact", "tiny" }) do
        ns.Modules.set("panel", "rowStyle", style); W:advance(0.2)
        local used = 3
        for _, b in ipairs({ tabs.crew, tabs.shame, tabs.act, tabs.cal, tabs.help }) do
          if b:IsShown() then used = used + b:GetWidth() + 4 end
        end
        A.ok(used - 4 <= root:GetWidth(), style .. ": fits with the icons' room counted (" .. used - 4 .. ")")
        local w = #tabs.shame.label:GetText() * 6 + 10
        A.eq(tabs.shame:GetWidth(), w + (tabs.shame.tcIconShown and 16 or 0), style .. ": 16 more per icon")
      end
    end,

    tab_words_are_the_same_with_and_without_icons = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "keepOpen", true); W:advance(1)
      local tabs = ns.Panel.tabButtonsForTest()
      local order = { "crew", "shame", "act", "cal", "help" }
      local function words()
        local out = {}
        for _, k in ipairs(order) do
          local b = tabs[k]
          out[#out + 1] = (b:IsShown() and "" or "(hidden)") .. tostring(b.label:GetText())
        end
        return table.concat(out, " | ")
      end
      local with = {}
      for _, style in ipairs({ "full", "compact", "tiny" }) do
        ns.Modules.set("panel", "rowStyle", style); W:advance(0.3)
        with[style] = words()
      end
      -- the same panel as if the atlas had not loaded: no tab has an icon
      for _, k in ipairs(order) do rawset(tabs[k], "tcIconOn", false) end
      for _, style in ipairs({ "full", "compact", "tiny" }) do
        ns.Modules.set("panel", "rowStyle", style); W:advance(0.3)
        A.eq(with[style], words(), style .. ": icons never take the words' place")
        for _, k in ipairs(order) do A.no(tabs[k].tcIconShown, style .. " " .. k .. ": no icon") end
      end
      A.contains(with.full, "Hall of Shame", "full rows keep Hall of Shame")
    end,

    ---------------------------------------------------------------------------------------------------- settings
    grey_lines_and_the_rarely_needed_heading = function(ns, A, W)
      A.eq(ns.Settings.greyLines("short"), 1)
      A.eq(ns.Settings.greyLines(string.rep("x", 75)), 2, "about 74 letters a line without the game's measure")
      A.eq(ns.Settings.greyLines("anything", 26), 2, "the game's measure: 13 a line")
      A.eq(ns.Settings.greyLines("anything", 12), 1)
      for key, line in pairs(ns.Help.SETTING_LINES) do
        A.ok(#line <= 100, key .. ": one short line")
        A.no(line:find("\226\128\148", 1, true), key .. ": no em dash")
      end
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("panel")
      local d = ns.Settings.describeForTest()
      local rare
      for _, v in ipairs(d) do if v == "section:Rarely needed" then rare = true end end
      A.ok(rare, "the Rarely needed heading")
      A.eq(ns.Log.errors(10), {})
    end,

    without_the_atlas_the_tabs_keep_their_words = function(ns, A, W)
      W.state.missingArt = { [ATLAS] = true }
      boot(W)
      ns.Settings.open()
      A.no(ns.Settings.tabIconsForTest(), "no icons")
      local tabs = ns.Settings.tabButtonsForTest()
      for _, pg in ipairs(ns.Settings.PAGES) do
        A.eq(tabs[pg.id].label:GetText(), pg.label, "the word stays")
        A.no(tabs[pg.id].icon:IsShown(), pg.id .. ": no empty square")
        A.eq(tabs[pg.id]:GetWidth(), math.floor(4 + #pg.label * 6 + 4 + 0.5), pg.id .. ": the icon's room is gone")
      end
    end,

    the_activity_tab_has_a_clear_button = function(ns, A, W)
      boot(W)
      W:advance(40) -- (the login quiet time)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(1)
      for lv = 13, 30 do receive(W, ns, "Frostie", "UPDATE", { lv = tostring(lv) }); W:advance(0.1) end
      ns.Modules.set("panel", "keepOpen", true); W:advance(0.2)
      ns.Panel.setTab("activity"); W:advance(0.2)
      A.contains(ns.Panel.noteForTest(), "Scroll for more")
      local clear = ns.Panel.activityClearForTest()
      A.ok(clear and clear:IsShown(), "Clear, right of Scroll for more")
      A.eq({ clear:GetSize() }, { 50, 18 })
      A.ok(rawget(clear, "tcButton"), "in the theme's button look")
      clear._scripts.OnClick(clear); W:advance(0.2)
      A.eq(#ns.Feed.entries(), 0, "the list is empty")
      A.eq(ns.Panel.noteForTest(), "Nothing has happened yet.")
      A.no(clear:IsShown(), "nothing to scroll: no button")
      ns.Panel.setTab("crew"); W:advance(0.2)
      A.no(clear:IsShown())
      A.eq(ns.Log.errors(10), {})
    end,

    the_activity_clear_button_stays_inside_the_panel = function(ns, A, W)
      boot(W)
      W:advance(40)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(1)
      for lv = 13, 30 do receive(W, ns, "Frostie", "UPDATE", { lv = tostring(lv) }); W:advance(0.1) end
      ns.Modules.set("panel", "keepOpen", true); W:advance(0.2)
      ns.Panel.setTab("activity"); W:advance(0.2)
      local root = ns.Panel.rootForTest()
      for _, style in ipairs({ "full", "compact", "tiny" }) do
        ns.Modules.set("panel", "rowStyle", style); W:advance(0.3)
        local clear = ns.Panel.activityClearForTest()
        A.ok(clear:IsShown(), style)
        local point, rel, relPoint, x, y = clear:GetPoint(1)
        A.eq({ point, rel, relPoint }, { "TOPRIGHT", root, "TOPLEFT" })
        A.ok(x <= root:GetWidth() - 8, style .. ": its right edge inside the padding (" .. x .. ")")
        A.ok(-y + 18 <= root:GetHeight(), style .. ": its bottom inside the panel")
        local note = ns.Panel.noteTextForTest()
        A.ok(note:GetWidth() <= x - 8 - 4, style .. ": the note makes room for it")
      end
    end,

    ---------------------------------------------------------------------------------------------------- the panel
    tucked_the_plate_lies_inside_the_holder = function(ns, A, W)
      boot(W)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      W:advance(1)
      local root, holder = ns.Panel.rootForTest(), ns.Panel.holderForTest()
      A.eq(root:GetParent(), holder, "tucked: the panel hangs in the clipping holder")
      local top, bottom = ns.Theme.PANEL_OVERHANG.top, ns.Theme.PANEL_OVERHANG.bottom
      local s = skin(root)
      local _, _, _, _, py = s.parts.plate:GetPoint(1)
      A.ok(py <= top, "the plate's overhang (" .. py .. ") fits in the holder's top " .. top)
      for _, scale in ipairs({ 1, 1.5 }) do
        ns.Modules.set("panel", "scale", scale); W:advance(0.5)
        local h = (ns.Panel._.rootH or 0) * scale
        A.eq(holder:GetHeight(), math.max(1, h) + (top + bottom) * scale, "holder = panel + overhang, at scale " .. scale)
        local _, _, _, _, ry = root:GetPoint(1)
        A.eq(ry, -top, "the panel hangs the top overhang lower in it (its own units)")
        local _, _, _, _, hy = holder:GetPoint(1)
        A.eq(hy, top * scale, "and the holder sits that much higher: the panel stays where it was")
      end
      A.eq(ns.Log.errors(10), {})
    end,

    edges_are_never_more_than_half_a_side = function(ns, A, W)
      local T = ns.Theme
      A.eq(T.clampEdge(32, 270, 50), 25, "a pop-up 50 tall: at most 25")
      A.eq(T.clampEdge(16, 24, 86), 12, "the tucked tab, 24 wide: at most 12")
      A.eq(T.clampEdge(10, 16, 16), 8, "the ? tab's caps")
      A.eq(T.clampEdge(12, 400, 300), 12, "a big frame keeps the edge")
      A.eq(T.clampEdge(12, 0, 0), 12, "a frame not sized yet keeps it")
      A.eq(T.CLASSIC.frames.popup.backdrop.edgeSize, 16, "the pop-up edge")
      A.eq(T.CLASSIC.frames.tab.backdrop.edgeSize, 12, "the tucked tab edge")
      boot(W)
      ns.Modules.set("panel", "keepOpen", true); W:advance(1)
      local help = ns.Panel.tabButtonsForTest().help
      local cap = help.tcTab.parts.piece1:GetWidth()
      A.ok(cap * 2 <= help:GetWidth(), "the ?'s two caps fit (" .. cap .. " of " .. help:GetWidth() .. ")")
      local tab = ns.Panel.tabForTest()
      A.ok(tab._backdrop.edgeSize * 2 <= 24, "the tucked tab's border fits")
      A.eq(ns.Log.errors(10), {})
    end,

    the_calendar_keeps_its_open_button_lit_after_a_repaint = function(ns, A, W)
      boot(W)
      ns.Calendar.open(); ns.Calendar.show("month"); W:advance(0.2)
      local subs = ns.Calendar.tipFramesForTest().subs
      local function white(b) local c = b.text._textColor; return c and c[1] == 1 and c[2] == 1 and c[3] == 1 end
      A.ok(white(subs.usual), "Usual times (not open) is white")
      A.no(white(subs.month), "Month (open) is lit")
      ns.Theme.apply(); W:advance(0.2)
      A.ok(white(subs.usual), "still white after the repaint")
      A.no(white(subs.month))
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
