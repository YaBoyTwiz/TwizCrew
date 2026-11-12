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

local function record(ns, name)
  local log = {}
  ns.Bus.on("test", name, function(...) log[#log + 1] = { ... } end)
  return log
end

local function logHas(ns, text)
  for _, line in ipairs(ns.Log.lines()) do if line:find(text, 1, true) then return true end end
  return false
end

-- A group member at `dist` yards (default 10); visible = the game shows them (same layer).
local function grouped(W, slot, name, visible, dist)
  W.state.pos = { x = 0, y = 0, instance = 1 }
  W.state.units[slot] = { name = name, player = true, visible = visible, pos = { x = dist or 10, y = 0, instance = 1 } }
end

local function seeMouseover(W, guid, times)
  W.state.guids.mouseover = guid
  for _ = 1, times or 2 do W:fire("UPDATE_MOUSEOVER_UNIT") end
end

return {
  files = "toc",
  tests = {
    fromGUID_cases = function(ns, A)
      local f = ns.LayerKey.fromGUID
      A.eq(f("Creature-0-4372-0-2345-299-0000ABCDEF"), "2345")
      A.eq(f("Vehicle-0-4372-0-17-555-0000AB"), "17")
      A.no(f("Player-4372-0ABCDEF")); A.no(f("Pet-0-4372-0-2345-299-01"))
      A.no(f("Creature-0-4372-0-0-299-01")); A.no(f(nil)); A.no(f("junk"))
      A.no(f("Creature-0-4372-0-x1-299-01"))
    end,
    tracker_needs_two_in_a_row = function(ns, A)
      local tr = ns.LayerKey.newTracker(2, 600)
      A.eq(tr:observe("1", 0), false); A.no(tr:current(0))
      A.eq(tr:observe("1", 1), true); A.eq(tr:current(1), "1")
      A.eq(tr:observe("2", 2), false); A.eq(tr:current(2), "1")
      tr:observe("1", 3); A.eq(tr:observe("2", 4), false)
      A.eq(tr:observe("2", 5), true); A.eq(tr:current(5), "2")
    end,
    tracker_goes_stale = function(ns, A)
      local tr = ns.LayerKey.newTracker(2, 600)
      tr:observe("2", 0); tr:observe("2", 5)
      A.eq(tr:current(5), "2")
      A.no(tr:current(606))
      A.eq(tr:current(605), "2")
      tr:reset(); A.no(tr:current(6))
    end,
    comparable_rules = function(ns, A)
      local c = ns.LayerKey.comparable
      local me = { zn = "Elwynn Forest", ins = false, online = true }
      local function them(t) local x = { zn = "Elwynn Forest", ins = false, online = true }
        for k, v in pairs(t) do x[k] = v end return x end
      A.eq(c(me, them({})), true)
      A.eq(c(me, them({ online = false })), false)
      A.eq(c(me, them({ zn = "Westfall" })), false)
      A.eq(c(me, them({ zn = false })), false)
      A.eq(c(me, them({ ins = true })), false)
      A.eq(c({ zn = "Elwynn Forest", ins = true, online = true }, them({})), false)
    end,
    judge_rules = function(ns, A)
      local j = ns.LayerKey.judge
      local mem = {}
      A.eq(j(mem, { comparable = true }, 0, 40, 8), "unknown", "never seen")
      A.eq(j(mem, { comparable = true, visible = true }, 1, 40, 8), "same")
      A.eq(j(mem, { comparable = true, visible = false, dist = 500 }, 2, 40, 8), "same", "far away: last verdict stands")
      A.eq(j(mem, { comparable = true, visible = false, dist = 10 }, 3, 40, 8), "same", "hidden, not long enough")
      A.eq(j(mem, { comparable = true, visible = false, dist = 10 }, 10, 40, 8), "same")
      A.eq(j(mem, { comparable = true, visible = false, dist = 10 }, 11, 40, 8), "different", "hidden nearby for 8 s")
      A.eq(j(mem, { comparable = true, visible = false, dist = 500 }, 12, 40, 8), "different", "stays while far")
      A.eq(j(mem, { comparable = true, visible = true }, 13, 40, 8), "same")
      A.eq(j(mem, { comparable = false }, 14, 40, 8), "unknown")
      A.eq(j(mem, { comparable = true }, 15, 40, 8), "unknown", "zone change forgets")
      local m2 = {}
      j(m2, { comparable = true, visible = false, dist = 10 }, 0, 40, 8)
      j(m2, { comparable = true, visible = false, dist = 100 }, 5, 40, 8) -- moved away: the wait starts over
      A.eq(j(m2, { comparable = true, visible = false, dist = 10 }, 9, 40, 8), "unknown")
      local m3 = {}
      j(m3, { comparable = true, visible = false, dist = 10, connected = false }, 0, 40, 8)
      A.eq(j(m3, { comparable = true, visible = false, dist = 10, connected = false }, 20, 40, 8), "unknown",
        "offline or ghost proves nothing")
      local m4 = {}
      j(m4, { comparable = true, visible = false }, 0, 40, 8)
      A.eq(j(m4, { comparable = true, visible = false }, 20, 40, 8), "unknown", "no distance proves nothing")
    end,
    sensor_reads_mouseover_and_skips_secret = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      A.eq(ns.LayerSensor.current(), "111")
      seeMouseover(W, W.secret())
      A.eq(ns.LayerSensor.current(), "111")
      A.eq(ns.LayerSensor.info().secretSkipped, 2)
      A.eq(ns.Log.errors(10), {})
    end,
    sensor_asks_about_secrets_before_looking_at_the_guid = function(ns, A, W)
      start(ns, W)
      local asked = {}
      W.env.issecretvalue = function(v) asked[#asked + 1] = v == nil and "nil" or v; return false end
      W.state.guids.mouseover = nil
      W:fire("UPDATE_MOUSEOVER_UNIT")
      A.eq(asked, { "nil" }, "checked even before the nil test")
      W.env.issecretvalue = function() error("broken") end
      W.state.guids.mouseover = "Creature-0-1-0-111-299-01"
      W:fire("UPDATE_MOUSEOVER_UNIT"); W:fire("UPDATE_MOUSEOVER_UNIT")
      A.no(ns.LayerSensor.current(), "a failing secret check skips the value")
      A.eq(ns.Log.errors(10), {})
    end,
    layer_changes_are_logged = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      A.ok(logHas(ns, "INFO layer key 111 confirmed in Elwynn Forest (mouseover)"))
      W:fire("ZONE_CHANGED_NEW_AREA")
      A.ok(logHas(ns, "INFO layer key reset in Elwynn Forest (zone change)"))
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      A.ok(logHas(ns, "INFO layer Frostie: unknown -> same (party1, visible, 10 yd; zones Elwynn Forest / Elwynn Forest)"))
    end,
    sensor_tolerates_missing_api = function(ns, A, W)
      start(ns, W)
      W.env.issecretvalue = nil
      W.env.UnitGUID = nil
      W:fire("UPDATE_MOUSEOVER_UNIT"); W:fire("PLAYER_TARGET_CHANGED"); W:fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      A.no(ns.LayerSensor.current())
      A.eq(ns.Log.errors(10), {})
    end,
    sensor_reads_target_and_nameplates = function(ns, A, W)
      start(ns, W)
      W.state.guids.target = "Creature-0-1-0-5-299-01"
      W:fire("PLAYER_TARGET_CHANGED"); W:fire("PLAYER_TARGET_CHANGED")
      A.eq(ns.LayerSensor.current(), "5")
      W.state.guids.nameplate3 = "Creature-0-1-0-6-299-01"
      W:fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); W:fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      A.eq(ns.LayerSensor.current(), "6")
    end,
    sensor_resets_on_zone_change = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      A.eq(ns.LayerSensor.current(), "111")
      W:fire("ZONE_CHANGED_NEW_AREA")
      A.no(ns.LayerSensor.current())
    end,
    sensor_resets_when_group_flips = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      W:fire("GROUP_ROSTER_UPDATE")
      A.eq(ns.LayerSensor.current(), "111")
      W.state.inGroup = true
      W:fire("GROUP_ROSTER_UPDATE")
      A.no(ns.LayerSensor.current())
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      W:fire("GROUP_ROSTER_UPDATE")
      A.eq(ns.LayerSensor.current(), "111")
    end,
    sensor_key_is_shared_and_goes_stale = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      W:advance(2)
      A.no(ns.Self.lastSent().lk == "111", "lk alone sends nothing: it rides along with the next update")
      W.state.combat = true -- a fight starts: this update carries lk with it
      W:fire("PLAYER_REGEN_DISABLED")
      W:advance(2)
      local found
      for _, s in ipairs(W.sent) do
        local m = ns.Codec.decode(s.text)
        if m and m.fields and m.fields.lk == "111" then found = true end
      end
      A.ok(found, "lk 111 was sent")
      W:advance(ns.Config.LAYER_STALE_AFTER + 40)
      A.no(ns.LayerSensor.current())
      W.state.combat = false
      W:fire("PLAYER_REGEN_ENABLED")
      W:advance(2)
      A.eq(ns.Self.lastSent().lk, "")
    end,
    same_layer_with_different_keys_is_same = function(ns, A, W)
      -- seen in game 2026-11-07: Twiz read key 1, Chaos read key 11, together in Darkshore
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-1-299-01")
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { lk = "11", zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "same")
    end,
    far_away_friend_is_never_different = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", false, 900)
      receive(ns, W, "Frostie", "STATE", { lk = "11", zn = "Elwynn Forest" })
      W:advance(60)
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
    end,
    seen_then_far_away_stays_same = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "same")
      W.state.units.party1.visible = false
      W.state.units.party1.pos = { x = 900, y = 0, instance = 1 }
      W:advance(60)
      A.eq(ns.Layer.relationOf("Frostie"), "same")
    end,
    hidden_nearby_for_a_while_is_different = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", zn = "Elwynn Forest" })
      local rel = record(ns, "LAYER_RELATION")
      W.state.units.party1.visible = false
      W:advance(ns.Config.LAYER_HIDDEN_FOR - ns.Config.LAYER_LOOK_TICK)
      A.eq(ns.Layer.relationOf("Frostie"), "same", "not yet")
      W:advance(ns.Config.LAYER_LOOK_TICK * 2 + 0.1)
      A.eq(ns.Layer.relationOf("Frostie"), "different")
      A.eq(rel, { { "Frostie", "same", "different" } })
      W.state.units.party1.visible = true
      W:advance(ns.Config.LAYER_LOOK_TICK + 0.1)
      A.eq(rel[2], { "Frostie", "different", "same" })
      A.eq(ns.Log.errors(10), {})
    end,
    many_nameplate_events_make_one_recompute = function(ns, A, W)
      start(ns, W)
      local looks = 0
      local members = ns.roster.members
      ns.roster.members = function(...) looks = looks + 1; return members(...) end
      for i = 1, 40 do W:fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. (i % 5 + 1)) end
      A.eq(looks, 0, "nothing runs inside the burst")
      W:advance(ns.Config.LAYER_RECOMPUTE_GAP + 0.01)
      A.eq(looks, 1, "one recompute for 40 events")
      ns.Bus.fire("MEMBER_UPDATED", "Frostie"); ns.Bus.fire("SELF_UPDATED")
      A.eq(looks, 1, "member and self updates wait too")
      W:advance(ns.Config.LAYER_RECOMPUTE_GAP + 0.01)
      A.ok(looks >= 2, "and then look")
      local before = looks
      W:advance(ns.Config.LAYER_LOOK_TICK)
      A.ok(looks > before, "the 2 s ticker still looks")
    end,
    ghost_is_not_another_layer = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", false)
      W.state.units.party1.ghost = true
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      W:advance(30)
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
    end,
    nameplate_counts_as_visible = function(ns, A, W)
      start(ns, W)
      W.state.units.nameplate3 = { name = "Frostie", player = true }
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "same", "not grouped, but their nameplate is up")
    end,
    surname_in_unit_name_still_matches = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie Coldsnap", true)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "same")
    end,
    unknown_never_becomes_different = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", false)
      receive(ns, W, "Frostie", "STATE", { zn = "Westfall" })
      W:advance(30)
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
      receive(ns, W, "Frostie", "UPDATE", { zn = "Elwynn Forest", ins = "1" })
      W:advance(30)
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
    end,
    offline_friend_becomes_unknown = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "same")
      local rel = record(ns, "LAYER_RELATION")
      W:advance(ns.Config.OFFLINE_AFTER + ns.Config.OFFLINE_TICK + 1)
      A.eq(rel, { { "Frostie", "same", "unknown" } })
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
    end,
    loading_screen_forgets = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      W.state.units.party1.visible = false
      W.state.units.party1.pos = { x = 900, y = 0, instance = 1 }
      W:fire("PLAYER_ENTERING_WORLD")
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
      A.ok(logHas(ns, "layer memory cleared (loading screen)"))
    end,
    layer_module_off_means_unknown = function(ns, A, W)
      start(ns, W)
      grouped(W, "party1", "Frostie", true)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "same")
      ns.Modules.setEnabled("layer", false)
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
      local rel = record(ns, "LAYER_RELATION")
      W:advance(10)
      A.eq(#rel, 0)
      ns.Modules.setEnabled("layer", true)
      A.eq(rel, { { "Frostie", "unknown", "same" } })
      A.eq(ns.Layer.relationOf("Frostie"), "same")
    end,
    layer_module_is_registered = function(ns, A)
      local d = ns.Modules.get("layer")
      A.ok(d); A.eq(d.name, "Layer tracker"); A.eq(d.tier, "module")
    end,
  },
}
