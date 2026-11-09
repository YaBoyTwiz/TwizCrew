-- Spell rank updater (module "rankup", a handy tool): one click swaps old spell ranks on your action bars for the
-- highest rank you know. From the panel's wrench (Tools) button, the row menus, /tc rankup, its own button, or the
-- Tools tab in the settings.
-- Only spells are touched: macros, items and empty slots stay as they are. Never in combat (the game forbids it).
local _, ns = ...

local RankUp = {}
ns.RankUp = RankUp

local FEATURE = "rankup"
local MAX_SLOT = 180 -- every bar, including stance/form bars and the extra pages

local enabled = false
local pendingAuto = false
local button, learnFrame

local function setting(key) return ns.Modules.setting(FEATURE, key) end
local function say(msg) print("TwizCrew: " .. msg) end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

-- "Rank 3" -> 3; anything else -> nil
function RankUp.rankOf(text)
  return type(text) == "string" and tonumber(text:match("(%d+)")) or nil
end
local rankOf = RankUp.rankOf

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local n = call(C_Spell.GetSpellName, id)
    if n then return n end
  end
  return (call(GetSpellInfo, id))
end

local function spellRank(id)
  if C_Spell and C_Spell.GetSpellSubtext then
    local r = rankOf(call(C_Spell.GetSpellSubtext, id))
    if r then return r end
  end
  return rankOf(call(GetSpellSubtext, id))
end

------------------------------------------------------------------------------------------------- spellbook
-- Every spell in your spellbook: add(name, spellID, rank or nil). The new API first, else the old one.
local function eachBookSpell(add)
  local SB = C_SpellBook
  if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookItemInfo then
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, (call(SB.GetNumSpellBookSkillLines) or 0) do
      local info = call(SB.GetSpellBookSkillLineInfo, line)
      if type(info) == "table" and not info.shouldHide then
        local first = (info.itemIndexOffset or 0) + 1
        for i = first, first + (info.numSpellBookItems or 0) - 1 do
          local item = call(SB.GetSpellBookItemInfo, i, bank)
          if type(item) == "table" and item.spellID and not item.isPassive
            and (item.itemType == nil or spellType == nil or item.itemType == spellType) then
            local name, sub = item.name, item.subName
            if not name and SB.GetSpellBookItemName then name, sub = call(SB.GetSpellBookItemName, i, bank) end
            add(name or spellName(item.spellID), item.spellID, rankOf(sub) or spellRank(item.spellID))
          end
        end
      end
    end
    return
  end
  local book = BOOKTYPE_SPELL or "spell"
  for tab = 1, (call(GetNumSpellTabs) or 0) do
    local _, _, offset, count = call(GetSpellTabInfo, tab)
    for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
      local kind, id = call(GetSpellBookItemInfo, i, book)
      if (kind == "SPELL" or kind == "spell") and id then
        local name, sub = call(GetSpellBookItemName, i, book)
        add(name or spellName(id), id, rankOf(sub) or spellRank(id))
      end
    end
  end
end

RankUp.eachBookSpell, RankUp.spellName, RankUp.spellRank = eachBookSpell, spellName, spellRank

-- name -> { id, rank } for the highest rank of each spell you know
function RankUp.bestRanks()
  local best = {}
  eachBookSpell(function(name, id, rank)
    if type(name) ~= "string" then return end
    local b = best[name]
    if not b or (rank or 0) > (b.rank or 0) then best[name] = { id = id, rank = rank } end
  end)
  return best
end

