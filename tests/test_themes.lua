-- Themes (2026-11-23): the three theme tables are complete, the 9-slice maths, switching repaints live (every module
-- on, every module off), the fallback to Classic when the art does not load, the vertical flip in one place, the
-- see-through darkening of Tavern night's oak, the report line, and old saved data.

local ATLAS = "Interface\\AddOns\\TwizCrew\\Art\\Icons\\Icons.tga"
local CROWN = "Interface\\AddOns\\TwizCrew\\Art\\CrownedCrew\\Frame.tga"

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

-- The root's 9-slice centre piece (nil when the frame is not drawn as a 9-slice now).
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
    every_theme_has_every_key = function(ns, A)
      local T = ns.Theme
      A.eq(keys(T.THEMES), { "classic", "crowned", "tavern" })
      A.eq(T.ORDER, { "classic", "crowned", "tavern" })
      A.eq(T.DEFAULT, "crowned")
      -- the union of each table's keys must be in every theme (false = "has none", nil = forgotten)
      local function sameKeys(get, what)
        local all = {}
        for _, id in ipairs(T.ORDER) do
          local t = get(T.THEMES[id])
          A.eq(type(t), "table", id .. ": " .. what)
          for k in pairs(t) do all[k] = true end
        end
        for _, id in ipairs(T.ORDER) do
          local t = get(T.THEMES[id])
          for k in pairs(all) do A.ok(t[k] ~= nil, id .. " has no " .. what .. "." .. tostring(k)) end
        end
      end
      sameKeys(function(t) return t end, "theme")
      sameKeys(function(t) return t.frames end, "frames")
      sameKeys(function(t) return t.ink end, "ink")
      for _, id in ipairs(T.ORDER) do
        local t = T.THEMES[id]
        A.eq(t.id, id)
        for _, kind in ipairs({ "panel", "card", "popup", "window", "menu", "tab" }) do
          local f = t.frames[kind]
          A.ok(f, id .. " frames." .. kind)
          if f.style == "backdrop" then
            A.ok(f.backdrop and f.backdrop.edgeFile and f.backdrop.insets and f.border, id .. " " .. kind .. " backdrop")
          elseif f.style == "slice" then
            A.ok(type(f.file) == "string" and f.margin and #f.u == 4 and #f.v == 4, id .. " " .. kind .. " slice")
          elseif f.style == "flat" then
            A.ok(f.bg and f.border, id .. " " .. kind .. " flat")
          elseif f.style == "file" then
            A.ok(type(f.file) == "string", id .. " " .. kind .. " file")
          else
            error(id .. " " .. kind .. ": unknown style " .. tostring(f.style))
          end
        end
        A.ok(t.tabs.style == "game" or t.tabs.style == "flat", id .. " tabs")
        A.ok(t.button.style == "game" or t.button.style == "band", id .. " button")
        A.ok(t.keep.style == "game" or t.keep.style == "chalk", id .. " keep")
        A.ok(t.divider.style and t.divider.color, id .. " divider")
        for role, r in pairs(t.ink) do A.ok(r.color and #r.color >= 3, id .. " ink." .. role .. " has a colour") end
      end
      A.eq(T.THEMES.classic.probe, false, "Classic needs no file")
      A.eq(T.THEMES.classic.emblem, false, "Classic has no emblem")
      A.eq(T.THEMES.tavern.accent, { 1, 0.82, 0.48, 1 })
      A.eq(T.THEMES.crowned.accent, { 1, 0.82, 0, 1 })
    end,

    every_role_the_code_uses_is_in_every_theme = function(ns, A)
      local roles = rolesInCode()
      A.ok(roles.cardTitle and roles.title and roles.heading, "the scan finds the roles")
      for role in pairs(roles) do
        for _, id in ipairs(ns.Theme.ORDER) do
          A.ok(ns.Theme.THEMES[id].ink[role], id .. " has no ink." .. role)
        end
      end
    end,

    nine_slice_maths = function(ns, A)
      local T = ns.Theme
      local u, v = T.sliceCuts(256, 512, 36)
      A.eq(u, T.THEMES.crowned.frames.panel.u, "Crowned crew u cuts")
      A.eq(v, T.THEMES.crowned.frames.panel.v, "Crowned crew v cuts")
      A.eq(u, { 0, 0.140625, 0.859375, 1 }); A.eq(v, { 0, 0.0703125, 0.9296875, 1 })
      u, v = T.sliceCuts(128, 256, 13)
      A.eq(u, T.THEMES.tavern.frames.panel.u, "Tavern night u cuts")
      A.eq(v, T.THEMES.tavern.frames.panel.v, "Tavern night v cuts")
      -- piece (col, row) uses u[col], u[col + 1], v[row], v[row + 1]
      A.eq({ T.sliceCoords(u, v, 0, 0) }, { 0, 0.1015625, 0, 0.05078125 })
      A.eq({ T.sliceCoords(u, v, 1, 1) }, { 0.1015625, 0.8984375, 0.05078125, 0.94921875 })
      A.eq({ T.sliceCoords(u, v, 2, 2) }, { 0.8984375, 1, 0.94921875, 1 })
      -- corners d x d at the corners, edges between them, the centre inside
      A.eq({ T.slicePoints(0, 0, 12) }, { "TOPLEFT", 0, 0, "TOPLEFT", 12, -12 })
      A.eq({ T.slicePoints(1, 0, 12) }, { "TOPLEFT", 12, 0, "TOPRIGHT", -12, -12 })
      A.eq({ T.slicePoints(2, 0, 12) }, { "TOPRIGHT", -12, 0, "TOPRIGHT", 0, -12 })
      A.eq({ T.slicePoints(0, 1, 12) }, { "TOPLEFT", 0, -12, "BOTTOMLEFT", 12, 12 })
      A.eq({ T.slicePoints(1, 1, 12) }, { "TOPLEFT", 12, -12, "BOTTOMRIGHT", -12, 12 })
      A.eq({ T.slicePoints(2, 1, 12) }, { "TOPRIGHT", -12, -12, "BOTTOMRIGHT", 0, 12 })
      A.eq({ T.slicePoints(0, 2, 12) }, { "BOTTOMLEFT", 0, 12, "BOTTOMLEFT", 12, 0 })
      A.eq({ T.slicePoints(1, 2, 12) }, { "BOTTOMLEFT", 12, 12, "BOTTOMRIGHT", -12, 0 })
      A.eq({ T.slicePoints(2, 2, 12) }, { "BOTTOMRIGHT", -12, 12, "BOTTOMRIGHT", 0, 0 })
    end,

    the_vertical_flip_is_one_switch = function(ns, A)
      local T = ns.Theme
      local u, v = T.sliceCuts(256, 512, 36)
      A.eq({ T.flipV(0.25, 0.5) }, { 0.25, 0.5 }, "off: as stored")
      T.FLIP_ART = true
      A.eq({ T.flipV(0.25, 0.5) }, { 0.75, 0.5 })
      A.eq({ T.sliceCoords(u, v, 0, 0) }, { 0, 0.140625, 1, 0.9296875 }, "the top-left piece reads from the other end")
      local tex = ns.Theme.frame("Frame", nil, UIParent):CreateTexture()
      A.eq(ns.Icons.set(tex, "tab_crew"), "atlas")
      A.eq(tex._coords, { 0.000977, 0.124023, 1 - 0.000977, 1 - 0.124023 }, "the atlas cell flips too")
      T.FLIP_ART = false
    end,

    ---------------------------------------------------------------------------------------------------- drawing
    everyone_starts_on_crowned_crew = function(ns, A, W)
      boot(W)
      A.eq(ns.Modules.setting("panel", "theme"), "crowned")
      A.eq(ns.Theme.chosen(), "crowned")
      A.eq(ns.Theme.drawnId(), "crowned", "no answer from SetTexture is not a failure")
      local root = ns.Panel.rootForTest()
      local s = skin(root)
      A.eq(s.mode, "slice")
      A.eq(s.parts.slice5._texture, CROWN, "the centre is the frame file")
      A.eq(s.parts.slice5._vertex[4], 0.8, "the centre takes Background darkness")
      A.ok(s.parts.plate:IsShown(), "the title plate")
      A.ok(s.parts.emblem and s.parts.emblem:IsShown(), "the crest on the bottom edge")
      A.eq(s.parts.emblem._texture, "Interface\\AddOns\\TwizCrew\\Art\\CrownedCrew\\Crest.tga")
      ns.Modules.set("panel", "bgAlpha", 0.5)
      A.eq(s.parts.slice5._vertex[4], 0.5, "Background darkness still works")
      A.eq(ns.Log.errors(10), {})
    end,

    switching_repaints_at_once = function(ns, A, W)
      boot(W)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(1)
      ns.Settings.open(); ns.About.open(); ns.Recent.open(); ns.Changelog.open()
      tc(W, "report")
      ns.Popups.notice("Interface\\Icons\\INV_Misc_Gift_01", "Hello", "there", nil, nil, "new_member")
      W:advance(1)
      local root = ns.Panel.rootForTest()
      local before = ns.Theme.trackedCountForTest()
      local seen = {}
      ns.Bus.on("test", "THEME_CHANGED", function(chosen, drawn) seen[#seen + 1] = chosen .. ">" .. drawn end)
      ns.Modules.set("panel", "theme", "tavern")
      W:advance(0.2)
      local s = skin(root)
      A.eq(s.mode, "slice")
      A.ok(not s.parts.slice5:IsShown(), "Tavern night: no centre piece")
      A.ok(s.parts.fill:IsShown(), "the oak fills the inside")
      A.eq(s.parts.fill._texture, "Interface\\AddOns\\TwizCrew\\Art\\TavernNight\\Oak.tga")
      A.ok(s.parts.band:IsShown(), "the header band")
      A.no(s.parts.plate:IsShown(), "no title plate")
      A.eq(skin(ns.Panel.tabForTest()).parts.file._texture, "Interface\\AddOns\\TwizCrew\\Art\\TavernNight\\Sign.tga")
      local settings = W.env.TwizCrewSettings
      A.eq(skin(settings).mode, "slice", "the settings window follows")
      A.ok(skin(W.env.TwizCrewChangelog), "the What's new window too")
      ns.Modules.set("panel", "theme", "classic")
      W:advance(0.2)
      A.eq(s.mode, "backdrop")
      A.eq(root._backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border")
      A.eq(settings._backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Gold-Border")
      A.no(s.parts.slice1:IsShown(), "no 9-slice pieces left over")
      A.no(s.parts.fill:IsShown(), "no oak left over")
      A.no(s.parts.emblem:IsShown(), "Classic: no emblem")
      ns.Modules.set("panel", "theme", "crowned")
      W:advance(0.2)
      A.eq(s.mode, "slice")
      A.eq(root._backdrop, nil, "the backdrop is gone again")
      A.eq(seen, { "tavern>tavern", "classic>classic", "crowned>crowned" })
      A.eq(ns.Theme.trackedCountForTest(), before, "switching makes nothing new")
      A.eq(ns.Log.errors(10), {})
    end,

    switching_with_every_module_off_and_on = function(ns, A, W)
      boot(W)
      local ids = {}
      for _, d in ipairs(ns.Modules.list()) do ids[#ids + 1] = d.id end
      for _, id in ipairs(ids) do ns.Modules.setEnabled(id, false) end
      W:advance(1)
      for _, theme in ipairs({ "tavern", "classic", "crowned" }) do
        ns.Modules.set("panel", "theme", theme)
        W:advance(0.2)
      end
      A.eq(ns.Log.errors(10), {}, "every module off")
      for _, id in ipairs(ids) do ns.Modules.setEnabled(id, true) end
      W:advance(1)
      ns.Settings.open()
      for _, theme in ipairs({ "tavern", "classic", "crowned", "tavern" }) do
        ns.Modules.set("panel", "theme", theme)
        W:advance(0.2)
      end
      A.eq(ns.Log.errors(10), {}, "every module on")
      ns.Modules.resetAll()
      A.eq(ns.Modules.setting("panel", "theme"), "crowned", "Reset everything: back to Crowned crew")
      A.eq(ns.Theme.drawnId(), "crowned")
      A.eq(ns.Log.errors(10), {})
    end,

    texts_take_the_theme = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "theme", "tavern")
      local title = ns.Panel.headerButtonsForTest().head -- (the title is a text on the header)
      A.ok(title)
      local tab = ns.Panel.tabForTest()
      A.eq(tab.label.tcRole, "tuckLetters")
      ns.Popups.notice("Interface\\Icons\\INV_Misc_Gift_01", "Hello", "there")
      W:advance(0.6)
      ns.Modules.set("panel", "theme", "classic")
      A.eq(ns.Log.errors(10), {})
    end,

    ---------------------------------------------------------------------------------------------------- fallback
    art_that_fails_is_drawn_as_classic = function(ns, A, W)
      W.state.missingArt = true
      boot(W)
      A.eq(ns.Modules.setting("panel", "theme"), "crowned", "the choice stays saved")
      A.eq(ns.Theme.chosen(), "crowned")
      A.eq(ns.Theme.drawnId(), "classic")
      local root = ns.Panel.rootForTest()
      A.eq(skin(root).mode, "backdrop", "drawn as Classic")
      A.eq(root._backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border")
      local warned = false
      for _, l in ipairs(ns.Log.lines()) do if tostring(l):find("theme art missing, using Classic", 1, true) then warned = true end end
      A.ok(warned, "one log line says so")
      ns.Modules.set("panel", "theme", "tavern")
      A.eq(ns.Theme.drawnId(), "classic", "Tavern night's art is missing too")
      A.eq(ns.Theme.emblemFile(), nil)
      A.contains(ns.Theme.reportLine(), "art missing")
      A.contains(ns.Theme.reportLine(), "icons missing")
      A.contains(ns.Theme.reportLine(), "drawn Classic")
      A.eq(ns.Log.errors(10), {}, "a missing file never raises an error")
    end,

    the_report_says_which_theme_is_drawn = function(ns, A, W)
      boot(W)
      A.eq(ns.Theme.reportLine(), "Theme: Crowned crew, drawn Crowned crew; art loaded (the game gave no answer); "
        .. "icons loaded (the game gave no answer)")
      local found = false
      for _, l in ipairs(ns.Report.lines()) do if l:find("^Theme: Crowned crew") then found = true end end
      A.ok(found, "/tc report has the line")
    end,

    old_saved_data_gets_the_default_theme = function(ns, A, W)
      W.env.TwizCrewDB = { schema = 1, aboutSeen = true, panelSince0112 = true, fadeOnSince017 = true,
        modules = { panel = { enabled = true, settings = { scale = 1, bgAlpha = 0.8, keepOpen = true } } } }
      boot(W)
      A.eq(W.env.TwizCrewDB.modules.panel.settings.theme, "crowned", "the new default is written in")
      A.eq(ns.Theme.drawnId(), "crowned")
      A.eq(ns.Log.errors(10), {})
    end,

    a_broken_saved_theme_is_the_default = function(ns, A, W)
      boot(W)
      W.env.TwizCrewDB.modules.panel.settings.theme = "neon"
      A.eq(ns.Theme.chosen(), "crowned")
      A.eq(ns.Theme.drawnId(), "crowned")
      A.eq(ns.Modules.set("panel", "theme", 7), false, "a number is refused")
    end,

    tavern_oak_darkens_while_see_through = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "theme", "tavern")
      ns.Modules.set("panel", "keepOpen", true)
      W:advance(3)
      local s = skin(ns.Panel.rootForTest())
      A.eq(s.parts.fill._vertex[1], 0.5, "faded: 50% darker")
      ns.Modules.set("panel", "idleAlpha", 1) -- (100%: never see-through)
      W:advance(0.5)
      A.eq(s.parts.fill._vertex[1], 0.65, "solid: 35% darker")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
