-- Minimap button, pure rules (no WoW frames): angles, round / square placement, drag maths, tooltip lines.

local function near(A, actual, expected, msg)
  A.ok(type(actual) == "number" and math.abs(actual - expected) < 0.01,
    (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function at(A, L, angle, shape, expectX, expectY, width, height)
  local x, y = L.offset(angle, shape, width or 140, height or 140)
  near(A, x, expectX, tostring(shape) .. " " .. angle .. " x:")
  near(A, y, expectY, tostring(shape) .. " " .. angle .. " y:")
end

return {
  files = { "Core/Init.lua", "Core/Util.lua", "Core/UpdateLogic.lua", "UI/MinimapLogic.lua" },
  tests = {
    defaults_in_config = function(ns, A)
      A.eq(ns.Config.MINIMAP_ANGLE, 190)
      A.eq(ns.Config.MINIMAP_ICON, "Interface\\Icons\\Ability_Warrior_BattleShout")
    end,

    normalize_keeps_angles_in_0_to_360 = function(ns, A)
      local L = ns.MinimapLogic
      A.eq(L.normalize(10), 10)
      A.eq(L.normalize(370), 10)
      A.eq(L.normalize(360), 0)
      A.eq(L.normalize(-90), 270)
      A.eq(L.normalize(-720), 0)
      A.eq(L.normalize(12.34), 12.3, "rounded to a tenth of a degree")
    end,

    normalize_refuses_junk = function(ns, A)
      local L = ns.MinimapLogic
      for _, v in ipairs({ "abc", "90", true, {}, 0 / 0, math.huge, -math.huge }) do
        A.eq(L.normalize(v), nil, tostring(v))
      end
      A.eq(L.normalize(nil), nil)
      A.eq(L.angleOrDefault(nil), 190)
      A.eq(L.angleOrDefault("x"), 190)
      A.eq(L.angleOrDefault(-10), 350)
    end,

    round_minimap_puts_the_button_on_the_circle = function(ns, A)
      local L = ns.MinimapLogic
      -- 140 wide: radius 70 + 5 so the button sits on the rim
      at(A, L, 0, "ROUND", 75, 0)
      at(A, L, 90, "ROUND", 0, 75)
      at(A, L, 180, "ROUND", -75, 0)
      at(A, L, 270, "ROUND", 0, -75)
      at(A, L, 225, "ROUND", -53.03, -53.03)
    end,

    missing_or_unknown_shape_counts_as_round = function(ns, A)
      local L = ns.MinimapLogic
      at(A, L, 45, nil, 53.03, 53.03)
      at(A, L, 45, "BLOB", 53.03, 53.03)
      at(A, L, 45, 42, 53.03, 53.03)
    end,

    square_minimap_puts_the_button_on_the_edge = function(ns, A)
      local L = ns.MinimapLogic
      at(A, L, 0, "SQUARE", 75, 0)
      at(A, L, 45, "SQUARE", 75, 75, "the corner")
      at(A, L, 30, "SQUARE", 75, 43.30)
      at(A, L, 200, "SQUARE", -75, -27.30)
      at(A, L, 300, "SQUARE", 43.30, -75)
    end,

    mixed_shapes_round_only_where_the_game_says = function(ns, A)
      local L = ns.MinimapLogic
      -- CORNER-TOPLEFT: only the top-left part is round
      at(A, L, 135, "CORNER-TOPLEFT", -53.03, 53.03)
      at(A, L, 315, "CORNER-TOPLEFT", 75, -75)
      -- SIDE-BOTTOM: the bottom half is round
      at(A, L, 270, "SIDE-BOTTOM", 0, -75)
      at(A, L, 45, "SIDE-BOTTOM", 75, 75)
      -- TRICORNER-TOPLEFT: everything round but the bottom-right
      at(A, L, 135, "TRICORNER-TOPLEFT", -53.03, 53.03)
      at(A, L, 315, "TRICORNER-TOPLEFT", 75, -75)
      A.ok(L.isRound("ROUND", 315))
      A.no(L.isRound("SQUARE", 10))
      A.ok(L.isRound("SIDE-RIGHT", 10))
      A.no(L.isRound("SIDE-RIGHT", 170))
    end,

    odd_minimap_sizes = function(ns, A)
      local L = ns.MinimapLogic
      at(A, L, 0, "ROUND", 105, 0, 200, 200)
      at(A, L, 90, "ROUND", 0, 55, 200, 100)
      at(A, L, 0, "ROUND", 75, 0, 0, nil) -- a size the game could not tell: the normal 140
      at(A, L, 0, "ROUND", 75, 0, "x", 0 / 0)
      at(A, L, "junk", "ROUND", -73.86, -13.02) -- a junk angle: the default 190
    end,

    cursor_to_angle = function(ns, A)
      local L = ns.MinimapLogic
      -- the cursor comes in screen pixels; divided by the minimap's scale it matches the minimap's centre
      near(A, L.angleFromCursor(1200, 800, 2, 500, 400), 0)
      near(A, L.angleFromCursor(500, 500, 1, 500, 400), 90)
      near(A, L.angleFromCursor(400, 400, 1, 500, 400), 180)
      near(A, L.angleFromCursor(500, 300, 1, 500, 400), 270)
      near(A, L.angleFromCursor(400, 300, 1, 500, 400), 225)
    end,

    cursor_to_angle_refuses_junk = function(ns, A)
      local L = ns.MinimapLogic
      A.eq(L.angleFromCursor(nil, 1, 1, 1, 1), nil)
      A.eq(L.angleFromCursor(1, 1, 0, 1, 1), nil, "scale 0")
      A.eq(L.angleFromCursor(1, 1, 1, nil, 1), nil, "no centre yet")
      A.eq(L.angleFromCursor(0 / 0, 1, 1, 1, 1), nil)
      A.eq(L.angleFromCursor(1, 1, -1, 1, 1), nil)
    end,

    drag_round_trip_lands_where_the_cursor_is = function(ns, A)
      local L = ns.MinimapLogic
      -- cursor up-left of the centre, on a round minimap: the button goes on the rim in that direction
      local angle = L.angleFromCursor(470, 430, 1, 500, 400)
      near(A, angle, 135)
      at(A, L, angle, "ROUND", -53.03, 53.03)
    end,

    tooltip_lines = function(ns, A)
      local L = ns.MinimapLogic
      A.eq(L.tooltipLines(2, 5, true, true), {
        "TwizCrew",
        "Left-click: open settings",
        "Right-click: hide the Crew panel",
        "Drag: move it around the minimap",
        "Crew online: 2 of 5",
      })
      local lines = L.tooltipLines(0, 0, false, false)
      A.eq(lines[3], "Right-click: show the Crew panel")
      A.eq(#lines, 4, "no drag hint outside the button")
      A.eq(lines[4], "Crew online: none seen yet")
      A.eq(L.tooltipLines(nil, nil, false, false)[4], "Crew online: none seen yet")
    end,

    tooltip_has_version_and_update_line = function(ns, A)
      local L = ns.MinimapLogic
      local lines = L.tooltipLines(1, 2, true, true, { version = "0.1.0" })
      A.eq(lines[1], "TwizCrew v0.1.0")
      A.eq(lines.attention, nil, "no update: no gold line")
      A.eq(#lines, 5)
      lines = L.tooltipLines(1, 2, true, false, { version = "0.1.0", update = { name = "Frostie", ver = "0.2.0" } })
      A.eq(lines[#lines], "Update available: v0.2.0 (Frostie has it)")
      A.eq(lines.attention, #lines, "the update line is the gold one")
      A.eq(L.tooltipLines(1, 2, true, false, { version = 7 })[1], "TwizCrew", "junk version: just the name")
    end,
  },
}
