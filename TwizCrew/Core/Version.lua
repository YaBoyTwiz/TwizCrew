-- Version check: tells you when a friend runs a newer TwizCrew than you.
local ADDON, ns = ...

local Version = {}
ns.Version = Version

local best          -- { name =, ver = } the newest version seen so far (newer than ours)
local plain         -- { name =, ver =, rs = } the same, plain numbers only (feeds the update notice)
local announced = false

local function line(entry)
  return ns.Util.safeText(entry.name) .. " has v" .. ns.Util.safeText(entry.ver)
    .. ", you have v" .. ns.VERSION .. ". Update in WowUp."
end

-- The update notice only trusts plain versions ("0.2.0"), kept apart from `best` so a junk version from a broken
-- copy cannot hide a real one. rs = that copy's RESTART_SINCE (nil = unknown: older copies do not send it).
local function notePlain(name, ver, rs)
  if not ns.Util.isVersion(ver) then return end
  if not ns.Util.isVersion(rs) then rs = nil end
  if plain then
    local c = ns.Util.compareVersions(ver, plain.ver)
    if c < 0 then return end
    if c == 0 then
      if plain.rs or not rs then return end
      plain.rs = rs -- learned later (another piece, another friend on the same version)
    else
      plain = { name = name, ver = ver, rs = rs }
    end
  else
    plain = { name = name, ver = ver, rs = rs }
  end
  ns.Bus.fire("UPDATE_SEEN", plain.name, plain.ver, plain.rs)
end

-- Called by Crew for every crew message that carries a version. Tolerates junk.
function Version.seen(name, ver, rs)
  if type(name) ~= "string" or name == "" or type(ver) ~= "string" or ver == "" then return end
  if ns.Util.compareVersions(ver, ns.VERSION) <= 0 then return end
  notePlain(name, ver, rs)
  if best and ns.Util.compareVersions(ver, best.ver) <= 0 then return end
  best = { name = name, ver = ver }
  ns.Bus.fire("VERSION_NEWER", name, ver)
  if not announced then
    announced = true
    if ns.Modules.setting("version", "chatNotice") then print("TwizCrew: " .. line(best)) end
  end
end

-- A copy of { name, ver, rs } for the newest plain version newer than ours, or nil.
function Version.newest()
  if not plain then return nil end
  return { name = plain.name, ver = plain.ver, rs = plain.rs }
end

function Version.summary()
  if not best then return "everyone up to date" end
  return line(best)
end

-- The game's ready-check icons: the default font has no tick or cross letters.
local ICON = {
  ok = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t",
  old = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t",
  unknown = "   ", -- about as wide as an icon, so the names line up
}

-- One line per crew member for the settings window: tick (up to date), cross (older) or "?" (offline, unknown).
function Version.lines()
  local members = ns.roster and ns.roster:members() or {}
  local out = {}
  for i, row in ipairs(ns.UpdateLogic.versionRows(ns.playerName(), ns.VERSION, members)) do
    local name = ns.Util.safeText(row.name) .. (row.me and " (you)" or "")
    local ver = row.version == "?" and "?" or ("v" .. ns.Util.safeText(row.version))
    out[i] = (ICON[row.mark] or ICON.unknown) .. " " .. name .. "  " .. ver
  end
  return out
end

ns.Modules.register({
  id = "version", name = "Version check", tier = "essential",
  info = "Notices when a friend has a newer version of TwizCrew than you.",
  defaults = { chatNotice = true },
  settings = {
    { key = "chatNotice", label = "Tell me in chat", kind = "toggle",
      info = "Tells you in chat when a friend has a newer version of TwizCrew." },
    { key = "tellCrew", label = "Tell crew to update", kind = "button",
      info = "Press this after you updated TwizCrew yourself. Friends online who have an older version get a "
        .. "small window with a Reload button, so they load the new version (unless they turned off Update "
        .. "reminders, or their copy is too old to know this button). They still need to update in WowUp first. "
        .. "You can press it again after 30 seconds.",
      onClick = function() ns.Updates.tellCrew() end },
    { key = "versions", label = "Crew versions", kind = "list",
      info = "Which TwizCrew version each friend runs. A green tick means up to date (the newest version seen), "
        .. "a red cross means older: they should update in WowUp. A ? means offline or not known yet.",
      lines = function() return Version.lines() end },
  },
})
