-- The Crew panel: a movable window with one row per friend. Registers the module "panel".
-- Hiding the panel = turning the module off. Redraws are coalesced: many requests in one frame -> one redraw.
-- While the stats module is on, two tabs sit under the header: "Crew" (the rows, with award titles under the
-- winners' names) and "Hall of Shame" (drawn by ns.Board). The tab is not saved.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local FEATURE = "panel"
local T, Widgets, Logic = ns.Theme, ns.Widgets, ns.PanelLogic
local C = T.COLOR

local ROW_WIDTH = { full = 230, compact = 200, tiny = 160 }
local ICON_SIZE = { full = 22, compact = 20, tiny = 16 }
local HEADER_HEIGHT, PAD, GAP, LINE = 24, 8, 10, 13
local TAB_HEIGHT, BOARD_WIDTH = 18, 320
local UPDATE_HEIGHT = 15 -- the gold "Update available: vX" line under the header
local BOARD_UNAVAILABLE = "Hall of Shame unavailable right now"
local TICK = 30 -- seconds; keeps "last seen 2h ago" fresh
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local LOOK_KEYS = { scale = true, bgAlpha = true, position = true, fadeOut = true, fadeAlpha = true }
local REDRAW_ON = { "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED", "LAYER_RELATION",
  "SETTING_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED", "STATS_CHANGED", "SESSION_CHANGED", "UPDATE_SEEN",
  "AWAY_CHANGED" }

local root, countText, noteText
local afkButton -- the "zzz" button in the header: go AFK / come back
local titleText, headerShort = nil, nil -- "TwizCrew" in the header; the short count ("1/3") when room is tight
local grip -- the move-arrows handle at the left of the header (dim while the panel is locked)
local versionText, updateBar  -- the version after "TwizCrew"; the gold update line (a button: click = how to update)
local titleVersion, updateLine = "", nil -- what they show now (for tests)
local tabBar, crewTab, shameTab
local tab = "crew"     -- "crew" | "shame" (session only)
local rowFrames = {}   -- pool, created once and reused (at most PANEL_MAX_ROWS)
local models = {}      -- row models of the last redraw
local header = ""
local note             -- the note under the rows (or the board's fallback line) while shown, else nil
local titleCache       -- { view, sid, titles } until stats, the session or the settings change (nil = compute)
local offset = 0       -- scroll: rows skipped at the top
local firstRow, visibleRows = 1, 0
local enabled, shown, inCombat, pending, moving = false, false, false, false, false
local ticker
local redraws = 0
local fadeElapsed = 0

local function setting(key) return ns.Modules.setting(FEATURE, key) end
local function set(key, value) return ns.Modules.set(FEATURE, key, value) end
local function script(frame, name, fn) Widgets.script(frame, name, fn, FEATURE) end

local function clamp(v, lo, hi, fallback)
  v = tonumber(v)
  if v == nil or v ~= v then return fallback end
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function round(v) return math.floor(v * 10 + 0.5) / 10 end

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
  return ns.Board ~= nil and tabBar ~= nil and ns.Modules.isEnabled("stats")
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
-- setting change, a settings reset or a module switch.
local function titleOf()
  if not statsOn() then return nil end
  local view = ns.Modules.setting("stats", "titles")
  if view ~= "session" and view ~= "all" then return nil end
  local session = ns.Session and ns.Session.current()
  local sid = session and session.id
  local c = titleCache
  if not c or c.view ~= view or c.sid ~= sid then
    c = { view = view, sid = sid, titles = computeTitles(view, sid) }
    titleCache = c
  end
  local titles = c.titles
  return function(name) return titles[name] end
end

local function inDungeon()
  if type(IsInInstance) ~= "function" then return false end
  local ok, _, kind = pcall(IsInInstance)
  return ok and (kind == "party" or kind == "raid")
end

---------------------------------------------------------------------------------------------------------- position
local function applyPosition()
  if moving then return end -- never re-anchor while the player is dragging it
  local p = setting("position")
  if type(p) ~= "table" or not POINTS[p.point] then p = ns.Modules.get(FEATURE).defaults.position end
  root:ClearAllPoints()
  root:SetPoint(p.point, UIParent, p.point, tonumber(p.x) or 0, tonumber(p.y) or 0)
end

-- Where the panel is now, anchored at the corner that matches the grow direction (top-left for down,
-- bottom-left for up), so the panel grows away from that corner. nil if the game has not placed it yet.
local function currentPosition()
  local left, top, bottom = root:GetLeft(), root:GetTop(), root:GetBottom()
  local s, u, uiTop = root:GetEffectiveScale(), UIParent:GetEffectiveScale(), UIParent:GetTop()
  for _, v in ipairs({ left, top, bottom, s, u, uiTop }) do
    if type(v) ~= "number" or v ~= v then return nil end
  end
  if s <= 0 or u <= 0 then return nil end
  if setting("grow") == "up" then return { point = "BOTTOMLEFT", x = round(left), y = round(bottom) } end
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
  if setting("locked") or not root.StartMoving then return end
  moving = true
  root:StartMoving()
end

local function stopDrag()
  if not moving then return end
  moving = false
  if root.StopMovingOrSizing then root:StopMovingOrSizing() end
  -- We save the position ourselves; the game's own layout cache must not move the panel at the next login.
  if root.SetUserPlaced then root:SetUserPlaced(false) end
  savePosition()
end

local function draggable(f)
  f:EnableMouse(true)
  if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
  script(f, "OnDragStart", startDrag)
  script(f, "OnDragStop", stopDrag)
end

---------------------------------------------------------------------------------------------------------- look
local function fadeTick(_, elapsed)
  fadeElapsed = fadeElapsed + (tonumber(elapsed) or 0)
  if fadeElapsed < 0.1 then return end
  fadeElapsed = 0
  local over = false
  if root.IsMouseOver then over = root:IsMouseOver()
  elseif type(MouseIsOver) == "function" then over = MouseIsOver(root) end
  root:SetAlpha(over and 1 or clamp(setting("fadeAlpha"), 0.1, 1, 0.3))
end

local function applyLook()
  root:SetScale(clamp(setting("scale"), 0.5, 2, 1))
  local alpha = clamp(setting("bgAlpha"), 0, 1, 0.8)
  T.setBackgroundAlpha(root, alpha)
  for _, r in ipairs(rowFrames) do T.setBackgroundAlpha(r, alpha) end
  applyPosition()
  if setting("fadeOut") then
    script(root, "OnUpdate", fadeTick)
    root:SetAlpha(clamp(setting("fadeAlpha"), 0.1, 1, 0.3))
  else
    root:SetScript("OnUpdate", nil)
    root:SetAlpha(1)
  end
end

---------------------------------------------------------------------------------------------------------- rows
local function createRow()
  local r = T.frame("Frame", nil, root)
  T.paint(r, C.row, clamp(setting("bgAlpha"), 0, 1, 0.8), C.rowBorder, 1)
  -- looks: the whole row in the player's class color with a very light fade (colored in layoutRow)
  r.fill = r:CreateTexture(nil, "BORDER", nil, 1)
  r.fill:SetPoint("TOPLEFT", r, "TOPLEFT", 1, -1)
  r.fill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -1, 1)
  r.gloss = T.gloss(r, nil, 0.06, "BORDER")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.afk = r:CreateTexture(nil, "OVERLAY", nil, 2) -- "zzz" on the portrait while they're away
  r.afk:SetTexture(ns.Tags.ICON.AFK)
  r.afk:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.afk:SetSize(14, 14)
  r.afk:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 4, -4)
  r.afk:Hide()
  -- the Mock button: only on a dead friend's row
  r.mock = T.frame("Button", nil, r)
  r.mock:SetSize(54, 18)
  r.mock:SetFrameLevel((r:GetFrameLevel() or 1) + 5)
  T.paint(r.mock, "8a1c1c", 1, "000000", 1)
  T.gloss(r.mock, nil, 0.25, "ARTWORK")
  r.mock.icon = r.mock:CreateTexture(nil, "OVERLAY")
  r.mock.icon:SetSize(14, 14)
  r.mock.icon:SetPoint("LEFT", r.mock, "LEFT", 3, 0)
  r.mock.icon:SetTexture(ns.Tags.ICON.DEAD)
  r.mock.text = T.readable(T.text(r.mock, T.FONT.small, C.white))
  r.mock.text:SetPoint("LEFT", r.mock.icon, "RIGHT", 2, 0)
  r.mock.text:SetText("Mock")
  local mockHl = r.mock:CreateTexture(nil, "HIGHLIGHT")
  mockHl:SetAllPoints(r.mock)
  T.color(mockHl, C.white, 0.15)
  script(r.mock, "OnClick", function(self) Panel.mock(self:GetParent()) end)
  script(r.mock, "OnEnter", function(self)
    local m = self:GetParent().tcModel
    if not GameTooltip or not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Mock " .. tostring(m.name))
    GameTooltip:AddLine("Sends a random roast the whole crew sees. Add your own with /tc mock add <text>.", 1, 1, 1,
      true)
    GameTooltip:Show()
  end)
  script(r.mock, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r.mock:Hide()
  r.name = T.text(r, T.FONT.normal)
  r.level = T.text(r, T.FONT.small, C.title)
  r.zone = T.text(r, T.FONT.small, C.zone)
  r.status = T.text(r, T.FONT.small, C.status)
  r.title = T.text(r, T.FONT.small, C.muted)
  for _, fs in ipairs({ r.name, r.zone, r.status, r.title }) do
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
  end
  -- readable on the class-colored row: black outline and shadow, the name a size bigger
  T.readable(r.name, 1)
  for _, fs in ipairs({ r.level, r.zone, r.status, r.title }) do T.readable(fs) end
  r.xpText = T.text(r, T.FONT.small, C.zone) -- "Lv 12 · 63%" next to the bar (full style)
  r.xpText:SetJustifyH("RIGHT")
  T.readable(r.xpText)
  r.xpBack = r:CreateTexture(nil, "ARTWORK")
  T.gradient(r.xpBack, "VERTICAL", "080808", C.xpBackTop, 0.9, 0.9)
  r.xpFill = r:CreateTexture(nil, "OVERLAY", nil, 1) -- colored in layoutRow (brighter the fuller it is)
  r.xpGloss = T.gloss(r, r.xpFill, 0.35, "OVERLAY")
  r.xpSpark = r:CreateTexture(nil, "OVERLAY", nil, 6)
  r.xpSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  if r.xpSpark.SetBlendMode then r.xpSpark:SetBlendMode("ADD") end
  r.xpSpark:SetSize(10, 18)
  r.pills = {}
  draggable(r)
  script(r, "OnEnter", function(self) Panel.showRowTip(self) end)
  script(r, "OnLeave", function(self) Panel.hideRowTip(self) end)
  return r
end

-- Width of a font string's text (a guess from its length when the game cannot tell yet).
local function textWidth(fs, text)
  local w = fs.GetStringWidth and fs:GetStringWidth()
  if type(w) ~= "number" or w ~= w or w <= 0 then w = #text * 5 end
  return w
end

local function placeLine(r, fs, text, y, width)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -y)
  fs:SetWidth(width - 16)
  fs:SetText(text)
  fs:Show()
