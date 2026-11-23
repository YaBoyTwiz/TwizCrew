-- "How to use TwizCrew": a short page about what the addon does and how to use it (the words: UI/Help.lua, ABOUT).
-- A window like What's new: static lines, the mouse wheel scrolls, Escape closes. Opened by the "?" next to the panel's
-- tabs, the wrench menu (and so the minimap button's menu), the button in the settings, /tc about and /tc help.
-- Once by itself on a new install: DB.init marks a brand-new saved data set with aboutSeen = false (data from before
-- this version gets true without a word); a few seconds after login, out of combat and outside a dungeon or raid, the
-- page opens once and the flag turns true. The flag is account-wide (not in DB.GUILD_PATHS).
-- Under the feature id "panel" like What's new; not a module.
local _, ns = ...

local About = {}
ns.About = About

local FEATURE = "panel"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, PAD = 600, 14
local LINE_H = 18
local LINES = 26 -- lines shown at once; the mouse wheel scrolls the rest
local FIRST_DELAY = 5 -- seconds after login before the page opens by itself on a new install
local RETRY = 15 -- seconds between tries while in a fight or a dungeon

local frame, rows, offset, open = nil, nil, 0, false

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function build()
  frame = T.frame("Frame", "TwizCrewAbout", UIParent)
  frame:SetSize(WIDTH, 60 + LINES * LINE_H + 20)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  script(frame, "OnDragStart", function(self) self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewAbout") end -- Escape
  script(frame, "OnHide", function() open = false end) -- Escape closes it too

  local title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("How to use TwizCrew")
  local close = Widgets.button(frame, "Close", function() About.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -8)
  local help = T.text(frame, T.FONT.small, C.muted)
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  help:SetText("v" .. ns.Util.safeText(tostring(ns.VERSION)) .. ". Scroll with the mouse wheel.")

  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -52)
  list:SetSize(WIDTH - 2 * PAD, LINES * LINE_H)
  if list.EnableMouseWheel then list:EnableMouseWheel(true) end
  script(list, "OnMouseWheel", function(_, delta) About.scroll(-(tonumber(delta) or 0) * 3) end)
  rows = {}
  for i = 1, LINES do
    local fs = T.text(list, T.FONT.small, C.text)
    fs:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * LINE_H)
    fs:SetWidth(WIDTH - 2 * PAD)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    rows[i] = fs
  end
end

function About.lines() return ns.Help.aboutLines() end

function About.refresh()
  if not frame then return end
  local all = About.lines()
  offset = math.max(0, math.min(offset, #all - LINES))
  for i, fs in ipairs(rows) do
    local l = all[offset + i]
    fs:SetText(l and l.text or "")
    fs:SetTextColor(T.rgb((l and l.head) and C.title or C.text))
  end
end

function About.scroll(lines)
  offset = math.max(0, offset + (tonumber(lines) or 0))
  About.refresh()
end

function About.open()
  if not frame then build() end
  offset = 0
  About.refresh()
  frame:Show()
  open = true
  if ns.db then ns.db.aboutSeen = true end
end

function About.close()
  open = false
  if frame then frame:Hide() end
end

function About.toggle()
  if About.isShown() then About.close() else About.open() end
end

function About.isShown() return open end

---------------------------------------------------------------------------------------------- once, on a new install
local function busy()
  if ns.Util.plain(InCombatLockdown) then return true end
  local _, kind = ns.Util.plain(IsInInstance)
  return kind == "party" or kind == "raid"
end

-- A new install in a guild is also owed the welcome card (UI/Welcome.lua), which has a button for this page: one
-- window at first login is enough. So while that card is owed this page waits for it once; when the card has shown,
-- this page counts as offered; when it could not show (no guild list, say), this page opens after all.
local CARD_WAIT = 40 -- seconds; the welcome card shows about 30 s after login
local waitedForCard = false

local function tryFirst()
  if not ns.db or ns.db.aboutSeen ~= false then return end -- seen already, or saved data from an older version
  local w = ns.db.welcome
  if type(w) == "table" and w.start == "shown" then ns.db.aboutSeen = true; return end
  if not waitedForCard and ns.Welcome and ns.Welcome.startOwed and ns.Welcome.startOwed()
    and C_Timer and C_Timer.After then
    waitedForCard = true
    C_Timer.After(CARD_WAIT, function() ns.Log.safe(FEATURE, tryFirst) end)
    return
  end
  if busy() then
    if C_Timer and C_Timer.After then C_Timer.After(RETRY, function() ns.Log.safe(FEATURE, tryFirst) end) end
    return
  end
  About.open()
end

-- At login: a new install opens the page once, a few seconds in.
function About.onLogin()
  if ns.db and ns.db.aboutSeen ~= false then return end -- (no saved data yet: asked again when the time comes)
  if C_Timer and C_Timer.After then
    C_Timer.After(FIRST_DELAY, function() ns.Log.safe(FEATURE, tryFirst) end)
  else
    tryFirst()
  end
end

ns.Events.on("about", "PLAYER_LOGIN", About.onLogin)

-- Test hook: the texts on screen right now.
function About.shownForTest()
  local out = {}
  for i, fs in ipairs(rows or {}) do out[i] = fs:GetText() end
  return out
end
