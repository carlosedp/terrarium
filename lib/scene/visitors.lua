-- visitors (voice, nb): voices from outside the terrarium (nb mods, MIDI, Just
-- Friends...) arrive as creatures. Which creature depends on the voice: ants,
-- beetles or moths. Each note calls the nearest one over, and it glows for as
-- long as the note lasts. Their sound is their own: they come from outside
-- the jar, so the color and air parts don't touch it.
-- The nb voice is the variant (hold K2 + E2). E2 is the voice's own
-- "modulate" (each voice decides what that does), E3 the note length.

local H = include('lib/helpers')

local visitors = {
  id = "visitors", name = "visitors", about = "nb", voice = "none",
  macros = {
    { id = "modulate", name = "modulate", default = 0.5 },
    { id = "length",   name = "length",   default = 0.4 },
  },
  extra_count = 2, -- nb's voice selector and its hidden companion
  variant = "visitors_voice",
  crowd = {}, kind = nil, voice_name = nil, last_mod = nil,
}

local KINDS = { "ant", "beetle", "moth" }

local function player() return params:lookup_param("visitors_voice"):get_player() end

-- the same voice always brings the same kind of creature
local function kind_of(name)
  local sum = 0
  for i = 1, #name do sum = sum + name:byte(i) end
  return KINDS[sum % #KINDS + 1]
end

local function arrive(kind, GY)
  local crowd = {}
  for i = 1, 6 do
    crowd[i] = {
      x = -3 - i * 4, target = nil, glow = 0, ph = math.random() * 6.283, -- file in from the left
      vx = 6 + math.random() * 8, y = kind == "moth" and 18 + math.random() * 22 or GY - 1,
    }
  end
  return crowd
end

function visitors:add_params(changed, sc)
  sc.nb:add_param("visitors_voice", "visitors voice")
end

-- note length in beats: 0.1 .. 2
local function beats(sc) return 0.1 * 2 ^ (sc.m(2, 2) * 4.3) end

function visitors:play(sc, note, vel)
  player():play_note(math.floor(note + 0.5), vel, beats(sc))
end

-- no engine voice; E2 goes to the nb voice's modulate, only when it moves
function visitors:sound(sc)
  local v = sc.m(2, 1)
  if v ~= self.last_mod then
    self.last_mod = v
    player():modulate(v)
  end
  return {}
end

function visitors:on_note(x, sc)
  local near
  for _, c in ipairs(self.crowd) do
    if not near or math.abs(c.x - x) < math.abs(near.x - x) then near = c end
  end
  if near then
    near.target = x
    near.glow = 1
    near.hold = beats(sc) * clock.get_beat_sec()
  end
end

function visitors:update(dt, sc)
  local name = params:string("visitors_voice")
  if name ~= self.voice_name then -- a new voice: a new kind of creature walks in
    self.voice_name = name
    self.kind = name ~= "none" and kind_of(name) or nil
    self.crowd = self.kind and arrive(self.kind, sc.GY) or {}
  end
  local lively = 0.4 + sc.m(2, 1) * 1.2
  for _, c in ipairs(self.crowd) do
    if c.target then -- hurry to the note
      local d = c.target - c.x
      c.x = c.x + H.clamp(d, -40 * dt, 40 * dt)
      if math.abs(d) < 1 then c.target = nil end
    else -- wander, turning back at the glass
      c.x = c.x + c.vx * lively * dt
      if (c.x > 124 and c.vx > 0) or (c.x < 3 and c.vx < 0) then c.vx = -c.vx end
    end
    c.hold = (c.hold or 0) - dt
    if c.hold <= 0 then c.glow = math.max(0, c.glow - dt * 3) end
    c.ph = c.ph + dt * (6 + lively * 6)
  end
end

function visitors:draw(cv, sc)
  local GY = sc.GY
  for _, c in ipairs(self.crowd) do
    local l = 5 + c.glow * 10
    local dir = (c.target and c.target > c.x or not c.target and c.vx > 0) and 1 or -1
    if self.kind == "ant" then
      cv.px(c.x, GY - 1, l); cv.px(c.x - dir, GY - 1, l * 0.8)
      cv.px(c.x + dir, GY - 2, l * 0.6) -- antenna
      if math.sin(c.ph) > 0 then cv.px(c.x, GY - 2, l * 0.3) end -- legs flicker
    elseif self.kind == "beetle" then
      cv.rect(c.x - 1, GY - 2, 3, 2, l)
      cv.px(c.x + 2 * dir, GY - 2, l * 0.6)
      if math.sin(c.ph) > 0 then cv.px(c.x - 2 * dir, GY - 1, l * 0.4) end
    else -- moth: flutters, wings beating
      local y = c.y + math.sin(c.ph * 0.4) * 2
      local w = math.sin(c.ph) > 0 and -1 or 0
      cv.px(c.x, y, l)
      cv.px(c.x - 1, y + w, l * 0.6); cv.px(c.x + 1, y + w, l * 0.6)
    end
  end
end

return visitors
