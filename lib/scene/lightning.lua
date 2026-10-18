-- lightning (brain, random): strikes at random times, sometimes twice, and
-- plays where it hits. An unchanged step strikes with the same bolt; more
-- change, wilder storm.

local H = include('lib/helpers')
local marks = include('lib/scene/marks')

local lightning = {
  id = "lightning", name = "lightning", about = "random",
  macros = {
    { id = "rate",   name = "rate",   default = 0.35 },
    { id = "change", name = "change", default = 0.3 },
  },
  bolts = {},
}

function lightning.wait(m)
  local rate = 0.3 * 2 ^ (m[1] * 4.3)
  local dt
  if math.random() < 0.22 then
    dt = 0.09 + math.random() * 0.08 -- a quick second strike
  else
    dt = (1 / rate) * (0.15 + math.random() * 1.7)
  end
  clock.sleep(dt)
  return dt
end

local function bolt_path(x, seed, wild, GY)
  local r, pts, jag = H.rng(seed), {}, 4 + wild * 6
  local bx = x + (r() - 0.5) * 24
  for y = 0, GY, 4 do
    bx = bx + (x - bx) * (y / GY) * 0.5 + (r() - 0.5) * jag
    pts[#pts + 1] = { y >= GY and x or bx, math.min(y, GY) }
  end
  local branches = {}
  for _ = 1, 1 + H.round(wild * 2) do
    local bi = 3 + math.floor(r() * 6)
    local dir = r() < 0.5 and -1 or 1
    local br = { pts[bi] }
    for k = 1, 3 + math.floor(r() * 3) do
      br[#br + 1] = { pts[bi][1] + dir * k * (2 + r() * 3), pts[bi][2] + k * 3 }
    end
    branches[#branches + 1] = br
  end
  return pts, branches
end

function lightning:spawn(ev, _, sc)
  local pts, branches = bolt_path(ev.x, ev.seed, sc.m(1, 2), sc.GY)
  table.insert(self.bolts, { t = 0, pts = pts, branches = branches })
end

function lightning:update(dt)
  for i = #self.bolts, 1, -1 do
    local b = self.bolts[i]
    b.t = b.t + dt
    if b.t >= 0.32 then table.remove(self.bolts, i) end
  end
end

local function polyline(cv, pts, l)
  for i = 2, #pts do cv.line(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], l) end
end

function lightning:draw(cv, sc)
  for _, b in ipairs(self.bolts) do
    local flicker = b.t < 0.06 and 15 or (b.t < 0.1 and 0 or 11 * (1 - (b.t - 0.1) / 0.22))
    if b.t < 0.05 then -- faint flash across the sky
      for y = 0, sc.GY - 1 do
        for x = 0, 127 do if H.bayer(x, y) < 2 then cv.px(x, y, 1) end end
      end
    end
    if flicker > 0 then
      polyline(cv, b.pts, flicker)
      for _, br in ipairs(b.branches) do polyline(cv, br, flicker * 0.5) end
    end
  end
  marks(cv, sc, "lightning")
end

return lightning
