-- The quest you're on (shared with the crew as qn / qo / qc, shown on your row and in its tooltip).
-- "On" = the quest whose objectives changed most recently (or that you just accepted); else the one you track;
-- else the first quest in your log. Works with the modern C_QuestLog functions and the older quest-log globals.
local _, ns = ...

local Quest = {}
ns.Quest = Quest

local TITLE_MAX, OBJ_MAX, OBJECTIVES = 40, 120, 3
local HEADING_MAX = 30 -- letters of a quest log heading (the zone name) sent with the quest list

local current          -- questID we decided you're on
local counts = {}      -- questID -> "n/m;n/m" of its objectives last time we looked (to see which one moved)

local call = ns.Util.plain

-- For fields of a table the game returned (the table is plain, its fields may be secret).
local function readable(v)
  return v ~= nil and not ns.Util.isSecret(v)
end

local function QLog() return type(C_QuestLog) == "table" and C_QuestLog or {} end -- looked up each time

-- A heading row's name as it is kept (nil when the game gives none or a secret one).
local function headingOf(title)
  if not readable(title) or type(title) ~= "string" or title == "" then return nil end
  return title
end

-- Every quest in the log: { id, title, index, complete, heading }. heading: the name of the heading row above it in
-- the game's quest log (the zone, or a group like a class or a dungeon), or nil.
local function entries()
  local list = {}
  local n = call(QLog().GetNumQuestLogEntries) or call(GetNumQuestLogEntries)
  n = tonumber(n) or 0
  local heading
  for i = 1, math.min(n, 60) do
    local info = call(QLog().GetInfo, i)
    if type(info) == "table" then
      if info.isHeader then
        heading = headingOf(info.title)
      elseif info.questID and readable(info.title) then
        list[#list + 1] = { id = info.questID, title = info.title, index = i,
          complete = call(QLog().IsComplete, info.questID) and true or false, heading = heading }
      end
    else
      local title, _, _, isHeader, _, isComplete, _, questID = call(GetQuestLogTitle, i)
      if isHeader then
        heading = headingOf(title)
      elseif title and readable(title) then
        list[#list + 1] = { id = questID or ("i" .. i), title = title, index = i,
          complete = isComplete == 1 or isComplete == true, heading = heading }
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
  local n = tonumber((call(GetNumQuestLeaderBoards, q.index))) or 0
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

