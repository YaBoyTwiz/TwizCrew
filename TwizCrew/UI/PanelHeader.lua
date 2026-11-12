-- The Crew panel's header: the bar at the top (move handle, title and version, the count, the buttons) and the gold
-- update line and the What's new line under it; drawHeader fits them to the panel's width. Part of the panel
-- (UI/Panel.lua); shared names live on ns.Panel._ (P).
local _, ns = ...

local Panel = ns.Panel
local P = Panel._

local T, Logic = ns.Theme, ns.PanelLogic
local C = T.COLOR
local ROW_WIDTH, HEADER_HEIGHT, PAD = P.ROW_WIDTH, P.HEADER_HEIGHT, P.PAD
local setting, minimized, openMenu, script, draggable = P.setting, P.minimized, P.openMenu, P.script, P.draggable

local UPDATE_HEIGHT = 17 -- the gold "Update available: vX" line under the header
local NEWS_HEIGHT = 18   -- the What's new line under it, always there (bright "New in vX!" until you've read it)

local afkButton -- the "zzz" button in the header: go AFK / come back
local toolsButton -- the wrench in the header: a menu of handy tools (spell ranks, ...)
local calButton   -- the scroll in the header, left of the wrench: the crew calendar
local titleText -- "TwizCrew" in the header
local grip -- the move-arrows handle at the left of the header (dim while the panel is locked)
local versionText, updateBar  -- the version after "TwizCrew"; the gold update line (a button: click = how to update)
local newsBar, versionButton -- "New in vX" line; click the title for What's new
local newsLine
local titleVersion, updateLine = "", nil -- what they show now (for tests)
local gearButton, miniButton, missedButton, noticeButton, updateHintButton
local rootHead
local barTextNow = ""  -- the text on the bar's count spot now (test hook)
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
P.drawAfkButton = drawAfkButton

-- Width of a header text: the game's own measure, else a roomy guess (so a guess never hides an overlap).
local function headerWidth(fs, text)
  local w = fs.GetStringWidth and fs:GetStringWidth()
  if type(w) ~= "number" or w ~= w or w <= 0 then w = #text * 6.5 end
  return w
end

-- What gives way, in order, when the full header is too narrow: the version, the long count ("2 of 3 online" ->
-- "2/3"), then the buttons whose actions are also in the right-click menu: AFK, calendar (the wrench menu), settings.
-- The minimize button, the wrench and the count always stay.
local FIT_STEPS = {
  { version = true, short = false, afk = true, cal = true, gear = true },
  { version = false, short = false, afk = true, cal = true, gear = true },
  { version = false, short = true, afk = true, cal = true, gear = true },
  { version = false, short = true, afk = false, cal = true, gear = true },
  { version = false, short = true, afk = false, cal = false, gear = true },
  { version = false, short = true, afk = false, cal = false, gear = false },
}
local fitNow = {} -- what the last full header kept (test hook)

