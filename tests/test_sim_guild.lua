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
      local tw = H.client("Twiz")
      tw.env.TwizCrewDB = { crew = { channel = "TwizCrewHQ", password = "goldshire", extra = { "Frostie" } },
        modules = { comm = { enabled = true, settings = { transport = "auto", debug = false } } } }
      H.link(tw)
      login(tw)
      H.advance(10)
      A.eq(tw.leaves, { "TwizCrewHQ" })
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

    login_with_50_members_online_costs_bounded_sends = function(_, A, _, H)
      local crew = fiftyOnline(H)
      local nb, nbNs = H.client("Newbie", { class = "PRIEST" })
      H.link(nb)
      local times = {} -- when the newcomer sent each message
      local send = nb.env.C_ChatInfo.SendAddonMessage
      nb.env.C_ChatInfo.SendAddonMessage = function(...)
        times[#times + 1] = nb.clock
        return send(...)
      end
      local marks = {}
      for i, c in ipairs(crew) do marks[i] = #c.W.sent end
      login(nb)
      local loginAt = nb.clock
      H.advance(30)
      local firstTen = {}
      for i, at in ipairs(times) do
        if at - loginAt <= 10 then firstTen[#firstTen + 1] = typeOf(nb.sent[i]) .. " " .. nb.sent[i].chatType end
      end
      A.ok(#firstTen <= 3, "the newcomer sent " .. #firstTen .. " in its first 10 s: " .. table.concat(firstTen, ", "))
      -- What each copy whispers to the newcomer: its STATE (the answer to the HELLO), and, in the bulk lane behind
      -- chat, the calendar swap: its digest (CALD, up to 3 pieces with 50 people in it), the diaries the newcomer
      -- asked it for (CALP; the newcomer asks for each person's diary once, from whoever offered it first) and its own
      -- ask for the newcomer's diary (CALQ, once).
      local diaries = 0
      for i, c in ipairs(crew) do
        local answers, digests, asks = 0, 0, 0
        for j = marks[i] + 1, #c.W.sent do
          local m = c.W.sent[j]
          if m.chatType == "WHISPER" and m.target == "Newbie" then
            local t = typeOf(m)
            if t == "CALP" then diaries = diaries + 1
            elseif t == "CALD" then digests = digests + 1
            elseif t == "CALQ" then asks = asks + 1
            else answers = answers + 1; A.eq(t, "STATE", c.ns.playerName() .. " whispered a " .. t) end
          end
        end
        A.ok(answers >= 1 and answers <= 2, c.ns.playerName() .. " answered with " .. answers .. " STATE pieces")
        A.ok(digests <= 3, c.ns.playerName() .. " sent " .. digests .. " digest pieces")
        A.ok(asks <= 1, c.ns.playerName() .. " asked " .. asks .. " times")
      end
      A.ok(diaries <= 51, diaries .. " diaries for 51 people")
      local seen = 0
      for _, c in ipairs(crew) do if online(c.ns, "Newbie") then seen = seen + 1 end end
      A.eq(seen, 50, "everyone sees the newcomer")
      local heard = 0
      for i = 1, 50 do if online(nbNs, "Member" .. i) then heard = heard + 1 end end
      A.eq(heard, 50, "the newcomer sees everyone")
      noErrors(A, nbNs, crew[1].ns, crew[50].ns)
    end,
  },
}
