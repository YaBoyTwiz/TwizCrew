-- A friend's whole quest log, so you can see every quest they could share with you (not only the one they're on).
-- QLQ = "send me your quest list" (t = who should answer); QLA = the list: s (a stamp, the same in every piece),
-- n (how many quests), and one "q<questID>" = "<1 can be shared | 0 can't | ? unknown><title>" per quest.
-- Since 2026-11-23 (list format 2) the list also has: f = "2" (in every piece; this copy also takes an ask for
-- several quests, Crew/QuestAsk.lua), "h<n>" = the name of the n-th heading of the sender's quest log (the zone),
-- and "z<questID>" = the number of the heading the quest is under (0: none). Older copies read only s, n and q<id>
-- and skip the new fields; a list from them has no f, and shows as one list without headings.
-- Asked when you hover or right-click a friend, and for crew members who are in your group. A copy in a group also
-- sends its list to the group again when its quests change. Copies without this (v0.2.0 and older) drop both
-- message types, so for them only the one quest on their row is known, as before.
-- The heads-up: when a group member's list shows quests you can get, one pop-up says so (once per grouping).
-- Clicking "Their quests" (or the heads-up) opens their quests in a window (UI/QuestWindow.lua).
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
local FORMAT = 2         -- the list format this copy sends (f): zone headings, and it takes an ask for several quests
local ICON_ASK = "Interface\\Icons\\Spell_ChargePositive"
local ICON_LIST = "Interface\\Icons\\INV_Misc_Book_08"

