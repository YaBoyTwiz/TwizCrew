-- Namespace basics: addon name, version, tunable values, clocks, player name.
local ADDON, ns = ...

ns.ADDON = ADDON

do
  local version
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  end
  if type(version) ~= "string" or version == "" then version = "0.0.0" end
  ns.VERSION = version
end

-- The one place for tunable values.
ns.Config = {
  PREFIX = "TwizCrew", PROTOCOL = 1,
  DEFAULT_CHANNEL = "TwizCrewHQ", DEFAULT_PASSWORD = "goldshire",
  CHANNEL_JOIN_DELAY = 5, CHANNEL_JOIN_TIMEOUT = 10, CHANNEL_FAILS_BEFORE_FALLBACK = 3,
  PING_INTERVAL = 60, OFFLINE_AFTER = 180, OFFLINE_TICK = 15,
  LAYER_STALE_AFTER = 600, LAYER_CONFIRMATIONS = 2, LAYER_TICK = 30,
  POPUP_COMBINE_WINDOW = 3, LOGIN_QUIET = 30, POPUP_MAX = 5,
  SELF_FLUSH_DELAY = 1, HELLO_JITTER_MIN = 0.5, HELLO_JITTER_MAX = 5,
  SEND_PER_SECOND = 2, SEND_BURST = 4, DEDUPE_WINDOW = 2, MAX_MESSAGE = 255,
  LOG_MAX = 500, STATUS_MAX = 40, BREAK_ERRORS = 3, BREAK_WINDOW = 60, PANEL_MAX_ROWS = 8,
  -- stats board
  STATS_TICK = 0.5, STEPS_PER_YARD = 1.2, MAX_RUN_SPEED = 100, FALL_WINDOW = 2, DROWN_GRACE = 1,
  WEAK_LEVELS = 5, WEAK_WINDOW = 10, AGAIN_WINDOW = 60, WIPE_WINDOW = 30,
  STATS_SEND_INTERVAL = 300, STATSREQ_GAP = 60, STATS_CHANGED_GAP = 5,
  SESSION_DECIDE_AFTER = 20, SESSION_RESUME = 1800, SESSION_ACTIVE_TICK = 60,
  ROAST_GAP = 10, WIPE_ROAST_DEDUPE = 60, ROAST_SECONDS = 6,
  SHOW_WAIT = 5, SHOW_BADGE = 0.6, SHOW_DRUMROLL = 1.5,
  COUCH_MIN_PLAYED = 1800, NEVERWALKS_MIN_YARDS = 1000,
}

function ns.now() return GetTime() end
function ns.wallclock() return time() end

function ns.playerName()
  local name = UnitName("player") or "Unknown"
  return Ambiguate(name, "none")
end
