-- Delivery: a hidden custom chat channel, with whisper / party / guild fallbacks.
-- The channel has three states: pending (not joined, not failed yet), joined, failed.
-- When the state leaves "pending" the Bus event TRANSPORT_READY fires, so Comm can send what it kept back.
-- Right after a (re)join the game may refuse channel sends for a moment: refusals in the first
-- CHANNEL_JOIN_GRACE seconds are kept and tried again, like throttled ones. A failure because sends were refused
-- never lasts the session: the channel is tried again after CHANNEL_RETRY_FIRST seconds (doubling up to
-- CHANNEL_RETRY_MAX) while the fallback carries the messages; when it is back, CHANNEL_BACK fires (Crew says HELLO).
-- WoW Forever takes addon messages sent to a custom channel but never delivers them (seen in game and reported by
-- other addon makers, November 2026). So the channel is mainly used to see who is in it: its member list
-- (ListChannelByName, every CHANNEL_LIST_INTERVAL seconds) and join / leave notices. Automatic mode whispers each
-- member, sends to the group when grouped, and still sends one copy to the channel in case the game starts
-- delivering it again. Right after joining, sends wait (up to CHANNEL_LIST_WAIT seconds) for the first member list.
local _, ns = ...

local Transport = {}
ns.Transport = Transport

local FEATURE = "comm"
local MODES = { auto = true, channel = true, whisper = true, group = true, guild = true }
local REJOIN_DELAY = 2      -- seconds between leaving the channel and joining it again
local AUTO_REJOIN_GAP = 10  -- a rejoin because the channel was lost happens at most this often
local OWN_LEAVE_GRACE = 5   -- a "you left" notice this soon after we left on purpose is about that leave
local CHANNEL_EVENTS = { "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL",
  "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_CHANNEL_LIST" }

local state = {
  started = false,
  channelName = nil,  -- the channel we are joining / joined
  index = 0,          -- chat channel number once joined
  joined = false,
  failed = false,
  failReason = nil,
  failedAt = nil,     -- when the channel went down (for /tc report)
  badSends = 0,       -- consecutive non-success results on channel sends (throttling does not count)
  lastResult = nil,
  generation = 0,     -- bumped by every (re)join, so old timers do nothing
  warnedPassword = false,
  leftAt = nil,       -- when we last left the channel on purpose
  nextAutoJoin = nil, -- when the last rejoin after losing the channel was (or will be) started
  hideFailed = false, -- no way to take the channel out of the chat windows in this game version
  joinedAt = nil,     -- when the channel last joined (refusals soon after are not counted)
  graceNoted = false, -- the "refused right after joining" line was logged for this join
  retries = 0,        -- tries since the channel last failed because sends were refused (0 = not retrying)
  nextRetryAt = nil,  -- when the next try is due (nil = no try planned)
  listed = false,     -- the first member list since the last join arrived (or we stopped waiting for it)
  listGen = 0,        -- bumped by every join, so an old member-list timer stops
  listsHeard = 0,     -- member lists heard this session (for /tc report)
}
-- Crew copies we can whisper: lower-case short name -> { name = the name as the game gave it, seenAt = time }.
-- On Forever that name is "First Last", which is what a whisper needs.
local members = {}
local ourNames = {}   -- lower-case names of every channel we joined this session (their chat lines are hidden)

local function crew() return ns.db and ns.db.crew or {} end

local function mode()
  local m = ns.Modules.setting("comm", "transport")
  return MODES[m] and m or "auto"
end

local function usesChannel(m) return m == "auto" or m == "channel" end

function Transport.isPending()
  local m = mode()
  if not usesChannel(m) then return false end
  if not state.joined and not state.failed then return true end
  return m == "auto" and state.joined and not state.failed and not state.listed
end

local function resolved()
  ns.Bus.fire("TRANSPORT_READY")
end

local tryAgain -- defined below

