-- aurora (drone, 2x MiPlaits): a drone on the key's root and fifth, drawn as
-- curtains of light across the top of the sky. glow brightens the tone and
-- lights the curtains; motion sets how far both drift. The drone follows the
-- key and glides when a season turns (the curtains flare), and its upper voice
-- follows the weather now and then (they flare softly). The Plaits engine
-- is the variant (hold K2 + E2). K3 hushes it and lets it rise again.

local H = include('lib/helpers')

local KINDS = { "string machine", "chords", "wavetable", "additive", "va filter", "wave terrain", "phase dist" }
local ENGINE = { 22, 6, 5, 4, 16, 21, 17 } -- MiPlaits engine numbers

local aurora = {
  id = "aurora", name = "aurora", about = "Plaits drone",
  macros = {
    { id = "glow",   name = "glow",   default = 0.4 },
    { id = "motion", name = "motion", default = 0.3 },
  },
  extra_count = 1,
  variant = "aurora_engine",
  flow = 0, light = 1,
}

function aurora:add_params(changed)
  params:add_option("aurora_engine", "aurora engine", KINDS, 1)
  params:set_action("aurora_engine", changed)
end

-- macro -> MiPlaits parameter (see doc/SOUND.md; change live with tune() in maiden)
aurora.map = {
  harm   = { 1, 0.3, 0.6 },
  timbre = { 1, 0.15, 0.75 },
  morph  = { 2, 0.35, 0.65 },
  wobble = { 2, 0.02, 0.3 }, -- how far a slow LFO moves timbre and morph
  amp    = 0.25,
}

function aurora:sound(sc)
  local s = sc.mapped(self)
  s.engine = ENGINE[params:get("aurora_engine")]
  s.pitch = sc.brain.drone_root()
  s.fifth = sc.brain.drone_interval() -- the upper voice, moved now and then by the weather
  s.hush = sc.hushed and 0 or 1
  s.duck = H.round(sc.activity * 50) / 50 -- gives way to the weather's notes, swells in the gaps
  s.lift = H.round(sc.lift * 50) / 50     -- brightens with each note, a strike most
  return s
end

local r = H.rng(700)
local GRAIN = {}
for x = 0, 127 do GRAIN[x] = r() * 6 end

function aurora:update(dt, sc)
  self.flow = self.flow + dt * (0.15 + sc.m(5, 2) * 1.2)
  -- the light fades with the sound (the engine glides hush over ~3 s)
  self.light = self.light + ((sc.hushed and 0 or 1) - self.light) * math.min(1, dt / 1.5)
end

function aurora:draw(cv, sc)
  if self.light < 0.02 then return end
  local glow, motion, t = math.min(1, sc.m(5, 1) + sc.lift * 0.5), sc.m(5, 2), self.flow
  local light = self.light * (1 - 0.35 * sc.activity) -- the curtains dim as the drone gives way
  local flare = math.max(0, 1 - (sc.t - sc.brain.season_t) / 3,  -- a season turning,
    0.5 * (1 - (sc.t - sc.brain.drone_t) / 2.5))                    -- softer: the upper voice moving
  for x = 0, 127 do
    -- the curtain's lower edge waves; light hangs from the top, brightest near the edge
    local edge = 7 + glow * 7 + math.sin(x * 0.07 + t) * (2 + motion * 4) + math.sin(x * 0.19 - t * 1.3) * 1.5
    local strength = (0.5 + 0.5 * math.sin(x * 0.045 - t * 0.6)) * light
    if strength > 0.15 then
      for y = 1, math.floor(edge) do
        local fall = y / edge
        local p = strength * fall * fall * (0.6 + glow * 0.6) + flare * 0.3
        if p * 16 > H.bayer(x, y) + GRAIN[x] then
          cv.px(x, y, (fall > 0.85 and 3 or 1) + math.floor(glow * 2 + flare * 3))
        end
      end
    end
  end
end

return aurora
