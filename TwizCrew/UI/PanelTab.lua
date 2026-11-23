-- The crew tab (2026-11-23): unless "Keep open" is on, the Crew panel is tucked away into a small tab on the left or
-- right edge of the screen ("CREW" and how many friends are here). Resting the mouse on the tab (or a click) slides
-- the whole panel out of it; it slides back about a second after the mouse has left the tab, the panel and their
-- menus. News (someone comes online, dies, levels up, changes layer, runs off, a new calendar note, a congrats or mock
-- for me) slides out one piece at a time: the header line and that friend's row, then back. The tab glows and counts
-- what was missed, carries the gold "!" of a waiting update and small marks while someone close is DEAD or on OTHER
-- LAYER. It can be dragged up and down its edge and across to the other edge.
-- The slide: the panel frame is the child of a holder (TwizCrewPanelHolder) that clips its children; the panel is laid
-- out once and only the holder's width changes, eased over SLIDE_SECONDS by an OnUpdate (the 0.1 s ticker finishes a
-- slide too, so tests that advance time see it end). Without SetClipsChildren (older clients) it shows at once.
-- Part of the panel (UI/Panel.lua); shared names live on ns.Panel._ (P).
local _, ns = ...

local Panel = ns.Panel
local P = Panel._

local FEATURE = "panel"
local T, Logic, FL = ns.Theme, ns.PanelLogic, ns.FeedLogic
local C = T.COLOR
local setting, set, keepOpen, clamp = P.setting, P.set, P.keepOpen, P.clamp
local requestRedraw, openMenu, script = P.requestRedraw, P.openMenu, P.script

local TAB_WIDTH, TAB_HEIGHT = 24, 86
P.TAB_HEIGHT = TAB_HEIGHT
local SLIDE_SECONDS = 0.18 -- the slide out and back
local HOVER_DELAY = 0.3    -- the mouse rests on the tab this long before the panel slides out
local CLOSE_AFTER = 1      -- the panel slides back this long after the mouse left the tab, the panel and their menus
local LEAVE_GRACE = 0.6    -- slid-out news stays this long after the mouse leaves it
local CLICK_KEEPS = 1      -- a click this soon after a hover-open keeps the panel out (it does not close it)
local NOTE_MIN = 6         -- opened from the one-time note's pop-up: out at least this long unless the mouse came by
local FLASH_SECONDS, BAR_TICK = 1.6, 0.1
local GLOW = 0.35          -- the tab's steady glow while there is unseen news
local SEE_RISE, SEE_FALL, SEE_DELAY = 0.2, 0.4, 1 -- see-through: to solid in 0.2 s; to idle 1 s after the last reason, in 0.4 s
local DEAD_COLOR = "ff3030"
local LAYER_COLOR = ns.Tags.COLOR.LAYER

local tab, holder           -- the tab and the holder the panel slides out of
local clips = false         -- the holder clips its children (SetClipsChildren exists)
local holderW = 0           -- the holder's width now
local barTicker, lastTickAt
local hoverSince            -- when the mouse came to rest on the tab
local hoverBlocked = false  -- a click closed the panel, or a right-click: no hover-open until the mouse leaves the tab
local tabHover = false      -- the tab's OnEnter ran and the mouse has not been seen leaving
local newsHeld = false      -- the mouse is on the slid-out news
local flashAt               -- when the last news was counted (the tab flashes)
local dragging, dragEndAt = false, nil
local lastLayer = {}        -- name -> "different" once "on another layer" was said (until "back on your layer")
local quietUntil          -- no layer or calendar news while logging in (set once, when the panel first starts listening)
local loadedAt               -- (no after-fight news in the first seconds after login; same moment)
local AFTER_FIGHT = 3       -- seconds after a fight ends before its news slides out
local FIGHT_MAX = 20        -- news kept from a fight at most
local fightNews = {}        -- copies of the news that came in a fight (in scope), oldest first, until it is shown
local fightWait = 0         -- counts the fights' ends: only the last one's wait acts
local seeCur, seeTarget      -- the alpha now and the one it is fading toward (nil until first set)
local seeAt                  -- time of the last fade step (nil while settled)
local lastSolidAt            -- when something last wanted the tab / panel solid
local seeFrame               -- frame whose OnUpdate runs the fade smoothly, only while it is fading
P.slide = nil               -- { from, to, t0 } while the holder slides

---------------------------------------------------------------------------------------------------------- mouse
local function over(frame)
  if not frame then return false end
  if frame.IsMouseOver then
    local ok, yes = pcall(frame.IsMouseOver, frame)
    return ok and yes == true
  elseif type(MouseIsOver) == "function" then
    local ok, yes = pcall(MouseIsOver, frame)
    return ok and yes == true
  end
  return false
end

local function shownNow(f) return f ~= nil and f:IsShown() == true end

-- The frames the game says the mouse is on (GetMouseFoci on newer clients, GetMouseFocus on older ones), or nil when
-- it cannot tell (then the mouse position alone decides).
local function focusFrames()
  if type(GetMouseFoci) == "function" then
    local ok, list = pcall(GetMouseFoci)
    if ok and type(list) == "table" then return list end
  end
  if type(GetMouseFocus) == "function" then
    local ok, f = pcall(GetMouseFocus)
    if ok and f ~= nil then return { f } end
  end
  return nil
