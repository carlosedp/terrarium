-- meadow (voice, MiPlaits): every note blooms a flower.
-- harmonics grows the grass, timbre adds petals. The flora is the Plaits
-- engine (hold K2 + E2), and each one grows its own kind of flower.

local H = include('lib/helpers')

-- melodic Plaits engines (numbers from MiPlaits: 0-15 classic, 16-23 newer);
-- new entries go at the end so saved PSETs keep their flora
local FLORA = { "modal", "string", "additive", "wavetable", "string machine", "chords",
  "va filter", "phase dist", "wave terrain", "waveshaper", "fm", "grain" }
local FLORA_ENGINE = { 12, 11, 4, 5, 22, 6, 16, 17, 21, 1, 2, 3 }
local FLORA_SHAPE = { "bell", "spike", "petals", "tulip", "umbel", "umbel",
  "tulip", "star", "puff", "star", "star", "puff" }

local meadow = {
  id = "meadow", name = "meadow", about = "Plaits", voice = "plaits",
  macros = {
    { id = "harmonics", name = "harmonics", default = 0.35 },
    { id = "timbre",    name = "timbre",    default = 0.5 },
  },
  extra_count = 1,
  variant = "meadow_flora",
  flowers = {},
}

local r = H.rng(7)
local blades = {}
for x = 1, 127, 2 do
  blades[#blades + 1] = { x = x + r() * 1.2, h = 0.35 + r() * 0.65, lv = r() < 0.3 and 4 or 3 }
end

function meadow:add_params(changed)
  params:add_option("meadow_flora", "meadow flora", FLORA, 1)
  params:set_action("meadow_flora", changed)
end

-- macro -> MiPlaits parameter (see doc/SOUND.md; change live with tune() in maiden)
meadow.map = {
  harm   = { 1, 0.05, 0.95 },
  timbre = { 2, 0.1, 0.9 },
  morph  = { 2, 0.35, 0.65 },
  decay  = { "brain", 1, 0.75, 0.4 }, -- fast rain, shorter notes
  lpg    = 0.5,
}

function meadow:sound(sc)
  local s = sc.mapped(self)
  s.engine = FLORA_ENGINE[params:get("meadow_flora")]
  return s
end

function meadow:on_note(x, sc)
  local shape = FLORA_SHAPE[params:get("meadow_flora")]
  table.insert(self.flowers, { x = x, t = 0, n = 3 + H.round(sc.m(2, 2) * 5), shape = shape })
  if #self.flowers > 14 then table.remove(self.flowers, 1) end
end

function meadow:update(dt)
  for i = #self.flowers, 1, -1 do
    local f = self.flowers[i]
    f.t = f.t + dt
    if f.t >= 1.8 then table.remove(self.flowers, i) end
  end
end

-- a flower head at (cx, cy): rad is its size, n its petals, l its brightness
local SHAPES = {
  petals = function(cv, cx, cy, rad, n, l, seed) -- additive: partials around a center
    for k = 0, n - 1 do
      local a = k / n * 6.283 + seed
      cv.px(cx + math.cos(a) * rad, cy + math.sin(a) * rad * 0.8, l)
    end
  end,
  bell = function(cv, cx, cy, rad, _, l) -- modal: a bell, open side down
    cv.ellipse(cx, cy, rad + 0.5, rad + 0.5, l, math.pi, 2 * math.pi)
    cv.px(cx - rad - 1, cy + 1, l * 0.7)
    cv.px(cx + rad + 1, cy + 1, l * 0.7)
    cv.px(cx, cy + 1, l)
  end,
  spike = function(cv, cx, cy, rad, n, l) -- string: seeds up a stalk
    for k = 0, n - 1 do cv.px(cx + (k % 2 == 0 and 1 or -1), cy - k * (0.6 + rad * 0.3), l * (1 - k / (n + 2))) end
  end,
  tulip = function(cv, cx, cy, rad, _, l) -- wavetable, va filter: a cup
    cv.line(cx - rad, cy - rad, cx, cy, l)
    cv.line(cx + rad, cy - rad, cx, cy, l)
    cv.px(cx, cy - rad, l * 0.7)
  end,
  umbel = function(cv, cx, cy, rad, n, l) -- chords, string machine: many small heads
    for k = 0, n - 1 do
      local a = -math.pi / 2 + (k / math.max(1, n - 1) - 0.5) * 1.8
      local hx, hy = cx + math.cos(a) * rad * 1.4, cy + math.sin(a) * rad * 1.4
      cv.line(cx, cy, hx, hy, l * 0.35)
      cv.px(hx, hy, l)
    end
  end,
  puff = function(cv, cx, cy, rad, n, l) -- grain, wave terrain: a dandelion clock
    for k = 0, 2 * n - 1 do
      local a = k / (2 * n) * 6.283
      cv.px(cx + math.cos(a) * (rad + 0.5), cy + math.sin(a) * (rad + 0.5), l * 0.5)
    end
  end,
  star = function(cv, cx, cy, rad, n, l, seed) -- fm, phase dist, waveshaper: sharp rays
    for k = 0, n - 1 do
      local a = k / n * 6.283 + seed
      local tx, ty = cx + math.cos(a) * (rad + 1), cy + math.sin(a) * (rad + 1) * 0.8
      cv.line(cx, cy, tx, ty, l * 0.5)
      cv.px(tx, ty, l)
    end
  end,
}

function meadow:draw(cv, sc)
  local GY, t = sc.GY, sc.t
  local hs = 3 + sc.m(2, 1) * 10
  local windy = sc.kind(1) == "rain" and H.clamp((-6 + sc.m(1, 2) * 34) / 28, 0.1, 1) or 0.15
  local tb = sc.m(2, 2)
  local function sway(b) return math.sin(t * 1.4 + b.x * 0.17) * (0.4 + windy * 2.2) end
  for _, b in ipairs(blades) do
    cv.line(b.x, GY, b.x + sway(b), GY - b.h * hs, b.lv)
  end
  for _, f in ipairs(self.flowers) do
    local b = blades[H.clamp(math.floor(f.x / 2) + 1, 1, #blades)]
    local cx, cy = b.x + sway(b), GY - b.h * hs - 2
    local life, grow = 1 - f.t / 1.8, math.min(1, f.t / 0.15)
    local rad = (1 + tb * 2.2) * grow
    cv.line(b.x, GY, cx, cy, 5 * life + 2)
    SHAPES[f.shape or "petals"](cv, cx, cy, rad, f.n, 11 * life, f.x)
    cv.px(cx, cy, 15 * life)
  end
end

return meadow
