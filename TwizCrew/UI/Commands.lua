-- Chat commands: /tc and /twizcrew (/twiz belongs to TwizTracker and is never registered here).
local _, ns = ...

local Commands = {}
ns.Commands = Commands

local FEATURE = "commands"

local HELP = {
  "TwizCrew commands:",
  "/tc - open or close the settings",
  "/tc show - show the crew panel",
  "/tc hide - hide the crew panel",
  "/tc mini - minimize the panel to its title bar (again to restore it)",
  "/tc recent - the list of recent happenings: friends online, deaths, level-ups, congrats and mocks",
  "/tc minimap - show or hide the TwizCrew button on the minimap",
  "/tc status <text> - a short note your friends see next to your name (/tc status alone clears it)",
  "/tc mock - the My mocks window: write, try and delete your own mocks",
  "/tc mock add <text> - add your own roast for the Mock button ({name} = the dead friend, {me} = you)",
  "/tc mock list - your roasts, numbered   /tc mock remove <number> - take one out",
  "/tc mock spot - put the mock show back in its normal spot (drag it to move it)",
  "/tc new - what's new: every version and what changed",
  "/tc rankup - put the highest rank of every spell on your action bars",
  "/tc cal - the crew calendar: who played when, and the best time to play together",
  "/tc recap - today's recap: time played, levels, quests, deaths, gold and who was on",
  "Key bindings: Esc > Options > Keybindings > AddOns > TwizCrew (panel, minimize, calendar, notes, AFK, ranks, mock, recap)",
  "/tc afk - show your crew you are away (again to come back; moving or casting also brings you back)",
  "/tc meet clear - take the meet-up away (to make one: Ctrl + right-click a spot on the world map)",
  "/tc reset - put every setting back to normal (asks first)",
  "/tc report - a health check you can copy and paste to Discord",
  "/tc debug - turn technical chat messages on or off",
  "/tc add <name> - add a friend by name, used when the hidden channel does not work",
  "/tc remove <name> - take a name off that list",
  "/tc awards - the awards show for this session, great on stream",
  "/tc awards all - the awards show for all time",
  "/tc session new - start a new crew session, everyone's session stats start from 0",
  "/tc stats reset - set your own stats back to 0 (asks first)",
  "/tc test - try things out alone: pretend friends and pop-ups, only on your screen (/tc test lists them)",
}

local function say(text) print("TwizCrew: " .. text) end

-- "  Status  LF Deadmines " -> "status", "LF Deadmines"
function Commands.parse(msg)
  local text = ns.Util.trim(tostring(msg or ""))
  local cmd, rest = text:match("^(%S+)%s*(.-)$")
  if not cmd then return "", "" end
  return cmd:lower(), ns.Util.trim(rest)
end

-- Trimmed, first letter capitalised like WoW names ("frostie" -> "Frostie"); nil when empty.
function Commands.normalizeName(text)
  local name = ns.Util.trim(tostring(text or ""))
  if name == "" then return nil end
  return name:sub(1, 1):upper() .. name:sub(2)
end

local function extraList()
  local crew = ns.db and ns.db.crew
  if not crew then return nil end
  if type(crew.extra) ~= "table" then crew.extra = {} end
  return crew.extra
end

local function findName(list, name)
  local low = name:lower()
  for i, n in ipairs(list) do
    if type(n) == "string" and n:lower() == low then return i end
  end
end

