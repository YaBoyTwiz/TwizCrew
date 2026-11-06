-- Pure rules of "Tell crew to update" (no WoW API): who is listened to, restart or reload, the words shown,
-- the line after a reload and the version list.
local _, ns = ...

local UpdateLogic = {}
ns.UpdateLogic = UpdateLogic

local function cmp(a, b) return ns.Util.compareVersions(a, b) end
local isVersion = function(v) return ns.Util.isVersion(v) end

-- req = { sender, ver, rs }; c = { myVersion, enabled, isCrew, shown = { [ver] = time shown }, now, repeatGap }
-- Returns true, or false and the reason (for the log).
function UpdateLogic.accept(req, c)
  if type(req) ~= "table" or type(req.sender) ~= "string" or req.sender == "" or not c.isCrew then
    return false, "not crew"
  end
  if not isVersion(req.ver) then return false, "bad version" end
  if cmp(req.ver, c.myVersion) <= 0 then return false, "not newer" end
  if not c.enabled then return false, "off" end
  local last = c.shown and c.shown[req.ver]
  if type(last) == "number" and c.now - last < c.repeatGap then return false, "repeat" end
  return true
end

-- Older than the sender's RESTART_SINCE: the new version added files, a /reload is not enough.
function UpdateLogic.needsRestart(myVersion, rs)
  return isVersion(rs) and cmp(myVersion, rs) < 0
end

function UpdateLogic.prompt(name, ver, restart)
  return {
    title = name .. " says v" .. ver .. " is out",
    note = restart and "Close and restart the game to load it"
      or "If nothing changed, open WowUp and click Update first",
    reload = not restart,
  }
end

-- Lines for chat after a login or /reload. saved = db.update ({ told, rs }); tocVersion = what the game's addon
-- list says; restartSince = our own RESTART_SINCE.
function UpdateLogic.afterLogin(myVersion, saved, tocVersion, restartSince)
  local out = {}
  if type(saved) == "table" and isVersion(saved.told) and cmp(myVersion, saved.told) < 0 then
    local how = UpdateLogic.needsRestart(myVersion, saved.rs) and "restart the game" or "/reload"
    out[#out + 1] = "Still on v" .. myVersion .. ". Open WowUp, click Update, then " .. how
  end
  -- The game kept the old .toc (file list) but loaded our new code: files added since then did not load.
  if isVersion(tocVersion) and isVersion(restartSince) and cmp(tocVersion, restartSince) < 0 then
    out[#out + 1] = "TwizCrew v" .. myVersion .. " added new files. Close and restart the game to finish the update."
  end
  return out
end

local function knownVersion(m)
  if m.online and isVersion(m.version) then return m.version end
  return nil
end

-- One row per crew member, me first, then online friends A-Z, then offline ones. mark: "ok" (same as or newer
-- than the newest version seen), "old", "unknown" (offline or not known: shown as "?").
function UpdateLogic.versionRows(myName, myVersion, members)
  local newest = myVersion
  for _, m in ipairs(members) do
    if isVersion(m.version) and cmp(m.version, newest) > 0 then newest = m.version end
  end
  local function mark(v)
    if not v then return "unknown" end
    return cmp(v, newest) >= 0 and "ok" or "old"
  end
  local others = {}
  for _, m in ipairs(members) do others[#others + 1] = m end
  table.sort(others, function(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
    local la, lb = string.lower(a.name), string.lower(b.name)
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  local rows = { { name = myName, me = true, version = myVersion, mark = mark(myVersion) } }
  for _, m in ipairs(others) do
    local v = knownVersion(m)
    rows[#rows + 1] = { name = m.name, version = v or "?", mark = mark(v) }
  end
  return rows
end

-- How many online friends are known to run an older version than mine.
function UpdateLogic.behind(myVersion, members)
  local n = 0
  for _, m in ipairs(members) do
    local v = knownVersion(m)
    if v and cmp(v, myVersion) < 0 then n = n + 1 end
  end
  return n
end

-- Whole seconds until the button can be pressed again (0 = now).
function UpdateLogic.cooldownLeft(lastPress, now, cooldown)
  if type(lastPress) ~= "number" then return 0 end
  local left = lastPress + cooldown - now
  if left <= 0 then return 0 end
  return math.ceil(left)
end

---------------------------------------------------------------------------------------------------- update notice
-- The newest version heard ({ name, ver, rs }) when it is newer than mine and Update reminders is on, else nil.
function UpdateLogic.available(myVersion, newest, enabled)
  if not enabled or type(newest) ~= "table" or not isVersion(newest.ver) then return nil end
  if cmp(newest.ver, myVersion) <= 0 then return nil end
  return newest
end

-- "Update available: v0.2.0", with withName "... (Frostie has it)". nil when there is no update.
function UpdateLogic.availableText(newest, withName)
  if type(newest) ~= "table" or type(newest.ver) ~= "string" then return nil end
  local text = "Update available: v" .. newest.ver
  if withName and type(newest.name) == "string" then text = text .. " (" .. newest.name .. " has it)" end
  return text
end

-- Should the notice pop-up show for `newest`? c = { myVersion, enabled, shown = newest version a pop-up was shown
-- for (saved), open = version of the window open or waiting }. Returns true, or false and the reason (for the log).
function UpdateLogic.showNotice(newest, c)
  if type(newest) ~= "table" or not isVersion(newest.ver) then return false, "none" end
  if cmp(newest.ver, c.myVersion) <= 0 then return false, "not newer" end
  if not c.enabled then return false, "off" end
  if isVersion(c.shown) and cmp(newest.ver, c.shown) <= 0 then return false, "already shown" end
  if isVersion(c.open) and cmp(newest.ver, c.open) <= 0 then return false, "window open" end
  return true
end

-- Older copies send no rs: count it as "restart since that version", so we say restart to be safe.
function UpdateLogic.safeRestartSince(rs, ver)
  if isVersion(rs) then return rs end
  return ver
end

-- The notice window's words. name and ver must already be safe to show.
function UpdateLogic.notice(name, ver, myVersion, rs)
  local restart = UpdateLogic.needsRestart(myVersion, UpdateLogic.safeRestartSince(rs, ver))
  local how = restart and "Close WoW, open WowUp and click Update, then start WoW again."
    or "Open WowUp and click Update, then press Reload now."
  return { title = "Update available: v" .. ver, note = name .. " has it. " .. how, reload = not restart }
end
