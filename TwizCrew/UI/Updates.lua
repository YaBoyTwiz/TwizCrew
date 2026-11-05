-- "Tell crew to update": the request (UPDREQ) out and in, the small window with Reload now, and the line after a
-- reload. Registers the module "updates" (Update reminders): what you see. Sending works whether it is on or not.
-- The rules live in Core/UpdateLogic.lua.
local _, ns = ...

local Updates = {}
ns.Updates = Updates

local FEATURE = "updates"
local LOGIN_FEATURE = "updatecheck" -- the after-login check runs even when the module is off (restart line)
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local Logic = ns.UpdateLogic
local WIDTH, HEIGHT, PAD = 330, 104, 12

local shown = {}      -- version -> time its window was shown (this session)
local lastPress       -- time the button was last pressed
local lastHeard       -- { name, ver, at } the last request accepted (for /tc report)
local waiting         -- a request held until the fight ends
local current         -- the request whose window is open
local frame, title, note, reloadButton, closeButton

local function inFight()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return true end
  if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then return true end
  return false
end

local function members() return ns.roster and ns.roster:members() or {} end

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
  title:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
  title:SetJustifyH("LEFT")
  note = T.text(frame, T.FONT.small, C.text)
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  note:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
  note:SetJustifyH("LEFT")
  reloadButton = Widgets.button(frame, "Reload now", reloadClick, nil, FEATURE)
  reloadButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 10)
  closeButton = Widgets.button(frame, "Later", hide, nil, FEATURE)
  closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)
  frame:Hide()
end

local function show(req)
  if not frame then build() end
  local p = Logic.prompt(ns.Util.safeText(req.name), ns.Util.safeText(req.ver), Logic.needsRestart(ns.VERSION, req.rs))
  current = { name = req.name, ver = req.ver, title = p.title, note = p.note, reload = p.reload }
  title:SetText(p.title)
  note:SetText(p.note)
  if p.reload then reloadButton:Show() else reloadButton:Hide() end
  closeButton.text:SetText(p.reload and "Later" or "OK")
  refreshReload()
  frame:Show()
end

---------------------------------------------------------------------------------------------------- receiving
local function remember(req)
  local saved = ns.db and ns.db.update
  if type(saved) ~= "table" then return end
  if ns.Util.isVersion(saved.told) and ns.Util.compareVersions(req.ver, saved.told) <= 0 then return end
  saved.told, saved.by, saved.rs, saved.at = req.ver, req.name, ns.Util.isVersion(req.rs) and req.rs or nil,
    ns.wallclock()
end

local function onRequest(sender, fields)
  if ns.Version and ns.Version.seen then ns.Version.seen(sender, fields.ver) end
  local req = { sender = sender, name = sender, ver = fields.ver, rs = fields.rs }
  local ok, why = Logic.accept(req, {
    myVersion = ns.VERSION, enabled = ns.Modules.isEnabled(FEATURE),
    isCrew = ns.roster ~= nil and ns.roster:get(sender) ~= nil,
    shown = shown, now = ns.now(), repeatGap = ns.Config.UPDATE_REPEAT_GAP,
  })
  if not ok then
    ns.Log.add("info", "update request from %s (v%s) ignored: %s", tostring(sender), tostring(fields.ver), why)
    return
  end
  if current and ns.Util.compareVersions(req.ver, current.ver) < 0 then
    ns.Log.add("info", "update request from %s ignored: v%s is already shown", sender, tostring(current.ver))
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

ns.Comm.on("UPDREQ", onRequest)

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
  info = "When a friend with a newer TwizCrew presses \"Tell crew to update\", you get a small window with a "
    .. "Reload button, and after the reload a reminder if you are still on the old version. Turn off to never "
    .. "get these.",
  onEnable = function()
    ns.Events.on(FEATURE, "PLAYER_REGEN_ENABLED", onFightEnd)
    ns.Events.on(FEATURE, "PLAYER_REGEN_DISABLED", refreshReload)
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
  return "Update: addon list says v" .. tostring(ns.TOC_VERSION or "?") .. ", restart needed since v"
    .. tostring(ns.RESTART_SINCE) .. ", last request heard: " .. heard
end

-- Test hooks.
function Updates.promptForTest()
  if not current then return nil end
  return { title = current.title, note = current.note, reload = current.reload }
end
function Updates.reloadButtonForTest() return reloadButton end
function Updates.closeForTest() hide() end
