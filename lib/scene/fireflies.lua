-- fireflies (air, MiBeads): each grain is a firefly. density fills the air,
-- glow stretches their trails, freeze holds them in place.

local H = include('lib/helpers')

local fireflies = {
  id = "fireflies", name = "fireflies", about = "Beads",
  macros = {
    { id = "density", name = "density", default = 0.5 },
    { id = "glow",    name = "glow",    default = 0.4 },
  },
  drift = 0, speed = 1.5, -- the swarm drifts with the weather's wind
}

local r = H.rng(200)
local FLIES = {}
for i = 1, 30 do
  FLIES[i] = {
    x = r() * 128, y = 16 + r() * 32, fx = 0.15 + r() * 0.35, fy = 0.3 + r() * 0.6,
    ph = r() * 6.28, bf = 0.7 + r() * 1.6, spark = 0,
  }
end

local function pos(f, t, drift)
  local x = (f.x + math.sin(t * f.fx + f.ph) * 14 + drift) % 136 - 4
  return x, f.y + math.sin(t * f.fy + f.ph * 2) * 5
end

-- macro -> MiBeads parameter (see doc/SOUND.md; change live with tune() in maiden)
fireflies.map = {
  density   = { 1, 0.56, 0.95 }, -- random-grain zone (0.48..0.52 makes no grains)
  fb        = { 1, 0.05, 0.35 },
  size      = { 2, 0.2, 0.85 },
  time_rnd  = { 2, 0.1, 0.3 },
  drywet    = 0.5,
  rvb       = { 2, 0.3, 0.8 },
  shape     = 0.6,
  pitch_rnd = 0.08,
  time      = 0.5,
  pitch     = 0,
}
-- in the cold (snow, at full): the grains wander less, in time and pitch
fireflies.chill = { time_rnd = 0.6, pitch_rnd = 0.6 }

function fireflies:sound(sc)
  local s = sc.mapped(self)
  s.freeze = sc.frozen and 1 or 0
  return s
end

function fireflies:on_note(x, sc)
  local near = {}
  for _, f in ipairs(FLIES) do
    local fx = pos(f, sc.fly_t, self.drift)
    near[#near + 1] = { d = math.abs(fx - x), f = f }
  end
  table.sort(near, function(a, b) return a.d < b.d end)
  for i = 1, 3 do near[i].f.spark = 1 end
end

function fireflies:update(dt, sc)
  if not sc.frozen then
    self.speed = 1.5 + sc.wind() * 0.25
    self.drift = self.drift + dt * self.speed
  end
  for _, f in ipairs(FLIES) do f.spark = math.max(0, f.spark - dt * 1.4) end
end

function fireflies:draw(cv, sc)
  local n, trail, t = 4 + H.round(sc.m(4, 1) * 26), H.round(sc.m(4, 2) * 6), sc.fly_t
  for i = 1, n do
    local f = FLIES[i]
    local blink = math.max(0, math.sin(t * f.bf + f.ph)) ^ 3
    local lv = (sc.frozen and 6 or 1 + blink * 10) + f.spark * 8
    for k = trail, 1, -1 do
      local tx, ty = pos(f, t - k * 0.09, self.drift - k * 0.09 * self.speed)
      cv.px(tx, ty, lv * 0.45 * (1 - k / (trail + 1)))
    end
    local x, y = pos(f, t, self.drift)
    cv.px(x, y, lv)
    if f.spark > 0.4 then cv.px(x + 1, y, lv * 0.5); cv.px(x - 1, y, lv * 0.5) end
  end
end

return fireflies
