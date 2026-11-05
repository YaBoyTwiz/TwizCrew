-- Rolling log, safe calls (ns.Log.safe) and the debug print.
local ADDON, ns = ...

local Log = {}
ns.Log = Log

Log.chatDebug = false
Log.onBroken = function() end -- Task 3 replaces this

local LEVELS = { info = "INFO", warn = "WARN", error = "ERROR", debug = "DEBUG" }

local store = {}   -- the array lines are written to (a temporary one until attach)
local failures = {} -- featureId -> times of recent errors
local broken = {}   -- featureId -> true once onBroken has been called

local function stamp()
  if type(date) == "function" then
    local ok, text = pcall(date, "%H:%M:%S")
    if ok and type(text) == "string" then return "[" .. text .. "] " end
  end
  return ""
end

local function trim()
  local extra = #store - ns.Config.LOG_MAX
  if extra > 0 then
    for i = 1, #store - extra do store[i] = store[i + extra] end
    for i = #store, #store - extra + 1, -1 do store[i] = nil end
  end
end

-- Saved lines from an older or broken file may hold things that are not text: those are dropped.
function Log.attach(lines)
  if type(lines) ~= "table" then lines = {} end
  local kept = {}
  for i = 1, table.maxn(lines) do
    if type(lines[i]) == "string" then kept[#kept + 1] = lines[i] end
  end
  for k in pairs(lines) do lines[k] = nil end
  for i, line in ipairs(kept) do lines[i] = line end
  local early = store
  store = lines
  for _, line in ipairs(early) do store[#store + 1] = line end
  trim()
end

function Log.add(level, fmt, ...)
  local label = LEVELS[level] or "INFO"
  local ok, text = pcall(string.format, tostring(fmt), ...)
  if not ok then text = tostring(fmt) end
  store[#store + 1] = stamp() .. label .. " " .. text
  trim()
end

function Log.lines() return store end

function Log.errors(n)
  local found = {}
  for i = #store, 1, -1 do
    local line = store[i]
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

local function noteFailure(featureId)
  local now = ns.now()
  local list = failures[featureId] or {}
  failures[featureId] = list
  list[#list + 1] = now
  while list[1] and now - list[1] > ns.Config.BREAK_WINDOW do table.remove(list, 1) end
  if #list >= ns.Config.BREAK_ERRORS and not broken[featureId] then
    broken[featureId] = true
    local ok, err = pcall(Log.onBroken, featureId)
    if not ok then Log.add("error", "onBroken for %s failed: %s", featureId, tostring(err)) end
  end
end

-- Runs fn(...) and never lets an error escape. Returns true, results... or false, err.
function Log.safe(featureId, fn, ...)
  local args, count = { ... }, select("#", ...)
  local trace
  local function handler(err)
    if type(debugstack) == "function" then trace = debugstack(3) end
    return err
  end
  local result = { xpcall(function() return fn(unpack(args, 1, count)) end, handler) }
  if result[1] then return unpack(result, 1, table.maxn(result)) end
  local err = tostring(result[2])
  Log.add("error", "%s: %s", tostring(featureId), err)
  if trace then Log.add("debug", "%s traceback: %s", tostring(featureId), (tostring(trace):gsub("\n", " < "))) end
  noteFailure(featureId)
  return false, err
end