-- My whole quest log for the crew (Crew/QuestList.lua): { id, title (cut for the wire), shareable (true / false /
-- nil when the game doesn't say), heading (the quest log heading it is under, cut for the wire, or nil) }. Empty
-- when I don't share quests.
Quest.TITLE_MAX = TITLE_MAX
Quest.HEADING_MAX = HEADING_MAX
local function pushable(id)
  if not QLog().IsPushableQuest then return nil end
  local p = call(QLog().IsPushableQuest, id)
  if p ~= nil and readable(p) then return (p and p ~= 0) and true or false end
  return nil
end

function Quest.log()
  local out = {}
  if ns.Modules.setting("panel", "shareQuest") == false then return out end
  for _, q in ipairs(entries()) do
    if type(q.id) == "number" then
      out[#out + 1] = { id = q.id, title = ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX), shareable = pushable(q.id),
        heading = q.heading and ns.Util.truncateUTF8(q.heading, HEADING_MAX) or nil }
    end
  end
  return out
end

-- One quest of my log by its ID: { id, title (cut for the wire), shareable }, or nil.
function Quest.find(id)
  id = tonumber(id)
  if not id then return nil end
  for _, q in ipairs(entries()) do
    if q.id == id then
      return { id = id, title = ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX), shareable = pushable(id) }
    end
  end
  return nil
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

-- Quests the game refused to share with me (a friend's copy told mine: see "why a share didn't work" below):
-- quest ID or title -> the words. Forgotten when I level up or turn a quest in (the reason may be gone), and on
-- /reload.
local refused = {}
local DID_IT = "you already did it" -- (a remembered "already done" refusal still reads as done: canGet's "done")

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
  local why = (id and refused[id]) or (type(title) == "string" and refused[title]) or nil
  if why then return (why == DID_IT and "done" or "no"), why end
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

-- Sharing needs a group: true (and the usual explanation in chat) when I'm in none.
function Quest.needGroup(name)
  if inAnyGroup() or ns.isTestName(name) then return false end
  print("TwizCrew: quest sharing only works in a group. Invite " .. ns.Util.safeText(tostring(name)) .. " first.")
  return true
end

-- Ask `name` to share `title` (their quest, as their copy sent it). Returns true when the request went out, or
-- false and a reason ("group", "soon", "quest").
function Quest.request(name, title)
  if type(name) ~= "string" or name == "" then return false, "quest" end
  if type(title) ~= "string" or title == "" then return false, "quest" end
  if Quest.needGroup(name) then return false, "group" end
  local now = ns.now()
  if askedAt[name] and now - askedAt[name] < REQUEST_GAP then
    print("TwizCrew: you just asked " .. ns.Util.safeText(name) .. ". Give them a moment.")
    return false, "soon"
  end
  askedAt[name] = now
  local fields = { t = ns.wireName(name), q = title }
  if not ns.Comm.sendTo(name, "QREQ", fields) then ns.Comm.sendGroup("QREQ", fields) end
  print("TwizCrew: asked " .. ns.Util.safeText(name) .. " to share \"" .. ns.Util.safeText(title) .. "\".")
  return true
end

-- Picks one quest of my log and shares it with the group (see Quest.share). The quest the quest log had picked
-- before is picked again afterwards, so an open quest log does not jump to the shared quest.
local function push(q)
  local wasId = QLog().GetSelectedQuest and call(QLog().GetSelectedQuest)
  local wasIndex = call(GetQuestLogSelection)
  if type(q.id) == "number" and QLog().SetSelectedQuest then call(QLog().SetSelectedQuest, q.id) end
  if type(SelectQuestLogEntry) == "function" then call(SelectQuestLogEntry, q.index) end
  local r = "shared"
  local can
  if type(q.id) == "number" and QLog().IsPushableQuest then
    can = call(QLog().IsPushableQuest, q.id)
  elseif type(GetQuestLogPushable) == "function" then
    can = call(GetQuestLogPushable)
  end
  if can == false or can == 0 then
    r = "unshareable"
  elseif type(QuestLogPushQuest) ~= "function" then
    r = "noapi"
  else
    call(QuestLogPushQuest)
  end
  if type(wasId) == "number" and wasId > 0 and QLog().SetSelectedQuest then call(QLog().SetSelectedQuest, wasId) end
  if type(wasIndex) == "number" and wasIndex > 0 and type(SelectQuestLogEntry) == "function" then
    call(SelectQuestLogEntry, wasIndex)
  end
  if r ~= "shared" then return r end
  return "shared", (type(q.id) == "number" and q.id or nil)
end

-- Shares the quest with this title (or the title as it was cut short for the wire) with the group.
-- Returns "shared", "missing" (not in your log), "unshareable" (the game won't share it) or "noapi".
function Quest.share(want)
  if type(want) ~= "string" or want == "" then return "missing" end
  for _, q in ipairs(entries()) do
    if q.title == want or ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX) == want then return push(q) end
  end
  return "missing"
end

-- Shares the quest with this ID (Quest.share's answers; "shared" comes with the ID and the title as sent).
function Quest.shareId(id)
  id = tonumber(id)
  if not id then return "missing" end
  for _, q in ipairs(entries()) do
    if q.id == id then
      local r = push(q)
      return r, id, ns.Util.truncateUTF8(tostring(q.title), TITLE_MAX)
    end
  end
  return "missing"
end

---------------------------------------------------------------------------------- why a share didn't work
-- The game tells only the one who shares why a share failed ("Twiz is not eligible for that quest"), as a system
-- line. After a share made for a friend's request, that line is watched for a few seconds and its reason is sent
-- back (QRES), so the friend's copy can say why and stop offering a quest they can't take. This is what tells
-- "too low" or "an earlier quest is missing" for people without Questie.
local PUSH_WINDOW = 10 -- seconds after the click in which the game's answer is taken as the answer to that share
local ACCEPT_GUARD = 2 -- seconds after a share in which "has accepted your quest" is taken as late news of the last one
-- One watch per friend: name -> { name, title, id, at, window (seconds, default PUSH_WINDOW), onResult (fn(code),
-- optional: a share of several, Crew/QuestAsk.lua, which then tells the friend itself) }
local watching = {}

-- { the game's own text (by its global name), the English text when the game has no such name, our code }
local PUSH_RESULTS = {
  { "ERR_QUEST_PUSH_INVALID_S", "%s is not eligible for that quest", "inv" },
  { "ERR_QUEST_PUSH_ALREADY_DONE_S", "%s has completed that quest", "done" },
  { "ERR_QUEST_PUSH_ONQUEST_S", "%s is already on that quest", "have" },
  { "ERR_QUEST_PUSH_LOG_FULL_S", "%s's quest log is full", "full" },
  { "ERR_QUEST_PUSH_BUSY_S", "%s is busy", "busy" },
  { "ERR_QUEST_PUSH_DECLINED_S", "%s has declined your quest", "decl" },
  { "ERR_QUEST_PUSH_TOO_FAR_S", "%s is too far away to receive your quest", "far" },
}

-- What each code means for the one who asked. keep = true: asking again is no use, so the quest stops being
-- offered (until a level-up or a quest turned in).
local RESULT_WORDS = {
  inv = { "you can't take it yet (too low, or an earlier quest is missing)", keep = true },
  done = { DID_IT, keep = true },
  have = { "you already have it" },
  full = { "your quest log is full" },
  busy = { "you were busy (a window was open)" },
  decl = { "you declined it" },
  far = { "you are too far away from them" },
  -- only from copies that share several quests at once (Crew/QuestAsk.lua; older copies drop unknown codes)
  gone = { "they don't have it anymore" },
  cant = { "the game won't let it be shared" },
}

-- "Frostie has accepted your quest": no QRES (nothing went wrong), only a share of several moves on.
local PUSH_ACCEPTED = { "ERR_QUEST_PUSH_ACCEPTED_S", "%s has accepted your quest" }

-- "%s is busy." -> "^(.+) is busy" (the name is captured; an ending full stop doesn't matter)
local function resultPattern(format)
  if type(format) ~= "string" or not format:find("%s", 1, true) then return nil end
  local p = format:gsub("%.$", ""):gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)")
  return "^" .. p
end

local function sameFriend(said, name)
  if type(said) ~= "string" or said == "" then return false end
  if ns.keyOfName(said) == name then return true end
  local full = ns.Transport and ns.Transport.fullName and ns.Transport.fullName(name)
  return said == full or ns.shortName(said) == ns.shortName(name)
end

-- A system line: is it the game's answer to the share I just made for a friend? Then tell them.
-- The friend's name in a system line of this kind ({ global name, English text }), or nil.
local function saidBy(text, def)
  local own = rawget(_G, def[1])
  local said = text:match(resultPattern(type(own) == "string" and own or def[2]) or "^$")
  if not said and type(own) == "string" then said = text:match(resultPattern(def[2]) or "^$") end
  return said
end

local function onSystemLine(text)
  if next(watching) == nil then return end
  local now = ns.now()
  local live = {}
  for name, p in pairs(watching) do
    if now - p.at > (p.window or PUSH_WINDOW) or now < p.at then watching[name] = nil else live[#live + 1] = p end
  end
  if #live == 0 or ns.Util.isSecret(text) or type(text) ~= "string" then return end
  for _, def in ipairs(PUSH_RESULTS) do
    local said = saidBy(text, def)
    if said then
      for _, p in ipairs(live) do
        if sameFriend(said, p.name) then
          watching[p.name] = nil
          ns.Log.add("info", "quest share for %s refused by the game: %s", p.name, def[3])
          if p.onResult then
            p.onResult(def[3])
          else
            Quest.tellResult(p.name, p.title, p.id, def[3])
          end
          return
        end
      end
    end
  end
  local said = saidBy(text, PUSH_ACCEPTED)
  if not said then return end
  for _, p in ipairs(live) do
    -- (a late line about the quest before this one, when the asker's copy already moved the share on, is not news)
    if p.onResult and sameFriend(said, p.name) and now - p.at >= ACCEPT_GUARD then
      watching[p.name] = nil
      p.onResult("ok")
      return
    end
  end
end

-- Shares my quest with this ID for a friend's ask of several (Crew/QuestAsk.lua) and watches for the game's answer
-- for `window` seconds: onResult(code) gets a PUSH_RESULTS code, or "ok" when the game says they took it. Returns
-- Quest.shareId's answer and the title.
function Quest.shareForQueue(name, id, onResult, window)
  local r, _, title = Quest.shareId(id)
  if r == "shared" then
    watching[name] = { name = name, title = title, id = tonumber(id), at = ns.now(), window = window, onResult = onResult }
  end
  return r, title
end

-- Stops watching for the game's answer to a share made by Quest.shareForQueue with this onResult.
function Quest.stopWatching(onResult)
  for name, p in pairs(watching) do
    if p.onResult == onResult then watching[name] = nil end
  end
end

-- Tells the friend why their quest did not come (a QRES with one of the codes of RESULT_WORDS).
function Quest.tellResult(name, title, id, code)
  local fields = { t = ns.wireName(name), q = title or "", i = id and tostring(id) or "", r = code }
  if not ns.Comm.sendTo(name, "QRES", fields) then ns.Comm.sendGroup("QRES", fields) end
end

-- A friend's copy says why the game didn't give me their quest.
local function onResult(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" or type(f.q) ~= "string" or f.q == "" then return end
  if f.t and not ns.wireIsMe(f.t) then return end
  if ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end -- crew only
  local words = RESULT_WORDS[f.r]
  if not words then return end
  local title = ns.Util.truncateUTF8(f.q, TITLE_MAX)
  if words.keep then
    local id = tonumber(f.i)
    if id then refused[id] = words[1] end
    refused[title] = words[1]
    if ns.QuestList and ns.QuestList.changed then ns.QuestList.changed() end
  end
  print("TwizCrew: " .. ns.Util.safeText(sender) .. " couldn't share \"" .. ns.Util.safeText(title) .. "\": "
    .. words[1] .. ".")
  if ns.QuestAsk and ns.QuestAsk.onResult then ns.QuestAsk.onResult(sender, tonumber(f.i), title, f.r) end
end

local function forgetRefused()
  if next(refused) == nil then return end
  refused = {}
  if ns.QuestList and ns.QuestList.changed then ns.QuestList.changed() end
end

function Quest.resultPatternForTest(format) return resultPattern(format) end

-- The click on the pop-up: share it, or say why not.
function Quest.shareFor(name, title)
  local r, id = Quest.share(title)
  if r == "shared" and type(name) == "string" then
    watching[name] = { name = name, title = title, id = id, at = ns.now() } -- the game's answer is watched for
  end
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
  if f.t and not ns.wireIsMe(f.t) then return end -- a group message meant for someone else
  if ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end -- crew only
  if ns.Modules.setting("panel", "shareQuest") == false then return end -- (not sharing: nobody can ask)
  local now = ns.now()
  if heardAt[sender] and now - heardAt[sender] < REQUEST_GAP then return end
  heardAt[sender] = now
  local title = ns.Util.truncateUTF8(f.q, TITLE_MAX)
  if ns.Popups and ns.Popups.questRequest then ns.Popups.questRequest(sender, title) end
  ns.Log.add("info", "quest share request from %s", sender)
end

ns.Comm.on("QREQ", function(sender, fields) ns.Log.safe("panel", onRequest, sender, fields) end)
ns.Comm.on("QRES", function(sender, fields) ns.Log.safe("quest", onResult, sender, fields) end)

function Quest.start()
  if Quest.started then return end
  Quest.started = true
  ns.Events.on("quest", "QUEST_ACCEPTED", function(a, b)
    local id = tonumber(b) or tonumber(a) -- classic: (logIndex, questID); modern: (questID)
    Quest.accepted(id)
    ns.Self.refresh("quest")
    if ns.QuestAsk and ns.QuestAsk.accepted then ns.QuestAsk.accepted(id) end
  end)
  -- only events every game version has (registering an unknown one is an error)
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_TURNED_IN" }) do
    ns.Events.on("quest", e, function() ns.Self.refresh("quest") end)
  end
  ns.Events.on("quest", "CHAT_MSG_SYSTEM", onSystemLine)
  ns.Events.on("quest", "PLAYER_LEVEL_UP", forgetRefused)
  ns.Events.on("quest", "QUEST_TURNED_IN", forgetRefused)
end
