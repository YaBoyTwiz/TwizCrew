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

local function tabOf(id)
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
