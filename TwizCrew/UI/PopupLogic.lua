-- Pure pop-up rules: what is dropped (quiet period), what is combined, and the exact words. No frames here.
local _, ns = ...

local PopupLogic = {}
ns.PopupLogic = PopupLogic

local Logic = {}
Logic.__index = Logic

-- opts: combineWindow (seconds a layer batch waits for more names), quietUntil (pushes before this are dropped)
function PopupLogic.new(opts)
  opts = opts or {}
  return setmetatable({
    combineWindow = opts.combineWindow or 3,
    quietUntil = opts.quietUntil or 0,
    deaths = {},
    batches = {},   -- kind -> { names = {...}, first = time }
  }, Logic)
end

local OPPOSITE = { layer_diff = "layer_same", layer_same = "layer_diff" }

local function indexOf(list, name)
  for i, n in ipairs(list) do if n == name then return i end end
end

-- Shown right away, one per friend (never combined): deaths and level-ups.
local INSTANT = { death = true, levelup = true }

-- kind: "layer_diff" | "layer_same" | "death" | "levelup"; extra: { zone, subzone } (deaths),
-- { level, maxLevel } (level-ups)
function Logic:push(kind, name, now, extra)
  if now < self.quietUntil then return end
  if INSTANT[kind] then
    self.deaths[#self.deaths + 1] = { kind = kind, names = { name }, extra = extra or {} }
    return
  end
  local opposite = OPPOSITE[kind]
  if not opposite then return end
  -- Going away and coming back inside one batch: nothing happened worth a pop-up.
  local other = self.batches[opposite]
  if other then
    local i = indexOf(other.names, name)
    if i then
      table.remove(other.names, i)
      if #other.names == 0 then self.batches[opposite] = nil end
      return
    end
  end
  local batch = self.batches[kind]
  if not batch then
    batch = { names = {}, first = now }
    self.batches[kind] = batch
  end
  if not indexOf(batch.names, name) then batch.names[#batch.names + 1] = name end
end

local function popupFor(kind, names)
  local p = { kind = kind, names = names, extra = {} }
  if kind == "layer_diff" then
    p.invite = {}
    for i, n in ipairs(names) do p.invite[i] = n end
  end
  return p
end

function Logic:due(now)
  local out = {}
  for _, d in ipairs(self.deaths) do out[#out + 1] = d end
  self.deaths = {}
  for _, kind in ipairs({ "layer_diff", "layer_same" }) do
    local batch = self.batches[kind]
    if batch and now >= batch.first + self.combineWindow then
      out[#out + 1] = popupFor(kind, batch.names)
      self.batches[kind] = nil
    end
  end
  return out
end

-- The one combined pop-up shown when the quiet period is over (nil when nobody is on a different layer).
function Logic:endQuiet(differentNames)
  if type(differentNames) ~= "table" or #differentNames == 0 then return nil end
  local names = {}
  for i, n in ipairs(differentNames) do names[i] = n end
  return popupFor("layer_diff", names)
end

local function identity(name) return name end

-- The short line under a ding, for the stream: how many levels are left.
local function levelsToGo(lv, maxLevel)
  if not lv or not maxLevel then return nil end
  local left = maxLevel - lv
  if left <= 0 then return "Max level. GG!" end
  if left == 1 then return "One more to go!" end
  return "Only " .. left .. " to go."
end

-- Returns text, subtext (subtext may be nil). colorName(name) wraps a name for display; default is identity.
function PopupLogic.text(kind, names, extra, colorName)
  colorName = colorName or identity
  local n = #names
  if kind == "layer_diff" or kind == "layer_same" then
    local tail = kind == "layer_diff" and "on a different layer" or "back on your layer"
    local text
    if n == 1 then
      text = string.format("%s is %s", colorName(names[1]), tail)
    elseif n == 2 then
      text = string.format("%s and %s are %s", colorName(names[1]), colorName(names[2]), tail)
    else
      text = string.format("%d friends are %s", n, tail)
    end
    return text, kind == "layer_diff" and "Click to invite them to your group" or nil
  end
  extra = extra or {}
  if kind == "levelup" then
    local lv, maxLevel = tonumber(extra.level), tonumber(extra.maxLevel)
    if not lv then return string.format("%s leveled up!", colorName(names[1])) end
    return string.format("%s reached level %d!", colorName(names[1]), lv), levelsToGo(lv, maxLevel)
  end
  -- death
  local text = string.format("%s died", colorName(names[1]))
  local zone = (type(extra.zone) == "string" and extra.zone ~= "") and extra.zone or nil
  local sub = (type(extra.subzone) == "string" and extra.subzone ~= "") and extra.subzone or nil
  local subtext
  if zone and sub then subtext = zone .. ", " .. sub else subtext = zone or sub end
  return text, subtext
end
