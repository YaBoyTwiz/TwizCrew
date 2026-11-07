-- Live roasts (module "roasts", stats Task 7): lines, the ROAST message, rate limits, the receiver's switches and
-- the roast pop-ups (which work even while the pop-ups module is off). Full TOC boot with the real ns.Roasts.

local function boot(W)
  W:fire("ADDON_LOADED", "TwizCrew")
  W:fire("PLAYER_LOGIN")
  W:fire("PLAYER_ENTERING_WORLD")
end

-- Boots and lets the crew session be decided (past SESSION_DECIDE_AFTER), so the connection is ready.
local function start(ns, W)
  boot(W)
  W:advance(ns.Config.SESSION_DECIDE_AFTER + 1)
end

local function receive(ns, W, sender, msgType, fields)
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {})) do
    W:fire("CHAT_MSG_ADDON", "TwizCrew", text, "CHANNEL", sender)
  end
end

-- Decoded ROAST messages in W.sent (fields tables).
local function roastsSent(ns, W)
  local out = {}
  for _, m in ipairs(W.sent) do
    local msg = ns.Codec.decode(m.text)
    if msg and msg.type == "ROAST" then out[#out + 1] = msg.fields end
  end
  return out
end

local function shown(ns) return ns.Roasts.forTest.shown() end

-- The fake game never runs OnUpdate on its own: run it once on every frame that has one.
local function frameUpdate(W)
  for _, f in ipairs(W.frames) do
    local h = f._scripts and f._scripts.OnUpdate
    if h then h(f, 0.1) end
  end
end

local function hasText(ns, part)
  for _, p in ipairs(ns.Popups.textsForTest()) do
    if p.text:find(part, 1, true) then return true end
  end
  return false
end

return {
  files = "toc",
  tests = {
    mock_sends_a_roast_everyone_sees = function(ns, A, W)
      start(ns, W)
      local text = ns.Roasts.mock("Frostie")
      A.ok(text, "a roast was picked")
      A.no(text:find("{", 1, true), "placeholders filled in: " .. text)
      W:advance(1) -- the send queue goes out on its next pump
      local sent
      for _, m in ipairs(W.sent) do
        local msg = ns.Codec.decode(m.text)
        if msg and msg.type == "MOCK" then sent = msg.fields end
      end
      A.ok(sent, "a MOCK message went out")
      A.eq(sent.t, "Frostie"); A.eq(sent.x, text)
      local s = shown(ns)
      A.eq(s[#s], "Twiz: " .. text, "shown here too, with who sent it")
      A.no(ns.Roasts.mock("Frostie"), "not again right away")
      W:advance(11)
      A.ok(ns.Roasts.mock("Frostie"), "fine after the gap")
      A.no(ns.Roasts.mock("Twiz"), "never yourself")
      A.eq(ns.Log.errors(10), {})
    end,
    mock_from_a_friend_shows = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Ginkan", "MOCK", { t = "Frostie", x = "Rest in pieces, Frostie." })
      local s = shown(ns)
      A.eq(s[#s], "Ginkan: Rest in pieces, Frostie.")
      ns.Modules.set("roasts", "mocks", false)
      receive(ns, W, "Pewpew", "MOCK", { t = "Frostie", x = "another" })
      A.eq(shown(ns)[#shown(ns)], "Ginkan: Rest in pieces, Frostie.", "switch off: not shown")
      A.no(ns.Roasts.canMock("Frostie"), "and no button")
    end,
    my_own_roasts_join_the_rotation = function(ns, A, W)
      start(ns, W)
      A.eq(ns.Roasts.addMock("  "), false, "blank is refused")
      A.ok(ns.Roasts.addMock("{name} tripped over a flower while {me} watched."))
      A.eq(ns.Roasts.myMocks(), { "{name} tripped over a flower while {me} watched." })
      A.eq(#ns.Roasts.rotation(), #ns.Roasts.MOCK_LINES + 1)
      ns.Modules.set("roasts", "ownOnly", true)
      A.eq(ns.Roasts.rotation(), { "{name} tripped over a flower while {me} watched." })
      A.eq(ns.Roasts.mock("Frostie"), "Frostie tripped over a flower while Twiz watched.")
      A.eq(ns.Roasts.removeMock(1), "{name} tripped over a flower while {me} watched.")
      A.eq(ns.Roasts.removeMock(1), nil)
      A.eq(#ns.Roasts.rotation(), #ns.Roasts.MOCK_LINES, "only-mine with none falls back to the built-in ones")
    end,
    rotation_has_no_repeats_until_all_used = function(ns, A, W)
      start(ns, W)
      local seen, n = {}, #ns.Roasts.MOCK_LINES
      for i = 1, n do
        local text = ns.Roasts.mock("Friend" .. i)
        A.ok(text and not seen[text], "line " .. i .. " is new")
        seen[text:gsub("Friend%d+", "X")] = true
      end
    end,
    mock_commands = function(ns, A, W)
      start(ns, W)
      W.env.SlashCmdList.TWIZCREW("mock add {name} forgot how to jump")
      A.eq(ns.Roasts.myMocks(), { "{name} forgot how to jump" })
      W.env.SlashCmdList.TWIZCREW("mock list")
      A.ok(W.printed[#W.printed]:find("1. {name} forgot how to jump", 1, true))
      W.env.SlashCmdList.TWIZCREW("mock remove 1")
      A.eq(ns.Roasts.myMocks(), {})
      W.env.SlashCmdList.TWIZCREW("mock frostie")
      local s = shown(ns)
      A.ok(s[#s] and s[#s]:find("Frostie", 1, true), "mocked by name")
      A.eq(ns.Log.errors(10), {})
    end,
    my_roasts_survive_a_settings_reset = function(ns, A, W)
      start(ns, W)
      ns.Roasts.addMock("keep me")
      ns.Modules.resetAll()
      A.eq(ns.Roasts.myMocks(), { "keep me" })
    end,
    roast_text_is_safe = function(ns, A, W)
      start(ns, W)
      local R = ns.Roasts
      A.eq(R.text("weak", 1, "Holy|bøi", 3, "|cffKobold"), "Holy||bøi died to a level 3 ||cffKobold. Embarrassing.")
      A.eq(R.text("steps", 1, "Ginkan", 100000), "Ginkan just passed 100,000 steps. Still lost.")
      A.eq(R.text("weak", 99, "A", 3), R.text("weak", 1, "A", 3), "out of range: line 1")
      A.eq(R.text("weak", 1, "A", 3), "A died to a level 3 mob. Embarrassing.", "no mob name: 'mob'")
      A.eq(R.text("wipe", 1, "A"), "WIPE! Everybody down in a dungeon.", "no place: 'a dungeon'")
      A.eq(R.text("fall", "2", "A"), R.text("fall", 2, "A"), "line number as text")
      A.eq(R.text("weak", 1, "A%1", 3, "%d %s"), "A%1 died to a level 3 %d %s. Embarrassing.")
      -- Odd letters and wire separators arrive intact and show as plain text.
      receive(ns, W, "Frostie", "ROAST", { k = "weak", v = "3", x = "Hog^ger~=|r", n = "1" })
      A.eq(shown(ns), { "Frostie died to a level 3 Hog^ger~=||r. Embarrassing." })
      A.eq(ns.Popups.textsForTest()[1].text, "Frostie died to a level 3 Hog^ger~=||r. Embarrassing.")
      local history = ns.Popups.shownForTest()
      A.eq(history[#history], "Frostie died to a level 3 Hog^ger~=||r. Embarrassing.")
      A.eq(ns.Log.errors(10), {})
    end,

    every_kind_has_three_lines = function(ns, A, W)
      start(ns, W)
      for _, kind in ipairs(ns.StatsDefs.ROAST_KINDS) do
        local lines = ns.Roasts.LINES[kind]
        A.ok(type(lines) == "table" and #lines >= 3, kind .. " has at least 3 lines")
        for i, line in ipairs(lines or {}) do
          local want = kind == "wipe" and "{x}" or "{name}"
          A.ok(line:find(want, 1, true) ~= nil, kind .. " line " .. i .. " has " .. want)
          local text = ns.Roasts.text(kind, i, "Twiz", 7, "Kobold")
          A.no(text:find("{", 1, true), kind .. " line " .. i .. " has no placeholder left")
        end
      end
    end,

    lines_read_well_with_defaults_and_names = function(ns, A, W)
      start(ns, W)
      local R = ns.Roasts
      for _, kind in ipairs(ns.StatsDefs.ROAST_KINDS) do
        for i = 1, #R.LINES[kind] do
          for _, x in ipairs({ "", "Hogger", "The Deadmines" }) do
            local text = R.text(kind, i, "Twiz", 3, x)
            A.no(text:find("^%l"), kind .. " " .. i .. " starts with a small letter: " .. text)
            A.no(text:find("[.!?] %l"), kind .. " " .. i .. " has a sentence starting small: " .. text)
            A.no(text:find("The Hogger", 1, true), kind .. " " .. i .. ": " .. text)
            A.no(text:find("The The", 1, true), kind .. " " .. i .. ": " .. text)
          end
        end
      end
    end,

    received_extra_text_and_numbers_are_tamed = function(ns, A, W)
      start(ns, W)
      local long = string.rep("ø", 50)
      receive(ns, W, "A", "ROAST", { k = "weak", v = "3", x = "Kob\1old" .. long, n = "1" })
      A.eq(#shown(ns), 1)
      local cut = "Kobold" .. string.rep("ø", 34)
      A.eq(shown(ns)[1], "A died to a level 3 " .. cut .. ". Embarrassing.", "40 letters, no control bytes")
      receive(ns, W, "B", "ROAST", { k = "wipe", x = "Dead\9mines\31", n = "1" })
      A.eq(shown(ns)[2], "WIPE! Everybody down in Deadmines.")
      -- a number too big to be real: ignored for the kinds that show it, harmless for the others
      receive(ns, W, "C", "ROAST", { k = "steps", v = "1e10", n = "1" })
      receive(ns, W, "D", "ROAST", { k = "jumps", v = "1000000001", n = "1" })
      A.eq(#shown(ns), 2)
      receive(ns, W, "E", "ROAST", { k = "jumps", v = "1000000000", n = "1" })
      A.eq(#shown(ns), 3, "1e9 itself is still a number")
      receive(ns, W, "F", "ROAST", { k = "fall", v = "1e300", n = "1" })
      A.eq(#shown(ns), 4)
      A.eq(ns.Log.errors(10), {})
    end,

    sent_extra_text_is_cut_and_cleaned = function(ns, A, W)
      start(ns, W)
      ns.Roasts.send("weak", 3, "Kob\2old" .. string.rep("x", 60))
      ns.Roasts.send("steps", 2e9) -- (dropped by the sender limit anyway, and unusable)
      W:advance(1)
      local sent = roastsSent(ns, W)
      A.eq(#sent, 1)
      A.eq(sent[1].x, "Kobold" .. string.rep("x", 34))
      W:advance(ns.Config.ROAST_GAP + 1)
      ns.Roasts.send("steps", 2e9)
      W:advance(1)
      A.eq(#roastsSent(ns, W), 1, "a number too big is not sent")
    end,

    own_roast_is_sent_and_shown = function(ns, A, W)
      start(ns, W)
      ns.Roasts.send("fall")
      W:advance(1)
      local sent = roastsSent(ns, W)
      A.eq(#sent, 1)
      A.eq(sent[1].k, "fall")
      local n = tonumber(sent[1].n)
      A.ok(n and n >= 1 and n <= #ns.Roasts.LINES.fall, "line number in range")
      A.ok(hasText(ns, "Twiz"), "my own roast shows on my screen")
      A.eq(shown(ns), { ns.Roasts.text("fall", n, "Twiz") })
      -- Sender limit: a second roast about me within ROAST_GAP is dropped.
      ns.Roasts.send("drown")
      W:advance(3)
      A.eq(#roastsSent(ns, W), 1)
      W:advance(ns.Config.ROAST_GAP)
      ns.Roasts.send("again", 12)
      W:advance(1)
      sent = roastsSent(ns, W)
      A.eq(#sent, 2)
      A.eq(sent[2].k, "again")
      A.eq(sent[2].v, "12")
      A.eq(#shown(ns), 2)
      A.eq(ns.Log.errors(10), {})
    end,

    roast_needing_a_number_is_not_sent_without_one = function(ns, A, W)
      start(ns, W)
      ns.Roasts.send("weak", nil, "Kobold")
      ns.Roasts.send("bogus", 3)
      W:advance(1)
      A.eq(#roastsSent(ns, W), 0)
      ns.Roasts.send("weak", 3.7, "Kobold")
      W:advance(1)
      local sent = roastsSent(ns, W)
      A.eq(#sent, 1, "a missing number does not use up the limit")
      A.eq(sent[1].v, "3")
      A.eq(sent[1].x, "Kobold")
    end,

    received_roast_shows_same_line = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "ROAST", { k = "fall", v = "", x = "", n = "2" })
      A.eq(shown(ns), { ns.Roasts.text("fall", 2, "Frostie") })
      A.ok(hasText(ns, "Frostie"))
      local found = false
      for _, line in ipairs(ns.Log.lines()) do
        if line:find("INFO", 1, true) and line:find("Frostie", 1, true) then found = true end
      end
      A.ok(found, "one info line in the log")
    end,

    received_garbage_is_ignored = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "A", "ROAST", { k = "boom", v = "3", n = "1" })
      receive(ns, W, "B", "ROAST", { k = "weak", v = "abc", n = "1" })
      receive(ns, W, "C", "ROAST", { k = "weak", n = "1" })
      receive(ns, W, "D", "ROAST", { k = "steps", v = "1e999", n = "1" })
      receive(ns, W, "E", "ROAST", { k = "jumps", v = "-5", n = "1" })
      receive(ns, W, "F", "ROAST", { n = "1" })
      A.eq(shown(ns), {})
      receive(ns, W, "G", "ROAST", { k = "fall", n = "zz" })
      receive(ns, W, "H", "ROAST", { k = "drown", n = "999" })
      receive(ns, W, "I", "ROAST", { k = "deaths", v = "10", n = "-1" })
      A.eq(shown(ns), { ns.Roasts.text("fall", 1, "G"), ns.Roasts.text("drown", 1, "H"),
        ns.Roasts.text("deaths", 1, "I", 10) })
      A.eq(ns.Log.errors(10), {})
    end,

    rate_limit_per_person = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "ROAST", { k = "fall", n = "1" })
      W:advance(3)
      receive(ns, W, "Frostie", "ROAST", { k = "drown", n = "1" })
      A.eq(#shown(ns), 1, "second roast about Frostie within 10 s is dropped")
      receive(ns, W, "Ginkan", "ROAST", { k = "fall", n = "1" })
      A.eq(#shown(ns), 2, "Ginkan is someone else")
      W:advance(8)
      receive(ns, W, "Frostie", "ROAST", { k = "drown", n = "1" })
      A.eq(#shown(ns), 3, "Frostie again after 11 s")
      A.eq(shown(ns)[3], ns.Roasts.text("drown", 1, "Frostie"))
    end,

    wipe_dedupe = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "ROAST", { k = "wipe", x = "The Deadmines", n = "1" })
      A.eq(shown(ns), { "WIPE! Everybody down in The Deadmines." })
      W:advance(5)
      receive(ns, W, "Ginkan", "ROAST", { k = "wipe", x = "The Deadmines", n = "2" })
      A.eq(#shown(ns), 1, "the same wipe from a second copy is ignored")
      ns.Roasts.send("wipe", nil, "X")
      W:advance(3)
      A.eq(#roastsSent(ns, W), 0, "a wipe roast was seen in the last 60 s")
      W:advance(ns.Config.WIPE_ROAST_DEDUPE)
      ns.Roasts.send("wipe", nil, "The Deadmines")
      A.eq(#roastsSent(ns, W), 0, "waits a moment first")
      W:advance(3)
      local sent = roastsSent(ns, W)
      A.eq(#sent, 1)
      A.eq(sent[1].k, "wipe")
      A.eq(sent[1].x, "The Deadmines")
      A.eq(#shown(ns), 2)
      receive(ns, W, "Ginkan", "ROAST", { k = "wipe", x = "The Deadmines", n = "1" })
      A.eq(#shown(ns), 2, "mine counts as the wipe roast seen")
    end,

    wipe_seen_during_wait_cancels_mine = function(ns, A, W)
      start(ns, W)
      ns.Roasts.send("wipe", nil, "The Deadmines")
      receive(ns, W, "Frostie", "ROAST", { k = "wipe", x = "The Deadmines", n = "1" })
      W:advance(3)
      A.eq(#roastsSent(ns, W), 0, "a friend's copy was first")
      A.eq(#shown(ns), 1)
    end,

    about_me_off_sends_nothing = function(ns, A, W)
      start(ns, W)
      A.eq(ns.Modules.setting("roasts", "aboutMe"), true)
      ns.Modules.set("roasts", "aboutMe", false)
      ns.Roasts.send("fall")
      ns.Roasts.send("wipe", nil, "X")
      W:advance(3)
      A.eq(#roastsSent(ns, W), 0)
      A.eq(shown(ns), {})
      receive(ns, W, "Frostie", "ROAST", { k = "fall", n = "1" })
      A.eq(#shown(ns), 1, "roasts about others still show")
    end,

    stats_off_sends_nothing = function(ns, A, W)
      start(ns, W)
      ns.Modules.setEnabled("stats", false)
      ns.Roasts.send("fall")
      W:advance(3)
      A.eq(#roastsSent(ns, W), 0)
      A.eq(shown(ns), {})
    end,

    receiver_side_switches = function(ns, A, W)
      start(ns, W)
      ns.Modules.set("roasts", "fall", false)
      receive(ns, W, "Frostie", "ROAST", { k = "fall", n = "1" })
      A.eq(shown(ns), {})
      receive(ns, W, "Frostie", "ROAST", { k = "weak", v = "3", x = "Kobold", n = "1" })
      A.eq(shown(ns), { "Frostie died to a level 3 Kobold. Embarrassing." })
      ns.Modules.setEnabled("roasts", false)
      receive(ns, W, "Ginkan", "ROAST", { k = "weak", v = "3", x = "Kobold", n = "1" })
      A.eq(#shown(ns), 1, "roasts module off: nothing shown")
      ns.Roasts.send("drown")
      W:advance(1)
      local sent = roastsSent(ns, W)
      A.eq(#sent, 1, "my own roast is still sent: others still see it")
      A.eq(sent[1].k, "drown")
      A.eq(#shown(ns), 1)
    end,

    sound_off_by_default = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "ROAST", { k = "fall", n = "1" })
      A.eq(#shown(ns), 1)
      A.eq(W.sounds, {})
      ns.Modules.set("roasts", "sound", true)
      receive(ns, W, "Ginkan", "ROAST", { k = "fall", n = "1" })
      A.eq(W.sounds, { 8959 })
    end,

    roast_popup_closes_itself = function(ns, A, W)
      start(ns, W)
      ns.Modules.setEnabled("popups", false)
      receive(ns, W, "Frostie", "ROAST", { k = "fall", n = "1" })
      A.eq(ns.Popups.visibleCount(), 1)
      A.eq(ns.Popups.textsForTest()[1].text, ns.Roasts.text("fall", 1, "Frostie"))
      A.eq(ns.Popups.shownForTest()[#ns.Popups.shownForTest()], ns.Roasts.text("fall", 1, "Frostie"))
      W:advance(3)
      frameUpdate(W)
      A.eq(ns.Popups.visibleCount(), 1, "still there after 3 s")
      W:advance(4)
      frameUpdate(W)
      A.eq(ns.Popups.visibleCount(), 0)
      A.eq(ns.Log.errors(10), {})
    end,

    roast_popup_with_popups_on = function(ns, A, W)
      start(ns, W)
      receive(ns, W, "Frostie", "ROAST", { k = "fall", n = "1" })
      A.eq(ns.Popups.visibleCount(), 1)
      W:advance(7)
      A.eq(ns.Popups.visibleCount(), 0, "the pop-ups ticker also closes it")
      A.eq(ns.Log.errors(10), {})
    end,

    module_and_settings_have_info = function(ns, A, W)
      start(ns, W)
      local d = ns.Modules.get("roasts")
      A.eq(d.name, "Live roasts")
      A.eq(d.tier, "module")
      A.ok(ns.Modules.isEnabled("roasts"))
      local keys = {}
      for _, s in ipairs(d.settings) do keys[s.key] = s end
      for _, kind in ipairs(ns.StatsDefs.ROAST_KINDS) do
        A.ok(keys[kind] ~= nil, "a switch for " .. kind)
        A.eq(ns.Modules.setting("roasts", kind), true)
      end
      A.eq(ns.Modules.setting("roasts", "aboutMe"), true)
      A.eq(ns.Modules.setting("roasts", "sound"), false)
      A.ok(keys.aboutMe.info:find("about you", 1, true) ~= nil)
    end,

    two_copies_show_the_same_line = function(ns, A, W, H)
      local WA, a = H.client("Twiz")
      local WB, b = H.client("Frostie")
      H.link(WA, WB)
      boot(WA); boot(WB)
      H.advance(a.Config.SESSION_DECIDE_AFTER + 2)
      b.Roasts.send("weak", 3, "Kobold")
      H.advance(2)
      A.eq(#b.Roasts.forTest.shown(), 1)
      A.eq(a.Roasts.forTest.shown(), b.Roasts.forTest.shown())
      A.ok(a.Roasts.forTest.shown()[1]:find("Frostie", 1, true) ~= nil)
      A.eq(a.Log.errors(10), {})
      A.eq(b.Log.errors(10), {})
    end,
  },
}