end

local function layoutPills(r, tags)
  for i, id in ipairs(tags) do
    local pill = r.pills[i] or Widgets.tagPill(r)
    r.pills[i] = pill
    pill:SetTag(id)
  end
  for i = #tags + 1, #r.pills do r.pills[i]:Hide() end
  -- In Tags.ORDER from left to right, the last one on the row's top-right corner.
  for i = #tags, 1, -1 do
    local pill = r.pills[i]
    pill:ClearAllPoints()
    if i == #tags then pill:SetPoint("RIGHT", r, "TOPRIGHT", 4, 0)
    else pill:SetPoint("RIGHT", r.pills[i + 1], "LEFT", -3, 0) end
    pill:Show()
  end
end

-- Draws one row model; returns the row's height.
local function layoutRow(r, m, style, s, width)
  r:SetWidth(width)
  local icon = ICON_SIZE[style]
  r.icon:ClearAllPoints()
  r.icon:SetSize(icon, icon)
  r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -5)
  -- the "zzz" badge stays in proportion: about 60% of the portrait, tucked on its bottom-right corner
  local badge = math.floor(icon * 0.6 + 0.5)
  r.afk:SetSize(badge, badge)
  r.afk:ClearAllPoints()
  r.afk:SetPoint("CENTER", r.icon, "BOTTOMRIGHT", -math.floor(badge / 6), math.floor(badge / 6))
  ns.ClassIcon.apply(r.icon, m.class)
  -- class color, a bit darker so white text stays readable; the top is slightly lighter than the bottom
  local cr, cg, cb = T.classColor(m.class)
  local function hex(k)
    return string.format("%02x%02x%02x", math.floor(cr * k * 255 + 0.5), math.floor(cg * k * 255 + 0.5),
      math.floor(cb * k * 255 + 0.5))
  end
  T.gradient(r.fill, "VERTICAL", hex(0.50), hex(0.62), 1, 1)
  local bgAlpha = clamp(setting("bgAlpha"), 0, 1, 0.8)
  r.fill:SetAlpha(bgAlpha); r.gloss:SetAlpha(bgAlpha)

  r.tcModel = m
  -- Top-right corner: the level and XP text in compact and tiny (when on), else the level number in full and
  -- compact. In full the text sits next to the XP bar instead, so the corner number would say the same twice.
  local corner
  if style ~= "full" and m.xpText then corner = m.xpText
  elseif style ~= "tiny" and m.level and not (style == "full" and m.xpText) then corner = tostring(m.level) end
  r.tcCorner = corner
  local roomRight = style == "tiny" and 8 or 34
  if corner then
    r.level:ClearAllPoints()
    r.level:SetPoint("RIGHT", r, "TOPRIGHT", -8, -(5 + icon / 2))
    r.level:SetText(corner)
    r.level:Show()
    roomRight = math.max(roomRight, textWidth(r.level, corner) + 14)
  else
    r.level:Hide()
  end
  r.name:ClearAllPoints()
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.name:SetWidth(math.max(20, width - 6 - icon - 5 - roomRight))
  r.name:SetText(m.name)
  r.name:SetTextColor(1, 1, 1) -- the row itself carries the class color now

  local y = 5 + icon + 2
  if m.title then -- award title: a small muted line under the name, in every row style
    local left = 6 + icon + 5
    r.title:ClearAllPoints()
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", left, -(y - 2))
    r.title:SetWidth(width - left - 8)
    r.title:SetText(m.title)
    r.title:Show()
    y = y + LINE
  else
    r.title:Hide()
  end
  r.zone:Hide(); r.status:Hide(); r.xpBack:Hide(); r.xpFill:Hide(); r.xpText:Hide()
  r.xpGloss:Hide(); r.xpSpark:Hide()
  r.tcBarText = nil
  if style == "full" then
    local line = m.offline and m.offlineText or (s.showZone and m.zoneText ~= "" and m.zoneText)
    if line then placeLine(r, r.zone, line, y, width); y = y + LINE end
    if not m.offline and s.showStatus and m.status ~= "" then
      placeLine(r, r.status, '"' .. m.status .. '"', y, width)
      y = y + LINE
    end
    -- XP line: the bar (none at max level) with "Lv 12 · 63%" on its right, or the text alone.
    local bar = not m.offline and s.showXP and m.xp and not m.atMax
    local label = not m.offline and m.xpText
    local barWidth = width - 16
    if label then
      r.tcBarText = label
      r.xpText:ClearAllPoints()
      r.xpText:SetText(label)
      if bar then
        local w = textWidth(r.xpText, label)
        barWidth = math.max(40, barWidth - w - 6)
        r.xpText:SetPoint("RIGHT", r, "TOPRIGHT", -8, -(y + 5))
      else
        r.xpText:SetPoint("LEFT", r, "TOPLEFT", 8, -(y + 5))
      end
      r.xpText:Show()
    end
    if bar then
      r.xpBack:ClearAllPoints()
      r.xpBack:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -(y + 2))
      r.xpBack:SetSize(barWidth, 6)
      r.xpBack:Show()
      local xp = clamp(m.xp, 0, 100, 0)
      if xp > 0 then
        r.xpFill:ClearAllPoints()
        r.xpFill:SetPoint("TOPLEFT", r.xpBack, "TOPLEFT", 0, 0)
        r.xpFill:SetSize(math.max(1, barWidth * xp / 100), 6)
        T.gradient(r.xpFill, "HORIZONTAL", C.xpDark, T.mix(C.xpLow, C.xpHigh, xp / 100), 1, 1)
        r.xpFill:Show()
        r.xpGloss:Show()
        if xp < 100 then
          r.xpSpark:ClearAllPoints()
          r.xpSpark:SetPoint("CENTER", r.xpFill, "RIGHT", 0, 0)
          r.xpSpark:Show()
        end
      end
    end
    if label then y = y + LINE elseif bar then y = y + 10 end
  end
  local height = y + 4
  r:SetHeight(height)
  local away = false
  for _, id in ipairs(m.tags or {}) do if id == "AFK" then away = true end end
  if away and not m.offline then r.afk:Show() else r.afk:Hide() end
  local dead = false
  for _, id in ipairs(m.tags or {}) do if id == "DEAD" then dead = true end end
  if dead and not m.offline and ns.Roasts and ns.Roasts.canMock(m.name) then
    r.mock:ClearAllPoints()
    r.mock:SetPoint("RIGHT", r, "RIGHT", -6, style == "full" and 0 or -2)
    r.mock:Show()
  else
    r.mock:Hide()
  end
  r:SetAlpha(m.offline and 0.4 or (away and 0.75 or 1))
  layoutPills(r, m.tags)
  return height