-- Pure: which slots to change. slots = { { slot, name, id, rank } } (spells only), best from bestRanks.
-- Returns { { slot, name, from = rank|nil, to = rank, id = new spell id } }.
function RankUp.plan(slots, best)
  local out = {}
  for _, s in ipairs(slots or {}) do
    local b = s.name and best[s.name]
    if b and b.id ~= s.id and b.rank and b.rank > (s.rank or 0) then
      out[#out + 1] = { slot = s.slot, name = s.name, from = s.rank, to = b.rank, id = b.id }
    end
  end
  return out
end

local function barSpells()
  local list = {}
  for slot = 1, MAX_SLOT do
    if call(HasAction, slot) then
      local kind, id = call(GetActionInfo, slot)
      if kind == "spell" and id then
        list[#list + 1] = { slot = slot, name = spellName(id), id = id, rank = spellRank(id) }
      end
    end
  end
  return list
end

------------------------------------------------------------------------------------------------- the swap
RankUp.barSpells, RankUp.MAX_SLOT = barSpells, MAX_SLOT

local function place(slot, id)
  ClearCursor()
  if C_Spell and C_Spell.PickupSpell then call(C_Spell.PickupSpell, id) else call(PickupSpell, id) end
  if type(GetCursorInfo) == "function" and not GetCursorInfo() then return false end
  PlaceAction(slot)
  ClearCursor() -- the old rank that came back onto the cursor
  return true
end

RankUp.place = place

-- quiet: say nothing when there's nothing to change (the automatic update). Returns how many slots changed.
function RankUp.update(quiet)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    if quiet then pendingAuto = true else say("can't change your bars during a fight. Try again after it.") end
    return 0
  end
  local todo = RankUp.plan(barSpells(), RankUp.bestRanks())
  local changed, failed = {}, 0
  for _, c in ipairs(todo) do
    if place(c.slot, c.id) then
      changed[#changed + 1] = string.format("%s %s-> Rank %d", c.name, c.from and ("Rank " .. c.from .. " ") or "", c.to)
    else
      failed = failed + 1
    end
  end
  if #changed > 0 then
    say("updated " .. #changed .. (#changed == 1 and " spell: " or " spells: ") .. table.concat(changed, ", "))
  elseif not quiet then
    say("your bars already have your highest spell ranks.")
  end
  if failed > 0 then say(failed .. " could not be swapped. Try again out of combat.") end
  return #changed
end

-- The button and menus call this: works even while the module is off (it's a one-off action you asked for).
function RankUp.run() return ns.Log.safe(FEATURE, RankUp.update, false) end

------------------------------------------------------------------------------------------------- button
local function savePos()
  if not button then return end
  local cx, cy = button:GetCenter()
  local ux, uy = UIParent:GetCenter()
  cx, cy, ux, uy = tonumber(cx), tonumber(cy), tonumber(ux), tonumber(uy)
  if cx and cy and ux and uy then
    ns.Modules.set(FEATURE, "buttonPos", { x = math.floor(cx - ux + 0.5), y = math.floor(cy - uy + 0.5) })
  end
end

local function buildButton()
  button = CreateFrame("Button", "TwizCrewRankUpButton", UIParent)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetMovable(true)
  if button.SetClampedToScreen then button:SetClampedToScreen(true) end
  if button.RegisterForDrag then button:RegisterForDrag("LeftButton") end
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  icon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfWisdom")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local hl = button:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(button)
  ns.Theme.color(hl, "ffffff", 0.2)
  ns.Widgets.script(button, "OnClick", function() RankUp.run() end, FEATURE)
  ns.Widgets.script(button, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  ns.Widgets.script(button, "OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end, FEATURE)
  ns.Widgets.script(button, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Update spell ranks")
    GameTooltip:AddLine("Click: put the highest rank of every spell on your action bars.", 1, 1, 1, true)
    GameTooltip:AddLine("Drag to move. Turn this button off with the wrench on the crew panel.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end, FEATURE)
  ns.Widgets.script(button, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end, FEATURE)
end

local function showButton()
  local want = enabled and setting("showButton")
  if not want then
    if button then button:Hide() end
    return
  end
  if not button then buildButton() end
  local p = setting("buttonPos")
  button:ClearAllPoints()
  if type(p) == "table" and tonumber(p.x) and tonumber(p.y) then
    button:SetPoint("CENTER", UIParent, "CENTER", tonumber(p.x), tonumber(p.y))
  else
    button:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
  end
  button:Show()
end

function RankUp.buttonShownForTest() return button ~= nil and enabled and setting("showButton") and true or false end

------------------------------------------------------------------------------------------------- module
local function onLearned()
  if not enabled or not setting("auto") then return end
  -- the spellbook updates a moment after the event
  C_Timer.After(1, function() ns.Log.safe(FEATURE, RankUp.update, true) end)
end

local function onEnable()
  enabled = true
  if not learnFrame then
    -- one of these exists in each game version; an unknown one must not cause an error
    learnFrame = CreateFrame("Frame")
    for _, e in ipairs({ "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
      pcall(learnFrame.RegisterEvent, learnFrame, e)
    end
    ns.Widgets.script(learnFrame, "OnEvent", onLearned, FEATURE)
  end
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function()
    if pendingAuto then pendingAuto = false; RankUp.update(true) end
  end)
  showButton()
end

local function onDisable()
  enabled = false
  pendingAuto = false
  showButton()
end

ns.Modules.register({
  id = FEATURE, name = "Spell rank updater", tier = "extra",
  info = "One click swaps the old ranks of your spells on your action bars for the highest rank you know, "
    .. "in the same slot. Macros and items are left alone. Also: the wrench button on the crew panel, /tc rankup.",
  defaults = { auto = false, showButton = false, buttonPos = false },
  settings = {
    { key = "update", label = "Update my spell ranks now", kind = "button", onClick = function() RankUp.run() end,
      info = "Looks at every action bar slot (also your form and stance bars) and puts the highest rank of each "
        .. "spell there. Not during a fight." },
    { key = "auto", label = "Update by itself when I learn a spell", kind = "toggle",
      info = "After you learn a new rank from a trainer, your bars get it a second later (after the fight, if "
        .. "you're in one). Note: this also replaces low ranks you keep on purpose, like a cheap Rank 1 heal." },
    { key = "showButton", label = "Show its button on screen", kind = "toggle",
      info = "A small button you can drag anywhere: click it to update your spell ranks." },
  },
  onEnable = onEnable,
  onDisable = onDisable,
  onSettingChanged = function(key)
    if key == "showButton" or key == "buttonPos" then showButton() end
  end,
})
