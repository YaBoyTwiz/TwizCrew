-- Pure calendar logic (no frames, no game calls): 15-minute play-time masks, dates without the game's date
-- functions, local time, a day's timeline, the month grid, "usual times" and the best time to play together.
--
-- Time: everything is stored in UTC (server time, seconds since 1970). A "slot" is 15 minutes: slot = floor(t/900).
-- A UTC day (floor(t/86400)) has 96 slots, kept as a 16-letter mask (6 slots per letter). Masks only ever gain
-- slots, so two copies merge by OR-ing them (the order never matters).
local _, ns = ...

local L = {}
ns.CalendarLogic = L

L.SLOT = 900
L.DAY = 86400
L.SLOTS_PER_DAY = 96
L.MASK_LEN = 16
local ABC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local VALUE = {}
for i = 1, #ABC do VALUE[ABC:sub(i, i)] = i - 1 end
L.EMPTY = string.rep("A", L.MASK_LEN)

----------------------------------------------------------------------------------------------------------- masks
local function digits(mask)
  local out = {}
  for i = 1, L.MASK_LEN do
    out[i] = VALUE[type(mask) == "string" and mask:sub(i, i) or ""] or 0
  end
  return out
end

local function letters(d)
  local out = {}
  for i = 1, L.MASK_LEN do out[i] = ABC:sub(d[i] + 1, d[i] + 1) end
  return table.concat(out)
end

local function bitOf(v, b) return math.floor(v / 2 ^ b) % 2 == 1 end

-- A valid mask, or nil.
function L.clean(mask)
  if type(mask) ~= "string" or #mask ~= L.MASK_LEN or mask:find("[^%w%-_]") then return nil end
  return mask
end

-- Slot i (0..95) of a day on?
function L.has(mask, i)
  if type(mask) ~= "string" or i < 0 or i >= L.SLOTS_PER_DAY then return false end
  local v = VALUE[mask:sub(math.floor(i / 6) + 1, math.floor(i / 6) + 1)] or 0
  return bitOf(v, i % 6)
end

function L.set(mask, i)
  if i < 0 or i >= L.SLOTS_PER_DAY then return mask or L.EMPTY end
  local d = digits(mask or L.EMPTY)
  local k, b = math.floor(i / 6) + 1, i % 6
  if not bitOf(d[k], b) then d[k] = d[k] + 2 ^ b end
  return letters(d)
end

function L.merge(a, b)
  if not a then return b end
  if not b then return a end
  local da, db = digits(a), digits(b)
  for i = 1, L.MASK_LEN do
    local v = 0
    for bit = 0, 5 do
      if bitOf(da[i], bit) or bitOf(db[i], bit) then v = v + 2 ^ bit end
    end
    da[i] = v
  end
  return letters(da)
end

function L.count(mask)
  local n = 0
  for i = 0, L.SLOTS_PER_DAY - 1 do if L.has(mask, i) then n = n + 1 end end
  return n
end

-- Slots on in a person's record ({ [utcDay] = { on = mask, afk = mask } }) from day `from` on.
function L.total(days, from)
  local n = 0
  for day, d in pairs(days or {}) do
    if not from or day >= from then n = n + L.count(d.on) end
  end
  return n
end

