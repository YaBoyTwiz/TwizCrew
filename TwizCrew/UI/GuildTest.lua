-- /tc guildtest: proves in the real game that guild addon messages work on this server, before the crew relies on
-- them. Sends one GPROBE to the guild (one addon message, straight to the game, not through the Comm queue), and every
-- other copy answers with a GPONG whisper to the sender name exactly as it arrived. Prints what happened in chat.
-- Needs Comm.onRaw (Comm/Comm.lua): the raw sender names and my own echo are only visible there.
local _, ns = ...

local GuildTest = {}
ns.GuildTest = GuildTest

local plain = ns.Util.plain
local ECHO_WAIT = 3      -- s: how long my own copy has to hear the probe back
local ANSWER_WAIT = 8    -- s: how long friends have to answer
local PONG_GAP = 10      -- s: one answer per sender at most this often

local facts = {}         -- the last run's results (GuildTest.facts)
local runId = 0
local nonce
local sentAt
local rawBySender = {}   -- short name -> raw sender name of their latest GUILD probe (to whisper back)
local pongRaw = {}       -- short name -> raw sender name of their GPONG whisper
local lastPong = {}      -- short name -> when I last answered them

local function say(text) print("TwizCrew: " .. ns.Util.safeText(text)) end

-- A raw sender name as text for the chat: a secret value is never shown or compared.
local function rawText(raw)
  if type(raw) ~= "string" then return "unknown" end
  if ns.Util.isSecret(raw) then return "hidden" end
  return raw
end

-- Game function that may live in C_ChatInfo or be a global; nil when this game has neither.
local function gameFn(name)
  if C_ChatInfo and type(C_ChatInfo[name]) == "function" then return C_ChatInfo[name] end
  local g = _G and _G[name]
  if type(g) == "function" then return g end
end

local function lockdownText()
  local exists = gameFn("InChatMessagingLockdown") ~= nil
  local fn = gameFn("AreOutgoingAddonChatMessagesRestricted")
  local restricted = fn and plain(fn)
  facts.lockdownExists = exists
  facts.restricted = restricted
  return "The game " .. (exists and "has" or "does not have") .. " InChatMessagingLockdown, and addon chat "
    .. (fn == nil and "restriction cannot be read here" or restricted == nil and "restriction reads as unknown"
      or ("is " .. (restricted and "restricted" or "not restricted") .. " right now")) .. "."
end

local function isAccepted(result) return result == 0 or result == true end

-- My own probe heard back (any GUILD message carrying my nonce).
local function onRawMessage(text, chatType, raw)
  if type(text) ~= "string" then return end
  if chatType ~= "GUILD" and chatType ~= "WHISPER" then return end
  local msg = ns.Codec.decode(text)
  if not msg then return end
  if msg.type == "GPROBE" and chatType == "GUILD" then
    if nonce and msg.fields.n == nonce then
      if not facts.echo then
        facts.echo = true
        facts.echoForm = rawText(raw)
        facts.echoAfter = ns.now() - (sentAt or ns.now())
      end
    elseif type(raw) == "string" and not ns.Util.isSecret(raw) then
      rawBySender[ns.shortName(raw)] = raw
    end
  elseif msg.type == "GPONG" and chatType == "WHISPER" and type(raw) == "string" and not ns.Util.isSecret(raw) then
    pongRaw[ns.shortName(raw)] = raw
  end
end

local function describeMe(e) return e.full end

