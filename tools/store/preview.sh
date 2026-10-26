#!/bin/sh
# Cuts the clips simctl recorded into the app preview: 886 by 1920, 30 fps, H.264, silent stereo.
# tools/store/preview.sh <clips dir> <out.mp4>
# The clips dir holds the .mov files and shots.tsv, one shot per line, tab separated:
# clip file, start second, duration, caption. storyboard.md gives the intended rows.
set -eu
# shellcheck source=serve.sh
. "$(dirname -- "$0")/serve.sh"
clips=$1
out=$2
serve "$clips"

frames="$stage/frames"
mkdir -p "$frames"
inputs=""
filter=""
n=0
while IFS="$(printf '\t')" read -r clip start duration caption; do
  [ -n "$clip" ] || continue
  encoded=$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$caption")
  shoot 886x1920 "$frames/$n.png" "http://127.0.0.1:$port/store/preview-frame.html#$encoded" \
    --default-background-color=00000000
  inputs="$inputs -ss $start -t $duration -i $clips/$clip -loop 1 -t $duration -i $frames/$n.png"
  v=$((n * 2))
  f=$((n * 2 + 1))
  # A clip shorter than its shot holds its last frame.
  filter="${filter}[$v:v]fps=30,scale=726:1577:flags=lanczos,setsar=1,"
  filter="${filter}tpad=stop_mode=clone:stop_duration=$duration,trim=duration=$duration,setpts=PTS-STARTPTS[c$n];"
  filter="${filter}color=c=0x0c0d11:s=886x1920:r=30:d=${duration}[b$n];"
  filter="${filter}[b$n][c$n]overlay=80:432:shortest=1[p$n];"
  filter="${filter}[p$n][$f:v]overlay=0:0:shortest=1,trim=duration=$duration,setpts=PTS-STARTPTS[s$n];"
  n=$((n + 1))
done < "$clips/shots.tsv"

i=0
while [ "$i" -lt "$n" ]; do
  filter="${filter}[s$i]"
  i=$((i + 1))
done
filter="${filter}concat=n=$n:v=1:a=0[v]"

# shellcheck disable=SC2086
ffmpeg -loglevel error -y $inputs -f lavfi -i anullsrc=r=48000:cl=stereo \
  -filter_complex "$filter" -map "[v]" -map "$((n * 2)):a" -shortest \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 10M -maxrate 12M -bufsize 24M \
  -r 30 -c:a aac -b:a 256k -movflags +faststart "$out"
ffprobe -v error -select_streams v -show_entries stream=width,height,r_frame_rate,codec_name:format=duration -of default=nw=1 "$out"
