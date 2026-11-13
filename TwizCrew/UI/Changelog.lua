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
local LINE_H = 18
local LINES = 20 -- lines shown at once; the mouse wheel scrolls

Changelog.HISTORY = {
  { ver = "0.1.24", date = "2026-11-12", lines = {
    "Minimize the panel: the minus button on the title bar, or /tc mini. Only the title bar stays.",
    "  While minimized, the bar shows who came online, died or levelled up, and the panel peeks open for a moment.",
    "Recent activity: a list of what happened (/tc recent, or the red number on the bar).",
    "Deaths, level-ups, congrats and mocks are also written in your chat (only you see them). Switch: Settings.",
    "Forget a friend: right-click an offline row, or /tc forget Name. Names not seen for 60 days drop off.",
    "A friend's wrong tag (a missed \"dead\", for example) now fixes itself within about two minutes.",
    "Hall of Shame: numbers no longer flash to zero, so no more false \"stole the crown\" pop-ups.",
    "Calendar: notes and comments are about 100 letters at most, and syncing them takes far fewer messages.",
    "A part of the addon that breaks comes back by itself after 5 minutes. /tc report lists problems.",
    "Fixed: dragging the awards show, the scale setting moving the panel, \"running off\" for a dead friend.",
    "Many safety fixes for dungeons and fights.",
    "Needs a full restart of the game (new files), not just /reload.",
  } },
  { ver = "0.1.23", date = "2026-11-09", lines = {
    "Spell helpers removed (window, /tc spells, new-spell pop-up). Macros it made stay in /macro; delete them there",
    "  if you don't want them. The rank updater now updates every spell on your bars.",
    "Needs a full game restart (files were removed), not just /reload.",
  } },
  { ver = "0.1.22", date = "2026-11-09", lines = {
    "Stolen crowns: a pop-up when someone takes the lead in a Hall of Shame award (after the first 15 minutes,",
    "  at most one a minute). Click it to see the award. Switch: Live roasts > Stolen crown pop-ups.",
    "Trophy case: when a crew session ends, each award's winners get a trophy. See them on the new Trophies tab,",
    "  with streaks (\"3 sessions in a row\"). Hover a friend on the Crew tab for their trophies.",
    "The awards show (/tc awards) now plays on everyone's screen and follows the presenter's clicks.",
    "  Escape closes it for you. Switch: Stats > Show the crew's awards show on my screen.",
    "Clown of the Night: after the last award, everyone votes (not for yourself, 30 seconds).",
    "  The clown gets the title under their name until the next show, and a clown trophy.",
    "Needs a full restart of the game (new files), not just /reload.",
  } },
  { ver = "0.1.21", date = "2026-11-09", lines = {
    "Hall of Shame: 11 new awards, in five tabs (Deaths, Moving, Money, Oops, Lazy). It remembers your tab.",
    "  Pauper: carries the least gold right now (exact amount; needs 30 minutes played).",
    "  Money Pit: lost the most gold. Ninja: won the most Need rolls in a group.",
    "  Out of Juice: \"Not enough mana\" the most. Too Far Away: \"Out of range\" the most.",
    "  Wanderer: ran off from the group the most (flights count; hearths, portals and ghosts don't).",
    "  Snail: the least XP per hour. Chatterbox and Emote Spammer: the most party chat and emotes.",
    "  Tourist: the most zones visited. Frequent Flyer: the most flight paths.",
    "Fixed: the crew panel disappearing inside dungeons until /reload.",
    "Spell helpers no longer move anything on your bars: drag each macro from the new Macro column yourself.",
    "The running-off warning is silent now (the flashing arrow and pop-up stay).",
    "Spell helpers and the rank updater were missing from the last download; they're in this one.",
    "Needs a full restart of the game (new files), not just /reload.",
  } },
  { ver = "0.1.20", date = "2026-11-08", lines = {
    "Spell helpers (wrench button, or /tc spells): every spell you know with three switches:",
    "  Newest rank: always the highest rank (switch it off to keep a cheap low rank on purpose).",
    "  Smart target: a harmful spell at a friend hits the friend's target; a helpful one at an enemy lands on",
    "  whoever the enemy is attacking (or you). Done with a macro in the spell's slot, same icon and tooltip.",
    "  Switch target: with smart target, that unit also becomes your target.",
    "  Hover each (i) for examples. Only this character's macro slots are used; your own macros are never touched.",
    "When you learn a new spell or rank, a pop-up says how it's set: click it to choose.",
    "Bigger text and icons everywhere: the panel, menus, pop-ups, the calendar, the settings and every window.",
    "Needs a full restart of the game (new files), not just /reload.",
  } },
  { ver = "0.1.19", date = "2026-11-08", lines = {
    "Calendar, a day: each bar starts with that person's class icon and has their times on it (7pm-11pm).",
    "Hover the timeline to see who was on at that moment (\"At 8:15pm, 3 on: ...\"), AFK marked.",
    "Calendar, the month: hover a day for each person's times, not just how long they played.",
    "More people than fit on a day: scroll with the mouse wheel.",
    "Usual times: click people in the list under the grid to see only them: one person in their class color,",
    "  several = how many of them are usually on, and their best time to play together. Click again to take them off.",
    "  Or click someone's row on a day to jump to their grid.",
    "Real weeks: \"See real weeks\" turns the grid into a past week (arrows for others): who was really on, hour by",
    "  hour, on those dates. Works with the people you picked. Click a square for that day; on a day, \"This week as a grid\".",
  } },
  { ver = "0.1.18", date = "2026-11-08", lines = {
    "Create note: the dungeon list is inside the window now (click one, scroll for more): no more clicks falling through.",
    "Time has up and down arrows for the hour and the minutes (the mouse wheel works too), and an AM / PM button.",
    "Menus always sit on top, so a window behind them never steals your click.",
    "Key bindings: Esc > Options > Keybindings > AddOns > TwizCrew (panel, calendar, a note, AFK, ranks, mock, recap).",
    "Right-click the minimap button for a menu: the crew panel, a calendar note, the tools, the settings.",
    "Quick statuses: one click for LF group, Questing, Farming, Dungeon soon or Back in 5.",
    "Hover a friend: \"Also on it\" lists who else (you too) is on the same quest, so you know who to group with.",
    "Today's recap: when you log out (or /tc recap): time played, levels, quests, deaths, gold and who was on.",
    "Running off: when a group member who was right next to you is suddenly far away, their arrow flashes red,",
    "  with a pop-up (click it for the big arrow) and a sound. Switches under Find the crew.",
    "The arrows on the panel are a little bigger.",
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
