-- Rolling log, safe calls (ns.Log.safe) and the debug print.
local ADDON, ns = ...

local Log = {}
ns.Log = Log

Log.chatDebug = false
Log.onBroken = function() end -- Modules replaces this
Log.onRearm = function() end -- Modules replaces this

local LEVELS = { info = "INFO", warn = "WARN", error = "ERROR", debug = "DEBUG" }

local store = {}   -- the array lines are written to (a temporary one until attach)
local problems = {} -- the ERROR and WARN lines (and tracebacks), kept apart so chatter cannot push them out
local counters = {}  -- session counters (Log.count)
local breaks = {}    -- featureId -> times it was marked broken this session (for the re-arm delay)
local failures = {} -- featureId -> times of recent errors
local broken = {}   -- featureId -> true once onBroken has been called

local function stamp()
  if type(date) == "function" then
    local ok, text = pcall(date, "%H:%M:%S")
    if ok and type(text) == "string" then return "[" .. text .. "] " end
  end
  return ""
end

local function trimTo(list, max)
  local extra = #list - max
  if extra > 0 then
    for i = 1, #list - extra do list[i] = list[i + extra] end
    for i = #list, #list - extra + 1, -1 do list[i] = nil end
  end
end

local function trim() trimTo(store, ns.Config.LOG_MAX) end

local function repair(lines)
  if type(lines) ~= "table" then lines = {} end
  local kept = {}
  for i = 1, table.maxn(lines) do
    if type(lines[i]) == "string" then kept[#kept + 1] = lines[i] end
  end
  for k in pairs(lines) do lines[k] = nil end
  for i, line in ipairs(kept) do lines[i] = line end
  return lines
end

-- Saved lines from an older or broken file may hold things that are not text: those are dropped.
function Log.attach(lines, saved)
  lines = repair(lines)
  saved = repair(saved)
  local early, earlyProblems = store, problems
  store, problems = lines, saved
  for _, line in ipairs(early) do store[#store + 1] = line end
  for _, line in ipairs(earlyProblems) do problems[#problems + 1] = line end
  trim()
  trimTo(problems, ns.Config.PROBLEMS_MAX)
end

local function write(level, text, keep)
  local line = stamp() .. (LEVELS[level] or "INFO") .. " " .. text
  store[#store + 1] = line
  trim()
  if keep or level == "error" or level == "warn" then
    problems[#problems + 1] = line
    trimTo(problems, ns.Config.PROBLEMS_MAX)
  end
end

function Log.add(level, fmt, ...)
  local ok, text = pcall(string.format, tostring(fmt), ...)
  if not ok then text = tostring(fmt) end
  write(level, text)
end

function Log.problems() return problems end

function Log.count(key) counters[key] = (counters[key] or 0) + 1 end

function Log.counts()
  local out = {}
  for k, v in pairs(counters) do out[k] = v end
  return out
end

function Log.lines() return store end

function Log.errors(n)
  local found = {}
  for i = #problems, 1, -1 do
    local line = problems[i]
    if line:find("^%[[^%]]*%] ERROR ") or line:find("^ERROR ") then
      found[#found + 1] = line
      if #found >= n then break end
    end
  end
  local out = {}
  for i = #found, 1, -1 do out[#out + 1] = found[i] end
  return out
end

function Log.debug(fmt, ...)
  Log.add("debug", fmt, ...)
  if Log.chatDebug then
    local ok, text = pcall(string.format, tostring(fmt), ...)
    print("TwizCrew: " .. (ok and text or tostring(fmt)))
  end
end

local function rearm(featureId)
  failures[featureId] = nil
  broken[featureId] = nil
  local ok, err = pcall(Log.onRearm, featureId)
  if not ok then Log.add("error", "onRearm for %s failed: %s", featureId, tostring(err)) end
end

local function noteFailure(featureId)
  local now = ns.now()
  local list = failures[featureId] or {}
  failures[featureId] = list
  list[#list + 1] = now
  while list[1] and now - list[1] > ns.Config.BREAK_WINDOW do table.remove(list, 1) end
  if #list >= ns.Config.BREAK_ERRORS and not broken[featureId] then
    broken[featureId] = true
    breaks[featureId] = (breaks[featureId] or 0) + 1
    local ok, err = pcall(Log.onBroken, featureId)
    if not ok then Log.add("error", "onBroken for %s failed: %s", featureId, tostring(err)) end
    -- Switched back on later: twice as long after each further break (at most 30 minutes).
    if C_Timer and C_Timer.After then
      local delay = math.min(ns.Config.BREAK_REARM * 2 ^ (breaks[featureId] - 1), 1800)
      C_Timer.After(delay, function() rearm(featureId) end)
    end
  end
end

local lastTrace
local function handler(err)
  if type(debugstack) == "function" then lastTrace = debugstack(3) end
  return err
end

-- Failure path (and the pass-through of results) of Log.safe: ok is xpcall's first result.
local function finish(featureId, ok, ...)
  if ok then return ok, ... end
  local err = tostring((...))
  Log.add("error", "%s: %s", tostring(featureId), err)
  if lastTrace then
    write("debug", string.format("%s traceback: %s", tostring(featureId), (tostring(lastTrace):gsub("\n", " < "))), true)
    lastTrace = nil
  end
  noteFailure(featureId)
  return false, err
end

-- The game's xpcall passes extra arguments on to the function; plain Lua 5.1 does not.
local passesArgs = select(2, xpcall(function(a) return a end, function() end, 7)) == 7

-- Runs fn(...) and never lets an error escape. Returns true, results... or false, err.
if passesArgs then
  function Log.safe(featureId, fn, ...)
    lastTrace = nil
    return finish(featureId, xpcall(fn, handler, ...))
  end
else
  function Log.safe(featureId, fn, ...)
    lastTrace = nil
    local args, count = { ... }, select("#", ...)
    return finish(featureId, xpcall(function() return fn(unpack(args, 1, count)) end, handler))
  end
end
