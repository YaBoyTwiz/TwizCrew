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

local RAW_KEEP = 15   -- s: a raw name is kept this long for the answer that uses it

local facts = {}         -- the last run's results (GuildTest.facts)
local runId = 0
local nonce
local sentAt
local lastRunAt
local rawBySender = {}   -- short name -> { raw, at } of their latest GUILD probe (to whisper back)
local pongRaw = {}       -- short name -> { form, at } of their GPONG whisper
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

local function fresh(entry) return entry and ns.now() - entry.at <= RAW_KEEP end

-- Sends the probe. Returns facts.sendText: accepted / accepted without a code / the call failed / refused.
local function sendProbe(text)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, "GUILD")
  local good = result == nil or result == true or result == 0
    or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success)
  if not ok then
    facts.accepted, facts.sendText = false, "the call failed (" .. ns.Util.safeText(tostring(result)) .. ")"
  elseif not good then
    facts.accepted, facts.sendText = false, "refused (result code " .. tostring(result) .. ")"
  elseif result == nil then
    facts.accepted, facts.sendText = true, "accepted (the game gave no result code)"
  else
    facts.accepted, facts.sendText = true, "accepted"
  end
  facts.sendResult = ok and result or nil
end

local function singleWord(raw) return not raw:find("[%s%-]") end

-- My own probe heard back (any GUILD message carrying my nonce); other probes and pongs remembered by raw name.
local function onRawMessage(text, chatType, raw)
  if type(text) ~= "string" then return end
  local isProbe = chatType == "GUILD" and text:find("^%d+%^GPROBE%^")
  local isPong = chatType == "WHISPER" and text:find("^%d+%^GPONG%^")
  if not isProbe and not isPong then return end
  local msg = ns.Codec.decode(text)
  if not msg then return end
  local usable = type(raw) == "string" and not ns.Util.isSecret(raw)
  if msg.type == "GPROBE" then
    if nonce and msg.fields.n == nonce then
      if not facts.echo then
        facts.echo = true
        facts.echoForm = rawText(raw)
        facts.echoAfter = ns.now() - (sentAt or ns.now())
      end
    elseif usable then
      rawBySender[ns.shortName(raw)] = { raw = raw, at = ns.now() }
    end
  elseif msg.type == "GPONG" then
    -- a whisper from outside the guild is not an answer (Comm drops it too); before the list loads we cannot tell
    if chatType == "WHISPER" and ns.Guild.loaded() and not ns.Guild.isMember(raw) then return end
    local short = usable and ns.shortName(raw) or ("?" .. tostring(msg.fields.n))
    pongRaw[short] = { form = rawText(raw), at = ns.now(), usable = usable }
  end
end

