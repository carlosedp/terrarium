-- terrarium
-- a small world of
-- Mutable Instruments
--
-- E1 choose a part
-- E2 E3 shape it
-- K2 swap its module
-- hold K2 + E2: its variant
-- K3 gesture
-- hold K1: peek + settings
--
-- needs mi-UGens

engine.name = "Terrarium"

local H = include("lib/helpers")
local cv = include("lib/canvas")
local Brain = include("lib/brain")
local installer = include("lib/installer")
local glass = include("lib/glass")
local Climate = include("lib/climate")

local FPS = 15
local GY = 54 -- the ground line

-- the four parts of the scene, back to front: brain = weather, voice = ground,
-- color = light and water, air = sky
local LAYERS = {
  { id = "brain", name = "brain", mods = { include("lib/scene/rain"), include("lib/scene/lightning") } },
  { id = "voice", name = "voice", mods = { include("lib/scene/meadow"), include("lib/scene/crystals") } },
  { id = "color", name = "color", mods = { include("lib/scene/pond"), include("lib/scene/fog") } },
  { id = "air",   name = "air",   mods = { include("lib/scene/clouds"), include("lib/scene/fireflies"), include("lib/scene/mountains") } },
}
local SLOT_SET = { nil, "voice_set", "color_set", "air_set" }

local SETTINGS = { "t_root", "t_scale", "t_range", "t_length", "t_seasons", "t_climate", "t_drift" }
local SETTING_NAMES = { "key", "scale", "range", "length", "seasons", "climate", "drift" }
local LENGTHS = { 4, 8, 12, 16 }
local SEASONS = { 0, 8, 4, 2 } -- phrases between turns: off, slow, steady, quick

-- climate: which attractor output (1 x, 2 y, 3 z) moves each macro, and how much
-- by default (the per-macro cv param, -1..1; full cv swings a macro by +-0.5)
local CV_SRC = { { 3, 1 }, { 1, 2 }, { 2, 3 }, { 3, 1 } }
local CV_DEFAULT = { { 0, 0.3 }, { 0.4, 0.3 }, { 0.35, 0.25 }, { 0.35, 0.3 } }

-- shared scene state handed to every module
local sc = { t = 0, GY = GY, frozen = false, fly_t = 0, brain = Brain }
function sc.cur(i) return LAYERS[i].mods[params:get(LAYERS[i].id .. "_kind")] end
function sc.kind(i) return sc.cur(i).id end
-- a macro as you set it
function sc.base(i, k)
  local mod = sc.cur(i)
  return params:get(mod.id .. "_" .. mod.macros[k].id)
end
-- a macro as it plays: your setting is the center, the climate adds to it like
-- CV. Rounded so a slow drift doesn't flood the engine with tiny changes.
function sc.m(i, k)
  local v = sc.base(i, k)
  if not Climate.on() then return v end
  local mod = sc.cur(i)
  local cv = params:get(mod.id .. "_" .. mod.macros[k].id .. "_cv")
  v = v + cv * 0.5 * Climate.out[CV_SRC[i][k]]
  return H.clamp(math.floor(v * 200 + 0.5) / 200, 0, 1)
end
-- the weather's wind, shared with the sky (never blowing backwards)
function sc.wind() return math.max(0, sc.cur(1).wind(sc)) end

local sel, focus_t, k1 = 1, 0, false
local k2, k2_turned = false, false -- K2 tap swaps the module; hold K2 + E2 picks its variant
local toast, toast_t = "", 0
local set_cursor = 1
local dirty_sound = true
local sent = { {}, {}, {}, {} } -- last values sent to the engine, per slot
local seasoning = false
local redraw_metro

local function say(text) toast, toast_t = text, 1.8 end
local function focus() focus_t = 2.5 end

-- ---------- sound ----------

