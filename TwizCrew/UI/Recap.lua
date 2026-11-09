-- Today's recap (module "recap", an extra): a short card about this play session. It shows by itself when you log
-- out or quit (during the game's countdown), and any time with /tc recap, the wrench menu or a key binding.
-- Only your own numbers, counted on this computer since you logged in; nothing is sent.
local _, ns = ...

local Recap = {}
ns.Recap = Recap

local FEATURE = "recap"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local I = "Interface\\Icons\\"

local s = nil -- this session's numbers (from login)
local frame, rows = nil, {}

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
end

local function num(v) v = tonumber(v); if v and v == v then return v end end

local function fresh()
  s = {
    started = ns.now(), money = num(call(GetMoney)), level = num(call(UnitLevel, "player")),
    xp = num(call(UnitXP, "player")) or 0, xpMax = num(call(UnitXPMax, "player")) or 0,
    xpGained = 0, levels = 0, deaths = 0, quests = 0, mocked = 0, cheered = 0, friends = {},
  }
  if ns.roster then
    for _, name in ipairs(ns.roster:names()) do
      local m = ns.roster:get(name)
      if m and m.online and not ns.isTestName(name) then s.friends[name] = m.class or true end
    end
  end
end

local function onXP()
  if not s then return end
  local xp, max, lv = num(call(UnitXP, "player")) or 0, num(call(UnitXPMax, "player")) or 0, num(call(UnitLevel, "player"))
  if lv and s.lastLevel and lv > s.lastLevel then
    s.xpGained = s.xpGained + math.max(0, (s.lastMax or 0) - (s.lastXP or 0)) + xp
  elseif xp >= (s.lastXP or s.xp) then
    s.xpGained = s.xpGained + (xp - (s.lastXP or s.xp))
  end
  s.lastXP, s.lastMax, s.lastLevel = xp, max, lv
end

-- Money as "1g 20s 5c" (with a sign).
local function money(c)
  local sign = c < 0 and "-" or "+"
  c = math.abs(math.floor(c))
  local g, sv, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if sv > 0 then parts[#parts + 1] = sv .. "s" end
  if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. "c" end
  return sign .. table.concat(parts, " ")
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- The card's lines: { icon, text }.
function Recap.lines()
  if not s then fresh() end
  local out = {}
  local played = math.max(0, ns.now() - s.started) / 60
  out[#out + 1] = { I .. "INV_Misc_PocketWatch_01", "Played " .. ns.CalendarLogic.duration(played) }
  local lv = num(call(UnitLevel, "player"))
  if s.levels > 0 then
    out[#out + 1] = { I .. "Spell_Holy_PowerInfusion", plural(s.levels, "level", "levels") .. " gained (now " .. tostring(lv) .. ")" }
  end
  if s.xpGained > 0 then
    out[#out + 1] = { I .. "INV_Misc_Book_09", ns.PanelLogic.thousands(s.xpGained) .. " XP earned" }
  end
  out[#out + 1] = { I .. "INV_Misc_Note_02", s.quests > 0 and (plural(s.quests, "quest", "quests") .. " turned in")
    or "No quests turned in" }
  out[#out + 1] = { I .. "INV_Misc_Bone_HumanSkull_01", s.deaths == 0 and "No deaths. Who are you and what did you do with the real you?"
    or (plural(s.deaths, "death", "deaths") .. (s.deaths >= 5 and ". The spirit healer knows you by name." or "")) }
  local now = num(call(GetMoney))
  if now and s.money then
    out[#out + 1] = { I .. "INV_Misc_Coin_01", "Gold: " .. money(now - s.money) }
  end
  if s.mocked > 0 or s.cheered > 0 then
    out[#out + 1] = { I .. "INV_Misc_Gift_01", "Mocked " .. plural(s.mocked, "time", "times") .. ", congratulated "
      .. plural(s.cheered, "time", "times") }
  end
  local names = {}
  for name in pairs(s.friends) do names[#names + 1] = name end
  table.sort(names)
  out[#out + 1] = { I .. "Ability_Warrior_BattleShout", #names > 0 and ("Crew online with you: " .. table.concat(names, ", "))
    or "Nobody from the crew was on. Lone wolf session." }
  return out
end

-- Test hooks: the counters.
function Recap.forTest() if not s then fresh() end return s end

local function build()
  frame = T.frame("Frame", "TwizCrewRecap", UIParent)
  frame:SetSize(420, 60)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  Widgets.script(frame, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  Widgets.script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end, FEATURE)
  T.paint(frame, C.backdrop, 0.97, C.title, 2)
  T.gloss(frame, nil, 0.05, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewRecap") end
  local logo = frame:CreateTexture(nil, "ARTWORK")
  logo:SetSize(T.icon(26), T.icon(26))
  logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
  logo:SetTexture(I .. "INV_Scroll_03")
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local title = T.readable(T.text(frame, T.FONT.normal, C.title), 3)
  title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  title:SetText("Today's recap")
  local close = Widgets.button(frame, "Close", function() frame:Hide() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
end

function Recap.show()
  if not frame then build() end
  local lines = Recap.lines()
  for i, l in ipairs(lines) do
    local r = rows[i]
    if not r then
      r = CreateFrame("Frame", nil, frame)
      r:SetSize(392, 28)
      r:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -(48 + (i - 1) * 30))
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(T.icon(22), T.icon(22))
      r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.text = T.readable(T.text(r, T.FONT.small, C.white))
      r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
      r.text:SetWidth(360)
      r.text:SetJustifyH("LEFT")
      rows[i] = r
    end
    r.icon:SetTexture(l[1])
    r.text:SetText(l[2])
    r:Show()
  end
  for i = #lines + 1, #rows do rows[i]:Hide() end
  frame:SetHeight(48 + #lines * 30 + 12)
  frame:Show()
  Recap.lastLines = lines
end

function Recap.isShown() return frame ~= nil and frame:IsShown() and true or false end

local function onEnable()
  if not s then fresh() end
  s.lastXP, s.lastMax, s.lastLevel = s.xp, s.xpMax, s.level
  ns.Events.on(FEATURE, "PLAYER_XP_UPDATE", onXP)
  ns.Events.on(FEATURE, "PLAYER_LEVEL_UP", function() if s then s.levels = s.levels + 1 end end)
  ns.Events.on(FEATURE, "PLAYER_DEAD", function() if s then s.deaths = s.deaths + 1 end end)
  ns.Events.on(FEATURE, "QUEST_TURNED_IN", function() if s then s.quests = s.quests + 1 end end)
  -- logging out or quitting: the game counts down, the card shows meanwhile
  ns.Events.on(FEATURE, "PLAYER_CAMPING", function() if ns.Modules.setting(FEATURE, "onLogout") ~= false then Recap.show() end end)
  ns.Events.on(FEATURE, "PLAYER_QUITING", function() if ns.Modules.setting(FEATURE, "onLogout") ~= false then Recap.show() end end)
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", function(name)
    if s and type(name) == "string" and not ns.isTestName(name) then
      local m = ns.roster and ns.roster:get(name)
      s.friends[name] = m and m.class or true
    end
  end)
  ns.Bus.on(FEATURE, "ABOUT_ME", function(kind)
    if not s then return end
    if kind == "cheer" then s.cheered = s.cheered + 1 else s.mocked = s.mocked + 1 end
  end)
end

local function onDisable()
  if frame then frame:Hide() end
end

ns.Modules.register({
  id = FEATURE, name = "Today's recap", tier = "extra",
  info = "A short card about your play session: time played, levels and XP, quests, deaths, gold, mocks and who "
    .. "from the crew was on. It shows when you log out (during the countdown), or any time with /tc recap.",
  defaults = { onLogout = true },
  settings = {
    { key = "show", label = "Show today's recap now", kind = "button", onClick = function() Recap.show() end,
      info = "Opens the card for this play session so far." },
    { key = "onLogout", label = "Show it when I log out", kind = "toggle",
      info = "The card shows by itself while the game counts down to log out or quit." },
  },
  onEnable = onEnable,
  onDisable = onDisable,
})
