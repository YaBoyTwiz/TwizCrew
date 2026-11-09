-- Spell helpers (module "spellhelp", a handy tool): spell by spell, choose
--   Newest rank    always the highest rank you know (the rank updater skips the spells you set to keep theirs)
--   Smart target   a harmful spell at a friend hits the friend's target, a helpful one at an enemy lands on the
--                  enemy's target (or you); done with a small macro (same icon and tooltip) that you drag from this
--                  window onto your bars yourself. TwizCrew never puts anything on, or takes anything off, your bars:
--                  it only writes its own macros (owner, 2026-11-08: it was putting things on the wrong bars).
--   Switch target  with smart target: that unit also becomes your target
-- A pop-up when you learn a new spell or rank says how it's set, click = this window at that spell.
-- The macros are this character's own (never the account-wide list) and only ones TwizCrew wrote are ever changed
-- or deleted (Tools/SpellHelpersLogic.lua knows their exact text). Never in combat: changes wait for the fight's end.
-- A macro keeps its name when its text changes, so one you put on your bars stays put.
-- Choices are per character, in TwizCrewDB.spellHelp[<Name-Realm>][<spell>] = { newest, smart, switch }.
local _, ns = ...

local SH = {}
ns.SpellHelpers = SH

local FEATURE = "spellhelp"
local L = ns.SpellHelpersLogic
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local I = "Interface\\Icons\\"
local ICON_MAIN = I .. "Spell_Holy_SealOfWisdom"

local enabled = false
local pending = false     -- a change waits for the end of a fight
local applyQueued = false
local learnFrame
local warnedFull = {}

local function setting(key) return ns.Modules.setting(FEATURE, key) end
local function say(msg) print("TwizCrew: " .. msg) end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local function inCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false end

------------------------------------------------------------------------------------------------------ choices
local function charKey()
  local realm = call(GetRealmName)
  return ns.playerName() .. "-" .. tostring(realm or "")
end

local function mine()
  local db = ns.db
  if not db then return {} end
  if type(db.spellHelp) ~= "table" then db.spellHelp = {} end
  local key = charKey()
  if type(db.spellHelp[key]) ~= "table" then db.spellHelp[key] = {} end
  return db.spellHelp[key]
end

-- A spell's choices (defaults filled in): { newest, smart, switch }.
function SH.choice(spell) return L.choice(mine()[spell]) end

-- For the rank updater: true when this spell keeps its rank.
function SH.keepsRank(spell)
  if type(spell) ~= "string" then return false end
  return not SH.choice(spell).newest
end

------------------------------------------------------------------------------------------------------ spells
local function rk() return ns.RankUp end

