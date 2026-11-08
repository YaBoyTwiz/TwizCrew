-- The settings window ("TwizCrewSettings"), built from the module registry, and the Options → AddOns entry.
-- Feature id "settings": part of the essentials, not a registered module.
-- Rows are made once and reused (game frames cannot be deleted); a rebuild only re-places them.
local _, ns = ...

local Win = {}
ns.Settings = Win

local FEATURE = "settings"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, PAD = 400, 14
local CONTENT_WIDTH = WIDTH - 2 * PAD
local HEADER = 84 -- title, version line and the Basics / Advanced tabs
local SUBTAB_ROW = 24 -- the Advanced tab's own row of sub-tabs
local FOOTER, CONFIRM = 40, 58
local ROW, MODULE_ROW, BROKEN_ROW, SECTION_ROW = 24, 26, 38, 26
local INDENT = { setting = 14, child = 32 }
local WHEEL_STEP = 40
local SECTIONS = {
  { tier = "essential", title = "Essentials", note = "always on, these make the rest work" },
  { tier = "module", title = "Modules", note = "turn on or off" },
  { tier = "extra", title = "Extras", note = "fun stuff, added over time" },
  { tier = "tools", title = "Try it out", note = "pretend friends and pop-ups, only on your screen" },
}
-- The Basics tab: a few everyday options. Everything (these too) is on the Advanced tab.
-- { module = id } is that module's on/off switch; { id, key } one of its settings.
local BASICS = {
  { title = "Look", note = "how the crew panel looks" },
  { id = "panel", key = "bgAlpha" },
  { id = "panel", key = "scale" },
  { id = "panel", key = "rowStyle" },
  { id = "panel", key = "fadeOut" },
  { id = "panel", key = "fadeAlpha" },
  { title = "Handy", note = "the things people change most" },
  { module = "panel" },
  { id = "panel", key = "showOffline" },
  { id = "panel", key = "locked" },
  { id = "panel", key = "hideInCombat" },
  { module = "popups" },
  { id = "tags", key = "autoAway" },
  { id = "tags", key = "awayMinutes" },
  { id = "roasts", key = "editMocks" },
  { id = "popups", key = "online" },
  { id = "minimap", key = "show" },
  { id = "panel", key = "whatsNew" },
  { title = "Find the crew", note = "arrows to your group and meet-ups" },
  { id = "find", key = "rowArrows" },
  { id = "find", key = "meetups" },
  { id = "find", key = "sharePosition" },
  { title = "Tools", note = "handy extras" },
  { id = "rankup", key = "update" },
  { id = "rankup", key = "showButton" },
}
local TABS = { { id = "basic", label = "Basics" }, { id = "advanced", label = "Advanced" } }
-- The Advanced tab's sub-tabs: which modules each shows, in that order. A module not listed lands on Crew.
-- "all" is the old single page with every section.
local SUBTABS = {
  { id = "panel", label = "Panel", modules = { "panel", "tags", "layer" } },
  { id = "roasts", label = "Roasts", modules = { "roasts", "stats" } },
  { id = "popups", label = "Pop-ups", modules = { "popups", "updates" } },
  { id = "find", label = "Find", modules = { "find" } },
  { id = "crew", label = "Crew", modules = { "comm", "version", "minimap", "pokes", "races" } },
  { id = "tools", label = "Tools", modules = { "rankup" } },
  { id = "test", label = "Test", modules = { "testtools" } },
  { id = "all", label = "All" },
}
Win.BROKEN_TEXT = "turned off after errors, /reload to try again"
local RESET_QUESTION = "Reset all TwizCrew settings and the panel position?"

local frame, scroll, content, subtitle, confirmBox, closeButton, resetButton
local tab = "basic"   -- the tab shown: "basic" or "advanced"
local sub = "panel"   -- the Advanced sub-tab shown
local tabButtons, subButtons = {}, {}

local function headerHeight() return tab == "advanced" and HEADER + SUBTAB_ROW or HEADER end
local isOpen, dirty, confirming = false, true, false
local rows = {}       -- cache key -> row frame
local placed = {}     -- rows placed by the last layout, in order
local described = {}  -- what the last layout drew (test hook)
local layouts = 0
local contentHeight, scrollOffset, scrollMax = 0, 0, 0
local optionsDone = false

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function settingDef(id, key)
  local d = ns.Modules.get(id)
  if not d then return nil end
  for _, s in ipairs(d.settings) do if s.key == key then return s end end
end

