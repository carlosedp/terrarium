-- canvas: a 128x64 framebuffer of brightness levels (0..15).
--
-- The scene draws into this buffer instead of straight to the screen, so later
-- layers can erase or dim earlier ones (mountains hide what's behind them, fog
-- darkens everything). blit() then sends it to the screen, merging runs of
-- equal pixels into rects and filling once per level, which keeps the number
-- of screen calls per frame low.

local W, H = 128, 64
local floor, ceil, max, abs = math.floor, math.ceil, math.max, math.abs

local Canvas = { W = W, H = H, mul = 1 }
local buf = {}
for i = 1, W * H do buf[i] = 0 end

local function round(v) return floor(v + 0.5) end

function Canvas.clear()
  for i = 1, W * H do buf[i] = 0 end
end

-- set a pixel; the level is scaled by Canvas.mul (used to dim unfocused layers)
function Canvas.px(x, y, l)
  x, y = round(x), round(y)
  if x < 0 or y < 0 or x >= W or y >= H then return end
  local v = round(l * Canvas.mul)
  if v <= 0 then return end
  if v > 15 then v = 15 end
  buf[y * W + x + 1] = v
end

function Canvas.erase(x, y)
  x, y = round(x), round(y)
  if x >= 0 and y >= 0 and x < W and y < H then buf[y * W + x + 1] = 0 end
end

function Canvas.get(x, y)
  if x < 0 or y < 0 or x >= W or y >= H then return 0 end
  return buf[y * W + x + 1]
end

function Canvas.line(x0, y0, x1, y1, l)
  x0, y0, x1, y1 = round(x0), round(y0), round(x1), round(y1)
  local dx, dy = abs(x1 - x0), -abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  for _ = 1, 512 do
    Canvas.px(x0, y0, l)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

function Canvas.ellipse(cx, cy, rx, ry, l, a0, a1)
  a0, a1 = a0 or 0, a1 or math.pi * 2
  local steps = max(8, ceil(max(rx, ry) * 6))
  for i = 0, steps do
    local a = a0 + (a1 - a0) * i / steps
    Canvas.px(cx + math.cos(a) * rx, cy + math.sin(a) * ry, l)
  end
end

function Canvas.rect(x, y, w, h, l)
  for j = 0, h - 1 do
    for i = 0, w - 1 do Canvas.px(x + i, y + j, l) end
  end
end

function Canvas.clear_rect(x, y, w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do Canvas.erase(x + i, y + j) end
  end
end

-- multiply every lit pixel (fog dims the whole scene)
function Canvas.scale(f)
  for i = 1, W * H do
    local v = buf[i]
    if v > 0 then buf[i] = max(1, ceil(v * f)) end
  end
end

-- reused between frames so blit makes no garbage
local runs, counts = {}, {}
for l = 1, 15 do runs[l] = {}; counts[l] = 0 end

function Canvas.blit()
  for l = 1, 15 do counts[l] = 0 end
  for y = 0, H - 1 do
    local row = y * W
    local x = 0
    while x < W do
      local l = buf[row + x + 1]
      if l > 0 then
        local x0 = x
        x = x + 1
        while x < W and buf[row + x + 1] == l do x = x + 1 end
        local n, r = counts[l], runs[l]
        r[n + 1], r[n + 2], r[n + 3] = x0, y, x - x0
        counts[l] = n + 3
      else
        x = x + 1
      end
    end
  end
  local rects = 0
  for l = 1, 15 do
    local n = counts[l]
    if n > 0 then
      screen.level(l)
      local r = runs[l]
      for k = 1, n, 3 do screen.rect(r[k], r[k + 1], r[k + 2], 1) end
      screen.fill()
      rects = rects + n // 3
    end
  end
  return rects
end

return Canvas
