-- A friend's whole quest log, so you can see every quest they could share with you (not only the one they're on).
-- QLQ = "send me your quest list" (t = who should answer); QLA = the list: s (a stamp, the same in every piece),
-- n (how many quests), and one "q<questID>" = "<1 can be shared | 0 can't | ? unknown><title>" per quest.
-- Asked when you hover or right-click a friend, and for crew members who are in your group. A copy in a group also
-- sends its list to the group again when its quests change. Copies without this (v0.2.0 and older) drop both
-- message types, so for them only the one quest on their row is known, as before.
-- The heads-up: when a group member's list shows quests you can get, one pop-up says so (once per grouping).
local _, ns = ...

local QuestList = {}
ns.QuestList = QuestList

local FEATURE = "quest"
local call = ns.Util.plain

local ASK_GAP = 20       -- seconds between two asks to the same friend
local FRESH = 60         -- a list this young is not asked for again on a hover or a right-click
local GROUP_FRESH = 300  -- ... and this young not when the group changes (group members send changes themselves)
local ANSWER_GAP = 10    -- seconds between two answers to the same asker
local PUSH_WAIT = 2      -- seconds after my quests changed before the group gets the new list
local BUILD_AGE = 60     -- a list whose pieces stopped coming is dropped after this
local CACHE = 5          -- seconds "what can I get from them" is remembered
local MAX_QUESTS = 30    -- more than a quest log holds
local GROUP_SETTLE = 1   -- seconds after a group change before looking at who is in it
local GROUP_ASK_WAIT = 5 -- ... and this many more before asking them (their own lists to the group come first)
local GROUP_COPY = 30    -- seconds a list I sent to the group stands in for a whisper to a member who asks
local MENU_TITLE = 30    -- letters of a quest's name in a menu line
local ICON_ASK = "Interface\\Icons\\Spell_ChargePositive"
local ICON_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_LIST = "Interface\\Icons\\INV_Misc_Book_08"

local lists = {}      -- friend -> { at, n, quests = { [id] = { id, title, shareable } } } (the last whole list)
local building = {}   -- friend -> { [stamp] = { at, n, count, quests } } (lists still arriving)
local askedAt, answeredAt = {}, {}
local told = {}       -- friend -> true: the heads-up for them was shown in this grouping
local cache = {}      -- friend -> { at, all }
local sentSig         -- my quests as they were when I last sent my list
local sends = 0
local pushWaiting, groupWaiting, askWaiting = false, false, false
local groupSent       -- { at, sig, members = { [name] = true } }: my last list sent to the group
local anchor

local function inAnyGroup()
  return (call(IsInGroup) or call(IsInRaid)) and true or false
end

