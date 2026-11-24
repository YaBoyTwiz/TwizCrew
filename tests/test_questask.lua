-- A friend's quests by zone in a window, ticks, and asking for several at once (UI/QuestWindow.lua,
-- Crew/QuestAsk.lua, the zone headings of Crew/QuestList.lua's list).

local function login(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function start(ns, W)
  login(W)
  W.env.TwizCrewDB.modules.panel.settings.showNoAddon = false
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

-- A fake modern quest log with heading rows: rows = { { header = "Elwynn Forest" } | { id, title } }.
local function questLog(W, rows)
  local QL = W.env.C_QuestLog
  rawset(QL, "GetNumQuestLogEntries", function() return #rows end)
  rawset(QL, "GetInfo", function(i)
    local r = rows[i]
    if not r then return nil end
    if r.header then return { title = r.header, isHeader = true } end
    return { title = r.title, questID = r.id, isHeader = false }
  end)
  rawset(QL, "GetQuestObjectives", function() return {} end)
  rawset(QL, "IsComplete", function() return false end)
  rawset(QL, "IsPushableQuest", function() return true end)
end

local function sentOf(ns, W, msgType, from)
  local out = {}
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then out[#out + 1] = msg.fields end
  end
  return out
end

local function textsOf(ns, W, msgType, from)
  local out = {}
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then out[#out + 1] = W.sent[i].text end
  end
  return out
end

-- A friend's list in format 2: heads = { "Westfall", ... }; quests = { { id, flag, title, heading number } }.
local function receiveList(ns, W, sender, stamp, heads, quests)
  local fields = { s = stamp, n = tostring(#quests), f = "2" }
  for i, h in ipairs(heads) do fields["h" .. i] = h end
  for _, q in ipairs(quests) do
    fields["q" .. q[1]] = q[2] .. q[3]
    fields["z" .. q[1]] = tostring(q[4])
  end
  for _, text in ipairs(ns.Codec.encode("QLA", fields, { repeatKeys = { "s", "n", "f" } })) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

-- A list as an older copy sends it (no f, no headings): quests = { { id, flag, title } }.
local function receiveOldList(ns, W, sender, stamp, quests)
  local fields = { s = stamp, n = tostring(#quests) }
  for _, q in ipairs(quests) do fields["q" .. q[1]] = q[2] .. q[3] end
  for _, text in ipairs(ns.Codec.encode("QLA", fields, { repeatKeys = { "s", "n" } })) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

-- What v0.4.1 and older make of a list (their reading of QLA, as it was): n, how many quests, id -> title.
local function oldRead(ns, texts)
  local n, count, quests = nil, 0, {}
  for _, text in ipairs(texts) do
    local f = ns.Codec.decode(text).fields
    n = tonumber(f.n)
    for k, v in pairs(f) do
      local id = type(k) == "string" and tonumber(k:match("^q(%d+)$"))
      if id and type(v) == "string" and #v >= 2 and not quests[id] then
        quests[id] = v:sub(2)
        count = count + 1
      end
    end
  end
  return n, count, quests
end

local function click(f) f._scripts.OnClick(f) end

local function popupWith(ns, text)
  for i, t in ipairs(ns.Popups.textsForTest()) do if t.text == text then return i, t end end
end

local function printedWith(W, text, from)
  local n = 0
  for i = (from or 0) + 1, #W.printed do if W.printed[i]:find(text, 1, true) then n = n + 1 end end
  return n
end

local function grouped(W, names)
  W.state.inGroup = true
  W.state.groupMembers = names
end

-- Frostie's list with three quests I can get in Elwynn Forest (my zone) and one in Westfall.
local ELWYNN = { "Elwynn Forest", "Westfall" }
local FOUR = { { 42, "1", "Kobolds", 1 }, { 43, "1", "Wolves", 1 }, { 44, "1", "Murlocs", 1 },
  { 50, "1", "Defias", 2 } }

return {
  files = "toc",
  tests = {
    ------------------------------------------------------------------------------------------------- the list
    my_list_carries_its_zone_headings_and_older_copies_still_read_it = function(ns, A, W)
      local rows = {}
      local zones = { "Elwynn Forest", "Westfall", "Redridge Mountains", "Duskwood", "The Barrens" }
      for z, zone in ipairs(zones) do
        rows[#rows + 1] = { header = zone }
        for i = 1, 6 do
          rows[#rows + 1] = { id = 1000 + z * 10 + i, title = "A long quest name " .. z .. "-" .. i .. " in " .. zone }
        end
      end
      questLog(W, rows)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(2)
      local before = #W.sent
      receive(ns, W, "Frostie", "QLQ", { t = "Twiz" })
      W:advance(30)
      local texts = textsOf(ns, W, "QLA", before)
      A.ok(#texts > 1, "a full log takes several messages")
      local f = {}
      for _, text in ipairs(texts) do
        local fields = ns.Codec.decode(text).fields
        A.eq(fields.f, "2", "every piece says the format")
        for k, v in pairs(fields) do f[k] = v end
      end
      A.eq(f.n, "30")
      A.eq(f.h1, "Elwynn Forest"); A.eq(f.h2, "Westfall"); A.eq(f.h5, "The Barrens"); A.eq(f.h6, nil)
      A.eq(f.z1011, "1"); A.eq(f.z1026, "2"); A.eq(f.z1056, "5")
      A.eq(f.q1011, "1A long quest name 1-1 in Elwynn Forest", "q<id> means what it always meant")
      -- an older copy reads the same list: every quest, the names whole, the new fields skipped
      local n, count, quests = oldRead(ns, texts)
      A.eq(n, 30); A.eq(count, 30)
      A.eq(quests[1056], "A long quest name 5-6 in The Barrens")
      for id, title in pairs(quests) do A.ok(title:find("^A long quest name"), "a whole name for " .. id) end
      -- a quest under no heading has number 0
      questLog(W, { { id = 7, title = "Loose" }, { header = "Westfall" }, { id = 8, title = "Defias" } })
      W:advance(11)
      before = #W.sent
      receive(ns, W, "Frostie", "QLQ", { t = "Twiz" })
      W:advance(5)
      local got = sentOf(ns, W, "QLA", before)
      A.eq(got[1].z7, "0"); A.eq(got[1].z8, "1"); A.eq(got[1].h1, "Westfall")
      A.eq(ns.Log.errors(10), {})
    end,
    a_list_waits_for_its_headings_whatever_order_the_pieces_come_in = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      local QL = ns.QuestList
      local function send(fields)
        for _, text in ipairs(ns.Codec.encode("QLA", fields, { repeatKeys = { "s", "n", "f" } })) do
          W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", "Frostie")
        end
      end
      -- every quest is here, the heading numbers are not yet
      send({ s = "7x1", n = "2", f = "2", h1 = "Westfall", q42 = "1Kobolds", q50 = "1Defias" })
      A.no(QL.known("Frostie"), "not whole without the heading numbers")
      send({ s = "7x1", n = "2", f = "2", z42 = "2", z50 = "1" })
      A.no(QL.known("Frostie"), "heading 2 has no name yet")
      send({ s = "7x1", n = "2", f = "2", h2 = "Elwynn Forest" })
      A.ok(QL.known("Frostie"))
      A.eq(QL.format("Frostie"), 2)
      -- the other way round: numbers and names first, the quests last
      W:advance(11)
      send({ s = "8x1", n = "1", f = "2", z60 = "1", h1 = "Duskwood" })
      A.eq(QL.listForTest("Frostie").n, 2, "still the last whole list")
      send({ s = "8x1", n = "1", f = "2", q60 = "1Night Web" })
      A.eq(QL.listForTest("Frostie").n, 1)
      A.eq(QL.groups("Frostie").groups[1].title, "Duskwood")
      -- an older copy's list: format 1, no headings
      W:advance(11)
      receiveOldList(ns, W, "Frostie", "9x1", { { 70, "1", "Old Style" } })
      A.eq(QL.format("Frostie"), 1)
      A.eq(QL.groups("Frostie").headed, false)
      A.eq(ns.Log.errors(10), {})
    end,
    their_quests_come_by_zone_and_mine_first = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      W.state.zone = "Elwynn Forest"
      receiveList(ns, W, "Frostie", "1x1", { "Westfall", "Elwynn Forest", "Redridge Mountains" }, {
        { 1, "1", "Defias", 1 }, { 2, "1", "Kobolds", 2 }, { 3, "1", "Wolves", 2 }, { 4, "0", "Bound", 2 },
        { 5, "1", "Murlocs", 3 }, { 6, "1", "Lost", 0 } })
      ns.QuestList.open("Frostie")
      A.ok(ns.QuestWindow.isShown())
      A.eq(ns.QuestWindow.linesForTest(), {
        "# Elwynn Forest (you are here) [Tick this zone]", "[ ] Kobolds", "[ ] Wolves",
        "- Can't share: Bound (it can't be shared)",
        "# Westfall [Tick this zone]", "[ ] Defias",
        "# Redridge Mountains [Tick this zone]", "[ ] Murlocs",
        "# Other quests [Tick this zone]", "[ ] Lost",
      }, "my zone first, then their order, quests under no heading last")
      -- somewhere none of their headings is: their order
      W.state.zone = "Duskwood"
      ns.QuestList.changed()
      local lines = ns.QuestWindow.linesForTest()
      A.eq(lines[1], "# Westfall [Tick this zone]")
      A.eq(lines[3], "# Elwynn Forest [Tick this zone]")
      A.eq(lines[#lines - 1], "# Other quests [Tick this zone]")
      A.eq(ns.QuestWindow.statusForTest(), "Sharing only works in a group.")
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------------ the window
    ticks_tick_this_zone_and_only_this_zone = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      receiveList(ns, W, "Frostie", "1x1", ELWYNN, {
        { 42, "1", "Kobolds", 1 }, { 43, "1", "Wolves", 1 }, { 45, "0", "Bound", 1 }, { 50, "1", "Defias", 2 } })
      ns.QuestList.open("Frostie")
      local QW = ns.QuestWindow
      A.eq({ QW.buttonForTest() }, { "Ask for quests", false }, "nothing ticked: the button can't be clicked")
      A.ok(QW.onlyBoxForTest():IsShown(), "their list has headings: Only this zone")
      -- the check box on a row
      local row = QW.rowForTest(2)
      A.eq(row.tcEntry.text, "Kobolds")
      A.ok(row.check:IsShown())
      click(row.check)
      A.eq(QW.linesForTest()[2], "[x] Kobolds")
      A.eq({ QW.buttonForTest() }, { "Ask for 1 quest", true })
      A.no(QW.rowForTest(4).check:IsShown(), "no box on a quest I can't get")
      A.no(QW.toggle(45), "and it can't be ticked")
      -- Tick this zone, then Untick this zone
      click(QW.rowForTest(1).zone)
      A.eq(QW.linesForTest(), { "# Elwynn Forest (you are here) [Untick this zone]", "[x] Kobolds", "[x] Wolves",
        "- Can't share: Bound (it can't be shared)", "# Westfall [Tick this zone]", "[ ] Defias" })
      A.eq({ QW.buttonForTest() }, { "Ask for 2 quests", true })
      click(QW.rowForTest(1).zone)
      A.eq(QW.linesForTest()[2], "[ ] Kobolds"); A.eq(QW.linesForTest()[3], "[ ] Wolves")
      -- a click on the line itself ticks it too
      QW.rowForTest(6)._scripts.OnMouseUp(QW.rowForTest(6))
      A.eq(QW.linesForTest()[6], "[x] Defias")
      -- Only this zone: Westfall hides, its tick still counts
      click(QW.onlyBoxForTest())
      A.eq(QW.linesForTest(), { "# Elwynn Forest (you are here) [Tick this zone]", "[ ] Kobolds", "[ ] Wolves",
        "- Can't share: Bound (it can't be shared)" })
      A.eq({ QW.buttonForTest() }, { "Ask for 1 quest", true })
      -- in a zone where they have nothing
      W.state.zone = "Duskwood"
      ns.QuestList.changed()
      A.eq(QW.linesForTest(), { "Frostie has no quests in Duskwood." })
      click(QW.onlyBoxForTest())
      A.eq(#QW.linesForTest(), 6, "off again: every zone")
      -- someone else's quests: fresh ticks; an older copy's list: no headings, no switch
      receive(ns, W, "Holly", "STATE", { cl = "PRIEST" })
      receiveOldList(ns, W, "Holly", "2x1", { { 70, "1", "Old Style" } })
      ns.QuestList.open("Holly")
      A.eq(QW.linesForTest(), { "[ ] Old Style" })
      A.no(QW.onlyBoxForTest():IsShown())
      ns.QuestList.open("Frostie")
      A.eq({ QW.buttonForTest() }, { "Ask for quests", false }, "the ticks were for Frostie's other look")
      -- Escape closes it like the other windows
      local listed = false
      for _, n in ipairs(W.env.UISpecialFrames) do if n == "TwizCrewQuests" then listed = true end end
      A.ok(listed)
      QW.close()
      A.no(QW.isShown())
      -- no list from them yet
      receive(ns, W, "Lurabe", "STATE", { cl = "MAGE" })
      ns.QuestList.open("Lurabe")
      A.eq(QW.linesForTest(), { "No quest list from them yet (asked just now)", "They may have an older TwizCrew" })
      A.eq(ns.Log.errors(10), {})
    end,
    a_long_list_scrolls_and_one_ask_holds_25 = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      local quests = {}
      for i = 1, 30 do quests[i] = { 9999900 + i, "1", string.format("Quest %02d", i), math.floor((i - 1) / 10) + 1 } end
      receiveList(ns, W, "Frostie", "1x1", { "Elwynn Forest", "Westfall", "Duskwood" }, quests)
      ns.QuestList.open("Frostie")
      local QW = ns.QuestWindow
      A.eq(#QW.linesForTest(), 33)
      A.eq(QW.hintForTest(), "Scroll for more (1-14 of 33)")
      QW.scroll(-1)
      A.eq(QW.hintForTest(), "Scroll for more (2-15 of 33)")
      A.eq(QW.rowForTest(1).tcEntry.text, "Quest 01")
      QW.scroll(-100)
      A.eq(QW.hintForTest(), "Scroll for more (20-33 of 33)")
      QW.scroll(100)
      -- three zones ticked: the third stops at 25 and says why
      local before = #W.printed
      for _, e in ipairs(QW.entries()) do if e.kind == "head" then QW.tickZone(e.group) end end
      A.eq({ QW.buttonForTest() }, { "Ask for 25 quests", true })
      A.eq(printedWith(W, "you can ask for up to 25 quests at once", before) > 0, true)
      -- 25 long quest IDs still go in one whole message
      grouped(W, { "Frostie" })
      local sent = #W.sent
      QW.press()
      W:advance(2)
      local ask = sentOf(ns, W, "QMR", sent)
      A.eq(#ask, 1)
      A.eq(#ns.QuestAsk.parseIds(ask[1].q), 25)
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------------- asking
    asking_a_friend_for_several_quests = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Holly", "STATE", { cl = "PRIEST" })
      W:advance(1)
      receiveList(ns, W, "Frostie", "1x1", ELWYNN, FOUR)
      ns.QuestList.open("Frostie")
      local QW = ns.QuestWindow
      QW.tickZone(QW.entries()[1].group)
      -- not in a group: the usual words, nothing sent, the ticks stay
      local before = #W.sent
      QW.press()
      W:advance(2)
      A.contains(W.printed[#W.printed], "quest sharing only works in a group. Invite Frostie first.")
      A.eq(#sentOf(ns, W, "QMR", before), 0)
      A.eq({ QW.buttonForTest() }, { "Ask for 3 quests", true })
      grouped(W, { "Frostie", "Holly" })
      before = #W.sent
      QW.press()
      W:advance(2)
      local ask = sentOf(ns, W, "QMR", before)
      A.eq(#ask, 1, "one message for all three")
      A.eq(ask[1].t, "Frostie"); A.eq(ask[1].q, "42,44,43", "in the window's order (Kobolds, Murlocs, Wolves)")
      local key = ask[1].k
      A.ok(type(key) == "string" and key ~= "")
      A.contains(W.printed[#W.printed], "TwizCrew: asked Frostie for 3 quests.")
      A.eq({ QW.buttonForTest() }, { "Stop asking", true })
      A.eq(QW.statusForTest(), "Asked for 3 quests. Waiting for Frostie to say yes.")
      A.eq(QW.linesForTest()[2], "[ ] Kobolds", "the ticks went with the ask")
      -- news about someone else's ask, or from someone else, changes nothing
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = "other", st = "yes" })
      receive(ns, W, "Holly", "QMS", { t = "Twiz", k = key, st = "yes" })
      receive(ns, W, "Frostie", "QMS", { t = "Holly", k = key, st = "yes" })
      A.eq(QW.statusForTest(), "Asked for 3 quests. Waiting for Frostie to say yes.")
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "yes" })
      A.eq(QW.statusForTest(), "Frostie said yes: got 0 of 3 so far.")
      -- I take one: their copy hears it, so the next can come
      before = #W.sent
      W:fire("QUEST_ACCEPTED", 42)
      W:advance(2)
      local news = sentOf(ns, W, "QMU", before)
      A.eq(#news, 1); A.eq(news[1].i, "42"); A.eq(news[1].k, key); A.eq(news[1].t, "Frostie")
      A.eq(QW.statusForTest(), "Frostie said yes: got 1 of 3 so far.")
      -- one is refused: the usual line
      receive(ns, W, "Frostie", "QRES", { t = "Twiz", q = "Murlocs", i = "44", r = "inv" })
      A.contains(W.printed[#W.printed], "Frostie couldn't share \"Murlocs\": you can't take it yet")
      -- the last one taken: one line to end it
      local printed = #W.printed
      W:fire("QUEST_ACCEPTED", 43)
      W:advance(2)
      A.eq(printedWith(W, "TwizCrew: You got 2 of 3 quests from Frostie.", printed), 1)
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "end", r = "done", d = "2" })
      A.eq(printedWith(W, "You got", printed), 1, "their end after mine: no second line")
      A.eq(#W.printed - printed, 1, "the whole share: no more chat than that")
      A.eq(QW.statusForTest(), "You got 2 of 3 quests from Frostie.")
      A.eq({ QW.buttonForTest() }, { "Ask for quests", false })
      A.eq(ns.Log.errors(10), {})
    end,
    an_ask_can_end_in_many_ways = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      receiveList(ns, W, "Frostie", "1x1", ELWYNN, FOUR)
      grouped(W, { "Frostie" })
      ns.QuestList.open("Frostie")
      local QW = ns.QuestWindow
      local function ask()
        if QW.linesForTest()[2] == "[ ] Kobolds" then QW.toggle(42) end
        local before = #W.sent
        QW.press()
        W:advance(1)
        local got = sentOf(ns, W, "QMR", before)
        return got[1] and got[1].k
      end
      -- no answer
      A.ok(ask())
      W:advance(31)
      A.contains(W.printed[#W.printed], "TwizCrew: No answer from Frostie.")
      -- busy
      W:advance(2)
      local key = ask()
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "busy" })
      A.contains(W.printed[#W.printed], "Frostie is sharing quests with someone else. Ask again in a moment.")
      -- asked again too soon
      QW.toggle(42)
      local before = #W.sent
      QW.press()
      A.contains(W.printed[#W.printed], "you just asked Frostie. Give them a moment.")
      A.eq(#sentOf(ns, W, "QMR", before), 0)
      -- I stop asking
      W:advance(16)
      key = ask()
      before = #W.sent
      QW.press()
      W:advance(1)
      local stop = sentOf(ns, W, "QMU", before)
      A.eq(stop[1].x, "1"); A.eq(stop[1].k, key)
      A.contains(W.printed[#W.printed], "Stopped asking Frostie (you got 0 of 1).")
      -- the group breaks
      W:advance(16)
      key = ask()
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "yes" })
      W.state.inGroup = false
      W:fire("GROUP_ROSTER_UPDATE")
      A.contains(W.printed[#W.printed], "Frostie stopped sharing (the group broke up). You got 0 of 1 quests.")
      -- their copy stops for want of a click
      grouped(W, { "Frostie" })
      W:advance(16)
      key = ask()
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "next", d = "0" })
      A.eq(QW.statusForTest(), "Frostie clicks for each one: got 0 of 1 so far.")
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "end", r = "noclick", d = "0" })
      A.contains(W.printed[#W.printed], "Frostie stopped sharing (no click for the next one).")
      -- their copy goes quiet
      W:advance(16)
      key = ask()
      receive(ns, W, "Frostie", "QMS", { t = "Twiz", k = key, st = "yes" })
      W:advance(122)
      A.contains(W.printed[#W.printed], "Frostie stopped sharing (their copy stopped answering).")
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------------ sharing
    a_friend_asks_for_several_and_one_click_shares_them_one_at_a_time = function(ns, A, W)
      questLog(W, { { header = "Elwynn Forest" }, { id = 42, title = "Kobolds" }, { id = 43, title = "Wolves" },
        { id = 44, title = "Murlocs" } })
      local pushed, selected = {}, nil
      rawset(W.env.C_QuestLog, "SetSelectedQuest", function(id) selected = id end)
      W.env.QuestLogPushQuest = function() pushed[#pushed + 1] = selected end
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Holly", "STATE", { cl = "PRIEST" })
      grouped(W, { "Frostie", "Holly" })
      W:advance(2)
      -- not from a stranger, not meant for someone else, not a broken or too long list
      receive(ns, W, "Ginkan", "QMR", { t = "Twiz", k = "1x1", q = "42" })
      receive(ns, W, "Frostie", "QMR", { t = "Holly", k = "1x1", q = "42" })
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "1x1", q = "42,x" })
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", q = "42" })
      local many = {}
      for i = 1, 26 do many[i] = tostring(100 + i) end
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "1x1", q = table.concat(many, ",") })
      A.eq(#ns.Popups.textsForTest(), 0)
      -- an ask: one pop-up, for the quests really in my log
      local before = #W.sent
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "5x1", q = "42,43,99,44" })
      local i, t = popupWith(ns, "Frostie asks for 3 quests")
      A.ok(i, "the pop-up")
      A.eq(t.subtext, "Click to share them, one at a time")
      A.eq(#pushed, 0, "nothing before the click")
      ns.Popups.clickForTest(i)
      A.eq(pushed, { 42 }, "the click shares the first")
      W:advance(2)
      local news = sentOf(ns, W, "QMS", before)
      A.eq(news[1].st, "yes"); A.eq(news[1].k, "5x1"); A.eq(news[1].t, "Frostie")
      -- they took it (their copy says so): the next one goes out by itself, a moment later
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "other", i = "42" })
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "5x1", i = "42" })
      W:advance(2)
      A.eq(pushed, { 42, 43 })
      -- they decline it: the game tells me, their copy hears why, and the next one goes out
      before = #W.sent
      W:fire("CHAT_MSG_SYSTEM", "Frostie has declined your quest.")
      W:advance(2)
      local res = sentOf(ns, W, "QRES", before)
      A.eq(#res, 1); A.eq(res[1].r, "decl"); A.eq(res[1].i, "43"); A.eq(res[1].t, "Frostie")
      A.eq(pushed, { 42, 43, 44 })
      -- no answer to the last one: it is over after a while
      W:advance(47)
      res = sentOf(ns, W, "QRES", before)
      A.eq(res[#res].r, "time"); A.eq(res[#res].i, "44")
      news = sentOf(ns, W, "QMS", before)
      A.eq(news[#news].st, "end"); A.eq(news[#news].r, "done"); A.eq(news[#news].d, "1")
      A.contains(W.printed[#W.printed], "TwizCrew: done sharing with Frostie (1 of 3 taken).")
      A.eq(ns.QuestAsk.jobForTest(), nil)
      A.eq(pushed, { 42, 43, 44 })
      A.eq(ns.Log.errors(10), {})
    end,
    sharing_stops_when_it_should = function(ns, A, W)
      questLog(W, { { header = "Elwynn Forest" }, { id = 42, title = "Kobolds" }, { id = 43, title = "Wolves" } })
      local pushed = 0
      W.env.QuestLogPushQuest = function() pushed = pushed + 1 end
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Holly", "STATE", { cl = "PRIEST" })
      grouped(W, { "Frostie", "Holly" })
      W:advance(2)
      -- not in my group: not heard
      receive(ns, W, "Lurabe", "STATE", { cl = "MAGE" })
      receive(ns, W, "Lurabe", "QMR", { t = "Twiz", k = "1x1", q = "42" })
      A.eq(#ns.Popups.textsForTest(), 0, "Lurabe is not in my group")
      -- Holly asks while Frostie's ask waits: busy
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "6x1", q = "42,43" })
      local before = #W.sent
      receive(ns, W, "Holly", "QMR", { t = "Twiz", k = "7x1", q = "42" })
      W:advance(2)
      local news = sentOf(ns, W, "QMS", before)
      A.eq(#news, 1); A.eq(news[1].t, "Holly"); A.eq(news[1].st, "busy")
      -- a second ask from Frostie within 15 s is not heard
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "6x2", q = "42" })
      A.eq(ns.QuestAsk.jobForTest().key, "6x1")
      -- Frostie's pop-up gets no click: "no", once
      before = #W.sent
      W:advance(22)
      news = sentOf(ns, W, "QMS", before)
      A.eq(#news, 1); A.eq(news[1].st, "no")
      A.eq(pushed, 0)
      -- the group breaks in the middle
      W:advance(16)
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "8x1", q = "42,43" })
      ns.Popups.clickForTest(popupWith(ns, "Frostie asks for 2 quests"))
      A.eq(pushed, 1)
      before = #W.sent
      W.state.groupMembers = { "Holly" }
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(2)
      news = sentOf(ns, W, "QMS", before)
      A.eq(news[#news].st, "end"); A.eq(news[#news].r, "group")
      A.contains(W.printed[#W.printed], "stopped sharing with Frostie (the group broke up).")
      W:advance(50)
      A.eq(pushed, 1, "nothing more")
      -- the asker stops
      grouped(W, { "Frostie", "Holly" })
      W:advance(16)
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "9x1", q = "42,43" })
      ns.Popups.clickForTest(popupWith(ns, "Frostie asks for 2 quests"))
      A.eq(pushed, 2)
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "9x1", x = "1" })
      A.eq(ns.QuestAsk.jobForTest(), nil)
      W:advance(50)
      A.eq(pushed, 2, "nothing more")
      -- the asker goes offline
      W:advance(16)
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "10x1", q = "42,43" })
      ns.Popups.clickForTest(popupWith(ns, "Frostie asks for 2 quests"))
      receive(ns, W, "Frostie", "BYE", {})
      W:advance(3)
      A.eq(ns.QuestAsk.jobForTest(), nil)
      -- quests I don't have: nothing to share, and they hear so
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(16)
      before = #W.sent
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "11x1", q = "99" })
      W:advance(2)
      news = sentOf(ns, W, "QMS", before)
      A.eq(news[1].st, "end"); A.eq(news[1].r, "none")
      A.eq(popupWith(ns, "Frostie asks for 1 quest"), nil)
      -- Share my quests off: nobody can ask
      ns.Modules.set("panel", "shareQuest", false)
      W:advance(16)
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "12x1", q = "42" })
      A.eq(ns.QuestAsk.jobForTest(), nil)
      A.eq(ns.Log.errors(10), {})
    end,
    the_game_may_want_a_click_for_each_share = function(ns, A, W)
      questLog(W, { { header = "Elwynn Forest" }, { id = 42, title = "Kobolds" }, { id = 43, title = "Wolves" },
        { id = 44, title = "Murlocs" } })
      local pushed, selected, block = {}, nil, false
      rawset(W.env.C_QuestLog, "SetSelectedQuest", function(id) selected = id end)
      W.env.QuestLogPushQuest = function()
        pushed[#pushed + 1] = selected
        if block then W:fire("ADDON_ACTION_BLOCKED", "TwizCrew", "QuestLogPushQuest()") end
      end
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      grouped(W, { "Frostie" })
      W:advance(2)
      -- the switch off: a pop-up for each next one
      ns.QuestAsk.AUTO_NEXT = false
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "1x1", q = "42,43" })
      ns.Popups.clickForTest(popupWith(ns, "Frostie asks for 2 quests"))
      A.eq(pushed, { 42 })
      local before = #W.sent
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "1x1", i = "42" })
      W:advance(3)
      A.eq(pushed, { 42 }, "waits for the click")
      local i, t = popupWith(ns, "Share next quest (2 of 2)")
      A.ok(i)
      A.eq(t.subtext, "Wolves for Frostie  -  click to share it")
      local news = sentOf(ns, W, "QMS", before)
      A.eq(news[#news].st, "next")
      ns.Popups.clickForTest(i)
      A.eq(pushed, { 42, 43 })
      -- the switch on, but the game blocks a share made by itself: that one comes back as a click, and the rest too
      ns.QuestAsk.AUTO_NEXT = true
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "1x1", i = "43" })
      W:advance(16)
      receive(ns, W, "Frostie", "QMR", { t = "Twiz", k = "2x1", q = "42,43,44" })
      ns.Popups.clickForTest(popupWith(ns, "Frostie asks for 3 quests"))
      A.eq(pushed[#pushed], 42)
      block = true
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "2x1", i = "42" })
      W:advance(2)
      block = false
      A.eq(pushed[#pushed], 43, "it tried by itself")
      A.ok(ns.QuestAsk.clickModeForTest(), "clicks from now on")
      i = popupWith(ns, "Share next quest (2 of 3)")
      A.ok(i, "the blocked one, offered again with a click")
      local count = #pushed
      ns.Popups.clickForTest(i)
      A.eq(#pushed, count + 1); A.eq(pushed[#pushed], 43)
      receive(ns, W, "Frostie", "QMU", { t = "Twiz", k = "2x1", i = "43" })
      W:advance(3)
      A.eq(#pushed, count + 1, "the next one waits for a click too")
      A.ok(popupWith(ns, "Share next quest (3 of 3)"))
      A.eq(ns.Log.errors(10), {})
    end,
    ------------------------------------------------------------------------------------------- older copies
    an_older_copy_is_asked_one_quest_at_a_time = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(1)
      receiveOldList(ns, W, "Frostie", "1x1", { { 42, "1", "Kobolds" }, { 43, "1", "Wolves" }, { 44, "1", "Murlocs" } })
      grouped(W, { "Frostie" })
      ns.QuestList.open("Frostie")
      local QW = ns.QuestWindow
      for _, id in ipairs({ 42, 43, 44 }) do QW.toggle(id) end
      local before = #W.sent
      QW.press()
      W:advance(1)
      A.eq(printedWith(W, "Frostie has an older TwizCrew, so you ask for one quest at a time"), 1)
      A.eq(#sentOf(ns, W, "QMR", before), 0, "their copy would drop the new ask")
      local req = sentOf(ns, W, "QREQ", before)
      A.eq(#req, 1); A.eq(req[1].q, "Kobolds")
      A.eq(QW.statusForTest(), "Asking one at a time (older TwizCrew): got 0 of 3 so far.")
      -- I take it at once: the next ask still waits, their copy drops a second ask within 15 s
      W:fire("QUEST_ACCEPTED", 42)
      W:advance(10)
      A.eq(#sentOf(ns, W, "QREQ", before), 1)
      W:advance(6)
      req = sentOf(ns, W, "QREQ", before)
      A.eq(#req, 2); A.eq(req[2].q, "Murlocs")
      -- refused: the next, again not sooner than 16 s after the last ask
      receive(ns, W, "Frostie", "QRES", { t = "Twiz", q = "Murlocs", i = "44", r = "inv" })
      W:advance(13)
      A.eq(#sentOf(ns, W, "QREQ", before), 2)
      W:advance(4)
      req = sentOf(ns, W, "QREQ", before)
      A.eq(#req, 3); A.eq(req[3].q, "Wolves")
      -- no answer to the last one
      W:advance(47)
      A.contains(W.printed[#W.printed], "TwizCrew: You got 1 of 3 quests from Frostie.")
      A.eq(#sentOf(ns, W, "QREQ", before), 3)
      A.eq(ns.Log.errors(10), {})
    end,
    -------------------------------------------------------------------------------------------- end to end
    two_copies_share_several_quests_end_to_end = function(_, A, _, H)
      local tw, twNs = H.client("Twiz")
      local fr, frNs = H.client("Frostie", { class = "MAGE" })
      H.link(tw, fr)
      questLog(fr, { { header = "Elwynn Forest" }, { id = 42, title = "Kobolds" }, { id = 43, title = "Wolves" },
        { header = "Westfall" }, { id = 50, title = "Defias" } })
      local selected, offered = nil, {}
      rawset(fr.env.C_QuestLog, "SetSelectedQuest", function(id) selected = id end)
      -- Frostie's game offers the quest to the group; Twiz takes it at once
      fr.env.QuestLogPushQuest = function()
        offered[#offered + 1] = selected
        tw:fire("QUEST_ACCEPTED", selected)
      end
      login(tw); login(fr)
      grouped(tw, { "Frostie" }); grouped(fr, { "Twiz" })
      H.advance(40)
      twNs.QuestList.open("Frostie")
      H.advance(5)
      local QW = twNs.QuestWindow
      A.eq(QW.linesForTest(), { "# Elwynn Forest (you are here) [Tick this zone]", "[ ] Kobolds", "[ ] Wolves",
        "# Westfall [Tick this zone]", "[ ] Defias" })
      click(QW.rowForTest(1).zone)
      QW.press()
      H.advance(3)
      local i = popupWith(frNs, "Twiz asks for 2 quests")
      A.ok(i, "Frostie's pop-up")
      frNs.Popups.clickForTest(i)
      H.advance(6)
      A.eq(offered, { 42, 43 }, "one click, both quests, one after the other")
      A.eq(printedWith(tw, "TwizCrew: You got 2 of 2 quests from Frostie."), 1)
      A.eq(printedWith(fr, "TwizCrew: done sharing with Twiz (2 of 2 taken)."), 1)
      A.eq(twNs.Log.errors(50), {}); A.eq(frNs.Log.errors(50), {})
    end,
  },
}
