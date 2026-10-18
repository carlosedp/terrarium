-- meadow (voice, MiPlaits): every note blooms a flower.
-- harmonics grows the grass, timbre adds petals.

local H = include('lib/helpers')

local FLORA = { "modal", "string", "additive", "wavetable", "string machine" }
local FLORA_ENGINE = { 12, 11, 4, 5, 22 } -- Plaits engine numbers

local meadow = {
  id = "meadow", name = "meadow", about = "Plaits",
  macros = {
    { id = "harmonics", name = "harmonics", default = 0.35 },
    { id = "timbre",    name = "timbre",    default = 0.5 },
  },
  extra_count = 1,
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

function meadow:sound(sc)
  local h, tb = sc.m(2, 1), sc.m(2, 2)
  return {
    engine = FLORA_ENGINE[params:get("meadow_flora")],
    harm = H.lin(h, 0.05, 0.95),
    timbre = H.lin(tb, 0.1, 0.9),
    morph = H.lin(tb, 0.35, 0.65),
    decay = H.lin(sc.m(1, 1), 0.75, 0.4), -- fast rain, shorter notes
    lpg = 0.5,
  }
end

function meadow:on_note(x, sc)
  table.insert(self.flowers, { x = x, t = 0, n = 3 + H.round(sc.m(2, 2) * 5) })
  if #self.flowers > 14 then table.remove(self.flowers, 1) end
end

function meadow:update(dt)
  for i = #self.flowers, 1, -1 do
    local f = self.flowers[i]
    f.t = f.t + dt
    if f.t >= 1.8 then table.remove(self.flowers, i) end
  end
end

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
    for k = 0, f.n - 1 do
      local a = k / f.n * 6.283 + f.x
      cv.px(cx + math.cos(a) * rad, cy + math.sin(a) * rad * 0.8, 11 * life)
    end
    cv.px(cx, cy, 15 * life)
  end
end

return meadow
