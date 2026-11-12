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
  },
}
