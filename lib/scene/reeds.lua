-- reeds (voice, MiRings): a reed bed by the water. Each note plucks the
-- nearest reed and it vibrates like the string it is. structure grows the
-- reeds taller and bends them (stranger resonances), brightness lights their
-- heads. The Rings model is the variant (hold K2 + E2); sympathetic strings
-- set the neighbors ringing too.

local H = include('lib/helpers')

local KINDS = { "modal", "sympathetic strings", "inharmonic string", "fm voice", "quantized strings", "string + reverb" }

local reeds = {
  id = "reeds", name = "reeds", about = "Rings", voice = "rings",
  macros = {
    { id = "structure",  name = "structure",  default = 0.4 },
    { id = "brightness", name = "brightness", default = 0.5 },
  },
  extra_count = 1,
  variant = "reeds_model",
}

local r = H.rng(600)
local REEDS = {}
for i = 1, 22 do
  REEDS[i] = {
    x = 3 + (i - 1) * 5.6 + (r() - 0.5) * 3, h = 0.55 + r() * 0.45, lean = (r() - 0.5) * 2,
    kink = (r() - 0.5) * 2, head = r() < 0.75, ph = r() * 6.283, f = 9 + r() * 5, amp = 0,
  }
end

function reeds:add_params(changed)
  params:add_option("reeds_model", "reeds model", KINDS, 1)
  params:set_action("reeds_model", changed)
end

-- macro -> MiRings parameter (see doc/SOUND.md; change live with tune() in maiden)
reeds.map = {
  struct = { 1, 0.15, 0.9 },
  bright = { 2, 0.2, 0.85 },
  damp   = { "brain", 1, 0.75, 0.45 }, -- fast rain, shorter rings
  pos    = 0.3,
}

function reeds:sound(sc)
  local s = sc.mapped(self)
  s.model = params:get("reeds_model") - 1
  return s
end

function reeds:on_note(x)
  local near = 1
  for i, rd in ipairs(REEDS) do
    if math.abs(rd.x - x) < math.abs(REEDS[near].x - x) then near = i end
  end
  REEDS[near].amp = 1
  local sym = params:get("reeds_model") == 2 and 0.6 or 0.2 -- sympathetic strings ring their neighbors
  for _, j in ipairs({ near - 1, near + 1 }) do
    if REEDS[j] then REEDS[j].amp = math.max(REEDS[j].amp, sym) end
  end
end

function reeds:update(dt, sc)
  local k = math.exp(-dt * (1 + sc.m(1, 1) * 2.5)) -- rings shorter in fast rain, like the sound
  for _, rd in ipairs(REEDS) do rd.amp = rd.amp * k end
end

function reeds:draw(cv, sc)
  local GY, t = sc.GY, sc.t
  local st, br = sc.m(2, 1), sc.m(2, 2)
  local len = 10 + st * 14
  for _, rd in ipairs(REEDS) do
    local L = len * rd.h
    local steps = math.ceil(L)
    local x, y
    for j = 0, steps do
      local s = j / steps
      -- a standing wave along the stalk while it rings; structure kinks it
      local wave = rd.amp * math.sin(math.pi * s) * math.sin(t * rd.f + rd.ph) * 2.5
      x = rd.x + rd.lean * s + rd.kink * st * 2 * math.max(0, s - 0.6) + wave
      y = GY - s * L
      cv.px(x, y, 3 + rd.amp * 9)
    end
    if rd.head then -- the seed head: brighter with brightness and while it rings
      local l = 3 + br * 6 + rd.amp * 6
      cv.px(x, y - 1, l); cv.px(x, y - 2, l); cv.px(x, y - 3, l * 0.8)
      if rd.amp > 0.4 and br > 0.5 then cv.px(x + math.sin(t * 20 + rd.ph) * 2, y - 5, l * 0.6) end
    end
  end
end

return reeds
