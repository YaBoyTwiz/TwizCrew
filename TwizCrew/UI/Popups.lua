-- Small pop-ups near the top centre for layer changes, deaths, friends' level-ups and friends coming online
-- (module "popups").
-- Rules about what shows and when live in PopupLogic; this file only owns the frames.
-- When more than POPUP_MAX pop-ups are due at once, the oldest visible one is replaced (nothing is queued).
-- Roasts (Popups.showRoast, called by the roasts module) use the same frames and work even while this module is off.
local _, ns = ...

local FEATURE = "popups"
local T = ns.Theme
local C = T.COLOR
local Widgets = ns.Widgets
local TICK, FADE = 0.5, 0.5
local WIDTH, HEIGHT, GAP, TOP = 270, 50, 4, -120
local ROAST_WIDTH = 360 -- roast lines are longer; the title wraps onto a second line when needed
local EDGE = { layer_diff = "b3261e", layer_same = "3fd34a", death = "888888", roast = "c46a00", levelup = "ffd100",
  meet = "3fa9f5", online = "33cc66", qshare = "f0c040", runaway = "ff3030", notice = "8a6cff" }
local QSHARE_SECONDS = 20 -- a quest share request stays this long (it needs a click)
local RELOG = 120 -- seconds: back online sooner than this (a /reload, a quick relog) is not news
local KIND_ICON = {
  layer_diff = "Interface\\Icons\\Spell_Arcane_Blink", layer_same = "Interface\\Icons\\Spell_Arcane_Blink",
  death = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", roast = "Interface\\Icons\\Spell_Fire_Fire",
  levelup = "Interface\\Icons\\Spell_Holy_PowerInfusion", meet = "Interface\\Icons\\INV_Misc_Map_01",
  online = "Interface\\Icons\\Ability_Warrior_BattleShout", qshare = "Interface\\Icons\\Spell_ChargePositive",
  runaway = "Interface\\Icons\\Ability_Rogue_Sprint",
}
local LEVEL_UP_SOUND = 888 -- the game's own level-up sound (LEVELUPSOUND), when SOUNDKIT has no name for it

local logic          -- PopupLogic instance (nil while the module is off)
local ticker
local pool = {}      -- frames, created on first use, then reused
local seq = 0        -- shows counted, so "oldest" is well defined even within one tick
local quietUntil     -- set once, the first time the module is enabled in this session
local quietDone = false
-- Per friend, so the same news is not shown twice: the last layer pop-up shown ("different" / "same"), and
-- whether they were seen on our layer since the last "different" one. Forgotten when they go offline.
local announced, sameSince = {}, {}
local offlineAt = {} -- name -> when they went offline this session (a quick /reload gets no "online" pop-up)
local history = {}   -- texts of the last pop-ups shown (test hook)

local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function colorName(name)
  local safe = ns.Util.safeText(tostring(name))
  local m = ns.roster and ns.roster:get(name)
  if m and type(m.class) == "string" then
    local r, g, b = T.classColor(m.class)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
      math.floor(b * 255 + 0.5), safe)
  end
  return safe
end

local function visibleFrames()
  local list = {}
  for _, f in ipairs(pool) do if f.tcShown then list[#list + 1] = f end end
  table.sort(list, function(a, b) return a.tcSeq < b.tcSeq end)
  return list
end

local function layout()
  for i, f in ipairs(visibleFrames()) do
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, TOP - (i - 1) * (HEIGHT + GAP))
  end
end

local function close(f)
  f.tcShown = false
  f.tcPopup = nil
  f:Hide()
  layout()
end

