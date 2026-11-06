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

-- members: already sorted. titleOf(name) -> award title | nil (optional; online rows only). Returns row models.
function PanelLogic.rows(members, settings, relationOf, tagsOn, now, wall, titleOf)
  settings = settings or {}
  local out = {}
  for _, m in ipairs(members or {}) do
    local offline = not m.online
    if not (offline and settings.showOffline == false) then
      local row = {
        name = text(m.name), class = m.class, level = level(m.level), zoneText = zoneText(m),
        status = text(m.status), xp = percent(m.xp), tags = tagList(m, settings, relationOf, tagsOn),
        offline = offline,
      }
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
    zone = fields.zn, subzone = fields.sz, status = fields.st, tags = ns.Tags.decode(fields.tg), online = true,
  }
end
