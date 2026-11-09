-- Namespace basics: addon name, version, tunable values, clocks, player name.
local ADDON, ns = ...

ns.ADDON = ADDON

-- Release maker: bump ADDON_VERSION for every release, together with "## Version" in TwizCrew.toc (a test checks
-- they match). Set RESTART_SINCE to the new version when a release adds or removes files or changes the .toc in any
-- other way (the game reads those only when it starts): older copies are then told to restart the game, not reload.
-- The version is kept here and not read from the .toc, because the game may keep the old .toc after a /reload.
local ADDON_VERSION = "0.1.23"
local RESTART_SINCE = "0.1.23"

ns.VERSION = ADDON_VERSION
ns.RESTART_SINCE = RESTART_SINCE

do -- what the game's addon list says (may be the old .toc after a /reload; shown in /tc report)
  local version
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  elseif type(GetAddOnMetadata) == "function" then
    version = GetAddOnMetadata(ADDON, "Version")
  end
  if type(version) == "string" and version ~= "" then ns.TOC_VERSION = version end
end

-- The one place for tunable values.
ns.Config = {
  PREFIX = "TwizCrew", PROTOCOL = 1,
  DEFAULT_CHANNEL = "TwizCrewHQ", DEFAULT_PASSWORD = "goldshire",
  CHANNEL_JOIN_DELAY = 5, CHANNEL_JOIN_TIMEOUT = 10, CHANNEL_FAILS_BEFORE_FALLBACK = 3,
  CHANNEL_JOIN_GRACE = 10, CHANNEL_RETRY_FIRST = 60, CHANNEL_RETRY_MAX = 300,
  CHANNEL_LIST_INTERVAL = 60, CHANNEL_LIST_WAIT = 5, CREW_FOUND_DELAY = 3,
  PING_INTERVAL = 60, OFFLINE_AFTER = 180, OFFLINE_TICK = 15,
  LAYER_STALE_AFTER = 600, LAYER_CONFIRMATIONS = 2, LAYER_TICK = 30,
  -- layer compare: a friend this close (yards) whom the game hides for this long (s) is on another layer
  LAYER_NEAR = 40, LAYER_HIDDEN_FOR = 8, LAYER_LOOK_TICK = 2,
  POPUP_COMBINE_WINDOW = 3, LOGIN_QUIET = 30, POPUP_MAX = 5,
  SELF_FLUSH_DELAY = 1, HELLO_JITTER_MIN = 0.5, HELLO_JITTER_MAX = 5,
  SEND_PER_SECOND = 2, SEND_BURST = 4, DEDUPE_WINDOW = 2, MAX_MESSAGE = 255,
  LOG_MAX = 500, STATUS_MAX = 40, BREAK_ERRORS = 3, BREAK_WINDOW = 60, PANEL_MAX_ROWS = 8,
  -- stats board
  STATS_TICK = 0.5, STEPS_PER_YARD = 1.2, MAX_RUN_SPEED = 100, FALL_WINDOW = 2, DROWN_GRACE = 1,
  WEAK_LEVELS = 5, WEAK_WINDOW = 10, AGAIN_WINDOW = 60, WIPE_WINDOW = 30,
  STATS_SEND_INTERVAL = 300, STATSREQ_GAP = 60, STATS_CHANGED_GAP = 5,
  STATSREQ_JITTER_MIN = 0.2, STATSREQ_JITTER_MAX = 2, -- STATSREQ replies land well inside the show's SHOW_WAIT
  SESSION_DECIDE_AFTER = 20, SESSION_RESUME = 1800, SESSION_ACTIVE_TICK = 60,
  ROAST_GAP = 10, WIPE_ROAST_DEDUPE = 60, ROAST_SECONDS = 6,
  SHOW_WAIT = 5, SHOW_BADGE = 0.6, SHOW_DRUMROLL = 1.5, SHOW_IDLE = 60, -- idle: no card change closes it
  COUCH_MIN_PLAYED = 1800, NEVERWALKS_MIN_YARDS = 1000,
  -- tell crew to update
  UPDATE_BUTTON_COOLDOWN = 30, UPDATE_REPEAT_GAP = 600, UPDATE_LOGIN_DELAY = 5,
  -- update notice: seconds between hearing of a newer version and its pop-up (a quick "Tell crew to update" wins)
  UPDATE_NOTICE_DELAY = 30,
  -- level progress: a gap between XP gains counts at most this long (s), and no estimate when the last gain is older
  -- (idle); an estimate needs XP_MIN_GAINS gains and XP_MIN_ACTIVE s of playing time, and is left out past
  -- XP_MAX_ESTIMATE s. MAX_LEVEL_FALLBACK when the game has no GetMaxPlayerLevel.
  XP_IDLE_AFTER = 600, XP_MIN_GAINS = 2, XP_MIN_ACTIVE = 180, XP_MAX_ESTIMATE = 12 * 3600, MAX_LEVEL_FALLBACK = 60,
  -- minimap button: the icon (must match "## IconTexture" in TwizCrew.toc, a test checks it) and the starting angle
  -- in degrees (0 = right, counter-clockwise; 190 = left edge, just below the middle)
  MINIMAP_ICON = "Interface\\Icons\\Ability_Warrior_BattleShout", MINIMAP_ANGLE = 190,
  -- find the crew: our position is looked at every FIND_TICK s and goes to the group when we moved FIND_MOVE yards
  -- and the last one is FIND_GAP s old, or every FIND_KEEPALIVE s; a friend's is unknown after FIND_STALE s. Row
  -- arrows hide within FIND_NEAR yards; the big arrow closes within FIND_NEAR yards of a friend and FIND_ARRIVE_MEET
  -- of a meet-up. A meet-up lives MEET_LIFE s.
  FIND_TICK = 1, FIND_MOVE = 10, FIND_GAP = 3, FIND_KEEPALIVE = 30, FIND_STALE = 60, FIND_NEAR = 15,
  FIND_ARRIVE_MEET = 20, MEET_LIFE = 900, FIND_ARROW_TICK = 0.1,
  -- "running off": a group member who was within FIND_RUN_NEAR yards and is FIND_RUN_FAR yards away within
  -- FIND_RUN_WINDOW seconds (and moved more than you did); their arrow flashes for FIND_RUN_ALARM seconds
  FIND_RUN_NEAR = 40, FIND_RUN_FAR = 100, FIND_RUN_WINDOW = 20, FIND_RUN_ALARM = 10,
}