-- Harmful, helpful or neither (stances, self-buffs, tracking): "harm" | "help" | nil. Both: nil (it can't guess).
local function kindOf(spell, id)
  local harm, help
  if id and C_Spell and C_Spell.IsSpellHarmful then
    harm, help = call(C_Spell.IsSpellHarmful, id), call(C_Spell.IsSpellHelpful, id)
  end
  if not harm and not help then
    harm, help = call(IsHarmfulSpell, spell), call(IsHelpfulSpell, spell)
  end
  if harm and not help then return "harm" end
  if help and not harm then return "help" end
  return nil
end

local function texture(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local t = call(C_Spell.GetSpellTexture, id)
    if t then return t end
  end
  return call(GetSpellTexture, id) or (I .. "INV_Misc_QuestionMark")
end

------------------------------------------------------------------------------------------------------ macros
local function limits()
  return tonumber(MAX_ACCOUNT_MACROS) or 120, tonumber(MAX_CHARACTER_MACROS) or 18
end

-- How many character macro slots are used, the most there can be, and how many are ours.
function SH.macroCount()
  local _, most = limits()
  local _, used = call(GetNumMacros)
  local ours = 0
  local acc = limits()
  for i = acc + 1, acc + (tonumber(used) or 0) do
    local _, _, body = call(GetMacroInfo, i)
    if L.parse(body) then ours = ours + 1 end
  end
  return tonumber(used) or 0, most, ours
end

-- This character's macros that TwizCrew wrote: { { index, name, body, p } } in index order.
local function ourMacros()
  local acc = limits()
  local _, used = call(GetNumMacros)
  local out = {}
  for i = acc + 1, acc + (tonumber(used) or 0) do
    local name, _, body = call(GetMacroInfo, i)
    local p = L.parse(body)
    if name and p then out[#out + 1] = { index = i, name = name, body = body, p = p } end
  end
  return out
end

-- What's on your bars (only read, never changed): plain spells and our macros. The window lists these spells first.
local function entries()
  local byName = {}
  for _, m in ipairs(ourMacros()) do byName[m.name] = byName[m.name] or m end
  local list = {}
  for slot = 1, rk().MAX_SLOT do
    if call(HasAction, slot) then
      local kind, id = call(GetActionInfo, slot)
      if kind == "spell" and id then
        list[#list + 1] = { slot = slot, spell = rk().spellName(id), rank = rk().spellRank(id), id = id }
      elseif kind == "macro" then
        -- id is the macro's number on most clients: when its name matches the slot's, its text decides (so your
        -- own macro called "Fireball" is never taken for ours); else the slot's macro name finds it
        local text = call(GetActionText, slot)
        local m
        local name, _, body = nil, nil, nil
        if id then name, _, body = call(GetMacroInfo, id) end
        if name and (text == nil or name == text) then
          local p = L.parse(body)
          if p then m = { index = id, name = name, body = body, p = p } end
        else
          m = byName[text or ""]
        end
        if m then
          list[#list + 1] = { slot = slot, spell = m.p.spell, rank = m.p.rank, ours = true, name = m.name, body = m.body }
        end
      end
    end
  end
  return list
end

-- This character's macro for a spell (the one to drag): its macro number, or nil.
function SH.macroFor(spell)
  for _, m in ipairs(ourMacros()) do
    if m.p.spell == spell then return m.index end
  end
  return nil
end

-- Puts a spell's macro on the cursor, as dragging it from the macro window would. You drop it on a bar yourself.
function SH.pickup(spell)
  if inCombat() then say("can't pick up a macro during a fight."); return false end
  local index = SH.macroFor(spell)
  if not index then return false end
  ClearCursor()
  call(PickupMacro, index)
  return true
end

-- Brings the macros in line with the choices; the bars are never touched. Returns how many macros changed.
local function doApply()
  local best = rk().bestRanks()
  local spells = {}
  for _, d in ipairs(SH.rows()) do spells[#spells + 1] = d.spell end
  local function plan()
    return L.macros(spells, ourMacros(), SH.choice,
      function(spell) return kindOf(spell, best[spell] and best[spell].id) end,
      function(spell) return best[spell] and best[spell].rank end)
  end
  local changed = 0
  -- delete first (frees slots), from the highest number down: deleting one moves the ones after it
  local _, _, drop = plan()
  for _, index in ipairs(drop) do call(DeleteMacro, index); changed = changed + 1 end
  -- then the rest, with the numbers read again; an edit keeps the name, so a macro on your bars stays there
  local edit, make = plan()
  for _, e in ipairs(edit) do call(EditMacro, e.index, e.name, L.ICON, e.body); changed = changed + 1 end
  local _, most = limits()
  local full = {}
  for _, m in ipairs(make) do
    local _, used = call(GetNumMacros)
    if (tonumber(used) or 0) < most then
      call(CreateMacro, m.name, L.ICON, m.body, true); changed = changed + 1
    else
      full[#full + 1] = m.spell
    end
  end
  local fresh = {}
  for _, s in ipairs(full) do if not warnedFull[s] then warnedFull[s] = true; fresh[#fresh + 1] = s end end
  if #fresh > 0 then
    say("no free macro slot on this character for smart target on " .. table.concat(fresh, ", ")
      .. ". Delete one of your macros, or turn smart target off for another spell (/tc spells).")
  end
  SH.lastFull = full
  return changed
end

-- Runs now when it can; in a fight (macros can't be changed then), after it.
function SH.apply()
  if not enabled or not rk() then return 0 end
  if inCombat() then pending = true; return 0 end
  local ok, n = ns.Log.safe(FEATURE, doApply)
  n = ok and tonumber(n) or 0
  if SH.refresh then SH.refresh() end
  return n
end

-- Soon (several changes in a row run once).
local function applySoon(delay)
  if applyQueued then return end
  applyQueued = true
  C_Timer.After(delay or 0.3, function() applyQueued = false; SH.apply() end)
end

-- Change one choice: key = "newest" | "smart" | "switch".
function SH.set(spell, key, value)
  if type(spell) ~= "string" or (key ~= "newest" and key ~= "smart" and key ~= "switch") then return end
  local t = mine()
  local c = type(t[spell]) == "table" and t[spell] or {}
  c[key] = value and true or false
  t[spell] = c
  if key == "smart" then warnedFull = {} end
  if SH.refresh then SH.refresh() end
  applySoon()
end

------------------------------------------------------------------------------------------------------ the list
-- Every spell you know, the ones on your bars first:
-- { spell, id (highest rank), rank, ranked (has ranks), kind, onBar }.
function SH.rows()
  if not rk() then return {} end
  local best = rk().bestRanks()
  local onBar = {}
  for _, e in ipairs(entries()) do onBar[e.spell] = true end
  local out = {}
  for spell, b in pairs(best) do
    out[#out + 1] = { spell = spell, id = b.id, rank = b.rank, ranked = b.rank ~= nil, kind = kindOf(spell, b.id),
      onBar = onBar[spell] or false }
  end
  table.sort(out, function(a, b)
    if a.onBar ~= b.onBar then return a.onBar end
    return a.spell < b.spell
  end)
  return out
end

------------------------------------------------------------------------------------------------------ window
local WIDTH, ROW_H, ROWS, PAD = 710, 30, 12, 14
local COL = { newest = 330, smart = 440, switch = 550, macro = 645 } -- the middle of each column
local LIST_TOP = 112
local frame, list, rowFrames, offset, focus = nil, nil, {}, 0, nil
local columnKeys = { "newest", "smart", "switch" }

local INFO = {
  newest = { "Newest rank", "On: this spell always uses the highest rank you know. The rank updater swaps old "
    .. "ranks on your bars for it, and a smart-target macro casts it by name (always the top rank).\n\nOff: it keeps "
    .. "the rank it has. Handy for a cheap Rank 1 heal, or a low rank you use to save mana.\n\nA dash: this spell has no ranks." },
  smart = { "Smart target", "On: TwizCrew makes a small macro for this spell (same icon, same tooltip). "
    .. "Drag its icon from the Macro column onto your bars, wherever you want it. TwizCrew never moves anything on "
    .. "your bars itself.\n\nHarmful spell, friend targeted: it hits what your friend is fighting. Example: target the tank, "
    .. "press Fireball, it hits the tank's target.\n\nHelpful spell, enemy targeted: it lands on whoever the enemy is "
    .. "attacking, or on you. Example: target the boss, press Flash Heal, it heals whoever the boss is hitting.\n\n"
    .. "Your target stays the same (see Switch target). Each spell uses one of this character's macro slots.\n\n"
    .. "A dash: the spell isn't aimed at anyone (stances, self-buffs), so there's nothing to redirect." },
  switch = { "Switch target", "Only matters with Smart target on.\n\nOn: whoever the spell goes to also becomes "
    .. "your target. Example: target the tank, press Fireball: now you're targeting the tank's enemy, so your next "
    .. "spells go there too.\n\nOff: you keep the target you had." },
  macros = { "Macro slots", "Smart target works through macros. Each spell with it on uses one of this character's "
    .. "macro slots (one more for each rank you keep). Turn it off and the macro is deleted, which also empties any "
    .. "bar slot it was in: drag the plain spell there from your spellbook.\n\nOnly macros TwizCrew wrote are ever changed or deleted: your own are never touched. The "
    .. "account-wide macro list isn't used." },
  macro = { "Macro", "With Smart target on, the spell's macro shows here. Drag it (or click it) and drop it on "
    .. "any bar slot, the same way you drag from the spellbook. Put it wherever you like: TwizCrew never moves it.\n\n"
    .. "It's also in the game's macro window (/macro, the character tab)." },
  notify = { "New spell pop-up", "When you learn a new spell or rank (at a trainer), a pop-up says what Newest "
    .. "rank and Smart target are set to for it, so you know to look. Click it to open this window at that spell." },
}

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function makeSwitch(parent, onClick)
  local sw = CreateFrame("Button", nil, parent)
  sw:SetSize(34, 18)
  sw.track = sw:CreateTexture(nil, "BACKGROUND")
  sw.track:SetAllPoints(sw)
  sw.knob = sw:CreateTexture(nil, "ARTWORK")
  sw.knob:SetSize(14, 14)
  function sw.Paint(on)
    sw.tcOn = on and true or false
    T.color(sw.track, on and C.switchOn or C.switchOff, 1)
    T.color(sw.knob, on and C.knobOn or C.knobOff, 1)
    sw.knob:ClearAllPoints()
    if on then sw.knob:SetPoint("RIGHT", sw, "RIGHT", -2, 0) else sw.knob:SetPoint("LEFT", sw, "LEFT", 2, 0) end
  end
  script(sw, "OnClick", onClick)
  sw.Paint(false)
  return sw
end

local function allSet(key, value)
  local t = mine()
  for _, d in ipairs(SH.rows()) do
    local fits = (key == "newest" and d.ranked) or (key ~= "newest" and d.kind)
    if fits then
      local c = type(t[d.spell]) == "table" and t[d.spell] or {}
      c[key] = value
      t[d.spell] = c
    end
  end
  if key == "smart" then warnedFull = {} end
  SH.refresh()
  applySoon()
end

local function build()
  frame = T.frame("Frame", "TwizCrewSpellHelpers", UIParent)
  frame:SetSize(WIDTH, LIST_TOP + ROWS * ROW_H + 64)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  script(frame, "OnDragStart", function(self) self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  script(frame, "OnHide", function() SH.shownFlag = false end)
  T.paint(frame, C.backdrop, 0.97, C.title, 2)
  T.gloss(frame, nil, 0.05, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewSpellHelpers") end
  local logo = frame:CreateTexture(nil, "ARTWORK")
  logo:SetSize(T.icon(26), T.icon(26))
  logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
  logo:SetTexture(ICON_MAIN)
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local title = T.readable(T.text(frame, T.FONT.normal, C.title), 3)
  title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  title:SetText("Spell helpers")
  local close = Widgets.button(frame, "Close", function() frame:Hide(); SH.shownFlag = false end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
  local intro = T.text(frame, T.FONT.small, C.muted)
  intro:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -44)
  intro:SetWidth(WIDTH - 2 * PAD)
  intro:SetJustifyH("LEFT")
  intro:SetText("Spell by spell: always the newest rank, and smart targeting. Turn on Smart target, then drag the "
    .. "spell's macro (Macro column) onto your bars. Hover the (i) for what each one does.")
  frame.combat = T.text(frame, T.FONT.small, "ff8040")
  frame.combat:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
  -- column headings: the name, its (i), and all on / all off
  for _, key in ipairs(columnKeys) do
    local x = COL[key]
    local h = T.text(frame, T.FONT.normal, C.title)
    h:SetPoint("TOP", frame, "TOPLEFT", PAD + x - 8, -70)
    h:SetText(INFO[key][1])
    local info = Widgets.infoButton(frame, INFO[key][1], INFO[key][2])
    info:SetPoint("LEFT", h, "RIGHT", 2, 0)
    local on = Widgets.button(frame, "all on", function() allSet(key, true) end, nil, FEATURE)
    on:SetSize(46, 16)
    on:SetPoint("TOPRIGHT", frame, "TOPLEFT", PAD + x - 1, -88)
    local off = Widgets.button(frame, "all off", function() allSet(key, false) end, nil, FEATURE)
    off:SetSize(46, 16)
    off:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + x + 1, -88)
  end
  local mh = T.text(frame, T.FONT.normal, C.title)
  mh:SetPoint("TOP", frame, "TOPLEFT", PAD + COL.macro - 8, -70)
  mh:SetText(INFO.macro[1])
  local minfo = Widgets.infoButton(frame, INFO.macro[1], INFO.macro[2])
  minfo:SetPoint("LEFT", mh, "RIGHT", 2, 0)
  local sh = T.text(frame, T.FONT.normal, C.title)
  sh:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 30, -70)
  sh:SetText("Spell")
  -- the list (the mouse wheel scrolls)
  list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -LIST_TOP)
  list:SetSize(WIDTH - 2 * PAD, ROWS * ROW_H)
  list:EnableMouseWheel(true)
  script(list, "OnMouseWheel", function(_, delta) SH.scroll(-(tonumber(delta) or 0) * 3) end)
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, list)
    r:SetSize(WIDTH - 2 * PAD, ROW_H - 2)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r.back = r:CreateTexture(nil, "BACKGROUND")
    r.back:SetAllPoints(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(T.icon(22), T.icon(22))
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = T.readable(T.text(r, T.FONT.small, C.text))
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetWidth(COL.newest - 70)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.tip = CreateFrame("Frame", nil, r) -- hover the spell: its tooltip
    r.tip:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.tip:SetSize(COL.newest - 30, ROW_H - 2)
    r.tip:EnableMouse(true)
    script(r.tip, "OnEnter", function(self)
      local d = r.tcData
      if not GameTooltip or not d then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetSpellByID and d.id then GameTooltip:SetSpellByID(d.id) else GameTooltip:SetText(d.spell) end
      if not d.onBar then GameTooltip:AddLine("Not on your bars.", 0.7, 0.7, 0.7, true) end
      GameTooltip:Show()
    end)
    script(r.tip, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.sw, r.dash = {}, {}
    for _, key in ipairs(columnKeys) do
      local sw = makeSwitch(r, function()
        local d = r.tcData
        if d then SH.set(d.spell, key, not SH.choice(d.spell)[key]) end
      end)
      sw:SetPoint("CENTER", r, "LEFT", COL[key], 0)
      r.sw[key] = sw
      local dash = T.text(r, T.FONT.normal, C.muted)
      dash:SetPoint("CENTER", r, "LEFT", COL[key], 0)
      dash:SetText("-")
      r.dash[key] = dash
    end
    -- the macro to drag onto your bars (shown when smart target is on and the macro exists)
    local mb = CreateFrame("Button", nil, r)
    mb:SetSize(T.icon(24), T.icon(24))
    mb:SetPoint("CENTER", r, "LEFT", COL.macro, 0)
    mb.icon = mb:CreateTexture(nil, "ARTWORK")
    mb.icon:SetAllPoints(mb)
    mb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if mb.RegisterForDrag then mb:RegisterForDrag("LeftButton") end
    local function grab() local d = r.tcData; if d then SH.pickup(d.spell) end end
    script(mb, "OnDragStart", grab)
    script(mb, "OnClick", grab)
    script(mb, "OnEnter", function(self)
      local d = r.tcData
      if not GameTooltip or not d then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Smart target: " .. ns.Util.safeText(d.spell))
      GameTooltip:AddLine("Drag onto your bars, wherever you want it.", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    script(mb, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.macro = mb
    r.macroDash = T.text(r, T.FONT.normal, C.muted)
    r.macroDash:SetPoint("CENTER", r, "LEFT", COL.macro, 0)
    r.macroDash:SetText("-")
    rowFrames[i] = r
  end
  frame.more = T.text(frame, T.FONT.small, C.muted)
  frame.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -4)
  -- the footer: macro slots, the new-spell pop-up
  local fy = -(LIST_TOP + ROWS * ROW_H + 26)
  frame.macros = T.text(frame, T.FONT.small, C.text)
  frame.macros:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, fy)
  local mi = Widgets.infoButton(frame, INFO.macros[1], INFO.macros[2])
  mi:SetPoint("LEFT", frame.macros, "RIGHT", 2, 0)
  local nsw = makeSwitch(frame, function()
    ns.Modules.set(FEATURE, "notify", not setting("notify"))
    SH.refresh()
  end)
  nsw:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, fy + 2)
  frame.notifySwitch = nsw
  local ni = Widgets.infoButton(frame, INFO.notify[1], INFO.notify[2])
  ni:SetPoint("LEFT", nsw, "RIGHT", 2, 0)
  local nl = T.text(frame, T.FONT.small, C.text)
  nl:SetPoint("RIGHT", nsw, "LEFT", -6, 0)
  nl:SetText("Pop-up when I learn a spell")
end

function SH.scroll(n)
  local rows = SH.lastRows or {}
  local top = math.max(0, #rows - ROWS)
  offset = math.max(0, math.min(top, offset + (tonumber(n) or 0)))
  SH.refresh()
end

function SH.refresh()
  if not frame or not frame:IsShown() and not SH.shownFlag then return end
  local rows = SH.rows()
  SH.lastRows = rows
  offset = math.max(0, math.min(offset, #rows - ROWS))
  local macros = {}
  for _, m in ipairs(ourMacros()) do macros[m.p.spell] = macros[m.p.spell] or m.index end
  for i, r in ipairs(rowFrames) do
    local d = rows[offset + i]
    r.tcData = d
    if d then
      local c = SH.choice(d.spell)
      r.icon:SetTexture(texture(d.id))
      r.name:SetText((d.onBar and "" or "|cff8a8a8a") .. ns.Util.safeText(d.spell) .. (d.onBar and "" or "|r")
        .. (d.rank and ("  |cff999999Rank " .. d.rank .. "|r") or ""))
      T.color(r.back, d.spell == focus and C.title or C.row, d.spell == focus and 0.25 or (i % 2 == 0 and 0.35 or 0.15))
      for _, key in ipairs(columnKeys) do
        local fits = (key == "newest" and d.ranked) or (key ~= "newest" and d.kind ~= nil)
        if fits then
          r.sw[key].Paint(c[key])
          r.sw[key]:SetAlpha((key == "switch" and not c.smart) and 0.4 or 1)
          r.sw[key]:Show(); r.dash[key]:Hide()
        else
          r.sw[key]:Hide(); r.dash[key]:Show()
        end
      end
      local has = c.smart and d.kind ~= nil and macros[d.spell]
      if has then
        r.macro.icon:SetTexture(texture(d.id))
        r.macro:Show(); r.macroDash:Hide()
      else
        r.macro:Hide(); r.macroDash:Show()
      end
      r:Show()
    else
      r:Hide()
    end
  end
  frame.more:SetText(#rows > ROWS and string.format("%d-%d of %d, scroll for more", offset + 1,
    math.min(#rows, offset + ROWS), #rows) or "")
  local used, most, ours = SH.macroCount()
  frame.macros:SetText(string.format("Macro slots on this character: %d of %d used (%d by TwizCrew)", used, most, ours))
  frame.notifySwitch.Paint(setting("notify"))
  frame.combat:SetText(pending and "In a fight: your changes happen when it ends." or "")
end

-- Opens the window; spell: scroll to it and light it up.
function SH.open(spell)
  if not frame then build() end
  SH.shownFlag = true
  focus = type(spell) == "string" and spell or nil
  frame:Show()
  SH.refresh()
  if focus then
    for i, d in ipairs(SH.lastRows or {}) do
      if d.spell == focus then offset = math.max(0, i - 3); break end
    end
    SH.refresh()
  end
end

function SH.toggle()
  if frame and frame:IsShown() then frame:Hide(); SH.shownFlag = false else SH.open() end
end

function SH.isShown() return frame ~= nil and SH.shownFlag == true end
function SH.rowForTest(i) local r = rowFrames[i]; return r and r.tcData end
function SH.switchForTest(i, key) local r = rowFrames[i]; return r and r.sw[key] end
function SH.macroButtonForTest(i) local r = rowFrames[i]; return r and r.macro end

------------------------------------------------------------------------------------------------------ learning
-- A new spell or rank: a pop-up with how it's set (click = this window at that spell).
function SH.learned(id)
  if not enabled or not setting("notify") or not id or not ns.Popups or not ns.Popups.notice then return end
  local spell = rk() and rk().spellName(id)
  if type(spell) ~= "string" then return end
  if call(IsPassiveSpell, id) then return end
  local rank = rk().spellRank(id)
  local c = SH.choice(spell)
  local parts = {}
  if rank then parts[#parts + 1] = "Newest rank: " .. (c.newest and "on" or "off") end
  if kindOf(spell, id) then parts[#parts + 1] = "Smart target: " .. (c.smart and "on" or "off") end
  if #parts == 0 then return end -- nothing to choose for it
  local title = (rank and rank > 1 and "New rank: " or "New spell: ") .. spell .. (rank and (" (Rank " .. rank .. ")") or "")
  SH.lastNotice = title
  ns.Popups.notice(texture(id), title, table.concat(parts, ", ") .. "  -  click to choose", function() SH.open(spell) end)
end

------------------------------------------------------------------------------------------------------ module
local function onEnable()
  enabled = true
  if not learnFrame then
    learnFrame = CreateFrame("Frame")
    for _, e in ipairs({ "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
      pcall(learnFrame.RegisterEvent, learnFrame, e)
    end
    script(learnFrame, "OnEvent", function(_, _, id)
      if not enabled then return end
      -- the spellbook updates a moment after the event
      C_Timer.After(1, function()
        ns.Log.safe(FEATURE, SH.learned, tonumber(id))
        SH.apply()
      end)
    end)
  end
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function()
    if pending then pending = false; SH.apply() end
  end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() applySoon(3) end)
  applySoon(3)
end

local function onDisable()
  enabled = false
  pending = false
  if frame then frame:Hide(); SH.shownFlag = false end
end

ns.Modules.register({
  id = FEATURE, name = "Spell helpers", tier = "extra",
  info = "Spell by spell: always the newest rank, and smart targeting (a harmful spell at a friend hits the "
    .. "friend's target, a helpful one at an enemy lands on the enemy's target). Also: the wrench button on the crew "
    .. "panel, /tc spells.",
  defaults = { notify = true },
  settings = {
    { key = "open", label = "Open spell helpers", kind = "button", onClick = function() SH.open() end,
      info = "The window with every spell you know and its switches: Newest rank, Smart target, Switch target." },
    { key = "notify", label = "Pop-up when I learn a spell", kind = "toggle", info = INFO.notify[2] },
  },
  onEnable = onEnable,
  onDisable = onDisable,
  onSettingChanged = function() if SH.refresh then SH.refresh() end end,
})
