-- "Tell crew to update": the request (UPDREQ) out and in, the small window with Reload now, and the line after a
-- reload. Also the update notice: the same window, once per new version, when any crew member runs a newer
-- version (heard in HELLO / STATE), plus Updates.available() for the minimap badge and the panel line.
-- Registers the module "updates" (Update reminders): what you see. Sending works whether it is on or not.
-- The rules live in Core/UpdateLogic.lua.
local _, ns = ...

local Updates = {}
ns.Updates = Updates

local FEATURE = "updates"
local LOGIN_FEATURE = "updatecheck" -- the after-login check runs even when the module is off (restart line)
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local Logic = ns.UpdateLogic
local WIDTH, HEIGHT, PAD = 330, 112, 12

local shown = {}      -- version -> time its window was shown (this session)
local lastPress       -- time the button was last pressed
local lastHeard       -- { name, ver, at } the last request accepted (for /tc report)
local waiting         -- a request held until the fight ends
local current         -- the request whose window is open
local noticeWait = 0  -- counts the notice's waits: only the latest one may show it
local frame, title, note, reloadButton, closeButton
local testShown       -- the test tools' pretend version a pop-up was shown for: memory only, never saved

local function inFight()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return true end
  return false
end

local function members() return ns.roster and ns.roster:members() or {} end

local function cmp(a, b) return ns.Util.compareVersions(a, b) end
local isVersion = function(v) return ns.Util.isVersion(v) end

-- The newest version an update pop-up (notice or Tell crew) was shown for. Saved: once per version.
-- For a pretend version (test tools, newest.name is a fake) the mark lives in memory only.
local function shownUpTo(newest)
  if type(newest) == "table" and ns.isTestName(newest.name) then return testShown end
  local saved = ns.db and ns.db.updateNotice
  return type(saved) == "table" and saved.shown or nil
end

local function markShown(ver, name)
  if ns.isTestName(name) then
    if isVersion(ver) then testShown = ver end
    return
  end
  local saved = ns.db and ns.db.updateNotice
  if type(saved) ~= "table" or not isVersion(ver) then return end
  if not isVersion(saved.shown) or cmp(ver, saved.shown) > 0 then saved.shown = ver end
end

---------------------------------------------------------------------------------------------------- sending
-- The button in the settings window. Returns true when the request went out.
function Updates.tellCrew()
  local left = Logic.cooldownLeft(lastPress, ns.now(), ns.Config.UPDATE_BUTTON_COOLDOWN)
  if left > 0 then
    print("TwizCrew: already sent. You can send it again in " .. left .. " s.")
    return false
  end
  lastPress = ns.now()
  ns.Comm.send("UPDREQ", { ver = ns.VERSION, rs = ns.RESTART_SINCE })
  local n = Logic.behind(ns.VERSION, members())
  local who
  if n == 0 then who = "Nobody online is known to be on an older version."
  elseif n == 1 then who = "1 friend online is on an older version."
  else who = n .. " friends online are on an older version." end
  print("TwizCrew: told your crew that v" .. ns.VERSION .. " is out. " .. who)
  ns.Log.add("info", "update request sent: v%s, restart since v%s", ns.VERSION, tostring(ns.RESTART_SINCE))
  return true
end

---------------------------------------------------------------------------------------------------- the window
local function hide()
  current = nil
  if frame then frame:Hide() end
end

local function refreshReload()
  if reloadButton then reloadButton:SetAlpha(inFight() and 0.45 or 1) end
end

-- Only ever runs from a click on Reload now.
local function reloadClick()
  if not current or not current.reload then return end
  if inFight() then
    print("TwizCrew: not during a fight. Click Reload now again when the fight is over.")
    return
  end
  ns.Log.add("info", "reload clicked for v%s", tostring(current.ver))
  if type(ReloadUI) == "function" then
    ReloadUI()
  elseif C_UI and type(C_UI.Reload) == "function" then
    C_UI.Reload()
  else
    ns.Log.add("warn", "update: no way to reload in this game version")
    print("TwizCrew: type /reload to load the new version.")
  end
end

local function build()
  frame = T.frame("Frame", "TwizCrewUpdate", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -170)
  frame:SetFrameStrata("DIALOG")
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  Widgets.script(frame, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  Widgets.script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end, FEATURE)
  Widgets.script(frame, "OnHide", function() current = nil end, FEATURE)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewUpdate") end -- Escape closes it
  title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
  title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
  title:SetJustifyH("LEFT")
  note = T.text(frame, T.FONT.small, C.text)
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  note:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -8)
  note:SetJustifyH("LEFT")
  reloadButton = Widgets.button(frame, "Reload now", reloadClick, nil, FEATURE)
  reloadButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 10)
  closeButton = Widgets.button(frame, "Later", hide, nil, FEATURE)
  closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)
  frame:Hide()
