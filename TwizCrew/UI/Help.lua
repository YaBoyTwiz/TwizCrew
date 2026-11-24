-- The words of the mouse-over tips and of the About page ("How to use TwizCrew"), in one place so they can be read,
-- tested and changed together. Pure data, no game calls. Each tip is { title, text }: a short gold title and one or
-- two plain sentences (tests/test_help.lua holds them to the limits). LINES are extra lines added inside tooltips that
-- already exist (a crew row, a calendar square). ABOUT is the About window, line by line ({ text, head = true } for a
-- heading). Widgets.helpTip(frame, key) puts a tip on a frame; Widgets.button and friends take a key as `tip`.
local _, ns = ...

local Help = {}
ns.Help = Help

local DOT = "  \194\183  " -- a middle dot with room around it

Help.TIPS = {
  ----------------------------------------------------------------------------------------------------- crew panel
  count = { "Here and online",
    "Here: you, plus the people in your party and the ones you pinned who are online. Online: the guild playing now." },
  tabCrew = { "Crew", "The list of your guild friends: who is online, where they are and what they are doing." },
  tabShame = { "Hall of Shame",
    "Silly stats and awards for the crew, like who died or fell the most. Just for laughs." },
  tabActivity = { "Activity", "What happened lately: who came online, died, levelled up, and roasts." },
  barGuild = { "Guild online",
    "Guild members who are online but not in your party and not pinned. Click to show or hide them." },
  barOffline = { "Offline",
    "Guild members who are not playing now, with when they were last seen. Click to show or hide them." },
  headParty = { "My party", "The people in your party or raid right now." },
  headPinned = { "Pinned",
    "People you pinned with the green +. They stay here while they are online, even outside your party." },
  pin = { "Pin to main view",
    "They stay in the main view while online, even when not in your party, and you get their pop-ups." },
  unpin = { "Unpin", "Takes them off your pinned list. Outside your party they go back to the Guild online list." },
  status = { "Your status", "A short note your friends see next to your name, like LF group or Back in 5." },
  about = { "How to use TwizCrew", "A short page about what TwizCrew does and how to use it." },
  crewTab = { "Crew tab",
    "Rest your mouse here or click to see the whole panel. News slides out from here for a few seconds." },
  idleAlpha = { "Fade when I'm not using it",
    "How visible the tab, or the panel when kept open, stays while your mouse is away. News and menus make it solid; 100% is off." },
  sounds = { "Sounds",
    "Shows only: just the mock laugh and the awards show. All: also pop-ups, level-ups and roasts (Off: none)." },
  chatNews = { "News in my chat", "Lines only you see. Important: deaths, level-ups, congrats and mocks; "
    .. "Everything: also friends coming online, going offline, and roasts." },
  keepOpen = { "Keep open",
    "ON: the panel stays on screen. OFF: it tucks away into its small tab and slides out when you mouse over it." },
  ------------------------------------------------------------------------------------------------- Hall of Shame
  viewSession = { "This session",
    "Tonight's game, shared by the crew online. A new one starts by itself after a break, or with /tc session new." },
  viewAll = { "All time", "Everything counted so far, not just tonight." },
  tab_deaths = { "Deaths",
    "Who died the most, fell, drowned or started a fight too early. Hover an award for its top 3." },
  tab_move = { "Moving", "Steps, jumps, swimming, zones visited and flight paths. Hover an award for its top 3." },
  tab_loot = { "Money", "The least gold, the most gold lost, repair bills, junk picked up and Need rolls won." },
  tab_oops = { "Oops", "Out of mana, out of range, quests given up, duels lost and more." },
  tab_lazy = { "Lazy", "Chat messages, emotes, time away, slow XP, and who brought people back to life." },
  tab_trophies = { "Trophies",
    "Awards won in every session the crew played. Hover a name for every award and streak." },
  wipe = { "Wipe Squad",
    "How many times the crew in a dungeon or raid all died together. It shows only when there were wipes." },
  ------------------------------------------------------------------------------------------------ awards show
  vote = { "Clown of the Night",
    "Vote for tonight's biggest clown: one vote each, 30 seconds. The winner gets a title on the panel and a trophy." },
  skip = { "Skip the vote",
    "Ends the vote with no clown. Nobody has the Clown of the Night title until the next show." },
  ---------------------------------------------------------------------------------------------------- calendar
  calEvents = { "Events", "The crew's notes, dungeon runs and raids on a month. Click a day to see its notes." },
  calPlay = { "Play times", "Who played when: a month of who was on, each day's timeline, and the usual times." },
  calMonth = { "Month", "Each day shows who played. Click a day for its timeline." },
  calUsual = { "Usual times", "When the crew is usually on in the last 4 weeks, and the best time to play together." },
  calCreate = { "Create a note", "Add a note, a dungeon run or a raid to a day. The whole crew sees it." },
  calZone = { "Your time zone", "Every time here is in your own time. Friends see the same notes in their own time." },
  calBack = { "Back to the month", "Goes back to the whole month." },
  calWeekGrid = { "This week as a grid", "Shows this whole week hour by hour: who was really on." },
  calRealWeeks = { "See real weeks",
    "Shows real weeks hour by hour instead of the usual times. The arrows go back in time." },
  calBackUsual = { "Usual times", "Goes back to the usual times of the last 4 weeks." },
  calEveryone = { "Show everyone", "Takes off the people you picked, so the grid shows the whole crew again." },
  calHabit = { "Pick a person", "Click to see only their hours in the grid above. Click again to take them off." },
  calRemove = { "Remove", "Takes your note off the calendar for the whole crew." },
  calEdit = { "Edit", "Change the day, time, words or dungeon. Answers and comments stay with it." },
  noteYes = { "I'm going", "Tells the crew you are coming. Click it again to take your answer back." },
  noteMaybe = { "Maybe", "Tells the crew you might come. Click it again to take your answer back." },
  noteNo = { "Can't make it", "Tells the crew you can't come. Click it again to take your answer back." },
  noteSeen = { "Seen by", "The friends who have opened this note." },
  noteDelComment = { "Delete comment", "Deletes your comment for the whole crew." },
  noteDelete = { "Delete my note", "Takes your note off the calendar for the whole crew." },
  noteEdit = { "Edit my note", "Change the day, time, words or dungeon. Answers and comments stay with it." },
  makerNote = { "Note", "A plain note with your own words, like a plan or a reminder." },
  makerDungeon = { "Dungeon", "A dungeon run: pick the dungeon and it shows with its picture on the calendar." },
  makerRaid = { "Raid", "A raid night: pick the raid and it shows with its picture on the calendar." },
  makerNoTime = { "No time", "The note is for the whole day, with no time on it." },
  makerTime = { "Hour and minutes",
    "Click the arrows or turn the mouse wheel over the box. Minutes go in steps of 15." },
  makerLevels = { "Level colors",
    "The level range is green when it fits your level, gray when you are above it, and red when you are too low yet." },
  ------------------------------------------------------------------------------------------------------- other
  popupLevelup = { "Click to congratulate",
    "Sends them a cheer the crew sees, like the Congrats button on their row." },
  popupOnline = { "Click to whisper", "Opens a whisper to them in chat." },
  bigArrow = { "Big arrow",
    "Points the way to a friend or a meet-up. Drag it to move it (unless the panel is locked)." },
  setBasics = { "Basics", "The few options most people change. Everything else is on the other tabs." },
  setPanel = { "Panel", "How the crew panel and its tab look and behave, and what your crew sees about you." },
  setAlerts = { "Alerts", "Which news gets a pop-up. The rarely needed options are last." },
  setFun = { "Fun", "Roasts, congrats and the Hall of Shame." },
  setFind = { "Find", "Arrows to your group and meet-ups on the map." },
  setMore = { "More", "The calendar, recap cards, spell ranks, updates and the minimap button." },
  setNew = { "What's new", "Every TwizCrew version and what changed. Also: click the panel's title, or /tc new." },
  actClear = { "Clear the list",
    "Empties the Activity list (and the Recent activity window). Only on your screen; nobody else is told." },
  setReset = { "Reset everything",
    "Every setting and the panel's place go back to the start (you are asked first). Stats, notes and friends stay." },
  setAbout = { "How to use TwizCrew", "A short page about what TwizCrew does and how to use it. Also /tc about." },
  choice = { "Next choice", "Click for the next choice. Right-click goes back one." },
  mockTry = { "Try it", "Shows this mock on yourself, only on your screen." },
  mockDelete = { "Delete", "Takes this mock off your list." },
}

