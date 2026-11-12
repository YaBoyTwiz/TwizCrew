-- The test tools ("Try it out" in /tc, and /tc test ...): pretend crew members and pop-ups through the real code, so
-- the owner can check things alone.
local _, ns = ...

-- "Try it out": pretend crew members (names end in " (test)", see ns.isTestName) that go through the real receive
-- path: their messages are built with Codec.encode and handed to Comm.inject, which calls the same handlers as a
-- friend's message. Fakes are never sent or saved: the roster never saves them and leaves them out of the lists
-- that send, save, count stats or list versions; the crew session and the stats detectors ignore them; a fake is
-- never invited; a pretend update lives apart in Version and Updates. Everything is in memory: Clear test stuff,
-- Reset everything to defaults, a logout or a /reload removes it.
local TestTools = {}
ns.TestTools = TestTools

local TOOLS = "testtools"
local BUDDY, MAXBUDDY, OFFBUDDY, COPY = "Testbuddy (test)", "Maxbuddy (test)", "Offbuddy (test)", "My copy (test)"
local XP_TICK, XP_GAIN = 20, 180  -- Testbuddy earns XP_GAIN every XP_TICK seconds (levels up after about 7 minutes)
local REVIVE_AFTER = 15           -- seconds Testbuddy stays dead after the Death pop-up button
local ALIVE_TAGS = "COMBAT,AFK"
local ROASTS = {                  -- the Roast pop-up button goes through these, one per press
  { k = "fall" }, { k = "drown" }, { k = "weak", v = "3", x = "Kobold Miner" }, { k = "again", v = "12" },
  { k = "deaths", v = "5" },
}

local WALKER = "Walkbuddy (test)" -- Find the crew: a pretend group member who walks around you
local WALK_TICK, WALK_RADIUS, WALK_STEP = 1, 80, 0.12 -- seconds, yards, radians per tick
local walkMeets = 0     -- Walkbuddy's meet-ups so far: each press gets a new id (an old id never comes back)
local ticker            -- Testbuddy's XP ticker
local walkTicker        -- Walkbuddy's steps
local walkMeetId        -- Walkbuddy's current meet-up id
local walkAngle = 0
local copyOn = false    -- "My copy" follows our own updates
local layerOf = {}      -- fake name -> "same" | "different" (the Layer pop-up button)
local expected          -- { kind, name } while a button makes the pop-up it expects
local reviveTurn, layerTurn, roastTurn = 0, 0, 0

local function say(text) print("TwizCrew: " .. text) end

-- XP needed for a level (not the game's table; 0 at max level).
local function need(lv)
  if lv >= ns.maxLevel() then return 0 end
  return 1000 + lv * 760
end

local function percent(cur, max)
  if max <= 0 then return "0" end
  return tostring(math.floor(cur / max * 100))
end

local function inject(name, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields)) do ns.Comm.inject(name, text) end
end

-- Runs fn while the pop-up `kind` about `name` is expected (Popups asks TestTools.wants).
local function expect(kind, name, fn)
  expected = { kind = kind, name = name }
  local ok, err = pcall(fn)
  expected = nil
  if not ok then error(err, 0) end
end

local function stopTicker()
  if ticker and ticker.Cancel then ticker:Cancel() end
  ticker = nil
end

local function stopWalk()
  if walkTicker and walkTicker.Cancel then walkTicker:Cancel() end
  walkTicker = nil
end

-- Takes a fake away the way a friend leaves (BYE: the layer tracker and pop-ups forget them), then out of the list.
local function removeFake(name)
  local m = ns.roster:get(name)
  if not m then return false end
  if m.online then inject(name, "BYE", {}) end
  ns.roster:remove(name)
  layerOf[name] = nil
  return true
end

local function levelFields(lv, xc, rx)
  local xm = need(lv)
  if xm == 0 then xc, rx = 0, 0 end
  return { lv = tostring(lv), xm = tostring(xm), xc = tostring(xc), rx = tostring(rx), xp = percent(xc, xm) }
end

-- Testbuddy earns XP; reaching the level's need is a level-up through the real path (its ding is expected: that
-- is the "one ding on a real level-up" check).
local function xpTick()
  local m = ns.roster:get(BUDDY)
  if not m or not m.online or not m.level or not m.xpMax or m.xpMax <= 0 then return end
  local lv, xc = m.level, (m.xpCur or 0) + XP_GAIN
  local rx = math.max(0, (m.rested or 0) - math.floor(XP_GAIN / 2))
  if xc >= m.xpMax then
    expect("levelup", BUDDY, function() inject(BUDDY, "UPDATE", levelFields(lv + 1, xc - m.xpMax, rx)) end)
  else
    inject(BUDDY, "UPDATE", { xp = percent(xc, m.xpMax), xc = tostring(xc), rx = tostring(rx) })
  end
