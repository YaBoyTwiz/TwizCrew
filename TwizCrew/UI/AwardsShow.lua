-- The awards show (/tc awards): a big window in the middle of the screen, one award at a time. It asks the crew for
-- fresh numbers, waits SHOW_WAIT s, then for each award: the badge and its name, "and the award goes to…", then
-- the winners (class colours), their number and the joke. Click or Space for the next one; Escape closes.
-- The crew follows on their screens: when the cards are built the presenter sends AWS { id, v }, then an AWC per
-- card as it starts (ShowLogic.cardToWire; again with r = "1" when a click jumps to the reveal) and AWX { id } when
-- it closes. SHOW_IDLE s with no card change close the show.
-- Viewer role: a known crew member's AWS opens the same window (stats setting "crewShow"); it shows the cards the
-- presenter sends (AWC) and closes on AWX. A viewer's clicks and Space do nothing except at the end card. In a fight
-- it waits and catches up to the latest card's reveal when the fight ends. Escape closes only the viewer's window.
-- Clown of the Night (session view only): after the last award, with 2 or more people in the session, the presenter
-- sends AWV { id, c = candidates, t = "30" } and every screen shows the vote card: a button per candidate except
-- yourself (up to 8, the first by name), "N of M voted" and a countdown. A click sends AWB { id, c } once; every
-- screen counts the AWBs it hears (one per voter, the first counts). The presenter ends it after 30 s, or once every
-- online candidate voted, with AWR { id, w, n } (ShowLogic.tally), or AWR { id, k = "skip" } from its Skip button.
-- The presenter's 30 s start once its AWV has left the send queue, so the crew gets the full time. An AWC still
-- waiting in the queue is replaced by the next one (the crew jumps to the latest card).
-- Every result replaces the clown on each screen that sees it (no clown or Skip: none until the next show): the
-- Crew-tab title db.stats.clown = { names, sid, at } and the session's trophy db.stats.clownBySid; CLOWN_CHANGED.
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
local VOTE_TITLE = "Who's the Clown of the Night?"
local NOT_VOTING = "Only the people in the session vote"
local MAX_BUTTONS, BUTTON_W, BUTTON_H, BUTTON_GAP = 8, 186, 24, 16

local frame, header, badge, title, line, number, joke, hint
local voteTitle, voteLine, skipButton
local buttons = {}     -- the vote card's buttons
local onButton = {}    -- [i] = the name on button i while it is shown
local skipShown = false
-- the Clown of the Night vote: { candidates (sorted), isCandidate, me (my name among them), votes = { [voter] =
-- choice }, count, mine, endsAt, escaped (names from the wire), endIndex (presenter: the end card), closed, result }
local vote = nil
local open = false
local view = "session"
local cards = {}       -- from StatsLogic.showCards (+ the "nobody" card)
local classes = {}     -- name -> class file, for the winners' colours
local index = 0
local phase = nil      -- "loading" | "badge" | "drum" | "reveal" | "nobody" | "vote" | "clown" | "end"
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

-- opts: replace (a key: a waiting copy with the same key is dropped for this one), onSent (runs once it went out).
local function send(msgType, fields, opts)
  ns.Comm.send(msgType, fields, { repeatKeys = ns.ShowLogic.REPEAT_KEYS, replace = opts and opts.replace,
    onSent = opts and opts.onSent })
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

  -- the vote card: its title, up to 8 buttons in two columns, "N of M voted" and the presenter's Skip
  voteTitle = centered(T.text(frame, T.FONT.normal, GOLD), -34)
  for i = 1, MAX_BUTTONS do
    local b = Widgets.button(frame, "", function() Show.vote(onButton[i]) end, nil, FEATURE)
    b:SetSize(BUTTON_W, BUTTON_H)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (BUTTON_W + BUTTON_GAP), -60 - row * (BUTTON_H + 4))
    b:Hide()
    buttons[i] = b
  end
  voteLine = centered(T.text(frame, T.FONT.small, C.text), -180)
  skipButton = Widgets.button(frame, "Skip", function() Show.skipVote() end, nil, FEATURE)
  skipButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 8)
  skipButton:Hide()

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
local function colored(name, escaped)
  return "|cff" .. hex(T.classColor(classes[name])) .. (escaped and name or ns.Util.safeText(name)) .. "|r"
