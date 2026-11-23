-- Pure rules of the "While you were away" card (UI/AwayCard.lua owns the frames and the timing): the guild list
-- snapshot kept at logout, what changed since (levels, joins, leaves), the Hall of Shame crowns that changed hands,
-- and the card's words. No frames and no game calls here.
--
-- A snapshot: { at = wall time, guild = the guild's name (Guild.here()), members = { [key] = { level, class, name
-- (as shown: first word, or full name for namesakes), full (as the game spells it), guid } }, crowns = { [award id]
-- = { winner keys } } }. Members are matched by GUID, then full name, then (old entries without a full name) key, so
-- a member whose key changed is the same member.
local _, ns = ...

local AwayLogic = {}
ns.AwayLogic = AwayLogic

AwayLogic.MIN_AWAY = 12 * 3600 -- s: gone at least this long (since the last logout) before the card shows
AwayLogic.MAX_LINES = 12       -- the card's lines at most, "...and N more" included
AwayLogic.CROWD = 3            -- more joins (or leaves) than this and than CROWD_SHARE of the members: none are listed
AwayLogic.CROWD_SHARE = 0.1

local function num(v) v = tonumber(v); if v and v == v then return v end end

local function entryOf(e)
  return { level = num(e.level), class = type(e.class) == "string" and e.class or nil,
    name = type(e.name) == "string" and e.name or e.key, full = type(e.full) == "string" and e.full or nil,
    guid = type(e.guid) == "string" and e.guid or nil }
end

-- A new snapshot of a whole guild list (members: { key, full, level, class, name, guid }).
function AwayLogic.snapshot(members, at, guild)
  local out = { at = at, guild = guild, members = {} }
  for _, e in ipairs(members or {}) do
    if type(e.key) == "string" and e.key ~= "" then out.members[e.key] = entryOf(e) end
  end
  return out
end

-- An older snapshot brought up to date from a list that may lack the offline members: listed members are updated
-- or added (they are members now), the others stay as they were. Same guild only (nil otherwise).
function AwayLogic.merge(old, members, at, guild)
  if type(old) ~= "table" or type(old.members) ~= "table" or old.guild ~= guild then return nil end
  local out = { at = at, guild = guild, members = {}, crowns = old.crowns }
  local byFull, byGuid = {}, {}
  for k, s in pairs(old.members) do
    if type(k) == "string" and type(s) == "table" then
      out.members[k] = s
      if type(s.full) == "string" then byFull[s.full:lower()] = k end
      if type(s.guid) == "string" then byGuid[s.guid] = k end
    end
  end
  for _, e in ipairs(members or {}) do
    if type(e.key) == "string" and e.key ~= "" then
      local was = (e.guid and byGuid[e.guid]) or (type(e.full) == "string" and byFull[e.full:lower()]) or nil
      if was then out.members[was] = nil end
      out.members[e.key] = entryOf(e)
    end
  end
  return out
end

