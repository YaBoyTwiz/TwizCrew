-- Two (or three) copies of TwizCrew talking to each other through the fake game (H.client / H.link / H.advance).

local LOGIN_LINE = "TwizCrew v0.1.0 loaded. Type /tc for settings."

local function login(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function rowOf(ns, name)
  for _, r in ipairs(ns.Panel.models()) do if r.name == name then return r end end
end

local function has(list, value)
  for _, v in ipairs(list or {}) do if v == value then return true end end
  return false
end

-- Advances and collects the text of every pop-up seen on this client meanwhile.
local function advanceWatching(H, ns, seconds)
  local seen = {}
  H.advance(seconds, function()
    for _, p in ipairs(ns.Popups.textsForTest()) do seen[p.text] = true end
  end)
  return seen
end

local function noErrors(A, ...)
  for _, ns in ipairs({ ... }) do A.eq(ns.Log.errors(50), {}, "errors on " .. ns.playerName()) end
end

-- Twiz (warrior 10) and Frostie (mage 12) in Elwynn Forest, linked and logged in for 10 s.
-- Twiz sees Frostie as party1, 10 yards away; visible = the game shows her (same layer).
local function frostieNear(c, visible)
  c.tw.state.pos = { x = 0, y = 0, instance = 1 }
  c.tw.state.units.party1 = { name = "Frostie", player = true, visible = visible, pos = { x = 10, y = 0, instance = 1 } }
end

local function twoFriends(H, opts)
  opts = opts or {}
  local tw, twNs = H.client("Twiz", opts.state)
  local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire",
    channelJoinFails = opts.state and opts.state.channelJoinFails })
  H.link(tw, fr)
  login(tw)
  login(fr)
  H.advance(opts.wait or 10)
  return { tw = tw, twNs = twNs, fr = fr, frNs = frNs }
end

---------------------------------------------------------------------------------------------------- steps
local function seeEachOther(H, A, c)
  local f = c.twNs.roster:get("Frostie")
  A.ok(f, "Twiz knows Frostie")
  A.eq(f.class, "MAGE"); A.eq(f.level, 12); A.eq(f.zone, "Elwynn Forest"); A.ok(f.online)
  local t = c.frNs.roster:get("Twiz")
  A.ok(t, "Frostie knows Twiz")
  A.eq(t.class, "WARRIOR"); A.eq(t.level, 10); A.eq(t.zone, "Elwynn Forest"); A.ok(t.online)
  A.eq(c.twNs.Panel.headerText(), "1 of 1 online")
  A.eq(c.frNs.Panel.headerText(), "1 of 1 online")
  A.ok(rowOf(c.twNs, "Frostie"), "Frostie has a row on Twiz's panel")
end

local function zoneChange(H, A, c)
  c.fr.state.zone, c.fr.state.subzone = "Westfall", "Sentinel Hill"
  c.fr:fire("ZONE_CHANGED_NEW_AREA")
  H.advance(2)
  A.eq(c.twNs.roster:get("Frostie").zone, "Westfall")
  A.eq(rowOf(c.twNs, "Frostie").zoneText, "Westfall, Sentinel Hill")
  -- and back, for the steps that follow
  c.fr.state.zone, c.fr.state.subzone = "Elwynn Forest", "Northshire"
  c.fr:fire("ZONE_CHANGED_NEW_AREA")
  H.advance(2)
  A.eq(c.twNs.roster:get("Frostie").zone, "Elwynn Forest")
end

local function otherLayer(H, A, c)
  frostieNear(c, false) -- next to Twiz on the map, but the game hides her
  local seen = advanceWatching(H, c.twNs, 35)
  A.eq(c.twNs.Layer.relationOf("Frostie"), "different")
  A.ok(seen["Frostie is on a different layer"], "a layer pop-up was shown")
  A.ok(has(rowOf(c.twNs, "Frostie").tags, "LAYER"), "OTHER LAYER tag on the panel")
  c.tw.state.units.party1.visible = true
  local back = advanceWatching(H, c.twNs, 5)
  A.eq(c.twNs.Layer.relationOf("Frostie"), "same")
  A.ok(back["Frostie is back on your layer"], "back on your layer pop-up")
  A.no(has(rowOf(c.twNs, "Frostie").tags, "LAYER"))
end

local function death(H, A, c)
  c.fr.state.dead = true
  c.fr:fire("PLAYER_DEAD")
  local seen = advanceWatching(H, c.twNs, 3)
  A.ok(seen["Frostie died"], "death pop-up")
  c.fr.state.dead = false
  c.fr:fire("PLAYER_ALIVE")
  H.advance(2)
end

local ODD = "50% ^_^ |Tx|t"

