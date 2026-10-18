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
  local count = #params:lookup_param(names[layer] .. "_kind").options
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

-- hold K2 + E2 picks the variant and doesn't swap the module; a K2 tap still swaps
for layer = 1, 4 do
  turn(1, -4); turn(1, 1, layer - 1)
  local kind_id = names[layer] .. "_kind"
  local before = params:get(kind_id)
  key(2, 1); turn(2, 1, 2); key(2, 0)
  assert(params:get(kind_id) == before, names[layer] .. ": hold K2 + E2 swapped the module")
  press(2)
  assert(params:get(kind_id) ~= before or #params:lookup_param(kind_id).options == 1, names[layer] .. ": K2 tap did not swap")
  for _ = 1, #params:lookup_param(kind_id).options - 1 do press(2) end -- back to the first module
end
check("hold K2 + E2 variants")

-- visitors: hold K2 + E2 picks the nb voice; notes go to nb, not the engine
turn(1, -4); turn(1, 1)
params:set("voice_kind", 4)
M.run(1.2) -- nb readies its selector after a second
key(2, 1); turn(2, 1); key(2, 0)
assert(params:string("visitors_voice") == "test voice", "visitors: hold K2 + E2 did not pick the nb voice")
local engine_before, nb_before = M.engine_calls.note or 0, M.nb_notes
press(3); press(3); M.run(3)
turn(2, 1, 10); M.run(0.2)
assert(M.nb_notes > nb_before, "visitors: no notes reached the nb voice")
assert((M.engine_calls.note or 0) == engine_before, "visitors: notes also went to the engine")
assert(M.nb_mods > 0, "visitors: E2 never reached the voice's modulate")
check(("visitors via nb (%d notes)"):format(M.nb_notes - nb_before))
params:set("voice_kind", 1)

-- every meadow flora (Plaits engine) blooms its own flower
turn(1, -4); turn(1, 1)
for f = 1, #params:lookup_param("meadow_flora").options do
  params:set("meadow_flora", f)
  press(3); M.run(0.4)
end
check(("meadow: %d flora"):format(#params:lookup_param("meadow_flora").options))

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

-- climate: every attractor moves the macros around where they're set, never out of range
params:set("t_drift", 3) -- fast
for c = 2, #params:lookup_param("t_climate").options do
  params:set("t_climate", c)
  local lo, hi, sum, n = 1, 0, 0, 0
  for _ = 1, 150 do
    M.run(0.1)
    -- the voice slot is back on meadow here; its harm is lin(harmonics, 0.05, 0.95)
    local v = params:get("meadow_harmonics")
    local m = (M.sets.voice_set.harm - 0.05) / 0.9
    lo, hi, sum, n = math.min(lo, m), math.max(hi, m), sum + (m - v), n + 1
  end
  hold1(function() end) -- peek view draws the attractor's path
  check(("climate %s"):format(params:string("t_climate")))
  assert(lo >= -1e-9 and hi <= 1 + 1e-9, "macro left 0..1")
  assert(hi - lo > 0.05, "climate did not move the macro")
  print(("    meadow harmonics swung %.2f..%.2f around %.2f, mean offset %+.2f"):format(
    lo, hi, params:get("meadow_harmonics"), sum / n))
end
params:set("t_climate", 1)

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
