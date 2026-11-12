-- A calendar note opened on its own (part of module "calendar"): the whole note, when it is (in your time zone),
-- who wrote it, Going / Maybe / Can't make it buttons with who picked what, who has seen it, comments and a reply
-- box. Opening a friend's note marks it "seen" for the crew. Everything here is shared like the notes themselves.
local _, ns = ...

local NoteView = {}
ns.NoteView = NoteView

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic

local W, H, PAD = 480, 560, 14
local COMMENT_ROWS = 6
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local STATUS = {
  { id = "yes", label = "I'm going", list = "Going", tex = READY },
  { id = "maybe", label = "Maybe", list = "Maybe", tex = WAITING },
  { id = "no", label = "Can't make it", list = "Can't", tex = NOT_READY },
}

local frame, shownKey
local banner, shade, bannerTitle, bigIcon, title, meta, dungeonLine
local statusButtons, listLines, seenLine, commentRows, commentsHeader, box, deleteButton = {}, {}, nil, {}, nil, nil, nil

local function script(f, name, fn) Widgets.script(f, name, fn, FEATURE) end

local function classHex(class)
  local r, g, b = T.classColor(class)
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function colored(name, class)
  return "|cff" .. classHex(class) .. ns.Util.safeText(tostring(name or "?")) .. "|r"
end

local function names(list)
  local out = {}
  for i, p in ipairs(list) do out[i] = colored(p.name, p.class) end
  return table.concat(out, ", ")
end

local function note(key)
  local n = ns.db and ns.db.calendar and ns.db.calendar.notes and ns.db.calendar.notes[key]
  if type(n) ~= "table" or n.x then return nil end
  local copy = { key = key }
  for k, v in pairs(n) do copy[k] = v end
  return copy
end

local function reply()
  local text = box and box:GetText()
  local key, why
  if shownKey then key, why = ns.Notes.comment(shownKey, text) end
  if key then
    box:SetText("")
    box:ClearFocus()
  elseif why == "full" then
    print("TwizCrew: this note has " .. ns.Notes.MAX_COMMENTS .. " comments, the most it can take.")
  else
    print("TwizCrew: type a comment first.")
  end
end

