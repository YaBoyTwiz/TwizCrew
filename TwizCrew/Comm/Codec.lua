-- Message codec (pure, no WoW API).
-- Format: <protocol>^<TYPE>^<k>=<v>~<k>=<v>...   Separators inside keys/values are %-escaped.
local _, ns = ...

local Codec = {}
ns.Codec = Codec

local KNOWN_TYPES = { HELLO = true, STATE = true, UPDATE = true, PING = true, BYE = true }

local ESCAPE = { ["%"] = "%25", ["^"] = "%5E", ["~"] = "%7E", ["="] = "%3D" }
local UNESCAPE = { ["25"] = "%", ["5E"] = "^", ["7E"] = "~", ["3D"] = "=" }

local function escape(s)
  return (string.gsub(s, "[%%%^~=]", ESCAPE))
end

-- Unknown or broken %XY sequences are kept literally.
local function unescape(s)
  return (string.gsub(s, "%%(%x%x)", function(code) return UNESCAPE[string.upper(code)] end))
end

local function header(msgType)
  return ns.Config.PROTOCOL .. "^" .. msgType .. "^"
end

-- Largest escaped "k=v" that fits in `room` bytes, cutting v on whole letters; nil if even "k=" does not fit.
local function fitEntry(ek, value, room)
  local prefix = ek .. "="
  if #prefix > room then return nil end
  local full = prefix .. escape(value)
  if #full <= room then return full end
  local lo, hi = 0, #value -- chars <= bytes; find the most characters that fit
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if #prefix + #escape(ns.Util.truncateUTF8(value, mid)) <= room then lo = mid else hi = mid - 1 end
  end
  return prefix .. escape(ns.Util.truncateUTF8(value, lo))
end

function Codec.encode(msgType, fields)
  local max = ns.Config.MAX_MESSAGE
  local keys = {}
  for k in pairs(fields or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  local out, curType, cur = {}, msgType, nil -- cur: string of entries in the open chunk
  for _, k in ipairs(keys) do
    local ek, value = escape(tostring(k)), tostring(fields[k])
    local entry = fitEntry(ek, value, max - #header(curType))
    if entry then
      local entryFull = ek .. "=" .. escape(value)
      if cur and #header(curType) + #cur + 1 + #entryFull <= max then
        cur = cur .. "~" .. entryFull
      else
        if cur then
          out[#out + 1] = header(curType) .. cur
          curType = "UPDATE"
        end
        cur = fitEntry(ek, value, max - #header(curType))
      end
    end
  end
  out[#out + 1] = header(curType) .. (cur or "")
  return out
end

function Codec.decode(text)
  if type(text) ~= "string" or text == "" then return nil, "empty" end
  local parts = ns.Util.split(text, "^")
  if #parts < 2 then return nil, "no separator" end
  if not string.find(parts[1], "^%d+$") then return nil, "bad protocol" end
  local protocol = tonumber(parts[1])
  local msgType = parts[2]
  if not KNOWN_TYPES[msgType] then return nil, "unknown type" end

  local fields = {}
  local body = parts[3] or ""
  if body ~= "" then
    for _, piece in ipairs(ns.Util.split(body, "~")) do
      local eq = string.find(piece, "=", 1, true)
      if eq and eq > 1 then
        fields[unescape(string.sub(piece, 1, eq - 1))] = unescape(string.sub(piece, eq + 1))
      end
    end
  end
  return { protocol = protocol, type = msgType, fields = fields }
end
