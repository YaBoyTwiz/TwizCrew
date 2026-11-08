-- Fake WoW API for tests. Stub.new() returns a fresh world W:
--   W.env      globals the addon sees (Lua whitelist + fake API); W.env._G == W.env
--   W.state    plain editable game state; fakes read it at call time
--   W:advance(s), W:fire(event, ...), W.sent, W.printed
-- Later tasks add fakes in the clearly marked section inside build().
local Stub = {}

local function permissive(W)
  local obj = { _events = {}, _scripts = {} }
  return setmetatable(obj, { __index = function(t, k)
    if k == "RegisterEvent" then
      return function(self, e) self._events[e] = true end
    elseif k == "UnregisterEvent" then
      return function(self, e) self._events[e] = nil end
    elseif k == "SetScript" then
      return function(self, name, fn) self._scripts[name] = fn end
    elseif k == "GetScript" then
      return function(self, name) return self._scripts[name] end
    elseif type(k) == "string" and k:sub(1, 6) == "Create" then
      return function() return permissive(W) end
    elseif type(k) == "string" and k:sub(1, 2) == "Is" then
      return function() return false end
    elseif type(k) == "string" and k:sub(1, 3) == "Get" then
      return function() return 0 end
    end
    return function() end
  end })
end

local function build(W)
  local env = {}
  env._G = env -- R4
  for _, name in ipairs({ "string", "table", "math", "pairs", "ipairs", "next", "type", "tostring", "tonumber",
    "select", "unpack", "error", "assert", "pcall", "xpcall", "setmetatable", "getmetatable", "rawget", "rawset",
    "rawequal" }) do
    env[name] = _G[name]
  end
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    W.printed[#W.printed + 1] = table.concat(parts, " ")
  end

  -- clock and timers
  env.GetTime = function() return W.clock end
  env.time = function() return math.floor(W.wall + W.clock) end
  env.date = function(fmt, t) return os.date(fmt, t or env.time()) end
  W.timers = {}
  local function addTimer(delay, fn, interval)
    local t = { due = W.clock + delay, fn = fn, interval = interval, cancelled = false }
    t.Cancel = function(self) self.cancelled = true end
    t.IsCancelled = function(self) return self.cancelled end
    W.timers[#W.timers + 1] = t
    return t
  end
  env.C_Timer = {
    After = function(delay, fn) addTimer(delay, fn) end,
    NewTicker = function(interval, fn) return addTimer(interval, fn, interval) end,
  }

  -- frames
  W.frames = {}
  env.CreateFrame = function()
    local f = permissive(W)
    W.frames[#W.frames + 1] = f
    return f
  end
  env.UIParent = permissive(W)
  env.GameTooltip = permissive(W)
  env.SlashCmdList = {}
  env.InCombatLockdown = function() return false end

  -- identity
  env.UnitName = function(unit)
    if unit == "player" then return W.state.player end
    return nil
  end
  env.GetRealmName = function() return W.state.realm end
  env.Ambiguate = function(name, _context)
    local suffix = "-" .. W.state.realm
    if name:sub(-#suffix) == suffix then return name:sub(1, #name - #suffix) end
    return name
  end
  env.C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "Version" then return W.state.tocVersion or W.state.version end
  end }
  env.GetBuildInfo = function() return "1.15.0", "00000", "Jan 1 2026", 16001 end

  -- >>> later tasks add their fakes below this line <<<

  -- chat transport (Task 6)
  W.state.channels = {}      -- channel name -> index, once joined
  W.state.groupMembers = {}  -- names counted as "in party"
  W.state.sendResult = 0
  -- Channel sends only: st.channelSendResult (nil = use sendResult) answers every CHANNEL send; st.channelReadyAfter
  -- = N makes CHANNEL sends answer 7 (InvalidChannel) for N seconds after the join that put us in the channel, like
  -- the game did on the owner's first login. Every W.sent entry keeps its result; the harness delivers only
  -- messages the game accepted.
  W.state.channelJoinedAt = {}
  W.removedChannels = {}     -- { frame, channel } for every ChatFrame_RemoveChannel call
  env.Enum = { SendAddonMessageResult = { Success = 0 } }
  local function sendResultFor(chatType, target)
    if chatType == "CHANNEL" then
      local name
      for n, i in pairs(W.state.channels) do if i == target then name = n end end
      local at = name and W.state.channelJoinedAt[name]
      if W.state.channelReadyAfter and at and W.clock - at < W.state.channelReadyAfter then return 7 end
      if W.state.channelSendResult ~= nil then return W.state.channelSendResult end
    end
    return W.state.sendResult or 0
  end
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) W.state.prefix = prefix; return true end,
    SendAddonMessage = function(prefix, text, chatType, target)
      local result = sendResultFor(chatType, target)
      W.sent[#W.sent + 1] = { prefix = prefix, text = text, chatType = chatType, target = target, result = result }
      return result
    end,
  }
  W.joins, W.leaves = {}, {}  -- { name, password } per JoinChannelByName call; names per LeaveChannelByName call
  env.JoinChannelByName = function(name, password)
    W.joins[#W.joins + 1] = { name = name, password = password }
    if not W.state.channelJoinFails then
      if not W.state.channels[name] then W.state.channelJoinedAt[name] = W.clock end
      W.state.channels[name] = 5
    end
  end
  env.LeaveChannelByName = function(name)
    W.leaves[#W.leaves + 1] = name
    W.state.channels[name] = nil
  end
  env.GetChannelName = function(name) return W.state.channels[name] or 0 end
  env.ChatFrame_RemoveChannel = function(frame, name)
    W.removedChannels[#W.removedChannels + 1] = { frame = frame, channel = name }
  end
  env.NUM_CHAT_WINDOWS = 10
  env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  W.messageFilters = {}      -- { event, fn } for every ChatFrame_AddMessageEventFilter call
  env.ChatFrame_AddMessageEventFilter = function(event, fn)
    W.messageFilters[#W.messageFilters + 1] = { event = event, fn = fn }
  end
  for i = 1, 10 do env["ChatFrame" .. i] = permissive(W) end
  env.IsInGroup = function() return W.state.inGroup or false end
  env.IsInRaid = function() return W.state.inRaid or false end
  env.IsInGuild = function() return W.state.inGuild or false end
  env.UnitInParty = function(name)
    for _, n in ipairs(W.state.groupMembers) do if n == name then return true end end
    return false
  end

  -- own state (Task 8)
  local st = W.state
  st.class, st.level, st.xp, st.xpMax = "WARRIOR", 10, 0, 100
  st.zone, st.subzone, st.inInstance, st.instanceType = "Elwynn Forest", "Goldshire", false, "none"
  st.combat, st.dead, st.taxi, st.afk = false, false, false, false
  env.UnitClass = function(_) return "Warrior", st.class end
  env.UnitLevel = function(_) return st.level end
  env.UnitXP = function(_) return st.xp end
  env.UnitXPMax = function(_) return st.xpMax end
  env.GetRealZoneText = function() return st.zone end
  env.GetSubZoneText = function() return st.subzone end
  env.IsInInstance = function() return st.inInstance, st.instanceType end
  env.UnitAffectingCombat = function() return st.combat end
  env.UnitIsDeadOrGhost = function() return st.dead end
  env.UnitOnTaxi = function() return st.taxi end
  env.UnitIsAFK = function() return st.afk end

  -- layer sensing (Task 10)
  st.guids, st.secret = {}, {}
  env.UnitGUID = function(unit) return st.guids[unit] end
  env.issecretvalue = function(v) return st.secret[v] == true end

  -- panel, widgets, class icons (Task 11)
  st.atlases = {}            -- atlas name -> info table, for atlases that "exist"
  env.C_Texture = { GetAtlasInfo = function(name) return st.atlases[name] end }
  env.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 } }
  env.RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
    MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" },
  }
  env.C_ClassColor = { GetClassColor = function(classFile)
    local c = env.RAID_CLASS_COLORS[classFile]
    if not c then return nil end
    return { r = c.r, g = c.g, b = c.b, GenerateHexColor = function() return c.colorStr end }
  end }
  env.UISpecialFrames = {}

  -- pop-ups (Task 12)
  W.invites, W.sounds = {}, {}   -- names passed to InviteUnit, sound ids passed to PlaySound
  env.C_PartyInfo = { InviteUnit = function(name) W.invites[#W.invites + 1] = name end }
  env.PlaySound = function(id) W.sounds[#W.sounds + 1] = id end
  env.SOUNDKIT = { RAID_WARNING = 8959 }

  -- Options → AddOns (Task 13). W.state.noSettingsAPI = true makes both functions disappear (read at call time).
  W.settingsCategories, W.addOnCategories = {}, {}
  local settingsAPI = {
    RegisterCanvasLayoutCategory = function(frame, name)
      local category = { frame = frame, name = name, ID = name }
      W.settingsCategories[#W.settingsCategories + 1] = category
      return category
    end,
    RegisterAddOnCategory = function(category) W.addOnCategories[#W.addOnCategories + 1] = category end,
  }
  env.Settings = setmetatable({}, { __index = function(_, k)
    if W.state.noSettingsAPI then return nil end
    return settingsAPI[k]
  end })

  -- stats board: detectors (stats Task 5).
  -- Missing APIs: these fakes live in `fakes` (and per-table fake lists) and reach the addon through an __index on
  -- env (and on C_QuestLog / C_Spell). A lookup returns nil while W.state.missing[name] is true, read at call time,
  -- so a test can set e.g. W.state.missing.GetUnitSpeed = true before firing ADDON_LOADED / PLAYER_LOGIN (the files
  -- are already loaded by then). Table functions use dotted names: "C_QuestLog.AbandonQuest", "C_Spell.GetSpellName".
  -- A function a test (or hooksecurefunc) stores on env or the table itself is a plain field and is never hidden.
  -- Other state: st.speed, st.mounted, st.swimming, st.falling, st.pos = { x, y, instance } (nil = no position),
  -- st.units[unit] = { name, level, hostile, player, dead }, st.repairCost (0 after RepairAllItems), st.spellNames[id].
  -- W.jumps, W.repairs, W.abandoned count calls of the game's own functions.
  st.missing, st.units, st.spellNames = {}, {}, {}
  st.speed, st.mounted, st.swimming, st.falling, st.repairCost = 0, false, false, false, 0
  W.jumps, W.repairs, W.abandoned = 0, {}, 0
  local function missing(name) return W.state.missing ~= nil and W.state.missing[name] == true end
  local function unit(u) return W.state.units and W.state.units[u] end
  local function hideable(prefix, list)
    return setmetatable({}, { __index = function(_, k)
      if missing(prefix .. k) then return nil end
      return list[k]
    end })
  end
  local fakes = {
    GetUnitSpeed = function(u)
      if u == "player" then return st.speed, 7, 7, 4.72 end
      return 0, 7, 7, 4.72
    end,
    IsMounted = function() return st.mounted and true or false end,
    IsSwimming = function() return st.swimming and true or false end,
    IsFalling = function() return st.falling and true or false end,
    UnitPosition = function(u)
      local p = st.pos
      if u ~= "player" then p = unit(u) and unit(u).pos end
      if type(p) ~= "table" then return nil end
      return p.y, p.x, 0, p.instance
    end,
    -- layer compare: st.units[u].visible / .connected (nil = true) / .ghost / .pos; st.ghost for the player
    UnitIsVisible = function(u)
      local x = unit(u)
      return (x and x.visible) and true or false
    end,
    UnitIsConnected = function(u)
      local x = unit(u)
      return (x and x.connected ~= false) and true or false
    end,
    UnitIsGhost = function(u)
      if u == "player" then return st.ghost and true or false end
      local x = unit(u)
      return (x and x.ghost) and true or false
    end,
    UnitExists = function(u) return u == "player" or unit(u) ~= nil end,
    UnitCanAttack = function(_, u)
      local x = unit(u)
      return (x and x.hostile) and true or false
    end,
    UnitIsDead = function(u)
      if u == "player" then return st.dead and true or false end
      local x = unit(u)
      return (x and x.dead) and true or false
    end,
    UnitIsPlayer = function(u)
      local x = unit(u)
      return u == "player" or ((x and x.player) and true or false)
    end,
    hooksecurefunc = function(tbl, name, fn)
      if type(tbl) == "string" then tbl, name, fn = env, tbl, name end
      local original = tbl[name]
      rawset(tbl, name, function(...)
        local results = { original(...) }
        fn(...)
        return unpack(results, 1, table.maxn(results))
      end)
    end,
    JumpOrAscendStart = function() W.jumps = W.jumps + 1 end,
    RepairAllItems = function(guild)
      W.repairs[#W.repairs + 1] = guild or false
      st.repairCost = 0
    end,
    GetRepairAllCost = function() return st.repairCost, st.repairCost > 0 end,
    AbandonQuest = function() W.abandoned = W.abandoned + 1 end,
    C_QuestLog = hideable("C_QuestLog.", { AbandonQuest = function() W.abandoned = W.abandoned + 1 end }),
    C_Spell = hideable("C_Spell.", { GetSpellName = function(id) return st.spellNames[id] end }),
    LOOT_ITEM_SELF = "You receive loot: %s.",
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
    DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel",
    DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel",
  }
  -- the tables are made once, so a test's rawset on them stays
  setmetatable(env, { __index = function(_, k)
    if missing(k) then return nil end
    return fakes[k]
  end })
  -- other units for UnitName / UnitLevel (the player's answers are unchanged)
  local v1UnitName, v1UnitLevel = env.UnitName, env.UnitLevel
  env.UnitName = function(u)
    local x = u ~= "player" and unit(u)
    if x then return x.name end
    return v1UnitName(u)
  end
  env.UnitLevel = function(u)
    local x = u ~= "player" and unit(u)
    if x then return x.level end
    return v1UnitLevel(u)
  end

  -- final review fixes: other units' combat (st.units[u].combat), mirror timers, money.
  -- st.mirror = { { name = "BREATH", paused = 0 }, ... } (slots 1..3; a missing slot is "UNKNOWN");
  -- st.money in copper (default plenty). GetMirrorTimerInfo and GetMoney are hideable through st.missing.
  st.mirror, st.money = {}, 100000000
  fakes.GetMirrorTimerInfo = function(i)
    local m = type(st.mirror) == "table" and st.mirror[i]
    if type(m) ~= "table" then return "UNKNOWN", 0, 0, 0, 0, "" end
    return m.name, 30000, 60000, -1, m.paused or 0, "Breath"
  end
  fakes.GetMoney = function() return st.money end

  -- minimap button: the Minimap frame, the cursor and the minimap shape, all hideable through st.missing
  -- ("Minimap", "GetCursorPosition", "GetMinimapShape"). st.minimap = size, centre and effective scale of the
  -- minimap; st.cursor = { x, y } in screen pixels; st.minimapShape = what GetMinimapShape answers (nil = "ROUND").
  st.minimap = { width = 140, height = 140, x = 500, y = 400, scale = 1 }
  st.cursor = { x = 0, y = 0 }
  local minimap = permissive(W)
  rawset(minimap, "GetWidth", function() return st.minimap.width end)
  rawset(minimap, "GetHeight", function() return st.minimap.height end)
  rawset(minimap, "GetCenter", function() return st.minimap.x, st.minimap.y end)
  rawset(minimap, "GetEffectiveScale", function() return st.minimap.scale end)
  fakes.Minimap = minimap
  fakes.GetCursorPosition = function() return st.cursor.x, st.cursor.y end
  fakes.GetMinimapShape = function() return st.minimapShape or "ROUND" end
  -- level progress: rested XP (st.rested, nil = none, like the game) and the max level (st.maxLevel), both
  -- hideable through st.missing ("GetXPExhaustion", "GetMaxPlayerLevel"). Level-up sounds land in W.sounds.
  -- find the crew: maps and positions, all hideable through st.missing ("C_Map.GetPlayerMapPosition",
  -- "GetPlayerFacing", ...). st.maps[id] = { c = continent, x0, y0 = world yards at map (0, 0), x1, y1 = at (1, 1),
  -- name } (a straight line between them; map x runs along world y, map y along world x, as in the game).
  -- st.map = { id, x, y } = the player on a map (nil = no position); st.facing (radians); st.indoors; st.cvars;
  -- st.ctrl (Ctrl held). WorldMapFrame: st.worldMap = { shown, mapID }, its click handlers in W.mapClickHandlers.
  st.maps = {
    [1429] = { c = 0, x0 = -8000, y0 = 0, x1 = -10000, y1 = -2000, name = "Elwynn Forest" },
    [1436] = { c = 0, x0 = -10000, y0 = 0, x1 = -12000, y1 = -2000, name = "Westfall" },
    [1438] = { c = 1, x0 = 11000, y0 = 2000, x1 = 9000, y1 = 0, name = "Teldrassil" },
    [947] = { name = "Azeroth" }, -- the whole world: no world coordinates
  }
  st.map = { id = 1429, x = 0.5, y = 0.5 }
  st.facing, st.indoors, st.cvars, st.ctrl = 0, false, {}, false
  st.worldMap = { shown = false, mapID = 1429 }
  local function vec(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
  end
  fakes.CreateVector2D = vec
  fakes.C_Map = hideable("C_Map.", {
    GetBestMapForUnit = function(u)
      if u ~= "player" or type(st.map) ~= "table" then return nil end
      return st.map.id
    end,
    GetPlayerMapPosition = function(mapID, u)
      if u ~= "player" or type(st.map) ~= "table" or st.map.id ~= mapID then return nil end
      return vec(st.map.x, st.map.y)
    end,
    GetWorldPosFromMapPos = function(mapID, pos)
      local m = st.maps[mapID]
      if not m or m.c == nil or type(pos) ~= "table" then return nil end
      local mx, my = pos.x, pos.y
      return m.c, vec(m.x0 + (m.x1 - m.x0) * my, m.y0 + (m.y1 - m.y0) * mx)
    end,
    GetMapPosFromWorldPos = function(c, pos, mapID)
      local m = st.maps[mapID]
      if not m or m.c ~= c or type(pos) ~= "table" then return nil end
      return mapID, vec((pos.y - m.y0) / (m.y1 - m.y0), (pos.x - m.x0) / (m.x1 - m.x0))
    end,
    GetMapInfo = function(mapID)
      local m = st.maps[mapID]
      return m and { mapID = mapID, name = m.name } or nil
    end,
  })
  fakes.GetPlayerFacing = function() return st.facing end
  fakes.IsIndoors = function() return st.indoors and true or false end
  fakes.GetCVar = function(name) return st.cvars[name] end
  fakes.IsControlKeyDown = function() return st.ctrl and true or false end
  W.mapClickHandlers = {}
  local worldMap = permissive(W)
  local canvas = permissive(W)
  rawset(canvas, "GetWidth", function() return 1000 end)
  rawset(canvas, "GetHeight", function() return 667 end)
  rawset(worldMap, "IsShown", function() return st.worldMap.shown and true or false end)
  rawset(worldMap, "IsVisible", function() return st.worldMap.shown and true or false end)
  rawset(worldMap, "GetMapID", function() return st.worldMap.mapID end)
  rawset(worldMap, "GetCanvas", function() return canvas end)
  rawset(worldMap, "GetCanvasScale", function() return 1 end)
  rawset(worldMap, "AddCanvasClickHandler", function(_, fn, priority)
    W.mapClickHandlers[#W.mapClickHandlers + 1] = { fn = fn, priority = priority }
  end)
  rawset(worldMap, "HookScript", function(self, name, fn) self._scripts["hook:" .. name] = fn end)
  fakes.WorldMapFrame = worldMap
  -- A click on the world map at (x, y) on the shown map, through the handlers (highest priority first, like the
  -- game). Returns whether a handler took it.
  function W:clickMap(button, x, y)
    table.sort(self.mapClickHandlers, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
    for _, h in ipairs(self.mapClickHandlers) do
      if h.fn(worldMap, button, x, y) then return true end
    end
    return false
  end
  st.maxLevel = 60
  fakes.GetXPExhaustion = function() return st.rested end
  fakes.GetMaxPlayerLevel = function() return st.maxLevel end
  local v1UnitAffectingCombat = env.UnitAffectingCombat
  env.UnitAffectingCombat = function(u)
    local x = u ~= "player" and unit(u)
    if x then return x.combat and true or false end
    return v1UnitAffectingCombat(u)
  end

  return env
end

function Stub.new()
  math.randomseed(12345)
  local W = { clock = 1000, wall = 1700000000 - 1000, printed = {}, sent = {},
    state = { player = "Twiz", realm = "Realm", version = "0.1.0" } }
  W.env = build(W)

  function W:advance(seconds)
    local target = self.clock + seconds
    while true do
      local best
      for _, t in ipairs(self.timers) do
        if not t.cancelled and t.due <= target and (not best or t.due < best.due) then best = t end
      end
      if not best then break end
      self.clock = best.due
      if best.interval then best.due = best.due + best.interval else best.cancelled = true end
      best.fn(best)
    end
    self.clock = target
    local live = {}
    for _, t in ipairs(self.timers) do if not t.cancelled then live[#live + 1] = t end end
    self.timers = live
  end

  function W:fire(event, ...)
    for _, f in ipairs(self.frames) do
      if f._events[event] then
        local h = f._scripts.OnEvent
        if h then h(f, event, ...) end
      end
    end
  end

  return W
end

return Stub
