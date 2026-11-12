-- Stolen crown pop-ups (Hall of Shame part 2): when someone takes the lead in an award this session, a pop-up says
-- so. Worked out from the numbers every copy already has (no message of its own). Not in the first STEAL_AFTER s of
-- a session; at most one pop-up every STEAL_GAP s (several steals together share one). Silent while my stats are
-- off; rates and "right now" awards (`noSteal`) never pop up. Switch: Live roasts, "Stolen crown pop-ups".
-- Click: the Hall of Shame at that award's tab, this session. Feature id "steals" (not a module).
local _, ns = ...

local Steals = {}
ns.Steals = Steals

local FEATURE = "steals"
local L = ns.TrophyLogic
local STEAL_AFTER, STEAL_GAP = 900, 60

local leaders, leadersSid, present -- the last check's leaders, their session and who was on the board
local queue, order = {}, {} -- queued steals by award id, in the order they came
local lastPopup, lastTitle
local started = false
local recheck = false -- a check waits for a friend's numbers to settle

local function names(list) return table.concat(list, " & ") end

local function has(list, name)
  for _, n in ipairs(list) do if n == name then return true end end
  return false
end

local function wanted()
  return ns.Modules.isEnabled("roasts") and ns.Modules.setting("roasts", "stealPopups") ~= false
end

local function statsOn() return ns.Modules.isEnabled("stats") end

-- Forget everything: the next check is a silent baseline.
local function reset() leaders, leadersSid, present, queue, order = nil, nil, nil, {}, {} end

local function openAt(def)
  if not statsOn() then return end
  if ns.Commands and ns.Commands.setPanel and not ns.Modules.isEnabled("panel") then ns.Commands.setPanel(true, true) end
  if ns.Board and ns.Board.setView then ns.Board.setView("session") end
  if ns.Board and ns.Board.setTab then ns.Board.setTab(def.tab) end
  if ns.Panel and ns.Panel.setTab then ns.Panel.setTab("shame") end
end

-- The session board now: session, awards, who is on it (set), valueOf(def, name) -> "8 deaths".
local function board()
  local session = ns.Session and ns.Session.current()
  if not session then return nil end
  local entries = ns.StatsStore.entries("session", session.id)
  local byName = {}
  for _, e in ipairs(entries) do byName[e.name] = e end
  local function valueOf(def, name)
    local e = byName[name]
    local v = e and ns.StatsLogic.awardValue(def, e.stats)
    return v and ns.StatsLogic.valueText(def, v, e.stats) or ""
  end
  return session, ns.StatsLogic.awards(entries), byName, valueOf
end

-- Seconds until every friend on the board has had STATS_CHANGED_GAP s without a new STATS piece (their snapshot
-- comes in pieces); nil when nobody's numbers are that fresh.
local function settleIn(here)
  local gap, wait = ns.Config.STATS_CHANGED_GAP, nil
  for name, e in pairs(here) do
    local ago = not e.mine and ns.StatsStore.heardAgo(name)
    if ago and ago < gap and (not wait or gap - ago > wait) then wait = gap - ago end
  end
  return wait
end

-- Compares the session's leaders with the last check; queues steals once the session is old enough.
-- Nothing while my stats are off (and the first check after is a silent baseline). While a friend's numbers are
-- still arriving it waits and checks again when they have settled.
function Steals.check()
  if not statsOn() then reset(); return end
  local session, list, here, valueOf = board()
  if not session then return end
  local wait = settleIn(here)
  if wait then
    if not recheck then
      recheck = true
      C_Timer.After(wait, function()
        ns.Log.safe(FEATURE, function()
          recheck = false
          Steals.check()
        end)
      end)
    end
    return
  end
  if leadersSid == session.id and ns.wallclock() - (session.start or 0) >= STEAL_AFTER then
    for _, s in ipairs(L.steals(leaders, list, valueOf, here, present)) do
      local q = queue[s.def.id]
      if q then
        q.thieves = s.thieves -- the newest thieves; the victims stay the first ones
      else
        queue[s.def.id] = s
        order[#order + 1] = s.def.id
      end
    end
  end
  leaders, leadersSid, present = L.leaders(list), session.id, here
end

-- Shows what's queued, once per award: one steal, or one pop-up for several. At most once every STEAL_GAP s.
-- Each award is checked again first: dropped when a victim has it back (or left), or nobody leads.
function Steals.flush()
  if not statsOn() or #order == 0 then return end
  if lastPopup and ns.now() - lastPopup < STEAL_GAP then return end
  local q, ids = queue, order
  queue, order = {}, {}
  if not wanted() or not ns.Popups or not ns.Popups.notice then return end
  local session, list, here, valueOf = board()
  if not session then return end
  local now = L.leaders(list)
  local shown = {}
  for _, id in ipairs(ids) do
    local s, cur = q[id], now[id]
    local undone = not cur
    for _, v in ipairs(s.victims) do
      if not here[v] or (cur and has(cur, v)) then undone = true end
    end
    if not undone then
      shown[#shown + 1] = { def = s.def, thieves = cur, victims = s.victims,
        thiefText = valueOf(s.def, cur[1]), victimText = valueOf(s.def, s.victims[1]) }
    end
  end
  if #shown == 0 then return end
  lastPopup = ns.now()
  local first = shown[1]
  local title, sub
  if #shown == 1 then
    title = names(first.thieves) .. " just stole " .. first.def.name .. " from " .. names(first.victims) .. "!"
    sub = "(" .. first.thiefText .. " vs " .. first.victimText .. ")  -  click to see"
  else
    title = #shown .. " crowns changed hands"
    local parts = {}
    for _, s in ipairs(shown) do parts[#parts + 1] = s.def.name .. ": " .. names(s.thieves) end
    sub = table.concat(parts, ", ")
  end
  lastTitle = title
  ns.Popups.notice(first.def.icon, title, sub, function() openAt(first.def) end)
end

function Steals.lastShown() return lastTitle end

-- Started by the stats module (onEnable), like Trophies.start.
function Steals.start()
  if started then return end
  started = true
  ns.Bus.on(FEATURE, "STATS_CHANGED", function() ns.Log.safe(FEATURE, Steals.check) end)
  ns.Bus.on(FEATURE, "SESSION_CHANGED", reset)
  ns.Bus.on(FEATURE, "MODULE_TOGGLED", function(id) if id == "stats" then reset() end end)
  C_Timer.NewTicker(5, function() ns.Log.safe(FEATURE, Steals.flush) end)
end
