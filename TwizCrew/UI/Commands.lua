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
  "/tc status <text> - a short note your friends see next to your name (/tc status alone clears it)",
  "/tc reset - put every setting back to normal (asks first)",
  "/tc report - a health check you can copy and paste to Discord",
  "/tc debug - turn technical chat messages on or off",
  "/tc add <name> - add a friend by name, used when the hidden channel does not work",
  "/tc remove <name> - take a name off that list",
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
  if Ambiguate(name, "none"):lower() == ns.playerName():lower() then
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

local function setPanel(on)
  if on then
    for _, id in ipairs(ns.Modules.broken()) do
      if id == "panel" then
        say("the crew panel turned itself off after errors. Type /reload to try again.")
        return
      end
    end
    ns.Modules.setEnabled("panel", true)
    say("panel shown.")
  else
    ns.Modules.setEnabled("panel", false)
    say("panel hidden. Type /tc show to bring it back.")
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

local function toggleDebug()
  local on = not ns.Modules.setting("comm", "debug")
  ns.Modules.set("comm", "debug", on)
  say(on and "technical messages on. Type /tc debug again to turn them off." or "technical messages off.")
end

local ACTIONS = {
  [""] = function() ns.Settings.toggle() end,
  show = function() setPanel(true) end,
  hide = function() setPanel(false) end,
  status = setStatus,
  reset = function()
    ns.Settings.open()
    ns.Settings.confirmReset()
  end,
  report = function() ns.Report.show() end,
  debug = toggleDebug,
  add = addName,
  remove = removeName,
}

function Commands.run(msg)
  local cmd, rest = Commands.parse(msg)
  local action = ACTIONS[cmd]
  if action then
    action(rest)
  else
    for _, line in ipairs(HELP) do print(line) end
  end
end

SLASH_TWIZCREW1 = "/tc"
SLASH_TWIZCREW2 = "/twizcrew"
if type(SlashCmdList) == "table" then
  SlashCmdList.TWIZCREW = function(msg) ns.Log.safe(FEATURE, Commands.run, msg) end
end
