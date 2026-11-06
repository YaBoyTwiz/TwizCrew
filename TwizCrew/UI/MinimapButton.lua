-- The round TwizCrew button on the minimap's edge (essential "minimap") and the addon compartment entry.
-- Left-click: the settings window (like /tc). Right-click: show or hide the Crew panel. Drag: move it around the
-- edge (the angle is saved when the drag ends). A small gold "!" while a friend has a newer TwizCrew (and Update
-- reminders is on). Plain frames only, every script inside ns.Log.safe.
-- The maths lives in UI/MinimapLogic.lua; the icon and starting angle in ns.Config (MINIMAP_ICON, MINIMAP_ANGLE).
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local FEATURE = "minimap"
local Logic, T, Widgets = ns.MinimapLogic, ns.Theme, ns.Widgets
local C = T.COLOR
local NAME = "TwizCrewMinimapButton" -- "...MinimapButton": minimap-button collector addons look for this
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local OPEN_FAILED = "TwizCrew: the settings window could not open. Type /tc report for details."
local OPEN_FAILED_FIGHT = "TwizCrew: the settings window could not open during this fight. Try again when it ends."

local button, badge
local badgeShown = false
local dragging = false
local dragAngle            -- where the drag has the button now (saved at the end)
local iconMissing = false
local noMinimapLogged = false

local function setting(key) return ns.Modules.setting(FEATURE, key) end
local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

-- A secret value (Midnight rules) can be shown but not used in maths: treat it as unknown.
local function readable(v)
  if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
  return v
end

local function minimapShape()
  if type(GetMinimapShape) ~= "function" then return "ROUND" end
  local ok, shape = pcall(GetMinimapShape)
  return ok and readable(shape) or "ROUND"
end

local function place(angle)
  if not button then return end
  local x, y = Logic.offset(angle or setting("angle"), minimapShape(), readable(Minimap:GetWidth()),
    readable(Minimap:GetHeight()))
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- The update Update reminders knows about, asked inside its own guard: an error there means "none", never a broken
-- button.
local function availableUpdate()
  if not ns.Updates or not ns.Updates.available then return nil end
  local ok, up = ns.Log.safe("updates", ns.Updates.available)
  if ok and type(up) == "table" then return up end
  return nil
end

local function refreshBadge()
  if not badge then return end
  badgeShown = availableUpdate() ~= nil
  if badgeShown then badge:Show() else badge:Hide() end
end

---------------------------------------------------------------------------------------------------- clicks, tooltip
function MinimapButton.click(mouseButton)
  if mouseButton == "RightButton" then
    ns.Commands.setPanel(not ns.Modules.isEnabled("panel"), true)
    return
  end
  if not ns.Log.safe(FEATURE, ns.Settings.toggle) then
    local fighting = type(InCombatLockdown) == "function" and InCombatLockdown()
    print(fighting and OPEN_FAILED_FIGHT or OPEN_FAILED)
  end
end

local function showTip(owner, withDrag)
  if not GameTooltip or not owner or dragging then return end
  local online, total = 0, 0
  if ns.roster then online, total = ns.roster:onlineCount() end
  local lines = Logic.tooltipLines(online, total, ns.Modules.isEnabled("panel"), withDrag,
    { version = ns.VERSION, update = availableUpdate() })
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText(lines[1], T.rgb(C.title))
  local r, g, b = T.rgb(C.text)
  for i = 2, #lines do
    if i == lines.attention then
      GameTooltip:AddLine(lines[i], T.rgb(C.title))
    else
      GameTooltip:AddLine(lines[i], r, g, b)
    end
  end
  GameTooltip:Show()
end

local function hideTip()
  if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------------------------------- drag
local function stopDrag(save)
  if not dragging then return end
  dragging = false
  button:SetScript("OnUpdate", nil)
  local angle = dragAngle
  dragAngle = nil
  if save and angle then ns.Modules.set(FEATURE, "angle", angle) end
end

local function dragStep()
  local cx, cy = GetCursorPosition()
  local mx, my = Minimap:GetCenter()
  local angle = Logic.angleFromCursor(readable(cx), readable(cy), readable(Minimap:GetEffectiveScale()),
    readable(mx), readable(my))
  if angle then
    dragAngle = angle
    place(angle)
  end
end

local function startDrag()
  hideTip()
  dragging = true
  -- An error here would repeat every frame: the first one ends the drag instead.
  button:SetScript("OnUpdate", function()
    if not ns.Log.safe(FEATURE, dragStep) then
      dragAngle = nil
      stopDrag(false)
    end
  end)
end

---------------------------------------------------------------------------------------------------- the button
local function texture(layer, path, size, x, y)
  local t = button:CreateTexture(nil, layer)
  t:SetTexture(path)
  t:SetSize(size, size)
  t:SetPoint("TOPLEFT", button, "TOPLEFT", x, y)
  return t
end

