-- /tc report: a short health check, printed in chat and put in a box to copy (for Discord or for Claude).
-- Also the test tools ("Try it out" in /tc, and /tc test ...): pretend crew members and pop-ups through the real
-- code, so the owner can check things alone. See the bottom of this file.
local _, ns = ...

local Report = {}
ns.Report = Report

local FEATURE = "report"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, HEIGHT, PAD, LINE_HEIGHT = 480, 320, 12, 14
local CHAT_LINES = 5 -- the first lines also go to chat

local frame, edit, scroll
local shownText = ""

local function yes(v) return v and "yes" or "no" end

local function try(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function interface()
  local ok, _, _, _, n = try(GetBuildInfo)
  return ok and n and tostring(n) or "unknown"
end

local function duration(seconds)
  seconds = math.ceil(seconds)
  if seconds < 60 then return seconds .. " s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. " min" end
  return math.floor(seconds / 3600) .. " h " .. math.floor(seconds % 3600 / 60) .. " min"
end

local function fallbackName()
  local ok, grouped = try(IsInGroup)
  return (ok and grouped) and "group chat and whispers" or "whispers"
end

local function connection()
  local s = ns.Transport.status()
  local state
  if s.failed then
    state = "failed: " .. tostring(s.failReason)
    if type(s.downFor) == "number" then state = state .. "; down for " .. duration(s.downFor) end
    if type(s.nextRetryIn) == "number" then
      local using = s.mode == "auto" and ("using " .. fallbackName() .. ", ") or ""
      state = state .. "; " .. using .. "next try in " .. duration(s.nextRetryIn)
    end
  elseif s.joined then state = "joined"
  else state = "not joined" end
  return "Connection: " .. tostring(s.mode) .. " (channel " .. tostring(s.channel) .. " " .. state .. ")"
end

local function layer()
  local i = ns.LayerSensor.info()
  local seen = type(i.age) == "number" and ns.Util.ago(i.age) or "never"
  return "Layer: key " .. tostring(i.key or "none") .. ", seen " .. seen .. ", " .. tostring(i.secretSkipped or 0)
    .. " hidden values skipped"
end

local function heard(m)
  if type(m.lastHeard) == "number" then return ns.Util.ago(ns.now() - m.lastHeard) end
  if type(m.lastSeen) == "number" then return ns.Util.ago(ns.wallclock() - m.lastSeen) end
  return "never"
end

local function crewLines(add)
  if not ns.roster then return end
  for _, name in ipairs(ns.roster:names()) do
    local m = ns.roster:get(name)
    add(name .. ": " .. (m.online and "online" or "offline") .. ", heard " .. heard(m) .. ", v"
      .. tostring(m.version or "?"))
  end
end

-- Extra lines that answer the in-game checks of the test list (docs/TESTING.md) in one paste.
local function checkLines(add)
  -- a secret answer (dungeons) can't be tested: it reads as nil ("no")
  local function open(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
  end
  local function call(fn, ...)
    local ok, a, b = try(fn, ...)
    if ok then return open(a), open(b) end
  end
  local inInstance, kind = call(IsInInstance)
  add("Game says: flying " .. yes(call(UnitOnTaxi, "player")) .. ", away " .. yes(call(UnitIsAFK, "player"))
    .. ", in a dungeon " .. yes(inInstance) .. " (" .. tostring(kind or "none") .. "), fighting "
    .. yes(call(UnitAffectingCombat, "player")) .. ", dead " .. yes(call(UnitIsDeadOrGhost, "player")))
  add("Where: " .. tostring(call(GetRealZoneText) or "?") .. ", " .. tostring(call(GetSubZoneText) or "?"))
  local api = Settings
  add("Game features: options list " .. yes(type(api) == "table" and type(api.RegisterAddOnCategory) == "function")
    .. ", invite " .. yes((C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit)
    .. ", secret check " .. yes(type(issecretvalue) == "function")
    .. ", atlas check " .. yes(C_Texture and C_Texture.GetAtlasInfo)
    .. ", chat filter " .. yes(type(ChatFrame_AddMessageEventFilter) == "function"))
  local s = ns.Transport.status()
  add("Channel: number " .. tostring(s.channelIndex or 0) .. ", last send result "
    .. tostring(s.lastResult == nil and "none" or s.lastResult))
  local i = ns.LayerSensor.info()
  add("Layer looks: " .. tostring(i.observations or 0) .. " NPCs read, waiting to confirm "
    .. tostring(i.pending or "nothing"))
  add("Log: " .. #ns.Log.lines() .. " lines kept (written to disk at /reload or logout)")
end

-- Stats board lines: counting and detectors, the crew session, the last STATS sent and heard.
local function statsLines(add)
  local on = ns.Modules.isEnabled("stats")
  local off = {}
  if on then
    for _, d in ipairs(ns.Detectors.status()) do
      if not d.on then off[#off + 1] = d.id .. (d.why and (" (" .. tostring(d.why) .. ")") or "") end
    end
  end
  local offText = on and (#off > 0 and table.concat(off, ", ") or "none") or "all (stats are turned off)"
  add("Stats: " .. (on and "on" or "off") .. ", steps by " .. tostring(ns.Detectors.stepsMethod())
    .. ", detectors off: " .. offText)
  local s = ns.Session.decided() and ns.Session.current()
  if s then
    add("Session: " .. tostring(s.id) .. " started " .. ns.BoardLogic.timeText(s.start) .. " ("
      .. (s.manual and "by hand" or "automatic") .. ")")
  else
    add("Session: not decided yet")
  end
  local st = ns.Stats.status()
  local wall = ns.wallclock()
  local sent = type(st.lastSent) == "number" and ns.Util.ago(math.max(0, wall - st.lastSent)) or "never"
  local h = st.lastHeard
  local heardText = "never"
  if type(h) == "table" and type(h.at) == "number" then
    heardText = ns.Util.ago(math.max(0, wall - h.at)) .. " from " .. tostring(h.name)
  end
  add("Stats sent " .. sent .. ", heard " .. heardText)
end

function Report.lines()
  local out = {}
  local function add(s) out[#out + 1] = s end
  add("TwizCrew v" .. ns.VERSION .. ", interface " .. interface())
  add(connection())
  add(layer())
  add("Class icons: " .. tostring(ns.ClassIcon.method()))
  local broken = ns.Modules.broken()
  add("Turned off after errors: " .. (#broken > 0 and table.concat(broken, ", ") or "none"))
  statsLines(add)
  add(ns.Updates.reportLine())
  add(ns.MinimapButton.reportLine())
  add(ns.TestTools.reportLine())
  local ok, findLine = ns.Log.safe("find", ns.Find.reportLine)
  add(ok and findLine or "Find the crew: report line failed")
  crewLines(add)
  add("Recent errors:")
  local errors = ns.Log.errors(10)
  if #errors == 0 then add("none") end
  for _, e in ipairs(errors) do add(e) end
  add("In-game checks:")
  checkLines(add)
  if ns.Transport.status().hideFailed then
    add("Warning: the crew channel could not be taken out of the chat windows")
  end
  local st = ns.Transport.status()
  local names = st.members or {}
  add("Crew in the channel: " .. (#names == 0 and "nobody seen" or table.concat(names, ", "))
    .. " (member lists heard: " .. tostring(st.listsHeard or 0) .. ")")
  add("Channel echoes heard: " .. tostring(ns.Comm.echoCount and ns.Comm.echoCount() or 0))
  return out
end

---------------------------------------------------------------------------------------------------- copy box
local function selectAll()
  edit:SetFocus()
  edit:HighlightText()
end

local function build()
  frame = T.frame("Frame", "TwizCrewReport", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  Widgets.script(frame, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  Widgets.script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end, FEATURE)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewReport") end -- Escape

  local title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
  title:SetText("TwizCrew report")
  local hint = T.text(frame, T.FONT.small, C.muted)
  hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -12)
  hint:SetText("Press Ctrl+C to copy")

  scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -32)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 40)
  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  if edit.SetFontObject then edit:SetFontObject(T.FONT.small) end
  edit:SetWidth(WIDTH - 2 * PAD)
  scroll:SetScrollChild(edit)
  -- The box is for copying only: typing puts the report back and selects it again.
  Widgets.script(edit, "OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(shownText)
      self:HighlightText()
    end
  end, FEATURE)
  Widgets.script(edit, "OnEscapePressed", function() frame:Hide() end, FEATURE)
  Widgets.script(edit, "OnMouseUp", selectAll, FEATURE)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  Widgets.script(scroll, "OnMouseWheel", function(self, delta)
    local most = math.max(0, (tonumber(edit:GetHeight()) or 0) - (tonumber(self:GetHeight()) or 0))
    local v = (tonumber(self:GetVerticalScroll()) or 0) - (tonumber(delta) or 0) * 3 * LINE_HEIGHT
    self:SetVerticalScroll(math.max(0, math.min(most, v)))
  end, FEATURE)

  local close = Widgets.button(frame, "Close", function() frame:Hide() end, nil, FEATURE)
  close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)
  frame:Hide()
end

-- Shows the report in the copy box with all the text selected, and the first lines in chat.
function Report.show()
  local lines = Report.lines()
  local safe = {}
  for i, line in ipairs(lines) do safe[i] = ns.Util.safeText(line) end
  for i = 1, math.min(CHAT_LINES, #safe) do print("TwizCrew: " .. safe[i]) end
  print("TwizCrew: the full report is in the box. Press Ctrl+C to copy it.")
  -- Also into the saved log, so Claude can read the owner's report from the SavedVariables file after a /reload.
  for _, line in ipairs(safe) do ns.Log.add("info", "report: %s", line) end
  if not frame then build() end
  shownText = table.concat(safe, "\n")
  edit:SetHeight(#safe * LINE_HEIGHT + 10)
  edit:SetText(shownText)
  frame:Show()
  scroll:SetVerticalScroll(0)
  selectAll()
end

---------------------------------------------------------------------------------------------------- test tools
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

function ACTIONS.layer()
  ensureFakes()
  local now = layerOf[BUDDY] == "different" and "same" or "different"
  if not ns.Modules.isEnabled("layer") then say("the Layer tracker is turned off in /tc, so nothing shows.") end
  popupHint(now == "same" and "layerSame" or "layerDiff", now == "same" and "Back on my layer" or "Layer changes")
  layerOf[BUDDY] = now
  layerTurn = layerTurn + 1
  expect(now == "same" and "layer_same" or "layer_diff", BUDDY, function()
    inject(BUDDY, "UPDATE", { lk = tostring(900 + layerTurn) }) -- any news makes the layer tracker look again
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