end

---------------------------------------------------------------------------------------------------------- row tooltip
local tipRow -- the row whose tooltip is showing (redraws refresh it)

-- Name in class colour, then the row model's tip lines (level, XP to level, rested, time to level).
function Panel.showRowTip(r)
  local m = r and r.tcModel
  if not GameTooltip or type(m) ~= "table" or type(m.tip) ~= "table" then return end
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  GameTooltip:SetText(m.name, T.classColor(m.class))
  local cr, cg, cb = T.rgb(C.text)
  for _, line in ipairs(m.tip) do GameTooltip:AddLine(line, cr, cg, cb) end
  GameTooltip:Show()
  tipRow = r
end

function Panel.hideRowTip(r)
  if tipRow ~= r then return end
  tipRow = nil
  if GameTooltip then GameTooltip:Hide() end
end

-- After a redraw: the row under the mouse may show someone else now, or new numbers.
local function refreshRowTip()
  local r = tipRow
  if not r then return end
  if GameTooltip and GameTooltip.IsOwned and not GameTooltip:IsOwned(r) then tipRow = nil; return end
  local m = r.tcModel -- hidden rows already closed their tooltip (redraw)
  if type(m) ~= "table" or type(m.tip) ~= "table" then Panel.hideRowTip(r); return end
  Panel.showRowTip(r)
