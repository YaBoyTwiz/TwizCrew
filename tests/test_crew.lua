local function start(ns, W)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  ns.Crew.start()
  ns.Self.start()
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
  return db
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- decoded messages sent since index `from`
local function sentSince(ns, W, from)
  local out = {}
  for i = from + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg then out[#out + 1] = msg end
  end
  return out
end

local function record(ns, name)
  local log = {}
  ns.Bus.on("test", name, function(...) log[#log + 1] = { ... } end)
  return log
end

local function noErrors(ns, A) A.eq(ns.Log.errors(10), {}) end

return {
  files = "toc",
  tests = {
    tags_detect_and_encode = function(ns, A, W)
      W.state.dead = true; W.state.afk = true
      A.eq(ns.Tags.encode(ns.Tags.detectSelf()), "DEAD,AFK")
      A.eq(ns.Tags.decode("AFK,BOGUS,DEAD"), { AFK = true, DEAD = true })
      W.state.inInstance = true; W.state.instanceType = "party"
      A.ok(ns.Tags.detectSelf().DUNGEON)
      W.state.instanceType = "pvp"
      A.no(ns.Tags.detectSelf().DUNGEON)
      A.no(ns.Tags.detectSelf().LAYER)
      A.eq(ns.Tags.ordered({ AFK = true, DEAD = true, COMBAT = true }), { "DEAD", "COMBAT", "AFK" })
    end,
    tags_module_is_registered = function(ns, A)
      local d = ns.Modules.get("tags")
      A.ok(d); A.eq(d.name, "Activity tags")
      for _, id in ipairs(ns.Tags.ORDER) do
        A.ok(ns.Tags.LABEL[id]); A.ok(ns.Tags.COLOR[id]); A.ok(ns.Tags.INFO[id])
      end
    end,
    self_diff_only_changes = function(ns, A)
      A.eq(ns.Self.diff({ zn = "A", lv = "10" }, { zn = "B", lv = "10", st = "" }), { zn = "B", st = "" })
    end,
    login_sends_hello_then_state = function(ns, A, W)
      start(ns, W)
      local msgs = sentSince(ns, W, 0)
      A.eq(msgs[1].type, "HELLO")
      A.eq(msgs[1].fields.ver, "0.1.0")
      A.eq(msgs[2].type, "STATE")
      A.eq(msgs[2].fields.cl, "WARRIOR")
      A.eq(msgs[2].fields.zn, "Elwynn Forest")
      A.eq(msgs[2].fields.ins, "0")
      A.eq(msgs[2].fields.xp, "0")
      noErrors(ns, A)
    end,
    xp_sends_on_whole_percent_only = function(ns, A, W)
      start(ns, W)
      W.state.xp = 10
      ns.Self.refresh("test"); W:advance(2)
      local n = #W.sent
      W.state.xp = 10.4
      ns.Self.refresh("test"); W:advance(2)
      A.eq(#W.sent, n)
      W.state.xp = 11
      ns.Self.refresh("test"); W:advance(2)
      local msgs = sentSince(ns, W, n)
      -- the exact XP rides along with the percent (level progress)
      A.eq(#msgs, 1); A.eq(msgs[1].type, "UPDATE"); A.eq(msgs[1].fields, { xp = "11", xc = "11" })
    end,
    self_sends_raw_xp_numbers = function(ns, A, W)
      W.state.level, W.state.xp, W.state.xpMax, W.state.rested = 12, 637.9, 1000, 500
      local f = ns.Self.gather()
      A.eq({ f.lv, f.xp, f.xc, f.xm, f.rx }, { "12", "63", "637", "1000", "500" })
      W.state.rested = nil
      A.eq(ns.Self.gather().rx, "0", "no rested XP")
      W.state.missing.GetXPExhaustion = true
      A.eq(ns.Self.gather().rx, "0", "no way to read rested XP")
    end,
    max_level_sends_zero_need = function(ns, A, W)
      W.state.level, W.state.xp, W.state.xpMax, W.state.rested = 60, 0, 0, 900
      local f = ns.Self.gather()
      A.eq({ f.xc, f.xm, f.rx, f.xp }, { "0", "0", "0", "0" })
      -- at the max level some games still answer an XP max: the level decides
      W.state.xp, W.state.xpMax = 5, 209800
      f = ns.Self.gather()
      A.eq({ f.xc, f.xm }, { "0", "0" })
      W.state.missing.GetMaxPlayerLevel = true
      A.eq(ns.Self.gather().xm, "209800", "without GetMaxPlayerLevel only XP max 0 means max level")
    end,
    secret_xp_keeps_what_was_sent = function(ns, A, W)
      start(ns, W)
      W.state.xp, W.state.xpMax = 40, 100
      ns.Self.refresh("test"); W:advance(2)
      W.state.xp = 55
      W.state.secret[55] = true
      local f = ns.Self.gather()
      A.eq({ f.xp, f.xc, f.xm }, { "40", "40", "100" }, "a secret value counts as unknown")
      noErrors(ns, A)
    end,
    xp_detail_alone_sends_nothing_and_rides_along = function(ns, A, W)
      start(ns, W)
      W.state.xp, W.state.xpMax, W.state.rested = 100, 1000, 300
      ns.Self.refresh("test"); W:advance(2)
      local n = #W.sent
      W.state.xp, W.state.rested = 104, 296    -- still 10%: only xc and rx change
      W:fire("PLAYER_XP_UPDATE"); W:advance(2)
      A.eq(#W.sent, n, "no message for a change in xc / rx alone")
      W.state.combat = true                   -- a fight starts: the FIGHTING tag goes out, xc and rx with it
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(2)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 1)
      A.eq(msgs[1].fields, { tg = "COMBAT", xc = "104", rx = "296" })
      noErrors(ns, A)
    end,
    level_up_sends_level_and_numbers_together = function(ns, A, W)
      start(ns, W)
      W.state.xp, W.state.xpMax = 950, 1000
      ns.Self.refresh("test"); W:advance(2)
      local n = #W.sent
      W.state.level, W.state.xp, W.state.xpMax = 11, 30, 1200
      W:fire("PLAYER_LEVEL_UP"); W:fire("PLAYER_XP_UPDATE"); W:advance(2)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 1)
      A.eq(msgs[1].fields, { lv = "11", xm = "1200", xc = "30", xp = "2" })
      -- lv, xm and xc lead the message, right after the zone / layer / session keys
      A.contains(W.sent[#W.sent].text, "^lv=11~xm=1200~xc=30~")
    end,
    longest_state_with_xp_numbers_fits = function(ns, A, W)
      start(ns, W)
      W.state.zone, W.state.subzone = string.rep("Z", 120), string.rep("S", 120)
      W.state.level, W.state.xp, W.state.xpMax, W.state.rested = 59, 9999998, 9999999, 9999999
      W.state.dead, W.state.combat, W.state.afk = true, true, true
      W.state.inInstance, W.state.instanceType = true, "party"
      ns.db.myStatus = string.rep("^", 40)
      local f = ns.Self.gather()
      f.lk = "123456789"
      local merged = {}
      local texts = ns.Codec.encode("STATE", f)
      for _, text in ipairs(texts) do
        A.ok(#text <= 255, "piece of " .. #text)
        for k, v in pairs(ns.Codec.decode(text).fields) do merged[k] = v end
      end
      A.eq(merged, f, "every field arrives whole")
      -- with a normal zone name the level and XP numbers all travel in the first piece
      W.state.zone, W.state.subzone = "Stranglethorn Vale", "The Crystal Shore"
      f = ns.Self.gather()
      f.lk = "123456789"
      local first = ns.Codec.decode(ns.Codec.encode("STATE", f)[1]).fields
      A.eq({ first.lv, first.xm, first.xc, first.rx }, { "59", "9999999", "9999998", "9999999" })
    end,
    xp_zero_max_gives_zero = function(ns, A, W)
      start(ns, W)
      W.state.xpMax = 0; W.state.xp = 5
      A.eq(ns.Self.gather().xp, "0")
    end,
    zone_change_sends_one_update = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      local seen = record(ns, "SELF_UPDATED")
      W.state.zone = "Westfall"
      W:fire("ZONE_CHANGED_NEW_AREA"); W:fire("ZONE_CHANGED")
      W:advance(2)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 1); A.eq(msgs[1].type, "UPDATE"); A.eq(msgs[1].fields, { zn = "Westfall" })
      A.eq(#seen, 1); A.eq(seen[1][1], { zn = "Westfall" })
      noErrors(ns, A)
    end,
    nothing_changed_sends_nothing = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      W:fire("ZONE_CHANGED"); W:advance(2)
      A.eq(#W.sent, n)
    end,
    hello_and_state_carry_restart_since = function(ns, A, W)
      start(ns, W)
      local hello, state
      for _, m in ipairs(sentSince(ns, W, 0)) do
        if m.type == "HELLO" then hello = m.fields elseif m.type == "STATE" then state = state or m.fields end
      end
      A.eq(hello, { ver = "0.1.0", rs = "0.1.0" })
      A.eq(state.rs, "0.1.0")
      A.eq(ns.Self.gather().rs, "0.1.0")
      -- the longest STATE still fits in 255-byte pieces, and ver and rs arrive
      W.state.zone, W.state.subzone = string.rep("Z", 120), string.rep("S", 120)
      ns.db.myStatus = string.rep("^", 40)
      local f = ns.Self.gather()
      local merged = {}
      for _, text in ipairs(ns.Codec.encode("STATE", f)) do
        A.ok(#text <= 255, "piece of " .. #text)
        for k, v in pairs(ns.Codec.decode(text).fields) do merged[k] = v end
      end
      A.eq(merged.rs, "0.1.0"); A.eq(merged.ver, "0.1.0")
    end,
    restart_since_reaches_the_version_check = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "HELLO", { ver = "0.2.0", rs = "0.2.0" })
      A.eq(ns.Version.newest(), { name = "Frostie", ver = "0.2.0", rs = "0.2.0" })
      A.eq(ns.roster:get("Frostie").restartSince, "0.2.0")
      -- a long STATE split in two pieces: rs in one, ver in the other, still put together
      receive(ns, W, "Ginkan", "STATE", { rs = "0.2.0", cl = "MAGE" })
      receive(ns, W, "Ginkan", "UPDATE", { ver = "0.3.0" })
      A.eq(ns.Version.newest(), { name = "Ginkan", ver = "0.3.0", rs = "0.2.0" })
      -- an old copy says HELLO without rs: what we knew is forgotten
      receive(ns, W, "Ginkan", "HELLO", { ver = "0.3.0" })
      A.eq(ns.roster:get("Ginkan").restartSince, "")
      noErrors(ns, A)
    end,
    friend_level_up_fires_once = function(ns, A, W)
      start(ns, W)
      local ups = record(ns, "MEMBER_LEVELUP")
      receive(ns, W, "Ginkan", "STATE", { cl = "MAGE", lv = "12", xc = "900", xm = "1000" })
      A.eq(#ups, 0, "first state")
      receive(ns, W, "Ginkan", "UPDATE", { lv = "13", xm = "1100", xc = "20" })
      A.eq(ups, { { "Ginkan", 13 } })
      receive(ns, W, "Ginkan", "UPDATE", { xc = "80" })
      receive(ns, W, "Ginkan", "HELLO", { ver = "0.1.0" })
      receive(ns, W, "Ginkan", "STATE", { lv = "14" })
      A.eq(#ups, 1, "no ding for the state after a HELLO")
      noErrors(ns, A)
    end,
    taxi_shows_flight_path_text = function(ns, A, W)
      start(ns, W)
      W.state.taxi = true
      local f = ns.Self.gather()
      A.eq(f.sz, "On a flight path"); A.eq(f.tg, "TAXI")
    end,
    setStatus_trims_and_caps = function(ns, A, W)
      local db = start(ns, W)
      ns.Self.setStatus("  " .. string.rep("é", 50) .. "  ")
      A.eq(db.myStatus, string.rep("é", 40))
      local n = #W.sent
      W:advance(2)
      local msgs = sentSince(ns, W, n - 0)
      A.eq(msgs[#msgs].fields.st, string.rep("é", 40))
    end,
    -- Found in game (WoW Forever): our own party/whisper messages came back from "Yaboytwiz Noodledog" (name plus
    -- realm, space-separated), so the copy put itself on its own crew list and showed itself as offline.
    own_echo_with_realm_is_ignored = function(ns, A, W)
      start(ns, W)
      for _, from in ipairs({ "Twiz Noodledog", "Twiz-Noodledog", "Twiz-Realm", "twiz" }) do
        for _, text in ipairs(ns.Codec.encode("HELLO", { ver = "0.1.0" })) do
          W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "PARTY", from)
        end
        A.eq(ns.roster:get(from), nil)
      end
      A.eq(next(ns.roster.byName), nil)
      noErrors(ns, A)
    end,
    friend_names_lose_their_realm = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Ginkan Noodledog", "HELLO", { ver = "0.1.0" })
      receive(ns, W, "Frostie-Noodledog", "HELLO", { ver = "0.1.0" })
      A.ok(ns.roster:get("Ginkan") ~= nil)
      A.ok(ns.roster:get("Frostie") ~= nil)
      A.eq(ns.roster:get("Ginkan Noodledog"), nil)
      noErrors(ns, A)
    end,
    saved_ghost_of_self_is_removed = function(ns, A, W)
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster["Twiz Noodledog"] = { name = "Twiz Noodledog", level = 6 }
      db.roster["Ginkan Noodledog"] = { name = "Ginkan Noodledog", level = 9 }
      ns.db = db
      ns.Modules.attach(db)
      ns.Comm.start()
      ns.Crew.start()
      A.eq(db.roster["Twiz Noodledog"], nil)
      A.eq(db.roster["Ginkan Noodledog"], nil)
      A.eq(db.roster["Ginkan"].name, "Ginkan")
      A.eq(ns.roster:get("Twiz Noodledog"), nil)
      A.ok(ns.roster:get("Ginkan") ~= nil)
      noErrors(ns, A)
    end,
    hello_gets_jittered_state_reply = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      receive(ns, W, "Ginkan", "HELLO", { ver = "0.1.0" })
      A.eq(#W.sent, n)
      W:advance(0.2)
      A.eq(#W.sent, n)
      W:advance(5)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 1); A.eq(msgs[1].type, "STATE")
      noErrors(ns, A)
    end,
    hello_burst_gets_one_reply = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      for i = 1, 3 do
        receive(ns, W, "Ginkan", "HELLO", { ver = "0.1." .. i })
        W:advance(0.1)
      end
      W:advance(8)
      local states = 0
      for _, m in ipairs(sentSince(ns, W, n)) do if m.type == "STATE" then states = states + 1 end end
      A.eq(states, 1)
    end,
    hellos_from_many_friends_get_one_state = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      for _, name in ipairs({ "A1", "B2", "C3", "D4", "E5" }) do
        receive(ns, W, name, "HELLO", { ver = "0.1.0" })
        W:advance(0.2)
      end
      W:advance(8)
      local states = 0
      for _, m in ipairs(sentSince(ns, W, n)) do if m.type == "STATE" then states = states + 1 end end
      A.eq(states, 1)
      A.ok(ns.roster:get("E5"))
    end,
    pings_from_many_strangers_get_one_hello = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      for _, name in ipairs({ "S1", "S2", "S3" }) do
        receive(ns, W, name, "PING", {})
        W:advance(1)
      end
      W:advance(2)
      local hellos = 0
      for _, m in ipairs(sentSince(ns, W, n)) do if m.type == "HELLO" then hellos = hellos + 1 end end
      A.eq(hellos, 1)
    end,
    state_from_friend_fills_roster_and_fires = function(ns, A, W)
      start(ns, W)
      local upd, on = record(ns, "MEMBER_UPDATED"), record(ns, "MEMBER_ONLINE")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lv = "12", zn = "Elwynn Forest", tg = "" })
      local m = ns.roster:get("Frostie")
      A.eq(m.class, "MAGE"); A.eq(m.level, 12)
      A.eq(#upd, 1); A.eq(upd[1][1], "Frostie"); A.ok(upd[1][2].class)
      A.eq(#on, 1); A.eq(on[1][1], "Frostie")
      noErrors(ns, A)
    end,
    friend_death_fires_MEMBER_DIED_with_place = function(ns, A, W)
      start(ns, W)
      local died = record(ns, "MEMBER_DIED")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", zn = "Elwynn Forest", sz = "Goldshire", tg = "" })
      A.eq(#died, 0)
      W:advance(3)
      receive(ns, W, "Frostie", "UPDATE", { tg = "DEAD" })
      A.eq(#died, 1)
      A.eq(died[1], { "Frostie", "Elwynn Forest", "Goldshire" })
    end,
    version_is_passed_on_if_present = function(ns, A, W)
      start(ns, W)
      local seen = {}
      ns.Version = { seen = function(name, ver) seen[#seen + 1] = { name, ver } end }
      receive(ns, W, "Frostie", "STATE", { ver = "0.2.0" })
      A.eq(seen, { { "Frostie", "0.2.0" } })
    end,
    ping_from_stranger_triggers_hello = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      receive(ns, W, "Stranger", "PING", {})
      W:advance(2)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 1); A.eq(msgs[1].type, "HELLO")
      -- a second ping soon after does not make us send again
      W:advance(5)
      n = #W.sent
      W:advance(1)
      receive(ns, W, "Stranger", "PING", { x = "1" })
      W:advance(2)
      for _, m in ipairs(sentSince(ns, W, n)) do A.no(m.type == "HELLO") end
    end,
    ping_from_known_member_marks_online = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(200)
      A.no(ns.roster:get("Frostie").online)
      local on = record(ns, "MEMBER_ONLINE")
      local n = #W.sent
      receive(ns, W, "Frostie", "PING", {})
      A.ok(ns.roster:get("Frostie").online)
      A.eq(#on, 1)
      W:advance(2)
      for _, m in ipairs(sentSince(ns, W, n)) do A.no(m.type == "HELLO") end
    end,
    silence_marks_offline = function(ns, A, W)
      start(ns, W)
      local off = record(ns, "MEMBER_OFFLINE")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(200)
      A.eq(#off, 1); A.eq(off[1][1], "Frostie")
      A.no(ns.roster:get("Frostie").online)
    end,
    bye_marks_offline_now = function(ns, A, W)
      start(ns, W)
      local off = record(ns, "MEMBER_OFFLINE")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Frostie", "BYE", {})
      A.eq(#off, 1)
      A.no(ns.roster:get("Frostie").online)
    end,
    hello_starts_a_fresh_session = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", lk = "111", ins = "1", tg = "AFK", zn = "Elwynn Forest" })
      local upd = record(ns, "MEMBER_UPDATED")
      receive(ns, W, "Frostie", "HELLO", { ver = "0.1.0" })
      local m = ns.roster:get("Frostie")
      A.eq(m.layerKey, nil); A.eq(m.inInstance, false); A.eq(m.tags, nil)
      A.eq(m.class, "MAGE"); A.eq(m.zone, "Elwynn Forest")
      A.ok(upd[1] and upd[1][2].layerKey, "the cleared layer key is reported as a change")
    end,
    bye_forgets_layer_key = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lk = "111", zn = "Elwynn Forest" })
      receive(ns, W, "Frostie", "BYE", {})
      A.eq(ns.roster:get("Frostie").layerKey, nil)
    end,
    full_state_tells_the_rest_of_the_addon = function(ns, A, W)
      start(ns, W)
      local upd = record(ns, "SELF_UPDATED")
      W.state.level = 11
      local full = ns.Self.fullState()
      A.eq(full.lv, "11")
      A.eq(upd, { { { lv = "11" } } })
      ns.Self.fullState()
      A.eq(#upd, 1, "nothing changed: no event")
    end,
    ping_ticker_sends_ping = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      W:advance(61)
      local pings = 0
      for _, m in ipairs(sentSince(ns, W, n)) do if m.type == "PING" then pings = pings + 1 end end
      A.ok(pings >= 1)
    end,
    logout_sends_bye_directly = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      W:fire("PLAYER_LOGOUT")
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 1); A.eq(msgs[1].type, "BYE")
    end,
  },
}
