-- clouds (air, MiClouds): clouds made of grains. density packs them, size
-- spreads them, freeze holds them still.

local H = include('lib/helpers')

local KINDS = { "granular", "stretch", "looping delay", "spectral" }

local clouds = {
  id = "clouds", name = "clouds", about = "Clouds",
  macros = {
    { id = "density", name = "density", default = 0.5 },
    { id = "size",    name = "size",    default = 0.5 },
  },
  extra_count = 1,
}

local CLOUDS = {}
for i, c in ipairs({ { 18, 13 }, { 66, 8 }, { 110, 16 } }) do
  local r = H.rng(100 + i)
  local grains = {}
  for k = 1, 44 do grains[k] = { a = r() * 6.283, d = math.sqrt(r()), f = r() } end
  CLOUDS[i] = { cx = c[1], cy = c[2], spark = 0, grains = grains }
end

function clouds:add_params(changed)
  params:add_option("clouds_kind", "clouds kind", KINDS, 1)
  params:set_action("clouds_kind", changed)
end

function clouds:sound(sc)
  local dn, sz = sc.m(4, 1), sc.m(4, 2)
  return {
    dens = H.lin(dn, 0.35, 0.9),
    fb = H.lin(dn, 0.05, 0.4),
    size = H.lin(sz, 0.1, 0.85),
    tex = H.lin(sz, 0.3, 0.7),
    drywet = 0.45, spread = 0.7, rvb = 0.3,
    mode = params:get("clouds_kind") - 1,
    freeze = sc.frozen and 1 or 0,
    pit_jitter = sc.m(1, 2) * 0.3, -- windy weather wobbles the grains
  }
end

function clouds:on_note(x)
  local best = CLOUDS[1]
  for _, c in ipairs(CLOUDS) do if math.abs(c.cx - x) < math.abs(best.cx - x) then best = c end end
  best.spark = 1
end

function clouds:update(dt, sc)
  for _, c in ipairs(CLOUDS) do
    if not sc.frozen then
      c.cx = c.cx + dt * 2.2
      if c.cx > 152 then c.cx = -24 end
    end
    c.spark = math.max(0, c.spark - dt * 1.6)
  end
end

function clouds:draw(cv, sc)
  local n, R, t = 6 + H.round(sc.m(4, 1) * 36), 3 + sc.m(4, 2) * 10, sc.t
  for _, c in ipairs(CLOUDS) do
    for i = 1, math.min(n, #c.grains) do
      local g = c.grains[i]
      local x = c.cx + math.cos(g.a) * g.d * R * 1.7
      local y = c.cy + math.sin(g.a) * g.d * R * 0.55
      local flick = sc.frozen and 3 or math.floor((math.sin(t * (3 + g.f * 9) + g.f * 40) + 1) / 2 * 4)
      cv.px(x, y, (sc.frozen and 5 or 2) + flick + H.round(c.spark * 7 * (1 - g.d)))
    end
  end
end

return clouds
