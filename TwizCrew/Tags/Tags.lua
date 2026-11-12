-- Activity tags: ids, labels, colors, detection of your own tags, wire encoding. Registers the module "tags".
-- The tags module itself is display only (the panel shows the pills); detection and sharing always run.
local _, ns = ...

local Tags = {}
ns.Tags = Tags

Tags.ORDER = { "DEAD", "LAYER", "COMBAT", "DUNGEON", "TAXI", "AFK" }

Tags.LABEL = {
  DEAD = "DEAD", LAYER = "OTHER LAYER", COMBAT = "FIGHTING", DUNGEON = "DUNGEON", TAXI = "FLYING", AFK = "AFK",
}

Tags.COLOR = {
  LAYER = "b3261e", COMBAT = "c46a00", DEAD = "555555", DUNGEON = "2a4fc9", TAXI = "1f7a6a", AFK = "333333",
}

-- Game icons shown on each pill (built into the client, nothing to download).
Tags.ICON = {
  DEAD = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  LAYER = "Interface\\Icons\\Spell_Arcane_PortalStormWind",
  COMBAT = "Interface\\Icons\\Ability_DualWield",
  DUNGEON = "Interface\\Icons\\INV_Misc_Key_03",
  TAXI = "Interface\\Icons\\Ability_Mount_Wyvern_01",
  AFK = "Interface\\Icons\\Spell_Nature_Sleep",
}

Tags.INFO = {
  DEAD = "This player is dead or a ghost.",
  LAYER = "This player is on a different copy of the world than you, so you cannot see each other.",
  COMBAT = "This player is in a fight right now.",
  DUNGEON = "This player is inside a dungeon or raid.",
  TAXI = "This player is riding a flight path.",
  AFK = "This player has marked themselves as away from the keyboard.",
}

-- In dungeons the game hides "AFK?", "dead?", "fighting?" behind secret values, and even testing one is an error (it
-- turned the Crew panel off mid-dungeon, 2026-11-08), so a secret answer counts as "don't know" (plain gives nil).
local plain = ns.Util.plain

------------------------------------------------------------------------------------------------------------- away
-- You count as away (the AFK tag and a "zzz" on your portrait in friends' panels) when the game says so (/afk, or its own idle
-- timer), when you have done nothing for a few minutes (setting "awayMinutes"), or after the AFK button / "/tc afk"
-- until you play again. TwizCrew never sets the game's own AFK flag: the button only tells the crew.
local Away = {}
ns.Away = Away

-- Things that mean "I'm playing". "soft" ones (mouse moved, camera turned) end idle time but not a chosen AFK:
-- clicking the AFK button moves the mouse too.
local HARD_EVENTS = { "PLAYER_STARTED_MOVING", "UNIT_SPELLCAST_SENT", "PLAYER_TARGET_CHANGED",
  "PLAYER_REGEN_DISABLED", "LOOT_OPENED", "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_DETAIL" }
local lastActive, chosen, idle = nil, false, false
local lastCursor, lastFacing
local started = false

local function readable(v)
  return v ~= nil and not ns.Util.isSecret(v)
end

local function changed(reason)
  if ns.Self then ns.Self.refresh(reason) end
  ns.Bus.fire("AWAY_CHANGED", Away.isAway())
end

function Away.active(soft)
  lastActive = ns.now()
  local was = Away.isAway()
  if not soft then chosen = false end
  idle = false
  if was ~= Away.isAway() then changed("back") end
end

function Away.isAway()
  return chosen or idle or (plain(UnitIsAFK, "player") and true or false)
end

-- The AFK button and "/tc afk": go away, or come back. Returns true when you are away afterwards (the game's own
-- /afk keeps you away until the game clears it).
function Away.toggle()
  if Away.isAway() then
    chosen, idle, lastActive = false, false, ns.now()
    changed("back")
    return Away.isAway()
  end
  chosen = true
  changed("away")
  return true
end

function Away.gameAFK() return plain(UnitIsAFK, "player") and true or false end

local function look()
  -- the mouse moving or the camera turning counts as being here
  local x, y = plain(GetCursorPosition)
  if readable(x) and readable(y) then
    local key = math.floor(x) .. "," .. math.floor(y)
    if lastCursor and key ~= lastCursor then Away.active(true) end
    lastCursor = key
  end
  local facing = plain(GetPlayerFacing)
  if readable(facing) and type(facing) == "number" then
    if lastFacing and math.abs(facing - lastFacing) > 0.01 then Away.active(true) end
    lastFacing = facing
  end
  local minutes = tonumber(ns.Modules.setting("tags", "awayMinutes")) or 3
  if ns.Modules.setting("tags", "autoAway") ~= false and not idle and lastActive
    and ns.now() - lastActive >= minutes * 60 then
    idle = true
    changed("idle")
  end
end

function Away.start()
  if started then return end
  started = true
  lastActive = ns.now()
  for _, event in ipairs(HARD_EVENTS) do
    ns.Events.on("away", event, function(unit)
      if event == "UNIT_SPELLCAST_SENT" and unit ~= "player" then return end
      Away.active(false)
    end)
  end
  ns.Events.on("away", "PLAYER_FLAGS_CHANGED", function() ns.Bus.fire("AWAY_CHANGED", Away.isAway()) end)
  C_Timer.NewTicker(2, function() ns.Log.safe("away", look) end)
end

-- Your own tags as a set. Never includes LAYER: that one is worked out per friend by the layer module.
function Tags.detectSelf()
  local set = {}
  if plain(UnitIsDeadOrGhost, "player") then set.DEAD = true end
  if plain(UnitAffectingCombat, "player") then set.COMBAT = true end
  local _, kind = plain(IsInInstance)
  if kind == "party" or kind == "raid" then set.DUNGEON = true end
  if plain(UnitOnTaxi, "player") then set.TAXI = true end
  if Away.isAway() then set.AFK = true end
  return set
end

function Tags.ordered(set)
  local list = {}
  if type(set) ~= "table" then return list end
  for _, id in ipairs(Tags.ORDER) do
    if set[id] then list[#list + 1] = id end
  end
  return list
end

function Tags.encode(set)
  return table.concat(Tags.ordered(set), ",")
end

function Tags.decode(str)
  local set = {}
  if type(str) ~= "string" then return set end
  for id in string.gmatch(str, "[^,]+") do
    if Tags.LABEL[id] then set[id] = true end
  end
  return set
end

ns.Modules.register({
  id = "tags", name = "Activity tags", tier = "module",
  info = "Shows small colored labels next to your friends: dead, fighting, in a dungeon, flying, away, or on another layer.",
  defaults = { autoAway = true, awayMinutes = 3 },
  settings = {
    { key = "autoAway", label = "Show me as away when idle", kind = "toggle",
      info = "Your friends see AFK next to your name when you haven't moved, cast, targeted or touched the mouse "
        .. "for a few minutes. It goes away as soon as you do something." },
    { key = "awayMinutes", label = "Minutes before away", kind = "slider", min = 1, max = 15, step = 1,
      parent = "autoAway", fmt = function(v) return tostring(math.floor(v + 0.5)) .. " min" end,
      info = "How long you can do nothing before you show as away." },
  },
})
