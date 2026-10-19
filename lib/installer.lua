-- installer: terrarium needs mi-UGens (Mutable Instruments SuperCollider
-- plugins). If they're missing, the script shows this screen instead of the
-- scene and offers to install a norns build of them.
--
-- K3 downloads the latest release of norns-mi-UGens and installs it.
-- K2 installs a mi-UGens-norns*.tar.gz you copied into dust/ yourself.
-- If the core modules are there but Beads or Elements isn't (an older build), it
-- offers the update instead: K3 updates, K2 carries on without fireflies or roots.
-- Both run the install.sh that ships inside the tarball, which also moves
-- older mi-UGens installs aside so SuperCollider doesn't find duplicate classes.

local REPO = "carlosedp/norns-mi-UGens"
local URL = "https://github.com/" .. REPO .. "/releases/latest/download/mi-UGens-norns.tar.gz"
local EXT = "/home/we/.local/share/SuperCollider/Extensions"
local LOCAL_GLOB = "/home/we/dust/mi-UGens-norns*.tar.gz"

local installer = { ok = false, has_beads = false, has_elements = false, active = false, busy = false, lines = {},
  offer = false, on_skip = nil }

local function has(class)
  return util.os_capture("find " .. EXT .. " -name " .. class .. ".sc 2>/dev/null | head -1") ~= ""
end

function installer.check()
  installer.ok = has("MiPlaits") and has("MiRings") and has("MiRipples") and has("MiClouds") and has("MiVerb")
  installer.has_beads = has("MiBeads")
  installer.has_elements = has("MiElements")
  installer.lines = { "terrarium needs mi-UGens", "", "K3: download + install", "K2: install from dust/" }
end

-- the core is there, but an older build without Beads or Elements: offer the update once
function installer.offer_update(on_skip)
  local missing = {}
  if not installer.has_beads then missing[#missing + 1] = "Beads" end
  if not installer.has_elements then missing[#missing + 1] = "Elements" end
  installer.active, installer.offer, installer.on_skip = true, true, on_skip
  installer.lines = { "mi-UGens without " .. table.concat(missing, ", "), "", "K3: update (needs wifi)", "K2: carry on without" }
end

local function install(src, url)
  installer.busy = true
  local fetch = url
    and ("wget -q -T 180 -O \"$d/b.tgz\" '" .. url .. "' || { echo 'download failed'; exit 1; }")
    or ("cp '" .. src .. "' \"$d/b.tgz\"")
  local script = ([[
    d=$(mktemp -d); trap "rm -rf $d" EXIT
    FETCH
    tar -C "$d" -xzf "$d/b.tgz" || { echo "bad tarball"; exit 1; }
    bash "$d/install.sh" "$d/mi-UGens"
  ]]):gsub("FETCH", function() return fetch end)
  local cmd = "bash -c '" .. script:gsub("'", "'\\''") .. "' 2>&1; echo \"exit=$?\""
  norns.system_cmd(cmd, function(out)
    installer.busy = false
    print(out)
    if out:match("exit=0") then
      installer.lines = { "mi-UGens installed", "", "SYSTEM > RESTART", "then run terrarium again" }
    else
      local err = (out:gsub("exit=%d+", "")):gsub("%s+$", ""):match("[^\n]*$") or ""
      installer.lines = { "install failed:", err, "", "see maiden for details" }
    end
  end)
end

function installer.key(n, z)
  if z == 0 or installer.busy then return end
  if installer.offer and n == 2 then -- carry on with what's installed
    installer.active, installer.offer = false, false
    if installer.on_skip then installer.on_skip() end
    return
  end
  if n == 3 then
    installer.lines = { "downloading...", REPO }
    install(nil, URL)
  elseif n == 2 then
    local f = util.os_capture("ls -t " .. LOCAL_GLOB .. " 2>/dev/null | head -1")
    if f == "" then
      installer.lines = { "no tarball in dust/", "copy mi-UGens-norns*.tar.gz", "there first" }
    else
      installer.lines = { "installing", f:match("[^/]+$") }
      install(f)
    end
  end
end

function installer.draw()
  screen.font_face(1)
  screen.font_size(8)
  screen.level(15)
  screen.move(0, 8)
  screen.text("TERRARIUM")
  screen.level(installer.busy and 4 or 10)
  for i, line in ipairs(installer.lines) do
    screen.move(0, 18 + i * 9)
    screen.text(line)
  end
end

return installer
