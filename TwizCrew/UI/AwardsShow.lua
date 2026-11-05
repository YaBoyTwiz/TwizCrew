-- The awards show (/tc awards): a big window in the middle of the screen, one award at a time. It asks the crew for
-- fresh numbers, waits SHOW_WAIT s, then for each award: the badge and its name, "and the award goes to…", then
-- the winners (class colours), their number and the joke. Click or Space for the next one; Escape closes.
-- Feature id "awards": every script and timer runs inside ns.Log.safe.
local _, ns = ...

local Show = {}
ns.AwardsShow = Show

local FEATURE = "awards"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, HEIGHT, PAD, BADGE = 420, 260, 16, 64
local GOLD = "ffd100"

local LOADING = "Getting the latest numbers…"
local DRUMROLL = "and the award goes to…"
local NOBODY = "Nobody has won anything yet."
local THE_END = "That's the show. GG crew."
local HINT_NEXT = "Click or press Space for the next one"
local HINT_CLOSE = "Click or press Space to close"

local frame, header, badge, title, line, number, joke, hint
local open = false
local view = "session"
local cards = {}       -- from StatsLogic.showCards (+ the "nobody" card)
local classes = {}     -- name -> class file, for the winners' colours
local index = 0
local phase = nil      -- "loading" | "badge" | "drum" | "reveal" | "nobody" | "end"
local generation = 0   -- bumped on every step and on close: a stale timer does nothing
local dragged = false

local function say(text) print("TwizCrew: " .. text) end
local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function inCombat()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return true end
  if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then return true end
  return false
end

local function lockdown()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function hex(r, g, b)
  local function byte(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

local function playSound(which)
  if ns.Modules.setting("stats", "showSound") == false then return end
  local s = ns.StatsDefs.SOUNDS[which]
  if not s or type(PlaySound) ~= "function" then return end
  local id = type(SOUNDKIT) == "table" and SOUNDKIT[s.kit] or nil
  PlaySound(id or s.id)
end

-- Runs fn after delay s, unless the show moved on (or closed) meanwhile.
local function after(delay, fn)
  local gen = generation
  C_Timer.After(delay, function()
    ns.Log.safe(FEATURE, function()
      if open and gen == generation then fn() end
    end)
  end)
end

---------------------------------------------------------------------------------------------------------- frames
local function bigFont()
  if _G.GameFontNormalHuge then return "GameFontNormalHuge" end
  return T.FONT.normal
end

local function centered(fs, y, width)
  fs:SetPoint("TOP", frame, "TOP", 0, y)
  fs:SetWidth(width or WIDTH - 2 * PAD)
  fs:SetJustifyH("CENTER")
  return fs
end

local function build()
  frame = T.frame("Frame", "TwizCrewAwards", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  T.paint(frame, C.backdrop, 0.97, GOLD, 2)
  local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 8)
  glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -8)
  T.color(glow, GOLD, 0.15)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewAwards") end -- Escape

  header = T.text(frame, T.FONT.small, C.muted)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
  badge = frame:CreateTexture(nil, "ARTWORK")
  badge:SetSize(BADGE, BADGE)
  badge:SetPoint("TOP", frame, "TOP", 0, -30)
  title = centered(T.text(frame, bigFont(), GOLD), -102)
  line = centered(T.text(frame, T.FONT.normal, C.text), -134)
  number = centered(T.text(frame, T.FONT.normal, GOLD), -158)
  joke = centered(T.text(frame, T.FONT.small, C.muted), -184)
  if joke.SetWordWrap then joke:SetWordWrap(true) end
  hint = T.text(frame, T.FONT.small, C.muted)
  hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)

  -- A click (not a drag) is "next". OnMouseDown resets the drag mark, so a lost OnMouseUp never eats a click.
  script(frame, "OnMouseDown", function() dragged = false end)
  script(frame, "OnDragStart", function(self) dragged = true; self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  script(frame, "OnMouseUp", function()
    if dragged then dragged = false; return end
    Show.next()
  end)
  -- Only Space is kept; every other key (Escape, movement, chat) goes on to the game.
  script(frame, "OnKeyDown", function(self, key)
    if not lockdown() and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(key ~= "SPACE") end
    if key == "SPACE" then Show.next() end
  end)
  script(frame, "OnHide", function() Show.close() end)
  frame:Hide()

  -- In a fight the keyboard goes back to the game (clicks still work).
  ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", function()
    if frame.EnableKeyboard then frame:EnableKeyboard(false) end
  end)
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function()
    if open and frame.EnableKeyboard then frame:EnableKeyboard(true) end
  end)
