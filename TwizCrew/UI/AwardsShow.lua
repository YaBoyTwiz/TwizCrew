-- The awards show (/tc awards): a big window in the middle of the screen, one award at a time. It asks the crew for
-- fresh numbers, waits SHOW_WAIT s, then for each award: the badge and its name, "and the award goes to…", then
-- the winners (class colours), their number and the joke. Click or Space for the next one; Escape closes.
-- The crew follows on their screens: when the cards are built the presenter sends AWS { id, v }, then an AWC per
-- card as it starts (ShowLogic.cardToWire; again with r = "1" when a click jumps to the reveal) and AWX { id } when
-- it closes. SHOW_IDLE s with no card change close the show.
-- Viewer role: a known crew member's AWS opens the same window (stats setting "crewShow"); it shows the cards the
-- presenter sends (AWC) and closes on AWX. A viewer's clicks and Space do nothing except at the end card. In a fight
-- it waits and catches up to the latest card's reveal when the fight ends. Escape closes only the viewer's window.
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
local cardSerial = 0   -- bumped on every card change and on close: a stale idle clock does nothing
local showId = nil     -- set when AWS was sent (this copy is presenting): "<me>-<wallclock>"
local role = nil       -- "presenter" | "viewer" while a show is open (or a viewer waits out a fight)
local follow = nil     -- viewer: { id, presenter, view, latest = last card (ShowLogic.cardFromWire), waiting }
local hidingForFight = false
local dragged = false
local headerText, lineText, numberText, hintText = "", "", "", ""

local function say(text) print("TwizCrew: " .. text) end
local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

-- A yes from a game function; an error or a secret answer counts as no.
local function yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  if not ok or (type(issecretvalue) == "function" and issecretvalue(v)) then return false end
  return v and true or false
end

local function inCombat()
  return yes(InCombatLockdown) or yes(UnitAffectingCombat, "player")
end

local function known(sender)
  return type(sender) == "string" and not ns.isMe(sender) and not ns.isTestName(sender) and ns.roster
    and ns.roster:get(sender) ~= nil
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

-- Closes the show when SHOW_IDLE s pass with no card change (started on every card change).
local function idleClock()
  local serial = cardSerial
  C_Timer.After(ns.Config.SHOW_IDLE, function()
    ns.Log.safe(FEATURE, function()
      if (open or follow) and serial == cardSerial then Show.close() end
    end)
  end)
end

local function send(msgType, fields)
  ns.Comm.send(msgType, fields, { repeatKeys = { "id", "i" } })
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
  -- Only Space is kept; every other key (Escape, movement, chat) goes on to the game. In combat lockdown the
  -- keyboard setting can't be changed: the show closes (hiding is allowed) so it never holds the keys in a fight.
  -- A viewer keeps Space only at the end card (where it closes); before that it goes on to the game.
  script(frame, "OnKeyDown", function(self, key)
    if lockdown() then
      Show.fightLockdown()
      return
    end
    local mine = key == "SPACE" and (role ~= "viewer" or phase == "end")
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not mine) end
    if mine then Show.next() end
  end)
  script(frame, "OnHide", function()
    if not hidingForFight then Show.close() end
  end)
  frame:Hide()

  -- In a fight the keyboard goes back to the game (clicks still work).
  ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", function()
    if frame.EnableKeyboard then frame:EnableKeyboard(false) end
  end)
  ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", function()
    if open and frame.EnableKeyboard then frame:EnableKeyboard(true) end
    Show.fightOver()
  end)
end

-- names: the winners; escaped: already cleaned with safeText (cards from the wire); more: winners not sent.
local function winnersText(names, escaped, more)
  local parts = {}
  for i, name in ipairs(names) do
    parts[i] = "|cff" .. hex(T.classColor(classes[name])) .. (escaped and name or ns.Util.safeText(name)) .. "|r"
  end
  local s = table.concat(parts, ", ")
  if more and more > 0 then s = s .. " and " .. more .. " more" end
  return s
end

local function card() return cards[index] end