local function invite(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then
    C_PartyInfo.InviteUnit(name)
  elseif type(InviteUnit) == "function" then
    InviteUnit(name)
  else
    ns.Log.add("warn", "invite: no way to invite %s in this game version", tostring(name))
  end
end

local function inGroup(name)
  if type(UnitInParty) == "function" and UnitInParty(name) then return true end
  if type(UnitInRaid) == "function" and UnitInRaid(name) then return true end
  return false
end

-- Runs on a real click only (an invite needs a hardware event); never called from a timer.
local function click(f)
  local p = f.tcPopup
  if not p then return end
  if p.kind == "layer_diff" and p.invite then
    for _, name in ipairs(p.invite) do
      if not inGroup(name) and not ns.isTestName(name) then invite(name) end -- a fake (test tools) is never invited
    end
  elseif p.kind == "notice" and type(p.onClick) == "function" then
    ns.Log.safe("popups", p.onClick)
  elseif p.kind == "runaway" and ns.BigArrow and not ns.isTestName(p.names[1]) then
    ns.BigArrow.point({ kind = "member", name = p.names[1] })
  elseif p.kind == "meet" and ns.Find and ns.Find.pointToMeet then
    ns.Find.pointToMeet()
  elseif p.kind == "qshare" and ns.Quest and ns.Quest.shareFor then
    ns.Quest.shareFor(p.names[1], p.title)
  elseif p.kind == "levelup" and ns.Roasts and ns.Roasts.canCheer and not ns.isTestName(p.names[1]) then
    ns.Roasts.cheer(p.names[1])
  elseif p.kind == "online" and #p.names == 1 and not ns.isTestName(p.names[1]) then
    local name = p.names[1]
    if type(ChatFrame_SendTell) == "function" then
      ChatFrame_SendTell(name)
    elseif type(ChatFrame_OpenChat) == "function" then
      ChatFrame_OpenChat("/w " .. name .. " ")
    end
  end
  close(f)
end

local function newFrame()
  local f = T.frame("Button", nil, UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  T.paint(f, C.backdrop, 0.92, C.rowBorder)
  f.edge = f:CreateTexture(nil, "ARTWORK")
  f.edge:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.edge:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  f.edge:SetWidth(4)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(T.icon(28), T.icon(28))
  f.icon:SetPoint("LEFT", f, "LEFT", 10, 0)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.title = T.text(f, T.FONT.normal, C.text)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + T.icon(28), -8)
  f.title:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.title:SetJustifyH("LEFT")
  f.sub = T.text(f, T.FONT.small, C.muted)
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.sub:SetJustifyH("LEFT")
  Widgets.script(f, "OnClick", function(self) click(self) end, FEATURE)
  -- Only the fade is smooth; showing and hiding is decided by the ticker. A roast closes itself here once its
  -- time is over, so it also goes away while this module (and its ticker) is off.
  Widgets.script(f, "OnUpdate", function(self)
    if not self.tcShown then return end
    local left = self.tcExpires - ns.now()
    local own = self.tcPopup and (self.tcPopup.kind == "roast" or self.tcPopup.kind == "qshare")
    if left <= 0 and own then close(self); return end
    self:SetAlpha(left >= FADE and 1 or math.max(0, left / FADE))
  end, FEATURE)
  pool[#pool + 1] = f
  return f
end

-- A free frame, else a new one while under POPUP_MAX, else the oldest visible one (replaced).
local function takeFrame()
  for _, f in ipairs(pool) do if not f.tcShown then return f end end
  if #pool < ns.Config.POPUP_MAX then return newFrame() end
  return visibleFrames()[1]
end

-- Kept without colour codes; an escaped "||" (a "|" in a name) stays as it is.
local function remember(text)
  history[#history + 1] = (text:gsub("||", "\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\1", "||"))
  if #history > 20 then table.remove(history, 1) end
end

-- Under "Frostie is online": "Level 12 Mage in Elwynn Forest"; for several friends, their names.
local function className(token)
  if type(token) ~= "string" or token == "" then return nil end
  local t = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[token]
  if type(t) == "string" then return t end
  return token:sub(1, 1) .. token:sub(2):lower()
end

local function onlineDetail(names)
  if #names > 2 then
    local list = {}
    for i, n in ipairs(names) do list[i] = ns.Util.safeText(tostring(n)) end
    return table.concat(list, ", ")
  end
  local m = ns.roster and ns.roster:get(names[1])
  if not m then return nil end
  local parts = {}
  if tonumber(m.level) then parts[#parts + 1] = "Level " .. math.floor(tonumber(m.level)) end
  local cls = className(m.class)
  if cls then parts[#parts + 1] = cls end
  local text = table.concat(parts, " ")
  if type(m.zone) == "string" and m.zone ~= "" then
    text = (text ~= "" and (text .. " in ") or "") .. ns.Util.safeText(m.zone)
  end
  if text == "" then return "Click to whisper them" end
  return text
end

local function show(p)
  local f = takeFrame()
  local names = {}
  for i, n in ipairs(p.names) do names[i] = n end
  local extra = { zone = p.extra.zone and ns.Util.safeText(p.extra.zone),
    subzone = p.extra.subzone and ns.Util.safeText(p.extra.subzone),
    level = p.extra.level, maxLevel = p.extra.maxLevel }
  if p.kind == "online" then extra.detail = onlineDetail(names) end
  local text, sub = ns.PopupLogic.text(p.kind, names, extra, colorName)
  seq = seq + 1
  remember(text)
  f:SetWidth(WIDTH)
  f.tcSeq, f.tcShown, f.tcPopup = seq, true, p
  f.tcText, f.tcSub = text, sub or false
  f.tcExpires = ns.now() + (tonumber(setting("seconds")) or 5) + FADE
  T.color(f.edge, EDGE[p.kind] or EDGE.death, 1)
  f.icon:SetTexture(KIND_ICON[p.kind] or KIND_ICON.death)
  f.title:SetText(text)
  f.sub:SetText(sub or "")
  f:SetAlpha(1)
  f:Show()
end

local function differentNames()
  local out = {}
  if not ns.roster or not ns.Layer then return out end
  for _, name in ipairs(ns.roster:names()) do
    if ns.Layer.relationOf(name) == "different" then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- "Different" was already shown for them and they have not been on our layer since: nothing new to say.
local function alreadyAnnounced(name)
  return announced[name] == "different" and not sameSince[name]
end

local function relation(name)
  return ns.Layer and ns.Layer.relationOf(name) or "unknown"
end

-- Just before a layer pop-up shows: keep only the names it is still true for (their relation may have changed
-- while the pop-up waited) and that are news. Returns nil when nobody is left.
local WANT = { layer_diff = "different", layer_same = "same" }
local function stillTrue(p)
  if p.kind == "online" then -- only the ones still online
    local names = {}
    for _, name in ipairs(p.names) do
      local m = ns.roster and ns.roster:get(name)
      if m and m.online then names[#names + 1] = name end
    end
    if #names == 0 then return nil end
    return { kind = "online", names = names, extra = p.extra or {} }
  end
  local want = WANT[p.kind]
  if not want then return p end
  local names = {}
  for _, name in ipairs(p.names) do
    if relation(name) == want and not (want == "different" and alreadyAnnounced(name)) then
      names[#names + 1] = name
    end
  end
  if #names == 0 then return nil end
  for _, name in ipairs(names) do
    announced[name] = want
    if want == "different" then sameSince[name] = false end
  end
  local out = { kind = p.kind, names = names, extra = p.extra or {} }
  if p.invite then out.invite = names end
  return out
end

local function tick()
  if not logic then return end
  local now = ns.now()
  for _, f in ipairs(visibleFrames()) do
    if now >= f.tcExpires then close(f) end
  end
  local due = logic:due(now)
  if not quietDone and now >= quietUntil then
    quietDone = true
    if setting("layerDiff") then
      local summary = logic:endQuiet(differentNames())
      if summary then due[#due + 1] = summary end
    end
  end
  local shown, dings = 0, 0
  for _, p in ipairs(due) do
    p = stillTrue(p)
    if p then
      show(p)
      if p.kind == "levelup" then dings = dings + 1 else shown = shown + 1 end
    end
  end
  layout()
  -- A ding plays only its own sound (its own switch), so the two never stack.
  if shown > 0 and setting("sound") and type(PlaySound) == "function" and SOUNDKIT then
    ns.Log.safe(FEATURE, PlaySound, SOUNDKIT.RAID_WARNING)
  end
  if dings > 0 and setting("levelUpSound") and type(PlaySound) == "function" then
    local kit = type(SOUNDKIT) == "table" and (SOUNDKIT.LEVELUP or SOUNDKIT.LEVEL_UP) or nil
    ns.Log.safe(FEATURE, PlaySound, kit or LEVEL_UP_SOUND)
  end
end

-- Test tools: a fake's pop-up shows only when a test button expects it (or for "My copy"), and then even in the
-- login quiet time. Returns whether to push, and whether to force it past the quiet time.
local function gate(kind, name)
  if not ns.isTestName(name) then return true, false end
  local wanted = ns.TestTools ~= nil and ns.TestTools.wants(kind, name) and true or false
  return wanted, wanted
end

local function push(kind, name, extra)
  local ok, force = gate(kind, name)
  if ok then logic:push(kind, name, ns.now(), extra, force) end
end

local function onRelation(name, old, new)
  if new == "different" and old ~= "different" then
    if setting("layerDiff") and not alreadyAnnounced(name) then push("layer_diff", name) end
  elseif new == "same" then
    local wasAway = old == "different" or announced[name] == "different"
    sameSince[name] = true
    if wasAway and setting("layerSame") then push("layer_same", name) end
  end
end

local function onOffline(name)
  announced[name], sameSince[name] = nil, nil
  offlineAt[name] = ns.now()
  if logic then logic:cancel("online", name) end
end

-- A friend started playing (or came back after a while). Not for a quick /reload or relog.
local function onOnline(name)
  if not setting("online") then return end
  local gone = offlineAt[name]
  offlineAt[name] = nil
  if gone and ns.now() - gone < RELOG then return end
  push("online", name)
end

local function onDied(name, zone, subzone)
  if setting("death") then push("death", name, { zone = zone, subzone = subzone }) end
end

-- A friend went up one level while we both were online (Roster decides; never our own level-up).
local function onLevelUp(name, level)
  if setting("levelUp") then
    push("levelup", name, { level = level, maxLevel = ns.maxLevel() })
  end
end

local function hideAll()
  for _, f in ipairs(pool) do
    f.tcShown, f.tcPopup = false, nil
    f:Hide()
  end
end

local function onEnable()
  if not quietUntil then quietUntil = ns.now() + ns.Config.LOGIN_QUIET end
  logic = ns.PopupLogic.new({ combineWindow = ns.Config.POPUP_COMBINE_WINDOW, quietUntil = quietUntil })
  ns.Bus.on(FEATURE, "LAYER_RELATION", onRelation)
  ns.Bus.on(FEATURE, "MEMBER_DIED", onDied)
  ns.Bus.on(FEATURE, "MEMBER_LEVELUP", onLevelUp)
  ns.Bus.on(FEATURE, "MEMBER_OFFLINE", onOffline)
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", onOnline)
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(TICK, function() ns.Log.safe(FEATURE, tick) end)
  end
end

local function onDisable()
  if ticker and ticker.Cancel then ticker:Cancel() end
  ticker = nil
  logic = nil   -- pending pop-ups are dropped
  hideAll()
end

ns.Modules.register({
  id = FEATURE, name = "Pop-ups", tier = "module",
  info = "Small messages near the top of the screen when a friend comes online, changes layer, dies or reaches a "
    .. "new level. They are short and never pile up.",
  defaults = { online = true, layerDiff = true, layerSame = true, death = true, levelUp = true, levelUpSound = false,
    sound = false, seconds = 5 },
  settings = {
    { key = "online", label = "Friends coming online", kind = "toggle",
      info = "Shows a pop-up like \"Frostie is online: Level 12 Mage in Elwynn Forest\" when a friend starts "
        .. "playing. Several at once share one pop-up. Not when you log in yourself, and not when a friend just did "
        .. "a /reload. Click it to whisper them." },
    { key = "layerDiff", label = "Layer changes", kind = "toggle",
      info = "Shows a pop-up when a friend ends up on a different layer than you. Click it to invite them." },
    { key = "layerSame", label = "Back on my layer", kind = "toggle",
      info = "Shows a pop-up when a friend who was on a different layer is back on yours." },
    { key = "death", label = "Deaths", kind = "toggle",
      info = "Shows a pop-up with the place when a friend dies." },
    { key = "levelUp", label = "Level-ups", kind = "toggle",
      info = "Shows a pop-up like \"Frostie reached level 13!\" when a friend levels up while you are both "
        .. "online. Never for your own level-up (the game shows that), and never for levels gained while you "
        .. "were offline." },
    { key = "levelUpSound", label = "Level-up sound", kind = "toggle", parent = "levelUp",
      info = "Plays the game's level-up sound with a friend's level-up pop-up. Off by default so streams stay "
        .. "quiet." },
    { key = "sound", label = "Play a sound", kind = "toggle",
      info = "Plays a short sound when pop-ups appear. Off by default so streams stay quiet." },
    { key = "seconds", label = "How long they stay", kind = "slider", min = 2, max = 15, step = 1,
      info = "How many seconds a pop-up stays on screen before it fades away." },
  },
  onEnable = onEnable,
  onDisable = onDisable,
})

local Popups = {}
ns.Popups = Popups

-- Shows one roast line (already safe plain text) for `seconds` plus the fade, whether or not this module is on.
-- Clicking it closes it.
function Popups.showRoast(text, seconds)
  if type(text) ~= "string" or text == "" then return end
  local f = takeFrame()
  seq = seq + 1
  remember(text)
  f.tcSeq, f.tcShown, f.tcPopup = seq, true, { kind = "roast" }
  f.tcText, f.tcSub = text, false
  f.tcExpires = ns.now() + (tonumber(seconds) or ns.Config.ROAST_SECONDS) + FADE
  f:SetWidth(ROAST_WIDTH)
  T.color(f.edge, EDGE.roast, 1)
  f.icon:SetTexture(KIND_ICON.roast)
  f.title:SetText(text)
  f.sub:SetText("")
  f:SetAlpha(1)
  f:Show()
  layout()
end

-- A friend asks you to share a quest: "<Name> asks you to share a quest", the title, click = share it. Shows whether
-- or not the pop-ups module is on (it's a direct request that needs your click), and closes itself.
function Popups.questRequest(name, title)
  if type(name) ~= "string" or type(title) ~= "string" then return end
  local f = takeFrame()
  seq = seq + 1
  local text = colorName(name) .. " asks you to share a quest"
  remember(text)
  f.tcSeq, f.tcShown, f.tcPopup = seq, true, { kind = "qshare", names = { name }, title = title, extra = {} }
  f.tcText, f.tcSub = text, ns.Util.safeText(title) .. "  -  click to share it"
  f.tcExpires = ns.now() + QSHARE_SECONDS + FADE
  f:SetWidth(ROAST_WIDTH)
  T.color(f.edge, EDGE.qshare, 1)
  f.icon:SetTexture(KIND_ICON.qshare)
  f.title:SetText(f.tcText)
  f.sub:SetText(f.tcSub)
  f:SetAlpha(1)
  f:Show()
  layout()
  if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.IG_QUEST_LIST_OPEN then
    pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN)
  end
end

-- A notice from one of our own tools (e.g. Spell helpers: "New spell: ..."): icon, title, the line under it, what a
-- click does. Shows whether or not the pop-ups module is on, and closes itself after `seconds` (12).
function Popups.notice(icon, title, sub, onClick, seconds)
  if type(title) ~= "string" then return end
  local f = takeFrame()
  seq = seq + 1
  remember(title)
  f.tcSeq, f.tcShown, f.tcPopup = seq, true, { kind = "notice", names = {}, extra = {}, onClick = onClick }
  f.tcText, f.tcSub = title, sub or false
  f.tcExpires = ns.now() + (tonumber(seconds) or 12) + FADE
  f:SetWidth(ROAST_WIDTH)
  T.color(f.edge, EDGE.notice, 1)
  f.icon:SetTexture(icon or KIND_ICON.levelup)
  f.title:SetText(title)
  f.sub:SetText(sub or "")
  f:SetAlpha(1)
  f:Show()
  layout()
end

-- A group member ran off (Find the crew): "<Name> is running off!", how far, click = the big arrow. Shown at the
-- next tick even in the login quiet time; needs this module on.
function Popups.runaway(name, distText)
  if not logic or type(name) ~= "string" then return end
  logic:push("runaway", name, ns.now(), { zone = distText }, true)
end

-- A friend's meet-up (Find the crew): "<Name> wants to meet up", the place, click = the big arrow. Shown at the next
-- tick even in the login quiet time (a meet-up is worth it); needs this module on, like the other pop-ups.
function Popups.meet(name, place)
  if not logic or type(name) ~= "string" then return end
  logic:push("meet", name, ns.now(), { zone = type(place) == "string" and place or nil }, true)
end

-- Test hooks.
function Popups.visibleCount() return #visibleFrames() end

function Popups.clickForTest(i)
  local f = visibleFrames()[i]
  if f then click(f) end
end

local function plain(s)
  if not s or s == false then return nil end
  s = s:gsub("||", "\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\1", "||")
  return s
end

-- Texts of the last pop-ups shown (at most 20), oldest first, without colour codes.
function Popups.shownForTest() return history end

-- Visible pop-ups, oldest first, with the colour codes taken out.
function Popups.textsForTest()
  local out = {}
  for i, f in ipairs(visibleFrames()) do out[i] = { text = plain(f.tcText), subtext = plain(f.tcSub) } end
  return out
end
