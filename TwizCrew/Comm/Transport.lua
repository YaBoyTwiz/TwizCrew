-- Delivery: a hidden custom chat channel, with whisper / party / guild fallbacks.
-- The channel has three states: pending (not joined, not failed yet), joined, failed.
-- When the state leaves "pending" the Bus event TRANSPORT_READY fires, so Comm can send what it kept back.
local _, ns = ...

local Transport = {}
ns.Transport = Transport

local FEATURE = "comm"
local MODES = { auto = true, channel = true, whisper = true, group = true, guild = true }

local state = {
  started = false,
  channelName = nil,  -- the channel we are joining / joined
  index = 0,          -- chat channel number once joined
  joined = false,
  failed = false,
  failReason = nil,
  badSends = 0,       -- consecutive non-success results on channel sends
  lastResult = nil,
  generation = 0,     -- bumped by every (re)join, so old timers do nothing
  warnedPassword = false,
}

local function crew() return ns.db and ns.db.crew or {} end

local function mode()
  local m = ns.Modules.setting("comm", "transport")
  return MODES[m] and m or "auto"
end

local function usesChannel(m) return m == "auto" or m == "channel" end

function Transport.isPending()
  return usesChannel(mode()) and not state.joined and not state.failed
end

local function resolved()
  ns.Bus.fire("TRANSPORT_READY")
end

local function markFailed(reason)
  if state.failed then return end
  state.failed = true
  state.failReason = reason
  ns.Log.add("warn", "channel failed: %s", reason)
  resolved()
end

local function hideChannel()
  if type(ChatFrame_RemoveChannel) ~= "function" then return end
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local frame = _G["ChatFrame" .. i]
    if frame then ChatFrame_RemoveChannel(frame, state.channelName) end
  end
end

local function lookupIndex()
  local index = GetChannelName(state.channelName)
  return tonumber(index) or 0
end

local function markJoined(index)
  if state.joined or state.failed then return end
  state.joined = true
  state.index = index
  state.badSends = 0
  hideChannel()
  ns.Log.add("info", "channel %s joined as %d", tostring(state.channelName), index)
  resolved()
end

-- Joins now, then looks once a second until it worked or CHANNEL_JOIN_TIMEOUT has passed.
local function joinNow()
  local gen = state.generation
  state.channelName = crew().channel
  JoinChannelByName(state.channelName, crew().password)
  local waited = 0
  local function check()
    if gen ~= state.generation or state.joined or state.failed then return end
    local index = lookupIndex()
    if index > 0 then markJoined(index); return end
    if waited >= ns.Config.CHANNEL_JOIN_TIMEOUT then
      markFailed("the channel did not join in time")
      return
    end
    waited = waited + 1
    C_Timer.After(1, function() ns.Log.safe(FEATURE, check) end)
  end
  check()
end

local function onNotice(text, _, _, channelName, _, _, _, _, baseName)
  if not state.channelName then return end
  local ours = state.channelName:lower()
  local a, b = tostring(channelName or ""):lower(), tostring(baseName or ""):lower()
  if not (a:find(ours, 1, true) or b:find(ours, 1, true)) then return end
  if text == "WRONG_PASSWORD" then
    if not state.warnedPassword then
      state.warnedPassword = true
      print("TwizCrew: the crew code didn't work. Check it in /tc settings.")
    end
    markFailed("wrong crew code")
  elseif text == "YOU_JOINED" then
    if state.joined then hideChannel() else
      local index = lookupIndex()
      if index > 0 then markJoined(index) end
    end
  end
end

function Transport.start()
  if state.started then return end
  state.started = true
  ns.Events.on(FEATURE, "CHAT_MSG_CHANNEL_NOTICE", onNotice)
  local gen = state.generation
  C_Timer.After(ns.Config.CHANNEL_JOIN_DELAY, function()
    ns.Log.safe(FEATURE, function()
      if gen == state.generation then joinNow() end
    end)
  end)
end

-- The crew code changed: forget the old channel and join the new one now.
function Transport.rejoin()
  local old = state.channelName
  state.generation = state.generation + 1
  state.joined, state.failed, state.failReason = false, false, nil
  state.index, state.badSends, state.warnedPassword = 0, 0, false
  if old and old ~= crew().channel and type(LeaveChannelByName) == "function" then
    ns.Log.safe(FEATURE, LeaveChannelByName, old)
  end
  state.channelName = crew().channel
  if state.started then joinNow() end
end

-- Names we may whisper: roster names and the extra names from the settings, never ourselves.
local function whisperNames(skipGroup)
  local out, seen = {}, {}
  local me = ns.playerName()
  local function add(name)
    if type(name) ~= "string" or name == "" then return end
    name = Ambiguate(name, "none")
    if name == me or seen[name] then return end
    if skipGroup and UnitInParty(name) then return end
    seen[name] = true
    out[#out + 1] = { chatType = "WHISPER", target = name }
  end
  if ns.roster and ns.roster.names then
    local ok, names = ns.Log.safe(FEATURE, function() return ns.roster:names() end)
    if ok and type(names) == "table" then for _, n in ipairs(names) do add(n) end end
  end
  for _, n in ipairs(crew().extra or {}) do add(n) end
  return out
end

local function groupDestination()
  if IsInRaid() then return { chatType = "RAID" } end
  if IsInGroup() then return { chatType = "PARTY" } end
end

local function fallback()
  local out = {}
  local g = groupDestination()
  if g then out[1] = g end
  for _, w in ipairs(whisperNames(g ~= nil)) do out[#out + 1] = w end
  return out
end

function Transport.destinations()
  local m = mode()
  if m == "channel" then
    if state.joined and not state.failed then return { { chatType = "CHANNEL", target = state.index } } end
    return {}
  elseif m == "whisper" then
    return whisperNames(false)
  elseif m == "group" then
    local g = groupDestination()
    return g and { g } or {}
  elseif m == "guild" then
    if IsInGuild() then return { { chatType = "GUILD" } } end
  end
  if state.joined and not state.failed then return { { chatType = "CHANNEL", target = state.index } } end
  return fallback()
end

local function succeeded(result)
  return result == nil or result == true or result == 0
    or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success)
end

function Transport.send(text, dest)
  local ok, result = ns.Log.safe(FEATURE, C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, dest.chatType, dest.target)
  if not ok then return false end
  state.lastResult = result
  local good = succeeded(result)
  if dest.chatType == "CHANNEL" then
    if good then
      state.badSends = 0
    else
      state.badSends = state.badSends + 1
      if state.badSends >= ns.Config.CHANNEL_FAILS_BEFORE_FALLBACK then
        markFailed("sends to the channel were refused (result " .. tostring(result) .. ")")
      end
    end
  end
  return good
end

function Transport.status()
  return {
    mode = mode(), channel = state.channelName or crew().channel, channelIndex = state.index,
    joined = state.joined, failed = state.failed, failReason = state.failReason, lastResult = state.lastResult,
  }
end
