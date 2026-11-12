-- The Crew panel's rows: the row frames and how one row model is drawn, the row arrows (Find the crew) and the row
-- tooltip. Part of the panel (UI/Panel.lua); shared names live on ns.Panel._ (P).
local _, ns = ...

local Panel = ns.Panel
local P = Panel._

local FEATURE = "panel"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local LINE = P.LINE
local setting, clamp, script, openMenu, draggable = P.setting, P.clamp, P.script, P.openMenu, P.draggable
local requestRedraw, rowFrames = P.requestRedraw, P.rowFrames

local ICON_SIZE = { full = 26, compact = 23, tiny = 19 }
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow" -- the row arrow to a group member (Find the crew)
local ARROW_SIZE = 26 -- big enough to read at a glance
local arrowTicker -- turns the visible row arrows between redraws (Find the crew)
---------------------------------------------------------------------------------------------------------- rows
local function createRow()
  local r = T.frame("Frame", nil, P.root)
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
    if button == "RightButton" and self.tcModel then openMenu(self, Panel.rowMenu(self.tcModel)) end
  end)
  draggable(r)
  script(r, "OnEnter", function(self) Panel.showRowTip(self) end)
  script(r, "OnLeave", function(self) Panel.hideRowTip(self) end)
  return r
end
P.createRow = createRow

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
P.layoutRow = layoutRow

---------------------------------------------------------------------------------------------------------- row tooltip

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
  P.tipRow = r
end

function Panel.hideRowTip(r)
  if P.tipRow ~= r then return end
  P.tipRow = nil
  if GameTooltip then GameTooltip:Hide() end
end

-- After a redraw: the row under the mouse may show someone else now, or new numbers.
local function refreshRowTip()
  local r = P.tipRow
  if not r then return end
  if GameTooltip and GameTooltip.IsOwned and not GameTooltip:IsOwned(r) then P.tipRow = nil; return end
  local m = r.tcModel -- hidden rows already closed their tooltip (redraw)
  if type(m) ~= "table" or type(m.tip) ~= "table" then Panel.hideRowTip(r); return end
  Panel.showRowTip(r)
end
P.refreshRowTip = refreshRowTip

---------------------------------------------------------------------------------------------------- arrow ticker
local function stopArrowTicker()
  if arrowTicker then arrowTicker:Cancel(); arrowTicker = nil end
end
P.stopArrowTicker = stopArrowTicker

-- Between redraws: turn the visible row arrows and update their distance. When an arrow appears, disappears or
-- changes kind (another zone), the whole panel redraws instead (sizes may change).
local function turnArrows()
  if not P.shown then return stopArrowTicker() end
  local s = setting("rowStyle")
  -- where we are and which way we face, read once for all rows (ten times a second)
  local me, facing
  if ns.Where then
    local ok, p, f = ns.Log.safe("find", function() return ns.Where.me(), ns.Where.facing() end)
    if ok then me, facing = p, f end
  end
  for i = 1, P.visibleRows do
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

P.updateArrowTicker = function()
  local any = false
  for i = 1, P.visibleRows do
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
  if not a or i > P.visibleRows then return nil end
  return { still = a.still and true or false, angle = rawget(r, "tcArrowAngle"), text = rawget(r, "tcArrowText") }
end
function Panel.arrowTickerForTest() return arrowTicker ~= nil end
function Panel.rowAlarmForTest(i) local r = rowFrames[i]; return r ~= nil and rawget(r, "tcAlarm") == true end
