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
      local function kindOf(s) return ({ Fireball = "harm", ["Flash Heal"] = "help" })[s] end
      local function bestRank(s) return ({ Fireball = 3, ["Flash Heal"] = 2 })[s] end
      local want, place = L.plan({
        { slot = 1, spell = "Fireball", rank = 1 },
        { slot = 2, spell = "Flash Heal", rank = 1 },
        { slot = 3, spell = "Bear Form" },
        { slot = 4, spell = "Frostbolt", rank = 2, ours = true, name = "Frostbolt 2", body = "x" },
        { slot = 5, spell = "Fireball", ours = true, name = "Fireball", body = "x" },
      }, choiceOf, kindOf, bestRank)
      A.eq(want, { Fireball = L.body("Fireball", nil, "harm", false),
        ["Flash Heal 1"] = L.body("Flash Heal", 1, "help", true) })
      A.eq(place, {
        { slot = 1, macro = "Fireball" },
        { slot = 2, macro = "Flash Heal 1" },
        { slot = 4, spell = "Frostbolt" }, -- smart target off now: the plain spell back (newest rank)
      }, "slot 5 already has the right macro (its text gets fixed in place)")
    end,
    smart_target_on_the_bars = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      local SH = ns.SpellHelpers
      SH.apply()
      A.eq(g.bars[1], { "spell", 131 }, "nothing changes until you ask")
      A.eq(#g.chars, 0)
      -- Fireball: smart target
      SH.set("Fireball", "smart", true)
      W:advance(1)
      local name, body = g.macroOn(1)
      A.eq(name, "Fireball")
      A.eq(body, ns.SpellHelpersLogic.body("Fireball", nil, "harm", false), "always the top rank: cast by name")
      A.eq(#g.chars, 1)
      -- switch target: the same macro, new text
      SH.set("Fireball", "switch", true)
      W:advance(1)
      name, body = g.macroOn(1)
      A.eq(name, "Fireball")
      A.contains(body, "/assist [help,nodead]")
      A.eq(#g.chars, 1, "still one macro")
      -- keep the rank: it keeps the one it has now (the top one), the old macro goes
      SH.set("Fireball", "newest", false)
      W:advance(1)
      name, body = g.macroOn(1)
      A.eq(name, "Fireball 3")
      A.contains(body, "Fireball(Rank 3)")
      A.eq(#g.chars, 1, "the unused macro was deleted")
      -- Flash Heal too: the numbers of the macros move (sorted), each slot still gets the right one
      SH.set("Flash Heal", "smart", true)
      W:advance(1)
      A.eq((g.macroOn(2)), "Flash Heal")
      A.contains(select(2, g.macroOn(2)), "[@target,help][@targettarget,help][@player] Flash Heal")
      A.eq((g.macroOn(1)), "Fireball 3")
      A.eq(#g.chars, 2)
      -- Bear Form isn't aimed at anyone: no macro even when asked
      SH.set("Bear Form", "smart", true)
      W:advance(1)
      A.eq(g.bars[3], { "spell", 300 })
      -- your own macro is never touched, even one with a spell's name
      local own = "/cast Flash Heal /say healing!"
      g.account[6] = { "Flash Heal", 1, own }
      g.bars[8] = { "macro", "Flash Heal", "account" }
      SH.apply()
      A.eq(g.account[6][3], own)
      A.eq(g.bars[8], { "macro", "Flash Heal", "account" }, "still your macro on that slot")
      g.bars[8] = nil
      A.eq(g.bars[4], { "macro", "MyMacro" })
      A.eq(g.account[5][3], "/say hi")
      -- smart target off: the plain spell back, at the rank it kept; its macro goes
      SH.set("Fireball", "smart", false)
      W:advance(1)
      A.eq(g.bars[1], { "spell", 133 })
      A.eq(#g.chars, 1)
      -- and with newest rank on again, the rank updater keeps it current
      SH.set("Flash Heal", "smart", false)
      W:advance(1)
      A.eq(g.bars[2], { "spell", 202 }, "newest rank: the top one")
      A.eq(#g.chars, 0)
      -- nothing left to do: nothing changes
      A.eq(SH.apply(), 0)
      A.eq(ns.Log.errors(10), {})
    end,
    waits_for_the_fight_and_the_cursor = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      local SH = ns.SpellHelpers
      g.combat = true
      SH.set("Fireball", "smart", true)
      W:advance(1)
      A.eq(g.bars[1], { "spell", 131 }, "not in a fight")
      g.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      A.eq((g.macroOn(1)), "Fireball", "right after it")
      -- holding something on the cursor: wait, never drop it
      SH.set("Fireball", "smart", false)
      W.env.PickupSpell(201)
      W:advance(1)
      A.eq((g.macroOn(1)), "Fireball", "waits while you drag")
      W.env.ClearCursor()
      W:advance(2)
      A.eq(g.bars[1][1], "spell", "done once the cursor is free")
      A.eq(ns.Log.errors(10), {})
    end,
    a_new_spell_on_the_bar_gets_it_too = function(ns, A, W)
      start(ns, W)
      local g = game(W)
      ns.SpellHelpers.set("Fireball", "smart", true)
      W:advance(1)
      g.bars[7] = { "spell", 132 }
      W:fire("ACTIONBAR_SLOT_CHANGED", 7)
      W:advance(1)
      A.eq((g.macroOn(7)), "Fireball", "dragged onto the bar: smart right away")
      A.eq(#g.chars, 1, "the same macro for both")
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