-- Plans the next try at the channel (60 s, 120 s, 240 s, then every 300 s with the default settings).
local function scheduleRetry()
  local c = ns.Config
  local delay = math.min(c.CHANNEL_RETRY_MAX, c.CHANNEL_RETRY_FIRST * 2 ^ state.retries)
  state.retries = state.retries + 1
  state.nextRetryAt = ns.now() + delay
  local gen = state.generation
  C_Timer.After(delay, function()
    ns.Log.safe(FEATURE, function()
      if gen == state.generation and state.failed and state.nextRetryAt then tryAgain() end
    end)
  end)
  return delay
end

-- Logs the first few tries, then only every sixth, so a channel that never works does not flood the log.
local function retryWorthLogging()
  return state.retries <= 3 or state.retries % 6 == 0
end

-- retry: the failure may pass (sends were refused), so the channel is tried again later.
local function markFailed(reason, retry)
  if state.failed then
    if not retry and state.retries > 0 then -- e.g. a wrong crew code while we were retrying: stop retrying
      state.generation = state.generation + 1
      state.nextRetryAt, state.retries = nil, 0
      state.failReason = reason
      ns.Log.add("warn", "channel failed: %s (no more tries)", reason)
    end
    return
  end
  state.failed = true
  state.failReason = reason
  -- still trying again after refusals (the channel never worked in between): it has been down since the first
  if state.retries == 0 or not state.failedAt then state.failedAt = ns.now() end
  if retry then
    local logIt = retryWorthLogging() -- same answer as for the try that just failed (none yet: logged)
    local delay = scheduleRetry()
    if logIt then
      ns.Log.add("warn", "channel failed: %s; using the fallback, trying the channel again in %d s", reason, delay)
    end
  else
    state.retries, state.nextRetryAt = 0, nil
    ns.Log.add("warn", "channel failed: %s", reason)
  end
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

-- A name from the game's member list or a notice: colours, links and the owner / moderator marks taken off.
local function cleanName(s)
  if type(s) ~= "string" or ns.Util.isSecret(s) then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
  s = s:gsub("^[%s%*@%+]+", ""):gsub("%s+$", "")
  if s == "" or s:find("[%[%]|,]") then return nil end
  return s
end

