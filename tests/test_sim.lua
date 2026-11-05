-- Two (or three) copies of TwizCrew talking to each other through the fake game (H.client / H.link / H.advance).

local LOGIN_LINE = "TwizCrew v0.1.0 loaded. Type /tc for settings."

local function login(W, before)
  W:fire("ADDON_LOADED", "TwizCrew")
  if before then before() end
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function tc(W, msg) W.env.SlashCmdList.TWIZCREW(msg) end

local function seeNpc(W, guid)
  W.state.guids.mouseover = guid
  W:fire("UPDATE_MOUSEOVER_UNIT")
  W:fire("UPDATE_MOUSEOVER_UNIT")
end

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
  seeNpc(c.tw, "Creature-0-1-0-111-299-0000ABCDEF")
  seeNpc(c.fr, "Creature-0-1-0-222-299-0000ABCDEF")
  local seen = advanceWatching(H, c.twNs, 35)
  A.eq(c.twNs.Layer.relationOf("Frostie"), "different")
  A.ok(seen["Frostie is on a different layer"], "a layer pop-up was shown")
  A.ok(has(rowOf(c.twNs, "Frostie").tags, "LAYER"), "OTHER LAYER tag on the panel")
  seeNpc(c.fr, "Creature-0-1-0-111-299-0000ABCDEF")
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

return {
  files = {},
  tests = {
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

    newer_version_is_announced = function(_, A, _, H)
      local c = twoFriends(H)
      local pwNs = newerVersion(H, A, c)
      noErrors(A, c.twNs, c.frNs, pwNs)
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
