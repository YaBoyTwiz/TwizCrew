-- Crew session rules (pure, no WoW API): wire form, which of two sessions wins, the login choice, switching.
-- A session is { id = "<starterName>-<startWallclock>", start = <wallclock>, manual = <started by hand> }.
local _, ns = ...

local Logic = {}
ns.SessionLogic = Logic

local MAX_DIGITS = 15 -- a start time longer than this is not a wallclock (and would lose precision)

-- s -> sid, sst ("", "" for no session). sst is the start time, with a trailing "m" when started by hand.
function Logic.toWire(s)
  if type(s) ~= "table" then return "", "" end
  return tostring(s.id or ""), tostring(s.start or "") .. (s.manual and "m" or "")
end

-- sid, sst -> session or nil (empty or broken fields).
function Logic.fromWire(sid, sst)
  if type(sid) ~= "string" or sid == "" or type(sst) ~= "string" then return nil end
  local digits, m = sst:match("^(%d+)(m?)$")
  if not digits or #digits > MAX_DIGITS then return nil end
  return { id = sid, start = tonumber(digits), manual = m == "m" }
end

local function isManual(s) return s.manual and true or false end

-- The session that wins between a and b (either may be nil).
function Logic.better(a, b)
  if a == nil then return b end
  if b == nil then return a end
  local ma, mb = isManual(a), isManual(b)
  if ma ~= mb then return ma and a or b end
  local sa, sb = tonumber(a.start) or 0, tonumber(b.start) or 0
  if sa ~= sb then
    if ma then return sa > sb and a or b end -- two by hand: the newest wins
    return sa < sb and a or b                -- two automatic: the oldest wins
  end
  return tostring(b.id) < tostring(a.id) and b or a
end

function Logic.newSession(me, wall, manual)
  return { id = tostring(me) .. "-" .. tostring(wall), start = wall, manual = manual and true or false }
end

-- Can the saved session `own` still be continued at `wall`?
function Logic.resumable(own, wall, resume)
  return type(own) == "table" and type(own.id) == "string" and own.id ~= "" and type(own.start) == "number"
    and type(own.lastActive) == "number" and wall - own.lastActive <= resume
end

-- The session to be in after logging in, and whether my counts so far are kept.
-- own: saved { id, start, manual, lastActive } or nil; heard: sessions of the online crew.
-- Spec 7: my saved session continues only if nobody online has moved on. Nobody online in a session: my own when
-- it can be resumed (counts kept), else a new automatic one. Someone online: the best of theirs; my counts are
-- kept only when that is my own (still resumable) session.
function Logic.atLogin(own, heard, wall, me, resume)
  local canResume = Logic.resumable(own, wall, resume)
  local best
  for _, s in ipairs(heard or {}) do best = Logic.better(best, s) end
  if best == nil then
    if canResume then return own, true end
    return Logic.newSession(me, wall, false), false
  end
  return best, (canResume and best.id == own.id) and true or false
end

-- Hearing `incoming` while in `current`: session, changed, keep.
function Logic.switch(current, incoming)
  if incoming == nil then return current, false, false end
  if current ~= nil and incoming.id == current.id then return current, false, false end
  if Logic.better(current, incoming) == current then return current, false, false end
  return incoming, true, not isManual(incoming)
end
