-- none: an empty module, for a part that should stay silent (the drone, so far).
-- No macros, no sound, nothing drawn; the engine frees that slot's synth.

return {
  id = "none", name = "none", about = "silence", voice = "none",
  macros = {},
  sound = function() return {} end,
  draw = function() end,
}