-- Saves one setting the way the window does. Text is trimmed and a blank text is refused.
-- Crew settings (store = "crew") land in ns.db.crew; the comm module's onSettingChanged then calls
-- Transport.rejoin(), so a new channel name or crew code takes effect at once.
function Win.save(id, key, value)
  local s = settingDef(id, key)
  if not s then return false end
  if s.kind == "text" then
    value = ns.Util.trim(tostring(value or ""))
    if value == "" then
      if isOpen then Win.refresh() end
      return false
    end
  end
  if value == ns.Modules.setting(id, key) then
    if isOpen then Win.refresh() end -- e.g. puts the trimmed text back in the box
    return false
  end
  return ns.Modules.set(id, key, value)
end

---------------------------------------------------------------------------------------------------- rows
local function cached(key, make)
  local r = rows[key]
  if not r then
    r = make()
    r.tcParent, r.tcModule = false, false
    rows[key] = r
  end
  return r
end

-- Fields refresh() reads; widget rows bring their own, plain frames get these.
local function plainRow(f)
  f.Refresh = function() end
  f.control = false
  return f
end

local function sectionRow(sec)
  return cached("section:" .. sec.tier, function()
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(CONTENT_WIDTH, SECTION_ROW)
    local title = T.text(f, T.FONT.normal, C.title)
    title:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 5)
    title:SetText(sec.title)
    local note = T.text(f, T.FONT.small, C.muted)
    note:SetPoint("LEFT", title, "RIGHT", 8, 0)
    note:SetText(sec.note)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    T.color(line, C.line, 1)
    return plainRow(f)
  end)
end

-- A module name with its (i) button and a note instead of a switch ("always on", or the broken text below it).
local function noteRow(def, text, below)
  local f = CreateFrame("Frame", nil, content)
  f:SetSize(CONTENT_WIDTH, below and BROKEN_ROW or MODULE_ROW)
  local label = T.text(f, T.FONT.normal, C.text)
  label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -6)
  label:SetText(def.name)
  local info = Widgets.infoButton(f, def.name, def.info)
  info:SetPoint("LEFT", label, "RIGHT", 2, 0)
  local note = T.text(f, T.FONT.small, below and C.dangerBorder or C.muted)
  if below then
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
  else
    note:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  end
  note:SetText(text)
  return plainRow(f)
end

local function moduleRow(def, broken)
  if def.tier == "essential" then
    return cached("module:" .. def.id .. ":always", function() return noteRow(def, "always on") end), "always on",
      MODULE_ROW
  end
  if def.comingSoon then
    return cached("module:" .. def.id .. ":soon", function()
      local r = Widgets.toggle(content, def.name, def.info, function() return false end, function() end)
      r.label:SetFontObject(T.FONT.normal)
      local note = T.text(r, T.FONT.small, C.muted)
      note:SetPoint("RIGHT", r, "RIGHT", -42, 0)
      note:SetText("coming later")
      r:SetActive(false)
      return r
    end), "coming later", MODULE_ROW
  end
  if def.tier == "tools" and not broken then
    return cached("module:" .. def.id .. ":tools", function() return noteRow(def, "only on your screen") end), "tools",
      MODULE_ROW
  end
  if broken then
    return cached("module:" .. def.id .. ":broken", function() return noteRow(def, Win.BROKEN_TEXT, true) end),
      "broken", BROKEN_ROW
  end
  return cached("module:" .. def.id .. ":switch", function()
    local r = Widgets.toggle(content, def.name, def.info,
      function() return ns.Modules.isEnabled(def.id) end,
      function(on) ns.Modules.setEnabled(def.id, on) end)
    r.label:SetFontObject(T.FONT.normal)
    return r
  end), "switch", MODULE_ROW
end

local function wholeNumber(v) return tostring(math.floor(v + 0.5)) end

local function settingRow(def, s)
  return cached("setting:" .. def.id .. ":" .. s.key, function()
    local id, key = def.id, s.key
    local function get() return ns.Modules.setting(id, key) end
    local function set(v) Win.save(id, key, v) end
    local r
    if s.kind == "button" then
      r = Widgets.action(content, s.label or key, s.info, s.onClick, FEATURE)
    elseif s.kind == "list" then
      r = Widgets.lines(content, s.label or key, s.info, s.lines)
    elseif s.kind == "toggle" then
      r = Widgets.toggle(content, s.label or key, s.info, get, set)
    elseif s.kind == "slider" then
      local step = s.step or 0.05
      r = Widgets.slider(content, s.label or key, s.info, s.min or 0, s.max or 1, step, get, set,
        s.fmt or (step >= 1 and wholeNumber or nil))
    elseif s.kind == "choice" then
      r = Widgets.choice(content, s.label or key, s.info, s.choices or {}, get, set)
    else
      if s.onSave then -- an "add" box: hands the text over, then empties itself
        get = function() return "" end
        set = function(v)
          if ns.Util.trim(tostring(v or "")) ~= "" then s.onSave(v) end
          if isOpen then Win.refresh() end
        end
      end
      r = Widgets.text(content, s.label or key, s.info, get, set, s.password)
    end
    r.tcList = s.kind == "list"
    return r
  end)
