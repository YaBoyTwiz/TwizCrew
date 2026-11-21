-- Delivery through the guild: one GUILD addon message reaches every copy in the guild, a whisper reaches one guild
-- member (by the full name the guild list gives), and PARTY / RAID reach the group. Outside a guild nothing is sent.
-- Pending: until the game has said whether we are in a guild (ns.Guild's GUILD_STATE, at most GUILD_ABSENT_GRACE
-- seconds after login). TRANSPORT_READY fires when that settles and again whenever the character joins or leaves a
-- guild, so Comm can send (or drop) what it kept back and Crew can say HELLO.
-- v0.1.24 and before used a hidden chat channel; on the first start after the update it is left once.
local _, ns = ...

local Transport = {}
ns.Transport = Transport

local FEATURE = "comm"
local OLD_CHANNEL_LEAVE_DELAY = 5 -- s after login: the game rejoins saved channels by itself, leave after that
local SETTLE_SPARE = 2            -- s past GUILD_ABSENT_GRACE before we stop waiting for the guild list module
local WHISPER_MEMORY = 10         -- s: the game's "No player named X" line after a whisper to X is hidden

local plain = ns.Util.plain
local started, settled, inGuild = false, false, false
local lastResult
local whispered = {} -- full name -> time of the last whisper

local function gameInGuild() return plain(IsInGuild) == true end

-- The game function may live in C_ChatInfo or be a global, or not exist at all (then never a lockdown).
local function lockdownFn()
  if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
    return C_ChatInfo.InChatMessagingLockdown
  end
  if type(InChatMessagingLockdown) == "function" then return InChatMessagingLockdown end
end

-- True while the game holds back chat messages (a secret answer counts as no).
function Transport.lockdown()
  local fn = lockdownFn()
  return fn ~= nil and plain(fn) == true
end

function Transport.isPending() return not settled end

local function settle(nowInGuild)
  settled, inGuild = true, nowInGuild and true or false
  ns.Bus.fire("TRANSPORT_READY")
end

-- v0.1.24 kept a channel name, a crew code and whisper names (db.crew) and a connection choice: none of it means
-- anything now.
local function forgetOldChannel()
  local db = ns.db
  if type(db) ~= "table" then return end
  local old = type(db.crew) == "table" and db.crew.channel or nil
  db.crew = nil
  local comm = type(db.modules) == "table" and db.modules.comm
  if type(comm) == "table" and type(comm.settings) == "table" then comm.settings.transport = nil end
  if type(old) ~= "string" or old == "" or type(LeaveChannelByName) ~= "function" then return end
  C_Timer.After(OLD_CHANNEL_LEAVE_DELAY, function()
    ns.Log.safe(FEATURE, function()
      LeaveChannelByName(old)
      ns.Log.add("info", "left the old crew channel %s", ns.Util.safeText(old))
    end)
  end)
end

-- The game's "No player named 'X' is currently playing." right after we whispered X (a member who just went
-- offline while the guild list still said online) is hidden from chat.
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
  if started then return end
  started = true
  ns.Log.safe(FEATURE, forgetOldChannel)
  if type(ChatFrame_AddMessageEventFilter) == "function" then
    ns.Log.safe(FEATURE, ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", hideNotFoundLine)
  end
  ns.Bus.on(FEATURE, "GUILD_STATE", settle)
  -- the guild list module always answers within GUILD_ABSENT_GRACE; if it never does, ask the game ourselves
  C_Timer.After(ns.Config.GUILD_ABSENT_GRACE + SETTLE_SPARE, function()
    ns.Log.safe(FEATURE, function()
      if not settled then settle(gameInGuild()) end
    end)
  end)
end

local function sending() return settled and inGuild and gameInGuild() end

-- Everyone: one GUILD message (nothing outside a guild). msgType is not needed any more; kept for the callers.
function Transport.destinations(_msgType)
  if sending() then return { { chatType = "GUILD" } } end
  return {}
end

-- A whisper to one guild member, by the full name in the guild list. nil for a stranger, for me, before the list
-- has loaded, or outside a guild.
function Transport.destinationFor(name)
  if type(name) ~= "string" or name == "" or not sending() or not ns.Guild then return nil end
  local key = ns.Guild.keyOf(name)
  local full = key and ns.Guild.fullName(key)
  if not full or ns.isMe(key) then return nil end
  return { chatType = "WHISPER", target = full }
end

-- The group (RAID or PARTY) as one destination, or nil when not in a group.
function Transport.groupDestination()
  if plain(IsInRaid) then return { chatType = "RAID" } end
  if plain(IsInGroup) then return { chatType = "PARTY" } end
end

-- The full name the game uses for a guild member (Forever adds surnames: "Chaos Deathbringr"), for whispers and
-- invites; the short name when the guild list does not know them.
function Transport.fullName(name)
  if type(name) ~= "string" or name == "" then return name end
  local key = ns.Guild and ns.Guild.keyOf(name)
  return (key and ns.Guild.fullName(key)) or ns.shortName(name) or name
end

local function succeeded(result)
  return result == nil or result == true or result == 0
    or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success)
end

-- "Not now": too many messages, or a chat lockdown. The message was not sent but may be tried again later.
local function mustWait(result)
  local codes = Enum and Enum.SendAddonMessageResult
  return result == (codes and codes.AddonMessageThrottle or 3) or result == (codes and codes.ChannelThrottle or 8)
    or result == (codes and codes.AddOnMessageLockdown or 11)
end

-- Returns sent (true/false) and retryLater (true when the game asked us to wait; the message should be kept).
-- A guild message or whisper still queued when we left the guild is dropped without asking the game.
function Transport.send(text, dest)
  if dest.chatType ~= "PARTY" and dest.chatType ~= "RAID" and not sending() then return false, false end
  local ok, result = ns.Log.safe(FEATURE, C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, dest.chatType,
    dest.target)
  if not ok then return false, false end
  lastResult = result
  if dest.chatType == "WHISPER" and type(dest.target) == "string" then whispered[dest.target] = ns.now() end
  local good = succeeded(result)
  if not good and mustWait(result) then return false, true end
  return good, false
end

-- mode: "guild" (sending to the guild) or "none" (not in a guild, or not known yet: pending = true).
function Transport.status()
  local guild = plain(GetGuildInfo, "player")
  return { mode = sending() and "guild" or "none", pending = not settled,
    guild = type(guild) == "string" and guild or nil, lockdown = Transport.lockdown(), lastResult = lastResult }
end
