-- roots (drone, MiElements): a bowed and blown drone on the key's root, drawn
-- as roots under the ground with light flowing down them. breath moves from
-- bowing to blowing (and speeds the light), depth grows the resonator and its
-- space (and the roots reach further). The Elements model is the variant.
-- K3 hushes it and lets it rise again.

local H = include('lib/helpers')

local KINDS = { "modal", "string", "strings" }

local roots = {
  id = "roots", name = "roots", about = "Elements drone",
  macros = {
    { id = "breath", name = "breath", default = 0.35 },
    { id = "depth",  name = "depth",  default = 0.4 },
  },
  extra_count = 1,
  variant = "roots_model",
  in_front = true, -- drawn after the color layer, so the pond's water doesn't hide the roots
  flow = 0, light = 1,
}

function roots:add_params(changed)
  params:add_option("roots_model", "roots model", KINDS, 2)
  params:set_action("roots_model", changed)
end

-- macro -> MiElements parameter (see doc/SOUND.md; change live with tune() in maiden)
roots.map = {
  bow      = { 1, 0.8, 0.15 }, -- breath turns the bow down...
  blow     = { 1, 0.1, 0.75 }, -- ...and the blowing up
  flow     = { 1, 0.3, 0.7 },
  geom     = { 2, 0.15, 0.6 },
  space    = { 2, 0.3, 0.85 },
  bright   = 0.4,
  damp     = 0.7,
  contour  = 0.8,
  strength = 0.6,
  amp      = 0.3,
}

function roots:sound(sc)
  local s = sc.mapped(self)
  s.model = params:get("roots_model") - 1
  s.pitch = sc.brain.drone_root()
  s.hush = sc.hushed and 0 or 1
  return s
end

-- each root: points going down from the ground (y is below the ground line)
local r = H.rng(800)
local ROOTS = {}
for i = 1, 9 do
  local x, y = 6 + (i - 1) * 14.5 + (r() - 0.5) * 6, 1
  local dir, pts = (r() - 0.5) * 1.2, { { x, 1 } }
  for _ = 1, 7 do
    x, y = x + dir + (r() - 0.5) * 1.6, y + 1.3
    pts[#pts + 1] = { x, y }
  end
  ROOTS[i] = { pts = pts, ph = r(), reach = r() }
end

function roots:update(dt, sc)
  self.flow = self.flow + dt * (0.1 + sc.m(5, 1) * 0.5)
  self.light = self.light + ((sc.hushed and 0 or 1) - self.light) * math.min(1, dt / 1.5)
end

function roots:draw(cv, sc)
  if self.light < 0.02 then return end
  local GY, depth = sc.GY, sc.m(5, 2)
  for _, root in ipairs(ROOTS) do
    if root.reach < 0.35 + depth * 0.65 then
      local n = math.max(2, math.floor(#root.pts * (0.5 + depth * 0.5)))
      local pulse = ((self.flow + root.ph) % 1) * (n + 2) -- light flowing down the root
      for j = 2, n do
        local a, b = root.pts[j - 1], root.pts[j]
        local near = math.max(0, 1 - math.abs(j - pulse) / 1.5)
        local l = (2 + near * 8) * self.light
        local steps = math.max(1, math.ceil(math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2]))))
        for s = 0, steps do -- lit, never darker: water and soil show around the roots
          cv.lit(a[1] + (b[1] - a[1]) * s / steps, GY + a[2] + (b[2] - a[2]) * s / steps, l)
        end
      end
    end
  end
end

return roots
