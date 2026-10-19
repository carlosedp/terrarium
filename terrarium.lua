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
-- hold K1 + K3: a new terrarium
--
-- needs mi-UGens
--
-- by Voltage Foundry Modular
-- vfmod.com

-- Copyright (C) 2026 Voltage Foundry Modular. Free software under the GNU GPL v3.0
-- (see LICENSE); the terrarium name, manual and images are all rights reserved.

engine.name = "Terrarium"

local H = include("lib/helpers")
local cv = include("lib/canvas")
local Brain = include("lib/brain")
local installer = include("lib/installer")
local glass = include("lib/glass")
local Climate = include("lib/climate")
local Day = include("lib/daylight")
local Breath = include("lib/breath")
local nb = include("lib/nb/lib/nb")

local FPS = 15
local GY = 54 -- the ground line

-- (a part's hold is the state its K3 toggles, kept as a param so presets save it)
-- the five parts of the scene: brain = weather, voice = ground, color = light and
-- water, air = sky, drone = the bed under it all (aurora in the sky, roots in the earth)
local LAYERS = {
  { id = "brain", name = "brain", mods = { include("lib/scene/rain"), include("lib/scene/lightning") } },
  { id = "voice", name = "voice", mods = { include("lib/scene/meadow"), include("lib/scene/crystals"), include("lib/scene/reeds"),
    include("lib/scene/visitors") } },
  { id = "color", name = "color", mods = { include("lib/scene/pond"), include("lib/scene/fog") } },
  { id = "air",   name = "air",   mods = { include("lib/scene/clouds"), include("lib/scene/fireflies"), include("lib/scene/mountains") },
    hold = { id = "air_freeze", name = "freeze", field = "frozen" } },
  { id = "drone", name = "drone", mods = { include("lib/scene/aurora"), include("lib/scene/roots"), include("lib/scene/none") },
    hold = { id = "drone_hush", name = "hush", field = "hushed" } },
}
local SLOT_SET = { nil, "voice_set", "color_set", "air_set", "drone_set" }
local PART = {}
for i, L in ipairs(LAYERS) do
  PART[L.id] = i
  for _, m in ipairs(L.mods) do m.part = i end
end
-- each sounding slot's level in PARAMS (dB), sent to its synth as vol
local LEVELS = { { "level_voice", "voice level", 2, 0 }, { "level_color", "color level", 3, 0 },
  { "level_air", "air level", 4, 0 }, { "level_drone", "drone level", 5, -12 } }

local SETTINGS = { "t_root", "t_scale", "t_range", "t_length", "t_seasons", "t_climate", "t_drift", "t_day", "t_breath" }
local SETTING_NAMES = { "key", "scale", "range", "length", "seasons", "climate", "drift", "day", "breath" }
local LENGTHS = { 4, 8, 12, 16 }
local SEASONS = { 0, 8, 4, 2 } -- phrases between turns: off, slow, steady, quick

-- climate: which attractor output (1 x, 2 y, 3 z) moves each macro, and how much
-- by default (the per-macro cv param, -1..1; full cv swings a macro by +-0.5)
local CV_SRC = { { 3, 1 }, { 1, 2 }, { 2, 3 }, { 3, 1 }, { 2, 3 } }
local CV_DEFAULT = { { 0, 0.3 }, { 0.4, 0.3 }, { 0.35, 0.25 }, { 0.35, 0.3 }, { 0.3, 0.35 } }

-- shared scene state handed to every module
local sc = { t = 0, GY = GY, frozen = false, fly_t = 0, brain = Brain, nb = nb, breath = Breath,
  activity = 0, lift = 0 } -- how busy the weather is lately, and how much it lights up the drone
function sc.cur(i) return LAYERS[i].mods[params:get(LAYERS[i].id .. "_kind")] end
function sc.kind(i) return sc.cur(i).id end
-- a macro as you set it
function sc.base(i, k)
  local mod = sc.cur(i)
  return params:get(mod.id .. "_" .. mod.macros[k].id)
end
-- a macro as it plays: your setting is the center; the climate and the day add
-- to it like CV. Rounded so a slow drift doesn't flood the engine with tiny changes.
local function moving() return Climate.on() or Day.on() end
function sc.m(i, k)
  local v = sc.base(i, k)
  if not moving() then return v end
  if Climate.on() then
    local mod = sc.cur(i)
    local cv = params:get(mod.id .. "_" .. mod.macros[k].id .. "_cv")
    v = v + cv * 0.5 * Climate.out[CV_SRC[i][k]]
  end
  v = v + Day.offset(i, k)
  return H.clamp(math.floor(v * 200 + 0.5) / 200, 0, 1)
end
-- a module's map (macro -> engine parameter), evaluated as it plays: a number is
-- fixed, { k, a, b [, curve] } maps this part's macro k from a to b, and
-- { "part", k, a, b [, curve] } follows another part's macro (a coupling)
function sc.mapped(mod)
  local out = {}
  for key, e in pairs(mod.map or {}) do
    if type(e) == "number" then
      out[key] = e
    else
      local part, k, a, b, curve
      if type(e[1]) == "string" then part, k, a, b, curve = PART[e[1]], e[2], e[3], e[4], e[5]
      else part, k, a, b, curve = mod.part, e[1], e[2], e[3], e[4] end
      local v = sc.m(part, k)
      if curve then v = v ^ curve end
      out[key] = a + (b - a) * v
    end
  end
  return out
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

-- names on touch: what an encoder just moved, shown for a moment, never resting on screen
local hud, hud_t = nil, 0 -- { part = i } after E1, { part = i, k = macro } after E2/E3
local HUD_SEC, HUD_PART_SEC, HUD_BAR = 1.2, 2.5, 20 -- after E1 the names stay as long as the dimming

local function say(text) toast, toast_t, hud_t = text, 1.8, 0 end
local function touched(t) hud, hud_t, toast_t = t, t.k and HUD_SEC or HUD_PART_SEC, 0 end
local scramble -- a new terrarium (below)
local function focus() focus_t = 2.5 end

-- ---------- sound ----------

local function db_amp(db) return db <= -59.5 and 0 or 10 ^ (db / 20) end

local function send_sound()
  for i = 2, #LAYERS do
    local fn = engine[SLOT_SET[i]]
    local s = sc.cur(i):sound(sc)
    for _, l in ipairs(LEVELS) do if l[3] == i then s.vol = db_amp(params:get(l[1])) end end
    for k, v in pairs(s) do
      if sent[i][k] ~= v then
        fn(k, v)
        sent[i][k] = v
      end
    end
  end
  dirty_sound = false
end

local function play(ev, fresh)
  local voice, vel = sc.cur(2), fresh and 1 or 0.7
  if voice.play then voice:play(sc, Brain.pitch(ev.x), vel) else engine.note(Brain.pitch(ev.x), vel) end
  -- the drone answers the weather: each note makes it give way a little (it swells back in
  -- the gaps) and lights it up for a moment, a lightning strike much more than a raindrop
  sc.activity = math.min(1, sc.activity + 0.3 * vel)
  sc.lift = math.min(1, sc.lift + (sc.kind(1) == "lightning" and 0.7 or 0.25) * vel)
  for i = 2, #LAYERS do
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
    if ev and Breath.rest() then ev = nil end -- a calm spell: the note rests, the phrase keeps it
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
  if i == 2 then engine.voice_kind(mod.voice)
  elseif i == 3 then engine.color_kind(mod.id)
  elseif i == 4 then engine.air_kind(mod.id)
  elseif i == 5 then engine.drone_kind(mod.id) end
  sent[i] = {}
  dirty_sound = true
end

-- ---------- params ----------

local function add_params()
  local changed = function() dirty_sound = true end

  params:add_separator("terrarium", "terrarium")
  params:add_trigger("t_randomize", "randomize the jar")
  params:set_action("t_randomize", function() scramble() end)
  params:add_group("terrarium_levels", "levels", #LEVELS)
  for _, l in ipairs(LEVELS) do
    params:add_control(l[1], l[2], controlspec.new(-60, 6, "lin", 0, l[4], "dB", 0.01))
    params:set_action(l[1], changed)
  end
  params:add_group("terrarium_settings", "settings", #SETTINGS)
  params:add_option("t_root", "key", Brain.NOTES, Brain.root + 1)
  params:set_action("t_root", function(v)
    Brain.root = v - 1
    dirty_sound = true -- the drone follows the key
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
  params:add_option("t_breath", "breath", Breath.NAMES, 1)
  params:set_action("t_breath", function(v) Breath.set(v) end)
  params:add_option("t_day", "day", Day.NAMES, 1)
  params:set_action("t_day", function(v)
    Day.set(v)
    dirty_sound = true
  end)

  for i, L in ipairs(LAYERS) do
    local names, count = {}, 1
    for _, m in ipairs(L.mods) do
      names[#names + 1] = m.name
      count = count + #m.macros * 2 + (m.extra_count or 0) -- each macro and its cv
    end
    if L.hold then count = count + 1 end
    params:add_group("terrarium_" .. L.id, L.name, count)
    params:add_option(L.id .. "_kind", L.name, names, 1)
    params:set_action(L.id .. "_kind", function() on_kind(i) end)
    if L.hold then -- freeze (air), hush (drone): K3 flips it
      params:add_option(L.hold.id, L.hold.name, { "off", "on" }, 1)
      params:set_action(L.hold.id, function(v)
        sc[L.hold.field] = v == 2
        dirty_sound = true
      end)
    end
    for _, m in ipairs(L.mods) do
      for k, mac in ipairs(m.macros) do
        local id = m.id .. "_" .. mac.id
        params:add_control(id, m.name .. " " .. mac.name, controlspec.new(0, 1, "lin", 0, mac.default, "", 0.02))
        params:set_action(id, changed)
        params:add_control(id .. "_cv", m.name .. " " .. mac.name .. " cv",
          controlspec.new(-1, 1, "lin", 0, CV_DEFAULT[i][k], "", 0.01))
        params:set_action(id .. "_cv", changed)
      end
      if m.add_params then m:add_params(changed, sc) end
    end
  end

  -- each nb voice's own params (visitors play them)
  params:add_separator("terrarium_nb", "visitor voices")
  nb:add_player_params()

  -- loading a PSET: nb asks for its voices to be stopped, so no note hangs
  params.action_read = function() nb:stop_all() end
end

-- the season turned: show it in the settings without moving home
-- at each phrase end: breath may calm the weather, and the drone may follow it
Brain.on_phrase = function(change, t)
  Breath.phrase()
  Brain.drone_follow(change, t)
  dirty_sound = true
end

Brain.on_season = function()
  seasoning = true
  params:set("t_root", Brain.root + 1)
  params:set("t_scale", Brain.scale)
  seasoning = false
  say(Brain.key_name())
end

-- ---------- a new terrarium ----------
-- hold K1 + K3 (or PARAMS > randomize the jar): every part gets a random module,
-- variety and knobs, kept away from the extremes, and the settings change too: key,
-- scale, range, length, seasons, climate, drift, breath. Never visitors (they need
-- an outside voice) or none (silence), and never the day: it's about time, not texture.
scramble = function()
  for i, L in ipairs(LAYERS) do
    local choices = {}
    for k, m in ipairs(L.mods) do
      if m.id ~= "visitors" and m.id ~= "none" then choices[#choices + 1] = k end
    end
    params:set(L.id .. "_kind", choices[math.random(#choices)])
    local mod = sc.cur(i)
    if mod.variant then params:set(mod.variant, math.random(#params:lookup_param(mod.variant).options)) end
    for _, mac in ipairs(mod.macros) do params:set(mod.id .. "_" .. mac.id, 0.15 + math.random() * 0.7) end
  end
  for _, id in ipairs({ "t_root", "t_scale", "t_length", "t_seasons", "t_climate", "t_drift", "t_breath" }) do
    params:set(id, math.random(#params:lookup_param(id).options))
  end
  params:set("t_range", math.random(1, 3))
  Brain.season_t = sc.t -- the light sweeps along the ground, like a season turning
  say("new: " .. Brain.key_name())
end

-- ---------- tuning from maiden ----------
-- Every module's macro -> engine mapping is a table (its `map`). tune() changes
-- one while the script runs and prints the table to paste back into the module:
--   tune()                                   list the modules
--   tune("clouds")                           print clouds' map
--   tune("clouds", "rvb", 2, 0.1, 0.6)       clouds' E3 macro moves rvb 0.1 -> 0.6
--   tune("clouds", "rvb", 0.4)               fix rvb at 0.4
--   tune("clouds", "rvb", 2, 0.1, 0.6, 2)    ... along a curve (macro ^ 2)
--   tune("meadow", "decay", "brain", 1, 0.75, 0.4)   follow another part's macro
--   tune("clouds", "rvb", nil)               drop it (the synth's default applies)
-- A key that isn't a control of the module's synth does nothing (see doc/SOUND.md).
local function show(v) return type(v) == "string" and ('"' .. v .. '"') or tostring(v) end

function tune(id, key, ...)
  local mod
  for _, L in ipairs(LAYERS) do
    for _, m in ipairs(L.mods) do
      if m.id == id then mod = m end
    end
  end
  if not mod then
    local ids = {}
    for _, L in ipairs(LAYERS) do
      for _, m in ipairs(L.mods) do if m.map then ids[#ids + 1] = m.id end end
    end
    print("tune: modules with a map: " .. table.concat(ids, ", "))
    return
  end
  if key then
    local args = table.pack(...)
    if args.n == 0 or args[1] == nil then mod.map[key] = nil
    elseif args.n == 1 then mod.map[key] = args[1]
    else mod.map[key] = { table.unpack(args, 1, args.n) } end
    sent[mod.part] = {}
    dirty_sound = true
  end
  local keys = {}
  for k in pairs(mod.map) do keys[#keys + 1] = k end
  table.sort(keys)
  print(mod.id .. ".map = {")
  for _, k in ipairs(keys) do
    local e = mod.map[k]
    if type(e) == "table" then
      local parts = {}
      for i, v in ipairs(e) do parts[i] = show(v) end
      e = "{ " .. table.concat(parts, ", ") .. " }"
    end
    print(("  %s = %s,"):format(k, tostring(e)))
  end
  print("}")
end

-- ---------- drawing ----------

local function peek_canvas()
  cv.clear_rect(0, 0, 128, 52)
  for i, L in ipairs(LAYERS) do
    local y, on, mod = 3 + (i - 1) * 8, i == sel, sc.cur(i)
    for k = 1, #mod.macros do
      local bx = 76 + (k - 1) * 26
      cv.rect(bx, y, 22, 3, 2)
      cv.rect(bx, y, math.max(1, H.round(sc.base(i, k) * 22)), 3, on and 13 or 6)
      if moving() then -- where the climate and the day have pushed it right now
        cv.rect(bx + math.min(21, H.round(sc.m(i, k) * 22)), y - 1, 1, 5, on and 15 or 9)
      end
    end
  end
  for j = 1, #SETTINGS do cv.rect(92 + (j - 1) * 4, 42, 2, 2, j == set_cursor and 13 or 3) end
  if SETTINGS[set_cursor] == "t_climate" or SETTINGS[set_cursor] == "t_drift" then
    local n = #Climate.trail -- the attractor's recent path (x across, z up), next to its name
    for j, q in ipairs(Climate.trail) do cv.px(82 + q[1] * 16, 46 - q[2] * 3.5, 1 + 12 * j / n) end
  end
  for i = 1, Brain.length do
    cv.rect(2 + (i - 1) * 3, 48, 2, 2, Brain.reg[i] and (i == Brain.last_step and 15 or 7) or 2)
  end
  cv.line(0, 51, 127, 51, 3)
end

local function peek_text()
  for i, L in ipairs(LAYERS) do
    local y, on = 2 + (i - 1) * 8, i == sel
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
  screen.move(2, 46)
  screen.text(SETTING_NAMES[set_cursor])
  screen.level(13)
  screen.move(2 + col + 5, 46)
  screen.text(params:string(SETTINGS[set_cursor]))
end

-- E2's macro on the left of the bottom strip, E3's on the right (where the
-- encoders are): its name and a bar, plus a tick where the climate has it now.
-- After E1, the part and module at the top left and both macro names at the
-- bottom (names only: two names and two bars don't fit 128 pixels).
-- The canvas part clears room and draws the bars; the text goes on after the blit.
local function text_w(s) return screen.text_extents(s) or #s * 5 end

local function hud_canvas()
  local fade = math.min(1, hud_t / 0.4)
  local mod, labels = sc.cur(hud.part), {}
  for k = 1, #mod.macros do
    if not hud.k or hud.k == k then
      local name = mod.macros[k].name
      local w = text_w(name)
      local bar = hud.k and HUD_BAR + 4 or 0
      local x = k == 1 and 2 or 126 - bar - w
      cv.clear_rect(x - 2, 55, w + bar + 4, 9)
      if hud.k then
        local bx = x + w + 4
        cv.rect(bx, 58, HUD_BAR, 2, 2)
        cv.rect(bx, 58, math.max(1, H.round(sc.base(hud.part, k) * HUD_BAR)), 2, 10 * fade)
        if moving() then
          cv.rect(bx + math.min(HUD_BAR - 1, H.round(sc.m(hud.part, k) * HUD_BAR)), 57, 1, 4, 15 * fade)
        end
      end
      labels[#labels + 1] = { x = x, y = 62, text = name, level = (hud.k and 13 or 10) * fade }
    end
  end
  if not hud.k then -- which part and module E1 landed on
    local part = LAYERS[hud.part].name
    local w = text_w(part) + 4 + text_w(mod.name)
    cv.clear_rect(0, 0, w + 6, 9)
    labels[#labels + 1] = { x = 2, y = 7, text = part, level = 15 * fade }
    labels[#labels + 1] = { x = 2 + text_w(part) + 4, y = 7, text = mod.name, level = 8 * fade }
  end
  return labels
end

local function hud_text(labels)
  for _, l in ipairs(labels) do
    screen.level(math.max(1, math.floor(l.level)))
    screen.move(l.x, l.y)
    screen.text(l.text)
  end
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

  local drone = sc.cur(5)
  cv.mul = 1; Day.draw(cv, sc)                                   -- sun, moon, stars: furthest back
  if not drone.in_front then cv.mul = dim(5); drone:draw(cv, sc) end -- then the drone (aurora)
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
  if drone.in_front then cv.mul = dim(5); drone:draw(cv, sc) end      -- roots glow up through water and soil
  cv.mul = 1
  glass.draw(cv)                           -- frost, condensation, the jar's rim
  for i = 1, #LAYERS do
    cv.rect(102 + (i - 1) * 4, 1, 2, 2, i == sel and (focus_t > 0 and 13 or 5) or (focus_t > 0 and 3 or 1))
  end
  screen.font_face(1)
  screen.font_size(8)
  local labels = (not k1 and hud_t > 0) and hud_canvas() or nil
  if k1 then peek_canvas() end
  cv.blit()

  if k1 then
    peek_text()
  elseif labels then
    hud_text(labels)
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
  hud_t = hud_t - dt
  if not installer.active then
    Climate.update(dt, params:get("t_drift"))
    Day.update(dt)
    Breath.update(dt, Climate.on() and Climate.out[1] or nil)
    if moving() then dirty_sound = true end
    for i = 1, #LAYERS do
      local mod = sc.cur(i)
      if mod.update then mod:update(dt, sc) end
    end
    glass.update(dt, sc)
    sc.activity = sc.activity * math.exp(-dt / 1.8) -- the drone swells back over a couple of seconds
    sc.lift = sc.lift * math.exp(-dt / 3)
    if sc.kind(5) ~= "none" and (sc.activity > 0.01 or sc.lift > 0.01) then dirty_sound = true end
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
    sel = H.clamp(sel + d, 1, #LAYERS)
    touched({ part = sel })
  else
    local mod = sc.cur(sel)
    if not mod.macros[n - 1] then -- an empty module ("none") has nothing to turn
      say(LAYERS[sel].name .. ": " .. mod.name)
      return
    end
    params:delta(mod.id .. "_" .. mod.macros[n - 1].id, d)
    touched({ part = sel, k = n - 1 })
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
  if k1 and n == 3 then -- hold K1 + K3: a new terrarium
    if z == 1 then scramble() end
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
      params:set("air_freeze", sc.frozen and 1 or 2)
      say(sc.frozen and "freeze" or "thaw")
    elseif sel == 5 then -- the drone fades out, or rises again
      params:set("drone_hush", sc.hushed and 1 or 2)
      say(sc.hushed and "hush" or "rise")
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
  nb:init()
  add_params()
  params:bang()
  Brain.new_phrase(sc.t)
  clock.run(brain_loop)
  redraw_metro:start()
  say(Brain.key_name())
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  nb:stop_all()
end
