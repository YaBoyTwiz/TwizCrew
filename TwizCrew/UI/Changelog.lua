-- "What's new": every version and what changed, in plain words, newest first. Opened by clicking the version in
-- the panel's title, the "New in vX" line after an update, the What's new button in the settings, or /tc new.
-- Add an entry at the top of HISTORY with every release (tests check the newest one is ns.VERSION).
local _, ns = ...

local Changelog = {}
ns.Changelog = Changelog

local FEATURE = "panel"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, PAD = 470, 14
local LINE_H = 16
local LINES = 22 -- lines shown at once; the mouse wheel scrolls

Changelog.HISTORY = {
  { ver = "0.1.18", date = "2026-11-08", lines = {
    "Create note: the dungeon list is inside the window now (click one, scroll for more): no more clicks falling through.",
    "Time has up and down arrows for the hour and the minutes (the mouse wheel works too), and an AM / PM button.",
    "Menus always sit on top, so a window behind them never steals your click.",
    "Key bindings: Esc > Options > Keybindings > AddOns > TwizCrew (panel, calendar, a note, AFK, ranks, mock, recap).",
    "Right-click the minimap button for a menu: the crew panel, a calendar note, the tools, the settings.",
    "Quick statuses: one click for LF group, Questing, Farming, Dungeon soon or Back in 5.",
    "Hover a friend: \"Also on it\" lists who else (you too) is on the same quest, so you know who to group with.",
    "Today's recap: when you log out (or /tc recap): time played, levels, quests, deaths, gold and who was on.",
  } },
  { ver = "0.1.17", date = "2026-11-08", lines = {
    "The big arrow to a friend stays until you close it: no more turning it on again after a fight.",
    "Next to them it says Right here, and points again when they move away.",
    "After a friend's quest: green + they can share it with you (click to ask), red X they can't (hover for why).",
    "A green check after a friend's quest when you're on it too.",
    "Congrats got sassier: 45 new lines that cheer for your friend while poking fun at them.",
    "Calendar notes: click a day, type a note and pick an icon. The whole crew sees it on that day.",
    "Create note button: pick the day, the time, note / dungeon / raid, an icon and the words. It lands on its day.",
    "Right-click a day or the day's timeline to start a note there (with that time).",
    "A dungeon or raid fills its day with the dungeon's picture, the time and name on top.",
    "The dungeon picker shows the levels (green: your range), lowest first, each with its icon.",
    "All 28 of Forever's dungeons (the 9 new ones marked new) and its raids: Barrow Deeps, Hyjal Summit, Onyxia's Lair.",
    "Click a note to open it: Going / Maybe / Can't make it, who has seen it, and comments.",
    "Everyone sees a timed note in their own time (their computer's clock, not the server's), on their own date.",
    "The calendar looks better: class icons for who played, note icons on the days, icons on the tabs.",
    "Icons all over: on the right-click menus, on every pop-up, and next to options in the settings.",
  } },
  { ver = "0.1.16", date = "2026-11-08", lines = {
    "Crew calendar (the scroll button next to the wrench, or /tc cal): who played each day, and for how long.",
    "Click a day for its timeline: one bar per friend, so you can see who was on together.",
    "Usual times: when the crew is usually on, the best time to play together, and everyone's habits.",
    "Your characters count as one person. Your copy swaps play times with the crew, so you see days you missed.",
    "Only times are shared, never where you were. Turn it off with Share my play times.",
  } },
  { ver = "0.1.15", date = "2026-11-08", lines = {
    "Before you ask: hover a friend to see if you can get their quest (with Questie: level, class, earlier quests).",
    "The right-click menu says Can't share (and why) when there's no use asking.",
  } },
  { ver = "0.1.14", date = "2026-11-08", lines = {
    "Fixed: Ask to share said you weren't in a group when you were.",
    "Fixed: Invite to group showed for friends already in your party.",
  } },
  { ver = "0.1.13", date = "2026-11-08", lines = {
    "The What's new line always stays at the top of the panel, so it's easy to find.",
    "Your own row is off again (less clutter). Turn it on with Show myself in the list.",
    "Right-click anyone's row for your own options too: set your status, go AFK.",
    "Congrats button: shows on a friend's row after they level up. They see your character cheer for them.",
    "Clicking a friend's level-up pop-up sends congrats too.",
    "New wrench button on the panel: handy tools in one place.",
    "First tool: put your highest spell ranks on your bars (also /tc rankup).",
    "Fixed: the + / - picture on the Offline bar was missing.",
    "Right-click a friend's row, Ask to share: they get a pop-up and one click shares their quest with you.",
    "Icons on every choice in the wrench menu.",
  } },
  { ver = "0.1.12", date = "2026-11-08", lines = {
    "This window! Click the version in the panel's title to see what changed.",
    "The panel only lists friends who are online. Click \"Offline\" at the bottom to see the rest.",
    "A pop-up when a friend comes online (not for a quick /reload). Click it to whisper them.",
    "The panel fades less when your mouse is away (50%), so it's easier to read.",
  } },
  { ver = "0.1.11", date = "2026-11-07", lines = {
    "The mock show appears beside the middle of the screen, never off screen.",
    "Drag the mock show anywhere; it remembers the spot. /tc mock spot puts it back.",
  } },
  { ver = "0.1.10", date = "2026-11-07", lines = {
    "3D mock show: the friend who mocks you laughs at you with their race's laugh.",
    "My mocks window (/tc mock): write, try and delete your own roasts.",
    "40 built-in mocks, with {name}, {zone}, {level} and more.",
    "Friends' quests on their rows, and more detail when you hover a name.",
    "Right-click a row: whisper, invite, inspect, point the way, mock, add friend.",
    "Advanced settings split into small tabs.",
    "The panel fades when your mouse is away; the Mock button stays solid.",
    "Find the crew: arrows to your group on the panel, a big arrow, meet-ups.",
    "Ctrl + right-click the world map to set a meet-up spot for the crew.",
  } },
  { ver = "0.1.9", date = "2026-11-07", lines = {
    "Mock button on a dead friend's row, with your own roasts (/tc mock add).",
  } },
  { ver = "0.1.8", date = "2026-11-07", lines = {
    "Easier to read text on the rows (black outline), bigger icons.",
  } },
  { ver = "0.1.7", date = "2026-11-07", lines = {
    "AFK button in the panel, away after a few idle minutes, and the game's /afk shows too.",
    "Hover a name to see which TwizCrew version they have.",
    "Settings open on a short Basics tab; everything else is under Advanced.",
  } },
  { ver = "0.1.6", date = "2026-11-07", lines = {
    "Rows in your friends' class colors, a gold XP bar that brightens as it fills.",
    "Icons on the tags (dead, fighting, AFK...).",
    "Layers: friends out of range no longer show as on a different layer.",
  } },
  { ver = "0.1.5", date = "2026-11-06", lines = {
    "Friends can see each other on WoW Forever (it now whispers the crew directly).",
  } },
  { ver = "0.1.4", date = "2026-11-06", lines = {
    "Friends in your group always hear each other.",
  } },
  { ver = "0.1.3", date = "2026-11-05", lines = {
    "Try it out (/tc test): pretend friends and pop-ups, only on your screen.",
  } },
  { ver = "0.1.2", date = "2026-11-05", lines = {
    "Level and XP on the rows, XP details and time to level on hover.",
    "\"Ding!\" pop-up when a friend levels up.",
    "Gold \"Update available\" line and an update pop-up once per new version.",
  } },
  { ver = "0.1.1", date = "2026-11-05", lines = {
    "TwizCrew button on the minimap.",
    "Tell crew to update button.",
  } },
  { ver = "0.1.0", date = "2026-11-05", lines = {
    "First version: the crew panel, layers, tags, pop-ups for layer changes and deaths.",
    "Stats, live roasts, the Hall of Shame and the awards show.",
  } },
}