end

local function makeFakes()
  stopTicker()
  reviveTurn = reviveTurn + 1
  for _, name in ipairs({ BUDDY, MAXBUDDY, OFFBUDDY }) do removeFake(name) end
  layerOf[BUDDY] = "different"
  local buddy = levelFields(12, 6400, 2500)
  buddy.cl, buddy.zn, buddy.sz, buddy.st, buddy.tg = "PALADIN", "Hillsbrad Foothills", "Southshore", "testing TwizCrew",
    ALIVE_TAGS
  buddy.ins, buddy.ver, buddy.rs = "0", ns.VERSION, ns.RESTART_SINCE
  inject(BUDDY, "STATE", buddy)
  local maxed = levelFields(ns.maxLevel(), 0, 0)
  maxed.cl, maxed.zn, maxed.sz, maxed.tg, maxed.ins, maxed.ver = "ROGUE", "Stormwind City", "Trade District", "", "0",
    "0.0.9" -- an older version: the version list and "Tell crew to update" must not count it
  inject(MAXBUDDY, "STATE", maxed)
  local off = levelFields(20, 4000, 0)
  off.cl, off.zn, off.sz, off.ins, off.ver = "DRUID", "Darkshore", "Auberdine", "0", ns.VERSION
  inject(OFFBUDDY, "STATE", off)
  inject(OFFBUDDY, "BYE", {})
  local m = ns.roster:get(OFFBUDDY)
  if m then m.lastSeen = ns.wallclock() - 7200 end -- "last seen 2h ago"
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(XP_TICK, function() ns.Log.safe(TOOLS, xpTick) end)
  end
end

local function ensureFakes()
  if not ns.roster:get(BUDDY) then makeFakes() end
end

-- A line in chat when a switch would hide the pop-up a button is about to make.
local function panelHint()
  if not ns.Modules.isEnabled("panel") then say("the Crew panel is hidden: type /tc show to see it.") end
end

local function popupHint(key, label)
  if not ns.Modules.isEnabled("popups") then
    say("pop-ups are turned off (/tc, Modules, Pop-ups), so nothing shows.")
  elseif key and not ns.Modules.setting("popups", key) then
    say("\"" .. label .. "\" pop-ups are off in /tc, under Pop-ups, so nothing shows.")
  end
end

---------------------------------------------------------------------------------------------------- the buttons
local ACTIONS = {}