end

-- Is the mouse focus `frame` or one of its children? (Bags or action bars lying over the tab or the panel have the
-- mouse then, not us.) True when the game cannot tell.
local function focusOn(frame)
  local list = focusFrames()
  if not list then return true end
  for _, f in ipairs(list) do
    for _ = 1, 30 do -- (up the parents; a guard against a loop)
      if type(f) ~= "table" then break end
      if f == frame then return true end
      if type(f.GetParent) ~= "function" then break end
      local ok, parent = pcall(f.GetParent, f)
      if not ok then break end
      f = parent
    end
  end
  return false
end

-- Is the mouse on the panel (or on one of our menus, which hang off it or the tab)? Tucked, only while it is out.
local function mouseOverPanel()
  if not P.root then return false end
  local out = keepOpen() or shownNow(holder)
  if out and shownNow(P.root) and over(P.root) and focusOn(P.root) then return true end
  -- an open menu counts only when it was opened from the panel or the tab
  local menu = ns.Widgets.menuFrame and ns.Widgets.menuFrame() or nil
  if menu and P.menuAnchor and menu.IsShown then
    local ok, shown = pcall(menu.IsShown, menu)
    if not (ok and shown == true) then return false end
    local got, _, rel = pcall(menu.GetPoint, menu, 1)
    if got and rel ~= nil then return rel == P.menuAnchor end
    return true -- cannot tell which frame it hangs from
  end
  return false
end
P.mouseOverPanel = mouseOverPanel

-- Is the tab's own right-click menu open? (Its full-screen catcher takes the mouse, so the mouse is "off" the tab.)
local function tabMenuOpen()
  local menu = ns.Widgets.menuFrame and ns.Widgets.menuFrame() or nil
  if not menu or not tab or P.menuAnchor ~= tab or not menu.IsShown then return false end
  local ok, shown = pcall(menu.IsShown, menu)
  return ok and shown == true
end

local function mouseOverTab()
  if not shownNow(tab) then return false end
  return (over(tab) or (shownNow(tab.badge) and over(tab.badge))) and focusOn(tab) -- (the red number hangs off it)
end

-- The player is turning the camera or holding a mouse button (guarded: not every client has these).
local function busyMouse()
  if type(IsMouselooking) == "function" and ns.Util.plain(IsMouselooking) then return true end
  if type(IsMouseButtonDown) == "function" then
    if ns.Util.plain(IsMouseButtonDown, "LeftButton") or ns.Util.plain(IsMouseButtonDown, "RightButton") then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------------------------------------- slide
local function setHolderWidth(w)
  holderW = math.max(0, w)
  holder:SetWidth(math.max(1, holderW))
end

local stopSlideScript
local function stepSlide(now)
  local s = P.slide
  if not s then return end
  local w, done = Logic.slideWidth(s.from, s.to, s.t0, SLIDE_SECONDS, now)
  setHolderWidth(w)
  if done then
    P.slide = nil
    stopSlideScript()
    if s.to <= 0 then
      holder:Hide()
      requestRedraw() -- now that it is in: lay the full panel out behind the closed holder
    end
  end
end

local slideWaited = 0
local function slideUpdate(_, elapsed)
  slideWaited = slideWaited + (tonumber(elapsed) or 0)
  if slideWaited < 0.01 then return end
  slideWaited = 0
  ns.Log.safe(FEATURE, stepSlide, ns.now())
end
stopSlideScript = function() if holder then holder:SetScript("OnUpdate", nil) end end

local startBarTicker -- (below)
local wakeSee -- (below)

-- Slide the holder to `target` wide (0 = in, hidden at the end).
function P.slideTo(target)
  if not holder then return end
  target = math.max(0, tonumber(target) or 0)
  if target > 0 and not holder:IsShown() then setHolderWidth(0); holder:Show() end
  if not clips then -- no clipping in this client: at once
    P.slide = nil
    setHolderWidth(target)
    if target <= 0 then holder:Hide() end
    return
  end
  if P.slide then
    if P.slide.to == target then return end
  elseif holderW == target then
    if target <= 0 then holder:Hide() end
    return
  end
  P.slide = { from = holderW, to = target, t0 = ns.now() }
  slideWaited = 0
  holder:SetScript("OnUpdate", slideUpdate)
  startBarTicker()
end

-- The holder is out (or sliding back in).
function P.clipOut() return shownNow(holder) end

-- After a redraw: the holder takes the panel's height (and, while it is out, slides to the panel's width).
function P.fitClip()
  if not holder or keepOpen() or not P.root then return end
  local scale = P.appliedScale()
  local w, h = (tonumber(P.rootW) or 0) * scale, (tonumber(P.rootH) or 0) * scale
  holder:SetHeight(math.max(1, h))
  if P.curView ~= "tab" and P.shown then P.slideTo(w) end
end