end

---------------------------------------------------------------------------------------------------- layout
local function setScroll(v)
  scrollOffset = math.max(0, math.min(scrollMax, tonumber(v) or 0))
  if scroll then scroll:SetVerticalScroll(scrollOffset) end
end

-- Window height: everything, or at most 85% of the screen (then the middle part scrolls).
local function fit()
  local footer = FOOTER + (confirming and CONFIRM or 0)
  local head = headerHeight()
  local want = head + contentHeight + footer + 6
  local screen = UIParent.GetHeight and UIParent:GetHeight()
  local height = want
  if type(screen) == "number" and screen > 0 then height = math.min(want, math.floor(screen * 0.85)) end
  frame:SetHeight(height)
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -head)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, footer)
  scrollMax = math.max(0, contentHeight - (height - head - footer))
  setScroll(scrollOffset)
end

local function layout()
  dirty = false
  layouts = layouts + 1
  for _, r in pairs(rows) do r:Hide() end
  placed, described = {}, {}
  local broken = {}
  for _, id in ipairs(ns.Modules.broken()) do broken[id] = true end
  local y = 0
  local function place(r, x, height, what)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    r:SetWidth(CONTENT_WIDTH - x) -- every switch and box lines up on the right edge
    r:Show()
    placed[#placed + 1] = r
    described[#described + 1] = what
    y = y + height
  end
  if tab == "basic" then
    local first = true
    for _, item in ipairs(BASICS) do
      if item.title then
        if not first then y = y + 10 end
        first = false
        place(sectionRow({ tier = "basic:" .. item.title, title = item.title, note = item.note }), 0, SECTION_ROW + 4,
          "section:" .. item.title)
      elseif item.module then
        local def = ns.Modules.get(item.module)
        if def then
          local r, state, height = moduleRow(def, broken[def.id])
          place(r, 0, height, "module:" .. def.id .. ":" .. state)
        end
      else
        local def, sdef = ns.Modules.get(item.id), settingDef(item.id, item.key)
        if def and sdef then
          local sr = settingRow(def, sdef)
          sr.tcModule, sr.tcParent = def.id, sdef.parent or false
          place(sr, sdef.parent and INDENT.child or 0, ROW, (sdef.parent and "child:" or "setting:") .. def.id .. ":"
            .. sdef.key)
        end
      end
    end
    y = y + 12
    place(sectionRow({ tier = "basic:more", title = "", note = "More options are on the Advanced tab." }), 0,
      SECTION_ROW, "note:advanced")
    contentHeight = y
    content:SetSize(CONTENT_WIDTH, math.max(1, y))
    fit()
    return
  end
  local function placeModule(def)
    local r, state, height = moduleRow(def, broken[def.id])
    place(r, 0, height, "module:" .. def.id .. ":" .. state)
    if not def.comingSoon then
      for _, s in ipairs(def.settings) do
        local sr = settingRow(def, s)
        sr.tcModule, sr.tcParent = def.id, s.parent or false
        if sr.tcList then sr.Refresh() end -- a list: its height depends on its lines
        place(sr, s.parent and INDENT.child or INDENT.setting, sr.tcList and sr.Height() or ROW,
          (s.parent and "child:" or "setting:") .. def.id .. ":" .. s.key)
      end
    end
    y = y + 4
  end
  if sub ~= "all" then
    local listed, chosen = {}, nil
    for _, st in ipairs(SUBTABS) do
      for _, id in ipairs(st.modules or {}) do listed[id] = st.id end
      if st.id == sub then chosen = st end
    end
    local ids = {}
    for _, id in ipairs(chosen and chosen.modules or {}) do ids[#ids + 1] = id end
    if sub == "crew" then -- anything not listed anywhere
      for _, def in ipairs(ns.Modules.list()) do
        if not listed[def.id] then ids[#ids + 1] = def.id end
      end
    end
    for i, id in ipairs(ids) do
      local def = ns.Modules.get(id)
      if def then
        if i > 1 then y = y + 8 end
        placeModule(def)
      end
    end
  else
    for i, sec in ipairs(SECTIONS) do
      if i > 1 then y = y + 10 end
      place(sectionRow(sec), 0, SECTION_ROW + 4, "section:" .. sec.title)
      for _, def in ipairs(ns.Modules.list(sec.tier)) do placeModule(def) end
    end
  end
  contentHeight = y
  content:SetSize(CONTENT_WIDTH, math.max(1, y))
  fit()
end

-- Puts the saved values back into every placed row and greys settings whose parent switch is off.
function Win.refresh()
  if not frame then return end
  subtitle:SetText("v" .. ns.VERSION .. " · " .. ns.Version.summary())
  for _, r in ipairs(placed) do
    local typing = r.control and r.control.HasFocus and r.control:HasFocus()
    if not typing then r.Refresh() end
    if r.tcParent then r:SetActive(ns.Modules.setting(r.tcModule, r.tcParent) and true or false) end
  end
end

---------------------------------------------------------------------------------------------------- tabs
local function drawTabs()
  for id, b in pairs(tabButtons) do
    local on = id == tab
    T.textColor(b.text, on and C.title or C.muted)
    if on then b.line:Show() else b.line:Hide() end
  end
  for id, b in pairs(subButtons) do
    if tab == "advanced" then b:Show() else b:Hide() end
    local on = id == sub
    T.textColor(b.text, on and C.white or C.muted)
    if on then b.fill:Show() else b.fill:Hide() end
  end
end

-- Shows the "basic" or "advanced" tab (anything else counts as basic); subId picks the Advanced sub-tab
-- ("panel", "roasts", "popups", "find", "crew", "test" or "all"; nil keeps the last one).
function Win.setTab(id, subId)
  local want = id == "advanced" and "advanced" or "basic"
  local wantSub = sub
  if want == "advanced" and subId then
    for _, st in ipairs(SUBTABS) do if st.id == subId then wantSub = subId end end
  end
  if want == tab and wantSub == sub then return end
  tab, sub = want, wantSub
  drawTabs()
  scrollOffset = 0
  Win.rebuild()
end

function Win.tab() return tab end
function Win.subTab() return sub end

---------------------------------------------------------------------------------------------------- frame
local function showConfirm(on)
  confirming = on and true or false
  if not frame then return end
  if confirming then confirmBox:Show() else confirmBox:Hide() end
  fit()
end

local function build()
  frame = T.frame("Frame", "TwizCrewSettings", UIParent)
  frame:SetWidth(WIDTH)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  script(frame, "OnDragStart", function(self) self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  script(frame, "OnHide", function()
    isOpen = false
    showConfirm(false)
  end)
  T.paint(frame, C.backdrop, 0.97, C.border, 2)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewSettings") end -- Escape

  local title = T.text(frame, T.FONT.normal, C.title)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("TwizCrew")
  subtitle = T.text(frame, T.FONT.small, C.muted)
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
  subtitle:SetJustifyH("LEFT")

  local x = PAD
  for _, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(90, 22)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -52)
    b.text = T.text(b, T.FONT.normal, C.muted)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.text:SetText(t.label)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    T.color(b.line, C.title, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    T.color(hl, C.white, 0.06)
    script(b, "OnClick", function() Win.setTab(t.id) end)
    tabButtons[t.id] = b
    x = x + 94
  end
  local under = frame:CreateTexture(nil, "ARTWORK")
  under:SetHeight(1)
  under:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -74)
  under:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -74)
  T.color(under, C.line, 1)

  -- the Advanced sub-tabs: small pill buttons in one row under the tabs
  local sx = PAD
  for _, st in ipairs(SUBTABS) do
    local b = CreateFrame("Button", nil, frame)
    b.text = T.text(b, T.FONT.small, C.muted)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetText(st.label)
    local w = tonumber(b.text.GetStringWidth and b.text:GetStringWidth()) or 0
    if w <= 0 then w = #st.label * 6 end
    b:SetSize(math.floor(w + 14), 18)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -80)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetAllPoints(b)
    T.color(b.fill, C.button, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    T.color(hl, C.white, 0.08)
    script(b, "OnClick", function() Win.setTab("advanced", st.id) end)
    subButtons[st.id] = b
    sx = sx + b:GetWidth() + 4
  end
  drawTabs()

  scroll = CreateFrame("ScrollFrame", nil, frame)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_WIDTH, 1)
  scroll:SetScrollChild(content)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  script(scroll, "OnMouseWheel", function(_, delta) setScroll(scrollOffset - (tonumber(delta) or 0) * WHEEL_STEP) end)

  closeButton = Widgets.button(frame, "Close", function() Win.close() end, nil, FEATURE)
  closeButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 10)
  resetButton = Widgets.button(frame, "Reset everything to defaults", function() Win.confirmReset() end, "danger",
    FEATURE)
  resetButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)

  confirmBox = T.frame("Frame", nil, frame)
  confirmBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, FOOTER)
  confirmBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOTER)
  confirmBox:SetHeight(CONFIRM - 6)
  T.paint(confirmBox, C.confirm, 1, C.dangerBorder, 1)
  local question = T.text(confirmBox, T.FONT.small, C.text)
  question:SetPoint("TOP", confirmBox, "TOP", 0, -8)
  question:SetText(RESET_QUESTION)
  local yes = Widgets.button(confirmBox, "Yes", function() Win.answerReset(true) end, "danger", FEATURE)
  yes:SetPoint("BOTTOMRIGHT", confirmBox, "BOTTOM", -6, 6)
  local no = Widgets.button(confirmBox, "No", function() Win.answerReset(false) end, nil, FEATURE)
  no:SetPoint("BOTTOMLEFT", confirmBox, "BOTTOM", 6, 6)
  confirmBox:Hide()
  frame:Hide()