function GuildTest.run()
  runId = runId + 1
  local id = runId
  facts = { ran = true, answers = {} }
  nonce = tostring(math.random(100000, 999999))
  local inGuild = plain(IsInGuild) == true
  facts.inGuild = inGuild
  local name = inGuild and plain(GetGuildInfo, "player") or nil
  facts.guildName = type(name) == "string" and name or nil
  local _, total = ns.Guild.count()
  local online = ns.Guild.count()
  facts.total, facts.online = total, online
  if not inGuild then
    say("You are not in a guild, so nothing was sent. Join a guild and try again.")
    say(lockdownText())
    return
  end
  say("You are in the guild " .. tostring(facts.guildName or "(name unknown)") .. ": " .. total .. " members, "
    .. online .. " online.")

  local sample
  for _, e in ipairs(ns.Guild.members()) do
    if not ns.Guild.isMe(e.full) then sample = e; break end
  end
  facts.sample = sample and describeMe(sample) or nil
  facts.zones = sample ~= nil and sample.zone ~= ""
  if sample then
    say("A guild list name looks like \"" .. sample.full .. "\", and zones are " .. (facts.zones and "given"
      or "not given") .. ".")
  else
    say("The guild list has nobody but you, so there is no name to show.")
  end

  local text = ns.Codec.encode("GPROBE", { n = nonce })[1]
  sentAt = ns.now()
  local result = plain(C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, "GUILD")
  facts.sendResult = result
  facts.accepted = isAccepted(result)

  C_Timer.After(ECHO_WAIT, function()
    if id ~= runId then return end
    local heard = facts.echo and (facts.echoAfter or 0) <= ECHO_WAIT
    say("The guild send was " .. (facts.accepted and "accepted" or "refused") .. " (result code "
      .. tostring(result) .. ") and my own copy " .. (heard and ("heard it back, sender shown as \""
      .. tostring(facts.echoForm) .. "\"") or "did not hear it back") .. ".")
  end)

  C_Timer.After(ANSWER_WAIT, function()
    if id ~= runId then return end
    if #facts.answers == 0 then
      say("Nobody answered (nobody else online with TwizCrew, or guild messages are not delivered).")
    else
      local parts = {}
      for i, a in ipairs(facts.answers) do
        parts[i] = a.key .. " in " .. string.format("%.1f", a.secs) .. " s (whisper sender shown as \"" .. a.form .. "\")"
      end
      say("These answered: " .. table.concat(parts, ", ") .. ".")
    end
    say(lockdownText())
  end)
end

function GuildTest.facts()
  local copy = {}
  for k, v in pairs(facts) do copy[k] = v end
  copy.answers = {}
  for i, a in ipairs(facts.answers or {}) do copy.answers[i] = a end
  return copy
end

-- One line for /tc report.
function GuildTest.reportLine()
  local inGuild = plain(IsInGuild) == true
  local parts
  if not inGuild then
    parts = "not in a guild"
  else
    local online, total = ns.Guild.count()
    local name = plain(GetGuildInfo, "player")
    parts = "in " .. (type(name) == "string" and name or "a guild") .. ", " .. total .. " members, " .. online
      .. " online"
  end
  local test
  if not facts.ran then
    test = "guild test not run (type /tc guildtest)"
  elseif not facts.inGuild then
    test = "guild test: not in a guild"
  else
    local who = {}
    for i, a in ipairs(facts.answers) do who[i] = a.key end
    test = "guild test: send " .. (facts.accepted and "accepted" or "refused") .. " (" .. tostring(facts.sendResult)
      .. "), own echo " .. (facts.echo and ("yes as \"" .. tostring(facts.echoForm) .. "\"") or "no") .. ", answered by "
      .. (#who > 0 and table.concat(who, ", ") or "nobody")
  end
  return "Guild: " .. parts .. "; " .. test
end

ns.Comm.onRaw(onRawMessage)

-- Someone's probe: whisper a GPONG back to the name as it arrived, at most once per sender every PONG_GAP seconds.
ns.Comm.on("GPROBE", function(sender, fields)
  local raw = rawBySender[sender]
  rawBySender[sender] = nil
  if not raw or type(fields.n) ~= "string" then return end
  local now = ns.now()
  if lastPong[sender] and now - lastPong[sender] < PONG_GAP then return end
  lastPong[sender] = now
  local text = ns.Codec.encode("GPONG", { n = fields.n })[1]
  plain(C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, "WHISPER", raw)
end)

ns.Comm.on("GPONG", function(sender, fields)
  if not nonce or fields.n ~= nonce or not facts.answers then return end
  for _, a in ipairs(facts.answers) do if a.sender == sender then return end end
  local key = ns.Guild.keyOf(sender) or sender
  local form = rawText(pongRaw[sender] or sender)
  facts.answers[#facts.answers + 1] = { sender = sender, key = key, secs = ns.now() - (sentAt or ns.now()), form = form }
end)
