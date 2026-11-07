-- Pop-ups (module "popups"), the pure rules in PopupLogic, and the two "coming later" extras.

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

local function seeMouseover(W, guid)
  W.state.guids.mouseover = guid
  for _ = 1, 2 do W:fire("UPDATE_MOUSEOVER_UNIT") end
end

-- A friend in our group standing 10 yards away; visible = on our layer. These tests check pop-up timing, so a
-- hidden friend counts as "different" at once (the 8 s wait is tested in test_layer).
local SLOTS = { Frostie = "party1", Ginkan = "party2" }
local function nearby(ns, W, name, visible)
  ns.Config.LAYER_HIDDEN_FOR = 0
  W.state.pos = { x = 0, y = 0, instance = 1 }
  W.state.units[SLOTS[name]] = { name = name, player = true, visible = visible, pos = { x = 10, y = 0, instance = 1 } }
end

local function look(W) W:fire("NAME_PLATE_UNIT_ADDED", "nameplate40") end -- makes the layer module look now

-- Past the login quiet period, with Frostie online in our group, next to us and visible (same layer).
local function ready(ns, W)
  start(ns, W)
  nearby(ns, W, "Frostie", true)
  receive(ns, W, "Frostie", "STATE", { cl = "MAGE", zn = "Elwynn Forest" })
  W:advance(31)
end

local function frostieMoves(ns, W)
  W.state.units.party1.visible = false
  look(W)
end

local function frostieBack(ns, W)
  W.state.units.party1.visible = true
  look(W)
end

