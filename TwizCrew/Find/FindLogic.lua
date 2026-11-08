-- Find the crew, pure rules (no WoW API): distance and direction between two world positions, what a row arrow and
-- the big arrow show, when to send our position, how long a meet-up has left, and where a point sits on the minimap.
-- A world position is { c = continent (instance id), x = yards north, y = yards west }, as the game's
-- C_Map.GetWorldPosFromMapPos gives it. Angles are radians, counter-clockwise from north (the game's facing too).
local _, ns = ...

local FindLogic = {}
ns.FindLogic = FindLogic

local PI = math.pi
local RIM = 6 -- a minimap icon on the edge sits this many pixels inside the rim

-- Minimap width in yards for each zoom level (0 = farthest out), outdoors and indoors. These are the sizes
-- minimap addons have long used (HereBeDragons-Pins has the same table).
local MINIMAP_YARDS = {
  outdoor = { [0] = 1400 / 3, 400, 1000 / 3, 800 / 3, 200, 400 / 3 },
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function valid(p)
  return type(p) == "table" and p.c ~= nil and finite(p.x) and finite(p.y)
end

-- distance (yards), bearing (radians from north, counter-clockwise) from one position to another; nil when either
-- is unknown or they are on different continents.
function FindLogic.vector(from, to)
  if not valid(from) or not valid(to) or from.c ~= to.c then return nil end
  local dx, dy = to.x - from.x, to.y - from.y
  return math.sqrt(dx * dx + dy * dy), math.atan2(dy, dx)
end

-- The direction on screen: bearing minus facing, in (-pi, pi]. No facing: the bearing itself (a north-up compass).
function FindLogic.relative(bearing, facing)
  local a = bearing
  if finite(facing) then a = bearing - facing end
  a = a % (2 * PI)
  if a > PI then a = a - 2 * PI end
  return a
end

-- "120 yd" under 1000 yards, "1.2k yd" from there.
function FindLogic.distanceText(yards)
  if not finite(yards) then return "" end
  if yards < 999.5 then return string.format("%d yd", math.floor(yards + 0.5)) end
  return string.format("%.1fk yd", yards / 1000)
end

-- A row arrow for a group member, or nil (hidden). me / them = positions (them.at = when it was heard, them.zone,
-- me.zone); opts = { near = yards, staleAfter = seconds }. Same zone: { angle, text, compass }. Another zone on the
-- same continent: { still = true, zone }.
function FindLogic.rowArrow(me, them, now, facing, opts)
  opts = opts or {}
  if not valid(me) or not valid(them) then return nil end
  if not finite(them.at) or not finite(now) or now - them.at > (opts.staleAfter or 60) then return nil end
  local dist, bearing = FindLogic.vector(me, them)
  if not dist then return nil end
  local sameZone = type(me.zone) == "string" and me.zone ~= "" and me.zone == them.zone
  if not sameZone then return { still = true, zone = them.zone } end
  if dist < (opts.near or 15) then return nil end
  return { angle = FindLogic.relative(bearing, facing), text = FindLogic.distanceText(dist),
    compass = not finite(facing) }
end

-- "Running off": track = what we remember about one group member ({ nearAt, me, them, armed }), me / them = the
-- two positions now. They count as close within opts.near yards; when, within opts.window seconds of being close,
-- they are opts.far yards away and they moved more than you did (so walking off yourself doesn't count), the
-- answer is true once (it arms again only after they were close again). Returns track, alarm, distance.
function FindLogic.runaway(track, me, them, now, opts)
  track = track or {}
  local dist = FindLogic.vector(me, them)
  if not dist or not finite(now) then return track, false end
  local function copy(p) return { c = p.c, x = p.x, y = p.y } end
  if dist <= opts.near then
    track.nearAt, track.me, track.them, track.armed = now, copy(me), copy(them), true
    return track, false, dist
  end
  if track.armed and dist >= opts.far and track.nearAt and now - track.nearAt <= opts.window then
    track.armed = false
    local mine = FindLogic.vector(track.me, me) or 0
    local theirs = FindLogic.vector(track.them, them) or math.huge
    if theirs > mine then return track, true, dist end
  end
  return track, false, dist
end

-- What the big arrow shows toward a target position: { angle, text, distance, arrived, compass }, or nil when there
-- is no direction (unknown, other continent).
function FindLogic.bigArrow(me, target, facing, arriveWithin)
  local dist, bearing = FindLogic.vector(me, target)
  if not dist then return nil end
  return { angle = FindLogic.relative(bearing, facing), text = FindLogic.distanceText(dist), distance = dist,
    arrived = dist <= (arriveWithin or 15), compass = not finite(facing) }
end

-- Should our position go out now? last = { c, x, y, at } of the last one sent (nil = none yet); cfg = { move, gap,
-- keepAlive }; forced = the group changed (still at most once a second).
function FindLogic.shouldSend(last, pos, now, cfg, forced)
  if not valid(pos) then return false end
  if not last or not finite(last.at) then return true end
  local since = now - last.at
  if forced then return since >= 1 end
  if since >= cfg.keepAlive then return true end
  if since < cfg.gap then return false end
  if last.c ~= pos.c then return true end
  local dist = FindLogic.vector(last, pos)
  return dist ~= nil and dist >= cfg.move
end

-- Seconds a meet-up has left (0 when over or missing).
function FindLogic.meetLeft(meet, now)
  if type(meet) ~= "table" or not finite(meet.expires) or not finite(now) then return 0 end
  return math.max(0, meet.expires - now)
end

-- A position as message fields (whole yards), or { u = "1" } when unknown.
function FindLogic.posFields(p)
  if not valid(p) then return { u = "1" } end
  return { c = tostring(p.c), x = tostring(math.floor(p.x + 0.5)), y = tostring(math.floor(p.y + 0.5)) }
end

-- Message fields back to a position; nil when unknown or junk.
function FindLogic.readPos(fields)
  if type(fields) ~= "table" or fields.u == "1" then return nil end
  local c, x, y = tonumber(fields.c), tonumber(fields.x), tonumber(fields.y)
  if not finite(c) or not finite(x) or not finite(y) then return nil end
  return { c = c, x = x, y = y }
end

-- Where a point dist yards away at bearing sits on the minimap, from its centre: x, y (pixels, y up), onEdge.
-- rotate: the minimap turns with the player (facing up). zoom: Minimap:GetZoom(). width: the minimap's width in
-- pixels. shape: GetMinimapShape() (round and square parts; far points sit on the edge, just inside the rim).
-- across: the yards the minimap shows edge to edge when the game says (C_Minimap.GetViewRadius * 2), else the zoom
-- table. nil when the minimap turns but our facing is unknown (no way to know where the point is on it).
function FindLogic.minimapOffset(dist, bearing, facing, rotate, zoom, indoors, width, shape, across)
  if not finite(dist) or not finite(bearing) then return nil end
  if rotate and not finite(facing) then return nil end
  local yards = finite(across) and across > 0 and across
    or (indoors and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor)[tonumber(zoom) or 0]
    or MINIMAP_YARDS.outdoor[0]
  width = finite(width) and width > 0 and width or 140
  local angle = bearing
  if rotate then angle = bearing - facing end
  local px = dist * width / yards
  local x, y = -math.sin(angle) * px, math.cos(angle) * px
  local radius = width / 2 - RIM
  local degrees = math.deg(math.atan2(y, x))
  local round = not ns.MinimapLogic or ns.MinimapLogic.isRound(shape, degrees)
  if round then
    if px <= radius then return x, y, false end
    return -math.sin(angle) * radius, math.cos(angle) * radius, true
  end
  local far = math.max(math.abs(x), math.abs(y))
  if far <= radius then return x, y, false end
  return x * radius / far, y * radius / far, true
end
