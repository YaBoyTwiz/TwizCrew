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
local ICON_SIZE = { full = 26, compact = 23, tiny = 19 }
local HEADER_HEIGHT, PAD, GAP, LINE = 24, 8, 10, 15
local TAB_HEIGHT, BOARD_WIDTH = 18, 320
local UPDATE_HEIGHT = 17 -- the gold "Update available: vX" line under the header
local NEWS_HEIGHT = 18   -- the What's new line under it, always there (bright "New in vX!" until you've read it)
local OFF_HEIGHT = 20    -- the "Offline (N)" bar between online and offline friends
local BOARD_UNAVAILABLE = "Hall of Shame unavailable right now"
local TICK = 30 -- seconds; keeps "last seen 2h ago" fresh
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local LOOK_KEYS = { scale = true, bgAlpha = true, position = true, fadeOut = true, fadeAlpha = true }
local REDRAW_ON = { "MEMBER_UPDATED", "MEMBER_ONLINE", "MEMBER_OFFLINE", "SELF_UPDATED", "LAYER_RELATION",
  "SETTING_CHANGED", "SETTINGS_RESET", "MODULE_TOGGLED", "STATS_CHANGED", "SESSION_CHANGED", "UPDATE_SEEN",
  "AWAY_CHANGED", "FIND_CHANGED", "TROPHIES_CHANGED", "CLOWN_CHANGED" }
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow" -- the row arrow to a group member (Find the crew)
local ARROW_SIZE = 26 -- big enough to read at a glance

local root, countText, noteText
local afkButton -- the "zzz" button in the header: go AFK / come back
local toolsButton -- the wrench in the header: a menu of handy tools (spell ranks, ...)
local calButton   -- the scroll in the header, left of the wrench: the crew calendar
local titleText, headerShort = nil, nil -- "TwizCrew" in the header; the short count ("1/3") when room is tight
local grip -- the move-arrows handle at the left of the header (dim while the panel is locked)
local versionText, updateBar  -- the version after "TwizCrew"; the gold update line (a button: click = how to update)
local newsBar, versionButton, offBar -- "New in vX" line; click the title for What's new; the "Offline (N)" bar
local newsLine, offBarShown, entries = nil, false, {}
local CHEER_FOR = 300 -- seconds the Congrats button stays on a friend's row after they level up
local dingAt, cheered = {}, {} -- name -> when they leveled up; name -> true once we congratulated them
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
local arrowTicker -- turns the visible row arrows between redraws (Find the crew)
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

