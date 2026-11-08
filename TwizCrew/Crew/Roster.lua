-- Crew roster (pure, no WoW API): who is in the crew and what we last heard from them.
-- `now` is the session clock, `wall` is the wallclock; both are passed in by the caller.
local _, ns = ...

local Roster = {}
ns.Roster = Roster
Roster.__index = Roster

local function num(v)
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

local function str(v)
  if type(v) == "string" then return v end
  return nil
end

-- "DEAD,AFK" -> { DEAD = true, AFK = true } (same shape as Tags.decode)
local function decodeTags(s)
  local set = {}
  for tag in string.gmatch(s, "[^,]+") do set[tag] = true end
  return set
end

local function sameSet(a, b)
  if a == nil or b == nil then return a == b end
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

-- wire key -> { member field, converter(value) -> new value or nil to keep the old one }
local function keepString(v) return str(v) end
local WIRE = {
  cl  = { "class", keepString },
  lv  = { "level", num },
  xp  = { "xp", num },
  zn  = { "zone", keepString },
  sz  = { "subzone", keepString },
  st  = { "status", keepString },
  tg  = { "tags", function(v) if type(v) == "string" then return decodeTags(v) end end },
  ver = { "version", keepString },
  rs  = { "restartSince", keepString }, -- that copy's RESTART_SINCE ("" = an older copy that does not send it)
  xc  = { "xpCur", num },   -- level progress: current XP
  xm  = { "xpMax", num },   -- XP needed for this level (0 = max level)
  rx  = { "rested", num },  -- rested XP
  lo  = { "look", keepString }, -- race, gender, visible gear (MockShow.decodeLook)
  qn  = { "questName", keepString },       -- the quest they're on
  qo  = { "questObjectives", keepString }, -- its objectives, "; " between them
  qc  = { "questComplete", function(v) if type(v) == "string" then return v == "1" end end }, -- ready to turn in
}

-- XP pace for one play session (m.xpTrack): XP earned and the playing time it took. Called after a message that
-- carries xc, with the member's level / need / XP as they are now (a split message brings lv and xm no later than
-- xc). Each gap between gains counts at most XP_IDLE_AFTER, so a long break does not drag the pace down.
-- Anything odd starts the count over: no estimate beats a wrong one.
local function newTrack(lv, xc, xm, now)
  return { first = now, lastGain = now, earned = 0, active = 0, gains = 0, lv = lv, xc = xc, xm = xm }
end

local function trackXP(m, now)
  local lv, xc, xm = m.level, m.xpCur, m.xpMax
  if not lv or not xc or not xm or xm <= 0 then m.xpTrack = nil; return end -- max level or unknown
  if xc < 0 or xc > xm then return end -- not a real reading: ignore it
  local t = m.xpTrack
  if not t then m.xpTrack = newTrack(lv, xc, xm, now); return end
  local gain
  if lv == t.lv then gain = xc - t.xc
  elseif lv == t.lv + 1 then gain = (t.xm - t.xc) + xc -- what was left of the old level, plus the new XP
  end
  if not gain or gain < 0 then m.xpTrack = newTrack(lv, xc, xm, now); return end
  if gain > 0 then
    t.active = t.active + math.min(math.max(0, now - t.lastGain), ns.Config.XP_IDLE_AFTER)
    t.earned = t.earned + gain
    t.gains = t.gains + 1
    t.lastGain = now
  end
  t.lv, t.xc, t.xm = lv, xc, xm
end

function Roster.new(saved)
  local r = setmetatable({ byName = {}, saved = saved or {} }, Roster)
  for name, row in pairs(r.saved) do
    if type(name) == "string" and name ~= "" and type(row) == "table" and not ns.isTestName(name) then
      r.byName[name] = {
        name = name, class = str(row.class), level = num(row.level),
        zone = str(row.zone), subzone = str(row.subzone),
        inInstance = false, online = false, lastSeen = num(row.lastSeen),
      }
    end
  end
  return r
end

function Roster:get(name) return self.byName[name] end

