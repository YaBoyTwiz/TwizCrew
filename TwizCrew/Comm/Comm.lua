-- Send / receive pipeline: encode, wait for the connection, queue, throttle; receive, trust, dedupe, decode, handlers.
-- Only guild members are trusted: a message from anyone else is dropped before it is decoded (see onAddon).
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
local started = false
local pausedUntil = 0

-- Kept back while the connection is being set up (R1), oldest dropped past PENDING_MAX.
local function keep(text, bulk, msgType)
  pending[#pending + 1] = { text = text, bulk = bulk, msgType = msgType }
  if #pending > PENDING_MAX then table.remove(pending, 1) end
end

local function sameDest(a, b)
  return a == b or (a.chatType == b.chatType and a.target == b.target)
end

-- key: waiting copies with this key (per destination) are dropped for the new one. sent: { left, fn }, counts the
-- copies still waiting; fn runs when the last one has gone out.
local function pushToDestinations(text, key, sent, bulk, msgType)
  local dests = ns.Transport.destinations(msgType)
  if ns.Transport.isPending() then keep(text, bulk, msgType); return end
  for _, dest in ipairs(dests) do
    local item = { text = text, dest = dest, sent = sent }
    if sent then sent.left = sent.left + 1 end
    if key then queue:supersede(key, item, sameDest, bulk) else queue:push(item, bulk) end
  end
end

local function flushPending()
  if ns.Transport.isPending() or #pending == 0 then return end
  local texts = pending
  pending = {}
  for _, text in ipairs(texts) do pushToDestinations(text.text, nil, nil, text.bulk, text.msgType) end
end

-- opts.bulk = true: the copies wait in the bulk lane, served only while no normal message is waiting (big swaps).
-- opts.replace = a key (a show id, say): copies of an earlier msgType message with the same key that are still
-- waiting are dropped, the new one goes out instead. opts.onSent = a function run once every copy has left the
-- queue (at once when nothing was queued: the connection is still being set up, or there is nobody to send to).
function Comm.send(msgType, fields, opts)
  local texts = ns.Codec.encode(msgType, fields or {}, opts)
  local replace = opts and opts.replace
  local bulk = opts and opts.bulk
  local sent = opts and opts.onSent and { left = 0, fn = opts.onSent }
  for i, text in ipairs(texts) do
    local key = replace and (msgType .. ":" .. replace .. "#" .. i)
    if ns.Transport.isPending() then keep(text, bulk, msgType) else pushToDestinations(text, key, sent, bulk, msgType) end
  end
  if sent and sent.left == 0 then ns.Log.safe(FEATURE, sent.fn) end
end

-- Only to this guild member, as a whisper. Returns false, sending nothing, when they cannot be whispered (not in the
-- guild, the guild list has not loaded yet, not in a guild at all): the caller sends to everyone instead.
function Comm.sendTo(name, msgType, fields, opts)
  local dest = ns.Transport.destinationFor(name)
  if not dest then return false end
  for _, text in ipairs(ns.Codec.encode(msgType, fields or {}, opts)) do
    queue:push({ text = text, dest = dest }, opts and opts.bulk)
  end
  return true
end

-- Only to the group (one PARTY or RAID message), never whispered and never to the guild. Returns false, sending
-- nothing, when not in a group. opts.replace = a key: a waiting message with that key gets the new text instead.
local groupDest = {} -- chat type -> one destination table, so Queue:replace can tell "the same destination"
function Comm.sendGroup(msgType, fields, opts)
  local g = ns.Transport.groupDestination()
  if not g then return false end
  local dest = groupDest[g.chatType]
  if not dest then dest = g; groupDest[g.chatType] = g end
  local key = opts and opts.replace
  for i, text in ipairs(ns.Codec.encode(msgType, fields or {}, opts)) do
    local bulk = opts and opts.bulk
    if key then queue:replace(key .. "#" .. i, { text = text, dest = dest }, bulk)
    else queue:push({ text = text, dest = dest }, bulk) end
  end
  return true
end

-- Asks for the same data of mine from several copies at once (every copy asks a newcomer for the newcomer's diary,
-- say): asks with the same key within `window` seconds (ASK_COLLECT by default) are answered once, when the window
-- ends: answer(name) for a whisper when one copy asked, answer(nil) for one guild message when more did. A key gets
-- at most one guild answer per ASK_ANSWER_GAP seconds: more asks inside the gap are ignored (they had it).
local asks = {} -- key -> { first = name, n = askers, by = { name = true } }
local guildAnsweredAt = {} -- key -> ns.now() of its last guild answer
function Comm.answerAsk(key, asker, answer, window)
  local a = asks[key]
  if a then
    if not a.by[asker] then a.by[asker], a.n = true, a.n + 1 end
    return
  end
  a = { first = asker, n = 1, by = { [asker] = true } }
  asks[key] = a
  C_Timer.After(window or ns.Config.ASK_COLLECT, function()
    asks[key] = nil
    local to = a.n == 1 and a.first or nil
    if not to then
      local at = guildAnsweredAt[key]
      if at and ns.now() - at < ns.Config.ASK_ANSWER_GAP then return end
      guildAnsweredAt[key] = ns.now()
    end
    ns.Log.safe(FEATURE, answer, to)
  end)
end

-- fn(text, chatType, rawSender) runs for every message with our prefix, before the "is it me" check and before any
-- filtering, so it also sees my own echo and the sender name exactly as the game gave it (possibly a secret value
-- inside dungeons). The guild test (UI/GuildTest.lua) depends on this hook: keep it when the receive filter changes.
local rawHooks = {}
function Comm.onRaw(fn) rawHooks[#rawHooks + 1] = fn end

function Comm.on(msgType, fn)
  local list = handlers[msgType]
  if not list then list = {}; handlers[msgType] = list end
  list[#list + 1] = fn
end

function Comm.dedupeSize() return seenCount end

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

-- The key a message is filed under, or nil when the sender must not be trusted. A GUILD message is from a member
-- by definition: their key; when the list has not loaded yet (or does not have them yet) the key saved for them
-- earlier, else their first word, unless that word is mine or given to someone else (then their full name, so data
-- never mixes). Any other chat type (whisper, party, raid) only from someone the guild list has.
local function senderKey(raw, chatType)
  local G = ns.Guild
  local key = G and G.keyOf(raw)
  if key then return key end
  if chatType ~= "GUILD" then
    if G and not G.loaded() then G.refresh() end -- maybe a member: ask for the list (at most every 10 s)
    return nil
  end
  if not G then return ns.shortName(raw) end
  if G.loaded() then G.refresh() end -- someone new: the list is behind
  local saved = G.savedKeyOf(raw)
  if saved then return saved end
  local short = ns.shortName(raw)
  if ns.isMe(short) or G.keyTakenByOther(short, raw) then return G.cleanName(raw) or short end
  return short
end

local function onAddon(prefix, text, chatType, raw)
  if prefix ~= ns.Config.PREFIX or type(raw) ~= "string" or type(text) ~= "string" then return end
  for _, fn in ipairs(rawHooks) do ns.Log.safe(FEATURE, fn, text, chatType, raw) end
  if ns.isMe(raw) then return end
  local sender = senderKey(raw, chatType)
  if not sender then
    ns.Log.count("recv not in guild")
    return
  end
  if raw ~= sender and not loggedNameForm then
    loggedNameForm = true
    ns.Log.add("info", "sender names look like \"%s\"; using \"%s\"", ns.Util.safeText(raw), ns.Util.safeText(sender))
  end
  local now = ns.now()
  sweepSeen(now)
  -- The same message by a second route (an old copy's whisper and party copy, say) is a duplicate; the same route
  -- twice is a resend.
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
    -- The game is throttling us (or holds chat back for a moment): keep the message at the front, wait a
    -- moment. Logged once per message, so a message kept for a while does not fill the log.
    pausedUntil = ns.now() + THROTTLE_PAUSE
    item.tries = (item.tries or 0) + 1
    if item.tries >= ns.Config.SEND_RETRY_MAX then
      ns.Log.add("warn", "send to %s given up after %d tries", tostring(item.dest.target or item.dest.chatType),
        item.tries)
      local sent = item.sent
      if sent then
        sent.left = sent.left - 1
        if sent.left == 0 then ns.Log.safe(FEATURE, sent.fn) end
      end
      return true -- dropped: the queue moves on
    end
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
  if ns.Transport.lockdown() then return end -- the game holds chat back (checked every pump)
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
  info = "How your copy of TwizCrew talks to the copies of your guild mates: through the guild, never in guild chat "
    .. "you can see. Only guild members are listened to.",
  defaults = { debug = false },
  settings = {
    { key = "debug", label = "Show technical messages", kind = "toggle",
      info = "Prints what TwizCrew sends and receives in your chat window. Only useful when fixing problems." },
  },
  onEnable = function() Comm.start() end,
  onSettingChanged = function(key)
    if key == "debug" then applyDebug() end
  end,
})
