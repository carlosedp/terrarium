-- brain: which notes play, and in what key.
--
-- * phrase: a Turing Machine-style register of 16 steps (the first `length` are
--   used). Each step is a note {x, seed, born} or false (a rest). Every time a
--   step plays, `change` is the chance it mutates first: a note is replaced
--   (75%) or dropped to a rest (25%); a rest gets a new note.
-- * pitch: x is a place on the land, mapped to a fixed semitone (C3 at the far
--   left) and stepped to the nearest note of the current key and scale.
-- * seasons: at the end of a phrase, every few phrases, the key moves to a
--   close neighbor (one note changed, or a pentatonic gaining or losing two),
--   drifting from home and finding its way back.
-- When notes happen is up to the brain modules (rain, lightning).

local H = include('lib/helpers')

local Brain = {}

Brain.NOTES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
Brain.SCALES = {
  { name = "major",      iv = { 0, 2, 4, 5, 7, 9, 11 } },
  { name = "minor",      iv = { 0, 2, 3, 5, 7, 8, 10 } },
  { name = "dorian",     iv = { 0, 2, 3, 5, 7, 9, 10 } },
  { name = "mixolydian", iv = { 0, 2, 4, 5, 7, 9, 10 } },
  { name = "lydian",     iv = { 0, 2, 4, 6, 7, 9, 11 } },
  { name = "phrygian",   iv = { 0, 1, 3, 5, 7, 8, 10 } },
  { name = "maj pent",   iv = { 0, 2, 4, 7, 9 } },
  { name = "min pent",   iv = { 0, 3, 5, 7, 10 } },
  { name = "hirajoshi",  iv = { 0, 2, 3, 7, 8 } },
}

local BASE = 48 -- C3, the far left of the land

Brain.root = 2       -- 0..11 (D)
Brain.scale = 3      -- index into SCALES (dorian)
Brain.octaves = 3
Brain.length = 8
Brain.home = { root = 2, scale = 3 }
Brain.season_every = 0 -- phrases between season turns, 0 = off
Brain.phrases = 0
Brain.season_t = -9
Brain.reg = {}
Brain.pos = 0
Brain.last_step, Brain.last_step_t = 0, -9
Brain.on_season = nil -- callback after the key turns

function Brain.scale_names()
  local t = {}
  for i, s in ipairs(Brain.SCALES) do t[i] = s.name end
  return t
end

function Brain.key_name(r, s)
  r, s = r or Brain.root, s or Brain.scale
  return Brain.NOTES[r + 1] .. " " .. Brain.SCALES[s].name
end

function Brain.set_home() Brain.home = { root = Brain.root, scale = Brain.scale } end

-- ---------- phrase ----------

function Brain.new_note(t)
  return { x = H.clamp(64 + H.gauss() * 60, 4, 123), seed = math.random(1, 1 << 30), born = t }
end

function Brain.new_phrase(t)
  for i = 1, 16 do Brain.reg[i] = math.random() < 0.85 and Brain.new_note(t) or false end
  Brain.pos = 0
end

-- advance one step; returns the note to play (or nil for a rest) and whether it is new
function Brain.step(change, t)
  local len = Brain.length
  local i = (Brain.pos % len) + 1
  Brain.pos = (Brain.pos + 1) % len
  if math.random() < change * change then
    if Brain.reg[i] and math.random() < 0.25 then Brain.reg[i] = false else Brain.reg[i] = Brain.new_note(t) end
  end
  local any = false
  for k = 1, len do if Brain.reg[k] then any = true; break end end
  if not any then Brain.reg[i] = Brain.new_note(t) end -- never let the phrase go silent
  Brain.last_step, Brain.last_step_t = i, t
  if i == len and Brain.on_phrase then Brain.on_phrase() end
  if i == len and Brain.season_every > 0 then
    Brain.phrases = Brain.phrases + 1
    if Brain.phrases >= Brain.season_every then
      Brain.phrases = 0
      Brain.turn_season(t)
    end
  end
  local ev = Brain.reg[i]
  if not ev then return nil end
  return ev, ev.born == t
end

-- ---------- pitch ----------

function Brain.pcs(r, s)
  local m = 0
  for _, iv in ipairs(Brain.SCALES[s].iv) do m = m | (1 << ((r + iv) % 12)) end
  return m
end

local function bits(m)
  local n = 0
  while m > 0 do n = n + (m & 1); m = m >> 1 end
  return n
end

-- notes that change between two sets: a swap (B to Bb) is 1, adding two notes is 2
function Brain.diff(a, b) return math.max(bits(a & ~b), bits(b & ~a)) end

-- the drone's note: the key's root (C3 + root; an octave lower sat below small speakers)
function Brain.drone_root() return 48 + Brain.root end

-- place on the land -> MIDI note
function Brain.pitch(x)
  local span = 12 * Brain.octaves
  local slot = H.clamp(H.round((x - 4) / 119 * span), 0, span)
  local set = Brain.pcs(Brain.root, Brain.scale)
  for d = 0, 6 do
    for _, s in ipairs({ slot - d, slot + d }) do -- down first on a tie
      if s >= 0 and s <= span and ((set >> ((BASE + s) % 12)) & 1) == 1 then return BASE + s end
    end
  end
  return BASE + slot
end

-- ---------- seasons ----------

function Brain.turn_season(t)
  local now = Brain.pcs(Brain.root, Brain.scale)
  local home = Brain.pcs(Brain.home.root, Brain.home.scale)
  local by_set = {}
  for r = 0, 11 do
    for s = 1, #Brain.SCALES do
      local set = Brain.pcs(r, s)
      local d = Brain.diff(now, set)
      local ok = d >= 1 and d <= 2 and Brain.diff(set, home) <= 3        -- close to here, not far from home
      if ok and d == 2 and (set & now) ~= now and (set & now) ~= set then -- two-note moves only add or remove
        ok = false
      end
      if ok then
        -- one candidate per set of notes, named with the current root, else home's
        local rank = (r == Brain.root) and 0 or ((r == Brain.home.root) and 1 or 2)
        local prev = by_set[set]
        if not prev or rank < prev.rank then
          by_set[set] = { r = r, s = s, d = d, rank = rank, to_home = Brain.diff(set, home) }
        end
      end
    end
  end
  local cands = {}
  for _, c in pairs(by_set) do cands[#cands + 1] = c end
  if #cands == 0 then return end
  table.sort(cands, function(a, b) return a.r * 100 + a.s < b.r * 100 + b.s end)

  local pick
  if Brain.diff(now, home) > 0 and math.random() < 0.4 then
    local nearest = math.huge
    for _, c in ipairs(cands) do nearest = math.min(nearest, c.to_home) end
    local back = {}
    for _, c in ipairs(cands) do if c.to_home == nearest then back[#back + 1] = c end end
    pick = back[math.random(#back)]
  else
    local w = {}
    for _, c in ipairs(cands) do
      w[#w + 1] = c
      if c.d == 1 then w[#w + 1] = c; w[#w + 1] = c end -- one-note moves are likelier
    end
    pick = w[math.random(#w)]
  end
  Brain.root, Brain.scale, Brain.season_t = pick.r, pick.s, t
  if Brain.on_season then Brain.on_season() end
end

return Brain
