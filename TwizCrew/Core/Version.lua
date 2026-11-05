-- Version check: tells you when a friend runs a newer TwizCrew than you.
local ADDON, ns = ...

local Version = {}
ns.Version = Version

local best          -- { name =, ver = } the newest version seen so far (newer than ours)
local announced = false

local function line(entry)
  return ns.Util.safeText(entry.name) .. " has v" .. ns.Util.safeText(entry.ver)
    .. ", you have v" .. ns.VERSION .. ". Update in WowUp."
end

-- Called by Crew for every crew message that carries a version. Tolerates junk.
function Version.seen(name, ver)
  if type(name) ~= "string" or name == "" or type(ver) ~= "string" or ver == "" then return end
  if ns.Util.compareVersions(ver, ns.VERSION) <= 0 then return end
  if best and ns.Util.compareVersions(ver, best.ver) <= 0 then return end
  best = { name = name, ver = ver }
  ns.Bus.fire("VERSION_NEWER", name, ver)
  if not announced then
    announced = true
    if ns.Modules.setting("version", "chatNotice") then print("TwizCrew: " .. line(best)) end
  end
end

function Version.summary()
  if not best then return "everyone up to date" end
  return line(best)
end

ns.Modules.register({
  id = "version", name = "Version check", tier = "essential",
  info = "Notices when a friend has a newer version of TwizCrew than you.",
  defaults = { chatNotice = true },
  settings = {
    { key = "chatNotice", label = "Tell me in chat", kind = "toggle",
      info = "Tells you in chat when a friend has a newer version of TwizCrew." },
  },
})
