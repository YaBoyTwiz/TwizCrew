-- Pure Hall of Shame logic (no frames): the board's model from the award list, and the session start time text.
local _, ns = ...

local BoardLogic = {}
ns.BoardLogic = BoardLogic

local function isNumber(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function text(v)
  if type(v) ~= "string" then return "" end
  return ns.Util.safeText(v)
end

-- "09:02 PM" -> "9:02 pm". "" when the time or the game's date() is missing.
function BoardLogic.timeText(wall)
  if not isNumber(wall) or type(date) ~= "function" then return "" end
  local ok, s = pcall(date, "%I:%M %p", wall)
  if not ok or type(s) ~= "string" then return "" end
  return (s:gsub("^0", ""):lower())
end

local function ago(ctx, name)
  local e = ctx.entries and ctx.entries[name]
  if type(e) ~= "table" or e.mine or not isNumber(e.at) or not isNumber(ctx.wall) then return "" end
  local online
  if type(ctx.online) == "function" then online = ctx.online(name) else online = e.online end
  if online then return "" end
  return " (updated " .. ns.Util.ago(math.max(0, ctx.wall - e.at)) .. ")"
end

local function tipLines(a, ctx)
  local tip = { a.def.info or a.def.name }
  for i, top in ipairs(a.top or {}) do
    tip[#tip + 1] = i .. ". " .. text(top.name) .. ": " .. top.text .. ago(ctx, top.name)
    if a.def.id == "corpse" then
      local e = ctx.entries and ctx.entries[top.name]
      local ds = type(e) == "table" and type(e.stats) == "table" and e.stats.ds
      if isNumber(ds) and ds > 0 then tip[#tip + 1] = "Time dead: " .. ns.StatsLogic.duration(ds) end
    end
  end
  return tip
end

-- Names shown on a row; more tied winners show as "+N", and every name is in the tooltip's "Tied:" line.
BoardLogic.SHOWN_WINNERS = 2

local function row(a, ctx)
  local def = a.def
  local r = {
    id = def.id, name = def.name, icon = def.icon or ns.StatsDefs.ICON_FALLBACK, winners = {}, classes = {},
    empty = a.empty and true or false, tip = tipLines(a, ctx), more = 0,
  }
  if r.empty then
    r.text = "nobody yet"
  else
    r.text = a.text or ""
    for i, name in ipairs(a.winners) do
      r.winners[i] = text(name)
      local e = ctx.entries and ctx.entries[name]
      r.classes[i] = type(e) == "table" and type(e.class) == "string" and e.class or false
    end
    if #r.winners > BoardLogic.SHOWN_WINNERS then
      r.more = #r.winners - BoardLogic.SHOWN_WINNERS
      r.tip[#r.tip + 1] = "Tied: " .. table.concat(r.winners, ", ")
    end
  end
  return r
end

local function wipes(ctx)
  local most = 0
  for _, e in pairs(ctx.entries or {}) do
    local wp = type(e) == "table" and type(e.stats) == "table" and e.stats.wp
    if isNumber(wp) and wp > most then most = wp end
  end
  return math.floor(most)
end

BoardLogic.TROPHY_TAB = { id = "trophies", label = "Trophies", name = "Trophies" }

local function awardDef(id)
  for _, d in ipairs(ns.StatsDefs.AWARDS) do if d.id == id then return d end end
end

-- One row per person with trophies: "7 trophies", their top awards by count, a tooltip with every award and streak.
local function trophyRows(summary, ctx)
  local people = {}
  for name, p in pairs(summary or {}) do
    if type(p) == "table" and (p.total or 0) > 0 then people[#people + 1] = { name = name, p = p } end
  end
  table.sort(people, function(a, b)
    if a.p.total ~= b.p.total then return a.p.total > b.p.total end
    return a.name < b.name
  end)
  local rows = {}
  for _, x in ipairs(people) do
    local awards = {}
    for id, n in pairs(x.p.counts or {}) do
      local d = awardDef(id)
      if d then awards[#awards + 1] = { name = d.name, n = n, streak = (x.p.streaks or {})[id] } end
    end
    table.sort(awards, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      return a.name < b.name
    end)
    local total = x.p.total .. (x.p.total == 1 and " trophy" or " trophies")
    local parts, tip = {}, { text(x.name) .. ": " .. total }
    for i, a in ipairs(awards) do
      if i <= 2 then parts[#parts + 1] = a.name .. " x" .. a.n end
      local line = a.name .. ": " .. a.n
      if a.streak and a.streak >= 2 then line = line .. " (" .. a.streak .. " sessions in a row)" end
      tip[#tip + 1] = line
    end
    local e = ctx.entries and ctx.entries[x.name]
    rows[#rows + 1] = {
      id = x.name, name = text(x.name), icon = "Interface\\Icons\\INV_Misc_Ribbon_01", text = total,
      winners = { table.concat(parts, ", ") }, classes = { type(e) == "table" and e.class or false },
      more = 0, empty = false, tip = tip,
    }
  end
  if #rows == 0 then
    rows[1] = { id = "none", name = "No trophies yet", icon = ns.StatsDefs.ICON_FALLBACK, text = "", winners = {},
      classes = {}, more = 0, empty = true,
      tip = { "Trophies are handed out when a crew session ends (at least 30 minutes, at least 2 people)." } }
  end
  return rows
end

local function tabOf(id)
  if id == "trophies" then return BoardLogic.TROPHY_TAB end
  for _, t in ipairs(ns.StatsDefs.TABS) do if t.id == id then return t end end
  return ns.StatsDefs.TABS[1]
end

local function lowerFirst(s) return (s:gsub("^%u", string.lower)) end

-- view: "session" | "all"; awardsList from StatsLogic.awards; ctx = { tab, session, starter, timeText, wipeLine,
-- entries = { [name] = entry }, online = fn(name) -> bool, wall }. Returns { subtitle, rows, footer, tabs }: the
-- rows of the chosen tab only (unknown tab: the first), tabs = { { id, label, active } } in order.
function BoardLogic.model(view, awardsList, ctx)
  ctx = ctx or {}
  local session = view == "session"
  local tab = tabOf(ctx.tab)
  local out = { rows = {}, tabs = {} }
  for _, t in ipairs(ns.StatsDefs.TABS) do
    out.tabs[#out.tabs + 1] = { id = t.id, label = t.label, active = t.id == tab.id }
  end
  out.tabs[#out.tabs + 1] = { id = BoardLogic.TROPHY_TAB.id, label = BoardLogic.TROPHY_TAB.label,
    active = tab.id == BoardLogic.TROPHY_TAB.id }
  if tab.id == "trophies" then
    out.subtitle = "Trophies: from every session the crew played"
    out.rows = trophyRows(ctx.trophies, ctx)
    return out
  end
  local sub
  if not session then
    sub = "All time"
  elseif type(ctx.session) == "table" then
    sub = "Session started " .. text(ctx.timeText) .. " by " .. text(ctx.starter)
  else
    sub = "Waiting for the crew session to start"
  end
  out.subtitle = tab.name .. ": " .. lowerFirst(sub)
  for _, a in ipairs(awardsList or {}) do
    if a.def.tab == tab.id then out.rows[#out.rows + 1] = row(a, ctx) end
  end
  if ctx.wipeLine then
    local n = wipes(ctx)
    if n > 0 then
      out.footer = "Wipe Squad: " .. n .. (n == 1 and " wipe" or " wipes") .. (session and " tonight" or "")
    end
  end
  return out
end