------------------------------------------------------------------------------------------------------- dates
-- Days since 1970-01-01 <-> year, month, day (proleptic Gregorian; H. Hinnant's algorithm).
function L.civil(z)
  z = z + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end

function L.daysFrom(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = m > 2 and m - 3 or m + 9
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- 0 = Sunday .. 6 = Saturday (1970-01-01 was a Thursday)
function L.weekday(day) return (day + 4) % 7 end

function L.monthLength(y, m)
  local ny, nm = y, m + 1
  if nm > 12 then ny, nm = y + 1, 1 end
  return L.daysFrom(ny, nm, 1) - L.daysFrom(y, m, 1)
end

L.MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December" }
L.WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
L.SHORT_DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- Seconds to add to UTC for local time, from the two broken-down times of the same moment ("*t" and "!*t").
function L.offsetFrom(loc, utc)
  if type(loc) ~= "table" or type(utc) ~= "table" then return 0 end
  local days
  if loc.year ~= utc.year then days = (loc.year > utc.year) and 1 or -1 else days = (loc.yday or 0) - (utc.yday or 0) end
  return days * 86400 + ((loc.hour or 0) - (utc.hour or 0)) * 3600 + ((loc.min or 0) - (utc.min or 0)) * 60
end

-- "7pm", "12am", "7:15pm"
function L.clock(minutes)
  minutes = math.floor(minutes) % 1440
  local h, m = math.floor(minutes / 60), minutes % 60
  local suffix = h < 12 and "am" or "pm"
  local h12 = h % 12
  if h12 == 0 then h12 = 12 end
  if m == 0 then return h12 .. suffix end
  return string.format("%d:%02d%s", h12, m, suffix)
end

-- "4h 15m", "45m", "6h"
function L.duration(minutes)
  minutes = math.floor(minutes + 0.5)
  if minutes < 60 then return minutes .. "m" end
  local h, m = math.floor(minutes / 60), minutes % 60
  if m == 0 then return h .. "h" end
  return h .. "h " .. m .. "m"
end

--------------------------------------------------------------------------------------------------- one local day
-- The state of a person in local slot j (0..95) of local day `day`: "on", "afk" or nil. off: local offset (s).
local function slotState(days, day, j, off)
  local t = day * L.DAY + j * L.SLOT - off -- UTC start of that local slot
  local s = math.floor(t / L.SLOT)
  local uday, idx = math.floor(s / L.SLOTS_PER_DAY), s % L.SLOTS_PER_DAY
  local d = days and days[uday]
  if not d or not L.has(d.on, idx) then return nil end
  if d.afk and L.has(d.afk, idx) then return "afk" end
  return "on"
end

-- people: { [id] = { name, class, days } }. Returns the people who played on local day `day`, most time first:
-- { id, name, class, minutes, runs = { { from = slot, to = slot (exclusive), afk = bool } } }.
function L.dayView(people, day, off)
  local out = {}
  for id, p in pairs(people or {}) do
    local runs, minutes, cur = {}, 0, nil
    for j = 0, L.SLOTS_PER_DAY - 1 do
      local st = slotState(p.days, day, j, off)
      if st then minutes = minutes + 15 end
      local afk = st == "afk"
      if st and cur and cur.afk == afk and cur.to == j then
        cur.to = j + 1
      elseif st then
        cur = { from = j, to = j + 1, afk = afk }
        runs[#runs + 1] = cur
      end
    end
    if minutes > 0 then
      out[#out + 1] = { id = id, name = p.name, class = p.class, minutes = minutes, runs = runs }
    end
  end
  table.sort(out, function(a, b)
    if a.minutes ~= b.minutes then return a.minutes > b.minutes end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

-- A day view's runs with AFK and active joined: { { from = slot, to = slot (exclusive) } }.
function L.spans(runs)
  local spans, cur = {}, nil
  for _, r in ipairs(runs or {}) do
    if cur and cur.to == r.from then cur.to = r.to else cur = { from = r.from, to = r.to }; spans[#spans + 1] = cur end
  end
  return spans
end

-- "7pm-11:15pm" for one span.
function L.spanText(s) return L.clock(s.from * 15) .. "-" .. L.clock(s.to * 15) end

-- "7pm-11:15pm, 11:30pm-12am" from a day view's runs (AFK and active joined).
function L.runText(runs)
  local out = {}
  for i, s in ipairs(L.spans(runs)) do out[i] = L.spanText(s) end
  return table.concat(out, ", ")
end

-- Who was really on in the 7 local days from `first`: grid[0..6][0..23] = the sum over people of the part of that
-- hour they were on (0..1 each, 15-minute steps), and each person's own grid, most time first:
-- { grid, count, first, people = { { id, name, class, minutes, grid } } }.
function L.week(people, first, off)
  local function empty()
    local g = {}
    for w = 0, 6 do g[w] = {}; for h = 0, 23 do g[w][h] = 0 end end
    return g
  end
  local grid, persons = empty(), {}
  for id, p in pairs(people or {}) do
    local mine, minutes = empty(), 0
    for w = 0, 6 do
      for h = 0, 23 do
        local n = 0
        for q = 0, 3 do if slotState(p.days, first + w, h * 4 + q, off) then n = n + 1 end end
        if n > 0 then
          mine[w][h] = n / 4
          grid[w][h] = grid[w][h] + n / 4
          minutes = minutes + n * 15
        end
      end
    end
    if minutes > 0 then
      persons[#persons + 1] = { id = id, name = p.name, class = p.class, minutes = minutes, grid = mine }
    end
  end
  table.sort(persons, function(a, b)
    if a.minutes ~= b.minutes then return a.minutes > b.minutes end
    return tostring(a.name) < tostring(b.name)
  end)
  return { grid = grid, people = persons, count = #persons, first = first }
end

-- Who was on in local slot j (0..95) of a day view, in its order: { { name, class, afk } }.
function L.whoAt(list, j)
  local out = {}
  for _, e in ipairs(list or {}) do
    for _, r in ipairs(e.runs or {}) do
      if j >= r.from and j < r.to then
        out[#out + 1] = { name = e.name, class = e.class, afk = r.afk }
        break
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------------------------------- month
-- The month grid: 42 cells (6 weeks, Sunday first) for local month (y, m). Each cell: { day, y, m, d, inMonth }.
function L.monthGrid(y, m)
  local first = L.daysFrom(y, m, 1)
  local start = first - L.weekday(first)
  local cells = {}
  for i = 0, 41 do
    local day = start + i
    local cy, cm, cd = L.civil(day)
    cells[#cells + 1] = { day = day, y = cy, m = cm, d = cd, inMonth = (cy == y and cm == m) }
  end
  return cells
end

---------------------------------------------------------------------------------------------- usual times
-- Over the `weeks` weeks ending on local day `today`: grid[w][h] = average number of people on in that weekday
-- (0 = Sunday) and hour, and per person their hours per week and the hours they're on most.
function L.usual(people, today, off, weeks)
  weeks = weeks or 4
  local grid = {}
  for w = 0, 6 do grid[w] = {}; for h = 0, 23 do grid[w][h] = 0 end end
  local first = today - weeks * 7 + 1
  local persons = {}
  local count = 0
  for id, p in pairs(people or {}) do
    local hours, minutes, weekdayMin, weekendMin = {}, 0, 0, 0
    for h = 0, 23 do hours[h] = 0 end
    local any = false
    for day = first, today do
      local w = L.weekday(day)
      for h = 0, 23 do
        local on = false
        for q = 0, 3 do
          if slotState(p.days, day, h * 4 + q, off) then
            on = true
            minutes = minutes + 15
            if w == 0 or w == 6 then weekendMin = weekendMin + 15 else weekdayMin = weekdayMin + 15 end
          end
        end
        if on then grid[w][h] = grid[w][h] + 1 / weeks; hours[h] = hours[h] + 1; any = true end
      end
    end
    if any then
      count = count + 1
      persons[#persons + 1] = { id = id, name = p.name, class = p.class, perWeek = minutes / weeks,
        hours = hours, weekdayMin = weekdayMin, weekendMin = weekendMin }
    end
  end
  table.sort(persons, function(a, b) return a.perWeek > b.perWeek end)
  return { grid = grid, people = persons, count = count }
end

-- "mostly 7pm-11pm, weeknights" from a person's usual() entry.
function L.habit(p)
  -- the peak: the hour whose 3-hour neighbourhood is busiest (so one odd hour doesn't beat a regular evening)
  local peak, score = nil, 0
  for h = 0, 23 do
    local s = p.hours[(h - 1) % 24] + p.hours[h] + p.hours[(h + 1) % 24]
    if p.hours[h] > 0 and s > score then score, peak = s, h end
  end
  if not peak then return "" end
  local best = p.hours[peak]
  local lo, hi = peak, peak
  local keep = best * 0.4
  for _ = 1, 23 do
    local nlo = (lo - 1) % 24
    if p.hours[nlo] >= keep and nlo ~= hi then lo = nlo else break end
  end
  for _ = 1, 23 do
    local nhi = (hi + 1) % 24
    if p.hours[nhi] >= keep and nhi ~= lo then hi = nhi else break end
  end
  local when
  local wd, we = p.weekdayMin / 5, p.weekendMin / 2 -- per day
  if wd > 0 and we > wd * 1.6 then when = "mostly weekends"
  elseif we > 0 and wd > we * 1.6 then when = "mostly weeknights"
  else when = "most days" end
  return "usually " .. L.clock(lo * 60) .. "-" .. L.clock((hi + 1) * 60) .. ", " .. when
end

-- The best time for the crew to play together: { weekday, from, to (hours, `to` exclusive), avg } or nil.
-- The busiest 2-hour block of the week, grown while the next hour is nearly as busy (up to 4 hours).
function L.bestTime(usual)
  local g = usual and usual.grid
  if not g then return nil end
  local best
  for w = 0, 6 do
    for h = 0, 22 do
      local v = g[w][h] + g[w][h + 1]
      if v > 0 and (not best or v > best.v) then best = { weekday = w, from = h, to = h + 2, v = v } end
    end
  end
  if not best then return nil end
  local w = best.weekday
  local peak = math.max(g[w][best.from], g[w][best.from + 1])
  while best.to - best.from < 4 do
    local before, after = g[w][best.from - 1] or 0, g[w][best.to] or 0
    if after >= peak * 0.75 and after > 0 and best.to < 24 then best.to = best.to + 1
    elseif before >= peak * 0.75 and before > 0 and best.from > 0 then best.from = best.from - 1
    else break end
  end
  local sum = 0
  for h = best.from, best.to - 1 do sum = sum + g[w][h] end
  best.avg = sum / (best.to - best.from)
  return best
end

-- "Best time to play together: Tue 8pm-11pm (usually 3 of 5 on)"
function L.bestTimeText(best, total)
  if not best then return "Not enough play time yet to find the best time to play together." end
  local avg = math.floor(best.avg + 0.5)
  if avg < 1 then avg = 1 end
  return string.format("Best time to play together: %s %s-%s (usually %d of %d on)", L.SHORT_DAYS[best.weekday + 1],
    L.clock(best.from * 60), L.clock(best.to * 60), avg, total or avg)
end
