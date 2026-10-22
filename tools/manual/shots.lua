-- The manual's scene pictures (doc/img), from the real Lua: run terrarium headless
-- against the test mock, stage each scene with params only (no keys, so nothing is
-- dimmed or labelled), and dump the screen of the liveliest frame as a PGM.
--
--   lua tools/manual/shots.lua <repo dir> <out dir>      (make manual-images does it all)
--
-- Text (labels, the peek view, toasts) is drawn by norns' font after this capture, so
-- screens with text are taken separately (by hand on the norns, or from norns-web).
local root, out = arg[1], arg[2]
arg[0] = root .. "/test/smoke.lua"
local M = dofile(root .. "/test/mock_norns.lua")
math.randomseed(11)
local real_include, cache = include, {}
function include(p)
  if p == "lib/canvas" or p == "lib/daylight" then cache[p] = cache[p] or real_include(p); return cache[p] end
  return real_include(p)
end
dofile(root .. "/terrarium.lua")
init()
local cv, Day = cache["lib/canvas"], cache["lib/daylight"]
local snap = {}
local orig_blit = cv.blit
cv.blit = function() for i = 0, 128 * 64 - 1 do snap[i] = cv.get(i % 128, i // 128) end return orig_blit() end
local function dump(name)
  local f = assert(io.open(out .. "/" .. name .. ".pgm", "wb"))
  f:write("P5 128 64 15\n")
  for i = 0, 128 * 64 - 1 do f:write(string.char(snap[i])) end
  f:close()
end
local function brightness(y0, y1)
  local s = 0
  for y = y0 or 0, y1 or 63 do for x = 0, 127 do s = s + snap[y * 128 + x] end end
  return s
end
local function set(t) for k, v in pairs(t) do params:set(k, v) end end
-- run for a while and keep the liveliest frame (brightest between rows y0 and y1);
-- no encoder or key is touched, so nothing on screen is dimmed or labelled
local function pick(name, secs, y0, y1)
  local best, bestv = nil, -1
  for _ = 1, math.floor(secs * 15) do
    M.run(1 / 15)
    local b = brightness(y0, y1)
    if b > bestv then bestv = b; best = {}; for i = 0, 128 * 64 - 1 do best[i] = snap[i] end end
  end
  snap = best; dump(name)
end
M.run(4) -- the start-up dimming fades

-- the default terrarium, a little rain on the meadow
set({ drone_kind = 1, rain_rate = 0.6, rain_change = 0.3, meadow_harmonics = 0.5, meadow_timbre = 0.6 })
M.run(6); pick("hero", 4, 30, 63)

-- brain
set({ rain_rate = 0.85, rain_change = 0.75 }); M.run(9); pick("rain", 2, 0, 50)
set({ brain_kind = 2, lightning_rate = 0.7, lightning_change = 0.5 }); M.run(2); pick("lightning", 12, 0, 63)
set({ brain_kind = 1, rain_rate = 0.75, rain_change = 0.3 }); M.run(2)

-- voice (the rain plays the notes)
set({ voice_kind = 1, meadow_flora = 1 }); M.run(3); pick("meadow", 4, 30, 53)
for _, f in ipairs({ 1, 2, 3, 4, 5, 8, 9 }) do
  set({ meadow_flora = f }); M.run(3); pick(("flora_%02d"):format(f), 4, 30, 53)
end
set({ meadow_flora = 1, voice_kind = 2, crystals_ratio = 0.7, crystals_index = 0.8 }); M.run(3); pick("crystals", 5, 20, 53)
set({ voice_kind = 3, reeds_structure = 0.6, reeds_brightness = 0.8, reeds_model = 2 }); M.run(3); pick("reeds", 5, 25, 53)
set({ voice_kind = 4, visitors_midi = 2 }); M.run(9); pick("visitors", 5, 45, 54)
set({ voice_kind = 1 }); M.run(2)

-- color
set({ color_kind = 1, pond_structure = 0.7, pond_damping = 0.2 }); M.run(4); pick("pond", 4, 55, 63)
set({ color_kind = 2, fog_clarity = 0.25, fog_shimmer = 0.5 }); M.run(3); pick("fog", 1, 0, 63)
set({ color_kind = 1 }); M.run(2)

-- air
set({ air_kind = 1, clouds_density = 0.8, clouds_size = 0.7 }); M.run(3); pick("clouds", 2, 0, 30)
set({ air_kind = 2, fireflies_density = 0.7, fireflies_glow = 0.9 }); M.run(4); pick("fireflies", 2, 10, 50)
set({ air_kind = 3, mountains_size = 0.9, mountains_echo = 0.8 }); M.run(3); pick("mountains", 4, 20, 54)
set({ air_kind = 1 }); M.run(2)

-- drone
set({ drone_kind = 1, aurora_glow = 0.9, aurora_motion = 0.5, air_kind = 3, mountains_size = 0.3 }); M.run(3); pick("aurora", 2, 0, 20)
set({ drone_kind = 2, roots_breath = 0.6, roots_depth = 1, color_kind = 2, fog_clarity = 1, fog_shimmer = 0 }); M.run(4); pick("roots", 3, 55, 63)
set({ drone_kind = 1, air_kind = 1, color_kind = 1 }); M.run(2)

-- frost and condensation
set({ air_freeze = 2 }); M.run(4); pick("frost", 1, 0, 63)
set({ air_freeze = 1, rain_rate = 1, rain_change = 0.2 }); M.run(14); pick("condensation", 1, 0, 63)
set({ rain_rate = 0.6 })

-- day and night
set({ t_day = 2, aurora_glow = 0.5 })
for _, ph in ipairs({ { "dawn", 0.02 }, { "noon", 0.2 }, { "dusk", 0.485 }, { "night", 0.72 } }) do
  Day.phase = ph[2]; M.run(1.5); Day.phase = ph[2]; M.run(0.1); dump("day_" .. ph[1])
end

-- snow, last so the shots above keep their random sequence: let it settle for a while first
set({ t_day = 1, brain_kind = 3, snow_rate = 0.85, snow_change = 0.4, voice_kind = 1, meadow_harmonics = 0.35 })
M.run(150); pick("snow", 4, 0, 53)
os.exit(0)
