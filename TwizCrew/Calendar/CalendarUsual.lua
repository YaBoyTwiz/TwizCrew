-- Crew calendar, Usual times: when the crew is usually on (a grid of the week's hours), the best time to play
-- together, everyone's habits, the people picked, and the real-week grid. Part of the calendar window
-- (Calendar/CalendarUI.lua); shared names live on ns.Calendar._ (P).
local _, ns = ...

local Calendar = ns.Calendar
local P = Calendar._

local FEATURE = "calendar"
local T, Widgets = ns.Theme, ns.Widgets
local C = T.COLOR
local L = ns.CalendarLogic
local I, PREV_TEX, NEXT_TEX = P.I, P.PREV_TEX, P.NEXT_TEX
local WIDTH, HEIGHT, PAD, TOP = P.WIDTH, P.HEIGHT, P.PAD, P.TOP
local script, classHex, colored, people, altsText = P.script, P.classHex, P.colored, P.people, P.altsText
local iconTexture, arrowButton = P.iconTexture, P.arrowButton

local ICON_BEST = I .. "Spell_Holy_BorrowedTime"
local HEAT_X, HEAT_W, HEAT_H = 60, 25, 18
local heatCells, habitLines = {}, {}
local usualWeek = nil -- the Usual pane shows a real week (its Sunday, a local day number), or nil = usual times
local usualPick = {} -- Usual times for the people picked (account ids, in the order picked); none = everyone
-------------------------------------------------------------------------------------------------------- usual
-- "Nov 3" for a local day number.
local function shortDate(day)
  local _, m, d = L.civil(day)
  return string.sub(L.MONTHS[m], 1, 3) .. " " .. d
end

local function hourTip(self, w, h)
  if not GameTooltip or not self.tcValue then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  if usualWeek then
    local day = usualWeek + w
    GameTooltip:SetText(L.WEEKDAYS[w + 1] .. ", " .. shortDate(day) .. "  " .. L.clock(h * 60) .. "-" .. L.clock((h + 1) * 60))
    local any = false
    for _, pk in ipairs(self.tcWeek or {}) do
      local v = pk.grid[w][h]
      if v > 0 then
        any = true
        GameTooltip:AddLine(colored(pk.name, pk.class) .. ": " .. (v >= 1 and "the whole hour" or (math.floor(v * 60 + 0.5) .. " min")),
          1, 1, 1)
      end
    end
    if not any then GameTooltip:AddLine("Nobody on", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Click for that day's timeline", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    return
  end
  GameTooltip:SetText(L.WEEKDAYS[w + 1] .. " " .. L.clock(h * 60) .. "-" .. L.clock((h + 1) * 60))
  if self.tcPicks then
    if #self.tcPicks > 1 then
      GameTooltip:AddLine(string.format("About %.1f of these %d online", self.tcValue, #self.tcPicks), 1, 1, 1)
    end
    for _, pk in ipairs(self.tcPicks) do
      local n = math.floor(pk.grid[w][h] * 4 + 0.5)
      GameTooltip:AddLine(colored(pk.name, pk.class) .. string.format(" was on %d of the last 4 %ss", n,
        L.WEEKDAYS[w + 1]), 1, 1, 1)
    end
  else
    GameTooltip:AddLine(string.format("About %.1f of the crew online", self.tcValue), 1, 1, 1)
  end
  GameTooltip:Show()
end

local function buildUsual()
  P.usualPane = CreateFrame("Frame", nil, P.frame)
  P.usualPane:SetPoint("TOPLEFT", P.frame, "TOPLEFT", PAD, -TOP)
  P.usualPane:SetSize(WIDTH - 2 * PAD, HEIGHT - TOP - PAD)
  local star = iconTexture(P.usualPane, ICON_BEST, 22)
  star:SetPoint("TOPLEFT", P.usualPane, "TOPLEFT", 0, 0)
  P.usualPane.best = T.readable(T.text(P.usualPane, T.FONT.normal, C.title), 1)
  P.usualPane.best:SetPoint("LEFT", star, "RIGHT", 8, 0)
  P.usualPane.best:SetWidth(WIDTH - 2 * PAD - 30)
  P.usualPane.best:SetJustifyH("LEFT")
  P.usualPane.note = T.text(P.usualPane, T.FONT.small, C.muted)
  P.usualPane.note:SetPoint("TOPLEFT", P.usualPane, "TOPLEFT", 0, -28)
  P.usualPane.note:SetWidth(390)
  P.usualPane.note:SetJustifyH("LEFT")
  if P.usualPane.note.SetWordWrap then P.usualPane.note:SetWordWrap(false) end
  -- usual times or a real week (arrows step through the weeks)
  P.usualPane.weekBtn = Widgets.button(P.usualPane, "See real weeks", function() Calendar.showWeek(ns.Diary.localToday()) end, nil, FEATURE)
  P.usualPane.weekBtn:SetPoint("TOPRIGHT", P.usualPane, "TOPRIGHT", 0, -22)
  P.usualPane.usualBtn = Widgets.button(P.usualPane, "Usual times", function() Calendar.showWeek(nil) end, nil, FEATURE)
  P.usualPane.usualBtn:SetPoint("TOPRIGHT", P.usualPane, "TOPRIGHT", 0, -22)
  P.usualPane.nextWeek = arrowButton(P.usualPane, NEXT_TEX, function() Calendar.moveWeek(1) end)
  P.usualPane.nextWeek:SetPoint("RIGHT", P.usualPane.usualBtn, "LEFT", -8, 0)
  P.usualPane.weekLabel = T.readable(T.text(P.usualPane, T.FONT.small, C.title))
  P.usualPane.weekLabel:SetPoint("RIGHT", P.usualPane.nextWeek, "LEFT", -4, 0)
  P.usualPane.prevWeek = arrowButton(P.usualPane, PREV_TEX, function() Calendar.moveWeek(-1) end)
  P.usualPane.prevWeek:SetPoint("RIGHT", P.usualPane.weekLabel, "LEFT", -4, 0)
  P.usualPane.dayLabels = {}
  for h = 0, 23, 3 do
    local t = T.text(P.usualPane, T.FONT.small, C.muted)
    t:SetPoint("BOTTOMLEFT", P.usualPane, "TOPLEFT", HEAT_X + h * HEAT_W, -60)
    t:SetText(L.clock(h * 60))
  end
  for w = 0, 6 do
    local lab = T.text(P.usualPane, T.FONT.small, (w == 0 or w == 6) and C.title or C.muted)
    lab:SetPoint("TOPLEFT", P.usualPane, "TOPLEFT", 0, -(64 + w * HEAT_H) - 3)
    lab:SetText(L.SHORT_DAYS[w + 1])
    P.usualPane.dayLabels[w] = lab
    heatCells[w] = {}
    for h = 0, 23 do
      local c = CreateFrame("Frame", nil, P.usualPane)
      c:SetSize(HEAT_W - 1, HEAT_H - 1)
      c:SetPoint("TOPLEFT", P.usualPane, "TOPLEFT", HEAT_X + h * HEAT_W, -(64 + w * HEAT_H))
      c.tex = c:CreateTexture(nil, "ARTWORK")
      c.tex:SetAllPoints(c)
      c.mark = c:CreateTexture(nil, "OVERLAY")
      c.mark:SetAllPoints(c)
      T.color(c.mark, C.title, 0.55)
      c.mark:Hide()
      c:EnableMouse(true)
      script(c, "OnEnter", function(self) hourTip(self, w, h) end)
      script(c, "OnMouseUp", function(_, button)
        if button == "LeftButton" and usualWeek then Calendar.openDay(usualWeek + w) end
      end)
      script(c, "OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      heatCells[w][h] = c
    end
  end
  local whoTop = 72 + 7 * HEAT_H
  local who = T.text(P.usualPane, T.FONT.normal, C.title)
  who:SetPoint("TOPLEFT", P.usualPane, "TOPLEFT", 0, -whoTop)
  who:SetText("Everyone's usual times")
  local hint = T.text(P.usualPane, T.FONT.small, C.muted)
  hint:SetPoint("LEFT", who, "RIGHT", 10, 0)
  hint:SetText("click people to see only them above (click again to take them off)")
  P.usualPane.everyone = Widgets.button(P.usualPane, "Show everyone", function() Calendar.showUsualFor(nil) end, nil, FEATURE)
  P.usualPane.everyone:SetPoint("TOPRIGHT", P.usualPane, "TOPRIGHT", 0, -(whoTop - 4))
  for i = 1, 10 do
    local r = CreateFrame("Button", nil, P.usualPane)
    r:SetSize(WIDTH - 2 * PAD, 20)
    r:SetPoint("TOPLEFT", P.usualPane, "TOPLEFT", 0, -(whoTop + 22 + (i - 1) * 21))
    r.face = r:CreateTexture(nil, "ARTWORK")
    r.face:SetSize(T.icon(16), T.icon(16))
    r.face:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text = T.text(r, T.FONT.small, C.text)
    r.text:SetPoint("LEFT", r.face, "RIGHT", 6, 0)
    r.text:SetWidth(WIDTH - 2 * PAD - 24)
    r.text:SetJustifyH("LEFT")
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints(r)
    T.color(r.sel, C.title, 0.18)
    r.sel:Hide()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(r)
    T.color(hl, C.white, 0.08)
    script(r, "OnClick", function(self)
      if not self.tcId then return end
      Calendar.toggleUsual(self.tcId)
    end)
    habitLines[i] = r
  end
end
P.buildUsual = buildUsual

-------------------------------------------------------------------------------------------------------- draw
local function drawUsual()
  local everyone = people()
  local today, off = ns.Diary.localToday(), ns.Diary.offsetOn -- each day its own offset
  local u = L.usual(everyone, today, off, 4)
  Calendar.lastUsual = u
  -- the people picked: only their hours (one person: in their class color; each square = how many of the last
  -- 4 weeks they were on then; several: how many of them are usually on, and their best time together)
  local keep, subset, picks = {}, {}, {}
  for _, id in ipairs(usualPick) do
    local p = everyone[id]
    if p and not subset[id] then
      keep[#keep + 1] = id
      subset[id] = p
      local one = L.usual({ [id] = p }, today, off, 4)
      local info = one.people[1] or { id = id, name = p.name, class = p.class }
      info.grid = one.grid
      picks[#picks + 1] = info
    end
  end
  usualPick = keep
  local mine = #picks > 0 and L.usual(subset, today, off, 4) or nil
  Calendar.lastUsualOne = #picks == 1 and mine or nil
  Calendar.lastUsualPick = mine and picks or nil
  local who = #picks == 1 and picks[1] or nil
  local grid = (mine or u).grid
  local best = (not who) and L.bestTime(mine or u) or nil
  -- a real week: who was really on, hour by hour, on those dates
  local wk = usualWeek and L.week(mine and subset or everyone, usualWeek, off) or nil
  Calendar.lastWeek = wk
  for w = 0, 6 do
    P.usualPane.dayLabels[w]:SetText(L.SHORT_DAYS[w + 1] .. (wk and (" " .. select(3, L.civil(usualWeek + w))) or ""))
  end
  if wk then
    P.usualPane.weekBtn:Hide(); P.usualPane.usualBtn:Show()
    P.usualPane.prevWeek:Show(); P.usualPane.nextWeek:Show(); P.usualPane.weekLabel:Show()
    P.usualPane.weekLabel:SetText(shortDate(usualWeek) .. " - " .. shortDate(usualWeek + 6))
  else
    P.usualPane.weekBtn:Show(); P.usualPane.usualBtn:Hide()
    P.usualPane.prevWeek:Hide(); P.usualPane.nextWeek:Hide(); P.usualPane.weekLabel:Hide()
  end
  if wk then
    grid, best = wk.grid, nil
    local parts = {}
    for i, pk in ipairs(wk.people) do
      if i <= 4 then parts[#parts + 1] = colored(pk.name, pk.class) .. " " .. L.duration(pk.minutes) end
    end
    if #wk.people > 4 then parts[#parts + 1] = "+" .. (#wk.people - 4) .. " more" end
    P.usualPane.best:SetText("Week of " .. shortDate(usualWeek) .. ": " .. (#parts > 0 and table.concat(parts, ", ")
      or "nobody played (that we know of)"))
    P.usualPane.note:SetText("Who was really on, your time. Hover a square; click one for that day.")
  elseif who then
    P.usualPane.best:SetText(colored(who.name, who.class) .. ": " .. (who.perWeek
      and ("about " .. L.duration(who.perWeek) .. " a week, " .. L.habit(who)) or "no play time in the last 4 weeks"))
    P.usualPane.note:SetText("The last 4 weeks, in your local time. Brighter = more weeks " .. ns.Util.safeText(who.name)
      .. " was on at that hour. Hover a square.")
  elseif mine then
    local names = {}
    for i, pk in ipairs(picks) do names[i] = colored(pk.name, pk.class) end
    P.usualPane.best:SetText(best and (L.bestTimeText(best, #picks) .. " for " .. table.concat(names, ", "))
      or ("No time yet when " .. table.concat(names, ", ") .. " play together."))
    P.usualPane.note:SetText("The last 4 weeks, in your local time. Brighter = more of these " .. #picks
      .. " online. Hover a square.")
  else
    P.usualPane.best:SetText(L.bestTimeText(best, u.count))
    P.usualPane.note:SetText("The last 4 weeks, in your local time. Brighter = more of the crew online. Hover a square.")
  end
  if mine then P.usualPane.everyone:Show() else P.usualPane.everyone:Hide() end
  local top = 0
  for w = 0, 6 do for h = 0, 23 do if grid[w][h] > top then top = grid[w][h] end end end
  if wk then
    top = who and 1 or 0
    if not who then for w = 0, 6 do for h = 0, 23 do if grid[w][h] > top then top = grid[w][h] end end end end
  elseif who then top = 1 elseif mine then top = #picks end -- every week / all of them = full brightness
  local hue = who and classHex(who.class) or "33cc66"
  for w = 0, 6 do
    for h = 0, 23 do
      local v = grid[w][h]
      local c = heatCells[w][h]
      c.tcValue = v
      c.tcPicks = mine and picks or nil
      c.tcWeek = wk and wk.people or nil
      if v > 0 and top > 0 then T.color(c.tex, hue, 0.15 + 0.85 * v / top) else T.color(c.tex, C.row, 0.6) end
      local inBest = (not wk) and best and best.weekday == w and h >= best.from and h < best.to
      if inBest then c.mark:Show() else c.mark:Hide() end
    end
  end
  for i, r in ipairs(habitLines) do
    local p = u.people[i]
    r.tcId = p and p.id or nil
    local picked = false
    for _, id in ipairs(usualPick) do if p and id == p.id then picked = true end end
    if picked then r.sel:Show() else r.sel:Hide() end
    if p then
      ns.ClassIcon.apply(r.face, p.class)
      r.face:Show()
      local alts = altsText(ns.Diary.people()[p.id])
      r.text:SetText(colored(p.name, p.class) .. ":  about " .. L.duration(p.perWeek) .. " a week, " .. L.habit(p)
        .. (alts and ("  (" .. alts .. ")") or ""))
      r:Show()
    elseif i == 1 then
      r.face:Hide()
      r.text:SetText("Nobody yet. Play times show up here as the crew plays with this version.")
      r:Show()
    else
      r:Hide()
    end
  end
end
P.drawUsual = drawUsual

-- Usual times for one person (an account id), or everyone (nil).
function Calendar.showUsualFor(id)
  usualPick = id and { id } or {}
  P.view = "usual"
  Calendar.refresh()
end

-- The grid for the real week holding local day `day` (nil: back to usual times).
function Calendar.showWeek(day)
  usualWeek = day and (day - L.weekday(day)) or nil
  P.view = "usual"
  Calendar.refresh()
end

function Calendar.moveWeek(delta)
  if not usualWeek then return end
  usualWeek = usualWeek + 7 * (tonumber(delta) or 0)
  Calendar.refresh()
end

-- Add a person to the Usual times grid, or take them off if they are on it.
function Calendar.toggleUsual(id)
  local out, found = {}, false
  for _, v in ipairs(usualPick) do if v == id then found = true else out[#out + 1] = v end end
  if not found then out[#out + 1] = id end
  usualPick = out
  P.view = "usual"
  Calendar.refresh()
end
