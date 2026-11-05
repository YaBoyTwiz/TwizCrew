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
}

function Roster.new(saved)
  local r = setmetatable({ byName = {}, saved = saved or {} }, Roster)
  for name, row in pairs(r.saved) do
    if type(name) == "string" and name ~= "" and type(row) == "table" then
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

  m.online = true
  m.lastHeard = now
  m.lastSeen = wall
  if not wasOnline then events[#events + 1] = "online" end
  if hadTags and m.tags and m.tags.DEAD then events[#events + 1] = "died" end

  self.saved[name] = {
    name = name, class = m.class, level = m.level,
    zone = m.zone, subzone = m.subzone, lastSeen = m.lastSeen,
  }
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

function Roster:gone(name)
  local m = self.byName[name]
  if m then m.online = false end
end

function Roster:tick(now)
  local gone = {}
  local limit = ns.Config.OFFLINE_AFTER
  for name, m in pairs(self.byName) do
    if m.online and m.lastHeard and now - m.lastHeard > limit then
      m.online = false
      gone[#gone + 1] = name
    end
  end
  table.sort(gone)
  return gone
end

function Roster:names()
  local list = {}
  for name in pairs(self.byName) do list[#list + 1] = name end
  table.sort(list)
  return list
end

function Roster:members()
  local list = {}
  for _, m in pairs(self.byName) do list[#list + 1] = m end
  return list
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
  local list = self:members()
  local function byName(a, b)
    local la, lb = lower(a), lower(b)
    if la ~= lb then return la < lb end
    return a.name < b.name
  end
  local function rank(m)
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
