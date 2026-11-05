-- Stats board: the table of stats (pure data). Awards and sounds are added with the awards rules.
local _, ns = ...

ns.StatsDefs = {
  -- Every stat key, in wire order. All are sums except "ld" (a minimum).
  KEYS = { "dt", "df", "dd", "dw", "db", "ld", "pl", "wp", "af", "ds", "st", "mt", "sw", "jp", "hs", "jk", "rp",
           "qa", "dl", "dv", "rz", "pt" },
  MIN_KEYS = { ld = true },
  -- Keys that never make a send due (time just passing).
  TIME_KEYS = { pt = true },
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
