-- the glass of the terrarium, drawn over the whole scene: rounded corners and a
-- glint, condensation while it rains (more at faster rates), frost while the air
-- is frozen, and dust on it with the erosion setting (some specks pop with the
-- crackle). Stateful: included only in terrarium.lua.

local H = include('lib/helpers')

local W, HT = 128, 64
local glass = { beads = {}, frost = 0 }

local FERNS = {}
for i, c in ipairs({ { 0, 0 }, { W - 1, 0 }, { 0, HT - 1 }, { W - 1, HT - 1 } }) do
  local r, br = H.rng(400 + i), {}
  for k = 1, 6 do br[k] = { a = 0.15 + r() * 1.25, l = 0.45 + r() * 0.55 } end
  FERNS[i] = { cx = c[1], cy = c[2], sx = c[1] == 0 and 1 or -1, sy = c[2] == 0 and 1 or -1, br = br }
end

function glass.update(dt, sc)
  glass.frost = H.clamp(glass.frost + dt * (sc.frozen and 0.45 or -0.9), 0, 1)

  local raining, rate = sc.kind(1) == "rain", sc.m(1, 1)
  local wet = 0
  for _, b in ipairs(glass.beads) do if not b.run then wet = wet + 1 end end
  if raining and wet < 4 + H.round(rate * 20) and math.random() < dt * (0.6 + rate * 4) then
    local r, x, y = math.random()
    if r < 0.6 then -- mostly along the top, some down the sides
      x, y = 3 + math.random() * (W - 6), 1 + math.random() * 9
    else
      x = r < 0.8 and 1 + math.random() * 8 or W - 2 - math.random() * 8
      y = 6 + math.random() * 30
    end
    table.insert(glass.beads, { x = x, y = y, a = 0, vy = 0, trail = {} })
  end

  for i = #glass.beads, 1, -1 do
    local b = glass.beads[i]
    b.a = H.clamp(b.a + dt * (raining and 1.5 or -0.4), 0, 1)
    if raining and not b.run and math.random() < dt * 0.012 * (1 + rate * 3) then b.run = true end
    if b.run and not b.gone then -- run, catch, run
      if math.random() > 0.12 then b.vy = math.min(12, b.vy + dt * 14) else b.vy = b.vy * 0.2 end
      local y0 = b.y
      b.y = b.y + b.vy * dt
      b.x = b.x + (math.random() - 0.5) * 0.3
      for yy = math.ceil(y0), math.floor(b.y) do table.insert(b.trail, { x = b.x, y = yy, t = 0 }) end
      if b.y >= sc.GY - 1 then b.gone = true end
    end
    for k = #b.trail, 1, -1 do
      local p = b.trail[k]
      p.t = p.t + dt
      if p.t >= 1.1 then table.remove(b.trail, k) end
    end
    if b.a <= 0 or (b.gone and #b.trail == 0) then table.remove(glass.beads, i) end
  end
end

local function draw_frost(cv)
  local f = glass.frost
  if f <= 0.01 then return end
  local R = f * 20
  for _, c in ipairs(FERNS) do
    for j = 0, math.ceil(R) - 1 do
      for i = 0, math.ceil(R) - 1 do
        local p = 1 - math.sqrt(i * i + j * j) / R
        if p > 0 then
          local x, y = c.cx + c.sx * i, c.cy + c.sy * j
          local h = H.hash(x, y)
          if h < p * p * 0.7 then cv.lit(x, y, h < p * 0.12 and 6 or 2) end
        end
      end
    end
    for _, b in ipairs(c.br) do -- fern streaks reaching inward
      local L, dx, dy = R * 1.25 * b.l, c.sx * math.cos(b.a), c.sy * math.sin(b.a)
      cv.line(c.cx, c.cy, c.cx + dx * L, c.cy + dy * L, 4)
      local mx, my, a = c.cx + dx * L * 0.55, c.cy + dy * L * 0.55, math.atan(dy, dx)
      for _, s in ipairs({ -0.7, 0.7 }) do
        cv.line(mx, my, mx + math.cos(a + s) * L * 0.3, my + math.sin(a + s) * L * 0.3, 3)
      end
    end
  end
  for y = 0, math.ceil(f * 3) - 1 do -- a rime along the top and bottom
    for x = 0, W - 1 do
      if H.hash(x, y) < 0.3 then cv.lit(x, y, 2) end
      if H.hash(x, HT - 1 - y) < 0.3 then cv.lit(x, HT - 1 - y, 2) end
    end
  end
end

local function draw_beads(cv)
  for _, b in ipairs(glass.beads) do
    for _, p in ipairs(b.trail) do cv.lit(p.x, p.y, 2.4 * (1 - p.t / 1.1) * b.a) end
    if not b.gone then
      cv.lit(b.x, b.y, (b.run and 5 or 3) * b.a)
      if b.run then cv.lit(b.x, b.y - 1, 2 * b.a) end
    end
  end
end

local function draw_rim(cv)
  local R = 7
  for _, c in ipairs(FERNS) do
    for j = 0, R - 1 do
      for i = 0, R - 1 do
        local d = math.sqrt((R - i - 0.5) ^ 2 + (R - j - 0.5) ^ 2)
        local x, y = c.cx + c.sx * i, c.cy + c.sy * j
        if d > R then cv.erase(x, y) elseif d > R - 1.1 then cv.lit(x, y, 2) end
      end
    end
  end
  for y = 6, 32 do cv.lit(3, y, 2 * H.clamp(math.min((y - 5) / 4, (33 - y) / 7), 0, 1)) end
  for y = 9, 17 do cv.lit(5, y, 1) end
end

-- dust on the glass, for the erosion setting: fixed specks (more as it ages), and now
-- and then one that pops, like the crackle
local DUST = {}
do
  local r = H.rng(1000)
  for i = 1, 26 do DUST[i] = { x = 4 + r() * 120, y = 2 + r() * 58, l = 1 + r() * 1.5 } end
end
local function draw_dust(cv, wear) -- wear: 0 (off) .. 1 (ancient)
  if not wear or wear <= 0 then return end
  for i = 1, math.floor(4 + wear * 22) do cv.lit(DUST[i].x, DUST[i].y, DUST[i].l) end
  if math.random() < wear * 0.28 then
    cv.lit(4 + math.random() * 120, 2 + math.random() * 58, 5 + math.random() * 4)
  end
end

function glass.draw(cv, sc)
  draw_frost(cv)
  draw_beads(cv)
  draw_dust(cv, sc and sc.erosion)
  draw_rim(cv)
end

return glass
