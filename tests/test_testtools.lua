-- Test tools ("Try it out" in /tc, and /tc test ...): fake crew members, a copy of yourself, pop-ups and the update
-- notice through the real code. Fake data is never sent and never saved.

local BUDDY, MAXBUDDY, OFFBUDDY, COPY = "Testbuddy (test)", "Maxbuddy (test)", "Offbuddy (test)", "My copy (test)"

local function boot(W, before, wait)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(wait or 6)
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function receive(W, ns, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

local function rowOf(ns, name)
  for _, r in ipairs(ns.Panel.models()) do if r.name == name then return r end end
end

local function rowIndex(ns, name)
  for i, r in ipairs(ns.Panel.models()) do if r.name == name then return i end end
end

local function has(list, value)
  for _, v in ipairs(list or {}) do if v == value then return true end end
  return false
end

local function printed(W, text)
  for _, line in ipairs(W.printed) do if line == text then return true end end
  return false
end

local function printedLike(W, pattern)
  for _, line in ipairs(W.printed) do if line:find(pattern, 1, true) then return true end end
  return false
end

local function count(list, value)
  local n = 0
  for _, v in ipairs(list) do if v == value then n = n + 1 end end
  return n
end

local function texts(ns)
  local out = {}
  for _, p in ipairs(ns.Popups.textsForTest()) do out[#out + 1] = p.text end
  return out
end

local function popupOf(ns, text)
  for _, p in ipairs(ns.Popups.textsForTest()) do if p.text == text then return p end end
end

local function msgType(m) return m.text:match("^%d+%^(%u+)%^") end

-- Every string anywhere in t (keys and values), except the debug log.
local function strings(t, out, seen)
  out, seen = out or {}, seen or {}
  if seen[t] then return out end
  seen[t] = true
  for k, v in pairs(t) do
    if k ~= "log" then
      if type(k) == "string" then out[#out + 1] = k end
      if type(v) == "string" then out[#out + 1] = v
      elseif type(v) == "table" then strings(v, out, seen) end
    end
  end
  return out
end

local function noFakeSaved(A, ns, W, when)
  for _, s in ipairs(strings(W.env.TwizCrewDB or ns.db)) do
    A.no(s:find("(test)", 1, true) or s:find("buddy", 1, true), "fake data saved " .. when .. ": " .. s)
  end
  A.eq(ns.db.update.told, nil, "no pretend update remembered " .. when)
  A.eq(ns.db.updateNotice.shown, nil, "no pretend update marked as shown " .. when)
end

-- Nothing sent since index `from` mentions a fake, whispers a fake, or is anything but the regular PING.
local function noFakeSent(A, W, from, when)
  for i = (from or 0) + 1, #W.sent do
    local m = W.sent[i]
    A.no(m.text:find("test", 1, true) or m.text:find("buddy", 1, true), "fake data sent " .. when .. ": " .. m.text)
    A.no(tostring(m.target or ""):find("test", 1, true), "whispered a fake " .. when)
    A.eq(msgType(m), "PING", "only the regular ping goes out " .. when .. " (got " .. m.text .. ")")
  end
end

-- Every test button once (fake friends first), with time for pop-ups and timers.
local function pressEverything(W)
  -- (the copy follows your own updates; its pop-ups show like a friend's would)
  tc(W, "test fake"); W:advance(1)
  tc(W, "test copy"); W:advance(1)
  tc(W, "test ding"); W:advance(1)
  tc(W, "test death"); W:advance(1)
  tc(W, "test layer"); W:advance(4)
  tc(W, "test layer"); W:advance(4)
  tc(W, "test roast"); W:advance(1)
  tc(W, "test update reload"); W:advance(1)
  tc(W, "test update restart"); W:advance(1)
end

return {
  files = "toc",
  tests = {
    ------------------------------------------------------------------------------------------------ fake friends
    fake_friends_show_in_every_row_style = function(ns, A, W)
      boot(W)
      ns.Modules.set("panel", "showOffline", true) -- open the Offline list so Offbuddy has a row
      tc(W, "test fake")
      W:advance(0.1)
      local b = rowOf(ns, BUDDY)
      A.ok(b, "Testbuddy has a row")
      A.eq(b.class, "PALADIN"); A.eq(b.level, 12); A.eq(b.xpText, "Lv 12 \194\183 63%")
      A.eq(b.zoneText, "Hillsbrad Foothills, Southshore"); A.eq(b.status, "testing TwizCrew")
      A.ok(has(b.tags, "COMBAT") and has(b.tags, "AFK") and has(b.tags, "LAYER"), "FIGHTING, AFK and OTHER LAYER")
      A.eq(b.tip[1], "Level 12 \194\183 63%")
      A.eq(b.tip[2], "3,720 XP to level 13")
      A.eq(b.tip[3], "Rested: 2,500 XP")
      local m = rowOf(ns, MAXBUDDY)
      A.ok(m and m.atMax, "Maxbuddy is max level"); A.eq(m.xpText, "Lv 60 \194\183 max level")
      local o = rowOf(ns, OFFBUDDY)
      A.ok(o and o.offline, "Offbuddy is offline"); A.eq(o.offlineText, "Offline, last seen 2h ago")
      A.eq(ns.Panel.rowTextsForTest(rowIndex(ns, BUDDY)).bar, "Lv 12 \194\183 63%")
      ns.Modules.set("panel", "rowStyle", "compact"); W:advance(0.1)
      A.eq(rowOf(ns, BUDDY).xpText, "Lv 12 \194\183 63%")
      A.eq(ns.Panel.rowTextsForTest(rowIndex(ns, BUDDY)).corner, "Lv 12 \194\183 63%")
      ns.Modules.set("panel", "rowStyle", "tiny"); W:advance(0.1)
      A.eq(ns.Panel.rowTextsForTest(rowIndex(ns, BUDDY)).corner, "63%")
      A.eq(ns.Panel.headerText(), "2 of 3 online")
      A.ok(printedLike(W, "Testbuddy"), "chat says what was added")
      A.eq(ns.Log.errors(10), {})
    end,

    fake_friends_make_no_popups_by_themselves = function(ns, A, W)
      boot(W)
      tc(W, "test fake")
      W:advance(60)
      A.eq(ns.Popups.shownForTest(), {}, "appearing, the layer tag and XP ticks are quiet")
      A.eq(W.invites, {})
    end,

    fake_friend_earns_xp_and_shows_time_to_level = function(ns, A, W)
      boot(W)
      tc(W, "test fake")
      W:advance(100)
      local b = rowOf(ns, BUDDY)
      A.no(b.tip[4], "no estimate before 3 minutes of XP")
      W:advance(110)
      b = rowOf(ns, BUDDY)
      A.ok(b.xp > 63, "XP went up")
      A.ok(b.tip[4] and b.tip[4]:find("^About %d+ min to level$"), "estimate shows: " .. tostring(b.tip[4]))
    end,

    fake_friend_levels_up_by_itself_with_exactly_one_ding = function(ns, A, W)
      boot(W)
      tc(W, "test fake")
      W:advance(480)
      local shown = ns.Popups.shownForTest()
      A.eq(count(shown, "Testbuddy (test) reached level 13!"), 1)
      A.eq(#shown, 1, "nothing else popped up")
      A.eq(ns.roster:get(BUDDY).level, 13)
    end,

    pressing_fake_again_starts_over = function(ns, A, W)
      boot(W)
      tc(W, "test fake")
      tc(W, "test ding")
      W:advance(1)
      tc(W, "test fake")
      W:advance(1)
      A.eq(ns.roster:get(BUDDY).level, 12)
      A.eq(#ns.roster:testNames(), 3)
    end,

    a_real_friend_named_testbuddy_never_collides = function(ns, A, W)
      boot(W)
      tc(W, "test fake")
      receive(W, ns, "Testbuddy-Realm", "STATE", { cl = "MAGE", lv = "30", zn = "Westfall" })
      A.eq(ns.roster:get("Testbuddy").level, 30)
      A.eq(ns.roster:get(BUDDY).level, 12)
      tc(W, "test clear")
      A.ok(ns.roster:get("Testbuddy"), "the real one stays")
      A.eq(ns.roster:get(BUDDY), nil)
      A.ok(ns.db.roster.Testbuddy, "the real one is saved")
    end,

    --------------------------------------------------------------------------------------------------- copy of me
    copy_of_me_shows_my_own_numbers_and_follows_my_updates = function(ns, A, W)
      W.state.level, W.state.xp, W.state.xpMax, W.state.rested = 12, 6363, 10100, 2500
      boot(W)
      tc(W, "test copy")
      W:advance(0.1)
      local m = ns.roster:get(COPY)
      A.ok(m, "the copy is in the crew list")
      A.eq({ m.class, m.level, m.xpCur, m.xpMax, m.rested, m.zone },
        { "WARRIOR", 12, 6363, 10100, 2500, "Elwynn Forest" })
      local r = rowOf(ns, COPY)
      A.eq(r.xpText, "Lv 12 \194\183 63%")
      A.eq(r.tip, { "Level 12 \194\183 63%", "3,737 XP to level 13", "Rested: 2,500 XP" })
      local sent = #W.sent
      W.state.xp = 6500 -- 64%: a real UPDATE goes out, and the copy follows it
      W:fire("PLAYER_XP_UPDATE"); W:advance(1.5)
      A.ok(#W.sent > sent, "the real update was sent to the crew")
      A.eq(m.xpCur, 6500)
      W.state.xp = 6520 -- still 64%: friends hear nothing yet (the number rides along later), nor does the copy
      W:fire("PLAYER_XP_UPDATE"); W:advance(1.5)
      A.eq(m.xpCur, 6500)
      W.state.level, W.state.xp, W.state.xpMax = 13, 100, 11000
      W:fire("PLAYER_LEVEL_UP"); W:fire("PLAYER_XP_UPDATE"); W:advance(5)
      A.eq({ m.level, m.xpCur, m.xpMax }, { 13, 100, 11000 })
      A.eq(ns.Popups.shownForTest(), { "My copy (test) reached level 13!" },
        "your real level-up gives your copy exactly one ding, like a friend would see")
      tc(W, "test copy")
      A.eq(ns.roster:get(COPY), nil, "pressing again removes it")
      W.state.xp = 2000
      W:fire("PLAYER_XP_UPDATE"); W:advance(1.5)
      A.eq(ns.roster:get(COPY), nil, "and it stays gone")
      A.eq(ns.Log.errors(10), {})
    end,

    ---------------------------------------------------------------------------------------------------- pop-ups
    ding_pops_up_once_even_in_the_login_quiet_time = function(ns, A, W)
      boot(W) -- 6 s after login: still inside the 30 s quiet time
      tc(W, "test ding") -- makes the fake friends first
      W:advance(1)
      local p = popupOf(ns, "Testbuddy (test) reached level 13!")
      A.ok(p, "ding shown: " .. table.concat(texts(ns), " / "))
      A.eq(p.subtext, "Only 47 to go.")
      W:advance(10)
      A.eq(count(ns.Popups.shownForTest(), "Testbuddy (test) reached level 13!"), 1)
      A.eq(rowOf(ns, BUDDY).level, 13)
      tc(W, "test ding"); W:advance(1)
      A.ok(popupOf(ns, "Testbuddy (test) reached level 14!"))
    end,

    ding_follows_the_popup_switch = function(ns, A, W)
      boot(W)
      ns.Modules.set("popups", "levelUp", false)
      tc(W, "test ding"); W:advance(1)
      A.eq(ns.Popups.shownForTest(), {})
      A.ok(printedLike(W, "Level-ups"), "chat says the switch is off")
    end,

    death_popup_through_the_real_code = function(ns, A, W)
      boot(W)
      tc(W, "test death"); W:advance(1)
      local p = popupOf(ns, "Testbuddy (test) died")
      A.ok(p); A.eq(p.subtext, "Hillsbrad Foothills, Southshore")
      A.ok(has(rowOf(ns, BUDDY).tags, "DEAD"))
      W:advance(20)
      A.no(has(rowOf(ns, BUDDY).tags, "DEAD"), "back to life after a few seconds")
      tc(W, "test death"); W:advance(1)
      A.eq(count(ns.Popups.shownForTest(), "Testbuddy (test) died"), 2, "works again")
    end,

    layer_popup_alternates_and_never_invites = function(ns, A, W)
      boot(W)
      tc(W, "test layer"); W:advance(4)
      A.ok(popupOf(ns, "Testbuddy (test) is back on your layer"), table.concat(texts(ns), " / "))
      A.no(has(rowOf(ns, BUDDY).tags, "LAYER"))
      tc(W, "test layer"); W:advance(4)
      local p = popupOf(ns, "Testbuddy (test) is on a different layer")
      A.ok(p); A.eq(p.subtext, "Click to invite them to your group")
      A.ok(has(rowOf(ns, BUDDY).tags, "LAYER"))
      for i = 1, ns.Popups.visibleCount() do ns.Popups.clickForTest(1) end
      A.eq(W.invites, {}, "a fake is never invited")
    end,

    roast_popup_through_the_real_code = function(ns, A, W)
      boot(W)
      tc(W, "test roast")
      local shown = ns.Roasts.forTest.shown()
      A.eq(#shown, 1)
      A.contains(shown[1], "Testbuddy (test)")
      A.ok(has(texts(ns), shown[1]), "on screen")
      tc(W, "test roast") -- within 10 s: the real limit holds it back
      A.eq(#ns.Roasts.forTest.shown(), 1)
      A.ok(printedLike(W, "10 seconds"), "chat explains")
      W:advance(11)
      tc(W, "test roast")
      shown = ns.Roasts.forTest.shown()
      A.eq(#shown, 2)
      A.ok(shown[1] ~= shown[2], "a different roast each time")
    end,

    ------------------------------------------------------------------------------------------------ update notice
    pretend_update_reload_shows_badge_line_and_window = function(ns, A, W)
      boot(W)
      tc(W, "test update reload"); W:advance(0.1)
      A.ok(ns.MinimapButton.badgeShownForTest(), "gold !")
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.1.1")
      local p = ns.Updates.promptForTest()
      A.eq(p.title, "Update available: v0.1.1")
      A.eq(p.note, "Testbuddy (test) has it. Open WowUp and click Update, then press Reload now.")
      A.ok(p.reload)
      ns.Updates.closeForTest()
      W:advance(40)
      A.eq(ns.Updates.promptForTest(), nil, "the notice does not come again")
      A.eq(ns.Version.summary(), "everyone up to date", "the real version check is untouched")
      noFakeSaved(A, ns, W, "after the pretend update")
      tc(W, "test clear"); W:advance(0.1)
      A.no(ns.MinimapButton.badgeShownForTest())
      A.eq(ns.Panel.updateLineForTest(), nil)
    end,

    pretend_update_restart = function(ns, A, W)
      boot(W)
      tc(W, "test update restart"); W:advance(0.1)
      local p = ns.Updates.promptForTest()
      A.eq(p.note, "Testbuddy (test) has it. Close WoW, open WowUp and click Update, then start WoW again.")
      A.no(p.reload)
      tc(W, "test clear")
      A.eq(ns.Updates.promptForTest(), nil, "clear closes the window")
    end,

    clear_brings_back_a_real_update = function(ns, A, W)
      boot(W)
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12", ver = "0.2.0", rs = "0.1.0" })
      W:advance(0.1)
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.2.0")
      tc(W, "test update reload"); W:advance(0.1)
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.2.1", "the pretend one is newer than the real one")
      tc(W, "test clear"); W:advance(0.1)
      A.eq(ns.Panel.updateLineForTest(), "Update available: v0.2.0")
      A.ok(ns.MinimapButton.badgeShownForTest())
    end,

    version_list_and_tell_crew_ignore_fakes = function(ns, A, W)
      boot(W)
      pressEverything(W)
      local lines = ns.Version.lines()
      A.eq(#lines, 1, "only you")
      A.contains(lines[1], "(you)")
      ns.Updates.tellCrew()
      A.ok(printedLike(W, "Nobody online is known to be on an older version."))
    end,

    ------------------------------------------------------------------------------------------------ never sent
    nothing_fake_is_ever_sent = function(ns, A, W)
      boot(W, nil, 25) -- past the session decision, so only the minute's PING is due
      local from = #W.sent
      pressEverything(W)
      ns.Comm.inject(BUDDY, ns.Codec.encode("UPDATE", { sid = "Zed-1", sst = "1" })[1]) -- another session
      W:advance(20)
      noFakeSent(A, W, from, "while testing")
      tc(W, "test clear"); W:advance(5)
      noFakeSent(A, W, from, "after clear")
      A.eq(W.invites, {})
    end,

    nothing_fake_is_whispered = function(ns, A, W)
      boot(W, nil, 25)
      receive(W, ns, "Frostie-Realm", "STATE", { cl = "MAGE", lv = "12" }) -- one real friend
      ns.Modules.set("comm", "transport", "whisper")
      W:advance(1)
      local from = #W.sent
      pressEverything(W)
      W.state.zone = "Westfall"; W:fire("ZONE_CHANGED_NEW_AREA") -- a real update goes out to the crew
      W:advance(70) -- and a PING
      W:fire("PLAYER_LOGOUT") -- and a BYE
      -- Only Frostie may be whispered (the transport would shorten "Testbuddy (test)" to "Testbuddy", a real
      -- player's name, so the check is on every target).
      local whispers = 0
      for i = from + 1, #W.sent do
        local m = W.sent[i]
        if m.chatType == "WHISPER" then
          whispers = whispers + 1
          A.eq(m.target, "Frostie", "whispered someone else: " .. m.text)
        end
      end
      A.ok(whispers >= 3, "the update, the ping and the goodbye went to Frostie")
    end,

    inject_accepts_only_fake_names = function(ns, A, W)
      boot(W)
      local text = ns.Codec.encode("STATE", { cl = "MAGE", lv = "5" })[1]
      A.no(ns.Comm.inject("Frostie", text))
      A.eq(ns.roster:get("Frostie"), nil)
      A.ok(ns.Comm.inject(BUDDY, text))
      A.eq(ns.roster:get(BUDDY).level, 5)
    end,

    ------------------------------------------------------------------------------------------------ never saved
    nothing_fake_is_saved_after_clear_and_logout = function(ns, A, W)
      boot(W)
      pressEverything(W)
      W:advance(30)
      noFakeSaved(A, ns, W, "while testing")
      tc(W, "test clear")
      noFakeSaved(A, ns, W, "after clear")
      pressEverything(W)
      W:fire("PLAYER_LOGOUT")
      noFakeSaved(A, ns, W, "after logout")
    end,

    stats_and_session_ignore_fakes = function(ns, A, W)
      boot(W, nil, 25)
      pressEverything(W)
      W:advance(10)
      for _, e in ipairs(ns.StatsStore.entries("all")) do
        A.no(ns.isTestName(e.name), "no fake on the Hall of Shame")
      end
      A.no(ns.Session.current().id:find("test", 1, true))
    end,

    a_reload_starts_without_fakes = function(ns, A, W, H)
      boot(W)
      pressEverything(W)
      W:fire("PLAYER_LOGOUT")
      local saved = ns.Util.copy(W.env.TwizCrewDB)
      local W2, ns2 = H.client("Twiz")
      W2.env.TwizCrewDB = saved
      boot(W2)
      A.eq(ns2.roster:testNames(), {})
      A.eq(ns2.Panel.updateLineForTest(), nil)
      for _, r in ipairs(ns2.Panel.models()) do A.no(ns2.isTestName(r.name)) end
    end,

    friends_never_hear_about_fakes = function(ns, A, W, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12 })
      H.link(tw, fr)
      for _, X in ipairs({ tw, fr }) do
        X:fire("ADDON_LOADED", "TwizCrew"); X:fire("PLAYER_LOGIN"); X:fire("PLAYER_ENTERING_WORLD")
      end
      H.advance(40)
      A.ok(frNs.roster:get("Twiz"), "the two copies see each other")
      local sentBefore = #tw.sent
      for _, cmd in ipairs({ "fake", "copy", "ding", "death", "layer", "roast", "update reload" }) do
        tc(tw, "test " .. cmd)
        H.advance(4)
      end
      H.advance(30)
      A.eq(frNs.roster:names(true), { "Twiz" }, "Frostie knows only Twiz")
      A.eq(frNs.Popups.shownForTest(), {}, "no pop-ups on Frostie's screen")
      A.eq(frNs.Roasts.forTest.shown(), {})
      A.eq(frNs.Panel.updateLineForTest(), nil)
      noFakeSent(A, tw, sentBefore, "to a friend")
    end,

    ---------------------------------------------------------------------------------------------- clear / reset
    clear_removes_every_fake = function(ns, A, W)
      boot(W)
      pressEverything(W)
      tc(W, "test clear")
      W:advance(30)
      A.eq(ns.roster:testNames(), {})
      for _, r in ipairs(ns.Panel.models()) do A.no(ns.isTestName(r.name), "row left: " .. r.name) end
      A.no(ns.MinimapButton.badgeShownForTest())
      A.eq(ns.Panel.updateLineForTest(), nil)
      A.eq(ns.Updates.promptForTest(), nil)
      A.ok(printed(W, "TwizCrew: test stuff cleared."))
      W:advance(600)
      A.eq(ns.roster:testNames(), {}, "no timer brings them back")
      tc(W, "test clear")
      A.ok(printed(W, "TwizCrew: nothing to clear."))
      A.eq(ns.Log.errors(10), {})
    end,

    reset_to_defaults_clears_fakes = function(ns, A, W)
      boot(W)
      pressEverything(W)
      ns.Modules.resetAll()
      W:advance(0.1)
      A.eq(ns.roster:testNames(), {})
      A.eq(ns.Panel.updateLineForTest(), nil)
    end,

    -------------------------------------------------------------------------------------------- settings / chat
    try_it_out_section_in_settings = function(ns, A, W)
      boot(W)
      ns.Settings.open(); ns.Settings.setTab("advanced", "all")
      local d = ns.Settings.describeForTest()
      local function at(what) for i, v in ipairs(d) do if v == what then return i end end end
      A.ok(at("section:Try it out") and at("section:Try it out") > at("section:Extras"), "last section")
      A.ok(at("module:testtools:tools"))
      for _, key in ipairs({ "fake", "copy", "ding", "death", "layer", "roast", "updateReload", "updateRestart",
        "clear" }) do
        A.ok(at("setting:testtools:" .. key), "button " .. key)
      end
      local def = ns.Modules.get("testtools")
      A.eq(def.tier, "tools")
      for _, s in ipairs(def.settings) do A.eq(s.kind, "button"); A.ok(#s.info > 20, "an (i) for " .. s.key) end
      A.ok(ns.Modules.isEnabled("testtools"))
      ns.Modules.setEnabled("testtools", false)
      A.ok(ns.Modules.isEnabled("testtools"), "not a switch")
      ns.Settings.rowForTest("testtools", "fake").button._scripts.OnClick()
      A.eq(#ns.roster:testNames(), 3, "the button works")
    end,

    tc_test_help = function(ns, A, W)
      boot(W)
      tc(W, "test")
      for _, sub in ipairs({ "fake", "copy", "ding", "death", "layer", "roast", "update reload", "update restart",
        "clear" }) do
        A.ok(printedLike(W, "/tc test " .. sub), "help lists " .. sub)
      end
      tc(W, "help")
      A.ok(printedLike(W, "/tc test - "), "/tc help mentions /tc test")
    end,

    report_says_what_is_fake = function(ns, A, W)
      boot(W)
      local function line()
        for _, l in ipairs(ns.Report.lines()) do if l:find("^Test tools:") then return l end end
      end
      A.eq(line(), "Test tools: nothing fake")
      pressEverything(W)
      A.eq(line(), "Test tools: on (Maxbuddy (test), My copy (test), Offbuddy (test), Testbuddy (test); "
        .. "pretend update v0.1.1)")
      for _, l in ipairs(ns.Report.lines()) do
        A.no(l:find("^Testbuddy") or l:find("^My copy"), "fakes are not listed as crew: " .. l)
      end
    end,

    -------------------------------------------------------------------------------------------------- failures
    a_failing_tool_never_breaks_the_rest = function(ns, A, W)
      boot(W)
      local gather = ns.Self.gather
      ns.Self.gather = function() error("boom") end
      tc(W, "test copy")
      A.ok(printedLike(W, "did not work"), "chat says so")
      local errs = ns.Log.errors(5)
      A.ok(#errs >= 1 and errs[#errs]:find("testtools: ", 1, true), "charged to the test tools")
      tc(W, "test copy"); tc(W, "test copy")
      A.ok(has(ns.Modules.broken(), "testtools"), "turned off after three errors")
      A.eq(#ns.Modules.broken(), 1, "nothing else turned off")
      ns.Self.gather = gather
      tc(W, "test fake")
      A.ok(printedLike(W, "test tools turned off after errors"))
      A.ok(ns.Modules.isEnabled("panel"))
      receive(W, ns, "Frostie", "STATE", { cl = "MAGE", lv = "12" }); W:advance(0.1)
      A.ok(rowOf(ns, "Frostie"), "the real panel still works")
    end,
  },
}
