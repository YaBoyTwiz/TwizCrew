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

local function sameDest(a, b)
  return a == b or (a.chatType == b.chatType and a.target == b.target)
end

-- key: waiting copies with this key (per destination) are dropped for the new one. sent: { left, fn }, counts the
-- copies still waiting; fn runs when the last one has gone out.
local function pushToDestinations(text, key, sent)
  local dests = ns.Transport.destinations() -- may find the channel gone and start joining it again
  if ns.Transport.isPending() then keep(text); return end
  for _, dest in ipairs(dests) do
    local item = { text = text, dest = dest, sent = sent }
    if sent then sent.left = sent.left + 1 end
    if key then queue:supersede(key, item, sameDest) else queue:push(item) end
  end
end

local function flushPending()
  if ns.Transport.isPending() or #pending == 0 then return end
  local texts = pending
  pending = {}
  for _, text in ipairs(texts) do pushToDestinations(text) end
end

-- opts.replace = a key (a show id, say): copies of an earlier msgType message with the same key that are still
-- waiting are dropped, the new one goes out instead. opts.onSent = a function run once every copy has left the
-- queue (at once when nothing was queued: the connection is still being set up, or there is nobody to send to).
function Comm.send(msgType, fields, opts)
  local texts = ns.Codec.encode(msgType, fields or {}, opts)
  local replace = opts and opts.replace
  local sent = opts and opts.onSent and { left = 0, fn = opts.onSent }
  for i, text in ipairs(texts) do
    local key = replace and (msgType .. ":" .. replace .. "#" .. i)
    if ns.Transport.isPending() then keep(text) else pushToDestinations(text, key, sent) end
  end
  if sent and sent.left == 0 then ns.Log.safe(FEATURE, sent.fn) end
end

-- Only to this crew member, as a whisper (automatic and whisper mode). Returns false, sending nothing, when this
-- mode cannot reach one person: the caller sends to everyone instead.
function Comm.sendTo(name, msgType, fields, opts)
  local dest = ns.Transport.destinationFor(name)
  if not dest then return false end
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {}, opts)) do
    queue:push({ text = text, dest = dest })
  end
  return true
end

-- Only to the group (one PARTY or RAID message), never whispered and never to the channel. Returns false, sending
-- nothing, when not in a group. opts.replace = a key: a waiting message with that key gets the new text instead.
local groupDest = {} -- chat type -> one destination table, so Queue:replace can tell "the same destination"
function Comm.sendGroup(msgType, fields, opts)
  local g = ns.Transport.groupDestination()
  if not g then return false end
  local dest = groupDest[g.chatType]
  if not dest then dest = g; groupDest[g.chatType] = g end
  local key = opts and opts.replace
  for i, text in ipairs(ns.Codec.encode(msgType, fields or {}, opts)) do
    if key then queue:replace(key .. "#" .. i, { text = text, dest = dest })
    else queue:push({ text = text, dest = dest }) end
  end
  return true
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

local loggedNameForm = false

local function dispatch(sender, msg)
  for _, fn in ipairs(handlers[msg.type] or {}) do
    ns.Log.safe(FEATURE, fn, sender, msg.fields)
  end
end

local function onAddon(prefix, text, chatType, sender)
  if prefix ~= ns.Config.PREFIX or type(sender) ~= "string" or type(text) ~= "string" then return end
  local raw = sender
  sender = ns.shortName(sender)
  if raw ~= sender and not loggedNameForm then
    loggedNameForm = true
    ns.Log.add("info", "sender names look like \"%s\"; using \"%s\"", ns.Util.safeText(raw), ns.Util.safeText(sender))
  end
  if ns.isMe(sender) then
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
  if msg.protocol > ns.Config.PROTOCOL then
    ns.Log.count("recv newer protocol")
    return
  end
  ns.Log.count("recv " .. tostring(msg.type))
  if ns.Log.chatDebug then ns.Log.debug("recv %s from %s via %s", msg.type, sender, tostring(chatType)) end
  ns.Log.safe(FEATURE, ns.Transport.heardFrom, raw, chatType)
  dispatch(sender, msg)
end

-- Test tools: a fake crew member's message (one encoded piece) goes through the same decode and handlers as a
-- friend's, without the transport or the duplicate check. Only fake names (ns.isTestName) are accepted.
function Comm.inject(sender, text)
  if not ns.isTestName(sender) then return false end
  local msg = ns.Codec.decode(text)
  if not msg then return false end
  dispatch(sender, msg)
  return true
end

local function sendItem(item)
  local ok, retryLater = ns.Transport.send(item.text, item.dest)
  if retryLater then
    -- The game is throttling us (or the channel was only just joined): keep the message at the front, wait a
    -- moment. Logged once per message, so a message kept for a while does not fill the log.
    pausedUntil = ns.now() + THROTTLE_PAUSE
    if not item.waitLogged then
      item.waitLogged = true
      ns.Log.debug("send to %s has to wait, trying again soon", tostring(item.dest.target or item.dest.chatType))
    end
    return false
  end
  local kind = tostring(item.text:match("^%d+%^(%u+)%^") or "?")
  ns.Log.count("send " .. kind)
  if not ok then ns.Log.count("send failed") end
  if ns.Log.chatDebug then
    ns.Log.debug("send %s via %s to %s%s", kind, tostring(item.dest.chatType),
      tostring(item.dest.target or "-"), ok and "" or " failed")
  end
  local sent = item.sent
  if sent then
    sent.left = sent.left - 1
    if sent.left == 0 then ns.Log.safe(FEATURE, sent.fn) end
  end
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
