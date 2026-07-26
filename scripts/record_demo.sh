#!/usr/bin/env bash
# Record the BLACKSTART demo to an MP4.
#
# Drives the real running app by clicking its own buttons, captures a frame at
# each beat, and stitches them with captions. Nothing is mocked - every number
# on screen came out of the simulator during the recording.
#
# Usage:
#   jac start --dev main.jac      # in another shell, with ANTHROPIC_API_KEY set
#   bash scripts/record_demo.sh
#
# Output: demo/blackstart-demo.mp4

set -euo pipefail

API="http://localhost:8001"
APP="http://localhost:8002/"
FRAMES="/tmp/bsframes"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/demo"
VIEWPORT="1600,1000"
B="jac browse -v $VIEWPORT"

rm -rf "$FRAMES"; mkdir -p "$FRAMES" "$OUT_DIR"

n=0
shot() {  # shot "<caption>" <seconds>
    n=$((n + 1))
    local id raw
    id=$(printf "%02d" "$n")
    raw=$($B screenshot 2>&1 | grep -oE '/[^ ]+\.png' | tail -1)
    cp "$raw" "$FRAMES/frame-$id.png"
    printf '%s\t%s\t%s\n' "$id" "$2" "$1" >> "$FRAMES/script.tsv"
    echo "  captured $id  (${2}s)  $1"
}

# Click a button by its visible label. Driving the real UI (rather than POSTing
# to the API) is what keeps the client's 60s read cache in step - a direct POST
# leaves the page showing stale numbers.
click_label() {
    local ref
    ref=$($B snapshot 2>/dev/null | grep -F "button \"$1\"" | grep -oE '@e[0-9]+' | head -1)
    if [ -z "$ref" ]; then
        echo "FATAL: no button labelled '$1' on the page" >&2
        exit 1
    fi
    $B click "$ref" >/dev/null 2>&1
}

# Fails loudly. A silent 422 here produces a video whose captions describe
# steps that never ran.
post() {
    local body="${2:-}"
    [ -z "$body" ] && body='{}'
    local resp
    resp=$(curl -s -X POST "$API/walker/$1" -H 'Content-Type: application/json' -d "$body")
    if ! printf '%s' "$resp" | grep -q '"ok":true'; then
        echo "FATAL: walker $1 failed: $(printf '%s' "$resp" | head -c 200)" >&2
        exit 1
    fi
}

echo "== resetting =="
post LoadSite '{"memory_enabled":true}'
$B open "$APP" >/dev/null 2>&1
sleep 9

echo "== capturing =="
shot "Naval Medical Center Portsmouth. A hospital, and a DoD installation." 5
shot "27 elements on the real campus. One island, running on utility power." 5

click_label "Cut river feeder"; sleep 5
shot "Cut the river feeder. Still lit - a second path is carrying the campus." 6

click_label "Cut both feeders"; sleep 5
shot "Both utility feeds gone. 76 hours left, under the 96 the law requires." 6

click_label "Run BLUE"; sleep 5
shot "BLUE sheds the galley, then imaging. 108 hours. No model involved." 6

click_label "Explain"; sleep 4
shot "Ask why the galley went dark. Every line cites the node it came from." 7

echo "== running a RED round (two model calls, be patient) =="
click_label "Run RED round"; sleep 50
shot "RED writes the next failure chain. Floods run downhill; trucks need roads." 7
$B scroll down >/dev/null 2>&1; sleep 3
shot "Then it writes down what it got wrong. The next round reads that sentence." 8

echo "== encoding =="
python3 "$(dirname "$0")/caption_frames.py" "$FRAMES"

ffmpeg -y -loglevel error -f concat -safe 0 -i "$FRAMES/concat.txt" \
    -vf "fps=30,format=yuv420p" -c:v libx264 -preset slow -crf 20 \
    -movflags +faststart "$OUT_DIR/blackstart-demo.mp4"

echo
echo "wrote $OUT_DIR/blackstart-demo.mp4"
ls -lh "$OUT_DIR/blackstart-demo.mp4" | awk '{print "  size:", $5}'
