-- small shared helpers

local H = {}

function H.clamp(v, a, b)
  if v < a then return a elseif v > b then return b end
  return v
end

-- macro (0..1) to a parameter range: H.lin(0.5, 0.1, 0.9) == 0.5
function H.lin(v, a, b) return a + (b - a) * v end

function H.round(v) return math.floor(v + 0.5) end

-- roughly gaussian in -1..1, centered on 0
function H.gauss() return (math.random() + math.random() + math.random() - 1.5) / 1.5 end

-- seeded random (Park-Miller), for scenery that should look the same every time
function H.rng(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function()
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  end
end

-- fixed noise per pixel (0..1), so textures like frost and soil hold still
function H.hash(x, y)
  local h = (math.floor(x) * 374761393 + math.floor(y) * 668265263) & 0xffffffff
  h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
  return (h ~ (h >> 16)) / 4294967296
end

-- 4x4 ordered dither, for fog and sky flashes
H.BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
function H.bayer(x, y) return H.BAYER[(math.floor(y) % 4) + 1][(math.floor(x) % 4) + 1] end

return H
