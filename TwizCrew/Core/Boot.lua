-- Start-up (loads last): saved data on ADDON_LOADED, everything else on PLAYER_LOGIN.
-- Each step runs on its own inside ns.Log.safe, so one broken part cannot stop the rest from starting.
local ADDON, ns = ...

local Boot = {}
ns.Boot = Boot

local FEATURE = "boot"
local loaded, loggedIn = false, false

function Boot.load()
  if loaded then return end
  loaded = true
  ns.db = ns.DB.init(TwizCrewDB, ns.Modules.list())
  TwizCrewDB = ns.db
  ns.Log.attach(ns.db.log)
  ns.Modules.attach(ns.db)
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    ns.Log.safe("comm", C_ChatInfo.RegisterAddonMessagePrefix, ns.Config.PREFIX)
  end
  ns.Settings.registerOptions()
  ns.Log.add("info", "loaded v%s", ns.VERSION)
end

function Boot.login()
  if loggedIn then return end
  if not loaded then ns.Log.safe(FEATURE, Boot.load) end
  loggedIn = true
  ns.Log.safe("comm", ns.Comm.start)
  ns.Log.safe("comm", ns.Crew.start)
  ns.Log.safe("comm", ns.Self.start)
  ns.Log.safe("comm", ns.LayerSensor.start)
  ns.Log.safe("session", ns.Session.start)
  ns.Log.safe(FEATURE, ns.Modules.startAll)
  print("TwizCrew v" .. ns.VERSION .. " loaded. Type /tc for settings.")
end

ns.Events.on(FEATURE, "ADDON_LOADED", function(name)
  if name == ADDON then Boot.load() end
end)
ns.Events.on(FEATURE, "PLAYER_LOGIN", Boot.login)
