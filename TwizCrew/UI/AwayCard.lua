-- "While you were away": about ten seconds after login, when this account last logged out with this guild's data
-- 12 hours ago or more, one card says what changed since: who levelled and by how much, who joined or left the guild
-- (from the game's guild list now against the one saved at that logout, so members without TwizCrew count too), new
-- calendar notes and Hall of Shame crowns that changed hands. The rules are in UI/AwayLogic.lua.
-- Switch: Today's recap, "Show what changed while I was away" (needs that module on).
--
-- The snapshot (db.away.snap, per guild: Core/DB.lua GUILD_PATHS) is written at PLAYER_LOGOUT (also before a
-- /reload), only once this session's card was worked out and shown (so a quick /reload right after login, or a logout
-- while the card still waits for the end of a dungeon, keeps the old one), only while TwizCrew uses this guild's data
-- and the list is complete: a whole list with at least 80% of the snapshot's members replaces it, any other list only
-- updates the members it has (AwayLogic.merge). The card waits for a whole list (GUILD_LIST)
-- up to CAP s after login; past that it goes on without "left" lines. Never during a fight or in an instance (it
-- waits for the end, whenFree). Also the card frame both cards use (AwayCard.newCard; UI/Welcome.lua).
local _, ns = ...

local AwayCard = {}
ns.AwayCard = AwayCard

local FEATURE = "awaycard"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local Logic = ns.AwayLogic
local I = "Interface\\Icons\\"
local WAIT, CAP, RETRY = 10, 90, 3 -- s after login: the earliest look, the latest (no whole list yet); retry when busy
local WIDTH, ROW, TOP, PAD = 420, 30, 48, 14

local baseline   -- the snapshot saved at the last logout (taken at start, before anything writes)
local startedAt
local started = false
local decided = false -- this session's card was decided on (it may still wait for the end of a fight or a dungeon)
local done = false    -- ...and worked out and shown (or nothing to show): from now on a logout saves a new snapshot
local card
local last       -- { sub, lines } of the card shown this session (the wrench menu shows it again)

---------------------------------------------------------------------------------------------------- the card frame
-- A small window like Today's recap: an icon and a title, a line under it, icon + text rows, Close at the top right,
-- and buttons at the bottom. closeOnClick: a click anywhere on it closes it. Returns { frame, fill(sub, lines,
-- buttons) }: lines { icon, text, onClick (a click on the row: runs it, then closes the card) }, buttons { label,
-- onClick } (the card closes after).
function AwayCard.newCard(name, icon, title, closeOnClick, featureId)
  featureId = featureId or FEATURE
  local c = { rows = {}, buttons = {} }
  local frame = T.frame("Frame", name, UIParent)
  c.frame = frame
  frame:SetSize(WIDTH, 60)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  T.paint(frame, C.backdrop, 0.97, C.title, 2)
  T.gloss(frame, nil, 0.05, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
  local logo = frame:CreateTexture(nil, "ARTWORK")
  logo:SetSize(T.icon(26), T.icon(26))
  logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
  logo:SetTexture(icon)
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.title = T.readable(T.text(frame, T.FONT.normal, C.title), 3)
  c.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  c.title:SetText(title)
  c.sub = T.readable(T.text(frame, T.FONT.small, C.muted))
  c.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP + 4)
  c.sub:SetWidth(WIDTH - 2 * PAD)
  c.sub:SetJustifyH("LEFT")
  local function hide() frame:Hide() end
  local close = Widgets.button(frame, "Close", hide, nil, featureId)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
  if closeOnClick then
    Widgets.script(frame, "OnMouseUp", function(_, button) if button ~= "RightButton" then hide() end end, featureId)
  end

  function c.fill(sub, lines, buttons)
    c.title:SetText(c.titleText or title)
    c.sub:SetText(sub or "")
    local top = TOP + ((sub and sub ~= "") and 22 or 0)
    for i, l in ipairs(lines) do
      local r = c.rows[i]
      if not r then
        r = CreateFrame("Button", nil, frame)
        r:SetSize(WIDTH - 2 * PAD, ROW - 2)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(T.icon(22), T.icon(22))
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = T.readable(T.text(r, T.FONT.small, C.white))
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.text:SetWidth(WIDTH - 2 * PAD - 40)
        r.text:SetJustifyH("LEFT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(r)
        T.color(hl, C.white, 0.06)
        r.hl = hl
        Widgets.script(r, "OnClick", function(self)
          if type(self.tcClick) == "function" then self.tcClick() end
          if self.tcClick or closeOnClick then hide() end
        end, featureId)
        c.rows[i] = r
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(top + (i - 1) * ROW))
      r.icon:SetTexture(l.icon)
      r.text:SetText(l.text)
      T.textColor(r.text, l.onClick and C.title or C.white)
      r.tcClick = l.onClick
      r:Show()
    end
    for i = #lines + 1, #c.rows do c.rows[i]:Hide() end
    local height = top + #lines * ROW + 8
    for i, b in ipairs(buttons or {}) do
      local w = c.buttons[i]
      if not w then
        w = Widgets.button(frame, b.label, function() local f = w.tcClick; hide(); if f then f() end end, nil, featureId)
        c.buttons[i] = w
      end
      w.text:SetText(b.label)
      w.tcClick = b.onClick
      w:ClearAllPoints()
      if i == 1 then w:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -height)
      else w:SetPoint("LEFT", c.buttons[i - 1], "RIGHT", 8, 0) end
      w:Show()
    end
    for i = #(buttons or {}) + 1, #c.buttons do c.buttons[i]:Hide() end
    if buttons and #buttons > 0 then height = height + 30 end
    frame:SetHeight(height + 6)
    frame:Show()
  end
  return c
