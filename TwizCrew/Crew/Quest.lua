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
  local none = { qn = "", qo = "", qc = "", qi = "", qs = "" }
  if ns.Modules.setting("panel", "shareQuest") == false then return none end
  local q = Quest.look()
  if not q then return none end
  -- qi: the quest's ID (friends check if they can get it); qs: "1" can be shared, "0" can't, "" unknown
  local qs = ""
  if type(q.id) == "number" and QLog().IsPushableQuest then
    local p = call(QLog().IsPushableQuest, q.id)
    if p ~= nil and readable(p) then qs = (p and p ~= 0) and "1" or "0" end
  end
  local objs = {}
  for i, o in ipairs(q.objectives or {}) do
    if i > OBJECTIVES then break end
    objs[#objs + 1] = (o.text:gsub(";", ","))
  end
  return {
    qn = ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX),
    qo = ns.Util.truncateUTF8(table.concat(objs, "; "), OBJ_MAX),
    qc = q.complete and "1" or "",
    qi = type(q.id) == "number" and tostring(q.id) or "",
    qs = qs,
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

---------------------------------------------------------------------------------------------- quest sharing
-- Asking a friend to share their quest: the game only shares when that player clicks something themselves, so the
-- friend gets a pop-up ("Twiz asks you to share Kobold Camp Cleanup") and one click on it shares it. Sharing only
-- works in a group (the game's rule).
local REQUEST_GAP = 15 -- seconds between requests to (or from) the same friend
local askedAt, heardAt = {}, {}

-- Am I in any group? (The game's "is this name in my party" can say no on Forever even when they are, because of
-- how names are written; so the request only needs a group, and the game itself refuses a share outside it.)
local function inAnyGroup()
  return call(IsInGroup) and true or call(IsInRaid) and true or false
end

-- Questie's database, when Questie is installed and ready (it knows level, class, race and earlier-quest rules).
local function questie()
  if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return nil end
  local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
  if ok and type(db) == "table" and type(db.IsDoableVerbose) == "function" then return db end
end

local QUESTIE_OK = { [0] = true, [5] = true } -- available; its parent quest is active
local QUESTIE_DONE, QUESTIE_HAVE = 1, 2

-- Can I get a friend's quest? id: its quest ID (or nil); title: its name; shareable: true / false / nil.
-- Returns status, words: "ok" (you can get it), "have", "done", "unshareable", "no" (with Questie's reason), or
-- "unknown" (no way to tell; asking is fine).
function Quest.canGet(id, title, shareable)
  id = tonumber(id)
  if shareable == false then return "unshareable", "it can't be shared" end
  for _, q in ipairs(entries()) do
    if (id and q.id == id) or (type(title) == "string" and title ~= "" and
      (q.title == title or ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX) == title)) then
      return "have", "you already have it"
    end
  end
  if not id then return "unknown", nil end
  if QLog().IsQuestFlaggedCompleted and call(QLog().IsQuestFlaggedCompleted, id) == true then
    return "done", "you already did it"
  end
  if type(IsQuestFlaggedCompleted) == "function" and call(IsQuestFlaggedCompleted, id) == true then
    return "done", "you already did it"
  end
  local db = questie()
  if db then
    local ok, text, _, state = pcall(db.IsDoableVerbose, id, false, true, true)
    if ok then
      if state == QUESTIE_DONE then return "done", "you already did it" end
      if state == QUESTIE_HAVE then return "have", "you already have it" end
      if QUESTIE_OK[state] then return "ok", "you can get it" end
      if state ~= nil then
        local why = type(text) == "string" and text:match(":%s*(.+)$") or nil
        return "no", "you can't take it" .. (why and (" (" .. why:lower() .. ")") or "")
      end
    end
  end
  return "unknown", nil
end

-- Ask `name` to share `title` (their quest, as their copy sent it). Returns true when the request went out, or
-- false and a reason ("group", "soon", "quest").
function Quest.request(name, title)
  if type(name) ~= "string" or name == "" then return false, "quest" end
  if type(title) ~= "string" or title == "" then return false, "quest" end
  if not inAnyGroup() and not ns.isTestName(name) then
    print("TwizCrew: quest sharing only works in a group. Invite " .. ns.Util.safeText(name) .. " first.")
    return false, "group"
  end
  local now = ns.now()
  if askedAt[name] and now - askedAt[name] < REQUEST_GAP then
    print("TwizCrew: you just asked " .. ns.Util.safeText(name) .. ". Give them a moment.")
    return false, "soon"
  end
  askedAt[name] = now
  local fields = { t = name, q = title }
  if not ns.Comm.sendTo(name, "QREQ", fields) then ns.Comm.sendGroup("QREQ", fields) end
  print("TwizCrew: asked " .. ns.Util.safeText(name) .. " to share \"" .. ns.Util.safeText(title) .. "\".")
  return true
end

-- Shares the quest with this title (or the title as it was cut short for the wire) with the group.
-- Returns "shared", "missing" (not in your log), "unshareable" (the game won't share it) or "noapi".
function Quest.share(want)
  if type(want) ~= "string" or want == "" then return "missing" end
  for _, q in ipairs(entries()) do
    if q.title == want or ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX) == want then
      if type(q.id) == "number" and QLog().SetSelectedQuest then call(QLog().SetSelectedQuest, q.id) end
      if type(SelectQuestLogEntry) == "function" then call(SelectQuestLogEntry, q.index) end
      local pushable
      if type(q.id) == "number" and QLog().IsPushableQuest then
        pushable = call(QLog().IsPushableQuest, q.id)
      elseif type(GetQuestLogPushable) == "function" then
        pushable = call(GetQuestLogPushable)
      end
      if pushable == false or pushable == 0 then return "unshareable" end
      if type(QuestLogPushQuest) ~= "function" then return "noapi" end
      call(QuestLogPushQuest)
      return "shared"
    end
  end
  return "missing"
end

-- The click on the pop-up: share it, or say why not.
function Quest.shareFor(name, title)
  local r = Quest.share(title)
  if r == "missing" then
    print("TwizCrew: you don't have \"" .. ns.Util.safeText(title) .. "\" anymore.")
  elseif r == "unshareable" then
    print("TwizCrew: the game won't let \"" .. ns.Util.safeText(title) .. "\" be shared.")
  elseif r == "noapi" then
    print("TwizCrew: quest sharing isn't available in this game version.")
  end
  return r
end

local function onRequest(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" or type(f.q) ~= "string" or f.q == "" then return end
  if f.t and not ns.isMe(f.t) then return end -- a group message meant for someone else
  if ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end -- crew only
  if ns.Modules.setting("panel", "questRequests") == false then return end
  local now = ns.now()
  if heardAt[sender] and now - heardAt[sender] < REQUEST_GAP then return end
  heardAt[sender] = now
  local title = ns.Util.truncateUTF8(f.q, TITLE_MAX)
  if ns.Popups and ns.Popups.questRequest then ns.Popups.questRequest(sender, title) end
  ns.Log.add("info", "quest share request from %s", sender)
end

ns.Comm.on("QREQ", function(sender, fields) ns.Log.safe("panel", onRequest, sender, fields) end)

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