---------------------------------------------------------------------------------------------------------- the tab
-- The tab's look: the count, the glow and missed number, the "!" and the marks.
local function drawTab(now)
  if not tab then return end
  tab.count:SetText(Logic.tabCount(P.here))
  local missed = P.bar and P.bar.missed or 0
  local a = missed > 0 and GLOW or 0
  if flashAt and now then
    local age = now - flashAt
    if age >= 0 and age < FLASH_SECONDS then a = math.max(a, GLOW + 0.5 * (1 - age / FLASH_SECONDS)) end
  end
  tab.glow:SetAlpha(a)
  tab.tcGlow = a
  if missed > 0 then
    tab.badge.text:SetText(Logic.missedText(missed))
    tab.badge:Show()
  else
    tab.badge:Hide()
  end
  local up = P.updateText and P.updateText() ~= nil
  if up then tab.hint:Show() else tab.hint:Hide() end
  tab.tcHint = up and true or false
  local marks = P.marks or {}
  if marks.dead then tab.dead:Show() else tab.dead:Hide() end
  if marks.layer then tab.layer:Show() else tab.layer:Hide() end
end

-- Places the tab on its edge and hangs the holder and the panel from it.
function P.placeTab()
  if not tab or dragging then return end
  local right = setting("tabSide") == "right"
  local okH, h = pcall(UIParent.GetHeight, UIParent)
  local scale = P.appliedScale()
  local y = Logic.clampTabY(setting("tabY"), okH and h or nil, TAB_HEIGHT, scale)
  local edge = right and "RIGHT" or "LEFT"
  tab:ClearAllPoints()
  tab:SetPoint(edge, UIParent, edge, 0, y)
  holder:ClearAllPoints()
  if right then holder:SetPoint("TOPRIGHT", tab, "TOPLEFT", 0, 0) else holder:SetPoint("TOPLEFT", tab, "TOPRIGHT", 0, 0) end
  -- the badge, the "!" and the marks sit on the side away from the edge
  local out, outPoint = right and "LEFT" or "RIGHT", right and "TOPLEFT" or "TOPRIGHT"
  local dx = right and -1 or 1
  tab.badge:ClearAllPoints()
  tab.badge:SetPoint("CENTER", tab, outPoint, dx * 2, 2)
  tab.hint:ClearAllPoints()
  tab.hint:SetPoint("CENTER", tab, right and "BOTTOMLEFT" or "BOTTOMRIGHT", dx * 2, 6)
  tab.dead:ClearAllPoints()
  tab.dead:SetPoint("CENTER", tab, out, dx * 2, 8)
  tab.layer:ClearAllPoints()
  tab.layer:SetPoint("CENTER", tab, out, dx * 2, -8)
  if P.root and not keepOpen() then
    P.root:ClearAllPoints()
    if right then P.root:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    else P.root:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0) end
  end
end

function P.showTab(on)
  if not tab then return end
  if on then
    tab:Show()
    drawTab(ns.now())
  else
    tab:Hide()
  end
end

function P.hideTab()
  if tab then tab:Hide() end
  if holder then
    P.slide = nil
    stopSlideScript()
    setHolderWidth(0)
    holder:Hide()
  end
end

-- Keep open or tucked: who the panel frame belongs to.
function P.applyMode()
  if not P.root or not holder then return end
  if keepOpen() then
    P.root:SetParent(UIParent)
    if P.root.SetClampedToScreen then P.root:SetClampedToScreen(true) end
    P.hideTab()
  else
    P.root:SetParent(holder)
    -- the holder keeps it on screen: the panel itself must be free to sit beside the tab while the holder is narrow
    if P.root.SetClampedToScreen then P.root:SetClampedToScreen(false) end
  end
  P.root:SetFrameStrata("MEDIUM")
  P.applyPosition()
end

local function tabTip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, setting("tabSide") == "right" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
  local title, text = ns.Help.tip("crewTab")
  GameTooltip:SetText(title, T.rgb(C.title))
  GameTooltip:AddLine(text, 1, 1, 1, true)
  GameTooltip:AddLine(Logic.tabCount(P.here) .. " here: you, plus your party and pinned friends who are online",
    T.rgb(C.muted))
  local missed = P.bar and P.bar.missed or 0
  if missed > 0 then
    GameTooltip:AddLine(missed == 1 and "1 thing happened since you last looked" or
      (missed .. " things happened since you last looked"), T.rgb(C.title))
  end
  if P.marks and P.marks.dead then GameTooltip:AddLine("Someone in your party or pinned is dead", T.rgb(DEAD_COLOR)) end
  if P.marks and P.marks.layer then
    GameTooltip:AddLine("Someone in your party or pinned is on another layer", T.rgb(LAYER_COLOR))
  end
  if P.updateText and P.updateText() then GameTooltip:AddLine("An update is waiting (see the panel)", T.rgb(C.title)) end
  GameTooltip:AddLine(setting("locked") and "Right-click for options (locked in place)"
    or "Drag to move it along the edge. Right-click for options.", T.rgb(C.muted))
  GameTooltip:Show()
end

local function dragStart(self)
  if setting("locked") or not self.StartMoving then return end
  dragging = true
  self:StartMoving()
  startBarTicker()
end

