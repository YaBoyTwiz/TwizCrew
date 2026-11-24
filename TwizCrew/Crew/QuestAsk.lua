-- Asking a friend for several of their quests at once (the ticks in their quest window, UI/QuestWindow.lua), and
-- sharing them, one at a time, when a friend asks me.
--   QMR = the ask: t (who should share), k (the ask's stamp), q (quest IDs, "33,42,57"; at most ASK_MAX, one message).
--         The titles are not sent: the sharer's copy takes them from its own log and leaves out what is not there.
--   QMS = the sharer's news: t (who asked), k, st ("yes" they clicked, "no" no click in time, "busy" sharing for
--         someone else, "next" their click is needed for the next quest, "end" finished or stopped), d (how many
--         quests the asker took), r (with "end": why it stopped).
--   QMU = the asker's news: t (who shares), k, i (a quest ID I just took), or x = "1" (I stopped asking).
-- The sharer gets ONE pop-up ("Twiz asks for 3 quests"); its click shares the first quest. The game offers the asker
-- one quest at a time, so the next share goes out only once the last one is answered: the asker's copy says it took
-- it (QMU), or the game tells the sharer it was refused or declined (Crew/Quest.lua, "why a share didn't work"), or
-- nobody answered in STEP_WAIT. The next share then goes out by itself (AUTO_NEXT), unless the game wants a click for
-- it: then (or with AUTO_NEXT off) the sharer gets a "Share next quest (2 of 3)" pop-up for each next one.
-- Some answers end the whole share instead: the asker's quest log is full, they are too far away (both would fail
-- the same way for every quest left), or no answer in STEP_WAIT (the offer may still be open on their screen).
-- "Busy" (a window was open) is tried once more, BUSY_RETRY later.
-- A friend whose list has no zone headings (list format 1) has an older copy that drops QMR: their quests are asked
-- for with the usual single asks (QREQ), one after another, each once the last one is answered (or asked once more
-- after OLD_WAIT, then skipped), never sooner than OLD_GAP after the last (an older copy drops a second ask from the
-- same friend within 15 s, counted when it arrives there).
local ADDON, ns = ...

local QuestAsk = {}
ns.QuestAsk = QuestAsk

local FEATURE = "quest"

-- THE SWITCH (to flip after seeing it in the game, docs/TESTING.md): true = after the sharer's one click, the next
-- quests are shared by themselves; false = the sharer clicks a "Share next quest" pop-up for each next one. Even when
-- true, a share the game blocks (it wants a click) turns the rest of this session to clicks.
QuestAsk.AUTO_NEXT = true

local ASK_MAX = 25      -- quests in one ask (more than a quest log holds; the IDs fit in one message)
local ASK_GAP = 15      -- seconds between two asks to (or from) the same friend
local ANSWER_WAIT = 30  -- asker: no "yes" or "no" from them by then: no answer
local STALL = 120       -- asker: no news at all for this long while they share: their copy stopped
local POPUP_SECONDS = 20 -- sharer: how long the ask (and each "share next") pop-up waits for the click
local STEP_WAIT = 45    -- sharer: seconds to wait for the answer to one offer before the next
local NEXT_GAP = 1      -- sharer: seconds between an answer and the next share (automatic)
local BLOCK_GAP = 2     -- sharer: a "blocked" from the game this soon after an automatic share is about that share
local BUSY_RETRY = 5    -- sharer: seconds before a quest that met "busy" is offered once more
local OLD_WAIT = 45     -- asker (older copy): a single ask with no answer by then is asked once more, then skipped
local OLD_GAP = 20      -- asker (older copy): seconds between two single asks (their copy needs 15 on arrival)
local OLD_STALL = 150   -- asker (older copy): no answer at all for this long: give up
local TICK = 1

local asks = {}         -- asker: friend -> { key, ids, titles, mode ("new" | "old"), state, got, failed, at, news, ... }
local lastWords = {}    -- asker: friend -> the line about my last ask to them (shown in their window)
local askedAt = {}      -- asker: friend -> when I last asked them
local job               -- sharer: { asker, key, ids, titles, i, state, created, at, auto, autoAt, nextAt, taken }
local heardAt = {}      -- sharer: friend -> when their last ask came
local clickMode = false -- sharer: the game blocked an automatic share this session
local ticker
local stamps = 0

