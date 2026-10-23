-- norns-web: the norns Lua API, enough to run a norns script in a browser.
--
-- Loaded by norns-web.js into a Lua VM (wasmoon, Lua 5.4; norns runs 5.3).
-- The script's files are mounted under /code/<name>/. Everything the script
-- touches happens here in Lua; the page only calls norns_web.tick() once per
-- animation frame and gets the screen back as a string of 128x64 levels
-- ("A" = 0 .. "P" = 15).
--
-- Covered: screen (no anti-aliasing, a small bitmap font), params (with a
-- panel on the page, and PSETs in browser storage), controlspec, clock,
-- metro, util, tab, include, norns,
-- engine commands (sent to a JS stand-in, lib/Engine_<name>.js, if any), and one
-- built-in nb voice ("web synth") for scripts that use nb.
-- midi out (when the host has ports: a plugin's); grid, arc, softcut, crow, poll and the rest
-- are silent stubs.

local W, H = 128, 64
local js = js_bridge -- set by norns-web.js: engine(), log(), os_capture()

norns_web = {}

-- ---------- any table of no-op functions (for APIs we don't emulate) ----------
local function stub(name)
  return setmetatable({}, {
    __index = function(t, k)
      if k == "connect" then return function() return stub(name .. ".device") end end
      return function() end
    end,
  })
end

-- ---------- print goes to the page too ----------
local raw_print = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  local s = table.concat(parts, "\t")
  raw_print(s)
  js.log(s)
end

-- ---------- screen ----------
local fb, CH = {}, {}
for i = 1, W * H do fb[i] = 0 end
for l = 0, 15 do CH[l] = string.char(65 + l) end -- "A".."P": no zero bytes, they'd cut the string short in JS
local cur = { level = 15, x = 0, y = 0, path = {}, font_size = 8 }
local dirty = false

local function plot(x, y, l)
  x, y = math.floor(x), math.floor(y)
  if x >= 0 and y >= 0 and x < W and y < H then fb[y * W + x + 1] = l end
end

local function seg(x0, y0, x1, y1, l)
  x0, y0, x1, y1 = math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  for _ = 1, 1024 do
    plot(x0, y0, l)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

-- 3x5 capitals, numbers and some punctuation (lowercase draws as capitals)
local FONT = {
  A = { 2, 5, 7, 5, 5 }, B = { 6, 5, 6, 5, 6 }, C = { 3, 4, 4, 4, 3 }, D = { 6, 5, 5, 5, 6 }, E = { 7, 4, 6, 4, 7 },
  F = { 7, 4, 6, 4, 4 }, G = { 3, 4, 5, 5, 3 }, H = { 5, 5, 7, 5, 5 }, I = { 7, 2, 2, 2, 7 }, J = { 1, 1, 1, 5, 2 },
  K = { 5, 5, 6, 5, 5 }, L = { 4, 4, 4, 4, 7 }, M = { 5, 7, 7, 5, 5 }, N = { 6, 5, 5, 5, 5 }, O = { 2, 5, 5, 5, 2 },
  P = { 6, 5, 6, 4, 4 }, Q = { 2, 5, 5, 6, 3 }, R = { 6, 5, 6, 5, 5 }, S = { 3, 4, 2, 1, 6 }, T = { 7, 2, 2, 2, 2 },
  U = { 5, 5, 5, 5, 7 }, V = { 5, 5, 5, 5, 2 }, W = { 5, 5, 7, 7, 5 }, X = { 5, 5, 2, 5, 5 }, Y = { 5, 5, 2, 2, 2 },
  Z = { 7, 1, 2, 4, 7 },
  ["0"] = { 7, 5, 5, 5, 7 }, ["1"] = { 2, 6, 2, 2, 7 }, ["2"] = { 6, 1, 2, 4, 7 }, ["3"] = { 6, 1, 2, 1, 6 },
  ["4"] = { 5, 5, 7, 1, 1 }, ["5"] = { 7, 4, 6, 1, 6 }, ["6"] = { 3, 4, 7, 5, 7 }, ["7"] = { 7, 1, 2, 2, 2 },
  ["8"] = { 7, 5, 7, 5, 7 }, ["9"] = { 7, 5, 7, 1, 6 },
  ["-"] = { 0, 0, 7, 0, 0 }, [":"] = { 0, 2, 0, 2, 0 }, ["."] = { 0, 0, 0, 0, 2 }, [","] = { 0, 0, 0, 2, 4 },
  ["/"] = { 1, 1, 2, 4, 4 }, [">"] = { 4, 2, 1, 2, 4 }, ["<"] = { 1, 2, 4, 2, 1 }, ["#"] = { 5, 7, 5, 7, 5 },
  ["+"] = { 0, 2, 7, 2, 0 }, ["("] = { 1, 2, 2, 2, 1 }, [")"] = { 4, 2, 2, 2, 4 }, ["%"] = { 5, 1, 2, 4, 5 },
  ["!"] = { 2, 2, 2, 0, 2 }, ["?"] = { 6, 1, 2, 0, 2 }, ["'"] = { 2, 2, 0, 0, 0 }, ["="] = { 0, 7, 0, 7, 0 },
  ["_"] = { 0, 0, 0, 0, 7 }, ["*"] = { 5, 2, 5, 0, 0 },
}
local function text_width(s) return #tostring(s) * 4 end

screen = {}
function screen.clear() for i = 1, W * H do fb[i] = 0 end; cur.path = {} end
function screen.level(l) cur.level = math.max(0, math.min(15, math.floor(l))) end
function screen.aa() end
function screen.font_face() end
function screen.font_size(s) cur.font_size = s end
function screen.line_width() end
function screen.line_cap() end
function screen.line_join() end
function screen.blend_mode() end
function screen.save() end
function screen.restore() end
function screen.move(x, y) cur.x, cur.y = x, y end
function screen.move_rel(dx, dy) cur.x, cur.y = cur.x + dx, cur.y + dy end
function screen.line(x, y)
  table.insert(cur.path, { "line", cur.x, cur.y, x, y })
  cur.x, cur.y = x, y
end
function screen.line_rel(dx, dy) screen.line(cur.x + dx, cur.y + dy) end
function screen.rect(x, y, w, h) table.insert(cur.path, { "rect", x, y, w, h }) end
function screen.circle(x, y, r) table.insert(cur.path, { "circle", x, y, r }) end
function screen.arc(x, y, r, a1, a2) table.insert(cur.path, { "arc", x, y, r, a1, a2 }) end
function screen.close() end
function screen.pixel(x, y) table.insert(cur.path, { "rect", x, y, 1, 1 }) end

local function arc_points(x, y, r, a1, a2, fn)
  local steps = math.max(8, math.ceil(r * 6))
  for i = 0, steps do
    local a = a1 + (a2 - a1) * i / steps
    fn(x + math.cos(a) * r, y + math.sin(a) * r)
  end
end

function screen.stroke()
  local l = cur.level
  for _, p in ipairs(cur.path) do
    if p[1] == "line" then seg(p[2], p[3], p[4], p[5], l)
    elseif p[1] == "rect" then
      local x, y, w, h = p[2], p[3], p[4], p[5]
      seg(x, y, x + w - 1, y, l); seg(x, y + h - 1, x + w - 1, y + h - 1, l)
      seg(x, y, x, y + h - 1, l); seg(x + w - 1, y, x + w - 1, y + h - 1, l)
    elseif p[1] == "circle" then arc_points(p[2], p[3], p[4], 0, 2 * math.pi, function(px, py) plot(px, py, l) end)
    elseif p[1] == "arc" then arc_points(p[2], p[3], p[4], p[5], p[6], function(px, py) plot(px, py, l) end)
    end
  end
  cur.path = {}
end

function screen.fill()
  local l = cur.level
  for _, p in ipairs(cur.path) do
    if p[1] == "rect" then
      local x0, y0 = math.floor(p[2]), math.floor(p[3])
      for y = y0, y0 + math.floor(p[5]) - 1 do
        if y >= 0 and y < H then
          local row = y * W + 1
          for x = math.max(0, x0), math.min(W - 1, x0 + math.floor(p[4]) - 1) do fb[row + x] = l end
        end
      end
    elseif p[1] == "circle" then
      local cx, cy, r = p[2], p[3], p[4]
      for y = math.floor(cy - r), math.ceil(cy + r) do
        for x = math.floor(cx - r), math.ceil(cx + r) do
          if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then plot(x, y, l) end
        end
      end
    elseif p[1] == "line" then seg(p[2], p[3], p[4], p[5], l)
    end
  end
  cur.path = {}
end

-- text sits on the baseline at the current point, like norns
function screen.text(s)
  s = tostring(s)
  local x, top = math.floor(cur.x), math.floor(cur.y) - 5
  for ch in s:upper():gmatch(".") do
    local rows = FONT[ch]
    if rows then
      for r = 1, 5 do
        for c = 0, 2 do
          if rows[r] & (4 >> c) ~= 0 then plot(x + c, top + r - 1, cur.level) end
        end
      end
    end
    x = x + 4
  end
  cur.x = x
end
function screen.text_right(s) cur.x = cur.x - text_width(s); screen.text(s) end
function screen.text_center(s) cur.x = cur.x - text_width(s) / 2; screen.text(s) end
function screen.text_extents(s) return text_width(s), 5 end
function screen.update() dirty = true end
function screen.peek() return "" end
function screen.display_png() end

local function frame_string()
  local t = {}
  for i = 1, W * H do t[i] = CH[fb[i]] end
  return table.concat(t)
end

-- ---------- controlspec ----------
controlspec = {}
controlspec.__index = controlspec
function controlspec.new(min, max, warp, step, default, units, quantum, wrap)
  local s = setmetatable({}, controlspec)
  s.minval, s.maxval, s.warp = min, max, warp or "lin"
  s.step, s.default, s.units = step or 0, default or min, units or ""
  s.quantum, s.wrap = quantum or 0.01, wrap or false
  return s
end
function controlspec:map(r)
  r = math.max(0, math.min(1, r))
  local v
  if self.warp == "exp" and self.minval > 0 then v = self.minval * (self.maxval / self.minval) ^ r
  else v = self.minval + (self.maxval - self.minval) * r end
  if self.step > 0 then v = math.floor(v / self.step + 0.5) * self.step end
  return v
end
function controlspec:unmap(v)
  if self.warp == "exp" and self.minval > 0 then return math.log(v / self.minval) / math.log(self.maxval / self.minval) end
  if self.maxval == self.minval then return 0 end
  return (v - self.minval) / (self.maxval - self.minval)
end
function controlspec:copy() local c = setmetatable({}, controlspec); for k, v in pairs(self) do c[k] = v end; return c end
controlspec.UNIPOLAR = controlspec.new(0, 1, "lin", 0, 0)
controlspec.BIPOLAR = controlspec.new(-1, 1, "lin", 0, 0)
controlspec.AMP = controlspec.new(0, 1, "lin", 0, 0)
controlspec.FREQ = controlspec.new(20, 20000, "exp", 0, 440, "Hz")
controlspec.PAN = controlspec.new(-1, 1, "lin", 0, 0)

-- ---------- params ----------
local P = { params = {}, lookup = {}, groups = {} }
params = P
local Param = {}
Param.__index = Param
function Param:get() return self.value end
function Param:set(v, silent) P:set(self.id, v, silent) end
function Param:delta(d) P:delta(self.id, d) end
function Param:string() return P:string(self.id) end
function Param:get_raw() return self.spec and self.spec:unmap(self.value) or self.value end

local function add(p)
  p = setmetatable(p, Param)
  table.insert(P.params, p)
  if p.id then P.lookup[p.id] = #P.params end
  local g = P._group
  if g and g.left > 0 then
    p.group = g.name
    g.left = g.left - 1
  end
  return p
end

function P:add_separator(id, name)
  add({ kind = "separator", id = name and id or nil, name = name or id or "" })
end
function P:add_group(id, name, n)
  if n == nil then id, name, n = id, id, name end -- add_group(name, n)
  self._group = nil -- the header isn't one of its own members
  add({ kind = "group", name = name, count = n })
  self._group = { name = name, left = n }
end
function P:add_option(id, name, options, default)
  add({ id = id, name = name, kind = "option", options = options, value = default or 1 })
end
function P:add_number(id, name, min, max, default, formatter, wrap)
  add({ id = id, name = name, kind = "number", min = min, max = max, value = default or min, formatter = formatter, wrap = wrap })
end
function P:add_control(id, name, spec, formatter)
  spec = spec or controlspec.UNIPOLAR:copy()
  add({ id = id, name = name, kind = "control", spec = spec, value = spec.default, formatter = formatter })
end
function P:add_taper(id, name, min, max, default, k, units)
  P:add_control(id, name, controlspec.new(min, max, "lin", 0, default or min, units))
end
function P:add_text(id, name, text) add({ id = id, name = name, kind = "text", value = text or "" }) end
function P:add_binary(id, name, behavior, default)
  add({ id = id, name = name, kind = "binary", value = default or 0, behavior = behavior or "toggle" })
end
function P:add_trigger(id, name) add({ id = id, name = name, kind = "trigger", value = 0 }) end
function P:add_file(id, name, path) add({ id = id, name = name, kind = "file", value = path or "" }) end
function P:add(t)
  local kind = t.type
  if kind == "option" then P:add_option(t.id, t.name, t.options, t.default)
  elseif kind == "number" then P:add_number(t.id, t.name, t.min, t.max, t.default, t.formatter)
  elseif kind == "control" then P:add_control(t.id, t.name, t.controlspec, t.formatter)
  elseif kind == "text" then P:add_text(t.id, t.name, t.text)
  elseif kind == "binary" then P:add_binary(t.id, t.name, t.behavior, t.default)
  elseif kind == "trigger" then P:add_trigger(t.id, t.name)
  elseif kind == "separator" then P:add_separator(t.id, t.name)
  elseif kind == "group" then P:add_group(t.id, t.name, t.n)
  else P:add_text(t.id, t.name, "") end
  if t.action and t.id then P:set_action(t.id, t.action) end
end

function P:lookup_param(id)
  local i = type(id) == "number" and id or self.lookup[id]
  local p = i and self.params[i]
  if not p then error("params: no param " .. tostring(id), 2) end
  return p
end
function P:set_action(id, f) self:lookup_param(id).action = f end
function P:get(id) return self:lookup_param(id).value end
function P:get_raw(id) return self:lookup_param(id):get_raw() end
function P:set(id, v, silent)
  local p = self:lookup_param(id)
  if p.kind == "option" then v = math.max(1, math.min(#p.options, math.floor(v)))
  elseif p.kind == "number" then
    if p.wrap then v = (v - p.min) % (p.max - p.min + 1) + p.min end
    v = math.max(p.min, math.min(p.max, math.floor(v)))
  elseif p.kind == "control" then v = math.max(math.min(p.spec.minval, p.spec.maxval), math.min(math.max(p.spec.minval, p.spec.maxval), v))
  end
  p.value = v
  if p.action and not silent then p.action(v) end
end
function P:set_raw(id, r) local p = self:lookup_param(id); self:set(id, p.spec:map(r)) end
function P:delta(id, d)
  local p = self:lookup_param(id)
  if p.kind == "control" then self:set(id, p.spec:map(p.spec:unmap(p.value) + d * p.spec.quantum))
  elseif p.kind == "binary" or p.kind == "trigger" then if d ~= 0 then self:set(id, d > 0 and 1 or 0) end
  elseif p.kind == "option" or p.kind == "number" then self:set(id, p.value + d)
  end
end
function P:string(id)
  local p = self:lookup_param(id)
  if p.formatter then return p.formatter(p) end
  if p.kind == "option" then return tostring(p.options[p.value]) end
  if p.kind == "control" then
    local v = p.value
    return (math.abs(v) < 10 and string.format("%.2f", v) or string.format("%.1f", v)) .. (p.spec.units ~= "" and (" " .. p.spec.units) or "")
  end
  return tostring(p.value)
end
function P:bang() for _, p in ipairs(self.params) do if p.action and p.id and p.kind ~= "trigger" then p.action(p.value) end end end
function P:hide(id) self:lookup_param(id).hidden = true end
function P:show(id) self:lookup_param(id).hidden = false end
function P:visible(id) return not self:lookup_param(id).hidden end
-- PSETs, kept in the browser's storage (one per numbered slot): every param's value
function P:write(n, name)
  n = n or 1
  local lines = {}
  for _, p in ipairs(self.params) do
    if p.id and p.kind ~= "separator" and p.kind ~= "group" and p.kind ~= "trigger" then
      lines[#lines + 1] = p.id .. "\t" .. tostring(p.value)
    end
  end
  js.storage_set("pset:" .. tostring(n), table.concat(lines, "\n"))
  print(("pset %s saved (%d params)"):format(tostring(n), #lines))
  if self.action_write then self.action_write(n, name, n) end
end
function P:read(n, silent)
  n = n or 1
  local s = js.storage_get("pset:" .. tostring(n))
  if not s or s == "" then print("pset " .. tostring(n) .. ": empty"); return end
  local count = 0
  for line in s:gmatch("[^\n]+") do
    local id, v = line:match("^([^\t]+)\t(.*)$")
    if id and self.lookup[id] then
      local p = self.params[self.lookup[id]]
      self:set(id, (p.kind == "text" or p.kind == "file") and v or tonumber(v), silent)
      count = count + 1
    end
  end
  print(("pset %s loaded (%d params)"):format(tostring(n), count))
  if self.action_read then self.action_read(n, silent, n) end
end
function P:default() end
function P:clear() end

-- the panel on the page: a JSON list of what PARAMS would show
local function json_str(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end
function norns_web.params_json()
  local out = {}
  for i, p in ipairs(P.params) do
    if not p.hidden then
      local item = { '"i":' .. i, '"kind":' .. json_str(p.kind), '"name":' .. json_str(p.name or p.id or "") }
      if p.group then item[#item + 1] = '"group":' .. json_str(p.group) end
      if p.id and p.kind ~= "separator" and p.kind ~= "group" then
        local ok, s = pcall(P.string, P, i)
        item[#item + 1] = '"str":' .. json_str(ok and s or "?")
        if type(p.value) == "number" then item[#item + 1] = '"value":' .. p.value end
      end
      out[#out + 1] = "{" .. table.concat(item, ",") .. "}"
    end
  end
  return "[" .. table.concat(out, ",") .. "]"
end
function norns_web.param_delta(i, d) P:delta(i, d) end
function norns_web.pset(action, n)
  local ok, err = pcall(action == "save" and P.write or P.read, P, n)
  if not ok then js.error(tostring(err)) end
end

-- ---------- clock and metro (driven by norns_web.tick) ----------
local now, tempo = 0, 120
local routines, next_id = {}, 1
local running = true -- false: the clock routines wait (a host's transport stopped); metros go on
clock = {}
function clock.run(f, ...)
  local args = table.pack(...)
  local id = next_id
  next_id = next_id + 1
  routines[id] = { co = coroutine.create(function() f(table.unpack(args, 1, args.n)) end), wake = now }
  return id
end
function clock.cancel(id) routines[id] = nil end
function clock.sleep(s) coroutine.yield("sleep", s) end
function clock.sync(beats) coroutine.yield("sync", beats) end
function clock.get_beats() return now * tempo / 60 end
function clock.get_tempo() return tempo end
function clock.get_beat_sec() return 60 / tempo end
function clock.set_tempo(t) tempo = t end
clock.tempo = tempo
clock.transport = {}

local metros = {}
metro = {}
function metro.init(arg, time, count)
  local m = type(arg) == "table" and arg or { event = arg, time = time, count = count }
  m.time, m.count, m.running = m.time or 1, m.count or -1, false
  function m:start(t, c)
    if t then self.time = t end
    if c then self.count = c end
    self.running, self.next, self.fired = true, now + self.time, 0
  end
  function m:stop() self.running = false end
  table.insert(metros, m)
  return m
end
function metro.free() end

-- Each routine runs at its own wake time: while it runs, now (util.time) is the moment it
-- asked for, not the tick that found it due, so what it does can be timed exactly by a host
-- that schedules ahead (the plugin stamps engine commands with it).
local function run_clocks()
  local tick_now = now
  for id, r in pairs(routines) do
    local guard = 0
    while routines[id] and r.wake <= tick_now and guard < 64 do
      guard = guard + 1
      local t = math.max(r.wake, tick_now - 1) -- a routine late by more than a second runs now
      now = t
      local ok, kind, v = coroutine.resume(r.co)
      now = tick_now
      if not ok then
        routines[id] = nil
        error("clock: " .. tostring(kind), 0)
      elseif coroutine.status(r.co) == "dead" then
        routines[id] = nil
      elseif kind == "sync" then
        local beat_sec = 60 / tempo
        local beats = math.max(v or 1, 1 / 64)
        local b = t / beat_sec
        r.wake = (math.floor(b / beats + 1e-6) + 1) * beats * beat_sec
        r.sync = beats
      else
        r.sync = nil
        r.wake = t + (v or 0)
        if r.wake < tick_now - 1 then r.wake = tick_now end -- don't try to catch up after a stall
      end
    end
  end
end

local function run_metros()
  for _, m in ipairs(metros) do
    if m.running and now >= m.next then
      m.fired = m.fired + 1
      m.next = math.max(m.next + m.time, now)
      if m.event then m.event(m.fired) end
      if m.count > 0 and m.fired >= m.count then m.running = false end
    end
  end
end

-- ---------- util, tab ----------
util = {}
function util.clamp(v, a, b) return math.max(a, math.min(b, v)) end
function util.round(n, q) q = q or 1; return math.floor(n / q + 0.5) * q end
function util.round_up(n, q) q = q or 1; return math.ceil(n / q) * q end
function util.linlin(a, b, c, d, x) return c + (d - c) * (util.clamp(x, math.min(a, b), math.max(a, b)) - a) / (b - a) end
function util.linexp(a, b, c, d, x) return c * (d / c) ^ ((util.clamp(x, math.min(a, b), math.max(a, b)) - a) / (b - a)) end
function util.explin(a, b, c, d, x) return c + (d - c) * math.log(x / a) / math.log(b / a) end
function util.time() return now end
function util.trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function util.acronym(s) return (tostring(s):gsub("(%w)%w*%s*", "%1")) end
function util.file_exists(path) local f = io.open(path, "r"); if f then f:close(); return true end; return false end
function util.os_capture(cmd) return js.os_capture(cmd) or "" end
function util.make_dir() end
function util.scandir() return {} end
function util.wrap(n, min, max) return (n - min) % (max - min + 1) + min end
tab = {}
function tab.invert(t) local r = {}; for k, v in pairs(t) do r[v] = k end; return r end
function tab.contains(t, x) for _, v in pairs(t) do if v == x then return true end end; return false end
function tab.count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
function tab.key(t, x) for k, v in pairs(t) do if v == x then return k end end end
function tab.print(t) for k, v in pairs(t) do print(k, v) end end
function tab.split(s, sep)
  local r = {}
  for part in tostring(s):gmatch("([^" .. sep .. "]+)") do r[#r + 1] = part end
  return r
end

-- ---------- engine: commands go to the page's stand-in for the SuperCollider engine ----------
engine = setmetatable({}, {
  __index = function(t, k)
    if k == "name" then return rawget(t, "_name") end
    return function(...) js.engine(k, ...) end
  end,
  __newindex = function(t, k, v)
    if k == "name" then rawset(t, "_name", v); js.engine_name(v) else rawset(t, k, v) end
  end,
})

-- ---------- the rest of the system ----------
_path = { code = "/code/", dust = "/dust/", data = "/data/", audio = "/audio/" }
norns = {
  state = {}, version = { update = "norns-web" },
  system_cmd = function(cmd, cb) print("system_cmd (not run in the browser): " .. cmd); if cb then cb("") end end,
  enc = { sens = function() end, accel = function() end },
  none = function() end,
}
function include(file)
  for _, base in ipairs({ norns.state.path, _path.code }) do
    local path = base .. file .. ".lua"
    if util.file_exists(path) then return dofile(path) end
  end
  error("include: can't find " .. file, 2)
end
-- midi: out through the host, when it has ports (js.midi_ports() names them, js.midi_send(port,
-- bytes...) sends, stamped with util.time); otherwise every port is "none" and sending is silent
midi = setmetatable({ vports = {}, devices = {} }, { __index = function() return function() end end })
local midi_ports = js.midi_ports and js.midi_ports() or {}
for i = 1, 16 do
  local name = midi_ports[i]
  midi.vports[i] = { name = name or "none", connected = name ~= nil }
end
local function midi_device(port)
  local d = { port = port, name = midi.vports[port] and midi.vports[port].name or "none" }
  local function send(...) if js.midi_send and midi.vports[port] and midi.vports[port].connected then js.midi_send(port, ...) end end
  local function status(s, ch) return s + util.clamp((ch or 1) - 1, 0, 15) end
  function d:note_on(n, v, ch) send(status(0x90, ch), n, v or 100) end
  function d:note_off(n, v, ch) send(status(0x80, ch), n, v or 0) end
  function d:cc(cc, v, ch) send(status(0xB0, ch), cc, v) end
  function d:pitchbend(v, ch) send(status(0xE0, ch), v & 0x7f, (v >> 7) & 0x7f) end
  function d:program_change(v, ch) send(status(0xC0, ch), v) end
  function d:send(data) if type(data) == "table" then send(table.unpack(data)) end end
  return d
end
function midi.connect(port) return midi_device(port or 1) end
grid, arc, hid, crow, softcut, audio, poll, osc, keyboard, gamepad = stub("grid"), stub("arc"), stub("hid"),
  stub("crow"), stub("softcut"), stub("audio"), stub("poll"), stub("osc"), stub("keyboard"), stub("gamepad")
_menu = { rebuild_params = function() end, redraw = function() end }
wifi = stub("wifi")

-- ---------- a built-in nb voice ----------
-- nb (sixolet/nb) finds voices in the global note_players, which mods fill in on a
-- norns. Here there are no mods, so the page offers one simple voice, played in JS.
note_players = note_players or {}
note_players["web synth"] = {
  add_params = function() end,
  note_on = function(_, note, vel) js.nb("on", note, vel or 1) end,
  note_off = function(_, note) js.nb("off", note, 0) end,
  modulate = function(_, v) js.nb("mod", 0, v) end,
  describe = function()
    return { name = "web synth", supports_bend = false, supports_slew = false, modulate_description = "brightness",
      note_mod_targets = {}, voice_mod_targets = {}, params = {} }
  end,
}

-- ---------- the page's entry points ----------
local function guarded(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then js.error(tostring(err)) end
end

-- dir: the script's folder, when it isn't _path.code .. name (a plugin carries it in its bundle)
function norns_web.boot(name, main, dir)
  dir = dir or (_path.code .. name .. "/")
  norns.state = { name = name, shortname = name, path = dir, script = dir .. main, data = _path.data .. name .. "/" }
  guarded(function()
    dofile(norns.state.script)
    if init then init() end
  end)
end

function norns_web.tick(t)
  now = t
  if running then guarded(run_clocks) end
  guarded(run_metros)
  if dirty then
    dirty = false
    return frame_string()
  end
end

-- the page's REPL, like maiden's: an expression prints its value, anything else just runs
function norns_web.repl(code)
  local chunk = load("return " .. code, "repl") or load(code, "repl")
  if not chunk then
    local _, err = load(code, "repl")
    js.error(tostring(err))
    return
  end
  local res = table.pack(pcall(chunk))
  if not res[1] then js.error(tostring(res[2])); return end
  if res.n > 1 then
    local parts = {}
    for i = 2, res.n do parts[#parts + 1] = tostring(res[i]) end
    print(table.concat(parts, "\t"))
  end
end

function norns_web.enc(n, d) if enc then guarded(enc, n, d) end end
function norns_web.key(n, z) if key then guarded(key, n, z) end end
function norns_web.set_tempo(t) tempo = t end
-- a host's transport: stopped, the clock routines wait (the screen's metros go on); started
-- again, one waiting on clock.sync lands on its next beat, one asleep wakes no earlier than now
function norns_web.set_running(on)
  if on == running then return end
  running = on
  if not on then return end
  local beat_sec = 60 / tempo
  for _, r in pairs(routines) do
    if r.sync then
      r.wake = math.max(r.wake, (math.floor(now / beat_sec / r.sync - 1e-6) + 1) * r.sync * beat_sec)
    elseif r.wake < now then
      r.wake = now
    end
  end
end