-- Is this friend (a member key) in my group? (As the row menu checks it: Forever's name check can miss them.)
local function inMyGroup(name)
  if ns.isTestName(name) then return false end
  local full = (ns.Guild and ns.Guild.fullName(name)) or name
  if call(UnitInParty, full) or call(UnitInRaid, full) then return true end
  return (ns.Where and ns.Where.unitFor and ns.Where.unitFor(name)) and true or false
end

local function redraw()
  local P = ns.Panel and ns.Panel._
  if P and P.requestRedraw then P.requestRedraw() end
end

------------------------------------------------------------------------------------------------------ my list
local function signature(log)
  local parts = {}
  for i, q in ipairs(log) do
    parts[i] = q.id .. (q.shareable == true and "+" or q.shareable == false and "-" or "")
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- My quest log as it is sent: no quest without a name, and no more than a friend's copy takes (MAX_QUESTS), so the
-- count in the list is what arrives.
local function myLog()
  local out = {}
  for _, q in ipairs(ns.Quest.log()) do
    if #out >= MAX_QUESTS then break end
    if type(q.title) == "string" and q.title ~= "" then out[#out + 1] = q end
  end
  return out
end

local function groupMembers()
  local out = {}
  for _, name in ipairs(ns.roster and ns.roster:names() or {}) do
    if not ns.isMe(name) and inMyGroup(name) then out[name] = true end
  end
  return out
end

-- Sends my list: to `to` as a whisper when that works, else to the group (a newer list takes the place of one
-- still waiting in the queue).
local function sendMine(to)
  local log = myLog()
  sends = sends + 1
  local fields = { s = (math.floor(ns.now()) % 100000) .. "x" .. sends, n = tostring(#log) }
  for _, q in ipairs(log) do
    fields["q" .. q.id] = (q.shareable == true and "1" or q.shareable == false and "0" or "?") .. q.title
  end
  local opts = { repeatKeys = { "s", "n" }, bulk = true }
  sentSig = signature(log)
  if to and ns.Comm.sendTo(to, "QLA", fields, opts) then return true end
  opts.replace = "QLA"
  if not ns.Comm.sendGroup("QLA", fields, opts) then return false end
  groupSent = { at = ns.now(), sig = sentSig, members = groupMembers() }
  return true
end

-- My quests changed while I'm in a group: the group gets the new list (once, a moment later).
local function pushIfChanged()
  if pushWaiting or not inAnyGroup() then return end
  if signature(myLog()) == sentSig then return end
  pushWaiting = true
  C_Timer.After(PUSH_WAIT, function()
    pushWaiting = false
    ns.Log.safe(FEATURE, function()
      if inAnyGroup() and signature(myLog()) ~= sentSig then sendMine(nil) end
    end)
  end)
end

----------------------------------------------------------------------------------------------- friends' lists
-- Asks `name` for their list, unless we have a young one or just asked. fresh: how young (seconds, FRESH).
function QuestList.want(name, fresh)
  if type(name) ~= "string" or name == "" or ns.isTestName(name) or ns.isMe(name) then return false end
  local m = ns.roster and ns.roster:get(name)
  if not m or not m.online then return false end
  local now = ns.now()
  local l = lists[name]
  if l and now - l.at < (fresh or FRESH) then return false end
  if askedAt[name] and now - askedAt[name] < ASK_GAP then return false end
  askedAt[name] = now
  local fields = { t = ns.wireName(name) }
  if ns.Comm.sendTo(name, "QLQ", fields) then return true end
  return ns.Comm.sendGroup("QLQ", fields) and true or false
end

-- Do we have their list? (false: never answered, or an older copy of the addon.)
function QuestList.known(name)
  return lists[name] ~= nil
end

-- Every quest of theirs with what it means for me, the ones I can get first:
-- { id, title, can (true: worth asking), status ("ok", "have", "done", "unshareable", "no", "unknown"), words }.
function QuestList.all(name)
  local l = lists[name]
  if not l then return {} end
  local now = ns.now()
  local c = cache[name]
  if c and now - c.at < CACHE and now >= c.at then return c.all end
  local all = {}
  for _, q in pairs(l.quests) do
    local status, words = ns.Quest.canGet(q.id, q.title, q.shareable)
    -- as on the row: yes when we know I can get it, or when it can be shared and I neither have it nor did it
    local can = status == "ok" or (status == "unknown" and q.shareable == true)
    all[#all + 1] = { id = q.id, title = q.title, can = can, status = status, words = words }
  end
  table.sort(all, function(a, b)
    if a.can ~= b.can then return a.can end
    if a.title ~= b.title then return a.title < b.title end
    return a.id < b.id
  end)
  cache[name] = { at = now, all = all }
  return all
end

-- How many of their quests I can get (0 when we don't have their list).
function QuestList.count(name)
  local n = 0
  for _, q in ipairs(QuestList.all(name)) do if q.can then n = n + 1 end end
  return n
end

local function shortTitle(title)
  local safe = ns.Util.safeText(title)
  local shown = ns.Util.truncateUTF8(safe, MENU_TITLE)
  if shown ~= safe then shown = shown .. "..." end
  return shown
end

-- The menu of a friend's quests: ask for the ones I can get, why not for the others.
function QuestList.menuItems(name)
  local items = {}
  if not lists[name] then
    QuestList.want(name)
    items[1] = { label = "No quest list from them yet (asked just now)", icon = ICON_LIST, onClick = function() end }
    items[2] = { label = "They may have an older TwizCrew", icon = ICON_NO, onClick = function() end }
    return items
  end
  local both = 0
  for _, q in ipairs(QuestList.all(name)) do
    if q.can then
      items[#items + 1] = { label = "Ask to share: " .. shortTitle(q.title), icon = ICON_ASK,
        onClick = function() ns.Quest.request(name, q.title) end }
    elseif q.status == "have" then
      both = both + 1
    else
      local why = q.words or (q.status == "unknown" and "can't tell if it can be shared") or "you can't get it"
      items[#items + 1] = { label = "Can't share: " .. shortTitle(q.title) .. " (" .. why .. ")", icon = ICON_NO,
        onClick = function() print("TwizCrew: no use asking: " .. tostring(why) .. ".") end }
    end
  end
  if both > 0 then
    items[#items + 1] = { label = both == 1 and "1 quest you both have" or (both .. " quests you both have"),
      icon = ICON_LIST, onClick = function() end }
  end
  if #items == 0 then
    items[1] = { label = "They have no quests (or don't share them)", icon = ICON_LIST, onClick = function() end }
  end
  return items
end

-- The row menu's entry for a friend: "Their quests (4 you can get)". nil for someone we can't ask.
function QuestList.rowItem(name, at)
  if type(name) ~= "string" or ns.isTestName(name) or ns.isMe(name) then return nil end
  local m = ns.roster and ns.roster:get(name)
  if not m or not m.online then return nil end
  QuestList.want(name)
  local label
  if not lists[name] then
    label = "Their quests (asking...)"
  else
    local n = QuestList.count(name)
    label = "Their quests (" .. (n == 0 and "none" or tostring(n)) .. " you can get)"
  end
  return { label = label, icon = ICON_LIST, onClick = function()
    -- under the row whose menu was just clicked (the panel remembers it), unless the caller named a frame
    QuestList.open(name, at or (ns.Panel and ns.Panel._ and ns.Panel._.menuAnchor) or nil)
  end }
end

local function cursorAnchor()
  if not anchor then
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(1, 1)
  end
  local x, y = call(GetCursorPosition)
  local scale = UIParent and call(UIParent.GetEffectiveScale, UIParent)
  if type(x) == "number" and type(y) == "number" and type(scale) == "number" and scale > 0 then
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
  end
  return anchor
end

-- Opens the menu of their quests under `at` (a frame), or at the mouse.
function QuestList.open(name, at)
  local items = QuestList.menuItems(name)
  QuestList.lastMenu = items
  if ns.Widgets and ns.Widgets.menu then ns.Widgets.menu(at or cursorAnchor(), items) end
  return items
end

------------------------------------------------------------------------------------------------------ heads-up
-- A group member has quests I can get: say so once per grouping.
local function headsUp(name)
  if told[name] or not lists[name] then return end
  if ns.Modules.setting("panel", "questHeadsUp") == false then return end
  if not inAnyGroup() or not inMyGroup(name) then return end
  local n = QuestList.count(name)
  if n == 0 then return end
  told[name] = true
  local who = ns.Util.safeText(name)
  local title = who .. " has " .. (n == 1 and "1 quest" or (n .. " quests")) .. " you can get"
  if ns.Popups and ns.Popups.notice then
    ns.Popups.notice(ICON_ASK, title, "Click to see " .. (n == 1 and "it" or "them") .. " and ask",
      function() QuestList.open(name) end, 12)
  end
  print("TwizCrew: " .. title .. ". Right-click their row, Their quests.")
end

-- A list from them is on its way (some of its pieces are here).
local function arriving(name)
  local now = ns.now()
  for _, cur in pairs(building[name] or {}) do
    if now - cur.at <= BUILD_AGE and now >= cur.at then return true end
  end
  return false
end

-- A moment after a group change: asks the crew members in my group whose lists did not come by themselves.
local function askGroupLater()
  if askWaiting then return end
  askWaiting = true
  C_Timer.After(GROUP_ASK_WAIT, function()
    askWaiting = false
    ns.Log.safe(FEATURE, function()
      if not inAnyGroup() then return end
      for name in pairs(groupMembers()) do
        if not arriving(name) then QuestList.want(name, GROUP_FRESH) end
      end
    end)
  end)
end

local function onGroupChanged()
  if groupWaiting then return end
  groupWaiting = true
  C_Timer.After(GROUP_SETTLE, function()
    groupWaiting = false
    ns.Log.safe(FEATURE, function()
      if not inAnyGroup() then
        told = {}
        return
      end
      for name in pairs(groupMembers()) do headsUp(name) end
      pushIfChanged()
      askGroupLater()
    end)
  end)
end

------------------------------------------------------------------------------------------------------ messages
local function onAsk(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  if f.t and not ns.wireIsMe(f.t) then return end -- a group message meant for someone else
  if ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end -- crew only
  local now = ns.now()
  if answeredAt[sender] and now - answeredAt[sender] < ANSWER_GAP then return end
  -- they were in my group when my list went to it a moment ago (it may still wait in the queue): they have it
  local g = groupSent
  if g and g.members[sender] and now - g.at < GROUP_COPY and now >= g.at and g.sig == signature(myLog())
    and inAnyGroup() and inMyGroup(sender) then
    return
  end
  answeredAt[sender] = now
  sendMine(sender)
end

local function onAnswer(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  if ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end
  local s, n = f.s, tonumber(f.n)
  if type(s) ~= "string" or s == "" or #s > 16 or not n or n < 0 or n > MAX_QUESTS then return end
  local now = ns.now()
  local b = building[sender]
  if not b then b = {}; building[sender] = b end
  for stamp, cur in pairs(b) do
    if now - cur.at > BUILD_AGE or now < cur.at then b[stamp] = nil end
  end
  local cur = b[s]
  if not cur then cur = { at = now, n = n, count = 0, quests = {} }; b[s] = cur end
  for k, v in pairs(f) do
    local id = type(k) == "string" and tonumber(k:match("^q(%d+)$"))
    if id and type(v) == "string" and #v >= 2 and not cur.quests[id] and cur.count < MAX_QUESTS then
      local flag = v:sub(1, 1)
      local shareable = nil
      if flag == "1" then shareable = true elseif flag == "0" then shareable = false end
      cur.quests[id] = { id = id, title = ns.Util.truncateUTF8(v:sub(2), ns.Quest.TITLE_MAX), shareable = shareable }
      cur.count = cur.count + 1
    end
  end
  if cur.count < cur.n then return end -- more pieces to come
  b[s] = nil
  lists[sender] = { at = now, n = cur.count, quests = cur.quests }
  cache[sender] = nil
  headsUp(sender)
  redraw()
end

ns.Comm.on("QLQ", function(sender, fields) ns.Log.safe(FEATURE, onAsk, sender, fields) end)
ns.Comm.on("QLA", function(sender, fields) ns.Log.safe(FEATURE, onAnswer, sender, fields) end)

function QuestList.start()
  if QuestList.started then return end
  QuestList.started = true
  ns.Events.on(FEATURE, "GROUP_ROSTER_UPDATE", onGroupChanged)
  for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN" }) do
    ns.Events.on(FEATURE, e, pushIfChanged)
  end
end

-- Something about what I can get changed (the game refused a share, say): count again and redraw.
function QuestList.changed()
  cache = {}
  redraw()
end

-- Test hooks.
function QuestList.listForTest(name) return lists[name] end
