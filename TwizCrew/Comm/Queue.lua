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

function Queue:push(item)
  self.back = self.back + 1
  self.items[self.back] = item
end

-- Like push, but a waiting item with the same key (and the same destination table) gets replaced instead: a newer
-- position takes the place of one that has not gone out yet, so stale ones never pile up.
function Queue:replace(key, item)
  item.key = key
  for i = self.first, self.back do
    local old = self.items[i]
    if old and old.key == key and old.dest == item.dest then
      self.items[i] = item
      return
    end
  end
  self:push(item)
end

-- Drops every waiting item with this key whose destination is the same (same(a, b) says so), then pushes the new
-- one at the back: the newest takes over, and it still goes out after anything queued before it.
function Queue:supersede(key, item, same)
  item.key = key
  local j = self.first
  for i = self.first, self.back do
    local old = self.items[i]
    if not (old.key == key and same(old.dest, item.dest)) then
      self.items[j] = old
      j = j + 1
    end
  end
  for i = j, self.back do self.items[i] = nil end
  self.back = j - 1
  self:push(item)
end

function Queue:size()
  return self.back - self.first + 1
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

-- Sends queued items while there are whole tokens and the queue is not held.
-- sendFn(item) returning false keeps the item at the front, costs no token, and stops this pump.
function Queue:pump(sendFn)
  self:refill()
  local sent = 0
  while not self.held and self:size() > 0 and self.tokens >= 1 - EPSILON do
    local item = self.items[self.first]
    if sendFn(item) == false then break end
    self.items[self.first] = nil
    self.first = self.first + 1
    self.tokens = self.tokens - 1
    sent = sent + 1
  end
  if self:size() == 0 then self.first, self.back = 1, 0 end
  return sent
end