local function safe(s) return ns.Util.safeText(tostring(s or "")) end
local function inAnyGroup() return ns.QuestList.inAnyGroup() end
local function inMyGroup(name) return ns.QuestList.inMyGroup(name) end

local function refresh()
  if ns.QuestWindow and ns.QuestWindow.refresh then ns.QuestWindow.refresh() end
end

local function sendTo(name, msgType, fields)
  if not ns.Comm.sendTo(name, msgType, fields) then ns.Comm.sendGroup(msgType, fields) end
end

local function quests(n) return n == 1 and "1 quest" or (n .. " quests") end

-- "33,42,57" -> { 33, 42, 57 } (each once); nil when it is not a list of at most ASK_MAX quest IDs.
function QuestAsk.parseIds(text)
  if type(text) ~= "string" or text == "" or #text > ASK_MAX * 8 then return nil end
  local out, seen = {}, {}
  for part in (text .. ","):gmatch("([^,]*),") do
    if not part:match("^%d%d?%d?%d?%d?%d?%d?$") then return nil end
    local id = tonumber(part)
    if id > 0 and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  if #out == 0 or #out > ASK_MAX then return nil end
  return out
end

local function startTicker()
  if ticker or not (C_Timer and C_Timer.NewTicker) then return end
  ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, QuestAsk.tick) end)
end

local function stopTickerIfIdle()
  if ticker and not job and next(asks) == nil then
    ticker:Cancel()
    ticker = nil
  end
end

--------------------------------------------------------------------------------------------------------- asking
local function countGot(a)
  local n = 0
  for _ in pairs(a.got) do n = n + 1 end
  return n
end

-- Every quest of the ask is answered (taken, or refused with a reason).
local function allAnswered(a)
  for _, id in ipairs(a.ids) do
    if not a.got[id] and not a.failed[id] then return false end
  end
  return true
end

-- Why a share stopped, as the asker reads it ...
local STOP_WORDS = {
  group = "the group broke up", noclick = "no click for the next one", stall = "their copy stopped answering",
  none = "they don't have those quests anymore", off = "they turned quest sharing off",
  noapi = "quest sharing isn't available in their game", gone = "they went offline",
  full = "your quest log is full", far = "you are too far away from them", time = "no answer to the last offer",
}
-- ... and as the sharer reads it.
local SHARER_WORDS = {
  group = "the group broke up", noclick = "no click for the next one", gone = "they went offline",
  noapi = "quest sharing isn't available in this game version", full = "their quest log is full",
  far = "they are too far away", time = "no answer to the last offer",
}

-- My ask to `name` is over: one line in chat, and the same words for their window.
local function finish(name, why)
  local a = asks[name]
  if not a then return end
  asks[name] = nil
  local who = safe(name)
  local got = countGot(a) .. " of " .. #a.ids
  local words
  if why == "no" or why == "noanswer" then
    words = "No answer from " .. who .. "."
  elseif why == "busy" then
    words = who .. " is sharing quests with someone else. Ask again in a moment."
  elseif why == "cancel" then
    words = "Stopped asking " .. who .. " (you got " .. got .. ")."
  elseif why == "done" then
    words = "You got " .. got .. " quests from " .. who .. "."
  else
    words = who .. " stopped sharing (" .. (STOP_WORDS[why] or "it didn't work") .. "). You got " .. got .. " quests."
  end
  lastWords[name] = words
  print("TwizCrew: " .. words)
  -- their copy may still be sharing for an ask mine gave up on: tell it to stop
  if a.mode == "new" and (why == "noanswer" or why == "stall") then
    sendTo(name, "QMU", { t = ns.wireName(name), k = a.key, x = "1" })
  end
  ns.Log.add("info", "quest ask to %s over: %s", name, tostring(why))
  if ns.QuestList.changed then ns.QuestList.changed() end
  refresh()
  stopTickerIfIdle()
end