local function byName(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end

-- What changed between a snapshot and the guild list now. opts: now (wall time), guild (this guild's name; a
-- snapshot of another guild is never used), whole (the list surely holds the offline members: only then are
-- "left" lines made), mine (a set of my own characters' GUIDs, keys and lower-case full names: never listed), minAway
-- (default MIN_AWAY). Real joins and leaves come a few at a time: more "left" lines than CROWD and than CROWD_SHARE
-- of the snapshot's members (a list that only looked whole: the offline members unlisted) drop them all; the same
-- for "joined" against the list now (a snapshot of only the online members). Returns nil when there is nothing to compare (no snapshot, another guild's, a bad time, gone
-- for less than minAway), else { gone = seconds, levels = { { key, name, from, to } }, joined = { { key, name,
-- level, class } }, left = { { key, name } } }.
function AwayLogic.diff(snap, members, opts)
  opts = opts or {}
  if type(snap) ~= "table" or type(snap.members) ~= "table" then return nil end
  local at, now = num(snap.at), num(opts.now)
  if not at or not now then return nil end
  if snap.guild ~= opts.guild then return nil end
  local gone = now - at
  if gone < (opts.minAway or AwayLogic.MIN_AWAY) then return nil end
  local mine = opts.mine or {}
  local function isMine(key, full, guid)
    return mine[key] or (type(full) == "string" and mine[full:lower()]) or (type(guid) == "string" and mine[guid])
  end
  local byGuid, byFull, byKey = {}, {}, {}
  for _, e in ipairs(members or {}) do
    if type(e.key) == "string" then
      if type(e.guid) == "string" then byGuid[e.guid] = e end
      if type(e.full) == "string" then byFull[e.full:lower()] = e end
      byKey[e.key] = e
    end
  end
  local out = { gone = gone, levels = {}, joined = {}, left = {} }
  local matched, before = {}, 0
  for key, s in pairs(snap.members) do
    if type(key) == "string" and type(s) == "table" then
      before = before + 1
      local e = (type(s.guid) == "string" and byGuid[s.guid]) or (type(s.full) == "string" and byFull[s.full:lower()])
        or (type(s.full) ~= "string" and byKey[key]) or nil
      if e and not matched[e] then
        matched[e] = true
        local from, to = num(s.level), num(e.level)
        if from and to and to > from and not isMine(e.key, e.full, e.guid) then
          out.levels[#out.levels + 1] = { key = e.key, name = e.name or e.key, from = from, to = to }
        end
      elseif opts.whole and not isMine(key, s.full, s.guid) then
        out.left[#out.left + 1] = { key = key, name = type(s.name) == "string" and s.name or key }
      end
    end
  end
  for _, e in ipairs(members or {}) do
    if type(e.key) == "string" and not matched[e] and not isMine(e.key, e.full, e.guid) then
      out.joined[#out.joined + 1] = { key = e.key, name = e.name or e.key, level = num(e.level), class = e.class }
    end
  end
  local function crowd(n, of) return n > math.max(AwayLogic.CROWD, of * AwayLogic.CROWD_SHARE) end
  if crowd(#out.left, before) then out.left = {} end
  if crowd(#out.joined, #(members or {})) then out.joined = {} end
  table.sort(out.levels, function(a, b)
    if a.to - a.from ~= b.to - b.from then return a.to - a.from > b.to - b.from end
    return byName(a, b)
  end)
  table.sort(out.joined, byName)
  table.sort(out.left, byName)
  return out
end

-- Who holds each all-time crown, from StatsLogic.awards: { [award id] = { winner keys, A-Z } }. Awards whose lead
-- changes without anyone doing anything (rates: `noSteal`), empty ones and test fakes (ns.isTestName) are left out.
function AwayLogic.crowns(awards)
  local out = {}
  for _, item in ipairs(awards or {}) do
    local def = item.def
    if type(def) == "table" and type(def.id) == "string" and not def.noSteal and not item.empty
      and type(item.winners) == "table" and #item.winners > 0 then
      local list = {}
      for _, n in ipairs(item.winners) do if not ns.isTestName(n) then list[#list + 1] = n end end
      table.sort(list)
      if #list > 0 then out[def.id] = list end
    end
  end
  return out
end

-- Crowns that changed hands: held before and now, by nobody who held it before. defs: the awards in board order
-- ({ id, name, tab }: StatsDefs.AWARDS). Test fakes count as nobody (also in an older snapshot). Returns { { id,
-- name, tab, to = { keys }, from = { keys } } }.
local function real(list)
  if type(list) ~= "table" then return nil end
  local out = {}
  for _, n in ipairs(list) do if not ns.isTestName(n) then out[#out + 1] = n end end
  return out
end

function AwayLogic.crownChanges(before, now, defs)
  local out = {}
  if type(before) ~= "table" or type(now) ~= "table" then return out end
  for _, def in ipairs(defs or {}) do
    local id = def.id
    local was, is = real(before[id]), real(now[id])
    if was and is and #was > 0 and #is > 0 then
      local held = {}
      for _, n in ipairs(was) do held[n] = true end
      local kept = false
      for _, n in ipairs(is) do if held[n] then kept = true end end
      if not kept then out[#out + 1] = { id = id, name = def.name or id, tab = def.tab, to = is, from = was } end
    end
  end
  return out
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- "You were gone 14 hours" (under a day and a half), else "You were gone 3 days".
function AwayLogic.goneText(seconds)
  local hours = math.floor((tonumber(seconds) or 0) / 3600)
  if hours < 36 then return "You were gone " .. plural(math.max(1, hours), "hour", "hours") end
  return "You were gone " .. plural(math.floor(hours / 24), "day", "days")
end

local I = "Interface\\Icons\\"
AwayLogic.ICONS = { calendar = I .. "INV_Scroll_03", joined = I .. "INV_Misc_Gift_01", left = I .. "Ability_Rogue_Sprint",
  crown = I .. "INV_Misc_Ribbon_01", level = I .. "Spell_Holy_PowerInfusion", more = I .. "INV_Misc_Note_02" }

-- The card's lines, most news first: new calendar notes, who joined, who left, crowns, level-ups. d: from diff (may
-- be nil); notes: how many new calendar notes; crowns: from crownChanges; display(key) names a crown holder (default:
-- the key). Names are made safe to show. Each line: { kind, text, icon, tab (crowns: the award's Hall of Shame tab) }.
function AwayLogic.lines(d, notes, crowns, display)
  local safe = ns.Util.safeText
  display = display or function(key) return key end
  local out = {}
  local function add(kind, text, extra)
    local l = { kind = kind, text = text, icon = AwayLogic.ICONS[kind] }
    for k, v in pairs(extra or {}) do l[k] = v end
    out[#out + 1] = l
  end
  notes = tonumber(notes) or 0
  if notes > 0 then add("calendar", plural(notes, "new calendar note", "new calendar notes")) end
  d = d or { levels = {}, joined = {}, left = {} }
  for _, j in ipairs(d.joined) do add("joined", safe(tostring(j.name)) .. " joined the guild") end
  for _, l in ipairs(d.left) do add("left", safe(tostring(l.name)) .. " left the guild") end
  for _, c in ipairs(crowns or {}) do
    local function list(keys)
      local names = {}
      for i, k in ipairs(keys) do names[i] = safe(tostring(display(k))) end
      return table.concat(names, " & ")
    end
    add("crown", list(c.to) .. " took " .. safe(tostring(c.name)) .. " from " .. list(c.from), { id = c.id, tab = c.tab })
  end
  for _, l in ipairs(d.levels) do add("level", safe(tostring(l.name)) .. " " .. l.from .. " -> " .. l.to) end
  return out
end

-- At most `max` lines (default MAX_LINES): past that, the last one is "...and N more".
function AwayLogic.cap(lines, max)
  max = max or AwayLogic.MAX_LINES
  if #lines <= max then return lines end
  local out = {}
  for i = 1, max - 1 do out[i] = lines[i] end
  out[max] = { kind = "more", text = "...and " .. (#lines - max + 1) .. " more", icon = AwayLogic.ICONS.more }
  return out
end
