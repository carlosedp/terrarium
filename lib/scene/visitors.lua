-- visitors (voice, audio in): creatures from outside the terrarium. Each note
-- goes out over MIDI to a synth beside the norns, and its sound comes back
-- through the audio input, where water and air shape it like any voice. Each
-- note also opens the input for a moment, so whatever plays into the jack
-- (that synth, a guitar, a radio) is let in by the weather; the creature
-- nearest the note glows for as long as it lasts.
-- The MIDI device is the variant (hold K2 + E2; "none" plays the input only).
-- E2 opens the input between notes too, E3 is the note length.

local H = include('lib/helpers')

local visitors = {
  id = "visitors", name = "visitors", about = "MIDI out, audio in", voice = "input",
  macros = {
    { id = "opening", name = "opening", default = 0.2 },
    { id = "length",  name = "length",  default = 0.4 },
  },
  extra_count = 2, -- the MIDI device and its channel
  variant = "visitors_midi",
  crowd = {}, kind = nil, device_name = nil,
  held = {}, -- notes sounding on the MIDI device, by "port channel note": how many
}

local KINDS = { "ant", "beetle", "moth" }

-- under snow (at full cover): the outside comes in less between notes
visitors.muffle = { open = 0.6 }

function visitors:add_params(changed)
  local ports = { "none" }
  for i = 1, 16 do ports[i + 1] = i .. ": " .. (midi.vports[i] and midi.vports[i].name or "none") end
  params:add_option("visitors_midi", "visitors midi out", ports, 1)
  params:add_number("visitors_channel", "visitors midi channel", 1, 16, 1)
end

-- the same device always brings the same kind of creature
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

-- note length in seconds: 0.1 .. 2 beats (exponential)
local function seconds(sc) return 0.1 * 2 ^ (sc.m(2, 2) * 4.3) * clock.get_beat_sec() end

-- the engine lets the input through: always by opening, and for each note's length
visitors.map = {
  open = { 1, 0, 1, 2 },
}

function visitors:sound(sc)
  local s = sc.mapped(self)
  s.len = math.floor(seconds(sc) * 100 + 0.5) / 100
  return s
end

-- the note goes out over MIDI as well; the engine still opens the input for it
function visitors:play(sc, note, vel)
  local port = params:get("visitors_midi") - 1
  if port < 1 then return end
  local dev, ch = midi.connect(port), params:get("visitors_channel")
  local n, v = H.clamp(math.floor(note + 0.5), 0, 127), H.clamp(math.floor(vel * 127 + 0.5), 1, 127)
  local key = port .. " " .. ch .. " " .. n
  dev:note_on(n, v, ch)
  self.held[key] = (self.held[key] or 0) + 1
  clock.run(function()
    clock.sleep(seconds(sc))
    self.held[key] = self.held[key] - 1
    if self.held[key] <= 0 then -- a repeat of the same note ends with the last one
      self.held[key] = nil
      dev:note_off(n, 0, ch)
    end
  end)
end

-- no note left hanging on the device (a PSET loaded, the script closed)
function visitors:stop()
  for key in pairs(self.held) do
    local port, ch, n = key:match("(%d+) (%d+) (%d+)")
    midi.connect(tonumber(port)):note_off(tonumber(n), 0, tonumber(ch))
  end
  self.held = {}
end

function visitors:on_note(x, sc)
  local near
  for _, c in ipairs(self.crowd) do
    if not near or math.abs(c.x - x) < math.abs(near.x - x) then near = c end
  end
  if near then
    near.target = x
    near.glow = 1
    near.hold = seconds(sc)
  end
end

function visitors:update(dt, sc)
  local name = params:string("visitors_midi")
  if name ~= self.device_name then -- another device: another kind of creature walks in
    self.device_name = name
    self.kind = kind_of(name)
    self.crowd = arrive(self.kind, sc.GY)
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