-- Older copy: the next single ask (QREQ), or the end.
local function oldNext(name)
  local a = asks[name]
  if not a then return end
  while true do
    a.cur = a.cur + 1
    local id = a.ids[a.cur]
    if not id then finish(name, "done"); return end
    if not a.got[id] and not a.failed[id] then
      local status = ns.Quest.canGet(id, a.titles[id], true)
      if status == "have" then
        a.got[id] = true
      elseif status == "done" then
        a.failed[id] = "done"
      else
        local ok, why = ns.Quest.request(name, a.titles[id])
        if ok then
          a.sentAt, a.ready, a.again = ns.now(), false, false
          refresh()
          return
        end
        if why == "group" then finish(name, "group"); return end
        a.cur = a.cur - 1 -- (asked them a moment ago by hand) try again in a moment
        a.sentAt, a.ready = ns.now(), true
        return
      end
    end
  end
end

-- Older copy: the single ask got no answer in OLD_WAIT: ask once more, then skip it (one line in chat).
local function oldTimeout(name)
  local a = asks[name]
  local id = a.ids[a.cur]
  if a.again or not id then
    print("TwizCrew: " .. safe(name) .. " didn't answer about \"" .. safe(a.titles[id]) .. "\", so it was skipped.")
    oldNext(name)
    return
  end
  local ok, why = ns.Quest.request(name, a.titles[id])
  if not ok and why == "group" then finish(name, "group"); return end
  a.sentAt, a.again = ns.now(), true
end

-- The ask in one message, whole: quests are left out from the end until it fits (never with a cut ID).
local function fitAsk(fields, list)
  while #list > 1 do
    fields.q = table.concat(list, ",")
    local texts = ns.Codec.encode("QMR", fields)
    local msg = #texts == 1 and ns.Codec.decode(texts[1])
    if msg and msg.fields.q == fields.q then return end
    table.remove(list)
  end
  fields.q = table.concat(list, ",")
end