function Roster:apply(name, fields, now, wall)
  local m = self.byName[name]
  local events, changes = {}, {}
  local isNew = m == nil
  local wasOnline = m ~= nil and m.online
  local hadTags = m ~= nil and m.tags ~= nil and not m.tags.DEAD or false
  -- a level-up counts only when we already got their level while they were online in this play session
  local levelBefore = m ~= nil and wasOnline and m.levelSeen and m.level or nil
  if isNew then
    m = { name = name, inInstance = false, online = false }
    self.byName[name] = m
    -- "new" means never seen at all (not even in saved data)
    events[#events + 1] = "new"
  end
  if type(fields) ~= "table" then fields = {} end

  for key, def in pairs(WIRE) do
    local value = def[2](fields[key])
    if value ~= nil then
      local field = def[1]
      local same
      if field == "tags" then same = sameSet(m.tags, value) else same = m[field] == value end
      if not same then m[field] = value; changes[field] = true end
    end
  end
  if fields.lk ~= nil and type(fields.lk) == "string" then
    local lk = fields.lk ~= "" and fields.lk or nil
    if m.layerKey ~= lk then m.layerKey = lk; changes.layerKey = true end
  end
  if fields.ins ~= nil then
    local ins = fields.ins == "1"
    if m.inInstance ~= ins then m.inInstance = ins; changes.inInstance = true end
  end

  if fields.xc ~= nil then trackXP(m, now) end

  m.online = true
  m.lastHeard = now
  m.lastSeen = wall
  if not wasOnline then events[#events + 1] = "online" end
  if hadTags and m.tags and m.tags.DEAD then events[#events + 1] = "died" end
  if levelBefore and m.level == levelBefore + 1 then events[#events + 1] = "levelup" end
  if num(fields.lv) ~= nil then m.levelSeen = true end

  if not ns.isTestName(name) then -- a fake (test tools) is never saved
    self.saved[name] = {
      name = name, class = m.class, level = m.level,
      zone = m.zone, subzone = m.subzone, lastSeen = m.lastSeen,
    }
  end
  return m, changes, events
end

function Roster:heard(name, now, wall)
  local m = self.byName[name]
  if not m then return {} end
  local events = {}
  if not m.online then events[1] = "online" end
  m.online = true
  m.lastHeard = now
  m.lastSeen = wall
  local row = self.saved[name]
  if type(row) == "table" then row.lastSeen = wall end
  return events
end

-- Forgets what is only true for one play session (layer key, in a dungeon, tags, XP pace): called when a friend goes
-- offline and when they log in again (HELLO), so old values never show. Returns the fields that changed.
function Roster:clearSession(name)
  local m = self.byName[name]
  local changes = {}
  if not m then return changes end
  if m.layerKey ~= nil then m.layerKey = nil; changes.layerKey = true end
  if m.inInstance then m.inInstance = false; changes.inInstance = true end
  if m.tags ~= nil then m.tags = nil; changes.tags = true end
  m.levelSeen, m.xpTrack = nil, nil -- no level-up from a level heard before, a new XP pace
  return changes
end

function Roster:gone(name)
  local m = self.byName[name]
  if m then
    m.online = false
    self:clearSession(name)
  end
end

function Roster:tick(now)
  local gone = {}
  local limit = ns.Config.OFFLINE_AFTER
  for name, m in pairs(self.byName) do
    if m.online and m.lastHeard and now - m.lastHeard > limit then
      m.online = false
      self:clearSession(name)
      gone[#gone + 1] = name
    end
  end
  table.sort(gone)
  return gone
end

-- names() and members() leave out fakes (test tools) unless withTest: every path that sends, saves, counts stats
-- or lists versions uses them as they are. Only the panel (sorted, onlineCount) and the layer tracker show fakes.
function Roster:names(withTest)
  local list = {}
  for name in pairs(self.byName) do
    if withTest or not ns.isTestName(name) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

function Roster:members(withTest)
  local list = {}
  for name, m in pairs(self.byName) do
    if withTest or not ns.isTestName(name) then list[#list + 1] = m end
  end
  return list
end

-- The fakes only, A-Z.
function Roster:testNames()
  local list = {}
  for name in pairs(self.byName) do
    if ns.isTestName(name) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- Takes a fake out of the roster (test tools). Real friends are never removed: returns false for them.
function Roster:remove(name)
  if not ns.isTestName(name) or not self.byName[name] then return false end
  self.byName[name] = nil
  if self.saved[name] ~= nil then self.saved[name] = nil end
  return true
end

function Roster:onlineCount()
  local on, total = 0, 0
  for _, m in pairs(self.byName) do
    total = total + 1
    if m.online then on = on + 1 end
  end
  return on, total
end

local function lower(m) return string.lower(m.name) end

function Roster:sorted(mode, relationOf)
  local list = self:members(true)
  local function byName(a, b)
    local la, lb = lower(a), lower(b)
    if la ~= lb then return la < lb end
    return a.name < b.name
  end
  local function rank(m)
    if mode == "name" then return 1 end -- plain A-Z, offline friends mixed in
    if not m.online then return 3 end
    if mode == "layer" and relationOf and relationOf(m.name) == "same" then return 1 end
    return 2
  end
  table.sort(list, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    if mode == "level" then
      local la, lb = a.level or 0, b.level or 0
      if la ~= lb then return la > lb end
    end
    return byName(a, b)
  end)
  return list
end

return Roster