local function addName(rest)
  local name = Commands.normalizeName(rest)
  local list = extraList()
  if not name then say("type a name after it, like /tc add Frostie"); return end
  if not list then return end
  if ns.isMe(name) then
    say("that's you, no need to add yourself.")
    return
  end
  local safe = ns.Util.safeText(name)
  if findName(list, name) then say(safe .. " is already on your list."); return end
  list[#list + 1] = name
  say("added " .. safe .. ". If the hidden channel does not work, TwizCrew will whisper them directly.")
end

local function removeName(rest)
  local name = Commands.normalizeName(rest)
  local list = extraList()
  if not name then say("type a name after it, like /tc remove Frostie"); return end
  if not list then return end
  local i = findName(list, name)
  if not i then say(ns.Util.safeText(name) .. " is not on your list."); return end
  local removed = table.remove(list, i)
  say("removed " .. ns.Util.safeText(removed) .. ".")
end

-- quiet: no "panel shown/hidden" line (the minimap button's right-click; the panel itself is the answer).
local function setPanel(on, quiet)
  if on then
    for _, id in ipairs(ns.Modules.broken()) do
      if id == "panel" then
        say("the crew panel turned itself off after errors. Type /reload to try again.")
        return
      end
    end
    ns.Modules.setEnabled("panel", true)
    if not quiet then say("panel shown.") end
  else
    ns.Modules.setEnabled("panel", false)
    if not quiet then say("panel hidden. Type /tc show to bring it back.") end
  end
end
Commands.setPanel = setPanel

-------------------------------------------------------------------------------------------------- key bindings
-- Bindings.xml names these (Esc > Options > Keybindings > AddOns > TwizCrew).
BINDING_HEADER_TWIZCREW = "TwizCrew"
BINDING_NAME_TWIZCREW_PANEL = "Show or hide the crew panel"
BINDING_NAME_TWIZCREW_MINI = "Minimize or restore the crew panel"
BINDING_NAME_TWIZCREW_CALENDAR = "Open the crew calendar"
BINDING_NAME_TWIZCREW_NOTE = "Create a calendar note"
BINDING_NAME_TWIZCREW_AFK = "Go AFK / I'm back"
BINDING_NAME_TWIZCREW_RANKUP = "Update my spell ranks"
BINDING_NAME_TWIZCREW_MOCK = "Mock my target (a dead crew friend)"
BINDING_NAME_TWIZCREW_RECAP = "Today's recap"
BINDING_NAME_TWIZCREW_SETTINGS = "TwizCrew settings"

function Commands.binding(what)
  if what == "panel" then setPanel(not ns.Modules.isEnabled("panel"), true)
  elseif what == "mini" then Commands.toggleMini(true)
  elseif what == "calendar" then ns.Calendar.toggle()
  elseif what == "note" then ns.Calendar.openMaker({})
  elseif what == "afk" then ns.Panel.toggleAway()
  elseif what == "rankup" then ns.RankUp.run()
  elseif what == "recap" then ns.Recap.show()
  elseif what == "settings" then ns.Settings.toggle()
  elseif what == "mock" then
    local name = type(UnitName) == "function" and UnitName("target") or nil
    local dead = type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("target")
    if type(name) ~= "string" or not (ns.roster and ns.roster:get(name)) or not dead then
      say("target a dead crew friend to mock them.")
    elseif not ns.Roasts.canMock(name) then
      say("mocks are switched off (Roasts, Mock button roasts).")
    elseif not ns.Roasts.mock(name) then
      say("give it a few seconds before mocking " .. name .. " again.")
    end
  end
end

-- /tc mini and its key binding: minimize or restore the panel. A hidden panel is only shown (as it was left).
-- quiet: no chat line.
function Commands.toggleMini(quiet)
  if not ns.Modules.isEnabled("panel") then setPanel(true, quiet) return end
  local now = ns.Panel.toggleMinimized()
  if not quiet then
    say(now and "panel minimized to its title bar. Type /tc mini to bring it back." or "panel restored.")
  end
end

function TwizCrew_Binding(what) ns.Log.safe(FEATURE, Commands.binding, what) end

local function toggleMinimap()
  if ns.MinimapButton.toggleShown() then
    say("minimap button shown.")
  else
    say("minimap button hidden. Type /tc minimap to bring it back.")
  end
end

local function setStatus(rest)
  ns.Self.setStatus(rest)
  local now = ns.db and ns.db.myStatus or ""
  if now == "" then
    say("status cleared")
  else
    say('status set to "' .. ns.Util.safeText(now) .. '"')
  end
end

-- "/tc mock add <text>", "/tc mock list", "/tc mock remove <n>", "/tc mock <name>" (mock a dead friend by name).
local function mock(rest)
  local what, more = rest:match("^(%S*)%s*(.-)$")
  what = (what or ""):lower()
  if what == "add" then
    if ns.Roasts.addMock(more) then say("roast added. It's in the rotation now.")
    else say("type your roast after /tc mock add, like: /tc mock add {name} tripped over a flower.") end
  elseif what == "list" then
    local mine = ns.Roasts.myMocks()
    if #mine == 0 then say("you have no roasts of your own yet. Add one with /tc mock add <text>.") return end
    say("your roasts:")
    for i, l in ipairs(mine) do print("  " .. i .. ". " .. ns.Util.safeText(l)) end
  elseif what == "spot" then
    ns.MockShow.resetSpot()
    say("the mock show is back in its normal spot.")
  elseif what == "remove" then
    local gone = ns.Roasts.removeMock(more)
    if gone then say('removed "' .. ns.Util.safeText(gone) .. '".')
    else say("type the number from /tc mock list, like: /tc mock remove 2") end
  elseif what ~= "" then
    local name = ns.shortName(Commands.normalizeName(rest))
    if ns.Roasts.mock(name) then return end
    say("can't mock " .. ns.Util.safeText(name) .. " right now (wait a few seconds between mocks).")
  else
    ns.MockEditor.open() -- /tc mock alone: the My mocks window
  end
end

-- /tc meet clear: takes the meet-up away for everyone it went to. Placing one is on the world map only.
local function meetCommand(rest)
  if rest:lower() == "clear" then
    if not ns.Modules.isEnabled("find") then say("Find the crew is turned off in /tc."); return end
    say(ns.Find.clearMeet() and "meet-up cleared." or "there is no meet-up to clear.")
  else
    say("to meet up, open the world map and Ctrl + right-click a spot. /tc meet clear takes the meet-up away.")
  end
end

local function toggleDebug()
  local on = not ns.Modules.setting("comm", "debug")
  ns.Modules.set("comm", "debug", on)
  say(on and "technical messages on. Type /tc debug again to turn them off." or "technical messages off.")
end

local function printHelp()
  for _, line in ipairs(HELP) do print(line) end
end

local function awards(rest)
  local what = rest:lower()
  if what == "" then
    ns.AwardsShow.start("session")
  elseif what == "all" then
    ns.AwardsShow.start("all")
  else
    say("type /tc awards for this session or /tc awards all for all time.")
  end
end

local function session(rest)
  if rest:lower() ~= "new" then printHelp(); return end
  ns.Session.newByHand()
  say("new session started. Everyone's session stats start from 0.")
end

local function stats(rest)
  local what = rest:lower():gsub("%s+", " ")
  if what == "reset" then
    say("this sets all your own stats (this session and all time) back to 0. Type /tc stats reset yes to do it.")
  elseif what == "reset yes" then
    ns.StatsStore.resetMine()
    ns.Bus.fire("STATS_CHANGED") -- the board and the titles show the zeros at once
    if ns.Modules.isEnabled("stats") then ns.Stats.send() end -- friends see the zeros (off: they see nothing)
    say("your stats are back to 0.")
  else
    printHelp()
  end
end

local ACTIONS = {
  [""] = function() ns.Settings.toggle() end,
  show = function() setPanel(true) end,
  hide = function() setPanel(false) end,
  minimap = toggleMinimap,
  mini = function() Commands.toggleMini(false) end,
  minimize = function() Commands.toggleMini(false) end,
  recent = function() ns.Recent.toggle() end,
  status = setStatus,
  mock = mock,
  afk = function() ns.Panel.toggleAway() end,
  new = function() ns.Changelog.open() end,
  rankup = function() ns.RankUp.run() end,
  cal = function() ns.Calendar.toggle() end,
  recap = function() ns.Recap.show() end,
  calendar = function() ns.Calendar.toggle() end,
  ranks = function() ns.RankUp.run() end,
  news = function() ns.Changelog.open() end,
  changelog = function() ns.Changelog.open() end,
  meet = meetCommand,
  reset = function()
    ns.Settings.open()
    ns.Settings.confirmReset()
  end,
  report = function() ns.Report.show() end,
  debug = toggleDebug,
  add = addName,
  remove = removeName,
  awards = awards,
  session = session,
  stats = stats,
  test = function(rest) ns.TestTools.command(rest) end,
}

function Commands.run(msg)
  local cmd, rest = Commands.parse(msg)
  local action = ACTIONS[cmd]
  if action then
    action(rest)
  else
    printHelp()
  end
end

SLASH_TWIZCREW1 = "/tc"
SLASH_TWIZCREW2 = "/twizcrew"
if type(SlashCmdList) == "table" then
  SlashCmdList.TWIZCREW = function(msg) ns.Log.safe(FEATURE, Commands.run, msg) end
end