end

-- req = { kind = "notice" | nil (a Tell crew request), name, ver, rs }. One window: a newer show replaces it.
local function show(req)
  if not frame then build() end
  local name, ver = ns.Util.safeText(req.name), ns.Util.safeText(req.ver)
  local p
  if req.kind == "notice" then
    p = Logic.notice(name, ver, ns.VERSION, req.rs)
  else
    p = Logic.prompt(name, ver, Logic.needsRestart(ns.VERSION, req.rs))
  end
  current = { kind = req.kind, name = req.name, ver = req.ver, title = p.title, note = p.note, reload = p.reload }
  markShown(req.ver, req.name)
  title:SetText(p.title)
  note:SetText(p.note)
  if p.reload then reloadButton:Show() else reloadButton:Hide() end
  closeButton.text:SetText(p.reload and "Later" or "OK")
  refreshReload()
  frame:Show()
end

---------------------------------------------------------------------------------------------------- receiving
local function remember(req)
  if ns.isTestName(req.name) then return end -- a pretend update (test tools) is never saved
  local saved = ns.db and ns.db.update
  if type(saved) ~= "table" then return end
  if isVersion(saved.told) and cmp(req.ver, saved.told) <= 0 then return end
  local rs = isVersion(req.rs) and req.rs or nil
  if req.kind == "notice" then rs = Logic.safeRestartSince(req.rs, req.ver) end -- unknown: restart to be safe
  saved.told, saved.by, saved.rs, saved.at = req.ver, req.name, rs, ns.wallclock()
end

local function newerThan(req, other)
  return not other or ns.Util.compareVersions(req.ver, other.ver) >= 0
end

local function handleRequest(sender, fields)
  local isCrew = ns.roster ~= nil and ns.roster:get(sender) ~= nil
  if isCrew and ns.Util.isVersion(fields.ver) and ns.Version and ns.Version.seen then
    ns.Version.seen(sender, fields.ver, fields.rs)
  end
  local req = { sender = sender, name = sender, ver = fields.ver, rs = fields.rs }
  local ok, why = Logic.accept(req, {
    myVersion = ns.VERSION, enabled = ns.Modules.isEnabled(FEATURE),
    isCrew = isCrew,
    shown = shown, now = ns.now(), repeatGap = ns.Config.UPDATE_REPEAT_GAP,
  })
  if not ok then
    ns.Log.add("info", "update request from %s (v%s) ignored: %s", tostring(sender), tostring(fields.ver), why)
    return
  end
  local ahead = (current and not newerThan(req, current)) and current or (waiting and not newerThan(req, waiting)
    and waiting) or nil
  if ahead then
    ns.Log.add("info", "update request from %s ignored: v%s is newer", sender, tostring(ahead.ver))
    return
  end
  shown[req.ver] = ns.now()
  lastHeard = { name = sender, ver = req.ver, at = ns.wallclock() }
  remember(req)
  ns.Log.add("info", "update request from %s: v%s (restart since v%s)", sender, req.ver, tostring(req.rs))
  if inFight() then
    waiting = req -- shown when the fight is over
    return
  end
  show(req)
end

local function onFightEnd()
  refreshReload()
  if waiting and not inFight() then
    local req = waiting
    waiting = nil
    show(req)
  end
end

-- Under this module's own error guard (Comm's guard is the essential "comm", which never turns off).
ns.Comm.on("UPDREQ", function(sender, fields) ns.Log.safe(FEATURE, handleRequest, sender, fields) end)

---------------------------------------------------------------------------------------------------- update notice
-- The newest version heard ({ name, ver, rs }) while it is newer than ours and Update reminders is on, else nil.
-- The minimap badge and the panel line ask this (inside their own ns.Log.safe).
function Updates.available()
  local newest = ns.Version and ns.Version.newest and ns.Version.newest() or nil
  return Logic.available(ns.VERSION, newest, ns.Modules.isEnabled(FEATURE))
end

local function newestOpen()
  local a, b = current and current.ver, waiting and waiting.ver
  if isVersion(a) and isVersion(b) then return cmp(a, b) >= 0 and a or b end
  return isVersion(a) and a or (isVersion(b) and b or nil)
end

local function checkNotice()
  local newest = ns.Version and ns.Version.newest and ns.Version.newest() or nil
  local ok, why = Logic.showNotice(newest, {
    myVersion = ns.VERSION, enabled = ns.Modules.isEnabled(FEATURE), shown = shownUpTo(newest), open = newestOpen(),
  })
  if not ok then
    if why ~= "none" then ns.Log.add("info", "update notice for v%s not shown: %s", tostring(newest.ver), why) end
    return
  end
  local req = { kind = "notice", name = newest.name, ver = newest.ver, rs = newest.rs }
  remember(req)
  ns.Log.add("info", "update notice: v%s from %s (restart since v%s)", req.ver, req.name, tostring(req.rs))
  if inFight() then
    waiting = req -- shown when the fight is over
    return
  end
  show(req)