-- Asks `name` for these quests of theirs (IDs from their list). Returns true when the ask went out.
function QuestAsk.ask(name, ids)
  if type(name) ~= "string" or name == "" or type(ids) ~= "table" or #ids == 0 then return false end
  if ns.Quest.needGroup(name) then return false end
  if not inMyGroup(name) and not ns.isTestName(name) then
    print("TwizCrew: quest sharing only works in a group. Invite " .. safe(name) .. " first.")
    return false
  end
  local now = ns.now()
  if asks[name] or (askedAt[name] and now - askedAt[name] < ASK_GAP and now >= askedAt[name]) then
    print("TwizCrew: you just asked " .. safe(name) .. ". Give them a moment.")
    return false
  end
  local titles = {}
  for _, q in ipairs(ns.QuestList.all(name)) do titles[q.id] = q.title end
  local list = {}
  for _, id in ipairs(ids) do
    if #list < ASK_MAX and titles[id] and id <= 9999999 then list[#list + 1] = id end
  end
  if #list == 0 then return false end
  askedAt[name] = now
  lastWords[name] = nil
  local a = { ids = list, titles = titles, got = {}, failed = {}, at = now, news = now, state = "sent" }
  asks[name] = a
  if (ns.QuestList.format(name) or 1) >= 2 then
    a.mode = "new"
    stamps = stamps + 1
    a.key = (math.floor(now) % 100000) .. "x" .. stamps
    local fields = { t = ns.wireName(name), k = a.key }
    fitAsk(fields, list)
    sendTo(name, "QMR", fields)
    print("TwizCrew: asked " .. safe(name) .. " for " .. quests(#list) .. ".")
  else
    a.mode = "old"
    a.cur = 0
    print("TwizCrew: " .. safe(name) .. " has an older TwizCrew, so you ask for one quest at a time (they click for "
      .. "each one).")
    oldNext(name)
  end
  startTicker()
  refresh()
  return true
end

-- Stops my ask to `name` (the window's "Stop asking").
function QuestAsk.cancel(name)
  local a = asks[name]
  if not a then return false end
  if a.mode == "new" then sendTo(name, "QMU", { t = ns.wireName(name), k = a.key, x = "1" }) end
  finish(name, "cancel")
  return true
end

-- Is an ask of mine to `name` going on?
function QuestAsk.active(name) return asks[name] ~= nil end

-- The line about my ask to `name` for their window (nil: nothing to say).
function QuestAsk.status(name)
  local a = asks[name]
  if not a then return lastWords[name] end
  local who = safe(name)
  local got = countGot(a) .. " of " .. #a.ids
  if a.mode == "old" then return "Asking one at a time (older TwizCrew): got " .. got .. " so far." end
  if a.state == "sent" then return "Asked for " .. quests(#a.ids) .. ". Waiting for " .. who .. " to say yes." end
  if a.waitClick then return who .. " clicks for each one: got " .. got .. " so far." end
  return who .. " said yes: got " .. got .. " so far."
end

-- I took a quest (QUEST_ACCEPTED): is it one I asked for?
function QuestAsk.accepted(id)
  id = tonumber(id)
  if not id then return end
  for name, a in pairs(asks) do
    for _, want in ipairs(a.ids) do
      if want == id and not a.got[id] then
        a.got[id], a.news = true, ns.now()
        if a.mode == "new" then
          sendTo(name, "QMU", { t = ns.wireName(name), k = a.key, i = tostring(id) })
        elseif a.ids[a.cur] == id then
          a.ready = true
        end
        if a.mode == "new" and allAnswered(a) then finish(name, "done") end
      end
    end
  end
  if ns.QuestList.changed then ns.QuestList.changed() end
end

-- A friend's copy says why the game didn't give me one of their quests (Crew/Quest.lua already said so in chat).
function QuestAsk.onResult(sender, id, title, code)
  local a = asks[sender]
  if not a then return end
  local found
  for _, want in ipairs(a.ids) do
    if (id and want == id) or (not id and a.titles[want] == title) then found = want end
  end
  if not found or a.got[found] then return end
  a.failed[found], a.news = code or "?", ns.now()
  if a.mode == "old" then
    if a.ids[a.cur] == found then a.ready = true end
  elseif allAnswered(a) then
    finish(sender, "done")
  end
  refresh()
end

local function onNews(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  if not ns.wireIsMe(f.t) or ns.isMe(sender) then return end
  local a = asks[sender]
  if not a or a.mode ~= "new" or f.k ~= a.key then return end
  a.news = ns.now()
  if f.st == "yes" then
    a.state = "yes"
  elseif f.st == "next" then
    a.state, a.waitClick = "yes", true
  elseif f.st == "no" or f.st == "busy" then
    finish(sender, f.st)
    return
  elseif f.st == "end" then
    finish(sender, type(f.r) == "string" and f.r ~= "" and f.r or "done")
    return
  end
  refresh()
end

--------------------------------------------------------------------------------------------------------- sharing
local onStep -- (below)

local function tellAsker(fields)
  if not job then return end
  fields.t, fields.k = ns.wireName(job.asker), job.key
  sendTo(job.asker, "QMS", fields)
end

-- The share for this ask is over (why: "done", "group", "cancel", "gone", "noclick", "noapi", "no", ...). The asker
-- is told, except when they stopped it, went offline, or were already told ("no").
local QUIET = { cancel = true, gone = true, no = true, replaced = true } -- the asker is not told (see above)
local function stop(why)
  local j = job
  if not j then return end
  if not QUIET[why] then tellAsker({ st = "end", r = why, d = tostring(j.taken) }) end
  ns.Quest.stopWatching(onStep)
  job = nil
  if j.state ~= "ask" then
    local who = safe(j.asker)
    if why == "done" then
      print("TwizCrew: done sharing with " .. who .. " (" .. j.taken .. " of " .. #j.ids .. " taken).")
    elseif why ~= "cancel" and why ~= "replaced" then
      print("TwizCrew: stopped sharing with " .. who .. " (" .. (SHARER_WORDS[why] or why) .. ").")
    end
  end
  ns.Log.add("info", "quest share for %s over: %s", j.asker, tostring(why))
  stopTickerIfIdle()
end

local function showNext()
  local id = job.ids[job.i + 1]
  job.state, job.at = "click", ns.now()
  tellAsker({ st = "next", d = tostring(job.taken) })
  if ns.Popups and ns.Popups.questAsk then
    ns.Popups.questAsk(job.asker, "next", #job.ids, job.i + 1, job.titles[id], QuestAsk.shareNextClick)
  end
end

-- Shares the next quest of the ask. byClick: called from the player's own click (else from the timer).
local function shareNext(byClick)
  while job do
    if job.i >= #job.ids then stop("done"); return end
    if not (inAnyGroup() and inMyGroup(job.asker)) then stop("group"); return end
    local i = job.i + 1
    local id = job.ids[i]
    job.i, job.state, job.at, job.auto, job.autoAt = i, "wait", ns.now(), not byClick, ns.now()
    local r, title = ns.Quest.shareForQueue(job.asker, id, onStep, STEP_WAIT)
    if not job or job.i ~= i or job.state ~= "wait" then -- (the game blocked it: now a click is needed)
      ns.Quest.stopWatching(onStep)
      return
    end
    if r == "shared" then return end
    if r == "noapi" then stop("noapi"); return end
    ns.Quest.tellResult(job.asker, title or job.titles[id], id, r == "unshareable" and "cant" or "gone")
  end
end

-- The next share in `gap` seconds (by itself), or a "Share next quest" pop-up when a click is needed.
local function nextStep(gap)
  if QuestAsk.AUTO_NEXT and not clickMode then
    job.state, job.nextAt = "next", ns.now() + gap
  else
    showNext()
  end
end

-- The answer to the quest I just offered (a code of Crew/Quest.lua's PUSH_RESULTS, "ok" (they took it) or "time").
-- A refusal is told to the asker here (QRES), except the ones that end the whole share.
onStep = function(code)
  if not job or job.state ~= "wait" then return end
  ns.Quest.stopWatching(onStep)
  local id = job.ids[job.i]
  if code == "ok" then
    job.taken = job.taken + 1
  elseif code == "full" or code == "far" or code == "time" then
    stop(code) -- every quest left would fail the same way (or their offer may still be open)
    return
  elseif code == "busy" and not job.retried[id] then
    job.retried[id] = true
    job.i = job.i - 1 -- the same quest once more, a little later
    nextStep(BUSY_RETRY)
    return
  else
    ns.Quest.tellResult(job.asker, job.titles[id], id, code)
  end
  if job.i >= #job.ids then stop("done"); return end
  nextStep(NEXT_GAP)
end

-- The click on the ask pop-up: say yes and share the first quest.
function QuestAsk.yesClick()
  if not job or job.state ~= "ask" then return end
  if not (inAnyGroup() and inMyGroup(job.asker)) then
    print("TwizCrew: quest sharing only works in a group. Invite " .. safe(job.asker) .. " first.")
    stop("group")
    return
  end
  tellAsker({ st = "yes" })
  shareNext(true)
end

-- The click on a "Share next quest" pop-up.
function QuestAsk.shareNextClick()
  if not job or job.state ~= "click" then return end
  shareNext(true)
end

-- The game blocked one of my calls (ADDON_ACTION_BLOCKED / _FORBIDDEN): when it is the share made by itself a moment
-- ago, the game wants a click for each share: offer that quest again with a pop-up, and use clicks from now on.
local function onBlocked(addon, fn)
  if addon ~= ADDON or not job or job.state ~= "wait" or not job.auto then return end
  -- (when the game names the blocked function, it must be the share)
  if not ns.Util.isSecret(fn) and type(fn) == "string" and not fn:find("QuestLogPushQuest", 1, true) then return end
  if ns.now() - job.autoAt > BLOCK_GAP then return end
  clickMode = true
  ns.Quest.stopWatching(onStep)
  ns.Log.add("warn", "an automatic quest share was blocked by the game: a click is needed for each one")
  job.i = job.i - 1
  showNext()
end

local function onAsk(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  if not ns.wireIsMe(f.t) or ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end -- crew only
  if type(f.k) ~= "string" or f.k == "" or #f.k > 16 then return end
  local ids = QuestAsk.parseIds(f.q)
  if not ids then return end
  if job and job.asker == sender and job.key == f.k then return end -- (the same ask by a second way)
  local now = ns.now()
  if heardAt[sender] and now - heardAt[sender] < ASK_GAP and now >= heardAt[sender] then return end
  if not (inAnyGroup() and inMyGroup(sender)) then return end -- sharing needs us in one group
  heardAt[sender] = now
  if ns.Modules.setting("panel", "shareQuest") == false then -- not sharing: nobody can ask, and they hear so
    sendTo(sender, "QMS", { t = ns.wireName(sender), k = f.k, st = "end", r = "off", d = "0" })
    return
  end
  if job and job.asker == sender then
    stop("replaced") -- their copy forgot the last ask (a /reload, say): this one counts
  elseif job then
    sendTo(sender, "QMS", { t = ns.wireName(sender), k = f.k, st = "busy" })
    return
  end
  local list, titles = {}, {}
  for _, id in ipairs(ids) do
    local q = ns.Quest.find(id)
    if q and q.shareable ~= false then
      list[#list + 1] = id
      titles[id] = q.title
    end
  end
  if #list == 0 then
    sendTo(sender, "QMS", { t = ns.wireName(sender), k = f.k, st = "end", r = "none", d = "0" })
    return
  end
  job = { asker = sender, key = f.k, ids = list, titles = titles, i = 0, state = "ask", created = now, at = now,
    taken = 0, retried = {} }
  if ns.Popups and ns.Popups.questAsk then
    ns.Popups.questAsk(sender, "ask", #list, 1, titles[list[1]], QuestAsk.yesClick)
  end
  ns.Log.add("info", "quest ask from %s for %d quests", sender, #list)
  startTicker()
end

local function onAskerNews(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  if not ns.wireIsMe(f.t) or not job or job.asker ~= sender or f.k ~= job.key then return end
  if f.x == "1" then stop("cancel"); return end
  local id = tonumber(f.i)
  if id and job.state == "wait" and job.ids[job.i] == id then onStep("ok") end
end

------------------------------------------------------------------------------------------------------- the clock
function QuestAsk.tick()
  local now = ns.now()
  -- asker
  local due = {}
  for name, a in pairs(asks) do due[#due + 1] = { name, a } end
  for _, x in ipairs(due) do
    local name, a = x[1], x[2]
    local m = ns.roster and ns.roster:get(name)
    if not m or not m.online then
      finish(name, "gone")
    elseif not inMyGroup(name) then
      finish(name, "group")
    elseif a.mode == "new" then
      if a.state == "sent" and now - a.at > ANSWER_WAIT then finish(name, "noanswer")
      elseif a.state ~= "sent" and now - a.news > STALL then finish(name, "stall") end
    elseif now - a.news > OLD_STALL then
      finish(name, "stall")
    elseif now - a.sentAt >= OLD_GAP then
      if a.ready then oldNext(name) elseif now - a.sentAt > OLD_WAIT then oldTimeout(name) end
    end
  end
  -- sharer
  if not job then stopTickerIfIdle(); return end
  local m = ns.roster and ns.roster:get(job.asker)
  if not m or not m.online then stop("gone"); return end
  if job.state == "ask" then
    if now - job.created > POPUP_SECONDS + 1 then
      tellAsker({ st = "no" })
      stop("no")
    end
    return
  end
  if not (inAnyGroup() and inMyGroup(job.asker)) then stop("group"); return end
  if job.state == "wait" and now - job.at > STEP_WAIT then
    onStep("time")
  elseif job.state == "next" and now >= job.nextAt then
    shareNext(false)
  elseif job.state == "click" and now - job.at > POPUP_SECONDS + 1 then
    stop("noclick")
  end
end

local function onGroupChanged()
  if inAnyGroup() then return end
  local names = {}
  for name in pairs(asks) do names[#names + 1] = name end
  for _, name in ipairs(names) do finish(name, "group") end
  if job and job.state ~= "ask" then stop("group") end
end

ns.Comm.on("QMR", function(sender, fields) ns.Log.safe(FEATURE, onAsk, sender, fields) end)
ns.Comm.on("QMS", function(sender, fields) ns.Log.safe(FEATURE, onNews, sender, fields) end)
ns.Comm.on("QMU", function(sender, fields) ns.Log.safe(FEATURE, onAskerNews, sender, fields) end)

function QuestAsk.start()
  if QuestAsk.started then return end
  QuestAsk.started = true
  ns.Events.on(FEATURE, "GROUP_ROSTER_UPDATE", onGroupChanged)
  ns.Events.on(FEATURE, "ADDON_ACTION_BLOCKED", onBlocked)
  ns.Events.on(FEATURE, "ADDON_ACTION_FORBIDDEN", onBlocked)
end

-- Test hooks.
QuestAsk.ASK_MAX = ASK_MAX
function QuestAsk.jobForTest() return job end
function QuestAsk.askForTest(name) return asks[name] end
function QuestAsk.clickModeForTest(on) if on ~= nil then clickMode = on end return clickMode end
