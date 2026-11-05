-- The Crew panel: a movable window with one row per friend. Registers the module "panel".
-- Hiding the panel = turning the module off. Redraws are coalesced: many requests in one frame -> one redraw.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local FEATURE = "panel"
local T, Widgets, Logic = ns.Theme, ns.Widgets, ns.PanelLogic
local C = T.COLOR

local ROW_WIDTH = { full = 230, compact = 200, tiny = 160 }
local ICON_SIZE = { full = 18, compact = 16, tiny = 14 }
local HEADER_HEIGHT, PAD, GAP, LINE = 24, 8, 10, 13
local TICK = 30 -- seconds; keeps "last seen 2h ago" fresh
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local LOOK_KEYS = { scale = true, bgAlpha = true, position = true, fadeOut = true, fadeAlpha = true }
local REDRAW_ON = { "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED", "LAYER_RELATION",
  "SETTING_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED" }

local root, countText, noteText
local rowFrames = {}   -- pool, created once and reused (at most PANEL_MAX_ROWS)
local models = {}      -- row models of the last redraw
local header = ""
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
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.name = T.text(r, T.FONT.normal)
  r.level = T.text(r, T.FONT.small, C.title)
  r.zone = T.text(r, T.FONT.small, C.zone)
  r.status = T.text(r, T.FONT.small, C.status)
  for _, fs in ipairs({ r.name, r.zone, r.status }) do
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
  end
  r.xpBack = r:CreateTexture(nil, "ARTWORK")
  T.color(r.xpBack, C.xpBack, 1)
  r.xpFill = r:CreateTexture(nil, "OVERLAY")
  T.color(r.xpFill, C.xp, 1)
  r.pills = {}
  draggable(r)
  return r
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
  ns.ClassIcon.apply(r.icon, m.class)

  local roomRight = style == "tiny" and 8 or 34
  r.name:ClearAllPoints()
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.name:SetWidth(width - 6 - icon - 5 - roomRight)
  r.name:SetText(m.name)
  r.name:SetTextColor(T.classColor(m.class))

  if style ~= "tiny" and m.level then
    r.level:ClearAllPoints()
    r.level:SetPoint("RIGHT", r, "TOPRIGHT", -8, -(5 + icon / 2))
    r.level:SetText(tostring(m.level))
    r.level:Show()
  else
    r.level:Hide()
  end

  local y = 5 + icon + 2
  r.zone:Hide(); r.status:Hide(); r.xpBack:Hide(); r.xpFill:Hide()
  if style == "full" then
    local line = m.offline and m.offlineText or (s.showZone and m.zoneText ~= "" and m.zoneText)
    if line then placeLine(r, r.zone, line, y, width); y = y + LINE end
    if not m.offline and s.showStatus and m.status ~= "" then
      placeLine(r, r.status, '"' .. m.status .. '"', y, width)
      y = y + LINE
    end
    if not m.offline and s.showXP and m.xp then
      local barWidth = width - 16
      r.xpBack:ClearAllPoints()
      r.xpBack:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -(y + 2))
      r.xpBack:SetSize(barWidth, 6)
      r.xpBack:Show()
      local xp = clamp(m.xp, 0, 100, 0)
      if xp > 0 then
        r.xpFill:ClearAllPoints()
        r.xpFill:SetPoint("TOPLEFT", r.xpBack, "TOPLEFT", 0, 0)
        r.xpFill:SetSize(math.max(1, barWidth * xp / 100), 6)
        r.xpFill:Show()
      end
      y = y + 10
    end
  end
  local height = y + 4
  r:SetHeight(height)
  r:SetAlpha(m.offline and 0.4 or 1)
  layoutPills(r, m.tags)
  return height
end

---------------------------------------------------------------------------------------------------------- redraw
local function hide()
  if root then
    stopDrag() -- a drag cut short by hiding must not leave the panel "moving"
    root:Hide()
  end
  shown = false
  Widgets.closeMenu()
end

local function redraw()
  redraws = redraws + 1
  if not root or not enabled then return end
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
  models = Logic.rows(members, s, relationOf, ns.Modules.isEnabled("tags"), ns.now(), ns.wallclock())
  header = Logic.headerText(online, total)
  countText:SetText(header)

  local max = ns.Config.PANEL_MAX_ROWS
  local first, last = Logic.window(#models, offset, max)
  offset, firstRow = first - 1, first
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style]
  local alpha = clamp(s.bgAlpha, 0, 1, 0.8)
  local y = HEADER_HEIGHT + GAP
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
  for i = used + 1, #rowFrames do rowFrames[i]:Hide() end
  visibleRows = used

  local note
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
  local title = T.text(head, T.FONT.normal, C.title)
  title:SetPoint("LEFT", head, "LEFT", PAD, -2)
  title:SetText("TwizCrew")
  countText = T.text(head, T.FONT.small, C.muted)
  countText:SetPoint("RIGHT", head, "RIGHT", -PAD, -2)
  noteText = T.text(root, T.FONT.small, C.muted)
  noteText:SetJustifyH("LEFT")
  root:Hide()
end

---------------------------------------------------------------------------------------------------------- public
-- Mouse wheel: delta 1 = up (earlier rows), -1 = down.
function Panel.scroll(delta)
  offset = offset - (tonumber(delta) or 0)
  requestRedraw()
end

function Panel.isShown() return shown end
function Panel.models() return models end
function Panel.headerText() return header end
function Panel.rowCountForTest() return visibleRows end
function Panel.firstRowForTest() return firstRow end
function Panel.redrawCountForTest() return redraws end
function Panel.isMovingForTest() return moving end

local function onEnable()
  enabled = true
  if not root then build() end
  local ok, fighting = false, false
  if type(UnitAffectingCombat) == "function" then ok, fighting = pcall(UnitAffectingCombat, "player") end
  inCombat = ok and fighting and true or false
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
        .. "Tiny: just the name and tags." },
    { key = "showZone", label = "Show zone line", kind = "toggle",
      info = "Shows where each friend is, like \"Elwynn Forest, Goldshire\"." },
    { key = "showStatus", label = "Show typed status", kind = "toggle",
      info = "Shows the short note a friend typed with /tc status, like \"LF Deadmines\"." },
    { key = "showXP", label = "Show XP bar", kind = "toggle",
      info = "Shows a purple bar with how close each friend is to their next level." },
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
