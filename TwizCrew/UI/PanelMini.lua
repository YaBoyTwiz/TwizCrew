-- The Crew panel minimized: the header bar alone, the notices on it (with the missed number and the flash), the peek
-- at a friend's row and the bar opening under the mouse. Part of the panel (UI/Panel.lua); shared names live on
-- ns.Panel._ (P).
local _, ns = ...

local Panel = ns.Panel
local P = Panel._

local FEATURE = "panel"
local FL = ns.FeedLogic
local setting, set, minimized, clamp = P.setting, P.set, P.minimized, P.clamp
local requestRedraw = P.requestRedraw

local FLASH_SECONDS, BAR_TICK = 1.6, 0.1
local barTicker
local lastTickAt
---------------------------------------------------------------------------------------------------------- minimize
-- Is the mouse on the panel (or on one of our menus, which hang off it)?
local function mouseOverPanel()
  if not P.root then return false end
  if P.root.IsMouseOver then
    local ok, over = pcall(P.root.IsMouseOver, P.root)
    if ok and over == true then return true end
  elseif type(MouseIsOver) == "function" then
    local ok, over = pcall(MouseIsOver, P.root)
    if ok and over == true then return true end
  end
  -- an open menu counts only when it was opened from the panel
  local menu = type(TwizCrewMenu) == "table" and TwizCrewMenu or nil
  if menu and P.menuAnchor and menu.IsShown then
    local ok, shownNow = pcall(menu.IsShown, menu)
    if not (ok and shownNow == true) then return false end
    local got, _, rel = pcall(menu.GetPoint, menu, 1)
    if got and rel ~= nil then return rel == P.menuAnchor end
    return true -- cannot tell which frame it hangs from
  end
  return false
end

local startBarTicker -- (below)

-- A notice's friend: their row drops open under the bar for a few seconds (never in a fight).
local function startPeek(e)
  if not e or not setting("peek") or P.inCombat then return end
  local raw = (tostring(e.who or ""):gsub("||", "|"))
  if not (ns.roster and ns.roster:get(raw)) then return end
  P.peek = { name = raw, untilT = ns.now() + clamp(setting("peekSeconds"), 1, 30, 5) }
end

local function needTicker()
  if not P.bar or not P.enabled then return false end
  return P.bar:current() ~= nil or P.peek ~= nil or P.hoverOpen
    or (P.shown and minimized() and setting("barHover") == true)
end

local function stopBarTicker()
  lastTickAt = nil
  if barTicker then barTicker:Cancel(); barTicker = nil end
end
P.stopBarTicker = stopBarTicker

-- Ten times a second while something is going on: the notice queue and its flash, the peek, the mouse on the bar.
local function barTick()
  if not P.bar or not P.enabled then stopBarTicker(); return end
  local now = ns.now()
  local dt = lastTickAt and math.max(0, math.min(now - lastTickAt, 1)) or 0
  lastTickAt = now
  local changed = false
  -- the mouse is on the peeked friend's row: that notice (and row) stay until it leaves, so a click on Congrats
  -- always goes to the friend the bar and the row show
  if P.peek and mouseOverPanel() then P.bar:delay(dt) end
  local cur, moved = P.bar:tick(now)
  if moved then
    changed = true
    if cur then startPeek(cur) end -- the next notice's friend
  end
  if P.flashTex then
    local age = cur and P.bar:flashAge(now) or nil
    local a = 0
    if age and age < FLASH_SECONDS then a = 0.5 * (1 - age / FLASH_SECONDS) end
    P.flashTex:SetAlpha(a)
  end
  if P.peek then
    local over = mouseOverPanel()
    if over then P.peek.held = true end
    if P.inCombat or (now >= P.peek.untilT and not over) then P.peek = nil; changed = true end
  end
  local want = minimized() and setting("barHover") == true
  if want then
    local over = mouseOverPanel()
    if over ~= P.hoverOpen then P.hoverOpen = over and true or false; changed = true end
  elseif P.hoverOpen then
    P.hoverOpen = false
    changed = true
  end
  if changed then requestRedraw() end
  if not needTicker() then stopBarTicker() end
end

startBarTicker = function()
  if barTicker or not needTicker() then return end
  if C_Timer and C_Timer.NewTicker then
    barTicker = C_Timer.NewTicker(BAR_TICK, function() ns.Log.safe(FEATURE, barTick) end)
  end
