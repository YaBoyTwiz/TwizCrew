-- Every game read goes through ns.Util.plain: a secret answer (dungeons) counts as "unknown" and never raises. One
-- test per adopted call site (the helper itself is tested in test_util). Full TOC boot.

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function start(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function lastPrinted(W) return W.printed[#W.printed] end

-- makes the named game functions answer with one secret value
local function hide(W, ...)
  local hidden = W.secret()
  for _, name in ipairs({ ... }) do W.env[name] = function() return hidden end end
  return hidden
end

return {
  files = "toc",
  tests = {
    self_state_reads_secret_instance_and_flight_as_unknown = function(ns, A, W)
      start(ns, W)
      W.state.subzone = "Goldshire"
      hide(W, "IsInInstance", "UnitOnTaxi")
      local f = ns.Self.gather()
      A.eq(f.ins, "0")
      A.eq(f.sz, "Goldshire", "a secret flight answer is not 'on a flight path'")
      A.eq(ns.Log.errors(10), {})
    end,
    quest_sharing_treats_a_secret_group_answer_as_not_grouped = function(ns, A, W)
      start(ns, W)
      hide(W, "IsInGroup", "IsInRaid")
      A.eq({ ns.Quest.request("Frostie", "Wolves") }, { false, "group" })
      A.contains(lastPrinted(W), "only works in a group")
      A.eq(ns.Log.errors(10), {})
    end,
    layer_keeps_its_verdicts_when_group_answers_are_secret = function(ns, A, W)
      start(ns, W)
      W.state.pos = { x = 0, y = 0, instance = 1 }
      W.state.inGroup = true
      W.state.units.party1 = { name = "Frostie", player = true, visible = true, pos = { x = 10, y = 0, instance = 1 } }
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      W:advance(1)
      A.eq(ns.Layer.relationOf("Frostie"), "same")
      hide(W, "IsInRaid", "IsInGroup", "UnitExists", "UnitIsPlayer", "IsInInstance")
      W:fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(ns.Config.LAYER_LOOK_TICK + 1)
      A.eq(ns.Layer.relationOf("Frostie"), "same", "verdict unchanged")
      A.eq(ns.Log.errors(10), {})
    end,
    detectors_add_nothing_for_secret_answers = function(ns, A, W)
      ns.Roasts = { send = function() end }
      start(ns, W)
      W.state.speed = 7
      hide(W, "UnitOnTaxi", "UnitIsDeadOrGhost", "IsMounted", "IsSwimming", "IsFalling", "UnitExists", "UnitIsAFK")
      for _ = 1, 20 do W:advance(0.5) end
      A.ok(ns.StatsStore.get("all", "st") > 0, "unknown riding / swimming / flight counts as walking")
      A.eq(ns.StatsStore.get("all", "mt"), 0)
      A.eq(ns.StatsStore.get("all", "sw"), 0)
      A.eq(ns.StatsStore.get("all", "af"), 0)
      A.eq(ns.StatsStore.get("all", "ds"), 0)
      A.eq(ns.Detectors.ctx.fallingAt, nil)
      A.eq(ns.Detectors.ctx.target, nil)
      A.eq(ns.Log.errors(10), {})
    end,
    the_target_detector_ignores_secret_target_answers = function(ns, A, W)
      ns.Roasts = { send = function() end }
      start(ns, W)
      W.state.units.target = { name = "Kobold Miner", level = 3, hostile = true, combat = true }
      hide(W, "UnitIsDead", "UnitIsPlayer", "UnitCanAttack", "UnitAffectingCombat")
      W:fire("PLAYER_TARGET_CHANGED")
      W:advance(3)
      A.eq(ns.Detectors.ctx.target, nil)
      A.eq(ns.Log.errors(10), {})
    end,
    mock_binding_treats_a_secret_dead_answer_as_not_dead = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W.state.units.target = { name = "Frostie", player = true }
      hide(W, "UnitIsDeadOrGhost")
      ns.Commands.binding("mock")
      A.eq(lastPrinted(W), "TwizCrew: target a dead crew friend to mock them.")
      A.eq(ns.Log.errors(10), {})
    end,
    report_lines_read_secret_answers_as_no = function(ns, A, W)
      start(ns, W)
      hide(W, "UnitOnTaxi", "UnitIsAFK", "IsInInstance", "UnitAffectingCombat", "UnitIsDeadOrGhost", "IsInGroup")
      local text = table.concat(ns.Report.lines(), "\n")
      A.contains(text, "Game says: flying no, away no, in a dungeon no (none), fighting no, dead no")
      A.eq(ns.Log.errors(10), {})
    end,
    diary_marks_me_as_here_not_away_when_the_answer_is_secret = function(ns, A, W)
      start(ns, W)
      hide(W, "UnitIsAFK")
      ns.Diary.mark(1700000000)
      local p = ns.Diary.people()[ns.Diary.myId()]
      local afk = 0
      for _, d in pairs(p.days) do if d.afk then afk = afk + ns.CalendarLogic.count(d.afk) end end
      A.eq(afk, 0)
      A.eq(ns.Log.errors(10), {})
    end,
    sending_to_the_group_treats_secret_group_answers_as_no_group = function(ns, A, W)
      start(ns, W)
      hide(W, "IsInRaid", "IsInGroup", "UnitInParty")
      local before = #W.sent
      ns.Comm.sendGroup("PING", {})
      for i = before + 1, #W.sent do A.no(W.sent[i].chatType == "RAID" or W.sent[i].chatType == "PARTY") end
      A.eq(ns.Log.errors(10), {})
    end,
    a_secret_level_at_death_is_unknown = function(ns, A, W)
      ns.Roasts = { send = function() end }
      start(ns, W)
      hide(W, "UnitLevel")
      W.state.dead = true
      W:fire("PLAYER_DEAD")
      W:advance(1)
      A.eq(ns.StatsStore.get("all", "dt"), 1)
      A.eq(ns.Log.errors(10), {})
    end,
    my_look_is_empty_when_race_and_sex_are_secret = function(ns, A, W)
      start(ns, W)
      hide(W, "UnitRace", "UnitSex")
      A.eq(ns.MockShow.myLook(), "")
      A.eq(ns.Log.errors(10), {})
    end,
    the_panel_reads_the_fight_from_the_lockdown_at_start_up = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      ns.Modules.set("panel", "hideInCombat", true)
      W:advance(2)
      A.eq(ns.Panel.isShown(), true)
      ns.Modules.setEnabled("panel", false)
      hide(W, "UnitAffectingCombat")
      ns.Modules.setEnabled("panel", true)
      W:advance(2)
      A.eq(ns.Panel.isShown(), true, "a secret fight answer is not a fight")
      ns.Modules.setEnabled("panel", false)
      W.state.combat = true
      ns.Modules.setEnabled("panel", true)
      W:advance(2)
      A.eq(ns.Panel.isShown(), false, "the lockdown is a fight")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
