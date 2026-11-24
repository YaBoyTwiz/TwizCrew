-- The Crew panel's header: the bar at the top (move handle, title and version, the count, the buttons), the Keep
-- open switch under it, then the gold update line and the What's new line; drawHeader fits them to the panel's
-- width. While one piece of news is slid out of the crew tab, the header is the title and the news line alone.
-- Part of the panel (UI/Panel.lua); shared names live on ns.Panel._ (P).
local _, ns = ...

local Panel = ns.Panel
local P = Panel._

local T, Logic = ns.Theme, ns.PanelLogic
local C = T.COLOR
local ROW_WIDTH, HEADER_HEIGHT, PAD = P.ROW_WIDTH, P.HEADER_HEIGHT, P.PAD
local setting, keepOpen, openMenu, script, draggable = P.setting, P.keepOpen, P.openMenu, P.script, P.draggable

local KEEP_HEIGHT = 20   -- the Keep open switch right under the header
local UPDATE_HEIGHT = 17 -- the gold "Update available: vX" line under it
local NEWS_HEIGHT = 18   -- the "New in vX!" line under it, only until the What's new window has been opened
local NEWS_ICON, NEWS_ICON_GAP = 16, 4 -- the icon left of the news line while news is slid out

local afkButton -- the "zzz" button in the header: go AFK / come back
local toolsButton -- the wrench in the header: a menu of handy tools (spell ranks, ...)
local titleText -- "TwizCrew" in the header
local grip -- the move-arrows handle at the left of the header (dim while the panel is locked)
local versionText, updateBar  -- the version after "TwizCrew"; the gold update line (a button: click = how to update)
local newsBar, versionButton -- "New in vX" line; click the title for What's new
local newsLine
local titleVersion, updateLine = "", nil -- what they show now (for tests)
local gearButton, noticeButton
local keepBar -- the Keep open switch: "Keep open: OFF" (dim) / "Keep open: ON" (lit)
local keepTextNow -- what it says now (test hook)
local countButton -- a hover area over the count ("2 here · 9 online"): what the two numbers mean
local rootHead
local newsIcon -- the news's icon left of the news line (tab slid out)
local barTextNow = ""  -- the text on the bar's count spot now (test hook)
---------------------------------------------------------------------------------------------------------- update
-- "Update available: vX" or nil, worked out inside Remind me to update' own guard: an error there means "no line",
-- never a broken panel.
local function updateText()
  if not ns.Updates or not ns.Updates.available then return nil end
  local ok, text = ns.Log.safe("updates", function()
    return ns.UpdateLogic.availableText(ns.Updates.available())
  end)
  if ok and type(text) == "string" then return ns.Util.safeText(text) end
  return nil
end
P.updateText = updateText

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

-- What gives way, in order, when the full header is too narrow: the version, the long count ("2 here · 3 online" ->
-- "2/3"), then the buttons whose actions are also in the right-click menu: AFK, settings.
-- The wrench and the count always stay. (The calendar has its own button next to the tabs.)
local FIT_STEPS = {
  { version = true, short = false, afk = true, gear = true },
  { version = false, short = false, afk = true, gear = true },
  { version = false, short = true, afk = true, gear = true },
  { version = false, short = true, afk = false, gear = true },
  { version = false, short = true, afk = false, gear = false },
}
local fitNow = {} -- what the last full header kept (test hook)