-- The game's own minimap-button pieces: dark disc, icon, round gold border, glow on hover.
local function build()
  if not Minimap then
    if not noMinimapLogged then
      noMinimapLogged = true
      ns.Log.add("warn", "minimap: this game has no minimap frame, so there is no minimap button")
    end
    return false
  end
  button = CreateFrame("Button", NAME, Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel((tonumber(readable(Minimap:GetFrameLevel())) or 0) + 8)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  texture("BACKGROUND", "Interface\\Minimap\\UI-Minimap-Background", 20, 7, -5)
  local icon = texture("ARTWORK", ns.Config.MINIMAP_ICON, 17, 7, -6)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the icon's own dark edge
  if icon:GetTexture() == nil then
    iconMissing = true
    icon:SetTexture(FALLBACK_ICON)
    ns.Log.add("warn", "minimap: icon %s is missing in this game, showing a question mark", ns.Config.MINIMAP_ICON)
  end
  texture("OVERLAY", "Interface\\Minimap\\MiniMap-TrackingBorder", 53, 0, 0)
  -- the update badge: a gold "!" at the icon's top-right, above the ring
  badge = T.text(button, "GameFontNormalLarge", C.title, "OVERLAY")
  if badge.SetDrawLayer then badge:SetDrawLayer("OVERLAY", 7) end
  badge:SetPoint("CENTER", button, "TOPLEFT", 25, -7)
  badge:SetText("!")
  badge:Hide()
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  script(button, "OnClick", function(_, which) MinimapButton.click(which) end)
  script(button, "OnEnter", function(self) showTip(self, true) end)
  script(button, "OnLeave", hideTip)
  script(button, "OnDragStart", startDrag)
  script(button, "OnDragStop", function() stopDrag(true) end)
  script(button, "OnHide", function() stopDrag(false) end)
  return true
end

-- Shows or hides the button to match the "show" setting (made the first time it is shown).
local function apply()
  if setting("show") then
    if not button and not build() then return end
    place()
    refreshBadge()
    button:Show()
  elseif button then
    stopDrag(false)
    button:Hide()
  end
end

-- Saved values of the wrong type (an old or damaged file) go back to the defaults, so later saves are accepted.
local function repair()
  local e = ns.db and ns.db.modules and ns.db.modules[FEATURE]
  if type(e) ~= "table" or type(e.settings) ~= "table" then return end
  if type(e.settings.show) ~= "boolean" then e.settings.show = true end
  if Logic.normalize(e.settings.angle) == nil then e.settings.angle = ns.Config.MINIMAP_ANGLE end
end

-- /tc minimap: turns the button on or off. Returns whether it is now on.
function MinimapButton.toggleShown()
  ns.Modules.set(FEATURE, "show", not setting("show"))
  return setting("show") and true or false
end

function MinimapButton.badgeShownForTest() return badgeShown end

-- /tc report line.
function MinimapButton.reportLine()
  if not setting("show") then return "Minimap button: hidden (/tc minimap shows it)" end
  if not button then return "Minimap button: on, but this game has no minimap to put it on" end
  return "Minimap button: shown at " .. tostring(Logic.angleOrDefault(setting("angle"))) .. " degrees, icon "
    .. (iconMissing and "missing (showing a question mark)" or "ok")
end

ns.Modules.register({
  id = FEATURE, name = "Minimap button", tier = "essential",
  info = "A round TwizCrew button on the edge of the minimap. Left-click opens these settings, right-click shows "
    .. "or hides the Crew panel. Drag it to move it around the minimap.",
  defaults = { show = true, angle = ns.Config.MINIMAP_ANGLE },
  settings = {
    { key = "show", label = "Show minimap button", kind = "toggle",
      info = "Shows the TwizCrew button on the minimap, so you can open these settings with a click instead of "
        .. "typing /tc. If you hide it, type /tc minimap to bring it back. TwizCrew is also in the minimap's "
        .. "AddOns list, if your game has one." },
  },
  onEnable = function()
    repair()
    apply()
    -- a minimap addon may change the shape while loading: place the button again after each loading screen
    ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() place() end)
    ns.Bus.on(FEATURE, "UPDATE_SEEN", refreshBadge)
    ns.Bus.on(FEATURE, "MODULE_TOGGLED", refreshBadge)
  end,
  onSettingChanged = function(key)
    if key == "show" then apply() elseif key == "angle" then place() end
  end,
})

---------------------------------------------------------------------------------------------------- addon compartment
-- The .toc's AddonCompartmentFunc lines name these. Clients without the compartment never call them.
function TwizCrew_OnAddonCompartmentClick(_, mouseButton)
  ns.Log.safe(FEATURE, MinimapButton.click, mouseButton)
end

function TwizCrew_OnAddonCompartmentEnter(_, owner)
  ns.Log.safe(FEATURE, showTip, owner, false)
end

function TwizCrew_OnAddonCompartmentLeave()
  ns.Log.safe(FEATURE, hideTip)
end