end

-- Not now: during a fight (the frames are fine, but it would cover the screen) or inside an instance (a dungeon,
-- a raid, a battleground).
local function busy()
  if ns.Util.plain(InCombatLockdown) or ns.Util.plain(UnitAffectingCombat, "player") then return true end
  return ns.Util.plain(IsInInstance) == true
end
AwayCard.busy = busy

-- Runs fn now, or once the player is out of the fight and out of the instance (checked every RETRY s).
function AwayCard.whenFree(fn, featureId)
  local function try()
    if busy() then C_Timer.After(RETRY, function() ns.Log.safe(featureId or FEATURE, try) end) return end
    fn()
  end
  try()
end

---------------------------------------------------------------------------------------------------- reading the list
-- The guild list now as AwayLogic reads it: { key, full, level, class, guid, online, name (as the panel shows it) }.
function AwayCard.memberList()
  local out = {}
  for _, e in ipairs(ns.Guild.members()) do
    out[#out + 1] = { key = e.key, full = e.full, level = e.level, class = e.class, guid = e.guid, online = e.online,
      name = ns.Guild.display(e.key) }
  end
  return out
end

-- My own characters in this guild: the GUIDs and keys saved by this guild's list (guild.mine[GUID] = key; keys are
-- never given to anyone else in this guild), the full names of the listed members they match, my key and GUID now.
-- Not stats.chars: those are the first words of my characters in any guild, and a new member here may share one. A
-- brand-new alt that never ran TwizCrew in this guild cannot be told apart.
function AwayCard.myCharacters()
  local set = {}
  local db = ns.db or {}
  local g = type(db.guild) == "table" and db.guild or {}
  local mine = type(g.mine) == "table" and g.mine or {}
  for guid, key in pairs(mine) do
    if type(guid) == "string" and type(key) == "string" then set[guid], set[key] = true, true end
  end
  local me = ns.Guild.myKey()
  if me then set[me] = true end
  local guid = ns.Util.plain(UnitGUID, "player")
  if type(guid) == "string" then set[guid] = true end
  for _, e in ipairs(ns.Guild.members()) do
    if type(e.full) == "string" and ((e.guid and set[e.guid]) or (me and e.key == me)) then set[e.full:lower()] = true end
  end
  return set
end

local function store()
  if type(ns.db.away) ~= "table" then ns.db.away = {} end
  return ns.db.away
end

local function wanted()
  return ns.Modules.isEnabled("recap") and ns.Modules.setting("recap", "awayCard") ~= false
end

-- Who holds each all-time crown now (nil while my stats are off).
local function crownsNow()
  if not ns.Modules.isEnabled("stats") or not ns.StatsStore or not ns.StatsLogic then return nil end
  return Logic.crowns(ns.StatsLogic.awards(ns.StatsStore.entries("all")))
end