end

---------------------------------------------------------------------------------------------------------- update
-- "Update available: vX" or nil, worked out inside Update reminders' own guard: an error there means "no line",
-- never a broken panel.
local function updateText()
  if not ns.Updates or not ns.Updates.available then return nil end
  local ok, text = ns.Log.safe("updates", function()
    return ns.UpdateLogic.availableText(ns.Updates.available())
  end)
  if ok and type(text) == "string" then return ns.Util.safeText(text) end
  return nil
end

-- Title version and the update line; returns how far down the content starts.
local function drawAfkButton()
  if not afkButton then return end
  local away = ns.Away and ns.Away.isAway()
  if afkButton.icon.SetDesaturated then afkButton.icon:SetDesaturated(not away) end
  afkButton.icon:SetAlpha(away and 1 or 0.55)
  if away then afkButton.glow:Show() else afkButton.glow:Hide() end
end

local function drawHeader(s)
  drawAfkButton()
  if grip then grip:SetAlpha(setting("locked") and 0.3 or 0.9) end
  titleVersion = Logic.titleVersion(s.rowStyle, ns.VERSION)
  versionText:SetText(titleVersion)
  -- Narrow rows (compact, tiny): make the header fit so the AFK button never sits on the title. First the version
  -- goes, then "2 of 3 online" becomes "2/3".
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style] + 2 * PAD
  local right = (PAD - 2) + 16 + 6 + 6 + 16 + 6 -- gear, gaps, AFK button, gap before the title side
  local left = (PAD - 2) + 16 + 4 + textWidth(titleText, "TwizCrew")
  local function fits(count, withVersion)
    local used = left + right + textWidth(countText, count)
    if withVersion and titleVersion ~= "" then used = used + 4 + textWidth(versionText, titleVersion) end
    return used <= width
  end
  local count = header
  if fits(header, true) then
    versionText:Show()
  else
    versionText:Hide()
    if not fits(header, false) and headerShort then count = headerShort end
  end
  countText:SetText(count)
  updateLine = updateText()
  local top = HEADER_HEIGHT
  if updateLine then
    updateBar.text:SetText(updateLine)
    updateBar:Show()
    top = top + UPDATE_HEIGHT
  else
    updateBar:Hide()
  end
  if tabBar then
    tabBar:ClearAllPoints()
    tabBar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(top - 2))
    tabBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(top - 2))
  end
  return top
