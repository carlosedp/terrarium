-- marks on the ground for every note in the phrase; new or changed notes glow,
-- the step that just played pulses. Shared by the brain modules.

local H = include('lib/helpers')

return function(cv, sc, kind)
  local B, GY, t = sc.brain, sc.GY, sc.t
  for i = 1, B.length do
    local e = B.reg[i]
    if e then
      local fresh = H.clamp(1 - (t - e.born) / 1.2, 0, 1)
      local hit = (i == B.last_step) and H.clamp(1 - (t - B.last_step_t) / 0.4, 0, 1) or 0
      local lv = 2 + fresh * 8 + hit * 5
      if kind == "rain" then
        cv.line(e.x - 2, GY + 2, e.x + 2, GY + 2, lv)                 -- puddle
      else
        cv.px(e.x, GY + 2, lv)                                        -- scorch mark
        cv.px(e.x - 1, GY + 3, lv * 0.6)
        cv.px(e.x + 1, GY + 3, lv * 0.6)
      end
    end
  end
end