function GuildTest.run()
  local now = ns.now()
  if lastRunAt and now - lastRunAt < PONG_GAP then
    say("Wait " .. math.ceil(PONG_GAP - (now - lastRunAt)) .. " seconds before testing again.")
    return
  end
  lastRunAt = now
  runId = runId + 1
  local id = runId
  facts = { ran = true, answers = {} }
  nonce = tostring(math.random(100000, 999999))
  local inGuild = plain(IsInGuild) == true
  facts.inGuild = inGuild
  local name = inGuild and plain(GetGuildInfo, "player") or nil
  facts.guildName = type(name) == "string" and name or nil
  if not inGuild then
    say("You are not in a guild, so nothing was sent. Join a guild and try again.")
    say(lockdownText())
    return
  end
  local loaded = ns.Guild.loaded()
  facts.listLoaded = loaded
  local online, total = ns.Guild.count()
  facts.total, facts.online = total, online
  local sample
  if loaded then
    say("You are in the guild " .. tostring(facts.guildName or "(name unknown)") .. ": " .. total .. " members, "
      .. online .. " online.")
    for _, e in ipairs(ns.Guild.members()) do
      if not ns.Guild.isMe(e.full) then sample = e; break end
    end
    facts.sample = sample and sample.full or nil
    facts.zones = sample ~= nil and sample.zone ~= ""
    if sample then
      say("A guild list name looks like \"" .. sample.full .. "\", and zones are " .. (facts.zones and "given"
        or "not given") .. ".")
    else
      say("The guild list has nobody but you, so there is no name to show.")
    end
  else
    ns.Guild.refresh()
    say("You are in the guild " .. tostring(facts.guildName or "(name unknown)") .. ", but the guild list has not "
      .. "loaded yet.")
    say("The guild list has not loaded yet, so there is no name to show.")
  end

  sentAt = now
  sendProbe(ns.Codec.encode("GPROBE", { n = nonce })[1])

  C_Timer.After(ECHO_WAIT, function()
    if id ~= runId then return end
    local heard = facts.echo and (facts.echoAfter or 0) <= ECHO_WAIT
    say("Guild send: " .. facts.sendText .. "; my own copy " .. (heard and ("heard it back, sender shown "
      .. "as \"" .. tostring(facts.echoForm) .. "\"") or "did not hear it back") .. ".")
  end)

  C_Timer.After(ANSWER_WAIT, function()
    if id ~= runId then return end
    if #facts.answers == 0 then
      local line = "Nobody answered (nobody else online with TwizCrew, or guild messages are not delivered)."
      if facts.echo and type(facts.echoForm) == "string" and facts.echoForm ~= "hidden" and singleWord(facts.echoForm)
        then
        line = line .. " Replies could not be tested: the game gave only a first name."
      end
      say(line)
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

GuildTest.forTest = { pongRaw = function() return pongRaw end }

function GuildTest.facts()
  local copy = {}
  for k, v in pairs(facts) do copy[k] = v end
  copy.answers = {}
  for i, a in ipairs(facts.answers or {}) do copy.answers[i] = a end
  return copy
end

-- One line for /tc report.
function GuildTest.reportLine()
  local parts
  if plain(IsInGuild) ~= true then
    parts = "not in a guild"
  else
    local name = plain(GetGuildInfo, "player")
    parts = "in " .. (type(name) == "string" and name or "a guild") .. ", "
    if ns.Guild.loaded() then
      local online, total = ns.Guild.count()
      parts = parts .. total .. " members, " .. online .. " online"
    else
      parts = parts .. "the guild list has not loaded yet"
    end
  end
  local test
  if not facts.ran then
    test = "guild test not run (type /tc guildtest)"
  elseif not facts.inGuild then
    test = "guild test: not in a guild"
  else
    local who = {}
    for i, a in ipairs(facts.answers) do who[i] = a.key end
    test = "guild test: send " .. tostring(facts.sendText) .. ", own echo "
      .. (facts.echo and ("yes as \"" .. tostring(facts.echoForm) .. "\"") or "no") .. ", answered by "
      .. (#who > 0 and table.concat(who, ", ") or "nobody")
  end
  return "Guild: " .. parts .. "; " .. test
end

ns.Comm.onRaw(onRawMessage)

-- Someone's probe: whisper a GPONG back, at most once per sender every PONG_GAP seconds. When the game gave only a
-- first name, the full name from the guild list is whispered instead (a first name alone cannot be whispered).
ns.Comm.on("GPROBE", function(sender, fields)
  local entry = rawBySender[sender]
  rawBySender[sender] = nil
  if not fresh(entry) or type(fields.n) ~= "string" then return end
  local target = entry.raw
  if singleWord(target) then
    local key = ns.Guild.keyOf(target)
    local full = key and ns.Guild.fullName(key)
    if full then target = full
    else ns.Log.add("warn", "guild test: cannot whisper back to \"%s\", only a first name and not in the list",
      ns.Util.safeText(target)) end
  end
  local now = ns.now()
  if lastPong[sender] and now - lastPong[sender] < PONG_GAP then return end
  lastPong[sender] = now
  local text = ns.Codec.encode("GPONG", { n = fields.n })[1]
  plain(C_ChatInfo.SendAddonMessage, ns.Config.PREFIX, text, "WHISPER", target)
end)

-- An answer counts only when it arrived by whisper (the raw hook saw it).
ns.Comm.on("GPONG", function(sender, fields)
  if not nonce or fields.n ~= nonce or not facts.answers then return end
  local seen = pongRaw[sender] or pongRaw["?" .. fields.n]
  pongRaw[sender], pongRaw["?" .. fields.n] = nil, nil
  if not fresh(seen) then return end
  for _, a in ipairs(facts.answers) do if a.sender == sender then return end end
  local key = ns.Guild.keyOf(sender) or sender
  facts.answers[#facts.answers + 1] = { sender = sender, key = key, secs = ns.now() - (sentAt or ns.now()),
    form = seen.usable and seen.form or "unknown" }
end)
