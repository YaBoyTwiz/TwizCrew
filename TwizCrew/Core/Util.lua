-- Pure helpers (no WoW API).
local _, ns = ...

local Util = {}
ns.Util = Util

-- Splits on a plain single character; keeps empty fields.
function Util.split(s, sep)
  local out, start = {}, 1
  while true do
    local i = string.find(s, sep, start, true)
    if not i then
      out[#out + 1] = string.sub(s, start)
      return out
    end
    out[#out + 1] = string.sub(s, start, i - 1)
    start = i + 1
  end
end

-- A short checksum of a string (at most 6 digits).
function Util.checksum(s)
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return tostring(h % 1000000)
end

function Util.trim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function Util.copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Util.copy(x) end
  return out
end

-- Fills missing keys recursively; replaces values whose type differs from the default's.
function Util.mergeDefaults(target, defaults)
  for k, d in pairs(defaults) do
    local cur = target[k]
    if type(cur) ~= type(d) then
      target[k] = Util.copy(d)
    elseif type(d) == "table" then
      Util.mergeDefaults(cur, d)
    end
  end
  return target
end

-- "v1.2.10-beta" -> { 1, 2, 10 }: a leading v and text after a number are ignored, junk counts as 0.
local function versionParts(v)
  local parts = {}
  local s = string.gsub(tostring(v or ""), "^[vV]", "")
  for piece in string.gmatch(s, "[^.]+") do
    parts[#parts + 1] = tonumber(string.match(piece, "^%d+") or "") or 0
  end
  return parts
end

-- Only plain versions like "0.2.10" (as sent by another copy) are trusted.
function Util.isVersion(v)
  return type(v) == "string" and #v <= 20 and string.find(v, "^%d+[%.%d]*$") ~= nil
    and not string.find(v, "..", 1, true) and string.sub(v, -1) ~= "."
end

function Util.compareVersions(a, b)
  local pa, pb = versionParts(a), versionParts(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

-- Cuts to at most maxChars characters, never in the middle of a multi-byte letter.
function Util.truncateUTF8(s, maxChars)
  local chars, i, n = 0, 1, #s
  while i <= n do
    local b = string.byte(s, i)
    local len = 1
    if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
    if chars == maxChars then return string.sub(s, 1, i - 1) end
    chars = chars + 1
    i = i + len
  end
  return s
end

-- WoW treats "|" as an escape; doubling it shows it as plain text.
function Util.safeText(s)
  return (string.gsub(s, "|", "||"))
end

function Util.ago(seconds)
  if seconds < 60 then return "just now" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
  return math.floor(seconds / 86400) .. "d ago"
end

-- True when the game says v is a "secret" value (dungeon rules: no tests, math or comparing). False when the game has
-- no issecretvalue. A failing check counts as secret.
function Util.isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, yes = pcall(issecretvalue, v)
  if not ok then return true end
  return yes == true
end

local function scrub(...)
  local n = select("#", ...)
  local out = {}
  for i = 1, n do
    local v = select(i, ...)
    if not Util.isSecret(v) then out[i] = v end
  end
  return unpack(out, 1, n)
end

local function scrubIfOk(ok, ...)
  if ok then return scrub(...) end
end

-- Calls fn(...) safely and returns its results with every secret one replaced by nil. Returns nothing when fn is not
-- a function or raises. Every yes/no or number from a game call goes through here before it is tested.
function Util.plain(fn, ...)
  if type(fn) ~= "function" then return end
  return scrubIfOk(pcall(fn, ...))
end

-- Opens a whisper to a crew member: the full "Name Realm" when the transport knows one, through whichever chat
-- function this game version has. Returns true when one existed.
function Util.whisper(name)
  if type(name) ~= "string" or name == "" then return false end
  local full = (ns.Transport and ns.Transport.fullName and ns.Transport.fullName(name)) or name
  if ChatFrameUtil and type(ChatFrameUtil.SendTell) == "function" then
    Util.plain(ChatFrameUtil.SendTell, full)
    return true
  end
  if type(ChatFrame_SendTell) == "function" then
    Util.plain(ChatFrame_SendTell, full)
    return true
  end
  if type(ChatFrame_OpenChat) == "function" then
    Util.plain(ChatFrame_OpenChat, "/w " .. full .. " ")
    return true
  end
  return false
end
