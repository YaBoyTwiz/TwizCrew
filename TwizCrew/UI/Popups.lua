-- Small pop-ups near the top centre for layer changes and deaths (module "popups").
-- Rules about what shows and when live in PopupLogic; this file only owns the frames.
-- When more than POPUP_MAX pop-ups are due at once, the oldest visible one is replaced (nothing is queued).
local _, ns = ...

local FEATURE = "popups"
local T = ns.Theme
local C = T.COLOR
local Widgets = ns.Widgets
local TICK, FADE = 0.5, 0.5
local WIDTH, HEIGHT, GAP, TOP = 260, 44, 4, -120
local EDGE = { layer_diff = "b3261e", layer_same = "3fd34a", death = "888888" }

local logic          -- PopupLogic instance (nil while the module is off)
local ticker
local pool = {}      -- frames, created on first use, then reused
local seq = 0        -- shows counted, so "oldest" is well defined even within one tick
local quietUntil     -- set once, the first time the module is enabled in this session
local quietDone = false
-- Per friend, so the same news is not shown twice: the last layer pop-up shown ("different" / "same"), and
-- whether they were seen on our layer since the last "different" one. Forgotten when they go offline.
local announced, sameSince = {}, {}
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
      if not inGroup(name) then invite(name) end
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
  f.title = T.text(f, T.FONT.normal, C.text)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -7)
  f.title:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.title:SetJustifyH("LEFT")
  f.sub = T.text(f, T.FONT.small, C.muted)
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.sub:SetJustifyH("LEFT")
  Widgets.script(f, "OnClick", function(self) click(self) end, FEATURE)
  -- Only the fade is smooth; showing and hiding is decided by the ticker.
  Widgets.script(f, "OnUpdate", function(self)
    if not self.tcShown then return end
    local left = self.tcExpires - ns.now()
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

local function show(p)
  local f = takeFrame()
  local names = {}
  for i, n in ipairs(p.names) do names[i] = n end
  local extra = { zone = p.extra.zone and ns.Util.safeText(p.extra.zone),
    subzone = p.extra.subzone and ns.Util.safeText(p.extra.subzone) }
  local text, sub = ns.PopupLogic.text(p.kind, names, extra, colorName)
  seq = seq + 1
  history[#history + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  if #history > 20 then table.remove(history, 1) end
  f.tcSeq, f.tcShown, f.tcPopup = seq, true, p
  f.tcText, f.tcSub = text, sub or false
  f.tcExpires = ns.now() + (tonumber(setting("seconds")) or 5) + FADE
  T.color(f.edge, EDGE[p.kind] or EDGE.death, 1)
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
  local shown = 0
  for _, p in ipairs(due) do
    p = stillTrue(p)
    if p then show(p); shown = shown + 1 end
  end
  layout()
  if shown > 0 and setting("sound") and type(PlaySound) == "function" and SOUNDKIT then
    ns.Log.safe(FEATURE, PlaySound, SOUNDKIT.RAID_WARNING)
  end
end

local function onRelation(name, old, new)
  if new == "different" and old ~= "different" then
    if setting("layerDiff") and not alreadyAnnounced(name) then logic:push("layer_diff", name, ns.now()) end
  elseif new == "same" then
    local wasAway = old == "different" or announced[name] == "different"
    sameSince[name] = true
    if wasAway and setting("layerSame") then logic:push("layer_same", name, ns.now()) end
  end
end

local function onOffline(name)
  announced[name], sameSince[name] = nil, nil
end

local function onDied(name, zone, subzone)
  if setting("death") then logic:push("death", name, ns.now(), { zone = zone, subzone = subzone }) end
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
  ns.Bus.on(FEATURE, "MEMBER_OFFLINE", onOffline)
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
  info = "Small messages near the top of the screen when a friend changes layer or dies. "
    .. "They are short and never pile up.",
  defaults = { layerDiff = true, layerSame = true, death = true, sound = false, seconds = 5 },
  settings = {
    { key = "layerDiff", label = "Layer changes", kind = "toggle",
      info = "Shows a pop-up when a friend ends up on a different layer than you. Click it to invite them." },
    { key = "layerSame", label = "Back on my layer", kind = "toggle",
      info = "Shows a pop-up when a friend who was on a different layer is back on yours." },
    { key = "death", label = "Deaths", kind = "toggle",
      info = "Shows a pop-up with the place when a friend dies." },
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
