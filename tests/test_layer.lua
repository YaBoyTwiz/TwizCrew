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
    relation_rules = function(ns, A)
      local r = ns.LayerKey.relation
      local me = { lk = "1", zn = "Elwynn Forest", ins = false, online = true }
      local function them(t) local x = { lk = "1", zn = "Elwynn Forest", ins = false, online = true }
        for k, v in pairs(t) do x[k] = v end return x end
      A.eq(r(me, them({})), "same")
      A.eq(r(me, them({ lk = "2" })), "different")
      A.eq(r(me, them({ lk = "2", online = false })), "unknown")
      A.eq(r(me, them({ lk = "2", zn = "Westfall" })), "unknown")
      A.eq(r(me, them({ lk = "2", zn = false })), "unknown")
      A.eq(r({ lk = nil, zn = "Elwynn Forest", online = true }, them({ lk = "2" })), "unknown")
      A.eq(r(me, them({ lk = "" })), "unknown")
      A.eq(r(me, them({ lk = "2", ins = true })), "unknown")
      A.eq(r({ lk = "1", zn = "Elwynn Forest", ins = true, online = true }, them({ lk = "2" })), "unknown")
    end,
    sensor_reads_mouseover_and_skips_secret = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      A.eq(ns.LayerSensor.current(), "111")
      W.state.secret["Creature-0-1-0-222-299-01"] = true
      seeMouseover(W, "Creature-0-1-0-222-299-01")
      A.eq(ns.LayerSensor.current(), "111")
      A.eq(ns.LayerSensor.info().secretSkipped, 2)
      A.eq(ns.Log.errors(10), {})
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
      local found
      for _, s in ipairs(W.sent) do
        local m = ns.Codec.decode(s.text)
        if m and m.fields and m.fields.lk == "111" then found = true end
      end
      A.ok(found, "lk 111 was sent")
      W:advance(ns.Config.LAYER_STALE_AFTER + 40)
      A.no(ns.LayerSensor.current())
      W:advance(2)
      A.eq(ns.Self.lastSent().lk, "")
    end,
    friend_on_other_layer_fires_relation = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      local rel = record(ns, "LAYER_RELATION")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lk = "222", zn = "Elwynn Forest" })
      A.eq(#rel, 1); A.eq(rel[1], { "Frostie", "unknown", "different" })
      A.eq(ns.Layer.relationOf("Frostie"), "different")
      receive(ns, W, "Frostie", "UPDATE", { lk = "111" })
      A.eq(#rel, 2); A.eq(rel[2], { "Frostie", "different", "same" })
      A.eq(ns.Layer.relationOf("Nobody"), "unknown")
      A.eq(ns.Log.errors(10), {})
    end,
    my_key_change_updates_relations = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lk = "222", zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
      local rel = record(ns, "LAYER_RELATION")
      seeMouseover(W, "Creature-0-1-0-222-299-01")
      W:advance(2)
      A.eq(rel, { { "Frostie", "unknown", "same" } })
    end,
    unknown_never_becomes_different = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      receive(ns, W, "Frostie", "STATE", { lk = "222", zn = "Westfall" })
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
      receive(ns, W, "Frostie", "UPDATE", { zn = "Elwynn Forest", ins = "1" })
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
    end,
    offline_friend_becomes_unknown = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      receive(ns, W, "Frostie", "STATE", { lk = "222", zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "different")
      local rel = record(ns, "LAYER_RELATION")
      W:advance(ns.Config.OFFLINE_AFTER + ns.Config.OFFLINE_TICK + 1)
      A.eq(rel, { { "Frostie", "different", "unknown" } })
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
    end,
    layer_module_off_means_unknown = function(ns, A, W)
      start(ns, W)
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      receive(ns, W, "Frostie", "STATE", { lk = "222", zn = "Elwynn Forest" })
      A.eq(ns.Layer.relationOf("Frostie"), "different")
      ns.Modules.setEnabled("layer", false)
      A.eq(ns.Layer.relationOf("Frostie"), "unknown")
      local rel = record(ns, "LAYER_RELATION")
      receive(ns, W, "Frostie", "UPDATE", { lk = "111" })
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