-- Draws the current phase.
local function draw()
  local c = card()
  local a = c and c.award
  badge:Hide()
  title:SetText("")
  joke:SetText("")
  lineText, numberText, hintText = "", "", HINT_NEXT
  if role == "viewer" then hintText = ns.Util.safeText(follow and follow.presenter or "") .. " is presenting" end
  if phase == "loading" then
    title:SetText(LOADING)
    if role ~= "viewer" then hintText = "" end
  elseif phase == "nobody" then
    title:SetText(NOBODY)
  elseif phase == "end" then
    title:SetText(THE_END)
    hintText = HINT_CLOSE
  elseif a then
    badge:SetTexture(a.def.icon or ns.StatsDefs.ICON_FALLBACK)
    badge:Show()
    title:SetText(a.def.name)
    if phase == "drum" then
      lineText = DRUMROLL
    elseif phase == "reveal" then
      local streak = ns.ShowLogic.streakLine(c.streak)
      local who = winnersText(a.winners, c.escaped, c.more)
      lineText = streak and (streak .. ", " .. who .. "!") or who
      numberText = ns.Util.safeText(a.text or "")
      joke:SetText(a.def.joke or "")
    end
  end
  line:SetText(lineText)
  number:SetText(numberText)
  hint:SetText(hintText)
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

-- The winner's streak with tonight (session view, one winner): their saved streak + 1; nil under 2.
local function streakFor(c)
  if view ~= "session" or not c or c.kind ~= "award" or not ns.Trophies then return nil end
  local winners = c.award.winners or {}
  if #winners ~= 1 then return nil end
  local p = ns.Trophies.summary()[winners[1]]
  local n = (p and p.streaks and p.streaks[c.award.def.id] or 0) + 1
  return n >= 2 and n or nil
end

local function sendCard(jump)
  if not showId then return end
  local c = cards[index] or { kind = "end" }
  send("AWC", ns.ShowLogic.cardToWire(showId, index, c, c.streak, jump))
end

local function showCard(i)
  index = i
  cardSerial = cardSerial + 1
  local c = cards[i]
  if c then c.streak = streakFor(c) end
  sendCard(false)
  idleClock()
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
  showId = ns.playerName() .. "-" .. ns.wallclock()
  send("AWS", { id = showId, v = view })
  showCard(1)
end

---------------------------------------------------------------------------------------------------------- viewer
local function setHeader(text)
  headerText = text
  header:SetText(text)
end

local function awardDef(id)
  for _, d in ipairs(ns.StatsDefs.AWARDS) do if d.id == id then return d end end
  return nil
end

local function classOf(name)
  if ns.isMe(name) then
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class or nil
  end
  local m = ns.roster and ns.roster:get(name)
  return m and m.class or nil
end

-- A card from the wire (ShowLogic.cardFromWire) in the shape draw() uses; its names are already escaped.
local function viewerCard(c)
  if c.kind ~= "award" then return { kind = c.kind } end
  return { kind = "award", escaped = true, streak = c.streak, more = c.more,
    award = { def = awardDef(c.awardId), winners = c.winners, text = c.text } }
end

-- Shows a card the presenter sent. reveal: straight to the reveal (a jump, or catching up after a fight).
local function showWireCard(c, reveal)
  reveal = reveal or c.jump
  if index == c.i and cards[index] then -- the same card again: only a jump changes anything
    if reveal and (phase == "badge" or phase == "drum") then setPhase("reveal") end
    return
  end
  cards = { [c.i] = viewerCard(c) }
  index = c.i
  for _, name in ipairs(c.winners or {}) do classes[name] = classOf(name) end
  if c.kind == "end" then
    setPhase("end")
  elseif c.kind == "nobody" then
    setPhase("nobody")
  else
    setPhase(reveal and "reveal" or "badge")
  end
end

local function openViewer()
  if not frame then build() end
  role, view = "viewer", follow.view
  setHeader(view == "all" and "TwizCrew Awards: all time"
    or "TwizCrew Awards: " .. ns.Util.safeText(follow.presenter) .. "'s show")
  cards, classes, index = {}, {}, 0
  open = true
  if follow.latest then showWireCard(follow.latest, true) else setPhase("loading") end
  if frame.EnableKeyboard then frame:EnableKeyboard(true) end
  frame:Show()
end

local function crewShowOn()
  return ns.Modules.isEnabled("stats") and ns.Modules.setting("stats", "crewShow") ~= false
end

