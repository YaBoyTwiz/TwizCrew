-- "While you were away" (UI/AwayCard.lua) and the welcome card (UI/Welcome.lua), with whole copies logging in and out
-- on a saved table (H.client).

local DAY = 86400

local function login(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function retire(H, W)
  W:fire("PLAYER_LOGOUT")
  H.advance(0.2)
  for i, L in ipairs(H.linked) do if L == W then table.remove(H.linked, i) end end
  for i, C in ipairs(H.clients) do if C == W then table.remove(H.clients, i) end end
end

local function noErrors(A, ...)
  for _, ns in ipairs({ ... }) do A.eq(ns.Log.errors(50), {}, "errors on " .. ns.playerName()) end
end

-- One session of "Twiz Main" in guild "Crew" with `members` (others, offline unless said), on `saved`, `daysLater`
-- days after the harness's start. Returns W, ns (still logged in).
local function session(H, saved, members, daysLater, state)
  local W, ns = H.client("Twiz Main", state)
  W.wall = W.wall + (daysLater or 0) * DAY
  H.guild("Crew", W, members)
  W.env.TwizCrewDB = saved
  H.link(W)
  login(W)
  return W, ns
end

local function texts(lines)
  local out = {}
  for i, l in ipairs(lines or {}) do out[i] = l.text end
  return out
end

-- (GUIDs given: the harness numbers them by position otherwise)
local BEFORE = { { name = "Irek Stone", level = 27, class = "MAGE", guid = "Player-1-0101" },
  { name = "Frostie Snow", level = 20, guid = "Player-1-0102" },
  { name = "Chaos Deathbringr", level = 30, guid = "Player-1-0103" } }
local AFTER = { { name = "Irek Stone", level = 30, class = "MAGE", guid = "Player-1-0101" },
  { name = "Chaos Deathbringr", level = 30, guid = "Player-1-0103" },
  { name = "Sneakz Rogue", level = 8, class = "ROGUE", guid = "Player-1-0104" } }

-- Session 1 (day 0) saves the snapshot at logout; returns the saved table.
local function firstSession(H, A, saved, members)
  saved = saved or {}
  local W, ns = session(H, saved, members or BEFORE, 0)
  H.advance(15)
  noErrors(A, ns)
  A.no(ns.AwayCard.isShown(), "nothing to compare on a first run")
  retire(H, W)
  return saved
end

local function popupIndex(ns, text)
  for i, t in ipairs(ns.Popups.textsForTest()) do if t.text == text then return i, t end end
end

return {
  files = "toc",
  tests = {
    ------------------------------------------------------------------------------------------- while you were away
    the_card_after_three_days = function(ns, A, W, H)
      local saved = firstSession(H, A)
      local snap = saved.away and saved.away.snap
      A.ok(snap, "a snapshot at logout")
      A.eq(snap.guild, "Crew")
      A.eq(snap.members.Irek.level, 27)
      A.eq(snap.members.Irek.full, "Irek Stone")
      local W2, ns2 = session(H, saved, AFTER, 3)
      H.advance(5)
      A.no(ns2.AwayCard.isShown(), "not in the first seconds")
      H.advance(10)
      A.ok(ns2.AwayCard.isShown(), "about ten seconds after login")
      local card = ns2.AwayCard.shownForTest()
      A.eq(card.sub, "You were gone 3 days")
      A.eq(texts(card.lines), { "Sneakz joined the guild", "Frostie left the guild", "Irek 27 -> 30" })
      ns2.AwayCard.clickLineForTest(1)
      A.no(ns2.AwayCard.isShown(), "a click closes it")
      local found
      for _, it in ipairs(ns2.Panel.toolItems()) do if it.label == "While you were away" then found = it end end
      A.ok(found, "the wrench menu shows it again")
      found.onClick()
      A.ok(ns2.AwayCard.isShown())
      noErrors(A, ns2)
      retire(H, W2)
      A.eq(saved.away.snap.members.Irek.level, 30, "the next snapshot")
      A.eq(saved.away.snap.members.Frostie, nil)
    end,
    nothing_under_twelve_hours_and_nothing_when_nothing_changed = function(ns, A, W, H)
      local saved = firstSession(H, A)
      local W2, ns2 = session(H, saved, AFTER, 0.4) -- about 10 hours
      H.advance(30)
      A.no(ns2.AwayCard.isShown(), "under 12 hours")
      local menu = {}
      for _, it in ipairs(ns2.Panel.toolItems()) do menu[it.label] = true end
      A.no(menu["While you were away"], "no card, nothing in the wrench menu")
      retire(H, W2)
      local W3, ns3 = session(H, saved, AFTER, 2)
      H.advance(30)
      A.no(ns3.AwayCard.isShown(), "nothing changed: no card at all")
      noErrors(A, ns3)
      retire(H, W3)
    end,
    a_quick_reload_keeps_the_last_logout = function(ns, A, W, H)
      local saved = firstSession(H, A)
      local at = saved.away.snap.at
      local W2 = session(H, saved, AFTER, 3)
      H.advance(4)
      retire(H, W2) -- a /reload before the card was worked out
      A.eq(saved.away.snap.at, at, "the old snapshot stays")
      local _, ns3 = session(H, saved, AFTER, 3)
      H.advance(15)
      A.ok(ns3.AwayCard.isShown(), "so the card still comes after the reload")
    end,
    waits_out_a_dungeon_and_a_fight = function(ns, A, W, H)
      local saved = firstSession(H, A)
      local W2, ns2 = session(H, saved, AFTER, 3)
      W2.state.inInstance, W2.state.instanceType = true, "party"
      H.advance(30)
      A.no(ns2.AwayCard.isShown(), "not inside a dungeon")
      W2.state.inInstance, W2.state.instanceType = false, "none"
      W2.state.combat = true
      H.advance(5)
      A.no(ns2.AwayCard.isShown(), "not in a fight")
      W2.state.combat = false
      H.advance(4)
      A.ok(ns2.AwayCard.isShown(), "after")
    end,
    the_setting_turns_it_off = function(ns, A, W, H)
      local saved = firstSession(H, A)
      saved.modules.recap.settings.awayCard = false
      local W2, ns2 = session(H, saved, AFTER, 3)
      H.advance(30)
      A.no(ns2.AwayCard.isShown())
      retire(H, W2)
      A.eq(saved.away.snap.members.Irek.level, 30, "the snapshot is kept up to date anyway")
    end,
    a_list_without_offline_members_has_no_left_lines = function(ns, A, W, H)
      local saved = firstSession(H, A)
      local W2, ns2 = session(H, saved, AFTER, 3, { guildOnlineOnly = true })
      for _, m in ipairs(W2.state.guild.members) do if m.name == "Irek Stone" then m.online = true end end
      H.advance(100) -- waits for a whole list, then goes on at the cap
      A.ok(ns2.AwayCard.isShown())
      A.eq(texts(ns2.AwayCard.shownForTest().lines), { "Irek 27 -> 30" }, "offline members may just be unlisted")
      retire(H, W2)
      A.eq(saved.away.snap.members.Frostie.level, 20, "merged: the unlisted members stay in the snapshot")
      A.eq(saved.away.snap.members.Irek.level, 30)
    end,
    new_calendar_notes = function(ns, A, W, H)
      local saved = firstSession(H, A, nil, AFTER)
      local t = saved.away.snap.at + 2 * DAY
      local date = os.date("!%Y-%m-%d", t)
      saved.calendar = saved.calendar or {}
      saved.calendar.notes = saved.calendar.notes or {}
      saved.calendar.notes["frost1-" .. t] = { d = date, t = "Deadmines tonight", i = 1, b = "Frostie", c = "MAGE", u = t }
      saved.calendar.notes["frost1-" .. (saved.away.snap.at - 3600)] = { d = date, t = "Older", i = 1, b = "Frostie",
        c = "MAGE", u = t }
      local _, ns2 = session(H, saved, AFTER, 3)
      H.advance(15)
      local lines = ns2.AwayCard.shownForTest().lines
      A.eq(texts(lines), { "1 new calendar note" }, "made after my logout, not opened")
      ns2.AwayCard.clickLineForTest(1)
      A.ok(ns2.Calendar.isShown(), "a click opens the calendar")
    end,
    crowns_that_changed_hands = function(ns, A, W, H)
      local saved = { guild = { name = "Crew" }, stats = { crew = {
        Frostie = { sid = "x", s = {}, a = { dt = 5 } }, Chaos = { sid = "x", s = {}, a = { dt = 2 } } } } }
      firstSession(H, A, saved, AFTER)
      A.eq(saved.away.snap.crowns.corpse, { "Frostie" }, "the crowns at logout")
      saved.stats.crew.Chaos.a.dt = 9 -- (as if Chaos's numbers arrived after login)
      local _, ns2 = session(H, saved, AFTER, 3)
      H.advance(15)
      local lines = ns2.AwayCard.shownForTest().lines
      A.eq(texts(lines), { "Chaos took Professional Corpse from Frostie" })
      ns2.AwayCard.clickLineForTest(1)
      A.eq(ns2.Panel.tab(), "shame", "a click opens the Hall of Shame")
      A.eq(ns2.Board.view(), "all")
      A.eq(ns2.Board.tab(), "deaths")
    end,
    the_snapshot_is_kept_per_guild = function(ns, A)
      local saved = { guild = { name = "Crew", byChar = { me = "Other" } }, away = { snap = { guild = "Crew" } },
        welcome = { start = "shown" }, guilds = { Other = { away = { snap = { guild = "Other" } } } } }
      local db = ns.DB.init(saved, ns.Modules.list())
      A.ok(ns.DB.useGuildOf(db, "me"))
      A.eq(db.away.snap.guild, "Other", "the other guild's snapshot comes up")
      A.eq(db.welcome, nil, "and its own (no) welcome data")
      A.eq(db.guilds.Crew.away.snap.guild, "Crew", "Crew's is parked with its set")
      A.eq(db.guilds.Crew.welcome.start, "shown")
    end,
    ------------------------------------------------------------------------------------------- welcome card
    say_hi_to_a_new_member = function(ns, A, W, H)
      local T, tns = H.client("Twiz Main")
      T.env.TwizCrewDB = {}
      H.link(T)
      login(T)
      H.advance(20)
      local said = {}
      T.env.SendChatMessage = function(msg, chan) said[#said + 1] = { msg, chan } end
      local S, sns = H.client("Sneakz Rogue", { class = "MAGE", level = 8 })
      S.env.TwizCrewDB = {}
      H.link(S)
      login(S)
      H.advance(3)
      local i, p = popupIndex(tns, "Say hi to Sneakz")
      A.ok(i, "a pop-up for the newcomer")
      A.eq(p.subtext, "Level 8 Mage just joined the guild - click to say hello")
      tns.Popups.clickForTest(i)
      A.eq(#said, 1, "one line in guild chat")
      A.eq(said[1][2], "GUILD")
      A.ok(said[1][1]:find("Sneakz", 1, true), said[1][1])
      A.no(popupIndex(tns, "Say hi to Sneakz"), "the pop-up goes")
      A.ok(T.env.TwizCrewDB.welcome.welcomed["sneakz rogue"], "remembered")
      T:fire("GUILD_ROSTER_UPDATE", false)
      H.advance(3)
      local again = 0
      for _, t in ipairs(tns.Popups.shownForTest()) do if t == "Say hi to Sneakz" then again = again + 1 end end
      A.eq(again, 1, "once per member")
      -- the newcomer's start card
      A.no(sns.Welcome.isStartShown(), "not at once")
      H.advance(30)
      A.ok(sns.Welcome.isStartShown(), "the newcomer's start card")
      local card = sns.Welcome.startCardForTest()
      A.eq(card.title:GetText(), "Welcome to Crew Guild")
      A.eq(card.rows[1].text:GetText(), "Online near your level: Twiz (10)")
      A.no(card.rows[2] and card.rows[2]:IsShown(), "no best play time from a brand-new copy")
      A.eq(card.buttons[1].text:GetText(), "Close", "no About page in this build: no button for it")
      noErrors(A, tns, sns)
    end,
    no_pop_up_for_the_first_list_or_with_the_setting_off = function(ns, A, W, H)
      local T, tns = H.client("Twiz Main")
      T.env.TwizCrewDB = {}
      H.link(T)
      login(T)
      H.advance(20)
      A.no(popupIndex(tns, "Say hi to Twiz"), "never for myself")
      tns.Modules.set("popups", "newMember", false)
      local S = H.client("Sneakz Rogue", { class = "MAGE", level = 8 })
      S.env.TwizCrewDB = {}
      H.link(S)
      login(S)
      H.advance(3)
      A.no(popupIndex(tns, "Say hi to Sneakz"), "switched off")
      A.eq(next(T.env.TwizCrewDB.welcome.welcomed), nil, "and not marked as welcomed")
    end,
    the_game_refuses_guild_chat = function(ns, A, W, H)
      local T, tns = H.client("Twiz Main")
      T.env.TwizCrewDB = {}
      H.link(T)
      login(T)
      H.advance(20)
      T.env.SendChatMessage = function() error("blocked") end
      local opened
      T.env.ChatFrame_OpenChat = function(text) opened = text end
      local S = H.client("Sneakz Rogue", { class = "MAGE", level = 8 })
      S.env.TwizCrewDB = {}
      H.link(S)
      login(S)
      H.advance(3)
      tns.Popups.clickForTest((popupIndex(tns, "Say hi to Sneakz")))
      A.ok(opened and opened:find("^/g .*Sneakz"), "the chat box opens with the line typed: " .. tostring(opened))
      T.env.ChatFrame_OpenChat = nil -- (a second newcomer, and no way to open the chat box either)
      local X = H.client("Xena Warrior", { class = "WARRIOR", level = 40 })
      X.env.TwizCrewDB = {}
      H.link(X)
      login(X)
      H.advance(3)
      local i = popupIndex(tns, "Say hi to Xena")
      A.ok(i)
      tns.Popups.clickForTest(i)
      A.contains(T.printed[#T.printed], "Type: /g ")
    end,
    an_existing_user_gets_no_start_card = function(ns, A, W, H)
      local saved = {}
      local W1, ns1 = session(H, saved, BEFORE, 0)
      H.advance(35)
      A.ok(ns1.Welcome.isStartShown(), "first run in this guild: owed and shown")
      A.eq(saved.welcome.start, "shown")
      retire(H, W1)
      local W3, ns3 = session(H, saved, BEFORE, 3)
      H.advance(60)
      A.no(ns3.Welcome.isStartShown(), "never twice")
      retire(H, W3)
      local old = { roster = { Frostie = { name = "Frostie", class = "MAGE" } }, guild = { name = "Crew",
        keys = { ["frostie snow"] = "Frostie" } } }
      local W2, ns2 = session(H, old, BEFORE, 0)
      H.advance(60)
      A.no(ns2.Welcome.isStartShown(), "saved crew data for this guild: not new")
      A.eq(old.welcome.start, "no")
      retire(H, W2)
      -- data from before guilds (v0.1.24) that this guild's list fits: adopted, not new either
      local legacy = { roster = { Frostie = { name = "Frostie", class = "WARRIOR" },
        Chaos = { name = "Chaos", class = "WARRIOR" } } }
      local W4, ns4 = session(H, legacy, BEFORE, 0)
      H.advance(60)
      A.eq(legacy.guild.name, "Crew", "adopted")
      A.no(ns4.Welcome.isStartShown(), "an old user whose data was just adopted")
      A.eq(legacy.welcome.start, "no")
      retire(H, W4)
    end,
    the_start_card_waits_for_the_fight_and_has_the_about_button = function(ns, A, W, H)
      local W1, ns1 = session(H, {}, BEFORE, 0, { level = 25 })
      local opened
      ns1.About = { open = function() opened = true end }
      W1.state.combat = true
      H.advance(60)
      A.no(ns1.Welcome.isStartShown(), "not in a fight")
      W1.state.combat = false
      H.advance(4)
      A.ok(ns1.Welcome.isStartShown())
      local card = ns1.Welcome.startCardForTest()
      A.eq(card.rows[1].text:GetText(), "Nobody near your level is on right now")
      A.eq(card.buttons[1].text:GetText(), "How to use TwizCrew")
      card.buttons[1]._scripts.OnClick(card.buttons[1], "LeftButton")
      A.ok(opened, "opens the About page")
      A.no(ns1.Welcome.isStartShown(), "and closes")
    end,
  },
}