end

local function winnersText(names, escaped, more, sep)
  local parts = {}
  for i, name in ipairs(names) do parts[i] = colored(name, escaped) end
  local s = table.concat(parts, sep or ", ")
  if more and more > 0 then s = s .. " and " .. more .. " more" end
  return s
end

local function card() return cards[index] end

-- The candidates on the vote card's buttons: everyone but me, the first MAX_BUTTONS by name.
local function buttonNames()
  local out = {}
  for _, name in ipairs(vote and vote.candidates or {}) do
    if name ~= vote.me and #out < MAX_BUTTONS then out[#out + 1] = name end
  end
  return out
end

local function votedText() return vote.count .. " of " .. #vote.candidates .. " voted" end

-- The full time until the clock starts (presenter: once AWV has gone out).
local function secondsLeft()
  if not vote.endsAt then return vote.seconds end
  return math.max(0, math.ceil(vote.endsAt - ns.now()))
end

-- My buttons work while I'm a candidate, the vote is open and time is left (they fade otherwise).
local function canVote() return vote.me ~= nil and not vote.closed and secondsLeft() > 0 end

local function drawVote()
  voteTitle:SetText(VOTE_TITLE)
  local list = buttonNames()
  local can = canVote()
  for i, b in ipairs(buttons) do
    local name = list[i]
    onButton[i] = name
    if name then
      local label = colored(name, vote.escaped)
      if vote.mine == name then label = "|cff" .. GOLD .. ">|r " .. label .. " |cff" .. GOLD .. "<|r" end
      b.text:SetText(label)
      b:SetAlpha(((vote.mine and vote.mine ~= name) or not can) and 0.45 or 1)
      b:Show()
    end
  end
  voteLine:SetText(votedText())
  hintText = vote.me and (secondsLeft() .. " s left") or (NOT_VOTING .. " · " .. secondsLeft() .. " s left")
  skipShown = role == "presenter"
  if skipShown then skipButton:Show() end
end

local function drawClown()
  local r = vote and vote.result or { names = {}, n = 0 }
  local def = ns.StatsDefs.trophyDef("clown")
  badge:SetTexture(def and def.icon or ns.StatsDefs.ICON_FALLBACK)
  badge:Show()
  if #r.names == 0 then
    title:SetText(ns.ShowLogic.clownLine(r.names, r.n))
  else
    title:SetText(ns.ShowLogic.CLOWN_TITLE)
    lineText = winnersText(r.names, vote.escaped, nil, " & ") .. " (" .. r.n .. (r.n == 1 and " vote)" or " votes)")
  end
end

-- Draws the current phase.
local function draw()
  local c = card()
  local a = c and c.award
  badge:Hide()
  title:SetText("")
  joke:SetText("")
  voteTitle:SetText("")
  voteLine:SetText("")
  for i, b in ipairs(buttons) do onButton[i] = nil; b:Hide() end
  skipShown = false
  skipButton:Hide()
  lineText, numberText, hintText = "", "", HINT_NEXT
  if role == "viewer" then hintText = ns.Util.safeText(follow and follow.presenter or "") .. " is presenting" end
  if phase == "vote" and vote then
    drawVote()
  elseif phase == "clown" then
    drawClown()
  elseif phase == "loading" then
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
  -- a card still waiting in the send queue is dropped: the crew jumps to the latest one
  send("AWC", ns.ShowLogic.cardToWire(showId, index, c, c.streak, jump), { replace = showId })
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

local function classOf(name)
  if ns.isMe(name) then
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class or nil
  end
  local m = ns.roster and ns.roster:get(name)
  return m and m.class or nil
end

------------------------------------------------------------------------------------------------------------ vote
local function showIdNow() return showId or (follow and follow.id) end

