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
local names = { "brain", "voice", "color", "air", "drone" }
for layer = 1, #names do
  turn(1, -5); turn(1, 1, layer - 1)
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
for layer = 1, #names do
  turn(1, -5); turn(1, 1, layer - 1)
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
turn(1, -5); turn(1, 1)
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

-- the drone: root of the key (and it follows it), K3 hushes and lets it rise
turn(1, -5); turn(1, 4)
for k = 1, #params:lookup_param("drone_kind").options - 1 do -- every drone but none
  params:set("drone_kind", k); M.run(0.3)
  assert(M.sets.drone_set.pitch == 48 + params:get("t_root") - 1, "drone: not on the key's root")
end
params:set("drone_kind", 1)
params:set("t_root", 8); M.run(0.2)
assert(M.sets.drone_set.pitch == 48 + 7, "drone: didn't follow a new key")
press(3); M.run(0.2)
assert(M.sets.drone_set.hush == 0, "drone: K3 didn't hush it")
press(3); M.run(0.2)
assert(M.sets.drone_set.hush == 1, "drone: K3 didn't let it rise")
params:set("drone_kind", #params:lookup_param("drone_kind").options) -- none
turn(2, 1, 5); turn(3, -1, 5); press(3); press(3); M.run(0.5)                 -- nothing to turn, no errors
assert(params:string("drone_kind") == "none", "drone: none isn't the last module")
params:set("t_root", 3); params:set("drone_kind", 1)
check("drone (root, key, hush, none)")

-- the day: it starts at noon, where the voice's second macro sits higher; off puts it back
params:set("voice_kind", 1); params:set("meadow_timbre", 0.5)
params:set("t_day", 2); M.run(0.2)
local noon = M.sets.voice_set.timbre
params:set("t_day", 1); M.run(0.2)
assert(noon > M.sets.voice_set.timbre + 0.05, "day: noon didn't brighten the voice")
for d = 2, #params:lookup_param("t_day").options do params:set("t_day", d); M.run(2) end
params:set("t_day", 1)
check("day (offsets, every mode)")

-- breath: deep calm spells let notes rest, so fewer play than without
params:set("brain_kind", 2); params:set("lightning_rate", 0.6); params:set("lightning_change", 0)
local function notes_in(sec) local before = M.engine_calls.note or 0; M.run(sec); return (M.engine_calls.note or 0) - before end
params:set("t_breath", 1); local open_air = notes_in(90)
params:set("t_breath", 3); local calm = notes_in(90)
assert(calm < open_air * 0.95, ("breath: %d notes with deep breath, %d without"):format(calm, open_air))
params:set("t_breath", 1); params:set("brain_kind", 1)
check(("breath (%d notes vs %d)"):format(calm, open_air))

-- freeze and hush are params (so PSETs keep them), and K3 flips them
turn(1, -5); turn(1, 3); press(3)
assert(params:get("air_freeze") == 2, "K3 on air didn't set the freeze param")
params:set("air_freeze", 1); M.run(0.2)
assert(M.sets.air_set.freeze == 0, "the freeze param didn't thaw the air")
turn(1, 1); press(3); M.run(0.2)
assert(params:get("drone_hush") == 2 and M.sets.drone_set.hush == 0, "K3 on the drone didn't hush it through its param")
params:set("drone_hush", 1); M.run(0.2)
assert(M.sets.drone_set.hush == 1, "the hush param didn't let the drone rise")
check("freeze and hush as params")

-- hold K1 + K3: a new terrarium, settings too, but never visitors, none or the day
params:set("t_day", 3)
local keys = {}
for _ = 1, 25 do
  key(1, 1); key(3, 1); key(3, 0); key(1, 0); M.run(0.3)
  assert(params:string("voice_kind") ~= "visitors" and params:string("drone_kind") ~= "none", "scramble picked visitors or none")
  assert(params:get("t_day") == 3, "scramble changed the day")
  keys[params:get("t_root")] = true
end
local n_keys = 0; for _ in pairs(keys) do n_keys = n_keys + 1 end
assert(n_keys > 3, "scramble didn't change the key")
params:set("t_randomize", 1); M.run(0.3)
-- back to a still jar for the tests below
params:set("t_day", 1); params:set("t_climate", 1); params:set("t_breath", 1); params:set("t_seasons", 1)
params:set("voice_kind", 1); params:set("drone_kind", 1)
check("K1 + K3: a new terrarium")

-- tuning from maiden: tune() remaps a parameter live; levels reach the synths as vol
params:set("air_kind", 1) -- clouds
params:set("clouds_size", 1)
tune("clouds", "rvb", 2, 0.1, 0.6)
M.run(0.2)
assert(math.abs(M.sets.air_set.rvb - 0.6) < 1e-6, "tune: clouds rvb didn't follow its macro")
tune("clouds", "rvb", 0.3)
M.run(0.2)
assert(M.sets.air_set.rvb == 0.3, "tune: clouds rvb didn't go back to a fixed value")
tune("meadow", "decay", "brain", 1, 0.75, 0.4)
tune() -- lists the modules
params:set("level_air", -60)
M.run(0.2)
assert(M.sets.air_set.vol == 0, "levels: air level didn't reach the synth")
params:set("level_air", 0)
check("tune() and levels")

-- every meadow flora (Plaits engine) blooms its own flower
turn(1, -5); turn(1, 1)
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

-- an older mi-UGens install without Beads: the installer, like none at all
M.relaunch()
M.has_beads = false
dofile(M.ROOT .. "/terrarium.lua")
init()
key(3, 1); key(3, 0)
assert(M.last_system_cmd and M.last_system_cmd:match("install.sh"), "no installer for a build without Beads")
M.run(0.3)
check("older mi-UGens (no Beads): installer")
M.has_beads = true
M.last_system_cmd = nil

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
