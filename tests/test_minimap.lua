-- The minimap button (essential "minimap"), its drag, clicks and tooltip, /tc minimap, reset, the addon
-- compartment functions and the .toc lines for them.

local BUTTON = "TwizCrewMinimapButton"

local function near(A, actual, expected, msg)
  A.ok(type(actual) == "number" and math.abs(actual - expected) < 0.01,
    (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- The button frame remembers its parent, last SetPoint, shown state and its textures; GameTooltip records lines.
local function record(W)
  local seen = { textures = {}, tip = { lines = {}, shown = false } }
  local create = W.env.CreateFrame
  W.env.CreateFrame = function(kind, name, parent, ...)
    local f = create(kind, name, parent, ...)
    if name ~= BUTTON then return f end
    seen.button = f
    local makeTexture = f.CreateTexture
    rawset(f, "tcParent", parent)
    rawset(f, "SetPoint", function(self, ...) rawset(self, "tcPoint", { ... }) end)
    rawset(f, "Show", function(self) rawset(self, "tcShown", true) end)
    rawset(f, "Hide", function(self) rawset(self, "tcShown", false) end)
    rawset(f, "IsShown", function(self) return rawget(self, "tcShown") == true end)
    rawset(f, "CreateTexture", function(self, ...)
      local t = makeTexture(self, ...)
      rawset(t, "SetTexture", function(self, path) rawset(self, "tcPath", path) end)
      rawset(t, "GetTexture", function(self)
        local path = rawget(self, "tcPath")
        if W.state.missingTextures and W.state.missingTextures[path] then return nil end
        return path
      end)
      seen.textures[#seen.textures + 1] = t
      return t
    end)
    return f
  end
  local tip = W.env.GameTooltip
  rawset(tip, "SetOwner", function(_, owner) seen.tip.owner = owner; seen.tip.lines = {} end)
  rawset(tip, "SetText", function(_, text) seen.tip.lines = { text } end)
  rawset(tip, "AddLine", function(_, text) seen.tip.lines[#seen.tip.lines + 1] = text end)
  rawset(tip, "Show", function() seen.tip.shown = true end)
  rawset(tip, "Hide", function() seen.tip.shown = false end)
  rawset(tip, "IsShown", function() return seen.tip.shown end)
  return seen
end

local function boot(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end
local function click(f, which) f._scripts.OnClick(f, which) end

local function printed(W, text)
  for _, line in ipairs(W.printed) do if line == text then return true end end
  return false
end

local function point(seen) return seen.button.tcPoint[4], seen.button.tcPoint[5] end

local function readToc()
  local f = assert(io.open("TwizCrew/TwizCrew.toc", "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local function minimapLine(ns)
  for _, line in ipairs(ns.Report.lines()) do
    if line:find("^Minimap button: ") then return line end
  end
end

local function hasLine(lines, text)
  for _, l in ipairs(lines) do if l == text then return true end end
  return false
end

return {
  files = "toc",
  tests = {
    registered_as_essential_with_a_show_switch = function(ns, A)
      local d = ns.Modules.get("minimap")
      A.ok(d, "module minimap")
      A.eq(d.tier, "essential")
      A.eq(d.name, "Minimap button")
      A.eq(d.defaults, { show = true, angle = 190 })
      A.eq(#d.settings, 1)
      local s = d.settings[1]
      A.eq({ s.key, s.kind, s.label }, { "show", "toggle", "Show minimap button" })
      A.contains(s.info, "/tc minimap")
    end,

    button_sits_on_the_minimap_after_login = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      A.ok(f, "button made")
      A.eq(f.tcParent, W.env.Minimap)
      A.eq(f.tcPoint[1], "CENTER")
      A.eq(f.tcPoint[2], W.env.Minimap)
      local x, y = point(seen)
      near(A, x, -73.86, "x")
      near(A, y, -13.02, "y")
      A.ok(f:IsShown())
      local paths = {}
      for _, t in ipairs(seen.textures) do paths[#paths + 1] = t.tcPath end
      A.ok(hasLine(paths, ns.Config.MINIMAP_ICON), "the icon")
      A.ok(hasLine(paths, "Interface\\Minimap\\MiniMap-TrackingBorder"), "the round border")
      A.eq(#ns.Log.errors(5), 0)
    end,

    settings_window_lists_it_under_essentials = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced", "all")
      local d = ns.Settings.describeForTest()
      local i, j
      for k, v in ipairs(d) do
        if v == "module:minimap:always on" then i = k end
        if v == "setting:minimap:show" then j = k end
      end
      A.ok(i and j and j == i + 1, "module row then its switch")
    end,

    left_click_opens_and_closes_settings = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local before = #W.printed
      click(seen.button, "LeftButton")
      A.ok(ns.Settings.isOpen())
      click(seen.button, "LeftButton")
      A.no(ns.Settings.isOpen())
      A.eq(#W.printed, before, "no chat lines")
    end,

    left_click_in_a_fight_still_opens = function(ns, A, W)
      local seen = record(W)
      boot(W)
      W.env.InCombatLockdown = function() return true end
      click(seen.button, "LeftButton")
      A.ok(ns.Settings.isOpen())
    end,

    left_click_that_fails_says_so_in_one_line = function(ns, A, W)
      local seen = record(W)
      boot(W)
      ns.Settings.toggle = function() error("boom") end
      click(seen.button, "LeftButton")
      A.ok(printed(W, "TwizCrew: the settings window could not open. Type /tc report for details."))
      W.env.InCombatLockdown = function() return true end
      click(seen.button, "LeftButton")
      A.ok(printed(W, "TwizCrew: the settings window could not open during this fight. Try again when it ends."))
    end,

    right_click_opens_a_menu_that_shows_and_hides_the_panel = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local before = #W.printed
      A.ok(ns.Modules.isEnabled("panel"))
      click(seen.button, "RightButton")
      A.ok(ns.Modules.isEnabled("panel"), "right-click opens the menu")
      local items = ns.MinimapButton.menuItems()
      A.eq(items[1].label, "Hide the crew panel")
      for _, it in ipairs(items) do A.eq(type(it.icon), "string", "an icon for " .. it.label) end
      items[1].onClick()
      A.no(ns.Modules.isEnabled("panel"))
      A.eq(ns.MinimapButton.menuItems()[1].label, "Show the crew panel")
      ns.MinimapButton.menuItems()[1].onClick()
      A.ok(ns.Modules.isEnabled("panel"))
      A.eq(#W.printed, before, "no chat lines")
      A.eq(ns.Log.errors(10), {})
    end,

    right_click_on_a_broken_panel_says_so = function(ns, A, W)
      local seen = record(W)
      boot(W)
      ns.Modules.markBroken("panel")
      ns.MinimapButton.menuItems()[1].onClick()
      A.ok(printed(W, "TwizCrew: the crew panel turned itself off after errors. Type /reload to try again."))
      A.no(ns.Modules.isEnabled("panel"))
    end,

    drag_moves_live_and_saves_once_at_the_end = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      f._scripts.OnDragStart(f)
      A.eq(type(f._scripts.OnUpdate), "function", "follows the cursor while dragging")
      W.state.cursor = { x = 500, y = 470 } -- straight above the minimap's centre (500, 400)
      f._scripts.OnUpdate(f, 0.02)
      local x, y = point(seen)
      near(A, x, 0, "x")
      near(A, y, 75, "y")
      A.eq(ns.Modules.setting("minimap", "angle"), 190, "not saved while dragging")
      f._scripts.OnDragStop(f)
      A.eq(ns.Modules.setting("minimap", "angle"), 90)
      A.eq(f._scripts.OnUpdate, nil)
    end,

    drag_uses_the_minimap_scale = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      W.state.minimap.scale = 2
      W.state.cursor = { x = 800, y = 800 } -- /2 = (400, 400): left of the centre
      f._scripts.OnDragStart(f)
      f._scripts.OnUpdate(f, 0.02)
      f._scripts.OnDragStop(f)
      A.eq(ns.Modules.setting("minimap", "angle"), 180)
    end,

    an_error_while_dragging_ends_the_drag = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      W.state.missing.GetCursorPosition = true
      f._scripts.OnDragStart(f)
      f._scripts.OnUpdate(f, 0.02)
      A.eq(f._scripts.OnUpdate, nil, "stopped following the cursor")
      A.eq(#ns.Log.errors(5), 1, "one error logged, not one per frame")
      f._scripts.OnDragStop(f)
      A.eq(ns.Modules.setting("minimap", "angle"), 190, "nothing saved")
    end,

    square_minimap_puts_it_on_the_edge = function(ns, A, W)
      local seen = record(W)
      W.state.minimapShape = "SQUARE"
      boot(W)
      local x, y = point(seen)
      near(A, x, -75, "x")
      near(A, y, -13.22, "y")
    end,

    no_shape_function_counts_as_round = function(ns, A, W)
      local seen = record(W)
      W.state.missing.GetMinimapShape = true
      boot(W)
      local x = point(seen)
      near(A, x, -73.86, "x")
    end,

    tc_minimap_turns_it_off_and_on = function(ns, A, W)
      local seen = record(W)
      boot(W)
      tc(W, "minimap")
      A.eq(ns.Modules.setting("minimap", "show"), false)
      A.no(seen.button:IsShown())
      A.ok(printed(W, "TwizCrew: minimap button hidden. Type /tc minimap to bring it back."))
      tc(W, "minimap")
      A.eq(ns.Modules.setting("minimap", "show"), true)
      A.ok(seen.button:IsShown())
      A.ok(printed(W, "TwizCrew: minimap button shown."))
    end,

    settings_switch_hides_it = function(ns, A, W)
      local seen = record(W)
      boot(W)
      ns.Settings.save("minimap", "show", false)
      A.no(seen.button:IsShown())
      ns.Settings.save("minimap", "show", true)
      A.ok(seen.button:IsShown())
    end,

    hiding_during_a_drag_ends_it = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      f._scripts.OnDragStart(f)
      tc(W, "minimap")
      A.eq(f._scripts.OnUpdate, nil)
    end,

    reset_shows_it_again_at_the_default_angle = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      W.state.cursor = { x = 600, y = 400 }
      f._scripts.OnDragStart(f)
      f._scripts.OnUpdate(f, 0.02)
      f._scripts.OnDragStop(f)
      A.eq(ns.Modules.setting("minimap", "angle"), 0)
      tc(W, "minimap")
      A.no(f:IsShown())
      ns.Modules.resetAll()
      A.ok(f:IsShown())
      A.eq(ns.Modules.setting("minimap", "angle"), 190)
      local x, y = point(seen)
      near(A, x, -73.86, "x")
      near(A, y, -13.02, "y")
    end,

    hidden_at_login_makes_no_frame_until_turned_on = function(ns, A, W)
      local seen = record(W)
      boot(W, function() ns.db.modules.minimap.settings.show = false end)
      A.eq(seen.button, nil)
      tc(W, "minimap")
      A.ok(seen.button and seen.button:IsShown())
      local x = point(seen)
      near(A, x, -73.86, "placed when made")
    end,

    junk_saved_values_are_repaired = function(ns, A, W)
      local seen = record(W)
      boot(W, function()
        ns.db.modules.minimap.settings.show = "yes"
        ns.db.modules.minimap.settings.angle = "abc"
      end)
      A.eq(ns.Modules.setting("minimap", "show"), true)
      A.eq(ns.Modules.setting("minimap", "angle"), 190)
      local f = seen.button
      W.state.cursor = { x = 400, y = 400 }
      f._scripts.OnDragStart(f)
      f._scripts.OnUpdate(f, 0.02)
      f._scripts.OnDragStop(f)
      A.eq(ns.Modules.setting("minimap", "angle"), 180, "a drag can be saved again")
    end,

    an_out_of_range_saved_angle_still_places = function(ns, A, W)
      local seen = record(W)
      boot(W, function() ns.db.modules.minimap.settings.angle = 450 end)
      local x, y = point(seen)
      near(A, x, 0, "x")
      near(A, y, 75, "y")
    end,

    no_minimap_frame_no_errors = function(ns, A, W)
      local seen = record(W)
      W.state.missing.Minimap = true
      boot(W)
      A.eq(seen.button, nil)
      tc(W, "minimap")
      tc(W, "minimap")
      A.eq(#ns.Log.errors(5), 0)
      local warned = false
      for _, line in ipairs(ns.Log.lines()) do
        if line:find("no minimap", 1, true) then warned = true end
      end
      A.ok(warned, "logged once")
    end,

    tooltip_shows_hints_and_crew_online = function(ns, A, W)
      local seen = record(W)
      boot(W)
      for _, text in ipairs(ns.Codec.encode("STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", ver = "0.1.0" })) do
        W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", "Frostie")
      end
      local f = seen.button
      f._scripts.OnEnter(f)
      A.ok(seen.tip.shown)
      A.eq(seen.tip.owner, f)
      A.eq(seen.tip.lines, {
        "TwizCrew v0.1.0",
        "Left-click: open settings",
        "Right-click: menu (crew panel, calendar, tools)",
        "Drag: move it around the minimap",
        "Crew online: 1 of 1",
      })
      f._scripts.OnLeave(f)
      A.no(seen.tip.shown)
    end,

    update_badge_and_tooltip_line = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      A.no(ns.MinimapButton.badgeShownForTest(), "up to date: no badge")
      for _, text in ipairs(ns.Codec.encode("STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", ver = "0.2.0",
        rs = "0.1.0" })) do
        W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", "Frostie")
      end
      A.ok(ns.MinimapButton.badgeShownForTest(), "a friend is newer: gold !")
      f._scripts.OnEnter(f)
      A.eq(seen.tip.lines[#seen.tip.lines], "Update available: v0.2.0 (Frostie has it)")
      ns.Modules.setEnabled("updates", false)
      A.no(ns.MinimapButton.badgeShownForTest(), "Update reminders off: no badge")
      f._scripts.OnEnter(f)
      A.eq(seen.tip.lines[#seen.tip.lines], "Crew online: 1 of 1", "and no tooltip line")
      A.eq(seen.tip.lines[1], "TwizCrew v0.1.0", "the version stays")
      ns.Modules.setEnabled("updates", true)
      A.ok(ns.MinimapButton.badgeShownForTest())
      tc(W, "minimap"); tc(W, "minimap")
      A.ok(ns.MinimapButton.badgeShownForTest(), "still there after hiding and showing the button")
      A.eq(#ns.Log.errors(5), 0)
    end,

    a_broken_update_check_never_breaks_the_button = function(ns, A, W)
      local seen = record(W)
      boot(W)
      ns.Updates.available = function() error("boom") end
      for _, text in ipairs(ns.Codec.encode("STATE", { cl = "MAGE", ver = "0.2.0" })) do
        W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", "Frostie")
      end
      A.no(ns.MinimapButton.badgeShownForTest())
      local f = seen.button
      f._scripts.OnEnter(f)
      A.ok(seen.tip.shown, "the tooltip still shows")
      click(f, "LeftButton")
      A.ok(ns.Settings.isOpen(), "clicks still work")
      for _, e in ipairs(ns.Log.errors(10)) do A.contains(e, "ERROR updates: ") end
    end,

    drag_hides_the_tooltip = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local f = seen.button
      f._scripts.OnEnter(f)
      f._scripts.OnDragStart(f)
      A.no(seen.tip.shown)
    end,

    missing_icon_falls_back_to_a_question_mark = function(ns, A, W)
      local seen = record(W)
      W.state.missingTextures = { [ns.Config.MINIMAP_ICON] = true }
      boot(W)
      local paths = {}
      for _, t in ipairs(seen.textures) do paths[#paths + 1] = t.tcPath end
      A.ok(hasLine(paths, "Interface\\Icons\\INV_Misc_QuestionMark"))
      A.eq(minimapLine(ns), "Minimap button: shown at 190 degrees, icon missing (showing a question mark)")
    end,

    report_has_a_minimap_line = function(ns, A, W)
      boot(W)
      A.eq(minimapLine(ns), "Minimap button: shown at 190 degrees, icon ok")
      tc(W, "minimap")
      A.eq(minimapLine(ns), "Minimap button: hidden (/tc minimap shows it)")
    end,

    help_lists_tc_minimap = function(ns, A, W)
      boot(W)
      tc(W, "help")
      A.ok(printed(W, "/tc minimap - show or hide the TwizCrew button on the minimap"))
    end,

    compartment_clicks_match_the_button = function(ns, A, W)
      boot(W, function() ns.db.modules.minimap.settings.show = false end)
      local clickFn = W.env.TwizCrew_OnAddonCompartmentClick
      A.eq(type(clickFn), "function")
      clickFn("TwizCrew", "LeftButton")
      A.ok(ns.Settings.isOpen(), "works with the minimap button hidden")
      clickFn("TwizCrew", "RightButton")
      A.no(ns.Modules.isEnabled("panel"))
      clickFn("TwizCrew", nil)
      A.no(ns.Settings.isOpen(), "no button name counts as a left-click")
    end,

    compartment_tooltip = function(ns, A, W)
      local seen = record(W)
      boot(W)
      local owner = W.env.CreateFrame("Button")
      W.env.TwizCrew_OnAddonCompartmentEnter("TwizCrew", owner)
      A.ok(seen.tip.shown)
      A.eq(seen.tip.owner, owner)
      A.eq(seen.tip.lines[1], "TwizCrew v0.1.0")
      A.no(hasLine(seen.tip.lines, "Drag: move it around the minimap"), "the list entry cannot be dragged")
      W.env.TwizCrew_OnAddonCompartmentLeave("TwizCrew", owner)
      A.no(seen.tip.shown)
      W.env.TwizCrew_OnAddonCompartmentEnter("TwizCrew", nil)
      A.no(seen.tip.shown, "no owner, no tooltip")
      A.eq(#ns.Log.errors(5), 0)
    end,

    toc_lines_for_the_compartment = function(ns, A, W)
      local toc = readToc()
      local icon = toc:match("\n## IconTexture:%s*([^\r\n]-)%s*[\r\n]")
      A.eq(icon, ns.Config.MINIMAP_ICON, "## IconTexture must match ns.Config.MINIMAP_ICON")
      for _, field in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
        local name = toc:match("\n## " .. field .. ":%s*([^\r\n]-)%s*[\r\n]")
        A.ok(name, "## " .. field)
        A.eq(type(W.env[name]), "function", name)
      end
      local logic = toc:find("UI\\MinimapLogic.lua", 1, true)
      local button = toc:find("UI\\MinimapButton.lua", 1, true)
      local commands = toc:find("UI\\Commands.lua", 1, true)
      A.ok(logic and button and commands and logic < button and button < commands, "load order")
    end,
  },
}
