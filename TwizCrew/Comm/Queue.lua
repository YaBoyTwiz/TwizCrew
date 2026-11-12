-- Throttled send queue (pure, no WoW API): a token bucket that keeps us under the message rate limit.
-- The clock is injected (opts.now), so tests can move time by hand.
local _, ns = ...

local Queue = {}
ns.Queue = Queue
Queue.__index = Queue

local EPSILON = 1e-9 -- so 0.1 s steps of 0.2 tokens still add up to a whole token

-- opts = { perSecond, burst, now = function() return seconds end }. The bucket starts full.
function Queue.new(opts)
  local q = setmetatable({}, Queue)
  q.perSecond = opts.perSecond
  q.burst = opts.burst
  q.now = opts.now
  q.tokens = opts.burst
  q.last = opts.now()
  q.items = {}
  q.first = 1 -- index of the front item
  q.back = 0 -- index of the back item
  q.held = false
  return q
end

-- Two lanes: the normal one, and a bulk lane (big swaps of stats, calendar...) that is served only while the normal
-- lane is empty. The queue object itself holds the normal lane; self.bulkLane is the same shape.
local function laneOf(self, bulk)
  if not bulk then return self end
  if not self.bulkLane then self.bulkLane = { items = {}, first = 1, back = 0 } end
  return self.bulkLane
end

local function lanePush(lane, item)
  lane.back = lane.back + 1
  lane.items[lane.back] = item
end

-- bulk = true puts the item in the bulk lane.
function Queue:push(item, bulk)
  lanePush(laneOf(self, bulk), item)
end

-- Like push, but a waiting item with the same key (and the same destination table) in the same lane gets replaced
-- instead: a newer position takes the place of one that has not gone out yet, so stale ones never pile up.
function Queue:replace(key, item, bulk)
  local lane = laneOf(self, bulk)
  item.key = key
  for i = lane.first, lane.back do
    local old = lane.items[i]
    if old and old.key == key and old.dest == item.dest then
      lane.items[i] = item
      return
    end
  end
  lanePush(lane, item)
end

-- Drops every waiting item of this lane with this key whose destination is the same (same(a, b) says so), then
-- pushes the new one at the back: the newest takes over, and it still goes out after anything queued before it.
function Queue:supersede(key, item, same, bulk)
  local lane = laneOf(self, bulk)
  item.key = key
  local j = lane.first
  for i = lane.first, lane.back do
    local old = lane.items[i]
    if not (old.key == key and same(old.dest, item.dest)) then
      lane.items[j] = old
      j = j + 1
    end
  end
  for i = j, lane.back do lane.items[i] = nil end
  lane.back = j - 1
  lanePush(lane, item)
end

local function laneSize(lane)
  return lane.back - lane.first + 1
end

function Queue:size()
  return laneSize(self) + (self.bulkLane and laneSize(self.bulkLane) or 0)
end

function Queue:hold(on)
  self.held = on and true or false
end

function Queue:refill()
  local t = self.now()
  local elapsed = t - self.last
  if elapsed > 0 then
    self.tokens = math.min(self.burst, self.tokens + elapsed * self.perSecond)
  end
  self.last = t
end

-- Sends queued items while there are whole tokens and the queue is not held. The normal lane goes first; the
-- bulk lane only gets its turn while the normal lane is empty.
-- sendFn(item) returning false keeps the item at the front, costs no token, and stops this pump.
function Queue:pump(sendFn)
  self:refill()
  local sent = 0
  while not self.held and self:size() > 0 and self.tokens >= 1 - EPSILON do
    local lane = self
    if laneSize(lane) == 0 then lane = self.bulkLane end
    local item = lane.items[lane.first]
    if sendFn(item) == false then break end
    lane.items[lane.first] = nil
    lane.first = lane.first + 1
    self.tokens = self.tokens - 1
    sent = sent + 1
  end
  if laneSize(self) == 0 then self.first, self.back = 1, 0 end
  local bulk = self.bulkLane
  if bulk and laneSize(bulk) == 0 then bulk.first, bulk.back = 1, 0 end
  return sent
end
