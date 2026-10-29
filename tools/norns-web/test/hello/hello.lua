-- hello: the smallest script norns-web runs, for trying it and for its tests.
-- A dot drifts across the screen; E2 sets its speed, E3 its size, K3 reverses it.
--
--   node serve.mjs test/hello

local x, dir = 64, 1

function init()
  params:add_control("speed", "speed", controlspec.new(0, 4, "lin", 0.1, 1))
  params:add_number("size", "size", 1, 8, 3)
  clock.run(function()
    while true do
      clock.sleep(1 / 30)
      x = x + dir * params:get("speed")
      if x < 0 or x > 127 then dir = -dir; x = util.clamp(x, 0, 127) end
      redraw()
    end
  end)
end

function enc(n, d)
  if n == 2 then params:delta("speed", d) end
  if n == 3 then params:delta("size", d) end
end

function key(n, z)
  if n == 3 and z == 1 then dir = -dir end
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.circle(x, 32, params:get("size"))
  screen.fill()
  screen.level(4)
  screen.move(2, 62)
  screen.text("hello")
  screen.update()
end
