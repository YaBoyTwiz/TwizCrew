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

local patternCache = {} -- format string -> { pattern, caps } (the game's few formats never change)

local function matchFormat(text, fmt)
  if type(text) ~= "string" or type(fmt) ~= "string" then return nil end
  local cached = patternCache[fmt]
  if not cached then
    cached = { formatPattern(fmt) }
    patternCache[fmt] = cached
  end
  local pat, caps = cached[1], cached[2]
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

-- ---------------------------------------------------------------------------------------------
-- Formatting

function L.number(n)
  if not isNumber(n) or n == math.huge or n == -math.huge then return "0" end
  local s = string.format("%.0f", math.floor(n))
  local sign, digits = s:match("^(-?)(%d+)$")
  if not digits then return s end
  digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return sign .. digits
end

function L.duration(sec)
  sec = isNumber(sec) and math.max(0, math.floor(sec)) or 0
  local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
  if h >= 1 then return m > 0 and (h .. "h " .. m .. "m") or (h .. "h") end
  if m >= 1 then return m .. "m" end
  return sec .. "s"
end

function L.money(copper)
  copper = isNumber(copper) and math.max(0, math.floor(copper)) or 0
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if c > 0 then out[#out + 1] = c .. "c" end
  if #out == 0 then return "0c" end
  return table.concat(out, " ")
end

-- unit -> singular, plural
local UNIT_WORDS = {
  death = { "death", "deaths" }, fall = { "fall death", "fall deaths" }, drown = { "drowning", "drownings" },
  weak = { "death", "deaths" }, again = { "quick death", "quick deaths" }, pull = { "pull", "pulls" },
  steps = { "step", "steps" }, yards = { "yard swum", "yards swum" }, jumps = { "jump", "jumps" },
  hearths = { "hearthstone", "hearthstones" }, junk = { "junk item", "junk items" },
  quests = { "quest abandoned", "quests abandoned" }, duels = { "duel lost", "duels lost" },
  rezzes = { "rez", "rezzes" },
  zones = { "zone", "zones" }, flights = { "flight", "flights" }, needs = { "Need roll won", "Need rolls won" },
  nojuice = { "time out of juice", "times out of juice" }, toofar = { "time too far", "times too far" },
  wanders = { "run-off", "run-offs" }, messages = { "message", "messages" }, emotes = { "emote", "emotes" },
}

function L.valueText(award, value, stats)
  local def = award.def or award
  local unit = def.unit
  if not isNumber(value) then return "" end
  if unit == "afk" then return L.duration(value) .. " AFK" end
  if unit == "money" then return L.money(value) end
  if unit == "perhour" then return L.number(value) .. " steps per hour" end
  if unit == "xpperhour" then return L.number(value) .. " XP per hour" end
  if unit == "ratio" then return string.format("rides %.1fx more than walks", value) end
  local words = UNIT_WORDS[unit]
  local n = math.floor(value)
  local text = L.number(value) .. " " .. (words and (n == 1 and words[1] or words[2]) or "")
  text = text:gsub(" $", "")
  if unit == "weak" and stats and isNumber(stats.ld) and stats.ld > 0 then
    text = text .. " (lvl " .. math.floor(stats.ld) .. " mob)"
  end
  return text
end

-- ---------------------------------------------------------------------------------------------
-- Awards

local function awardValue(def, stats)
  if type(stats) ~= "table" then return nil end
  local v
  if def.value then v = def.value(stats) else v = stats[def.key] end
  if not isNumber(v) or v == math.huge or v == -math.huge then return nil end
  return v
end

function L.awards(entries)
  local out = {}
  for _, def in ipairs(ns.StatsDefs.AWARDS) do
    local rows = {}
    for _, e in ipairs(entries or {}) do
      local v = awardValue(def, e.stats)
      if v ~= nil then rows[#rows + 1] = { name = e.name, value = v, stats = e.stats } end
    end
    table.sort(rows, function(a, b)
      if a.value ~= b.value then
        if def.lowest then return a.value < b.value end
        return a.value > b.value
      end
      return tostring(a.name) < tostring(b.name)
    end)
    local item = { def = def, winners = {}, top = {}, empty = true }
    local best = rows[1]
    if best and (def.lowest or best.value > 0) then
      item.empty = false
      item.value = best.value
      item.text = L.valueText(def, best.value, best.stats)
      for _, r in ipairs(rows) do
        if r.value == best.value then item.winners[#item.winners + 1] = r.name end
      end
      table.sort(item.winners)
      for _, r in ipairs(rows) do
        if #item.top >= 3 then break end
        if def.lowest or r.value > 0 then
          item.top[#item.top + 1] = { name = r.name, value = r.value, text = L.valueText(def, r.value, r.stats) }
        end
      end
    end
    out[#out + 1] = item
  end
  return out
end

function L.titles(list)
  local t = {}
  for _, a in ipairs(list or {}) do
    if not a.empty then
      for _, name in ipairs(a.winners) do
        if t[name] == nil then t[name] = a.def.name end
      end
    end
  end
  return t
end

function L.showCards(list)
  local first, last = {}, {}
  for _, a in ipairs(list or {}) do
    if not a.empty then
      local card = { kind = "award", award = a }
      if a.def.last then last[#last + 1] = card else first[#first + 1] = card end
    end
  end
  for _, c in ipairs(last) do first[#first + 1] = c end
  first[#first + 1] = { kind = "end" }
  return first
end

-- ---------------------------------------------------------------------------------------------
-- Wire format

function L.toWire(snap)
  local f = {}
  if type(snap) ~= "table" then return f end
  if snap.sid ~= nil then f.sid = tostring(snap.sid) end
  if snap.q ~= nil then f.q = tostring(snap.q) end
  if snap.off then
    f.off = "1"
    return f
  end
  for _, prefix in ipairs({ "s", "a" }) do
    local src = snap[prefix]
    if type(src) == "table" then
      for _, key in ipairs(ns.StatsDefs.KEYS) do
        local v = src[key]
        if isNumber(v) and v ~= math.huge then
          v = math.floor(v)
          if v > 0 or (v == 0 and ns.StatsDefs.SET_KEYS[key]) then
            f[prefix .. "_" .. key] = string.format("%.0f", v)
          end
        end
      end
    end
  end
  return f
end

local WIRE_MAX = 1e12 -- a number above this is not a real count (treated as missing)

function L.fromWire(f)
  if type(f) ~= "table" or type(f.sid) ~= "string" or f.sid == "" then return nil end
  local snap = { sid = f.sid, q = type(f.q) == "string" and f.q or nil, s = {}, a = {} }
  if f.off == "1" then snap.off = true end
  for _, prefix in ipairs({ "s", "a" }) do
    for _, key in ipairs(ns.StatsDefs.KEYS) do
      local raw = f[prefix .. "_" .. key]
      local v = type(raw) == "string" and tonumber(raw) or nil
      if v and v == v and v >= 0 and v <= WIRE_MAX then
        v = math.floor(v)
        if v == 0 then v = 0 end -- folds -0
        snap[prefix][key] = v
      end
    end
  end
  return snap
end
