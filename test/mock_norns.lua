-- A minimal stand-in for the norns Lua runtime, enough to run terrarium
-- headless on a computer: screen, params, controlspec, clock, metro, engine,
-- util, tab, midi, norns.system_cmd, and one fake nb voice. Not a simulator;
-- it records what the script does.

local M = { now = 0, screen_calls = 0, engine_calls = {}, sets = {}, metros = {}, coroutines = {} }

-- ---------- include ----------
local ROOT = (arg and arg[0] or ""):match("^(.*)/test/[^/]+$") or "."
function include(path) return dofile(ROOT .. "/" .. path .. ".lua") end
M.ROOT = ROOT
_path = { code = ROOT .. "/" } -- so nb finds its own files relative to the script

-- ---------- screen ----------
screen = setmetatable({}, {
  __index = function(_, k)
    return function() M.screen_calls = M.screen_calls + 1 end
  end,
})

-- ---------- engine ----------
engine = setmetatable({}, {
  __index = function(_, k)
    if k == "name" then return rawget(engine, "_name") end
    return function(...)
      M.engine_calls[k] = (M.engine_calls[k] or 0) + 1
      M.last_engine = { k, ... }
      local key, v = ...
      if k:match("_set$") then -- latest value per slot parameter
        M.sets[k] = M.sets[k] or {}
        M.sets[k][key] = v
      end
    end
  end,
  __newindex = function(t, k, v) if k == "name" then rawset(t, "_name", v) else rawset(t, k, v) end end,
})

-- ---------- controlspec ----------
controlspec = {}
function controlspec.new(min, max, warp, step, default, units, quantum)
  return { minval = min, maxval = max, default = default, quantum = quantum or 0.01 }
end

-- ---------- params ----------
-- like norns: params.lookup maps id -> index, params:lookup_param(id) is the param
local P = { list = {}, by_id = {}, lookup = {} }
params = P
local Param = {}
Param.__index = Param
function Param:get() return self.value end
local function add(p)
  assert(not P.by_id[p.id], "duplicate param id: " .. tostring(p.id))
  setmetatable(p, Param)
  P.list[#P.list + 1] = p
  P.by_id[p.id] = p
  P.lookup[p.id] = #P.list
  return p
end
function P:add_separator(id, name) -- ends the open group, like the menu does visually
  if self._group and not self._group.stop then self._group.stop = #self.list end
end
function P:add_text(id, name, default) add({ id = id, kind = "text", value = default or "" }) end
function P:add_trigger(id, name) add({ id = id, kind = "trigger", value = 0 }) end
function P:add_binary(id, name) add({ id = id, kind = "binary", value = 0 }) end
function P:hide(id) end
function P:show(id) end
function P:add_group(id, name, n)
  self._group = { id = id, expect = n, start = #self.list }
  self.groups = self.groups or {}
  self.groups[#self.groups + 1] = self._group
end
function P:add_option(id, name, options, default)
  add({ id = id, kind = "option", options = options, value = default or 1 })
end
function P:add_number(id, name, min, max, default, formatter)
  add({ id = id, kind = "number", min = min, max = max, value = default or min, formatter = formatter })
end
function P:add_control(id, name, spec)
  add({ id = id, kind = "control", spec = spec, value = spec.default })
end
function P:set_action(id, f) assert(self.by_id[id], "set_action on missing param " .. id).action = f end
function P:lookup_param(id) return assert(self.by_id[id], "no param " .. tostring(id)) end
function P:get(id) return self:lookup_param(id).value end
function P:set(id, v, silent)
  local p = self:lookup_param(id)
  if p.kind == "option" then v = math.max(1, math.min(#p.options, v)) end
  if p.kind == "number" then v = math.max(p.min, math.min(p.max, v)) end
  if p.kind == "control" then v = math.max(p.spec.minval, math.min(p.spec.maxval, v)) end
  p.value = v
  if p.action and not silent then p.action(v) end
end
function P:delta(id, d)
  local p = self:lookup_param(id)
  if p.kind == "control" then self:set(id, p.value + d * p.spec.quantum) else self:set(id, p.value + d) end
end
function P:string(id)
  local p = self:lookup_param(id)
  if p.kind == "option" then return p.options[p.value] end
  if p.formatter then return p.formatter({ get = function() return p.value end }) end
  return tostring(p.value)
end
function P:bang() for _, p in ipairs(self.list) do if p.action then p.action(p.value) end end end
function P:check_groups()
  for i, g in ipairs(self.groups or {}) do
    local stop = g.stop or self.groups[i + 1] and self.groups[i + 1].start or #self.list
    assert(stop - g.start == g.expect,
      ("group %s declares %d params but has %d"):format(g.id, g.expect, stop - g.start))
  end
end

-- ---------- clock (seconds; 120 bpm) ----------
clock = {}
function clock.get_beat_sec() return 0.5 end
function clock.sleep(s) coroutine.yield(s) end
function clock.sync(beats) coroutine.yield(beats * 0.5) end
function clock.cancel(id) end
function clock.run(f)
  local co = coroutine.create(f)
  local entry = { co = co, wake = M.now }
  M.coroutines[#M.coroutines + 1] = entry
  return #M.coroutines
end
function M.advance_clocks()
  for _, e in ipairs(M.coroutines) do
    while coroutine.status(e.co) ~= "dead" and e.wake <= M.now do
      local ok, delay = coroutine.resume(e.co)
      if not ok then error("clock coroutine failed: " .. tostring(delay)) end
      e.wake = e.wake + (delay or 0)
    end
  end
end

-- ---------- metro ----------
metro = {}
function metro.init(f, time)
  local m = { event = f, time = time, running = false }
  function m:start() self.running = true end
  function m:stop() self.running = false end
  M.metros[#M.metros + 1] = m
  return m
end

-- ---------- util / norns ----------
M.has_mi, M.has_beads = true, true
util = {}
function util.os_capture(cmd)
  if cmd:match("^find .*MiBeads") then return M.has_beads and "/x/MiBeads.sc" or "" end
  if cmd:match("^find ") then return M.has_mi and "/x/Mi.sc" or "" end
  return ""
end
function util.acronym(s) return s:sub(1, 3) end
function util.clamp(v, a, b) return math.max(a, math.min(b, v)) end
tab = {}
function tab.invert(t) local r = {} for k, v in pairs(t) do r[v] = k end return r end
midi = { vports = {} }
_menu = { rebuild_params = function() end }

-- one fake nb voice (as a mod would register it), recording what it's asked to play
M.nb_notes, M.nb_mods = 0, 0
note_players = {
  ["test voice"] = {
    add_params = function() end,
    note_on = function() M.nb_notes = M.nb_notes + 1 end,
    note_off = function() end,
    modulate = function() M.nb_mods = M.nb_mods + 1 end,
  },
}

norns = { system_cmd = function(cmd, cb) M.last_system_cmd = cmd; if cb then cb("installed: MiPlaits\nexit=0") end end }

-- run the frame metro and clocks for `sec` seconds of simulated time
function M.run(sec)
  local m = M.metros[1]
  local frames = math.floor(sec * 15 + 0.5)
  for _ = 1, frames do
    M.now = M.now + 1 / 15
    M.advance_clocks()
    local before = M.screen_calls
    if m and m.running then m.event() end
    local calls = M.screen_calls - before
    M.max_calls = math.max(M.max_calls or 0, calls)
    M.total_calls = (M.total_calls or 0) + calls
    M.frames = (M.frames or 0) + 1
  end
end

return M
