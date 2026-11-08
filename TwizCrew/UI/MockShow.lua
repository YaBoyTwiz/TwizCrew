-- Mock show (part of module "roasts"): when a friend mocks YOU, their 3D character laughs at you with the roast in
-- a speech bubble. Which picture, best first:
--   live        they are loaded near you right now: their real character (party unit or nameplate)
--   remembered  you were near them earlier this session: the real character kept in a hidden model since then
--   icon        their class icon (a far-away friend you haven't been near this session)
-- Also: each copy shares its race and gender (MockShow.myLook, sent by SelfState as "lo"): it picks the laugh voice.
-- (A race-model stand-in in their gear was tried and dropped: on Forever it didn't look good.)
local _, ns = ...

local MockShow = {}
ns.MockShow = MockShow

local FEATURE = "roasts"
local T = ns.Theme
local C = T.COLOR

local LAUGH = 70          -- the /laugh animation
local SECONDS = 6         -- how long the show stays up
local FADE = 0.6
local CAPTURE_TICK = 5    -- how often we look for crew members near us to remember their look
local RECAPTURE_AFTER = 120
local MODEL_W, MODEL_H = 300, 340
local WIDTH = 420 -- the whole show (the speech bubble); the model sits centered under it
-- Camera: close on the face and upper body. Portrait zoom 0 shows the whole body, 1 only the face.
local ZOOM = 0.6
local GAP = 10 -- between the crew panel and the show
local TEXT_GROW = 10 -- the roast's letters: this many points bigger than normal text (hard to miss)

-- The game's own /laugh voice for each race (raceID -> { male, female } sound file numbers, from the community
-- listfile). Races Forever doesn't have are here too, in case.
MockShow.LAUGH_SOUNDS = {
  [1] = { 540739, 540540 },   -- Human
  [2] = { 541230, 541153 },   -- Orc
  [3] = { 539883, 539798 },   -- Dwarf
  [4] = { 540945, 540877 },   -- Night Elf
  [5] = { 542595, 542518 },   -- Undead
  [6] = { 542898, 542806 },   -- Tauren
  [7] = { 540267, 540268 },   -- Gnome
  [8] = { 543094, 543091 },   -- Troll
  [9] = { 541902, 541840 },   -- Goblin
  [10] = { 539287, 539267 },  -- Blood Elf
  [11] = { 539604, 539719 },  -- Draenei
  [22] = { 542246, 542077 },  -- Worgen
  [24] = { 641324, 644720 },  -- Pandaren
  [25] = { 641324, 644720 },
  [26] = { 641324, 644720 },
}

-- The laugh sound file for a race and sex (UnitSex: 2 male, 3 female), or nil.
function MockShow.laughSound(race, sex)
  local pair = MockShow.LAUGH_SOUNDS[tonumber(race) or 0]
  if not pair then return nil end
  return tonumber(sex) == 3 and pair[2] or pair[1]
end
-- gear slots you can see on a character: head, shoulders, shirt, chest, waist, legs, feet, wrists, hands, back,
-- main hand, off hand, ranged, tabard
local VISIBLE_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function readable(v)
  if v == nil then return false end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return false end
  end
  return true
end

-- Calls model:method(...) if this game version has it; true when it ran.
local function try(model, method, ...)
  local fn = model and model[method]
  if type(fn) ~= "function" then return false end
  return (pcall(fn, model, ...))
end

---------------------------------------------------------------------------------------------------------- the look
-- "<raceID>.<sex>.<slot>-<itemID>.<slot>-<itemID>..." (dots and dashes: nothing the message format escapes).
function MockShow.encodeLook(race, sex, items)
  race, sex = tonumber(race), tonumber(sex)
  if not race or not sex then return "" end
  local parts = { tostring(math.floor(race)), tostring(math.floor(sex)) }
  for _, slot in ipairs(VISIBLE_SLOTS) do
    local id = items and tonumber(items[slot])
    if id and id > 0 then parts[#parts + 1] = slot .. "-" .. math.floor(id) end
  end
  return table.concat(parts, ".")
end

-- The other way: { race, sex, items = { [slot] = itemID } }, or nil for junk.
function MockShow.decodeLook(s)
  if type(s) ~= "string" or s == "" or #s > 300 then return nil end
  local race, sex, rest = s:match("^(%d+)%.(%d+)(.*)$")
  if not race then return nil end
  local look = { race = tonumber(race), sex = tonumber(sex), items = {} }
  for slot, id in rest:gmatch("%.(%d+)%-(%d+)") do
    slot, id = tonumber(slot), tonumber(id)
    if slot and id and slot >= 1 and slot <= 19 and id > 0 then look.items[slot] = id end
  end
  return look
end

-- My race and gender, as sent to the crew ("" when the game won't say). No gear: nothing uses it any more.
function MockShow.myLook()
  local _, _, race = call(UnitRace, "player")
  local sex = call(UnitSex, "player")
  if not readable(race) or not readable(sex) then return "" end
  return MockShow.encodeLook(race, sex, nil)
end

------------------------------------------------------------------------------------------------- finding them near
local function unitName(u)
  local n = call(UnitName, u)
  if type(n) ~= "string" or not readable(n) or n == "" then return nil end
  return ns.shortName(n)
end

local function visible(u)
  local v = call(UnitIsVisible, u)
  return readable(v) and v and true or false
end

-- A unit token for this friend that the game is drawing right now, or nil.
local function liveUnit(name)
  if type(name) ~= "string" then return nil end
  local lower = name:lower()
  local raid = call(IsInRaid)
  for i = 1, raid and 40 or 4 do
    local u = (raid and "raid" or "party") .. i
    local n = unitName(u)
    if n and n:lower() == lower then return visible(u) and u or nil end
  end
  for _, u in ipairs({ "target", "mouseover", "focus" }) do
    local n = unitName(u)
    if n and n:lower() == lower and call(UnitIsPlayer, u) and visible(u) then return u end
  end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if call(UnitExists, u) and call(UnitIsPlayer, u) then
      local n = unitName(u)
      if n and n:lower() == lower then return u end
    end
  end
  return nil
end
MockShow.liveUnit = liveUnit

------------------------------------------------------------------------------------------------- remembered looks
-- name (lower case) -> a model frame that had their real character loaded while they were near us. It lives off
-- screen (shown, so the game keeps it loaded) and is borrowed by the show. Lost on /reload: that's game memory.
local remembered, rememberedAt = {}, {}
local borrowed -- the remembered model the show is using right now

local function newModel(parent)
  local m = CreateFrame("DressUpModel", nil, parent or UIParent)
  return m
end

local function park(model)
  model:SetParent(UIParent)
  model:ClearAllPoints()
  model:SetSize(MODEL_W, MODEL_H)
  model:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -3000, 3000) -- far off screen
  model:Show()
end

local function remember(name, unit)
  local key = name:lower()
  local m = remembered[key]
  if m and m == borrowed then return end -- on screen in the show right now: leave it alone
  if not m then
    m = newModel()
    park(m)
    remembered[key] = m
  end
  if try(m, "SetUnit", unit) then
    rememberedAt[key] = ns.now()
    ns.Log.add("info", "mock show: remembered how %s looks", name)
  end
end

local function lookAround()
  if not ns.Modules.isEnabled(FEATURE) or ns.Modules.setting(FEATURE, "mockModel") == false or not ns.roster then
    return
  end
  local now = ns.now()
  for _, m in ipairs(ns.roster:members(false)) do
    if m.online then
      local key = m.name:lower()
      if not rememberedAt[key] or now - rememberedAt[key] >= RECAPTURE_AFTER then
        local u = liveUnit(m.name)
        if u then remember(m.name, u) end
      end
    end
  end
end

function MockShow.isRemembered(name)
  return type(name) == "string" and remembered[name:lower()] ~= nil
end

---------------------------------------------------------------------------------------------------------- the show
local frame, holder, bubble, bubbleText, liveModel, iconTex, nameText
local hideAt, fadeFrom
local current -- the model being animated (or nil for the icon)

local function laugh(model)
  try(model, "SetFacing", 0)
  try(model, "SetPortraitZoom", ZOOM) -- loading a model or an animation can reset the camera: set it every time
  try(model, "SetAnimation", LAUGH)
end

local function build()
  frame = T.frame("Button", "TwizCrewMockShow", UIParent)
  frame:SetSize(WIDTH, MODEL_H + 70)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)

  bubble = T.frame("Frame", nil, frame)
  bubble:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bubble:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  bubble:SetHeight(58)
  T.paint(bubble, C.backdrop, 0.92, C.title, 2)
  nameText = T.readable(T.text(bubble, T.FONT.normal, C.title))
  nameText:SetPoint("TOPLEFT", bubble, "TOPLEFT", 10, -8)
  bubbleText = T.readable(T.text(bubble, T.FONT.normal, C.white), TEXT_GROW)
  do -- a thick outline at this size, so it reads on any background
    local path, size, flags = bubbleText:GetFont()
    if type(path) == "string" and type(size) == "number" then pcall(bubbleText.SetFont, bubbleText, path, size, "THICKOUTLINE") end
  end
  bubbleText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)
  if bubbleText.SetSpacing then bubbleText:SetSpacing(2) end
  bubbleText:SetWidth(WIDTH - 20)
  bubbleText:SetJustifyH("LEFT")
  if bubbleText.SetWordWrap then bubbleText:SetWordWrap(true) end

  holder = CreateFrame("Frame", nil, frame)
  holder:SetPoint("TOP", bubble, "BOTTOM", 0, -4)
  holder:SetSize(MODEL_W, MODEL_H)

  liveModel = newModel(holder)
  liveModel:SetAllPoints(holder)
  liveModel:SetScript("OnModelLoaded", function(self) ns.Log.safe(FEATURE, laugh, self) end)
  liveModel:Hide()
  iconTex = holder:CreateTexture(nil, "ARTWORK")
  iconTex:SetSize(96, 96)
  iconTex:SetPoint("CENTER", holder, "CENTER", 0, 0)
  iconTex:Hide()

  frame:SetScript("OnClick", function() ns.Log.safe(FEATURE, MockShow.hide) end)
  frame:SetScript("OnUpdate", function(self, elapsed)
    ns.Log.safe(FEATURE, function()
      if not hideAt then return end
      local now = ns.now()
      if current and (not self.tcNextLaugh or now >= self.tcNextLaugh) then
        self.tcNextLaugh = now + 2.5 -- keep laughing (the animation ends after a couple of seconds)
        laugh(current)
      end
      if now >= hideAt + FADE then
        MockShow.hide()
      elseif now >= hideAt then
        self:SetAlpha(math.max(0, 1 - (now - hideAt) / FADE))
      end
    end)
  end)
  frame:Hide()