local function build()
  frame = T.frame("Frame", "TwizCrewNoteView", UIParent)
  frame:SetSize(W, H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 60, 30)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
  script(frame, "OnDragStart", function(self) self:StartMoving() end)
  script(frame, "OnDragStop", function(self) self:StopMovingOrSizing() end)
  T.paint(frame, C.backdrop, 0.98, C.title, 2)
  T.gloss(frame, nil, 0.04, "BORDER")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TwizCrewNoteView") end
  script(frame, "OnHide", function() shownKey = nil end)
  local head = T.readable(T.text(frame, T.FONT.normal, C.title), 1)
  head:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  head:SetText("Crew note")
  local close = Widgets.button(frame, "Close", function() frame:Hide() end, nil, FEATURE)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -8)

  -- the top: a dungeon's artwork with the words on it, or a big icon with the words beside it
  banner = frame:CreateTexture(nil, "ARTWORK")
  banner:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -40)
  banner:SetSize(W - 2 * PAD, 120)
  shade = frame:CreateTexture(nil, "ARTWORK", nil, 2)
  shade:SetAllPoints(banner)
  T.gradient(shade, "VERTICAL", "000000", "000000", 0.9, 0.05)
  bannerTitle = T.readable(T.text(frame, T.FONT.normal, C.white), 5)
  bannerTitle:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 10, 10)
  bannerTitle:SetWidth(W - 2 * PAD - 20)
  bannerTitle:SetJustifyH("LEFT")
  if bannerTitle.SetShadowOffset then bannerTitle:SetShadowOffset(2, -2) end
  if bannerTitle.SetShadowColor then bannerTitle:SetShadowColor(0, 0, 0, 1) end
  bigIcon = frame:CreateTexture(nil, "ARTWORK")
  bigIcon:SetSize(48, 48)
  bigIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -46)
  bigIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  title = T.readable(T.text(frame, T.FONT.normal, C.white), 3)
  title:SetPoint("TOPLEFT", bigIcon, "TOPRIGHT", 12, 0)
  title:SetWidth(W - 2 * PAD - 64)
  title:SetJustifyH("LEFT")
  if title.SetWordWrap then title:SetWordWrap(true) end

  meta = T.text(frame, T.FONT.small, C.muted)
  meta:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -168)
  meta:SetWidth(W - 2 * PAD)
  meta:SetJustifyH("LEFT")
  dungeonLine = T.text(frame, T.FONT.small, C.title)
  dungeonLine:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -186)

  -- Going / Maybe / Can't make it
  for i, st in ipairs(STATUS) do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(146, 28)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * 152, -208)
    T.paint(b, C.button, 1, C.buttonBorder, 1)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    T.color(b.glow, C.title, 0.3)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(T.icon(18), T.icon(18))
    b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.icon:SetTexture(st.tex)
    b.text = T.text(b, T.FONT.small, C.white)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    T.color(hl, C.white, 0.1)
    script(b, "OnClick", function() NoteView.answer(st.id) end)
    statusButtons[st.id] = b
  end
  for i, st in ipairs(STATUS) do
    local fs = T.text(frame, T.FONT.small, C.text)
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(246 + (i - 1) * 18))
    fs:SetWidth(W - 2 * PAD)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    listLines[st.id] = fs
  end
  seenLine = T.text(frame, T.FONT.small, C.muted)
  seenLine:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -302)
  seenLine:SetWidth(W - 2 * PAD)
  seenLine:SetJustifyH("LEFT")
  if seenLine.SetWordWrap then seenLine:SetWordWrap(false) end

  -- comments
  local sep = frame:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -322)
  sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -322)
  T.color(sep, C.line, 1)
  commentsHeader = T.text(frame, T.FONT.normal, C.title)
  commentsHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -330)
  for i = 1, COMMENT_ROWS do
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(W - 2 * PAD, 20)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(352 + (i - 1) * 21))
    r.text = T.text(r, T.FONT.small, C.text)
    r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text:SetWidth(W - 2 * PAD - 30)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.del = Widgets.button(r, "X", function() if r.tcKey then ns.Notes.deleteComment(r.tcKey) end end, "danger", FEATURE)
    r.del:SetSize(22, 18)
    r.del:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r:EnableMouse(true)
    script(r, "OnEnter", function(self)
      if not GameTooltip or not self.tcText then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tcText, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    script(r, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    commentRows[i] = r
  end
  box = T.frame("EditBox", nil, frame)
  box:SetSize(W - 2 * PAD - 90, 24)
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(356 + COMMENT_ROWS * 21))
  T.paint(box, C.row, 1, C.rowBorder, 1)
  box:SetAutoFocus(false)
  if box.SetFontObject then box:SetFontObject(T.FONT.small) end
  if box.SetTextInsets then box:SetTextInsets(6, 6, 0, 0) end
  script(box, "OnTextChanged", function(self) -- stops at what one message can carry
    local text = self:GetText()
    local fit = ns.Notes.fitWords(text)
    if fit ~= text then self:SetText(fit) end
  end)
  script(box, "OnEnterPressed", function() reply() end)
  script(box, "OnEscapePressed", function(self) self:ClearFocus() end)
  local send = Widgets.button(frame, "Comment", function() reply() end, nil, FEATURE)
  send:SetSize(82, 24)
  send:SetPoint("LEFT", box, "RIGHT", 6, 0)
  deleteButton = Widgets.button(frame, "Delete my note", function()
    if shownKey and ns.Notes.remove(shownKey) then frame:Hide() end
  end, "danger", FEATURE)
  deleteButton:SetSize(130, 24)
  deleteButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 12)
  frame:Hide()
end

