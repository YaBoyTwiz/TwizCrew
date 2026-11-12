-- Test runner. Run from the repo root via tests/run.sh [pattern].
-- A test file returns { files = {...} | "toc", tests = { name = function(ns, A, W, H) end } }.
-- H is a fresh multi-client helper per test (see newHarness below).
local Stub = dofile("tests/wowstub.lua")

local A = {}
local function deepEq(a, b)
  if a == b then return true end
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

local function loadFiles(W, ns, files)
  for _, file in ipairs(files) do
    local chunk = assert(loadfile("TwizCrew/" .. file))
    setfenv(chunk, W.env)
    chunk("TwizCrew", ns)
  end
  -- In the real game automatic mode copies a message to the channel only after the channel delivered something
  -- (or for a PING). Most tests are about what is sent, not about that rule, so they start as if it had delivered;
  -- a test of the rule puts its own ns.Comm.echoCount back.
  if ns.Comm and ns.Comm.echoCount then
    local real = ns.Comm.echoCount
    W.realEchoCount = real -- a test of the rule itself restores it: ns.Comm.echoCount = W.realEchoCount
    ns.Comm.echoCount = function() return math.max(1, real()) end
  end
end

-- Each client gets its own math.random: deterministic (seeded from the name) and independent of the others.
local function clientMath(name)
  local M = 2147483647
  local seed = 7
  for i = 1, #name do seed = (seed * 31 + name:byte(i)) % M end
  if seed == 0 then seed = 1 end
  local m = {}
  for k, v in pairs(math) do m[k] = v end
  function m.random(a, b)
    seed = (seed * 16807) % M
    local r = (seed - 1) / (M - 1)
    if a == nil then return r end
    if b == nil then a, b = 1, a end
    return a + math.floor(r * (b - a + 1))
  end
  function m.randomseed(s) seed = math.floor(tonumber(s) or 1) % (M - 1) + 1 end
  return m
end

local function channelNameOf(W, index)
  for name, i in pairs(W.state.channels or {}) do if i == index then return name end end
end

-- Would this addon message (as recorded in from.sent) reach `to` in the real game?
-- A message the game refused (a result other than success) reaches nobody. Like WoW Forever, an addon message to a
-- custom channel reaches nobody either (the game takes it and never delivers it), unless H.channelDelivers is set.
local function reaches(from, to, m, channelDelivers)
  if m.result ~= nil and m.result ~= 0 and m.result ~= true then return false end
  local t = m.chatType
  if t == "CHANNEL" then
    if not channelDelivers then return false end
    local name = channelNameOf(from, m.target)
    return name ~= nil and to.state.channels[name] ~= nil
  elseif t == "PARTY" or t == "RAID" then
    return true
  elseif t == "GUILD" then
    return (from.state.inGuild and to.state.inGuild) and true or false
  elseif t == "WHISPER" then
    local target = tostring(m.target or "")
    return target == to.state.player or target == to.state.player .. "-" .. to.state.realm
  end
  return false
end

local SIM_STEP = 0.1 -- seconds per simulation step

-- Multi-client helper:
--   H.client(name, state) -> W, ns   a full TOC load in its own fake game (state: W.state overrides, set first)
--   H.link(W, ...)                   these clients hear each other's addon messages from now on
--   H.advance(seconds, onStep)       all clients' clocks move together; messages are delivered every step
-- The channel member list (ListChannelByName -> CHAT_MSG_CHANNEL_LIST) and join / leave notices work between linked
-- clients, as in the game.
local function newHarness()
  local H = { clients = {}, linked = {}, elapsed = 0, channelDelivers = false, events = {} }

  local function isLinked(W)
    for _, L in ipairs(H.linked) do if L == W then return true end end
    return false
  end

  -- Channel events are fired at the next delivery, not inside the call that caused them.
  local function later(W, ...)
    H.events[#H.events + 1] = { W = W, args = { ... } }
  end

  local function noticeOthers(W, event, name)
    if not isLinked(W) then return end
    for _, other in ipairs(H.linked) do
      local idx = other.state.channels[name]
      if other ~= W and idx then later(other, event, "", W.state.player, "", name, "", "", 0, idx, name) end
    end
  end

  local function setupChannels(W)
    W.env.ListChannelByName = function(name)
      local idx = W.state.channels[name]
      if not idx then return end
      local names = {}
      for _, other in ipairs(H.linked) do
        if other.state.channels[name] then names[#names + 1] = other.state.player end
      end
      if not isLinked(W) then names = { W.state.player } end
      later(W, "CHAT_MSG_CHANNEL_LIST", table.concat(names, ", "), "", "", name, "", "", 0, idx, name)
    end
    local join, leave = W.env.JoinChannelByName, W.env.LeaveChannelByName
    W.env.JoinChannelByName = function(name, ...)
      local was = W.state.channels[name]
      join(name, ...)
      if not was and W.state.channels[name] then noticeOthers(W, "CHAT_MSG_CHANNEL_JOIN", name) end
    end
    W.env.LeaveChannelByName = function(name, ...)
      local was = W.state.channels[name]
      leave(name, ...)
      if was then noticeOthers(W, "CHAT_MSG_CHANNEL_LEAVE", name) end
    end
  end

  function H.client(name, state)
    local W = Stub.new()
    W.state.player = name
    for k, v in pairs(state or {}) do W.state[k] = v end
    W.clock = W.clock + H.elapsed
    W.env.math = clientMath(name)
    setupChannels(W)
    W.cursor = 0
    local ns = {}
    loadFiles(W, ns, tocFiles())
    -- state.version / state.restartSince stand for another release's code (the constants in Core/Init.lua)
    if W.state.version then ns.VERSION = W.state.version end
    if W.state.restartSince then ns.RESTART_SINCE = W.state.restartSince end
    H.clients[#H.clients + 1] = W
    return W, ns
  end

  function H.link(...)
    for _, W in ipairs({ ... }) do
      local known = false
      for _, L in ipairs(H.linked) do if L == W then known = true end end
      if not known then H.linked[#H.linked + 1] = W end
    end
  end

  -- Every message a linked client sent since the last delivery arrives as CHAT_MSG_ADDON at the others.
  function H.deliver()
    while #H.events > 0 do
      local list = H.events
      H.events = {}
      for _, e in ipairs(list) do e.W:fire(unpack(e.args)) end
    end
    for _, from in ipairs(H.linked) do
      while from.cursor < #from.sent do
        from.cursor = from.cursor + 1
        local m = from.sent[from.cursor]
        local sender = from.state.player .. "-" .. from.state.realm
        for _, to in ipairs(H.linked) do
          if to ~= from and reaches(from, to, m, H.channelDelivers) then
            to:fire("CHAT_MSG_ADDON", m.prefix, m.text, m.chatType, sender)
          end
        end
      end
    end
  end

  function H.advance(seconds, onStep)
    H.deliver()
    local steps = math.max(1, math.floor(seconds / SIM_STEP + 0.5))
    for _ = 1, steps do
      for _, W in ipairs(H.clients) do W:advance(SIM_STEP) end
      H.elapsed = H.elapsed + SIM_STEP
      H.deliver()
      if onStep then onStep() end
    end
  end

  return H
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
        loadFiles(W, ns, files)
        -- Tests are written against the stub's version (W.state.version), not the real release number in
        -- Core/Init.lua, so bumping the version for a release never breaks them.
        if ns.VERSION and W.state.version then
          ns.VERSION = W.state.version
          ns.RESTART_SINCE = W.state.restartSince or W.state.version
        end
        suite.tests[name](ns, A, W, newHarness())
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
