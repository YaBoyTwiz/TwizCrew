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
    if field == "Version" then return W.state.version end
  end }
  env.GetBuildInfo = function() return "1.15.0", "00000", "Jan 1 2026", 16001 end

  -- >>> later tasks add their fakes below this line <<<

  -- chat transport (Task 6)
  W.state.channels = {}      -- channel name -> index, once joined
  W.state.groupMembers = {}  -- names counted as "in party"
  W.state.sendResult = 0
  W.removedChannels = {}     -- { frame, channel } for every ChatFrame_RemoveChannel call
  env.Enum = { SendAddonMessageResult = { Success = 0 } }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) W.state.prefix = prefix; return true end,
    SendAddonMessage = function(prefix, text, chatType, target)
      W.sent[#W.sent + 1] = { prefix = prefix, text = text, chatType = chatType, target = target }
      return W.state.sendResult or 0
    end,
  }
  W.joins, W.leaves = {}, {}  -- { name, password } per JoinChannelByName call; names per LeaveChannelByName call
  env.JoinChannelByName = function(name, password)
    W.joins[#W.joins + 1] = { name = name, password = password }
    if not W.state.channelJoinFails then W.state.channels[name] = 5 end
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
  -- st.units[unit] = { name, level, hostile, player }, st.repairCost (0 after RepairAllItems), st.spellNames[id].
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
      if u ~= "player" or type(st.pos) ~= "table" then return nil end
      return st.pos.y, st.pos.x, 0, st.pos.instance
    end,
    UnitExists = function(u) return u == "player" or unit(u) ~= nil end,
    UnitCanAttack = function(_, u)
      local x = unit(u)
      return (x and x.hostile) and true or false
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
