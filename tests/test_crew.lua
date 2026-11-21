-- db: saved data to start with (already attached), else a fresh one
local function start(ns, W, db)
  if not db then
    db = ns.DB.init(nil, ns.Modules.list())
    ns.db = db
    ns.Modules.attach(db)
  end
  ns.Comm.start()
  ns.Crew.start()
  ns.Self.start()
  ns.Guild.start()
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
  return db
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
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
      W.state.xp = W.secret()
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
    layer_key_alone_sends_nothing_and_rides_along = function(ns, A, W)
      start(ns, W)
      ns.LayerSensor.start()
      ns.Self.refresh("test"); W:advance(2)
      local n = #W.sent
      W.state.guids.mouseover = "Creature-0-1-0-111-299-01"
      for _ = 1, 2 do W:fire("UPDATE_MOUSEOVER_UNIT") end
      W:advance(3)
      A.eq(ns.LayerSensor.current(), "111")
      A.eq(#sentSince(ns, W, n), 0, "a new layer key alone sends no UPDATE")
      W.state.combat = true                    -- a fight starts: the tag goes out, the key with it
      W:fire("PLAYER_REGEN_DISABLED"); W:advance(3)
      local ups = {}
      for _, m in ipairs(sentSince(ns, W, n)) do if m.type == "UPDATE" then ups[#ups + 1] = m end end
      A.eq(#ups, 1)
      A.eq(ups[1].fields.tg, "COMBAT")
      A.eq(ups[1].fields.lk, "111", "lk rides along")
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
      receive(ns, W, "Ginkan Realm", "HELLO", { ver = "0.1.0" }) -- WoW Forever: "Name Realm"
      receive(ns, W, "Frostie-Noodledog", "HELLO", { ver = "0.1.0" })
      A.ok(ns.roster:get("Ginkan") ~= nil)
      A.ok(ns.roster:get("Frostie") ~= nil)
      A.eq(ns.roster:get("Ginkan Realm"), nil)
      noErrors(ns, A)
    end,
    saved_ghost_of_self_is_removed = function(ns, A, W)
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster["Twiz-Noodledog"] = { name = "Twiz-Noodledog", level = 6 }
      db.roster["Ginkan-Noodledog"] = { name = "Ginkan-Noodledog", level = 9 }
      db.stats.crew["Ginkan-Noodledog"] = { sid = "s", s = {}, a = {} }
      ns.db = db
      ns.Modules.attach(db)
      ns.Comm.start()
      ns.Crew.start()
      A.eq(db.roster["Twiz-Noodledog"], nil)
      A.eq(db.roster["Ginkan-Noodledog"], nil)
      A.eq(db.roster["Ginkan"].name, "Ginkan")
      A.ok(db.stats.crew["Ginkan"], "the numbers moved too")
      A.eq(ns.roster:get("Twiz-Noodledog"), nil)
      A.ok(ns.roster:get("Ginkan") ~= nil)
      noErrors(ns, A)
    end,
    -- Keys are guild member keys now: full names and "Name (2)" are real keys, never shortened at load.
    saved_full_name_keys_survive_the_load = function(ns, A, W)
      W.state.player = "Chaos Deathbringr"
      local db = ns.DB.init(nil, ns.Modules.list())
      db.guild.keys = { ["chaos deathbringr"] = "Chaos", ["chaos other"] = "Chaos Other", ["frostie pebble"] = "Frostie",
        ["frostie snow"] = "Frostie Snow", ["ginkan a"] = "Ginkan", ["ginkan b"] = "Ginkan (2)" }
      for _, name in ipairs({ "Chaos Other", "Frostie", "Frostie Snow", "Ginkan (2)" }) do
        db.roster[name] = { name = name, level = #name }
        db.stats.crew[name] = { sid = "s", s = { gn = #name }, a = {} }
      end
      db.roster["Lurabe Moon"] = { name = "Lurabe Moon", level = 11 } -- not in the saved keys: kept as it is too
      ns.db = db
      ns.Modules.attach(db)
      ns.Comm.start()
      ns.Crew.start()
      for _, name in ipairs({ "Chaos Other", "Frostie", "Frostie Snow", "Ginkan (2)", "Lurabe Moon" }) do
        A.eq(db.roster[name] and db.roster[name].level, #name, name .. " keeps its row")
        A.ok(ns.roster:get(name), name .. " is on the roster")
      end
      for _, name in ipairs({ "Chaos Other", "Frostie", "Frostie Snow", "Ginkan (2)" }) do
        A.eq(db.stats.crew[name].s.gn, #name, name .. " keeps its numbers")
      end
      A.eq(db.roster["Chaos"], nil)
      A.eq(db.roster["Ginkan"], nil)
      noErrors(ns, A)
    end,
    -- The game may give only my first word (UnitName "Chaos") while the guild list has not loaded: a saved row of a
    -- namesake ("Chaos Other") is not me, even with no saved guild key for it.
    a_namesakes_row_is_not_my_ghost_when_the_game_gives_one_word = function(ns, A, W)
      W.state.player = "Chaos"
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster["Chaos Other"] = { name = "Chaos Other", level = 20 }
      db.roster["Chaos-Realm"] = { name = "Chaos-Realm", level = 6 }
      db.stats.crew["Chaos Other"] = { sid = "s", s = {}, a = {} }
      ns.db = db
      ns.Modules.attach(db)
      ns.Comm.start()
      ns.Crew.start()
      A.eq(db.roster["Chaos Other"].level, 20, "several words: never mine on a first-word match")
      A.ok(db.stats.crew["Chaos Other"])
      A.eq(db.roster["Chaos-Realm"], nil, "my own ghost (my name with a realm) goes")
      A.eq(db.roster["Chaos"], nil)
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
    -- Each guild member's hello gets our state back as a whisper to that member only (one answer each, each after its
    -- own short random wait), never a copy to the whole guild per hello.
    hellos_from_many_friends_get_one_state_each = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      for _, name in ipairs({ "Frostie", "Ginkan", "Lurabe", "Pewpew", "Chaos" }) do
        receive(ns, W, name, "HELLO", { ver = "0.1.0" })
        W:advance(0.2)
      end
      W:advance(8)
      local to = {}
      for i = n + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "STATE" then
          A.eq(W.sent[i].chatType, "WHISPER")
          to[W.sent[i].target] = (to[W.sent[i].target] or 0) + 1
        end
      end
      A.eq(to, { Frostie = 1, Ginkan = 1, Lurabe = 1, Pewpew = 1, Chaos = 1 })
      A.ok(ns.roster:get("Chaos"))
    end,
    -- With many copies online the answers to a newcomer must not land at once: each waits 0 to HELLO_REPLY_JITTER s.
    hello_answers_are_spread_over_the_jitter = function(ns, A, W)
      start(ns, W)
      A.eq(ns.Config.HELLO_REPLY_JITTER, 5)
      local delays = {}
      local after = W.env.C_Timer.After
      W.env.C_Timer.After = function(delay, fn) delays[#delays + 1] = delay; return after(delay, fn) end
      for _, name in ipairs({ "Frostie", "Ginkan", "Lurabe" }) do receive(ns, W, name, "HELLO", { ver = "0.1.0" }) end
      receive(ns, W, "Frostie", "HELLO", { ver = "0.1.1" }) -- already waiting for an answer: no second one
      W.env.C_Timer.After = after
      A.eq(#delays, 3, "one pending answer per newcomer")
      for _, d in ipairs(delays) do A.ok(d >= 0 and d <= 5, "delay " .. d) end
      A.no(delays[1] == delays[2] and delays[2] == delays[3], "random, not all the same")
    end,
    -- Someone the guild list does not have yet (they just joined): no STATE to the whole guild (every copy would send
    -- one); the answer waits for a guild list that has them, at most HELLO_LIST_WAIT s.
    hello_from_someone_the_list_does_not_have_waits_for_the_list = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      receive(ns, W, "Newbie", "HELLO", { ver = "0.1.0" })
      receive(ns, W, "Oldnew", "HELLO", { ver = "0.1.0" })
      W:advance(8)
      for _, m in ipairs(sentSince(ns, W, n)) do A.no(m.type == "STATE", "nothing yet, and nothing to the guild") end
      table.insert(W.state.guild.members, { name = "Newbie Joined", online = true })
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(2)
      local to = {}
      for i = n + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "STATE" then to[#to + 1] = W.sent[i].chatType .. " " .. tostring(W.sent[i].target) end
      end
      A.eq(to, { "WHISPER Newbie Joined" }, "the new list has Newbie: whispered")
      W:advance(20)
      table.insert(W.state.guild.members, { name = "Oldnew Late", online = true })
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(2)
      for i = n + 1, #W.sent do A.no(W.sent[i].target == "Oldnew Late", "given up after 10 s") end
    end,
    -- A HELLO heard while our sends still wait for the guild list is answered once the list is in.
    hello_heard_while_waiting_for_the_list_is_answered_when_it_comes = function(ns, A, W)
      W.state.guildListDelay = 4
      local db = ns.DB.init(nil, ns.Modules.list())
      ns.db = db
      ns.Modules.attach(db)
      ns.Comm.start()
      ns.Crew.start()
      ns.Self.start()
      ns.Guild.start()
      W:fire("PLAYER_ENTERING_WORLD")
      A.ok(ns.Transport.isPending())
      receive(ns, W, "Frostie", "HELLO", { ver = "0.1.0" })
      local from = #W.sent
      W:advance(12)
      local to
      for i = from + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "STATE" and W.sent[i].chatType == "WHISPER" then to = W.sent[i].target end
      end
      A.eq(to, "Frostie", "answered by whisper once the list was in")
    end,
    a_waiting_hello_answer_is_retried_when_the_transport_is_ready = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Newbie", "HELLO", { ver = "0.1.0" })
      W:advance(6) -- waiting: nobody can whisper Newbie yet
      local real = ns.Transport.destinationFor
      ns.Transport.destinationFor = function(name)
        if name == "Newbie" then return { chatType = "WHISPER", target = "Newbie Joined" } end
        return real(name)
      end
      local from = #W.sent
      ns.Bus.fire("TRANSPORT_READY")
      W:advance(1)
      ns.Transport.destinationFor = real
      local to
      for i = from + 1, #W.sent do
        if ns.Codec.decode(W.sent[i].text).type == "STATE" and W.sent[i].chatType == "WHISPER" then to = W.sent[i].target end
      end
      A.eq(to, "Newbie Joined")
    end,
    forgetting_someone_drops_an_answer_still_waiting_for_them = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Newbie", "HELLO", { ver = "0.1.0" })
      W:advance(6) -- the answer now waits for a guild list that has Newbie
      receive(ns, W, "Newbie", "BYE", {})
      A.ok(ns.Crew.forget("Newbie"))
      local from = #W.sent
      table.insert(W.state.guild.members, { name = "Newbie Joined", online = true })
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(2)
      for i = from + 1, #W.sent do A.no(W.sent[i].target == "Newbie Joined", "nothing for a forgotten friend") end
    end,
    pings_from_many_strangers_get_one_hello = function(ns, A, W)
      start(ns, W)
      W:advance(30) -- past the answers to our own login HELLO
      local n = #W.sent
      for _, name in ipairs({ "Lurabe", "Pewpew", "Chaos" }) do -- guild members we have not heard from
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
      W:advance(30) -- past the answers to our own login HELLO
      local n = #W.sent
      receive(ns, W, "Pewpew", "PING", {}) -- a guild member we have not heard from
      W:advance(2)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 2); A.eq(msgs[1].type, "HELLO"); A.eq(msgs[2].type, "STATE")
      for i = n + 1, #W.sent do A.eq(W.sent[i].target, "Pewpew", "to the asker only") end
      -- a second ping soon after does not make us send again
      W:advance(5)
      n = #W.sent
      W:advance(1)
      receive(ns, W, "Pewpew", "PING", { x = "1" })
      W:advance(2)
      for _, m in ipairs(sentSince(ns, W, n)) do A.no(m.type == "HELLO") end
    end,
    -- Right after our HELLO a PING from someone we have not heard yet may just have overtaken their answer: no HELLO
    -- back for that (else, with many copies online, every copy would get a second answer).
    no_hello_back_while_the_answers_to_ours_are_coming = function(ns, A, W)
      start(ns, W)
      local n = #W.sent
      receive(ns, W, "Pewpew", "PING", {})
      W:advance(5)
      A.eq(#sentSince(ns, W, n), 0)
      W:advance(25)
      receive(ns, W, "Pewpew", "PING", { x = "1" })
      W:advance(2)
      A.eq(sentSince(ns, W, n)[1].type, "HELLO", "later on, a stranger's PING is answered")
    end,
    -- A PING from someone the guild list does not have: a HELLO to the whole guild would make every copy answer, so
    -- nothing; once the list has them, their next PING is answered.
    ping_from_someone_not_whisperable_is_answered_once_the_list_has_them = function(ns, A, W)
      start(ns, W)
      W:advance(30) -- past the answers to our own login HELLO
      local n = #W.sent
      receive(ns, W, "Newbie", "PING", {})
      W:advance(2)
      A.eq(#sentSince(ns, W, n), 0)
      table.insert(W.state.guild.members, { name = "Newbie Joined", online = true })
      W:advance(10)
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(2)
      receive(ns, W, "Newbie", "PING", { x = "1" })
      W:advance(2)
      local msgs = sentSince(ns, W, n)
      A.eq(#msgs, 2); A.eq(msgs[1].type, "HELLO")
      A.eq(W.sent[#W.sent].target, "Newbie Joined", "whispered by the full name from the guild list")
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
      A.eq(m.raw, { ver = "0.1.0", rs = "" }, "what they sent before the HELLO no longer counts for the digest")
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
    ping_from_a_stranger_is_answered_to_that_sender_only = function(ns, A, W, H)
      local a, aNs = H.client("Twiz")
      local b, bNs = H.client("Frostie", { class = "MAGE" })
      local c, cNs = H.client("Ginkan", { class = "ROGUE" })
      H.link(a, b, c)
      for _, w in ipairs({ a, b, c }) do
        w:fire("ADDON_LOADED", "TwizCrew"); w:fire("PLAYER_LOGIN"); w:fire("PLAYER_ENTERING_WORLD")
      end
      H.advance(15)
      b.state.dead = true
      b:fire("PLAYER_DEAD")
      H.advance(40) -- past the gap between answers to strangers
      A.ok(aNs.roster:get("Frostie").tags.DEAD, "Twiz sees Frostie's DEAD tag")
      A.ok(aNs.roster:get("Ginkan"), "Twiz knows Ginkan")
      aNs.roster.byName["Ginkan"] = nil -- from Twiz's side Ginkan is now a stranger
      aNs.roster.saved["Ginkan"] = nil
      local fromA = 0
      bNs.Comm.on("HELLO", function(sender) if sender == "Twiz" then fromA = fromA + 1 end end)
      bNs.Comm.on("STATE", function(sender) if sender == "Twiz" then fromA = fromA + 1 end end)
      local heardAtC = {}
      cNs.Comm.on("HELLO", function(sender) heardAtC[#heardAtC + 1] = "HELLO" end)
      cNs.Comm.on("STATE", function(sender) heardAtC[#heardAtC + 1] = "STATE" end)
      cNs.Comm.send("PING", {})
      H.advance(6)

      A.eq(fromA, 0, "Frostie hears nothing new from Twiz")
      A.eq(heardAtC, { "HELLO", "STATE" }, "Ginkan gets the answer")
      A.ok(bNs.roster:get("Twiz"), "Frostie still knows Twiz")
      A.ok(aNs.roster:get("Frostie").tags.DEAD, "Frostie's tag is still DEAD on Twiz's side")
      A.ok(bNs.roster:get("Twiz").online)
    end,
    digest_ignores_ride_along_keys_and_old_copies_never_mismatch = function(ns, A, W)
      A.eq(ns.Self.digestOf({ zn = "A", xc = "1", rx = "2", lk = "x" }), ns.Self.digestOf({ zn = "A", xc = "9" }))
      A.no(ns.Self.digestOf({ zn = "A" }) == ns.Self.digestOf({ zn = "B" }))
      A.ok(#ns.Self.digestOf({ zn = "A" }) <= 6)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lv = "20", zn = "Westfall" })
      local from = #W.sent
      for _ = 1, 4 do receive(ns, W, "Frostie", "PING", {}); W:advance(61) end -- no "h": an old copy
      for _, m in ipairs(sentSince(ns, W, from)) do A.no(m.type == "SREQ", "no SREQ for an old copy") end
    end,
    two_pings_with_a_wrong_digest_ask_once_and_sreq_is_answered = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lv = "20", zn = "Westfall" })
      local from = #W.sent
      receive(ns, W, "Frostie", "PING", { h = "1" })
      W:advance(11)
      A.eq(#sentSince(ns, W, from), 0, "one mismatch is not enough")
      receive(ns, W, "Frostie", "PING", { h = "2" })
      W:advance(11)
      local got = sentSince(ns, W, from)
      A.eq(#got, 1); A.eq(got[1].type, "SREQ")
      A.eq(W.sent[#W.sent].chatType, "WHISPER", "to the sender only")
      for _ = 1, 3 do receive(ns, W, "Frostie", "PING", { h = "3" }) end
      W:advance(11)
      A.eq(#sentSince(ns, W, from), 1, "not again within a ping interval")
      -- a matching digest clears the count
      receive(ns, W, "Frostie", "PING", { h = ns.roster:digest("Frostie") })
      -- SREQ is answered with the whole state to the asker only
      from = #W.sent
      receive(ns, W, "Frostie", "SREQ", {})
      W:advance(11)
      got = sentSince(ns, W, from)
      A.eq(#got >= 1 and got[1].type, "STATE")
      A.eq(W.sent[from + 1].chatType, "WHISPER")
      noErrors(ns, A)
    end,
    -- Before the guild list loads nobody can be whispered: the SREQ waits for the next PING (the mismatch is kept).
    sreq_is_counted_only_when_it_could_be_sent = function(ns, A, W)
      local rows = 0
      local real = W.env.GetNumGuildMembers
      W.env.GetNumGuildMembers = function() if rows == 0 then return 0, 0, 0 end return real() end
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lv = "20", zn = "Westfall" })
      local from = #W.sent
      receive(ns, W, "Frostie", "PING", { h = "1" })
      receive(ns, W, "Frostie", "PING", { h = "2" })
      W:advance(11)
      A.eq(ns.Log.counts()["sent SREQ"], nil, "nobody can be whispered yet: nothing sent, nothing counted")
      for _, m in ipairs(sentSince(ns, W, from)) do A.no(m.type == "SREQ") end
      rows = 7
      W:fire("GUILD_ROSTER_UPDATE")
      W:advance(2)
      receive(ns, W, "Frostie", "PING", { h = "3" })
      W:advance(11)
      A.eq(ns.Log.counts()["sent SREQ"], 1, "the next PING asks")
    end,
    -- Many copies may notice the same loss: each waits a random 0 to SREQ_JITTER s, and a STATE meanwhile settles it.
    sreq_waits_a_moment_and_a_state_meanwhile_settles_it = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lv = "20", zn = "Westfall" })
      local delays = {}
      local after = W.env.C_Timer.After
      W.env.C_Timer.After = function(d, fn) delays[#delays + 1] = d; return after(d, fn) end
      local from = #W.sent
      W:advance(1)
      receive(ns, W, "Frostie", "PING", { h = "1" })
      receive(ns, W, "Frostie", "PING", { h = "2" })
      W.env.C_Timer.After = after
      A.ok(#delays >= 1 and delays[#delays] >= 0 and delays[#delays] <= ns.Config.SREQ_JITTER, "a random wait")
      A.ok(delays[#delays] > 0.01, "(this run's wait leaves room for the STATE)")
      W:advance(0.01)
      receive(ns, W, "Frostie", "STATE", { lv = "21", zn = "Westfall" }) -- her full state arrives meanwhile
      W:advance(11)
      for _, m in ipairs(sentSince(ns, W, from)) do A.no(m.type == "SREQ", "no need to ask any more") end
    end,
    -- Several copies asking at once (all lost the same UPDATE) get one STATE to the guild, not one whisper each.
    many_sreqs_at_once_get_one_guild_state = function(ns, A, W)
      start(ns, W)
      local from = #W.sent
      for _, name in ipairs({ "Frostie", "Ginkan", "Lurabe" }) do receive(ns, W, name, "SREQ", {}) end
      W:advance(ns.Config.SREQ_COLLECT + 2)
      local states = {}
      for i = from + 1, #W.sent do
        local msg = ns.Codec.decode(W.sent[i].text)
        if msg and msg.type == "STATE" then states[#states + 1] = W.sent[i].chatType end
      end
      A.ok(#states >= 1 and #states <= 2, "one STATE (in pieces at most): " .. #states)
      for _, t in ipairs(states) do A.eq(t, "GUILD") end
    end,
    sreq_is_answered_at_most_once_per_ping_interval = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lv = "20", zn = "Westfall" })
      local function statesSince(from)
        local k = 0
        for _, m in ipairs(sentSince(ns, W, from)) do if m.type == "STATE" then k = k + 1 end end
        return k
      end
      local from = #W.sent
      receive(ns, W, "Frostie", "SREQ", {})
      W:advance(11)
      local one = statesSince(from)
      A.ok(one >= 1, "the first SREQ is answered")
      receive(ns, W, "Frostie", "SREQ", { x = "1" })
      receive(ns, W, "Ginkan", "SREQ", {})
      W:advance(11)
      A.eq(statesSince(from), one * 2, "Frostie's second ask is ignored, Ginkan's is answered")
      W:advance(ns.Config.PING_INTERVAL)
      receive(ns, W, "Frostie", "SREQ", { x = "2" })
      W:advance(11)
      A.eq(statesSince(from), one * 3, "answered again after a ping interval")
      noErrors(ns, A)
    end,
    forget_removes_an_offline_friend_everywhere = function(ns, A, W)
      local db = start(ns, W)
      receive(ns, W, "Frostie", "STATE", { lv = "20" })
      ns.StatsStore.applyWire("Frostie", { sid = "s1", q = "1", a_gn = "5" }, 100)
      A.ok(db.stats.crew.Frostie, "saved numbers")
      local removed = record(ns, "MEMBER_REMOVED")
      local ok, why = ns.Crew.forget("Frostie")
      A.no(ok); A.eq(why, "online right now")
      A.ok(ns.roster:get("Frostie"), "an online friend stays")
      receive(ns, W, "Frostie", "BYE", {})
      A.ok(ns.Crew.forget("frostie"))
      A.eq(ns.roster:get("Frostie"), nil)
      A.eq(db.roster.Frostie, nil)
      A.eq(db.stats.crew.Frostie, nil)
      A.eq(#removed, 1); A.eq(removed[1][1], "Frostie")
      A.no(ns.Crew.forget("Frostie"), "already gone")
      local me, why2 = ns.Crew.forget("Twiz")
      A.no(me); A.eq(why2, "that is you")
      receive(ns, W, "Frostie", "STATE", { lv = "21" })
      A.ok(ns.roster:get("Frostie"), "a friend who shows up again is added again")
      noErrors(ns, A)
    end,
    -- The roster follows the guild list: a saved friend a complete list lacks is hidden (never deleted for it).
    saved_friend_not_in_guild_is_hidden_after_first_list_load_only = function(ns, A, W)
      W.state.guildListDelay = 20 -- the list reads as empty for 20 s after the first ask
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster.Oldpal = { name = "Oldpal", class = "ROGUE", level = 30 }
      db.roster.Frostie = { name = "Frostie", class = "MAGE", level = 20 }
      db.stats.crew.Oldpal = { sid = "s", s = { gn = 3 }, a = { gn = 3 } }
      db.stats.crew.Frostie = { sid = "s", s = { gn = 4 }, a = { gn = 4 } }
      ns.db = db
      ns.Modules.attach(db)
      local updated = record(ns, "MEMBER_UPDATED")
      start(ns, W, db)
      A.no(ns.Guild.loaded())
      A.eq(ns.roster:names(), { "Frostie", "Oldpal" }, "before the list loads nobody is hidden")
      W:advance(20)
      A.ok(ns.Guild.loaded())
      A.eq(ns.roster:names(), { "Frostie" }, "hidden once the list has loaded")
      A.eq(ns.roster:get("Oldpal"), nil)
      local _, total = ns.roster:onlineCount(); A.eq(total, 1)
      A.eq(db.roster.Oldpal.level, 30, "their row stays on disk")
      A.eq(db.stats.crew.Oldpal.a.gn, 3, "their numbers stay on disk")
      local shown = {}
      for _, e in ipairs(ns.StatsStore.entries("all")) do shown[#shown + 1] = e.name end
      A.eq(shown, { "Frostie" }, "boards leave them out")
      local told
      for _, u in ipairs(updated) do if u[1] == "Oldpal" then told = u[2] end end
      A.eq(told, { inGuild = false }, "the panel is told, with the real value")
      noErrors(ns, A)
    end,
    saved_friend_in_guild_keeps_stats_trophies_notes = function(ns, A, W)
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster.Frostie = { name = "Frostie", class = "MAGE", level = 20 }
      db.stats.crew.Frostie = { sid = "s", s = { gn = 4 }, a = { gn = 4 } }
      db.stats.trophies = { s1 = { sid = "s1", people = { "Frostie", "Twiz" }, winners = { gn = "Frostie" } } }
      db.calendar = { notes = { n1 = { d = "2026-11-21", t = "raid", b = "Frostie" } } }
      ns.db = db
      ns.Modules.attach(db)
      start(ns, W, db)
      W:advance(5)
      A.ok(ns.Guild.loaded())
      A.eq(ns.roster:names(), { "Frostie" })
      A.eq(db.roster.Frostie.level, 20)
      A.eq(db.stats.crew.Frostie.a.gn, 4)
      A.eq(db.stats.trophies.s1.winners.gn, "Frostie")
      A.eq(db.calendar.notes.n1.b, "Frostie")
      noErrors(ns, A)
    end,
    -- Ruling: being out of the guild never deletes anything; only FORGET_AFTER_DAYS of silence does (at load).
    out_of_guild_is_only_hidden_never_forgotten = function(ns, A, W)
      local day = 86400
      local db = ns.DB.init(nil, ns.Modules.list())
      local now = ns.wallclock()
      db.roster.Gone = { name = "Gone", level = 5, lastSeen = now - 31 * day, outSince = now - 40 * day }
      db.stats.crew.Gone = { sid = "s", s = {}, a = { gn = 1 } }
      ns.db = db
      ns.Modules.attach(db)
      local removed = record(ns, "MEMBER_REMOVED")
      start(ns, W, db)
      A.ok(ns.roster:isHidden("Gone"))
      A.eq(db.roster.Gone.outSince, nil, "a test build's outSince is removed")
      W.wall = W.wall + 25 * day -- still under the 60 days of silence
      W:advance(ns.Config.OFFLINE_TICK * 3)
      A.eq(db.roster.Gone.level, 5, "kept")
      A.ok(db.stats.crew.Gone)
      A.eq(#removed, 0)
      noErrors(ns, A)
    end,
    rejoining_shows_them_again = function(ns, A, W)
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster.Oldpal = { name = "Oldpal", level = 30 }
      db.stats.crew.Oldpal = { sid = "s", s = {}, a = { gn = 3 } }
      ns.db = db
      ns.Modules.attach(db)
      local updated = record(ns, "MEMBER_UPDATED")
      start(ns, W, db)
      A.ok(ns.roster:isHidden("Oldpal"))
      local list = W.state.guild.members
      list[#list + 1] = { name = "Oldpal", online = false, guid = "Player-1-0099", lastOnline = { 0, 0, 1, 0 } }
      W:fire("GUILD_ROSTER_UPDATE", false)
      W:advance(2)
      A.no(ns.roster:isHidden("Oldpal"))
      A.eq(ns.roster:names(), { "Oldpal" })
      A.eq(ns.roster:get("Oldpal").inGuild, true)
      A.eq(updated[#updated], { "Oldpal", { inGuild = true } })
      A.eq(db.stats.crew.Oldpal.a.gn, 3, "back with their numbers")
      noErrors(ns, A)
    end,
    nothing_is_hidden_when_the_list_never_loads = function(ns, A, W)
      W.state.guildListDelay = 1e9
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster.Oldpal = { name = "Oldpal", level = 30 }
      db.roster.Frostie = { name = "Frostie", level = 20 }
      ns.db = db
      ns.Modules.attach(db)
      start(ns, W, db)
      W:advance(120)
      A.no(ns.Guild.loaded())
      A.eq(ns.roster:names(), { "Frostie", "Oldpal" })
      noErrors(ns, A)
    end,
    -- One unreadable (secret) row: the read is partial, nobody is hidden and no new key is given out.
    a_partial_guild_read_hides_nobody = function(ns, A, W)
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster.Oldpal = { name = "Oldpal", level = 30 }
      db.roster.Frostie = { name = "Frostie", level = 20 }
      db.guild.keys = { twiz = "Twiz", frostie = "Frostie" } -- given out before
      ns.db = db
      ns.Modules.attach(db)
      local real = W.env.GetGuildRosterInfo
      W.env.GetGuildRosterInfo = function(i)
        if i == 3 then local v = "Secret Name"; W.state.secret[v] = true; return v end
        return real(i)
      end
      start(ns, W, db)
      A.ok(ns.Guild.loaded()); A.no(ns.Guild.complete())
      A.eq(ns.Guild.get("Frostie").full, "Frostie", "members with saved keys are listed")
      A.eq(ns.Guild.get("Lurabe"), nil, "no new key on a partial read")
      A.eq(db.guild.keys.lurabe, nil)
      A.eq(ns.roster:names(), { "Frostie", "Oldpal" }, "a partial read hides nobody")
      W.env.GetGuildRosterInfo = real
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      W:advance(2)
      A.ok(ns.Guild.complete())
      A.eq(ns.roster:names(), { "Frostie" })
      A.eq(db.guild.keys.lurabe, "Lurabe", "new keys once the read is complete")
      noErrors(ns, A)
    end,
    prune_at_load_drops_old_friends_and_their_numbers = function(ns, A, W)
      local db = ns.DB.init(nil, ns.Modules.list())
      ns.db = db
      ns.Modules.attach(db)
      local day, now = 86400, ns.wallclock()
      db.roster = { Old = { name = "Old", level = 5, lastSeen = now - 61 * day },
        Recent = { name = "Recent", level = 5, lastSeen = now - 59 * day },
        Undated = { name = "Undated", level = 5 } }
      db.stats.crew.Old = { sid = "s", s = {}, a = {} }
      db.stats.crew.Recent = { sid = "s", s = {}, a = {} }
      ns.Comm.start()
      ns.Crew.start()
      A.eq(ns.roster:names(), { "Recent", "Undated" })
      A.eq(db.roster.Old, nil)
      A.eq(db.stats.crew.Old, nil)
      A.ok(db.stats.crew.Recent)
      A.eq(db.roster.Undated.lastSeen, now, "no saved time: today")
      noErrors(ns, A)
    end,
  },
}
