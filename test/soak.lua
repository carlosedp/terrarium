-- Soak test: hours of jar time, headless, with everything that moves switched on (climate,
-- a 20-minute day, seasons, breath) and a new terrarium every 20 minutes, the way a norns
-- left running all evening would go. Checks what only shows up over hours: tables or memory
-- that keep growing, values that drift out of range or turn into NaN, and states that get
-- stuck (silence, a hush that never lifts, snow that never thaws).
--
--   lua test/soak.lua [hours, default 8]      (make soak; about 2 minutes per hour of jar time)

local hours = tonumber(arg[1]) or 8
local M = dofile((arg[0]:match("^(.*)/[^/]+$") or ".") .. "/mock_norns.lua")
math.randomseed(7)

-- keep hold of the stateful modules, to look inside them
local real_include, mods = include, {}
function include(p)
  local m = real_include(p)
  if p == "lib/brain" or p == "lib/glass" or p:match("^lib/scene/") then mods[p] = m end
  return m
end
dofile(M.ROOT .. "/terrarium.lua")
init()

local function setup()
  params:set("t_day", 2) -- a 20-minute day
  params:set("t_drift", 2)
  if params:get("t_climate") == 1 then params:set("t_climate", 4) end -- tides
  if params:get("t_seasons") == 1 then params:set("t_seasons", 3) end
  if params:get("t_breath") == 1 then params:set("t_breath", 2) end
end
setup()

local failures = {}
local function fail(msg)
  if not failures[msg] then print("FAIL " .. msg) end
  failures[msg] = true
end
local function finite(v) return type(v) ~= "number" or (v == v and v > -1e9 and v < 1e9) end

local function check_sets()
  for slot, t in pairs(M.sets) do
    for k, v in pairs(t) do
      if not finite(v) then fail(("%s.%s is %s"):format(slot, k, tostring(v))) end
    end
  end
  local d = M.sets.drone_set
  if d and params:string("drone_kind") ~= "none" then
    if d.hush ~= 1 then fail("the hum stayed hushed with nobody pressing K3") end
    if d.duck and (d.duck < 0 or d.duck > 1) then fail("duck out of 0..1: " .. d.duck) end
  end
end

-- the largest any growing list gets
local most = {}
local function size(name, n) most[name] = math.max(most[name] or 0, n) end
local function check_sizes()
  local snow, glass, brain = mods["lib/scene/snow"], mods["lib/glass"], mods["lib/brain"]
  size("snow flakes", #snow.flakes); size("snow drips", #snow.drips)
  size("glass beads", #glass.beads)
  size("clock coroutines", #M.coroutines)
  size("phrase steps", #brain.reg)
  size("pond rings", #mods["lib/scene/pond"].rings)
  size("meadow flowers", #mods["lib/scene/meadow"].flowers)
end

collectgarbage("collect")
local mem0 = collectgarbage("count")
print(("soak: %d hours of jar time; memory at start %.0f KB"):format(hours, mem0))
print(" hour  notes  memory KB  key          weather / soil / water / air / hum")

local mem_hour1
for h = 1, hours do
  local notes0 = M.engine_calls.note or 0
  for minute = 1, 60 do
    M.run(60)
    check_sets(); check_sizes()
    if minute % 20 == 0 then -- a new terrarium, as K1 + K3 would make it
      params:set("t_randomize", 1)
      setup()
    end
  end
  local notes = (M.engine_calls.note or 0) - notes0
  if notes < 200 then fail(("only %d notes in hour %d"):format(notes, h)) end
  collectgarbage("collect")
  local mem = collectgarbage("count")
  if h == 1 then mem_hour1 = mem end
  local parts = {}
  for _, id in ipairs({ "brain", "voice", "color", "air", "drone" }) do parts[#parts + 1] = params:string(id .. "_kind") end
  print(("%5d %6d %10.0f  %-12s %s"):format(h, notes, mem, params:string("t_root") .. " " .. params:string("t_scale"),
    table.concat(parts, " / ")))
end

collectgarbage("collect")
local mem = collectgarbage("count")
if hours > 1 and mem > mem_hour1 * 1.25 + 200 then
  fail(("memory grew from %.0f KB after the first hour to %.0f KB"):format(mem_hour1, mem))
end
print("\nlargest each list got:")
local names = {}
for k in pairs(most) do names[#names + 1] = k end
table.sort(names)
for _, k in ipairs(names) do print(("  %-18s %d"):format(k, most[k])) end
if most["clock coroutines"] > 60 then fail("clock coroutines piled up: " .. most["clock coroutines"]) end
if most["snow flakes"] > 40 then fail("snow flakes piled up: " .. most["snow flakes"]) end

if next(failures) then
  print("\nsoak FAILED")
  os.exit(1)
end
print(("\nsoak ok: %d hours, %d frames"):format(hours, M.frames))
