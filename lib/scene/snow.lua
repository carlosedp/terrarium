-- snow (brain, drifting): flakes leave on the norns clock but drift down at
-- their own pace, so they land loosely: on the beat with no change, all over
-- the place at full change, as the wind gusts. They settle on the soil as a
-- layer that muffles it (the voice darkens, its notes shorten and soften).
-- The cover thaws slowly; with the day on, the sun thaws it, the meltwater
-- dripping a few soft notes from the phrase, and the night lets it build up
-- and glow faintly. It thaws away under other weather.

local H = include('lib/helpers')
local marks = include('lib/scene/marks')

local snow = {
  id = "snow", name = "snow", about = "drifting",
  macros = {
    { id = "rate",   name = "rate",   default = 0.5 },
    { id = "change", name = "change", default = 0.3 },
  },
  -- spawn() returns when the flake lands; its note plays then
  drifts = true,
  -- it keeps sc.cover, the snow on the ground (0..1)
  covers = true,
  flakes = {}, drips = {}, melted = 0, mark = 0, window = 0,
}

-- beats between flakes, slow to fast: slower than rain
snow.DIVS = { 8, 6, 4, 3, 2, 3 / 2, 1 }

-- each flake's share of the cover, how fast it thaws (per second, with no day)
-- and how much has to melt for a drip
local SETTLE, MELT, DRIP = 0.025, 1 / 90, 0.04

-- the snowfall around the flakes that play: silent specks, near (brighter, faster) and far,
-- more of them as the rate goes up (their own random numbers, so they don't change the music's)
local FALL = {}
do
  local r = H.rng(77)
  for i = 1, 40 do
    local near = r() < 0.35
    FALL[i] = { x = r() * 128, y = r() * 54, v = near and 7 + r() * 3 or 3.5 + r() * 2,
      l = near and 5 or 3, ph = r() * 6.283 }
  end
end

function snow.wait(m)
  local div = snow.DIVS[H.round(m[1] * (#snow.DIVS - 1)) + 1]
  clock.sync(div)
  return clock.get_beat_sec() * div
end

-- gusts: change blows harder, and never steadily
function snow.wind(sc) return sc.m(1, 2) * (6 + 6 * math.sin(sc.t * 0.23)) end

-- a flake takes a step to fall, and with change up to two and a half, so later ones overtake it
function snow:spawn(ev, dt, sc)
  local fall = dt * (1 + sc.m(1, 2) * math.random() * 1.5)
  local ph, r = math.random() * 6.283, math.random()
  table.insert(self.flakes, { x = ev.x, t = 0, fall = fall, ph = ph, size = r < 0.35 and 0 or (r < 0.8 and 1 or 2) })
  return fall
end

-- meltwater: a soft note from the phrase, and a drop where it falls
local function drip(self, sc)
  if sc.breath.calm > 0.5 then return end
  local notes = {}
  for i = 1, sc.brain.length do
    if sc.brain.reg[i] then notes[#notes + 1] = sc.brain.reg[i] end
  end
  if #notes == 0 then return end
  local ev = notes[math.random(#notes)]
  table.insert(self.drips, { x = ev.x, t = 0 })
  sc.play(ev, false, 0.35)
end

function snow:update(dt, sc)
  for i = #self.flakes, 1, -1 do
    local f = self.flakes[i]
    f.t = f.t + dt
    if f.t >= f.fall then
      sc.cover = sc.cover + SETTLE * (1 - sc.cover)
      table.remove(self.flakes, i)
    end
  end
  -- the thaw: steady with no day; with it, four times faster at noon, four times slower at midnight
  local melt = MELT
  if sc.day.on() then melt = MELT * 4 ^ sc.day.light end
  sc.cover = sc.cover * math.exp(-dt * melt)
  -- when the cover shrinks (the sun is up, or the snow eases off), the meltwater drips
  self.window = self.window + dt
  if self.window >= 4 then
    self.melted = self.melted + math.max(0, self.mark - sc.cover)
    self.mark, self.window = sc.cover, 0
  end
  if self.melted >= DRIP and math.random() < dt * 0.8 then
    self.melted = self.melted - DRIP
    drip(self, sc)
  end
  for i = #self.drips, 1, -1 do
    local d = self.drips[i]
    d.t = d.t + dt
    if d.t >= 0.4 then table.remove(self.drips, i) end
  end
  local wind = snow.wind(sc)
  for _, s in ipairs(FALL) do
    s.y = s.y + s.v * dt
    s.x = (s.x + wind * s.v * 0.04 * dt) % 128
    if s.y > sc.GY then s.y = s.y - sc.GY - 2 end
  end
end

-- a flake: a speck far off, or a little star that tumbles as it falls, its arms turning
-- between + and x; the biggest has longer arms
local function flake(cv, x, y, size, turn)
  cv.px(x, y, 12)
  if size == 0 then return end
  local l = size == 2 and 7 or 5
  if turn then
    cv.px(x - 1, y - 1, l); cv.px(x + 1, y - 1, l); cv.px(x - 1, y + 1, l); cv.px(x + 1, y + 1, l)
  else
    cv.px(x - 1, y, l); cv.px(x + 1, y, l); cv.px(x, y - 1, l); cv.px(x, y + 1, l)
  end
  if size == 2 then -- the long arms stay upright, the short ones turn
    cv.px(x - 2, y, 4); cv.px(x + 2, y, 4); cv.px(x, y - 2, 4); cv.px(x, y + 2, 4)
  end
end

-- the snow's height along the ground, uneven so it starts in patches
local function bump(x) return 0.7 + 0.18 * math.sin(x * 0.09) + 0.12 * math.sin(x * 0.31 + 2) end

function snow:draw(cv, sc)
  local GY, wind = sc.GY, snow.wind(sc)
  local depth = sc.cover * 6
  for i = 1, math.floor(8 + sc.m(1, 1) * 32) do
    local s = FALL[i]
    cv.px(s.x + math.sin(sc.t * 1.3 + s.ph) * 1.2, s.y, s.l)
  end
  for _, f in ipairs(self.flakes) do
    local u = f.t / f.fall
    local y = -2 + u * (GY + 1 - depth)
    local x = f.x - wind * (f.fall - f.t) * 0.3 + math.sin(sc.t * 1.6 + f.ph) * 1.5 * (1 - u)
    flake(cv, H.round(x), H.round(y), f.size, math.floor(sc.t * 1.2 + f.ph) % 2 == 0)
  end
  marks(cv, sc, "snow")
end

-- drawn after the soil: the cover buries the foot of the grass, the reeds and the crystals,
-- with their tops sticking out; its crest catches the light, and at night it glows a little
function snow:draw_front(cv, sc)
  local GY, depth = sc.GY, sc.cover * 6
  local glow = sc.day.on() and math.max(0, -sc.day.light) * 3 or 0
  if depth > 0.3 then
    for x = 0, 127 do
      local h = H.round(depth * bump(x))
      for row = 1, h do cv.px(x, GY - row, (row == h and 9 or 6) + glow) end
    end
  end
  for _, d in ipairs(self.drips) do
    cv.px(d.x, GY - depth * bump(d.x) + d.t * 6, 10 * (1 - d.t / 0.4))
  end
end

return snow
