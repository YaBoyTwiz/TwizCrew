-- /tc report: a short health check, printed in chat and put in a box to copy (for Discord or for Claude).
local _, ns = ...

local Report = {}
ns.Report = Report

local FEATURE = "report"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, HEIGHT, PAD, LINE_HEIGHT = 480, 320, 12, 14
local CHAT_LINES = 5 -- the first lines also go to chat

local frame, edit, scroll
local shownText = ""

local function yes(v) return v and "yes" or "no" end

local function try(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function interface()
  local ok, _, _, _, n = try(GetBuildInfo)
  return ok and n and tostring(n) or "unknown"
end

local function connection()
  local s = ns.Transport.status()
  local state
  if s.failed then state = "failed: " .. tostring(s.failReason)
  elseif s.joined then state = "joined"
  else state = "not joined" end
  return "Connection: " .. tostring(s.mode) .. " (channel " .. tostring(s.channel) .. " " .. state .. ")"
end

local function layer()
  local i = ns.LayerSensor.info()
  local seen = type(i.age) == "number" and ns.Util.ago(i.age) or "never"
  return "Layer: key " .. tostring(i.key or "none") .. ", seen " .. seen .. ", " .. tostring(i.secretSkipped or 0)
    .. " hidden values skipped"
end

local function heard(m)
  if type(m.lastHeard) == "number" then return ns.Util.ago(ns.now() - m.lastHeard) end
  if type(m.lastSeen) == "number" then return ns.Util.ago(ns.wallclock() - m.lastSeen) end
  return "never"
end

local function crewLines(add)
  if not ns.roster then return end
  for _, name in ipairs(ns.roster:names()) do
    local m = ns.roster:get(name)
    add(name .. ": " .. (m.online and "online" or "offline") .. ", heard " .. heard(m) .. ", v"
      .. tostring(m.version or "?"))
  end
end

-- Extra lines that answer the in-game checks of the test list (docs/TESTING.md) in one paste.
local function checkLines(add)
  local function call(fn, ...)
    local ok, a, b = try(fn, ...)
    if ok then return a, b end
  end
  local inInstance, kind = call(IsInInstance)
  add("Game says: flying " .. yes(call(UnitOnTaxi, "player")) .. ", away " .. yes(call(UnitIsAFK, "player"))
    .. ", in a dungeon " .. yes(inInstance) .. " (" .. tostring(kind or "none") .. "), fighting "
    .. yes(call(UnitAffectingCombat, "player")) .. ", dead " .. yes(call(UnitIsDeadOrGhost, "player")))
  add("Where: " .. tostring(call(GetRealZoneText) or "?") .. ", " .. tostring(call(GetSubZoneText) or "?"))
  local api = Settings
  add("Game features: options list " .. yes(type(api) == "table" and type(api.RegisterAddOnCategory) == "function")
    .. ", invite " .. yes((C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit)
    .. ", secret check " .. yes(type(issecretvalue) == "function")
    .. ", atlas check " .. yes(C_Texture and C_Texture.GetAtlasInfo)
    .. ", chat filter " .. yes(type(ChatFrame_AddMessageEventFilter) == "function"))
  local s = ns.Transport.status()
  add("Channel: number " .. tostring(s.channelIndex or 0) .. ", last send result "
    .. tostring(s.lastResult == nil and "none" or s.lastResult))
  local i = ns.LayerSensor.info()
  add("Layer looks: " .. tostring(i.observations or 0) .. " NPCs read, waiting to confirm "
    .. tostring(i.pending or "nothing"))
  add("Log: " .. #ns.Log.lines() .. " lines kept (written to disk at /reload or logout)")
end

function Report.lines()
  local out = {}
  local function add(s) out[#out + 1] = s end
  add("TwizCrew v" .. ns.VERSION .. ", interface " .. interface())
  add(connection())
  add(layer())
  add("Class icons: " .. tostring(ns.ClassIcon.method()))
  local broken = ns.Modules.broken()
  add("Turned off after errors: " .. (#broken > 0 and table.concat(broken, ", ") or "none"))
  crewLines(add)
  add("Recent errors:")
  local errors = ns.Log.errors(10)
  if #errors == 0 then add("none") end
  for _, e in ipairs(errors) do add(e) end
  add("In-game checks:")
  checkLines(add)
  return out
end

---------------------------------------------------------------------------------------------------- copy box
local function selectAll()
  edit:SetFocus()
  edit:HighlightText()
end

local function build()
  frame = T.frame("Frame", "TwizCrewReport", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  Widgets.script(frame, "OnDragStart", function(self) self:StartMoving() end, FEATURE)
  Widgets.script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end, FEATURE)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewReport") end -- Escape

  local title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
  title:SetText("TwizCrew report")
  local hint = T.text(frame, T.FONT.small, C.muted)
  hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -12)
  hint:SetText("Press Ctrl+C to copy")

  scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -32)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 40)
  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  if edit.SetFontObject then edit:SetFontObject(T.FONT.small) end
  edit:SetWidth(WIDTH - 2 * PAD)
  scroll:SetScrollChild(edit)
  -- The box is for copying only: typing puts the report back and selects it again.
  Widgets.script(edit, "OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(shownText)
      self:HighlightText()
    end
  end, FEATURE)
  Widgets.script(edit, "OnEscapePressed", function() frame:Hide() end, FEATURE)
  Widgets.script(edit, "OnMouseUp", selectAll, FEATURE)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  Widgets.script(scroll, "OnMouseWheel", function(self, delta)
    local most = math.max(0, (tonumber(edit:GetHeight()) or 0) - (tonumber(self:GetHeight()) or 0))
    local v = (tonumber(self:GetVerticalScroll()) or 0) - (tonumber(delta) or 0) * 3 * LINE_HEIGHT
    self:SetVerticalScroll(math.max(0, math.min(most, v)))
  end, FEATURE)

  local close = Widgets.button(frame, "Close", function() frame:Hide() end, nil, FEATURE)
  close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)
  frame:Hide()
end

-- Shows the report in the copy box with all the text selected, and the first lines in chat.
function Report.show()
  local lines = Report.lines()
  local safe = {}
  for i, line in ipairs(lines) do safe[i] = ns.Util.safeText(line) end
  for i = 1, math.min(CHAT_LINES, #safe) do print("TwizCrew: " .. safe[i]) end
  print("TwizCrew: the full report is in the box. Press Ctrl+C to copy it.")
  if not frame then build() end
  shownText = table.concat(safe, "\n")
  edit:SetHeight(#safe * LINE_HEIGHT + 10)
  edit:SetText(shownText)
  frame:Show()
  scroll:SetVerticalScroll(0)
  selectAll()
end