local function oddStatus(H, A, c)
  tc(c.fr, "status " .. ODD)
  H.advance(3)
  A.eq(c.twNs.roster:get("Frostie").status, ODD)
  A.eq(rowOf(c.twNs, "Frostie").status, c.twNs.Util.safeText(ODD))
  A.eq(rowOf(c.twNs, "Frostie").status, "50% ^_^ ||Tx||t")
end

local function newerVersion(H, A, c)
  local pw, pwNs = H.client("Pewpew", { version = "0.2.0", class = "MAGE" })
  H.link(pw)
  login(pw)
  H.advance(12)
  local found = false
  for _, line in ipairs(c.tw.printed) do
    if line == "TwizCrew: Pewpew has v0.2.0, you have v0.1.0. Update in WowUp." then found = true end
  end
  A.ok(found, "Twiz was told about the newer version")
  A.eq(c.twNs.Version.summary(), "Pewpew has v0.2.0, you have v0.1.0. Update in WowUp.")
  A.eq(c.twNs.Panel.headerText(), "2 of 2 online")
  return pwNs
end

-- Twiz runs a newer copy than Frostie. opts.restartSince: Twiz's RESTART_SINCE.
local function oldAndNew(H, opts)
  opts = opts or {}
  local tw, twNs = H.client("Twiz", { version = "0.2.0", restartSince = opts.restartSince or "0.1.0" })
  local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire" })
  H.link(tw, fr)
  login(tw)
  login(fr)
  H.advance(12)
  return { tw = tw, twNs = twNs, fr = fr, frNs = frNs }
end

local function printedLine(W, text)
  for _, line in ipairs(W.printed) do if line == text then return true end end
  return false
end

-- Frostie "reloads": a fresh copy of the game with Frostie's saved data, at `version`.
local function reload(H, c, version)
  for i, L in ipairs(H.linked) do if L == c.fr then table.remove(H.linked, i) end end
  local fr2, fr2Ns = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire", version = version })
  fr2.env.TwizCrewDB = c.frNs.db
  H.link(fr2)
  login(fr2)
  H.advance(8)
  return fr2, fr2Ns
end

---------------------------------------------------------------------------------------------- level progress
local DOT = "\194\183"

-- Twiz and Frostie (mage 12, 200 of 1871 XP), linked, past the login quiet time.
local function levelingFriends(H)
  local tw, twNs = H.client("Twiz")
  local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12, xp = 200, xpMax = 1871, subzone = "Northshire" })
  H.link(tw, fr)
  login(tw)
  login(fr)
  H.advance(35)
  return { tw = tw, twNs = twNs, fr = fr, frNs = frNs }
end

-- Frostie fights a mob for `fight` seconds and gets `xp` for it (her game fires what the real one does).
local function kill(H, c, xp, fight, newLevel, newMax)
  c.fr.state.combat = true
  c.fr:fire("PLAYER_REGEN_DISABLED")
  H.advance(fight or 20)
  c.fr.state.combat = false
  c.fr.state.xp = c.fr.state.xp + xp
  if newLevel then
    c.fr.state.level, c.fr.state.xp, c.fr.state.xpMax = newLevel, c.fr.state.xp - c.fr.state.xpMax, newMax
    c.fr:fire("PLAYER_LEVEL_UP", newLevel)
  end
  c.fr:fire("PLAYER_XP_UPDATE", "player")
  c.fr:fire("PLAYER_REGEN_ENABLED")
end

local function shownCount(ns, text)
  local n = 0
  for _, t in ipairs(ns.Popups.shownForTest()) do if t == text then n = n + 1 end end
  return n
end

local function dings(ns)
  local n = 0
  for _, t in ipairs(ns.Popups.shownForTest()) do if t:find("reached level", 1, true) then n = n + 1 end end
  return n
end

-- How many times the update notice showed on this copy (its log says so each time).
local function noticesShown(ns)
  local n = 0
  for _, line in ipairs(ns.Log.lines()) do
    if line:find("INFO update notice: v", 1, true) then n = n + 1 end
  end
  return n
end

