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

    -- One TwizCrew guild per account: the home guild is set by the first guild message heard from another member.
    home_guild_is_set_by_the_first_guild_message_heard = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      H.link(tw)
      login(tw)
      H.advance(30)
      A.eq(twNs.Guild.home(), nil, "alone: my own messages prove nothing")
      A.eq(twNs.Transport.status().mode, "guild", "unset home: this guild is used")
      local fr = H.client("Frostie", { class = "MAGE" })
      H.link(fr)
      login(fr)
      H.advance(10)
      A.eq(twNs.Guild.home(), "Crew Guild")
      A.eq(twNs.db.guild.keysFor, "Crew Guild")
      noErrors(A, twNs)
    end,

    alt_in_another_guild_stays_quiet_and_the_main_is_unchanged = function(_, A, _, H)
      -- the main, in the home guild, with a friend and an old friend out of the guild
      local main, mainNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(main, fr)
      login(main)
      login(fr)
      H.advance(30)
      A.eq(mainNs.Guild.home(), "Crew Guild")
      mainNs.db.roster.Oldpal = { name = "Oldpal", level = 5, lastSeen = mainNs.wallclock() }
      main:fire("PLAYER_LOGOUT")
      H.advance(1)
      unlink(H, main)
      local saved = mainNs.db
      local keysBefore = {}
      for k, v in pairs(saved.guild.keys) do keysBefore[k] = v end
      -- an alt of the same account in another guild that also has a TwizCrew user
      local alt, altNs = H.client("Altie", { class = "PRIEST" })
      local other = H.client("Stranger", { class = "ROGUE" })
      H.guild("Other Guild", alt, other)
      alt.env.TwizCrewDB = saved
      H.link(alt, other)
      login(alt)
      login(other)
      H.advance(5 * 60)
      tc(alt, "report")
      local sent = 0
      for _, m in ipairs(alt.sent) do if m.chatType ~= "PARTY" and m.chatType ~= "RAID" then sent = sent + 1 end end
      A.eq(sent, 0, "zero sends in a foreign guild")
      A.eq(altNs.Transport.status().mode, "none")
      A.ok(altNs.Transport.status().foreign)
      A.eq(altNs.Guild.home(), "Crew Guild", "home unchanged by the other guild's messages")
      A.no(altNs.Guild.active()); A.no(altNs.Guild.loaded())
      A.eq(altNs.roster:get("Stranger"), nil, "their messages are not accepted")
      A.eq(altNs.roster:names(), { "Frostie", "Oldpal" }, "no row hidden")
      A.eq(saved.guild.keys, keysBefore, "no key written")
      A.eq(saved.guild.keysFor, "Crew Guild")
      local reported = false
      for _, line in ipairs(alt.printed) do
        if line:find("this character's guild (Other Guild) is not your TwizCrew guild (Crew Guild)", 1, true) then
          reported = true
        end
      end
      A.ok(reported, "/tc report says why")
      noErrors(A, altNs)
      alt:fire("PLAYER_LOGOUT")
      H.advance(1)
      unlink(H, alt)
      -- back on the main: as before
      local main2, main2Ns = H.client("Twiz")
      main2.state.guild = main.state.guild
      main2.env.TwizCrewDB = saved
      H.link(main2)
      login(main2)
      H.advance(30)
      A.eq(main2Ns.Transport.status().mode, "guild")
      A.ok(online(main2Ns, "Frostie"))
      A.ok(online(frNs, "Twiz"))
      A.eq(main2Ns.roster:names(), { "Frostie" }, "the old friend is hidden again in the home guild")
      noErrors(A, main2Ns, frNs)
    end,

    tc_home_here_switches_the_home_guild = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      H.guild("New Guild", tw)
      tw.env.TwizCrewDB = { guild = { home = "Old Guild", keysFor = "Old Guild", keys = { someone = "Someone" } } }
      H.link(tw)
      login(tw)
      H.advance(30)
      A.eq(#tw.sent, 0, "a foreign guild: quiet")
      tc(tw, "home")
      A.ok(tw.printed[#tw.printed]:find("Old Guild", 1, true), "/tc home names it")
      tc(tw, "home here")
      A.eq(tw.printed[#tw.printed], "TwizCrew: your TwizCrew guild is now New Guild.")
      A.eq(twNs.Guild.home(), "New Guild")
      H.advance(10)
      A.ok(twNs.Guild.active())
      A.eq(twNs.db.guild.keys.someone, nil, "the old guild's keys are gone")
      A.eq(twNs.db.guild.keys.twiz, "Twiz")
      local hellos = 0
      for _, m in ipairs(tw.sent) do if typeOf(m) == "HELLO" then hellos = hellos + 1 end end
      A.eq(hellos, 1, "now it says hello")
      noErrors(A, twNs)
    end,
  },
}
