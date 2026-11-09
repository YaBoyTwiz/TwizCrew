-- Trophy case and stolen crowns: pure rules (no game calls). A session record is
-- { sid, start, people = { names }, winners = { [awardId] = { names } } }: who was in the session and who won what.
local _, ns = ...

local L = {}
ns.TrophyLogic = L

local function isNumber(v) return type(v) == "number" and v == v end

local function real(name) return type(name) == "string" and name ~= "" and not ns.isTestName(name) end

local function sorted(set)
  local out = {}
  for name in pairs(set) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- The record of a session that just ended, or nil (fewer than 2 people, or nobody played minPlayed seconds).
function L.record(sid, entries, awardsList, minPlayed)
  if type(sid) ~= "string" or sid == "" then return nil end
  local people, longest, kept, dropped = {}, 0, {}, false
  for _, e in ipairs(entries or {}) do
    if real(e.name) then
      kept[#kept + 1] = e
      people[e.name] = true
      local pt = type(e.stats) == "table" and e.stats.pt
      if isNumber(pt) and pt > longest then longest = pt end
    else
      dropped = true
    end
  end
  -- a fake crew member must not take a crown from a real one: when any were left out, the awards are worked out again
  if dropped and ns.StatsLogic then awardsList = ns.StatsLogic.awards(kept) end
  local names = sorted(people)
  if #names < 2 or longest < (minPlayed or 0) then return nil end
  local winners = {}
  for _, a in ipairs(awardsList or {}) do
    if not a.empty then
      local set = {}
      for _, name in ipairs(a.winners) do if people[name] then set[name] = true end end
      local list = sorted(set)
      if #list > 0 then winners[a.def.id] = list end
    end
  end
  return { sid = sid, start = tonumber(sid:match("%-(%d+)$")) or 0, people = names, winners = winners }
end

local function has(list, name)
  for _, n in ipairs(list or {}) do if n == name then return true end end
  return false
end

-- Per person: total trophies, trophies per award, and current streaks (their own sessions, newest first).
function L.summary(records)
  local list = {}
  for _, r in pairs(records or {}) do if type(r) == "table" then list[#list + 1] = r end end
  table.sort(list, function(a, b)
    if (a.start or 0) ~= (b.start or 0) then return (a.start or 0) > (b.start or 0) end
    return tostring(a.sid) > tostring(b.sid)
  end)
  local out = {}
  local function person(name)
    local p = out[name]
    if not p then p = { total = 0, counts = {}, streaks = {} }; out[name] = p end
    return p
  end
  for _, r in ipairs(list) do
    for id, names in pairs(r.winners or {}) do
      for _, name in ipairs(names) do
        local p = person(name)
        p.total = p.total + 1
        p.counts[id] = (p.counts[id] or 0) + 1
      end
    end
  end
  -- streaks: walk each person's sessions newest first; a streak lives while they keep winning it
  for name, p in pairs(out) do
    local alive = nil -- award ids still going; nil until their newest session
    for _, r in ipairs(list) do
      if has(r.people, name) then
        if alive == nil then
          alive = {}
          for id, names in pairs(r.winners or {}) do
            if has(names, name) then alive[id] = true; p.streaks[id] = 1 end
          end
        else
          for id in pairs(alive) do
            if has(r.winners and r.winners[id], name) then p.streaks[id] = p.streaks[id] + 1 else alive[id] = nil end
          end
        end
        if alive and next(alive) == nil then break end
      end
    end
  end
  return out
end

-- Wire form of a record (TRP): s, t, p, k = number of w_ fields, w_<awardId> = names.
function L.toWire(r)
  local f = { s = r.sid, t = tostring(r.start or 0), p = table.concat(r.people or {}, ",") }
  local k = 0
  for id, names in pairs(r.winners or {}) do
    f["w_" .. id] = table.concat(names, ",")
    k = k + 1
  end
  f.k = tostring(k)
  return f
end

local function split(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for name in s:gmatch("[^,]+") do
    name = ns.Util.truncateUTF8(ns.Util.safeText(name), 24)
    if real(name) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- A record from merged TRP pieces, or nil while incomplete (fewer w_ fields than k, or no p) or broken.
function L.fromPieces(f)
  if type(f) ~= "table" or type(f.s) ~= "string" or f.s == "" or #f.s > 64 then return nil end
  local k = tonumber(f.k)
  if not k or k < 0 or type(f.p) ~= "string" then return nil end
  local winners, n = {}, 0
  for key, v in pairs(f) do
    local id = type(key) == "string" and key:match("^w_(%w+)$")
    if id then
      local names = split(v)
      if #names > 0 then winners[id] = names end
      n = n + 1
    end
  end
  if n < k then return nil end
  local people = split(f.p)
  if #people < 2 then return nil end
  return { sid = f.s, start = tonumber(f.t) or 0, people = people, winners = winners }
end