local function send_sound()
  for i = 2, 4 do
    local fn = engine[SLOT_SET[i]]
    for k, v in pairs(sc.cur(i):sound(sc)) do
      if sent[i][k] ~= v then
        fn(k, v)
        sent[i][k] = v
      end
    end
  end
  dirty_sound = false
end

local function play(ev, fresh)
  engine.note(Brain.pitch(ev.x), fresh and 1 or 0.7)
  for i = 2, 4 do
    local mod = sc.cur(i)
    if mod.on_note then mod:on_note(ev.x, sc) end
  end
end

-- the brain: wait (clock sync or random sleep), step the phrase, play
local function brain_loop()
  local pending, pending_fresh
  while true do
    local mod = sc.cur(1)
    local m = { sc.m(1, 1), sc.m(1, 2) }
    local dt = mod.wait(m)
    local ev, fresh = Brain.step(m[2], sc.t)
    if mod.lookahead then -- rain: the drop spawned last step lands now
      if pending then play(pending, pending_fresh) end
      pending, pending_fresh = ev, fresh
      if ev then mod:spawn(ev, dt, sc) end
    else
      pending = nil
      if ev then
        mod:spawn(ev, dt, sc)
        play(ev, fresh)
      end
    end
  end
end

local function on_kind(i)
  local mod = sc.cur(i)
  if i == 3 then engine.color_kind(mod.id) elseif i == 4 then engine.air_kind(mod.id) end
  sent[i] = {}
  dirty_sound = true
end

-- ---------- params ----------