-- Menu pictures by the start of an entry's words (entries that bring their own icon keep it).
local MENU_ICONS = {
  { "^Whisper", "Interface\\Icons\\INV_Misc_Note_02" },
  { "^Invite", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" },
  { "^Inspect", "Interface\\Icons\\Spell_Holy_MindVision" },
  { "^Point the arrow", "Interface\\Icons\\Ability_Hunter_Pathfinding" },
  { "^Ask to share", "Interface\\Icons\\Spell_ChargePositive" },
  { "^Can't share", "Interface\\RaidFrame\\ReadyCheck-NotReady" },
  { "^Congratulate", "Interface\\Icons\\INV_Misc_Gift_01" },
  { "^Mock", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
  { "^Add to friends", "Interface\\Icons\\Spell_Holy_GreaterHeal" },
  { "set my status", "Interface\\Icons\\INV_Misc_Note_01" },
  { "^Set my status", "Interface\\Icons\\INV_Misc_Note_01" },
  { "AFK", "AFK_TAG" },
  { "I'm back", "AFK_TAG" },
  { "spell ranks", "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
  { "^Show offline", "Interface\\Icons\\Ability_Stealth" },
  { "^Lock position", "Interface\\Icons\\INV_Misc_Key_03" },
  { "^Row style", "Interface\\Icons\\INV_Fabric_Linen_01" },
  { "^Hide during fights", "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
  { "^Open settings", "Interface\\Icons\\Trade_Engineering" },
  { "^Hide panel", "Interface\\Icons\\Spell_Nature_Invisibilty" },
}

-- A list without its holes (menu entries that are nil when their feature is off), each with its picture.
local function compact(t)
  local out = {}
  for i = 1, table.maxn(t) do
    local it = t[i]
    if it ~= nil then
      if type(it) == "table" and it.icon == nil and type(it.label) == "string" then
        for _, m in ipairs(MENU_ICONS) do
          if it.label:find(m[1]) then
            it.icon = m[2] == "AFK_TAG" and ns.Tags.ICON.AFK or m[2]
            break
          end
        end
      end
      out[#out + 1] = it
    end
  end
  return out
end

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
  r.afk:SetSize(T.icon(14), T.icon(14))
  r.afk:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 4, -4)
  r.afk:Hide()
  -- the Mock button: only on a dead friend's row
  r.mock = T.frame("Button", nil, r)
  r.mock:SetSize(54, 18)
  r.mock:SetFrameLevel((r:GetFrameLevel() or 1) + 5)
  T.paint(r.mock, "8a1c1c", 1, "000000", 1)
  T.gloss(r.mock, nil, 0.25, "ARTWORK")
  r.mock.icon = r.mock:CreateTexture(nil, "OVERLAY")
  r.mock.icon:SetSize(T.icon(14), T.icon(14))
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
  -- important: stays fully visible while the panel is faded (or the row dimmed)
  if r.mock.SetIgnoreParentAlpha then r.mock:SetIgnoreParentAlpha(true) end
  -- the Congrats button: on a friend's row for a few minutes after they level up
  r.cheer = T.frame("Button", nil, r)
  r.cheer:SetSize(66, 18)
  r.cheer:SetFrameLevel((r:GetFrameLevel() or 1) + 5)
  T.paint(r.cheer, "1f7a2e", 1, "000000", 1)
  T.gloss(r.cheer, nil, 0.25, "ARTWORK")
  r.cheer.icon = r.cheer:CreateTexture(nil, "OVERLAY")
  r.cheer.icon:SetSize(T.icon(14), T.icon(14))
  r.cheer.icon:SetPoint("LEFT", r.cheer, "LEFT", 3, 0)
  r.cheer.icon:SetTexture("Interface\\Icons\\INV_Misc_Gift_01")
  r.cheer.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.cheer.text = T.readable(T.text(r.cheer, T.FONT.small, C.white))
  r.cheer.text:SetPoint("LEFT", r.cheer.icon, "RIGHT", 2, 0)
  r.cheer.text:SetText("Congrats")
  local cheerHl = r.cheer:CreateTexture(nil, "HIGHLIGHT")
  cheerHl:SetAllPoints(r.cheer)
  T.color(cheerHl, C.white, 0.15)
  script(r.cheer, "OnClick", function(self) Panel.cheer(self:GetParent()) end)
  script(r.cheer, "OnEnter", function(self)
    local m = self:GetParent().tcModel
    if not GameTooltip or not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Congratulate " .. tostring(m.name))
    GameTooltip:AddLine("Sends an encouraging line the crew sees. " .. tostring(m.name) .. " sees your character "
      .. "cheer for them.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(r.cheer, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r.cheer:Hide()
  if r.cheer.SetIgnoreParentAlpha then r.cheer:SetIgnoreParentAlpha(true) end
  -- Find the crew: a small arrow to a group member (turns as you turn) and the distance; click = the big arrow
  r.arrow = T.frame("Button", nil, r)
  r.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  r.arrow:SetFrameLevel((r:GetFrameLevel() or 1) + 4)
  r.arrow.tex = r.arrow:CreateTexture(nil, "ARTWORK")
  r.arrow.tex:SetAllPoints(r.arrow)
  r.arrow.tex:SetTexture(ARROW_TEXTURE)
  local arrowHl = r.arrow:CreateTexture(nil, "HIGHLIGHT")
  arrowHl:SetAllPoints(r.arrow)
  T.color(arrowHl, C.white, 0.15)
  r.arrow.dist = T.readable(T.text(r, T.FONT.small, C.white))
  r.arrow.dist:SetJustifyH("RIGHT")
  script(r.arrow, "OnClick", function(self) Panel.arrowClicked(self:GetParent()) end)
  script(r.arrow, "OnEnter", function(self)
    local m = self:GetParent().tcModel
    local a = rawget(self:GetParent(), "tcArrow")
    if not GameTooltip or not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Point the way to " .. tostring(m.name))
    if a and a.still and a.zone then GameTooltip:AddLine("In " .. tostring(a.zone), 1, 1, 1) end
    GameTooltip:AddLine("Click for a big arrow that leads you there (click again to close it).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(r.arrow, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r.arrow:Hide()
  r.arrow.dist:Hide()
  r.name = T.text(r, T.FONT.normal)
  r.level = T.text(r, T.FONT.small, C.title)
  r.zone = T.text(r, T.FONT.small, C.zone)
  r.status = T.text(r, T.FONT.small, C.status)
  r.title = T.text(r, T.FONT.small, C.muted)
  r.quest = T.text(r, T.FONT.small, C.status) -- the quest they're on, with a ! (or ? when ready to turn in)
  r.questIcon = r:CreateTexture(nil, "ARTWORK")
  r.questIcon:SetSize(T.icon(12), T.icon(12))
  -- "they can share this quest with you": a small icon after the !, a button (click = ask them to share it)
  r.share = T.frame("Button", nil, r)
  r.share:SetSize(T.icon(13), T.icon(13))
  r.share:SetFrameLevel((r:GetFrameLevel() or 1) + 4)
  r.share.icon = r.share:CreateTexture(nil, "ARTWORK")
  r.share.icon:SetAllPoints(r.share)
  -- (picture set in layoutRow: green + you can get it, red X you can't, green check you're on it too)
  local shareHl = r.share:CreateTexture(nil, "HIGHLIGHT")
  shareHl:SetAllPoints(r.share)
  T.color(shareHl, C.white, 0.3)
  script(r.share, "OnClick", function(self) Panel.askShare(self:GetParent()) end)
  script(r.share, "OnEnter", function(self)
    local m = self:GetParent().tcModel
    if not GameTooltip or not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if m.questShare == "yes" then
      GameTooltip:SetText(tostring(m.name) .. " can share this quest with you", 0.3, 1, 0.4)
      GameTooltip:AddLine(tostring(m.questName or ""), 1, 1, 1)
      GameTooltip:AddLine("Click to ask them to share it (you need to be in a group).", 0.8, 0.8, 0.8, true)
    elseif m.questShare == "same" then
      GameTooltip:SetText("You're on this quest too", 0.3, 1, 0.4)
      GameTooltip:AddLine(tostring(m.questName or ""), 1, 1, 1)
    else
      GameTooltip:SetText(tostring(m.name) .. " can't share this quest with you", 1, 0.35, 0.3)
      GameTooltip:AddLine(tostring(m.questName or ""), 1, 1, 1)
      local why = tostring(m.questWhy or "")
      if why ~= "" then GameTooltip:AddLine((why:gsub("^%l", string.upper)) .. ".", 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:Show()
  end)
  script(r.share, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r.share:Hide()
  if r.share.SetIgnoreParentAlpha then r.share:SetIgnoreParentAlpha(true) end -- easy to spot while faded
  for _, fs in ipairs({ r.name, r.zone, r.status, r.title, r.quest }) do
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
  end
  -- readable on the class-colored row: black outline and shadow, the name a size bigger
  T.readable(r.name, 1)
  for _, fs in ipairs({ r.level, r.zone, r.status, r.title, r.quest }) do T.readable(fs) end
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
  script(r, "OnMouseUp", function(self, button)
    if button == "RightButton" and self.tcModel then Widgets.menu(self, Panel.rowMenu(self.tcModel)) end
  end)
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

---------------------------------------------------------------------------------------------------- row arrows
local DIST_WIDTH = 44 -- room for "999 yd" / "1.2k yd", so a changing distance never pushes into the name

-- The row arrow for a model (Find the crew), worked out in that module's own guard: an error there means "no
-- arrow", never a broken panel.
local function rowArrow(m, me, facing)
  if type(m) ~= "table" or m.offline or not ns.Find or not ns.Find.arrowFor then return nil end
  local ok, a = ns.Log.safe("find", ns.Find.arrowFor, m.name, me, facing)
  if ok and type(a) == "table" then return a end
  return nil
end

-- Colours and turns a row's arrow: the friend's class colour; a still arrow (another zone) is dimmer and points up.
local function paintArrow(r, a, m, withDist)
  local cr, cg, cb = T.classColor(m.class)
  r.arrow.tex:SetVertexColor(math.min(1, cr + 0.25), math.min(1, cg + 0.25), math.min(1, cb + 0.25))
  -- running off: flashing red and yellow, pulsing bigger, until the alarm runs out
  local alarm = ns.Find and ns.Find.isRunningOff and ns.Find.isRunningOff(m.name)
  r.tcAlarm = alarm or nil
  if alarm then
    local t = ns.now()
    if math.floor(t * 4) % 2 == 0 then r.arrow.tex:SetVertexColor(1, 0.15, 0.15) else r.arrow.tex:SetVertexColor(1, 0.85, 0.1) end
    local size = ARROW_SIZE * (1.35 + 0.25 * math.sin(t * 10))
    r.arrow:SetSize(size, size)
  else
    r.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  end
  if a.still then
    r.arrow.tex:SetRotation(0)
    r.arrow.tex:SetAlpha(0.6)
  else
    r.arrow.tex:SetRotation(a.angle or 0)
    r.arrow.tex:SetAlpha(1)
  end
  r.tcArrowAngle = (not a.still) and a.angle or nil
  if withDist then
    r.arrow.dist:ClearAllPoints()
    r.arrow.dist:SetPoint("RIGHT", r.arrow, "LEFT", -2, 0)
    r.arrow.dist:SetWidth(DIST_WIDTH)
    r.arrow.dist:SetText(a.text or "")
    r.arrow.dist:Show()
    r.tcArrowText = a.text
  else
    r.arrow.dist:Hide()
    r.tcArrowText = nil
  end
end

-- Draws one row model; returns the row's height.
-- The quest line's share picture: { texture, is a spell icon (trim its edge) }
local SHARE_PIC = {
  yes = { "Interface\\Icons\\Spell_ChargePositive", true },
  no = { "Interface\\RaidFrame\\ReadyCheck-NotReady", false },
  same = { "Interface\\RaidFrame\\ReadyCheck-Ready", false },
}

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
  -- Find the crew: the row arrow (and its distance) sits just left of the corner text, on the name's line
  local a = rowArrow(m)
  r.tcArrow = a
  if a then
    local right = corner and (textWidth(r.level, corner) + 12) or 8
    r.arrow:ClearAllPoints()
    r.arrow:SetPoint("RIGHT", r, "TOPRIGHT", -right, -(5 + icon / 2))
    local withDist = not a.still and style ~= "tiny"
    paintArrow(r, a, m, withDist)
    r.arrow:Show()
    roomRight = math.max(roomRight, right + ARROW_SIZE + 4 + (withDist and (DIST_WIDTH + 2) or 0))
  else
    r.arrow:Hide()
    r.arrow.dist:Hide()
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
  r.quest:Hide(); r.questIcon:Hide(); r.share:Hide()
  r.tcShare = nil
  r.xpGloss:Hide(); r.xpSpark:Hide()
  r.tcBarText = nil
  if style == "full" then
    local line = m.offline and m.offlineText or (s.showZone and m.zoneText ~= "" and m.zoneText)
    if line then placeLine(r, r.zone, line, y, width); y = y + LINE end
    if not m.offline and s.showStatus and m.status ~= "" then
      placeLine(r, r.status, '"' .. m.status .. '"', y, width)
      y = y + LINE
    end
    if not m.offline and s.showQuest ~= false and m.quest then
      r.questIcon:ClearAllPoints()
      r.questIcon:SetPoint("TOPLEFT", r, "TOPLEFT", 7, -y)
      r.questIcon:SetTexture(m.questDone and "Interface\\GossipFrame\\ActiveQuestIcon"
        or "Interface\\GossipFrame\\AvailableQuestIcon")
      r.questIcon:Show()
      placeLine(r, r.quest, m.quest, y, width)
      local textX = 22
      if m.questShare then
        local pic = SHARE_PIC[m.questShare]
        r.share.icon:SetTexture(pic[1])
        if pic[2] then r.share.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else r.share.icon:SetTexCoord(0, 1, 0, 1) end
        r.share:ClearAllPoints()
        r.share:SetPoint("TOPLEFT", r, "TOPLEFT", 21, -y + 1)
        r.share:Show()
        r.tcShare = m.questShare
        textX = 37
      end
      r.quest:ClearAllPoints()
      r.quest:SetPoint("TOPLEFT", r, "TOPLEFT", textX, -y)
      r.quest:SetWidth(width - textX - 8)
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
  local mockOn = dead and not m.offline and ns.Roasts and ns.Roasts.canMock(m.name)
  if mockOn then
    r.mock:ClearAllPoints()
    r.mock:SetPoint("RIGHT", r, "RIGHT", -6, style == "full" and 0 or -2)
    r.mock:Show()
  else
    r.mock:Hide()
  end
  r.tcCheer = nil
  if m.dinged and not m.offline and ns.Roasts and ns.Roasts.canCheer and ns.Roasts.canCheer(m.name) then
    r.cheer:ClearAllPoints()
    if mockOn then
      r.cheer:SetPoint("RIGHT", r.mock, "LEFT", -4, 0)
    else
      r.cheer:SetPoint("RIGHT", r, "RIGHT", -6, style == "full" and 0 or -2)
    end
    r.cheer:Show()
    r.tcCheer = true
  else
    r.cheer:Hide()
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
  if not GameTooltip or type(m) ~= "table" or (type(m.tip) ~= "table" and type(m.info) ~= "table") then return end
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  GameTooltip:SetText(m.name, T.classColor(m.class))
  local cr, cg, cb = T.rgb(C.text)
  for _, line in ipairs(m.tip or {}) do GameTooltip:AddLine(line, cr, cg, cb) end
  for _, line in ipairs(m.info or {}) do GameTooltip:AddLine(line, cr, cg, cb) end
  -- live: how far they are (group members, Find the crew)
  if ns.Find and ns.Find.arrowFor and not m.offline then
    local ok, a = pcall(ns.Find.arrowFor, m.name)
    if ok and type(a) == "table" and type(a.text) == "string" and a.text ~= "" then
      GameTooltip:AddLine("Distance: " .. a.text, cr, cg, cb)
    end
  end
  local mr, mg, mb = T.rgb(C.muted)
  GameTooltip:AddLine("Right-click for options", mr, mg, mb)
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
  local right = (PAD - 2) + 16 + 4 + 16 + 4 + 16 + 6 + 6 + 16 + 6 -- gear, tools, calendar, gaps, AFK, gap
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
  -- What's new: always there so it's easy to find; bright with "New in vX!" until the window has been opened
  newsLine = nil
  if ns.Changelog then
    local fresh = ns.Changelog.unseen()
    local ver = "v" .. ns.Util.safeText(tostring(ns.VERSION))
    if fresh then
      newsLine = s.rowStyle == "tiny" and ("New in " .. ver .. "!") or ("New in " .. ver .. "! Click to see what changed")
    else
      newsLine = s.rowStyle == "tiny" and "What's new" or ("What's new in " .. ver)
    end
    newsBar:ClearAllPoints()
    newsBar:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -(top - 2))
    newsBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, -(top - 2))
    newsBar.text:SetText(newsLine)
    newsBar.text:SetTextColor(T.rgb(fresh and "8fd0ff" or "c8c8c8"))
    newsBar.glow:SetAlpha(fresh and 1 or 0.45)
    newsBar:Show()
    top = top + NEWS_HEIGHT
  else
    newsBar:Hide()
  end
  if tabBar then
    tabBar:ClearAllPoints()
    tabBar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(top - 2))
    tabBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(top - 2))
  end
  return top
end

---------------------------------------------------------------------------------------------------------- redraw
local updateArrowTicker -- (below requestRedraw) starts or stops the row arrows' ticker

local function stopArrowTicker()
  if arrowTicker then arrowTicker:Cancel(); arrowTicker = nil end
end

local function hide()
  if root then
    stopDrag() -- a drag cut short by hiding must not leave the panel "moving"
    root:Hide()
  end
  if tipRow then Panel.hideRowTip(tipRow) end
  shown = false
  note = nil
  stopArrowTicker()
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
  local hidden
  models, hidden = Logic.rows(members, s, relationOf, ns.Modules.isEnabled("tags"), ns.now(), ns.wallclock(),
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
  entries = Logic.entries(models, hidden, s.showOffline ~= false)
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
    offBar:Hide(); offBarShown = false
    if tipRow then Panel.hideRowTip(tipRow) end
    visibleRows = 0
    stopArrowTicker()
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
  local first, last = Logic.window(#entries, offset, max)
  offset, firstRow = first - 1, first
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
      offBar:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -y)
      offBar:SetSize(width, OFF_HEIGHT)
      offBar.text:SetText(Logic.offlineBarText(e.count, e.open))
      offBar.icon:SetTexture(e.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
      offBar:Show()
      offBarShown = true
      y = y + OFF_HEIGHT + GAP
    else
      used = used + 1
      local r = rowFrames[used]
      if not r then r = createRow(); rowFrames[used] = r end
      local h = layoutRow(r, e, style, s, width)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -y)
      T.setBackgroundAlpha(r, alpha)
      r:Show()
      y = y + h + GAP
    end
  end
  if not offBarShown then offBar:Hide() end
  for i = used + 1, #rowFrames do
    rowFrames[i]:Hide()
    if tipRow == rowFrames[i] then Panel.hideRowTip(tipRow) end
  end
  visibleRows = used
  refreshRowTip()
  updateArrowTicker()

  note = nil
  if #entries == 0 then note = "No crew yet. Friends show up here when they play with TwizCrew."
  elseif #entries == 1 and entries[1].bar then note = "Nobody else is online right now."
  elseif #entries > max then note = "Scroll for more (" .. first .. "-" .. last .. " of " .. #entries .. ")" end
  if note then
    noteText:ClearAllPoints()
    noteText:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -(y - GAP + 4))
    noteText:SetWidth(width)
    noteText:SetText(note)
    noteText:Show()
    y = y - GAP + 4 + (#entries == 0 and 2 * LINE or LINE)
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

-- Between redraws: turn the visible row arrows and update their distance. When an arrow appears, disappears or
-- changes kind (another zone), the whole panel redraws instead (sizes may change).
local function turnArrows()
  if not shown then return stopArrowTicker() end
  local s = setting("rowStyle")
  -- where we are and which way we face, read once for all rows (ten times a second)
  local me, facing
  if ns.Where then
    local ok, p, f = ns.Log.safe("find", function() return ns.Where.me(), ns.Where.facing() end)
    if ok then me, facing = p, f end
  end
  for i = 1, visibleRows do
    local r = rowFrames[i]
    local old = r and rawget(r, "tcArrow")
    local m = r and r.tcModel
    if m then
      local a = rowArrow(m, me, facing)
      if (a == nil) ~= (old == nil) or (a and old and (a.still and true or false) ~= (old.still and true or false)) then
        requestRedraw()
        return
      end
      if a then
        r.tcArrow = a
        paintArrow(r, a, m, not a.still and s ~= "tiny")
      end
    end
  end
end

updateArrowTicker = function()
  local any = false
  for i = 1, visibleRows do
    local r = rowFrames[i]
    if r and rawget(r, "tcArrow") then any = true end
  end
  if any and not arrowTicker and C_Timer and C_Timer.NewTicker then
    arrowTicker = C_Timer.NewTicker(ns.Config.FIND_ARROW_TICK, function() ns.Log.safe(FEATURE, turnArrows) end)
  elseif not any then
    stopArrowTicker()
  end
end

-- A row arrow was clicked: the big arrow to that friend (again: closes it).
function Panel.arrowClicked(r)
  local m = r and r.tcModel
  if not m or not ns.BigArrow then return end
  ns.Log.safe("find", ns.BigArrow.toggle, m.name)
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

-- The wrench button's menu: handy tools. New tools go here.
function Panel.toolItems()
  local function rank(key) return ns.Modules.setting("rankup", key) end
  local function flipRank(key)
    return function()
      if not ns.Modules.isEnabled("rankup") then ns.Modules.setEnabled("rankup", true) end
      ns.Modules.set("rankup", key, not rank(key))
    end
  end
  return compact {
    ns.RankUp and { label = "Update my spell ranks", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
      onClick = function() ns.RankUp.run() end } or nil,
    ns.RankUp and { label = "...by itself when I learn a spell", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      checked = function() return rank("auto") and true or false end, onClick = flipRank("auto") } or nil,
    ns.RankUp and { label = "...with its own button on screen", icon = "Interface\\Icons\\INV_Misc_Rune_01",
      checked = function() return rank("showButton") and true or false end, onClick = flipRank("showButton") } or nil,
    ns.SpellHelpers and { label = "Spell helpers (ranks, smart target)", icon = "Interface\\Icons\\Spell_Holy_HealingFocus",
      onClick = function() ns.SpellHelpers.toggle() end } or nil,
    ns.Calendar and { label = "Crew calendar", icon = "Interface\\Icons\\INV_Scroll_03",
      onClick = function() ns.Calendar.toggle() end } or nil,
    ns.MockEditor and { label = "My mocks", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
      onClick = function() ns.MockEditor.open() end } or nil,
    ns.Recap and { label = "Today's recap", icon = "Interface\\Icons\\INV_Misc_Book_11",
      onClick = function() ns.Recap.show() end } or nil,
    ns.Changelog and { label = "What's new", icon = "Interface\\Icons\\INV_Misc_Book_09",
      onClick = function() ns.Changelog.open() end } or nil,
    { label = "Health check (to copy to Discord)", icon = "Interface\\Icons\\INV_Misc_Note_01",
      onClick = function() if ns.Report then ns.Report.show() end end },
  }
end

function Panel.toolsButtonForTest() return toolsButton end
function Panel.calendarButtonForTest() return calButton end

function Panel.menuItems()
  return compact {
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

-- The quick statuses in the status box.
Panel.STATUS_PRESETS = { "LF group", "Questing", "Farming", "Dungeon soon", "Back in 5" }

function Panel.setStatusPreset(text)
  ns.Self.setStatus(text or "")
  local now = ns.db and ns.db.myStatus or ""
  if now == "" then print("TwizCrew: status cleared")
  else print('TwizCrew: status set to "' .. ns.Util.safeText(now) .. '"') end
  if statusBox then statusBox.open = false; statusBox.edit:ClearFocus(); statusBox:Hide() end
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
  f:SetSize(300, 132)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:EnableMouse(true)
  T.paint(f, C.backdrop, 0.95, C.border, 2)
  local title = T.text(f, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText("Set my status")
  local e = T.frame("EditBox", nil, f)
  e:SetSize(276, 22)
  e:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
  T.paint(e, C.row, 1, C.buttonBorder, 1)
  e:SetAutoFocus(false)
  if e.SetFontObject then e:SetFontObject(T.FONT.small) end
  if e.SetTextInsets then e:SetTextInsets(5, 5, 0, 0) end
  if e.SetMaxLetters then e:SetMaxLetters(ns.Config.STATUS_MAX) end
  local hint = T.text(f, T.FONT.small, C.muted)
  hint:SetPoint("TOPLEFT", e, "BOTTOMLEFT", 0, -4)
  hint:SetText("Enter saves, Escape cancels. Leave it empty to clear it.")
  -- one click for the usual ones
  local presets = T.text(f, T.FONT.small, C.muted)
  presets:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  presets:SetText("Quick:")
  local x, y = 0, 0
  for i, p in ipairs(Panel.STATUS_PRESETS) do
    local b = Widgets.button(f, p, function() Panel.setStatusPreset(p) end, nil, FEATURE)
    b:SetHeight(20)
    local w = b:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = 70 end
    if x + w > 240 then x, y = 0, y + 23 end
    b:SetPoint("TOPLEFT", presets, "TOPRIGHT", 6 + x, 3 - y)
    x = x + w + 4
  end
  local clear = Widgets.button(f, "Clear", function() Panel.setStatusPreset("") end, "danger", FEATURE)
  clear:SetHeight(20)
  clear:SetPoint("TOPLEFT", presets, "TOPRIGHT", 6 + x, 3 - y)
  script(e, "OnEnterPressed", saveStatus)
  script(e, "OnEscapePressed", closeStatusBox)
  script(f, "OnHide", function() f.open = false end)
  f.edit = e
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewStatus") end -- Escape closes it
  return f
end

-------------------------------------------------------------------------------------------------------- row menu
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
end

-- Is this friend in my group? The game's name check, else their name in my party / raid slots (Forever's name
-- check can miss them).
local function inMyGroup(name)
  if (call(UnitInParty, name) or call(UnitInRaid, name)) then return true end
  if ns.Where and ns.Where.unitFor then
    if ns.Where.unitFor(name) then return true end
    local short = ns.shortName and ns.shortName(name)
    if short and short ~= name and ns.Where.unitFor(short) then return true end
  end
  return false
end

local function whisper(full)
  if ChatFrameUtil and type(ChatFrameUtil.SendTell) == "function" then return call(ChatFrameUtil.SendTell, full) end
  if type(ChatFrame_SendTell) == "function" then return call(ChatFrame_SendTell, full) end
  if type(ChatFrame_OpenChat) == "function" then call(ChatFrame_OpenChat, "/w " .. full .. " ") end
end

local function inviteName(full)
  if C_PartyInfo and C_PartyInfo.InviteUnit then call(C_PartyInfo.InviteUnit, full)
  elseif type(InviteUnit) == "function" then call(InviteUnit, full) end
end

local function addFriend(full)
  if C_FriendList and C_FriendList.AddFriend then call(C_FriendList.AddFriend, full)
  elseif type(AddFriend) == "function" then call(AddFriend, full) end
  print("TwizCrew: asked the game to add " .. full .. " to your friends list.")
end

-- The right-click menu of a row: what you can do for (or to) that friend right now.
function Panel.rowMenu(m)
  local items = {}
  local name = m and m.name
  if type(name) ~= "string" or name == "" then return items end
  if ns.isMe(name) then
    items[#items + 1] = { label = "Set my status", onClick = function() Panel.openStatusBox() end }
    items[#items + 1] = { label = (ns.Away and ns.Away.isAway()) and "I'm back" or "Go AFK",
      onClick = function() Panel.toggleAway() end }
    return compact(items)
  end
  local full = (ns.Transport and ns.Transport.fullName and ns.Transport.fullName(name)) or name
  if not m.offline then
    items[#items + 1] = { label = "Whisper", onClick = function() whisper(full) end }
    if not inMyGroup(name) then
      items[#items + 1] = { label = "Invite to group", onClick = function() inviteName(full) end }
    end
    local unit = ns.MockShow and ns.MockShow.liveUnit(name)
    if unit and call(CanInspect, unit) and type(InspectUnit) == "function" then
      items[#items + 1] = { label = "Inspect", onClick = function() call(InspectUnit, unit) end }
    end
    if ns.Find and ns.BigArrow and ns.Find.positionOf and call(ns.Find.positionOf, name) then
      items[#items + 1] = { label = "Point the arrow at them",
        onClick = function() ns.BigArrow.point({ kind = "member", name = name }) end }
    end
    local dead = false
    for _, id in ipairs(m.tags or {}) do if id == "DEAD" then dead = true end end
    if m.questName and ns.Quest and ns.Quest.request then
      local title = m.questName
      local shown = ns.Util.truncateUTF8(ns.Util.safeText(title), 28)
      if shown ~= ns.Util.safeText(title) then shown = shown .. "..." end
      local status, words = "unknown", nil
      if ns.Quest.canGet then status, words = ns.Quest.canGet(m.questId, title, m.questShareable) end
      if status == "ok" or status == "unknown" then
        items[#items + 1] = { label = "Ask to share: " .. shown, onClick = function() ns.Quest.request(name, title) end }
      else
        items[#items + 1] = { label = "Can't share: " .. shown .. " (" .. tostring(words) .. ")",
          onClick = function() print("TwizCrew: no use asking: " .. tostring(words) .. ".") end }
      end
    end
    if m.dinged and ns.Roasts and ns.Roasts.canCheer and ns.Roasts.canCheer(name) then
      items[#items + 1] = { label = "Congratulate them", onClick = function() Panel.cheer({ tcModel = m }) end }
    end
    if dead and ns.Roasts and ns.Roasts.canMock(name) then
      items[#items + 1] = { label = "Mock them", onClick = function()
        if not ns.Roasts.mock(name) then print("TwizCrew: give it a few seconds before mocking " .. name .. " again.") end
      end }
    end
  end
  items[#items + 1] = { label = "Add to friends", onClick = function() addFriend(full) end }
  -- my own things, on every row (my own row is off by default); later features for me go here too
  for _, it in ipairs(Panel.myItems()) do items[#items + 1] = it end
  return compact(items)
end

-- What I can do for myself from any row's menu (and my own row's).
function Panel.myItems()
  return compact {
    { label = "Me: set my status", onClick = function() Panel.openStatusBox() end },
    { label = (ns.Away and ns.Away.isAway()) and "Me: I'm back" or "Me: go AFK", onClick = function() Panel.toggleAway() end },
    ns.RankUp and ns.Modules.isEnabled("rankup") and
      { label = "Me: update my spell ranks", onClick = function() ns.RankUp.run() end } or nil,
  }
end

-- The share icon on a quest line: ask them to share it.
function Panel.askShare(r)
  local m = r and r.tcModel
  if not m or not m.questName or not ns.Quest or not ns.Quest.request then return end
  if m.questShare == "no" then print("TwizCrew: no use asking: " .. tostring(m.questWhy or "you can't get it") .. "."); return end
  if m.questShare == "same" then print("TwizCrew: you're on that quest too."); return end
  ns.Quest.request(m.name, m.questName)
end

function Panel.rowShareShownForTest(i)
  local r = rowFrames[i]
  if r == nil or i > visibleRows then return nil end
  return rawget(r, "tcShare") -- "yes" | "no" | "same" | nil
end

-- The Congrats button (or menu entry): congratulate them once; the button goes away.
function Panel.cheer(r)
  local m = r and r.tcModel
  if not m or not ns.Roasts or not ns.Roasts.cheer then return end
  if ns.Roasts.cheer(m.name) then
    cheered[m.name] = true
    requestRedraw()
  end
end

function Panel.rowCheerShownForTest(i)
  local r = rowFrames[i]
  return r ~= nil and i <= visibleRows and rawget(r, "tcCheer") == true
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
  grip:SetSize(T.icon(16), T.icon(16))
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
  -- click the title (or its version) for What's new; dragging it still moves the panel
  versionButton = CreateFrame("Button", nil, head)
  versionButton:SetPoint("TOPLEFT", title, "TOPLEFT", -2, 3)
  versionButton:SetPoint("BOTTOMRIGHT", versionText, "BOTTOMRIGHT", 2, -3)
  draggable(versionButton)
  script(versionButton, "OnClick", function() if ns.Changelog then ns.Changelog.toggle() end end)
  script(versionButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("TwizCrew v" .. tostring(ns.VERSION))
    GameTooltip:AddLine("Click to see what's new in each version", 1, 1, 1)
    GameTooltip:Show()
  end)
  script(versionButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  local gear = CreateFrame("Button", nil, head)
  gear:SetSize(T.icon(16), T.icon(16))
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
  -- the tools button: a wrench left of the gear; click = a menu of handy tools
  toolsButton = CreateFrame("Button", nil, head)
  toolsButton:SetSize(T.icon(16), T.icon(16))
  toolsButton:SetPoint("RIGHT", gear, "LEFT", -4, 0)
  local toolsIcon = toolsButton:CreateTexture(nil, "ARTWORK")
  toolsIcon:SetAllPoints(toolsButton)
  toolsIcon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
  toolsIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local toolsHl = toolsButton:CreateTexture(nil, "HIGHLIGHT")
  toolsHl:SetAllPoints(toolsButton)
  T.color(toolsHl, C.white, 0.25)
  script(toolsButton, "OnClick", function(self) Widgets.menu(self, Panel.toolItems()) end)
  script(toolsButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Tools")
    GameTooltip:AddLine("Click for handy tools, like putting your highest spell ranks on your bars.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(toolsButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- the calendar button: left of the wrench
  calButton = CreateFrame("Button", nil, head)
  calButton:SetSize(T.icon(16), T.icon(16))
  calButton:SetPoint("RIGHT", toolsButton, "LEFT", -4, 0)
  local calIcon = calButton:CreateTexture(nil, "ARTWORK")
  calIcon:SetAllPoints(calButton)
  calIcon:SetTexture("Interface\\Icons\\INV_Scroll_03")
  calIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local calHl = calButton:CreateTexture(nil, "HIGHLIGHT")
  calHl:SetAllPoints(calButton)
  T.color(calHl, C.white, 0.25)
  script(calButton, "OnClick", function() if ns.Calendar then ns.Calendar.toggle() end end)
  script(calButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Crew calendar")
    GameTooltip:AddLine("Who played when, and the best time for the crew to play together (or /tc cal).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(calButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  countText:SetPoint("RIGHT", calButton, "LEFT", -6, 0)
  afkButton = CreateFrame("Button", nil, head)
  afkButton:SetSize(T.icon(16), T.icon(16))
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
  if updateBar.SetIgnoreParentAlpha then updateBar:SetIgnoreParentAlpha(true) end -- important: never faded
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

  newsBar = CreateFrame("Button", nil, root)
  if newsBar.SetIgnoreParentAlpha then newsBar:SetIgnoreParentAlpha(true) end -- important: never faded
  newsBar:SetHeight(NEWS_HEIGHT)
  newsBar.glow = newsBar:CreateTexture(nil, "BACKGROUND")
  newsBar.glow:SetAllPoints(newsBar)
  T.color(newsBar.glow, "3fa9f5", 0.18)
  local newsHl = newsBar:CreateTexture(nil, "HIGHLIGHT")
  newsHl:SetAllPoints(newsBar)
  T.color(newsHl, "3fa9f5", 0.25)
  newsBar.icon = newsBar:CreateTexture(nil, "ARTWORK")
  newsBar.icon:SetSize(T.icon(13), T.icon(13))
  newsBar.icon:SetPoint("LEFT", newsBar, "LEFT", PAD - 4, 0)
  newsBar.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
  newsBar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  newsBar.text = T.readable(T.text(newsBar, T.FONT.small, "8fd0ff"))
  newsBar.text:SetPoint("LEFT", newsBar.icon, "RIGHT", 4, 0)
  newsBar.text:SetPoint("RIGHT", newsBar, "RIGHT", -(PAD - 2), 0)
  newsBar.text:SetJustifyH("LEFT")
  script(newsBar, "OnClick", function() if ns.Changelog then ns.Changelog.toggle() end end)
  script(newsBar, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("What's new", T.rgb("8fd0ff"))
    GameTooltip:AddLine("Click to see every TwizCrew version and what changed (or type /tc new).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(newsBar, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  newsBar:Hide()

  offBar = CreateFrame("Button", nil, root)
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

-- Opens or closes the offline friends list at the bottom (the "Offline (N)" bar; remembered).
function Panel.toggleOffline()
  set("showOffline", setting("showOffline") == false)
  requestRedraw()
end

function Panel.newsLineForTest() return newsLine end
function Panel.offlineBarForTest() return offBarShown and offBar or nil end
function Panel.entriesForTest() return entries end
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
-- Row i's arrow (Find the crew): nil when hidden, else { still, angle, text } as drawn.
function Panel.rowArrowForTest(i)
  local r = rowFrames[i]
  local a = r and rawget(r, "tcArrow")
  if not a or i > visibleRows then return nil end
  return { still = a.still and true or false, angle = rawget(r, "tcArrowAngle"), text = rawget(r, "tcArrowText") }
end
function Panel.arrowTickerForTest() return arrowTicker ~= nil end
function Panel.rowAlarmForTest(i) local r = rowFrames[i]; return r ~= nil and rawget(r, "tcAlarm") == true end

local function onEnable()
  enabled = true
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
  if not root then build() end
  local ok, fighting = false, false
  if type(UnitAffectingCombat) == "function" then ok, fighting = pcall(UnitAffectingCombat, "player") end
  inCombat = ok and fighting and true or false
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
    showQuest = true, shareQuest = true, questRequests = true,
    xpText = true, xpTooltip = true,
    fadeOut = true, fadeAlpha = 0.5, locked = false, grow = "down", hideInCombat = false, hideInInstance = false,
    hideWhenAlone = false, showOffline = false, sort = "online", showSelf = false,
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
    if root and LOOK_KEYS[key] then applyLook() end
  end,
})
