-- Key bindings (Commands.binding), quick statuses, "Also on it" in a friend's tooltip, and Today's recap.

local function start(ns, W)
  local db = ns.DB.init(nil, ns.Modules.list())
  ns.db = db
  ns.Modules.attach(db)
  ns.Comm.start()
  ns.Crew.start()
  ns.Self.start()
  ns.LayerSensor.start()
  ns.Modules.startAll()
  W:fire("PLAYER_ENTERING_WORLD")
  W:advance(6)
  return db
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

return {
  files = "toc",
  tests = {
    key_bindings = function(ns, A, W)
      start(ns, W)
      A.eq(type(W.env.TwizCrew_Binding), "function")
      A.eq(W.env.BINDING_HEADER_TWIZCREW, "TwizCrew")
      A.ok(W.env.BINDING_NAME_TWIZCREW_CALENDAR)
      W.env.TwizCrew_Binding("panel")
      A.no(ns.Modules.isEnabled("panel"), "the panel key hides it")
      W.env.TwizCrew_Binding("panel")
      A.ok(ns.Modules.isEnabled("panel"))
      W.env.TwizCrew_Binding("calendar")
      A.ok(ns.Calendar.isShown())
      W.env.TwizCrew_Binding("afk")
      A.ok(ns.Away.isAway())
      W.env.TwizCrew_Binding("mock")
      A.contains(W.printed[#W.printed], "target a dead crew friend")
      for _, k in ipairs({ "note", "rankup", "recap", "settings" }) do W.env.TwizCrew_Binding(k) end
      A.eq(ns.Log.errors(10), {})
      -- the file the game reads for them
      local f = io.open("TwizCrew/Bindings.xml")
      local xml = f:read("*a"); f:close()
      for _, n in ipairs({ "PANEL", "CALENDAR", "NOTE", "AFK", "RANKUP", "MOCK", "RECAP", "SETTINGS" }) do
        A.contains(xml, 'name="TWIZCREW_' .. n .. '"')
        A.ok(W.env["BINDING_NAME_TWIZCREW_" .. n], "a name for " .. n)
      end
    end,
    quick_statuses = function(ns, A, W)
      start(ns, W)
      A.eq(#ns.Panel.STATUS_PRESETS >= 4, true)
      ns.Panel.openStatusBox()
      ns.Panel.setStatusPreset("LF group")
      A.eq(ns.db.myStatus, "LF group")
      W:advance(2)
      A.eq(ns.Self.lastSent().st, "LF group", "the crew sees it")
      ns.Panel.setStatusPreset("")
      A.eq(ns.db.myStatus, "")
    end,
    also_on_it = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE", qn = "Wolves", qi = "33" })
      receive(ns, W, "Ginkan", "STATE", { cl = "WARRIOR", qn = "Wolves", qi = "33" })
      receive(ns, W, "Holly", "STATE", { cl = "PRIEST", qn = "Kobolds", qi = "7" })
      W:advance(1)
      local by = {}
      for _, r in ipairs(ns.Panel.models()) do by[r.name] = r end
      A.eq(by.Frostie.questMates, { "Ginkan" })
      A.eq(by.Ginkan.questMates, { "Frostie" })
      A.eq(by.Holly.questMates, nil, "alone on hers")
      local found
      for _, l in ipairs(by.Frostie.info) do if l == "   Also on it: Ginkan" then found = true end end
      A.ok(found, "a line in the tooltip")
    end,
    todays_recap = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "STATE", { cl = "MAGE" })
      local s = ns.Recap.forTest()
      W:fire("PLAYER_DEAD")
      W:fire("PLAYER_DEAD")
      W:fire("QUEST_TURNED_IN", 7)
      W:fire("PLAYER_LEVEL_UP", 11)
      ns.Bus.fire("ABOUT_ME", "mock", "Frostie")
      ns.Bus.fire("ABOUT_ME", "cheer", "Frostie")
      W:advance(3600)
      A.eq(s.deaths, 2); A.eq(s.quests, 1); A.eq(s.levels, 1); A.eq(s.mocked, 1); A.eq(s.cheered, 1)
      ns.Recap.show()
      local text = {}
      for _, l in ipairs(ns.Recap.lastLines) do text[#text + 1] = l[2] end
      local all = table.concat(text, "|")
      A.contains(all, "Played 1h")
      A.contains(all, "2 deaths")
      A.contains(all, "1 quest turned in")
      A.contains(all, "1 level gained")
      A.contains(all, "Mocked 1 time, congratulated 1 time")
      A.contains(all, "Frostie", "who from the crew was on")
      for _, l in ipairs(ns.Recap.lastLines) do A.eq(type(l[1]), "string", "an icon on every line") end
      -- it shows by itself when you log out
      ns.Recap.lastLines = nil
      W:fire("PLAYER_CAMPING")
      A.ok(ns.Recap.lastLines, "shown at logout")
      ns.Modules.set("recap", "onLogout", false)
      ns.Recap.lastLines = nil
      W:fire("PLAYER_CAMPING")
      A.eq(ns.Recap.lastLines, nil, "switched off")
      W.env.SlashCmdList.TWIZCREW("recap")
      A.ok(ns.Recap.lastLines, "/tc recap")
      A.eq(ns.Log.errors(10), {})
    end,
  },
}
