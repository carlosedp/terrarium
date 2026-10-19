-- rain (brain, clocked): drops fall on the norns clock and play where they land.
-- More change brings wind, and the phrase starts to drift.

local H = include('lib/helpers')
local marks = include('lib/scene/marks')

local rain = {
  id = "rain", name = "rain", about = "clocked",
  macros = {
    { id = "rate",   name = "rate",   default = 0.45 },
    { id = "change", name = "change", default = 0.2 },
  },
  -- a drop is spawned one step ahead and its note plays when it lands
  lookahead = true,
  drops = {}, splashes = {},
}

-- beats between drops, slow to fast
-- (the middle of the knob, and the default, is a drop a beat: ambient, not a downpour)
rain.DIVS = { 4, 3, 2, 1, 1 / 2, 1 / 3, 1 / 4 }

function rain.wait(m)
  local div = rain.DIVS[H.round(m[1] * (#rain.DIVS - 1)) + 1]
  clock.sync(div)
  return clock.get_beat_sec() * div
end

function rain.wind(sc) return -6 + sc.m(1, 2) * 34 end

function rain:spawn(ev, dt)
  local fall = H.clamp(dt, 0.12, 1.4)
  table.insert(self.drops, { x = ev.x, t = 0, fall = fall, delay = math.max(0, dt - fall) })
end

function rain:update(dt)
  for i = #self.drops, 1, -1 do
    local d = self.drops[i]
    if d.delay > 0 then d.delay = d.delay - dt else d.t = d.t + dt end
    if d.t >= d.fall then
      table.insert(self.splashes, { x = d.x, t = 0 })
      table.remove(self.drops, i)
    end
  end
  for i = #self.splashes, 1, -1 do
    local s = self.splashes[i]
    s.t = s.t + dt
    if s.t >= 0.18 then table.remove(self.splashes, i) end
  end
end

function rain:draw(cv, sc)
  local GY, wind = sc.GY, rain.wind(sc)
  for _, d in ipairs(self.drops) do
    if d.delay <= 0 then
      local y = -2 + (d.t / d.fall) * (GY + 1)
      local x = d.x - wind * (d.fall - d.t)
      cv.px(x, y, 7)
      cv.px(x - wind * 0.02, y - 1, 3)
    end
  end
  for _, s in ipairs(self.splashes) do
    local f, up = 1 - s.t / 0.18, s.t * 8 - s.t * s.t * 30
    cv.px(s.x - 1 - s.t * 9, GY - 1 - up, 6 * f)
    cv.px(s.x + 1 + s.t * 9, GY - 1 - up, 6 * f)
  end
  marks(cv, sc, "rain")
end

return rain
