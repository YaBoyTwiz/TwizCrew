-- Shared helpers for the server-side storage probes (/tc caltest, /tc chattest): test tools only, they change no
-- addon behaviour. Every line goes to chat and to the saved log (ns.Log, saved in TwizCrewDB), so the results can be
-- read from the SavedVariables file afterwards. Every game call is guarded: the function may be missing on this game
-- version, may raise, and may give secret values (never compared or joined to text).
local _, ns = ...

local Probes = {}
ns.Probes = Probes

local isSecret = ns.Util.isSecret

-- say(text): one line to chat and the same line to the saved log, tagged with the probe's name.
function Probes.sayer(tag)
  return function(text)
    text = tostring(text)
    print("TwizCrew: " .. ns.Util.safeText(text))
    ns.Log.add("info", "%s: %s", tag, text)
  end
end

-- The function t[name] when t is a table and it is a function; nil otherwise.
function Probes.fn(t, name)
  if type(t) ~= "table" then return nil end
  local ok, f = pcall(function() return t[name] end)
  if ok and type(f) == "function" then return f end
end

local function scrubbed(ok, ...)
  if not ok then return false, ns.Util.safeText(tostring((...))) end
  local n = select("#", ...)
  local out = {}
  for i = 1, n do
    local v = select(i, ...)
    if isSecret(v) then v = nil end
    out[i] = v
  end
  return true, unpack(out, 1, n)
end

-- Calls fn(...) safely: true, results (secret ones as nil) ... or false, the error as text. A missing function is
-- false, "missing".
function Probes.try(fn, ...)
  if type(fn) ~= "function" then return false, "missing" end
  return scrubbed(pcall(fn, ...))
end

-- A field of a game table, nil when the table is not a table, the read raises or the value is secret.
function Probes.field(t, k)
  if type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

-- A game value as text for a chat line: "hidden" for a secret, "none" for nil.
function Probes.text(v)
  if isSecret(v) then return "hidden" end
  if v == nil then return "none" end
  return tostring(v)
end

-- "yes" / "no" / "unknown" for a yes-or-no from the game.
function Probes.yesNo(v)
  if v == true then return "yes" elseif v == false then return "no" end
  return "unknown"
end

-- Text cut to at most maxChars letters and maxBytes bytes, never inside a letter.
function Probes.cut(s, maxChars, maxBytes)
  local whole = tostring(s or "")
  local out = ns.Util.truncateUTF8(whole, maxChars)
  while maxBytes and #out > maxBytes and maxChars > 0 do
    maxChars = maxChars - 1
    out = ns.Util.truncateUTF8(whole, maxChars)
  end
  return out
end

-- The character's name as text ("Yaboytwiz"), "Someone" when the game does not give it.
function Probes.myName()
  local name = ns.Util.plain(UnitName, "player")
  if type(name) ~= "string" or name == "" then return "Someone" end
  return name
end

-- The time of day as "21:04:33", or "" when the game gives no clock.
function Probes.clock()
  local ok, text = Probes.try(date, "%H:%M:%S")
  if ok and type(text) == "string" then return text end
  return ""
end

-- Waits for one of `events` (or the timeout, in seconds): onDone(event, ...) once, with event nil on timeout. filter
-- (optional) is filter(event, ...) -> true for the events that count. Returns a cancel function.
function Probes.wait(events, timeout, onDone, filter, featureId)
  local done = false
  local frame = CreateFrame("Frame")
  local function finish(event, ...)
    if done then return end
    done = true
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    onDone(event, ...)
  end
  for _, e in ipairs(events) do pcall(frame.RegisterEvent, frame, e) end
  frame:SetScript("OnEvent", function(_, event, ...)
    local args = { n = select("#", ...), ... }
    ns.Log.safe(featureId or "probes", function()
      if filter and not filter(event, unpack(args, 1, args.n)) then return end
      finish(event, unpack(args, 1, args.n))
    end)
  end)
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(timeout, function() ns.Log.safe(featureId or "probes", finish, nil) end)
  end
  return function() finish("cancelled") end
end

-- A small window in the middle of the screen with one button (a click is the player's own action, which restricted
-- game calls need) and a Close button. One window per key; showing it again replaces the button's action.
local windows = {}
function Probes.button(key, label, onClick, featureId)
  local w = windows[key]
  if not w then
    w = ns.Theme.frame("Frame", nil, UIParent)
    w:SetSize(220, 70)
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    w:SetFrameStrata("DIALOG")
    ns.Theme.skin(w, "window", { alpha = 0.98 }) -- the theme's frame (UI/Skin.lua)
    w.title = ns.Theme.text(w, ns.Theme.FONT.small, ns.Theme.COLOR.white)
    w.title:SetPoint("TOP", w, "TOP", 0, -8)
    w.title:SetText("TwizCrew test")
    w.go = ns.Widgets.button(w, label, function() if w.action then w.action() end end, nil, featureId)
    w.go:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 10, 10)
    w.close = ns.Widgets.button(w, "Close", function() w:Hide() end, nil, featureId)
    w.close:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -10, 10)
    windows[key] = w
  end
  w.action = function()
    w:Hide()
    onClick()
  end
  w:Show()
  return w
end

Probes.forTest = { window = function(key) return windows[key] end }
