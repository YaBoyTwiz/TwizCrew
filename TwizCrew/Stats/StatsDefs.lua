-- Stats board: the table of stats, awards and sounds (pure data).
local _, ns = ...

ns.StatsDefs = {
  -- Every stat key, in wire order. All are sums except "ld" (a minimum), "gn" (set: the number now, the same in
  -- both views, sent even at 0) and "zv" (distinct zones, see StatsStore.addZone).
  KEYS = { "dt", "df", "dd", "dw", "db", "ld", "pl", "wp", "af", "ds", "st", "mt", "sw", "jp", "hs", "jk", "rp",
           "qa", "dl", "dv", "rz", "pt", "gn", "ml", "mg", "nj", "oj", "tf", "wd", "xg", "xt", "ch", "em", "zv", "fp" },
  MIN_KEYS = { ld = true },
  SET_KEYS = { gn = true },
  -- Keys that never make a send due (time just passing).
  TIME_KEYS = { pt = true, xt = true },
  ROAST_KINDS = { "weak", "fall", "drown", "again", "deaths", "wipe", "steps", "jumps", "quit" },
  SPELLS = {
    hearth = { names = { "Hearthstone" }, ids = { 8690 } },
    rez = {
      names = { "Resurrection", "Redemption", "Ancestral Spirit", "Rebirth" },
      ids = { 2006, 2010, 10880, 10881, 20770, 7328, 10322, 10324, 20772, 20773, 2008, 20609, 20610, 20776, 20777,
              20484, 20739, 20742, 20747, 20748 },
    },
  },
}

-- Sounds for the awards show (kit name, with the numeric id as fallback).
ns.StatsDefs.SOUNDS = {
  badge = { kit = "READY_CHECK", id = 8960 },
  reveal = { kit = "RAID_WARNING", id = 8959 },
}
ns.StatsDefs.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Every award, in show order. `key` = plain stat, or `value(stats)` -> number | nil (nil = not taking part).
-- `lowest` = the smallest value wins; `last` = shown at the end of the show.
ns.StatsDefs.AWARDS = {
  { id = "corpse", name = "Professional Corpse", key = "dt", unit = "death",
    icon = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    info = "Died the most.", joke = "Has seen more graveyards than loading screens." },
  { id = "gravity", name = "Gravity Tester", key = "df", unit = "fall",
    icon = "Interface\\Icons\\Spell_Magic_FeatherFall",
    info = "Died from falling the most.", joke = "Proved gravity works, again and again." },
  { id = "fishfood", name = "Fish Food", key = "dd", unit = "drown",
    icon = "Interface\\Icons\\Spell_Shadow_DemonBreath",
    info = "Drowned the most.", joke = "Forgot that water is not a floor." },
  { id = "weakling", name = "Died to a Weakling", key = "dw", unit = "weak",
    icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    info = "Died the most to monsters far below their own level.",
    joke = "Lost to something a few levels away from being a critter." },
  { id = "again", name = "Back for More", key = "db", unit = "again",
    icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
    info = "Died again within a minute of coming back the most.",
    joke = "The graveyard door had barely closed." },
  { id = "leeroy", name = "Leeroy", key = "pl", unit = "pull",
    icon = "Interface\\Icons\\Ability_Warrior_Charge",
    info = "Started the most fights in a dungeon before the crew was ready.",
    joke = "Who needs a plan when you have a charge button?" },
  { id = "furniture", name = "Furniture", key = "af", unit = "afk",
    icon = "Interface\\Icons\\Spell_Nature_Sleep",
    info = "Spent the most time away from the keyboard.",
    joke = "Could be mistaken for a very quiet statue." },
  { id = "marathon", name = "Marathon Runner", key = "st", unit = "steps",
    icon = "Interface\\Icons\\INV_Misc_Foot_Kodo",
    info = "Walked the most steps on foot.", joke = "Never met a mount they could not out-walk." },
  { id = "couch", name = "Couch Potato", unit = "perhour", lowest = true,
    value = function(st)
      local pt = st.pt
      if type(pt) ~= "number" or pt < ns.Config.COUCH_MIN_PLAYED then return nil end
      -- no steps at all = not taking part (Count steps off, or nothing counted): never a winner with 0
      if type(st.st) ~= "number" or st.st <= 0 then return nil end
      return st.st / (pt / 3600)
    end,
    icon = "Interface\\Icons\\INV_Misc_Fork&Knife",
    info = "Walked the fewest steps per hour (needs at least 30 minutes played).",
    joke = "Moves only when the loot window opens." },
  { id = "neverwalks", name = "Never Walks", unit = "ratio",
    value = function(st)
      local mt, yards = st.mt or 0, (st.st or 0) / ns.Config.STEPS_PER_YARD
      if mt + yards < ns.Config.NEVERWALKS_MIN_YARDS then return nil end
      return mt / math.max(yards, 1)
    end,
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    info = "Rode a mount far more than walked (needs at least 1,000 yards travelled).",
    joke = "Their own two feet are mostly decoration." },
  { id = "fish", name = "Fish", key = "sw", unit = "yards",
    icon = "Interface\\Icons\\INV_Misc_Fish_02",
    info = "Swam the most yards.", joke = "Was probably a murloc in a past life." },
  { id = "bunny", name = "Bunny Hopper", key = "jp", unit = "jumps",
    icon = "Interface\\Icons\\Ability_Rogue_Sprint",
    info = "Jumped the most times.", joke = "The space bar is worn smooth." },
  { id = "homesick", name = "Homesick", key = "hs", unit = "hearths",
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    info = "Used the Hearthstone the most.", joke = "Always one step away from the inn." },
  { id = "trash", name = "Trash Collector", key = "jk", unit = "junk",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    info = "Picked up the most gray junk items.", joke = "Bags full of treasures nobody wants." },
  { id = "broke", name = "Broke", key = "rp", unit = "money",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    info = "Paid the most for repairs.", joke = "The repair bot sends a thank-you card." },
  { id = "quitter", name = "Quitter", key = "qa", unit = "quests",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    info = "Abandoned the most quests.", joke = "The quest log is a list of good intentions." },
  { id = "duel", name = "Duel Loser", key = "dl", unit = "duels",
    icon = "Interface\\Icons\\INV_Sword_04",
    info = "Lost the most duels.", joke = "Will definitely win the next one." },
  { id = "medic", name = "Medic", key = "rz", unit = "rezzes", last = true,
    icon = "Interface\\Icons\\Spell_Holy_Resurrection",
    info = "Brought the most people back to life.", joke = "The crew's favorite sight after a wipe." },
}
