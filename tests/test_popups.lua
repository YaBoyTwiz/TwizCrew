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

-- Past the login quiet period, standing on layer 111, with Frostie online on the same layer.
local function ready(ns, W)
  start(ns, W)
  seeMouseover(W, "Creature-0-1-0-111-299-01")
  receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lk = "111", zn = "Elwynn Forest" })
  W:advance(31)
end

local function frostieMoves(ns, W)
  receive(ns, W, "Frostie", "UPDATE", { lk = "222" })
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
      receive(ns, W, "Frostie", "UPDATE", { lk = "111" }); W:advance(4)
      A.eq(ns.Popups.textsForTest()[1].text, "Frostie is back on your layer")
      A.no(ns.Popups.textsForTest()[1].subtext)
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
      seeMouseover(W, "Creature-0-1-0-111-299-01")
      receive(ns, W, "Frostie", "STATE", { lk = "222", zn = "Elwynn Forest" })
      receive(ns, W, "Ginkan", "STATE", { lk = "333", zn = "Elwynn Forest" })
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
