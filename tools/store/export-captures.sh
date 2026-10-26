#!/bin/sh
# Copies every screenshot attachment out of a result bundle, named as the test attached it.
# tools/store/export-captures.sh <bundle.xcresult> <out dir>
set -eu
bundle=$1
out=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xcrun xcresulttool export attachments --path "$bundle" --output-path "$tmp" > /dev/null
mkdir -p "$out"
python3 -I - "$tmp" "$out" <<'PY'
import json, re, shutil, sys
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2])
for test in json.loads((src / "manifest.json").read_text()):
    for item in test["attachments"]:
        # xcresulttool suggests "<name>_<index>_<uuid>.png"; the test's name is what the templates load.
        match = re.fullmatch(r"(.+)_\d+_[0-9A-F-]{36}\.png", item["suggestedHumanReadableName"])
        if not match:
            continue
        name = match.group(1) + ".png"
        shutil.copy(src / item["exportedFileName"], out / name)
        print(name)
PY
