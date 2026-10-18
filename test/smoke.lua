-- Headless smoke test: loads terrarium with a mocked norns, plays every module,
-- gesture and setting, and reports screen calls per frame.
--
--   lua test/smoke.lua        (Lua 5.3+, from the repo root)

local M = dofile((arg[0]:match("^(.*)/[^/]+$") or ".") .. "/mock_norns.lua")
math.randomseed(1)

dofile(M.ROOT .. "/terrarium.lua")
assert(engine.name == "Terrarium", "engine.name not set")
init()
params:check_groups()

local function turn(n, d, times) for _ = 1, times or 1 do enc(n, d) end end
local function press(n) key(n, 1); key(n, 0) end
local function hold1(f) key(1, 1); f(); M.run(0.3); key(1, 0) end
local function check(label) print(("ok  %-34s notes so far: %d"):format(label, M.engine_calls.note or 0)) end

M.run(4); check("default scene (rain/meadow/pond/clouds)")

-- every module in every slot, with macros pushed both ways and each gesture
local names = { "brain", "voice", "color", "air" }
for layer = 1, 4 do
  turn(1, -4); turn(1, 1, layer - 1)
  local count = #params:lookup(names[layer] .. "_kind").options
  for _ = 1, count do
    turn(2, 1, 60); turn(3, 1, 60); M.run(1.5)
    turn(2, -1, 60); turn(3, -1, 60); M.run(1.5)
    turn(2, 1, 25); turn(3, 1, 25)
    press(3); M.run(1)
    press(3); M.run(0.5)
    check(names[layer] .. " -> " .. params:string(names[layer] .. "_kind"))
    press(2)
  end
end

-- settings while holding K1: every setting, both directions, plus seasons running
hold1(function()
  for s = 1, 5 do
    turn(2, -5); turn(2, 1, s - 1)
    turn(3, 1, 12); turn(3, -1, 3)
  end
end)
check("settings via K1")
params:set("t_seasons", 4) -- quick
params:set("rain_change", 0.6)
M.run(40)
check("40 s with seasons quick")
print(("    key drifted to %s %s"):format(params:string("t_root"), params:string("t_scale")))

-- the installer path when mi-UGens are missing
local loaded = M
loaded.has_mi = false
dofile(M.ROOT .. "/terrarium.lua")
init()
key(3, 1); key(3, 0)
assert(loaded.last_system_cmd and loaded.last_system_cmd:match("install.sh"), "installer did not run install.sh")
M.run(0.5)
check("installer path (no mi-UGens)")

print(("\nframes: %d, screen calls per frame: avg %.0f, max %d"):format(
  M.frames, M.total_calls / M.frames, M.max_calls))
print("engine commands:")
for k, v in pairs(M.engine_calls) do print(("  %-12s %d"):format(k, v)) end
