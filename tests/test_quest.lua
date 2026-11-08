-- The quest you're on (Crew/Quest.lua), friends' quests on the panel and in the tooltip, and the row's right-click
-- menu (Panel.rowMenu).

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

local function start(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
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

return {
  files = "toc",
  tests = {
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
      local before = #W.sent
      ask.onClick()
      W:advance(1)
      A.eq(#W.sent, before, "not in a group: nothing sent")
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
      A.eq(labels(M({ name = "Frostie", offline = true, tags = {} })), { "Add to friends", ME1, ME2, ME3 }, "offline")
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
