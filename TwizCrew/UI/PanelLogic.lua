-- Pure panel logic (no WoW API): row models, when the panel shows, the scroll window, the header text.
local _, ns = ...

local PanelLogic = {}
ns.PanelLogic = PanelLogic

local function text(v)
  if type(v) ~= "string" then return "" end
  return ns.Util.safeText(v)
end

local function percent(v)
  local n = tonumber(v)
  if n == nil or n ~= n then return nil end
  if n < 0 then return 0 end
  if n > 100 then return 100 end
  return math.floor(n)
end

local function level(v)
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  return math.floor(n)
end

local function zoneText(m)
  local zone = type(m.zone) == "string" and m.zone or ""
  local sub = type(m.subzone) == "string" and m.subzone or ""
  if zone == "" then return text(sub) end
  if sub == "" or sub == zone then return text(zone) end
  return text(zone .. ", " .. sub)
end

-- Tag ids in Tags.ORDER: the member's own tags (when the tags module is on) plus LAYER from the layer module.
-- A friend can never send LAYER themselves: only relationOf decides it.
local function tagList(m, settings, relationOf, tagsOn)
  local set = {}
  if not m.online then return {} end
  if tagsOn and type(m.tags) == "table" then
    for id in pairs(m.tags) do if id ~= "LAYER" then set[id] = true end end
  end
  if relationOf and relationOf(m.name) == "different" then set.LAYER = true end
  local list = {}
  for _, id in ipairs(ns.Tags.ORDER) do
    if set[id] and settings["tag_" .. id] ~= false then list[#list + 1] = id end
  end
  return list
end

---------------------------------------------------------------------------------------------- level progress
local DOT = "\194\183" -- the middle dot "·" (UTF-8)

local function count(v)
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

-- Max level: the friend's copy says it needs no XP (xm = 0), or the level is the game's max (older copies).
function PanelLogic.isMaxLevel(m, maxLevel)
  if count(m.xpMax) == 0 then return true end
  local lv = level(m.level)
  return lv ~= nil and maxLevel ~= nil and lv >= maxLevel
end

-- The level and XP text on a row, made to fit the row style (nil when there is nothing to say):
-- full and compact "Lv 12 · 63%", tiny "63%"; at max level "Lv 60 · max level" (full), "Lv 60 · max", "max".
function PanelLogic.xpText(style, lv, xp, atMax)
  lv, xp = level(lv), percent(xp)
  if atMax then
    if style == "tiny" or not lv then return "max" end
    return "Lv " .. lv .. " " .. DOT .. (style == "full" and " max level" or " max")
  end
  if not xp then return nil end
  if style == "tiny" or not lv then return xp .. "%" end
  return "Lv " .. lv .. " " .. DOT .. " " .. xp .. "%"
end

-- 1234567 -> "1,234,567" (whole numbers, rounded down)
function PanelLogic.thousands(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local sign, digits = s:match("^(%-?)(%d+)$")
  if not digits then return s end
  digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if digits:sub(1, 1) == "," then digits = digits:sub(2) end
  return sign .. digits
end

-- "About 25 min to level", "About 1 h 20 min to level"
function PanelLogic.durationText(seconds)
  local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
  if minutes < 60 then return "About " .. minutes .. " min to level" end
  local h, mm = math.floor(minutes / 60), minutes % 60
  if mm == 0 then return "About " .. h .. " h to level" end
  return "About " .. h .. " h " .. mm .. " min to level"
end

-- Seconds to the next level at the friend's pace this play session (track: see Roster), or nil when there is no
-- real pace yet (too few gains, too little playing time), the friend looks idle, or the answer would be wild.
function PanelLogic.timeToLevel(track, left, now)
  local c = ns.Config
  if type(track) ~= "table" or not count(left) or left <= 0 or not count(now) then return nil end
  if (track.gains or 0) < c.XP_MIN_GAINS or (track.active or 0) < c.XP_MIN_ACTIVE then return nil end
  if (track.earned or 0) <= 0 or now - (track.lastGain or 0) > c.XP_IDLE_AFTER then return nil end
  local seconds = left / (track.earned / track.active)
  if seconds > c.XP_MAX_ESTIMATE then return nil end
  return seconds
end

-- A new scale keeps the panel's corner where it is on screen: the saved offsets are in scaled units, so they
-- shrink when the scale grows. Unchanged when either scale is missing or zero.
function PanelLogic.rescalePosition(x, y, oldScale, newScale)
  x, y, oldScale, newScale = tonumber(x), tonumber(y), tonumber(oldScale), tonumber(newScale)
  if not x or not y then return x, y end
  if not oldScale or oldScale <= 0 or not newScale or newScale <= 0 then return x, y end
  local k = oldScale / newScale
  return x * k, y * k
end

-- "TwizCrew v0.1.5 (older than yours)" for the row tooltip; nil when we don't know their version.
function PanelLogic.versionLine(ver)
  if type(ver) ~= "string" or ver == "" then return nil end
  local line = "TwizCrew v" .. text(ver)
  if ns.Util.isVersion(ver) and ns.VERSION then
    local c = ns.Util.compareVersions(ver, ns.VERSION)
    if c < 0 then line = line .. " (older than yours)" elseif c > 0 then line = line .. " (newer than yours)" end
  end
  return line
end

-- The tooltip's second part (online friends): where they are, the quest they're on with its objectives, their
-- typed status. nil when there's nothing to say.
function PanelLogic.infoLines(m)
  local lines = {}
  local where = zoneText(m)
  if where ~= "" then lines[#lines + 1] = "Where: " .. where end
  if type(m.questName) == "string" and m.questName ~= "" then
    lines[#lines + 1] = "Quest: " .. text(m.questName) .. (m.questComplete and " (ready to turn in)" or "")
    for _, o in ipairs(ns.Quest and ns.Quest.objectiveLines(m.questObjectives) or {}) do
      lines[#lines + 1] = "   - " .. text(o)
    end
    -- can I get it? (only when we can tell)
    if ns.Quest and ns.Quest.canGet then
      local shareable = (m.questShareable == true or m.questShareable == false) and m.questShareable or nil
      local status, words = ns.Quest.canGet(m.questId, m.questName, shareable)
      if status ~= "unknown" and words then
        lines[#lines + 1] = "   " .. (status == "ok" and "You can get it: right-click to ask them to share it"
          or ("You: " .. words))
      end
    end
  end
  if type(m.status) == "string" and m.status ~= "" then lines[#lines + 1] = 'Status: "' .. text(m.status) .. '"' end
  if #lines == 0 then return nil end
  return lines
end

-- The lines under the name in a row's tooltip.
function PanelLogic.tooltipLines(m, now, maxLevel)
  local lv, xp = level(m.level), percent(m.xp)
  local lines = {}
  local head = lv and ("Level " .. lv) or "Level unknown"
  if not m.online then return { head } end
  if PanelLogic.isMaxLevel(m, maxLevel) then return { head, "Max level" } end
  lines[1] = xp and (head .. " " .. DOT .. " " .. xp .. "%") or head
  local cur, need = count(m.xpCur), count(m.xpMax)
  if cur and need and need > 0 then
    local left = math.max(0, need - cur)
    lines[#lines + 1] = PanelLogic.thousands(left) .. " XP to level " .. (lv and lv + 1 or "next")
    local rested = count(m.rested)
    if rested and rested > 0 then lines[#lines + 1] = "Rested: " .. PanelLogic.thousands(rested) .. " XP" end
    local seconds = PanelLogic.timeToLevel(m.xpTrack, left, now)
    if seconds then lines[#lines + 1] = PanelLogic.durationText(seconds) end
  end
  return lines
end

-- members: already sorted. titleOf(name) -> award title | nil (optional; online rows only). maxLevel: the game's
-- max level (optional). Returns row models, and how many offline friends were left out (showOffline off).
function PanelLogic.rows(members, settings, relationOf, tagsOn, now, wall, titleOf, maxLevel)
  settings = settings or {}
  local style = settings.rowStyle or "full"
  local out = {}
  local hidden = 0
  for _, m in ipairs(members or {}) do
    local offline = not m.online
    if offline and settings.showOffline == false then hidden = hidden + 1 end
    if not (offline and settings.showOffline == false) then
      local row = {
        name = text(m.name), class = m.class, level = level(m.level), zoneText = zoneText(m),
        status = text(m.status), xp = percent(m.xp), tags = tagList(m, settings, relationOf, tagsOn),
        offline = offline,
      }
      if not offline then
        row.quest = ns.Quest and ns.Quest.short(m.questName, m.questObjectives, m.questComplete) or nil
        if type(m.questName) == "string" and m.questName ~= "" then
          row.questName = m.questName
          row.questId = tonumber(m.questId)
          if m.questShareable == true or m.questShareable == false then row.questShareable = m.questShareable end
          -- can they share it with me? yes when we know I can get it (Questie), or when it can be shared and I
          -- neither have it nor did it (without Questie we can't check level or earlier quests)
          -- questShare: "yes" (they can share it with me), "no" (they can't: questWhy says why), "same" (I'm on it
          -- too), nil (can't tell)
          if ns.Quest and ns.Quest.canGet then
            local status, words = ns.Quest.canGet(row.questId, m.questName, row.questShareable)
            row.questCanGet, row.questWhy = status, words
            if status == "ok" or (status == "unknown" and row.questShareable == true and row.questId ~= nil) then
              row.questShare = "yes"
            elseif status == "have" then
              row.questShare = "same"
            elseif status == "no" or status == "done" or status == "unshareable" then
              row.questShare = "no"
            end
          end
        end
        row.questDone = m.questComplete and true or false
        row.atMax = PanelLogic.isMaxLevel(m, maxLevel)
        if settings.xpText ~= false then row.xpText = PanelLogic.xpText(style, m.level, m.xp, row.atMax) end
      end
      local tip = settings.xpTooltip ~= false and PanelLogic.tooltipLines(m, now, maxLevel) or {}
      if not offline then row.info = PanelLogic.infoLines(m) end
      local ver = PanelLogic.versionLine(m.ver)
      if ver then tip[#tip + 1] = ver end
      if #tip > 0 then row.tip = tip end
      if offline then
        if type(m.lastSeen) == "number" and type(wall) == "number" then
          row.offlineText = "Offline, last seen " .. ns.Util.ago(wall - m.lastSeen)
        else
          row.offlineText = "Offline"
        end
      elseif titleOf then
        local title = titleOf(m.name)
        if type(title) == "string" and title ~= "" then row.title = text(title) end
      end
      out[#out + 1] = row
    end
  end
  -- who else is on the same quest (online friends, and me): a line in each one's tooltip
  local byQuest = {}
  local function questKey(id, name)
    if tonumber(id) then return "#" .. tonumber(id) end
    if type(name) == "string" and name ~= "" then return "=" .. name end
  end
  for _, m in ipairs(members or {}) do
    local k = m.online and questKey(m.questId, m.questName)
    if k then byQuest[k] = byQuest[k] or {}; table.insert(byQuest[k], text(m.name)) end
  end
  local mine = ns.Self and ns.Self.lastSent and ns.Self.lastSent() or {}
  local myKey = questKey(mine.qi, mine.qn)
  for _, row in ipairs(out) do
    local k = not row.offline and questKey(row.questId, row.questName)
    if k then
      local others = {}
      for _, n in ipairs(byQuest[k] or {}) do if n ~= row.name then others[#others + 1] = n end end
      if myKey == k and not (ns.isMe and ns.isMe(row.name)) then others[#others + 1] = "you" end
      if #others > 0 then
        row.questMates = others
        row.info = row.info or {}
        local line = "   Also on it: " .. table.concat(others, ", ")
        local at = #row.info + 1
        for i, l in ipairs(row.info) do if l:find("^Status:") then at = i; break end end
        table.insert(row.info, at, line)
      end
    end
  end
  return out, hidden
end

-- What the panel draws, top to bottom: the online rows, then the "Offline (N)" bar (when anyone is offline), then
-- the offline rows when the bar is open. rows: from PanelLogic.rows; hidden: its second result; open: showOffline.
function PanelLogic.entries(rows, hidden, open)
  local on, off = {}, {}
  for _, r in ipairs(rows or {}) do
    if r.offline then off[#off + 1] = r else on[#on + 1] = r end
  end
  local out = {}
  for _, r in ipairs(on) do out[#out + 1] = r end
  local count = #off + (tonumber(hidden) or 0)
  if count > 0 then
    out[#out + 1] = { bar = true, count = count, open = open and true or false }
    if open then for _, r in ipairs(off) do out[#out + 1] = r end end
  end
  return out
end

-- The offline bar's words: "Offline (3)" with a hint which way a click goes.
function PanelLogic.offlineBarText(count, open)
  return "Offline (" .. (tonumber(count) or 0) .. ")" .. (open and "  -  click to hide" or "  -  click to show")
end

-- ctx = { inCombat, inInstance, onlineCount }
function PanelLogic.visible(settings, ctx)
  settings, ctx = settings or {}, ctx or {}
  if settings.hideInCombat and ctx.inCombat then return false end
  if settings.hideInInstance and ctx.inInstance then return false end
  if settings.hideWhenAlone and (ctx.onlineCount or 0) == 0 then return false end
  return true
end

-- Which rows to draw: first, last (1-based). offset is clamped to the valid range.
function PanelLogic.window(rowCount, offset, maxRows)
  local most = math.max(0, rowCount - maxRows)
  offset = math.floor(tonumber(offset) or 0)
  if offset < 0 then offset = 0 elseif offset > most then offset = most end
  return offset + 1, math.min(rowCount, offset + maxRows)
end

-- The version shown after "TwizCrew" in the panel's title ("" in the tiny row style: the header is too narrow).
function PanelLogic.titleVersion(style, version)
  if style == "tiny" or type(version) ~= "string" or version == "" then return "" end
  return "v" .. ns.Util.safeText(version)
end

function PanelLogic.headerText(online, total)
  return (online or 0) .. " of " .. (total or 0) .. " online"
end

-- My own row, from what I last sent (wire fields) and my name.
function PanelLogic.selfMember(name, fields)
  fields = fields or {}
  return {
    name = name, class = fields.cl, level = tonumber(fields.lv), xp = tonumber(fields.xp),
    xpCur = tonumber(fields.xc), xpMax = tonumber(fields.xm), rested = tonumber(fields.rx),
    zone = fields.zn, subzone = fields.sz, status = fields.st, tags = ns.Tags.decode(fields.tg), online = true,
  }
end

---------------------------------------------------------------------------------------------------------- minimize
-- What the panel shows: "full" (everything), "mini" (just the header bar) or "peek" (the bar and one friend's row).
-- ctx: { minimized, hover (the mouse is on the bar and "open while my mouse is on the bar" is on), peek (a peek is
-- due), inCombat }. Never a peek in a fight.
function PanelLogic.view(ctx)
  ctx = ctx or {}
  if not ctx.minimized then return "full" end
  if ctx.hover then return "full" end
  if ctx.peek and not ctx.inCombat then return "peek" end
  return "mini"
end

-- While minimized the saved position means "where the bar is". For a panel that grows up (anchored at its bottom
-- corner) the bar is the top of the panel, so a taller view (a peek, the full panel opened by the mouse) must sit
-- lower by its extra height for the bar not to jump. Returns the y of the bottom corner for a panel of `height`.
function PanelLogic.barFixedY(savedY, height, barHeight)
  savedY, height, barHeight = tonumber(savedY) or 0, tonumber(height) or 0, tonumber(barHeight) or 0
  return savedY - math.max(0, height - barHeight)
end

-- The saved bottom-corner y of a grow-up panel that is now `height` tall: when it is minimized the saved y is the
-- bar's, the bottom of the bar-sized panel.
function PanelLogic.barSavedY(bottomY, height, barHeight)
  bottomY, height, barHeight = tonumber(bottomY) or 0, tonumber(height) or 0, tonumber(barHeight) or 0
  return bottomY + math.max(0, height - barHeight)
end

-- A switch between the full panel and the bar of a grow-up panel keeps the bar still: the saved bottom y after the
-- switch. `savedY` and `fullHeight` are the ones of the full panel; barHeight the bar's.
function PanelLogic.yAfterMinimize(savedY, fullHeight, barHeight)
  return (tonumber(savedY) or 0) + (tonumber(fullHeight) or 0) - (tonumber(barHeight) or 0)
end
function PanelLogic.yAfterRestore(barSavedY, fullHeight, barHeight)
  return (tonumber(barSavedY) or 0) + (tonumber(barHeight) or 0) - (tonumber(fullHeight) or 0)
end

-- The count text on the bar: the notice line while one shows, else "2 of 3 online" (or the short "2/3").
function PanelLogic.barText(noticeLine, count)
  if type(noticeLine) == "string" and noticeLine ~= "" then return noticeLine end
  return count
end

-- The missed-counter badge text ("" when nothing was missed; "9+" past nine).
function PanelLogic.missedText(n)
  n = tonumber(n) or 0
  if n <= 0 then return "" end
  if n > 9 then return "9+" end
  return tostring(math.floor(n))
end

-- The toggle's words in the menu and chat.
function PanelLogic.miniLabel(minimized)
  return minimized and "Restore the panel" or "Minimize the panel"
end
