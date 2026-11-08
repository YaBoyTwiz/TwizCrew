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
-- max level (optional). Returns row models.
function PanelLogic.rows(members, settings, relationOf, tagsOn, now, wall, titleOf, maxLevel)
  settings = settings or {}
  local style = settings.rowStyle or "full"
  local out = {}
  for _, m in ipairs(members or {}) do
    local offline = not m.online
    if not (offline and settings.showOffline == false) then
      local row = {
        name = text(m.name), class = m.class, level = level(m.level), zoneText = zoneText(m),
        status = text(m.status), xp = percent(m.xp), tags = tagList(m, settings, relationOf, tagsOn),
        offline = offline,
      }
      if not offline then
        row.quest = ns.Quest and ns.Quest.short(m.questName, m.questObjectives, m.questComplete) or nil
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
  return out
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