-- view: "full" or "peek" (one piece of news, `news`, slid out of the crew tab).
local function drawHeader(s, view, news)
  view = view or "full"
  local mini = view ~= "full"
  drawAfkButton()
  if grip then grip:SetAlpha((setting("locked") or not keepOpen()) and 0.3 or 0.9) end
  titleVersion = Logic.titleVersion(s.rowStyle, ns.VERSION)
  versionText:SetText(titleVersion)
  local notice = mini and news or nil
  P.noticeShown = notice
  local noticeLine = notice and ns.Feed and ns.Feed.coloredLine(notice) or nil
  local style = ROW_WIDTH[s.rowStyle] and s.rowStyle or "full"
  local width = ROW_WIDTH[style] + 2 * PAD
  local B = T.icon(16)
  local count = P.header
  local step
  if mini then
    -- one piece of news: the title and the news line (the count when there is no line)
    for _, b in ipairs({ gearButton, toolsButton, afkButton }) do if b then b:Hide() end end
    versionText:Hide()
    P.countText:ClearAllPoints()
    P.countText:SetPoint("RIGHT", rootHead, "RIGHT", -(PAD - 2), 0)
    -- the news's icon left of its line (the atlas; none for layer news, or when the atlas did not load)
    local icon = noticeLine and newsIcon and ns.Icons.news(notice.kind)
    if icon and ns.Icons.set(newsIcon, icon) == "atlas" then
      newsIcon:ClearAllPoints()
      newsIcon:SetPoint("LEFT", titleText, "RIGHT", 8, 0)
      P.countText:SetPoint("LEFT", newsIcon, "RIGHT", NEWS_ICON_GAP, 0)
    else
      if newsIcon then newsIcon:Hide() end
      if noticeLine then P.countText:SetPoint("LEFT", titleText, "RIGHT", 8, 0) end
    end
  else
    if newsIcon then newsIcon:Hide() end
    -- the full header: take the first step that fits, measured with the buttons' real size
    local function used(st, c)
      local right = (PAD - 2) + (st.gear and (B + 4) or 0) + B + 6
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
    vis(gearButton, step.gear); vis(afkButton, step.afk); vis(toolsButton, true)
    fitNow.afk, fitNow.gear = step.afk, step.gear
    -- the chain from the right: settings, wrench, count, AFK (a hidden one is skipped)
    toolsButton:ClearAllPoints()
    if step.gear then
      toolsButton:SetPoint("RIGHT", gearButton, "LEFT", -4, 0)
    else
      toolsButton:SetPoint("RIGHT", rootHead, "RIGHT", -PAD + 2, -2)
    end
    P.countText:ClearAllPoints()
    P.countText:SetPoint("RIGHT", toolsButton, "LEFT", -6, 0)
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
  local countRole = noticeLine and "news" or "count" -- (the look's header colours; a repaint re-inks it)
  if P.countText.tcRole ~= countRole then T.ink(P.countText, countRole) end
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
  if countButton then
    if noticeLine then
      countButton:Hide()
    else
      countButton:ClearAllPoints()
      countButton:SetPoint("TOPLEFT", P.countText, "TOPLEFT", -2, 3)
      countButton:SetPoint("BOTTOMRIGHT", P.countText, "BOTTOMRIGHT", 2, -3)
      countButton:Show()
    end
  end
  local top = HEADER_HEIGHT
  if mini then
    updateLine, newsLine, keepTextNow = nil, nil, nil
    keepBar:Hide()
    updateBar:Hide()
    newsBar:Hide()
    if P.tabBar then P.tabBar:Hide() end
    return top
  end
  -- Keep open: a wide switch, easy to see and to hit, in both modes (owner: "extremely easy and visible")
  local kept = keepOpen()
  keepTextNow = Logic.keepSwitchText(kept, style)
  keepBar.text:SetText(keepTextNow)
  T.setKeep(keepBar, kept) -- the look's switch, lit while on (UI/Skin.lua)
  keepBar:ClearAllPoints()
  keepBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 2, -(top - 2))
  keepBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", -2, -(top - 2))
  keepBar:Show()
  top = top + KEEP_HEIGHT
  updateLine = updateText()
  if updateLine then
    updateBar.text:SetText(updateLine)
    updateBar:ClearAllPoints()
    updateBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 2, -(top - 2))
    updateBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", -2, -(top - 2))
    updateBar:Show()
    top = top + UPDATE_HEIGHT
  else
    updateBar:Hide()
  end
  -- What's new: only while there is something new (owner, 2026-11-23: no longer always there); a click on the title,
  -- the wrench menu and /tc new open it any time.
  newsLine = nil
  if ns.Changelog and ns.Changelog.unseen() then
    local ver = "v" .. ns.Util.safeText(tostring(ns.VERSION))
    newsLine = s.rowStyle == "tiny" and ("New in " .. ver .. "!") or ("New in " .. ver .. "! Click to see what changed")
    newsBar:ClearAllPoints()
    newsBar:SetPoint("TOPLEFT", P.root, "TOPLEFT", 2, -(top - 2))
    newsBar:SetPoint("TOPRIGHT", P.root, "TOPRIGHT", -2, -(top - 2))
    newsBar.text:SetText(newsLine)
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
    local movable = not locked and keepOpen()
    if movable and type(SetCursor) == "function" then pcall(SetCursor, "Interface\\CURSOR\\UI-Cursor-Move") end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("TwizCrew")
    if not keepOpen() then
      GameTooltip:AddLine("Tucked into its tab: drag the tab to move it", 1, 1, 1)
    else
      GameTooltip:AddLine(locked and "Locked in place (unlock it with the right-click menu)" or "Drag to move", 1, 1, 1)
    end
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
  T.ink(title, "title") -- the look's title colour and font
  newsIcon = head:CreateTexture(nil, "ARTWORK")
  newsIcon:SetSize(NEWS_ICON, NEWS_ICON)
  newsIcon:Hide()
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
  gearButton = gear
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
  P.countText:SetPoint("RIGHT", toolsButton, "LEFT", -6, 0)
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
  -- the news line while news is slid out of the tab: click = what clicking that pop-up would do (congratulate,
  -- whisper, open the calendar)
  noticeButton = CreateFrame("Button", nil, head)
  draggable(noticeButton)
  script(noticeButton, "OnClick", function() Panel.noticeClicked() end)
  script(noticeButton, "OnMouseUp", function(self, button) -- the bar's options still open from the notice
    if button == "RightButton" then openMenu(head, Panel.menuItems()) end
  end)
  script(noticeButton, "OnEnter", function(self)
    if not GameTooltip or not P.noticeShown then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Logic.noticeClickText(P.noticeShown.kind))
    GameTooltip:Show()
  end)
  script(noticeButton, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  noticeButton:Hide()
  -- the count: dragging it still moves the panel, right-click is the bar's menu, hovering explains the numbers
  countButton = CreateFrame("Frame", nil, head)
  draggable(countButton)
  script(countButton, "OnMouseUp", function(_, button)
    if button == "RightButton" then openMenu(head, Panel.menuItems()) end
  end)
  ns.Widgets.helpTip(countButton, "count", "panel", "ANCHOR_BOTTOM")

  -- the Keep open switch: a wide button right under the header, lit while on (owner: "extremely easy and visible")
  keepBar = CreateFrame("Button", nil, P.root)
  keepBar:SetHeight(KEEP_HEIGHT)
  keepBar.glow = keepBar:CreateTexture(nil, "ARTWORK")
  keepBar.glow:SetPoint("TOPLEFT", keepBar, "TOPLEFT", 1, -1)
  keepBar.glow:SetPoint("BOTTOMRIGHT", keepBar, "BOTTOMRIGHT", -1, 1)
  T.color(keepBar.glow, C.title, 1)
  keepBar.glow:SetAlpha(0.06)
  local keepHl = keepBar:CreateTexture(nil, "HIGHLIGHT")
  keepHl:SetAllPoints(keepBar)
  T.color(keepHl, C.white, 0.15)
  keepBar.text = T.readable(T.text(keepBar, T.FONT.normal, C.muted))
  keepBar.text:SetPoint("CENTER", keepBar, "CENTER", 6, 0)
  keepBar.dot = keepBar:CreateTexture(nil, "OVERLAY") -- a check mark before the words, lit while on
  keepBar.dot:SetSize(T.icon(14), T.icon(14))
  keepBar.dot:SetPoint("RIGHT", keepBar.text, "LEFT", -4, 0)
  keepBar.dot:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  T.skinKeep(keepBar)
  script(keepBar, "OnClick", function() Panel.toggleKeepOpen() end)
  ns.Widgets.helpTip(keepBar, "keepOpen", "panel", "ANCHOR_TOP")
  keepBar:Hide()

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
    GameTooltip:SetOwner(self, P.sideAnchor())
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
    GameTooltip:SetOwner(self, P.sideAnchor())
    GameTooltip:SetText("What's new", T.rgb("8fd0ff"))
    GameTooltip:AddLine("Click to see every TwizCrew version and what changed (or type /tc new).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  script(newsBar, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  newsBar:Hide()
end

---------------------------------------------------------------------------------------------------------- test hooks
function Panel.toolsButtonForTest() return toolsButton end
function Panel.newsLineForTest() return newsLine end
function Panel.titleVersionForTest() return titleVersion end
function Panel.updateLineForTest() return updateLine end
function Panel.updateLineButtonForTest() return updateBar end
function Panel.barTextForTest() return barTextNow end
function Panel.titleButtonForTest() return versionButton end
function Panel.headerFitForTest() return fitNow end
function Panel.headerButtonsForTest()
  return { keep = keepBar, gear = gearButton, tools = toolsButton, afk = afkButton,
    title = versionButton, notice = noticeButton, head = rootHead }
end
function Panel.keepSwitchForTest() return keepBar end
function Panel.keepTextForTest() return keepTextNow end
function Panel.noticeButtonForTest() return noticeButton end
function Panel.newsIconForTest() return newsIcon end
function Panel.countButtonForTest() return countButton end
