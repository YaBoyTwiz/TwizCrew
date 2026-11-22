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

-- The guild members the addon has never heard from (no roster row), as members for the panel: { name = key, class,
-- level, zone, online, lastSeen = their last-online time, noAddon = true }. guild: ns.Guild.members(); have: set of
-- keys the roster has a row for; myKey: left out. A member who stays in the list is one row per key.
function PanelLogic.noAddonMembers(guild, have, myKey)
  local out = {}
  for _, e in ipairs(guild or {}) do
    if type(e) == "table" and type(e.key) == "string" and e.key ~= myKey and not (have and have[e.key]) then
      out[#out + 1] = { name = e.key, class = e.class, level = e.level, zone = e.zone, online = e.online and true or false,
        lastSeen = e.lastOnline, noAddon = true }
    end
  end
  return out
end

-- How many people the main view holds: my party and my pinned members who are online, and me (always). Counted the
-- way the rows are sectioned: list is the members (roster rows and noAddonMembers), ctx the one of PanelLogic.rows.
function PanelLogic.hereCount(list, ctx, showNoAddon, active)
  ctx = ctx or {}
  local n = active and 1 or 0
  for _, m in ipairs(list or {}) do
    if m.online and not m.self and not (m.noAddon and showNoAddon == false) then
      local key = m.name
      if (ctx.party and ctx.party[key]) or (ctx.pins and ctx.pins[key] == true) then n = n + 1
      elseif not active then n = n + 1 end
    end
  end
  return n
end

-- The "online" half of the header: guild members online, without the no-addon ones while they are hidden.
function PanelLogic.guildOnline(onlineAll, noAddon, showNoAddon)
  local n = tonumber(onlineAll) or 0
  if showNoAddon == false then
    for _, m in ipairs(noAddon or {}) do if m.online then n = n - 1 end end
  end
  return math.max(0, n)
end

local function sectionOf(m, online, pinned, party)
  if m.self then return "self" end -- my own row: the top of the main view, no heading
  if not online then return "offline" end
  if party then return "party" end
  if pinned then return "pinned" end
  return "guild"
end