function ns.now() return GetTime() end
function ns.wallclock() return time() end

-- A character name without its realm. WoW Forever hands us "Name Realm" (space) for party and whisper senders,
-- other clients "Name-Realm"; character names never contain a space or a hyphen, so we keep what comes before.
-- The crew is same-realm, so the short name is enough to whisper and to tell people apart.
function ns.shortName(name)
  if type(name) ~= "string" then return name end
  local ok, amb = pcall(Ambiguate, name, "none")
  if ok and type(amb) == "string" and amb ~= "" then name = amb end
  return name:match("^([^%s%-]+)") or name
end

-- The game's max level (for "max level" and the ding's "N to go"); MAX_LEVEL_FALLBACK when it cannot tell.
function ns.maxLevel()
  if type(GetMaxPlayerLevel) == "function" then
    local ok, n = pcall(GetMaxPlayerLevel)
    if ok and type(n) == "number" and n > 0 and n < 1000 then return math.floor(n) end
  end
  return ns.Config.MAX_LEVEL_FALLBACK
end

-- Test tools ("Try it out"): every fake crew member's name ends in " (test)". A real character name has no space or
-- bracket, and every real sender goes through shortName (which keeps what comes before the first space), so a fake
-- name can never be a real friend's. Fakes are never sent or saved (see Roster and UI/Report.lua).
function ns.isTestName(name)
  return type(name) == "string" and #name > 7 and name:sub(-7) == " (test)"
end

function ns.playerName()
  return ns.shortName(UnitName("player") or "Unknown")
end

function ns.isMe(name)
  return type(name) == "string" and ns.shortName(name):lower() == ns.playerName():lower()
end