-- The Hall of Shame, all-time numbers, at an award's tab.
local function openShame(tab)
  if not ns.Modules.isEnabled("stats") then return end
  if ns.Commands and ns.Commands.setPanel and not ns.Modules.isEnabled("panel") then ns.Commands.setPanel(true, true) end
  if ns.Board then
    ns.Board.setView("all")
    if tab then ns.Board.setTab(tab) end
  end
  if ns.Panel and ns.Panel.setTab then ns.Panel.setTab("shame") end
  -- tucked into the crew tab nothing would show: slide the panel out (like the one-time note's pop-up does)
  if ns.Panel and ns.Panel.openTab and ns.Panel.isKeptOpen and not ns.Panel.isKeptOpen() then ns.Panel.openTab("note") end
end

-- The card's words now, or nil when there is nothing to say (or nothing to compare).
local function work()
  local G = ns.Guild
  if not G.active() or not G.complete() then return nil end
  local d = Logic.diff(baseline, AwayCard.memberList(), { now = ns.wallclock(), guild = G.here(), whole = G.whole(),
    mine = AwayCard.myCharacters() })
  if not d then return nil end
  local notes = ns.Notes and ns.Notes.newSince and ns.Notes.newSince(baseline.at) or 0
  local crowns = {}
  local nowCrowns = crownsNow()
  if nowCrowns then crowns = Logic.crownChanges(baseline.crowns, nowCrowns, ns.StatsDefs.AWARDS) end
  local lines = Logic.lines(d, notes, crowns, G.display)
  if #lines == 0 then return nil end
  for _, l in ipairs(lines) do
    if l.kind == "calendar" and ns.Calendar then
      l.onClick = function() ns.Calendar.open() end
    elseif l.kind == "crown" then
      local tab = l.tab
      l.onClick = function() openShame(tab) end
    end
  end
  return Logic.goneText(d.gone), Logic.cap(lines)
end

local function show(sub, lines)
  if not card then card = AwayCard.newCard("TwizCrewAwayCard", I .. "INV_Misc_PocketWatch_01", "While you were away", true) end
  card.fill(sub, lines)
  last = { sub = sub, lines = lines }
end

local function showNow()
  if not wanted() then done = true return end
  local sub, lines = work()
  if sub then show(sub, lines) end
  done = true
end

-- Works out this session's card once: WAIT s after login, with a whole list (or, at the CAP, with a complete one).
local function decide(final)
  if decided or not started or ns.now() - startedAt < WAIT - 1 then return end -- (timers run a hair early)
  local G = ns.Guild
  local ready = G.active() and G.complete()
  if not ready or (not G.whole() and not final) then
    if final then decided, done = true, true end -- (no card this session; a later logout may still save the list)
    return
  end
  decided = true
  if wanted() and baseline then AwayCard.whenFree(showNow) else done = true end
end

-- At logout (and before a /reload): this guild's list and crowns for the next login. A whole list replaces the
-- snapshot only when it has at least KEEP of its members (a list of only the online members can look whole); else it
-- is merged in like a list that may lack the offline members.
local KEEP = 0.8
local function save()
  if not done or not ns.db then return end
  local G = ns.Guild
  if not G.active() or not G.complete() then return end
  local guild, at = G.here(), ns.wallclock()
  local old = store().snap
  local snap
  local list = AwayCard.memberList()
  local had = 0
  if type(old) == "table" and old.guild == guild and type(old.members) == "table" then
    for _ in pairs(old.members) do had = had + 1 end
  end
  if G.whole() and #list >= had * KEEP then
    snap = Logic.snapshot(list, at, guild)
    if type(old) == "table" and old.guild == guild then snap.crowns = old.crowns end
  else
    snap = Logic.merge(old, list, at, guild)
  end
  if not snap then return end
  local crowns = crownsNow()
  if crowns then snap.crowns = crowns end
  store().snap = snap
end

function AwayCard.start()
  if started then return end
  started = true
  startedAt = ns.now()
  local snap = ns.db and type(ns.db.away) == "table" and ns.db.away.snap or nil
  baseline = type(snap) == "table" and snap or nil
  ns.Bus.on(FEATURE, "GUILD_LIST", function() decide(false) end)
  ns.Events.on(FEATURE, "PLAYER_LOGOUT", save)
  C_Timer.After(WAIT, function() ns.Log.safe(FEATURE, decide, false) end)
  C_Timer.After(CAP, function() ns.Log.safe(FEATURE, decide, true) end)
end

-- The wrench menu: the card shown this session, again.
function AwayCard.hasCard() return last ~= nil end
function AwayCard.reshow() if last then show(last.sub, last.lines) end end

-- Test hooks.
function AwayCard.isShown() return card ~= nil and card.frame:IsShown() and true or false end
function AwayCard.shownForTest() return last end
function AwayCard.clickLineForTest(i)
  local r = card and card.rows[i]
  if r and r:IsShown() then r._scripts.OnClick(r, "LeftButton") end
end
function AwayCard.frameForTest() return card and card.frame end