end

---------------------------------------------------------------------------------------------------------- redraw
local function hide()
  if root then
    stopDrag() -- a drag cut short by hiding must not leave the panel "moving"
    root:Hide()
  end
  if tipRow then Panel.hideRowTip(tipRow) end
  shown = false
  note = nil
  Widgets.closeMenu()
end

local function redraw()
  redraws = redraws + 1
  if not root or not enabled then return end
  if not statsOn() then tab = "crew" end
  local s = allSettings()
  local online, total = 0, 0
  if ns.roster then online, total = ns.roster:onlineCount() end
  if not Logic.visible(s, { inCombat = inCombat, inInstance = inDungeon(), onlineCount = online }) then
    hide()
    return
  end

  local members = ns.roster and ns.roster:sorted(s.sort, relationOf) or {}
  if s.showSelf and ns.Self then
    table.insert(members, 1, Logic.selfMember(ns.playerName(), ns.Self.lastSent()))
  end
  models = Logic.rows(members, s, relationOf, ns.Modules.isEnabled("tags"), ns.now(), ns.wallclock(), titleOf(),
    ns.maxLevel())
  header = Logic.headerText(online, total)
  headerShort = (online or 0) .. "/" .. (total or 0)
  countText:SetText(header)

  local top = drawHeader(s)
  if statsOn() then
    crewTab:SetActive(tab == "crew")
    shameTab:SetActive(tab == "shame")
    tabBar:Show()
    top = top + TAB_HEIGHT
  elseif tabBar then
    tabBar:Hide()
  end

  if tab == "shame" then
    for _, r in ipairs(rowFrames) do r:Hide() end
    if tipRow then Panel.hideRowTip(tipRow) end
    visibleRows = 0
    local ok, h = ns.Log.safe("board", ns.Board.draw, root, top + GAP, BOARD_WIDTH)
    if ok and type(h) == "number" then
      noteText:Hide()
      note = nil
    else
      ns.Log.safe("board", ns.Board.hide)
      noteText:ClearAllPoints()
      noteText:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -(top + GAP))
      noteText:SetWidth(BOARD_WIDTH)
      noteText:SetText(BOARD_UNAVAILABLE)
      noteText:Show()
      note = BOARD_UNAVAILABLE
      h = LINE
    end
    root:SetSize(BOARD_WIDTH + 2 * PAD, top + GAP + h + PAD)
    root:Show()
    shown = true
    normalizeAnchor()
    return
  end
  if ns.Board then ns.Log.safe("board", ns.Board.hide) end

  local max = ns.Config.PANEL_MAX_ROWS
  local first, last = Logic.window(#models, offset, max)
  offset, firstRow = first - 1, first
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style]
  local alpha = clamp(s.bgAlpha, 0, 1, 0.8)
  local y = top + GAP
  local used = 0
  for i = first, last do
    used = used + 1
    local r = rowFrames[used]
    if not r then r = createRow(); rowFrames[used] = r end
    local h = layoutRow(r, models[i], style, s, width)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -y)
    T.setBackgroundAlpha(r, alpha)
    r:Show()
    y = y + h + GAP
  end
  for i = used + 1, #rowFrames do
    rowFrames[i]:Hide()
    if tipRow == rowFrames[i] then Panel.hideRowTip(tipRow) end
  end
  visibleRows = used
  refreshRowTip()

  note = nil
  if #models == 0 then note = "No crew yet. Friends show up here when they play with TwizCrew."
  elseif #models > max then note = "Scroll for more (" .. first .. "-" .. last .. " of " .. #models .. ")" end
  if note then
    noteText:ClearAllPoints()
    noteText:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -(y - GAP + 4))
    noteText:SetWidth(width)
    noteText:SetText(note)
    noteText:Show()
    y = y - GAP + 4 + (#models == 0 and 2 * LINE or LINE)
  else
    noteText:Hide()
  end
  root:SetSize(width + 2 * PAD, y + 2)
  root:Show()
  shown = true
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

---------------------------------------------------------------------------------------------------------- menu
local function choiceLabel(key, value)
  for _, def in ipairs(ns.Modules.get(FEATURE).settings) do
    if def.key == key then
      for _, c in ipairs(def.choices or {}) do if c[1] == value then return c[2] end end
    end
  end
  return tostring(value)
end

local NEXT_STYLE = { full = "compact", compact = "tiny", tiny = "full" }

local function flip(key)
  return function() set(key, not setting(key)) end
end

local function isOn(key)
  return function() return setting(key) and true or false end
end

function Panel.menuItems()
  return {
    { label = "Show offline friends", checked = isOn("showOffline"), onClick = flip("showOffline") },
    { label = "Lock position", checked = isOn("locked"), onClick = flip("locked") },
    { label = "Row style: " .. choiceLabel("rowStyle", setting("rowStyle")),
      onClick = function() set("rowStyle", NEXT_STYLE[setting("rowStyle")] or "full") end },
    { label = "Hide during fights", checked = isOn("hideInCombat"), onClick = flip("hideInCombat") },
    { label = "Set my status", onClick = function() Panel.openStatusBox() end },
    { label = (ns.Away and ns.Away.isAway()) and "I'm back" or "Go AFK", onClick = function() Panel.toggleAway() end },
    { label = "Open settings", onClick = function()
      if ns.Settings and ns.Settings.open then ns.Settings.open() end
    end },
    { label = "Hide panel", onClick = function()
      ns.Modules.setEnabled(FEATURE, false)
      print("TwizCrew: panel hidden. Type /tc show to bring it back.")
    end },
  }
end

---------------------------------------------------------------------------------------------------- status box
-- A small box of our own (not a StaticPopup) to type the status: Enter saves, Escape cancels, empty clears.
local statusBox

local function closeStatusBox()
  if not statusBox then return end
  statusBox.edit:ClearFocus()
  statusBox:Hide()
end

local function saveStatus()
  if not statusBox or not statusBox.open then return end -- one save per opening
  statusBox.open = false
  local text = statusBox.edit:GetText()
  ns.Self.setStatus(type(text) == "string" and text or "")
  local now = ns.db and ns.db.myStatus or ""
  if now == "" then print("TwizCrew: status cleared")
  else print('TwizCrew: status set to "' .. ns.Util.safeText(now) .. '"') end
  closeStatusBox()
end

local function buildStatusBox()
  local f = T.frame("Frame", "TwizCrewStatus", UIParent)
  f:SetSize(280, 76)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:EnableMouse(true)
  T.paint(f, C.backdrop, 0.95, C.border, 2)
  local title = T.text(f, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText("Set my status")
  local e = T.frame("EditBox", nil, f)
  e:SetSize(256, 22)
  e:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
  T.paint(e, C.row, 1, C.buttonBorder, 1)
  e:SetAutoFocus(false)
  if e.SetFontObject then e:SetFontObject(T.FONT.small) end
  if e.SetTextInsets then e:SetTextInsets(5, 5, 0, 0) end
  if e.SetMaxLetters then e:SetMaxLetters(ns.Config.STATUS_MAX) end
  local hint = T.text(f, T.FONT.small, C.muted)
  hint:SetPoint("TOPLEFT", e, "BOTTOMLEFT", 0, -4)
  hint:SetText("Enter saves, Escape cancels. Leave it empty to clear it.")
  script(e, "OnEnterPressed", saveStatus)
  script(e, "OnEscapePressed", closeStatusBox)
  script(f, "OnHide", function() f.open = false end)
  f.edit = e
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewStatus") end -- Escape closes it
  return f
end

function Panel.mock(r)
  local m = r and r.tcModel
  if not m or not ns.Roasts then return end
  if not ns.Roasts.mock(m.name) then print("TwizCrew: give it a few seconds before mocking " .. m.name .. " again.") end
end

function Panel.toggleAway()
  if not ns.Away then return end
  local before = ns.Away.isAway()
  local away = ns.Away.toggle()
  if before and away then
    print("TwizCrew: the game itself still has you AFK. Move or type /afk to clear it.")
  else
    print("TwizCrew: " .. (away and "your crew sees you as AFK." or "welcome back!"))
  end
  drawAfkButton()
end

function Panel.openStatusBox()
  if not statusBox then statusBox = buildStatusBox() end
  statusBox.edit:SetText(tostring(ns.db and ns.db.myStatus or ""))
  statusBox.open = true
  statusBox:Show()
  statusBox.edit:SetFocus()
  if statusBox.edit.HighlightText then statusBox.edit:HighlightText() end
end

---------------------------------------------------------------------------------------------------------- build
local function build()
  root = T.frame("Frame", "TwizCrewPanel", UIParent)
  root:SetFrameStrata("MEDIUM")
  root:SetMovable(true)
  if root.SetDontSavePosition then root:SetDontSavePosition(true) end -- the position lives in our saved data
  if root.SetClampedToScreen then root:SetClampedToScreen(true) end
  root:SetSize(ROW_WIDTH.full + 2 * PAD, HEADER_HEIGHT + 2 * PAD)
  T.paint(root, C.backdrop, clamp(setting("bgAlpha"), 0, 1, 0.8), C.border, 2)
  draggable(root)
  script(root, "OnHide", stopDrag)
  if root.EnableMouseWheel then root:EnableMouseWheel(true) end
  script(root, "OnMouseWheel", function(_, delta) Panel.scroll(delta) end)

  local head = CreateFrame("Frame", nil, root)
  head:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  head:SetHeight(HEADER_HEIGHT)
  draggable(head)
  script(head, "OnMouseUp", function(self, button)
    if button == "RightButton" then Widgets.menu(self, Panel.menuItems()) end
  end)
  -- a move handle so it's obvious the panel can be dragged; hovering the header shows the move cursor and a tip
  grip = head:CreateTexture(nil, "ARTWORK")
  grip:SetTexture("Interface\\CURSOR\\UI-Cursor-Move")
  grip:SetSize(16, 16)
  grip:SetPoint("LEFT", head, "LEFT", PAD - 2, -2)
  script(head, "OnEnter", function(self)
    local locked = setting("locked")
    if not locked and type(SetCursor) == "function" then pcall(SetCursor, "Interface\\CURSOR\\UI-Cursor-Move") end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("TwizCrew")
    GameTooltip:AddLine(locked and "Locked in place (unlock it with the right-click menu)" or "Drag to move", 1, 1, 1)
    GameTooltip:AddLine("Right-click for options", 1, 1, 1)
    GameTooltip:Show()
  end)
  script(head, "OnLeave", function()
    if type(ResetCursor) == "function" then pcall(ResetCursor) end
    if GameTooltip then GameTooltip:Hide() end
  end)
  local title = T.text(head, T.FONT.normal, C.title)
  titleText = title
  title:SetPoint("LEFT", grip, "RIGHT", 4, 0)
  title:SetText("TwizCrew")
  versionText = T.text(head, T.FONT.small, C.muted)
  versionText:SetPoint("LEFT", title, "RIGHT", 4, 0)
  local gear = CreateFrame("Button", nil, head)
  gear:SetSize(16, 16)
  gear:SetPoint("RIGHT", head, "RIGHT", -PAD + 2, -2)
  local gearIcon = gear:CreateTexture(nil, "ARTWORK")
  gearIcon:SetAllPoints(gear)
  gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  local gearHl = gear:CreateTexture(nil, "HIGHLIGHT")
  gearHl:SetAllPoints(gear)
  gearHl:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  if gearHl.SetBlendMode then gearHl:SetBlendMode("ADD") end
  script(gear, "OnClick", function() if ns.Settings then ns.Settings.toggle() end end)
  script(gear, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Settings")
    GameTooltip:AddLine("Click to open the TwizCrew settings (or type /tc)", 1, 1, 1)
    GameTooltip:Show()
  end)
  script(gear, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  countText = T.text(head, T.FONT.small, C.muted)
  countText:SetPoint("RIGHT", gear, "LEFT", -6, 0)
  afkButton = CreateFrame("Button", nil, head)
  afkButton:SetSize(16, 16)
  afkButton:SetPoint("RIGHT", countText, "LEFT", -6, 0)
  afkButton.glow = afkButton:CreateTexture(nil, "BACKGROUND")
  afkButton.glow:SetPoint("TOPLEFT", afkButton, "TOPLEFT", -3, 3)
  afkButton.glow:SetPoint("BOTTOMRIGHT", afkButton, "BOTTOMRIGHT", 3, -3)
  T.color(afkButton.glow, C.title, 0.35)
  afkButton.icon = afkButton:CreateTexture(nil, "ARTWORK")
  afkButton.icon:SetAllPoints(afkButton)
  afkButton.icon:SetTexture(ns.Tags.ICON.AFK)
  afkButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local afkHl = afkButton:CreateTexture(nil, "HIGHLIGHT")
  afkHl:SetAllPoints(afkButton)
  T.color(afkHl, C.white, 0.2)
  script(afkButton, "OnClick", function() Panel.toggleAway() end)
  script(afkButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local away = ns.Away and ns.Away.isAway()
    GameTooltip:SetText(away and "I'm back" or "Go AFK")
    GameTooltip:AddLine(away and "Click to show your crew you're back." or
      "Click to tell your crew you're away (only TwizCrew friends see it). Moving or casting brings you back.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(afkButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  drawAfkButton()

  updateBar = CreateFrame("Button", nil, root)
  updateBar:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -(HEADER_HEIGHT - 2))
  updateBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, -(HEADER_HEIGHT - 2))
  updateBar:SetHeight(UPDATE_HEIGHT)
  local glow = updateBar:CreateTexture(nil, "BACKGROUND")
  glow:SetAllPoints(updateBar)
  T.color(glow, C.title, 0.12)
  local hl = updateBar:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(updateBar)
  T.color(hl, C.title, 0.12)
  updateBar.text = T.text(updateBar, T.FONT.small, C.title)
  updateBar.text:SetPoint("LEFT", updateBar, "LEFT", PAD - 2, 0)
  updateBar.text:SetPoint("RIGHT", updateBar, "RIGHT", -(PAD - 2), 0)
  updateBar.text:SetJustifyH("LEFT")
  script(updateBar, "OnClick", function() ns.Log.safe("updates", ns.Updates.showHowTo) end)
  script(updateBar, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Click for how to update", T.rgb(C.title))
    GameTooltip:Show()
  end)
  script(updateBar, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  updateBar:Hide()
  noteText = T.text(root, T.FONT.small, C.muted)
  noteText:SetJustifyH("LEFT")

  if ns.Board then -- tabs, shown only while the stats module is on
    tabBar = CreateFrame("Frame", nil, root)
    tabBar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(HEADER_HEIGHT - 2))
    tabBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(HEADER_HEIGHT - 2))
    tabBar:SetHeight(TAB_HEIGHT)
    draggable(tabBar)
    crewTab = ns.Board.textButton(tabBar, "Crew", function() Panel.setTab("crew") end, FEATURE)
    crewTab:SetPoint("LEFT", tabBar, "LEFT", PAD - 5, 0)
    shameTab = ns.Board.textButton(tabBar, "Hall of Shame", function() Panel.setTab("shame") end, FEATURE)
    shameTab:SetPoint("LEFT", crewTab, "RIGHT", 4, 0)
    tabBar:Hide()
  end
  root:Hide()
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
function Panel.refresh() requestRedraw() end

function Panel.isShown() return shown end
function Panel.models() return models end
function Panel.headerText() return header end
function Panel.noteForTest() return note end
function Panel.rowCountForTest() return visibleRows end
function Panel.firstRowForTest() return firstRow end
function Panel.redrawCountForTest() return redraws end
function Panel.isMovingForTest() return moving end
function Panel.titleVersionForTest() return titleVersion end
function Panel.updateLineForTest() return updateLine end
function Panel.updateLineButtonForTest() return updateBar end
function Panel.rowFrameForTest(i) return rowFrames[i] end
-- What row i shows as level / XP text: { corner = top-right text, bar = text next to the XP bar } (nil = hidden).
function Panel.rowTextsForTest(i)
  local r = rowFrames[i]
  if not r then return nil end
  return { corner = rawget(r, "tcCorner"), bar = rawget(r, "tcBarText") }
end

local function onEnable()
  enabled = true
  if not root then build() end
  local ok, fighting = false, false
  if type(UnitAffectingCombat) == "function" then ok, fighting = pcall(UnitAffectingCombat, "player") end
  inCombat = ok and fighting and true or false
  titleCache = nil
  for _, name in ipairs({ "STATS_CHANGED", "SESSION_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED" }) do
    ns.Bus.on(FEATURE, name, forgetTitles)
  end
  ns.Bus.on(FEATURE, "SETTING_CHANGED", function(id) if id == "stats" then forgetTitles() end end)
  for _, name in ipairs(REDRAW_ON) do ns.Bus.on(FEATURE, name, requestRedraw) end
  ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", function() inCombat = true; requestRedraw() end)
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function() inCombat = false; requestRedraw() end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", requestRedraw)
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, requestRedraw) end)
  end
  applyLook()
  redraw()
