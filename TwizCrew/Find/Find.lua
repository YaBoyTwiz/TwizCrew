-- Find the crew (extras module "find"): arrows to group members and crew meet-ups.
-- Positions: our copy sends its position to the group only (one PARTY / RAID message, never whispered), when we
-- moved or now and then, and nothing at all when not in a group. Group members' positions come from those POS
-- messages, or live from the game (UnitPosition on party units) when it tells us.
-- Meet-ups: a spot on the world map (MeetMap.lua), sent to the party or to everyone (the sender's choice) as a MEET
-- message. One meet-up at a time: the newest wins. Anyone it went to can clear it; it ends by itself after MEET_LIFE.
-- Never touches the game's own waypoint or super-tracking (QuestMaster and others use that one slot).
local _, ns = ...

local Find = {}
ns.Find = Find

local FEATURE = "find"
local Logic = ns.FindLogic
local Where = ns.Where

local positions = {}  -- name -> { c, x, y, at } from POS messages (group members only)
local private = {}    -- name -> true: they turned "Share my position" off (no arrow, not even from the game's own)
local lastSent        -- { c, x, y, at } of our last POS; { unknown = true, at } after an "unknown" one (off = true:
                      -- the one that says we don't share)
local forceSend = false
local meet            -- { id, by, c, x, y, place, audience, expires, mine }
local meetIds = {}    -- every meet-up id this copy has had or seen cleared: an old one sent again never comes back
local seq = 0
local groupNames = {} -- lower-case names in our group at the last roster look (to notice someone joining)
local arrowKey = ""   -- who has a row arrow now, to tell the panel when that changes
local ticker
local enabled = false

local function cfg() return ns.Config end
local function setting(key) return ns.Modules.setting(FEATURE, key) end

local function changed() ns.Bus.fire("FIND_CHANGED") end

------------------------------------------------------------------------------------------------------- positions
local function sendCfg()
  local c = cfg()
  return { move = c.FIND_MOVE, gap = c.FIND_GAP, keepAlive = c.FIND_KEEPALIVE }
end

-- "Unknown" (instance, no position). off: because "Share my position" is off; friends' copies then also hide the
-- game's own party position of us (older copies just read it as unknown).
local function sendUnknown(off)
  local fields = Logic.posFields(nil)
  if off then fields.off = "1" end
  ns.Comm.sendGroup("POS", fields, { replace = "POS" })
  lastSent = { unknown = true, off = off or nil, at = ns.now() }
end

local function sendPosition()
  if not Where.inGroup() then
    lastSent, forceSend = nil, false
    return
  end
  if not setting("sharePosition") then
    -- once, and again when someone joins, so every group member's copy knows to show no arrow to us
    if forceSend or not (lastSent and lastSent.off) then
      if not lastSent or ns.now() - lastSent.at >= 1 then sendUnknown(true); forceSend = false end
    end
    return
  end
  local now = ns.now()
  local me = Where.me()
  if not me then
    if lastSent and not lastSent.unknown then sendUnknown() end -- arrows to us go away now, not after a minute
    forceSend = false
    return
  end
  local last = lastSent
  if last and last.unknown then last = nil end
  if Logic.shouldSend(last, me, now, sendCfg(), forceSend) then
    ns.Comm.sendGroup("POS", Logic.posFields(me), { replace = "POS" })
    lastSent = { c = me.c, x = me.x, y = me.y, at = now }
    forceSend = false
  end
end

local function onPos(sender, fields)
  if not enabled then return end
  if not Where.isGroupMember(sender) then
    ns.Log.debug("position from %s ignored (not in our group)", tostring(sender))
    return
  end
  local p = Logic.readPos(fields)
  if p then p.at = ns.now() end
  positions[sender] = p
  private[sender] = (not p and fields.off == "1") or nil
end

-- Where a group member is: live from the game when it tells us, else their last POS (unless older than
-- FIND_STALE). nil = unknown.
function Find.positionOf(name)
  if type(name) ~= "string" or private[name] or not Where.isGroupMember(name) then return nil end
  local live = Where.unit(Where.unitFor(name))
  if live then
    live.at = ns.now()
    return live
  end
  local p = positions[name]
  if p and ns.now() - p.at > cfg().FIND_STALE then return nil end
  return p
end

local function zoneOf(name)
  local m = ns.roster and ns.roster:get(name)
  return m and m.zone or nil
end

-- The row arrow for a crew member: nil (hidden), { angle, text, compass } (same zone) or { still, zone } (another
-- zone on the same continent). Only for group members, only while "Arrows on the Crew panel" is on.
function Find.arrowFor(name, me, facing)
  if not enabled or not setting("rowArrows") then return nil end
  local them = Find.positionOf(name)
  if not them then return nil end
  me = me or Where.me()
  if not me then return nil end
  local target = { c = them.c, x = them.x, y = them.y, at = them.at, zone = zoneOf(name) }
  if facing == nil then facing = Where.facing() end
  return Logic.rowArrow(me, target, ns.now(), facing, { near = cfg().FIND_NEAR, staleAfter = cfg().FIND_STALE })
end

-- Who has a row arrow (and what kind): the panel redraws when this changes.
local function checkArrows()
  if not ns.roster then return end
  local me, facing = Where.me(), Where.facing()
  local parts = {}
  for _, name in ipairs(ns.roster:names(true)) do
    local a = me and Find.arrowFor(name, me, facing)
    if a then parts[#parts + 1] = name .. (a.still and ":s" or ":a") end
  end
  local key = table.concat(parts, ",")
  if key ~= arrowKey then
    arrowKey = key
    changed()
  end
end

------------------------------------------------------------------------------------------------------- meet-ups
local function meetFields(m)
  local f = Logic.posFields(m)
  f.id, f.p, f.a = m.id, m.place or "", m.audience
  f.l = tostring(math.max(1, math.floor(Logic.meetLeft(m, ns.now()))))
  return f
end

-- To its audience: the group for a party meet-up, everyone otherwise (or one friend: `to`).
local function sendMeet(m, to)
  local fields = meetFields(m)
  if m.audience == "party" then return ns.Comm.sendGroup("MEET", fields) end
  if to and ns.Comm.sendTo(to, "MEET", fields) then return true end
  ns.Comm.send("MEET", fields)
  return true
end

local function sendClear(m)
  local fields = { id = m.id, clr = "1", a = m.audience }
  if m.audience == "party" then ns.Comm.sendGroup("MEET", fields) else ns.Comm.send("MEET", fields) end
end

function Find.meet()
  if meet and Logic.meetLeft(meet, ns.now()) <= 0 then meet = nil end
  return meet
end

local function pointToMeet()
  if ns.BigArrow and ns.BigArrow.point then ns.Log.safe(FEATURE, ns.BigArrow.point, { kind = "meet" }) end
end
Find.pointToMeet = pointToMeet

local function closeMeetArrow()
  if ns.BigArrow and ns.BigArrow.closeIf then ns.Log.safe(FEATURE, ns.BigArrow.closeIf, "meet") end
end

-- A meet-up at a map point. audience = "party" | "all". Returns true, or false and why: "off", "noplace",
-- "nogroup".
function Find.placeMeet(mapID, mx, my, audience)
  if not enabled or not setting("meetups") then return false, "off" end
  if audience ~= "party" and audience ~= "all" then return false, "audience" end
  local c, x, y = Where.toWorld(mapID, mx, my)
  if c == nil then return false, "noplace" end
  if audience == "party" and not Where.inGroup() then return false, "nogroup" end
  seq = seq + 1
  meet = {
    id = ns.playerName() .. "-" .. tostring(math.floor(ns.wallclock())) .. "-" .. seq,
    by = ns.playerName(), c = c, x = x, y = y, place = Where.placeName(mapID, mx, my) or "", audience = audience,
    expires = ns.now() + cfg().MEET_LIFE, mine = true,
  }
  meetIds[meet.id] = true
  sendMeet(meet)
  changed()
  return true
end

-- Clears the meet-up for everyone it went to. Returns false when there is none.
function Find.clearMeet()
  local m = Find.meet()
  if not m then return false end
  sendClear(m)
  meet = nil
  closeMeetArrow()
  changed()
  return true
end

local function onMeet(sender, fields)
  if not enabled or not setting("meetups") then return end
  local audience = fields.a
  if audience ~= "party" and audience ~= "all" then return end
  if audience == "party" and not Where.isGroupMember(sender) then
    ns.Log.debug("party meet-up from %s ignored (not in our group)", tostring(sender))
    return
  end
  if type(fields.id) ~= "string" or fields.id == "" then return end
  if fields.clr == "1" then
    meetIds[fields.id] = true
    if meet and meet.id == fields.id then
      meet = nil
      closeMeetArrow()
      changed()
    end
    return
  end
  local p = Logic.readPos(fields)
  local left = tonumber(fields.l)
  if not p or not left or left ~= left or left <= 0 then return end
  left = math.min(left, cfg().MEET_LIFE)
  local now = ns.now()
  if meet and meet.id == fields.id then -- the same meet-up again (a resend): no second pop-up
    meet.expires = now + left
    return
  end
  -- one we had before (replaced by a newer one, cleared, or over): its sender may still send it to newcomers, but
  -- it never takes the newest one's place here
  if meetIds[fields.id] then return end
  meetIds[fields.id] = true
  meet = {
    id = fields.id, by = sender, c = p.c, x = p.x, y = p.y, place = ns.Util.safeText(fields.p or ""),
    audience = audience, expires = now + left,
  }
  changed()
  if setting("meetPopup") and ns.Popups and ns.Popups.meet then
    ns.Log.safe(FEATURE, ns.Popups.meet, sender, meet.place)
  end
  if setting("meetArrow") then pointToMeet() end
end

------------------------------------------------------------------------------------------------------- group
local function currentGroup()
  local out = {}
  if not Where.inGroup() then return out end
  local okRaid, raid = pcall(IsInRaid)
  raid = okRaid and not Where.isSecret(raid) and raid and true or false
  for i = 1, raid and 40 or 4 do
    local ok, n = pcall(UnitName, (raid and "raid" or "party") .. i)
    if ok and not Where.isSecret(n) and type(n) == "string" and n ~= "" then
      out[ns.shortName(n):lower()] = true
    end
  end
  return out
end

local function onGroupChanged()
  Where.forget()
  local now = currentGroup()
  local grew = false
  for name in pairs(now) do if not groupNames[name] then grew = true end end
  groupNames = now
  for name in pairs(positions) do
    if not Where.isGroupMember(name) then positions[name] = nil end
  end
  for name in pairs(private) do
    if not Where.isGroupMember(name) then private[name] = nil end
  end
  if grew then
    forceSend = true
    local m = Find.meet()
    if m and m.mine and m.audience == "party" then sendMeet(m) end -- reaches whoever joined while it lives
  end
  if not Where.inGroup() then lastSent = nil end
  checkArrows()
end

local function onOnline(name)
  local m = Find.meet()
  if not (m and m.mine and m.audience == "all") or not C_Timer then return end
  C_Timer.After(3, function()
    ns.Log.safe(FEATURE, function()
      local now = Find.meet()
      if now and now.id == m.id then sendMeet(now, name) end
    end)
  end)
end

-------------------------------------------------------------------------------------------------- running off
-- A group member who was right next to you and suddenly isn't: their arrow flashes red and a pop-up shows (no sound).
-- When we are the one who left, RAN_OFF fires instead (the stats count it for Wanderer).
local runTracks, runUntil, selfTracks = {}, {}, {}
local lastMe -- { c, x, y, at }: my position at the last look, to tell a teleport from a walk or a flight

function Find.isRunningOff(name)
  return type(name) == "string" and runUntil[name] ~= nil and ns.now() < runUntil[name]
end

-- For tests and the test tools: start the alarm for a name.
function Find.alarmForTest(name, dist) runUntil[name] = ns.now() + cfg().FIND_RUN_ALARM; ns.Bus.fire("RUNNING_OFF", name, dist) end

-- Each group member: the alarm when they ran off from us (setting "runaway"), and RAN_OFF when we ran off from
-- them (the same rule with the two positions swapped; the stats count it for Wanderer, alarm setting or not).
local function checkRunaways()
  if not ns.roster then return end
  local me = Where.me()
  local now = ns.now()
  local c = cfg()
  local before = lastMe
  lastMe = me and { c = me.c, x = me.x, y = me.y, at = now }
  if not me then return end
  -- a portal, summon, hearthstone or a ghost released to the graveyard: we moved faster than any mount
  local jumped = false
  if before then
    local moved = Logic.vector(before, me)
    jumped = moved == nil or moved > c.MAX_RUN_SPEED * (now - before.at)
  end
  local selfOff = jumped or Where.meDead() -- dead or teleported: we didn't run off from anyone
  local opts = { near = c.FIND_RUN_NEAR, far = c.FIND_RUN_FAR, window = c.FIND_RUN_WINDOW }
  local alarmOn = setting("runaway") ~= false
  for _, name in ipairs(ns.roster:names()) do
    local them = Find.positionOf(name)
    if them then
      if alarmOn then
        local track, alarm, dist = Logic.runaway(runTracks[name], me, them, ns.now(), opts)
        runTracks[name] = track
        if alarm then
          runUntil[name] = ns.now() + c.FIND_RUN_ALARM
          ns.Log.add("info", "find: %s is running off (%d yd)", name, math.floor(dist or 0))
          ns.Bus.fire("RUNNING_OFF", name, dist)
          -- no sound (owner, 2026-11-08): the flashing arrow and the pop-up are enough
          if ns.Popups and ns.Popups.runaway then ns.Popups.runaway(name, Logic.distanceText(dist or 0)) end
        end
      else
        runTracks[name] = nil
      end
      if selfOff then
        selfTracks[name] = nil
      else
        local mine, ran, dist = Logic.runaway(selfTracks[name], them, me, now, opts)
        selfTracks[name] = mine
        if ran then ns.Bus.fire("RAN_OFF", name, dist) end
      end
    else
      runTracks[name], selfTracks[name] = nil, nil
    end
  end
end

local function tick()
  if not enabled then return end
  sendPosition()
  ns.Log.safe(FEATURE, checkRunaways)
  if meet and Logic.meetLeft(meet, ns.now()) <= 0 then
    meet = nil
    closeMeetArrow()
    changed()
  end
  checkArrows()
end

------------------------------------------------------------------------------------------------------- report
local function minutes(seconds)
  local m = math.ceil(seconds / 60)
  return m <= 1 and "1 min" or (m .. " min")
end

function Find.reportLine()
  if not enabled then return "Find the crew: off" end
  local me = Where.me()
  local pos = me and ("ok (map " .. tostring(me.map or "?") .. ")") or "unknown"
  local facing = Where.facing() and "ok" or "unknown"
  local count = 0
  for name in pairs(positions) do if Find.positionOf(name) then count = count + 1 end end
  local m = Find.meet()
  local meetText = "none"
  if m then
    meetText = tostring(m.by) .. " (" .. (m.audience == "party" and "party" or "everyone") .. ")"
      .. (m.place ~= "" and (" in " .. m.place) or "") .. ", " .. minutes(Logic.meetLeft(m, ns.now())) .. " left"
  end
  return "Find the crew: position " .. pos .. ", facing " .. facing .. ", group members with positions: " .. count
    .. ", meet-up: " .. meetText .. (setting("sharePosition") and "" or ", not sharing my position")
end

------------------------------------------------------------------------------------------------------- tests
Find.forTest = {
  positions = function() return positions end,
  lastSent = function() return lastSent end,
  tick = function() tick() end,
}

ns.Comm.on("POS", function(sender, fields) ns.Log.safe(FEATURE, onPos, sender, fields) end)
ns.Comm.on("MEET", function(sender, fields) ns.Log.safe(FEATURE, onMeet, sender, fields) end)

local function onEnable()
  enabled = true
  groupNames = currentGroup()
  ns.Events.on(FEATURE, "GROUP_ROSTER_UPDATE", onGroupChanged)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() forceSend = true end)
  ns.Bus.on(FEATURE, "MEMBER_ONLINE", onOnline)
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(cfg().FIND_TICK, function() ns.Log.safe(FEATURE, tick) end)
  end
  if ns.MeetMap then ns.MeetMap.start() end
end

local function onDisable()
  enabled = false
  if ticker then ticker:Cancel(); ticker = nil end
  if lastSent and not lastSent.unknown and Where.inGroup() then sendUnknown() end
  positions, private, lastSent, meet, arrowKey = {}, {}, nil, nil, ""
  if ns.BigArrow and ns.BigArrow.close then ns.Log.safe(FEATURE, ns.BigArrow.close) end
  if ns.MeetMap then ns.Log.safe(FEATURE, ns.MeetMap.stop) end
  changed()
end

ns.Modules.register({
  id = FEATURE, name = "Find the crew", tier = "extra",
  info = "Arrows that point to the friends in your group, and meet-ups: Ctrl + right-click a spot on the world map "
    .. "to tell your party (or everyone) to meet there. Your position only goes to your group.",
  defaults = {
    rowArrows = true, meetups = true, sharePosition = true, meetPopup = true, meetArrow = true, meetMinimap = true,
    runaway = true,
    arrowScale = 1.0, arrowPos = { point = "TOP", x = 230, y = -150 },
  },
  settings = {
    { key = "rowArrows", label = "Arrows on the Crew panel", kind = "toggle",
      info = "A small arrow next to each friend in your group that points to them as you turn, with how far away "
        .. "they are. Click it for a big arrow that leads you there. Friends outside your group get no arrow." },
    { key = "runaway", label = "Warn me when someone runs off", kind = "toggle",
      info = "When a group member who was right next to you is suddenly far away (about 100 yards within 20 "
        .. "seconds, and they moved, not you), their arrow on the panel flashes red and grows, a pop-up says so (click "
        .. "it for the big arrow), and the big arrow flashes too if it points at them. No sound." },
    { key = "meetups", label = "Meet-ups", kind = "toggle",
      info = "Ctrl + right-click a spot on the world map to ask your party (or everyone) to meet there. They get a "
        .. "pop-up, an arrow and an icon on their map. Off: you can't send them and you don't get them." },
    { key = "sharePosition", label = "Share my position with my group", kind = "toggle",
      info = "Lets the friends in your group see an arrow to you. Your position never goes to anyone outside your "
        .. "group, and nothing is sent while you're not in a group." },
    { key = "meetPopup", label = "Meet-up pop-up", kind = "toggle", parent = "meetups",
      info = "Shows a small pop-up when a friend asks to meet up. Click it for the big arrow." },
    { key = "meetArrow", label = "Big arrow for a meet-up", kind = "toggle", parent = "meetups",
      info = "Turns on the big arrow toward the spot when a friend asks to meet up. It goes away when you get there." },
    { key = "meetMinimap", label = "Meet-up on the minimap", kind = "toggle", parent = "meetups",
      info = "Shows the meet-up spot on your minimap too (on its edge when it's farther away), not only on the world "
        .. "map." },
    { key = "arrowScale", label = "Big arrow size", kind = "slider", min = 0.5, max = 2.0, step = 0.1,
      fmt = ns.Widgets and ns.Widgets.percent or nil,
      info = "Makes the big arrow bigger or smaller. Drag the arrow to move it (unless the Crew panel is locked)." },
  },
  onEnable = onEnable,
  onDisable = onDisable,
  onSettingChanged = function(key, value)
    if key == "sharePosition" and enabled then
      if value == false and Where.inGroup() then sendUnknown(true) else lastSent = nil end
      if value ~= false then forceSend = true end
    elseif key == "rowArrows" then
      checkArrows()
    elseif key == "meetups" and value == false then
      meet = nil
      closeMeetArrow()
      changed()
    end
    if key == "arrowScale" and ns.BigArrow and ns.BigArrow.applyLook then ns.Log.safe(FEATURE, ns.BigArrow.applyLook) end
  end,
})
