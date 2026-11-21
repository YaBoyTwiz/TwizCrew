-- ns.Guild: the game's guild list, keys, names and refreshes.
local function member(name, extra)
  local m = { name = name, class = "WARRIOR", level = 31, zone = "Stonetalon", rank = "Member", rankIndex = 2,
    online = true, guid = "Player-1-" .. tostring(#name) .. name:sub(1, 2) }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- Boots a game whose player is `me` in a guild of `members` (nil members = no guild). Starts the guild module.
local function boot(ns, W, me, members, mutate)
  W.state.player = me
  W.state.guild = members and { name = "Test Guild", members = members } or nil
  if mutate then mutate(W) end
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Guild.start()
  return db
end

local function listen(ns)
  local seen = { list = 0, states = {} }
  ns.Bus.on("test", "GUILD_LIST", function() seen.list = seen.list + 1 end)
  ns.Bus.on("test", "GUILD_STATE", function(v) seen.states[#seen.states + 1] = v end)
  return seen
end

return {
  files = "toc",
  tests = {
    members_come_from_the_game_list = function(ns, A, W)
      local seen = listen(ns)
      boot(ns, W, "Chaos Deathbringr", {
        member("Chaos Deathbringr", { class = "DRUID", guid = "Player-1-0001", rank = "Guild Master", rankIndex = 0 }),
        member("Ginkan Pebble", { class = "MAGE", level = 12, zone = "Elwynn Forest", online = false,
          guid = "Player-1-0002", lastOnline = { 0, 0, 3, 5 } }),
      })
      A.ok(ns.Guild.inGuild()); A.ok(ns.Guild.loaded())
      local list = ns.Guild.members()
      A.eq(#list, 2)
      local c = ns.Guild.get("Chaos")
      A.eq({ c.key, c.full, c.first, c.class, c.level, c.zone, c.rank, c.rankIndex, c.online, c.guid },
        { "Chaos", "Chaos Deathbringr", "Chaos", "DRUID", 31, "Stonetalon", "Guild Master", 0, true, "Player-1-0001" })
      A.eq(ns.Guild.count(), 1)
      local _, total = ns.Guild.count()
      A.eq(total, 2)
      A.eq(ns.Guild.fullName("Ginkan"), "Ginkan Pebble")
      A.eq(ns.Guild.myKey(), "Chaos")
      A.eq(ns.Guild.get("Ginkan").online, false)
      A.eq(seen.list, 1, "GUILD_LIST after the first read")
      A.eq(seen.states, { true })
      list[1] = nil
      A.eq(#ns.Guild.members(), 2, "a fresh array every time")
    end,

    members_are_sorted_a_to_z_by_full_name = function(ns, A, W)
      boot(ns, W, "Zed Zed", { member("Zed Zed"), member("bob Smith"), member("Anna Lee") })
      local names = {}
      for _, m in ipairs(ns.Guild.members()) do names[#names + 1] = m.full end
      A.eq(names, { "Anna Lee", "bob Smith", "Zed Zed" })
    end,

    not_in_a_guild_is_empty_and_quiet = function(ns, A, W)
      local seen = listen(ns)
      boot(ns, W, "Twiz", nil)
      A.no(ns.Guild.inGuild()); A.no(ns.Guild.loaded())
      A.eq(ns.Guild.members(), {})
      A.eq(ns.Guild.keyOf("Anyone"), nil)
      A.eq(ns.Guild.myKey(), nil)
      A.eq(W.guildRosterCalls, 0, "nothing asked of the game")
      W:advance(9)
      A.eq(seen.states, {}, "not announced before the grace time")
      W:advance(2)
      A.eq(seen.states, { false })
      A.eq(#W.sent, 0)
    end,

    leaving_the_guild_is_announced_after_the_grace_time = function(ns, A, W)
      local seen = listen(ns)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") })
      A.eq(seen.states, { true })
      W.state.guild = nil
      W:advance(5)
      A.ok(ns.Guild.inGuild(), "still in a guild for now")
      W:advance(6)
      A.no(ns.Guild.inGuild())
      A.eq(seen.states, { true, false })
      A.eq(ns.Guild.members(), {})
    end,

    key_is_first_word = function(ns, A, W)
      local db = boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble"), member("Frostie Snow") })
      A.eq(ns.Guild.get("Ginkan").full, "Ginkan Pebble")
      A.eq(ns.Guild.get("Frostie").first, "Frostie")
      A.eq(db.guild.keys["ginkan pebble"], "Ginkan", "saved the first time the member is seen")
    end,

    namesakes_get_full_name_key = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Chaos Zed"), member("Chaos Abel") })
      -- both first seen in one read, no saved class data: the A-Z first full name keeps the first word
      A.eq(ns.Guild.get("Chaos").full, "Chaos Abel")
      A.eq(ns.Guild.get("Chaos Zed").full, "Chaos Zed")
      A.eq(ns.Guild.keyOf("Chaos Zed"), "Chaos Zed")
      A.eq(ns.Guild.display("Chaos"), "Chaos Abel", "full name while a namesake is listed")
      A.eq(ns.Guild.display("Chaos Zed"), "Chaos Zed")
      A.eq(ns.Guild.display("Twiz"), "Twiz")
    end,

    key_never_changes_when_a_namesake_joins_later = function(ns, A, W)
      local db = boot(ns, W, "Twiz", { member("Twiz"), member("Chaos Zed") })
      A.eq(ns.Guild.get("Chaos").full, "Chaos Zed")
      table.insert(W.state.guild.members, member("Chaos Abel"))
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(ns.Guild.get("Chaos").full, "Chaos Zed", "the first holder keeps the first word")
      A.eq(ns.Guild.get("Chaos Abel").full, "Chaos Abel")
      A.eq(ns.Guild.display("Chaos"), "Chaos Zed")
      A.eq(db.guild.keys["chaos zed"], "Chaos")
      -- the holder leaves: the word is still theirs
      table.remove(W.state.guild.members, 2)
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(ns.Guild.get("Chaos"), nil)
      A.eq(ns.Guild.get("Chaos Abel").full, "Chaos Abel")
      A.eq(ns.Guild.display("Chaos Abel"), "Chaos", "alone with the word again: the first name shows")
    end,

    saved_class_decides_who_keeps_the_first_word = function(ns, A, W)
      W.state.guild = { name = "G", members = { member("Twiz"), member("Chaos Abel", { class = "WARRIOR" }),
        member("Chaos Zed", { class = "DRUID" }) } }
      W.state.player = "Twiz"
      local db = ns.DB.init(nil, ns.Modules.list())
      db.roster.Chaos = { class = "DRUID" }
      ns.db = db
      ns.Modules.attach(db)
      ns.Guild.start()
      A.eq(ns.Guild.get("Chaos").full, "Chaos Zed", "the saved class matches the druid")
      A.eq(ns.Guild.get("Chaos Abel").full, "Chaos Abel")
    end,

    keyOf_accepts_every_name_form = function(ns, A, W)
      local pending = { member("Twiz"), member("Chaos Deathbringr") }
      A.eq(ns.Guild.keyOf("Chaos"), nil, "before the first read")
      boot(ns, W, "Twiz", pending)
      A.eq(ns.Guild.keyOf("Chaos"), "Chaos")
      A.eq(ns.Guild.keyOf("chaos deathbringr"), "Chaos")
      A.eq(ns.Guild.keyOf("Chaos Deathbringr-Realm"), "Chaos")
      A.eq(ns.Guild.keyOf("Chaos Deathbringr Realm"), "Chaos", "the space form the game also uses")
      A.eq(ns.Guild.keyOf("Chaos Stranger"), nil)
      A.eq(ns.Guild.keyOf("Stranger"), nil)
      A.eq(ns.Guild.keyOf(nil), nil)
      A.eq(ns.Guild.keyOf(5), nil)
      A.ok(ns.Guild.isMember("Chaos-Realm")); A.no(ns.Guild.isMember("Stranger"))
    end,

    names_in_the_list_may_carry_the_realm = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") }, function(w) w.state.rosterRealm = true end)
      A.eq(ns.Guild.get("Ginkan").full, "Ginkan Pebble")
      A.eq(ns.Guild.myKey(), "Twiz")
    end,

    isMe_with_a_namesake = function(ns, A, W)
      boot(ns, W, "Chaos Deathbringr", { member("Chaos Deathbringr"), member("Chaos Other") })
      A.no(ns.Guild.isMe("Chaos Other"))
      A.ok(ns.Guild.isMe("Chaos Deathbringr"))
      A.ok(ns.Guild.isMe("Chaos"))
      A.ok(ns.Guild.isMe("chaos deathbringr-Realm"))
      A.no(ns.Guild.isMe("Ginkan"))
      A.eq(ns.Guild.myKey(), "Chaos", "the A-Z first namesake holds the first word")
      A.eq(ns.Guild.keyOf("Chaos Other"), "Chaos Other")
    end,

    refresh_is_throttled = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz") })
      local before = W.guildRosterCalls
      ns.Guild.refresh(); ns.Guild.refresh()
      A.eq(W.guildRosterCalls, before, "start just asked")
      W:advance(10)
      ns.Guild.refresh(); ns.Guild.refresh()
      A.eq(W.guildRosterCalls, before + 1)
    end,

    watched_refreshes_every_30s = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz") })
      ns.Guild.setWatched(true)
      local before = W.guildRosterCalls
      W:advance(31)
      A.eq(W.guildRosterCalls, before + 1)
      W:advance(30)
      A.eq(W.guildRosterCalls, before + 2)
      ns.Guild.setWatched(false)
      local mid = W.guildRosterCalls
      W:advance(90)
      A.eq(W.guildRosterCalls, mid, "hidden: every 120 s")
      W:advance(40)
      A.eq(W.guildRosterCalls, mid + 1)
    end,

    secret_values_do_not_raise = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") })
      W.env.GetGuildRosterInfo = function() return W.secret(), W.secret(), W.secret(), W.secret(), W.secret(),
        W.secret(), W.secret(), W.secret(), W.secret(), W.secret(), W.secret(), W.secret(), W.secret(), W.secret(),
        W.secret(), W.secret(), W.secret() end
      W.env.GetGuildRosterLastOnline = function() return W.secret(), W.secret(), W.secret(), W.secret() end
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(#ns.Guild.members(), 2, "an unreadable list changes nothing")
      W.env.GetNumGuildMembers = function() return W.secret(), W.secret(), W.secret() end
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(#ns.Guild.members(), 2)
      W.env.IsInGuild = function() return W.secret() end
      W:advance(30)
      A.ok(ns.Guild.inGuild(), "a secret answer is no answer")
    end,

    secret_values_before_the_first_read_do_not_raise = function(ns, A, W)
      W.state.player = "Twiz"
      W.state.guild = { name = "G", members = { member("Twiz") } }
      W.env.GetGuildRosterInfo = function() return W.secret(), W.secret() end
      boot(ns, W, "Twiz", nil)
      A.no(ns.Guild.loaded())
      A.eq(ns.Guild.members(), {})
    end,

    last_online_becomes_wall_seconds = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble", { online = false, lastOnline = { 1, 2, 3, 4 } }),
        member("Frostie Snow", { online = false, lastOnline = { 0, 0, 0, 0 } }) })
      local secs = ((365 + 60 + 3) * 24 + 4) * 3600
      A.eq(ns.Guild.get("Ginkan").lastOnline, W.env.time() - secs)
      A.eq(ns.Guild.get("Frostie").lastOnline, W.env.time())
      A.eq(ns.Guild.get("Twiz").lastOnline, nil, "online")
    end,

    last_online_is_nil_when_the_game_gives_nothing = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble", { online = false }) })
      A.eq(ns.Guild.get("Ginkan").lastOnline, nil)
    end,

    guild_list_fires_again_only_when_something_changed = function(ns, A, W)
      local seen = listen(ns)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") })
      A.eq(seen.list, 1)
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(seen.list, 1, "same list, no event")
      W.state.guild.members[2].zone = "Westfall"
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(seen.list, 2)
      A.eq(ns.Guild.get("Ginkan").zone, "Westfall")
    end,

    an_empty_list_late_at_login_wipes_nothing = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") })
      local members = W.state.guild.members
      W.state.guild.members = {}
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(#ns.Guild.members(), 2)
      A.ok(ns.Guild.inGuild())
      W.state.guild.members = members
    end,

    a_first_word_given_to_someone_who_left_is_not_taken_by_a_namesake = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Chaos Deathbringr"), member("Chaos Abel") })
      A.eq(ns.Guild.keyOf("Chaos"), "Chaos", "Abel is first A-Z and holds the word")
      -- make Deathbringr the holder, then he leaves
      local db = ns.db
      db.guild.keys = { twiz = "Twiz", ["chaos deathbringr"] = "Chaos", ["chaos abel"] = "Chaos Abel" }
      W.state.guild.members = { member("Twiz"), member("Chaos Abel") }
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(ns.Guild.get("Chaos Abel").full, "Chaos Abel")
      A.eq(ns.Guild.keyOf("Chaos"), nil)
      A.no(ns.Guild.isMember("Chaos"))
      A.eq(ns.Guild.keyOf("Chaos Abel"), "Chaos Abel")
    end,

    a_one_word_member_never_shares_a_key = function(ns, A, W)
      local db = boot(ns, W, "Twiz Other", { member("Twiz Other"), member("Ginkan Pebble") })
      A.eq(ns.Guild.myKey(), "Twiz")
      table.insert(W.state.guild.members, member("Twiz"))
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      local a, b = ns.Guild.get("Twiz"), ns.Guild.get("Twiz (2)")
      A.eq(a.full, "Twiz Other"); A.eq(b.full, "Twiz")
      A.eq(db.guild.keys["twiz"], "Twiz (2)", "saved, so stable")
      A.eq(#ns.Guild.members(), 3)
      A.eq(ns.Guild.keyOf("Twiz"), "Twiz (2)", "an exact full name wins over a key")
      A.eq(ns.Guild.keyOf("Twiz Other"), "Twiz")
      A.eq(ns.Guild.keyOf("Twiz-Realm"), "Twiz (2)")
      A.eq(ns.Guild.keyOf("Twiz (2)"), "Twiz (2)")
      A.eq(ns.Guild.get("Twiz").full, "Twiz Other", "the key still belongs to the holder")
      A.ok(not ns.Guild.get("Twiz (2)").key:find(" (test)", 1, true))
    end,

    keys_that_differ_only_in_case_do_not_collide = function(ns, A, W)
      W.state.player = "Twiz"
      W.state.guild = { name = "G", members = { member("Twiz"), member("Zed Zed") } }
      local db = ns.DB.init(nil, ns.Modules.list())
      db.guild.keys["zed zed"] = "twiz"
      ns.db = db; ns.Modules.attach(db)
      ns.Guild.start()
      A.eq(ns.Guild.get("twiz").full, "Zed Zed")
      A.eq(ns.Guild.get("Twiz (2)").full, "Twiz")
    end,

    isMe_uses_my_own_full_name_before_the_list_loads = function(ns, A, W)
      W.state.player = "Chaos Deathbringr"
      local db = ns.DB.init(nil, ns.Modules.list())
      ns.db = db; ns.Modules.attach(db)
      A.no(ns.Guild.loaded())
      A.no(ns.Guild.isMe("Chaos Other"))
      A.ok(ns.Guild.isMe("Chaos Deathbringr"))
      A.ok(ns.Guild.isMe("Chaos"))
    end,

    isMe_one_word_me_and_a_longer_namesake = function(ns, A, W)
      W.state.guids.player = "Player-1-ME"
      boot(ns, W, "Twiz", { member("Twiz", { guid = "Player-1-ME" }), member("Twiz Other") })
      A.no(ns.Guild.isMe("Twiz Other")); A.ok(ns.Guild.isMe("Twiz")); A.ok(ns.Guild.isMe("twiz-Realm"))
      A.eq(ns.Guild.myKey(), "Twiz")
    end,

    isMe_longer_me_and_a_one_word_namesake = function(ns, A, W)
      W.state.guids.player = "Player-1-ME"
      boot(ns, W, "Twiz Other", { member("Twiz Other", { guid = "Player-1-ME" }), member("Twiz") })
      A.no(ns.Guild.isMe("Twiz")); A.ok(ns.Guild.isMe("Twiz Other"))
    end,

    isMe_unitname_gives_only_the_first_word = function(ns, A, W)
      W.state.guids.player = "Player-1-ME"
      boot(ns, W, "Chaos", { member("Chaos Deathbringr", { guid = "Player-1-ME" }), member("Ginkan Pebble") })
      A.ok(ns.Guild.isMe("Chaos Deathbringr")); A.no(ns.Guild.isMe("Chaos Other")); A.ok(ns.Guild.isMe("Chaos"))
      A.eq(ns.Guild.myKey(), "Chaos")
    end,

    isMe_before_the_list_loads = function(ns, A, W)
      W.state.player = "Chaos"
      ns.db = ns.DB.init(nil, ns.Modules.list())
      A.ok(ns.Guild.isMe("Chaos Deathbringr")); A.ok(ns.Guild.isMe("Chaos Other")); A.ok(ns.Guild.isMe("Chaos"))
      A.no(ns.Guild.isMe("Ginkan"))
      W.state.player = "Chaos Deathbringr"
      A.no(ns.Guild.isMe("Chaos Other")); A.ok(ns.Guild.isMe("Chaos Deathbringr")); A.ok(ns.Guild.isMe("Chaos"))
    end,

    -- resolve: names from message fields (keys, full names, an old copy's first words) and typed names
    resolve_takes_keys_full_names_and_a_first_word_only_one_member_has = function(ns, A, W)
      A.eq(ns.Guild.resolve("Twiz"), nil, "nothing before the list loads")
      boot(ns, W, "Twiz", { member("Twiz"), member("Chaos Deathbringr"), member("Chaos Other"),
        member("Ginkan Pebble") })
      A.eq(ns.Guild.get("Chaos").full, "Chaos Deathbringr")
      A.eq(ns.Guild.resolve("Chaos"), "Chaos", "an exact key")
      A.eq(ns.Guild.resolve("chaos other"), "Chaos Other", "any case")
      A.eq(ns.Guild.resolve("Chaos Deathbringr"), "Chaos", "an exact full name")
      A.eq(ns.Guild.resolve("Chaos Deathbringr-Realm"), "Chaos", "a realm is taken off")
      A.eq(ns.Guild.resolve("Ginkan"), "Ginkan")
      A.eq(ns.Guild.resolve("ginkan pebble"), "Ginkan")
      A.eq(ns.Guild.resolve("Stranger"), nil)
      A.eq(ns.Guild.resolve("Bob (test)"), nil)
      A.eq(ns.Guild.resolve(nil), nil)
      A.eq(ns.Guild.resolve(""), nil)
    end,

    resolve_maps_a_first_word_whose_old_holder_left = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Chaos Deathbringr"), member("Chaos Abel") })
      ns.db.guild.keys = { twiz = "Twiz", ["chaos deathbringr"] = "Chaos", ["chaos abel"] = "Chaos Abel" }
      W.state.guild.members = { member("Twiz"), member("Chaos Abel") }
      W:advance(11)
      W.env.C_GuildInfo.GuildRoster()
      A.eq(ns.Guild.keyOf("Chaos"), nil, "a sender name: the word stays with whoever had it")
      A.eq(ns.Guild.resolve("Chaos"), "Chaos Abel", "a field or typed name: the one member with that word now")
    end,

    resolve_typed_first_word_two_members_share_asks_which_one = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Chaos Deathbringr"), member("Chaos Other") })
      A.eq(ns.Guild.resolve("Chaos"), "Chaos", "from a message: the key")
      local key, why = ns.Guild.resolve("Chaos", true)
      A.eq(key, nil, "typed: two members start with it"); A.eq(why, "ambiguous")
      A.eq(ns.Guild.resolve("Chaos Other", true), "Chaos Other")
      A.eq(ns.Guild.resolve("Chaos Deathbringr", true), "Chaos")
      A.eq(ns.Guild.resolve("Twiz", true), "Twiz")
      A.eq(ns.resolveName("chaos other"), "Chaos Other")
      A.eq(ns.resolveName("Bob (test)"), "Bob (test)", "the text as it is when the list cannot tell")
    end,

    home_guild_rules = function(ns, A, W)
      boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") })
      A.eq(ns.Guild.name(), "Test Guild")
      A.eq(ns.Guild.home(), nil); A.ok(ns.Guild.isHome(), "no home yet: any guild"); A.ok(ns.Guild.active())
      A.eq(ns.Guild.setHome(), "Test Guild"); A.eq(ns.db.guild.home, "Test Guild"); A.ok(ns.Guild.isHome())
      ns.db.guild.home = "Main Guild"
      A.no(ns.Guild.isHome()); A.no(ns.Guild.active()); A.ok(ns.Guild.inGuild(), "inGuild stays the game's answer")
      W.state.guild.name = nil
      local real = W.env.GetGuildInfo
      W.env.GetGuildInfo = function() return nil end
      A.no(ns.Guild.isHome(), "the name is not known and a home is set")
      ns.db.guild.home = nil
      A.ok(ns.Guild.isHome())
      W.env.GetGuildInfo = real
    end,

    another_guild_drops_the_list_and_keys_belong_to_one_guild = function(ns, A, W)
      local seen = listen(ns)
      local db = boot(ns, W, "Twiz", { member("Twiz"), member("Ginkan Pebble") })
      A.ok(ns.Guild.loaded()); A.eq(db.guild.keysFor, "Test Guild")
      db.guild.home = "Main Guild"
      W:advance(2)
      A.no(ns.Guild.loaded(), "not my TwizCrew guild: no list")
      A.eq(seen.states, { true, false })
      A.eq(ns.Guild.keyOf("Ginkan Pebble"), nil)
      W.state.guild.members = { member("Twiz"), member("Zed Zed") }
      W.env.C_GuildInfo.GuildRoster()
      W:advance(2)
      A.eq(db.guild.keys["zed zed"], nil, "nothing keyed in another guild")
      -- this guild becomes the TwizCrew guild: its own keys only
      db.guild.keysFor = "Main Guild"
      A.eq(ns.Guild.setHome(), "Test Guild")
      A.ok(ns.Guild.loaded())
      A.eq(db.guild.keys["ginkan pebble"], nil, "the other guild's keys were cleared")
      A.eq(db.guild.keys["zed zed"], "Zed")
      A.eq(db.guild.keysFor, "Test Guild")
    end,

    my_key_is_saved_per_character_and_known_before_the_list = function(ns, A, W)
      local db = boot(ns, W, "Chaos Other", { member("Chaos Deathbringr", { guid = "Player-1-0001" }),
        member("Chaos Other", { guid = "Player-1-0002" }) })
      A.eq(ns.Guild.myKey(), "Chaos Other")
      A.eq(db.guild.mine["Player-1-0002"], "Chaos Other")
      A.eq(ns.myKey(), "Chaos Other")
    end,

    my_saved_key_answers_while_the_list_is_not_loaded = function(ns, A, W)
      W.state.player = "Chaos Other"
      W.state.guild = { name = "Test Guild", members = {} }
      W.state.guids = W.state.guids or {}
      W.state.guids.player = "Player-1-0002"
      local db = ns.DB.init({ guild = { keys = {}, mine = { ["Player-1-0002"] = "Chaos Other" } } }, ns.Modules.list())
      ns.db = db
      ns.Modules.attach(db)
      ns.Guild.start()
      A.no(ns.Guild.loaded())
      A.eq(ns.Guild.myKey(), "Chaos Other")
      A.eq(ns.myKey(), "Chaos Other", "not my first word")
    end,

    the_module_is_registered = function(ns, A)
      local d = ns.Modules.get("guild")
      A.ok(d); A.eq(d.tier, "essential"); A.eq(d.name, "Guild list")
    end,
  },
}
