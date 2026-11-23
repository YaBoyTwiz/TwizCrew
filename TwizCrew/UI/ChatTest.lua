-- /tc chattest: a test tool (changes no addon behaviour) that checks in the real game whether the guild's chat
-- channels on the guild tab (C_Club streams) keep their history on Blizzard's server, so a line written while a
-- guild mate was offline could be read when they log on. Shapes from Blizzard's Classic Era communities code:
-- GetGuildClubId() -> clubId; GetStreams(clubId) -> { streamId, name, streamType } (Enum.ClubStreamType.Guild = 1);
-- GetMessageRanges(clubId, streamId) -> { oldestMessageId, newestMessageId } (newest range last);
-- GetMessagesInRange(clubId, streamId, oldest, newest) -> { messageId = { epoch (microseconds), position }, content,
-- author }; RequestMoreMessagesBefore(clubId, streamId, messageId or nil, count) -> CLUB_MESSAGE_HISTORY_RECEIVED;
-- SendMessage(clubId, streamId, text) is restricted (the player's own key press or click). Every line goes to chat
-- and the saved log (UI/Probes.lua).
--   /tc chattest        which functions exist, the streams, how much history can be read, a verdict line
--   /tc chattest send   posts "TCtest <time>" to the guild stream (the whole guild sees it): typed, and a button
local _, ns = ...

local ChatTest = {}
ns.ChatTest = ChatTest

local P = ns.Probes
local FEATURE = "chattest"
local say = P.sayer("chattest")
local field = P.field
local isSecret = ns.Util.isSecret

local HISTORY_WAIT = 5 -- s: how long the server has to send older lines
local SEND_WAIT = 5    -- s: how long the line has to show in the stream
local BUSY_MAX = 30    -- s: a run older than this no longer blocks a new one
local MAX_STREAMS = 5
local ASK_COUNT = 50   -- older lines asked for
local GUILD_STREAM = 1 -- Enum.ClubStreamType.Guild in Blizzard's code

local CHECKS = { "GetGuildClubId", "GetStreams", "GetStreamInfo", "GetMessageRanges", "GetMessagesInRange",
  "RequestMoreMessagesBefore", "FocusStream", "SendMessage", "GetClubPrivileges", "CreateStream", "EditMessage",
  "DestroyMessage" }

-- When this copy of the addon started (login or /reload), by the computer's clock: messages older than this were
-- written before this login.
local loadedAt = (function()
  local ok, t = pcall(time)
  if ok and type(t) == "number" then return t end
end)()

local busySince
local tried = {} -- way -> what happened

local function club(name) return P.fn(C_Club, name) end

local function busy()
  if busySince and ns.now() - busySince < BUSY_MAX then
    say("A chat test is still running. Wait a few seconds and try again.")
    return true
  end
  busySince = ns.now()
  return false
end
local function free() busySince = nil end

local function nowSeconds()
  local ok, t = P.try(time)
  if ok and type(t) == "number" then return t end
end

-- A message's time in seconds (its id's epoch is in microseconds), nil when unreadable.
local function secondsOf(msg)
  local id = field(msg, "messageId")
  local epoch = tonumber(field(id, "epoch"))
  if not epoch or epoch <= 0 then return nil end
  return epoch / 1000000
end

local function ageText(seconds)
  local now = nowSeconds()
  if not seconds or not now then return "unknown age" end
  local age = now - seconds
  if age < -300 or age > 20 * 365 * 86400 then return "unknown age" end
  return ns.Util.ago(math.max(0, age))
end

-- The usable text of a message ("hidden" for a secret one), cut to n letters.
local function contentOf(msg, n)
  local okR, content = pcall(function() return msg.content end)
  if not okR or content == nil then return "" end
  if isSecret(content) then return "hidden" end
  return P.cut(tostring(content), n)
end

local function idOf(v) return isSecret(v) and "hidden" or tostring(v) end

