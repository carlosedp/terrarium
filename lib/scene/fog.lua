-- fog (color, MiRipples): a low filter is a foggy, dim scene. clarity lifts the
-- fog and opens the filter, shimmer waves it as resonance rises.

local H = include('lib/helpers')

local fog = {
  id = "fog", name = "fog", about = "Ripples",
  macros = {
    { id = "clarity", name = "clarity", default = 0.55 },
    { id = "shimmer", name = "shimmer", default = 0.3 },
  },
}

-- macro -> MiRipples parameter (see doc/SOUND.md; change live with tune() in maiden)
fog.map = {
  cf    = { 1, 0.12, 0.92, 1.5 }, -- curved: most of the action in the lower half
  reson = { 2, 0.05, 0.85 },      -- kept below self-oscillation
  drive = { 2, 1, 1.6 },
}

function fog:sound(sc) return sc.mapped(self) end

-- soil under the ground: fixed specks, denser further down, and a few pebbles
local r = H.rng(500)
local PEBBLES = {}
for i = 1, 9 do PEBBLES[i] = { math.floor(r() * 126), 57 + math.floor(r() * 7) } end

local function soil(cv, GY)
  for y = GY + 1, 63 do
    for x = 0, 127 do
      if H.hash(x, y) < 0.06 + (y - GY) * 0.006 then cv.lit(x, y, 1) end
    end
  end
  for _, p in ipairs(PEBBLES) do cv.lit(p[1], p[2], 2); cv.lit(p[1] + 1, p[2], 2) end
end

function fog:draw(cv, sc)
  local c, sh, t, GY = sc.m(3, 1), sc.m(3, 2), sc.t, sc.GY
  soil(cv, GY)
  cv.scale(0.4 + 0.6 * c) -- the whole scene darkens with the filter
  local d = 1 - c
  local ox = math.floor(t * 3)
  for x = 0, 127 do
    local top = GY - 18 + math.sin(x * 0.08 + t * (0.3 + sh * 2.2)) * sh * 5
    for y = math.max(0, math.floor(top)), 63 do
      local p = d * H.clamp((y - top) / 14, 0, 1) * 1.15
      if p * 16 > H.bayer(x + ox, y) then
        cv.px(x, y, (sh > 0.6 and (x + y + ox) % 7 == 0) and 4 or 2)
      end
    end
  end
end

return fog
