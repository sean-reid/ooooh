#!/bin/sh
# Resizes the session screen snapshots to the site's display sizes, plus a bare copy of each with the orb
# painted out for the landing page's travelling orb to land on. Run after re-recording them; needs magick and cwebp.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
src="$here/../App/Tests/__Snapshots__/SessionSnapshotTests"
# The band between the status bar and the question holds only the orb on a flat background.
band_top=0.094
band_bottom=0.829
for scheme in dark light; do
  for width in 280 560; do
    out="$here/images/session-$scheme-$width"
    magick "$src/speaking-scheme.402-$scheme.png" -filter Lanczos -resize "${width}x" -strip -define png:compression-level=9 "$out.png"
    cwebp -quiet -q 85 -m 6 "$out.png" -o "$out.webp"
    height=$(magick identify -format '%h' "$out.png")
    sky=$(magick "$out.png" -format '%[pixel:p{3,3}]' info:)
    top=$(printf '%.0f' "$(echo "$height * $band_top" | bc -l)")
    bottom=$(printf '%.0f' "$(echo "$height * $band_bottom" | bc -l)")
    magick "$out.png" -fill "$sky" -draw "rectangle 0,$top $width,$bottom" -strip -define png:compression-level=9 "$out-bare.png"
    cwebp -quiet -q 85 -m 6 "$out-bare.png" -o "$out-bare.webp"
  done
done