-- The guild club id, or nil and a reason.
local function guildClub()
  local fn = club("GetGuildClubId")
  if not fn then return nil, "GetGuildClubId is missing" end
  local ok, id = P.try(fn)
  if not ok then return nil, "GetGuildClubId failed: " .. id end
  if id == nil then return nil, "the game gives no guild club id (not in a guild, or no guild channels here)" end
  return id
end

-- The streams: { id, name, kind }; nil and a reason when they cannot be read.
local function streamsOf(clubId)
  local ok, list = P.try(club("GetStreams"), clubId)
  if not ok then return nil, "GetStreams " .. (list == "missing" and "is missing" or ("failed: " .. list)) end
  local out = {}
  for _, s in ipairs(type(list) == "table" and list or {}) do
    local id = field(s, "streamId")
    if id ~= nil then
      out[#out + 1] = { id = id, name = field(s, "name"), kind = field(s, "streamType") }
    end
  end
  return out
end

local function kindText(kind)
  local names = { [0] = "General", [1] = "Guild", [2] = "Officer", [3] = "Other" }
  local e = Enum and type(Enum.ClubStreamType) == "table" and Enum.ClubStreamType or nil
  if e then for k, v in pairs(e) do if v == kind and type(k) == "string" then return k end end end
  return names[kind] or P.text(kind)
end

local function guildKind()
  local e = Enum and type(Enum.ClubStreamType) == "table" and Enum.ClubStreamType.Guild
  return type(e) == "number" and e or GUILD_STREAM
end

-- The stream to post to and ask history of: the one of the Guild kind, else the first.
local function mainStream(streams)
  for _, s in ipairs(streams) do if s.kind == guildKind() then return s end end
  return streams[1]
end

-- Every message the game holds for a stream: list of messages (oldest first by range), the range count, the oldest
-- message id (for asking older history). Second result an error text.
local function readStream(clubId, streamId)
  local okR, ranges = P.try(club("GetMessageRanges"), clubId, streamId)
  if not okR then return nil, "GetMessageRanges " .. (ranges == "missing" and "is missing" or ("failed: " .. ranges)) end
  ranges = type(ranges) == "table" and ranges or {}
  local msgs, oldestId = {}, nil
  local inRange = club("GetMessagesInRange")
  for i, r in ipairs(ranges) do
    local oldest, newest = field(r, "oldestMessageId"), field(r, "newestMessageId")
    if i == 1 then oldestId = oldest end
    if inRange and oldest and newest then
      local ok, list = P.try(inRange, clubId, streamId, oldest, newest)
      if ok and type(list) == "table" then
        for _, m in ipairs(list) do msgs[#msgs + 1] = m end
      end
    end
  end
  return { msgs = msgs, ranges = #ranges, oldestId = oldestId }
end

-- Facts about a stream's readable messages: count, oldest and newest time, how many before this login.
local function facts(read)
  local f = { count = #read.msgs, before = 0 }
  for _, m in ipairs(read.msgs) do
    local s = secondsOf(m)
    if s then
      if not f.oldest or s < f.oldest then f.oldest = s end
      if not f.newest or s > f.newest then f.newest, f.newestMsg = s, m end
      if loadedAt and s < loadedAt then f.before = f.before + 1 end
    end
  end
  if not f.newestMsg then f.newestMsg = read.msgs[#read.msgs] end
  return f
end

local function streamLine(read)
  local f = facts(read)
  local line = "  ranges: " .. read.ranges .. ", messages readable: " .. f.count
  if f.count > 0 then
    line = line .. ", oldest " .. ageText(f.oldest) .. ", newest " .. ageText(f.newest) .. ": \""
      .. contentOf(f.newestMsg, 40) .. "\""
  end
  return line
end

local function verdict(answer, beforeText)
  say("History kept by the server: " .. answer .. "; messages written before this login: " .. beforeText .. ".")
end

function ChatTest.run()
  if type(C_Club) ~= "table" then
    say("Guild chat channels (C_Club) are not available on this game, so there is nothing to test.")
    verdict("can't tell", "can't tell")
    return
  end
  if busy() then return end
  local have, miss = {}, {}
  for _, name in ipairs(CHECKS) do
    if club(name) then have[#have + 1] = name else miss[#miss + 1] = name end
  end
  say("C_Club functions present (" .. #have .. " of " .. #CHECKS .. "): " .. table.concat(have, ", ") .. ".")
  say("Missing: " .. (#miss > 0 and table.concat(miss, ", ") or "none") .. ".")
  local clubId, why = guildClub()
  if clubId == nil then
    say("No guild channels to read: " .. why .. ".")
    verdict("can't tell", "can't tell")
    free()
    return
  end
  say("Guild club id: " .. idOf(clubId) .. ".")
  local privOk, priv = P.try(club("GetClubPrivileges"), clubId)
  if privOk and type(priv) == "table" then
    say("You may write lines: " .. P.yesNo(field(priv, "canCreateMessage")) .. "; make channels: "
      .. P.yesNo(field(priv, "canCreateStream")) .. ".")
  end
  local streams, whyS = streamsOf(clubId)
  if not streams then
    say("The channels could not be read: " .. whyS .. ".")
    verdict("can't tell", "can't tell")
    free()
    return
  end
  if #streams == 0 then
    say("The guild has no channels the game will list.")
    verdict("can't tell", "can't tell")
    free()
    return
  end
  local before = 0
  for i, s in ipairs(streams) do
    say("Channel " .. i .. ": \"" .. P.text(s.name) .. "\", type " .. kindText(s.kind) .. ", id " .. idOf(s.id) .. ".")
    if i <= MAX_STREAMS then
      local focusOk, focused = P.try(club("FocusStream"), clubId, s.id)
      local read, err = readStream(clubId, s.id)
      if read then
        say(streamLine(read) .. (club("FocusStream") and ("; focus: " .. (focusOk and P.yesNo(focused)
          or "failed")) or "") .. ".")
        before = before + facts(read).before
      else
        say("  " .. err .. ".")
      end
    end
  end
  local main = mainStream(streams)
  local firstRead = readStream(clubId, main.id)
  local firstCount = firstRead and #firstRead.msgs or 0
  local ask = club("RequestMoreMessagesBefore")
  if not ask then
    say("RequestMoreMessagesBefore is missing, so older lines cannot be asked for.")
    local answer = before > 0 and "yes" or "can't tell"
    verdict(answer, before > 0 and ("readable (" .. before .. ")") or "none seen")
    free()
    return
  end
  local function finish(event, already)
    local again = readStream(clubId, main.id)
    local f = again and facts(again) or { count = 0, before = 0 }
    local more = f.count - firstCount
    if event then
      say("Asked the server for older lines of \"" .. P.text(main.name) .. "\": " .. (more > 0 and (more ..
        " more arrived") or "nothing new arrived") .. "; now " .. f.count .. " readable" .. (f.count > 0 and
        (", oldest " .. ageText(f.oldest)) or "") .. ".")
    elseif already == true then
      say("Asked the server for older lines: the game says it already has them; " .. f.count .. " readable.")
    else
      say("Asked the server for older lines: no answer within " .. HISTORY_WAIT .. " s.")
    end
    local beforeAll = math.max(before, f.before)
    local answer
    if beforeAll > 0 or more > 0 then
      answer = "yes"
    elseif event and f.count == 0 then
      answer = "no (nothing came back; maybe nobody has written there yet)"
    elseif event then
      answer = "no (only lines from this login)"
    else
      answer = "can't tell"
    end
    verdict(answer, beforeAll > 0 and ("readable (" .. beforeAll .. ")") or (event and "none" or "can't tell"))
    say("Type /tc chattest send to post a test line (the whole guild sees it).")
    free()
  end
  local already
  P.wait({ "CLUB_MESSAGE_HISTORY_RECEIVED" }, HISTORY_WAIT, function(event) finish(event, already) end,
    function(_, cid, sid)
      if isSecret(cid) or isSecret(sid) then return false end
      return cid == clubId and sid == main.id
    end, FEATURE)
  local ok, result = P.try(ask, clubId, main.id, firstRead and firstRead.oldestId or nil, ASK_COUNT)
  if not ok then
    say("RequestMoreMessagesBefore failed: " .. result .. ".")
  else
    already = result
  end
end

local function summary()
  say("Ways tried so far: typed command: " .. (tried["typed command"] or "not tried") .. "; button: "
    .. (tried["button"] or "not tried") .. ".")
end

-- One try at posting the test line. way: "typed command" or "button". after() when done.
local function attempt(way, after)
  local send = club("SendMessage")
  if not send then
    say("SendMessage is missing on this game, so no line can be posted.")
    tried[way] = "not possible here"
    after()
    return
  end
  local clubId, why = guildClub()
  if clubId == nil then
    say("Cannot post: " .. why .. ".")
    tried[way] = "no guild club"
    after()
    return
  end
  local streams, whyS = streamsOf(clubId)
  if not streams or #streams == 0 then
    say("Cannot post: " .. (whyS or "the guild has no channels the game will list") .. ".")
    tried[way] = "no channel"
    after()
    return
  end
  local main = mainStream(streams)
  local text = "TCtest " .. P.clock()
  local callError
  P.wait({ "CLUB_MESSAGE_ADDED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }, SEND_WAIT, function(event)
    local result
    if callError then
      result = "SendMessage raised an error (" .. callError .. ")"
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
      result = "the game blocked SendMessage (it wants a key press or click)"
    elseif event == "CLUB_MESSAGE_ADDED" then
      result = "a new line arrived in the channel"
    else
      result = "no new line within " .. SEND_WAIT .. " s"
    end
    local read = readStream(clubId, main.id)
    local shows = false
    for _, m in ipairs(read and read.msgs or {}) do
      if contentOf(m, 60) == text then shows = true end
    end
    say("SendMessage from the " .. way .. ": " .. result .. "; the line \"" .. text .. "\" shows in the channel: "
      .. (shows and "yes" or "no") .. ".")
    tried[way] = (shows and "worked" or "did not work") .. " (" .. result .. ")"
    summary()
    after()
  end, function(event, a1, a2)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
      return not isSecret(a1) and a1 == ns.ADDON
    end
    if isSecret(a1) or isSecret(a2) then return false end
    return a1 == clubId and a2 == main.id
  end, FEATURE)
  say("Posting \"" .. text .. "\" to \"" .. P.text(main.name) .. "\" from the " .. way .. " (the whole guild sees it).")
  local ok, err = P.try(send, clubId, main.id, text)
  if not ok then callError = err end
end

function ChatTest.send()
  if type(C_Club) ~= "table" then
    say("Guild chat channels (C_Club) are not available on this game, so no line can be posted.")
    return
  end
  if busy() then return end
  attempt("typed command", function()
    free()
    local why = tried["typed command"]
    if why == "not possible here" or why == "no guild club" or why == "no channel" then return end
    say("Now click \"Send test line\" in the small window to try the same with a click (it posts a second line"
      .. " the guild sees).")
    P.button("chattest", "Send test line", function()
      if busy() then return end
      attempt("button", function() free() end)
    end, FEATURE)
  end)
end

local USAGE = "/tc chattest - check whether guild chat keeps its history on the server; /tc chattest send - post"
  .. " a test line to guild chat (the whole guild sees it)."

function ChatTest.command(rest)
  local what = ns.Util.trim(tostring(rest or "")):lower()
  if what == "" then ChatTest.run()
  elseif what == "send" then ChatTest.send()
  else say(USAGE) end
end

ChatTest.forTest = { reset = function() busySince = nil; tried = {} end,
  setLoadedAt = function(t) loadedAt = t end }
