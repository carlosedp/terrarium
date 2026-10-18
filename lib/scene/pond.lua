-- pond (color, MiRings): each note rings out as ripples. The voice excites the
-- resonator. structure adds rings, damping shortens how long they spread.
-- The water under the ground mirrors the scene, and the ripples bend it.

local H = include('lib/helpers')

local KINDS = { "modal", "sympathetic strings", "inharmonic string", "fm voice", "quantized strings", "string + reverb" }

local pond = {
  id = "pond", name = "pond", about = "Rings",
  macros = {
    { id = "structure", name = "structure", default = 0.5 },
    { id = "damping",   name = "damping",   default = 0.35 },
  },
  extra_count = 1,
  rings = {},
}

function pond:add_params(changed)
  params:add_option("pond_kind", "pond kind", KINDS, 1)
  params:set_action("pond_kind", changed)
end

function pond:sound(sc)
  local st, dp = sc.m(3, 1), sc.m(3, 2)
  return {
    struct = H.lin(st, 0.1, 0.85),
    damp = H.lin(dp, 0.92, 0.35),           -- more damping, shorter ring
    bright = H.lin(sc.m(2, 2), 0.35, 0.7),  -- a brighter voice rings brighter
    model = params:get("pond_kind") - 1,
    pos = 0.3,
    mix = 0.8,
  }
end

function pond:on_note(x)
  table.insert(self.rings, { x = x, t = 0 })
  if #self.rings > 10 then table.remove(self.rings, 1) end
end

function pond:update(dt, sc)
  local life = 0.4 + (1 - sc.m(3, 2)) * 2.4
  for i = #self.rings, 1, -1 do
    local r = self.rings[i]
    r.t = r.t + dt
    if r.t >= life then table.remove(self.rings, i) end
  end
end

-- the band above the ground, squashed 2:1 into the water and wobbling; each
-- ring bends the reflection where it passes
local function reflect(cv, sc, rings, life)
  local GY, t = sc.GY, sc.t
  local band = math.floor(t * 3)
  for y = GY + 1, 63 do
    local d = y - GY
    local sy, dim = GY - d * 2, (y + band) % 4 == 0 and 0.225 or 0.45
    for x = 0, 127 do
      local ox = math.sin(t * 2.1 + y * 1.7 + x * 0.05) * (0.3 + d * 0.08)
      for _, r in ipairs(rings) do
        local rad = r.t * 22
        if rad >= 1 then
          local ex, ey = x - r.x, (y - GY - 4) / 0.14
          local e = math.sqrt(ex * ex + ey * ey)
          if math.abs(e - rad) < 4 then ox = ox + 2.2 * (1 - r.t / life) * math.sin((e - rad) * 1.4) end
        end
      end
      local v = cv.get(H.round(x + ox), sy)
      if v > 0 then cv.lit(x, y, v * dim) end
    end
  end
end

function pond:draw(cv, sc)
  local GY = sc.GY
  local n = 2 + H.round(sc.m(3, 1) * 4)
  local life = 0.4 + (1 - sc.m(3, 2)) * 2.4
  reflect(cv, sc, self.rings, life)
  for _, r in ipairs(self.rings) do -- flat rings that stay in the water
    local k = 1 - r.t / life
    for i = 0, n - 1 do
      local rad = (r.t - i * 0.11) * 22
      if rad > 0.5 then
        local ry, l = math.min(5, rad * 0.14), 11 * k * (1 - i / (n + 1))
        local steps = math.max(8, math.ceil(rad * 6))
        for s = 0, steps do
          local a = s / steps * 2 * math.pi
          local y = GY + 4 + math.sin(a) * ry
          if y > GY + 0.5 then cv.px(r.x + math.cos(a) * rad, y, l) end
        end
      end
    end
  end
end

return pond
