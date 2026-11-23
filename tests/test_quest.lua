-- The quest you're on (Crew/Quest.lua), friends' quests on the panel and in the tooltip, and the row's right-click
-- menu (Panel.rowMenu).

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W.env.TwizCrewDB.modules.panel.settings.showNoAddon = false -- these tests are about friends who talk, not "no addon" rows
  W:fire("PLAYER_ENTERING_WORLD")
end

local function start(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender)
  end
end

-- A fake modern quest log: quests = { { id, title, objectives = { { text, finished } }, complete } }.
local function questLog(W, quests, watched)
  local QL = W.env.C_QuestLog
  rawset(QL, "GetNumQuestLogEntries", function() return #quests end)
  rawset(QL, "GetInfo", function(i)
    local q = quests[i]
    return q and { title = q.title, questID = q.id, isHeader = false } or nil
  end)
  rawset(QL, "GetQuestObjectives", function(id)
    for _, q in ipairs(quests) do if q.id == id then return q.objectives end end
  end)
  rawset(QL, "IsComplete", function(id)
    for _, q in ipairs(quests) do if q.id == id then return q.complete end end
  end)
  rawset(QL, "GetQuestIDForQuestWatchIndex", function(i) if i == 1 then return watched end end)
end

local function labels(items)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.label end
  return out
end

-- Every message of one type sent since `from` (an index into W.sent), decoded: a list of their fields.
local function sentOf(ns, W, msgType, from)
  local out = {}
  for i = (from or 0) + 1, #W.sent do
    local msg = ns.Codec.decode(W.sent[i].text)
    if msg and msg.type == msgType then out[#out + 1] = msg.fields end
  end
  return out
end

-- A friend's quest list arrives (in as many pieces as it takes).
local function receiveList(ns, W, sender, stamp, quests)
  local fields = { s = stamp, n = tostring(#quests) }
  for _, q in ipairs(quests) do fields["q" .. q[1]] = q[2] .. q[3] end
  local texts = ns.Codec.encode("QLA", fields, { repeatKeys = { "s", "n" } })
  for _, text in ipairs(texts) do W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "GUILD", sender) end
  return #texts
end

return {
  files = "toc",
  tests = {
    my_whole_quest_list_goes_to_a_friend_who_asks = function(ns, A, W)
      local quests = {
        { id = 7, title = "Kobold Camp Cleanup", objectives = {} },
        { id = 33, title = "Wolves Across the Border", objectives = {} },
        { id = 52, title = "A Very Long Quest Name That Goes On And On Forever", objectives = {} },
      }
      questLog(W, quests, 7)
      rawset(W.env.C_QuestLog, "IsPushableQuest", function(id) return id ~= 33 end)
      start(ns, W)
      W.state.inGroup = true
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      W:advance(2)
      local before = #W.sent
      receive(ns, W, "Ginkan", "QLQ", { t = "Twiz" })
      receive(ns, W, "Frostie", "QLQ", { t = "Holly" })
      W:advance(5)
      A.eq(#sentOf(ns, W, "QLA", before), 0, "not for strangers, not when it is meant for someone else")
      receive(ns, W, "Frostie", "QLQ", { t = "Twiz" })
      W:advance(5)
      local got = sentOf(ns, W, "QLA", before)
      A.eq(#got, 1, "three quests fit in one message")
      A.eq(got[1].n, "3")
      A.eq(got[1].q7, "1Kobold Camp Cleanup")
      A.eq(got[1].q33, "0Wolves Across the Border", "0: the game won't share this one")
      A.eq(got[1].q52, "1A Very Long Quest Name That Goes On And ", "the name is cut as on the row")
      -- asked again at once: no second answer
      before = #W.sent
      receive(ns, W, "Frostie", "QLQ", { t = "Twiz" })
      W:advance(5)
      A.eq(#sentOf(ns, W, "QLA", before), 0)
      -- my quests change while I'm in a group: the group gets the new list by itself
      quests[4] = { id = 60, title = "Brand New", objectives = {} }
      W:fire("QUEST_ACCEPTED", 60)
      W:advance(6)
      got = sentOf(ns, W, "QLA", before)
      A.eq(#got, 1, "one new list")
      A.eq(got[1].n, "4"); A.eq(got[1].q60, "1Brand New")
      -- nothing changed: nothing more
      before = #W.sent
      W:fire("QUEST_LOG_UPDATE")
      W:advance(6)
      A.eq(#sentOf(ns, W, "QLA", before), 0)
      -- sharing switched off: an empty list
      ns.Modules.set("panel", "shareQuest", false)
      W:advance(11)
      before = #W.sent
      receive(ns, W, "Frostie", "QLQ", { t = "Twiz" })
      W:advance(5)
      got = sentOf(ns, W, "QLA", before)
      A.eq(got[#got].n, "0"); A.eq(got[#got].q7, nil)
      A.eq(ns.Log.errors(10), {})
    end,
    a_friends_whole_quest_list_shows_what_i_can_get = function(ns, A, W)
      questLog(W, { { id = 7, title = "Kobold Camp Cleanup", objectives = {} } }, 7)
      local done = { [40] = true }
      rawset(W.env.C_QuestLog, "IsQuestFlaggedCompleted", function(id) return done[id] == true end)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves Across the Border", qi = "33", qs = "1" })
      W:advance(1)
      local QL = ns.QuestList
      A.eq(QL.known("Frostie"), false)
      A.eq(QL.count("Frostie"), 0, "no list yet")
      local row = ns.Panel.models()[1]
      local item
      for _, it in ipairs(ns.Panel.rowMenu(row)) do if it.label:find("^Their quests") then item = it end end
      A.ok(item, "Their quests in the row menu")
      A.eq(item.label, "Their quests (asking...)")
      W:advance(2)
      local asks = sentOf(ns, W, "QLQ")
      A.eq(#asks, 1, "opening the menu asked for their list")
      A.eq(asks[1].t, "Frostie")
      A.eq(#ns.Panel.rowMenu(row) > 0, true)
      W:advance(2)
      A.eq(#sentOf(ns, W, "QLQ"), 1, "not asked again right away")
      receiveList(ns, W, "Frostie", "100x1", {
        { 33, "1", "Wolves Across the Border" }, -- can be shared, I don't have it
        { 7, "1", "Kobold Camp Cleanup" },       -- I have it too
        { 40, "1", "Old one" },                  -- I did it
        { 41, "0", "Bound to them" },            -- the game won't share it
        { 42, "1", "A Fine Quest" },
      })
      A.eq(QL.known("Frostie"), true)
      A.eq(QL.count("Frostie"), 2)
      A.eq(labels(QL.menuItems("Frostie")), {
        "Ask to share: A Fine Quest",
        "Ask to share: Wolves Across the Border",
        "Can't share: Bound to them (it can't be shared)",
        "Can't share: Old one (you already did it)",
        "1 quest you both have",
      })
      for _, it in ipairs(ns.Panel.rowMenu(row)) do if it.label:find("^Their quests") then item = it end end
      A.eq(item.label, "Their quests (2 you can get)")
      item.onClick()
      A.eq(labels(QL.lastMenu)[1], "Ask to share: A Fine Quest", "the click opens their quests")
      -- asking for one of them is the usual share request
      W.state.inGroup = true
      local before = #W.sent
      QL.lastMenu[1].onClick()
      W:advance(2)
      local req = sentOf(ns, W, "QREQ", before)
      A.eq(#req, 1); A.eq(req[1].q, "A Fine Quest"); A.eq(req[1].t, "Frostie")
      -- a newer list replaces the old one
      W:advance(6)
      receiveList(ns, W, "Frostie", "200x2", { { 42, "1", "A Fine Quest" } })
      A.eq(QL.count("Frostie"), 1)
      A.eq(labels(QL.menuItems("Frostie")), { "Ask to share: A Fine Quest" })
      W:advance(6)
      receiveList(ns, W, "Frostie", "300x3", {})
      A.eq(labels(QL.menuItems("Frostie")), { "They have no quests (or don't share them)" })
      -- a full quest log comes in several pieces and is only used once whole
      local many = {}
      for i = 1, 25 do many[i] = { 1000 + i, "1", "Quest number " .. i .. " with a long enough name" } end
      W:advance(6)
      local pieces = receiveList(ns, W, "Frostie", "400x4", many)
      A.ok(pieces > 1, "more than one message")
      A.eq(QL.listForTest("Frostie").n, 25)
      A.eq(QL.count("Frostie"), 25)
      -- half a list changes nothing
      W:advance(6)
      local texts = ns.Codec.encode("QLA", { s = "500x5", n = "3", q1 = "1One" }, { repeatKeys = { "s", "n" } })
      W:fire("CHAT_MSG_ADDON", "TwizCrew", texts[1], "GUILD", "Frostie")
      A.eq(QL.count("Frostie"), 25, "still the last whole list")
      -- strangers' lists are not kept
      receiveList(ns, W, "Ginkan", "1x1", { { 42, "1", "A Fine Quest" } })
      A.eq(QL.known("Ginkan"), false)
      A.eq(ns.Log.errors(10), {})
    end,
    a_group_member_with_quests_for_me_gets_one_heads_up = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Holly", "STATE", { cl = "PRIEST" })
      W:advance(1)
      -- not in my group: the list is kept, nothing pops up
      receiveList(ns, W, "Holly", "1x1", { { 42, "1", "A Fine Quest" } })
      A.eq(#ns.Popups.textsForTest(), 0)
      -- I join a group with Frostie: their list is asked for
      W.state.inGroup = true
      W.state.groupMembers = { "Frostie" }
      local before = #W.sent
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(4)
      local asks = sentOf(ns, W, "QLQ", before)
      A.eq(#asks, 1, "asked the one in my group, once")
      A.eq(asks[1].t, "Frostie")
      receiveList(ns, W, "Frostie", "5x1", { { 42, "1", "A Fine Quest" }, { 43, "1", "Another One" },
        { 44, "0", "Bound to them" } })
      local t = ns.Popups.textsForTest()
      A.eq(#t, 1)
      A.eq(t[1].text, "Frostie has 2 quests you can get")
      A.eq(t[1].subtext, "Click to see them and ask")
      A.contains(W.printed[#W.printed], "Frostie has 2 quests you can get")
      ns.Popups.clickForTest(1)
      A.eq(labels(ns.QuestList.lastMenu), { "Ask to share: A Fine Quest", "Ask to share: Another One",
        "Can't share: Bound to them (it can't be shared)" }, "the click opens their quests")
      -- their list changes: no second pop-up in the same grouping
      W:advance(6)
      receiveList(ns, W, "Frostie", "6x2", { { 42, "1", "A Fine Quest" }, { 45, "1", "Third" }, { 46, "1", "Fourth" } })
      A.eq(#ns.Popups.textsForTest(), 0)
      -- Holly joins: her list is already here, so she gets hers right away
      W.state.groupMembers = { "Frostie", "Holly" }
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(2)
      t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "Holly has 1 quest you can get")
      A.eq(t[#t].subtext, "Click to see it and ask")
      -- the group ends and forms again: told again
      W:advance(20)
      W.state.inGroup = false
      W.state.groupMembers = {}
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(2)
      ns.Modules.set("panel", "questHeadsUp", false)
      W.state.inGroup = true
      W.state.groupMembers = { "Frostie" }
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(2)
      A.eq(#ns.Popups.textsForTest(), 0, "switched off: no pop-up")
      ns.Modules.set("panel", "questHeadsUp", true)
      W:fire("GROUP_ROSTER_UPDATE")
      W:advance(2)
      t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "Frostie has 3 quests you can get")
      A.eq(ns.Log.errors(10), {})
    end,
    short_and_objective_lines = function(ns, A)
      local Q = ns.Quest
      A.eq(Q.short("Kobold Camp Cleanup", "Kobold Vermin slain: 3/8; Kobold Worker slain: 0/6"),
        "Kobold Camp Cleanup (3/8)")
      A.eq(Q.short("Kobold Camp Cleanup", "Kobold Vermin slain: 8/8; Kobold Worker slain: 2/6"),
        "Kobold Camp Cleanup (2/6)", "the first one not done yet")
      A.eq(Q.short("Wolves", "", true), "Wolves (ready to turn in)")
      A.eq(Q.short("Talk to Bob", "Speak with Bob"), "Talk to Bob")
      A.eq(Q.short("", "x"), nil); A.eq(Q.short(nil), nil)
      A.eq(Q.objectiveLines("a: 1/2; b: 0/3"), { "a: 1/2", "b: 0/3" })
      A.eq(Q.objectiveLines(""), {})
    end,
    shares_the_quest_you_make_progress_on = function(ns, A, W)
      local quests = {
        { id = 7, title = "Kobold Camp Cleanup", objectives = { { text = "Kobold Vermin slain: 3/8" } } },
        { id = 33, title = "Wolves Across the Border", objectives = { { text = "Diseased Wolf Pelt: 1/8" } } },
      }
      questLog(W, quests, 7)
      start(ns, W)
      W:advance(2)
      A.eq(ns.Self.lastSent().qn, "Kobold Camp Cleanup", "the watched one at first")
      A.eq(ns.Self.lastSent().qo, "Kobold Vermin slain: 3/8")
      quests[2].objectives[1].text = "Diseased Wolf Pelt: 2/8" -- progress on the wolves
      W:fire("QUEST_LOG_UPDATE")
      W:advance(2)
      A.eq(ns.Self.lastSent().qn, "Wolves Across the Border", "the one that moved")
      quests[2].complete = true
      quests[2].objectives[1] = { text = "Diseased Wolf Pelt: 8/8", finished = true }
      W:fire("QUEST_LOG_UPDATE")
      W:advance(2)
      A.eq(ns.Self.lastSent().qc, "1", "ready to turn in")
      table.remove(quests, 2) -- turned in
      W:fire("QUEST_LOG_UPDATE")
      W:advance(2)
      A.eq(ns.Self.lastSent().qn, "Kobold Camp Cleanup", "back to the watched one")
      ns.Modules.set("panel", "shareQuest", false)
      W:fire("QUEST_LOG_UPDATE")
      W:advance(2)
      A.eq(ns.Self.lastSent().qn, "", "sharing off")
      A.eq(ns.Log.errors(10), {})
    end,
    accepting_a_quest_makes_it_current = function(ns, A, W)
      local quests = { { id = 7, title = "Old one", objectives = {} } }
      questLog(W, quests, 7)
      start(ns, W)
      quests[2] = { id = 50, title = "Brand new", objectives = { { text = "Thing: 0/1" } } }
      W:fire("QUEST_ACCEPTED", 50)
      W:advance(2)
      A.eq(ns.Self.lastSent().qn, "Brand new")
    end,
    no_quests_no_problem = function(ns, A, W)
      start(ns, W)
      W:advance(2)
      A.eq(ns.Self.lastSent().qn, "")
      A.eq(ns.Log.errors(10), {})
    end,
    friend_quest_on_the_row_and_in_the_tooltip = function(ns, A, W)
      local L = ns.PanelLogic
      local m = { name = "Frostie", online = true, level = 12, zone = "Elwynn Forest", subzone = "Goldshire",
        questName = "Kobold Camp Cleanup", questObjectives = "Kobold Vermin slain: 3/8; Kobold Worker slain: 0/6",
        status = "LF group" }
      local rows = L.rows({ m }, {}, nil, true, 0, 0)
      A.eq(rows[1].quest, "Kobold Camp Cleanup (3/8)")
      A.eq(rows[1].info, { "Where: Elwynn Forest, Goldshire", "Quest: Kobold Camp Cleanup",
        "   - Kobold Vermin slain: 3/8", "   - Kobold Worker slain: 0/6", 'Status: "LF group"' })
      m.online = false
      rows = L.rows({ m }, {}, nil, true, 0, 0)
      A.eq(rows[1].quest, nil, "offline: no quest line")
      A.eq(rows[1].info, nil)
    end,
    friend_quest_arrives_over_the_wire = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves", qo = "Pelt: 8/8", qc = "1" })
      local f = ns.roster:get("Frostie")
      A.eq(f.questName, "Wolves"); A.eq(f.questObjectives, "Pelt: 8/8"); A.eq(f.questComplete, true)
      receive(ns, W, "Frostie", "UPDATE", { qc = "" })
      A.eq(ns.roster:get("Frostie").questComplete, false)
    end,
    row_menu_builds_when_group_and_inspect_answers_are_secret = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves Across the Border", qo = "Pelt: 2/8" })
      W:advance(1)
      local hidden = W.secret()
      for _, name in ipairs({ "UnitInParty", "UnitInRaid", "CanInspect" }) do
        W.env[name] = function() return hidden end
      end
      local labels = {}
      for _, it in ipairs(ns.Panel.rowMenu(ns.Panel.models()[1])) do labels[#labels + 1] = it.label end
      A.eq(labels[1], "Whisper")
      A.eq(labels[2], "Invite to group", "a secret answer is not 'already in my group'")
      A.eq(ns.Log.errors(10), {})
    end,
    ask_a_friend_to_share_their_quest = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves Across the Border", qo = "Pelt: 2/8" })
      W:advance(1)
      local row = ns.Panel.models()[1]
      A.eq(row.questName, "Wolves Across the Border")
      local items = ns.Panel.rowMenu(row)
      local ask
      for _, it in ipairs(items) do if it.label:find("^Ask to share") then ask = it end end
      A.ok(ask, "Ask to share in the row menu")
      A.eq(ask.label, "Ask to share: Wolves Across the Border")
      ask.onClick()
      W:advance(1)
      A.eq(#sentOf(ns, W, "QREQ"), 0, "not in a group: nothing sent")
      A.contains(W.printed[#W.printed], "only works in a group")
      -- grouped, but the game's name check misses Frostie (as on Forever): still asks
      W.state.inGroup = true
      W.state.units.party1 = { name = "Frostie", player = true }
      W:advance(1) -- the party list is read again after half a second
      A.ok(ns.Quest.request("Frostie", "Wolves Across the Border"))
      A.no(ns.Panel.rowMenu(row)[2] and ns.Panel.rowMenu(row)[2].label == "Invite to group",
        "no Invite for someone already in my party")
      W:advance(1)
      local req
      for _, m in ipairs(W.sent) do
        local msg = ns.Codec.decode(m.text)
        if msg and msg.type == "QREQ" then req = msg.fields end
      end
      A.ok(req, "a QREQ went out")
      A.eq(req.t, "Frostie"); A.eq(req.q, "Wolves Across the Border")
      A.no(ns.Quest.request("Frostie", "Wolves Across the Border"), "not again right away")
      A.eq(ns.Log.errors(10), {})
    end,
    a_share_request_pops_up_and_one_click_shares = function(ns, A, W)
      questLog(W, { { id = 7, title = "Kobold Camp Cleanup", objectives = {} },
        { id = 33, title = "Wolves Across the Border", objectives = {} } }, 7)
      local selected, pushed = nil, 0
      rawset(W.env.C_QuestLog, "SetSelectedQuest", function(id) selected = id end)
      rawset(W.env.C_QuestLog, "IsPushableQuest", function() return true end)
      W.env.QuestLogPushQuest = function() pushed = pushed + 1 end
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      receive(ns, W, "Frostie", "QREQ", { t = "Twiz", q = "Wolves Across the Border" })
      local t = ns.Popups.textsForTest()
      A.eq(t[#t].text, "Frostie asks you to share a quest")
      A.eq(t[#t].subtext, "Wolves Across the Border  -  click to share it")
      ns.Popups.clickForTest(#t)
      A.eq(selected, 33, "that quest is picked")
      A.eq(pushed, 1, "and shared")
      receive(ns, W, "Ginkan", "QREQ", { t = "Twiz", q = "Wolves Across the Border" })
      A.eq(#ns.Popups.textsForTest(), 0, "strangers can't ask")
      W:advance(16)
      receive(ns, W, "Frostie", "QREQ", { t = "Holly", q = "Wolves Across the Border" })
      A.eq(#ns.Popups.textsForTest(), 0, "a request meant for someone else")
      A.eq(ns.Quest.share("Not In My Log"), "missing")
      rawset(W.env.C_QuestLog, "IsPushableQuest", function() return false end)
      A.eq(ns.Quest.share("Kobold Camp Cleanup"), "unshareable")
      ns.Modules.set("panel", "questRequests", false)
      W:advance(16)
      receive(ns, W, "Frostie", "QREQ", { t = "Twiz", q = "Kobold Camp Cleanup" })
      A.eq(#ns.Popups.textsForTest(), 0, "switched off")
      A.eq(ns.Log.errors(10), {})
    end,
    my_quest_id_and_shareable_go_out = function(ns, A, W)
      questLog(W, { { id = 7, title = "Kobold Camp Cleanup", objectives = { { text = "Vermin: 1/8" } } } }, 7)
      rawset(W.env.C_QuestLog, "IsPushableQuest", function() return true end)
      start(ns, W)
      W:advance(2)
      A.eq(ns.Self.lastSent().qi, "7")
      A.eq(ns.Self.lastSent().qs, "1")
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves", qi = "33", qs = "0" })
      local f = ns.roster:get("Frostie")
      A.eq(f.questId, 33); A.eq(f.questShareable, false)
    end,
    can_i_get_their_quest = function(ns, A, W)
      questLog(W, { { id = 7, title = "Kobold Camp Cleanup", objectives = {} } }, 7)
      local done = { [40] = true }
      rawset(W.env.C_QuestLog, "IsQuestFlaggedCompleted", function(id) return done[id] == true end)
      start(ns, W)
      local Q = ns.Quest
      A.eq(Q.canGet(nil, "Wolves"), "unknown", "no ID, not mine: can't tell")
      A.eq(Q.canGet(7, "Kobold Camp Cleanup"), "have")
      A.eq(Q.canGet(nil, "Kobold Camp Cleanup"), "have", "by name too")
      A.eq(Q.canGet(40, "Old one"), "done")
      A.eq(Q.canGet(33, "Wolves", false), "unshareable")
      A.eq(Q.canGet(33, "Wolves"), "unknown", "without Questie: can't tell")
      -- with Questie
      local state, text = 8, "Unavailable: Class requirement"
      W.env.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieDB" then return { IsDoableVerbose = function() return text, true, state end } end
      end }
      local st, words = Q.canGet(33, "Wolves")
      A.eq(st, "no"); A.eq(words, "you can't take it (class requirement)")
      state, text = 0, "Available: Doable"
      A.eq(Q.canGet(33, "Wolves"), "ok")
      -- the menu and the tooltip say so
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves", qi = "33", qs = "1" })
      W:advance(1)
      local row = ns.Panel.models()[1]
      local found
      for _, l in ipairs(row.info or {}) do if l:find("You can get it", 1, true) then found = true end end
      A.ok(found, "tooltip: you can get it")
      A.eq(row.questShare, "yes")
      A.eq(ns.Panel.rowShareShownForTest(1), "yes", "green: they can share it with you")
      state, text = 7, "Unavailable: Missing pre quest"
      W:advance(31) -- the panel redraws by itself
      A.eq(ns.Panel.rowShareShownForTest(1), "no", "red: an earlier step is missing")
      A.eq(ns.Panel.models()[1].questWhy, "you can't take it (missing pre quest)")
      state, text = 0, "Available: Doable"
      done[33] = true
      W:advance(31)
      A.eq(ns.Panel.rowShareShownForTest(1), "no", "already done: red too")
      local label
      for _, it in ipairs(ns.Panel.rowMenu(row)) do if it.label:find("share") then label = it.label end end
      A.eq(label, "Can't share: Wolves (you already did it)")
      A.eq(ns.Log.errors(10), {})
    end,
    right_click_menu = function(ns, A, W)
      start(ns, W)
      local M = ns.Panel.rowMenu
      local ME1, ME2, ME3 = "Me: set my status", "Me: go AFK", "Me: update my spell ranks" -- mine, on every row
      A.eq(labels(M({ name = "Frostie", tags = {} })), { "Whisper", "Invite to group", "Add to friends", ME1, ME2, ME3 })
      A.eq(labels(M({ name = "Frostie", offline = true, tags = {} })), { "Add to friends", "Forget this friend", ME1, ME2, ME3 }, "offline")
      W.state.groupMembers = { "Frostie" }
      A.eq(labels(M({ name = "Frostie", tags = {} })), { "Whisper", "Add to friends", ME1, ME2, ME3 }, "already grouped")
      W.state.groupMembers = {}
      A.eq(labels(M({ name = "Frostie", tags = { "DEAD" } })), { "Whisper", "Invite to group", "Mock them",
        "Add to friends", ME1, ME2, ME3 }, "dead: mock")
      A.eq(labels(M({ name = "Frostie", dinged = true, tags = {} })), { "Whisper", "Invite to group",
        "Congratulate them", "Add to friends", ME1, ME2, ME3 }, "just leveled up: congrats")
      local items = M({ name = "Frostie", tags = {} })
      items[5].onClick()
      A.eq(ns.Away.isAway(), true, "Me: go AFK from a friend's row")
      A.eq(labels(M({ name = "Frostie", tags = {} }))[5], "Me: I'm back")
      items[5].onClick()
      W.state.units.party1 = { name = "Frostie", player = true, visible = true }
      W.env.CanInspect = function() return true end
      local inspected
      W.env.InspectUnit = function(u) inspected = u end
      local items = M({ name = "Frostie", tags = {} })
      A.eq(labels(items)[3], "Inspect", "near and inspectable")
      items[3].onClick()
      A.eq(inspected, "party1")
      A.eq(labels(M({ name = "Twiz", tags = {} })), { "Set my status", "Go AFK" }, "my own row")
      items = M({ name = "Ginkan", tags = {} })
      items[2].onClick()
      A.eq(W.invites[#W.invites], "Ginkan", "invite uses the name the game knows")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