-- Texts of the layer pop-ups shown so far, in order.
local function layerShows(ns)
  local out = {}
  for _, t in ipairs(ns.Popups.shownForTest()) do
    if t:find("layer", 1, true) then out[#out + 1] = t end
  end
  return out
end

return {
  files = "toc",
  tests = {
    text_copy = function(ns, A)
      local P = ns.PopupLogic
      A.eq(P.text("layer_diff", { "Frostie" }), "Frostie is on a different layer")
      A.eq(select(2, P.text("layer_diff", { "Frostie" })), "Click to invite them to your group")
      A.eq(P.text("layer_diff", { "A", "B" }), "A and B are on a different layer")
      A.eq(P.text("layer_diff", { "A", "B", "C" }), "3 friends are on a different layer")
      A.eq(P.text("layer_same", { "A" }), "A is back on your layer")
      A.eq(P.text("layer_same", { "A", "B" }), "A and B are back on your layer")
      A.eq(P.text("layer_same", { "A", "B", "C" }), "3 friends are back on your layer")
      A.no(select(2, P.text("layer_same", { "A" })))
      A.eq({ P.text("death", { "Holyboi" }, { zone = "Westfall", subzone = "Jangolode Mine" }) },
        { "Holyboi died", "Westfall, Jangolode Mine" })
      A.eq({ P.text("death", { "Holyboi" }, { zone = "Westfall" }) }, { "Holyboi died", "Westfall" })
      A.eq({ P.text("death", { "Holyboi" }, {}) }, { "Holyboi died" })
      A.eq(P.text("layer_diff", { "A" }, nil, function(n) return "<" .. n .. ">" end), "<A> is on a different layer")
    end,
    combines_within_window = function(ns, A)
      local pl = ns.PopupLogic.new({ combineWindow = 3, quietUntil = 0 })
      pl:push("layer_diff", "A", 0); pl:push("layer_diff", "B", 1)
      A.eq(pl:due(2), {})
      local d = pl:due(3)
      A.eq(#d, 1); A.eq(d[1].kind, "layer_diff"); A.eq(d[1].names, { "A", "B" }); A.eq(d[1].invite, { "A", "B" })
      A.eq(pl:due(10), {})
    end,
    diff_then_same_cancels = function(ns, A)
      local pl = ns.PopupLogic.new({ combineWindow = 3, quietUntil = 0 })
      pl:push("layer_diff", "A", 0); pl:push("layer_same", "A", 1)
      A.eq(pl:due(4), {})
      pl:push("layer_same", "B", 5); pl:push("layer_diff", "B", 6)
      A.eq(pl:due(9), {})
    end,
    same_has_no_invite_list = function(ns, A)
      local pl = ns.PopupLogic.new({ combineWindow = 3, quietUntil = 0 })
      pl:push("layer_same", "A", 0)
      local d = pl:due(3)
      A.eq(d[1].names, { "A" }); A.no(d[1].invite)
    end,
    deaths_are_immediate_and_separate = function(ns, A)
      local pl = ns.PopupLogic.new({ combineWindow = 3, quietUntil = 0 })
      pl:push("death", "A", 0, { zone = "Westfall" }); pl:push("death", "B", 0, { zone = "Duskwood" })
      local d = pl:due(0)
      A.eq(#d, 2); A.eq(d[1].names, { "A" }); A.eq(d[2].extra.zone, "Duskwood")
      A.eq(pl:due(1), {})
    end,
    quiet_drops_then_summarizes = function(ns, A)
      local pl = ns.PopupLogic.new({ combineWindow = 3, quietUntil = 30 })
      pl:push("layer_diff", "A", 5); pl:push("death", "B", 5, {})
      A.eq(pl:due(40), {})
      local p = pl:endQuiet({ "A", "B", "C" })
      A.eq(p.kind, "layer_diff"); A.eq(p.names, { "A", "B", "C" }); A.eq(p.invite, { "A", "B", "C" })
      A.no(pl:endQuiet({}))
    end,
    popups_end_to_end = function(ns, A, W)
      ready(ns, W)
      A.eq(ns.Popups.visibleCount(), 0)
      frostieMoves(ns, W)
      W:advance(2)
      A.eq(ns.Popups.visibleCount(), 0)   -- still inside the 3 s combine window
      W:advance(2)
      A.eq(ns.Popups.visibleCount(), 1)
      A.eq(ns.Popups.textsForTest()[1].text, "Frostie is on a different layer")
      A.eq(ns.Popups.textsForTest()[1].subtext, "Click to invite them to your group")
      ns.Popups.clickForTest(1)
      A.eq(W.invites, { "Frostie" })
      A.eq(ns.Popups.visibleCount(), 0)
      A.eq(ns.Log.errors(10), {})
    end,
    back_on_my_layer_text = function(ns, A, W)
      ready(ns, W)
      frostieMoves(ns, W); W:advance(4)
      ns.Popups.clickForTest(1)
      frostieBack(ns, W); W:advance(4)
      A.eq(ns.Popups.textsForTest()[1].text, "Frostie is back on your layer")
      A.no(ns.Popups.textsForTest()[1].subtext)
    end,
    batch_drops_friends_no_longer_on_another_layer = function(ns, A, W)
      ready(ns, W)
      frostieMoves(ns, W)
      W:advance(1)
      receive(ns, W, "Frostie", "UPDATE", { zn = "Westfall" })   -- can't compare any more: unknown, not "back"
      W:advance(4)
      A.eq(ns.Popups.visibleCount(), 0)
      A.eq(layerShows(ns), {})
    end,
    different_unknown_different_shows_once = function(ns, A, W)
      ready(ns, W)
      frostieMoves(ns, W); W:advance(4)
      receive(ns, W, "Frostie", "UPDATE", { zn = "Westfall" }); W:advance(1)
      receive(ns, W, "Frostie", "UPDATE", { zn = "Elwynn Forest" }); W:advance(4)
      A.eq(ns.Layer.relationOf("Frostie"), "different")
      A.eq(layerShows(ns), { "Frostie is on a different layer" })
    end,
    different_same_different_shows_each = function(ns, A, W)
      ready(ns, W)
      frostieMoves(ns, W); W:advance(4)
      frostieBack(ns, W); W:advance(4)
      frostieMoves(ns, W); W:advance(4)
      A.eq(layerShows(ns), { "Frostie is on a different layer", "Frostie is back on your layer",
        "Frostie is on a different layer" })
    end,
    summary_counts_as_announced = function(ns, A, W)
      start(ns, W)
      nearby(ns, W, "Frostie", false)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      W:advance(25)
      A.eq(layerShows(ns), { "Frostie is on a different layer" })
      receive(ns, W, "Frostie", "UPDATE", { zn = "Westfall" }); W:advance(1)
      receive(ns, W, "Frostie", "UPDATE", { zn = "Elwynn Forest" }); W:advance(4)
      A.eq(layerShows(ns), { "Frostie is on a different layer" })
    end,
    offline_and_back_announces_again = function(ns, A, W)
      ready(ns, W)
      frostieMoves(ns, W); W:advance(4)
      receive(ns, W, "Frostie", "BYE", {}); W:advance(1)
      receive(ns, W, "Frostie", "HELLO", { ver = "0.1.0" })
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" }); W:advance(4)
      A.eq(layerShows(ns), { "Frostie is on a different layer", "Frostie is on a different layer" })
    end,
    invite_skips_people_already_in_group = function(ns, A, W)
      ready(ns, W)
      W.state.groupMembers = { "Frostie" }
      frostieMoves(ns, W); W:advance(4)
      ns.Popups.clickForTest(1)
      A.eq(W.invites, {})
    end,
    popup_expires_after_seconds = function(ns, A, W)
      ready(ns, W)
      ns.Bus.fire("MEMBER_DIED", "Frostie", "Westfall", "Jangolode Mine")
      W:advance(0.5)
      A.eq(ns.Popups.visibleCount(), 1)
      A.eq(ns.Popups.textsForTest()[1], { text = "Frostie died", subtext = "Westfall, Jangolode Mine" })
      W:advance(5)
      A.eq(ns.Popups.visibleCount(), 1)
      W:advance(1.5)
      A.eq(ns.Popups.visibleCount(), 0)
    end,
    level_up_text_and_fun_line = function(ns, A)
      local P = ns.PopupLogic
      A.eq({ P.text("levelup", { "Frostie" }, { level = 13, maxLevel = 60 }) },
        { "Frostie reached level 13!", "Only 47 to go." })
      A.eq({ P.text("levelup", { "Frostie" }, { level = 59, maxLevel = 60 }) }, { "Frostie reached level 59!",
        "One more to go!" })
      A.eq({ P.text("levelup", { "Frostie" }, { level = 60, maxLevel = 60 }) }, { "Frostie reached level 60!",
        "Max level. GG!" })
      A.eq({ P.text("levelup", { "Frostie" }, {}) }, { "Frostie leveled up!" })
      A.eq(P.text("levelup", { "F" }, { level = 13 }, function(n) return "<" .. n .. ">" end), "<F> reached level 13!")
    end,
    level_up_logic_respects_quiet_time = function(ns, A)
      local pl = ns.PopupLogic.new({ combineWindow = 3, quietUntil = 30 })
      pl:push("levelup", "Frostie", 10, { level = 13 })
      A.eq(pl:due(31), {}, "dropped in the quiet time")
      pl:push("levelup", "Frostie", 40, { level = 14 })
      pl:push("levelup", "Ginkan", 40, { level = 20 })
      local d = pl:due(40)
      A.eq(#d, 2, "one pop-up each, right away")
      A.eq(d[1].kind, "levelup"); A.eq(d[1].names, { "Frostie" }); A.eq(d[1].extra.level, 14)
    end,
    ding_pop_up_for_a_friend = function(ns, A, W)
      ready(ns, W)
      receive(ns, W, "Frostie", "UPDATE", { lv = "12" })
      W:advance(1)
      A.eq(ns.Popups.visibleCount(), 0)
      receive(ns, W, "Frostie", "UPDATE", { lv = "13" })
      W:advance(1)
      A.eq(ns.Popups.textsForTest(), { { text = "Frostie reached level 13!", subtext = "Only 47 to go." } })
      A.eq(W.sounds, {}, "no sound by default")
      ns.Modules.set("popups", "sound", true)
      receive(ns, W, "Frostie", "UPDATE", { lv = "14" })
      W:advance(1)
      A.eq(W.sounds, {}, "the general pop-up sound is not the ding sound")
      ns.Modules.set("popups", "levelUpSound", true)
      receive(ns, W, "Frostie", "UPDATE", { lv = "15" })
      W:advance(1)
      A.eq(W.sounds, { 888 }, "the game's level-up sound")
      ns.Modules.set("popups", "levelUp", false)
      receive(ns, W, "Frostie", "UPDATE", { lv = "16" })
      W:advance(1)
      A.eq(#ns.Popups.shownForTest(), 3, "no pop-up with Level-ups off (13, 14 and 15 only)")
      A.eq(ns.Log.errors(10), {})
    end,
    no_ding_in_the_login_quiet_time = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12" })
      receive(ns, W, "Frostie", "UPDATE", { lv = "13" })
      W:advance(40)
      for _, t in ipairs(ns.Popups.shownForTest()) do A.no(t:find("reached", 1, true), t) end
    end,
    popups_settings_in_order = function(ns, A)
      local d = ns.Modules.get("popups")
      local keys = {}
      for i, s in ipairs(d.settings) do keys[i] = s.key end
      A.eq(keys, { "layerDiff", "layerSame", "death", "levelUp", "levelUpSound", "sound", "seconds" })
      A.eq(d.defaults.levelUp, true); A.eq(d.defaults.levelUpSound, false)
      for _, s in ipairs(d.settings) do if s.key == "levelUpSound" then A.eq(s.parent, "levelUp") end end
    end,
    sound_off_by_default = function(ns, A, W)
      ready(ns, W)
      ns.Bus.fire("MEMBER_DIED", "Frostie", "Westfall", "")
      W:advance(0.5)
      A.eq(W.sounds, {})
      ns.Modules.set("popups", "sound", true)
      ns.Bus.fire("MEMBER_DIED", "Holyboi", "Westfall", "")
      ns.Bus.fire("MEMBER_DIED", "Pewpew", "Westfall", "")
      W:advance(0.5)
      A.eq(W.sounds, { 8959 })   -- once per batch, not per pop-up
    end,
    setting_off_suppresses = function(ns, A, W)
      ready(ns, W)
      ns.Modules.set("popups", "death", false)
      ns.Bus.fire("MEMBER_DIED", "Frostie", "Westfall", "")
      W:advance(1)
      A.eq(ns.Popups.visibleCount(), 0)
      ns.Modules.set("popups", "layerDiff", false)
      frostieMoves(ns, W); W:advance(4)
      A.eq(ns.Popups.visibleCount(), 0)
    end,
    quiet_period_then_one_summary = function(ns, A, W)
      start(ns, W)
      nearby(ns, W, "Frostie", false)
      nearby(ns, W, "Ginkan", false)
      receive(ns, W, "Frostie", "STATE", { zn = "Elwynn Forest" })
      receive(ns, W, "Ginkan", "STATE", { zn = "Elwynn Forest" })
      ns.Bus.fire("MEMBER_DIED", "Holyboi", "Westfall", "")
      W:advance(10)
      A.eq(ns.Popups.visibleCount(), 0)
      W:advance(15)   -- start() already spent 6 s: now past the 30 s quiet period
      A.eq(ns.Popups.visibleCount(), 1)
      A.eq(ns.Popups.textsForTest()[1].text, "Frostie and Ginkan are on a different layer")
    end,
    at_most_popup_max_frames = function(ns, A, W)
      ready(ns, W)
      for i = 1, ns.Config.POPUP_MAX + 3 do ns.Bus.fire("MEMBER_DIED", "Friend" .. i, "Westfall", "") end
      W:advance(0.5)
      A.eq(ns.Popups.visibleCount(), ns.Config.POPUP_MAX)
      local t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "Friend" .. (ns.Config.POPUP_MAX + 3) .. " died")   -- the oldest were replaced
    end,
    module_off_hides_and_drops = function(ns, A, W)
      ready(ns, W)
      ns.Bus.fire("MEMBER_DIED", "Frostie", "Westfall", "")
      W:advance(0.5)
      frostieMoves(ns, W)
      ns.Modules.setEnabled("popups", false)
      A.eq(ns.Popups.visibleCount(), 0)
      ns.Modules.setEnabled("popups", true)
      W:advance(5)
      A.eq(ns.Popups.visibleCount(), 0)   -- the pending layer pop-up was dropped
    end,
    names_from_others_are_escaped = function(ns, A, W)
      ready(ns, W)
      ns.Bus.fire("MEMBER_DIED", "Bad|cffff0000Name", "Zone|r", "")
      W:advance(0.5)
      local t = ns.Popups.textsForTest()[1]
      A.contains(t.text, "Bad||cffff0000Name")
      A.eq(t.subtext, "Zone||r")
    end,
    extras_are_coming_later = function(ns, A)
      for _, id in ipairs({ "pokes", "races" }) do
        local d = ns.Modules.get(id)
        A.eq(d.tier, "extra"); A.ok(d.comingSoon); A.eq(d.defaultEnabled, false)
        A.no(ns.Modules.isEnabled(id))
        A.eq(#d.settings, 0)
      end
      A.eq(ns.Modules.get("pokes").name, "Pokes & soundboard")
      A.eq(ns.Modules.get("races").name, "Group races")
    end,
  },
}