function NoteView.refresh()
  if not frame or not shownKey then return end
  local n = note(shownKey)
  if not n then frame:Hide(); return end
  local off = ns.Diary.offset()
  local dg = n.g and ns.Notes.dungeon(n.g)
  local text = ns.Util.safeText(n.t or "")
  if dg then
    ns.Calendar.setArt(banner, dg.key, ns.Notes.iconTexture(n.i))
    banner:Show(); shade:Show()
    bannerTitle:SetText(text)
    bannerTitle:Show()
    bigIcon:Hide(); title:Hide()
    dungeonLine:SetText((text ~= dg.name and (dg.name .. "  \194\183  ") or "") .. ns.Notes.dungeonLine(dg))
    dungeonLine:Show()
  else
    banner:Hide(); shade:Hide(); bannerTitle:Hide()
    bigIcon:SetTexture(ns.Notes.iconTexture(n.i))
    bigIcon:Show()
    title:SetText(text)
    title:Show()
    dungeonLine:Hide()
  end
  -- when, in your time zone; who wrote it
  local day
  if type(n.at) == "number" then day = math.floor((n.at + off) / L.DAY) else day = ns.Notes.dayOfKey(n.d) end
  local whenText = ""
  if day then
    local _, m, d = L.civil(day)
    whenText = L.WEEKDAYS[L.weekday(day) + 1] .. ", " .. L.MONTHS[m] .. " " .. d
  end
  local t = ns.Notes.timeText(n, off)
  if t then whenText = whenText .. "  \194\183  " .. t .. " your time (" .. ns.Calendar.zoneName() .. ")" end
  meta:SetText(whenText .. "  \194\183  by " .. colored(n.b, n.c))
  -- answers
  local r = ns.Notes.repliesFor(shownKey)
  NoteView.lastReplies = r
  for _, st in ipairs(STATUS) do
    local b = statusButtons[st.id]
    b.text:SetText(st.label .. " (" .. #r[st.id] .. ")")
    if r.mine == st.id then b.glow:Show() else b.glow:Hide() end
    local who = #r[st.id] > 0 and names(r[st.id]) or "|cff777777nobody yet|r"
    listLines[st.id]:SetText("|T" .. st.tex .. ":14|t  " .. st.list .. ":  " .. who)
  end
  seenLine:SetText("Seen by:  " .. (#r.seen > 0 and names(r.seen) or "nobody yet"))
  -- comments: the newest ones
  commentsHeader:SetText("Comments (" .. #r.comments .. ")")
  local first = math.max(1, #r.comments - COMMENT_ROWS + 1)
  for i, row in ipairs(commentRows) do
    local cm = r.comments[first + i - 1]
    if cm then
      local ago = cm.at and ns.Util.ago(math.max(0, ns.Diary.now() - cm.at)) or ""
      row.tcKey, row.tcText = cm.key, cm.text
      row.text:SetText(colored(cm.name, cm.class) .. ":  " .. ns.Util.safeText(cm.text) .. "  |cff777777" .. ago .. "|r")
      if cm.mine then row.del:Show() else row.del:Hide() end
      row:Show()
    else
      row.tcKey, row.tcText = nil, nil
      row:Hide()
    end
  end
  if ns.Notes.isMine(n) then deleteButton:Show() else deleteButton:Hide() end
end

-- Opens a note by its key; a friend's note is marked "seen" for the crew.
function NoteView.open(key)
  if not note(key) then return false end
  if not frame then build() end
  shownKey = key
  frame:Show()
  if not ns.Notes.isMine({ key = key }) then ns.Notes.markSeen(key) end
  NoteView.refresh()
  return true
end

-- Going / maybe / can't; picking your current answer again takes it back.
function NoteView.answer(status)
  if not shownKey then return end
  local r = ns.Notes.repliesFor(shownKey)
  ns.Notes.rsvp(shownKey, r.mine ~= status and status or nil)
end

function NoteView.isShown() return shownKey ~= nil end
function NoteView.close() if frame then frame:Hide() end; shownKey = nil end

-- Test hook: type a comment and press Enter.
function NoteView.commentForTest(text)
  if not box then return end
  rawset(box, "GetText", function() return text end)
  reply()
end
function NoteView.boxForTest() return box end
