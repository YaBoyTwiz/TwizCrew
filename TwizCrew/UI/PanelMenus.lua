-- The Crew panel's menus: the right-click menu of the header and of a row, the wrench's tools menu, the row buttons'
-- actions (Congrats, Mock, ask to share) and the status box. Part of the panel (UI/Panel.lua); shared names live on
-- ns.Panel._ (P).
local _, ns = ...

local Panel = ns.Panel
local P = Panel._

local FEATURE = "panel"
local T, Widgets, Logic = ns.Theme, ns.Widgets, ns.PanelLogic
local C = T.COLOR
local setting, set, minimized, script = P.setting, P.set, P.minimized, P.script
local requestRedraw, rowFrames, cheered = P.requestRedraw, P.rowFrames, P.cheered
-- Menu pictures by the start of an entry's words (entries that bring their own icon keep it).
local MENU_ICONS = {
  { "^Whisper", "Interface\\Icons\\INV_Misc_Note_02" },
  { "^Invite", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" },
  { "^Inspect", "Interface\\Icons\\Spell_Holy_MindVision" },
  { "^Point the arrow", "Interface\\Icons\\Ability_Hunter_Pathfinding" },
  { "^Ask to share", "Interface\\Icons\\Spell_ChargePositive" },
  { "^Can't share", "Interface\\RaidFrame\\ReadyCheck-NotReady" },
  { "^Congratulate", "Interface\\Icons\\INV_Misc_Gift_01" },
  { "^Mock", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
  { "^Add to friends", "Interface\\Icons\\Spell_Holy_GreaterHeal" },
  { "^Forget this friend", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_02" },
  { "set my status", "Interface\\Icons\\INV_Misc_Note_01" },
  { "^Set my status", "Interface\\Icons\\INV_Misc_Note_01" },
  { "AFK", "AFK_TAG" },
  { "I'm back", "AFK_TAG" },
  { "spell ranks", "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
  { "^Show offline", "Interface\\Icons\\Ability_Stealth" },
  { "^Lock position", "Interface\\Icons\\INV_Misc_Key_03" },
  { "^Minimize", "Interface\\Icons\\INV_Misc_Spyglass_03" },
  { "^Restore", "Interface\\Icons\\INV_Misc_Spyglass_03" },
  { "^Recent activity", "Interface\\Icons\\INV_Misc_Note_02" },
  { "^Row style", "Interface\\Icons\\INV_Fabric_Linen_01" },
  { "^Hide during fights", "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
  { "^Open settings", "Interface\\Icons\\Trade_Engineering" },
  { "^Hide panel", "Interface\\Icons\\Spell_Nature_Invisibilty" },
}

-- A list without its holes (menu entries that are nil when their feature is off), each with its picture.
local function compact(t)
  local out = {}
  for i = 1, table.maxn(t) do
    local it = t[i]
    if it ~= nil then
      if type(it) == "table" and it.icon == nil and type(it.label) == "string" then
        for _, m in ipairs(MENU_ICONS) do
          if it.label:find(m[1]) then
            it.icon = m[2] == "AFK_TAG" and ns.Tags.ICON.AFK or m[2]
            break
          end
        end
      end
      out[#out + 1] = it
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------------- menu
local function choiceLabel(key, value)
  for _, def in ipairs(ns.Modules.get(FEATURE).settings) do
    if def.key == key then
      for _, c in ipairs(def.choices or {}) do if c[1] == value then return c[2] end end
    end
  end
  return tostring(value)
end

local NEXT_STYLE = { full = "compact", compact = "tiny", tiny = "full" }

local function flip(key)
  return function() set(key, not setting(key)) end
end

local function isOn(key)
  return function() return setting(key) and true or false end
end

-- The wrench button's menu: handy tools. New tools go here.
function Panel.toolItems()
  local function rank(key) return ns.Modules.setting("rankup", key) end
  local function flipRank(key)
    return function()
      if not ns.Modules.isEnabled("rankup") then ns.Modules.setEnabled("rankup", true) end
      ns.Modules.set("rankup", key, not rank(key))
    end
  end
  return compact {
    ns.RankUp and { label = "Update my spell ranks", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
      onClick = function() ns.RankUp.run() end } or nil,
    ns.RankUp and { label = "...by itself when I learn a spell", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      checked = function() return rank("auto") and true or false end, onClick = flipRank("auto") } or nil,
    ns.RankUp and { label = "...with its own button on screen", icon = "Interface\\Icons\\INV_Misc_Rune_01",
      checked = function() return rank("showButton") and true or false end, onClick = flipRank("showButton") } or nil,
    ns.Calendar and { label = "Crew calendar", icon = "Interface\\Icons\\INV_Scroll_03",
      onClick = function() ns.Calendar.toggle() end } or nil,
    ns.MockEditor and { label = "My mocks", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
      onClick = function() ns.MockEditor.open() end } or nil,
    ns.Recent and { label = "Recent activity", icon = "Interface\\Icons\\INV_Misc_Note_02",
      onClick = function() ns.Recent.open() end } or nil,
    ns.Recap and { label = "Today's recap", icon = "Interface\\Icons\\INV_Misc_Book_11",
      onClick = function() ns.Recap.show() end } or nil,
    ns.Changelog and { label = "What's new", icon = "Interface\\Icons\\INV_Misc_Book_09",
      onClick = function() ns.Changelog.open() end } or nil,
    { label = "Health check (to copy to Discord)", icon = "Interface\\Icons\\INV_Misc_Note_01",
      onClick = function() if ns.Report then ns.Report.show() end end },
  }
end

function Panel.menuItems()
  return compact {
    { label = "Show offline friends", checked = isOn("showOffline"), onClick = flip("showOffline") },
    { label = "Lock position", checked = isOn("locked"), onClick = flip("locked") },
    { label = Logic.miniLabel(minimized()), onClick = function() Panel.toggleMinimized() end },
    { label = "Row style: " .. choiceLabel("rowStyle", setting("rowStyle")),
      onClick = function() set("rowStyle", NEXT_STYLE[setting("rowStyle")] or "full") end },
    { label = "Hide during fights", checked = isOn("hideInCombat"), onClick = flip("hideInCombat") },
    { label = "Set my status", onClick = function() Panel.openStatusBox() end },
    { label = (ns.Away and ns.Away.isAway()) and "I'm back" or "Go AFK", onClick = function() Panel.toggleAway() end },
    { label = "Open settings", onClick = function()
      if ns.Settings and ns.Settings.open then ns.Settings.open() end
    end },
    { label = "Hide panel", onClick = function()
      ns.Modules.setEnabled(FEATURE, false)
      print("TwizCrew: panel hidden. Type /tc show to bring it back.")
    end },
  }
end

---------------------------------------------------------------------------------------------------- status box
-- A small box of our own (not a StaticPopup) to type the status: Enter saves, Escape cancels, empty clears.
local statusBox

local function closeStatusBox()
  if not statusBox then return end
  statusBox.edit:ClearFocus()
  statusBox:Hide()
end

-- The quick statuses in the status box.
Panel.STATUS_PRESETS = { "LF group", "Questing", "Farming", "Dungeon soon", "Back in 5" }

function Panel.setStatusPreset(text)
  ns.Self.setStatus(text or "")
  local now = ns.db and ns.db.myStatus or ""
  if now == "" then print("TwizCrew: status cleared")
  else print('TwizCrew: status set to "' .. ns.Util.safeText(now) .. '"') end
  if statusBox then statusBox.open = false; statusBox.edit:ClearFocus(); statusBox:Hide() end
end

local function saveStatus()
  if not statusBox or not statusBox.open then return end -- one save per opening
  statusBox.open = false
  local text = statusBox.edit:GetText()
  ns.Self.setStatus(type(text) == "string" and text or "")
  local now = ns.db and ns.db.myStatus or ""
  if now == "" then print("TwizCrew: status cleared")
  else print('TwizCrew: status set to "' .. ns.Util.safeText(now) .. '"') end
  closeStatusBox()
end

local function buildStatusBox()
  local f = T.frame("Frame", "TwizCrewStatus", UIParent)
  f:SetSize(300, 132)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:EnableMouse(true)
  T.paint(f, C.backdrop, 0.95, C.border, 2)
  local title = T.text(f, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText("Set my status")
  local e = T.frame("EditBox", nil, f)
  e:SetSize(276, 22)
  e:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
  T.paint(e, C.row, 1, C.buttonBorder, 1)
  e:SetAutoFocus(false)
  if e.SetFontObject then e:SetFontObject(T.FONT.small) end
  if e.SetTextInsets then e:SetTextInsets(5, 5, 0, 0) end
  if e.SetMaxLetters then e:SetMaxLetters(ns.Config.STATUS_MAX) end
  local hint = T.text(f, T.FONT.small, C.muted)
  hint:SetPoint("TOPLEFT", e, "BOTTOMLEFT", 0, -4)
  hint:SetText("Enter saves, Escape cancels. Leave it empty to clear it.")
  -- one click for the usual ones
  local presets = T.text(f, T.FONT.small, C.muted)
  presets:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  presets:SetText("Quick:")
  local x, y = 0, 0
  for i, p in ipairs(Panel.STATUS_PRESETS) do
    local b = Widgets.button(f, p, function() Panel.setStatusPreset(p) end, nil, FEATURE)
    b:SetHeight(20)
    local w = b:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = 70 end
    if x + w > 240 then x, y = 0, y + 23 end
    b:SetPoint("TOPLEFT", presets, "TOPRIGHT", 6 + x, 3 - y)
    x = x + w + 4
  end
  local clear = Widgets.button(f, "Clear", function() Panel.setStatusPreset("") end, "danger", FEATURE)
  clear:SetHeight(20)
  clear:SetPoint("TOPLEFT", presets, "TOPRIGHT", 6 + x, 3 - y)
  script(e, "OnEnterPressed", saveStatus)
  script(e, "OnEscapePressed", closeStatusBox)
  script(f, "OnHide", function() f.open = false end)
  f.edit = e
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewStatus") end -- Escape closes it
  return f
end

-------------------------------------------------------------------------------------------------------- row menu
local call = ns.Util.plain

-- Is this friend in my group? The game's name check, else their name in my party / raid slots (Forever's name
-- check can miss them).
local function inMyGroup(name)
  if (call(UnitInParty, name) or call(UnitInRaid, name)) then return true end
  if ns.Where and ns.Where.unitFor then
    if ns.Where.unitFor(name) then return true end
    local short = ns.shortName and ns.shortName(name)
    if short and short ~= name and ns.Where.unitFor(short) then return true end
  end
  return false
end

local function inviteName(full)
  if C_PartyInfo and C_PartyInfo.InviteUnit then call(C_PartyInfo.InviteUnit, full)
  elseif type(InviteUnit) == "function" then call(InviteUnit, full) end
end

local function addFriend(full)
  if C_FriendList and C_FriendList.AddFriend then call(C_FriendList.AddFriend, full)
  elseif type(AddFriend) == "function" then call(AddFriend, full) end
  print("TwizCrew: asked the game to add " .. full .. " to your friends list.")
end

-- The right-click menu of a row: what you can do for (or to) that friend right now.
function Panel.rowMenu(m)
  local items = {}
  local name = m and m.name
  if type(name) ~= "string" or name == "" then return items end
  if ns.isMe(name) then
    items[#items + 1] = { label = "Set my status", onClick = function() Panel.openStatusBox() end }
    items[#items + 1] = { label = (ns.Away and ns.Away.isAway()) and "I'm back" or "Go AFK",
      onClick = function() Panel.toggleAway() end }
    return compact(items)
  end
  local full = (ns.Transport and ns.Transport.fullName and ns.Transport.fullName(name)) or name
  if not m.offline then
    items[#items + 1] = { label = "Whisper", onClick = function() ns.Util.whisper(name) end }
    if not inMyGroup(name) then
      items[#items + 1] = { label = "Invite to group", onClick = function() inviteName(full) end }
    end
    local unit = ns.MockShow and ns.MockShow.liveUnit(name)
    if unit and call(CanInspect, unit) and type(InspectUnit) == "function" then
      items[#items + 1] = { label = "Inspect", onClick = function() call(InspectUnit, unit) end }
    end
    if ns.Find and ns.BigArrow and ns.Find.positionOf and call(ns.Find.positionOf, name) then
      items[#items + 1] = { label = "Point the arrow at them",
        onClick = function() ns.BigArrow.point({ kind = "member", name = name }) end }
    end
    local dead = false
    for _, id in ipairs(m.tags or {}) do if id == "DEAD" then dead = true end end
    if m.questName and ns.Quest and ns.Quest.request then
      local title = m.questName
      local shown = ns.Util.truncateUTF8(ns.Util.safeText(title), 28)
      if shown ~= ns.Util.safeText(title) then shown = shown .. "..." end
      local status, words = "unknown", nil
      if ns.Quest.canGet then status, words = ns.Quest.canGet(m.questId, title, m.questShareable) end
      if status == "ok" or status == "unknown" then
        items[#items + 1] = { label = "Ask to share: " .. shown, onClick = function() ns.Quest.request(name, title) end }
      else
        items[#items + 1] = { label = "Can't share: " .. shown .. " (" .. tostring(words) .. ")",
          onClick = function() print("TwizCrew: no use asking: " .. tostring(words) .. ".") end }
      end
    end
    if m.dinged and ns.Roasts and ns.Roasts.canCheer and ns.Roasts.canCheer(name) then
      items[#items + 1] = { label = "Congratulate them", onClick = function() Panel.cheer({ tcModel = m }) end }
    end
    if dead and ns.Roasts and ns.Roasts.canMock(name) then
      items[#items + 1] = { label = "Mock them", onClick = function()
        if not ns.Roasts.mock(name) then print("TwizCrew: give it a few seconds before mocking " .. name .. " again.") end
      end }
    end
  end
  items[#items + 1] = { label = "Add to friends", onClick = function() addFriend(full) end }
  if m.offline then
    items[#items + 1] = { label = "Forget this friend", onClick = function()
      local ok, why = ns.Crew.forget(name)
      if ok then print("TwizCrew: forgot " .. ns.Util.safeText(name) .. ".")
      else print("TwizCrew: could not forget " .. ns.Util.safeText(name) .. " (" .. tostring(why) .. ").") end
    end }
  end
  -- my own things, on every row (my own row is off by default); later features for me go here too
  for _, it in ipairs(Panel.myItems()) do items[#items + 1] = it end
  return compact(items)
end

-- What I can do for myself from any row's menu (and my own row's).
function Panel.myItems()
  return compact {
    { label = "Me: set my status", onClick = function() Panel.openStatusBox() end },
    { label = (ns.Away and ns.Away.isAway()) and "Me: I'm back" or "Me: go AFK", onClick = function() Panel.toggleAway() end },
    ns.RankUp and ns.Modules.isEnabled("rankup") and
      { label = "Me: update my spell ranks", onClick = function() ns.RankUp.run() end } or nil,
  }
end

-- The share icon on a quest line: ask them to share it.
function Panel.askShare(r)
  local m = r and r.tcModel
  if not m or not m.questName or not ns.Quest or not ns.Quest.request then return end
  if m.questShare == "no" then print("TwizCrew: no use asking: " .. tostring(m.questWhy or "you can't get it") .. "."); return end
  if m.questShare == "same" then print("TwizCrew: you're on that quest too."); return end
  ns.Quest.request(m.name, m.questName)
end

function Panel.rowShareShownForTest(i)
  local r = rowFrames[i]
  if r == nil or i > P.visibleRows then return nil end
  return rawget(r, "tcShare") -- "yes" | "no" | "same" | nil
end

-- The Congrats button (or menu entry): congratulate them once; the button goes away.
function Panel.cheer(r)
  local m = r and r.tcModel
  if not m or not ns.Roasts or not ns.Roasts.cheer then return end
  if ns.Roasts.cheer(m.name) then
    cheered[m.name] = true
    requestRedraw()
  end
end

function Panel.rowCheerShownForTest(i)
  local r = rowFrames[i]
  return r ~= nil and i <= P.visibleRows and rawget(r, "tcCheer") == true
end

function Panel.mock(r)
  local m = r and r.tcModel
  if not m or not ns.Roasts then return end
  if not ns.Roasts.mock(m.name) then print("TwizCrew: give it a few seconds before mocking " .. m.name .. " again.") end
end

function Panel.toggleAway()
  if not ns.Away then return end
  local before = ns.Away.isAway()
  local away = ns.Away.toggle()
  if before and away then
    print("TwizCrew: the game itself still has you AFK. Move or type /afk to clear it.")
  else
    print("TwizCrew: " .. (away and "your crew sees you as AFK." or "welcome back!"))
  end
  P.drawAfkButton()
end

function Panel.openStatusBox()
  if not statusBox then statusBox = buildStatusBox() end
  statusBox.edit:SetText(tostring(ns.db and ns.db.myStatus or ""))
  statusBox.open = true
  statusBox:Show()
  statusBox.edit:SetFocus()
  if statusBox.edit.HighlightText then statusBox.edit:HighlightText() end
end