-- friend -> { at, n, format, quests = { [id] = { id, title, shareable, heading, hi } } } (the last whole list;
-- heading: the name of the heading it is under, hi: that heading's place in their log, 0 for none)
local lists = {}
local building = {}   -- friend -> { [stamp] = { at, n, count, quests, format, heads, zones } } (lists still arriving)
local askedAt, answeredAt = {}, {}
local told = {}       -- friend -> true: the heads-up for them was shown in this grouping
local cache = {}      -- friend -> { at, all }
local sentSig         -- my quests as they were when I last sent my list
local sends = 0
local pushWaiting, groupWaiting, askWaiting = false, false, false
local groupSent       -- { at, sig, members = { [name] = true } }: my last list sent to the group

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
QuestList.inAnyGroup, QuestList.inMyGroup = inAnyGroup, inMyGroup

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
  local fields = { s = (math.floor(ns.now()) % 100000) .. "x" .. sends, n = tostring(#log), f = tostring(FORMAT) }
  local heads, count = {}, 0 -- heading name -> its number, in the order of my log
  for _, q in ipairs(log) do
    fields["q" .. q.id] = (q.shareable == true and "1" or q.shareable == false and "0" or "?") .. q.title
    local h = 0
    if type(q.heading) == "string" and q.heading ~= "" then
      h = heads[q.heading]
      if not h then
        count = count + 1
        h, heads[q.heading] = count, count
        fields["h" .. h] = q.heading
      end
    end
    fields["z" .. q.id] = tostring(h)
  end
  local opts = { repeatKeys = { "s", "n", "f" }, bulk = true }
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

-- Their list's format: 2 = it came with zone headings and their copy takes an ask for several quests
-- (Crew/QuestAsk.lua); 1 = an older copy; nil = no list.
function QuestList.format(name)
  local l = lists[name]
  return l and (l.format or 1) or nil
end

-- Every quest of theirs with what it means for me, the ones I can get first:
-- { id, title, can (true: worth asking), status ("ok", "have", "done", "unshareable", "no", "unknown"), words,
-- heading (the heading it is under in their log, or nil), hi (that heading's place in their log, 0 for none) }.
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
    all[#all + 1] = { id = q.id, title = q.title, can = can, status = status, words = words, heading = q.heading,
      hi = q.hi or 0 }
  end
  table.sort(all, function(a, b)
    if a.can ~= b.can then return a.can end
    if a.title ~= b.title then return a.title < b.title end
    return a.id < b.id
  end)
  cache[name] = { at = now, all = all }
  return all
end

-- Why I can't get one of their quests (an entry of QuestList.all), in the words the lists use.
function QuestList.why(q)
  return q.words or (q.status == "unknown" and "can't tell if it can be shared") or "you can't get it"
end

-- How many of their quests I can get (0 when we don't have their list).
function QuestList.count(name)
  local n = 0
  for _, q in ipairs(QuestList.all(name)) do if q.can then n = n + 1 end end
  return n
end

-- The zone I'm in, as the game names it in a few ways: { [lower-case name] = true }, and the name to show (or nil).
local function myZones()
  local set, shown = {}, nil
  for _, fn in ipairs({ "GetZoneText", "GetRealZoneText" }) do
    local z = call(_G[fn])
    if type(z) == "string" and z ~= "" then
      set[z:lower()] = true
      shown = shown or z
    end
  end
  return set, shown
end

-- Their quests under the headings of their quest log, the zone I'm in first (else in the order of their log):
-- { headed = true when their copy sent headings, zone = the name of my zone (or nil), groups = { { title (nil in a
-- list without headings), here = true for my zone, quests = { entries of QuestList.all } } } }. A list without
-- headings (an older copy) is one group. Quests under no heading come last, as "Other quests".
function QuestList.groups(name)
  local all = QuestList.all(name)
  local zones, shown = myZones()
  local l = lists[name]
  local headed = false
  if l and (l.format or 1) >= 2 then
    for _, q in ipairs(all) do if q.heading then headed = true end end
  end
  if not headed then return { headed = false, zone = shown, groups = { { quests = all } } } end
  local byPlace, places = {}, {}
  for _, q in ipairs(all) do
    local place = q.heading and q.hi or 0
    local g = byPlace[place]
    if not g then
      g = { title = q.heading or "Other quests", quests = {}, place = place }
      g.here = q.heading ~= nil and zones[q.heading:lower()] == true
      byPlace[place] = g
      places[#places + 1] = place
    end
    g.quests[#g.quests + 1] = q
  end
  table.sort(places, function(a, b)
    local ga, gb = byPlace[a], byPlace[b]
    if ga.here ~= gb.here then return ga.here end
    if (a == 0) ~= (b == 0) then return b == 0 end
    return a < b
  end)
  local groups = {}
  for i, place in ipairs(places) do groups[i] = byPlace[place] end
  return { headed = true, zone = shown, groups = groups }
end

-- The row menu's entry for a friend: "Their quests (4 you can get)". nil for someone we can't ask.
function QuestList.rowItem(name)
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
  return { label = label, icon = ICON_LIST, onClick = function() QuestList.open(name) end }
end

-- Opens the window of their quests (UI/QuestWindow.lua), asking for their list when ours is old.
function QuestList.open(name)
  if type(name) ~= "string" or name == "" then return false end
  QuestList.want(name)
  if ns.QuestWindow and ns.QuestWindow.open then return ns.QuestWindow.open(name) end
  return false
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

-- Is this list whole? All n quests, and for a list with headings (format 2) every quest's heading number and every
-- heading name those numbers point at (their pieces may come in any order).
local function whole(cur)
  if cur.count < cur.n then return false end
  if cur.format < 2 then return true end
  for id in pairs(cur.quests) do
    local z = cur.zones[id]
    if z == nil or (z > 0 and not cur.heads[z]) then return false end
  end
  return true
end

local function onAnswer(sender, f)
  if type(sender) ~= "string" or type(f) ~= "table" then return end
  if ns.isMe(sender) then return end
  if not (ns.roster and ns.roster:get(sender)) then return end
  local s, n = f.s, tonumber(f.n)
  if type(s) ~= "string" or s == "" or #s > 16 or not n or n < 0 or n > MAX_QUESTS then return end
  local format = tonumber(f.f) or 1
  format = format >= 2 and 2 or 1 -- a newer format reads as the newest this copy knows (its fields are kept)
  local now = ns.now()
  local b = building[sender]
  if not b then b = {}; building[sender] = b end
  for stamp, cur in pairs(b) do
    if now - cur.at > BUILD_AGE or now < cur.at then b[stamp] = nil end
  end
  local cur = b[s]
  if not cur then
    cur = { at = now, n = n, count = 0, quests = {}, format = format, heads = {}, zones = {}, zoneCount = 0 }
    b[s] = cur
  end
  for k, v in pairs(f) do
    if type(k) == "string" and type(v) == "string" then
      local id = tonumber(k:match("^q(%d+)$"))
      if id and #v >= 2 and not cur.quests[id] and cur.count < MAX_QUESTS then
        local flag = v:sub(1, 1)
        local shareable = nil
        if flag == "1" then shareable = true elseif flag == "0" then shareable = false end
        cur.quests[id] = { id = id, title = ns.Util.truncateUTF8(v:sub(2), ns.Quest.TITLE_MAX), shareable = shareable }
        cur.count = cur.count + 1
      end
      local h = tonumber(k:match("^h(%d+)$"))
      if h and h >= 1 and h <= MAX_QUESTS and v ~= "" then
        cur.heads[h] = ns.Util.truncateUTF8(v, ns.Quest.HEADING_MAX)
      end
      local zid = tonumber(k:match("^z(%d+)$"))
      local z = tonumber(v)
      if zid and z and z >= 0 and z <= MAX_QUESTS and z == math.floor(z) and cur.zones[zid] == nil
        and cur.zoneCount < MAX_QUESTS then
        cur.zones[zid] = z
        cur.zoneCount = cur.zoneCount + 1
      end
    end
  end
  if not whole(cur) then return end -- more pieces to come
  b[s] = nil
  for id, q in pairs(cur.quests) do
    local z = cur.format >= 2 and cur.zones[id] or 0
    q.hi = z
    q.heading = z > 0 and cur.heads[z] or nil
  end
  lists[sender] = { at = now, n = cur.count, quests = cur.quests, format = cur.format }
  cache[sender] = nil
  headsUp(sender)
  redraw()
  if ns.QuestWindow and ns.QuestWindow.refresh then ns.QuestWindow.refresh(sender) end
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
  if ns.QuestWindow and ns.QuestWindow.refresh then ns.QuestWindow.refresh() end
end

-- Test hooks.
function QuestList.listForTest(name) return lists[name] end