-- members: already sorted (roster rows and noAddonMembers together). titleOf(name) -> award title | nil (optional;
-- online rows only). maxLevel: the game's max level (optional). ctx (optional): { party = set of keys in my group,
-- pins = set of pinned keys, canPin, get = fn(key) -> guild entry, display = fn(key) -> shown name }.
-- Returns row models (each with key, section "party" | "pinned" | "guild" | "offline", pinned, pinAction "pin" |
-- "unpin" | nil), and how many offline members were left out (showOffline off).
function PanelLogic.rows(members, settings, relationOf, tagsOn, now, wall, titleOf, maxLevel, ctx)
  settings = settings or {}
  ctx = ctx or {}
  local style = settings.rowStyle or "full"
  local out = {}
  local hidden = 0
  for _, m in ipairs(members or {}) do
    local offline = not m.online
    local skip = m.noAddon and settings.showNoAddon == false
    if offline and settings.showOffline == false and not skip then hidden = hidden + 1 end
    if not (skip or (offline and settings.showOffline == false)) then
      local key = m.name
      local pinned = ctx.pins ~= nil and ctx.pins[key] == true
      local row = {
        key = key, name = text(ctx.display and ctx.display(key) or key), class = m.class, level = level(m.level),
        zoneText = zoneText(m), status = text(m.status), xp = percent(m.xp),
        tags = m.noAddon and {} or tagList(m, settings, relationOf, tagsOn), offline = offline,
        noAddon = m.noAddon and true or nil, pinned = pinned,
        section = sectionOf(m, not offline, pinned, ctx.party ~= nil and ctx.party[key] == true),
      }
      if ctx.canPin and not m.self and not ns.isTestName(key) then
        if pinned then row.pinAction = "unpin"
        elseif row.section == "guild" or row.section == "offline" then row.pinAction = "pin" end
      end
      if m.noAddon then
        -- the guild list tells name, class, level and zone; nothing else is known
      elseif not offline then
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
      if not m.noAddon then
        local tip = settings.xpTooltip ~= false and PanelLogic.tooltipLines(m, now, maxLevel) or {}
        if not offline then row.info = PanelLogic.infoLines(m) end
        local ver = PanelLogic.versionLine(m.ver)
        if ver then tip[#tip + 1] = ver end
        if #tip > 0 then row.tip = tip end
      end
      if offline then
        -- last seen: what the addon recorded, else the guild list's last-online time
        local seen = type(m.lastSeen) == "number" and m.lastSeen or nil
        if seen == nil and ctx.get then
          local e = ctx.get(key)
          if type(e) == "table" and type(e.lastOnline) == "number" then seen = e.lastOnline end
        end
        if seen ~= nil and type(wall) == "number" then
          row.offlineText = "Offline, last seen " .. ns.Util.ago(math.max(0, wall - seen))
        else
          row.offlineText = "Offline"
        end
      elseif m.noAddon then
        -- (no title)
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
  local memberOf = {} -- key -> member, built once
  for _, m in ipairs(members or {}) do memberOf[m.name] = m end
  for _, row in ipairs(out) do
    local m = memberOf[row.key]
    local k = m and m.online and not m.noAddon and questKey(m.questId, m.questName)
    if k then byQuest[k] = byQuest[k] or {}; table.insert(byQuest[k], row.name) end
  end
  local mine = ns.Self and ns.Self.lastSent and ns.Self.lastSent() or {}
  local myKey = questKey(mine.qi, mine.qn)
  for _, row in ipairs(out) do
    local k = not row.offline and questKey(row.questId, row.questName)
    if k then
      local others = {}
      for _, n in ipairs(byQuest[k] or {}) do if n ~= row.name then others[#others + 1] = n end end
      if myKey == k and not (ns.isMe and ns.isMe(row.key)) then others[#others + 1] = "you" end
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

-- What the panel draws, top to bottom: { head = "My party" } and the party rows (when grouped and there are any);
-- { head = "Pinned" } and the pinned online rows (the heading only when something else is shown with them); the
-- "Guild online (N)" bar and, when it is open, its rows; the "Offline (N)" bar and its rows when open.
-- rows: from PanelLogic.rows; hidden: its second result (offline members left out).
-- opts: { inGroup, guildOpen, offlineOpen, hiddenOffline, flat }. With no party row and no pinned online row the
-- Guild online list is open whatever guildOpen says. flat: no guild bar, the online rows are listed as they are
-- (the guild is not usable yet; only pretend friends can be shown).
function PanelLogic.entries(rows, opts)
  opts = opts or {}
  local me, party, pinned, guild, off = {}, {}, {}, {}, {}
  for _, r in ipairs(rows or {}) do
    if r.section == "self" then me[#me + 1] = r
    elseif r.offline then off[#off + 1] = r
    elseif r.section == "party" and opts.inGroup then party[#party + 1] = r
    elseif r.section == "pinned" then pinned[#pinned + 1] = r
    else guild[#guild + 1] = r end
  end
  local out = {}
  local offCount = #off + (tonumber(opts.hiddenOffline) or 0)
  for _, r in ipairs(me) do out[#out + 1] = r end
  if #party > 0 then
    out[#out + 1] = { head = "My party" }
    for _, r in ipairs(party) do out[#out + 1] = r end
  end
  if #pinned > 0 then
    if #party > 0 or ((#guild > 0 or offCount > 0) and not opts.flat) then out[#out + 1] = { head = "Pinned" } end
    for _, r in ipairs(pinned) do out[#out + 1] = r end
  end
  if opts.flat then
    for _, r in ipairs(guild) do out[#out + 1] = r end
  elseif #guild > 0 then
    local open = opts.guildOpen and true or false
    if #party == 0 and #pinned == 0 then open = true end
    out[#out + 1] = { bar = "guild", count = #guild, open = open }
    if open then for _, r in ipairs(guild) do out[#out + 1] = r end end
  end
  if offCount > 0 then
    local open = opts.offlineOpen and true or false
    out[#out + 1] = { bar = "offline", count = offCount, open = open }
    if open then for _, r in ipairs(off) do out[#out + 1] = r end end
  end
  return out
end

-- Height of the note under the rows: the font string's real height when the game gives one, else a guess from how many
-- characters fit on a line of `width` pixels (about 6 px each).
function PanelLogic.noteHeight(text, width, line, real)
  if type(real) == "number" and real > 0 then return real end
  local perLine = math.max(8, math.floor((tonumber(width) or 160) / 5.9))
  return math.max(1, math.ceil(#text / perLine)) * line
end

-- The bars' words: "Offline (3)" with a hint which way a click goes.
function PanelLogic.offlineBarText(count, open)
  return "Offline (" .. (tonumber(count) or 0) .. ")" .. (open and "  -  click to hide" or "  -  click to show")
end

function PanelLogic.guildBarText(count, open)
  return "Guild online (" .. (tonumber(count) or 0) .. ")" .. (open and "  -  click to hide" or "  -  click to show")
end

-- The words in the body while the addon cannot work (nil when it can). state: { inGuild, needsReload, guildName }.
function PanelLogic.stateLine(state)
  state = state or {}
  if not state.inGuild then return "TwizCrew works inside a guild. Join one and it starts by itself." end
  if state.needsReload then
    return "TwizCrew keeps separate data for each guild. Type /reload to switch to "
      .. text(state.guildName or "your guild") .. "."
  end
  if not state.active then return "Waiting for the guild list\226\128\166" end
  return nil
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

-- The header count: "3 here · 14 online" (people in the main view, guild members online); the short form "3/14".
function PanelLogic.headerCount(here, online, short)
  if short then return (here or 0) .. "/" .. (online or 0) end
  return (here or 0) .. " here " .. DOT .. " " .. (online or 0) .. " online"
end

-- My own row, from what I last sent (wire fields) and my name.
function PanelLogic.selfMember(name, fields)
  fields = fields or {}
  return {
    name = name, class = fields.cl, level = tonumber(fields.lv), xp = tonumber(fields.xp),
    xpCur = tonumber(fields.xc), xpMax = tonumber(fields.xm), rested = tonumber(fields.rx),
    zone = fields.zn, subzone = fields.sz, status = fields.st, tags = ns.Tags.decode(fields.tg), online = true,
    self = true,
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
