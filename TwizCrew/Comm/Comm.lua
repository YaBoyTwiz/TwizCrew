-- Send / receive pipeline: encode, wait for the connection, queue, throttle; receive, dedupe, decode, handlers.
-- Registers the essential module "comm".
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local FEATURE = "comm"
local PUMP_INTERVAL = 0.2 -- seconds between queue pumps
local PENDING_MAX = 50    -- texts kept while the connection is still being set up

local queue = ns.Queue.new({ perSecond = ns.Config.SEND_PER_SECOND, burst = ns.Config.SEND_BURST, now = ns.now })
local handlers = {}  -- msgType -> { fn, ... }
local pending = {}   -- encoded texts waiting for the transport to resolve
local seen, seenCount, lastSweep = {}, 0, 0
local started = false

local function pushToDestinations(text)
  for _, dest in ipairs(ns.Transport.destinations()) do
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
    if ns.Transport.isPending() then
      pending[#pending + 1] = text
      if #pending > PENDING_MAX then table.remove(pending, 1) end
    else
      pushToDestinations(text)
    end
  end
end

function Comm.on(msgType, fn)
  local list = handlers[msgType]
  if not list then list = {}; handlers[msgType] = list end
  list[#list + 1] = fn
end

function Comm.dedupeSize() return seenCount end

local function sweepSeen(now)
  if now - lastSweep < ns.Config.DEDUPE_WINDOW then return end
  lastSweep = now
  for key, at in pairs(seen) do
    if now - at > ns.Config.DEDUPE_WINDOW then seen[key] = nil; seenCount = seenCount - 1 end
  end
end

local function onAddon(prefix, text, chatType, sender)
  if prefix ~= ns.Config.PREFIX or type(sender) ~= "string" or type(text) ~= "string" then return end
  sender = Ambiguate(sender, "none")
  if sender == ns.playerName() then return end
  local now = ns.now()
  sweepSeen(now)
  local key = sender .. "\0" .. text
  local at = seen[key]
  if at and now - at <= ns.Config.DEDUPE_WINDOW then return end
  if not at then seenCount = seenCount + 1 end
  seen[key] = now
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
  local ok = ns.Transport.send(item.text, item.dest)
  if not ok then
    ns.Log.debug("send to %s failed", tostring(item.dest.target or item.dest.chatType))
  end
  return true -- a refused message is dropped, never retried forever
end

local function pump()
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
      info = "The hidden channel your crew meets in. Everyone in the crew needs the same name." },
    { key = "password", label = "Crew code", kind = "text", store = "crew",
      info = "The secret code for the crew channel. Everyone in the crew needs the same code." },
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
