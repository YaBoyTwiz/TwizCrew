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
  env.JoinChannelByName = function(name, _password)
    if not W.state.channelJoinFails then W.state.channels[name] = 5 end
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
