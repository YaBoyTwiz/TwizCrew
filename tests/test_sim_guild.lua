-- Whole copies of TwizCrew talking through the guild (H.client / H.link / H.advance; linked clients share the
-- harness guild unless made with noGuild = true or put in their own with H.guild).

local function login(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function noErrors(A, ...)
  for _, ns in ipairs({ ... }) do A.eq(ns.Log.errors(50), {}, "errors on " .. ns.playerName()) end
end

local function unlink(H, W)
  for i, L in ipairs(H.linked) do if L == W then table.remove(H.linked, i) end end
end

local function online(ns, name)
  local m = ns.roster:get(name)
  return m ~= nil and m.online == true
end

local function typeOf(m) return m.text:match("^%d+%^(%u+)%^") end

local function whisper(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "WHISPER", sender)
  end
end

-- 50 copies in one guild, logged in together and settled (everyone has met everyone).
local function fiftyOnline(H, settle)
  local crew = {}
  for i = 1, 50 do
    local W, ns = H.client("Member" .. i, { class = (i % 2 == 0) and "MAGE" or "WARRIOR", level = 10 + i % 7 })
    crew[i] = { W = W, ns = ns }
    H.link(W)
    login(W)
  end
  H.advance(settle or 60)
  return crew
end


-- A character logged out: its copy stops running (it would keep writing into the shared saved table otherwise).
local function retire(H, W)
  W:fire("PLAYER_LOGOUT")
  H.advance(1)
  for i, L in ipairs(H.linked) do if L == W then table.remove(H.linked, i) end end
  for i, C in ipairs(H.clients) do if C == W then table.remove(H.clients, i) end end
end

-- The per-guild data on top of a saved table, deep-copied (Core/DB.lua GUILD_PATHS), and the guild name.
local function snapshot(saved)
  local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
  end
  return { name = saved.guild.name, roster = copy(saved.roster), crew = copy(saved.stats.crew),
    trophies = copy(saved.stats.trophies), calendar = copy(saved.calendar), keys = copy(saved.guild.keys),
    mine = copy(saved.guild.mine), session = copy(saved.stats.session), feed = copy(saved.feed),
    clown = copy(saved.stats.clown) }
end

-- My alt "Altie" (its own GUID) in guild `name` with "Stranger", who has TwizCrew too, logged in on `saved`.
local function altIn(H, name, saved)
  local alt, altNs = H.client("Altie", { class = "PRIEST" })
  alt.state.guids.player = "Player-9-0001"
  local other = H.client("Stranger", { class = "ROGUE" })
  H.guild(name, alt, other)
  alt.env.TwizCrewDB = saved
  H.link(alt, other)
  login(alt)
  login(other)
  return alt, altNs
end

local function groupless(sent)
  local n = 0
  for _, m in ipairs(sent) do if m.chatType ~= "PARTY" and m.chatType ~= "RAID" then n = n + 1 end end
  return n
end

local function printed(W, text)
  for _, line in ipairs(W.printed) do if line == text then return true end end
  return false
end


-- v0.1.24-style saved data: ten friends (first-word keys, mixed classes), their numbers, a trophy and a note.
local function oldSave()
  local saved = { roster = {}, stats = { crew = {}, trophies = { old = { sid = "old", people = { "FriendA", "Twiz" } } },
    chars = { Twiz = { sid = "x", s = {}, a = { dt = 1 } } } },
    calendar = { notes = { n1 = { d = "2026-11-01", t = "old note", b = "FriendA" } } } }
  for k = 1, 10 do
    local name = "Friend" .. string.char(64 + k)
    saved.roster[name] = { name = name, level = 10 + k, lastSeen = 1700000000 }
    saved.stats.crew[name] = { sid = "x", s = {}, a = { dt = k } }
  end
  return saved
end

-- Guild members for oldSave's friends: the first n of them (with surnames), plus a few others.
local function guildOf(n)
  local list = {}
  for k = 1, n do list[#list + 1] = { name = "Friend" .. string.char(64 + k) .. " Surname" } end
  for k = 1, 4 do list[#list + 1] = { name = "Other" .. k .. " Person" } end
  return list
end

local function countPrinted(W, sub)
  local n = 0
  for _, line in ipairs(W.printed) do if line:find(sub, 1, true) then n = n + 1 end end
  return n
end

-- One session of my main "Twiz" (GUID Player-1-0001) in `guildName` with `members`, on `saved`: logged in, played
-- for `seconds`, then (unless keep) logged out. state: more W.state for the client (e.g. guildListDelay).
local function mainSession(H, saved, guildName, members, seconds, state, keep)
  local W, ns = H.client("Twiz", state)
  W.state.guids.player = "Player-1-0001"
  H.guild(guildName, W, members)
  W.env.TwizCrewDB = saved
  H.link(W)
  login(W)
  H.advance(seconds)
  if not keep then retire(H, W) end
  return W, ns
end

local MAIN, ALT = "Player-1-0001", "Player-9-0001"

-- The saved table holds exactly the old (oldSave) data on top: every row, number, trophy and note.
local function oldDataOnTop(A, saved, when)
  local n = 0
  for name in pairs(saved.roster) do if name:match("^Friend%u$") then n = n + 1 end end
  A.eq(n, 10, when .. ": all ten old rows")
  A.eq(saved.stats.crew.FriendJ.a.dt, 10, when .. ": crew numbers")
  A.eq(saved.stats.trophies.old.sid, "old", when .. ": the trophy")
  A.eq(saved.calendar.notes.n1.t, "old note", when .. ": the note")
end

return {
  files = {},
  tests = {
    two_friends_meet_through_the_guild = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie Snow", { class = "MAGE", level = 12 })
      H.link(tw, fr)
      login(tw)
      login(fr)
      H.advance(10)
      A.ok(online(twNs, "Frostie"), "Twiz sees Frostie")
      A.eq(twNs.roster:get("Frostie").class, "MAGE")
      A.ok(online(frNs, "Twiz"), "Frostie sees Twiz")
      for _, W in ipairs({ tw, fr }) do
        for _, m in ipairs(W.sent) do
          A.ok(m.chatType == "GUILD" or m.chatType == "WHISPER", "only guild messages and whispers: " .. m.chatType)
          if m.chatType == "WHISPER" then
            A.ok(m.target == "Twiz" or m.target == "Frostie Snow", "a whisper to a guild member by full name")
          end
        end
      end
      noErrors(A, twNs, frNs)
    end,

    not_in_a_guild_sends_nothing_and_raises_nothing = function(_, A, _, H)
      local tw, twNs = H.client("Twiz", { noGuild = true })
      H.link(tw)
      login(tw)
      H.advance(5 * 60 + 15)
      tw.state.zone = "Westfall"
      tw:fire("ZONE_CHANGED_NEW_AREA")
      tc(tw, "status hello")
      tc(tw, "report")
      H.advance(30)
      A.eq(#tw.sent, 0, "nothing sent")
      A.no(twNs.Transport.isPending())
      A.eq(twNs.Transport.status().mode, "none")
      noErrors(A, twNs)
    end,

    leaving_the_guild_mid_session_stops_sends = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(tw, fr)
      login(tw)
      login(fr)
      H.advance(30)
      A.ok(online(frNs, "Twiz"))
      tw.state.guild = nil -- kicked
      local mark = #tw.sent
      tw.state.zone = "Westfall"
      tw:fire("ZONE_CHANGED_NEW_AREA")
      H.advance(3 * 60)
      A.eq(#tw.sent, mark, "no sends after leaving")
      A.eq(twNs.Transport.status().mode, "none")
      A.eq(frNs.roster:get("Twiz").zone, "Elwynn Forest", "Frostie never heard the zone change")
      noErrors(A, twNs, frNs)
    end,

    joining_a_guild_mid_session_says_hello = function(_, A, _, H)
      local tw, twNs = H.client("Twiz", { noGuild = true })
      local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12 })
      H.link(tw, fr)
      login(tw)
      login(fr)
      H.advance(30)
      A.eq(#tw.sent, 0)
      A.eq(frNs.roster:get("Twiz"), nil)
      H.joinCrewGuild(tw) -- invited
      H.advance(10)
      local hellos = 0
      for _, m in ipairs(tw.sent) do if typeOf(m) == "HELLO" then hellos = hellos + 1 end end
      A.eq(hellos, 1, "one HELLO")
      A.ok(online(frNs, "Twiz"), "Frostie sees Twiz")
      A.ok(online(twNs, "Frostie"), "Twiz sees Frostie (her answer)")
      A.eq(twNs.roster:get("Frostie").class, "MAGE")
      noErrors(A, twNs, frNs)
    end,

    old_channel_is_left_once_on_upgrade = function(_, A, _, H)
      local tw = H.client("Twiz", { channels = { TwizCrewHQ = 6 } }) -- the game rejoined the old channel at login
      tw.env.TwizCrewDB = { crew = { channel = "TwizCrewHQ", password = "goldshire", extra = { "Frostie" } },
        modules = { comm = { enabled = true, settings = { transport = "auto", debug = false } } } }
      H.link(tw)
      login(tw)
      H.advance(10)
      A.eq(tw.leaves, { "TwizCrewHQ" })
      A.eq(tw.state.channels.TwizCrewHQ, nil)
      local db = tw.env.TwizCrewDB
      A.eq(db.crew, nil)
      A.eq(db.modules.comm.settings.transport, nil)
      unlink(H, tw)
      local tw2, tw2Ns = H.client("Twiz")
      tw2.env.TwizCrewDB = db
      H.link(tw2)
      login(tw2)
      H.advance(10)
      A.eq(tw2.leaves, {}, "only on the first start after the update")
      noErrors(A, tw2Ns)
    end,

    old_channel_marker_goes_after_three_logins_without_it = function(_, A, _, H)
      local db = { crew = { channel = "TwizCrewHQ", password = "goldshire" } }
      local last
      for n = 1, 3 do
        if last then unlink(H, last) end
        local tw = H.client("Twiz")
        tw.env.TwizCrewDB = db
        H.link(tw)
        login(tw)
        H.advance(10)
        tw:fire("PLAYER_ENTERING_WORLD") -- a loading screen in the same login counts once
        H.advance(10)
        db = tw.env.TwizCrewDB
        A.eq(tw.leaves, {}, "never there: never left")
        if n < 3 then A.eq(db.crew, { channel = "TwizCrewHQ", zeroLogins = n }, "login " .. n) end
        last = tw
      end
      A.eq(db.crew, nil, "not there on three logins: forgotten")
    end,

    -- An ask goes to one friend or nowhere: while we cannot whisper yet (the guild list is late) a digest's asks wait,
    -- they never become a guild CALQ that every copy would answer.
    asks_wait_for_the_list_and_never_go_to_the_guild = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(tw, fr)
      login(tw)
      login(fr)
      H.advance(60)
      tw:fire("PLAYER_LOGOUT")
      H.advance(1)
      unlink(H, tw)
      -- meanwhile Frostie learns about someone's evening that Twiz has never seen
      local today = math.floor(frNs.Diary.now() / 86400)
      local L = frNs.CalendarLogic
      frNs.Diary.people().zzzz9999 = { name = "Ghost", class = "PRIEST", alts = {},
        days = { [today] = { on = L.set(L.set(L.EMPTY, 3), 4) } } }
      local tw2, tw2Ns = H.client("Twiz", { guildListDelay = 8 })
      tw2.env.TwizCrewDB = twNs.db
      H.link(tw2)
      login(tw2)
      H.advance(1)
      A.ok(tw2Ns.Transport.isPending(), "still waiting for the list")
      frNs.Diary.sendDigest() -- Frostie's digest to everyone arrives now
      H.advance(1)
      for _, m in ipairs(tw2.sent) do A.no(m.text:find("^%d+%^CALQ%^") and m.chatType == "GUILD", "a guild CALQ") end
      H.advance(30)
      local asked = false
      for _, m in ipairs(tw2.sent) do
        if m.text:find("^%d+%^CALQ%^") then
          A.eq(m.chatType, "WHISPER"); A.eq(m.target, "Frostie"); asked = true
        end
      end
      A.ok(asked, "asked Frostie once the list was in")
      A.ok(tw2Ns.Diary.people().zzzz9999, "the diary arrived")
      noErrors(A, tw2Ns, frNs)
    end,

    -- I am "Chaos Deathbringr"; another member is "Chaos Other". Their data never mixes with mine.
    namesake_of_me_is_heard = function(_, A, _, H)
      local me, meNs = H.client("Chaos Deathbringr")
      local other, otherNs = H.client("Chaos Other", { class = "MAGE", level = 20 })
      H.link(me, other)
      login(me)
      login(other)
      H.advance(15)
      A.eq(meNs.Guild.keyOf("Chaos Other"), "Chaos Other")
      local m = meNs.roster:get("Chaos Other")
      A.ok(m and m.online, "their STATE arrived under their own key")
      A.eq(m.class, "MAGE"); A.eq(m.level, 20)
      A.eq(meNs.roster:get("Chaos"), nil, "nothing stored under my key")
      A.no(meNs.isMe("Chaos Other"))
      A.ok(meNs.isMe("Chaos"))
      local mine = otherNs.roster:get("Chaos")
      A.ok(mine and mine.online, "and they hear me under my key")
      A.eq(mine.class, "WARRIOR")
      A.no(otherNs.isMe("Chaos"), "my key is not theirs")
      A.ok(otherNs.isMe("Chaos Other"))
      noErrors(A, meNs, otherNs)
    end,

    -- Saved data keyed by full names ("Chaos Other", "Frostie Snow") survives a reload: nothing is shortened or mixed.
    namesakes_keep_their_saved_rows_across_a_reload = function(_, A, _, H)
      local me, meNs = H.client("Chaos Deathbringr")
      local others = {}
      for _, x in ipairs({ { "Chaos Other", "MAGE", 20 }, { "Frostie Pebble", "PRIEST", 14 }, { "Frostie Snow", "ROGUE", 9 } }) do
        local W, ns = H.client(x[1], { class = x[2], level = x[3] })
        others[#others + 1] = { W = W, ns = ns, class = x[2], level = x[3] }
      end
      H.link(me, others[1].W, others[2].W, others[3].W)
      login(me)
      for _, o in ipairs(others) do login(o.W) end
      H.advance(60)
      for _, o in ipairs(others) do o.ns.Stats.send() end -- everyone's numbers, so the stats rows exist too
      H.advance(10)
      local keys = { "Chaos Other", "Frostie", "Frostie Snow" } -- Pebble is first A-Z: the first word is hers
      local function check(ns, when)
        for i, key in ipairs(keys) do
          local row = ns.db.roster[key]
          A.ok(row, when .. ": roster row " .. key)
          A.eq(row.class, others[i].class, when .. ": " .. key .. "'s class")
          A.eq(row.level, others[i].level, when .. ": " .. key .. "'s level")
          A.ok(ns.db.stats.crew[key], when .. ": stats row " .. key)
        end
        A.eq(ns.db.roster["Chaos"], nil, when .. ": nothing under my key")
      end
      check(meNs, "first session")
      me:fire("PLAYER_LOGOUT")
      H.advance(1)
      unlink(H, me)
      local me2, me2Ns = H.client("Chaos Deathbringr")
      me2.env.TwizCrewDB = meNs.db
      me2:fire("ADDON_LOADED", "TwizCrew")
      me2:fire("PLAYER_LOGIN")
      check(me2Ns, "after the reload")
      H.link(me2)
      me2:fire("PLAYER_ENTERING_WORLD")
      H.advance(30)
      check(me2Ns, "back online")
      noErrors(A, me2Ns, others[1].ns, others[3].ns)
    end,

    whisper_from_a_member_before_the_list_loads_is_dropped_then_repaired = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12 })
      H.link(tw, fr)
      login(tw)
      login(fr)
      H.advance(40)
      A.ok(online(twNs, "Frostie"))
      -- Twiz logs out; meanwhile Frostie moves on; Twiz comes back and the guild list is late (40 s)
      tw:fire("PLAYER_LOGOUT")
      H.advance(1)
      unlink(H, tw)
      fr.state.zone, fr.state.level = "Westfall", 13
      fr:fire("ZONE_CHANGED_NEW_AREA")
      fr:fire("PLAYER_LEVEL_UP", 13)
      H.advance(5)
      local tw2, tw2Ns = H.client("Twiz")
      tw2.env.TwizCrewDB = twNs.db
      local listAt = H.elapsed + 40
      local real = tw2.env.GetNumGuildMembers
      tw2.env.GetNumGuildMembers = function() if H.elapsed < listAt then return 0, 0, 0 end return real() end
      H.link(tw2)
      login(tw2)
      local loginAt = H.elapsed
      H.advance(20) -- the HELLO waited GUILD_LIST_WAIT (10 s) for the list, then went out anyway
      A.ok((tw2Ns.Log.counts()["recv not in guild"] or 0) >= 1, "Frostie's whispered answer was dropped")
      A.eq(tw2Ns.roster:get("Frostie").zone, "Elwynn Forest", "still the old saved row")
      local fixedAt, listed = nil, false
      H.advance(130 - 20, function()
        if not listed and H.elapsed >= listAt then -- the game tells the addon when the list has come in
          listed = true
          tw2:fire("GUILD_ROSTER_UPDATE", false)
        end
        local m = tw2Ns.roster:get("Frostie")
        if not fixedAt and m.zone == "Westfall" and m.level == 13 and m.online then fixedAt = H.elapsed end
      end)
      A.ok(fixedAt, "repaired")
      A.ok(fixedAt - loginAt <= 130, "within 130 s: " .. tostring(fixedAt and fixedAt - loginAt))
      noErrors(A, tw2Ns, frNs)
    end,

    stranger_mock_calendar_note_and_update_notice_change_nothing = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      H.guild("Crew", tw, { { name = "Frostie Snow", class = "MAGE", online = true } })
      H.link(tw)
      login(tw)
      H.advance(35) -- past the quiet time after login
      local function poke(sender, day)
        whisper(tw, twNs, sender, "STATE", { cl = "MAGE", lv = "12", ver = "9.9.9", rs = "9.9.9", lo = "7.3.1-100" })
        whisper(tw, twNs, sender, "MOCK", { t = "Twiz", x = "Rest in pieces, Twiz." })
        whisper(tw, twNs, sender, "CALN", { k = "zz-" .. day, d = "2026-11-" .. day, t = "spam", i = "1",
          u = "5" })
        whisper(tw, twNs, sender, "UPDREQ", { ver = "9.9.9", rs = "9.9.9" })
      end
      poke("Stranger Danger-Realm", "14")
      H.advance(40)
      A.no(twNs.MockShow.isShown(), "no mock show")
      A.eq(#twNs.Roasts.forTest.shown(), 0, "no mock line")
      A.eq(#twNs.Notes.forDate("2026-11-14"), 0, "no saved note")
      A.eq(twNs.db.update, {}, "no update record")
      A.eq(twNs.Updates.promptForTest(), nil, "no update window")
      A.eq(twNs.roster:get("Stranger"), nil, "not on the panel")
      A.eq(#twNs.Popups.shownForTest(), 0, "no pop-up")
      A.eq(twNs.Log.counts()["recv not in guild"], 4)
      -- the same messages from a guild member do all of that
      poke("Frostie Snow", "15")
      H.advance(1)
      A.ok(twNs.MockShow.isShown(), "a member's mock shows")
      A.eq(#twNs.Notes.forDate("2026-11-15"), 1, "a member's note is kept")
      A.ok(twNs.roster:get("Frostie"), "a member is on the panel")
      noErrors(A, twNs)
    end,

    -- Copies agree on who answers for the crew without talking: with the same rosters exactly k say yes.
    -- A stranger whose name is "<a member's first word> <realm>" is not that member in the " Realm" space form.
    stranger_named_first_word_and_realm_changes_nothing = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      H.guild("Crew", tw, { { name = "Chaos Deathbringr", class = "WARRIOR", online = true } })
      H.link(tw)
      login(tw)
      H.advance(35)
      A.eq(tw.state.realm, "Realm")
      local before = twNs.roster:get("Chaos") and twNs.roster:get("Chaos").level
      whisper(tw, twNs, "Chaos Realm", "STATE", { cl = "MAGE", lv = "55", zn = "Stranger Land" })
      whisper(tw, twNs, "Chaos Realm", "MOCK", { t = "Twiz", x = "Rest in pieces, Twiz." })
      H.advance(5)
      A.no(twNs.MockShow.isShown(), "no mock show")
      A.eq(#twNs.Roasts.forTest.shown(), 0, "no mock line")
      local row = twNs.roster:get("Chaos")
      A.eq(row and row.level, before, "Chaos's row did not change")
      A.eq(twNs.roster:get("Chaos Realm"), nil, "not on the panel")
      A.eq(twNs.Log.counts()["recv not in guild"], 2)
      -- the real space form of the member's name still lands on Chaos
      whisper(tw, twNs, "Chaos Deathbringr Realm", "MOCK", { t = "Twiz", x = "Rest in pieces, Twiz." })
      H.advance(1)
      A.ok(twNs.MockShow.isShown(), "a member's mock shows")
      A.eq(twNs.Log.counts()["recv not in guild"], 2)
      noErrors(A, twNs)
    end,

    responders_are_the_same_few_on_every_copy = function(_, A, _, H)
      local all = {}
      for i = 1, 8 do
        local W, ns = H.client("Pal" .. i)
        all[i] = ns
        H.link(W)
        login(W)
      end
      H.advance(20)
      for _, newcomer in ipairs({ "Newbie", "Pal3", "Zed" }) do
        local yes = 0
        for _, ns in ipairs(all) do if ns.Crew.isResponder(newcomer, 3) then yes = yes + 1 end end
        A.eq(yes, 3, "three copies answer for " .. newcomer)
      end
      local picked = {}
      for i, ns in ipairs(all) do if ns.Crew.isResponder("Newbie", 3) then picked[#picked + 1] = i end end
      local other = {}
      for i, ns in ipairs(all) do if ns.Crew.isResponder("Zed", 3) then other[#other + 1] = i end end
      A.no(table.concat(picked, ",") == table.concat(other, ","), "a different few for someone else")
      A.ok(all[1].Crew.isResponder("Newbie", 8), "fewer than k others online: everyone answers")
    end,

    -- The newcomer's guild list comes 4 s late: its HELLO waits for it, so no whispered answer is dropped.
    a_late_guild_list_loses_no_answer_with_50_online = function(_, A, _, H)
      local crew = fiftyOnline(H)
      local nb, nbNs = H.client("Newbie", { class = "PRIEST", guildListDelay = 4 })
      H.link(nb)
      login(nb)
      local loginAt = H.elapsed
      A.ok(nbNs.Transport.isPending(), "waiting for the list")
      local knownAt
      H.advance(15, function()
        if knownAt then return end
        for i = 1, 50 do
          local m = nbNs.roster:get("Member" .. i)
          if not (m and m.online and m.level == 10 + i % 7) then return end
        end
        knownAt = H.elapsed
      end)
      A.eq(nbNs.Log.counts()["recv not in guild"], nil, "no answer was dropped")
      A.ok(knownAt, "the newcomer knows everyone's state within 15 s")
      A.ok(knownAt - loginAt >= 4, "not before the list came")
      noErrors(A, nbNs, crew[1].ns)
    end,

    -- 50 copies online, a newcomer logs in: every addon send of the next 60 s is counted (the PING every copy sends
    -- once a minute anyway is left out of the per-copy numbers). What it costs:
    --   newcomer: HELLO and STATE to the guild in its first 10 s (at most 3 sends there), at most 12 sends in 60 s
    --     (its digests and numbers to the guild, one guild answer for its own diary, batched asks for the diaries it
    --     lacks: one CALQ per 20 people);
    --   an existing copy that is not a responder (Crew.isResponder): its STATE answer only (at most 2 pieces);
    --   a responder (about 3): also its calendar digest (up to 3 pieces with 50 people), our session (UPDATE) and at
    --     most one ask, by whisper (at most 7 sends), plus the diaries the newcomer asked it for (CALP: in all at most
    --     one per person, 51).
    login_with_50_members_online_costs_bounded_sends = function(_, A, _, H)
      local crew = fiftyOnline(H)
      local nb, nbNs = H.client("Newbie", { class = "PRIEST" })
      H.link(nb)
      local function timed(W)
        local at = {}
        local send = W.env.C_ChatInfo.SendAddonMessage
        W.env.C_ChatInfo.SendAddonMessage = function(...)
          at[#W.sent + 1] = W.clock
          return send(...)
        end
        return at
      end
      local nbAt = timed(nb)
      local marks, ats = {}, {}
      for i, c in ipairs(crew) do marks[i], ats[i] = #c.W.sent, timed(c.W) end
      login(nb)
      local loginAt = nb.clock
      H.advance(60)
      local firstTen, all = {}, {}
      for i, m in ipairs(nb.sent) do
        local what = typeOf(m) .. " " .. m.chatType
        all[#all + 1] = what
        if nbAt[i] - loginAt <= 10 then firstTen[#firstTen + 1] = what end
      end
      A.ok(#firstTen <= 3, "the newcomer sent " .. #firstTen .. " in its first 10 s: " .. table.concat(firstTen, ", "))
      A.ok(#all <= 12, "the newcomer sent " .. #all .. " in 60 s: " .. table.concat(all, ", "))
      local diaries, responders = 0, 0
      local storm = {} -- 0.1 s step -> the copy that sent something other than its STATE answer then
      for i, c in ipairs(crew) do
        local responder = c.ns.Crew.isResponder("Newbie")
        if responder then responders = responders + 1 end
        local sends, states = {}, 0
        for j = marks[i] + 1, #c.W.sent do
          local m = c.W.sent[j]
          local t = typeOf(m)
          if t == "CALP" then
            diaries = diaries + 1
          elseif t ~= "PING" then
            sends[#sends + 1] = t .. " " .. m.chatType
            if t == "STATE" then
              states = states + 1
              A.eq(m.chatType, "WHISPER", "a STATE answer is a whisper")
            else
              local step = math.floor(ats[i][j] * 10 + 0.5)
              A.ok(storm[step] == nil or storm[step] == i, "two copies sent at the same moment: " .. t)
              storm[step] = i
            end
          end
        end
        local who = c.ns.playerName() .. (responder and " (responder)" or "")
        A.ok(states >= 1 and states <= 2, who .. " answered with " .. states .. " STATE pieces")
        A.ok(#sends <= (responder and 7 or 2), who .. " sent " .. table.concat(sends, ", "))
      end
      A.ok(responders >= 1 and responders <= 6, responders .. " responders")
      A.ok(diaries <= 51, diaries .. " diaries for 51 people")
      local seen = 0
      for _, c in ipairs(crew) do if online(c.ns, "Newbie") then seen = seen + 1 end end
      A.eq(seen, 50, "everyone sees the newcomer")
      local heard = 0
      for i = 1, 50 do if online(nbNs, "Member" .. i) then heard = heard + 1 end end
      A.eq(heard, 50, "the newcomer sees everyone")
      noErrors(A, nbNs, crew[1].ns, crew[50].ns)
    end,


    -- Saved data is kept per guild: a main in guild A and an alt in guild B share one saved table.
    main_and_alt_keep_separate_guild_data = function(_, A, _, H)
      local main, mainNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(main, fr)
      login(main)
      login(fr)
      H.advance(30)
      local saved = mainNs.db
      A.eq(saved.guild.name, "Crew Guild", "an empty roster: adopted by the first guild")
      A.ok(online(mainNs, "Frostie"))
      saved.stats.trophies.s1 = { sid = "s1", people = { "Frostie", "Twiz" } }
      saved.calendar.notes = { n1 = { d = "2026-11-21", t = "raid night", b = "Twiz" } }
      saved.roster.Oldpal = { name = "Oldpal", level = 5, lastSeen = mainNs.wallclock() }
      mainNs.Modules.set("panel", "scale", 1.2) -- a setting: shared by every character
      mainNs.Stats.count("dt", 4)               -- my own numbers: shared too
      retire(H, main)
      local guildA = snapshot(saved)
      -- the alt's first login: guild B's name is not the data in use: quiet, and it says /reload
      local alt, altNs = altIn(H, "Other Guild", saved)
      H.advance(5 * 60)
      A.eq(groupless(alt.sent), 0, "zero sends")
      A.ok(printed(alt, "TwizCrew keeps separate data for each guild. Type /reload to switch to Other Guild."))
      A.ok(altNs.Transport.status().reload)
      A.eq(altNs.roster:get("Stranger"), nil, "nothing accepted")
      A.eq(altNs.roster:names(), { "Frostie", "Oldpal" }, "nobody hidden")
      A.eq(snapshot(saved), guildA, "guild A's data: nothing hidden, deleted or rewritten")
      A.eq(saved.modules.panel.settings.scale, 1.2, "settings are shared")
      noErrors(A, altNs)
      retire(H, alt)
      -- the alt's second login: guild B's own data, and it works
      local alt2, alt2Ns = altIn(H, "Other Guild", saved)
      H.advance(30)
      A.eq(saved.guild.name, "Other Guild")
      A.eq(countPrinted(alt2, "TwizCrew: Other Guild starts with new TwizCrew data. You have other saved sets: type"
        .. " /tc guild."), 1)
      A.ok(online(alt2Ns, "Stranger"), "the alt meets its guild")
      A.eq(alt2Ns.roster:get("Frostie"), nil, "guild A's people are not here")
      A.eq(saved.guilds["Crew Guild"].roster.Frostie.class, "MAGE", "guild A's data is parked")
      A.eq(saved.guilds["Crew Guild"].stats.trophies.s1.sid, "s1")
      A.eq(saved.guilds["Crew Guild"].calendar.notes.n1.t, "raid night")
      A.ok(saved.guilds["Crew Guild"].guild.keys.frostie, "with its keys")
      A.eq(saved.guild.keys.frostie, nil)
      A.ok(saved.guild.keys.stranger, "guild B's own keys")
      A.eq(saved.stats.chars.Twiz.a.dt, 4, "my own characters' numbers are shared")
      A.eq(saved.modules.panel.settings.scale, 1.2)
      noErrors(A, alt2Ns)
      retire(H, alt2)
      -- the main again: guild A's data back on top, guild B's parked
      local main2, main2Ns = H.client("Twiz")
      main2.state.guild = main.state.guild
      main2.env.TwizCrewDB = saved
      main2:fire("ADDON_LOADED", "TwizCrew")
      main2:fire("PLAYER_LOGIN")
      A.eq(saved.guild.name, "Crew Guild")
      A.eq(saved.roster.Frostie.class, "MAGE")
      A.eq(saved.stats.trophies.s1.sid, "s1")
      A.eq(saved.guilds["Other Guild"].roster.Stranger.class, "ROGUE")
      H.link(main2)
      main2:fire("PLAYER_ENTERING_WORLD")
      H.advance(30)
      A.ok(online(main2Ns, "Frostie"))
      A.eq(main2Ns.roster:names(), { "Frostie" }, "the old friend is hidden again, never deleted")
      A.ok(saved.roster.Oldpal)
      noErrors(A, main2Ns, frNs)
    end,

    old_data_opened_first_on_an_alt_stays_for_its_guild = function(_, A, _, H)
      local saved = { roster = { Frostie = { name = "Frostie", class = "MAGE", level = 20, lastSeen = 1700000000 } },
        stats = { chars = { Twiz = { sid = "x", s = {}, a = { dt = 9 } } },
          crew = { Frostie = { sid = "x", s = {}, a = { dt = 3 } } }, trophies = { old = { sid = "old", people = {} } } },
        calendar = { notes = { n1 = { d = "2026-11-01", t = "old note", b = "Frostie" } } } }
      local alt, altNs = altIn(H, "Other Guild", saved)
      H.advance(60)
      A.eq(groupless(alt.sent), 0, "an unrelated guild: quiet")
      A.no(printed(alt, "TwizCrew keeps separate data for each guild. Type /reload to switch to Other Guild."),
        "no /reload line for unnamed data")
      A.eq(saved.guild.name, nil)
      A.eq(saved.roster.Frostie.level, 20, "the old data is intact")
      A.eq(altNs.roster:names(), { "Frostie" }, "nobody hidden")
      noErrors(A, altNs)
      A.eq(saved.guild.byChar[ALT], nil, "no guild remembered for data that is not its own")
      retire(H, alt)
      local alt2, alt2Ns = altIn(H, "Other Guild", saved)
      H.advance(30)
      A.eq(saved.guild.name, nil, "the second login: the old data still on top, unnamed (no set is made by itself)")
      A.no(alt2Ns.Guild.active())
      A.eq(next(saved.guilds), nil, "nothing parked")
      retire(H, alt2)
      -- the main, in guild A where Frostie is: the old data fits at once
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(fr)
      login(fr)
      local main2, main2Ns = H.client("Twiz")
      main2.env.TwizCrewDB = saved
      H.link(main2)
      login(main2)
      H.advance(30)
      A.eq(saved.guild.name, "Crew Guild", "the old data found its guild")
      A.eq(saved.guilds[""], nil)
      A.eq(saved.stats.crew.Frostie.a.dt, 3)
      A.eq(saved.stats.trophies.old.sid, "old")
      A.eq(saved.calendar.notes.n1.t, "old note")
      A.eq(saved.stats.chars.Twiz.a.dt, 9)
      A.ok(online(main2Ns, "Frostie"))
      A.eq(next(saved.guilds), nil, "nothing was parked on the way")
      noErrors(A, main2Ns, frNs)
    end,

    a_guildless_alt_changes_nothing = function(_, A, _, H)
      local main, mainNs = H.client("Twiz")
      local fr = H.client("Frostie", { class = "MAGE" })
      H.link(main, fr)
      login(main)
      login(fr)
      H.advance(30)
      local saved = mainNs.db
      saved.roster.Oldpal = { name = "Oldpal", level = 5, lastSeen = mainNs.wallclock() }
      retire(H, main)
      local before = snapshot(saved)
      local alt, altNs = H.client("Loner", { noGuild = true })
      alt.state.guids.player = "Player-9-0002"
      alt.env.TwizCrewDB = saved
      H.link(alt)
      login(alt)
      H.advance(5 * 60)
      A.eq(#alt.sent, 0)
      A.eq(saved.guild.name, "Crew Guild", "nothing swapped")
      A.eq(altNs.roster:names(), { "Frostie", "Oldpal" }, "nothing hidden")
      A.eq(snapshot(saved), before, "nothing rewritten")
      noErrors(A, altNs)
    end,

    -- Two copies give a namesake pair OPPOSITE keys: names on the wire (first word, or full name when shared) still
    -- land on the right person: a mock, a quest share ask, a vote (candidates, ballot, result) and an award card.
    namesakes_with_opposite_keys_land_on_the_right_person = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      local cd, cdNs = H.client("Chaos Deathbringr", { class = "WARRIOR" })
      local co, coNs = H.client("Chaos Other", { class = "ROGUE" })
      tw.env.TwizCrewDB = { guild = { name = "Crew Guild",
        keys = { ["chaos deathbringr"] = "Chaos", ["chaos other"] = "Chaos Other" } } }
      fr.env.TwizCrewDB = { guild = { name = "Crew Guild",
        keys = { ["chaos other"] = "Chaos", ["chaos deathbringr"] = "Chaos Deathbringr" } } }
      H.link(tw, fr, cd, co)
      for _, W in ipairs({ tw, fr, cd, co }) do login(W) end
      H.advance(40)
      A.eq(twNs.Guild.keyOf("Chaos Other"), "Chaos Other")
      A.eq(frNs.Guild.keyOf("Chaos Other"), "Chaos", "Frostie's copy: the opposite keys")
      -- a mock from Twiz at Chaos Other (his key "Chaos Other")
      twNs.Roasts.mock("Chaos Other")
      H.advance(2)
      A.ok(coNs.MockShow.isShown(), "Chaos Other sees it is about him")
      A.no(cdNs.MockShow.isShown(), "Deathbringr does not")
      local about
      for _, e in ipairs(frNs.Feed.entries()) do if e.kind == "mock" then about = e.other end end
      A.eq(about, "Chaos", "Frostie's feed files it under her key for Chaos Other")
      -- a quest share ask from Frostie to her "Chaos" (Chaos Other), seen by both namesakes in the group
      local asked = {}
      for _, x in ipairs({ { cdNs, "cd" }, { coNs, "co" } }) do
        local ns, tag = x[1], x[2]
        ns.Popups.questRequest = function(name) asked[tag] = name end
      end
      for _, W in ipairs({ tw, fr, cd, co }) do W.state.inGroup = true end
      for _, text in ipairs(frNs.Codec.encode("QREQ", { t = frNs.wireName("Chaos"), q = "Kobold Camp Cleanup" })) do
        cd:fire("CHAT_MSG_ADDON", "TwizCrew", text, "PARTY", "Frostie")
        co:fire("CHAT_MSG_ADDON", "TwizCrew", text, "PARTY", "Frostie")
      end
      A.eq(asked.co, "Frostie", "Chaos Other is asked")
      A.eq(asked.cd, nil, "Deathbringr is not")
      -- a v0.1.24-style first word: dropped when shared, read when unique
      A.no(coNs.wireIsMe("Chaos")); A.no(cdNs.wireIsMe("Chaos"))
      A.eq(frNs.fromWire("Frostie"), "Frostie")
      -- the vote and a card, Twiz presenting, Frostie's copy viewing
      local wire = twNs.ShowLogic.voteToWire("Twiz-1", { "Chaos", "Chaos Other", "Frostie", "Twiz" }, 30)
      A.eq(wire.c, "Chaos Deathbringr,Chaos Other,Frostie,Twiz")
      for _, text in ipairs(twNs.Codec.encode("AWS", { id = "Twiz-1", v = "session" })) do
        fr:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Twiz")
      end
      local card = twNs.ShowLogic.cardToWire("Twiz-1", 1, { kind = "award",
        award = { def = twNs.StatsDefs.AWARDS[1], winners = { "Chaos Other" } } })
      A.eq(card.w, "Chaos Other")
      for _, text in ipairs(twNs.Codec.encode("AWC", card)) do
        fr:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Twiz")
      end
      for _, text in ipairs(twNs.Codec.encode("AWV", wire)) do
        fr:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Twiz")
      end
      local st = frNs.AwardsShow.stateForTest()
      A.eq(st.buttons, { "Chaos", "Chaos Deathbringr", "Twiz" }, "candidates as Frostie's keys")
      local mark = #fr.sent
      A.ok(frNs.AwardsShow.pressForTest("Chaos"), "Frostie votes for her Chaos (Chaos Other)")
      H.advance(2)
      local ballot
      for k = mark + 1, #fr.sent do
        local msg = frNs.Codec.decode(fr.sent[k].text)
        if msg and msg.type == "AWB" then ballot = msg.fields.c end
      end
      A.eq(ballot, "Chaos Other", "the ballot carries the presenter's name for him")
      for _, text in ipairs(twNs.Codec.encode("AWR", { id = "Twiz-1", w = "Chaos Other", n = "1" })) do
        fr:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Twiz")
      end
      A.eq(frNs.db.stats.clown.names, { "Chaos" }, "Frostie's copy files the clown under her key for him")
      noErrors(A, twNs, frNs, cdNs, coNs)
    end,

    a_thirty_letter_full_name_survives_the_vote_and_the_trophy_record = function(_, A, _, H)
      local long = "Abcdefghijklmn Opqrstuvwxyzabc" -- 30 letters
      local tw, twNs = H.client("Twiz")
      local lg, lgNs = H.client(long, { class = "MAGE" })
      local ab = H.client("Abcdefghijklmn Other", { class = "ROGUE" })
      H.link(tw, lg, ab)
      login(tw); login(lg); login(ab)
      H.advance(30)
      local key = twNs.Guild.keyOf(long)
      A.eq(twNs.wireName(key), long, "shared first word: the full name")
      local f = twNs.ShowLogic.voteToWire("Twiz-1", { key, "Twiz" }, 30)
      local v = lgNs.ShowLogic.voteFromWire(f)
      A.ok(v.raw[long] or v.raw[lgNs.Util.safeText(long)], "the whole name arrives in AWV")
      local people = {}
      for i = 1, 9 do people[i] = string.format("Member%02d Withalongsurname", i) end
      people[#people + 1] = long
      table.sort(people)
      local r = { sid = "Twiz-1", start = 1, people = people, winners = { [twNs.StatsDefs.AWARDS[1].id] = { long } } }
      local merged = {}
      for _, text in ipairs(twNs.Codec.encode("TRP", twNs.TrophyLogic.toWire(r),
        { repeatKeys = { "s", "k", "t", "l", "e" } })) do
        local msg = twNs.Codec.decode(text)
        for k2, x in pairs(msg.fields) do merged[k2] = x end
      end
      local back = twNs.TrophyLogic.fromPieces(merged)
      A.ok(back, "a whole record from the pieces")
      A.eq(back.people, people, "every name whole")
      A.eq(back.winners[twNs.StatsDefs.AWARDS[1].id], { long })
      noErrors(A, twNs, lgNs)
    end,

    -- My own numbers are account-wide, by my first word; in each guild's data they show under my key there.
    a_namesake_characters_numbers_follow_it_across_guilds = function(_, A, _, H)
      local function entries(ns)
        local out = {}
        for _, e in ipairs(ns.StatsStore.entries("all")) do out[e.name] = e end
        return out
      end
      local me, meNs = H.client("Chaos Other", { class = "ROGUE" })
      H.guild("Guild A", me, { { name = "Chaos Deathbringr", class = "WARRIOR" } })
      me.env.TwizCrewDB = { guild = { name = "Guild A", keys = { ["chaos deathbringr"] = "Chaos" } } }
      H.link(me)
      login(me)
      H.advance(30)
      local saved = meNs.db
      A.eq(saved.guild.name, "Guild A")
      A.eq(meNs.myKey(), "Chaos Other")
      meNs.Stats.count("dt", 2)
      saved.stats.crew.Chaos = { sid = "x", s = {}, a = { dt = 9 }, at = meNs.wallclock() }
      local rows = entries(meNs)
      A.ok(rows["Chaos Other"] and rows["Chaos Other"].mine, "my row, under my key here")
      A.eq(rows["Chaos Other"].stats.dt, 2)
      A.ok(rows.Chaos and not rows.Chaos.mine, "the friend Chaos, apart")
      A.eq(rows.Chaos.stats.dt, 9)
      retire(H, me)
      -- the same character, now in guild B: the first login says /reload, the second has guild B's data
      local me2 = H.client("Chaos Other", { class = "ROGUE" })
      H.guild("Guild B", me2, { { name = "Stranger Person" } })
      me2.env.TwizCrewDB = saved
      H.link(me2)
      login(me2)
      H.advance(30)
      retire(H, me2)
      local me3, me3Ns = H.client("Chaos Other", { class = "ROGUE" })
      H.guild("Guild B", me3, { { name = "Stranger Person" } })
      me3.env.TwizCrewDB = saved
      H.link(me3)
      login(me3)
      H.advance(30)
      A.eq(saved.guild.name, "Guild B")
      A.eq(me3Ns.myKey(), "Chaos", "alone with my first word here")
      rows = entries(me3Ns)
      A.ok(rows.Chaos and rows.Chaos.mine, "my row, under my key here")
      A.eq(rows.Chaos.stats.dt, 2, "the same numbers")
      A.eq(rows["Chaos Other"], nil, "no stale row of mine")
      A.eq(saved.stats.chars.Chaos.a.dt, 2)
      noErrors(A, me3Ns)
    end,

    -- A character in no guild keeps its own session across logins (account-wide, per character), never a guild's.
    a_guildless_character_keeps_its_session_across_logins = function(_, A, _, H)
      local saved = { guild = { name = "Crew Guild" }, stats = { session = { id = "Frostie-1", start = 1, manual = false,
        lastActive = 1700000000 } } }
      local lo, loNs = H.client("Loner", { noGuild = true })
      lo.state.guids.player = "Player-9-0003"
      lo.env.TwizCrewDB = saved
      H.link(lo)
      login(lo)
      H.advance(30)
      local first = loNs.Session.current().id
      A.ok(first ~= "Frostie-1", "the guild's session is not mine")
      A.eq(saved.solo["Player-9-0003"].session.id, first)
      A.eq(saved.stats.session.id, "Frostie-1", "the guild's saved session untouched")
      retire(H, lo)
      local lo2, lo2Ns = H.client("Loner", { noGuild = true })
      lo2.state.guids.player = "Player-9-0003"
      lo2.env.TwizCrewDB = saved
      H.link(lo2)
      login(lo2)
      H.advance(30)
      A.eq(lo2Ns.Session.current().id, first, "the same session after a short break")
      noErrors(A, lo2Ns)
    end,

    -- (a2) v0.1.24 main, 8 of 10 fit, but three sessions end after 2 s, before the list is complete: nothing is
    -- decided or parked meanwhile; the next full session adopts the old data with everything in it.
    old_data_survives_short_sessions_before_the_list_is_complete = function(_, A, _, H)
      local saved = oldSave()
      for n = 1, 3 do
        mainSession(H, saved, "Crew Guild", guildOf(8), 2, { guildListDelay = 8 })
        A.eq(saved.guild.name, nil, "session " .. n .. ": still unnamed")
        A.eq(next(saved.guilds), nil, "session " .. n .. ": nothing parked")
        A.eq(saved.guild.byChar[MAIN], nil, "session " .. n .. ": no guild remembered for unnamed data")
        oldDataOnTop(A, saved, "session " .. n)
      end
      local W, ns = mainSession(H, saved, "Crew Guild", guildOf(8), 30, { guildListDelay = 8 }, true)
      A.eq(saved.guild.name, "Crew Guild", "adopted")
      A.ok(ns.Guild.active())
      oldDataOnTop(A, saved, "adopted")
      A.eq(next(saved.guilds), nil, "nothing parked")
      A.eq(saved.guild.byChar[MAIN], "Crew Guild", "remembered once the data is this guild's")
      noErrors(A, ns)
      retire(H, W)
    end,

    -- (b, first part) 3 of 10: the player types nothing for five logins: the old data stays on top, unnamed, and the
    -- choice line shows once in each session.
    old_data_with_three_of_ten_stays_through_five_quiet_logins = function(_, A, _, H)
      local saved = oldSave()
      for n = 1, 5 do
        local W, ns = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
        A.eq(countPrinted(W, "If Crew Guild is your crew's guild, type /tc guild use."), 1, "login " .. n .. ": told once")
        A.no(ns.Guild.active())
        A.eq(groupless(W.sent), 0, "login " .. n .. ": quiet")
        noErrors(A, ns)
        retire(H, W)
        A.eq(saved.guild.name, nil, "login " .. n .. ": unnamed")
        A.eq(next(saved.guilds), nil, "login " .. n .. ": nothing parked")
        oldDataOnTop(A, saved, "login " .. n)
      end
    end,

    -- (a) v0.1.24 main, 8 of 10 fit, a normal login: adopted at once, everything kept, nothing parked. (A friend not
    -- seen for 70 days and not in the guild is forgotten, as always once the data is this guild's.)
    old_data_with_eight_of_ten_is_adopted_at_login = function(_, A, _, H)
      local saved = oldSave()
      saved.roster.Oldpal = { name = "Oldpal", level = 9, lastSeen = 1700000000 - 70 * 86400 }
      local W, ns = mainSession(H, saved, "Crew Guild", guildOf(8), 30, nil, true)
      A.eq(saved.guild.name, "Crew Guild"); A.ok(ns.Guild.active())
      oldDataOnTop(A, saved, "adopted")
      A.eq(saved.roster.Oldpal, nil, "the usual 60-day rule")
      A.eq(next(saved.guilds), nil); A.eq(saved.guild.byChar[MAIN], "Crew Guild")
      for k = 1, 10 do A.eq(saved.pins["Friend" .. string.char(64 + k)], true, "the old crew is pinned") end
      A.eq(saved.guild.pinnedOld, true)
      noErrors(A, ns)
      retire(H, W)
      saved.pins.FriendA = nil -- the player unpins someone: it stays that way
      local _, ns2 = mainSession(H, saved, "Crew Guild", guildOf(8), 20)
      A.eq(saved.pins.FriendA, nil, "pinned once only"); A.eq(saved.pins.FriendB, true)
      noErrors(A, ns2)
    end,

    -- (b) 3 of 10 (and a friend unseen for 70 days): quiet, one line. /tc guild use says why it will not and how to
    -- insist; /tc guild use yes adopts, and nothing old is forgotten in that session.
    old_data_with_three_of_ten_and_tc_guild_use_yes = function(_, A, _, H)
      local saved = oldSave()
      saved.roster.Oldpal = { name = "Oldpal", level = 9, lastSeen = 1700000000 - 70 * 86400 }
      saved.stats.crew.Oldpal = { sid = "x", s = {}, a = { dt = 5 } }
      local tw, twNs = mainSession(H, saved, "Crew Guild", guildOf(3), 60, nil, true)
      A.eq(groupless(tw.sent), 0, "quiet")
      A.no(twNs.Guild.active())
      A.eq(countPrinted(tw, "If Crew Guild is your crew's guild, type /tc guild use."), 1, "told once")
      A.eq(saved.guild.name, nil, "nothing decided for good")
      tc(tw, "report")
      A.eq(countPrinted(tw, "in a guild, but the saved data is not this guild's (see /tc guild)"), 1)
      tc(tw, "guild")
      A.eq(countPrinted(tw, "0: from before guilds (in use), 11 friends, last seen "), 1)
      tc(tw, "guild use")
      A.ok(printed(tw, "TwizCrew: Only 3 of 11 saved friends are in Crew Guild. If this really is your crew's guild,"
        .. " type /tc guild use yes."))
      H.advance(5)
      A.no(twNs.Guild.active(), "refused"); A.eq(saved.guild.name, nil)
      tc(tw, "guild use yes")
      A.ok(printed(tw, "TwizCrew: the saved data in use now belongs to Crew Guild."))
      H.advance(15)
      A.ok(twNs.Guild.active())
      A.eq(saved.guild.name, "Crew Guild"); A.eq(saved.guild.byChar[MAIN], "Crew Guild")
      A.ok(groupless(tw.sent) > 0, "sends now")
      A.eq(#twNs.roster:allNames(), 11, "every old friend kept (8 of them hidden)")
      A.eq(twNs.roster:names(), { "FriendA", "FriendB", "FriendC" })
      A.ok(saved.roster.Oldpal, "nothing old forgotten: the list does not fit the saved friends")
      A.eq(saved.pins.FriendJ, true, "use yes pins the old crew too")
      A.eq(saved.stats.crew.Oldpal.a.dt, 5)
      oldDataOnTop(A, saved, "use yes")
      A.eq(next(saved.guilds), nil)
      noErrors(A, twNs)
    end,

    -- (c) /tc guild new and a /reload: a fresh set, the old data parked and listed. The player regrets it: /tc guild
    -- load brings the old data back on top for this guild after a /reload; the fresh set is parked and listed.
    old_data_with_three_of_ten_tc_guild_new_then_load_back = function(_, A, _, H)
      local saved = oldSave()
      local tw = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
      tc(tw, "guild new")
      A.ok(printed(tw, "TwizCrew: Crew Guild gets its own fresh saved data. Type /reload to start it; nothing saved is"
        .. " deleted."))
      A.eq(saved.guild.request, { kind = "new", guild = "Crew Guild", char = MAIN })
      tc(tw, "guild")
      A.ok(printed(tw, "TwizCrew: waiting for your next login: a fresh set for Crew Guild."))
      retire(H, tw)
      local tw2, tw2Ns = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
      A.eq(countPrinted(tw2, "TwizCrew: Your /tc guild request was carried out."), 1)
      A.eq(countPrinted(tw2, "starts with new TwizCrew data"), 0, "(asked for: no extra line)")
      A.eq(saved.guild.name, "Crew Guild"); A.ok(tw2Ns.Guild.active())
      A.eq(next(saved.roster), nil, "a fresh set")
      A.eq(saved.guilds[""].roster.FriendJ.name, "FriendJ", "the old data, parked")
      A.eq(saved.guilds[""].stats.trophies.old.sid, "old")
      A.eq(saved.guild.request, nil, "the request was used once")
      A.eq(saved.guild.byChar[MAIN], "Crew Guild")
      tc(tw2, "guild")
      A.eq(countPrinted(tw2, "0: Crew Guild (in use), 0 friends"), 1)
      A.eq(countPrinted(tw2, "1: from before guilds, 10 friends, last seen "), 1)
      tc(tw2, "guild use")
      A.ok(printed(tw2, "TwizCrew: the saved data in use is already Crew Guild's."))
      tc(tw2, "guild load 1")
      A.ok(printed(tw2, "TwizCrew: This will make set 1 (from before guilds, 10 friends) the data for Crew Guild. The"
        .. " data in use now is kept as a parked set. Type /tc guild load 1 yes."))
      A.eq(saved.guild.request, nil, "asked first")
      tc(tw2, "guild load 1 yes")
      A.ok(printed(tw2, "TwizCrew: Type /reload."))
      A.eq(saved.guild.request, { kind = "load", guild = "Crew Guild", char = MAIN, from = "guilds", key = "" })
      retire(H, tw2)
      local tw3, tw3Ns = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
      A.eq(countPrinted(tw3, "TwizCrew: Your /tc guild request was carried out."), 1)
      A.eq(saved.guild.name, "Crew Guild"); A.ok(tw3Ns.Guild.active())
      oldDataOnTop(A, saved, "loaded back")
      A.eq(saved.guilds[""], nil)
      A.eq(next(saved.guilds["Crew Guild (replaced)"].roster), nil, "the fresh set, parked")
      A.eq(saved.guild.request, nil)
      tc(tw3, "guild")
      A.eq(countPrinted(tw3, "1: Crew Guild (replaced), 0 friends"), 1, "and listed")
      noErrors(A, tw3Ns)
    end,

    -- Item 2: /tc guild new when this guild already has a parked set: refused, and the /reload switches to that set.
    tc_guild_new_never_makes_a_second_set_for_a_guild = function(_, A, _, H)
      local saved = oldSave()
      saved.guild = { byChar = {} }
      saved.guilds = { ["Crew Guild"] = { roster = { Mine = { name = "Mine", level = 3, lastSeen = 1700000000 } } } }
      local tw, twNs = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
      A.no(twNs.Guild.active())
      A.eq(countPrinted(tw, "TwizCrew: Crew Guild has its own saved data. Type /reload to switch to it."), 1)
      tc(tw, "guild new")
      A.ok(printed(tw, "TwizCrew: Crew Guild already has saved TwizCrew data. Type /reload to switch to it."))
      A.eq(saved.guild.request, nil, "no fresh set asked for")
      A.eq(saved.guild.byChar[MAIN], "Crew Guild")
      retire(H, tw)
      local tw2, tw2Ns = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
      A.eq(saved.guild.name, "Crew Guild"); A.ok(tw2Ns.Guild.active())
      A.eq(saved.roster.Mine.level, 3, "its own set")
      A.eq(saved.guilds[""].roster.FriendJ.name, "FriendJ", "the old data parked, unnamed")
      noErrors(A, tw2Ns)
    end,

    -- Item 3: a /tc guild new request is one shot: /tc guild use cancels it, and any other login uses it up.
    tc_guild_new_request_never_goes_stale = function(_, A, _, H)
      local saved = oldSave()
      local tw = mainSession(H, saved, "Crew Guild", guildOf(3), 30, nil, true)
      tc(tw, "guild new")
      tc(tw, "guild use yes")
      A.eq(saved.guild.request, nil, "use cancels it")
      retire(H, tw)
      local _, ns = mainSession(H, saved, "Crew Guild", guildOf(3), 30)
      A.eq(saved.guild.name, "Crew Guild"); oldDataOnTop(A, saved, "after use")
      A.eq(next(saved.guilds), nil, "no fresh set")
      noErrors(A, ns)
      -- another new request, then an alt logs in first: used up, never carried out later
      local saved2 = oldSave()
      local tw3 = mainSession(H, saved2, "Crew Guild", guildOf(3), 30, nil, true)
      tc(tw3, "guild new")
      retire(H, tw3)
      local alt = altIn(H, "Other Guild", saved2)
      H.advance(30)
      retire(H, alt)
      A.eq(saved2.guild.request, nil, "used up at the alt's login")
      A.eq(saved2.guild.name, nil); A.eq(next(saved2.guilds), nil)
      A.eq(saved2.guild.requestResult, { char = MAIN, kind = "new", done = false,
        reason = "another character logged in first" })
      local tw4 = mainSession(H, saved2, "Crew Guild", guildOf(3), 30)
      A.eq(countPrinted(tw4, "TwizCrew: Your /tc guild request was not carried out: another character logged in"
        .. " first. Type /tc guild."), 1)
      A.eq(saved2.guild.requestResult, nil)
      A.eq(saved2.guild.name, nil, "the main's next login: nothing made by an old request")
      oldDataOnTop(A, saved2, "after the alt")
      A.eq(next(saved2.guilds), nil)
    end,

    -- (e) An alt types /tc guild use yes on the main's old data by mistake (nothing forgotten that session). The main
    -- recovers it with /tc guild load: every row and number is back, friends unseen for 60+ days included.
    a_mistaken_use_yes_on_an_alt_is_undone_with_load = function(_, A, _, H)
      local saved = oldSave()
      for _, name in ipairs({ "Oldpal", "Oldbuddy" }) do
        saved.roster[name] = { name = name, level = 9, lastSeen = 1700000000 - 70 * 86400 }
        saved.stats.crew[name] = { sid = "x", s = {}, a = { dt = 7 } }
      end
      local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
      local rows, stats = count(saved.roster), count(saved.stats.crew)
      local function everything(when)
        oldDataOnTop(A, saved, when)
        A.ok(saved.roster.Oldpal and saved.roster.Oldbuddy, when .. ": friends unseen for 70 days")
        A.eq(saved.stats.crew.Oldbuddy.a.dt, 7, when)
        A.ok(count(saved.roster) >= rows and count(saved.stats.crew) >= stats, when .. ": no row or number deleted")
      end
      -- the main's guild: eight of the old friends, and the two not seen for 70 days are still members (offline)
      local mainGuild = guildOf(8)
      mainGuild[#mainGuild + 1] = { name = "Oldpal Person" }
      mainGuild[#mainGuild + 1] = { name = "Oldbuddy Person" }
      local alt, altNs = altIn(H, "Other Guild", saved)
      H.advance(30)
      tc(alt, "guild use")
      A.ok(printed(alt, "TwizCrew: Only 0 of 12 saved friends are in Other Guild. If this really is your crew's guild,"
        .. " type /tc guild use yes."))
      tc(alt, "guild use yes")
      H.advance(30)
      A.eq(saved.guild.name, "Other Guild"); A.ok(altNs.Guild.active())
      everything("the alt's session")
      noErrors(A, altNs)
      retire(H, alt)
      for n = 1, 2 do -- the alt logs in twice more before the main notices: the list does not fit, nothing is pruned
        local a, aNs = altIn(H, "Other Guild", saved)
        H.advance(30)
        A.ok(aNs.Guild.active(), "alt login " .. n)
        A.no(aNs.Guild.listFits(), "alt login " .. n .. ": the list does not fit the friends")
        everything("alt login " .. n)
        noErrors(A, aNs)
        retire(H, a)
      end
      local main = mainSession(H, saved, "Crew Guild", mainGuild, 30, nil, true)
      A.ok(printed(main, "TwizCrew keeps separate data for each guild. Type /reload to switch to Crew Guild."))
      retire(H, main)
      local main2, main2Ns = mainSession(H, saved, "Crew Guild", mainGuild, 30, nil, true)
      A.eq(saved.guild.name, "Crew Guild"); A.eq(next(saved.roster), nil, "a set of its own, empty")
      A.eq(countPrinted(main2, "TwizCrew: Crew Guild starts with new TwizCrew data. You have other saved sets: type"
        .. " /tc guild."), 1)
      A.ok(saved.guilds["Other Guild"].roster.Oldpal, "the old data, parked as Other Guild's")
      tc(main2, "guild")
      A.eq(countPrinted(main2, "1: Other Guild, 13 friends, last seen "), 1, "(the alt met Stranger)")
      tc(main2, "guild load 1")
      tc(main2, "guild load 1 yes")
      A.ok(printed(main2, "TwizCrew: Type /reload."))
      noErrors(A, main2Ns)
      retire(H, main2)
      local main3, main3Ns = mainSession(H, saved, "Crew Guild", mainGuild, 30, nil, true)
      A.eq(countPrinted(main3, "TwizCrew: Your /tc guild request was carried out."), 1)
      A.eq(saved.guild.name, "Crew Guild"); A.ok(main3Ns.Guild.active())
      A.ok(main3Ns.Guild.listFits(), "the main's list fits: the usual rule runs, and keeps its members")
      everything("recovered")
      A.eq(saved.guilds["Other Guild"], nil)
      A.ok(saved.guilds["Crew Guild (replaced)"], "the empty set, parked")
      A.eq(saved.guild.byChar[MAIN], "Crew Guild"); A.eq(saved.guild.byChar[ALT], "Other Guild")
      A.eq(saved.guild.requestResult, nil, "told once, then cleared")
      noErrors(A, main3Ns)
      retire(H, main3)
    end,

    -- Round 5 (1b): on a game that never names guilds, an alt in another guild is active on the shared "?" set and
    -- forgets nothing of the main's (its list does not fit them).
    no_name_alt_on_the_shared_set_prunes_nothing = function(_, A, _, H)
      local saved = oldSave()
      saved.guild = { name = "?" }
      saved.roster.Oldpal = { name = "Oldpal", level = 9, lastSeen = 1700000000 - 70 * 86400 }
      saved.stats.crew.Oldpal = { sid = "x", s = {}, a = { dt = 7 } }
      local W, ns = H.client("Altie", { guildNameHidden = true })
      W.state.guids.player = ALT
      H.guild("Other Guild", W, { { name = "Zed Zed" } })
      W.env.TwizCrewDB = saved
      H.link(W)
      login(W)
      H.advance(ns.Config.GUILD_NAME_WAIT + 30)
      A.ok(ns.Guild.active(), "the shared set"); A.ok(ns.Guild.complete()); A.no(ns.Guild.listFits())
      A.ok(saved.roster.Oldpal, "nothing pruned"); A.eq(saved.stats.crew.Oldpal.a.dt, 7)
      oldDataOnTop(A, saved, "after the alt")
      noErrors(A, ns)
    end,

    -- Round 5 (1c): a character that changed guild while offline is active on its old guild's set during a nameless
    -- gap (byChar): its new guild's list does not fit, nothing is pruned.
    a_character_in_a_new_guild_during_a_nameless_gap_prunes_nothing = function(_, A, _, H)
      local saved = oldSave()
      saved.guild = { name = "Crew Guild", named = true, byChar = { [MAIN] = "Crew Guild" } }
      saved.roster.Oldpal = { name = "Oldpal", level = 9, lastSeen = 1700000000 - 70 * 86400 }
      local W, ns = mainSession(H, saved, "New Guild", { { name = "Zed Zed" } }, 40, { guildNameHidden = true }, true)
      A.ok(ns.Guild.active(), "active by byChar while nameless"); A.no(ns.Guild.listFits())
      A.ok(saved.roster.Oldpal, "nothing pruned")
      oldDataOnTop(A, saved, "nameless gap")
      noErrors(A, ns)
      retire(H, W)
    end,

    -- Round 5 (2): on a game that never names guilds, load parks the shared set as "? (replaced)" and every command
    -- still works afterwards: the set can be loaded back.
    no_name_load_and_load_back = function(_, A, _, H)
      local saved = { guild = { name = "?" }, roster = { Qone = { name = "Qone", lastSeen = 1700000000 } },
        guilds = { [""] = { roster = { Lone = { name = "Lone" }, Ltwo = { name = "Ltwo" } } } } }
      local hidden = { guildNameHidden = true }
      local W, ns = mainSession(H, saved, "Crew Guild", guildOf(2), 25, hidden, true)
      A.ok(ns.Guild.active())
      tc(W, "guild load 1"); tc(W, "guild load 1 yes")
      A.ok(printed(W, "TwizCrew: Type /reload."))
      retire(H, W)
      W, ns = mainSession(H, saved, "Crew Guild", guildOf(2), 25, hidden, true)
      A.eq(saved.guild.name, "?"); A.ok(saved.roster.Lone); A.ok(ns.Guild.active())
      A.eq(saved.guilds["? (replaced)"].roster.Qone.name, "Qone")
      A.no(saved.guild.named, "no real guild name was ever read")
      tc(W, "guild")
      A.eq(countPrinted(W, "1: ? (replaced), 1 friend"), 1)
      tc(W, "guild load 1")
      A.eq(countPrinted(W, "This will make set 1 (? (replaced), 1 friend) the data for this guild."), 1)
      tc(W, "guild load 1 yes")
      A.ok(printed(W, "TwizCrew: Type /reload."))
      noErrors(A, ns)
      retire(H, W)
      W, ns = mainSession(H, saved, "Crew Guild", guildOf(2), 25, hidden, true)
      A.eq(saved.guild.name, "?"); A.ok(saved.roster.Qone, "back")
      A.ok(saved.guilds["? (replaced)"].roster.Lone, "and the other set parked")
      A.eq(saved.guilds[""], nil)
      noErrors(A, ns)
      retire(H, W)
    end,

    -- (f) A main in guild A and an alt in guild B, both with sets, alternating five times: each login is on its own
    -- guild's data at once (no /reload), and nothing mixes.
    main_and_alt_alternate_between_their_guild_sets = function(_, A, _, H)
      local saved = {}
      local function main(n)
        local W, ns = mainSession(H, saved, "Guild A", { { name = "Annie Alpha", class = "MAGE" } }, 20, nil, true)
        return W, ns
      end
      local W, ns = main()
      A.eq(saved.guild.name, "Guild A")
      retire(H, W)
      local alt = altIn(H, "Guild B", saved) -- first login: Guild A's set on top: the /reload line
      H.advance(20)
      retire(H, alt)
      for n = 1, 5 do
        local a, aNs = altIn(H, "Guild B", saved)
        H.advance(20)
        A.eq(saved.guild.name, "Guild B", "round " .. n .. ": the alt on Guild B's set")
        A.ok(aNs.Guild.active(), "round " .. n .. ": at once")
        A.ok(saved.guild.keys.stranger and not saved.guild.keys["annie alpha"], "round " .. n .. ": B's keys only")
        A.eq(saved.guilds["Guild A"].guild.keys["annie alpha"], "Annie", "round " .. n .. ": A's set parked whole")
        noErrors(A, aNs)
        retire(H, a)
        W, ns = main()
        A.eq(saved.guild.name, "Guild A", "round " .. n .. ": the main on Guild A's set")
        A.ok(ns.Guild.active(), "round " .. n .. ": at once")
        A.ok(saved.guild.keys["annie alpha"] and not saved.guild.keys.stranger, "round " .. n .. ": A's keys only")
        A.ok(saved.guilds["Guild B"].guild.keys.stranger, "round " .. n .. ": B's set parked whole")
        A.eq(saved.guild.byChar, { [MAIN] = "Guild A", [ALT] = "Guild B" })
        noErrors(A, ns)
        retire(H, W)
      end
      local count = 0
      for _ in pairs(saved.guilds) do count = count + 1 end
      A.eq(count, 1, "one parked set, never a copy")
    end,

    -- (j) A fresh install: the first guild takes the empty data at once.
    a_fresh_install_belongs_to_the_first_guild = function(_, A, _, H)
      local saved = {}
      local W, ns = mainSession(H, saved, "Crew Guild", guildOf(2), 20, nil, true)
      A.eq(saved.guild.name, "Crew Guild"); A.ok(ns.Guild.active())
      A.eq(saved.guild.byChar[MAIN], "Crew Guild"); A.eq(next(saved.guilds), nil)
      A.eq(next(saved.pins), nil, "nobody pinned on a fresh install")
      A.eq(countPrinted(W, "starts with new TwizCrew data"), 0)
      noErrors(A, ns)
      retire(H, W)
    end,

    -- (d) An alt in an unrelated guild opens the old data first and types nothing, three logins: quiet, one line each
    -- time, nothing named, parked or remembered. Then the main (8 of 10 fit): adopted at its first login.
    old_data_first_on_an_alt_then_the_main_with_eight_of_ten = function(_, A, _, H)
      local saved = oldSave()
      for n = 1, 3 do
        local alt, altNs = altIn(H, "Other Guild", saved)
        H.advance(30)
        A.eq(groupless(alt.sent), 0, "alt login " .. n .. ": quiet")
        A.no(altNs.Guild.active())
        A.eq(countPrinted(alt, "If Other Guild is your crew's guild, type /tc guild use."), 1, "alt login " .. n)
        noErrors(A, altNs)
        retire(H, alt)
        A.eq(saved.guild.name, nil, "alt login " .. n .. ": unnamed")
        A.eq(next(saved.guilds), nil, "alt login " .. n .. ": nothing parked")
        A.eq(saved.guild.byChar[ALT], nil, "alt login " .. n .. ": no guild remembered")
        oldDataOnTop(A, saved, "alt login " .. n)
      end
      local main, mainNs = mainSession(H, saved, "Crew Guild", guildOf(8), 30, nil, true)
      A.eq(saved.guild.name, "Crew Guild", "8 of 10: adopted at the first login")
      A.ok(mainNs.Guild.active())
      A.no(printed(main, "TwizCrew keeps separate data for each guild. Type /reload to switch to Crew Guild."))
      oldDataOnTop(A, saved, "adopted")
      A.eq(next(saved.guilds), nil, "nothing parked")
      A.eq(saved.guild.byChar[MAIN], "Crew Guild"); A.eq(saved.guild.byChar[ALT], nil)
      noErrors(A, mainNs)
    end,

    -- (4) The game never names the guild: the main's old data becomes "?" and stays in use across logins whatever the
    -- members do; an alt in another (also unnamed) guild uses the same "?" data (the accepted limitation); a name
    -- read later renames it.
    no_guild_name_single_guild_mode = function(_, A, _, H)
      local saved = oldSave()
      local function session(name, guildName, members, nameHidden)
        local W, ns = H.client(name)
        W.state.guildNameHidden = nameHidden
        H.guild(guildName, W, members)
        W.env.TwizCrewDB = saved
        H.link(W)
        login(W)
        H.advance(ns.Config.GUILD_NAME_WAIT + 20)
        return W, ns
      end
      local w, ns = session("Twiz", "Crew Guild", guildOf(8), true)
      A.eq(saved.guild.name, "?"); A.ok(ns.Guild.active())
      retire(H, w)
      for round = 1, 3 do -- heavy churn: nobody from before is listed any more
        local churn = {}
        for k = 1, 6 do churn[k] = { name = "Newbie" .. round .. k .. " Person" } end
        w, ns = session("Twiz", "Crew Guild", churn, true)
        A.ok(ns.Guild.active(), "login " .. round .. ": still in use")
        A.eq(saved.guild.name, "?")
        retire(H, w)
      end
      w, ns = session("Altie", "Other Guild", { { name = "Zed Zed" } }, true)
      A.ok(ns.Guild.active(), "the alt uses the same \"?\" data")
      retire(H, w)
      A.eq(next(saved.guild.byChar), nil, "no byChar without a readable name"); A.eq(next(saved.guilds), nil)
      w, ns = session("Twiz", "Crew Guild", guildOf(8), false)
      A.eq(saved.guild.name, "Crew Guild", "renamed once the name is readable (8 of 10 fit)")
      A.ok(ns.Guild.active())
      A.eq(#ns.roster:allNames(), 10)
      A.eq(next(saved.guilds), nil); A.eq(saved.guild.byChar[ns.DB.charId()], "Crew Guild")
      noErrors(A, ns)
    end,

    -- (5) A switch from guild A to guild B mid-session: no key written into A's data, nothing sent, the /reload line.
    a_guild_switch_mid_session_touches_nothing = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      H.guild("Guild A", tw, { { name = "Frostie Snow" } })
      H.link(tw)
      login(tw)
      H.advance(30)
      A.eq(twNs.Guild.dataGuild(), "Guild A")
      local keys = {}
      for k, v in pairs(twNs.db.guild.keys) do keys[k] = v end
      local mark = #tw.sent
      tw.state.guild = { name = "Guild B", members = { { name = "Twiz", online = true, guid = "Player-1-0001" },
        { name = "Bob Builder", online = true, guid = "Player-1-0042" } } }
      tw:fire("PLAYER_GUILD_UPDATE")
      tw:fire("GUILD_ROSTER_UPDATE")
      H.advance(3)
      A.no(twNs.Guild.active(), "a switch pending: nothing counts")
      tw.state.zone = "Westfall"; tw:fire("ZONE_CHANGED_NEW_AREA")
      H.advance(30)
      tw:fire("GUILD_ROSTER_UPDATE")
      H.advance(30)
      local sent = 0
      for k = mark + 1, #tw.sent do if tw.sent[k].chatType ~= "PARTY" then sent = sent + 1 end end
      A.eq(sent, 0, "nothing sent into the new guild")
      A.eq(twNs.db.guild.keys, keys, "no key written into A's data")
      A.ok(printed(tw, "TwizCrew keeps separate data for each guild. Type /reload to switch to Guild B."))
      A.eq(twNs.db.guild.name, "Guild A"); A.eq(next(twNs.db.guilds), nil)
      A.eq(twNs.db.guild.byChar[twNs.DB.charId()], "Guild B", "the next login parks Guild A's set")
      noErrors(A, twNs)
    end,
  },
}
