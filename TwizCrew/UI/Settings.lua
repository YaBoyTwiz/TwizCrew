-- The settings window ("TwizCrewSettings"), built from the module registry, and the Options → AddOns entry.
-- Feature id "settings": part of the essentials, not a registered module.
-- Rows are made once and reused (game frames cannot be deleted); a rebuild only re-places them.
-- Layout (2026-11-23, with the themes): the title and two links (How to use TwizCrew · What's new), one row of six
-- tabs (Basics, Panel, Alerts, Fun, Find, More) in the theme's tab look, each with its icon (dropped, not the words,
-- when the row does not fit), then the page. Every setting is on exactly one page; the theme picker (three previews
-- drawn live) is on Basics and first on Panel. Basics has a grey line under each control (UI/Help.lua SETTING_LINES).
local _, ns = ...

local Win = {}
ns.Settings = Win

local FEATURE = "settings"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local WIDTH, PAD = 400, 14
local CONTENT_WIDTH = WIDTH - 2 * PAD
local HEADER = 80 -- title, version line and the row of tabs
local TAB_Y, TAB_H, TAB_ICON = 50, 22, 13 -- the tab row: its top, height and the icons left of the words
local GREY_LINE = 13 -- one line of the grey explanation under a Basics control
local PICKER_ROW = 24 + 80 + 6 -- "Theme" and its (i), then the three previews with their names
local PREVIEW, PREVIEW_GAP = 64, 8
local FOOTER, CONFIRM = 40, 58
local ROW, MODULE_ROW, BROKEN_ROW, SECTION_ROW = 24, 26, 38, 26
local INDENT = { child = 32 } -- a setting under its parent switch
local WHEEL_STEP = 40
local RARE = { title = "Rarely needed", note = "most people never change these" }
-- The Basics tab: the few things people really change (on no other page), each with a grey line under it.
-- Items: { module = id } is that module's on/off switch; { id, key } one of its settings; { title, note } a heading;
-- { button = key } a button of this window (BUTTONS below); { picker = "theme" } the theme picker.
local BASICS = {
  { title = "The panel", note = "the crew list and its tab" },
  { picker = "theme" },
  { id = "panel", key = "keepOpen" },
  { id = "panel", key = "scale" },
  { id = "panel", key = "idleAlpha" },
  { title = "News", note = "pop-ups, chat lines and sounds" },
  { id = "panel", key = "noticeScope" },
  { module = "popups" },
  { id = "activity", key = "chatNews" },
  { id = "popups", key = "sounds" },
  { title = "Me", note = "what your crew sees" },
  { id = "tags", key = "autoAway" },
}
-- Settings that are not on a page: the two links at the top of the window do what these buttons did.
Win.LINKED = { ["panel:about"] = true, ["panel:whatsNew"] = true }
-- Buttons that belong to this window rather than to a module.
local BUTTONS = {
  tryit = { label = "Try it out\226\128\166", icon = "Interface\\Icons\\Trade_Engineering",
    info = "Opens a small window with pretend friends and pop-ups, so you can see how TwizCrew looks without waiting "
      .. "for your crew. Only on your screen. Also: /tc test.",
    onClick = function() if ns.TestTools and ns.TestTools.open then ns.TestTools.open() end end },
}

