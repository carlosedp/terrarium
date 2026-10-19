-- daylight: a slow day and night, the longest arc in the piece. Like the
-- climate it adds to the macros around where you set them: by night the
-- weather slows, the voice darkens, the air grows and the drone comes forward;
-- by day the reverse. The sky shows it: a sun arcing over by day, a moon and
-- stars by night, a glow along the horizon at dawn and dusk.
-- Stateful: included only in terrarium.lua.

local H = include('lib/helpers')

local Day = { kind = 1, phase = 0.25, light = 1 } -- phase: 0 dawn, .25 noon, .5 dusk, .75 midnight

Day.NAMES = { "off", "20 min", "1 hour", "clock" }
local PERIOD = { nil, 20 * 60, 60 * 60 } -- seconds per day; "clock" follows the local time

-- how far each part's macros move at full day (+) and, mirrored, at full night (-)
local DEPTH = {
  { 0.12, 0 },     -- brain: rain falls faster by day, slower at night
  { 0, 0.12 },     -- voice: brighter by day (timbre, index, brightness)
  { 0.1, 0 },      -- color: clearer by day
  { -0.12, -0.1 }, -- air: denser, bigger, longer at night
  { -0.12, 0 },    -- drone: comes forward at night
}

function Day.on() return Day.kind > 1 end

function Day.set(i)
  Day.kind = i
  if i == 4 then Day.sync() end
end

-- the local time of day, as a phase (dawn at 6:00)
function Day.sync()
  local t = os.date("*t")
  Day.phase = ((t.hour + t.min / 60 + t.sec / 3600 - 6) / 24) % 1
end

function Day.update(dt)
  if Day.kind == 4 then Day.sync()
  elseif PERIOD[Day.kind] then Day.phase = (Day.phase + dt / PERIOD[Day.kind]) % 1 end
  Day.light = math.sin(Day.phase * 2 * math.pi) -- +1 noon, -1 midnight
end

function Day.offset(i, k)
  if not Day.on() then return 0 end
  return DEPTH[i][k] * Day.light
end

-- ---------- the sky ----------
local r = H.rng(900)
local STARS = {}
for i = 1, 26 do STARS[i] = { x = 4 + r() * 120, y = 3 + r() * 34, ph = r() * 6.283, bright = 0.4 + r() * 0.6 } end

local function body(p, GY)
  -- across the sky from left horizon to right, highest halfway
  local u = (p % 0.5) / 0.5
  return 6 + u * 116, GY - 6 - math.sin(u * math.pi) * 38
end

function Day.draw(cv, sc)
  if not Day.on() then return end
  local GY, night = sc.GY, math.max(0, -Day.light)
  for _, s in ipairs(STARS) do -- stars come out as the light goes
    local l = night * s.bright * (0.6 + 0.4 * math.sin(sc.t * 1.3 + s.ph)) * 6
    if l >= 1 then cv.lit(s.x, s.y, l) end
  end
  local edge = math.max(0, 1 - math.abs(Day.light) * 4) -- dawn and dusk: a glow along the horizon
  if edge > 0 then
    for y = GY - 12, GY - 1 do
      local p = edge * (y - (GY - 13)) / 12
      for x = 0, 127 do
        if p * 16 > H.bayer(x, y) * 1.6 then cv.lit(x, y, 1 + edge) end
      end
    end
  end
  local x, y = body(Day.phase, GY)
  if Day.phase < 0.5 then -- the sun, with slowly turning rays
    for dy = -2, 2 do for dx = -2, 2 do if dx * dx + dy * dy <= 5 then cv.lit(x + dx, y + dy, 9) end end end
    for k = 0, 5 do
      local a = k / 6 * 2 * math.pi + sc.t * 0.2
      cv.lit(x + math.cos(a) * 4.5, y + math.sin(a) * 4.5, 4)
    end
  else -- the moon, a crescent
    for dy = -3, 3 do
      for dx = -3, 3 do
        if dx * dx + dy * dy <= 9 and (dx - 1.6) ^ 2 + (dy + 0.6) ^ 2 > 6 then cv.lit(x + dx, y + dy, 8) end
      end
    end
  end
end

return Day