end

---------------------------------------------------------------------------------------------------- public
function Win.open()
  if not frame then build() end
  if dirty then layout() end
  Win.refresh()
  frame:Show()
  isOpen = true
end

function Win.close()
  isOpen = false
  showConfirm(false)
  if frame then frame:Hide() end
end

function Win.toggle()
  if isOpen then Win.close() else Win.open() end
end

-- Re-places every row now if the window is open, otherwise on the next open.
function Win.rebuild()
  dirty = true
  if isOpen and frame then
    layout()
    Win.refresh()
  end
end

function Win.confirmReset()
  if not isOpen then Win.open() end
  showConfirm(true)
end

function Win.answerReset(yes)
  showConfirm(false)
  if yes then
    ns.Modules.resetAll()
    print("TwizCrew: all settings and the panel position are back to the defaults.")
  end
end

function Win.isOpen() return isOpen end
function Win.rowForTest(id, key) return rows["setting:" .. id .. ":" .. key] end
function Win.isConfirming() return confirming end
function Win.describeForTest() return described end
function Win.layoutCountForTest() return layouts end

ns.Bus.on(FEATURE, "SETTINGS_RESET", Win.rebuild)
ns.Bus.on(FEATURE, "MODULE_TOGGLED", Win.rebuild)
ns.Bus.on(FEATURE, "VERSION_NEWER", Win.rebuild)
ns.Bus.on(FEATURE, "SETTING_CHANGED", function() if isOpen then Win.refresh() end end)
-- The crew versions list: a friend came, went or changed version. Its height may change, so lay out again
-- (now if the window is open, otherwise on the next open).
local function crewChanged(_, changes)
  if type(changes) ~= "table" or changes.version then Win.rebuild() end
