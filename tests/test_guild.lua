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
  if members then W.state.guild = { name = "Test Guild", members = members } end
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

    the_module_is_registered = function(ns, A)
      local d = ns.Modules.get("guild")
      A.ok(d); A.eq(d.tier, "essential"); A.eq(d.name, "Guild list")
    end,
  },
}