return {
  files = {},
  tests = {
    update_notice_once_on_the_old_copy = function(_, A, _, H)
      local c = oldAndNew(H)                     -- Twiz v0.2.0 (restart since v0.1.0), Frostie v0.1.0
      A.ok(c.frNs.MinimapButton.badgeShownForTest(), "badge as soon as Twiz is heard")
      A.eq(c.frNs.Panel.updateLineForTest(), "Update available: v0.2.0")
      A.eq(c.frNs.Updates.promptForTest(), nil, "the pop-up waits a little")
      H.advance(60)
      A.eq(noticesShown(c.frNs), 1, "exactly one pop-up")
      A.eq(c.frNs.Updates.promptForTest(), { title = "Update available: v0.2.0",
        note = "Twiz has it. Open WowUp and click Update, then press Reload now.", reload = true })
      A.eq(noticesShown(c.twNs), 0, "the new copy gets nothing")
      A.no(c.twNs.MinimapButton.badgeShownForTest())
      A.eq(c.twNs.Panel.updateLineForTest(), nil)
      A.eq(c.twNs.Panel.titleVersionForTest(), "v0.2.0")
      A.eq(c.frNs.Panel.titleVersionForTest(), "v0.1.0")
      local reloads = 0
      c.fr.env.ReloadUI = function() reloads = reloads + 1 end
      local b = c.frNs.Updates.reloadButtonForTest()
      b._scripts.OnClick(b, "LeftButton")
      A.eq(reloads, 1)

      local fr2, fr2Ns = reload(H, c, "0.1.0")   -- WowUp had not downloaded it yet
      A.ok(printedLine(fr2, "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then /reload"))
      local before = noticesShown(fr2Ns)       -- the saved log came along
      H.advance(60)
      A.eq(noticesShown(fr2Ns), before, "no pop-up again for the same version after a /reload")
      A.eq(fr2Ns.Updates.promptForTest(), nil)
      A.ok(fr2Ns.MinimapButton.badgeShownForTest(), "the badge stays while still old")

      local fr3, fr3Ns = reload(H, { fr = fr2, frNs = fr2Ns }, "0.2.0")   -- updated
      H.advance(60)
      A.no(fr3Ns.MinimapButton.badgeShownForTest(), "on that version: no badge")
      A.eq(fr3Ns.Panel.updateLineForTest(), nil)
      A.eq(fr3Ns.Updates.promptForTest(), nil)
      for _, line in ipairs(fr3.printed) do A.no(line:find("Still on", 1, true), line) end
      noErrors(A, c.twNs, fr3Ns)
    end,

    update_notice_says_restart_when_files_were_added = function(_, A, _, H)
      local c = oldAndNew(H, { restartSince = "0.2.0" })
      H.advance(60)
      A.eq(noticesShown(c.frNs), 1)
      A.eq(c.frNs.Updates.promptForTest(), { title = "Update available: v0.2.0",
        note = "Twiz has it. Close WoW, open WowUp and click Update, then start WoW again.", reload = false })
      c.twNs.Updates.tellCrew()                  -- the owner presses the button anyway: still one window
      H.advance(3)
      A.eq(c.frNs.Updates.promptForTest().title, "Twiz says v0.2.0 is out")
      local fr2 = reload(H, c, "0.1.0")
      A.ok(printedLine(fr2, "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then restart the game"))
      noErrors(A, c.twNs, c.frNs)
    end,

    tell_crew_right_away_means_no_second_pop_up = function(_, A, _, H)
      local c = oldAndNew(H)
      c.twNs.Updates.tellCrew()
      H.advance(60)
      A.eq(c.frNs.Updates.promptForTest().title, "Twiz says v0.2.0 is out")
      A.eq(noticesShown(c.frNs), 0, "the request won")
      noErrors(A, c.twNs, c.frNs)
    end,

    update_request_goes_from_new_to_old_only = function(_, A, _, H)
      local c = oldAndNew(H)
      c.frNs.Updates.tellCrew()   -- the old copy asks: the new one ignores it
      H.advance(3)
      A.eq(c.twNs.Updates.promptForTest(), nil, "a newer copy ignores the request")
      c.twNs.Updates.tellCrew()   -- the new copy asks: the old one shows the window
      H.advance(3)
      A.eq(c.frNs.Updates.promptForTest(), { title = "Twiz says v0.2.0 is out",
        note = "If nothing changed, open WowUp and click Update first", reload = true })
      A.ok(printedLine(c.tw, "TwizCrew: told your crew that v0.2.0 is out. 1 friend online is on an older version."))
      A.ok(printedLine(c.fr, "TwizCrew: told your crew that v0.1.0 is out. Nobody online is known to be on an older version."))
      local reloads = 0
      c.fr.env.ReloadUI = function() reloads = reloads + 1 end
      local b = c.frNs.Updates.reloadButtonForTest()
      b._scripts.OnClick(b, "LeftButton")
      A.eq(reloads, 1)
      A.eq(c.frNs.db.update.told, "0.2.0")
      noErrors(A, c.twNs, c.frNs)
    end,

    versions_list_on_both = function(_, A, _, H)
      local c = oldAndNew(H)
      local OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
      local OLD = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"
      A.eq(c.twNs.Version.lines(), { OK .. " Twiz (you)  v0.2.0", OLD .. " Frostie  v0.1.0" })
      A.eq(c.frNs.Version.lines(), { OLD .. " Frostie (you)  v0.1.0", OK .. " Twiz  v0.2.0" })
    end,

    restart_needed_when_files_were_added = function(_, A, _, H)
      local c = oldAndNew(H, { restartSince = "0.2.0" })
      c.twNs.Updates.tellCrew()
      H.advance(3)
      A.eq(c.frNs.Updates.promptForTest(), { title = "Twiz says v0.2.0 is out",
        note = "Close and restart the game to load it", reload = false })
      local fr2 = reload(H, c, "0.1.0")
      A.ok(printedLine(fr2, "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then restart the game"))
    end,

    after_reload_still_old_or_updated = function(_, A, _, H)
      local c = oldAndNew(H)
      c.twNs.Updates.tellCrew()
      H.advance(3)
      A.ok(c.frNs.Updates.promptForTest())
      local fr2, fr2Ns = reload(H, c, "0.1.0")   -- WowUp had not downloaded it yet
      A.ok(printedLine(fr2, "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then /reload"))
      A.eq(fr2Ns.db.update, {}, "said once")
      local fr3, fr3Ns = reload(H, { fr = fr2, frNs = fr2Ns }, "0.1.0")
      A.no(printedLine(fr3, "TwizCrew: Still on v0.1.0. Open WowUp, click Update, then /reload"), "not again")
      H.advance(31)                             -- past Twiz's button cooldown, Twiz asks again
      c.twNs.Updates.tellCrew()
      H.advance(3)
      A.ok(fr3Ns.Updates.promptForTest(), "asked again after the reload")
      local fr4, fr4Ns = reload(H, { fr = fr3, frNs = fr3Ns }, "0.2.0")   -- updated this time
      for _, line in ipairs(fr4.printed) do A.no(line:find("Still on", 1, true), line) end
      A.eq(c.twNs.Version.lines()[2], "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t Frostie  v0.2.0")
      noErrors(A, c.twNs, fr4Ns)
    end,

    two_friends_see_each_other = function(_, A, _, H)
      local c = twoFriends(H)
      seeEachOther(H, A, c)
      for _, W in ipairs({ c.tw, c.fr }) do
        local n = 0
        for _, line in ipairs(W.printed) do if line == LOGIN_LINE then n = n + 1 end end
        A.eq(n, 1, "login line once")
      end
      noErrors(A, c.twNs, c.frNs)
    end,

    zone_change_reaches_friend = function(_, A, _, H)
      local c = twoFriends(H)
      zoneChange(H, A, c)
      noErrors(A, c.twNs, c.frNs)
    end,

    other_layer_tag_and_popup = function(_, A, _, H)
      local c = twoFriends(H, { wait = 1 })
      otherLayer(H, A, c)
      noErrors(A, c.twNs, c.frNs)
    end,

    death_popup = function(_, A, _, H)
      local c = twoFriends(H, { wait = 35 })
      death(H, A, c)
      noErrors(A, c.twNs, c.frNs)
    end,

    status_with_odd_characters_arrives_intact = function(_, A, _, H)
      local c = twoFriends(H)
      oddStatus(H, A, c)
      noErrors(A, c.twNs, c.frNs)
    end,

    channel_failure_falls_back_to_whispers = function(_, A, _, H)
      local c = twoFriends(H, { state = { channelJoinFails = true }, wait = 1 })
      -- each has the other in the whisper list (typed after logging in, like a player would)
      tc(c.tw, "add Frostie")
      tc(c.fr, "add twiz")
      A.eq(c.twNs.db.crew.extra, { "Frostie" })
      A.eq(c.frNs.db.crew.extra, { "Twiz" })
      H.advance(19)
      A.ok(c.twNs.roster:get("Frostie") and c.twNs.roster:get("Frostie").online, "Twiz sees Frostie")
      A.ok(c.frNs.roster:get("Twiz") and c.frNs.roster:get("Twiz").online, "Frostie sees Twiz")
      A.eq(c.twNs.roster:get("Frostie").class, "MAGE")
      local whispered = false
      for _, m in ipairs(c.tw.sent) do if m.chatType == "WHISPER" and m.target == "Frostie" then whispered = true end end
      A.ok(whispered, "the messages went by whisper")
      local lines = c.twNs.Report.lines()
      A.contains(lines[2], "failed: the channel did not join in time")
      noErrors(A, c.twNs, c.frNs)
    end,

    -- The owner's first-ever login (from the saved log): the channel joined as 6 and the HELLO, STATE and UPDATE
    -- sent in that same second came back with result 7. Then the copy gave up on the channel for the session.
    first_login_refusals_right_after_join_still_reach_a_friend = function(_, A, _, H)
      local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire" })
      H.link(fr)
      login(fr)
      H.advance(10)
      local hellos = {}
      frNs.Comm.on("HELLO", function(sender) hellos[#hellos + 1] = sender end)
      local tw, twNs = H.client("Twiz", { channelReadyAfter = 2 }) -- refuses channel sends for 2 s after joining
      H.link(tw)
      login(tw)
      H.advance(20)
      -- (the whisper copies to Frostie go out first and are not refused; only the channel copies are)
      local refused, firstChannel, firstGood = 0, nil, nil
      for i, m in ipairs(tw.sent) do
        if m.chatType == "CHANNEL" then
          if m.result == 7 then refused = refused + 1 end
          firstChannel = firstChannel or i
          if not firstGood and m.result == 0 then firstGood = i end
        end
      end
      A.ok(refused >= 1, "the first channel sends were refused, like in the game")
      A.eq(tw.sent[firstChannel].result, 7)
      A.ok(firstGood, "the channel took a message later")
      A.contains(tw.sent[firstGood].text, "HELLO", "the refused HELLO was kept and sent again")
      A.eq(tw.sent[1].chatType, "WHISPER")
      A.eq(tw.sent[1].target, "Frostie")
      A.contains(tw.sent[1].text, "HELLO", "the first thing Frostie gets is the HELLO, by whisper")
      local st = twNs.Transport.status()
      A.ok(st.joined, "on the channel"); A.no(st.failed, "never gave up on it")
      A.eq(hellos, { "Twiz" }, "Frostie heard Twiz's HELLO")
      A.ok(frNs.roster:get("Twiz") and frNs.roster:get("Twiz").online, "Frostie sees Twiz")
      A.ok(twNs.roster:get("Frostie") and twNs.roster:get("Frostie").online, "Twiz sees Frostie")
      A.contains(twNs.Report.lines()[2], "TwizCrewHQ joined)")
      noErrors(A, twNs, frNs)
    end,

    -- A channel that refuses for longer: the copy falls back, tries the channel again a minute later, and when it
    -- works says HELLO there, so a friend who never heard it learns about it.
    channel_back_after_refusals_says_hello_to_the_crew = function(_, A, _, H)
      local fr, frNs = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire" })
      H.link(fr)
      login(fr)
      H.advance(10)
      local hellos = {}
      frNs.Comm.on("HELLO", function(sender) hellos[#hellos + 1] = sender end)
      local tw, twNs = H.client("Twiz", { channelSendResult = 7 })
      H.link(tw)
      login(tw)
      H.advance(70) -- joined at 5 s, refusals waited out until 15 s, then counted: down at about 20 s
      local st = twNs.Transport.status()
      A.ok(st.failed, "Twiz gave up on the channel for now")
      A.contains(twNs.Report.lines()[2], "failed: sends to the channel were refused (result 7)")
      A.contains(twNs.Report.lines()[2], "next try in")
      -- meanwhile the fallback covers: Twiz heard Frostie on the channel, so Twiz whispers her
      local whispered = false
      for _, m in ipairs(tw.sent) do
        if m.chatType == "WHISPER" and m.target == "Frostie" and m.result == 0 then whispered = true end
      end
      A.ok(whispered, "the fallback whispers Frostie")
      local heardBefore, sentBefore = #hellos, #tw.sent
      tw.state.channelSendResult = nil -- the game takes channel messages again
      H.advance(st.nextRetryIn + 15)
      st = twNs.Transport.status()
      A.ok(st.joined, "back on the channel"); A.no(st.failed)
      local helloOnChannel = false
      for i = sentBefore + 1, #tw.sent do
        local m = tw.sent[i]
        if m.chatType == "CHANNEL" and m.result == 0 and m.text:find("^%d+%^HELLO%^") then helloOnChannel = true end
      end
      A.ok(helloOnChannel, "Twiz said HELLO on the channel when it came back")
      A.ok(#hellos > heardBefore and hellos[#hellos] == "Twiz", "Frostie heard it")
      A.ok(frNs.roster:get("Twiz") and frNs.roster:get("Twiz").online, "Frostie sees Twiz")
      A.eq(frNs.roster:get("Twiz").class, "WARRIOR", "and Twiz's STATE")
      A.ok(twNs.roster:get("Frostie") and twNs.roster:get("Frostie").online, "Twiz sees Frostie (her reply)")
      local log = table.concat(twNs.Log.lines(), "\n")
      A.contains(log, "trying channel TwizCrewHQ again (try 1)")
      A.contains(log, "channel TwizCrewHQ works again")
      A.contains(twNs.Report.lines()[2], "TwizCrewHQ joined)")
      noErrors(A, twNs, frNs)
    end,

    friend_logging_back_in_shows_no_old_layer = function(_, A, _, H)
      local c = twoFriends(H, { wait = 31 })
      frostieNear(c, true)
      H.advance(3)
      A.eq(c.twNs.Layer.relationOf("Frostie"), "same")
      c.fr:fire("PLAYER_LOGOUT")           -- Frostie logs out (sends BYE)
      H.advance(1)
      for i, L in ipairs(H.linked) do if L == c.fr then table.remove(H.linked, i) end end
      A.no(c.twNs.roster:get("Frostie").online)
      c.tw.state.units.party1 = nil       -- she left the group when she logged out
      H.advance(3)
      local fr2, fr2Ns = H.client("Frostie", { class = "MAGE", level = 12, subzone = "Northshire" })
      H.link(fr2)
      login(fr2)                           -- Frostie logs back in, no layer key yet
      local seen = advanceWatching(H, c.twNs, 15)
      A.ok(c.twNs.roster:get("Frostie").online, "Frostie is back")
      A.no(seen["Frostie is on a different layer"], "no pop-up from Frostie's old layer key")
      A.eq(c.twNs.Layer.relationOf("Frostie"), "unknown")
      noErrors(A, c.twNs, fr2Ns)
    end,

    newer_version_is_announced = function(_, A, _, H)
      local c = twoFriends(H)
      local pwNs = newerVersion(H, A, c)
      noErrors(A, c.twNs, c.frNs, pwNs)
    end,

    -- WoW Forever: channel addon messages never arrive (the harness drops them, like the game). A third friend who
    -- logs in later finds the others in the channel's member list, and they find them by the join notice.
    a_friend_who_logs_in_later_sees_everyone_and_everyone_sees_them = function(_, A, _, H)
      local c = twoFriends(H)
      local gi, giNs = H.client("Ginkan", { class = "PRIEST", level = 8 })
      H.link(gi)
      login(gi)
      H.advance(15)
      for _, pair in ipairs({ { c.twNs, "Frostie" }, { c.twNs, "Ginkan" }, { c.frNs, "Twiz" }, { c.frNs, "Ginkan" },
          { giNs, "Twiz" }, { giNs, "Frostie" } }) do
        local m = pair[1].roster:get(pair[2])
        A.ok(m and m.online, pair[1].playerName() .. " sees " .. pair[2])
      end
      A.eq(giNs.Panel.headerText(), "2 of 2 online")
      local channelOnly = true
      for _, m in ipairs(gi.sent) do if m.chatType ~= "CHANNEL" then channelOnly = false end end
      A.no(channelOnly, "Ginkan whispered")
      noErrors(A, c.twNs, c.frNs, giNs)
    end,
    level_progress_reaches_a_friend = function(_, A, _, H)
      local c = levelingFriends(H)
      local row = rowOf(c.twNs, "Frostie")
      A.eq(row.xpText, "Lv 12 " .. DOT .. " 10%", "the number on the bar")
      A.eq(row.tip, { "Level 12 " .. DOT .. " 10%", "1,671 XP to level 13" }, "no pace yet, so no estimate")
      local sentBefore = #c.fr.sent
      for _ = 1, 6 do                    -- a mob a minute, 120 XP each
        kill(H, c, 120, 20)
        H.advance(40)
      end
      -- two UPDATEs per mob (the fight starts; it ends with the XP), as before this feature
      local updates = 0
      for i = sentBefore + 1, #c.fr.sent do
        local msg = c.frNs.Codec.decode(c.fr.sent[i].text)
        if msg and msg.type == "UPDATE" and c.fr.sent[i].chatType == "WHISPER" then updates = updates + 1 end
      end
      A.eq(updates, 6 * 2, "counted once: the whisper to Twiz (the channel copy goes out too)")
      row = rowOf(c.twNs, "Frostie")
      A.eq(row.xpText, "Lv 12 " .. DOT .. " 49%")
      A.eq(row.tip[2], "951 XP to level 13")
      local minutes = tonumber(row.tip[3]:match("^About (%d+) min to level$"))
      A.ok(minutes and minutes >= 7 and minutes <= 9, "estimate near 8 min (2 XP a second): " .. tostring(row.tip[3]))
      -- rested XP shows when Frostie has some
      c.fr.state.rested = 2500
      kill(H, c, 120, 20)
      H.advance(5)
      A.eq(rowOf(c.twNs, "Frostie").tip[3], "Rested: 2,500 XP")
      -- Frostie goes idle: after 10 minutes without XP the estimate is left out
      H.advance(11 * 60)
      row = rowOf(c.twNs, "Frostie")
      A.eq(#row.tip, 3, "no estimate while idle")
      noErrors(A, c.twNs, c.frNs)
    end,

    level_up_gives_exactly_one_ding = function(_, A, _, H)
      local c = levelingFriends(H)
      c.fr.state.xp = 1800
      kill(H, c, 20, 5)                  -- 1820 of 1871: not yet
      H.advance(5)
      local seen = {}
      kill(H, c, 100, 5, 13, 2000)        -- 1920: level 13 with 49 XP
      H.advance(10, function()
        for _, p in ipairs(c.twNs.Popups.textsForTest()) do seen[p.text] = p.subtext end
      end)
      A.eq(seen["Frostie reached level 13!"], "Only 47 to go.", "ding on Twiz's screen")
      H.advance(60)
      kill(H, c, 30, 5)
      H.advance(30)
      A.eq(shownCount(c.twNs, "Frostie reached level 13!"), 1, "exactly one ding")
      A.eq(dings(c.frNs), 0, "no ding for your own level-up")
      local row = rowOf(c.twNs, "Frostie")
      A.eq(row.xpText, "Lv 13 " .. DOT .. " 3%")
      A.eq(row.tip[2], "1,921 XP to level 14")
      A.eq(c.twNs.roster:get("Frostie").xpTrack.earned, 1920 - 200 + 30, "the level-up counts as XP earned")
      noErrors(A, c.twNs, c.frNs)
    end,

    no_ding_on_login_reload_or_reconnect = function(_, A, _, H)
      local c = levelingFriends(H)
      -- Frostie logs out at 12, levels on another computer (say), logs back in at 13
      c.fr:fire("PLAYER_LOGOUT")
      H.advance(1)
      for i, L in ipairs(H.linked) do if L == c.fr then table.remove(H.linked, i) end end
      H.advance(60)
      local fr2, fr2Ns = H.client("Frostie", { class = "MAGE", level = 13, xp = 10, xpMax = 2000 })
      fr2.env.TwizCrewDB = c.frNs.db
      H.link(fr2)
      login(fr2)
      H.advance(40)
      A.eq(c.twNs.roster:get("Frostie").level, 13)
      A.eq(dings(c.twNs), 0, "logging back in a level higher is not a ding")
      -- Twiz reloads; even if the saved list still said 12, Frostie's state at 13 is not a ding
      for i, L in ipairs(H.linked) do if L == c.tw then table.remove(H.linked, i) end end
      c.twNs.db.roster.Frostie.level = 12
      local tw2, tw2Ns = H.client("Twiz")
      tw2.env.TwizCrewDB = c.twNs.db
      H.link(tw2)
      login(tw2)
      H.advance(40)
      A.eq(tw2Ns.roster:get("Frostie").level, 13)
      A.eq(dings(tw2Ns), 0, "a reload is not a ding")
      -- Frostie's game crashes (no goodbye): Twiz marks her offline after 3 minutes; she comes back at 14
      for i, L in ipairs(H.linked) do if L == fr2 then table.remove(H.linked, i) end end
      H.advance(4 * 60)
      A.no(tw2Ns.roster:get("Frostie").online)
      local fr3, fr3Ns = H.client("Frostie", { class = "MAGE", level = 14, xp = 5, xpMax = 2200 })
      fr3.env.TwizCrewDB = fr2Ns.db
      H.link(fr3)
      login(fr3)
      H.advance(40)
      A.ok(tw2Ns.roster:get("Frostie").online, "Frostie is back")
      A.eq(tw2Ns.roster:get("Frostie").level, 14)
      A.eq(dings(tw2Ns), 0, "a level seen after a gap is not a ding")
      -- and a real one still works afterwards, once
      fr3.state.combat = true
      fr3:fire("PLAYER_REGEN_DISABLED")
      H.advance(5)
      fr3.state.combat = false
      fr3.state.level, fr3.state.xp, fr3.state.xpMax = 15, 1, 2400
      fr3:fire("PLAYER_LEVEL_UP", 15)
      fr3:fire("PLAYER_REGEN_ENABLED")
      H.advance(30)
      A.eq(dings(tw2Ns), 1)
      noErrors(A, tw2Ns, fr3Ns)
    end,

    -- The game's real state: the channel delivers nothing, so everything below travels by whisper.
    in_fallback_mode_friends_who_marked_each_other_offline_find_each_other_after_a_ping = function(_, A, _, H)
      local c = twoFriends(H, { state = { channelJoinFails = true }, wait = 20 })
      c.twNs.Comm.echoCount = c.tw.realEchoCount
      c.frNs.Comm.echoCount = c.fr.realEchoCount
      c.twNs.db.crew.extra = { "Frostie" }
      c.frNs.db.crew.extra = { "Twiz" }
      c.twNs.Comm.send("HELLO", {})
      c.frNs.Comm.send("HELLO", {})
      H.advance(10)
      A.ok(c.twNs.roster:get("Frostie") and c.frNs.roster:get("Twiz"), "they met by whisper")
      c.twNs.db.crew.extra, c.frNs.db.crew.extra = {}, {} -- from now on only the roster says who to whisper
      H.advance(25) -- let what is still queued go out and arrive first
      c.twNs.Transport.forget("Frostie") -- (a whisper made them channel members too)
      c.frNs.Transport.forget("Twiz")
      c.twNs.roster:gone("Frostie")
      c.frNs.roster:gone("Twiz")
      A.no(c.twNs.roster:get("Frostie").online)
      A.no(c.frNs.roster:get("Twiz").online)
      H.advance(61)
      A.ok(c.twNs.roster:get("Frostie").online, "Twiz hears Frostie's PING again")
      A.ok(c.frNs.roster:get("Twiz").online, "Frostie hears Twiz's PING again")
      noErrors(A, c.twNs, c.frNs)
    end,
    a_lost_update_is_repaired_after_two_pings = function(_, A, _, H)
      local c = twoFriends(H)
      c.twNs.Comm.echoCount = c.tw.realEchoCount
      c.frNs.Comm.echoCount = c.fr.realEchoCount
      H.advance(130)
      A.eq(c.twNs.Log.counts()["sent SREQ"], nil, "nothing lost, nothing asked")
      -- every UPDATE of Frostie's that says she is dead is lost on the way to Twiz (the answer to a request is a STATE)
      local api, lost = c.fr.env.C_ChatInfo, 0
      local real = api.SendAddonMessage
      api.SendAddonMessage = function(prefix, text, ...)
        local result = real(prefix, text, ...)
        if text:find("^1%^UPDATE%^") and text:find("tg=DEAD", 1, true) then
          c.fr.sent[#c.fr.sent].result = 99
          lost = lost + 1
        end
        return result
      end
      c.fr.state.dead = true
      c.fr:fire("PLAYER_DEAD")
      H.advance(3)
      A.ok(lost >= 1, "the update was lost")
      A.no(c.twNs.roster:get("Frostie").tags.DEAD, "Twiz still thinks she is alive")
      H.advance(61) -- one PING: could be an update in flight, no question yet
      A.eq(c.twNs.Log.counts()["sent SREQ"], nil, "one PING is not enough")
      H.advance(61)
      A.eq(c.twNs.Log.counts()["sent SREQ"], 1, "the second PING in a row makes Twiz ask")
      H.advance(5)
      api.SendAddonMessage = real
      A.ok(c.twNs.roster:get("Frostie").tags.DEAD, "Frostie's answer fixed the panel")
      A.eq(c.frNs.Log.counts()["sent SREQ"], nil)
      H.advance(300)
      A.eq(c.twNs.Log.counts()["sent SREQ"], 1, "repaired: no more questions")
      noErrors(A, c.twNs, c.frNs)
    end,
    with_no_loss_ten_pings_cause_no_state_request = function(_, A, _, H)
      local c = twoFriends(H)
      c.twNs.Comm.echoCount = c.tw.realEchoCount
      c.frNs.Comm.echoCount = c.fr.realEchoCount
      c.fr.state.zone = "Westfall"
      c.fr:fire("ZONE_CHANGED_NEW_AREA")
      H.advance(660)
      A.eq(c.twNs.Log.counts()["sent SREQ"], nil)
      A.eq(c.frNs.Log.counts()["sent SREQ"], nil)
      A.ok(c.twNs.Log.counts()["recv PING"] >= 10, "the pings did arrive")
      noErrors(A, c.twNs, c.frNs)
    end,

    no_errors_anywhere = function(_, A, _, H)
      local c = twoFriends(H, { wait = 1 })
      otherLayer(H, A, c)      -- needs the first 30 s (login quiet time) to pass inside the step
      seeEachOther(H, A, c)
      zoneChange(H, A, c)
      death(H, A, c)
      oddStatus(H, A, c)
      tc(c.tw, "report")
      tc(c.fr, "")
      local pwNs = newerVersion(H, A, c)
      H.advance(200)           -- pings, offline ticks, layer ticks
      A.eq(c.twNs.Panel.headerText(), "2 of 2 online", "pings keep everyone online")
      noErrors(A, c.twNs, c.frNs, pwNs)
    end,
  },
}
