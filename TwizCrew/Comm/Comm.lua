-- Send / receive pipeline: encode, wait for the connection, queue, throttle; receive, dedupe, decode, handlers.
-- Registers the essential module "comm".
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local FEATURE = "comm"
local PUMP_INTERVAL = 0.2 -- seconds between queue pumps
local PENDING_MAX = 50    -- texts kept while the connection is still being set up
local THROTTLE_PAUSE = 1  -- seconds the queue waits after the game says "too many messages"

local queue = ns.Queue.new({ perSecond = ns.Config.SEND_PER_SECOND, burst = ns.Config.SEND_BURST, now = ns.now })
local handlers = {}  -- msgType -> { fn, ... }
local pending = {}   -- encoded texts waiting for the transport to resolve
local seen, seenCount, lastSweep = {}, 0, 0 -- seen: sender .. "\0" .. text -> { at = time, via = chat type }
local echoes = 0     -- our own CHANNEL messages heard back (shows the channel delivers)
local started = false
local pausedUntil = 0

-- Kept back while the connection is being set up (R1), oldest dropped past PENDING_MAX.
local function keep(text)
  pending[#pending + 1] = text
  if #pending > PENDING_MAX then table.remove(pending, 1) end
end

local function pushToDestinations(text)
  local dests = ns.Transport.destinations() -- may find the channel gone and start joining it again
  if ns.Transport.isPending() then keep(text); return end
  for _, dest in ipairs(dests) do
    queue:push({ text = text, dest = dest })
  end
end

local function flushPending()
  if ns.Transport.isPending() or #pending == 0 then return end
  local texts = pending
  pending = {}
  for _, text in ipairs(texts) do pushToDestinations(text) end
end

function Comm.send(msgType, fields)
  local texts = ns.Codec.encode(msgType, fields or {})
  for _, text in ipairs(texts) do
    if ns.Transport.isPending() then keep(text) else pushToDestinations(text) end
  end
end

function Comm.on(msgType, fn)
  local list = handlers[msgType]
  if not list then list = {}; handlers[msgType] = list end
  list[#list + 1] = fn
end

function Comm.dedupeSize() return seenCount end
function Comm.echoCount() return echoes end

local function sweepSeen(now)
  if now - lastSweep < ns.Config.DEDUPE_WINDOW then return end
  lastSweep = now
  for key, entry in pairs(seen) do
    if now - entry.at > ns.Config.DEDUPE_WINDOW then seen[key] = nil; seenCount = seenCount - 1 end
  end
end

local function onAddon(prefix, text, chatType, sender)
  if prefix ~= ns.Config.PREFIX or type(sender) ~= "string" or type(text) ~= "string" then return end
  sender = Ambiguate(sender, "none")
  if sender == ns.playerName() then
    if chatType == "CHANNEL" then echoes = echoes + 1 end
    return
  end
  local now = ns.now()
  sweepSeen(now)
  -- The same message by a second route (channel and party, say) is a duplicate; the same route twice is a resend.
  local key = sender .. "\0" .. text
  local entry = seen[key]
  if entry and now - entry.at <= ns.Config.DEDUPE_WINDOW and entry.via ~= chatType then return end
  if not entry then seenCount = seenCount + 1 end
  seen[key] = { at = now, via = chatType }
  local msg, why = ns.Codec.decode(text)
  if not msg then
    ns.Log.debug("ignored message from %s (%s)", sender, tostring(why))
    return
  end
  ns.Log.debug("recv %s from %s via %s", msg.type, sender, tostring(chatType))
  for _, fn in ipairs(handlers[msg.type] or {}) do
    ns.Log.safe(FEATURE, fn, sender, msg.fields)
  end
end

local function sendItem(item)
  local ok, retryLater = ns.Transport.send(item.text, item.dest)
  if retryLater then
    -- The game is throttling us: keep the message at the front and wait a moment.
    pausedUntil = ns.now() + THROTTLE_PAUSE
    ns.Log.debug("send to %s throttled, trying again soon", tostring(item.dest.target or item.dest.chatType))
    return false
  end
  ns.Log.debug("send %s via %s to %s%s", tostring(item.text:match("^%d+%^(%u+)%^") or "?"),
    tostring(item.dest.chatType), tostring(item.dest.target or "-"), ok and "" or " failed")
  return true -- a refused message is dropped, never retried forever
end

local function pump()
  if ns.now() < pausedUntil then return end
  queue:pump(sendItem)
end

local function applyDebug()
  ns.Log.chatDebug = ns.Modules.setting(FEATURE, "debug") == true
end

function Comm.start()
  if started then return end
  started = true
  applyDebug()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    ns.Log.safe(FEATURE, C_ChatInfo.RegisterAddonMessagePrefix, ns.Config.PREFIX)
  end
  ns.Events.on(FEATURE, "CHAT_MSG_ADDON", onAddon)
  ns.Events.on(FEATURE, "ENCOUNTER_START", function() queue:hold(true) end)
  ns.Events.on(FEATURE, "ENCOUNTER_END", function() queue:hold(false) end)
  ns.Events.on(FEATURE, "PLAYER_ENTERING_WORLD", function() queue:hold(false) end)
  ns.Bus.on(FEATURE, "TRANSPORT_READY", flushPending)
  C_Timer.NewTicker(PUMP_INTERVAL, function() ns.Log.safe(FEATURE, pump) end)
  ns.Transport.start()
end

ns.Modules.register({
  id = "comm", name = "Crew connection", tier = "essential",
  info = "How your copy of TwizCrew talks to your friends' copies. Leave it on automatic unless something is wrong.",
  defaults = { transport = "auto", debug = false },
  settings = {
    { key = "transport", label = "Connection", kind = "choice", choices = { { "auto", "Automatic" }, { "channel", "Hidden channel" }, { "whisper", "Whispers" },
        { "group", "Group chat" }, { "guild", "Guild chat" } },
      info = "How messages travel. Automatic uses a hidden chat channel and falls back to whispers or your group if that fails." },
    { key = "channel", label = "Crew channel", kind = "text", store = "crew",
      info = "The hidden channel your crew meets in. The channel name and the crew code must match your crew's. "
        .. "To lock someone out, pick a new channel name and tell your crew." },
    { key = "password", label = "Crew code", kind = "text", store = "crew", password = true,
      info = "The secret code for the crew channel. The channel name and the code must match your crew's. "
        .. "Changing only the code does not lock anyone out: to do that, pick a new channel name and tell your crew." },
    { key = "debug", label = "Show technical messages", kind = "toggle",
      info = "Prints what TwizCrew sends and receives in your chat window. Only useful when fixing problems." },
  },
  onEnable = function() Comm.start() end,
  onSettingChanged = function(key, value)
    if key == "debug" then
      applyDebug()
    elseif key == "transport" then
      flushPending()
    elseif key == "channel" or key == "password" then
      ns.Transport.rejoin()
    end
  end,
})
