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

-- Would this addon message (as recorded in from.sent) reach `to` in the real game?
-- A message the game refused (a result other than success) reaches nobody. Like WoW Forever, an addon message to a
-- custom channel reaches nobody either (the game takes it and never delivers it).
local function reaches(from, to, m)
  if m.result ~= nil and m.result ~= 0 and m.result ~= true then return false end
  local t = m.chatType
  if t == "PARTY" or t == "RAID" then
    return true
  elseif t == "GUILD" then
    local a, b = from.state.guild, to.state.guild
    if a or b then return (a ~= nil and b ~= nil and a.name == b.name) end -- the same guild, the sender included
    return (from.state.inGuild and to.state.inGuild) and true or false -- older tests: a bare flag, sender excluded
  elseif t == "WHISPER" then
    local target = tostring(m.target or "")
    return target == to.state.player or target == to.state.player .. "-" .. to.state.realm
  end
  return false
end

local SIM_STEP = 0.1 -- seconds per simulation step

-- Multi-client helper:
--   H.client(name, state) -> W, ns   a full TOC load in its own fake game (state: W.state overrides, set first;
--                                    state.noGuild = true: this client is in no guild, even once linked)
--   H.link(W, ...)                   these clients hear each other's addon messages from now on. A linked client that
--                                    is in no guild yet (and not noGuild) joins the harness guild "Crew Guild" (see
--                                    H.joinCrewGuild), so linked clients share a guild unless a test says otherwise.
--   H.joinCrewGuild(W)               puts W in the harness guild "Crew Guild": one member list shared by every client
--                                    in it (W's player name, class, level, zone, online, a GUID); the others get a
--                                    GUILD_ROSTER_UPDATE at the next delivery, like the game sends when someone joins.
--   H.advance(seconds, onStep)       all clients' clocks move together; messages are delivered every step
--   H.guild(name, W1, W2, ..., extras)  puts the clients in one guild called `name`: each client's W.state.guild
--                                    gets a member entry for every client (its player name, class, level and zone as
--                                    they are now, online, a GUID "Player-1-000N") plus `extras`, an optional last
--                                    argument: an array of entries for members without the addon or offline ones, e.g.
--                                    { { name = "Ginkan Other", class = "MAGE" }, ... } (defaults: WARRIOR, level 10,
--                                    "Elwynn Forest", rank "Member" / rankIndex 2, offline, lastOnline 1 day, a GUID).
--                                    Every client gets its own copy of the list. A GUILD send reaches every linked
--                                    client of the same guild name, the sender too; the sender name follows the sender's
--                                    W.state.senderForm: "full" (default: "Chaos Deathbringr"), "first" ("Chaos"),
--                                    "realm" ("Chaos Deathbringr-Realm"). Link the clients with H.link as usual.
local function newHarness()
  local H = { clients = {}, linked = {}, elapsed = 0, events = {} }
  local crewGuild = { name = "Crew Guild", members = {} }

  -- Game events for a client, fired at the next delivery, not inside the call that caused them.
  local function later(W, ...)
    H.events[#H.events + 1] = { W = W, args = { ... } }
  end

  function H.client(name, state)
    local W = Stub.new()
    W.state.player = name
    for k, v in pairs(state or {}) do W.state[k] = v end
    W.clock = W.clock + H.elapsed
    W.env.math = clientMath(name)
    W.cursor = 0
    local ns = {}
    loadFiles(W, ns, tocFiles())
    -- state.version / state.restartSince stand for another release's code (the constants in Core/Init.lua)
    if W.state.version then ns.VERSION = W.state.version end
    if W.state.restartSince then ns.RESTART_SINCE = W.state.restartSince end
    H.clients[#H.clients + 1] = W
    return W, ns
  end

  function H.joinCrewGuild(W)
    local st = W.state
    st.noGuild = nil
    local entry
    for _, m in ipairs(crewGuild.members) do if m.name == st.player then entry = m end end
    if entry then
      entry.online, entry.class, entry.level, entry.zone = true, st.class, st.level, st.zone
    else
      crewGuild.members[#crewGuild.members + 1] = { name = st.player, class = st.class, level = st.level,
        zone = st.zone, rank = "Member", rankIndex = 2, online = true,
        guid = string.format("Player-1-%04d", #crewGuild.members + 1) }
    end
    st.guild = crewGuild
    for _, other in ipairs(H.clients) do
      if other ~= W and other.state.guild == crewGuild then later(other, "GUILD_ROSTER_UPDATE", false) end
    end
  end

  function H.guild(name, ...)
    local args = { ... }
    local extras = {}
    if #args > 0 and type(args[#args]) == "table" and not args[#args].env then extras = table.remove(args) end
    local entries = {}
    local function guid() return string.format("Player-1-%04d", #entries + 1) end
    for _, W in ipairs(args) do
      local st = W.state
      entries[#entries + 1] = { name = st.player, class = st.class, level = st.level, zone = st.zone, rank = "Member",
        rankIndex = 2, online = true, guid = guid() }
    end
    for _, e in ipairs(extras) do
      local m = {}
      for k, v in pairs(e) do m[k] = v end
      m.class, m.level, m.zone = m.class or "WARRIOR", m.level or 10, m.zone or "Elwynn Forest"
      m.rank, m.rankIndex = m.rank or "Member", m.rankIndex or 2
      if m.online == nil then m.online = false end
      m.guid = m.guid or guid()
      if not m.online and not m.lastOnline then m.lastOnline = { 0, 0, 1, 0 } end
      entries[#entries + 1] = m
    end
    for _, W in ipairs(args) do
      local copy = {}
      for i, m in ipairs(entries) do
        local c = {}
        for k, v in pairs(m) do c[k] = type(v) == "table" and { unpack(v) } or v end
        copy[i] = c
      end
      W.state.guild = { name = name, members = copy }
    end
  end

  function H.link(...)
    for _, W in ipairs({ ... }) do
      local known = false
      for _, L in ipairs(H.linked) do if L == W then known = true end end
      if not known then H.linked[#H.linked + 1] = W end
      if W.state.guild == nil and not W.state.noGuild and not W.state.inGuild then H.joinCrewGuild(W) end
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
        local inGuildList = m.chatType == "GUILD" and from.state.guild ~= nil
        if inGuildList then
          local form = from.state.senderForm or "full"
          if form == "first" then sender = from.state.player:match("^(%S+)") or from.state.player
          elseif form == "full" then sender = from.state.player end
        end
        for _, to in ipairs(H.linked) do
          if (to ~= from or inGuildList) and reaches(from, to, m) then
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

-- Single-client tests (the W a test gets): the player is in "Test Guild" with the friends most tests talk to, all
-- online, so sends go out as one GUILD message and those friends' whispers are trusted. A test about having no guild
-- sets W.state.guild = nil before anything starts.
local DEFAULT_GUILD = { "Twiz", "Frostie", "Ginkan", "Lurabe", "Pewpew", "Holybøi", "Chaos" }
local function defaultGuild(W)
  local members = {}
  for i, name in ipairs(DEFAULT_GUILD) do
    members[i] = { name = name, online = true, guid = string.format("Player-1-%04d", i) }
  end
  W.state.guild = { name = "Test Guild", members = members }
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
      defaultGuild(W)
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