end

local function onDisable()
  enabled = false
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
    xpText = true, xpTooltip = true,
    fadeOut = false, fadeAlpha = 0.3, locked = false, grow = "down", hideInCombat = false, hideInInstance = false,
    hideWhenAlone = false, showOffline = true, sort = "online", showSelf = false,
    tag_DEAD = true, tag_LAYER = true, tag_COMBAT = true, tag_DUNGEON = true, tag_TAXI = true, tag_AFK = true,
    position = { point = "LEFT", x = 40, y = 100 },
  },
  settings = {
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
    { key = "showXP", label = "Show XP bar", kind = "toggle",
      info = "Shows a gold bar with how close each friend is to their next level. It gets brighter as it fills." },
    { key = "xpText", label = "Show level and XP numbers", kind = "toggle",
      info = "Shows each friend's level and how far into it they are, like \"Lv 12 \194\183 63%\". Full rows show it "
        .. "next to the XP bar, Compact rows in the top-right corner, Tiny rows just the percent." },
    { key = "xpTooltip", label = "XP details on hover", kind = "toggle",
      info = "Hover over a friend's row to see the exact XP they need for the next level, their rested XP, "
        .. "and about how long until they level at their pace this session (shown once there is a steady pace)." },
    { key = "fadeOut", label = "Fade when the mouse is not over it", kind = "toggle",
      info = "Makes the panel see-through while your mouse is somewhere else, so it gets in the way less." },
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
      info = "Also lists friends who are not playing, greyed out, with when they were last seen." },
    { key = "sort", label = "Sort", kind = "choice",
      choices = { { "name", "Name" }, { "level", "Level" }, { "online", "Online first" },
        { "layer", "Same layer first" } },
      info = "The order friends are listed in. Same layer first puts the friends you can actually see "
        .. "in the world at the top." },
    { key = "showSelf", label = "Show myself in the list", kind = "toggle",
      info = "Adds a row for you at the top, so you can see what your friends see about you." },
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
    if root and LOOK_KEYS[key] then applyLook() end
  end,
})
