#!/bin/sh
# Renders every template in shots/ with headless Chrome: the screenshots at each App Store size,
# the product-page artwork at the sizes the Header and Search Results tab takes.
# tools/store/render.sh <captures dir> <out dir>
# The captures dir holds the PNGs export-captures.sh wrote; the templates load them by name.
set -eu
# shellcheck source=serve.sh
. "$(dirname -- "$0")/serve.sh"
serve "$1"
out=$2
# Apple's names for the display classes, then the pixel size rendered for each.
sizes="6.9:1320x2868 6.5:1284x2778 6.3:1206x2622"
# Each artwork file, then the template drawn at the size in its name; universal fills both slots.
art="header-3840x1646:header search-3840x2560:search search-sunrise-3840x2560:search-sunrise universal-5244x2950:header"

mkdir -p "$out"
for template in "$here"/shots/*.html; do
  name=$(basename "$template" .html)
  case " $art " in *":$name "*) continue ;; esac
  for entry in $sizes; do
    label=${entry%%:*}
    shoot "${entry#*:}" "$out/$name-$label.png" "http://127.0.0.1:$port/store/shots/$name.html"
    echo "$name-$label.png"
  done
done
for entry in $art; do
  file=${entry%%:*}
  shoot "${file##*-}" "$out/$file.png" "http://127.0.0.1:$port/store/shots/${entry#*:}.html"
  echo "$file.png"
done
