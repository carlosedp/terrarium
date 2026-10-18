-- climate: a chaotic attractor that slowly moves the macros, like CV into a
-- eurorack module. The macro you set is the center; each macro has its own cv
-- amount (an attenuverter) in PARAMS. The attractor's three outputs (x, y, z)
-- are linked, so the parts drift together, like weather moving through.
-- Stateful: included only in terrarium.lua.

local H = include('lib/helpers')

local Climate = { kind = 1, out = { 0, 0, 0 }, trail = {} }

-- on screen the attractors go by how they move, as weather
Climate.NAMES = { "off", "fronts", "gusts", "tides", "squalls" }
local ATTRACTOR_OF = { fronts = "lorenz", gusts = "rossler", tides = "thomas", squalls = "chua" }
Climate.DRIFTS = { "slow", "medium", "fast" }
local LOOP_SEC = { 40, 15, 5 } -- seconds per loop, roughly, for each drift

-- per attractor: equations, integration step, its natural loop time, and the
-- 5th/50th/95th percentiles of each output, measured over a long run. Outputs
-- are centered on the median and scaled so the wider tail reaches +-1.
local ATTRACTORS = {
  lorenz = {
    h = 0.01, period = 2, p0 = { 0.1, 0, 20 },
    q = { { -13.3, 0.06, 13.35 }, { -15.92, -0.02, 15.99 }, { 10.62, 22.33, 38.04 } },
    f = function(x, y, z) return 10 * (y - x), x * (28 - z) - y, x * y - 8 / 3 * z end,
  },
  rossler = { -- z idles near 0 and spikes: gusts
    h = 0.04, period = 5.9, p0 = { 1, 1, 0 },
    q = { { -7.71, -0.38, 9.13 }, { -9.14, -0.78, 6.6 }, { 0.01, 0.04, 5.55 } },
    f = function(x, y, z) return -y - z, x + 0.2 * y, 0.2 + z * (x - 5.7) end,
  },
  thomas = { -- cyclically symmetric: x, y, z are one motion, phase shifted
    h = 0.08, period = 16, p0 = { 0.1, 0, 0 },
    q = { { -0.61, 2.15, 3.52 }, { -0.61, 2.15, 3.53 }, { -0.59, 2.17, 3.53 } },
    f = function(x, y, z)
      local b = 0.208186
      return math.sin(y) - b * x, math.sin(z) - b * y, math.sin(x) - b * z
    end,
  },
  chua = { -- the double scroll: flips between two lobes
    h = 0.01, period = 1.5, p0 = { 0.7, 0, 0 },
    q = { { -1.97, 0.39, 2 }, { -0.29, 0, 0.28 }, { -2.92, -0.19, 2.8 } },
    f = function(x, y, z)
      local m0, m1 = -1.143, -0.714
      local g = m1 * x + 0.5 * (m0 - m1) * (math.abs(x + 1) - math.abs(x - 1))
      return 15.6 * (y - x - g), x - y + z, -28 * y
    end,
  },
}

local function rk4(f, p, h)
  local x, y, z = p[1], p[2], p[3]
  local a1, b1, c1 = f(x, y, z)
  local a2, b2, c2 = f(x + a1 * h / 2, y + b1 * h / 2, z + c1 * h / 2)
  local a3, b3, c3 = f(x + a2 * h / 2, y + b2 * h / 2, z + c2 * h / 2)
  local a4, b4, c4 = f(x + a3 * h, y + b3 * h, z + c3 * h)
  p[1] = x + h / 6 * (a1 + 2 * a2 + 2 * a3 + a4)
  p[2] = y + h / 6 * (b1 + 2 * b2 + 2 * b3 + b4)
  p[3] = z + h / 6 * (c1 + 2 * c2 + 2 * c3 + c4)
end

local att, p, acc, tacc = nil, { 0, 0, 0 }, 0, 0

function Climate.on() return att ~= nil end

-- pick an attractor by index into NAMES (1 = off)
function Climate.set(i)
  Climate.kind = i
  att = ATTRACTORS[ATTRACTOR_OF[Climate.NAMES[i]]]
  Climate.out = { 0, 0, 0 }
  Climate.trail = {}
  if att then
    p = { att.p0[1], att.p0[2], att.p0[3] }
    for _ = 1, 600 do rk4(att.f, p, att.h) end -- settle onto the attractor
  end
end

function Climate.update(dt, drift)
  if not att then return end
  acc = acc + dt * att.period / LOOP_SEC[drift]
  local n = 0
  while acc >= att.h and n < 64 do
    rk4(att.f, p, att.h)
    acc, n = acc - att.h, n + 1
  end
  if n == 64 then acc = 0 end
  for k = 1, 3 do
    local q = att.q[k]
    local scale = math.max(q[3] - q[2], q[2] - q[1])
    Climate.out[k] = H.clamp((p[k] - q[2]) / scale, -1, 1)
  end
  -- the peek view draws the last loop or so, sampled in attractor time
  tacc = tacc + n * att.h
  if tacc >= att.period / 32 then
    tacc = 0
    table.insert(Climate.trail, { Climate.out[1], Climate.out[3] })
    if #Climate.trail > 48 then table.remove(Climate.trail, 1) end
  end
end

return Climate
