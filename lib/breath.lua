-- breath: calm spells, silence as part of the music. Now and then, at the end
-- of a phrase, the weather calms for one to three phrases: notes rest (the
-- phrase keeps them, they come back after) and their marks dim, then it
-- breathes in again. With the climate on, the calm also follows its first
-- output, so the calm and the gusts line up.
-- Stateful: included only in terrarium.lua.

local Breath = { kind = 1, calm = 0, target = 0, left = 0 }

Breath.NAMES = { "off", "gentle", "deep" }
local CHANCE = { 0, 0.2, 0.35 } -- a spell starting, at each phrase end
local DEPTH = { 0, 0.55, 0.85 } -- how many notes rest at the bottom of a spell

function Breath.set(i)
  Breath.kind = i
  if i == 1 then Breath.target, Breath.left = 0, 0 end
end

-- at each phrase end: a spell goes on, ends, or begins
function Breath.phrase()
  if Breath.kind == 1 then return end
  if Breath.left > 0 then
    Breath.left = Breath.left - 1
    if Breath.left == 0 then Breath.target = 0 end
  elseif math.random() < CHANCE[Breath.kind] then
    Breath.left = math.random(1, 3)
    Breath.target = DEPTH[Breath.kind] * (0.7 + math.random() * 0.3)
  end
end

-- breathe out and in over a few seconds; climate_x (-1..1) or nil
function Breath.update(dt, climate_x)
  local target = Breath.target
  if climate_x and Breath.kind > 1 then target = math.max(target, DEPTH[Breath.kind] * math.max(0, -climate_x) * 0.6) end
  Breath.calm = Breath.calm + (target - Breath.calm) * math.min(1, dt / 4)
end

-- should this note rest?
function Breath.rest() return Breath.calm > 0.01 and math.random() < Breath.calm end

return Breath
