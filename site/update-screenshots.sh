#!/bin/sh
# Copies the session screen snapshots into the site. Run after re-recording them.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
src="$here/../Packages/Tests/DesignTests/__Snapshots__/SnapshotTests"
cp "$src/sessionScreen-device-scheme.402-dark.png" "$here/images/session-dark.png"
cp "$src/sessionScreen-device-scheme.402-light.png" "$here/images/session-light.png"