local function drawHeader(s, view)
  view = view or "full"
  local mini = view ~= "full"
  drawAfkButton()
  if grip then grip:SetAlpha(setting("locked") and 0.3 or 0.9) end
  titleVersion = Logic.titleVersion(s.rowStyle, ns.VERSION)
  versionText:SetText(titleVersion)
  if miniButton then
    miniButton.icon:SetTexture(minimized() and "Interface\\Buttons\\UI-PlusButton-Up"
      or "Interface\\Buttons\\UI-MinusButton-Up")
  end
  -- minimized, a small gold "!" says an update is waiting (the update line itself is hidden then)
  local hintShown = mini and updateText() ~= nil
  if updateHintButton then
    if hintShown then updateHintButton:Show() else updateHintButton:Hide() end
  end
  local missed = mini and P.bar and P.bar.missed or 0
  local missedShown = missed > 0
  if missedButton then
    missedButton:ClearAllPoints()
    missedButton:SetPoint("RIGHT", hintShown and updateHintButton or miniButton, "LEFT", -4, 0)
    if missedShown then
      missedButton.text:SetText(Logic.missedText(missed))
      missedButton:Show()
    else
      missedButton:Hide()
    end
  end
  local notice = mini and P.bar and P.bar:current() or nil
  P.noticeShown = notice
  local noticeLine = notice and ns.Feed and ns.Feed.coloredLine(notice) or nil
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style] + 2 * PAD
  local B = T.icon(16)
  local count = P.header
  local step
  if mini then
    -- the bar alone keeps the title, the count (or the notice), the missed number, the "!" and the minimize button
    for _, b in ipairs({ gearButton, toolsButton, calButton, afkButton }) do if b then b:Hide() end end
    local right = (PAD - 2) + B + 6 + (hintShown and (B + 4) or 0) + (missedShown and (T.icon(18) + 4) or 0) + 6
    local left = (PAD - 2) + B + 4 + headerWidth(titleText, "TwizCrew") + 6
    local function fitsMini(c, withVersion)
      local used = left + right + headerWidth(P.countText, c)
      if withVersion and titleVersion ~= "" then used = used + 4 + headerWidth(versionText, titleVersion) end
      return used <= width
    end
    if noticeLine then
      versionText:Hide() -- the notice needs the room
    elseif fitsMini(P.header, true) then
      versionText:Show()
    else
      versionText:Hide()
      if not fitsMini(P.header, false) and P.headerShort then count = P.headerShort end
    end
    P.countText:ClearAllPoints()
    P.countText:SetPoint("RIGHT", missedShown and missedButton or (hintShown and updateHintButton or miniButton), "LEFT",
      -6, 0)
    if noticeLine then P.countText:SetPoint("LEFT", titleText, "RIGHT", 8, 0) end
  else
    -- the full header: take the first step that fits, measured with the buttons' real size
    local function used(st, c)
      local right = (PAD - 2) + B + 4 + (st.gear and (B + 4) or 0) + B + (st.cal and (4 + B) or 0) + 6
        + headerWidth(P.countText, c) + (st.afk and (6 + B) or 0)
      local left = (PAD - 2) + B + 4 + headerWidth(titleText, "TwizCrew") + 6
        + ((st.version and titleVersion ~= "") and (4 + headerWidth(versionText, titleVersion)) or 0)
      return left + right
    end
    for i, st in ipairs(FIT_STEPS) do
      step = st
      if used(st, st.short and P.headerShort or P.header) <= width or i == #FIT_STEPS then
        fitNow = { step = i, used = used(st, st.short and P.headerShort or P.header), width = width }
        break
      end
    end
    count = step.short and P.headerShort or P.header
    if step.version and titleVersion ~= "" then versionText:Show() else versionText:Hide() end
    local function vis(b, on) if b then if on then b:Show() else b:Hide() end end end
    vis(gearButton, step.gear); vis(calButton, step.cal); vis(afkButton, step.afk); vis(toolsButton, true)
    fitNow.afk, fitNow.cal, fitNow.gear = step.afk, step.cal, step.gear
    -- the chain from the right: minimize, settings, wrench, calendar, count, AFK (a hidden one is skipped)
    toolsButton:ClearAllPoints()
    toolsButton:SetPoint("RIGHT", step.gear and gearButton or miniButton, "LEFT", -4, 0)
    calButton:ClearAllPoints()
    calButton:SetPoint("RIGHT", toolsButton, "LEFT", -4, 0)
    P.countText:ClearAllPoints()
    P.countText:SetPoint("RIGHT", step.cal and calButton or toolsButton, "LEFT", -6, 0)
  end
  -- the title's click area ends where the title or its version ends, so it never reaches the notice or the count
  if versionButton then
    versionButton:ClearAllPoints()
    versionButton:SetPoint("TOPLEFT", titleText, "TOPLEFT", -2, 3)
    local last = versionText:IsShown() and versionText or titleText
    versionButton:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 2, -3)
  end
  if P.countText.SetJustifyH then P.countText:SetJustifyH("RIGHT") end
  if P.countText.SetWordWrap then P.countText:SetWordWrap(false) end
  T.textColor(P.countText, noticeLine and C.text or C.muted)
  barTextNow = Logic.barText(noticeLine, count)
  P.countText:SetText(barTextNow)
  if noticeButton then
    if noticeLine then
      noticeButton:ClearAllPoints()
      noticeButton:SetPoint("TOPLEFT", P.countText, "TOPLEFT", 0, 3)
      noticeButton:SetPoint("BOTTOMRIGHT", P.countText, "BOTTOMRIGHT", 3, -3)
      noticeButton:Show()
    else
      noticeButton:Hide()
    end
  end
  local top = HEADER_HEIGHT
  if mini then
    updateLine, newsLine = nil, nil
    updateBar:Hide()
    newsBar:Hide()
    if P.tabBar then P.tabBar:Hide() end
    return top
  end
  updateLine = updateText()
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
    newsBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 2, -(top - 2))
    newsBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", -2, -(top - 2))
    newsBar.text:SetText(newsLine)
    newsBar.text:SetTextColor(T.rgb(fresh and "8fd0ff" or "c8c8c8"))
    newsBar.glow:SetAlpha(fresh and 1 or 0.45)
    newsBar:Show()
    top = top + NEWS_HEIGHT
  else
    newsBar:Hide()
  end
  if P.tabBar then
    P.tabBar:ClearAllPoints()
    P.tabBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 0, -(top - 2))
    P.tabBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", 0, -(top - 2))
  end
  return top