end
P.startBarTicker = startBarTicker

P.syncBarTicker = function()
  if needTicker() then startBarTicker() else stopBarTicker() end
end

-- Which news the bar shows: the pop-up kinds follow the pop-up switches (no point in news you turned off).
local POPUP_SWITCH = { online = "online", died = "death", levelup = "levelUp" }
local function noticeWanted(e)
  local key = POPUP_SWITCH[e.kind]
  if not key then return true end
  return ns.Modules.isEnabled("popups") and ns.Modules.setting("popups", key) == true
end

-- The activity feed recorded something (FEED_ADDED). While minimized: a notice on the bar (and a peek), and one more
-- missed.
function Panel.onFeed(e)
  if not P.enabled or not P.bar or not minimized() or type(e) ~= "table" then return end
  -- no bar on screen (hidden in a fight, when alone, in a dungeon) or the panel is open under the mouse: the pop-up
  -- was shown, so the bar neither shows it nor counts it as missed
  if not P.shown or P.curView == "full" then return end
  if not FL.isNoticeKind(e) or not noticeWanted(e) then return end
  P.bar:addMissed()
  local started, promoted = P.bar:push(e, ns.now())
  if promoted then startPeek(promoted) elseif started then startPeek(e) end
  startBarTicker()
  requestRedraw()
end

-- Is this pop-up (the pop-ups module's kind: online, death, levelup) replaced by the bar right now? Only while the
-- bar is on screen and shows notices, and the player left "show these on the bar instead of pop-ups" on.
function Panel.suppressesPopup(popupKind, name)
  return FL.suppressesPopup(popupKind, {
    feedTakes = ns.Feed ~= nil and ns.Feed.willTake(popupKind, name) or false,
    minimized = minimized(),
    barShown = P.enabled and P.shown and ns.Feed ~= nil and ns.Modules.isEnabled("activity") and P.curView ~= "full",
    setting = setting("barInstead") == true,
  })
end

-- Minimize or restore; returns whether the panel is minimized now. Saved with the other settings.
function Panel.toggleMinimized()
  local now = not minimized()
  set("minimized", now)
  return now
end

function Panel.isMinimized() return minimized() end

-- The "minimized" setting changed (from the button, /tc mini, the key, the settings window or a reset).
function Panel.minimizedChanged()
  if not minimized() then -- restored: whatever was missed is on the panel again
    if P.bar then P.bar:clear(); P.bar:clearMissed() end
    P.peek, P.hoverOpen = nil, false
    if P.flashTex then P.flashTex:SetAlpha(0) end
    stopBarTicker()
  end
  if P.enabled then
    startBarTicker()
    requestRedraw()
  end
end

-- A click on the notice on the bar: what clicking that pop-up does (a level-up: congratulate them; online: whisper
-- them); anything else opens the recent activity list. The notice is then done.
function Panel.noticeClicked()
  if not P.bar then return end
  local e = P.bar:current()
  if not e or e ~= P.noticeShown then return end -- the notice drawn is not the one the bar holds now
  local raw = (tostring(e.who or ""):gsub("||", "|"))
  if e.kind == "levelup" then
    if not ns.isTestName(raw) then Panel.cheer({ tcModel = { name = raw } }) end
  elseif e.kind == "online" then
    if ns.Popups and ns.Popups.act then ns.Popups.act("online", raw) end
  elseif ns.Recent then
    ns.Recent.open()
  end
  local nextEntry = P.bar:dismiss(ns.now())
  if not (P.peek and mouseOverPanel()) then -- (never swap the row under the mouse)
    if nextEntry then startPeek(nextEntry) else P.peek = nil end
  end
  startBarTicker()
  requestRedraw()
end

-- A click on the missed number: the recent activity list (which counts as having seen them).
function Panel.missedClicked()
  if ns.Recent and ns.Recent.open() and P.bar then
    P.bar:clearMissed()
    requestRedraw()
  end
end

function Panel.barForTest() return P.bar end
function Panel.peekForTest() return P.peek end
function Panel.barTickerForTest() return barTicker ~= nil end
function Panel.viewForTest() return P.curView end
function Panel.noticeForTest() return P.noticeShown end
function Panel.rootForTest() return P.root end
function Panel.hoverOpenForTest() return P.hoverOpen end