-- started: the clock runs from now (a viewer); the presenter's starts once its AWV has gone out.
local function newVote(candidates, seconds, escaped, started)
  local v = { candidates = candidates, isCandidate = {}, votes = {}, count = 0,
    endsAt = started and ns.now() + seconds or nil, escaped = escaped, seconds = seconds }
  for _, name in ipairs(candidates) do
    v.isCandidate[name] = true
    if ns.isMe(name) then v.me = name end
  end
  return v
end

-- Shows the vote card (and keeps its countdown going once a second, drawn on this screen only).
local function enterVote()
  for _, name in ipairs(vote.candidates) do classes[name] = classes[name] or classOf(name) end
  setPhase("vote")
  local function tick()
    if phase ~= "vote" then return end
    draw()
    if not vote.closed then after(1, tick) end
  end
  after(1, tick)
end

-- Every vote result replaces the clown on this screen (only candidates; none: no clown until the next show). The
-- Crew-tab title is db.stats.clown; the trophy is the last clown voted in a session, db.stats.clownBySid[sid],
-- which a later "no clown" in the same session does not take away.
local function saveClown(names)
  if not ns.db then return end
  local list = {}
  for _, name in ipairs(names or {}) do
    if vote.isCandidate[name] and not ns.isTestName(name) then list[#list + 1] = name end
  end
  if type(ns.db.stats) ~= "table" then ns.db.stats = {} end
  local stats = ns.db.stats
  if #list == 0 then
    if stats.clown == nil then return end
    stats.clown = nil
  else
    local session = ns.Session and ns.Session.current()
    local sid = session and session.id or nil
    stats.clown = { names = list, sid = sid, at = ns.wallclock() }
    -- only this session's: an ended session's trophy was already recorded when it ended
    if sid then stats.clownBySid = { [sid] = list } end
  end
  ns.Bus.fire("CLOWN_CHANGED")
end

-- The result is known: saved, and shown unless show is false (a viewer in a fight sees it afterwards).
local function reveal(names, n, show)
  vote.closed = true
  vote.result = { names = names, n = n }
  saveClown(names)
  cardSerial = cardSerial + 1
  idleClock()
  if show ~= false then setPhase("clown") end
end

-- Presenter: the vote is over (30 s, or everyone online voted): tally, tell the crew, reveal.
local function finishVote()
  if role ~= "presenter" or not vote or vote.closed then return end
  local w, n = ns.ShowLogic.tally(vote.votes, vote.candidates)
  send("AWR", { id = showId, w = table.concat(w, ","), n = tostring(n) })
  reveal(w, n)
end

local function isOnline(name)
  if ns.isMe(name) then return true end
  local m = ns.roster and ns.roster:get(name)
  return m ~= nil and m.online and true or false
end

local function everyoneVoted()
  for _, name in ipairs(vote.candidates) do
    if not vote.votes[name] and isOnline(name) then return false end
  end
  return true
end

-- One vote per voter (the first counts), only candidates, never for yourself.
local function countVote(voter, choice)
  if not vote or vote.closed or not vote.isCandidate[voter] or not vote.isCandidate[choice] or voter == choice
    or vote.votes[voter] then return end
  vote.votes[voter] = choice
  vote.count = vote.count + 1
  if phase == "vote" then draw() end
  if role == "presenter" and everyoneVoted() then finishVote() end
end

-- Presenter: AWV has left the send queue, so the crew has it: now the vote clock starts (they get the full time).
local function voteSent(v)
  if vote ~= v or v.closed or not open or role ~= "presenter" then return end
  v.endsAt = ns.now() + v.seconds
  cardSerial = cardSerial + 1 -- the idle clock waits for the vote too
  idleClock()
  C_Timer.After(v.seconds, function()
    ns.Log.safe(FEATURE, function() if vote == v and open then finishVote() end end)
  end)
  if phase == "vote" then draw() end
end

-- The people in this session (real names, sorted); nil outside the session view.
local function sessionCandidates()
  if view ~= "session" or not ns.Session then return nil end
  local session = ns.Session.current()
  if not session then return nil end
  local seen, list = {}, {}
  for _, e in ipairs(ns.StatsStore.entries("session", session.id)) do
    local name = e.name
    if type(name) == "string" and name ~= "" and not ns.isTestName(name) and not seen[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  table.sort(list)
  return list
end

-- Presenter: starts the vote before the end card (endIndex); false when there is no vote (all time, fewer than 2).
local function startVote(endIndex)
  local list = sessionCandidates()
  if not showId or not list or #list < 2 then return false end
  local f, kept = ns.ShowLogic.voteToWire(showId, list, ns.ShowLogic.VOTE_SECONDS)
  if #kept < 2 then return false end
  vote = newVote(kept, ns.ShowLogic.VOTE_SECONDS, false, false)
  vote.endIndex = endIndex
  cardSerial = cardSerial + 1
  idleClock()
  enterVote()
  local v = vote
  send("AWV", f, { onSent = function() voteSent(v) end })
  return true
end

-- A card from the wire (ShowLogic.cardFromWire) in the shape draw() uses; its names are already escaped.
local function viewerCard(c)
  if c.kind ~= "award" then return { kind = c.kind } end
  return { kind = "award", escaped = true, streak = c.streak, more = c.more,
    award = { def = ns.StatsDefs.awardDef(c.awardId), winners = c.winners, text = c.text } }
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

-- The latest thing the presenter sent, shown after a fight: a card's reveal, the vote card or the clown.
local function showLatest(c)
  if c.kind == "vote" then
    if vote and not vote.closed then enterVote() else setPhase("end") end
  elseif c.kind == "clown" then
    setPhase("clown")
  elseif c.kind == "skip" then
    setPhase("end") -- the vote was skipped: the presenter's end card follows
  else
    showWireCard(c, true)
  end
end

local function openViewer()
  if not frame then build() end
  role, view = "viewer", follow.view
  setHeader(view == "all" and "TwizCrew Awards: all time"
    or "TwizCrew Awards: " .. ns.Util.safeText(follow.presenter) .. "'s show")
  cards, classes, index = {}, {}, 0
  open = true
  if follow.latest then showLatest(follow.latest) else setPhase("loading") end
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
  vote = nil
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

-- Remembers what to show next; true when it can be drawn now (not waiting out a fight).
local function latest(c)
  cardSerial = cardSerial + 1
  idleClock()
  follow.latest = c
  if follow.waiting or inCombat() then
    follow.waiting = true -- drawn when the fight is over
    return false
  end
  return true
end

local function onVoteStart(sender, f)
  if not fromPresenter(sender, f) or vote then return end -- one vote per show
  local v = ns.ShowLogic.voteFromWire(f)
  if not v then return end
  vote = newVote(v.candidates, v.seconds, true, true)
  if latest({ kind = "vote" }) then enterVote() end
end

-- Names from the wire, cleaned like the candidates a viewer got (ShowLogic names).
local function wireName(s)
  if type(s) ~= "string" then return nil end
  return ns.Util.truncateUTF8(ns.Util.safeText(s), 24)
end

local function onBallot(sender, f)
  if not vote or type(f) ~= "table" or f.id == nil or f.id ~= showIdNow() or not known(sender) then return end
  if vote.escaped then
    countVote(wireName(sender), wireName(f.c))
  else
    countVote(sender, f.c)
  end
end

local function onResult(sender, f)
  if not fromPresenter(sender, f) or not vote or vote.closed then return end
  local r = ns.ShowLogic.resultFromWire(f)
  if not r then return end
  if r.skip then -- no clown until the next show; the presenter's end card follows
    vote.closed = true
    saveClown(nil)
    if latest({ kind = "skip" }) then setPhase("end") end
    return
  end
  reveal(r.names, r.n, false)
  if latest({ kind = "clown" }) then setPhase("clown") end
end

ns.Comm.on("AWS", function(s, f) ns.Log.safe(FEATURE, onStart, s, f) end)
ns.Comm.on("AWC", function(s, f) ns.Log.safe(FEATURE, onCard, s, f) end)
ns.Comm.on("AWX", function(s, f) ns.Log.safe(FEATURE, onEnd, s, f) end)
ns.Comm.on("AWV", function(s, f) ns.Log.safe(FEATURE, onVoteStart, s, f) end)
ns.Comm.on("AWB", function(s, f) ns.Log.safe(FEATURE, onBallot, s, f) end)
ns.Comm.on("AWR", function(s, f) ns.Log.safe(FEATURE, onResult, s, f) end)

local FIGHT_RETRIES = 5

-- The fight is over: a viewer who waited opens (or redraws) at the latest thing the presenter sent. The event can
-- come a moment before the game stops saying "in combat": then it tries again each second, a few times.
function Show.fightOver(tries)
  if not follow or not follow.waiting then return end
  if inCombat() then
    tries = (tries or 0) + 1
    local waiting = follow
    if tries <= FIGHT_RETRIES then
      C_Timer.After(1, function()
        ns.Log.safe(FEATURE, function() if follow == waiting then Show.fightOver(tries) end end)
      end)
    end
    return
  end
  follow.waiting = false
  if not open then
    openViewer()
  elseif follow.latest then
    showLatest(follow.latest)
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
  vote = nil
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
  vote = nil
  generation = generation + 1
  cardSerial = cardSerial + 1
  phase = nil
  if showId then
    send("AWX", { id = showId })
    showId = nil
  end
  if frame and wasOpen then frame:Hide() end
end

-- Click or Space: before the reveal jump to it, at the reveal (or the "nobody" card) go on (after the last award:
-- the vote, when there is one), at the clown go to the end card, at the end close. The vote card only takes its
-- buttons. A viewer's click only closes the end card.
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
    local nextIndex = index + 1
    local c = cards[nextIndex]
    if not vote and (not c or c.kind == "end") and startVote(nextIndex) then return end
    showCard(nextIndex)
  elseif phase == "clown" then
    showCard(vote and vote.endIndex or index + 1)
  elseif phase == "end" then
    Show.close()
  end
end

-- A vote button: my vote, once (the presenter counts it at once; it is also sent so every screen counts it).
function Show.vote(name)
  if not open or phase ~= "vote" or not vote or vote.mine or not canVote() then return end
  if type(name) ~= "string" or name == vote.me or not vote.isCandidate[name] then return end
  vote.mine = name
  send("AWB", { id = showIdNow(), c = name })
  countVote(vote.me, name)
  if phase == "vote" then draw() end
end

-- The presenter's Skip: no clown tonight, straight to the end card.
function Show.skipVote()
  if role ~= "presenter" or phase ~= "vote" or not vote or vote.closed then return end
  vote.closed = true
  saveClown(nil)
  send("AWR", { id = showId, k = "skip" })
  showCard(vote.endIndex)
end

-- Tests: clicks the shown vote button with this name (or "Skip"); false when there is none.
function Show.pressForTest(label)
  local target
  if label == "Skip" then
    target = skipShown and skipButton or nil
  else
    for i, b in ipairs(buttons) do if onButton[i] == label then target = b end end
  end
  if not target then return false end
  target:GetScript("OnClick")(target)
  return true
end

function Show.stateForTest()
  local c = cards[index]
  local a = c and c.award
  local s = { phase = phase, index = index, count = #cards, winners = {}, role = role, header = headerText,
    hint = hintText, line = lineText, number = numberText, more = c and c.more or nil }
  if phase == "vote" and vote then
    s.title, s.voted, s.picked, s.skip, s.buttons = VOTE_TITLE, votedText(), vote.mine, skipShown, {}
    for i = 1, MAX_BUTTONS do
      if onButton[i] then s.buttons[#s.buttons + 1] = onButton[i] end
    end
    s.left = secondsLeft()
    s.dimmed = not canVote()
  elseif phase == "clown" then
    local r = vote and vote.result or { names = {}, n = 0 }
    s.title = #r.names == 0 and ns.ShowLogic.clownLine(r.names, r.n) or ns.ShowLogic.CLOWN_TITLE
    s.text = ns.ShowLogic.clownLine(r.names, r.n)
  elseif phase == "loading" then
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
