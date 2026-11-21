-- The test stub itself is strict, so later tests catch real mistakes: unknown widget methods raise, shown / hidden
-- state is tracked, the 255-byte send limit is enforced and secret values raise when misused.

return {
  files = {},
  tests = {
    unknown_method_raises_and_names_it = function(ns, A, W)
      local f = W.env.CreateFrame("Frame")
      A.errors(function() f:SetPonit() end, "SetPonit")
      A.errors(function() f:SetPonit() end, "Frame has no method SetPonit")
      A.errors(function() f:CreateTexture():SetPonit("CENTER") end, "Texture has no method SetPonit")
      A.errors(function() f:CreateFontString():SetTexture("x") end, "attempt to call")
      A.errors(function() W.env.CreateFrame("NotAFrame") end, "unknown frame type")
    end,

    real_methods_are_accepted = function(ns, A, W)
      local f = W.env.CreateFrame("Frame")
      f:SetPoint("CENTER")
      f:SetSize(10, 20)
      local b = W.env.CreateFrame("Button", nil, f)
      b:SetNormalTexture("x"); b:RegisterForClicks("LeftButtonUp")
      local e = W.env.CreateFrame("EditBox", nil, f)
      e:SetAutoFocus(false); e:SetMaxLetters(5); e:SetText("hi")
      A.eq(e:GetText(), "hi")
      local s = W.env.CreateFrame("Slider", nil, f)
      s:SetMinMaxValues(0, 1); s:SetValue(0.5)
      A.eq(s:GetValue(), 0.5)
      W.env.CreateFrame("StatusBar", nil, f):SetStatusBarColor(1, 1, 1)
      W.env.CreateFrame("ScrollFrame", nil, f):SetVerticalScroll(3)
      W.env.CreateFrame("DressUpModel", nil, f):SetUnit("player")
      W.env.CreateFrame("Cooldown", nil, f):SetCooldown(0, 1)
      f:CreateTexture():SetColorTexture(1, 1, 1, 1)
      f:CreateFontString():SetJustifyH("LEFT")
      local group = f:CreateAnimationGroup()
      group:CreateAnimation("Alpha"):SetDuration(1)
    end,

    a_method_of_another_type_is_not_there = function(ns, A, W)
      local f = W.env.CreateFrame("Frame")
      A.no(f.SetText, "a plain frame has no SetText")
      A.no(f.SetBackdrop, "no backdrop without BackdropTemplate")
      A.ok(W.env.CreateFrame("Frame", nil, nil, "BackdropTemplate").SetBackdrop, "with the template")
    end,

    shown_and_hidden_state_is_tracked = function(ns, A, W)
      local parent = W.env.CreateFrame("Frame")
      local child = W.env.CreateFrame("Frame", nil, parent)
      A.eq(child:IsShown(), true, "frames start shown")
      child:Hide()
      A.eq(child:IsShown(), false)
      A.eq(child:IsVisible(), false)
      child:Show()
      A.eq(child:IsShown(), true)
      A.eq(child:IsVisible(), true)
      parent:Hide()
      A.eq(child:IsShown(), true, "the child itself is still shown")
      A.eq(child:IsVisible(), false, "but not visible under a hidden parent")
      child:SetShown(false)
      A.eq(child:IsShown(), false)
    end,

    send_addon_message_allows_255_bytes_and_refuses_256 = function(ns, A, W)
      local send = W.env.C_ChatInfo.SendAddonMessage
      A.eq(send("TwizCrew", string.rep("x", 255), "PARTY"), 0)
      A.errors(function() send("TwizCrew", string.rep("x", 256), "PARTY") end, "256")
      A.eq(#W.sent, 1, "only the 255-byte one was sent")
    end,

    secret_values_raise_when_used_and_are_recognised = function(ns, A, W)
      local secret = W.secret()
      A.eq(W.env.issecretvalue(secret), true)
      A.eq(W.env.issecretvalue(5), false)
      A.errors(function() return secret + 1 end, "secret")
      A.errors(function() return secret - 1 end, "secret")
      A.errors(function() return secret * 2 end, "secret")
      A.errors(function() return secret / 2 end, "secret")
      A.errors(function() return secret % 2 end, "secret")
      A.errors(function() return -secret end, "secret")
      A.errors(function() return secret .. "x" end, "secret")
      A.errors(function() return secret < 1 end, "attempt to")
      A.errors(function() return secret <= 1 end, "attempt to")
      A.errors(function() return #secret end, "secret")
      A.errors(function() return secret() end, "secret")
      A.errors(function() return secret.field end, "secret")
      A.errors(function() return secret == W.secret() end, "secret")
    end,

    guild_list_calls_return_what_the_state_holds = function(ns, A, W)
      W.state.guild = nil -- (the runner puts every test's player in a guild)
      A.eq(W.env.IsInGuild(), false)
      A.eq(W.env.GetNumGuildMembers(), 0)
      A.eq(W.env.GetGuildInfo("player"), nil)
      local lastOnline = { 1, 2, 3, 4 }
      W.state.guild = { name = "Test Guild", members = {
        { name = "Twiz", class = "DRUID", level = 31, zone = "Stonetalon", rank = "Officer", rankIndex = 1,
          online = true, guid = "Player-1-0001" },
        { name = "Ginkan Pebble", class = "MAGE", level = 12, zone = "Elwynn Forest", rank = "Member", rankIndex = 2,
          online = false, guid = "Player-1-0002", lastOnline = lastOnline },
      } }
      A.eq(W.env.IsInGuild(), true)
      local total, online = W.env.GetNumGuildMembers()
      A.eq({ total, online }, { 2, 1 })
      local r = { W.env.GetGuildRosterInfo(2) }
      A.eq(r[1], "Ginkan Pebble"); A.eq(r[2], "Member"); A.eq(r[3], 2); A.eq(r[4], 12); A.eq(r[6], "Elwynn Forest")
      A.eq(r[9], false); A.eq(r[11], "MAGE"); A.eq(r[17], "Player-1-0002")
      A.eq(W.env.GetGuildRosterInfo(3), nil)
      A.eq({ W.env.GetGuildRosterLastOnline(2) }, { 1, 2, 3, 4 })
      A.eq(W.env.GetGuildRosterLastOnline(1), nil, "online members have no last-online time")
      A.eq({ W.env.GetGuildInfo("player") }, { "Test Guild", "Officer", 1 })
      A.eq(W.env.UnitGUID("player"), "Player-1-0001")
      W.state.rosterRealm = true
      A.eq(W.env.GetGuildRosterInfo(1), "Twiz-Realm")
      local fired = 0
      local f = W.env.CreateFrame("Frame")
      f:RegisterEvent("GUILD_ROSTER_UPDATE")
      f:SetScript("OnEvent", function() fired = fired + 1 end)
      W.env.C_GuildInfo.GuildRoster()
      A.eq({ W.guildRosterCalls, fired }, { 1, 1 })
    end,

    a_guild_send_outside_a_guild_is_refused = function(ns, A, W)
      W.state.guild = nil
      local send = W.env.C_ChatInfo.SendAddonMessage
      A.ok(send("TwizCrew", "x", "GUILD") ~= 0)
      W.state.guild = { name = "G", members = {} }
      A.eq(send("TwizCrew", "x", "GUILD"), 0)
    end,

    guild_sends_reach_the_guild_and_nobody_else = function(ns, A, W, H)
      local a, b, c = H.client("Chaos Deathbringr"), H.client("Ginkan Pebble"), H.client("Outsider")
      local d = H.client("Other Guilder")
      H.guild("One", a, b, { { name = "Offline Guy" } })
      H.guild("Two", d)
      H.link(a, b, c, d)
      local heard = {}
      for _, W2 in ipairs({ a, b, c, d }) do
        local f = W2.env.CreateFrame("Frame")
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:SetScript("OnEvent", function(_, _, prefix, text, chatType, sender)
          heard[W2.state.player] = { text = text, sender = sender, chatType = chatType }
        end)
      end
      A.eq(#a.state.guild.members, 3, "two clients and the extra member")
      A.eq(a.state.guild.members[3].online, false)
      a.env.C_ChatInfo.SendAddonMessage("TwizCrew", "hi", "GUILD")
      H.advance(1)
      A.eq(heard["Chaos Deathbringr"].text, "hi", "the sender hears its own guild message")
      A.eq(heard["Ginkan Pebble"].text, "hi")
      A.eq(heard["Outsider"], nil, "not in a guild")
      A.eq(heard["Other Guilder"], nil, "another guild")
    end,

    guild_senders_come_in_three_forms = function(ns, A, W, H)
      local a, b = H.client("Chaos Deathbringr"), H.client("Ginkan Pebble")
      H.guild("One", a, b)
      H.link(a, b)
      local sender
      local f = b.env.CreateFrame("Frame")
      f:RegisterEvent("CHAT_MSG_ADDON")
      f:SetScript("OnEvent", function(_, _, _, _, _, s) sender = s end)
      local seen = {}
      for _, form in ipairs({ "full", "first", "realm" }) do
        a.state.senderForm = form
        a.env.C_ChatInfo.SendAddonMessage("TwizCrew", form, "GUILD")
        H.advance(1)
        seen[form] = sender
      end
      A.eq(seen, { full = "Chaos Deathbringr", first = "Chaos", realm = "Chaos Deathbringr-Realm" })
    end,
  },
}
