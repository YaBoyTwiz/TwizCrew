-- Spell helpers: the smart-target macro rules (pure) and the bars, macros and window (with a pretend spellbook,
-- action bars and macro list).

local function start(ns, W)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  ns.Crew.start()
  ns.Self.start()
  ns.LayerSensor.start()
  ns.Modules.startAll()
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
  return db
end

-- A pretend game: Fireball ranks 1-3 (harmful), Flash Heal ranks 1-2 (helpful), Bear Form (no ranks, neither).
-- Bars: 1 Fireball Rank 1, 2 Flash Heal Rank 2, 3 Bear Form, 4 your own macro "MyMacro".
-- Character macros are kept sorted by name (as the game does), so their numbers move when one is made.
local function game(W)
  local E = W.env
  local g = {}
  local names = { [131] = "Fireball", [132] = "Fireball", [133] = "Fireball", [201] = "Flash Heal", [202] = "Flash Heal",
    [300] = "Bear Form" }
  local ranks = { [131] = 1, [132] = 2, [133] = 3, [201] = 1, [202] = 2 }
  local book = { 131, 132, 133, 201, 202, 300 }
  g.book = book
  for id, n in pairs(names) do W.state.spellNames[id] = n end
  E.GetSpellSubtext = function(id) return ranks[id] and ("Rank " .. ranks[id]) or nil end
  E.GetNumSpellTabs = function() return 1 end
  E.GetSpellTabInfo = function() return "General", nil, 0, #book end
  E.GetSpellBookItemInfo = function(i) return "SPELL", book[i] end
  E.GetSpellBookItemName = function(i) return names[book[i]], ranks[book[i]] and ("Rank " .. ranks[book[i]]) or "" end
  E.IsHarmfulSpell = function(n) return n == "Fireball" end
  E.IsHelpfulSpell = function(n) return n == "Flash Heal" end
  E.GetSpellTexture = function() return 135812 end
  -- macros
  g.account = { [5] = { "MyMacro", 1, "/say hi" } }
  g.chars = {}
  E.MAX_ACCOUNT_MACROS, E.MAX_CHARACTER_MACROS = 120, 18
  local function sortChars() table.sort(g.chars, function(a, b) return a[1] < b[1] end) end
  local function indexOf(name)
    for i, m in ipairs(g.chars) do if m[1] == name then return 120 + i end end
    for i, m in pairs(g.account) do if m[1] == name then return i end end
  end
  g.indexOf = indexOf
  E.GetNumMacros = function() return 1, #g.chars end
  E.GetMacroInfo = function(i)
    local m = i > 120 and g.chars[i - 120] or g.account[i]
    if m then return m[1], m[2], m[3] end
  end
  E.CreateMacro = function(name, icon, body, perChar)
    assert(perChar, "only character macros")
    g.chars[#g.chars + 1] = { name, icon, body }
    sortChars()
    return indexOf(name)
  end
  E.EditMacro = function(i, name, icon, body)
    local m = g.chars[i - 120]
    m[1], m[2], m[3] = name or m[1], icon or m[2], body or m[3]
    sortChars()
    return indexOf(m[1])
  end
  E.DeleteMacro = function(i) table.remove(g.chars, i - 120) end
  -- bars (a macro on a bar is kept by name here; the game keeps it pointing at the right macro too)
  g.bars = { [1] = { "spell", 131 }, [2] = { "spell", 202 }, [3] = { "spell", 300 }, [4] = { "macro", "MyMacro" } }
  local cursor
  E.ClearCursor = function() cursor = nil end
  E.PickupSpell = function(id) cursor = { "spell", id } end
  E.PickupMacro = function(i) local name = E.GetMacroInfo(i); if name then cursor = { "macro", name } end end
  E.GetCursorInfo = function() return cursor and cursor[1] or nil end
  E.PlaceAction = function(slot) g.bars[slot] = cursor and { cursor[1], cursor[2] } or nil end
  E.HasAction = function(slot) return g.bars[slot] ~= nil end
  E.GetActionInfo = function(slot)
    local b = g.bars[slot]
    if not b then return nil end
    if b[1] == "macro" and b[3] == "account" then
      for i, m in pairs(g.account) do if m[1] == b[2] then return "macro", i end end
    end
    if b[1] == "macro" then return "macro", indexOf(b[2]) end
    return b[1], b[2]
  end
  E.GetActionText = function(slot) local b = g.bars[slot]; return b and b[1] == "macro" and b[2] or nil end
  E.InCombatLockdown = function() return g.combat == true end
  E.GetRealmName = function() return "Testrealm" end
  g.macroOn = function(slot)
    local b = g.bars[slot]
    if not b or b[1] ~= "macro" then return nil end
    local i = indexOf(b[2])
    local name, _, body = E.GetMacroInfo(i)
    return name, body
  end
  return g
end

return {
  files = "toc",
  tests = {
    macro_text = function(ns, A)
      local L = ns.SpellHelpersLogic
      A.eq(L.body("Fireball", nil, "harm", false),
        "#showtooltip\n/cast [@target,harm,nodead][@targettarget,harm,nodead][] Fireball")
      A.eq(L.body("Fireball", 3, "harm", true), "#showtooltip\n/assist [help,nodead]\n/cast Fireball(Rank 3)")
      A.eq(L.body("Flash Heal", nil, "help", false), "#showtooltip\n/cast [@target,help][@targettarget,help][@player] Flash Heal")
      A.eq(L.body("Flash Heal", 2, "help", true), "#showtooltip\n/assist [harm,nodead]\n/cast [@target,help][@player] Flash Heal(Rank 2)")
      A.eq(L.body("Bear Form", nil, nil, false), nil, "neither: no macro")
      -- read back exactly, and only ours
      for _, case in ipairs({ { "Fireball", nil, "harm", false }, { "Fireball", 3, "harm", true },
        { "Power Word: Shield", 10, "help", false }, { "Flash Heal", nil, "help", true } }) do
        local p = L.parse(L.body(case[1], case[2], case[3], case[4]))
        A.eq(p, { spell = case[1], rank = case[2], kind = case[3], switch = case[4] })
      end
      A.eq(L.parse(L.body("Fireball", nil, "harm", false) .. "\n"), { spell = "Fireball", kind = "harm", switch = false },
        "a newline at the end is fine")
      A.eq(L.parse("/cast Fireball"), nil, "your own macro")
      A.eq(L.parse("#showtooltip\n/cast [@target,harm,nodead][] Fireball"), nil, "close is not enough")
      A.eq(L.parse(nil), nil)
      -- names fit in 16 letters
      A.eq(L.macroName("Fireball"), "Fireball")
      A.eq(L.macroName("Flash Heal", 3), "Flash Heal 3")
      A.eq(L.macroName("Power Word: Shield"), "Power Word: Shie")
      A.eq(L.macroName("Power Word: Shield", 10), "Power Word: S 10")
      A.ok(#L.macroName("Power Word: Fortitude", 6) <= 16)
      A.eq(L.choice(nil), { newest = true, smart = false, switch = false }, "the defaults")
    end,
    the_plan = function(ns, A)
      local L = ns.SpellHelpersLogic
      local choices = { Fireball = { smart = true }, ["Flash Heal"] = { smart = true, newest = false, switch = true } }
      local function choiceOf(s) return L.choice(choices[s]) end
      local function kindOf(s) return ({ Fireball = "harm", ["Flash Heal"] = "help", Frostbolt = "harm" })[s] end
      local function bestRank(s) return ({ Fireball = 3, ["Flash Heal"] = 2, Frostbolt = 4 })[s] end
      local fb = L.body("Fireball", nil, "harm", false)
      local have = {
        { index = 121, name = "Fireball", body = fb, p = L.parse(fb) },
        { index = 122, name = "Frostbolt 2", body = L.body("Frostbolt", 2, "harm", false),
          p = L.parse(L.body("Frostbolt", 2, "harm", false)) },
        { index = 123, name = "Flash Heal 1", body = L.body("Flash Heal", 1, "help", false),
          p = L.parse(L.body("Flash Heal", 1, "help", false)) },
      }
      local edit, make, drop = L.macros({ "Fireball", "Flash Heal", "Bear Form", "Frostbolt" }, have, choiceOf, kindOf, bestRank)
      A.eq(edit, { { index = 123, name = "Flash Heal 1", body = L.body("Flash Heal", 1, "help", true) } },
        "Flash Heal keeps its macro and its name (so it stays on your bars) and the rank it had; only the text changes")
      A.eq(make, {}, "Fireball's macro is already right")
      A.eq(drop, { 122 }, "smart target is off for Frostbolt: its macro goes")
      -- a new one: named after the spell, never with the rank (so the name never has to change)
      edit, make, drop = L.macros({ "Fireball", "Flash Heal" }, {}, choiceOf, kindOf, bestRank)
      A.eq(make, { { name = "Fireball", body = fb, spell = "Fireball" },
        { name = "Flash Heal", body = L.body("Flash Heal", 2, "help", true), spell = "Flash Heal" } })
      A.eq(edit, {}); A.eq(drop, {})
    end,
    smart_target_never_touches_the_bars = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      local SH = ns.SpellHelpers
      local before = {}
      for k, v in pairs(g.bars) do before[k] = { v[1], v[2], v[3] } end
      SH.apply()
      A.eq(#g.chars, 0, "nothing until you ask")
      -- Fireball: smart target makes its macro, the bars stay as they are
      SH.set("Fireball", "smart", true)
      W:advance(1)
      A.eq(g.bars, before, "bars untouched")
      A.eq(#g.chars, 1)
      local i = g.indexOf("Fireball")
      A.eq(select(3, W.env.GetMacroInfo(i)), ns.SpellHelpersLogic.body("Fireball", nil, "harm", false))
      A.eq(SH.macroFor("Fireball"), i)
      -- you drag it onto slot 7 yourself
      A.ok(SH.pickup("Fireball"))
      W.env.PlaceAction(7)
      W.env.ClearCursor()
      W:fire("ACTIONBAR_SLOT_CHANGED", 7)
      W:advance(1)
      A.eq((g.macroOn(7)), "Fireball")
      A.eq(g.bars[1], { "spell", 131 }, "the plain Fireball on slot 1 is left alone")
      -- switch target / keep the rank: the same macro (same name), new text; slot 7 still has it
      SH.set("Fireball", "switch", true)
      W:advance(1)
      A.contains(select(2, g.macroOn(7)), "/assist [help,nodead]")
      SH.set("Fireball", "newest", false)
      W:advance(1)
      A.eq((g.macroOn(7)), "Fireball", "the name never changes")
      A.contains(select(2, g.macroOn(7)), "Fireball(Rank 3)")
      A.eq(#g.chars, 1)
      -- Flash Heal too: its own macro, nothing moves
      SH.set("Flash Heal", "smart", true)
      W:advance(1)
      A.eq(#g.chars, 2)
      A.eq(g.bars[2], { "spell", 202 })
      A.eq((g.macroOn(7)), "Fireball")
      -- Bear Form isn't aimed at anyone: no macro
      SH.set("Bear Form", "smart", true)
      W:advance(1)
      A.eq(#g.chars, 2)
      -- your own macro is never touched, even one with a spell's name
      local own = "/cast Flash Heal /say healing!"
      g.account[6] = { "Flash Heal", 1, own }
      SH.apply()
      A.eq(g.account[6][3], own)
      A.eq(g.account[5][3], "/say hi")
      A.eq(g.bars[4], { "macro", "MyMacro" })
      -- smart target off: the macro goes (and the game empties its slot); nothing is put anywhere
      SH.set("Fireball", "smart", false)
      W:advance(1)
      A.eq(#g.chars, 1)
      A.eq(g.bars[1], { "spell", 131 })
      A.eq(SH.apply(), 0, "nothing left to do")
      A.eq(ns.Log.errors(10), {})
    end,
    waits_for_the_fight = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      local SH = ns.SpellHelpers
      g.combat = true
      SH.set("Fireball", "smart", true)
      W:advance(1)
      A.eq(#g.chars, 0, "no macro changes in a fight")
      A.eq(SH.pickup("Fireball"), false)
      g.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.eq(#g.chars, 1, "right after it")
      A.eq(ns.Log.errors(10), {})
    end,
    a_spell_dragged_onto_the_bar_stays_plain = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      ns.SpellHelpers.set("Fireball", "smart", true)
      W:advance(1)
      g.bars[7] = { "spell", 132 }
      W:fire("ACTIONBAR_SLOT_CHANGED", 7)
      W:advance(2)
      A.eq(g.bars[7], { "spell", 132 }, "what you put on your bars stays exactly as you put it")
    end,
    the_rank_updater_skips_kept_ranks = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      ns.SpellHelpers.set("Fireball", "newest", false)
      W:advance(1)
      ns.RankUp.update(true)
      A.eq(g.bars[1], { "spell", 131 }, "Fireball keeps Rank 1")
      ns.SpellHelpers.set("Fireball", "newest", true)
      W:advance(1)
      ns.RankUp.update(true)
      A.eq(g.bars[1], { "spell", 133 })
    end,
    out_of_macro_slots = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      W.env.MAX_CHARACTER_MACROS = 1
      ns.SpellHelpers.set("Fireball", "smart", true)
      ns.SpellHelpers.set("Flash Heal", "smart", true)
      W:advance(1)
      A.eq(#g.chars, 1, "only one fits")
      A.eq(#ns.SpellHelpers.lastFull, 1)
      local said = table.concat(W.printed, "\n")
      A.contains(said, "no free macro slot")
      A.eq(ns.Log.errors(10), {})
    end,
    the_window = function(ns, A, W)
      start(ns, W)
      game(W)
      local SH = ns.SpellHelpers
      W.env.SlashCmdList.TWIZCREW("spells")
      A.ok(SH.isShown(), "/tc spells")
      local rows = SH.lastRows
      A.eq(#rows, 3)
      A.eq(rows[1].onBar, true)
      local byName = {}
      for _, r in ipairs(rows) do byName[r.spell] = r end
      A.eq(byName.Fireball.kind, "harm")
      A.eq(byName["Flash Heal"].kind, "help")
      A.eq(byName["Bear Form"].kind, nil, "no smart target for it")
      A.eq(byName["Bear Form"].ranked, false, "no newest rank either")
      -- clicking a switch flips that choice
      local i
      for k = 1, 3 do if SH.rowForTest(k).spell == "Fireball" then i = k end end
      local sw = SH.switchForTest(i, "smart")
      sw._scripts.OnClick(sw)
      A.eq(SH.choice("Fireball").smart, true)
      A.eq(sw.tcOn, true, "painted on")
      W:advance(1)
      local mb = SH.macroButtonForTest(i)
      A.eq(SH.macroFor("Fireball"), 121, "made")
      mb._scripts.OnDragStart(mb)
      A.eq(W.env.GetCursorInfo(), "macro", "dragging it picks the macro up")
      W.env.ClearCursor()
      -- in the wrench menu
      local found
      for _, it in ipairs(ns.Panel.toolItems()) do if it.label:find("Spell helpers") then found = it end end
      A.ok(found, "in the wrench menu")
      A.eq(ns.Log.errors(10), {})
    end,
    a_pop_up_for_a_new_rank = function(ns, A, W)
      start(ns, W)
      game(W)
      local SH = ns.SpellHelpers
      SH.learned(133)
      A.eq(SH.lastNotice, "New rank: Fireball (Rank 3)")
      local texts = table.concat(ns.Popups.shownForTest(), "\n")
      A.contains(texts, "New rank: Fireball (Rank 3)")
      SH.learned(300) -- Bear Form: nothing to choose
      A.eq(SH.lastNotice, "New rank: Fireball (Rank 3)")
      ns.Modules.set("spellhelp", "notify", false)
      SH.learned(201)
      A.eq(SH.lastNotice, "New rank: Fireball (Rank 3)", "switched off")
      ns.Modules.set("spellhelp", "notify", true)
      SH.learned(201)
      A.eq(SH.lastNotice, "New spell: Flash Heal (Rank 1)")
      ns.Popups.clickForTest(1)
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
