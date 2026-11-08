-- The Congrats button (Roasts.cheer, the panel's button and menu entry, the cheer mock show) and the spell rank
-- updater (Tools/RankUp.lua).

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

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function sent(ns, W, msgType)
  local out = {}
  for _, m in ipairs(W.sent) do
    local msg = ns.Codec.decode(m.text)
    if msg and msg.type == msgType then out[#out + 1] = msg.fields end
  end
  return out
end

-- Frostie online at level 12, then dings 13.
local function ding(ns, W)
  receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
  W:advance(2)
  receive(ns, W, "Frostie", "UPDATE", { lv = "13" })
  W:advance(1)
end

return {
  files = "toc",
  tests = {
    congrats_button_after_a_level_up = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest" })
      W:advance(1)
      A.no(ns.Panel.rowCheerShownForTest(1), "no button before a level-up")
      ding(ns, W)
      A.eq(ns.Panel.models()[1].level, 13)
      A.ok(ns.Panel.rowCheerShownForTest(1), "Congrats button after the ding")
      local r = ns.Panel.rowFrameForTest(1)
      ns.Panel.cheer(r) -- what the button does (the fake game has no GetParent)
      W:advance(1) -- the send queue
      local msgs = sent(ns, W, "MOCK")
      A.eq(#msgs, 1)
      A.eq(msgs[1].t, "Frostie"); A.eq(msgs[1].k, "g")
      A.no(msgs[1].x:find("{", 1, true), "placeholders filled: " .. msgs[1].x)
      A.no(ns.Panel.rowCheerShownForTest(1), "gone once you congratulated them")
      A.eq(ns.Log.errors(10), {})
    end,
    congrats_button_goes_away_by_itself = function(ns, A, W)
      start(ns, W)
      ding(ns, W)
      A.ok(ns.Panel.rowCheerShownForTest(1))
      W:advance(302)
      A.no(ns.Panel.rowCheerShownForTest(1), "after 5 minutes")
    end,
    congrats_about_me_cheers_in_3d = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      receive(ns, W, "Frostie", "MOCK", { t = "Twiz", x = "GG Twiz! Level 13 looks good on you.", k = "g" })
      A.ok(ns.MockShow.isShown(), "the show")
      A.eq(ns.MockShow.lastKind, "cheer", "cheering, not laughing")
      ns.MockShow.hide()
      ns.Modules.set("roasts", "cheers", false)
      W:advance(11)
      receive(ns, W, "Frostie", "MOCK", { t = "Twiz", x = "GG again", k = "g" })
      A.no(ns.MockShow.isShown(), "Congrats switched off: not shown")
      A.eq(ns.Log.errors(10), {})
    end,
    congrats_rules = function(ns, A, W)
      start(ns, W)
      A.no(ns.Roasts.canCheer("Twiz"), "not myself")
      A.ok(ns.Roasts.canCheer("Frostie"))
      A.ok(ns.Roasts.cheer("Frostie"))
      A.eq(ns.Roasts.cheer("Frostie"), nil, "not twice within 10 seconds")
      W:advance(11)
      A.ok(ns.Roasts.cheer("Frostie"))
      for _, l in ipairs(ns.Roasts.CHEER_LINES) do A.ok(#l <= 120, "short enough: " .. l) end
      A.ok(#ns.Roasts.CHEER_LINES >= 20)
      W.env.SlashCmdList.TWIZCREW("test cheer")
      A.eq(ns.MockShow.lastKind, "cheer", "/tc test cheer")
    end,
    ----------------------------------------------------------------------------------------------- spell ranks
    rank_plan_rules = function(ns, A)
      local R = ns.RankUp
      A.eq(R.rankOf("Rank 3"), 3); A.eq(R.rankOf(""), nil); A.eq(R.rankOf(nil), nil)
      local best = { Moonfire = { id = 105, rank = 5 }, Wrath = { id = 210, rank = 2 }, Thorns = { id = 300 } }
      local plan = R.plan({
        { slot = 1, name = "Moonfire", id = 101, rank = 1 },
        { slot = 2, name = "Wrath", id = 210, rank = 2 },   -- already the best
        { slot = 3, name = "Thorns", id = 299 },            -- no ranks known: left alone
        { slot = 4, name = "Moonfire", id = 105, rank = 5 },
        { slot = 5, name = "Mystery", id = 9 },
      }, best)
      A.eq(plan, { { slot = 1, name = "Moonfire", from = 1, to = 5, id = 105 } })
    end,
    rank_update_swaps_old_ranks_on_the_bars = function(ns, A, W)
      start(ns, W)
      local E = W.env
      local names = { [101] = "Moonfire", [103] = "Moonfire", [105] = "Moonfire", [201] = "Wrath" }
      local ranks = { [101] = 1, [103] = 3, [105] = 5, [201] = 1 }
      local book = { 101, 103, 105, 201 }
      local bars = { [1] = { "spell", 101 }, [2] = { "macro", 7 }, [3] = { "spell", 201 }, [74] = { "spell", 103 } }
      for id, n in pairs(names) do W.state.spellNames[id] = n end
      E.GetSpellSubtext = function(id) return ranks[id] and ("Rank " .. ranks[id]) or nil end
      E.GetNumSpellTabs = function() return 1 end
      E.GetSpellTabInfo = function() return "General", nil, 0, #book end
      E.GetSpellBookItemInfo = function(i) return "SPELL", book[i] end
      E.GetSpellBookItemName = function(i) return names[book[i]], "Rank " .. ranks[book[i]] end
      E.HasAction = function(slot) return bars[slot] ~= nil end
      E.GetActionInfo = function(slot) local b = bars[slot]; if b then return b[1], b[2] end end
      local cursor
      E.ClearCursor = function() cursor = nil end
      E.PickupSpell = function(id) cursor = id end
      E.GetCursorInfo = function() return cursor and "spell" or nil end
      E.PlaceAction = function(slot) bars[slot] = { "spell", cursor } end
      E.InCombatLockdown = function() return false end
      A.eq(ns.RankUp.update(false), 2)
      A.eq(bars[1][2], 105, "Moonfire Rank 1 -> Rank 5")
      A.eq(bars[74][2], 105, "on the bear bar too")
      A.eq(bars[2][1], "macro", "macros are left alone")
      A.eq(bars[3][2], 201, "Wrath already at its best")
      A.eq(ns.RankUp.update(false), 0, "nothing left to do")
      E.InCombatLockdown = function() return true end
      bars[1] = { "spell", 101 }
      A.eq(ns.RankUp.update(false), 0, "never in a fight")
      A.eq(bars[1][2], 101)
      W.env.SlashCmdList.TWIZCREW("rankup") -- /tc rankup runs it (still in a fight here: a message, no error)
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
