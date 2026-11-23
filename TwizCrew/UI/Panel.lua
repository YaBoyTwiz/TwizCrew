-- The Crew panel: a movable window with one row per guild member, in four sections: My party, Pinned (online),
-- the "Guild online (N)" bar and its rows, the "Offline (N)" bar and its rows (rules: UI/PanelLogic.lua). Guild
-- members without the addon are rows too, dimmed. Pins are saved per guild (ns.db.pins). Registers the module "panel".
-- Hiding the panel = turning the module off. Redraws are coalesced: many requests in one frame -> one redraw.
-- While the stats module is on, two tabs sit under the header: "Crew" (the rows, with award titles under the
-- winners' names) and "Hall of Shame" (drawn by ns.Board). The tab is not saved. While the calendar module is on, a
-- "Calendar" button sits next to them: it opens the crew calendar's own window (not a tab), and a gold glow pulses
-- behind it while the calendar has something new (ns.Notes.fresh). Either module alone keeps the bar. A gold "?" at
-- the end (when it fits) opens "How to use TwizCrew" (UI/About.lua; the wrench menu has it too).
-- The crew tab (2026-11-23): unless "Keep open" is on, the panel is tucked away into a small tab on the left or right
-- screen edge; resting the mouse on the tab (or a click) slides the whole panel out, and news slides out one row at a
-- time. While tucked, the panel frame is the child of a holder that clips it (UI/PanelTab.lua); with Keep open on it
-- is the ordinary movable window it always was.
-- This file: settings, the frame, look and position, the redraw, enable / disable. The rest, loaded right after it:
-- UI/PanelRows.lua (rows, row arrows, row tooltips), UI/PanelHeader.lua (the header bar, the Keep open switch, the
-- update and What's new lines), UI/PanelMenus.lua (the menus and the status box) and UI/PanelTab.lua (the crew tab,
-- the slide, the news queue).
-- What more than one of these files uses lives on ns.Panel._ (P).
local _, ns = ...

local Panel = {}
ns.Panel = Panel
local P = {}
Panel._ = P

local FEATURE = "panel"
local T, Widgets, Logic = ns.Theme, ns.Widgets, ns.PanelLogic
local C = T.COLOR

local ROW_WIDTH = { full = 230, compact = 200, tiny = 160 }
local HEADER_HEIGHT, PAD, GAP, LINE = 24, 8, 10, 15
local TAB_HEIGHT, BOARD_WIDTH = 18, 320
local OFF_HEIGHT = 20    -- the "Guild online (N)" and "Offline (N)" bars
local HEAD_HEIGHT = 14   -- the thin "My party" / "Pinned" headings
local BOARD_UNAVAILABLE = "Hall of Shame unavailable right now"
local TICK = 30 -- seconds; keeps "last seen 2h ago" fresh
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local LOOK_KEYS = { scale = true, bgAlpha = true, position = true, fadeOut = true, fadeAlpha = true }
local REDRAW_ON = { "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED", "LAYER_RELATION",
  "SETTING_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED", "STATS_CHANGED", "SESSION_CHANGED", "UPDATE_SEEN",
  "MEMBER_REMOVED", "AWAY_CHANGED", "FIND_CHANGED", "TROPHIES_CHANGED", "CLOWN_CHANGED", "GUILD_LIST", "GUILD_STATE",
  "PINS_CHANGED", "CALENDAR_FRESH" }
P.ROW_WIDTH, P.HEADER_HEIGHT, P.PAD, P.LINE = ROW_WIDTH, HEADER_HEIGHT, PAD, LINE

-- Shared state (set and read by more than one of the panel's files)
-- Functions and constants on P are set once, at load, in this file; later files may copy them into locals; state
-- that changes is always read as P.x.
P.root = nil           -- the panel frame (made in build)
P.countText = nil      -- the count in the header ("2 here · 3 online"), or the news line while news is slid out
P.header, P.headerShort = "", nil -- the count's text; the short count ("1/3") when room is tight
P.tabBar = nil         -- the Crew / Hall of Shame tabs and the Calendar button (only made when ns.Board exists)
P.visibleRows = 0      -- rows drawn by the last redraw
P.enabled, P.shown, P.inCombat = false, false, false
P.tipRow = nil         -- the row whose tooltip is showing (redraws refresh it)
P.tipKey = nil         -- whose row it was (a redraw can put someone else in that row)
P.menuAnchor = nil     -- the frame the panel's last menu hangs from (see openMenu)
P.noticeShown = nil    -- the news entry the header line shows now (test hook)
-- The crew tab (UI/PanelTab.lua). See PanelLogic.view and FeedLogic.newBar.
P.bar = nil            -- the news queue and the missed counter (FeedLogic.newBar), made when the panel starts
P.open = nil           -- { by = "hover" | "click", leftAt } while the whole panel is slid out of the tab
P.curView = "full"     -- "full", "peek" or "tab" (PanelLogic.view), set by every redraw
P.marks = { dead = false, layer = false } -- the tab's steady marks (PanelLogic.tabMarks)
P.here = 0             -- the header's "here" count (the tab shows it)
P.tab = nil            -- the crew tab frame (made in UI/PanelTab.lua's buildTab; scaled with the panel)

local noteText
local offBar, guildBar -- the "Offline (N)" and "Guild online (N)" bars
local offBarShown, guildBarShown, entries = false, false, {}
local headFrames = {}      -- "My party" / "Pinned" heading -> its frame
local CHEER_FOR = 300 -- seconds the Congrats button stays on a friend's row after they level up
local dingAt, cheered = {}, {} -- name -> when they leveled up; name -> true once we congratulated them
P.cheered = cheered
local crewTab, shameTab, calTab, helpTab
local calTicker        -- pulses the glow behind the Calendar button while the calendar has something new
local CAL_PULSE_TICK = 0.1
local tab = "crew"     -- "crew" | "shame" (session only)
local rowFrames = {}   -- pool, created once and reused (at most PANEL_MAX_ROWS)
P.rowFrames = rowFrames
local models = {}      -- row models of the last redraw
local note             -- the note under the rows (or the board's fallback line) while shown, else nil
local titleCache       -- { view, sid, titles } until stats, the session or the settings change (nil = compute)
local offset = 0       -- scroll: rows skipped at the top
local firstRow = 1
local pending, moving = false, false
local ticker
local redraws = 0
local fadeElapsed = 0
local FL = ns.FeedLogic
local NOTICE_SHORT, NOTICE_QUEUE = 3, 8 -- news stays 3 s when two or more wait, 8 wait at most

local function setting(key) return ns.Modules.setting(FEATURE, key) end
local function set(key, value) return ns.Modules.set(FEATURE, key, value) end
local function keepOpen() return setting("keepOpen") == true end

-- Is the panel on the right half of the screen (the tab on the right edge, or a kept-open panel there)? Tooltips and
-- menus then open toward the middle of the screen.
local function onRight()
  if not keepOpen() then return setting("tabSide") == "right" end
  if not P.root then return false end
  local ok, cx = pcall(P.root.GetCenter, P.root)
  local okW, w = pcall(UIParent.GetWidth, UIParent)
  local s = P.root.GetEffectiveScale and P.root:GetEffectiveScale() or 1
  local u = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if not ok or not okW or type(cx) ~= "number" or type(w) ~= "number" or w <= 0 or type(s) ~= "number"
    or type(u) ~= "number" or u <= 0 then
    return false
  end
  return cx * s / u > w / 2
end
P.onRight = onRight
-- "ANCHOR_RIGHT" for a tooltip beside the panel, "ANCHOR_LEFT" when the panel is on the right.
function P.sideAnchor() return onRight() and "ANCHOR_LEFT" or "ANCHOR_RIGHT" end

-- The panel's own menus go through here, so we know which frame the shared menu (the minimap button, the calendar and
-- the meet map use it too) hangs from. On the right half of the screen they open toward the middle.
local function openMenu(anchor, items)
  P.menuAnchor = anchor
  return Widgets.menu(anchor, items, onRight())
end
local function script(frame, name, fn) Widgets.script(frame, name, fn, FEATURE) end

local function clamp(v, lo, hi, fallback)
  v = tonumber(v)
  if v == nil or v ~= v then return fallback end
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function round(v) return math.floor(v * 10 + 0.5) / 10 end
P.setting, P.set, P.keepOpen, P.openMenu, P.script, P.clamp = setting, set, keepOpen, openMenu, script, clamp

local function allSettings()
  local out = {}
  for key in pairs(ns.Modules.get(FEATURE).defaults) do out[key] = setting(key) end
  return out
end

local function relationOf(name)
  if ns.Layer then return ns.Layer.relationOf(name) end
  return "unknown"
end

-- The Hall of Shame tab and titles exist only while the stats module is on.
local function statsOn()
  return ns.Board ~= nil and P.tabBar ~= nil and ns.Modules.isEnabled("stats")
end

-- The Calendar button next to the tabs exists only while the calendar module is on.
local function calOn()
  return ns.Calendar ~= nil and calTab ~= nil and ns.Modules.isEnabled("calendar")
end

-- Something new in the calendar (asked inside ns.Log.safe("calendar", ...): never an error charged to the panel).
local function calFresh()
  if not ns.Notes then return false end
  local ok, fresh = ns.Log.safe("calendar", ns.Notes.fresh)
  return ok and fresh == true
end

local function stopCalPulse()
  if calTicker then calTicker:Cancel(); calTicker = nil end
  if calTab then calTab.glow:SetAlpha(0) end
end

local function pulseCal() calTab.glow:SetAlpha(Logic.pulseAlpha(ns.now())) end

-- The glow pulses only while the button is on screen and something is new.
local function syncCalPulse(on)
  if not on then return stopCalPulse() end
  pulseCal()
  if not calTicker and C_Timer and C_Timer.NewTicker then
    calTicker = C_Timer.NewTicker(CAL_PULSE_TICK, function() ns.Log.safe(FEATURE, pulseCal) end)
  end
end

local function setCalWords(words)
  if calTab.words == words then return end
  calTab.words = words
  calTab.label:SetText(words)
  local w = calTab.label:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = #words * 6 end
  calTab:SetWidth(w + 10)
end

-- The bar under the header: Crew, Hall of Shame (stats on), Calendar (calendar on), then "?" (the About page) when it
-- fits (the wrench menu has it too). width: the panel's width now.
local function drawTabs(width)
  local stats, cal = statsOn(), calOn()
  local used = (PAD - 5) + crewTab:GetWidth() + 4 + (stats and (shameTab:GetWidth() + 4) or 0)
  crewTab:SetActive(tab == "crew")
  if stats then
    shameTab:SetActive(tab == "shame")
    shameTab:Show()
  else
    shameTab:Hide()
  end
  if cal then
    local fresh = calFresh()
    local before = (PAD - 5) + crewTab:GetWidth() + 4 + (stats and (shameTab:GetWidth() + 4) or 0)
    setCalWords("Calendar")
    -- tiny rows: the short word (room kept for the "?" after it)
    if before + calTab:GetWidth() + 4 + helpTab:GetWidth() > width then setCalWords("Cal") end
    calTab:ClearAllPoints()
    calTab:SetPoint("LEFT", stats and shameTab or crewTab, "RIGHT", 4, 0)
    T.textColor(calTab.label, fresh and C.text or C.muted)
    calTab:Show()
    syncCalPulse(fresh)
    used = used + calTab:GetWidth() + 4
  else
    calTab:Hide()
    stopCalPulse()
  end
  helpTab:ClearAllPoints()
  helpTab:SetPoint("LEFT", cal and calTab or (stats and shameTab or crewTab), "RIGHT", 4, 0)
  if used + helpTab:GetWidth() <= width then helpTab:Show() else helpTab:Hide() end
  P.tabBar:Show()
end

local function forgetTitles() titleCache = nil end

-- The award titles, computed inside ns.Log.safe("board", ...): a stats-side error means no titles (until the next
-- change), never an error charged to the panel.
local function computeTitles(view, sid)
  local ok, titles = ns.Log.safe("board", function()
    return ns.StatsLogic.titles(ns.StatsLogic.awards(ns.StatsStore.entries(view, sid)))
  end)
  if not ok or type(titles) ~= "table" then titles = {} end
  return titles
end

-- titleOf(name) for the row models (nil = no titles). Cached until STATS_CHANGED, SESSION_CHANGED, a stats
-- setting change, a settings reset, a module switch or a new Clown of the Night (CLOWN_CHANGED).
local function titleOf()
  if not statsOn() then return nil end
  local view = ns.Modules.setting("stats", "titles")
  if view ~= "session" and view ~= "all" then return nil end
  local session = ns.Session and ns.Session.current()
  local sid = session and session.id
  local c = titleCache
  if not c or c.view ~= view or c.sid ~= sid then
    c = { view = view, sid = sid, titles = computeTitles(view, sid), clowns = {} }
    -- the Clown of the Night (voted in the awards show) beats award titles until the next vote
    local clown = ns.db and type(ns.db.stats) == "table" and ns.db.stats.clown
    if type(clown) == "table" and type(clown.names) == "table" then
      for _, name in ipairs(clown.names) do if type(name) == "string" then c.clowns[name] = true end end
    end
    titleCache = c
  end
  local titles, clowns = c.titles, c.clowns
  return function(name)
    if clowns[name] then return ns.ShowLogic.CLOWN_TITLE end
    return titles[name]
  end
end

local function inDungeon()
  local _, kind = ns.Util.plain(IsInInstance)
  return kind == "party" or kind == "raid"
end
P.inDungeon = inDungeon

---------------------------------------------------------------------------------------------------------- position
local function applyPosition()
  if moving then return end -- never re-anchor while the player is dragging it
  if not keepOpen() then return P.placeTab() end -- tucked: the tab has the place, the panel hangs from it
  local p = setting("position")
  if type(p) ~= "table" or not POINTS[p.point] then p = ns.Modules.get(FEATURE).defaults.position end
  P.root:ClearAllPoints()
  P.root:SetPoint(p.point, UIParent, p.point, tonumber(p.x) or 0, tonumber(p.y) or 0)
end
P.applyPosition = applyPosition

-- Where the panel is now, anchored at the corner that matches the grow direction (top-left for down,
-- bottom-left for up), so the panel grows away from that corner. nil if the game has not placed it yet.
local function currentPosition()
  local left, top, bottom = P.root:GetLeft(), P.root:GetTop(), P.root:GetBottom()
  local s, u, uiTop = P.root:GetEffectiveScale(), UIParent:GetEffectiveScale(), UIParent:GetTop()
  for _, v in ipairs({ left, top, bottom, s, u, uiTop }) do
    if type(v) ~= "number" or v ~= v then return nil end
  end
  if s <= 0 or u <= 0 then return nil end
  if setting("grow") == "up" then return { point = "BOTTOMLEFT", x = round(left), y = round(bottom) } end
  return { point = "TOPLEFT", x = round(left), y = round(top - uiTop * u / s) }
end

local function savePosition()
  if not keepOpen() then return end -- (tucked, the panel hangs from the tab: its own place is kept for Keep open)
  local p = currentPosition()
  if p then set("position", p) end
end

-- After a reset or a grow change the saved corner may not match; convert it without moving the panel.
local function normalizeAnchor()
  if moving or not keepOpen() then return end
  local p = setting("position")
  local want = setting("grow") == "up" and "BOTTOMLEFT" or "TOPLEFT"
  if type(p) ~= "table" or p.point ~= want then savePosition() end
end

local function startDrag()
  if setting("locked") or not keepOpen() or not P.root.StartMoving then return end
  moving = true
  P.root:StartMoving()
end

local function stopDrag()
  if not moving then return end
  moving = false
  if P.root.StopMovingOrSizing then P.root:StopMovingOrSizing() end
  -- We save the position ourselves; the game's own layout cache must not move the panel at the next login.
  if P.root.SetUserPlaced then P.root:SetUserPlaced(false) end
  savePosition()
end

local function draggable(f)
  f:EnableMouse(true)
  if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
  script(f, "OnDragStart", startDrag)
  script(f, "OnDragStop", stopDrag)
end
P.draggable = draggable

---------------------------------------------------------------------------------------------------------- look
local function fadeStep()
  local over = false
  if P.root.IsMouseOver then over = P.root:IsMouseOver()
  elseif type(MouseIsOver) == "function" then over = MouseIsOver(P.root) end

  P.root:SetAlpha(over and 1 or clamp(setting("fadeAlpha"), 0.1, 1, 0.3))
end

-- The raw handler only adds up the time; the safe wrapper runs once per 0.1 s step.
local function fadeTick(_, elapsed)
  fadeElapsed = fadeElapsed + (tonumber(elapsed) or 0)
  if fadeElapsed < 0.1 then return end
  fadeElapsed = 0
  ns.Log.safe(FEATURE, fadeStep)
end

local appliedScale -- the scale the panel has now, to keep its corner still when the scale changes
P.appliedScale = function() return appliedScale or 1 end

-- Only the player changing the scale setting moves the saved corner (a reset brings its own position).
-- Reset relies on Modules.resetAll running the setting hooks in alphabetical key order: "position" is put back
-- before "scale" comes here.
local function rescaleSavedPosition()
  local newScale = clamp(setting("scale"), 0.5, 2, 1)
  local oldScale = appliedScale
  local pos = setting("position")
  if oldScale and oldScale ~= newScale and type(pos) == "table" then
    local x, y = Logic.rescalePosition(pos.x, pos.y, oldScale, newScale)
    if x and y and (x ~= tonumber(pos.x) or y ~= tonumber(pos.y)) then
      local moved = ns.Util.copy(pos)
      moved.x, moved.y = round(x), round(y)
      appliedScale = newScale -- (saving runs applyLook, which must not rescale again)
      set("position", moved)
    end
    -- the tab's height is in its own scaled units too
    local ty = tonumber(setting("tabY"))
    if ty then
      local _, y2 = Logic.rescalePosition(0, ty, oldScale, newScale)
      if y2 and y2 ~= ty then appliedScale = newScale; set("tabY", round(y2)) end
    end
  end
end

local function applyLook()
  local newScale = clamp(setting("scale"), 0.5, 2, 1)
  appliedScale = newScale
  P.root:SetScale(newScale)
  local alpha = clamp(setting("bgAlpha"), 0, 1, 0.8)
  T.setBackgroundAlpha(P.root, alpha)
  for _, r in ipairs(rowFrames) do T.setBackgroundAlpha(r, alpha) end
  if P.tab then P.tab:SetScale(newScale) end
  applyPosition()
  if setting("fadeOut") and keepOpen() then -- (a tucked panel only shows while it is looked at)
    P.root:SetScript("OnUpdate", fadeTick)
    P.root:SetAlpha(clamp(setting("fadeAlpha"), 0.1, 1, 0.3))
  else
    P.root:SetScript("OnUpdate", nil)
    P.root:SetAlpha(1)
  end
end
P.applyLook = applyLook

---------------------------------------------------------------------------------------------------------- redraw
local function hide()
  if P.root then
    stopDrag() -- a drag cut short by hiding must not leave the panel "moving"
    P.root:Hide()
  end
  P.hideTab()
  P.open = nil -- (hidden in a fight, a dungeon or alone: it must not slide out by itself when it comes back)
  if P.tipRow then Panel.hideRowTip(P.tipRow) end
  P.shown = false
  if ns.Guild then ns.Guild.setWatched(false) end
  P.syncBarTicker()
  note = nil
  P.curView = "tab"
  P.stopArrowTicker()
  stopCalPulse()
  Widgets.closeMenu()
end

-- After every resize: remembers the height, reads the guild list often while the panel or its tab is on screen
-- (the tab shows the count too), and fits the tab's holder to the panel. The full panel's last height is kept in ns.db.panelFullHeight (the first run of the crew
-- tab uses it to place the tab).
local function settle(width, height, view)
  P.rootW, P.rootH = width, height
  if ns.Guild then ns.Guild.setWatched(true) end
  if view == "full" and ns.db then ns.db.panelFullHeight = height end
  P.fitClip()
end

---------------------------------------------------------------------------------------------------------- who is shown
local function pinsOf()
  local g = ns.Guild
  if g and g.active() and ns.db and type(ns.db.pins) == "table" then return ns.db.pins end
  return nil
end

-- Keys (of these rows) that are in my party or raid. Only asked while grouped (or for a pretend friend), the game's
-- group check is not free.
local function partyOf(keys)
  local set, any = {}, false
  local grouped = ns.Where ~= nil and ns.Where.inGroup() or false
  for key in pairs(keys) do
    if ns.Where and (grouped or ns.isTestName(key)) and ns.Where.isGroupMember(key) then set[key] = true; any = true end
  end
  return set, grouped or any
end

-- Is this member close to me: in my party or raid, or pinned? (Test tools' fakes always count.) The same group check
-- as the party section (Where.isGroupMember).
-- (Like isPinned, false for real friends while TwizCrew is not using this guild's data; fakes always close.)
function Panel.isClose(key)
  if type(key) ~= "string" then return false end
  if ns.isTestName(key) then return true end
  if ns.Guild and not ns.Guild.active() then return false end
  if Panel.isPinned(key) then return true end
  return ns.Where ~= nil and ns.Where.isGroupMember(key) == true
end

-- Should a notice of this kind (feed or pop-up kind name) about this member be shown now? The "Tell me about" setting.
function Panel.noticeInScope(kind, key)
  if not ns.Modules.isEnabled(FEATURE) then return true end -- no panel: no pins and no setting to reach
  local scope = ns.Modules.setting(FEATURE, "noticeScope")
  return ns.FeedLogic.inScope(kind, scope, scope ~= "guild" and Panel.isClose(key))
end

-- The members to draw (roster rows, the guild's members without the addon, in the sort order) and what the rows need to
-- know (Logic.rows ctx). Not in a usable guild: only the pretend friends (test tools), listed flat.
local function crewOf(s, active)
  local list, extra = {}, {}
  for _, m in ipairs(ns.roster and ns.roster:members(true) or {}) do
    if active or ns.isTestName(m.name) then list[#list + 1] = m end
  end
  if active then
    local have = {}
    for _, m in ipairs(list) do have[m.name] = true end
    extra = Logic.noAddonMembers(ns.Guild.members(), have, ns.myKey())
    for _, m in ipairs(extra) do list[#list + 1] = m end
  end
  ns.Roster.sortList(list, s.sort, relationOf)
  local keys = {}
  for _, m in ipairs(list) do if m.online then keys[m.name] = true end end
  local party, grouped = partyOf(keys)
  local ctx = { party = party, pins = pinsOf(), canPin = active, display = active and ns.Guild.display or nil,
    get = active and ns.Guild.get or nil }
  return list, extra, ctx, grouped
end

local function hideChrome()
  offBar:Hide(); guildBar:Hide()
  offBarShown, guildBarShown = false, false
  for _, f in pairs(headFrames) do f:Hide() end
end

local function redraw()
  redraws = redraws + 1
  if not P.root or not P.enabled then return end
  if not statsOn() then tab = "crew" end
  local s = allSettings()
  local online = 0
  if ns.roster then online = ns.roster:onlineCount() end
  if not Logic.visible(s, { inCombat = P.inCombat, inInstance = inDungeon(), onlineCount = online }) then
    hide()
    return
  end

  -- kept open: everything ("full"). Tucked into the tab: the tab alone ("tab"), one piece of news slid out ("peek"),
  -- or everything while the mouse or a click opened it ("full"). While tucked, the panel is laid out as the full
  -- panel behind the closed holder, so it is ready to slide out.
  local kept = s.keepOpen == true
  local news = (not kept) and P.newsNow() or nil
  local view = Logic.view({ keepOpen = kept, open = P.open ~= nil, news = news ~= nil, inCombat = P.inCombat })
  P.curView = view
  local active = ns.Guild ~= nil and ns.Guild.active()
  local members, extra, ctx, grouped = crewOf(s, active)
  -- the header: people in the main view (party and pinned, and me), guild members online (the count follows the
  -- no-addon setting)
  local here, onlineAll = Logic.hereCount(members, ctx, s.showNoAddon, active), 0
  P.here = here
  if s.showSelf and ns.Self and active then
    table.insert(members, 1, Logic.selfMember(ns.myKey(), ns.Self.lastSent()))
  end
  local hidden
  models, hidden = Logic.rows(members, s, relationOf, ns.Modules.isEnabled("tags"), ns.now(), ns.wallclock(),
    titleOf(), ns.maxLevel(), ctx)
  P.marks = Logic.tabMarks(models)
  if active then
    onlineAll = Logic.guildOnline((ns.Guild.count()), extra, s.showNoAddon)
    for _, m in ipairs(members) do if m.online and ns.isTestName(m.name) then onlineAll = onlineAll + 1 end end
  else
    onlineAll = online
  end
  P.header = Logic.headerCount(here, onlineAll)
  P.headerShort = Logic.headerCount(here, onlineAll, true)
  P.countText:SetText(P.header)
  P.shown = true
  P.showTab(not kept)
  -- tucked and the holder is still out (or sliding in): only slide it in; the content stays as it is until it is in
  if view == "tab" and P.clipOut() then
    P.slideTo(0)
    if P.tipRow then Panel.hideRowTip(P.tipRow) end
    P.stopArrowTicker()
    stopCalPulse()
    P.syncBarTicker()
    return
  end
  local layout = view == "tab" and "full" or view
  local peekMember
  if layout == "peek" then
    -- the news's friend (a calendar note has no row; the after-fight summary shows the row of the one thing to react
    -- to, else none)
    local about = news.kind == "fight" and news.show or news
    local key = (about ~= nil and about.kind ~= "calnote" and about.kind ~= "calreply") and FL.keyOf(about) or nil
    peekMember = type(key) == "string" and ns.roster and ns.roster:get(key) or nil
    local rowSettings = {}
    for k, v in pairs(s) do rowSettings[k] = v end
    rowSettings.showOffline = true
    models = peekMember and Logic.rows({ peekMember }, rowSettings, relationOf, ns.Modules.isEnabled("tags"), ns.now(),
      ns.wallclock(), titleOf(), ns.maxLevel(), ctx) or {}
    for _, m in ipairs(models) do
      if (about.kind == "mock" or about.kind == "congrats") and about.dir == "in" then m.mockBack = true end
    end
  end
  local now = ns.now()
  for _, m in ipairs(models) do
    local at = dingAt[m.key]
    if at and not m.offline and not cheered[m.key] and now - at < CHEER_FOR then m.dinged = true end
  end
  if ns.Trophies then
    for _, m in ipairs(models) do
      local line = ns.Trophies.lineFor(m.key)
      if line then
        m.tip = m.tip or {}
        m.tip[#m.tip + 1] = line
      end
    end
  end
  entries = layout == "peek" and models or Logic.entries(models, { inGroup = grouped, guildOpen = s.showGuildOnline == true,
    offlineOpen = s.showOffline ~= false, hiddenOffline = hidden, flat = not active })
  local G = ns.Guild
  local stateLine = Logic.stateLine({ inGuild = G ~= nil and G.inGuild(), known = G ~= nil and G.known(),
    active = active, needsReload = G ~= nil and G.needsReload(), guildName = G and (G.name() or G.id()),
    reason = G and G.quietReason() })

  local top = P.drawHeader(s, layout, news)
  local live = view ~= "tab" -- on screen now (tucked and closed: laid out behind the holder)
  if layout ~= "peek" and (statsOn() or calOn()) then
    local wide = tab == "shame"
    drawTabs((wide and BOARD_WIDTH or ROW_WIDTH[ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"]) + 2 * PAD)
    if not live then stopCalPulse() end
    top = top + TAB_HEIGHT
  else
    if P.tabBar then P.tabBar:Hide() end
    stopCalPulse()
  end

  if tab == "shame" and layout == "full" and not live then
    -- tucked and closed: nobody sees the board behind the closed holder; it is drawn when the panel slides out
    P.syncBarTicker()
    return
  end
  if tab == "shame" and layout == "full" then
    for _, r in ipairs(rowFrames) do r:Hide() end
    hideChrome()
    if P.tipRow then Panel.hideRowTip(P.tipRow) end
    P.visibleRows = 0
    P.stopArrowTicker()
    local ok, h = ns.Log.safe("board", ns.Board.draw, P.root, top + GAP, BOARD_WIDTH)
    if ok and type(h) == "number" then
      noteText:Hide()
      note = nil
    else
      ns.Log.safe("board", ns.Board.hide)
      noteText:ClearAllPoints()
      noteText:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -(top + GAP))
      noteText:SetWidth(BOARD_WIDTH)
      noteText:SetText(BOARD_UNAVAILABLE)
      noteText:Show()
      note = BOARD_UNAVAILABLE
      h = LINE
    end
    P.root:SetSize(BOARD_WIDTH + 2 * PAD, top + GAP + h + PAD)
    P.root:Show()
    P.syncBarTicker()
    settle(BOARD_WIDTH + 2 * PAD, top + GAP + h + PAD, view)
    normalizeAnchor()
    return
  end
  if ns.Board then ns.Log.safe("board", ns.Board.hide) end

  local max = ns.Config.PANEL_MAX_ROWS
  local first, last = Logic.window(#entries, layout == "peek" and 0 or offset, max)
  if layout ~= "peek" then offset = first - 1 end -- (a peek never moves the player's scroll)
  firstRow = first
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style]
  local alpha = clamp(s.bgAlpha, 0, 1, 0.8)
  local y = top + GAP
  local used = 0
  hideChrome()
  for i = first, last do
    local e = entries[i]
    if e.head then
      local f = headFrames[e.head]
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -y)
      f:SetSize(width, HEAD_HEIGHT)
      f:Show()
      y = y + HEAD_HEIGHT + 4
    elseif e.bar then
      local bar = e.bar == "guild" and guildBar or offBar
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -y)
      bar:SetSize(width, OFF_HEIGHT)
      bar.text:SetText(e.bar == "guild" and Logic.guildBarText(e.count, e.open) or Logic.offlineBarText(e.count, e.open))
      bar.icon:SetTexture(e.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
      bar:Show()
      if e.bar == "guild" then guildBarShown = true else offBarShown = true end
      y = y + OFF_HEIGHT + GAP
    else
      used = used + 1
      local r = rowFrames[used]
      if not r then r = P.createRow(); rowFrames[used] = r end
      local h = P.layoutRow(r, e, style, s, width)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -y)
      T.setBackgroundAlpha(r, alpha)
      r:Show()
      y = y + h + GAP
    end
  end
  for i = used + 1, #rowFrames do
    rowFrames[i]:Hide()
    if P.tipRow == rowFrames[i] then Panel.hideRowTip(P.tipRow) end
  end
  P.visibleRows = used
  P.refreshRowTip()
  if live then P.updateArrowTicker() else P.stopArrowTicker() end

  note = nil
  if layout == "peek" then
    -- no note under a slid-out row; the after-fight summary with no row names what happened
    if news.kind == "fight" and not news.show then note = news.summary end
  elseif stateLine then note = stateLine
  elseif #entries == 0 then note = "Nobody else is in the guild yet."
  elseif #entries == 1 and entries[1].bar == "offline" then note = "Nobody else is online right now."
  elseif #entries > max then note = "Scroll for more (" .. first .. "-" .. last .. " of " .. #entries .. ")" end
  if note then
    noteText:ClearAllPoints()
    noteText:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -(y - GAP + 4))
    noteText:SetWidth(width)
    noteText:SetText(note)
    noteText:Show()
    local real = noteText.GetStringHeight and noteText:GetStringHeight() or nil
    y = y - GAP + 4 + Logic.noteHeight(note, width, LINE, real)
  else
    noteText:Hide()
  end
  if used == 0 and layout == "peek" and not note then y = top + 4 end -- (news with no row: the header line alone)
  P.root:SetSize(width + 2 * PAD, y + 2)
  P.root:Show()
  P.syncBarTicker()
  settle(width + 2 * PAD, y + 2, view)
  normalizeAnchor()
end

local function requestRedraw()
  if pending then return end
  pending = true
  local function run()
    pending = false
    redraw()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() ns.Log.safe(FEATURE, run) end)
  else
    run()
  end
end
P.requestRedraw = requestRedraw

---------------------------------------------------------------------------------------------------------- build
local function build()
  P.root = T.frame("Frame", "TwizCrewPanel", UIParent)
  P.root:SetFrameStrata("MEDIUM")
  P.root:SetMovable(true)
  if P.root.SetDontSavePosition then P.root:SetDontSavePosition(true) end -- the position lives in our saved data
  if P.root.SetClampedToScreen then P.root:SetClampedToScreen(true) end
  P.root:SetSize(ROW_WIDTH.full + 2 * PAD, HEADER_HEIGHT + 2 * PAD)
  T.paint(P.root, C.backdrop, clamp(setting("bgAlpha"), 0, 1, 0.8), C.border, 2)
  draggable(P.root)
  script(P.root, "OnHide", stopDrag)
  if P.root.EnableMouseWheel then P.root:EnableMouseWheel(true) end
  script(P.root, "OnMouseWheel", function(_, delta) Panel.scroll(delta) end)

  P.buildHeader() -- the header bar, the update line and the What's new line (UI/PanelHeader.lua)

  local function makeBar(onClick, tip)
    local bar = CreateFrame("Button", nil, P.root)
    bar:SetSize(ROW_WIDTH.full, OFF_HEIGHT)
    T.paint(bar, C.row, 0.6, C.rowBorder, 1)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(T.icon(14), T.icon(14))
    bar.icon:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.text = T.readable(T.text(bar, T.FONT.small, C.muted))
    bar.text:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
    bar.text:SetJustifyH("LEFT")
    local hl = bar:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(bar)
    T.color(hl, C.white, 0.08)
    draggable(bar)
    script(bar, "OnClick", onClick)
    Widgets.helpTip(bar, tip, FEATURE)
    bar:Hide()
    return bar
  end
  guildBar = makeBar(function() Panel.toggleGuildOnline() end, "barGuild")
  offBar = makeBar(function() Panel.toggleOffline() end, "barOffline")
  local HEAD_TIPS = { ["My party"] = "headParty", Pinned = "headPinned" }
  for _, words in ipairs({ "My party", "Pinned" }) do -- thin headings
    local f = CreateFrame("Frame", nil, P.root)
    f:SetSize(ROW_WIDTH.full, HEAD_HEIGHT)
    f.text = T.readable(T.text(f, T.FONT.small, C.title))
    f.text:SetPoint("LEFT", f, "LEFT", 2, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetText(words)
    draggable(f)
    Widgets.helpTip(f, HEAD_TIPS[words], FEATURE)
    f:Hide()
    headFrames[words] = f
  end

  noteText = T.text(P.root, T.FONT.small, C.muted)
  noteText:SetJustifyH("LEFT")

  if ns.Board then -- tabs and the Calendar button, shown only while the stats or the calendar module is on
    P.tabBar = CreateFrame("Frame", nil, P.root)
    P.tabBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 0, -(HEADER_HEIGHT - 2))
    P.tabBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", 0, -(HEADER_HEIGHT - 2))
    P.tabBar:SetHeight(TAB_HEIGHT)
    draggable(P.tabBar)
    crewTab = ns.Board.textButton(P.tabBar, "Crew", function() Panel.setTab("crew") end, FEATURE, "tabCrew")
    crewTab:SetPoint("LEFT", P.tabBar, "LEFT", PAD - 5, 0)
    shameTab = ns.Board.textButton(P.tabBar, "Hall of Shame", function() Panel.setTab("shame") end, FEATURE,
      "tabShame")
    shameTab:SetPoint("LEFT", crewTab, "RIGHT", 4, 0)
    calTab = ns.Board.textButton(P.tabBar, "Calendar", function() if ns.Calendar then ns.Calendar.toggle() end end,
      FEATURE)
    calTab.words = "Calendar"
    calTab:SetPoint("LEFT", shameTab, "RIGHT", 4, 0)
    calTab.glow = calTab:CreateTexture(nil, "BACKGROUND")
    calTab.glow:SetAllPoints(calTab)
    T.color(calTab.glow, C.title, 1)
    calTab.glow:SetAlpha(0)
    script(calTab, "OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Crew calendar")
      if calFresh() then
        GameTooltip:AddLine("Something new: a note from the crew, or an answer on one of yours.", T.rgb(C.title))
      end
      GameTooltip:AddLine("Who played when, and the best time for the crew to play together (or /tc cal).", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    script(calTab, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- "?": the About window (How to use TwizCrew), after the Calendar button (or the last tab shown)
    helpTab = ns.Board.textButton(P.tabBar, "?", function() if ns.About then ns.About.toggle() end end, FEATURE,
      "about")
    T.textColor(helpTab.label, C.title)
    P.tabBar:Hide()
  end
  P.root:Hide()
  P.buildTab() -- the crew tab and the holder the panel slides out of (UI/PanelTab.lua)
end

---------------------------------------------------------------------------------------------------------- public
-- Mouse wheel: delta 1 = up (earlier rows), -1 = down. The Hall of Shame does not scroll.
function Panel.scroll(delta)
  if Panel.tab() == "shame" then return end
  offset = offset - (tonumber(delta) or 0)
  requestRedraw()
end

-- "crew" | "shame". Opening the Hall of Shame asks the crew for fresh numbers (Stats.request rate-limits itself).
function Panel.setTab(id)
  if id == "shame" then
    if not statsOn() then return end
    tab = "shame"
    ns.Stats.request()
  elseif id == "crew" then
    tab = "crew"
  else
    return
  end
  requestRedraw()
end

function Panel.tab() return (tab == "shame" and statsOn()) and "shame" or "crew" end

-- Opens or closes the offline friends list at the bottom (the "Offline (N)" bar; remembered).
function Panel.toggleOffline()
  set("showOffline", setting("showOffline") == false)
  requestRedraw()
end

-- Opens or closes the Guild online list (the "Guild online (N)" bar; remembered).
function Panel.toggleGuildOnline()
  set("showGuildOnline", setting("showGuildOnline") ~= true)
  requestRedraw()
end

-- Pins: members shown in the main view while they are online. Saved per guild (ns.db.pins[key] = true), written only
-- while the guild's data is in use.
-- Pinned to the main view (false while TwizCrew is not using this guild's data: the pins are another guild's, or
-- nobody's news; the pins themselves are kept).
function Panel.isPinned(key)
  if ns.Guild and not ns.Guild.active() then return false end
  return type(key) == "string" and ns.db ~= nil and type(ns.db.pins) == "table" and ns.db.pins[key] == true
end

function Panel.pin(key)
  if type(key) ~= "string" or not ns.db or not ns.Guild or not ns.Guild.active() or not ns.Guild.get(key) then
    return false
  end
  if type(ns.db.pins) ~= "table" then ns.db.pins = {} end
  ns.db.pins[key] = true
  ns.Bus.fire("PINS_CHANGED", key, true)
  return true
end

function Panel.unpin(key)
  if type(key) ~= "string" or not ns.db or not ns.Guild or not ns.Guild.active() then return false end
  if type(ns.db.pins) ~= "table" or ns.db.pins[key] == nil then return false end
  ns.db.pins[key] = nil
  ns.Bus.fire("PINS_CHANGED", key, false)
  return true
end

function Panel.offlineBarForTest() return offBarShown and offBar or nil end
function Panel.guildBarForTest() return guildBarShown and guildBar or nil end
function Panel.headFrameForTest(words) local f = headFrames[words]; return f and f:IsShown() and f or nil end
function Panel.entriesForTest() return entries end
function Panel.tabButtonsForTest() return { bar = P.tabBar, crew = crewTab, shame = shameTab, cal = calTab, help = helpTab } end
function Panel.calPulseForTest() return calTicker ~= nil end
function Panel.refresh() requestRedraw() end

function Panel.isShown() return P.shown end
function Panel.models() return models end
function Panel.headerText() return P.header end
function Panel.noteForTest() return note end
function Panel.noteTextForTest() return noteText end
function Panel.rowCountForTest() return P.visibleRows end
function Panel.firstRowForTest() return firstRow end
function Panel.redrawCountForTest() return redraws end
function Panel.isMovingForTest() return moving end

-- The crew tab, once per account (db.panelTabSince): it is the default for everyone. An existing user (the older marks
-- are there) gets the tab on the edge nearest to where the panel was, at about its height, "open when my mouse rests
-- on the tab" turned on (saved settings keep their old values, so a new default alone would not reach them), Keep
-- open off, and a one-time note. Their panel's place is kept for when they turn Keep open on.
local TAB_NOTE = "TwizCrew now tucks away into a small tab. Mouse over the tab, or click it, to see everything. "
  .. "Want it always open? Click Keep open at the top of the panel."
local function migrateToTab(existing)
  if not ns.db or ns.db.panelTabSince then return end
  ns.db.panelTabSince = true
  local saved = type(ns.db.modules) == "table" and type(ns.db.modules.panel) == "table" and ns.db.modules.panel.settings
  if type(saved) == "table" then saved.minimized = nil end -- (the old minimize switch is gone)
  if not existing then return end
  local p = setting("position")
  if type(p) == "table" and p.mini == true then -- a grow-up panel saved while minimized kept the bar's y
    local fh = tonumber(ns.db.panelFullHeight)
    local y = fh and Logic.yAfterRestore(p.y, fh, HEADER_HEIGHT) or tonumber(p.y) or 0
    set("position", { point = p.point, x = p.x, y = round(y) })
  end
  if setting("keepOpen") ~= false then set("keepOpen", false) end
  if setting("barHover") ~= true then set("barHover", true) end
  local okW, w = pcall(UIParent.GetWidth, UIParent)
  local okH, h = pcall(UIParent.GetHeight, UIParent)
  local style = ROW_WIDTH[setting("rowStyle")] and setting("rowStyle") or "full"
  local side, y = Logic.tabFromPosition(setting("position"), okW and w or nil, okH and h or nil,
    ROW_WIDTH[style] + 2 * PAD, tonumber(ns.db.panelFullHeight) or 200, P.TAB_HEIGHT, clamp(setting("scale"), 0.5, 2, 1))
  set("tabSide", side)
  set("tabY", round(y))
  ns.db.tabNoteDue = true
end

-- The one-time note: a chat line and a pop-up, never in a fight or inside a dungeon or raid (hover does not open the
-- panel there): it waits until the player is free (the away card's rule, ns.AwayCard.busy).
local function noteBusy()
  if P.inCombat or ns.Util.plain(InCombatLockdown) or inDungeon() then return true end
  return ns.AwayCard ~= nil and type(ns.AwayCard.busy) == "function" and ns.AwayCard.busy() == true
end
local function showTabNote()
  if not ns.db or not ns.db.tabNoteDue or not P.enabled then return end
  if noteBusy() then
    if C_Timer and C_Timer.After then C_Timer.After(5, function() ns.Log.safe(FEATURE, showTabNote) end) end
    return
  end
  ns.db.tabNoteDue = nil
  print("|cffffd100TwizCrew:|r " .. TAB_NOTE)
  if ns.Popups and ns.Popups.notice then
    ns.Popups.notice("Interface\\Icons\\Ability_Warrior_BattleShout", "TwizCrew now tucks away into a small tab",
      "Mouse over the tab, or click it, to see everything.", function() Panel.openTab("note") end, 20)
  end
end
Panel.TAB_NOTE = TAB_NOTE

local function onEnable()
  P.enabled = true
  -- an older install (these marks are set below on every start): the crew tab's first run moves its panel over
  local existing = ns.db ~= nil and (ns.db.panelSince0112 == true or ns.db.fadeOnSince017 == true)
  if ns.Changelog then ns.Changelog.checkFresh() end -- before the marks below: a new install has no "new" line
  if ns.db and ns.db.fadeOnSince017 and not ns.db.panelSince0112 then
    -- v0.1.12, once for copies that saved the old defaults: online friends only (offline behind the bar), my own
    -- row on, a lighter fade
    if ns.Modules.setting(FEATURE, "showOffline") == true then ns.Modules.set(FEATURE, "showOffline", false) end
    if ns.Modules.setting(FEATURE, "showSelf") == false then ns.Modules.set(FEATURE, "showSelf", true) end
    if ns.Modules.setting(FEATURE, "fadeAlpha") == 0.35 then ns.Modules.set(FEATURE, "fadeAlpha", 0.5) end
  end
  if ns.db then ns.db.panelSince0112 = true end
  if ns.db and not ns.db.panelSince0113 then -- v0.1.13: my own row off again ("too much clutter"); once
    ns.db.panelSince0113 = true
    if ns.Modules.setting(FEATURE, "showSelf") == true then ns.Modules.set(FEATURE, "showSelf", false) end
  end
  if ns.db and not ns.db.fadeOnSince017 then -- v0.1.10: fading became the default; once, for everyone
    ns.db.fadeOnSince017 = true
    if ns.Modules.setting(FEATURE, "fadeOut") == false then ns.Modules.set(FEATURE, "fadeOut", true) end
    if ns.Modules.setting(FEATURE, "fadeAlpha") == 0.3 then ns.Modules.set(FEATURE, "fadeAlpha", 0.35) end
  end
  if not P.root then build() end
  migrateToTab(existing)
  if ns.db and ns.db.tabNoteDue and C_Timer and C_Timer.After then
    C_Timer.After(10, function() ns.Log.safe(FEATURE, showTabNote) end)
  end
  P.inCombat = ns.Util.plain(InCombatLockdown) and true or false
  titleCache = nil
  for _, name in ipairs({ "STATS_CHANGED", "SESSION_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED", "CLOWN_CHANGED" }) do
    ns.Bus.on(FEATURE, name, forgetTitles)
  end
  ns.Bus.on(FEATURE, "SETTING_CHANGED", function(id) if id == "stats" then forgetTitles() end end)
  ns.Events.on(FEATURE, "GROUP_ROSTER_UPDATE", requestRedraw)
  for _, name in ipairs(REDRAW_ON) do ns.Bus.on(FEATURE, name, requestRedraw) end
  ns.Bus.on(FEATURE, "MEMBER_LEVELUP", function(name)
    if type(name) ~= "string" then return end
    dingAt[name], cheered[name] = ns.now(), nil
    requestRedraw()
    -- the button goes away by itself after a few minutes
    if C_Timer and C_Timer.After then C_Timer.After(CHEER_FOR + 1, function() ns.Log.safe(FEATURE, requestRedraw) end) end
  end)
  P.bar = FL.newBar({ seconds = clamp(setting("peekSeconds"), 1, 30, 5), short = NOTICE_SHORT, max = NOTICE_QUEUE,
    lengths = P.newsLengths })
  P.open = nil
  ns.Bus.on(FEATURE, "FEED_ADDED", Panel.onFeed)
  P.listenForNews() -- layer changes, running off, calendar notes (UI/PanelTab.lua)
  -- a fight drops the news waiting to slide out (it is still counted as missed)
  ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", function() P.inCombat = true; P.bar:clear(); requestRedraw() end)
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function() P.inCombat = false; requestRedraw(); P.fightEnded() end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", requestRedraw)
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, requestRedraw) end)
  end
  P.applyMode()
  applyLook()
  redraw()
  P.startBarTicker()
end

local function onDisable()
  P.enabled = false
  P.stopBarTicker()
  P.open = nil
  if ticker then ticker:Cancel(); ticker = nil end
  hide()
end

local function tagSetting(id, info)
  return { key = "tag_" .. id, label = 'Show the "' .. ns.Tags.LABEL[id] .. '" tag', kind = "toggle", info = info }
end

ns.Modules.register({
  id = FEATURE, name = "Crew panel", tier = "module",
  info = "The window that lists your crew: who is online, where they are, their level, XP and tags. "
    .. "It tucks away into a small tab on the edge of your screen: rest your mouse on the tab to see it all. "
    .. "Right-click its title (or the tab) for quick options.",
  defaults = {
    scale = 1.0, bgAlpha = 0.8, rowStyle = "full", showZone = true, showStatus = true, showXP = true,
    showQuest = true, shareQuest = true, questRequests = true, questHeadsUp = true,
    xpText = true, xpTooltip = true,
    fadeOut = true, fadeAlpha = 0.5, locked = false, grow = "down", hideInCombat = false, hideInInstance = false,
    hideWhenAlone = false, showOffline = false, showGuildOnline = false, showNoAddon = true, sort = "online",
    showSelf = false, noticeScope = "close",
    keepOpen = false, peek = true, peekSeconds = 5, barHover = true, barInstead = false, tabSide = "left", tabY = 100,
    tag_DEAD = true, tag_LAYER = true, tag_COMBAT = true, tag_DUNGEON = true, tag_TAXI = true, tag_AFK = true,
    position = { point = "LEFT", x = 40, y = 100 },
  },
  settings = {
    { key = "noticeScope", label = "Tell me about", kind = "choice",
      choices = { { "close", "My party and pinned" }, { "guild", "Everyone in the guild" } },
      info = "Who gets a pop-up, a bar notice or a chat line when they come online, go offline, die or level up. "
        .. "My party and pinned: only people in your party or raid and the ones you pinned. Everyone in the guild: "
        .. "every guild member. The Recent list keeps everyone either way, and mocks and congrats aimed at you "
        .. "always show. The Congrats button on a row stays for everyone." },
    { key = "keepOpen", label = "Keep open", kind = "toggle",
      info = "Off (the normal way): the panel tucks away into a small tab on the edge of your screen. Rest your mouse "
        .. "on the tab, or click it, to see everything; news slides out from it for a few seconds. On: the panel stays "
        .. "on screen like before and you can drag it anywhere. The Keep open switch at the top of the panel and "
        .. "/tc mini do the same." },
    { key = "peek", label = "Slide out news", kind = "toggle",
      info = "While the panel is tucked into its tab, news from your crew slides out from the tab for a few seconds "
        .. "with that friend's row, then slides back: someone comes online, dies, levels up, changes layer or runs "
        .. "off, a new calendar note, a congrats or mock for you. News with a Congrats or Mock button stays about 12 "
        .. "seconds. Keep your mouse on it to keep it out. Never during a fight: what came during the fight slides "
        .. "out a few seconds after it." },
    { key = "peekSeconds", label = "How long news stays out", kind = "slider", min = 2, max = 15, step = 1,
      parent = "peek",
      info = "How many seconds plain news stays out from the tab. News with a Congrats or Mock button on it stays "
        .. "about 12 seconds." },
    { key = "barHover", label = "Open when my mouse rests on the tab", kind = "toggle",
      info = "Rest your mouse on the tab for a moment and the whole panel slides out. It slides back about a second "
        .. "after your mouse leaves. Not while you turn the camera, in a fight, or in a dungeon or raid: a click on "
        .. "the tab still opens it then. Off: only a click opens it." },
    { key = "barInstead", label = "Show news on the tab, not as pop-ups", kind = "toggle",
      info = "Pop-ups keep showing unless this is on. Turn it on and, while the panel is tucked into its tab and news "
        .. "slides out, the pop-ups for friends coming online, dying, leveling up, changing layer and running off are "
        .. "not shown, because the tab already tells you. With Keep open on, pop-ups work as always." },
    { key = "scale", label = "Scale", kind = "slider", min = 0.5, max = 2.0, step = 0.05, fmt = Widgets.percent,
      info = "Makes the whole panel bigger or smaller. 100% is the normal size." },
    { key = "bgAlpha", label = "Background opacity", kind = "slider", min = 0, max = 1, step = 0.05,
      fmt = Widgets.percent,
      info = "How solid the dark background is. Lower it to see more of the game behind the panel." },
    { key = "rowStyle", label = "Row style", kind = "choice",
      choices = { { "full", "Full" }, { "compact", "Compact" }, { "tiny", "Tiny" } },
      info = "How much each friend's row shows. Full: zone, status and XP. Compact: name, level and tags. "
        .. "Tiny: just the name and tags (and the XP percent, if level and XP numbers are on)." },
    { key = "showZone", label = "Show zone line", kind = "toggle",
      info = "Shows where each friend is, like \"Elwynn Forest, Goldshire\"." },
    { key = "showStatus", label = "Show typed status", kind = "toggle",
      info = "Shows the short note a friend typed with /tc status, like \"LF Deadmines\"." },
    { key = "showQuest", label = "Show quests", kind = "toggle",
      info = "Shows the quest each friend is on, like \"Kobold Camp Cleanup (3/8)\". Hover a row for all its "
        .. "objectives." },
    { key = "shareQuest", label = "Share my quests", kind = "toggle",
      info = "Tells your crew which quest you're on (the one you made progress on last, or the one you track) and "
        .. "its objectives, and lets them see the names of the other quests in your log, so they can ask you to "
        .. "share one. Turn it off to keep them to yourself." },
    { key = "questRequests", label = "Quest share requests", kind = "toggle",
      info = "Lets friends ask you to share your quest (right-click your row, Ask to share). You get a pop-up; one "
        .. "click on it shares the quest. Sharing only works in a group." },
    { key = "questHeadsUp", label = "Tell me what my group can share", kind = "toggle",
      info = "When someone in your group has quests you can get, one pop-up says how many. Click it to see them and "
        .. "ask. You can always see them yourself: right-click a friend's row, Their quests." },
    { key = "showXP", label = "Show XP bar", kind = "toggle",
      info = "Shows a gold bar with how close each friend is to their next level. It gets brighter as it fills." },
    { key = "xpText", label = "Show level and XP numbers", kind = "toggle",
      info = "Shows each friend's level and how far into it they are, like \"Lv 12 \194\183 63%\". Full rows show it "
        .. "next to the XP bar, Compact rows in the top-right corner, Tiny rows just the percent." },
    { key = "xpTooltip", label = "XP details on hover", kind = "toggle",
      info = "Hover over a friend's row to see the exact XP they need for the next level, their rested XP, "
        .. "and about how long until they level at their pace this session (shown once there is a steady pace)." },
    { key = "fadeOut", label = "Fade when the mouse is not over it", kind = "toggle",
      info = "Makes the panel see-through while your mouse is somewhere else, so it gets in the way less. "
        .. "Important things, like the Mock button and the update line, stay fully visible. Only with Keep open on: "
        .. "a tucked panel only slides out while you look at it." },
    { key = "fadeAlpha", label = "How much to fade", kind = "slider", min = 0.1, max = 1, step = 0.05,
      fmt = Widgets.percent, parent = "fadeOut",
      info = "How visible the panel stays while it is faded. Lower means more see-through." },
    { key = "locked", label = "Lock position", kind = "toggle",
      info = "Stops the panel (with Keep open on) and the crew tab from being dragged by accident. Turn it off to "
        .. "move them again." },
    { key = "grow", label = "Grow direction", kind = "choice", choices = { { "down", "Down" }, { "up", "Up" } },
      info = "Whether the panel gets longer downward or upward when more friends come online. "
        .. "Pick Up if the panel sits near the bottom of your screen. Only with Keep open on." },
    { key = "hideInCombat", label = "Hide during fights", kind = "toggle",
      info = "Hides the panel (and the crew tab) while you are in a fight and brings it back when the fight is over." },
    { key = "hideInInstance", label = "Hide in dungeons and raids", kind = "toggle",
      info = "Hides the panel (and the crew tab) while you are inside a dungeon or raid, and shows it again when you "
        .. "leave." },
    { key = "hideWhenAlone", label = "Hide when no crew is online", kind = "toggle",
      info = "Hides the panel (and the crew tab) while none of your friends are playing, and shows it when one logs "
        .. "in." },
    { key = "showGuildOnline", label = "Show the guild online list", kind = "toggle",
      info = "Opens the list of guild members who are online but not in your party or pinned. Off: only your party "
        .. "and the members you pinned show, and a \"Guild online\" bar opens the rest. Clicking that bar does the "
        .. "same as this switch. With nobody in your party and nobody pinned, the list is open anyway." },
    { key = "showNoAddon", label = "Show guild members without the addon", kind = "toggle",
      info = "Lists guild members who do not have TwizCrew, dimmed, with their name, class, level and zone from the "
        .. "guild list. Turn it off to show only the members who run TwizCrew." },
    { key = "showOffline", label = "Show offline friends", kind = "toggle",
      info = "Opens the list of guild members who are not playing (greyed out, with when they were last seen) at "
        .. "the bottom of the panel. Off: an \"Offline\" bar opens them. Clicking that bar does the same as this "
        .. "switch." },
    { key = "sort", label = "Sort", kind = "choice",
      choices = { { "name", "Name" }, { "level", "Level" }, { "online", "Online first" },
        { "layer", "Same layer first" } },
      info = "The order friends are listed in. Same layer first puts the friends you can actually see "
        .. "in the world at the top." },
    { key = "showSelf", label = "Show myself in the list", kind = "toggle",
      info = "Adds a row for you at the top, so you can see what your friends see about you. Off by default: "
        .. "your own options (status, AFK) are in the right-click menu of any row." },
    { key = "whatsNew", label = "What's new", kind = "button",
      onClick = function() if ns.Changelog then ns.Changelog.open() end end,
      info = "Shows every TwizCrew version and what changed. Also: click the panel's title, or /tc new." },
    { key = "about", label = "How to use TwizCrew", kind = "button",
      onClick = function() if ns.About then ns.About.open() end end,
      info = "A short page about what TwizCrew does and how to use it. Also: the \"?\" next to the panel's tabs, "
        .. "the wrench menu, or /tc about." },
    tagSetting("DEAD", "Shows DEAD on a friend who is dead or a ghost."),
    tagSetting("LAYER", "Shows OTHER LAYER on a friend who is on a different copy of the world, "
      .. "so you cannot see each other."),
    tagSetting("COMBAT", "Shows FIGHTING on a friend who is in a fight."),
    tagSetting("DUNGEON", "Shows DUNGEON on a friend who is inside a dungeon or raid."),
    tagSetting("TAXI", "Shows FLYING on a friend who is riding a flight path."),
    tagSetting("AFK", "Shows AFK on a friend who has marked themselves as away from the keyboard."),
  },
  onEnable = onEnable,
  onDisable = onDisable,
  onSettingChanged = function(key)
    if P.root and key == "scale" then rescaleSavedPosition() end
    if P.root and LOOK_KEYS[key] then applyLook() end
    if key == "keepOpen" then Panel.keepOpenChanged() end
    if (key == "tabSide" or key == "tabY") and P.root and not moving then applyPosition() end
    if key == "peekSeconds" and P.bar then P.bar.seconds = clamp(setting("peekSeconds"), 1, 30, 5) end
    if key == "locked" and P.enabled then requestRedraw() end
  end,
})
