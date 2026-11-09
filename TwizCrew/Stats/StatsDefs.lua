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
  -- Red error texts, by the game's own global names (their text is read at start; a missing name is skipped).
  ERRORS = {
    oj = { "ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_FOCUS" },
    tf = { "ERR_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE", "ERR_USE_TOO_FAR" },
  },
}

-- Sounds for the awards show (kit name, with the numeric id as fallback).
ns.StatsDefs.SOUNDS = {
  badge = { kit = "READY_CHECK", id = 8960 },
  reveal = { kit = "RAID_WARNING", id = 8959 },
}
ns.StatsDefs.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The Hall of Shame's tabs, in order (owner: "Category tabs"). label = the short button text (five must fit in the
-- 320 px board); name = the full name, shown at the start of the subtitle.
ns.StatsDefs.TABS = {
  { id = "deaths", label = "Deaths", name = "Deaths" },
  { id = "move", label = "Moving", name = "On the Move" },
  { id = "loot", label = "Money", name = "Money & Loot" },
  { id = "oops", label = "Oops", name = "Butterfingers" },
  { id = "lazy", label = "Lazy", name = "Lazy & Loud" },
}

-- Every award, tab by tab (TABS order), in show order. `key` = plain stat, or `value(stats)` -> number | nil (nil =
-- not taking part). `lowest` = the smallest value wins; `last` = shown at the end of the show.
ns.StatsDefs.AWARDS = {
  -- Deaths
  { id = "corpse", tab = "deaths", name = "Professional Corpse", key = "dt", unit = "death",
    icon = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    info = "Died the most.", joke = "Has seen more graveyards than loading screens." },
  { id = "gravity", tab = "deaths", name = "Gravity Tester", key = "df", unit = "fall",
    icon = "Interface\\Icons\\Spell_Magic_FeatherFall",
    info = "Died from falling the most.", joke = "Proved gravity works, again and again." },
  { id = "fishfood", tab = "deaths", name = "Fish Food", key = "dd", unit = "drown",
    icon = "Interface\\Icons\\Spell_Shadow_DemonBreath",
    info = "Drowned the most.", joke = "Forgot that water is not a floor." },
  { id = "weakling", tab = "deaths", name = "Died to a Weakling", key = "dw", unit = "weak",
    icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    info = "Died the most to monsters far below their own level.",
    joke = "Lost to something a few levels away from being a critter." },
  { id = "again", tab = "deaths", name = "Back for More", key = "db", unit = "again",
    icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
    info = "Died again within a minute of coming back the most.",
    joke = "The graveyard door had barely closed." },
  { id = "leeroy", tab = "deaths", name = "Leeroy", key = "pl", unit = "pull",
    icon = "Interface\\Icons\\Ability_Warrior_Charge",
    info = "Started the most fights in a dungeon before the crew was ready.",
    joke = "Who needs a plan when you have a charge button?" },
  -- On the Move
  { id = "marathon", tab = "move", name = "Marathon Runner", key = "st", unit = "steps",
    icon = "Interface\\Icons\\INV_Misc_Foot_Kodo",
    info = "Walked the most steps on foot.", joke = "Never met a mount they could not out-walk." },
  { id = "couch", tab = "move", name = "Couch Potato", unit = "perhour", lowest = true,
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
  { id = "neverwalks", tab = "move", name = "Never Walks", unit = "ratio",
    value = function(st)
      local mt, yards = st.mt or 0, (st.st or 0) / ns.Config.STEPS_PER_YARD
      if mt + yards < ns.Config.NEVERWALKS_MIN_YARDS then return nil end
      return mt / math.max(yards, 1)
    end,
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    info = "Rode a mount far more than walked (needs at least 1,000 yards travelled).",
    joke = "Their own two feet are mostly decoration." },
  { id = "fish", tab = "move", name = "Fish", key = "sw", unit = "yards",
    icon = "Interface\\Icons\\INV_Misc_Fish_02",
    info = "Swam the most yards.", joke = "Was probably a murloc in a past life." },
  { id = "bunny", tab = "move", name = "Bunny Hopper", key = "jp", unit = "jumps",
    icon = "Interface\\Icons\\Ability_Rogue_Sprint",
    info = "Jumped the most times.", joke = "The space bar is worn smooth." },
  { id = "tourist", tab = "move", name = "Tourist", key = "zv", unit = "zones", -- new
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    info = "Visited the most different zones.", joke = "Has a postcard from every zone and a quest done in none." },
  { id = "flyer", tab = "move", name = "Frequent Flyer", key = "fp", unit = "flights", -- new
    icon = "Interface\\Icons\\Ability_Hunter_EagleEye",
    info = "Took the most flight paths.", joke = "The flight master knows their coffee order." },
  -- Money & Loot
  { id = "pauper", tab = "loot", name = "Pauper", key = "gn", unit = "money", lowest = true, -- new
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    info = "Carries the least gold right now.", joke = "Checks the couch cushions for copper." },
  { id = "moneypit", tab = "loot", name = "Money Pit", unit = "money", -- new
    value = function(st)
      local lost = (type(st.ml) == "number" and st.ml or 0) - (type(st.mg) == "number" and st.mg or 0)
      if lost <= 0 then return nil end
      return lost
    end,
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    info = "Lost the most gold (spent more than they made).", joke = "Gold goes in. Gold does not come out." },
  { id = "broke", tab = "loot", name = "Broke", key = "rp", unit = "money",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    info = "Paid the most for repairs.", joke = "The repair bot sends a thank-you card." },
  { id = "trash", tab = "loot", name = "Trash Collector", key = "jk", unit = "junk",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    info = "Picked up the most gray junk items.", joke = "Bags full of treasures nobody wants." },
  { id = "ninja", tab = "loot", name = "Ninja", key = "nj", unit = "needs", -- new
    icon = "Interface\\Icons\\Ability_Stealth",
    info = "Won the most Need rolls in a group.", joke = "Needed it. For an alt. Probably." },
  -- Butterfingers
  { id = "juice", tab = "oops", name = "Out of Juice", key = "oj", unit = "nojuice", -- new
    icon = "Interface\\Icons\\INV_Potion_76",
    info = "Tried to use a spell without enough mana, rage or energy the most.",
    joke = "Runs on fumes and good intentions." },
  { id = "toofar", tab = "oops", name = "Too Far Away", key = "tf", unit = "toofar", -- new
    icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    info = "Got \"Out of range\" or \"You are too far away\" the most.", joke = "Measures distance in hopes." },
  { id = "wanderer", tab = "oops", name = "Wanderer", key = "wd", unit = "wanders", -- new
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    info = "Ran off from a group member the most.", joke = "Was right behind you. Then wasn't." },
  { id = "quitter", tab = "oops", name = "Quitter", key = "qa", unit = "quests",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    info = "Abandoned the most quests.", joke = "The quest log is a list of good intentions." },
  { id = "duel", tab = "oops", name = "Duel Loser", key = "dl", unit = "duels",
    icon = "Interface\\Icons\\INV_Sword_04",
    info = "Lost the most duels.", joke = "Will definitely win the next one." },
  { id = "homesick", tab = "oops", name = "Homesick", key = "hs", unit = "hearths",
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    info = "Used the Hearthstone the most.", joke = "Always one step away from the inn." },
  -- Lazy & Loud
  { id = "chatter", tab = "lazy", name = "Chatterbox", key = "ch", unit = "messages", -- new
    icon = "Interface\\Icons\\Spell_Holy_Silence",
    info = "Sent the most party and raid chat messages (only the count is kept).",
    joke = "Types faster than they pull." },
  { id = "emotes", tab = "lazy", name = "Emote Spammer", key = "em", unit = "emotes", -- new
    icon = "Interface\\Icons\\Spell_Shadow_SoothingKiss",
    info = "Used the most emotes, like /dance and /lol.", joke = "Has a /dance for every occasion." },
  { id = "furniture", tab = "lazy", name = "Furniture", key = "af", unit = "afk",
    icon = "Interface\\Icons\\Spell_Nature_Sleep",
    info = "Spent the most time away from the keyboard.",
    joke = "Could be mistaken for a very quiet statue." },
  { id = "snail", tab = "lazy", name = "Snail", unit = "xpperhour", lowest = true, -- new
    value = function(st)
      local xt = st.xt
      if type(xt) ~= "number" or xt < ns.Config.COUCH_MIN_PLAYED then return nil end
      return (type(st.xg) == "number" and st.xg or 0) / (xt / 3600)
    end,
    icon = "Interface\\Icons\\Spell_Nature_Slow",
    info = "Gained the least XP per hour (needs at least 30 minutes played below max level).",
    joke = "Levels at the speed of continental drift." },
  { id = "medic", tab = "lazy", name = "Medic", key = "rz", unit = "rezzes", last = true,
    icon = "Interface\\Icons\\Spell_Holy_Resurrection",
    info = "Brought the most people back to life.", joke = "The crew's favorite sight after a wipe." },
}