-- Pictures next to module names and common options (where a picture says it faster than words).
local MODULE_ICONS = {
  panel = "Interface\\Icons\\Ability_Warrior_BattleShout", activity = "Interface\\Icons\\INV_Misc_Note_02", popups = "Interface\\Icons\\Spell_Holy_PowerInfusion",
  roasts = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", stats = "Interface\\Icons\\INV_Misc_Note_02",
  find = "Interface\\Icons\\Ability_Hunter_Pathfinding", calendar = "Interface\\Icons\\INV_Scroll_03",
  rankup = "Interface\\Icons\\Spell_Holy_SealOfWisdom", tags = "Interface\\Icons\\INV_Misc_Note_01",
  layer = "Interface\\Icons\\Spell_Arcane_Blink", comm = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
  version = "Interface\\Icons\\INV_Misc_Book_09", updates = "Interface\\Icons\\INV_Misc_Book_09",
  minimap = "Interface\\Icons\\INV_Misc_Map_01",
}
local SETTING_ICONS = {
  ["panel:bgAlpha"] = "Interface\\Icons\\Spell_Shadow_Twilight", ["panel:scale"] = "Interface\\Icons\\INV_Misc_Spyglass_03",
  ["panel:rowStyle"] = "Interface\\Icons\\INV_Fabric_Linen_01", ["panel:idleAlpha"] = "Interface\\Icons\\Spell_Nature_Invisibilty",
  ["panel:keepOpen"] = "Interface\\Icons\\INV_Misc_Spyglass_03", ["panel:peek"] = "Interface\\Icons\\Spell_Holy_MindVision",
  ["activity:chatNews"] = "Interface\\Icons\\INV_Misc_Note_02",
  ["panel:locked"] = "Interface\\Icons\\INV_Misc_Key_03",
  ["panel:hideInCombat"] = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
  ["panel:shareQuest"] = "Interface\\Icons\\INV_Misc_Note_02", ["panel:questHeadsUp"] = "Interface\\Icons\\Spell_ChargePositive",
  ["panel:whatsNew"] = "Interface\\Icons\\INV_Misc_Book_09",
  ["panel:about"] = "Interface\\Icons\\INV_Misc_QuestionMark",
  ["tags:autoAway"] = "AFK_TAG", ["roasts:editMocks"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  ["roasts:cheers"] = "Interface\\Icons\\INV_Misc_Gift_01", ["roasts:mocks"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  ["popups:online"] = "Interface\\Icons\\Ability_Warrior_BattleShout", ["popups:death"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  ["popups:levelUp"] = "Interface\\Icons\\Spell_Holy_PowerInfusion", ["popups:layerDiff"] = "Interface\\Icons\\Spell_Arcane_Blink",
  ["minimap:show"] = "Interface\\Icons\\INV_Misc_Map_01", ["find:rowArrows"] = "Interface\\Icons\\Ability_Hunter_Pathfinding",
  ["find:meetups"] = "Interface\\Icons\\INV_Misc_Map_01", ["find:sharePosition"] = "Interface\\Icons\\Spell_Holy_MindVision",
  ["calendar:share"] = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  ["rankup:auto"] = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  ["rankup:showButton"] = "Interface\\Icons\\INV_Misc_Rune_01",
}

-- Puts a small picture before a row's words (or its button). Done once per row.
local function decorate(r, tex)
  if not r or not tex or rawget(r, "tcIcon") then return end
  if tex == "AFK_TAG" then tex = ns.Tags.ICON.AFK end
  local target = rawget(r, "label") or rawget(r, "button")
  if not target then return end
  local ok, point, rel, relPoint, x, y = pcall(target.GetPoint, target, 1)
  if not ok or type(point) ~= "string" then point, rel, relPoint, x, y = "LEFT", r, "LEFT", 0, 0 end
  target:ClearAllPoints()
  target:SetPoint(point, rel or r, relPoint or point, (tonumber(x) or 0) + 20, tonumber(y) or 0)
  local ic = r:CreateTexture(nil, "ARTWORK")
  ic:SetSize(T.icon(16), T.icon(16))
  ic:SetPoint("RIGHT", target, "LEFT", -4, 0)
  ic:SetTexture(tex)
  ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.tcIcon = ic
end
-- The other five tabs, each a list of items like BASICS (everyday first, then the rarely needed ones). A module that
-- is on no page (a new one) lands at the end of More with its switch and all its settings.
local SUBTABS = {
  { id = "panel", label = "Panel", items = {
    { picker = "theme" },
    { module = "panel" },
    { title = "Look" },
    { id = "panel", key = "bgAlpha" }, { id = "panel", key = "rowStyle" }, { id = "panel", key = "sort" },
    { title = "The tab" },
    { id = "panel", key = "peek" }, { id = "panel", key = "barHover" }, { id = "panel", key = "locked" },
    { title = "Hiding" },
    { id = "panel", key = "hideInCombat" }, { id = "panel", key = "hideInInstance" },
    { title = "Me", note = "what your crew sees" },
    { id = "panel", key = "shareQuest" },
    RARE,
    { id = "panel", key = "hideWhenAlone" }, { id = "panel", key = "showNoAddon" }, { id = "panel", key = "showSelf" },
    { id = "panel", key = "barInstead" }, { id = "tags", key = "awayMinutes" }, { module = "tags" }, { module = "layer" },
  } },
  { id = "alerts", label = "Alerts", items = {
    { title = "Pop-ups", note = "which news gets one" },
    { id = "popups", key = "online" }, { id = "popups", key = "death" }, { id = "popups", key = "levelUp" },
    { id = "popups", key = "layerDiff" }, { id = "popups", key = "newMember" }, { id = "panel", key = "questHeadsUp" },
    RARE,
    { module = "activity" },
  } },
  { id = "fun", label = "Fun", items = {
    { module = "roasts" },
    { id = "roasts", key = "aboutMe" }, { id = "roasts", key = "mocks" }, { id = "roasts", key = "editMocks" },
    { id = "roasts", key = "cheers" },
    { module = "stats" },
    { id = "stats", key = "titles" }, { id = "roasts", key = "stealPopups" }, { id = "stats", key = "crewShow" },
    RARE,
    { id = "roasts", key = "mockModel" }, { id = "stats", key = "countSteps" },
  } },
  { id = "find", label = "Find", items = {
    { module = "find" },
    { id = "find", key = "rowArrows" }, { id = "find", key = "sharePosition" }, { id = "find", key = "runaway" },
    { id = "find", key = "meetups" },
    RARE,
    { id = "find", key = "arrowScale" },
  } },
  { id = "more", label = "More", items = {
    { title = "Calendar" },
    { module = "calendar" }, { id = "calendar", key = "share" },
    { title = "Recap cards" },
    { module = "recap" }, { id = "recap", key = "onLogout" }, { id = "recap", key = "awayCard" },
    { title = "Spell ranks" },
    { module = "rankup" }, { id = "rankup", key = "auto" }, { id = "rankup", key = "showButton" },
    { title = "Updates" },
    { module = "updates" }, { id = "version", key = "versions" }, { id = "version", key = "tellCrew" },
    { title = "Other" },
    { id = "minimap", key = "show" }, { button = "tryit" },
    RARE,
    { id = "calendar", key = "size" },
  } },
}
Win.BROKEN_TEXT = "turned off after errors, /reload to try again"
local RESET_QUESTION = "Reset all TwizCrew settings and the panel position?"

-- The six tabs, left to right (icon: UI/Icons.lua page names).
local PAGES = { { id = "basic", label = "Basics", tip = "setBasics", items = BASICS } }
for _, st in ipairs(SUBTABS) do
  PAGES[#PAGES + 1] = { id = st.id, label = st.label, tip = "set" .. st.label, items = st.items }
end
Win.PAGES = PAGES

local frame, scroll, content, subtitle, confirmBox, closeButton, resetButton
local tab = "basic"   -- the tab shown: a PAGES id
local tabButtons = {}
local tabIcons = false -- the tab row has room for its icons (decided when the window is built)
local links -- the two links on the title line: { about, new }

local function headerHeight() return HEADER end
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

-- A font string a few points bigger or smaller than its font object (the game's font; unchanged if it cannot).
local function resize(fs, by)
  local ok, path, size, flags = pcall(function() return fs:GetFont() end)
  if ok and type(path) == "string" and type(size) == "number" and size > 0 then
    pcall(fs.SetFont, fs, path, size + by, flags or "")
  end
  return fs
end

local function sectionRow(sec)
  return cached("section:" .. sec.tier, function()
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(CONTENT_WIDTH, SECTION_ROW)
    local title = resize(T.text(f, T.FONT.normal, C.title), -1.5)
    title:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 5)
    title:SetText(sec.title)
    T.ink(title, "setHeading", sec.title) -- the theme's heading look (accent, Friz 12; Tavern night: Morpheus)
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

-- "Rarely needed": the theme's divider across the page 10 above it, then the words, muted.
local RARE_ROW = 10 + SECTION_ROW
local function rareRow()
  return cached("rare", function()
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(CONTENT_WIDTH, RARE_ROW)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    T.divider(line)
    f.line = line
    local title = resize(T.text(f, T.FONT.normal, "998f70"), -1.5)
    title:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 5)
    title:SetText(RARE.title)
    local note = T.text(f, T.FONT.small, "808080")
    note:SetPoint("LEFT", title, "RIGHT", 6, 0)
    note:SetText(RARE.note)
    return plainRow(f)
  end)
end

-- How many grey lines a text takes (the game's measure when it has one, else about 74 letters a line).
function Win.greyLines(text, realHeight)
  if type(realHeight) == "number" and realHeight > 0 then
    return math.max(1, math.floor(realHeight / GREY_LINE + 0.5))
  end
  return math.max(1, math.ceil(#tostring(text or "") / 74))
end

-- The grey explanation under a Basics control (UI/Help.lua SETTING_LINES); returns the row and its height.
local function greyRow(key, text)
  local r = cached("grey:" .. key, function()
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(CONTENT_WIDTH, GREY_LINE + 3)
    f.text = resize(T.text(f, T.FONT.small, "9e9e9e"), -1)
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.text:SetWidth(CONTENT_WIDTH)
    f.text:SetJustifyH("LEFT")
    if f.text.SetWordWrap then f.text:SetWordWrap(true) end
    f.text:SetText(text)
    return plainRow(f)
  end)
  local h = r.text.GetStringHeight and r.text:GetStringHeight() or nil
  return r, Win.greyLines(text, h) * GREY_LINE + 3
end

---------------------------------------------------------------------------------------------------- theme picker
-- One small panel drawn in a theme's own frame (no picture files): a title bar with an accent line under it, three
-- bars in class colours, the emblem at the bottom (none for Classic).
local PREVIEW_BARS = { { 0.98, 0.49, 0.04 }, { 0.25, 0.78, 0.92 }, { 0.96, 0.55, 0.73 } }
local function paintPreviewInside(inner, t)
  local accent = t.accent
  inner.line:SetColorTexture(accent[1], accent[2], accent[3], 1)
  local emblem = T.emblemFile(t)
  if emblem then
    T.setTexture(inner.emblem, emblem)
    T.setCoords(inner.emblem, 0, 1, T.flipV(0, 1))
    inner.emblem:Show()
  else
    inner.emblem:Hide()
  end
end

local function previewBox(parent, id)
  local box = T.frame("Frame", nil, parent)
  box:SetSize(PREVIEW, PREVIEW)
  box.tcThemeId = id
  local p = T.THEMES[id].preview
  T.skin(box, "panel", { alpha = 0.9, margin = p.margin, edgeSize = p.edgeSize, tile = p.tile })
  local inner = CreateFrame("Frame", nil, box)
  inner:SetAllPoints(box)
  inner.tcThemeId = id
  inner.line = inner:CreateTexture(nil, "ARTWORK")
  inner.line:SetHeight(1)
  inner.line:SetPoint("TOPLEFT", box, "TOPLEFT", 7, -17)
  inner.line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -7, -17)
  for i, c in ipairs(PREVIEW_BARS) do
    local bar = inner:CreateTexture(nil, "ARTWORK")
    bar:SetHeight(6)
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -(21 + (i - 1) * 9))
    bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -(21 + (i - 1) * 9))
    bar:SetColorTexture(c[1], c[2], c[3], 0.7)
  end
  inner.emblem = inner:CreateTexture(nil, "OVERLAY")
  inner.emblem:SetSize(16, 16)
  inner.emblem:SetPoint("BOTTOM", box, "BOTTOM", 0, 3)
  T.track(inner, paintPreviewInside)
  return box
end

-- "Theme" with its (i), then the three previews (Classic, Crowned crew, Tavern night) with their names; the chosen
-- one has a 2 px accent outline and its name in the accent colour. A click switches at once. page: one row per page.
local function pickerRow(page)
  return cached("picker:" .. page, function()
    local def = settingDef("panel", "theme")
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(CONTENT_WIDTH, PICKER_ROW)
    f.label = T.text(f, T.FONT.small, C.text)
    f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -5)
    f.label:SetText(def and def.label or "Theme")
    f.info = Widgets.infoButton(f, def and def.label or "Theme", def and def.info or "")
    f.info:SetPoint("LEFT", f.label, "RIGHT", 2, 0)
    f.control = false
    f.previews = {}
    for i, id in ipairs(T.ORDER) do
      local b = CreateFrame("Button", nil, f)
      b:SetSize(PREVIEW, PREVIEW + 16)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (PREVIEW + PREVIEW_GAP), -24)
      b.box = previewBox(b, id)
      b.box:SetPoint("TOP", b, "TOP", 0, 0)
      if b.box.EnableMouse then b.box:EnableMouse(false) end
      b.outline = {}
      -- the 2 px outline just outside the box: top, bottom, left, right
      for k, side in ipairs({ { "TOPLEFT", -2, 2, "TOPRIGHT", 2, 2, "h" }, { "BOTTOMLEFT", -2, -2, "BOTTOMRIGHT", 2, -2, "h" },
        { "TOPLEFT", -2, 2, "BOTTOMLEFT", -2, -2, "w" }, { "TOPRIGHT", 2, 2, "BOTTOMRIGHT", 2, -2, "w" } }) do
        local o = b:CreateTexture(nil, "OVERLAY")
        o:SetPoint(side[1], b.box, side[1], side[2], side[3])
        o:SetPoint(side[4], b.box, side[4], side[5], side[6])
        if side[7] == "h" then o:SetHeight(2) else o:SetWidth(2) end
        b.outline[k] = o
      end
      b.name = T.text(b, T.FONT.small, C.text)
      b.name:SetPoint("TOP", b.box, "BOTTOM", 0, -3)
      b.name:SetText(T.THEMES[id].name)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints(b.box)
      T.color(hl, C.white, 0.12)
      script(b, "OnClick", function() Win.save("panel", "theme", id) end)
      Widgets.addTip(b, T.THEMES[id].name, "Click to use this look now.", FEATURE, "ANCHOR_TOP")
      b.tcId = id
      f.previews[i] = b
    end
    f.Refresh = function()
      local chosen = T.chosen()
      local a = T.active().accent
      for _, b in ipairs(f.previews) do
        local on = b.tcId == chosen
        for _, o in ipairs(b.outline) do
          o:SetColorTexture(a[1], a[2], a[3], 1)
          if on then o:Show() else o:Hide() end
        end
        if on then b.name:SetTextColor(a[1], a[2], a[3], 1) else T.textColor(b.name, C.text) end
      end
    end
    f.SetActive = function() end
    f.Refresh()
    return f
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
  if broken then
    return cached("module:" .. def.id .. ":broken", function() return noteRow(def, Win.BROKEN_TEXT, true) end),
      "broken", BROKEN_ROW
  end
  return cached("module:" .. def.id .. ":switch", function()
    local r = Widgets.toggle(content, def.name, def.info,
      function() return ns.Modules.isEnabled(def.id) end,
      function(on) ns.Modules.setEnabled(def.id, on) end)
    r.label:SetFontObject(T.FONT.normal)
    decorate(r, MODULE_ICONS[def.id])
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
    if s.kind ~= "list" then decorate(r, s.icon or SETTING_ICONS[id .. ":" .. key]) end
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

-- A row for one of this window's own buttons (BUTTONS).
local function buttonRow(key)
  local b = BUTTONS[key]
  if not b then return nil end
  return cached("button:" .. key, function()
    local r = Widgets.action(content, b.label, b.info, b.onClick, FEATURE)
    decorate(r, b.icon)
    return r
  end)
end

-- The modules no page mentions (a new module): they land at the end of More, switch and settings.
local function unlisted()
  local listed = {}
  local function note(list)
    for _, item in ipairs(list) do
      if item.module then listed[item.module] = true elseif item.id then listed[item.id] = true end
    end
  end
  note(BASICS)
  for _, st in ipairs(SUBTABS) do note(st.items) end
  local out = {}
  for _, def in ipairs(ns.Modules.list()) do
    if not listed[def.id] and def.tier ~= "essential" and def.tier ~= "tools" and not def.comingSoon then
      out[#out + 1] = def
    end
  end
  return out
end

local function layout()
  dirty = false
  layouts = layouts + 1
  for _, r in pairs(rows) do r:Hide() end
  placed, described = {}, {}
  local broken = {}
  for _, id in ipairs(ns.Modules.broken()) do broken[id] = true end
  local y = 0
  local first = true
  local function place(r, x, height, what)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    r:SetWidth(CONTENT_WIDTH - x) -- every switch and box lines up on the right edge
    r:Show()
    placed[#placed + 1] = r
    described[#described + 1] = what
    y = y + height
    first = false
  end
  local function placeModule(def)
    local r, state, height = moduleRow(def, broken[def.id])
    place(r, 0, height, "module:" .. def.id .. ":" .. state)
  end
  local function placeSetting(def, sdef)
    local sr = settingRow(def, sdef)
    sr.tcModule, sr.tcParent = def.id, sdef.parent or false
    if sr.tcList then sr.Refresh() end -- a list: its height depends on its lines
    place(sr, sdef.parent and INDENT.child or 0, sr.tcList and sr.Height() or ROW,
      (sdef.parent and "child:" or "setting:") .. def.id .. ":" .. sdef.key)
  end
  -- Basics: the grey line under a control
  local function placeGrey(key)
    local text = ns.Help.SETTING_LINES and ns.Help.SETTING_LINES[key]
    if not text then return end
    local r, height = greyRow(key, text)
    y = y - 2
    place(r, 0, height, "grey:" .. key)
  end
  local function placeItems(list, grey)
    for _, item in ipairs(list) do
      if item == RARE then
        if not first then y = y + 4 end
        place(rareRow(), 0, RARE_ROW + 4, "section:" .. item.title)
      elseif item.title then
        if not first then y = y + 10 end
        place(sectionRow({ tier = "page:" .. item.title, title = item.title, note = item.note or "" }), 0,
          SECTION_ROW + 4, "section:" .. item.title)
      elseif item.picker then
        place(pickerRow(tab), 0, PICKER_ROW, "picker:panel:theme")
      elseif item.module then
        local def = ns.Modules.get(item.module)
        if def then
          placeModule(def)
          if grey then placeGrey("module:" .. def.id) end
        end
      elseif item.button then
        local r = buttonRow(item.button)
        if r then place(r, 0, ROW, "button:" .. item.button) end
      else
        local def, sdef = ns.Modules.get(item.id), settingDef(item.id, item.key)
        if def and sdef then
          placeSetting(def, sdef)
          if grey then placeGrey(item.id .. ":" .. item.key) end
        end
      end
    end
  end
  local page = PAGES[1]
  for _, p in ipairs(PAGES) do if p.id == tab then page = p end end
  placeItems(page.items, page.id == "basic")
  if page.id == "more" then
    for _, def in ipairs(unlisted()) do
      y = y + 8
      placeModule(def)
      for _, sdef in ipairs(def.settings) do placeSetting(def, sdef) end
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
  for id, b in pairs(tabButtons) do b:SetActive(id == tab) end
end

-- Shows one of the six tabs: "basic", "panel", "alerts", "fun", "find" or "more" (an unknown id changes nothing).
-- ("advanced", page) from before the six tabs still works: it shows that page.
function Win.setTab(id, page)
  if id == "advanced" then id = page or "panel" end
  local known = false
  for _, p in ipairs(PAGES) do if p.id == id then known = true end end
  if not known or id == tab then return end
  tab = id
  drawTabs()
  scrollOffset = 0
  Win.rebuild()
end

function Win.tab() return tab end
function Win.tabIconsForTest() return tabIcons end
function Win.tabButtonsForTest() return tabButtons end
function Win.linksForTest() return links end
function Win.pickerForTest(page) return rows["picker:" .. (page or "basic")] end

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
  T.skin(frame, "window", { alpha = 0.97 }) -- the theme's frame (UI/Skin.lua)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewSettings") end -- Escape

  local title = resize(T.text(frame, T.FONT.normal, C.title), 3) -- Friz 16.5
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("TwizCrew settings")
  T.ink(title, "title") -- the theme's title colour and font
  subtitle = T.text(frame, T.FONT.small, C.muted)
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
  subtitle:SetJustifyH("LEFT")

  -- the two links on the title line, right-aligned: How to use TwizCrew · What's new (they were buttons in Basics)
  local function link(words, onClick, tip)
    local b = CreateFrame("Button", nil, frame)
    b.text = T.text(b, T.FONT.small, C.title)
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetText(words)
    T.ink(b.text, "link")
    local w = b.text:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = #words * 6 end
    b:SetSize(w, 14)
    b.under = b:CreateTexture(nil, "ARTWORK")
    b.under:SetHeight(1)
    b.under:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
    b.under:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
    T.color(b.under, C.white, 1)
    b.under:Hide()
    script(b, "OnClick", onClick)
    script(b, "OnEnter", function(self)
      self.text:SetTextColor(1, 1, 1, 1)
      self.under:Show()
      local t, x = ns.Help.tip(tip)
      if t then Widgets.tip(self, t, x, "ANCHOR_TOP") end
    end)
    script(b, "OnLeave", function(self)
      T.paintInk(self.text)
      self.under:Hide()
      if GameTooltip then GameTooltip:Hide() end
    end)
    return b
  end
  local newLink = link("What's new", function() if ns.Changelog then ns.Changelog.toggle() end end, "setNew")
  newLink:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -14)
  local dot = T.text(frame, T.FONT.small, C.muted)
  dot:SetText(" \194\183 ")
  dot:SetPoint("RIGHT", newLink, "LEFT", 0, 0)
  local aboutLink = link("How to use TwizCrew", function() if ns.About then ns.About.toggle() end end, "setAbout")
  aboutLink:SetPoint("RIGHT", dot, "LEFT", 0, 0)
  links = { about = aboutLink, new = newLink }

  -- one row of six tabs in the theme's tab look; each: 4, icon 13, 2, the word, 4; 2 between. When the row is wider
  -- than the page, the icons go (never the words).
  local made, total, iconsAll = {}, -2, true
  for i, pg in ipairs(PAGES) do
    local b = CreateFrame("Button", nil, frame)
    b.label = T.text(b, T.FONT.small, C.muted)
    b.label:SetText(pg.label)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b)
    T.skinTab(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(TAB_ICON, TAB_ICON)
    b.icon:SetPoint("LEFT", b, "LEFT", 4, 0)
    if ns.Icons.set(b.icon, ns.Icons.page(pg.id)) ~= "atlas" then iconsAll = false end
    local w = b.label:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = #pg.label * 6 end
    b.tcWordWidth = w
    total = total + 4 + TAB_ICON + 2 + w + 4 + 2
    local id = pg.id
    script(b, "OnClick", function() Win.setTab(id) end)
    Widgets.helpTip(b, pg.tip, FEATURE, "ANCHOR_TOP")
    tabButtons[id] = b
    made[i] = b
  end
  tabIcons = iconsAll and total <= CONTENT_WIDTH
  local x = PAD
  for _, b in ipairs(made) do
    local lead = tabIcons and (4 + TAB_ICON + 2) or 4
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", lead, 0)
    if tabIcons then b.icon:Show() else b.icon:Hide() end
    b:SetSize(math.floor(lead + b.tcWordWidth + 4 + 0.5), TAB_H)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -TAB_Y)
    x = x + b:GetWidth() + 2
  end
  local under = frame:CreateTexture(nil, "ARTWORK")
  under:SetHeight(1)
  under:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TAB_Y + TAB_H))
  under:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TAB_Y + TAB_H))
  T.color(under, C.line, 1)
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
    FEATURE, "setReset")
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
function Win.buttonRowForTest(key) return rows["button:" .. key] end
function Win.isConfirming() return confirming end
function Win.describeForTest() return described end
function Win.layoutCountForTest() return layouts end

ns.Bus.on(FEATURE, "SETTINGS_RESET", Win.rebuild)
ns.Bus.on(FEATURE, "MODULE_TOGGLED", Win.rebuild)
ns.Bus.on(FEATURE, "VERSION_NEWER", Win.rebuild)
ns.Bus.on(FEATURE, "SETTING_CHANGED", function() if isOpen then Win.refresh() end end)
-- The crew versions list: a friend came, went, changed version, or was hidden / shown (guild list). Its height may
-- change, so lay out again (now if the window is open, otherwise on the next open).
local function crewChanged(_, changes)
  if type(changes) ~= "table" or changes.version or changes.inGuild ~= nil then Win.rebuild() end
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
