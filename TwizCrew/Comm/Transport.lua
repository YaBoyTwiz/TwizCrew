-- Delivery: a hidden custom chat channel, with whisper / party / guild fallbacks.
-- The channel has three states: pending (not joined, not failed yet), joined, failed.
-- When the state leaves "pending" the Bus event TRANSPORT_READY fires, so Comm can send what it kept back.
local _, ns = ...

local Transport = {}
ns.Transport = Transport

local FEATURE = "comm"
local MODES = { auto = true, channel = true, whisper = true, group = true, guild = true }
local REJOIN_DELAY = 2      -- seconds between leaving the channel and joining it again
local AUTO_REJOIN_GAP = 10  -- a rejoin because the channel was lost happens at most this often
local OWN_LEAVE_GRACE = 5   -- a "you left" notice this soon after we left on purpose is about that leave
local CHANNEL_EVENTS = { "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL",
  "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }

local state = {
  started = false,
  channelName = nil,  -- the channel we are joining / joined
  index = 0,          -- chat channel number once joined
  joined = false,
  failed = false,
  failReason = nil,
  badSends = 0,       -- consecutive non-success results on channel sends (throttling does not count)
  lastResult = nil,
  generation = 0,     -- bumped by every (re)join, so old timers do nothing
  warnedPassword = false,
  leftAt = nil,       -- when we last left the channel on purpose
  nextAutoJoin = nil, -- when the last rejoin after losing the channel was (or will be) started
  hideFailed = false, -- no way to take the channel out of the chat windows in this game version
}
local ourNames = {}   -- lower-case names of every channel we joined this session (their chat lines are hidden)

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

-- "5. TwizCrewHQ" / base name "TwizCrewHQ" -> "twizcrewhq" (nil if neither is a usable string).
local function baseNameOf(channelName, baseName)
  local name
  if type(baseName) == "string" and baseName ~= "" then
    name = baseName
  elseif type(channelName) == "string" then
    name = channelName:gsub("^%d+%.%s*", "")
  end
  if not name or name == "" then return nil end
  return name:lower()
end

local function isCurrentChannel(channelName, baseName)
  local name = baseNameOf(channelName, baseName)
  return name ~= nil and type(state.channelName) == "string" and name == state.channelName:lower()
end

-- Chat filter: hides every line of our hidden channel (joined/left notices, anything typed in it), matched on the
-- exact channel name (any case): the crew channel now, and any crew channel joined earlier this session.
local function hideChannelLine(_, _, _, _, _, channelName, _, _, _, _, baseName)
  local ok, hide = pcall(function()
    local name = baseNameOf(channelName, baseName)
    if name == nil then return false end
    local current = crew().channel
    return ourNames[name] == true or (type(current) == "string" and name == current:lower())
  end)
  return ok and hide == true
end

local function removeFromWindow(frame, name)
  if type(ChatFrame_RemoveChannel) == "function" then
    ChatFrame_RemoveChannel(frame, name)
  elseif type(ChatFrameUtil) == "table" and type(ChatFrameUtil.RemoveChannel) == "function" then
    ChatFrameUtil.RemoveChannel(frame, name)
  elseif type(frame) == "table" and type(frame.RemoveChannel) == "function" then
    frame:RemoveChannel(name)
  else
    return false
  end
  return true
end

local function hideChannel()
  local removed = false
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local frame = _G["ChatFrame" .. i]
    if frame then
      local ok, done = pcall(removeFromWindow, frame, state.channelName)
      if ok and done then removed = true end
    end
  end
  if not removed and not state.hideFailed then
    state.hideFailed = true
    ns.Log.add("warn", "could not take the channel %s out of the chat windows (no way to do it in this game version)",
      tostring(state.channelName))
  end
end

local function lookupIndex()
  if type(GetChannelName) ~= "function" or not state.channelName then return 0 end
  local ok, index = pcall(GetChannelName, state.channelName)
  return ok and tonumber(index) or 0
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
  if type(state.channelName) == "string" then ourNames[state.channelName:lower()] = true end
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

-- Forgets the current connection (old timers stop); sends wait until the next join resolves.
local function resetConnection()
  state.generation = state.generation + 1
  state.joined, state.failed, state.failReason = false, false, nil
  state.index, state.badSends = 0, 0
end

local function joinLater(delay)
  local gen = state.generation
  C_Timer.After(delay, function()
    ns.Log.safe(FEATURE, function()
      if gen == state.generation then joinNow() end
    end)
  end)
end

-- The channel went away under us (we were kicked, the game left it, its number is gone): join it again,
-- at most once every AUTO_REJOIN_GAP seconds.
local function lostChannel(why)
  if not state.joined then return end
  ns.Log.add("warn", "channel %s lost (%s), joining it again", tostring(state.channelName), why)
  resetConnection()
  local now = ns.now()
  local delay = REJOIN_DELAY
  if state.nextAutoJoin then delay = math.max(delay, state.nextAutoJoin + AUTO_REJOIN_GAP - now) end
  state.nextAutoJoin = now + delay
  if state.started then joinLater(delay) end
end

-- Our channel joined while we use it: make sure its number is still ours (it can change or vanish).
local function checkChannel()
  if not state.joined or state.failed then return end
  local index = lookupIndex()
  if index <= 0 then
    lostChannel("its channel number is gone")
  elseif index ~= state.index then
    ns.Log.add("info", "channel %s is now number %d (was %d)", tostring(state.channelName), index, state.index)
    state.index = index
  end
end

local function onNotice(text, _, _, channelName, _, _, _, _, baseName)
  if not isCurrentChannel(channelName, baseName) then return end
  if text == "WRONG_PASSWORD" then
    if not state.warnedPassword then
      state.warnedPassword = true
      print("TwizCrew: the crew code didn't work. Check it in /tc settings.")
    end
    markFailed("wrong crew code")
  elseif text == "YOU_JOINED" then
    hideChannel() -- always, even when the join came after we gave up waiting
    if not state.joined then
      local index = lookupIndex()
      if index > 0 then markJoined(index) end
    end
  elseif text == "YOU_LEFT" then
    if state.leftAt and ns.now() - state.leftAt <= OWN_LEAVE_GRACE then return end -- we left on purpose
    lostChannel("the game says we left it")
  end
end

-- Names we whispered recently; the game's "No player named X is currently playing." line for them is hidden.
local WHISPER_MEMORY = 10 -- seconds
local whispered = {}      -- name -> time of the last whisper

local function hideNotFoundLine(_, _, message)
  local ok, hide = pcall(function()
    if type(message) ~= "string" then return false end
    local now = ns.now()
    local pattern = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
    for name, at in pairs(whispered) do
      if now - at > WHISPER_MEMORY then
        whispered[name] = nil
      elseif message == string.format(pattern, name) then
        return true
      end
    end
    return false
  end)
  return ok and hide == true
end

function Transport.start()
  if state.started then return end
  state.started = true
  if type(ChatFrame_AddMessageEventFilter) == "function" then
    ns.Log.safe(FEATURE, ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", hideNotFoundLine)
    for _, event in ipairs(CHANNEL_EVENTS) do
      ns.Log.safe(FEATURE, ChatFrame_AddMessageEventFilter, event, hideChannelLine)
    end
  end
  ns.Events.on(FEATURE, "CHAT_MSG_CHANNEL_NOTICE", onNotice)
  joinLater(ns.Config.CHANNEL_JOIN_DELAY)
end

-- The channel name or crew code changed: leave our channel, then join (the new) one after a short delay.
-- Leaving first matters even when only the code changed: a code only applies when the channel is created again.
function Transport.rejoin()
  local old = state.channelName
  resetConnection()
  state.warnedPassword = false
  if old and type(LeaveChannelByName) == "function" then
    state.leftAt = ns.now()
    ns.Log.safe(FEATURE, LeaveChannelByName, old)
  end
  state.channelName = crew().channel
  if state.started then joinLater(REJOIN_DELAY) end
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
  if usesChannel(m) then checkChannel() end
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

-- "Too many messages right now": the message was not sent but may be tried again later.
local function throttled(result)
  local codes = Enum and Enum.SendAddonMessageResult
  local addon = codes and codes.AddonMessageThrottle or 3
  local channel = codes and codes.ChannelThrottle or 8
  return result == addon or result == channel
end

-- Returns sent (true/false) and retryLater (true when the game asked us to slow down; the message should be kept).
function Transport.send(text, dest)
  local target = dest.target
  if dest.chatType == "CHANNEL" then
    if state.failed then return false, false end         -- the fallback took over; this copy is not needed
    if not state.joined then return false, true end      -- (re)joining: wait for it
    target = state.index                                 -- the number may have changed since this was queued
  end
  local ok, result = ns.Log.safe(FEATURE, C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, dest.chatType, target)
  if not ok then return false, false end
  state.lastResult = result
  if dest.chatType == "WHISPER" and dest.target then whispered[dest.target] = ns.now() end
  local good = succeeded(result)
  if not good and throttled(result) then return false, true end
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
  return good, false
end

function Transport.status()
  return {
    mode = mode(), channel = state.channelName or crew().channel, channelIndex = state.index,
    joined = state.joined, failed = state.failed, failReason = state.failReason, lastResult = state.lastResult,
    hideFailed = state.hideFailed,
  }
end