-- Try a mock: you laughing at yourself, the way a friend's mock about you would look.
local function tryMock(mode)
  local me = ns.playerName()
  local lines = ns.Roasts.rotation()
  local line = lines[math.random(math.max(1, #lines))] or "{name}, have you tried not dying?"
  local text = ns.Roasts.mockText(line, me, me)
  local _, class = UnitClass("player")
  local used = ns.MockShow.show(me, text, { mode = mode, unit = "player",
    look = ns.MockShow.decodeLook(ns.MockShow.myLook()), class = class })
  if used ~= mode then
    say("the " .. mode .. " picture didn't work on this game version; it showed the " .. used .. " instead.")
  end
end

function ACTIONS.mockLive() tryMock("live") end
function ACTIONS.cheer()
  local me = ns.playerName()
  local lines = ns.Roasts.CHEER_LINES
  local text = ns.Roasts.mockText(lines[math.random(#lines)], me, me, ns.Roasts.mockInfo(me))
  local _, class = UnitClass("player")
  ns.MockShow.show(me, (text:gsub("{%a+}", "")), { cheer = true, mode = "live", unit = "player", class = class,
    look = ns.MockShow.decodeLook(ns.MockShow.myLook()) })
end
function ACTIONS.mockIcon() tryMock("icon") end

function ACTIONS.fake()
  makeFakes()
  panelHint()
  say("added Testbuddy (earns XP every 20 seconds: \"About … min to level\" shows on hover after about 3 minutes, "
    .. "and it levels up by itself after about 7), Maxbuddy (max level) and Offbuddy (offline). Only on your "
    .. "screen. /tc test clear removes them.")
end

function ACTIONS.copy()
  if copyOn or ns.roster:get(COPY) then
    copyOn = false
    removeFake(COPY)
    say("your copy is gone.")
    return
  end
  inject(COPY, "STATE", ns.Self.gather()) -- your numbers, built like the STATE your friends get
  copyOn = true
  panelHint()
  say("added \"My copy\": what your friends see about you. Hover it and compare with your XP bar. It updates when "
    .. "your copy of TwizCrew tells the crew (each whole percent, a level-up, a zone change...). Press again to "
    .. "remove it.")
end

function ACTIONS.ding()
  ensureFakes()
  local m = ns.roster:get(BUDDY)
  if (m.level or 0) >= ns.maxLevel() then
    say("Testbuddy is already max level. Press Fake friends to start over.")
    return
  end
  popupHint("levelUp", "Level-ups")
  expect("levelup", BUDDY, function() inject(BUDDY, "UPDATE", levelFields(m.level + 1, 300, m.rested or 0)) end)
end

function ACTIONS.death()
  ensureFakes()
  popupHint("death", "Deaths")
  local m = ns.roster:get(BUDDY)
  if m.tags and m.tags.DEAD then inject(BUDDY, "UPDATE", { tg = ALIVE_TAGS }) end
  expect("death", BUDDY, function() inject(BUDDY, "UPDATE", { tg = "DEAD" }) end)
  reviveTurn = reviveTurn + 1
  local mine = reviveTurn
  C_Timer.After(REVIVE_AFTER, function()
    ns.Log.safe(TOOLS, function()
      if mine == reviveTurn and ns.roster:get(BUDDY) then inject(BUDDY, "UPDATE", { tg = ALIVE_TAGS }) end
    end)
  end)
end

-- Offbuddy comes online (through the real path: the pop-up, the activity feed, the bar notice and the chat line).
function ACTIONS.online()
  ensureFakes()
  popupHint("online", "Friends coming online")
  local m = ns.roster:get(OFFBUDDY)
  if m and m.online then inject(OFFBUDDY, "BYE", {}) end
  local off = levelFields(20, 4000, 0)
  off.cl, off.zn, off.sz, off.ins, off.ver = "DRUID", "Darkshore", "Auberdine", "0", ns.VERSION
  expect("online", OFFBUDDY, function() inject(OFFBUDDY, "STATE", off) end)
  panelHint()
end

-- Testbuddy congratulates you: the message a friend's Congrats button sends, through the real path (your character
-- cheers, and the activity feed, the bar notice and the chat line show the words).
function ACTIONS.congratsIn()
  ensureFakes()
  local me = ns.playerName()
  local lines = ns.Roasts.CHEER_LINES
  local text = ns.Roasts.mockText(lines[math.random(#lines)], me, BUDDY, ns.Roasts.mockInfo(me))
  text = ns.Util.trim((text:gsub("{%a+}", "")))
  if not ns.Modules.isEnabled("roasts") or ns.Modules.setting("roasts", "cheers") == false then
    say("Live roasts or the Congrats button is off in /tc, so a congrats from a friend shows nothing.")
  end
  expect("congrats", BUDDY, function() inject(BUDDY, "MOCK", { t = me, x = text, k = "g" }) end)
end

function ACTIONS.layer()
  ensureFakes()
  if ns.Layer and ns.Layer.lookNow then ns.Layer.lookNow() end -- the fakes' first look, before the button's own news
  local now = layerOf[BUDDY] == "different" and "same" or "different"
  if not ns.Modules.isEnabled("layer") then say("the Layer tracker is turned off in /tc, so nothing shows.") end
  popupHint(now == "same" and "layerSame" or "layerDiff", now == "same" and "Back on my layer" or "Layer changes")
  layerOf[BUDDY] = now
  layerTurn = layerTurn + 1
  expect(now == "same" and "layer_same" or "layer_diff", BUDDY, function()
    inject(BUDDY, "UPDATE", { lk = tostring(900 + layerTurn) }) -- any news makes the layer tracker look again
    if ns.Layer and ns.Layer.lookNow then ns.Layer.lookNow() end -- now, while the pop-up is expected
  end)
end

function ACTIONS.roast()
  ensureFakes()
  roastTurn = roastTurn % #ROASTS + 1
  local r = ROASTS[roastTurn]
  local before = #ns.Roasts.forTest.shown()
  inject(BUDDY, "ROAST", { k = r.k, v = r.v or "", x = r.x or "", n = tostring(math.random(#ns.Roasts.LINES[r.k])) })
  if #ns.Roasts.forTest.shown() == before then
    say("no roast showed: Live roasts (or that kind of roast) is off in /tc, or one about Testbuddy showed less than "
      .. "10 seconds ago.")
  end
end

-- Testbuddy says it has the next version (after ours and after any real one heard): the gold "!", the panel line
-- and the how-to window come from the real update notice. restart: that version needs a game restart.
local function pretendUpdate(restart)
  ensureFakes()
  local base = ns.VERSION
  local real = ns.Version.realNewest()
  if real and ns.Util.compareVersions(real.ver, base) > 0 then base = real.ver end
  local head, n = tostring(base):match("^(.-)(%d+)$")
  local ver = (head or "0.0.") .. ((tonumber(n) or 0) + 1)
  inject(BUDDY, "UPDATE", { ver = ver, rs = restart and ver or ns.RESTART_SINCE })
  if not ns.Modules.isEnabled("updates") then
    say("Update reminders is turned off in /tc, so nothing shows.")
    return
  end
  ns.Updates.showHowTo()
end

function ACTIONS.updateReload() pretendUpdate(false) end
function ACTIONS.updateRestart() pretendUpdate(true) end

-- Find the crew: Walkbuddy is a pretend group member who walks in a circle around you (its positions go through the
-- real code), plus a pretend party meet-up 120 yards north of you. Press again to remove both.
local function walkStep()
  local me = ns.Where.me()
  if not me or not ns.roster:get(WALKER) then return end
  walkAngle = walkAngle + WALK_STEP
  inject(WALKER, "POS", ns.FindLogic.posFields({ c = me.c, x = me.x + math.cos(walkAngle) * WALK_RADIUS,
    y = me.y + math.sin(walkAngle) * WALK_RADIUS }))
end

local function removeWalker()
  stopWalk()
  if walkMeetId and ns.Find and ns.Find.meet() and ns.Find.meet().id == walkMeetId then
    inject(WALKER, "MEET", { id = walkMeetId, clr = "1", a = "party" })
  end
  return removeFake(WALKER)
end

function ACTIONS.walk()
  if ns.roster:get(WALKER) then
    removeWalker()
    say("Walkbuddy is gone.")
    return
  end
  if not ns.Modules.isEnabled("find") then
    say("Find the crew is turned off in /tc (under Extras), so no arrows show.")
    return
  end
  local me = ns.Where.me()
  if not me then
    say("the game doesn't tell TwizCrew where you are right now (in a dungeon?), so there is nothing to point at.")
    return
  end
  local zone = ns.Util.safeText(me.zone or "")
  inject(WALKER, "STATE", { cl = "HUNTER", lv = "11", zn = zone, sz = "", ins = "0", ver = ns.VERSION,
    rs = ns.RESTART_SINCE, tg = "" })
  walkAngle = 0
  walkStep()
  if C_Timer and C_Timer.NewTicker then
    walkTicker = C_Timer.NewTicker(WALK_TICK, function() ns.Log.safe(TOOLS, walkStep) end)
  end
  walkMeets = walkMeets + 1
  walkMeetId = "Walkbuddy-test-" .. walkMeets
  inject(WALKER, "MEET", { id = walkMeetId, c = tostring(me.c), x = tostring(math.floor(me.x + 120 + 0.5)),
    y = tostring(math.floor(me.y + 0.5)), p = zone, a = "party", l = tostring(ns.Config.MEET_LIFE) })
  panelHint()
  say("added Walkbuddy: a pretend member of your group walking around you, with an arrow on its row (click it for "
    .. "the big arrow), and a pretend meet-up 120 yards north (pop-up, big arrow, icon on your maps). Press again "
    .. "to remove them.")
end

-- Removes every fake thing. quiet: no chat line (Reset to defaults, logout).
local function clear(quiet)
  stopTicker()
  if ns.roster and ns.roster:get(WALKER) then ns.Log.safe(TOOLS, removeWalker) end
  stopWalk()
  reviveTurn = reviveTurn + 1
  copyOn, expected = false, nil
  local any = false
  for _, name in ipairs(ns.roster and ns.roster:testNames() or {}) do
    if ns.Log.safe(TOOLS, removeFake, name) then any = true end
  end
  layerOf = {}
  if ns.Feed then
    local fed, hadFeed = ns.Log.safe(TOOLS, ns.Feed.removeFakes)
    if fed and hadFeed then any = true end
  end
  local ok, had = ns.Log.safe(TOOLS, ns.Version.clearTest)
  if ok and had then any = true end
  ok, had = ns.Log.safe(TOOLS, ns.Updates.clearTest)
  if ok and had then any = true end
  if not quiet then say(any and "test stuff cleared." or "nothing to clear.") end
  return any
end

function ACTIONS.clear() clear(false) end

-- Belt and braces at logout: no fake name in the saved crew list or stats, whatever happened.
local function scrub()
  clear(true)
  local db = ns.db
  if type(db) ~= "table" then return end
  local lists = { db.roster }
  if type(db.stats) == "table" then lists[#lists + 1] = db.stats.crew; lists[#lists + 1] = db.stats.chars end
  for _, list in ipairs(lists) do
    if type(list) == "table" then
      for name in pairs(list) do if ns.isTestName(name) then list[name] = nil end end
    end
  end
end

local function run(id)
  if not ns.Modules.isEnabled(TOOLS) then
    say("the test tools turned off after errors. Type /reload to try again.")
    return
  end
  if not ns.roster then
    say("not ready yet, try again in a few seconds.")
    return
  end
  ns.Log.add("info", "test tools: %s pressed", id)
  local ok = ns.Log.safe(TOOLS, ACTIONS[id])
  if not ok then say("that test did not work. Type /tc report and tell Claude.") end
end

---------------------------------------------------------------------------------------------------- for the rest
-- Popups: may this fake's pop-up show? "My copy" shows what friends would see (your real level-ups and deaths);
-- other fakes only when a button expects that pop-up.
function TestTools.wants(kind, name)
  if name == COPY then return copyOn end
  return expected ~= nil and expected.kind == kind and expected.name == name
end

-- Layer: the layer the Layer pop-up button gave a fake (nil = work it out as usual).
function TestTools.layerOf(name) return layerOf[name] end

-- Find the crew: Walkbuddy counts as a member of your group (nobody else fake does).
function TestTools.inGroup(name) return name == WALKER end

-- /tc report line.
function TestTools.reportLine()
  local names = ns.roster and ns.roster:testNames() or {}
  local up = ns.Version.newest()
  local pretend = up and ns.isTestName(up.name) and up.ver or nil
  if #names == 0 and not pretend then return "Test tools: nothing fake" end
  local parts = {}
  if #names > 0 then parts[#parts + 1] = table.concat(names, ", ") end
  if pretend then parts[#parts + 1] = "pretend update v" .. pretend end
  return "Test tools: on (" .. table.concat(parts, "; ") .. ")"
end

local COMMANDS = {
  fake = "fake", copy = "copy", ding = "ding", death = "death", layer = "layer", roast = "roast", clear = "clear",
  online = "online", ["congrats in"] = "congratsIn",
  ["update reload"] = "updateReload", ["update restart"] = "updateRestart", walk = "walk",
  mock = "mockLive", ["mock live"] = "mockLive", ["mock icon"] = "mockIcon", cheer = "cheer", congrats = "cheer",
}

TestTools.HELP = {
  "TwizCrew test tools: only on your screen, never sent to your crew, never saved (also in /tc, under Try it out):",
  "/tc test fake - pretend friends: Testbuddy (earns XP, levels up after about 7 min), Maxbuddy (max level), "
    .. "Offbuddy (offline)",
  "/tc test copy - a pretend friend made from your own numbers, to compare with your XP bar (again: removes it)",
  "/tc test ding - Testbuddy levels up: the level-up pop-up",
  "/tc test death - Testbuddy dies: the death pop-up",
  "/tc test online - Offbuddy comes online: the online pop-up (or the bar notice while minimized) and a chat line",
  "/tc test congrats in - Testbuddy congratulates you: your character cheers, and the words show in the feed",
  "/tc test layer - Testbuddy changes layer: the layer pop-up",
  "/tc test roast - a roast about Testbuddy",
  "/tc test update reload - pretend a friend has a newer version that a /reload loads",
  "/tc test update restart - pretend a friend has a newer version that needs a game restart",
  "/tc test walk - Walkbuddy: a pretend group member walking around you (row arrow, big arrow) and a pretend "
    .. "meet-up 120 yards north (again: removes them)",
  "/tc test mock live | icon - you laughing at yourself: how a friend's mock about you looks",
  "/tc test clear - remove every pretend thing (Reset to defaults and /reload do too)",
}

-- /tc test <what>
function TestTools.command(rest)
  local id = COMMANDS[ns.Util.trim(tostring(rest or "")):lower():gsub("%s+", " ")]
  if not id then
    for _, line in ipairs(TestTools.HELP) do print(line) end
    return
  end
  run(id)
end

local function button(key, label, info)
  return { key = key, label = label, kind = "button", info = info, onClick = function() run(key) end }
end

ns.Modules.register({
  id = TOOLS, name = "Test tools", tier = "tools",
  info = "Pretend friends and pop-ups, so you can check how TwizCrew looks without waiting for your crew. Only on "
    .. "your screen: nothing is sent to your crew and nothing is saved. Clear test stuff, Reset everything to "
    .. "defaults or /reload removes it all. Also in chat: /tc test.",
  settings = {
    button("fake", "Fake friends", "Adds three pretend friends to the Crew panel: Testbuddy (level 12, XP numbers, "
      .. "FIGHTING, AFK and OTHER LAYER tags), Maxbuddy (max level) and Offbuddy (offline). Try every Row style and "
      .. "hover Testbuddy. It earns XP: \"About … min to level\" shows after about 3 minutes, and it levels up by "
      .. "itself after about 7 (you should get one ding). Press again to start them over."),
    button("copy", "Copy of me", "Adds \"My copy\": a pretend friend made from what your TwizCrew tells your crew "
      .. "about you, through the same code a friend's copy uses. Hover it and compare the numbers with your own XP "
      .. "bar. It keeps following you: your real level-ups and deaths pop up for it, like your friends would see. "
      .. "Press again to remove it."),
    button("ding", "Ding", "Testbuddy goes up one level: you should get one \"Testbuddy (test) reached level 13!\" "
      .. "pop-up, even right after logging in."),
    button("death", "Death pop-up", "Testbuddy dies: the death pop-up with the place, and a DEAD tag on the row for "
      .. "15 seconds."),
    button("online", "Friend comes online", "Offbuddy comes online: the \"is online\" pop-up, or the notice on the "
      .. "bar while the panel is minimized (with a peek at its row), the line in Recent activity and, if you turned "
      .. "it on, the chat line. Press again to go offline and online again."),
    button("congratsIn", "Congrats from a friend", "Testbuddy congratulates you, the way a friend's Congrats button "
      .. "does: your character cheers, and what was said shows on the minimized bar, in Recent activity and in chat."),
    button("layer", "Layer pop-up", "Testbuddy moves to the other layer: \"back on your layer\" or \"on a different "
      .. "layer\", taking turns. Clicking the pop-up invites nobody."),
    button("roast", "Roast pop-up", "An orange roast about Testbuddy, a different one each press. Roasts about the "
      .. "same person wait 10 seconds between them, like the real ones."),
    button("mockLive", "Try a mock (live)", "Your own character laughs at you with a roast, the way a friend near "
      .. "you looks when they mock you. Checks the 3D model and the laugh."),
    button("cheer", "Try a congrats", "Your own character cheers for you with an encouraging line, the way a "
      .. "friend's Congrats looks when you level up."),
    button("mockIcon", "Try a mock (icon)", "What a far-away friend you haven't been near this session gets: their "
      .. "class icon with the speech bubble."),
    button("updateReload", "Update notice (reload)", "Pretends Testbuddy has a newer TwizCrew that a /reload loads: "
      .. "the gold ! on the minimap button, the gold line on the Crew panel and the how-to window with Reload now."),
    button("updateRestart", "Update notice (restart)", "The same, for a newer version that needs a game restart: "
      .. "the window says to close WoW and has an OK button instead."),
    button("walk", "Walking buddy", "Adds Walkbuddy, a pretend member of your group walking in a circle around you: "
      .. "an arrow on its row turns as you turn and shows how far it is; click the arrow for the big arrow. Also a "
      .. "pretend meet-up 120 yards north of you: its pop-up, the big arrow and its icon on your world map and "
      .. "minimap. Press again to remove them."),
    button("clear", "Clear test stuff", "Removes every pretend friend, the pretend update (gold !, gold line, "
      .. "window) and stops their timers. Reset everything to defaults and /reload do this too."),
  },
  onEnable = function()
    ns.Bus.on(TOOLS, "SELF_UPDATED", function(changes)
      if copyOn and ns.roster and ns.roster:get(COPY) and type(changes) == "table" then
        inject(COPY, "UPDATE", changes) -- the same changes your friends just got
      end
    end)
    ns.Bus.on(TOOLS, "SETTINGS_RESET", function() clear(true) end)
    ns.Events.on(TOOLS, "PLAYER_LOGOUT", scrub)
  end,
  onDisable = function() clear(true) end,
})
