-- crystals (voice, MiPlaits 6-op FM): glassy spires that glint when struck.
-- ratio grows them taller and sharper, index throws more sparks.

local H = include('lib/helpers')

local BANKS = { "dx bank 1", "dx bank 2", "dx bank 3" }
local BANK_ENGINE = { 18, 19, 20 }

local crystals = {
  id = "crystals", name = "crystals", about = "Plaits 6-op", voice = "plaits",
  macros = {
    { id = "ratio", name = "ratio", default = 0.4 },
    { id = "index", name = "index", default = 0.45 },
  },
  extra_count = 1,
  variant = "crystals_bank",
  glints = {},
}

local CLUSTERS = {}
for i, x in ipairs({ 10, 30, 52, 76, 98, 118 }) do
  local r = H.rng(50 + i)
  local n = 2 + math.floor(r() * 2)
  local spires = {}
  for k = 0, n - 1 do
    spires[#spires + 1] = {
      dx = (k - (n - 1) / 2) * 4 + (r() - 0.5) * 2,
      h = 5 + r() * 7, lean = (r() - 0.5) * 3, w = 1.5 + r() * 1.2,
    }
  end
  local top = spires[1]
  for _, s in ipairs(spires) do if s.h > top.h then top = s end end
  CLUSTERS[i] = { x = x, spires = spires, top = top }
end

function crystals:add_params(changed)
  params:add_option("crystals_bank", "crystals bank", BANKS, 1)
  params:set_action("crystals_bank", changed)
end

-- macro -> MiPlaits parameter (see doc/SOUND.md; change live with tune() in maiden)
crystals.map = {
  harm   = { 1, 0, 1 },          -- picks the 6-op patch within the bank
  timbre = { 2, 0.15, 0.85 },
  morph  = { 2, 0.3, 0.7 },
  decay  = { "brain", 1, 0.8, 0.5 },
  lpg    = 0.6,
}
-- under snow (at full cover): duller, shorter, and the low-pass gate closes in
crystals.muffle = { timbre = 0.5, decay = 0.45, lpg = 0.7 }

function crystals:sound(sc)
  local s = sc.mapped(self)
  s.engine = BANK_ENGINE[params:get("crystals_bank")]
  return s
end

function crystals:on_note(x, sc)
  local ci = 1
  for i, c in ipairs(CLUSTERS) do
    if math.abs(c.x - x) < math.abs(CLUSTERS[ci].x - x) then ci = i end
  end
  local sparks = {}
  for k = 1, 2 + H.round(sc.m(2, 2) * 8) do
    sparks[k] = { vx = (math.random() - 0.5) * 30, vy = -10 - math.random() * 22 }
  end
  table.insert(self.glints, { c = ci, t = 0, sparks = sparks })
  if #self.glints > 10 then table.remove(self.glints, 1) end
end

function crystals:update(dt)
  for i = #self.glints, 1, -1 do
    local g = self.glints[i]
    g.t = g.t + dt
    if g.t >= 1 then table.remove(self.glints, i) end
  end
end

function crystals:draw(cv, sc)
  local GY, s = sc.GY, 0.6 + sc.m(2, 1)
  local lit = {}
  for _, g in ipairs(self.glints) do lit[g.c] = math.max(lit[g.c] or 0, 1 - g.t) end
  for ci, c in ipairs(CLUSTERS) do
    local glow = lit[ci] or 0
    for _, sp in ipairs(c.spires) do
      local bx = c.x + sp.dx
      local ax, ay = bx + sp.lean * s, GY - sp.h * s
      local lv = 4 + glow * 11
      cv.line(bx - sp.w, GY, ax, ay, lv)
      cv.line(bx + sp.w, GY, ax, ay, lv)
      cv.line(bx, GY, ax, ay, 2 + glow * 5)
    end
  end
  for _, g in ipairs(self.glints) do
    local c = CLUSTERS[g.c]
    local ax, ay = c.x + c.top.dx + c.top.lean * s, GY - c.top.h * s
    for _, sp in ipairs(g.sparks) do
      cv.px(ax + sp.vx * g.t, ay + sp.vy * g.t + 30 * g.t * g.t, 12 * (1 - g.t))
    end
  end
end

return crystals
