-- Stolen crown pop-ups (Hall of Shame part 2): when someone takes the lead in an award this session, a pop-up says
-- so. Worked out from the numbers every copy already has (no message of its own). Not in the first STEAL_AFTER s of
-- a session; at most one pop-up every STEAL_GAP s (several steals together share one). Switch: Live roasts,
-- "Stolen crown pop-ups". Click: the Hall of Shame at that award's tab. Feature id "steals" (not a module).
local _, ns = ...

local Steals = {}
ns.Steals = Steals

local FEATURE = "steals"
local L = ns.TrophyLogic
local STEAL_AFTER, STEAL_GAP = 900, 60

local leaders, leadersSid -- the last check's leaders and the session they belong to
local queue = {}
local lastPopup, lastTitle
local started = false

local function names(list) return table.concat(list, " & ") end

local function wanted()
  return ns.Modules.isEnabled("roasts") and ns.Modules.setting("roasts", "stealPopups") ~= false
end

local function openAt(def)
  if ns.Commands and ns.Commands.setPanel and not ns.Modules.isEnabled("panel") then ns.Commands.setPanel(true, true) end
  if ns.Board and ns.Board.setTab then ns.Board.setTab(def.tab) end
  if ns.Panel and ns.Panel.setTab then ns.Panel.setTab("shame") end
end

-- Compares the session's leaders with the last check; queues steals once the session is old enough.
function Steals.check()
  local session = ns.Session and ns.Session.current()
  if not session then return end
  local entries = ns.StatsStore.entries("session", session.id)
  local list = ns.StatsLogic.awards(entries)
  local byName = {}
  for _, e in ipairs(entries) do byName[e.name] = e end
  if leadersSid == session.id and ns.wallclock() - (session.start or 0) >= STEAL_AFTER then
    local found = L.steals(leaders, list, function(def, name)
      local e = byName[name]
      local v = e and ns.StatsLogic.awardValue(def, e.stats)
      return v and ns.StatsLogic.valueText(def, v, e.stats) or ""
    end)
    for _, s in ipairs(found) do queue[#queue + 1] = s end
  end
  leaders, leadersSid = L.leaders(list), session.id
end

-- Shows what's queued: one steal, or one pop-up for several. At most once every STEAL_GAP s.
function Steals.flush()
  if #queue == 0 then return end
  if lastPopup and ns.now() - lastPopup < STEAL_GAP then return end
  local list = queue
  queue = {}
  if not wanted() or not ns.Popups or not ns.Popups.notice then return end
  lastPopup = ns.now()
  local first = list[1]
  local title, sub
  if #list == 1 then
    title = names(first.thieves) .. " just stole " .. first.def.name .. " from " .. names(first.victims) .. "!"
    sub = "(" .. first.thiefText .. " vs " .. first.victimText .. ")  -  click to see"
  else
    title = #list .. " crowns changed hands"
    local parts = {}
    for _, s in ipairs(list) do parts[#parts + 1] = s.def.name .. ": " .. names(s.thieves) end
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
  ns.Bus.on(FEATURE, "SESSION_CHANGED", function() leaders, leadersSid, queue = nil, nil, {} end)
  C_Timer.NewTicker(5, function() ns.Log.safe(FEATURE, Steals.flush) end)
end