-- The flat list of lines the window shows: { text, head = true for a version's title }.
function Changelog.lines()
  local out = {}
  for i, e in ipairs(Changelog.HISTORY) do
    if i > 1 then out[#out + 1] = { text = "" } end
    local head = "v" .. e.ver .. "  " .. (e.date or "")
    if e.ver == ns.VERSION then head = head .. "  (your version)" end
    out[#out + 1] = { text = head, head = true }
    for _, l in ipairs(e.lines) do out[#out + 1] = { text = "-  " .. l } end
  end
  return out
end

----------------------------------------------------------------------------------------------- "new in vX" line
-- Shown in the panel once after an update, until the window has been opened (or the line clicked).
-- A brand-new install has nothing "new" to show: checkFresh runs before anything else touches the saved data
-- (the panel calls it first thing), and counts it as an update only when an older copy left its marks.
function Changelog.checkFresh()
  local db = ns.db
  if not db or db.newsSeen ~= nil then return end
  local before = db.fadeOnSince017 or (type(db.roster) == "table" and next(db.roster) ~= nil)
  if not before then db.newsSeen = ns.VERSION end
end

function Changelog.unseen()
  local db = ns.db
  if not db then return false end
  return db.newsSeen ~= ns.VERSION
end

function Changelog.markSeen()
  if ns.db then ns.db.newsSeen = ns.VERSION end
  if ns.Panel and ns.Panel.refresh then ns.Panel.refresh() end
end

---------------------------------------------------------------------------------------------------------- window
local frame, rows, offset, open = nil, nil, 0, false

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function build()
  frame = T.frame("Frame", "TwizCrewChangelog", UIParent)
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
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewChangelog") end -- Escape
  script(frame, "OnHide", function() open = false end) -- Escape closes it too

  local title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("What's new in TwizCrew")
  local close = Widgets.button(frame, "Close", function() Changelog.close() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -8)
  local help = T.text(frame, T.FONT.small, C.muted)
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  help:SetText("Newest first. Scroll with the mouse wheel.")

  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -52)
  list:SetSize(WIDTH - 2 * PAD, LINES * LINE_H)
  if list.EnableMouseWheel then list:EnableMouseWheel(true) end
  script(list, "OnMouseWheel", function(_, delta) Changelog.scroll(-(tonumber(delta) or 0) * 3) end)
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

function Changelog.refresh()
  if not frame then return end
  local all = Changelog.lines()
  offset = math.max(0, math.min(offset, #all - LINES))
  for i, fs in ipairs(rows) do
    local l = all[offset + i]
    fs:SetText(l and l.text or "")
    local col = (l and l.head) and C.title or C.text
    fs:SetTextColor(T.rgb(col))
  end
end

function Changelog.scroll(lines)
  offset = math.max(0, offset + (tonumber(lines) or 0))
  Changelog.refresh()
end

function Changelog.open()
  if not frame then build() end
  offset = 0
  Changelog.refresh()
  frame:Show()
  open = true
  Changelog.markSeen()
end

function Changelog.close()
  open = false
  if frame then frame:Hide() end
end

function Changelog.toggle()
  if Changelog.isShown() then Changelog.close() else Changelog.open() end
end

function Changelog.isShown() return open end

-- Test hook: the texts on screen right now.
function Changelog.shownForTest()
  local out = {}
  for i, fs in ipairs(rows or {}) do out[i] = fs:GetText() end
  return out
end