local function dragStop(self)
  if not dragging then return end
  dragging = false
  dragEndAt = ns.now()
  if self.StopMovingOrSizing then self:StopMovingOrSizing() end
  if self.SetUserPlaced then self:SetUserPlaced(false) end
  local okC, cx, cy = pcall(self.GetCenter, self)
  local okW, w = pcall(UIParent.GetWidth, UIParent)
  local okH, h = pcall(UIParent.GetHeight, UIParent)
  local s = self.GetEffectiveScale and self:GetEffectiveScale() or 1
  local u = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  local side, y
  if okC and okW and okH and type(cx) == "number" and type(cy) == "number" and type(s) == "number"
    and type(u) == "number" and u > 0 then
    side, y = Logic.tabSnap(cx * s / u, cy * s / u, w, h, TAB_HEIGHT, P.appliedScale())
  end
  if side then
    set("tabSide", side)
    set("tabY", math.floor(y * 10 + 0.5) / 10)
  end
  P.placeTab()
end

function P.buildTab()
  holder = CreateFrame("Frame", "TwizCrewPanelHolder", UIParent)
  holder:SetFrameStrata("MEDIUM")
  if holder.SetClampedToScreen then holder:SetClampedToScreen(true) end
  if holder.SetClipsChildren then holder:SetClipsChildren(true); clips = true end
  holder:SetSize(1, 1)
  holder:Hide()

  tab = T.frame("Button", "TwizCrewTab", UIParent)
  P.tab = tab -- (applyLook scales it with the panel: the placing code counts in the tab's own scaled units)
  tab:SetSize(TAB_WIDTH, TAB_HEIGHT)
  tab:SetFrameStrata("MEDIUM")
  tab:SetMovable(true)
  if tab.SetDontSavePosition then tab:SetDontSavePosition(true) end
  if tab.SetClampedToScreen then tab:SetClampedToScreen(true) end
  T.paint(tab, C.backdrop, 0.9, C.border, 2)
  tab.glow = tab:CreateTexture(nil, "ARTWORK")
  tab.glow:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -2)
  tab.glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 2)
  T.color(tab.glow, C.title, 1)
  tab.glow:SetAlpha(0)
  local hl = tab:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(tab)
  T.color(hl, C.white, 0.12)
  tab.label = T.readable(T.text(tab, T.FONT.small, C.title))
  tab.label:SetPoint("TOP", tab, "TOP", 0, -7)
  tab.label:SetText("C\nR\nE\nW")
  tab.count = T.readable(T.text(tab, T.FONT.normal, C.text), 1)
  tab.count:SetPoint("BOTTOM", tab, "BOTTOM", 0, 8)
  -- the missed number (red: a click opens the panel on the Activity tab), the gold "!" of a waiting update, and the
  -- two marks
  tab.badge = CreateFrame("Button", nil, tab)
  tab.badge:SetSize(T.icon(16), T.icon(13))
  tab.badge:SetFrameLevel((tab:GetFrameLevel() or 1) + 3)
  local badgeBg = tab.badge:CreateTexture(nil, "BACKGROUND")
  badgeBg:SetAllPoints(tab.badge)
  T.color(badgeBg, "b3261e", 0.95)
  tab.badge.text = T.readable(T.text(tab.badge, T.FONT.small, C.white))
  tab.badge.text:SetPoint("CENTER", tab.badge, "CENTER", 0, 0)
  if tab.badge.RegisterForClicks then tab.badge:RegisterForClicks("LeftButtonUp") end
  script(tab.badge, "OnClick", function() Panel.openActivity() end)
  script(tab.badge, "OnEnter", function()
    tabHover = true
    wakeSee()
    tabTip(tab)
  end)
  script(tab.badge, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  tab.badge:Hide()
  tab.hint = T.readable(T.text(tab, T.FONT.normal, C.title), 1)
  tab.hint:SetText("!")
  tab.hint:Hide()
  local function mark(hex, icon)
    local m = tab:CreateTexture(nil, "OVERLAY")
    m:SetSize(T.icon(11), T.icon(11))
    m:SetTexture(icon)
    m:SetVertexColor(T.rgb(hex))
    m:Hide()
    return m
  end
  tab.dead = mark(DEAD_COLOR, ns.Tags.ICON.DEAD)
  tab.layer = mark(LAYER_COLOR, ns.Tags.ICON.LAYER)
  if tab.RegisterForClicks then tab:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  if tab.RegisterForDrag then tab:RegisterForDrag("LeftButton") end
  script(tab, "OnDragStart", dragStart)
  script(tab, "OnDragStop", dragStop)
  script(tab, "OnHide", function(self) if dragging then dragStop(self) end end)
  script(tab, "OnClick", function(self, button)
    if dragging or (dragEndAt and ns.now() - dragEndAt < 0.3) then return end
    if button == "RightButton" then
      hoverBlocked, hoverSince = true, nil -- (the panel must not slide out under the menu)
      openMenu(self, Panel.tabMenuItems())
    else
      Panel.tabClicked()
    end
  end)
  script(tab, "OnEnter", function(self)
    tabHover = true
    wakeSee()
    tabTip(self)
  end)
  script(tab, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  tab:Hide()
end

---------------------------------------------------------------------------------------------------------- open / close
-- The tab's tooltip goes when the panel slides out (it could cover the header).
local function hideTabTip()
  if not tab or not GameTooltip then return end
  local owned = false
  if type(GameTooltip.IsOwned) == "function" then
    local ok, yes = pcall(GameTooltip.IsOwned, GameTooltip, tab)
    owned = ok and yes == true
  elseif type(GameTooltip.GetOwner) == "function" then
    local ok, owner = pcall(GameTooltip.GetOwner, GameTooltip)
    owned = ok and owner == tab
  end
  if owned then GameTooltip:Hide() end
end

-- The whole panel slides out of the tab (by = "hover", "click" or "note": the one-time note's pop-up, where the mouse
-- is somewhere else). What was missed counts as seen.
function Panel.openTab(by)
  if not P.enabled or keepOpen() or not P.bar then return end
  P.open = { by = (by == "hover" or by == "note") and by or "click", at = ns.now() }
  hoverSince = nil
  hideTabTip()
  P.bar:clear()
  P.bar:clearMissed()
  flashAt = nil
  startBarTicker()
  requestRedraw()
end

-- The red number on the tab (and the after-fight summary): the panel, straight on the Activity tab.
function Panel.openActivity()
  if not P.open then Panel.openTab("click") end
  Panel.setTab("activity")
end

function Panel.closeTab()
  if not P.open then return end
  P.open = nil
  requestRedraw()
end

-- A click on the tab: open the panel, or close it when it is out (a click works in fights and dungeons too). A click
-- right after the mouse slid it out keeps it out instead (the player clicked to open it, it was just quicker).
function Panel.tabClicked()
  local o = P.open
  if o and o.by == "hover" and ns.now() - (o.at or 0) < CLICK_KEEPS then
    o.by = "click"
  elseif o then
    Panel.closeTab()
    hoverBlocked = true -- (the mouse is still on the tab: it must not slide right back out)
  else
    Panel.openTab("click")
  end
end

---------------------------------------------------------------------------------------------------------- see-through
-- Idle, the tab (and the kept-open panel) fade to the "See-through when idle" level (whole frames: text and bars too).
-- Solid (1) while: the mouse is on the tab, the panel or the holder, or on a menu opened from them; the panel is out
-- (hover, click, the note) or sliding; news is out or the tab flashes for new news; the tab or the kept-open panel is
-- being dragged. It goes back to idle SEE_DELAY seconds after the last of those. 100% = nothing but alpha 1.
local function idleAlpha() return clamp(setting("idleAlpha"), 0.1, 1, 0.4) end

-- Returns solid, and a second value true when the only reason is the mouse (that one rises over SEE_RISE; every other
-- reason, news, an open panel, a slide, a drag, is solid at once so news never slides out faint).
local function seeSolid(now)
  if dragging or (P.isMoving and P.isMoving()) then return true end
  if P.open ~= nil or P.slide ~= nil or P.curView == "peek" then return true end
  if P.bar and (P.bar:current() ~= nil or (flashAt ~= nil and now - flashAt < FLASH_SECONDS)) then return true end
  if mouseOverTab() or mouseOverPanel() then return true, true end
  if shownNow(holder) and over(holder) and focusOn(holder) then return true, true end
  return false
end

local function applyAlpha(a)
  seeCur = a
  local kept = keepOpen()
  if tab then tab:SetAlpha(a) end
  if holder then holder:SetAlpha(kept and 1 or a) end
  if P.root then P.root:SetAlpha(kept and a or 1) end
end

local function stopSeeFrame()
  if seeFrame and seeFrame.seeSet then seeFrame.seeSet = nil; seeFrame:SetScript("OnUpdate", nil) end
end

local seeMove
local function seeFrameStep() ns.Log.safe(FEATURE, seeMove, ns.now()) end

-- Moves the alpha toward the target by the time since the last step; a frame's OnUpdate keeps it smooth until it
-- arrives (then nothing runs).
seeMove = function(now)
  if seeTarget == nil then return end
  -- (the first step of a fade counts one frame, so it starts moving at once)
  local dt = seeAt and math.max(0, math.min(now - seeAt, 1)) or 0.02
  seeAt = now
  local nxt = Logic.seeStep(seeCur, seeTarget, dt, idleAlpha(), SEE_RISE, SEE_FALL)
  if nxt ~= seeCur then applyAlpha(nxt) end
  if nxt == seeTarget then seeAt = nil; stopSeeFrame(); return end
  if not seeFrame then seeFrame = CreateFrame("Frame") end
  if not seeFrame.seeSet then seeFrame.seeSet = true; seeFrame:SetScript("OnUpdate", seeFrameStep) end
end

-- Decides the target (every ticker tick, or at once with `snap`: a setting changed) and steps toward it.
local function seeTick(now, snap)
  local idle = idleAlpha()
  local solid, soft = false, false
  if idle < 1 then solid, soft = seeSolid(now) end
  if solid then lastSolidAt = now end
  seeTarget = Logic.seeTarget(idle, solid, lastSolidAt and now - lastSolidAt or nil, SEE_DELAY)
  if solid and not soft then snap = true end -- news, an open panel, a slide, a drag: solid at once, no rise
  if snap or seeCur == nil then applyAlpha(seeTarget); seeAt = nil; stopSeeFrame(); return end
  seeMove(now)
end

-- Is the see-through level still changing or waiting to change (the ticker must run)?
local function seeBusy(now)
  if idleAlpha() >= 1 then return false end
  if seeCur ~= seeTarget then return true end
  if lastSolidAt and now - lastSolidAt < SEE_DELAY then return true end
  return seeSolid(now)
end

-- Starts the ticker for a reason and applies the see-through level at once (the ticker's first fire is 0.1 s away).
wakeSee = function()
  startBarTicker()
  if P.enabled and P.bar then seeTick(ns.now()) end
end

local seeWaited = 0
local function seeWake(_, elapsed)
  seeWaited = seeWaited + (tonumber(elapsed) or 0)
  if seeWaited < 0.1 then return end
  seeWaited = 0
  ns.Log.safe(FEATURE, function() if mouseOverPanel() then wakeSee() end end)
end

-- The setting or the mode changed (applyLook): apply at once. A kept-open panel has no tab whose OnEnter wakes the
-- ticker, so it polls the mouse (a cheap check, 10 times a second) while it is see-through.
function P.seeSync()
  if idleAlpha() >= 1 then lastSolidAt = nil end
  seeTick(ns.now(), true)
  if P.root then P.root:SetScript("OnUpdate", (keepOpen() and idleAlpha() < 1) and seeWake or nil) end
  startBarTicker()
end

---------------------------------------------------------------------------------------------------------- ticker
local function needTicker()
  if not P.bar or not P.enabled then return false end
  return P.bar:current() ~= nil or P.open ~= nil or P.slide ~= nil or tabHover or newsHeld
    or seeBusy(ns.now())
    or (flashAt ~= nil and ns.now() - flashAt < FLASH_SECONDS)
end

local function stopBarTicker()
  lastTickAt = nil
  if barTicker then barTicker:Cancel(); barTicker = nil end
end
P.stopBarTicker = stopBarTicker

-- Ten times a second while something is going on: the slide, the news queue, the mouse on the tab or the panel.
local function barTick()
  if not P.bar or not P.enabled then stopBarTicker(); return end
  local now = ns.now()
  local dt = lastTickAt and math.max(0, math.min(now - lastTickAt, 1)) or 0
  lastTickAt = now
  local changed = false
  stepSlide(now)
  -- the mouse on the slid-out news keeps it out (so a click on Congrats always goes to the friend it shows); when it
  -- leaves, the news goes shortly after
  if P.curView == "peek" then
    if mouseOverPanel() then
      P.bar:delay(dt)
      newsHeld = true
    elseif newsHeld then
      newsHeld = false
      P.bar:endAfter(now, LEAVE_GRACE)
    end
  else
    newsHeld = false
  end
  local _, moved = P.bar:tick(now)
  if moved then changed = true end
  if not keepOpen() and P.shown then
    local onTab = mouseOverTab()
    if P.open then
      if onTab or mouseOverPanel() then
        P.open.leftAt, P.open.visited = nil, true
      elseif P.open.by == "note" and not P.open.visited and now - (P.open.at or now) < NOTE_MIN then
        P.open.leftAt = nil -- (opened from the note's pop-up: the mouse has not come yet)
      else
        P.open.leftAt = P.open.leftAt or now
        if now - P.open.leftAt >= CLOSE_AFTER then P.open = nil; changed = true end
      end
    elseif onTab and not hoverBlocked then
      local busy = busyMouse()
      if busy or not hoverSince then hoverSince = now end -- turning the camera starts the wait again
      if Logic.hoverOpens({ setting = setting("barHover") == true, restedFor = now - hoverSince, delay = HOVER_DELAY,
        mouselook = busy, inCombat = P.inCombat, inDungeon = P.inDungeon() }) then
        Panel.openTab("hover")
        changed = true
      end
    end
    if not onTab then
      hoverSince, tabHover = nil, false
      if not tabMenuOpen() then hoverBlocked = false end -- (the menu's catcher has the mouse: still on the tab)
    end
  else
    tabHover = false
  end
  drawTab(now)
  seeTick(now)
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

---------------------------------------------------------------------------------------------------------- news
-- The news slid out now (nil: none): the shown entry of the queue, while "Show news from the tab" is on, the tab is on
-- screen, the panel is tucked and there is no fight.
function P.newsNow()
  if not P.bar or keepOpen() or not setting("peek") or P.inCombat then return nil end
  return P.bar:current()
end

-- Would this news's row show a button to react with (PanelLogic.newsReactable)?
local function canReact(e)
  local key = FL.keyOf(e)
  local R = ns.Roasts
  local can = {
    cheer = R ~= nil and R.canCheer ~= nil and R.canCheer(key) and not P.cheered[key] or false,
    mock = R ~= nil and R.canMock ~= nil and R.canMock(key) or false,
  }
  return Logic.newsReactable(e.kind, e.dir, can)
end

-- How long a piece of news stays out: longer when its row shows a button to react with. The after-fight summary
-- always stays the longer time.
function P.newsLengths(e)
  e.reactable = e.kind == "fight" or canReact(e)
  return Logic.newsSeconds(e.reactable, Logic.NEWS_SECONDS, 3)
end

-- Which news the tab shows: the pop-up kinds follow the pop-up switches (no point in news you turned off).
local POPUP_SWITCH = { online = "online", died = "death", levelup = "levelUp", otherlayer = "layerDiff",
  samelayer = "layerDiff" }
local function noticeWanted(e)
  local key = POPUP_SWITCH[e.kind]
  if not key then return true end
  return ns.Modules.isEnabled("popups") and ns.Modules.setting("popups", key) == true
end

local function copyOf(e)
  local c = {}
  for k, v in pairs(e) do c[k] = v end
  return c
end

-- The activity feed recorded something (FEED_ADDED), or the tab made its own news (Panel.news). While tucked: one
-- more missed (the tab glows) and, with "Show news from the tab" on and no fight, the news slides out in its turn.
function Panel.onFeed(e)
  if not P.enabled or not P.bar or keepOpen() or type(e) ~= "table" then return end
  -- no tab on screen (hidden in a fight, when alone, in a dungeon) or the panel is out: the pop-up was shown, so the
  -- tab neither shows it nor counts it as missed
  if not P.shown or P.curView == "full" then return end
  if not FL.isNoticeKind(e) then return end
  -- out of scope (a guildmate who is not in my party or pinned): no news, not counted as missed
  if not Panel.noticeInScope(e.kind, FL.keyOf(e)) or not noticeWanted(e) then return end
  local now = ns.now()
  P.bar:addMissed()
  flashAt = now
  if not P.inCombat then
    -- (a copy: feed entries are saved, and the queue writes its own marks on what it holds)
    if setting("peek") then P.bar:push(copyOf(e), now) end
  elseif #fightNews < FIGHT_MAX then
    -- in a fight it is only counted, and kept for after the fight (a copy too)
    local c = copyOf(e)
    c.inScope, c.got = true, now
    fightNews[#fightNews + 1] = c
  end
  wakeSee()
  requestRedraw()
end

-- The pop-up the pop-ups module shows for this news (its own kind names).
local POPUP_OF = { online = "online", died = "death", levelup = "levelup", otherlayer = "layer_diff",
  samelayer = "layer_same", runaway = "runaway" }

-- About 3 s after a fight ends (and not in a new fight): the news that came during it and that no pop-up showed
-- slides out: one piece as usual, several as one summary (FeedLogic.afterFight).
local function afterFight()
  if not P.enabled or not P.bar or keepOpen() or #fightNews == 0 then fightNews = {}; return end
  local now = ns.now()
  for _, c in ipairs(fightNews) do
    local kind = POPUP_OF[c.kind]
    c.popup = kind ~= nil and ns.Popups ~= nil and ns.Popups.shownSince ~= nil
      and ns.Popups.shownSince(kind, FL.keyOf(c), (c.got or now) - 1) or false
    c.reactable = canReact(c)
  end
  local act, e = FL.afterFight(fightNews, { inCombat = P.inCombat, peek = setting("peek") == true,
    sinceLogin = now - (loadedAt or now) })
  if act == "wait" then return end
  fightNews = {}
  -- (the panel out or not on screen: nothing to slide out; the Activity tab has it all)
  if act ~= "push" or not P.shown or P.curView == "full" then return end
  P.bar:push(e, now)
  startBarTicker()
  requestRedraw()
end

-- The fight ended (PLAYER_REGEN_ENABLED): its news comes AFTER_FIGHT seconds later.
function P.fightEnded()
  if #fightNews == 0 then return end
  fightWait = fightWait + 1
  local mine = fightWait
  if C_Timer and C_Timer.After then
    C_Timer.After(AFTER_FIGHT, function() if mine == fightWait then ns.Log.safe(FEATURE, afterFight) end end)
  end
end

local function inQuiet() return quietUntil ~= nil and ns.now() < quietUntil end

-- News only the tab shows: "otherlayer", "samelayer", "runaway", "calnote", "calreply" (FeedLogic.newsEntry).
function Panel.news(kind, who, extra)
  if not P.enabled or not P.bar or keepOpen() or type(who) ~= "string" or who == "" or inQuiet() then return end
  if kind == "calnote" or kind == "calreply" then
    if P.bar:has("calnote") or P.bar:has("calreply") then return end -- a sync that brings many notes says it once
    for _, c in ipairs(fightNews) do if c.kind == "calnote" or c.kind == "calreply" then return end end
  end
  local m = ns.roster and ns.roster:get(who)
  local e = FL.newsEntry(kind, who, extra, ns.wallclock(), m and m.class or nil)
  if e then Panel.onFeed(e) end
end

local function onRelation(name, old, new)
  if type(name) ~= "string" then return end
  if new == "different" and old ~= "different" and lastLayer[name] ~= "different" then
    lastLayer[name] = "different"
    Panel.news("otherlayer", name)
  elseif new == "same" and (old == "different" or lastLayer[name] == "different") then
    lastLayer[name] = nil
    Panel.news("samelayer", name)
  end
end

function P.listenForNews()
  -- the quiet time counts from login, not from when the file was read (a long loading screen would eat it)
  if not loadedAt then loadedAt = ns.now(); quietUntil = loadedAt + ns.Config.LOGIN_QUIET end
  ns.Bus.on(FEATURE, "LAYER_RELATION", onRelation)
  ns.Bus.on(FEATURE, "MEMBER_OFFLINE", function(name) if name then lastLayer[name] = nil end end)
  ns.Bus.on(FEATURE, "RUNNING_OFF", function(name, dist)
    local F = ns.FindLogic
    Panel.news("runaway", name, { zone = F and F.distanceText and F.distanceText(tonumber(dist) or 0) or nil })
  end)
  ns.Bus.on(FEATURE, "CALENDAR_NEWS", function(kind, author)
    Panel.news(kind == "reply" and "calreply" or "calnote", author)
  end)
end

-- Will the tab show this pop-up's news itself (the layer pop-ups, running off)?
local TAB_KIND = { layer_diff = "otherlayer", layer_same = "samelayer", runaway = "runaway" }
local function tabTakes(popupKind)
  local kind = TAB_KIND[popupKind]
  if not kind or inQuiet() then return false end
  return noticeWanted({ kind = kind })
end

-- Is this pop-up (the pop-ups module's kind) replaced by the tab right now? Only while the panel is tucked into its
-- tab, the tab is on screen and slides news out, and the player turned on "show news on the tab, not as pop-ups".
-- Never in a fight: nothing slides out then, so the pop-up shows (the after-fight news leaves out what it showed).
function Panel.suppressesPopup(popupKind, name)
  local takes
  if FL.POPUP_FEED[popupKind] then
    takes = ns.Feed ~= nil and ns.Modules.isEnabled("activity") and ns.Feed.willTake(popupKind, name) or false
  else
    takes = tabTakes(popupKind)
  end
  return FL.suppressesPopup(popupKind, {
    tucked = not keepOpen(),
    tabShown = P.enabled and P.shown and P.curView ~= "full" and setting("peek") == true and not P.inCombat,
    setting = setting("barInstead") == true,
    takes = takes,
  })
end

---------------------------------------------------------------------------------------------------------- keep open
-- Keep open or let it tuck away; returns whether it is kept open now. Saved with the other settings.
function Panel.toggleKeepOpen()
  local now = not keepOpen()
  set("keepOpen", now)
  return now
end

function Panel.isKeptOpen() return keepOpen() end

-- The "keepOpen" setting changed (the switch, /tc mini, the key, a menu, the settings window or a reset).
function Panel.keepOpenChanged()
  P.open = nil
  fightNews = {}
  newsHeld, hoverSince = false, nil
  if P.bar then P.bar:clear(); P.bar:clearMissed() end
  flashAt = nil
  if P.root then
    P.applyMode()
    P.applyLook()
  end
  if P.enabled then
    P.syncBarTicker()
    requestRedraw()
  end
end

-- A click on the slid-out news line: what clicking that pop-up does (a level-up: congratulate them; online: whisper
-- them; a calendar note: the calendar; running off: the big arrow; a layer change: the whole panel); anything else
-- opens the recent activity list. That news is then done.
function Panel.noticeClicked()
  if not P.bar then return end
  local e = P.bar:current()
  if not e or e ~= P.noticeShown then return end -- the line drawn is not the news the queue holds now
  local raw = FL.keyOf(e)
  if e.kind == "levelup" then
    if not ns.isTestName(raw) then Panel.cheer({ tcModel = { name = raw } }) end
  elseif e.kind == "online" then
    if ns.Popups and ns.Popups.act then ns.Popups.act("online", raw) end
  elseif e.kind == "calnote" or e.kind == "calreply" then
    if ns.Calendar then ns.Calendar.open() end
  elseif e.kind == "runaway" then
    if ns.BigArrow and not ns.isTestName(raw) then ns.BigArrow.point({ kind = "member", name = raw }) end
  elseif e.kind == "otherlayer" or e.kind == "samelayer" then
    return Panel.openTab("click")
  elseif e.kind == "fight" then -- the after-fight summary: the whole panel, on the Activity tab
    return Panel.openActivity()
  elseif ns.Recent then
    ns.Recent.open()
  end
  P.bar:dismiss(ns.now())
  startBarTicker()
  requestRedraw()
end

---------------------------------------------------------------------------------------------------------- test hooks
function Panel.barForTest() return P.bar end
function Panel.seeForTest()
  return { cur = seeCur, target = seeTarget, tab = tab and tab:GetAlpha(), root = P.root and P.root:GetAlpha(),
    holder = holder and holder:GetAlpha() }
end
function Panel.barTickerForTest() return barTicker ~= nil end
function Panel.viewForTest() return P.curView end
function Panel.noticeForTest() return P.noticeShown end
function Panel.rootForTest() return P.root end
function Panel.tabForTest() return tab end
function Panel.holderForTest() return holder end
function Panel.holderWidthForTest() return holderW end
function Panel.openForTest() return P.open end
function Panel.slideForTest() return P.slide end
-- Ends a running slide at once.
function Panel.finishSlideForTest()
  if P.slide then stepSlide(P.slide.t0 + SLIDE_SECONDS + 1) end
end
function Panel.tabStateForTest()
  if not tab then return nil end
  return { shown = tab:IsShown(), count = tab.count:GetText(), missed = P.bar and P.bar.missed or 0,
    badge = tab.badge:IsShown(), glow = rawget(tab, "tcGlow") or 0, hint = rawget(tab, "tcHint") == true,
    dead = tab.dead:IsShown(), layer = tab.layer:IsShown(), side = setting("tabSide") }
end
Panel.TAB_TIMES = { slide = SLIDE_SECONDS, hover = HOVER_DELAY, close = CLOSE_AFTER, grace = LEAVE_GRACE }
