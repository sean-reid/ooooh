# Sourced by render.sh and preview.sh: serves the site, the fonts, this directory, and a captures
# directory over one local port, so the templates load as modules the way the site does.
# serve <captures dir>; sets $port and $stage, and tears both down when the caller exits.
serve() {
  here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
  root=$(CDPATH= cd -- "$here/../.." && pwd -P)
  port=${PORT:-8923}
  stage=$(mktemp -d)
  ln -s "$root/site" "$stage/site"
  ln -s "$root/Packages/Sources/Design/Fonts" "$stage/fonts"
  ln -s "$here" "$stage/store"
  ln -s "$(CDPATH= cd -- "$1" && pwd -P)" "$stage/captures"
  python3 -m http.server "$port" --bind 127.0.0.1 -d "$stage" > /dev/null 2>&1 &
  server=$!
  trap 'kill "$server" 2> /dev/null; wait "$server" 2> /dev/null || true; rm -rf "$stage"' EXIT
  sleep 1
}

chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}

# shoot <WxH> <out.png> <url> [more chrome flags]
shoot() {
  shoot_size=$1
  shoot_file=$2
  shoot_url=$3
  shift 3
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --user-data-dir="$stage/chrome" --force-prefers-reduced-motion \
    --virtual-time-budget=3000 --window-size="${shoot_size%x*},${shoot_size#*x}" \
    --screenshot="$shoot_file" "$@" "$shoot_url" 2> /dev/null
}
