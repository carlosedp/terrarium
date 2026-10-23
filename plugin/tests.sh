#!/usr/bin/env bash
# The plugin's core, tested without a DAW: terrarium-render plays the jar offline and each check
# reads what it reports. Run from the repo's root, with the built renderer:
#
#   bash plugin/tests.sh build/plugin/terrarium-render
#
# CI runs it on every push and PR (plugin-core.yml) and before every release (plugin.yml).
set -euo pipefail
r=${1:?usage: plugin/tests.sh <terrarium-render>}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
say() { printf '\n== %s\n' "$*"; }

say "on the host's beat: 93 BPM, starting off-beat, an odd block size"
"$r" --script . --seconds 20 --bpm 93 --start 3.37 --block 441 --quiet --out "$out/beat.wav"

say "PARAMS, for the face and the host's automation"
"$r" --script . --quiet --check-params

say "every slot's modules swapped mid-play, twice a second (built off the audio thread)"
args=()
i=0
for t in $(seq 1 0.5 19); do
  case $((i % 6)) in
    0) c="params:set('voice_kind', $((i % 4 + 1)))" ;; 1) c="params:set('color_kind', $((i % 2 + 1)))" ;;
    2) c="params:set('air_kind', $((i % 3 + 1)))" ;;   3) c="params:set('drone_kind', $((i % 3 + 1)))" ;;
    4) c="params:set('t_erosion', $((i % 5 + 1)))" ;;  5) c="params:set('brain_kind', $((i % 3 + 1)))" ;;
  esac
  args+=(--at "$t" "$c")
  i=$((i + 1))
done
"$r" --script . --quiet --seconds 20 --out "$out/swaps.wav" "${args[@]}"

# the engine runs at 48 kHz at any host rate: about the same level at 44.1, 48 and 96 kHz (the notes
# differ from run to run on some platforms, so not exactly; before, 96 kHz was 40% quieter)
say "the same level at any sample rate"
for sr in 44100 48000 96000; do
  "$r" --script . --quiet --seconds 20 --sr "$sr" --out "$out/sr.wav" | grep -o 'rms [0-9.]*' | cut -d' ' -f2
done | awk '{ v[NR] = $1; if (NR == 1 || $1 < lo) lo = $1; if ($1 > hi) hi = $1 }
  END { printf "rms by rate: %s %s %s\n", v[1], v[2], v[3]; if (hi > lo * 1.25) { print "levels differ by rate"; exit 1 } }'

say "stop with the transport: no notes while it's stopped"
"$r" --script . --quiet --seconds 25 --stopped-between 8 16 --stop-with-transport --out "$out/stop.wav" | tee "$out/stop.txt"
grep -q ': 0 notes meanwhile' "$out/stop.txt"

say "visitors: notes out to the DAW's MIDI port, the input let in"
"$r" --script . --quiet --seconds 15 --midi-ports "DAW,device" --input-tone \
  --lua "params:set('voice_kind', 4)" --lua "params:set('visitors_midi', 2)" --out "$out/visitors.wav" | tee "$out/v.txt"
grep -qE 'MIDI: [1-9][0-9]* messages to the DAW' "$out/v.txt"

say "all good"
