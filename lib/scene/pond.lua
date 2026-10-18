-- pond (color, MiRings): each note rings out as ripples. The voice excites the
-- resonator. structure adds rings, damping shortens how long they spread.

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

function pond:draw(cv, sc)
  local n = 2 + H.round(sc.m(3, 1) * 4)
  local life = 0.4 + (1 - sc.m(3, 2)) * 2.4
  for _, r in ipairs(self.rings) do
    local k = 1 - r.t / life
    for i = 0, n - 1 do
      local rad = (r.t - i * 0.11) * 22
      if rad > 0.5 then cv.ellipse(r.x, sc.GY + 4, rad, rad * 0.32, 11 * k * (1 - i / (n + 1))) end
    end
  end
end

return pond
