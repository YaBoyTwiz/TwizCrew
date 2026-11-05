-- Stats board: pure rules (no game calls). Tunables come from ns.Config at call time.
local _, ns = ...

local L = {}
ns.StatsLogic = L

local function isNumber(v) return type(v) == "number" and v == v end

-- Which kind of travel counts right now (nil = none).
function L.motionBucket(s)
  s = s or {}
  if s.taxi or s.dead then return nil end
  if s.mounted then return "mount" end
  if s.swimming then return "swim" end
  return "foot"
end

function L.speedYards(speed, elapsed, secret)
  if secret then return nil end
  if not isNumber(speed) or not isNumber(elapsed) then return nil end
  if speed < 0 or elapsed < 0 or speed > ns.Config.MAX_RUN_SPEED then return nil end
  return speed * elapsed
end

function L.positionYards(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return nil end
  if not (isNumber(a.x) and isNumber(a.y) and isNumber(b.x) and isNumber(b.y)) then return nil end
  if not (isNumber(a.t) and isNumber(b.t)) or b.t <= a.t then return nil end
  if a.instance == nil or a.instance ~= b.instance then return nil end
  local dx, dy = b.x - a.x, b.y - a.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d / (b.t - a.t) > ns.Config.MAX_RUN_SPEED then return nil end
  return d
end

function L.classifyDeath(i)
  local c = ns.Config
  local r = {}
  local now = i.now
  if isNumber(i.fallingAt) and now - i.fallingAt <= c.FALL_WINDOW then r.fall = true end
  if i.breathRunning or (isNumber(i.breathStoppedAt) and now - i.breathStoppedAt <= c.DROWN_GRACE) then
    r.drown = true
  end
  local t = i.target
  if type(t) == "table" and isNumber(t.at) and now - t.at <= c.WEAK_WINDOW
      and type(t.level) == "number" and t.level >= 1 and isNumber(i.myLevel)
      and i.myLevel - t.level >= c.WEAK_LEVELS then
    r.weak = true
    r.mobLevel = t.level
    r.mobName = t.name
  end
  if isNumber(i.aliveAt) and now - i.aliveAt <= c.AGAIN_WINDOW then
    r.again = true
    r.againSeconds = math.floor(now - i.aliveAt)
  end
  return r
end

-- fixed marks, then (optionally) every `step` from `from` on.
local MILESTONES = {
  deaths = { marks = { 5, 10, 20, 50 } },
  steps = { marks = { 10000, 50000 }, step = 100000 },
  jumps = { marks = { 1000 }, step = 5000, from = 5000 },
  quit = { marks = { 3 } },
}

function L.milestone(kind, old, new)
  local m = MILESTONES[kind]
  if not m or not isNumber(old) or not isNumber(new) then return nil end
  local best
  if m.step then
    local k = math.floor(new / m.step) * m.step
    if k >= (m.from or m.step) and k > old and k <= new then best = k end
  end
  for _, mark in ipairs(m.marks) do
    if mark > old and mark <= new and (not best or mark > best) then best = mark end
  end
  return best
end

function L.newLimiter(gap)
  local l = { last = {} }
  function l:allow(key, now)
    local t = self.last[key]
    if t ~= nil and now - t < gap then return false end
    self.last[key] = now
    return true
  end
  return l
end

-- Turn a game format string ("%1$s has defeated %2$s", "%s x%d.") into a Lua pattern.
-- Returns pattern, list of { arg = n, kind = "s"|"d" } in capture order.
local function formatPattern(fmt)
  local out, caps, next = { "^" }, {}, 1
  local i, n = 1, #fmt
  while i <= n do
    local ch = fmt:sub(i, i)
    if ch == "%" then
      local num, kind = fmt:match("^%%(%d+)%$([sd])", i)
      if num then
        i = i + #num + 3
      else
        kind = fmt:match("^%%([sd])", i)
        if kind then
          num = next
          i = i + 2
        end
      end
      if kind then
        caps[#caps + 1] = { arg = tonumber(num), kind = kind }
        next = next + 1
        out[#out + 1] = kind == "d" and "(%d+)" or "(.-)"
      else
        out[#out + 1] = "%%"
        i = i + (fmt:sub(i + 1, i + 1) == "%" and 2 or 1)
      end
    else
      out[#out + 1] = ch:find("^%p") and ("%" .. ch) or ch
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out), caps
end

local function matchFormat(text, fmt)
  if type(text) ~= "string" or type(fmt) ~= "string" then return nil end
  local pat, caps = formatPattern(fmt)
  local found = { text:match(pat) }
  if found[1] == nil then return nil end
  local byArg = {}
  for idx, cap in ipairs(caps) do byArg[cap.arg] = found[idx] end
  return byArg
end

local function stripRealm(name)
  return (tostring(name or ""):gsub("%-.*$", ""))
end

function L.duelResult(text, me, knockoutFmt, retreatFmt)
  me = stripRealm(me)
  local a = matchFormat(text, knockoutFmt)
  local b = (not a) and matchFormat(text, retreatFmt) or nil
  local r = a or b
  if not r or not r[1] or not r[2] then return nil end
  local winner, loser = stripRealm(r[1]), stripRealm(r[2])
  if winner == me then return "won" end
  if loser == me then return "lost" end
  return nil
end

function L.junkCount(text, selfFmt, multiFmt)
  local r = matchFormat(text, multiFmt)
  local count
  if r then
    count = tonumber(r[2])
  else
    r = matchFormat(text, selfFmt)
    count = 1
  end
  if not r or not r[1] or not count then return 0 end
  if not r[1]:lower():find("^|cff9d9d9d") then return 0 end
  return count
end

function L.isPull(me, members)
  if type(me) ~= "table" or not me.dungeon then return false end
  local any = false
  for _, m in ipairs(members or {}) do
    if m.online and m.inInstance and m.zone == me.zone then
      if m.tags and m.tags.COMBAT then return false end
      any = true
    end
  end
  return any
end

function L.newWipeWatch(window)
  local w = { deadAt = {}, latched = nil }
  function w:dead(name, now) self.deadAt[name] = now end
  function w:alive(name)
    self.deadAt[name] = nil
    if self.latched and self.latched[name] then self.latched = nil end
  end
  function w:check(names, now)
    if self.latched or type(names) ~= "table" or #names < 2 then return false end
    local lo, hi
    for _, name in ipairs(names) do
      local t = self.deadAt[name]
      if t == nil then return false end
      if not lo or t < lo then lo = t end
      if not hi or t > hi then hi = t end
    end
    if hi - lo > window then return false end
    self.latched = {}
    for _, name in ipairs(names) do self.latched[name] = true end
    return true
  end
  return w
end
