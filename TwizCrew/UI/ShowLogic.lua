-- Pure rules of the shared awards show (Hall of Shame part 3), no frames: a card's wire form (AWC), the streak
-- wording on a card, and the Clown of the Night vote count.
local _, ns = ...

local L = {}
ns.ShowLogic = L

local MAX_CARD = 100
local NAME_CHARS = 24

local function awardDef(id)
  if type(id) ~= "string" then return nil end
  for _, d in ipairs(ns.StatsDefs.AWARDS) do if d.id == id then return d end end
  return nil
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

-- The whole AWC goes out as one codec piece with w and x uncut (a split or cut card would be misread).
local function onePiece(f)
  local out = ns.Codec.encode("AWC", f, { repeatKeys = L.REPEAT_KEYS })
  local msg = #out == 1 and ns.Codec.decode(out[1])
  return msg and msg.fields.w == f.w and msg.fields.x == f.x and msg.fields.k == f.k or false
end

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
