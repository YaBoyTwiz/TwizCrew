-- Pure rules of the shared awards show (Hall of Shame part 3), no frames: a card's wire form (AWC), the streak
-- wording on a card, the Clown of the Night vote messages (AWV, AWR) and the vote count.
local _, ns = ...

local L = {}
ns.ShowLogic = L

local MAX_CARD = 100
local NAME_CHARS = 24

local function awardDef(id)
  if type(id) ~= "string" then return nil end
  return ns.StatsDefs.awardDef(id)
end

-- "a,b" -> { "a", "b" }: cleaned, cut to 24 letters, fake crew members left out; the order is kept.
local function names(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for name in s:gmatch("[^,]+") do
    name = ns.Util.truncateUTF8(ns.Util.safeText(name), NAME_CHARS)
    if name ~= "" and not ns.isTestName(name) then out[#out + 1] = name end
  end
  return out
end

-- 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
function L.ordinal(n)
  n = math.floor(tonumber(n) or 0)
  local last2, last = n % 100, n % 10
  local suffix = "th"
  if last2 < 11 or last2 > 13 then
    if last == 1 then suffix = "st" elseif last == 2 then suffix = "nd" elseif last == 3 then suffix = "rd" end
  end
  return n .. suffix
end

-- "and for the 3rd session in a row"; nil under 2.
function L.streakLine(n)
  n = tonumber(n)
  if not n or n < 2 then return nil end
  return "and for the " .. L.ordinal(n) .. " session in a row"
end

L.REPEAT_KEYS = { "id", "i" }

-- The whole message goes out as one codec piece with the given fields uncut (a split or cut one would be misread).
local function fits(msgType, f, keys)
  local out = ns.Codec.encode(msgType, f, { repeatKeys = L.REPEAT_KEYS })
  local msg = #out == 1 and ns.Codec.decode(out[1])
  if not msg then return false end
  for _, k in ipairs(keys) do
    if msg.fields[k] ~= f[k] then return false end
  end
  return true
end

local function onePiece(f) return fits("AWC", f, { "w", "x", "k" }) end

-- An AWC's fields for card i of show id. streak: shown when 2 or more; jump: straight to the reveal.
-- Fake crew members are never sent. When too many winners tie to fit one message, w keeps the first ones that fit
-- and m says how many more there are.
function L.cardToWire(id, i, card, streak, jump)
  local f = { id = id, i = tostring(i), k = card and card.kind or "end" }
  if f.k == "award" then
    local a = card.award
    f.a = a.def.id
    local real = {}
    for _, name in ipairs(a.winners or {}) do
      if not ns.isTestName(name) then real[#real + 1] = name end
    end
    if a.text ~= nil then f.x = tostring(a.text) end
    local n = tonumber(streak)
    if n and n >= 2 then f.s = tostring(math.floor(n)) end
    if jump then f.r = "1" end
    local kept = #real
    while true do
      f.w = table.concat(real, ",", 1, kept)
      f.m = kept < #real and tostring(#real - kept) or nil
      if kept == 0 or onePiece(f) then break end
      kept = kept - 1
    end
  elseif f.k ~= "nobody" then
    f.k = "end"
  end
  return f
end

-- A card from an AWC's fields, or nil when broken (card number not 1..100, unknown kind or award).
function L.cardFromWire(f)
  if type(f) ~= "table" then return nil end
  local i = tonumber(f.i)
  if not i or i ~= math.floor(i) or i < 1 or i > MAX_CARD then return nil end
  if f.k == "nobody" or f.k == "end" then return { i = i, kind = f.k } end
  if f.k ~= "award" then return nil end
  local def = awardDef(f.a)
  if not def then return nil end
  local c = { i = i, kind = "award", awardId = def.id, winners = names(f.w),
    text = type(f.x) == "string" and f.x or "", jump = f.r == "1" }
  local s = tonumber(f.s)
  if s and s >= 2 and s == math.floor(s) then c.streak = s end
  local more = tonumber(f.m)
  if more and more >= 1 and more == math.floor(more) and more <= 1000 then c.more = more end
  return c
end

-- votes = { [voter] = choice }. Counts only choices that are candidates and not the voter. Returns the names with
-- the most votes (sorted; a tie gives all of them) and their count; no valid votes: {}, 0.
function L.tally(votes, candidates)
  local isCandidate, count = {}, {}
  for _, name in ipairs(candidates or {}) do isCandidate[name] = true end
  for voter, choice in pairs(votes or {}) do
    if isCandidate[choice] and choice ~= voter then count[choice] = (count[choice] or 0) + 1 end
  end
  local best, winners = 0, {}
  for name, n in pairs(count) do
    if n > best then best, winners = n, { name } elseif n == best then winners[#winners + 1] = name end
  end
  table.sort(winners)
  return winners, best
end

L.VOTE_SECONDS = 30
L.CLOWN_TITLE = "Clown of the Night"

-- An AWV's fields: the candidates that fit one message uncut (the last ones are left out), and that list.
function L.voteToWire(id, candidates, seconds)
  local list = {}
  for _, name in ipairs(candidates or {}) do
    if not ns.isTestName(name) then list[#list + 1] = name end
  end
  local f = { id = id, t = tostring(seconds or L.VOTE_SECONDS) }
  local kept = #list
  while true do
    f.c = table.concat(list, ",", 1, kept)
    if kept == 0 or fits("AWV", f, { "c", "t" }) then break end
    kept = kept - 1
  end
  local out = {}
  for i = 1, kept do out[i] = list[i] end
  return f, out
end

-- An AWV as { candidates (sorted, no doubles, no fakes), seconds }, or nil with fewer than 2 candidates.
function L.voteFromWire(f)
  if type(f) ~= "table" then return nil end
  local seen, list = {}, {}
  for _, name in ipairs(names(f.c)) do
    if not seen[name] then seen[name] = true; list[#list + 1] = name end
  end
  if #list < 2 then return nil end
  table.sort(list)
  local t = tonumber(f.t)
  if not t or t ~= math.floor(t) or t < 5 or t > 120 then t = L.VOTE_SECONDS end
  return { candidates = list, seconds = t }
end

-- An AWR as { skip = true } or { names (in the sent order), n }.
function L.resultFromWire(f)
  if type(f) ~= "table" then return nil end
  if f.k == "skip" then return { skip = true } end
  local n = tonumber(f.n)
  if not n or n < 0 or n ~= math.floor(n) or n > 1000 then n = 0 end
  return { names = names(f.w), n = n }
end

-- "Clown of the Night: Twiz & Frostie (1 vote)", or "No clown tonight.". joined(list, sep) can colour the names.
function L.clownLine(list, n, joined)
  if type(list) ~= "table" or #list == 0 then return "No clown tonight." end
  local who = joined and joined(list, " & ") or table.concat(list, " & ")
  n = tonumber(n) or 0
  return L.CLOWN_TITLE .. ": " .. who .. " (" .. n .. (n == 1 and " vote)" or " votes)")
end
