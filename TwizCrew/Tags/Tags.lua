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

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end

-- Your own tags as a set. Never includes LAYER: that one is worked out per friend by the layer module.
function Tags.detectSelf()
  local set = {}
  if try(UnitIsDeadOrGhost, "player") then set.DEAD = true end
  if try(UnitAffectingCombat, "player") then set.COMBAT = true end
  local _, kind = try(IsInInstance)
  if kind == "party" or kind == "raid" then set.DUNGEON = true end
  if try(UnitOnTaxi, "player") then set.TAXI = true end
  if try(UnitIsAFK, "player") then set.AFK = true end
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
})
