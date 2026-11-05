-- Test runner. Run from the repo root via tests/run.sh [pattern].
-- A test file returns { files = {...} | "toc", tests = { name = function(ns, A, W) end } }.
local Stub = dofile("tests/wowstub.lua")

local A = {}
local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function show(v)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = "[" .. show(k) .. "]=" .. show(v[k]) end
  return "{" .. table.concat(out, ", ") .. "}"
end
function A.eq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end
function A.ok(v, msg) if not v then error(msg or "expected a truthy value", 2) end end
function A.no(v, msg) if v then error(msg or "expected a falsy value", 2) end end
function A.errors(fn, pattern)
  local ok, err = pcall(fn)
  if ok then error("expected an error, none raised", 2) end
  if pattern and not tostring(err):find(pattern) then
    error("error " .. tostring(err) .. " does not match " .. pattern, 2)
  end
end
function A.contains(str, sub, msg)
  if type(str) ~= "string" or not str:find(sub, 1, true) then
    error((msg and (msg .. ": ") or "") .. show(str) .. " does not contain " .. show(sub), 2)
  end
end

local function tocFiles()
  local list = {}
  local f = assert(io.open("TwizCrew/TwizCrew.toc", "r"))
  for line in f:lines() do
    line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 2) ~= "##" then list[#list + 1] = (line:gsub("\\", "/")) end
  end
  f:close()
  return list
end

local function matches(pattern, id)
  if not pattern then return true end
  for alt in (pattern .. "|"):gmatch("(.-)|") do
    if alt ~= "" then
      if id:find(alt, 1, true) then return true end
      local ok, found = pcall(string.find, id, alt)
      if ok and found then return true end
    end
  end
  return false
end

local pattern = arg and arg[1]
local total, failed, failures = 0, 0, {}

local p = io.popen("ls tests/test_*.lua | sort")
local testFiles = {}
for line in p:lines() do testFiles[#testFiles + 1] = line end
p:close()

for _, path in ipairs(testFiles) do
  local chunk, loadErr = loadfile(path)
  local suiteOk, suite = false, loadErr
  if chunk then suiteOk, suite = pcall(chunk) end
  if not suiteOk or type(suite) ~= "table" or type(suite.tests) ~= "table" then
    total = total + 1
    failed = failed + 1
    failures[#failures + 1] = "FAIL " .. path .. " (could not load)\n  " .. tostring(suiteOk and "no tests table returned" or suite)
    suite = { tests = {} }
  end
  local names = {}
  for name in pairs(suite.tests) do names[#names + 1] = name end
  table.sort(names)
  local files = suite.files == "toc" and tocFiles() or suite.files or {}
  for _, name in ipairs(names) do
    local id = path:match("([^/]+)$") .. ":" .. name
    if matches(pattern, id) then
      total = total + 1
      local W = Stub.new()
      local ns = {}
      local ok, err = pcall(function()
        for _, file in ipairs(files) do
          local chunk = assert(loadfile("TwizCrew/" .. file))
          setfenv(chunk, W.env)
          chunk("TwizCrew", ns)
        end
        suite.tests[name](ns, A, W)
      end)
      if not ok then
        failed = failed + 1
        failures[#failures + 1] = "FAIL " .. id .. "\n  " .. tostring(err)
      end
    end
  end
end

for _, f in ipairs(failures) do print(f) end
if total == 0 then
  print("NO TESTS MATCHED")
  os.exit(1)
end
if failed > 0 then
  print("FAILED " .. failed .. " of " .. total)
  os.exit(1)
end
print("ALL PASSED (" .. total .. " tests)")