end

local function winnersText(names)
  local parts = {}
  for i, name in ipairs(names) do
    parts[i] = "|cff" .. hex(T.classColor(classes[name])) .. ns.Util.safeText(name) .. "|r"
  end
  return table.concat(parts, ", ")
end

local function card() return cards[index] end

-- Draws the current phase.
local function draw()
  local c = card()
  local a = c and c.award
  badge:Hide()
  title:SetText("")
  line:SetText("")
  number:SetText("")
  joke:SetText("")
  hint:SetText(HINT_NEXT)
  if phase == "loading" then
    title:SetText(LOADING)
    hint:SetText("")
  elseif phase == "nobody" then
    title:SetText(NOBODY)
  elseif phase == "end" then
    title:SetText(THE_END)
    hint:SetText(HINT_CLOSE)
  elseif a then
    badge:SetTexture(a.def.icon or ns.StatsDefs.ICON_FALLBACK)
    badge:Show()
    title:SetText(a.def.name)
    if phase == "drum" then
      line:SetText(DRUMROLL)
    elseif phase == "reveal" then
      line:SetText(winnersText(a.winners))
      number:SetText(ns.Util.safeText(a.text or ""))
      joke:SetText(a.def.joke or "")
    end
  end
end

local function setPhase(p)
  generation = generation + 1
  phase = p
  draw()
  if p == "badge" then
    playSound("badge")
    after(ns.Config.SHOW_BADGE, function()
      setPhase("drum")
      after(ns.Config.SHOW_DRUMROLL, function() setPhase("reveal") end)
    end)
  elseif p == "reveal" then
    playSound("reveal")
  end
end

local function showCard(i)
  index = i
  local c = cards[i]
  if not c or c.kind == "end" then
    setPhase("end")
  elseif c.kind == "nobody" then
    setPhase("nobody")
  else
    setPhase("badge")
  end
end

local function buildCards()
  local session = ns.Session and ns.Session.current() or nil
  local list = ns.StatsStore.entries(view, session and session.id)
  classes = {}
  for _, e in ipairs(list) do classes[e.name] = e.class end
  cards = ns.StatsLogic.showCards(ns.StatsLogic.awards(list))
  if #cards == 1 then table.insert(cards, 1, { kind = "nobody" }) end
  showCard(1)
end

---------------------------------------------------------------------------------------------------------- public
-- view: "session" | "all". Refuses (with a chat line) while stats is off or during a fight.
function Show.start(v)
  if not ns.Modules.isEnabled("stats") then
    say("turn on Stats & Hall of Shame in /tc first.")
    return false
  end
  if inCombat() then
    say("the awards show waits until the fight is over.")
    return false
  end
  if not frame then build() end
  view = v == "all" and "all" or "session"
  header:SetText(view == "all" and "TwizCrew Awards: all time" or "TwizCrew Awards: this session")
  cards, classes, index = {}, {}, 0
  open = true
  setPhase("loading")
  if frame.EnableKeyboard then frame:EnableKeyboard(true) end
  frame:Show()
  ns.Stats.request()
  after(ns.Config.SHOW_WAIT, buildCards)
  return true
end

function Show.isOpen() return open end

function Show.close()
  if not open then return end
  open = false
  generation = generation + 1
  phase = nil
  if frame then frame:Hide() end
end

-- Click or Space: before the reveal jump to it, at the reveal (or the "nobody" card) go on, at the end close.
function Show.next()
  if not open then return end
  if phase == "badge" or phase == "drum" then
    setPhase("reveal")
  elseif phase == "reveal" or phase == "nobody" then
    showCard(index + 1)
  elseif phase == "end" then
    Show.close()
  end
end

function Show.stateForTest()
  local c = cards[index]
  local a = c and c.award
  local s = { phase = phase, index = index, count = #cards, winners = {} }
  if phase == "loading" then
    s.title, s.text = LOADING, LOADING
  elseif phase == "nobody" then
    s.title, s.text = NOBODY, NOBODY
  elseif phase == "end" then
    s.title, s.text = THE_END, THE_END
  elseif a then
    s.title = a.def.name
    if phase == "drum" then s.text = DRUMROLL
    elseif phase == "reveal" then
      s.text = a.text
      for i, name in ipairs(a.winners) do s.winners[i] = name end
    else s.text = "" end
  end
  return s
end
