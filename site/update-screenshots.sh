#!/bin/sh
# Resizes the session screen snapshots to the site's display sizes. Run after re-recording them; needs magick and cwebp.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
src="$here/../Packages/Tests/DesignTests/__Snapshots__/SnapshotTests"
for scheme in dark light; do
  for width in 280 560; do
    out="$here/images/session-$scheme-$width"
    magick "$src/sessionScreen-device-scheme.402-$scheme.png" -filter Lanczos -resize "${width}x" -strip -define png:compression-level=9 "$out.png"
    cwebp -quiet -q 85 -m 6 "$out.png" -o "$out.webp"
  done
done