local function add_params()
  local changed = function() dirty_sound = true end

  params:add_separator("terrarium", "terrarium")
  params:add_group("terrarium_settings", "settings", #SETTINGS)
  params:add_option("t_root", "key", Brain.NOTES, Brain.root + 1)
  params:set_action("t_root", function(v)
    Brain.root = v - 1
    if not seasoning then Brain.set_home() end
  end)
  params:add_option("t_scale", "scale", Brain.scale_names(), Brain.scale)
  params:set_action("t_scale", function(v)
    Brain.scale = v
    if not seasoning then Brain.set_home() end
  end)
  params:add_number("t_range", "range", 1, 3, Brain.octaves, function(p) return p:get() .. " oct" end)
  params:set_action("t_range", function(v) Brain.octaves = v end)
  params:add_option("t_length", "length", { "4 steps", "8 steps", "12 steps", "16 steps" }, 2)
  params:set_action("t_length", function(v)
    Brain.length = LENGTHS[v]
    Brain.pos = Brain.pos % Brain.length
  end)
  params:add_option("t_seasons", "seasons", { "off", "slow", "steady", "quick" }, 1)
  params:set_action("t_seasons", function(v)
    Brain.season_every = SEASONS[v]
    Brain.phrases = 0
  end)
  params:add_option("t_climate", "climate", Climate.NAMES, 1)
  params:set_action("t_climate", function(v)
    Climate.set(v)
    dirty_sound = true
  end)
  params:add_option("t_drift", "drift", Climate.DRIFTS, 2)

  for i, L in ipairs(LAYERS) do
    local names, count = {}, 1
    for _, m in ipairs(L.mods) do
      names[#names + 1] = m.name
      count = count + #m.macros * 2 + (m.extra_count or 0) -- each macro and its cv
    end
    params:add_group("terrarium_" .. L.id, L.name, count)
    params:add_option(L.id .. "_kind", L.name, names, 1)
    params:set_action(L.id .. "_kind", function() on_kind(i) end)
    for _, m in ipairs(L.mods) do
      for k, mac in ipairs(m.macros) do
        local id = m.id .. "_" .. mac.id
        params:add_control(id, m.name .. " " .. mac.name, controlspec.new(0, 1, "lin", 0, mac.default, "", 0.02))
        params:set_action(id, changed)
        params:add_control(id .. "_cv", m.name .. " " .. mac.name .. " cv",
          controlspec.new(-1, 1, "lin", 0, CV_DEFAULT[i][k], "", 0.01))
        params:set_action(id .. "_cv", changed)
      end
      if m.add_params then m:add_params(changed) end
    end
  end
end

-- the season turned: show it in the settings without moving home
Brain.on_season = function()
  seasoning = true
  params:set("t_root", Brain.root + 1)
  params:set("t_scale", Brain.scale)
  seasoning = false
  say(Brain.key_name())
end

-- ---------- drawing ----------

local function peek_canvas()
  cv.clear_rect(0, 0, 128, 52)
  for i, L in ipairs(LAYERS) do
    local y, on, mod = 3 + (i - 1) * 9, i == sel, sc.cur(i)
    for k = 1, #mod.macros do
      local bx = 76 + (k - 1) * 26
      cv.rect(bx, y, 22, 3, 2)
      cv.rect(bx, y, math.max(1, H.round(sc.base(i, k) * 22)), 3, on and 13 or 6)
      if Climate.on() then -- where the climate has pushed it right now
        cv.rect(bx + math.min(21, H.round(sc.m(i, k) * 22)), y - 1, 1, 5, on and 15 or 9)
      end
    end
  end
  for j = 1, #SETTINGS do cv.rect(100 + (j - 1) * 4, 40, 2, 2, j == set_cursor and 13 or 3) end
  if SETTINGS[set_cursor] == "t_climate" or SETTINGS[set_cursor] == "t_drift" then
    local n = #Climate.trail -- the attractor's recent path (x across, z up), next to its name
    for j, q in ipairs(Climate.trail) do cv.px(82 + q[1] * 16, 46 - q[2] * 3.5, 1 + 12 * j / n) end
  end
  for i = 1, Brain.length do
    cv.rect(2 + (i - 1) * 3, 46, 2, 3, Brain.reg[i] and (i == Brain.last_step and 15 or 7) or 2)
  end
  cv.line(0, 51, 127, 51, 3)
end

local function peek_text()
  for i, L in ipairs(LAYERS) do
    local y, on = 2 + (i - 1) * 9, i == sel
    screen.level(on and 15 or 6)
    screen.move(2, y + 5)
    screen.text(L.name)
    screen.level(on and 12 or 5)
    screen.move(26, y + 5)
    screen.text(sc.cur(i).name)
  end
  -- the value sits past the widest setting name, so no name runs into it
  local col = 0
  for _, name in ipairs(SETTING_NAMES) do col = math.max(col, screen.text_extents(name) or 28) end
  screen.level(6)
  screen.move(2, 44)
  screen.text(SETTING_NAMES[set_cursor])
  screen.level(13)
  screen.move(2 + col + 5, 44)
  screen.text(params:string(SETTINGS[set_cursor]))
end

function redraw()
  screen.clear()
  screen.aa(0)
  if installer.active then
    installer.draw()
    screen.update()
    return
  end

  cv.clear()
  local ease = math.min(1, focus_t * 4)
  local function dim(i) return (focus_t > 0 and i ~= sel) and (1 - 0.65 * ease) or 1 end

  cv.mul = dim(4); sc.cur(4):draw(cv, sc)  -- air (sky)
  cv.mul = dim(1); sc.cur(1):draw(cv, sc)  -- brain (weather)
  cv.mul = 1
  cv.line(0, GY, 127, GY, 3)               -- ground
  local sw = (sc.t - Brain.season_t) / 1.4 -- a light sweeps along it as the season turns
  if sw >= 0 and sw < 1 then
    local sx = sw * 152 - 12
    for x = math.max(0, math.floor(sx - 12)), math.min(127, math.floor(sx + 12)) do
      cv.px(x, GY, 3 + 10 * (1 - math.abs(x - sx) / 12) * (1 - sw * 0.5))
    end
  end
  cv.mul = dim(2); sc.cur(2):draw(cv, sc)  -- voice (ground)
  cv.mul = 1
  local brain = sc.cur(1)
  if brain.flash then                      -- a strike lights the land; fog, drawn next, muffles it
    local f = brain:flash()
    if f > 0 then cv.add(f) end
  end
  cv.mul = dim(3); sc.cur(3):draw(cv, sc)  -- color (light, water)
  cv.mul = 1
  glass.draw(cv)                           -- frost, condensation, the jar's rim
  for i = 1, 4 do
    cv.rect(106 + (i - 1) * 4, 1, 2, 2, i == sel and (focus_t > 0 and 13 or 5) or (focus_t > 0 and 3 or 1))
  end
  if k1 then peek_canvas() end
  cv.blit()

  screen.font_face(1)
  screen.font_size(8)
  if k1 then
    peek_text()
  elseif toast_t > 0 then
    screen.level(math.floor(14 * math.min(1, toast_t / 0.6)))
    screen.move(2, 62)
    screen.text(toast)
  end
  screen.update()
end

local function tick()
  local dt = 1 / FPS
  sc.t = sc.t + dt
  if not sc.frozen then sc.fly_t = sc.fly_t + dt end
  focus_t = math.max(0, focus_t - dt)
  toast_t = toast_t - dt
  if not installer.active then
    Climate.update(dt, params:get("t_drift"))
    if Climate.on() then dirty_sound = true end
    for i = 1, 4 do
      local mod = sc.cur(i)
      if mod.update then mod:update(dt, sc) end
    end
    glass.update(dt, sc)
    if dirty_sound then send_sound() end
  end
  redraw()
end

-- ---------- controls ----------

function enc(n, d)
  if installer.active then return end
  if k1 and n > 1 then -- holding K1: settings
    if n == 2 then set_cursor = H.clamp(set_cursor + d, 1, #SETTINGS)
    else params:delta(SETTINGS[set_cursor], d) end
    return
  end
  if k2 and n == 2 then -- holding K2: the module's variant (Plaits engine, Rings model...)
    k2_turned = true
    local mod = sc.cur(sel)
    if mod.variant then
      params:delta(mod.variant, d)
      say(params:string(mod.variant))
    else
      say(mod.name .. ": one kind")
    end
    focus()
    return
  end
  if n == 1 then
    sel = H.clamp(sel + d, 1, 4)
  else
    local mod = sc.cur(sel)
    params:delta(mod.id .. "_" .. mod.macros[n - 1].id, d)
  end
  focus()
end

function key(n, z)
  if installer.active then
    installer.key(n, z)
    return
  end
  if n == 1 then
    k1 = z == 1
    return
  end
  if n == 2 then -- swap on release, unless E2 picked a variant while it was held
    if z == 1 then
      k2, k2_turned = true, false
      return
    end
    k2 = false
    if not k2_turned then
      local L = LAYERS[sel]
      params:set(L.id .. "_kind", params:get(L.id .. "_kind") % #L.mods + 1)
      say(sc.cur(sel).name)
    end
    focus()
    return
  end
  if z == 0 then return end
  if n == 3 then
    if sel == 1 then
      Brain.new_phrase(sc.t)
      say("new phrase")
    elseif sel == 4 then
      sc.frozen = not sc.frozen
      dirty_sound = true
      say(sc.frozen and "freeze" or "thaw")
    else
      play({ x = 4 + math.random() * 119 }, true) -- strike
    end
  end
  focus()
end

-- ---------- lifecycle ----------

function init()
  installer.check()
  redraw_metro = metro.init(tick, 1 / FPS)
  if not installer.ok then
    installer.active = true
    redraw_metro:start()
    return
  end
  if not installer.has_beads then -- older mi-UGens builds have no Beads
    local mods = {}
    for _, m in ipairs(LAYERS[4].mods) do if m.id ~= "fireflies" then mods[#mods + 1] = m end end
    LAYERS[4].mods = mods
  end
  add_params()
  params:bang()
  Brain.new_phrase(sc.t)
  clock.run(brain_loop)
  redraw_metro:start()
  say(Brain.key_name())
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
end