end
ns.Bus.on(FEATURE, "MEMBER_ONLINE", crewChanged)
ns.Bus.on(FEATURE, "MEMBER_OFFLINE", crewChanged)
ns.Bus.on(FEATURE, "MEMBER_UPDATED", crewChanged)

---------------------------------------------------------------------------------------------------- Options → AddOns
local function buildCanvas()
  local canvas = CreateFrame("Frame")
  canvas.name = "TwizCrew"
  local title = T.text(canvas, "GameFontNormalLarge", C.title)
  title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
  title:SetText("TwizCrew")
  local line = T.text(canvas, T.FONT.small, C.text)
  line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  line:SetText("TwizCrew has its own settings window.")
  local open = Widgets.button(canvas, "Open TwizCrew settings", function() Win.open() end, nil, FEATURE)
  open:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -10)
  local hint = T.text(canvas, T.FONT.small, C.muted)
  hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
  hint:SetText("Or type /tc")
  return canvas
end

-- Adds TwizCrew to the game's Options → AddOns list. If this game version lacks the API, logs it and moves on.
function Win.registerOptions()
  if optionsDone then return end
  optionsDone = true
  ns.Log.safe(FEATURE, function()
    local api = Settings -- the game's own Settings API, not ns.Settings
    if type(api) ~= "table" or type(api.RegisterCanvasLayoutCategory) ~= "function"
      or type(api.RegisterAddOnCategory) ~= "function" then
      ns.Log.add("warn", "settings: the game's Options > AddOns list is not available here; /tc opens the settings")
      return
    end
    local category = api.RegisterCanvasLayoutCategory(buildCanvas(), "TwizCrew")
    api.RegisterAddOnCategory(category)
    ns.Log.add("info", "settings: added to Options > AddOns")
  end)
end
