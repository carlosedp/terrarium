-- mountains (air, MiVerb): bigger rooms are bigger ranges. Each note echoes
-- back off the far ridge.

local H = include('lib/helpers')

local mountains = {
  id = "mountains", name = "mountains", about = "MiVerb",
  macros = {
    { id = "size", name = "size", default = 0.45 },
    { id = "echo", name = "echo", default = 0.45 },
  },
  echoes = {},
}

local RIDGES = {}
for j = 1, 3 do
  local r = H.rng(300 + j)
  local ph = { r() * 6, r() * 6, r() * 6 }
  local fr = { 0.03 + (j - 1) * 0.01, 0.07 + (j - 1) * 0.02, 0.16 }
  local ridge = {}
  for x = 0, 127 do
    local v = 0.55 * math.sin(x * fr[1] + ph[1]) + 0.3 * math.sin(x * fr[2] + ph[2]) + 0.15 * math.sin(x * fr[3] + ph[3])
    ridge[x] = 0.5 + 0.5 * v
  end
  RIDGES[j] = ridge
end

-- macro -> MiVerb parameter (see doc/SOUND.md; change live with tune() in maiden)
mountains.map = {
  time   = { 1, 0.5, 0.97 },
  drywet = { 2, 0.12, 0.65 },
  damp   = 0.5,
  hp     = 0.05,
  diff   = 0.7,
}

function mountains:sound(sc)
  local s = sc.mapped(self)
  if sc.kind(3) == "fog" then s.damp = H.lin(sc.m(3, 1), 0.75, 0.35) end -- foggy, darker tail
  s.freeze = sc.frozen and 1 or 0
  return s
end

function mountains:on_note(x, sc)
  local n = 1 + H.round(sc.m(4, 2) * 3)
  for k = 1, n do
    table.insert(self.echoes, { x = 128 - x, t = -0.22 * k, a = 1 - (k - 1) / (n + 1) })
  end
  while #self.echoes > 16 do table.remove(self.echoes, 1) end
end

function mountains:update(dt)
  for i = #self.echoes, 1, -1 do
    local e = self.echoes[i]
    e.t = e.t + dt
    if e.t >= 0.5 then table.remove(self.echoes, i) end
  end
end

function mountains:draw(cv, sc)
  local size, GY = sc.m(4, 1), sc.GY
  local L = 1 + H.round(size * 2)
  local first = 4 - L
  for j = first, 3 do
    local hmax = (5 + size * 17) * (1 - (j - first) * 0.2)
    local lv = sc.frozen and 6 or 2 + (j - first)
    for x = 0, 127 do
      local y = H.round(GY - RIDGES[j][x] * hmax)
      for yy = y + 1, GY - 1 do cv.erase(x, yy) end -- nearer ridges hide farther ones
      cv.px(x, y, lv)
    end
  end
  local hfar = 5 + size * 17
  for _, e in ipairs(self.echoes) do
    if e.t >= 0 then
      local fade = (1 - e.t / 0.5) * e.a
      for dx = -3, 3 do
        local x = H.round(e.x + dx)
        if x >= 0 and x <= 127 then
          cv.px(x, H.round(GY - RIDGES[first][x] * hfar), 13 * fade * (1 - math.abs(dx) / 4))
        end
      end
    end
  end
end

return mountains