-- "[*Frostie Snow, @Ginkan Pebble, Twiz]" (the text of CHAT_MSG_CHANNEL_LIST) -> { "Frostie Snow", ... }
function Transport.parseList(text)
  local out = {}
  if type(text) ~= "string" or ns.Util.isSecret(text) then return out end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
  for piece in (text .. ","):gmatch("(.-),") do
    local name = cleanName((piece:gsub("^%s*%[", ""):gsub("%]%s*$", "")))
    if name then out[#out + 1] = name end
  end
  return out
end

local function memberKey(name)
  local short = ns.shortName(name)
  if type(short) ~= "string" or short == "" or ns.isMe(short) then return nil end
  return short:lower(), short
end

-- found: true when this is someone we did not know (logged; CREW_FOUND fires once the first list is in).
local function addMember(raw)
  local name = cleanName(raw)
  if not name then return end
  local key, short = memberKey(name)
  if not key then return end
  local m = members[key]
  if m then
    if #name > #m.name then m.name = name end -- "First Last" beats "First"
    m.seenAt = ns.now()
    return
  end
  members[key] = { name = name, seenAt = ns.now() }
  ns.Log.add("info", "crew channel: %s is here", ns.Util.safeText(name))
  if state.listed then ns.Bus.fire("CREW_FOUND", short) end
end

local function removeMember(raw, why)
  local name = cleanName(raw)
  local key = name and memberKey(name)
  if not key or not members[key] then return end
  members[key] = nil
  ns.Log.add("info", "crew channel: %s left (%s)", ns.Util.safeText(name), why)
end

local function memberKeys()
  local keys = {}
  for key in pairs(members) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

-- Members missing from three lists in a row are forgotten (they left without a notice).
local function pruneMembers()
  local limit = ns.Config.CHANNEL_LIST_INTERVAL * 3 + 10
  local now = ns.now()
  for _, key in ipairs(memberKeys()) do
    local m = members[key]
    if now - m.seenAt > limit then removeMember(m.name, "not in the member list any more") end
  end
end

local function markListed()
  if state.listed then return end
  state.listed = true
  resolved()
end

local function requestList()
  if type(ListChannelByName) ~= "function" or not state.channelName then return false end
  return (pcall(ListChannelByName, state.channelName))
end

-- After a join: ask for the member list now and every CHANNEL_LIST_INTERVAL seconds while joined. Sends wait for the
-- first list, at most CHANNEL_LIST_WAIT seconds.
local function startListing()
  state.listGen = state.listGen + 1
  state.listed = false
  local gen = state.listGen
  local c = ns.Config
  local function tick()
    if gen ~= state.listGen or not state.joined then return end
    pruneMembers()
    requestList()
    C_Timer.After(c.CHANNEL_LIST_INTERVAL, function() ns.Log.safe(FEATURE, tick) end)
  end
  if type(ListChannelByName) ~= "function" then
    if not state.noListNoted then
      state.noListNoted = true
      ns.Log.add("warn", "this game version cannot list channel members; whispering known names only")
    end
    markListed()
    return
  end
  tick()
  C_Timer.After(c.CHANNEL_LIST_WAIT, function()
    ns.Log.safe(FEATURE, function()
      if gen ~= state.listGen or state.listed then return end
      if not state.noListNoted then
        state.noListNoted = true
        ns.Log.add("info", "no member list from channel %s yet; sending to who we know", tostring(state.channelName))
      end
      markListed()
    end)
  end)
end

-- quiet: log nothing about this join (not even a refusal right after it); the caller logs what it wants.
local function markJoined(index, quiet)
  if state.joined or state.failed then return end
  state.joined = true
  state.index = index
  state.badSends = 0
  state.joinedAt = ns.now()
  state.graceNoted = quiet and true or false
  hideChannel()
  if not quiet then ns.Log.add("info", "channel %s joined as %d", tostring(state.channelName), index) end
  startListing()
  resolved()
end

-- Looks for the channel number now and then once a second, until it is there or CHANNEL_JOIN_TIMEOUT has passed.
-- waiting() says whether we still want it (checked before every look).
local function watchJoin(waiting, onJoined, onTimeout)
  local gen = state.generation
  local waited = 0
  local function check()
    if gen ~= state.generation or not waiting() then return end
    local index = lookupIndex()
    if index > 0 then onJoined(index); return end
    if waited >= ns.Config.CHANNEL_JOIN_TIMEOUT then onTimeout(); return end
    waited = waited + 1
    C_Timer.After(1, function() ns.Log.safe(FEATURE, check) end)
  end
  check()
end

local function startJoin()
  state.channelName = crew().channel
  if type(state.channelName) == "string" then ourNames[state.channelName:lower()] = true end
  JoinChannelByName(state.channelName, crew().password)
end

-- Joins now, then waits for the channel number (sends are kept meanwhile).
local function joinNow()
  startJoin()
  watchJoin(function() return not state.joined and not state.failed end, markJoined,
    function() markFailed("the channel did not join in time") end)
end

-- After sends were refused: join again (harmless if we are still in the channel) while the fallback keeps working.
-- When the channel number is there, go back to the channel; otherwise plan the next try.
tryAgain = function()
  if not usesChannel(mode()) then scheduleRetry(); return end -- not using the channel right now: look again later
  state.nextRetryAt = nil
  local try = state.retries
  local logIt = retryWorthLogging()
  if logIt then ns.Log.add("info", "trying channel %s again (try %d)", tostring(crew().channel), try) end
  local ok = ns.Log.safe(FEATURE, startJoin)
  local function notThere()
    local delay = scheduleRetry()
    if logIt then ns.Log.add("warn", "channel %s did not join on try %d; next try in %d s", tostring(state.channelName),
      try, delay) end
  end
  if not ok then notThere(); return end
  watchJoin(function() return state.failed end, function(index)
    -- joined is still set from before the refusals; failedAt stays until a send works (see Transport.send)
    state.joined, state.failed, state.failReason = false, false, nil
    markJoined(index, true)
    state.graceNoted = not logIt -- a refusal right after this join is logged only when the try was
    if logIt then ns.Log.add("info", "channel %s joined again as %d (try %d); saying hello there",
      tostring(state.channelName), index, try) end
    ns.Bus.fire("CHANNEL_BACK")
  end, notThere)
end

-- Forgets the current connection (old timers stop); sends wait until the next join resolves.
local function resetConnection()
  state.generation = state.generation + 1
  state.joined, state.failed, state.failReason, state.failedAt = false, false, nil, nil
  state.index, state.badSends = 0, 0
  state.retries, state.nextRetryAt = 0, nil
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

local function isOurChannelEvent(channelName, channelIndex, baseName)
  if isCurrentChannel(channelName, baseName) then return true end
  return state.joined and tonumber(channelIndex) ~= nil and tonumber(channelIndex) == state.index and state.index > 0
end

local function onList(text, _, _, channelName, _, _, _, channelIndex, baseName)
  if not isOurChannelEvent(channelName, channelIndex, baseName) then return end
  state.listsHeard = state.listsHeard + 1
  for _, name in ipairs(Transport.parseList(text)) do addMember(name) end
  markListed()
end

local function onJoinNotice(_, playerName, _, channelName, _, _, _, channelIndex, baseName)
  if isOurChannelEvent(channelName, channelIndex, baseName) then addMember(playerName) end
end

local function onLeaveNotice(_, playerName, _, channelName, _, _, _, channelIndex, baseName)
  if isOurChannelEvent(channelName, channelIndex, baseName) then removeMember(playerName, "left the channel") end
end

-- "No player named 'X' is currently playing." after a whisper to a member: they are gone.
local function onSystem(message)
  if type(message) ~= "string" or ns.Util.isSecret(message) then return end
  local pattern = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
  for _, key in ipairs(memberKeys()) do
    local m = members[key]
    if message == string.format(pattern, m.name) then removeMember(m.name, "not playing") end
  end
end

-- Comm heard a TwizCrew message from this sender (raw name, as the game gave it). A whisper means their copy knows
-- us, so they become someone we whisper back; party and raid only fill in the full name of a known member.
function Transport.heardFrom(rawSender, chatType)
  if chatType == "WHISPER" then
    addMember(rawSender)
  elseif chatType == "PARTY" or chatType == "RAID" then
    local name = cleanName(rawSender)
    local key = name and memberKey(name)
    if key and members[key] then addMember(name) end
  end
end

function Transport.members()
  local out = {}
  for _, key in ipairs(memberKeys()) do out[#out + 1] = members[key].name end
  return out
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
  ns.Events.on(FEATURE, "CHAT_MSG_CHANNEL_LIST", onList)
  ns.Events.on(FEATURE, "CHAT_MSG_CHANNEL_JOIN", onJoinNotice)
  ns.Events.on(FEATURE, "CHAT_MSG_CHANNEL_LEAVE", onLeaveNotice)
  ns.Events.on(FEATURE, "CHAT_MSG_SYSTEM", onSystem)
  joinLater(ns.Config.CHANNEL_JOIN_DELAY)
end

-- The channel name or crew code changed: leave our channel, then join (the new) one after a short delay.
-- Leaving first matters even when only the code changed: a code only applies when the channel is created again.
function Transport.rejoin()
  local old = state.channelName
  resetConnection()
  for _, key in ipairs(memberKeys()) do members[key] = nil end -- another channel: other people
  state.warnedPassword = false
  if old and type(LeaveChannelByName) == "function" then
    state.leftAt = ns.now()
    ns.Log.safe(FEATURE, LeaveChannelByName, old)
  end
  state.channelName = crew().channel
  if state.started then joinLater(REJOIN_DELAY) end
end

local function inGroup(a, b)
  if ns.Util.plain(UnitInParty, a) then return true end
  if b and b ~= a then return ns.Util.plain(UnitInParty, b) and true or false end
  return false
end

-- One whisper destination per person: a channel member's full name when we know it, never ourselves.
local function addWhisper(out, seen, name, skipGroup)
  if type(name) ~= "string" or name == "" then return end
  local key, short = memberKey(name)
  if not key or seen[key] then return end
  local target = members[key] and members[key].name or short
  if skipGroup and inGroup(short, target) then return end
  seen[key] = true
  out[#out + 1] = { chatType = "WHISPER", target = target }
end

-- Names we may whisper: channel members, then (rosterToo) roster names, and the extra names from the settings.
local function whisperNames(skipGroup, rosterToo, out)
  out = out or {}
  local seen = {}
  for _, key in ipairs(memberKeys()) do addWhisper(out, seen, members[key].name, skipGroup) end
  if rosterToo ~= false and ns.roster and ns.roster.names then
    local ok, names = ns.Log.safe(FEATURE, function() return ns.roster:names() end)
    if ok and type(names) == "table" then for _, n in ipairs(names) do addWhisper(out, seen, n, skipGroup) end end
  end
  for _, n in ipairs(crew().extra or {}) do addWhisper(out, seen, n, skipGroup) end
  return out
end

local function groupDestination()
  if ns.Util.plain(IsInRaid) then return { chatType = "RAID" } end
  if ns.Util.plain(IsInGroup) then return { chatType = "PARTY" } end
end

-- The group (RAID or PARTY) as one destination, or nil when not in a group.
function Transport.groupDestination() return groupDestination() end

local function fallback()
  local out = {}
  local g = groupDestination()
  if g then out[1] = g end
  return whisperNames(g ~= nil, true, out)
end

-- A whisper to one crew member (nil when this mode does not whisper, or the name is ours).
-- The full name the game uses for a crew member (Forever adds surnames: "Chaos Deathbringr"), for whispers and
-- invites. The short name when we don't know better.
function Transport.fullName(name)
  if type(name) ~= "string" or name == "" then return name end
  local key, short = memberKey(name)
  return (key and members[key] and members[key].name) or short or name
end

function Transport.destinationFor(name)
  local m = mode()
  if m ~= "auto" and m ~= "whisper" then return nil end
  local out = {}
  addWhisper(out, {}, name, false)
  return out[1]
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
  if state.joined and not state.failed then
    -- The group (when grouped), a whisper to each channel member outside it, and one copy to the channel in case
    -- the game delivers it again. The receiver drops the second copy of the same message.
    local out = {}
    local g = groupDestination()
    if g then out[1] = g end
    whisperNames(g ~= nil, false, out)
    out[#out + 1] = { chatType = "CHANNEL", target = state.index }
    return out
  end
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
      if state.retries > 0 then
        ns.Log.add("info", "channel %s works again", tostring(state.channelName))
        state.retries, state.failedAt = 0, nil
      end
    elseif state.joinedAt and ns.now() - state.joinedAt < ns.Config.CHANNEL_JOIN_GRACE then
      -- Just joined: the game may not take messages on the channel yet. Keep this one and try again soon.
      if not state.graceNoted then
        state.graceNoted = true
        ns.Log.add("info", "channel %s refused a send right after joining (result %s); trying again shortly",
          tostring(state.channelName), tostring(result))
      end
      return false, true
    else
      state.badSends = state.badSends + 1
      if state.badSends >= ns.Config.CHANNEL_FAILS_BEFORE_FALLBACK then
        markFailed("sends to the channel were refused (result " .. tostring(result) .. ")", true)
      end
    end
  end
  return good, false
end

function Transport.status()
  local now = ns.now()
  return {
    mode = mode(), channel = state.channelName or crew().channel, channelIndex = state.index,
    joined = state.joined, failed = state.failed, failReason = state.failReason, lastResult = state.lastResult,
    hideFailed = state.hideFailed,
    downFor = state.failed and state.failedAt and math.max(0, now - state.failedAt) or nil,
    nextRetryIn = state.failed and state.nextRetryAt and math.max(0, state.nextRetryAt - now) or nil,
    retries = state.retries,
    members = Transport.members(), listed = state.listed, listsHeard = state.listsHeard,
  }
end
