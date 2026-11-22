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
  "/tc guildtest - check that guild messages reach your guildmates' copies (needs one of them online with TwizCrew)",
  "/tc debug - turn technical chat messages on or off",
  "/tc forget <name> - delete an offline guildmate's saved stats and notes here; first or full name (/tc remove does the same). A member who just left the guild is only hidden and comes back with their data",
  "/tc guild - every set of saved crew data, numbered; /tc guild use - make the one in use this guild's",
  "/tc guild new - start fresh for this guild; /tc guild load <number> - use another set (nothing is deleted)",
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

-- /tc guild: every set of saved crew data, numbered (0 = the one in use), and what to type; "use [yes]": the data in
-- use becomes this guild's; "new": this guild starts fresh at the next /reload; "load <number> [yes]": that set
-- becomes this guild's at the next /reload. Nothing saved is ever deleted (Core/DB.lua, Crew/Guild.lua).
local NO_NAMES = "This game does not tell addons the guild's name, so TwizCrew uses one shared set of saved data."

local function friends(n) return n == 1 and "1 friend" or (n .. " friends") end

-- A set's real friends (test rows left out) and the newest last-seen date ("2026-11-21"; nil when none).
local function setInfo(set)
  local n, newest = 0, nil
  local roster = type(set) == "table" and set.roster
  for name, row in pairs(type(roster) == "table" and roster or {}) do
    if type(name) == "string" and not ns.isTestName(name) then
      n = n + 1
      local seen = type(row) == "table" and tonumber(row.lastSeen) or nil
      if seen and (not newest or seen > newest) then newest = seen end
    end
  end
  local ok, day = false, nil
  if newest then ok, day = pcall(date, "%Y-%m-%d", newest) end
  return n, ok and type(day) == "string" and day or nil
end

-- How a set's name reads: a guild's name, "from before guilds" (unnamed), "?"; kept-aside names say so.
local function nameOf(name)
  if name == "" then return "from before guilds" end
  if name == ns.Guild.PLACEHOLDER then return "\"?\"" end
  return ns.Util.safeText(name)
end

local function setLabel(entry)
  if entry.from ~= "bad" then return nameOf(entry.name) end
  local base, n = entry.key:match("^(.*)#(%d+)$")
  if base then return nameOf(base) .. " (kept aside " .. n .. ")" end
  return nameOf(entry.key) .. " (kept aside)"
end

-- "Old Guild, 14 friends"
local function setText(entry)
  return setLabel(entry) .. ", " .. friends((setInfo(entry.set)))
end

local REFUSED = {
  noguild = "this character is not in a guild.",
  changing = "Your guild is changing. Try again in a few seconds.",
  noname = "the game has not named your guild yet, so TwizCrew cannot tell which one it is.",
}

local function listSets(G)
  local name = G.inGuild() and (G.id() and ns.Util.safeText(G.id()) or "(the game gives no name)") or "none"
  say("this character's guild: " .. name)
  local here = G.inGuild() and G.here() or nil
  if here == G.PLACEHOLDER then say(NO_NAMES) end
  local sets = ns.DB.sets(ns.db)
  say("saved data (the number is for /tc guild load):")
  for _, entry in ipairs(sets) do
    local n, day = setInfo(entry.set)
    local label = setLabel(entry)
    if entry.from == "top" then
      if entry.name == "" and G.dataEmpty() then label = "new (nothing saved yet)" end
      label = label .. " (in use)"
    end
    print("  " .. entry.number .. ": " .. label .. ", " .. friends(n) .. (day and (", last seen " .. day) or ""))
  end
  local g = ns.db.guild
  local req, res = g.request, g.requestResult
  if type(req) == "table" then
    local whose = req.guild == G.PLACEHOLDER and "the shared set" or ns.Util.safeText(tostring(req.guild))
    say("waiting for " .. (req.char == ns.DB.charId() and "your" or "this character's") .. " next login: "
      .. (req.kind == "new" and "a fresh set" or ("the set " .. nameOf(tostring(req.key)))) .. " for " .. whose .. ".")
  end
  if type(res) == "table" then
    say("the last /tc guild request " .. (res.done and "was carried out." or ("was not carried out: "
      .. ns.Util.safeText(tostring(res.reason)) .. ".")))
  end
  if not G.inGuild() then return end
  if G.settling() then say(REFUSED.changing); return end
  if not here and G.deciding() then say(REFUSED.noname); return end
  if not here then
    say("the game does not name your guild right now. /tc guild load <number> uses a set here.")
    return
  end
  local shown = here == G.PLACEHOLDER and "this guild" or ns.Util.safeText(here)
  if G.needsReload() then
    say("type /reload to switch to " .. shown .. "'s own saved data.")
  elseif not G.active() then
    say("type /tc guild use to make set 0 " .. shown .. "'s, /tc guild new to start fresh, or /tc guild load"
      .. " <number> to use another set.")
  elseif #sets > 1 then
    say("/tc guild load <number> makes another set " .. shown .. "'s data.")
  end