end
P.drawHeader = drawHeader

---------------------------------------------------------------------------------------------------------- build
-- The header bar and its buttons, then the update line and the What's new line (called by build).
function P.buildHeader()
  local head = CreateFrame("Frame", nil, P.root)
  rootHead = head
  head:SetPoint("TOPLEFT", P.root, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", 0, 0)
  head:SetHeight(HEADER_HEIGHT)
  draggable(head)
  script(head, "OnMouseUp", function(self, button)
    if button == "RightButton" then openMenu(self, Panel.menuItems()) end
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
  script(versionButton, "OnMouseUp", function(_, button)
    if button == "RightButton" then openMenu(head, Panel.menuItems()) end
  end)
  -- (minimized, the title brings the panel back instead: the What's new line is hidden then)
  script(versionButton, "OnClick", function()
    if minimized() then Panel.toggleMinimized() elseif ns.Changelog then ns.Changelog.toggle() end
  end)
  script(versionButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("TwizCrew v" .. tostring(ns.VERSION))
    GameTooltip:AddLine(minimized() and "Click to bring the whole panel back" or "Click to see what's new in each version",
      1, 1, 1)
    GameTooltip:Show()
  end)
  script(versionButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- a soft glow over the bar that flashes when a notice arrives while minimized
  P.flashTex = head:CreateTexture(nil, "BACKGROUND")
  P.flashTex:SetAllPoints(head)
  T.color(P.flashTex, C.title, 1)
  P.flashTex:SetAlpha(0)
  -- the minimize button, at the far right of the bar: minus = minimize, plus = restore
  miniButton = CreateFrame("Button", nil, head)
  miniButton:SetSize(T.icon(16), T.icon(16))
  miniButton:SetPoint("RIGHT", head, "RIGHT", -PAD + 2, -2)
  miniButton.icon = miniButton:CreateTexture(nil, "ARTWORK")
  miniButton.icon:SetAllPoints(miniButton)
  miniButton.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
  local miniHl = miniButton:CreateTexture(nil, "HIGHLIGHT")
  miniHl:SetAllPoints(miniButton)
  T.color(miniHl, C.white, 0.25)
  script(miniButton, "OnClick", function() Panel.toggleMinimized() end)
  script(miniButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(Logic.miniLabel(minimized()))
    GameTooltip:AddLine(minimized() and "Click to bring the whole panel back (or /tc mini)."
      or "Click to shrink the panel to just this bar (or /tc mini). It tells you about news on the bar.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(miniButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- a small gold "!" while minimized and an update is waiting: click = how to update
  updateHintButton = CreateFrame("Button", nil, head)
  updateHintButton:SetSize(T.icon(12), T.icon(16))
  updateHintButton:SetPoint("RIGHT", miniButton, "LEFT", -4, 0)
  updateHintButton.text = T.readable(T.text(updateHintButton, T.FONT.normal, C.title))
  updateHintButton.text:SetPoint("CENTER", updateHintButton, "CENTER", 0, 0)
  updateHintButton.text:SetText("!")
  script(updateHintButton, "OnClick", function() ns.Log.safe("updates", ns.Updates.showHowTo) end)
  script(updateHintButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("An update is waiting", T.rgb(C.title))
    GameTooltip:AddLine("Click for how to update. The update line is hidden while the panel is minimized.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(updateHintButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  updateHintButton:Hide()
  -- the number of news items missed while minimized: click = the recent activity list
  missedButton = CreateFrame("Button", nil, head)
  missedButton:SetSize(T.icon(18), T.icon(14))
  missedButton:SetPoint("RIGHT", miniButton, "LEFT", -4, 0)
  missedButton.bg = missedButton:CreateTexture(nil, "BACKGROUND")
  missedButton.bg:SetAllPoints(missedButton)
  T.color(missedButton.bg, "b3261e", 0.9)
  missedButton.text = T.readable(T.text(missedButton, T.FONT.small, C.white))
  missedButton.text:SetPoint("CENTER", missedButton, "CENTER", 0, 0)
  local missedHl = missedButton:CreateTexture(nil, "HIGHLIGHT")
  missedHl:SetAllPoints(missedButton)
  T.color(missedHl, C.white, 0.25)
  script(missedButton, "OnClick", function() Panel.missedClicked() end)
  script(missedButton, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Missed while minimized")
    GameTooltip:AddLine("Click to see what happened (or /tc recent). Opening the panel clears this number.", 1, 1, 1,
      true)
    GameTooltip:Show()
  end)
  script(missedButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  missedButton:Hide()
  local gear = CreateFrame("Button", nil, head)
  gearButton = gear
  gear:SetSize(T.icon(16), T.icon(16))
  gear:SetPoint("RIGHT", miniButton, "LEFT", -4, 0)
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
  P.countText = T.text(head, T.FONT.small, C.muted)
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
  script(toolsButton, "OnClick", function(self) openMenu(self, Panel.toolItems()) end)
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
  P.countText:SetPoint("RIGHT", calButton, "LEFT", -6, 0)
  afkButton = CreateFrame("Button", nil, head)
  afkButton:SetSize(T.icon(16), T.icon(16))
  afkButton:SetPoint("RIGHT", P.countText, "LEFT", -6, 0)
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
  -- the news on a minimized bar: click = what clicking that pop-up would do (congratulate, whisper)
  noticeButton = CreateFrame("Button", nil, head)
  draggable(noticeButton)
  script(noticeButton, "OnClick", function() Panel.noticeClicked() end)
  script(noticeButton, "OnMouseUp", function(self, button) -- the bar's options still open from the notice
    if button == "RightButton" then openMenu(head, Panel.menuItems()) end
  end)
  script(noticeButton, "OnEnter", function(self)
    if not GameTooltip or not P.noticeShown then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(P.noticeShown.kind == "levelup" and "Click to congratulate them"
      or P.noticeShown.kind == "online" and "Click to whisper them" or "Click to open the recent activity list")
    GameTooltip:Show()
  end)
  script(noticeButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  noticeButton:Hide()

  updateBar = CreateFrame("Button", nil, P.root)
  if updateBar.SetIgnoreParentAlpha then updateBar:SetIgnoreParentAlpha(true) end -- important: never faded
  updateBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 2, -(HEADER_HEIGHT - 2))
  updateBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", -2, -(HEADER_HEIGHT - 2))
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

  newsBar = CreateFrame("Button", nil, P.root)
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
end

---------------------------------------------------------------------------------------------------------- test hooks
function Panel.toolsButtonForTest() return toolsButton end
function Panel.calendarButtonForTest() return calButton end
function Panel.newsLineForTest() return newsLine end
function Panel.titleVersionForTest() return titleVersion end
function Panel.updateLineForTest() return updateLine end
function Panel.updateLineButtonForTest() return updateBar end
function Panel.barTextForTest() return barTextNow end
function Panel.titleButtonForTest() return versionButton end
function Panel.headerFitForTest() return fitNow end
function Panel.headerButtonsForTest()
  return { mini = miniButton, gear = gearButton, tools = toolsButton, cal = calButton, afk = afkButton,
    hint = updateHintButton, title = versionButton, notice = noticeButton, head = rootHead }
end
function Panel.miniButtonForTest() return miniButton end
function Panel.missedButtonForTest() return missedButton end
function Panel.noticeButtonForTest() return noticeButton end
