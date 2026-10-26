#!/bin/sh
# Renders every template in shots/ at each App Store size with headless Chrome.
# tools/store/render.sh <captures dir> <out dir>
# The captures dir holds the PNGs export-captures.sh wrote; the templates load them by name.
set -eu
# shellcheck source=serve.sh
. "$(dirname -- "$0")/serve.sh"
serve "$1"
out=$2
# Apple's names for the display classes, then the pixel size rendered for each.
sizes="6.3:1206x2622 6.9:1320x2868 6.5:1284x2778"

mkdir -p "$out"
for template in "$here"/shots/*.html; do
  name=$(basename "$template" .html)
  for entry in $sizes; do
    label=${entry%%:*}
    shoot "${entry#*:}" "$out/$name-$label.png" "http://127.0.0.1:$port/store/shots/$name.html"
    echo "$name-$label.png"
  done
done