end

-- Next to the crew panel: on its right, or on its left when there's no room on the right. Top middle of the
-- screen when the panel is hidden.
local function place()
  frame:ClearAllPoints()
  local panel = TwizCrewPanel
  local shown = panel and panel.IsShown and panel:IsShown()
  local right = shown and panel.GetRight and panel:GetRight()
  if type(right) ~= "number" or right <= 0 then
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    return "top"
  end
  -- the panel has its own scale: compare in screen pixels
  local ps = tonumber(panel.GetEffectiveScale and panel:GetEffectiveScale()) or 1
  local us = tonumber(frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
  if ps <= 0 then ps = 1 end
  if us <= 0 then us = 1 end
  local screen = UIParent.GetWidth and UIParent:GetWidth()
  local roomRight = type(screen) == "number" and screen > 0 and (right * ps + (GAP + WIDTH) * us <= screen * us)
  if roomRight or type(screen) ~= "number" or screen <= 0 then
    frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", GAP, 0)
    return "right"
  end
  frame:SetPoint("TOPRIGHT", panel, "TOPLEFT", -GAP, 0)
  return "left"
end
MockShow.place = function() if frame then return place() end end

local function giveBack()
  if borrowed then
    park(borrowed)
    borrowed = nil
  end
end

function MockShow.hide()
  if not frame then return end
  giveBack()
  hideAt, current = nil, nil
  liveModel:Hide(); iconTex:Hide()
  frame:Hide()
end

-- Which picture we'd use for this friend right now: "live", "remembered" or "icon".
function MockShow.pick(name)
  if liveUnit(name) then return "live" end
  if MockShow.isRemembered(name) then return "remembered" end
  return "icon"
end

-- Shows the show. name: who mocked you; text: the roast. opts (test tools): { mode =, unit =, look =, class = }.
-- Returns the mode used.
function MockShow.show(name, text, opts)
  opts = opts or {}
  if not frame then build() end
  MockShow.hide()
  local m = ns.roster and ns.roster:get(name)
  local mode = opts.mode or MockShow.pick(name)
  current = nil
  if mode == "live" then
    local unit = opts.unit or liveUnit(name)
    if unit and try(liveModel, "SetUnit", unit) then
      liveModel:Show()
      current = liveModel
      if not opts.unit then remember(name, unit) end
    else
      mode = "icon"
    end
  elseif mode == "remembered" then
    borrowed = remembered[name:lower()]
    borrowed:SetParent(holder)
    borrowed:ClearAllPoints()
    borrowed:SetAllPoints(holder)
    borrowed:Show()
    current = borrowed
  end
  if mode == "icon" then
    ns.ClassIcon.apply(iconTex, opts.class or (m and m.class))
    iconTex:Show()
  end
  if current then laugh(current) end
  nameText:SetText(ns.Util.safeText(tostring(name)) .. " laughs at you:")
  bubbleText:SetText(ns.Util.safeText(tostring(text)))
  -- the bubble grows with the roast (long ones wrap onto more lines)
  local nameH = tonumber(nameText.GetStringHeight and nameText:GetStringHeight()) or 0
  local textH = tonumber(bubbleText.GetStringHeight and bubbleText:GetStringHeight()) or 0
  if nameH <= 0 then nameH = 14 end
  if textH <= 0 then textH = 20 end
  local bubbleH = math.max(58, math.floor(nameH + textH + 22))
  bubble:SetHeight(bubbleH)
  frame:SetHeight(bubbleH + 4 + MODEL_H)
  MockShow.lastSound = nil
  if ns.Modules.setting(FEATURE, "mockSound") ~= false then
    local race, sex
    local unit = (mode == "live") and (opts.unit or liveUnit(name)) or nil
    if unit then
      local _, _, r = call(UnitRace, unit)
      race, sex = readable(r) and r or nil, call(UnitSex, unit)
    end
    local look = opts.look or (m and MockShow.decodeLook(m.look))
    if (not race or not readable(sex)) and look then race, sex = look.race, look.sex end
    local file = MockShow.laughSound(race, sex)
    if file and type(PlaySoundFile) == "function" then
      pcall(PlaySoundFile, file, "Master")
      MockShow.lastSound = file
    end
  end
  frame.tcNextLaugh = nil
  place()
  frame:SetAlpha(1)
  frame:Show()
  hideAt = ns.now() + SECONDS
  ns.Log.add("info", "mock show: %s (%s)", tostring(name), mode)
  return mode
end

function MockShow.isShown() return frame ~= nil and hideAt ~= nil end

function MockShow.start()
  if MockShow.started then return end
  MockShow.started = true
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(CAPTURE_TICK, function() ns.Log.safe(FEATURE, lookAround) end)
  end
end