-- Lines added inside existing tooltips. %s marks are filled in by the code.
Help.LINES = {
  noAddon = "This guild member does not have TwizCrew, so only name, level and zone are known "
    .. "(from the game's guild list)",
  rightClick = "Right-click for options",
  title = "Title: %s - their Hall of Shame award",
  dimAway = "Dimmed, with zzz: they are away (AFK)",
  arrowRun = "Flashing arrow: they were right next to you and quickly ran far off",
  arrowOtherZone = "Dim arrow: they are in another zone",
  xpBar = "Gold bar: how close they are to their next level",
  questOn = "!: the quest they are on",
  questDone = "?: their quest is ready to turn in",
  bigArrowNorth = "Gold N: north. The game can't tell which way you face, so the arrow points like the map",
  calBest = "Gold square: the best time to play together",
  calNow = "The gold line is now",
  calAnswers = "%s going   %s maybe",
  calLegend = "|cffffd100Gold|r: a note" .. DOT .. "|cff3fa9f5Blue|r: a dungeon run" .. DOT
    .. "|cffa335eePurple|r: a raid" .. DOT .. "|cffffd100new|r: not opened yet" .. DOT .. "Gold top line: today",
}

-- The grey line under each control on the settings window's Basics page ("module:<id>" is a part's switch): the
-- (i) tip in one plain line.
Help.SETTING_LINES = {
  ["panel:keepOpen"] = "Off: the panel tucks into a small tab on the screen edge. On: it stays open where you drag it.",
  ["panel:scale"] = "Makes the panel and its tab bigger or smaller. 100% is the normal size.",
  ["panel:idleAlpha"] = "How see-through the tab, or the kept-open panel, is while your mouse is away. 100% is off.",
  ["panel:noticeScope"] = "Whose news you get: only your party and pinned friends, or the whole guild.",
  ["module:popups"] = "Small boxes on your screen when friends come online, die or level up.",
  ["activity:chatNews"] = "Lines in your chat only you see. Important: deaths, level-ups, congrats and mocks.",
  ["popups:sounds"] = "Which TwizCrew sounds play: none, just the mock laugh and the awards show, or all.",
  ["tags:autoAway"] = "Your crew sees AFK next to your name when you have not played for a few minutes.",
}

