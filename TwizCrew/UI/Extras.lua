-- Grayed "coming later" extras. They have no code yet; the settings window lists them as not available.
local _, ns = ...

ns.Modules.register({
  id = "pokes", name = "Pokes & soundboard", tier = "extra", comingSoon = true, defaultEnabled = false,
  info = "Coming later: send a friend a small poke or a funny sound that plays on their screen. "
    .. "Not available yet.",
  defaults = {},
})

ns.Modules.register({
  id = "races", name = "Group races", tier = "extra", comingSoon = true, defaultEnabled = false,
  info = "Coming later: start a little race with your friends, like who reaches the next level first. "
    .. "Not available yet.",
  defaults = {},
})
