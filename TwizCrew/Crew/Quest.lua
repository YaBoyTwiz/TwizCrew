-- The quest you're on (shared with the crew as qn / qo / qc, shown on your row and in its tooltip).
-- "On" = the quest whose objectives changed most recently (or that you just accepted); else the one you track;
-- else the first quest in your log. Works with the modern C_QuestLog functions and the older quest-log globals.
local _, ns = ...

local Quest = {}
ns.Quest = Quest

local TITLE_MAX, OBJ_MAX, OBJECTIVES = 40, 120, 3

local current          -- questID we decided you're on
local counts = {}      -- questID -> "n/m;n/m" of its objectives last time we looked (to see which one moved)

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h
end

local function readable(v)
  if v == nil then return false end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return false end
  end
  return true
end

local function QLog() return type(C_QuestLog) == "table" and C_QuestLog or {} end -- looked up each time

-- Every quest in the log: { id, title, index, complete }.
local function entries()
  local list = {}
  local n = call(QLog().GetNumQuestLogEntries) or call(GetNumQuestLogEntries)
  n = tonumber(n) or 0
  for i = 1, math.min(n, 60) do
    local info = call(QLog().GetInfo, i)
    if type(info) == "table" then
      if not info.isHeader and info.questID and readable(info.title) then
        list[#list + 1] = { id = info.questID, title = info.title, index = i,
          complete = call(QLog().IsComplete, info.questID) and true or false }
      end
    else
      local title, _, _, isHeader, _, isComplete, _, questID = call(GetQuestLogTitle, i)
      if title and not isHeader and readable(title) then
        list[#list + 1] = { id = questID or ("i" .. i), title = title, index = i, complete = isComplete == 1 or isComplete == true }
      end
    end
  end
  return list
end

-- Objective lines of one quest: { { text, done } }.
local function objectives(q)
  local out = {}
  local list = type(q.id) == "number" and call(QLog().GetQuestObjectives, q.id)
  if type(list) == "table" and #list > 0 then
    for _, o in ipairs(list) do
      if type(o) == "table" and readable(o.text) and o.text ~= "" then out[#out + 1] = { text = o.text, done = o.finished and true or false } end
    end
    return out
  end
  local n = tonumber(call(GetNumQuestLeaderBoards, q.index)) or 0
  for j = 1, n do
    local text, _, done = call(GetQuestLogLeaderBoard, j, q.index)
    if readable(text) and text and text ~= "" then out[#out + 1] = { text = text, done = done and true or false } end
  end
  return out
end

local function countsOf(objs)
  local parts = {}
  for _, o in ipairs(objs) do parts[#parts + 1] = (o.text:match("(%d+/%d+)") or "") .. (o.done and "!" or "") end
  return table.concat(parts, ";")
end

-- The first quest on your watch list (TwizCrew never reads or touches the game's waypoint / super-track: those
-- belong to QuestMaster, Questie and the game, see test_lint).
local function tracked(list)
  local watched = call(QLog().GetQuestIDForQuestWatchIndex, 1)
  if watched then
    for _, q in ipairs(list) do if q.id == watched then return q end end
  end
  return nil
end

-- Looks at the log: notes which quest moved, and returns the one you're on (with its objectives), or nil.
function Quest.look()
  local list = entries()
  local byId, moved = {}, nil
  for _, q in ipairs(list) do
    byId[q.id] = q
    q.objectives = objectives(q)
    local c = countsOf(q.objectives)
    if counts[q.id] ~= nil and counts[q.id] ~= c then moved = q.id end
    counts[q.id] = c
  end
  for id in pairs(counts) do if not byId[id] then counts[id] = nil end end -- turned in or dropped
  if moved then current = moved end
  local q = current and byId[current]
  if not q then
    q = tracked(list) or list[1]
    current = q and q.id or nil
  end
  return q
end

-- You just accepted a quest: that's the one you're on now.
function Quest.accepted(questID)
  if questID then current = questID end
end

-- The wire fields: qn (title), qo (objectives, "; " between them), qc ("1" = ready to turn in). Empty when you
-- don't share quests or have none.
function Quest.wire()
  if ns.Modules.setting("panel", "shareQuest") == false then return { qn = "", qo = "", qc = "" } end
  local q = Quest.look()
  if not q then return { qn = "", qo = "", qc = "" } end
  local objs = {}
  for i, o in ipairs(q.objectives or {}) do
    if i > OBJECTIVES then break end
    objs[#objs + 1] = (o.text:gsub(";", ","))
  end
  return {
    qn = ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX),
    qo = ns.Util.truncateUTF8(table.concat(objs, "; "), OBJ_MAX),
    qc = q.complete and "1" or "",
  }
end

-- "Kobold Camp Cleanup (3/8)" / "(ready to turn in)" from a crew member's shared fields (pure); nil without one.
function Quest.short(name, objText, complete)
  if type(name) ~= "string" or name == "" then return nil end
  if complete then return name .. " (ready to turn in)" end
  if type(objText) == "string" then
    for part in (objText .. ";"):gmatch("%s*(.-)%s*;") do
      local n, m = part:match("(%d+)/(%d+)")
      if n and tonumber(n) < tonumber(m) then return name .. " (" .. n .. "/" .. m .. ")" end
    end
  end
  return name
end

-- The objective lines from qo (pure).
function Quest.objectiveLines(objText)
  local out = {}
  if type(objText) ~= "string" or objText == "" then return out end
  for part in (objText .. ";"):gmatch("%s*(.-)%s*;") do
    if part ~= "" then out[#out + 1] = part end
  end
  return out
end

function Quest.start()
  if Quest.started then return end
  Quest.started = true
  ns.Events.on("comm", "QUEST_ACCEPTED", function(a, b)
    Quest.accepted(tonumber(b) or tonumber(a)) -- classic: (logIndex, questID); modern: (questID)
    ns.Self.refresh("quest")
  end)
  -- only events every game version has (registering an unknown one is an error)
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_TURNED_IN" }) do
    ns.Events.on("comm", e, function() ns.Self.refresh("quest") end)
  end
end
