-- Trophy case and stolen crowns: pure rules (no game calls). A session record is
-- { sid, start, people = { names }, winners = { [awardId] = { names } }, late }: who was in the session and who won
-- what. late = true: saved at my next login from the numbers I had when I left (maybe before the end);
-- e = how fresh a late record's numbers are (wallclock of the newest of them).
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

-- Award ids this copy knows, extra trophies (Clown of the Night) included (a newer copy's award would make a blank
-- line).
local function knownIds()
  local out = {}
  for _, d in ipairs(ns.StatsDefs and ns.StatsDefs.AWARDS or {}) do out[d.id] = true end
  for _, d in ipairs(ns.StatsDefs and ns.StatsDefs.EXTRA_TROPHIES or {}) do out[d.id] = true end
  return out
end

-- Per person: total trophies, trophies per award, and current streaks (their own sessions, newest first).
-- Only awards this copy knows count.
function L.summary(records)
  local known = knownIds()
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
      for _, name in ipairs(known[id] and names or {}) do
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
            if known[id] and has(names, name) then alive[id] = true; p.streaks[id] = 1 end
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

-- Wire form of a record (TRP): s, t, p, k = number of w_ fields, w_<awardId> = names, l = "1" and e when late.
function L.toWire(r)
  local f = { s = r.sid, t = tostring(r.start or 0), p = table.concat(r.people or {}, ","), l = r.late and "1" or nil }
  if r.late then f.e = tostring(math.floor(tonumber(r.e) or 0)) end
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

-- A record from merged TRP pieces, or nil while incomplete (fewer w_ fields than k, no p or no t) or broken.
function L.fromPieces(f)
  if type(f) ~= "table" or type(f.s) ~= "string" or f.s == "" or #f.s > 64 then return nil end
  local k = tonumber(f.k)
  if not k or k < 0 or type(f.p) ~= "string" or not tonumber(f.t) then return nil end
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
  local late = f.l == "1" or nil
  local e = late and math.floor(math.max(tonumber(f.e) or 0, 0)) or nil
  return { sid = f.s, start = tonumber(f.t), people = people, winners = winners, late = late, e = e }
end

-- A short checksum (a string) of a full record's content: session, start, people and winners, as the record reads
-- after a trip over the wire (so the sender and the receiver of it get the same one).
function L.checksum(r)
  local ok, f = pcall(L.toWire, r) -- (saved data may be broken)
  r = ok and L.fromPieces(f) or r
  local people = type(r.people) == "table" and r.people or {}
  local parts = { tostring(r.sid), tostring(tonumber(r.start) or 0), table.concat(people, ",") }
  local ids = {}
  for id, names in pairs(type(r.winners) == "table" and r.winners or {}) do
    if type(id) == "string" and type(names) == "table" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do parts[#parts + 1] = id .. "=" .. table.concat(r.winners[id], ",") end
  return ns.Util.checksum(table.concat(parts, "|"))
end

-- Does record r replace old? Full beats late (whatever the people); late never beats full; two late ones: the
-- fresher numbers (higher e) win; otherwise (same e, or both full) strictly more people wins. Two full ones with
-- as many people: the smaller checksum string wins, so every copy ends up with the same record.
function L.better(old, r)
  if type(old) ~= "table" then return true end
  if type(r) ~= "table" then return false end
  if old.late and not r.late then return true end
  if r.late and not old.late then return false end
  if r.late then
    local re, oe = tonumber(r.e) or 0, tonumber(old.e) or 0
    if re ~= oe then return re > oe end
  end
  if type(old.people) ~= "table" then return false end
  local rn, on = #(r.people or {}), #old.people
  if rn ~= on or r.late then return rn > on end
  return L.checksum(r) < L.checksum(old)
end

-- One digest entry: "<sid>" for a full record, "<sid>*<e>" for a late one.
function L.digestEntry(sid, r)
  if type(r) == "table" and r.late then return sid .. "*" .. math.floor(tonumber(r.e) or 0) end
  return sid
end

-- The same entry's part of the digest's c (v0.1.23 ignores c): "<people>.<checksum>" for a full record, "-" for a
-- late one.
function L.digestSum(r)
  if type(r) ~= "table" or r.late or type(r.people) ~= "table" then return "-" end
  return #r.people .. "." .. L.checksum(r)
end

-- A digest's c as a list in r's order: { n = people, sum = checksum } or false (late, or unreadable).
function L.parseSums(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for item in text:gmatch("[^,]+") do
    local n, sum = item:match("^(%d+)%.(%d+)$")
    out[#out + 1] = n and { n = tonumber(n), sum = sum } or false
  end
  return out
end

-- A digest's r as a list of { sid, late, e }, in its order; malformed entries are skipped.
function L.parseDigest(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for item in text:gmatch("[^,]+") do
    if item:find("*", 1, true) then
      local sid, e = item:match("^([^*]+)%*(%d+)$")
      if sid and #sid <= 64 then out[#out + 1] = { sid = sid, late = true, e = tonumber(e) } end
    elseif #item <= 64 then
      out[#out + 1] = { sid = item }
    end
  end
  return out
end

-- Stolen crowns: who leads each award now ({ [awardId] = { names } }, only awards with a winner).
function L.leaders(awardsList)
  local out = {}
  for _, a in ipairs(awardsList or {}) do
    if not a.empty then
      local list = {}
      for _, name in ipairs(a.winners) do if real(name) then list[#list + 1] = name end end
      if #list > 0 then out[a.def.id] = list end
    end
  end
  return out
end

local function allIn(list, set)
  for _, name in ipairs(list) do if not set[name] then return false end end
  return true
end

-- Steals between the old leaders and the awards now: the new winners share nobody with the old ones.
-- valueOf(def, name) -> the person's number as text ("8 deaths"). here / wasHere (optional sets of names): who is on
-- the board now / was at the last check. A victim who left (stats off) or a thief who just came back is no steal.
-- Awards with `noSteal` never count.
function L.steals(old, awardsList, valueOf, here, wasHere)
  local out = {}
  local now = L.leaders(awardsList)
  for _, a in ipairs(awardsList or {}) do
    local id = a.def.id
    local before, after = old and old[id], now[id]
    if before and after and #before > 0 and not a.def.noSteal
      and (not here or allIn(before, here)) and (not wasHere or allIn(after, wasHere)) then
      local shared = false
      for _, name in ipairs(after) do if has(before, name) then shared = true end end
      if not shared then
        out[#out + 1] = { def = a.def, thieves = after, victims = before,
          thiefText = valueOf(a.def, after[1]) or "", victimText = valueOf(a.def, before[1]) or "" }
      end
    end
  end
  return out
end