end

-- A short wait first, so a "Tell crew to update" pressed right away shows its own window instead (it then counts
-- as shown and the notice stays quiet). Each news (a newer version, its rs learned) starts the wait again.
local function scheduleNotice()
  noticeWait = noticeWait + 1
  local mine = noticeWait
  C_Timer.After(ns.Config.UPDATE_NOTICE_DELAY, function()
    if mine == noticeWait then ns.Log.safe(FEATURE, checkNotice) end
  end)
end

-- The how-to window on demand (the panel's gold line). Returns whether there was an update to show.
function Updates.showHowTo()
  local up = Updates.available()
  if not up then return false end
  local req = { kind = "notice", name = up.name, ver = up.ver, rs = up.rs }
  remember(req)
  show(req)
  return true
end

---------------------------------------------------------------------------------------------------- after a login
-- Taken at login and forgotten at once, so a request heard in the first seconds is kept for the next login.
local function checkAfterLogin()
  local saved = ns.db and ns.db.update
  local told = type(saved) == "table" and { told = saved.told, rs = saved.rs } or nil
  if ns.db then ns.db.update = {} end
  if not ns.Modules.isEnabled(FEATURE) then told = nil end
  local lines = Logic.afterLogin(ns.VERSION, told, ns.TOC_VERSION, ns.RESTART_SINCE)
  if #lines == 0 then return end
  C_Timer.After(ns.Config.UPDATE_LOGIN_DELAY, function()
    ns.Log.safe(LOGIN_FEATURE, function()
      for _, line in ipairs(lines) do
        print("TwizCrew: " .. line)
        ns.Log.add("info", "after login: %s", line)
      end
    end)
  end)
end

ns.Events.on(LOGIN_FEATURE, "PLAYER_LOGIN", checkAfterLogin)

---------------------------------------------------------------------------------------------------- module
ns.Modules.register({
  id = FEATURE, name = "Update reminders", tier = "module",
  info = "Tells you when a friend has a newer TwizCrew: a gold ! on the minimap button, a gold line on the Crew "
    .. "panel, and once per new version a small window that says how to update (with a Reload button when that "
    .. "is enough). Also the window you get when a friend presses \"Tell crew to update\", and a reminder after "
    .. "a reload if you are still on the old version. Turn off to never get these. The version number stays.",
  onEnable = function()
    ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", onFightEnd)
    ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", refreshReload)
    ns.Bus.on(FEATURE, "UPDATE_SEEN", scheduleNotice)
    scheduleNotice() -- turned on with an update already known: its pop-up (if not shown before) comes too
  end,
  onDisable = function()
    waiting = nil
    hide()
  end,
})

-- /tc report line.
function Updates.reportLine()
  local heard = "none"
  if lastHeard then
    heard = "v" .. ns.Util.safeText(lastHeard.ver) .. " from " .. ns.Util.safeText(lastHeard.name) .. ", "
      .. ns.Util.ago(math.max(0, ns.wallclock() - lastHeard.at))
  end
  local newest = ns.Version and ns.Version.newest and ns.Version.newest()
  local newestText = "none"
  if newest then
    newestText = "v" .. ns.Util.safeText(newest.ver) .. " from " .. ns.Util.safeText(newest.name)
      .. " (restart since " .. (newest.rs and ("v" .. newest.rs) or "unknown") .. ")"
  end
  local popup = isVersion(shownUpTo()) and ("v" .. shownUpTo()) or "none"
  return "Update: addon list says v" .. tostring(ns.TOC_VERSION or "?") .. ", restart needed since v"
    .. tostring(ns.RESTART_SINCE) .. ", last request heard: " .. heard .. ", newest heard: " .. newestText
    .. ", pop-up shown for: " .. popup
end

-- Test tools' Clear: forgets the pretend version's pop-up mark and closes its window. Returns whether a window was
-- open or waiting for it.
function Updates.clearTest()
  testShown = nil
  local had = false
  if waiting and ns.isTestName(waiting.name) then waiting = nil; had = true end
  if current and ns.isTestName(current.name) then hide(); had = true end
  return had
end

-- Test hooks.
function Updates.promptForTest()
  if not current then return nil end
  return { title = current.title, note = current.note, reload = current.reload }
end
function Updates.reloadButtonForTest() return reloadButton end
function Updates.closeForTest() hide() end