-- title, text of a tip (nil when there is no such key).
function Help.tip(key)
  local t = Help.TIPS[key]
  if type(t) ~= "table" then return nil end
  return t[1], t[2]
end

local function head(text) return { text = text, head = true } end

-- The About window, top to bottom. Every line fits the window (tests: at most ABOUT_WIDTH characters).
Help.ABOUT_WIDTH = 90
Help.ABOUT_CLOSING = "TwizCrew is still growing. Things may change, and this page is updated with each version."
Help.ABOUT = {
  head("What TwizCrew is"),
  "See your guild friends, find them, plan with them and laugh at them.",
  "It works for everyone in your guild who has TwizCrew. There is nothing to set up.",
  "",
  head("The crew panel"),
  "It tucks away into a small tab on the screen edge. Rest your mouse on the tab to see it.",
  "Click Keep open at the top of the panel to keep it on screen. Drag the tab to move it.",
  "From the top: My party, then Pinned, then the Guild online and Offline bars.",
  "Click a bar to open or close its list. A setting adds your own row at the top.",
  "The count at the top: people here (you, your party and pins) and the guild online.",
  "The Activity tab lists what happened lately. The red number on the tab opens it.",
  "The green + pins someone: they stay in the main view while online, and you get",
  "their pop-ups.",
  "The gold star unpins them.",
  "A dimmed row: offline, away (AFK), or no TwizCrew (only name, level and zone known).",
  "Tags on a row:",
  "   DEAD: dead or a ghost.   FIGHTING: in a fight.   AFK: away from the keyboard.",
  "   DUNGEON: in a dungeon or raid.   FLYING: riding a flight path.",
  "   OTHER LAYER: on another copy of the world, so you can't see each other.",
  "",
  head("Right-click a friend"),
  "Whisper, invite, pin, see their quests (Their quests) or point the arrow at them.",
  "Hover a row for their level, XP, quest and more.",
  "",
  head("Finding each other"),
  "In a group, a small arrow on a friend's row points to them, with how far away they are.",
  "Click it for the big arrow, and again to close it.",
  "Meet-up: Ctrl + right-click a spot on the world map. Your party (or everyone) gets",
  "a pop-up and an arrow to that spot.",
  "",
  head("Hall of Shame and the awards show"),
  "Silly stats for the crew: deaths, falls, jumps, gold, time away and more.",
  "The winners get awards, a title on the panel, and trophies for the sessions they win.",
  "/tc awards starts the awards show, great on stream. The crew can watch it with you.",
  "",
  head("The calendar"),
  "Notes, planned dungeon runs and raids, and who usually plays when.",
  "Open it with the Calendar button on the panel, or type /tc cal.",
  "",
  head("Settings"),
  "Click the gear on the panel, or type /tc. Every setting has an (i) that explains it.",
  "Hover almost anything for a tip.",
  "",
  head("Handy commands"),
  "/tc  -  settings",
  "/tc cal  -  the calendar",
  "/tc recent  -  what happened lately",
  "/tc report  -  a health check to copy to Discord",
  "/tc help  -  this page, and the everyday commands in chat (/tc help more: the rest)",
  "",
  Help.ABOUT_CLOSING,
}

-- The About lines as { text, head } tables.
function Help.aboutLines()
  local out = {}
  for i, l in ipairs(Help.ABOUT) do
    if type(l) == "table" then out[i] = { text = l.text, head = true } else out[i] = { text = l } end
  end
  return out
end
