-- The Crew panel: a movable window with one row per friend. Registers the module "panel".
-- Hiding the panel = turning the module off. Redraws are coalesced: many requests in one frame -> one redraw.
-- While the stats module is on, two tabs sit under the header: "Crew" (the rows, with award titles under the
-- winners' names) and "Hall of Shame" (drawn by ns.Board). The tab is not saved.
-- This file: settings, the frame, look and position, the redraw, enable / disable. The rest, loaded right after it:
-- UI/PanelRows.lua (rows, row arrows, row tooltips), UI/PanelHeader.lua (the header bar, the update and What's new
-- lines), UI/PanelMenus.lua (the menus and the status box) and UI/PanelMini.lua (minimize, bar notices, peek).
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
local OFF_HEIGHT = 20    -- the "Offline (N)" bar between online and offline friends
local BOARD_UNAVAILABLE = "Hall of Shame unavailable right now"
local TICK = 30 -- seconds; keeps "last seen 2h ago" fresh
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local LOOK_KEYS = { scale = true, bgAlpha = true, position = true, fadeOut = true, fadeAlpha = true }
local REDRAW_ON = { "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED", "LAYER_RELATION",
  "SETTING_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED", "STATS_CHANGED", "SESSION_CHANGED", "UPDATE_SEEN",
  "MEMBER_REMOVED", "AWAY_CHANGED", "FIND_CHANGED", "TROPHIES_CHANGED", "CLOWN_CHANGED" }
P.ROW_WIDTH, P.HEADER_HEIGHT, P.PAD, P.LINE = ROW_WIDTH, HEADER_HEIGHT, PAD, LINE

-- Shared state (set and read by more than one of the panel's files)
P.root = nil           -- the panel frame (made in build)
P.countText = nil      -- the count in the header ("2 of 3 online"), or the notice while minimized
P.header, P.headerShort = "", nil -- the count's text; the short count ("1/3") when room is tight
P.tabBar = nil         -- the Crew / Hall of Shame tabs (only made when ns.Board exists)
P.visibleRows = 0      -- rows drawn by the last redraw
P.enabled, P.shown, P.inCombat = false, false, false
P.tipRow = nil         -- the row whose tooltip is showing (redraws refresh it)
P.menuAnchor = nil     -- the frame the panel's last menu hangs from (see openMenu)
P.noticeShown = nil    -- the entry the bar shows now (test hook)
P.flashTex = nil       -- a soft glow over the bar that flashes when a notice arrives while minimized
-- Minimize (the header bar alone), the notices on that bar, and the peek. See PanelLogic.view and FeedLogic.newBar.
P.bar = nil            -- the notice queue and the missed counter (FeedLogic.newBar), made when the panel starts
P.hoverOpen = false    -- the mouse is on the minimized bar and "open while my mouse is on the bar" is on
P.peek = nil           -- { name, untilT, held } while a friend's row is dropped open below the bar
P.curView = "full"     -- see settle()

local noteText
local offBar -- the "Offline (N)" bar
local offBarShown, entries = false, {}
local CHEER_FOR = 300 -- seconds the Congrats button stays on a friend's row after they level up
local dingAt, cheered = {}, {} -- name -> when they leveled up; name -> true once we congratulated them
P.cheered = cheered
local crewTab, shameTab
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
local NOTICE_SECONDS, NOTICE_SHORT, NOTICE_QUEUE = 6, 3, 8 -- a notice stays 6 s (3 s when others wait), 8 wait at most
local fullHeight, curHeight = nil, HEADER_HEIGHT -- see settle()

local function setting(key) return ns.Modules.setting(FEATURE, key) end
local function set(key, value) return ns.Modules.set(FEATURE, key, value) end
local function minimized() return setting("minimized") == true end

-- The panel's own menus go through here, so we know which frame the shared menu (the minimap button, the calendar and
-- the meet map use it too) hangs from.
local function openMenu(anchor, items)
  P.menuAnchor = anchor
  return Widgets.menu(anchor, items)
end
local function script(frame, name, fn) Widgets.script(frame, name, fn, FEATURE) end

local function clamp(v, lo, hi, fallback)
  v = tonumber(v)
  if v == nil or v ~= v then return fallback end
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function round(v) return math.floor(v * 10 + 0.5) / 10 end
P.setting, P.set, P.minimized, P.openMenu, P.script, P.clamp = setting, set, minimized, openMenu, script, clamp

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

---------------------------------------------------------------------------------------------------------- position
local function applyPosition()
  if moving then return end -- never re-anchor while the player is dragging it
  local p = setting("position")
  if type(p) ~= "table" or not POINTS[p.point] then p = ns.Modules.get(FEATURE).defaults.position end
  local y = tonumber(p.y) or 0
  -- a panel that grows up and is minimized keeps its bar still while a peek or the mouse opens it taller
  if p.point == "BOTTOMLEFT" and p.mini == true and minimized() then y = Logic.barFixedY(y, curHeight, HEADER_HEIGHT) end
  P.root:ClearAllPoints()
  P.root:SetPoint(p.point, UIParent, p.point, tonumber(p.x) or 0, y)
end

-- Where the panel is now, anchored at the corner that matches the grow direction (top-left for down,
-- bottom-left for up), so the panel grows away from that corner. nil if the game has not placed it yet.
local function currentPosition()
  local left, top, bottom = P.root:GetLeft(), P.root:GetTop(), P.root:GetBottom()
  local s, u, uiTop = P.root:GetEffectiveScale(), UIParent:GetEffectiveScale(), UIParent:GetTop()
  for _, v in ipairs({ left, top, bottom, s, u, uiTop }) do
    if type(v) ~= "number" or v ~= v then return nil end
  end
  if s <= 0 or u <= 0 then return nil end
  if setting("grow") == "up" then
    -- minimized, the saved y is the bar's (the bottom of a bar-sized panel), whatever view is open now
    local y = minimized() and Logic.barSavedY(bottom, curHeight, HEADER_HEIGHT) or bottom
    return { point = "BOTTOMLEFT", x = round(left), y = round(y), mini = minimized() or nil }
  end
  return { point = "TOPLEFT", x = round(left), y = round(top - uiTop * u / s) }
end

local function savePosition()
  local p = currentPosition()
  if p then set("position", p) end
end

-- After a reset or a grow change the saved corner may not match; convert it without moving the panel.
local function normalizeAnchor()
  if moving then return end
  local p = setting("position")
  local want = setting("grow") == "up" and "BOTTOMLEFT" or "TOPLEFT"
  if type(p) ~= "table" or p.point ~= want then savePosition() end
end

local function startDrag()
  if setting("locked") or not P.root.StartMoving then return end
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
  if P.bar and (P.bar:current() or P.peek or P.hoverOpen) then over = true end -- a notice or a peek must be seen
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

-- Only the player changing the scale setting moves the saved corner (a reset brings its own position).
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
  end
end

local function applyLook()
  local newScale = clamp(setting("scale"), 0.5, 2, 1)
  appliedScale = newScale
  P.root:SetScale(newScale)
  local alpha = clamp(setting("bgAlpha"), 0, 1, 0.8)
  T.setBackgroundAlpha(P.root, alpha)
  for _, r in ipairs(rowFrames) do T.setBackgroundAlpha(r, alpha) end
  applyPosition()
  if setting("fadeOut") then
    P.root:SetScript("OnUpdate", fadeTick)
    P.root:SetAlpha(clamp(setting("fadeAlpha"), 0.1, 1, 0.3))
  else
    P.root:SetScript("OnUpdate", nil)
    P.root:SetAlpha(1)
  end
end

---------------------------------------------------------------------------------------------------------- redraw
local function hide()
  if P.root then
    stopDrag() -- a drag cut short by hiding must not leave the panel "moving"
    P.root:Hide()
  end
  if P.tipRow then Panel.hideRowTip(P.tipRow) end
  P.shown = false
  P.syncBarTicker()
  note = nil
  P.stopArrowTicker()
  Widgets.closeMenu()
end

-- After every resize. Remembers the height. A panel that grows up is anchored at its bottom corner, which is the bar's
-- bottom only while minimized. The saved position says which of the two its y means (`mini = true` = the bar's), so
-- whatever happened while the panel was off, the next draw converts it once and nothing drifts. The full panel's last
-- height is kept in ns.db.panelFullHeight (it survives a /reload) for the conversion to the bar.
local function settle(height)
  curHeight = height
  local now = minimized() and "mini" or "full"
  if now == "full" then
    fullHeight = height
    if ns.db then ns.db.panelFullHeight = height end
  end
  if setting("grow") ~= "up" then return end
  local p = setting("position")
  if type(p) ~= "table" or p.point ~= "BOTTOMLEFT" or moving then return end
  local savedMini = p.mini == true
  if savedMini ~= (now == "mini") then
    local y = tonumber(p.y) or 0
    if now == "mini" then
      local fh = fullHeight or (ns.db and tonumber(ns.db.panelFullHeight))
      if fh then y = Logic.yAfterMinimize(y, fh, HEADER_HEIGHT) end
    else
      y = Logic.yAfterRestore(y, height, HEADER_HEIGHT)
    end
    set("position", { point = p.point, x = p.x, y = round(y), mini = (now == "mini") or nil })
  end
  if now == "mini" then applyPosition() end
end

local function redraw()
  redraws = redraws + 1
  if not P.root or not P.enabled then return end
  if not statsOn() then tab = "crew" end
  local s = allSettings()
  local online, total = 0, 0
  if ns.roster then online, total = ns.roster:onlineCount() end
  if not Logic.visible(s, { inCombat = P.inCombat, inInstance = inDungeon(), onlineCount = online }) then
    hide()
    return
  end

  -- minimized: just the bar ("mini"), the bar and one friend's row ("peek"), or all of it while the mouse is on the
  -- bar and that is allowed ("full")
  local peekMember = P.peek and ns.roster and ns.roster:get(P.peek.name) or nil
  local view = Logic.view({ minimized = minimized(), hover = P.hoverOpen and s.barHover == true,
    peek = peekMember ~= nil and P.bar ~= nil, inCombat = P.inCombat })
  P.curView = view
  local members = ns.roster and ns.roster:sorted(s.sort, relationOf) or {}
  if s.showSelf and ns.Self then
    table.insert(members, 1, Logic.selfMember(ns.playerName(), ns.Self.lastSent()))
  end
  local rowSettings = s
  if view == "peek" then
    members = { peekMember }
    rowSettings = {}
    for k, v in pairs(s) do rowSettings[k] = v end
    rowSettings.showOffline = true
  end
  local hidden
  models, hidden = Logic.rows(members, rowSettings, relationOf, ns.Modules.isEnabled("tags"), ns.now(), ns.wallclock(),
    titleOf(), ns.maxLevel())
  local now = ns.now()
  for _, m in ipairs(models) do
    local at = dingAt[m.name]
    if at and not m.offline and not cheered[m.name] and now - at < CHEER_FOR then m.dinged = true end
  end
  if ns.Trophies then
    for _, m in ipairs(models) do
      local line = ns.Trophies.lineFor(m.name)
      if line then
        m.tip = m.tip or {}
        m.tip[#m.tip + 1] = line
      end
    end
  end
  entries = view == "peek" and models or Logic.entries(models, hidden, s.showOffline ~= false)
  P.header = Logic.headerText(online, total)
  P.headerShort = (online or 0) .. "/" .. (total or 0)
  P.countText:SetText(P.header)

  local top = P.drawHeader(s, view)
  if view == "mini" then
    for _, r in ipairs(rowFrames) do r:Hide() end
    if P.tipRow then Panel.hideRowTip(P.tipRow) end
    offBar:Hide(); offBarShown = false
    noteText:Hide(); note = nil
    if ns.Board then ns.Log.safe("board", ns.Board.hide) end
    if P.tabBar then P.tabBar:Hide() end
    P.visibleRows = 0
    P.stopArrowTicker()
    P.root:SetSize(ROW_WIDTH[ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"] + 2 * PAD, HEADER_HEIGHT)
    P.root:Show()
    P.shown = true
    P.syncBarTicker()
    settle(HEADER_HEIGHT)
    normalizeAnchor()
    return
  end
  if view == "peek" then
    if P.tabBar then P.tabBar:Hide() end
  elseif statsOn() then
    crewTab:SetActive(tab == "crew")
    shameTab:SetActive(tab == "shame")
    P.tabBar:Show()
    top = top + TAB_HEIGHT
  elseif P.tabBar then
    P.tabBar:Hide()
  end

  if tab == "shame" and view == "full" then
    for _, r in ipairs(rowFrames) do r:Hide() end
    offBar:Hide(); offBarShown = false
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
    P.shown = true
    P.syncBarTicker()
    settle(top + GAP + h + PAD)
    normalizeAnchor()
    return
  end
  if ns.Board then ns.Log.safe("board", ns.Board.hide) end

  local max = ns.Config.PANEL_MAX_ROWS
  local first, last = Logic.window(#entries, view == "peek" and 0 or offset, max)
  if view ~= "peek" then offset = first - 1 end -- (a peek never moves the player's scroll)
  firstRow = first
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style]
  local alpha = clamp(s.bgAlpha, 0, 1, 0.8)
  local y = top + GAP
  local used = 0
  offBarShown = false
  for i = first, last do
    local e = entries[i]
    if e.bar then
      offBar:ClearAllPoints()
      offBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -y)
      offBar:SetSize(width, OFF_HEIGHT)
      offBar.text:SetText(Logic.offlineBarText(e.count, e.open))
      offBar.icon:SetTexture(e.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
      offBar:Show()
      offBarShown = true
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
  if not offBarShown then offBar:Hide() end
  for i = used + 1, #rowFrames do
    rowFrames[i]:Hide()
    if P.tipRow == rowFrames[i] then Panel.hideRowTip(P.tipRow) end
  end
  P.visibleRows = used
  P.refreshRowTip()
  P.updateArrowTicker()

  note = nil
  if view == "peek" then
    -- no note under a peeked row
  elseif #entries == 0 then note = "No crew yet. Friends show up here when they play with TwizCrew."
  elseif #entries == 1 and entries[1].bar then note = "Nobody else is online right now."
  elseif #entries > max then note = "Scroll for more (" .. first .. "-" .. last .. " of " .. #entries .. ")" end
  if note then
    noteText:ClearAllPoints()
    noteText:SetPoint("TOPLEFT", P.root, "TOPLEFT", PAD, -(y - GAP + 4))
    noteText:SetWidth(width)
    noteText:SetText(note)
    noteText:Show()
    y = y - GAP + 4 + (#entries == 0 and 2 * LINE or LINE)
  else
    noteText:Hide()
  end
  P.root:SetSize(width + 2 * PAD, y + 2)
  P.root:Show()
  P.shown = true
  P.syncBarTicker()
  settle(y + 2)
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

  offBar = CreateFrame("Button", nil, P.root)
  offBar:SetSize(ROW_WIDTH.full, OFF_HEIGHT)
  T.paint(offBar, C.row, 0.6, C.rowBorder, 1)
  offBar.icon = offBar:CreateTexture(nil, "ARTWORK")
  offBar.icon:SetSize(T.icon(14), T.icon(14))
  offBar.icon:SetPoint("LEFT", offBar, "LEFT", 4, 0)
  offBar.text = T.readable(T.text(offBar, T.FONT.small, C.muted))
  offBar.text:SetPoint("LEFT", offBar.icon, "RIGHT", 4, 0)
  offBar.text:SetJustifyH("LEFT")
  local offHl = offBar:CreateTexture(nil, "HIGHLIGHT")
  offHl:SetAllPoints(offBar)
  T.color(offHl, C.white, 0.08)
  draggable(offBar)
  script(offBar, "OnClick", function() Panel.toggleOffline() end)
  offBar:Hide()

  noteText = T.text(P.root, T.FONT.small, C.muted)
  noteText:SetJustifyH("LEFT")

  if ns.Board then -- tabs, shown only while the stats module is on
    P.tabBar = CreateFrame("Frame", nil, P.root)
    P.tabBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 0, -(HEADER_HEIGHT - 2))
    P.tabBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", 0, -(HEADER_HEIGHT - 2))
    P.tabBar:SetHeight(TAB_HEIGHT)
    draggable(P.tabBar)
    crewTab = ns.Board.textButton(P.tabBar, "Crew", function() Panel.setTab("crew") end, FEATURE)
    crewTab:SetPoint("LEFT", P.tabBar, "LEFT", PAD - 5, 0)
    shameTab = ns.Board.textButton(P.tabBar, "Hall of Shame", function() Panel.setTab("shame") end, FEATURE)
    shameTab:SetPoint("LEFT", crewTab, "RIGHT", 4, 0)
    P.tabBar:Hide()
  end
  P.root:Hide()
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

function Panel.offlineBarForTest() return offBarShown and offBar or nil end
function Panel.entriesForTest() return entries end
function Panel.refresh() requestRedraw() end

function Panel.isShown() return P.shown end
function Panel.models() return models end
function Panel.headerText() return P.header end
function Panel.noteForTest() return note end
function Panel.rowCountForTest() return P.visibleRows end
function Panel.firstRowForTest() return firstRow end
function Panel.redrawCountForTest() return redraws end
function Panel.isMovingForTest() return moving end

local function onEnable()
  P.enabled = true
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
  P.inCombat = ns.Util.plain(InCombatLockdown) and true or false
  titleCache = nil
  for _, name in ipairs({ "STATS_CHANGED", "SESSION_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED", "CLOWN_CHANGED" }) do
    ns.Bus.on(FEATURE, name, forgetTitles)
  end
  ns.Bus.on(FEATURE, "SETTING_CHANGED", function(id) if id == "stats" then forgetTitles() end end)
  for _, name in ipairs(REDRAW_ON) do ns.Bus.on(FEATURE, name, requestRedraw) end
  ns.Bus.on(FEATURE, "MEMBER_LEVELUP", function(name)
    if type(name) ~= "string" then return end
    dingAt[name], cheered[name] = ns.now(), nil
    requestRedraw()
    -- the button goes away by itself after a few minutes
    if C_Timer and C_Timer.After then C_Timer.After(CHEER_FOR + 1, function() ns.Log.safe(FEATURE, requestRedraw) end) end
  end)
  P.bar = FL.newBar({ seconds = NOTICE_SECONDS, short = NOTICE_SHORT, max = NOTICE_QUEUE })
  P.peek, P.hoverOpen = nil, false
  ns.Bus.on(FEATURE, "FEED_ADDED", Panel.onFeed)
  ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", function() P.inCombat = true; P.peek = nil; requestRedraw() end)
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function() P.inCombat = false; requestRedraw() end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", requestRedraw)
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, requestRedraw) end)
  end
  applyLook()
  redraw()
  P.startBarTicker()
end

local function onDisable()
  P.enabled = false
  P.stopBarTicker()
  P.peek, P.hoverOpen = nil, false
  if ticker then ticker:Cancel(); ticker = nil end
  hide()
end

local function tagSetting(id, info)
  return { key = "tag_" .. id, label = 'Show the "' .. ns.Tags.LABEL[id] .. '" tag', kind = "toggle", info = info }
end

ns.Modules.register({
  id = FEATURE, name = "Crew panel", tier = "module",
  info = "The window that lists your crew: who is online, where they are, their level, XP and tags. "
    .. "Drag it to move it; right-click its title for quick options.",
  defaults = {
    scale = 1.0, bgAlpha = 0.8, rowStyle = "full", showZone = true, showStatus = true, showXP = true,
    showQuest = true, shareQuest = true, questRequests = true,
    xpText = true, xpTooltip = true,
    fadeOut = true, fadeAlpha = 0.5, locked = false, grow = "down", hideInCombat = false, hideInInstance = false,
    hideWhenAlone = false, showOffline = false, sort = "online", showSelf = false,
    minimized = false, peek = true, peekSeconds = 5, barHover = false, barInstead = false,
    tag_DEAD = true, tag_LAYER = true, tag_COMBAT = true, tag_DUNGEON = true, tag_TAXI = true, tag_AFK = true,
    position = { point = "LEFT", x = 40, y = 100 },
  },
  settings = {
    { key = "minimized", label = "Minimize the panel", kind = "toggle",
      info = "Shrinks the panel to just its title bar, so it takes almost no room on your screen. News from your "
        .. "crew (someone comes online, dies, levels up, congratulates or mocks you) shows on the bar for a few "
        .. "seconds, and a small number counts what you missed. Click the minus button on the bar, its title, or "
        .. "type /tc mini to bring the whole panel back. Resetting settings also brings it back." },
    { key = "peek", label = "Peek at the friend", kind = "toggle",
      info = "While the panel is minimized, when news comes in, the panel drops open under the bar for a few "
        .. "seconds and shows only that friend's row (with the Congrats button after a level-up), then closes "
        .. "again. Keep your mouse on it to keep it open. It never opens during a fight." },
    { key = "peekSeconds", label = "How long to peek", kind = "slider", min = 2, max = 15, step = 1, parent = "peek",
      info = "How many seconds the friend's row stays open under the bar." },
    { key = "barHover", label = "Open while my mouse is on the bar", kind = "toggle",
      info = "While the panel is minimized, holding your mouse on the title bar opens the whole panel, and it "
        .. "shrinks back when the mouse leaves. Off by default so the panel never opens by accident." },
    { key = "barInstead", label = "Show news on the bar, not as pop-ups", kind = "toggle",
      info = "Pop-ups keep showing unless this is on. Turn it on and, while the panel is minimized, the pop-ups for "
        .. "friends coming online, dying and leveling up are not shown, because the bar already tells you. "
        .. "Pop-ups work as always while the panel is not minimized." },
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
    { key = "shareQuest", label = "Share my quest", kind = "toggle",
      info = "Tells your crew which quest you're on (the one you made progress on last, or the one you track) and "
        .. "its objectives. Turn it off to keep it to yourself." },
    { key = "questRequests", label = "Quest share requests", kind = "toggle",
      info = "Lets friends ask you to share your quest (right-click your row, Ask to share). You get a pop-up; one "
        .. "click on it shares the quest. Sharing only works in a group." },
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
        .. "Important things, like the Mock button and the update line, stay fully visible." },
    { key = "fadeAlpha", label = "How much to fade", kind = "slider", min = 0.1, max = 1, step = 0.05,
      fmt = Widgets.percent, parent = "fadeOut",
      info = "How visible the panel stays while it is faded. Lower means more see-through." },
    { key = "locked", label = "Lock position", kind = "toggle",
      info = "Stops the panel from being dragged by accident. Turn it off to move the panel again." },
    { key = "grow", label = "Grow direction", kind = "choice", choices = { { "down", "Down" }, { "up", "Up" } },
      info = "Whether the panel gets longer downward or upward when more friends come online. "
        .. "Pick Up if the panel sits near the bottom of your screen." },
    { key = "hideInCombat", label = "Hide during fights", kind = "toggle",
      info = "Hides the panel while you are in a fight and brings it back when the fight is over." },
    { key = "hideInInstance", label = "Hide in dungeons and raids", kind = "toggle",
      info = "Hides the panel while you are inside a dungeon or raid, and shows it again when you leave." },
    { key = "hideWhenAlone", label = "Hide when no crew is online", kind = "toggle",
      info = "Hides the panel while none of your friends are playing, and shows it when one logs in." },
    { key = "showOffline", label = "Show offline friends", kind = "toggle",
      info = "Opens the list of friends who are not playing (greyed out, with when they were last seen) at the "
        .. "bottom of the panel. Off: only friends who are online show, and an \"Offline\" bar opens the rest. "
        .. "Clicking that bar does the same as this switch." },
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
    if key == "minimized" then Panel.minimizedChanged() end
    if key == "barHover" and P.enabled then
      if not setting("barHover") then P.hoverOpen = false end
      P.startBarTicker()
      requestRedraw()
    end
  end,
})