end

local function guildCommand(rest)
  local G, safe = ns.Guild, ns.Util.safeText
  local what, arg = rest:lower():match("^(%S*)%s*(.-)$")
  if what == "" then listSets(G); return end
  local here = G.here()
  local shown = (here == nil or here == G.PLACEHOLDER) and "this guild" or safe(here)
  local ok, why, a, b
  if what == "use" and (arg == "" or arg == "yes") then
    ok, why, a, b = G.useHere(arg == "yes")
    if ok then say("the saved data in use now belongs to " .. shown .. ".")
    elseif why == "nofit" then
      say("Only " .. a .. " of " .. b .. " saved friends are in " .. shown .. ". If this really is your crew's guild,"
        .. " type /tc guild use yes.")
    elseif why == "noroster" then
      say("The saved data has no friend list to check against " .. shown .. ". If this is your crew's guild, type /tc"
        .. " guild use yes.")
    elseif why == "nolist" then say("the guild list has not come in yet. Try again in a few seconds.") end
  elseif what == "new" and (arg == "" or arg == "yes") then
    ok, why = G.newHere(arg == "yes")
    if ok then say(shown .. " gets its own fresh saved data. Type /reload to start it; nothing saved is deleted.")
    elseif why == "shared" then
      say("This game gives no guild names, so all your characters share one set. /tc guild new would start that shared"
        .. " set fresh. Type /tc guild new yes.")
    end
  elseif what == "load" then
    local n, yes = arg:match("^(%d+)%s*(%a*)$")
    n = tonumber(n)
    if not n or (yes ~= "" and yes ~= "yes") then
      say("type the number from /tc guild, like /tc guild load 1.")
      return
    end
    ok, why = G.loadHere(n, yes == "yes")
    if ok and yes == "yes" then say("Type /reload.")
    elseif ok then
      say("This will make set " .. n .. " (" .. setText(why) .. ") the data for " .. shown .. ". The data in use now is"
        .. " kept as a parked set. Type /tc guild load " .. n .. " yes.")
    elseif why == "nonumber" then say("there is no set " .. n .. ". Type /tc guild to see the numbers.")
    elseif why == "nopreview" then say("Type /tc guild load " .. n .. " first.")
    elseif why == "inuse" then say("set 0 is the data in use already.") end
  else
    say("type /tc guild, /tc guild use, /tc guild new or /tc guild load <number>.")
    return
  end
  if ok then return end
  if REFUSED[why] then say(REFUSED[why])
  elseif why == "named" then
    say("the saved data in use is " .. safe(tostring(G.dataGuild())) .. "'s. Type /reload to switch to " .. shown
      .. ".")
  elseif why == "parked" then say(shown .. " already has saved TwizCrew data. Type /reload to switch to it.")
  elseif why == "parkedShared" then
    say("the shared set (\"?\") is parked. To use it, type /tc guild load <number> (the numbers are in /tc guild).")
  elseif why == "inuse" and what ~= "load" then say("the saved data in use is already " .. shown .. "'s.") end
end

local function forgetName(rest)
  local name = Commands.normalizeName(rest)
  if not name then say("type a name after it, like /tc forget Frostie"); return end
  local ok, why, names = ns.Crew.forget(name)
  local safe = ns.Util.safeText(name)
  if ok then say("forgot " .. ns.Util.safeText(why or name) .. ".")
  elseif why == "that is you" then say("that's you.")
  elseif why == "which one" then
    say("which one? " .. ns.Util.safeText(table.concat(names or {}, ", ")) .. ". Type the full name.")
  elseif why == "online right now" then say(safe .. " is online right now; try again when they are offline.")
  else say(safe .. " is not on your list.") end
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
    local name = ns.Guild.keyOfUnit("target") -- their member key
    local dead = ns.Util.plain(UnitIsDeadOrGhost, "target")
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
    local typed = Commands.normalizeName(rest)
    local key, why = ns.Guild.resolveTyped(typed)
    if why == "ambiguous" then
      say("more than one member is called " .. ns.Util.safeText(rest) .. "; type the full name.")
      return
    end
    local name = key or ns.shortName(typed) -- the list does not know them: the first word, as before the guild
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
  guildtest = function() ns.GuildTest.run() end,
  debug = toggleDebug,
  remove = forgetName,
  forget = forgetName,
  guild = guildCommand,
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