local function onStart(sender, f)
  if open or follow then return end -- a show is open already (mine, or the one I follow)
  if type(f) ~= "table" or type(f.id) ~= "string" or f.id == "" then return end
  if not crewShowOn() or not known(sender) then return end
  if not frame then build() end -- its PLAYER_REGEN_ENABLED handler ends a wait in a fight
  follow = { id = f.id, presenter = sender, view = f.v == "all" and "all" or "session" }
  cardSerial = cardSerial + 1
  idleClock()
  if inCombat() then
    follow.waiting = true
    return
  end
  openViewer()
end

local function fromPresenter(sender, f)
  return follow and type(f) == "table" and f.id == follow.id and sender == follow.presenter
end

local function onCard(sender, f)
  if not fromPresenter(sender, f) then return end
  local c = ns.ShowLogic.cardFromWire(f)
  if not c then return end
  cardSerial = cardSerial + 1
  idleClock()
  follow.latest = c
  if follow.waiting or inCombat() then
    follow.waiting = true -- drawn when the fight is over
    return
  end
  showWireCard(c, false)
end

local function onEnd(sender, f)
  if fromPresenter(sender, f) then Show.close() end
end

ns.Comm.on("AWS", function(s, f) ns.Log.safe(FEATURE, onStart, s, f) end)
ns.Comm.on("AWC", function(s, f) ns.Log.safe(FEATURE, onCard, s, f) end)
ns.Comm.on("AWX", function(s, f) ns.Log.safe(FEATURE, onEnd, s, f) end)

-- The fight is over: a viewer who waited opens (or redraws) at the latest card's reveal.
function Show.fightOver()
  if not follow or not follow.waiting or inCombat() then return end
  follow.waiting = false
  if not open then
    openViewer()
  elseif follow.latest then
    showWireCard(follow.latest, true)
  end
end

-- A key pressed in combat lockdown: the window can't let go of the keyboard, so it hides. The presenter's show
-- closes; a viewer keeps following and comes back when the fight is over.
function Show.fightLockdown()
  if role ~= "viewer" or not follow then
    Show.close()
    return
  end
  open = false
  generation = generation + 1
  phase = nil
  follow.waiting = true
  hidingForFight = true
  frame:Hide()
  hidingForFight = false
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
  setHeader(view == "all" and "TwizCrew Awards: all time" or "TwizCrew Awards: this session")
  cards, classes, index = {}, {}, 0
  if showId then send("AWX", { id = showId }) end -- started again over a show the crew is following
  showId = nil
  follow = nil -- I was watching a friend's show: mine replaces it
  role = "presenter"
  cardSerial = cardSerial + 1 -- the old show's idle clock must not close this one
  open = true
  setPhase("loading")
  if frame.EnableKeyboard then frame:EnableKeyboard(true) end
  frame:Show()
  ns.Stats.request()
  after(ns.Config.SHOW_WAIT, buildCards)
  return true
end

function Show.isOpen() return open end

-- Closes the show on this screen (the presenter also tells the crew). A viewer waiting out a fight stops waiting.
function Show.close()
  if not open and not follow then return end
  local wasOpen = open
  open = false
  follow = nil
  role = nil
  generation = generation + 1
  cardSerial = cardSerial + 1
  phase = nil
  if showId then
    send("AWX", { id = showId })
    showId = nil
  end
  if frame and wasOpen then frame:Hide() end
end

-- Click or Space: before the reveal jump to it, at the reveal (or the "nobody" card) go on, at the end close.
-- A viewer's click only closes the end card.
function Show.next()
  if not open then return end
  if role == "viewer" then
    if phase == "end" then Show.close() end
    return
  end
  if phase == "badge" or phase == "drum" then
    setPhase("reveal")
    sendCard(true)
  elseif phase == "reveal" or phase == "nobody" then
    showCard(index + 1)
  elseif phase == "end" then
    Show.close()
  end
end

function Show.stateForTest()
  local c = cards[index]
  local a = c and c.award
  local s = { phase = phase, index = index, count = #cards, winners = {}, role = role, header = headerText,
    hint = hintText, line = lineText, number = numberText, more = c and c.more or nil }
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
      s.streak = ns.ShowLogic.streakLine(c.streak)
      for i, name in ipairs(a.winners) do s.winners[i] = name end
    else s.text = "" end
  end
  return s
end
