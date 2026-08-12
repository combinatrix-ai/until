#!/usr/bin/env bash
set -euo pipefail
# Render assets/store/slide*.html to 2880x1800 PNGs for the Mac App Store.
# Headless Chrome sometimes never exits after writing the shot, so run it in
# the background, wait for the file, then kill it.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/.build/store-shots}"
mkdir -p "$OUT"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for f in "$ROOT"/assets/store/slide*.html; do
  name="$(basename "${f%.html}")"
  shot="$OUT/$name.png"
  rm -f "$shot"
  profile="$(mktemp -d)"
  "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$profile" \
    --window-size=2880,1800 --force-device-scale-factor=1 \
    --screenshot="$shot" --hide-scrollbars "file://$f" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 60); do
    [[ -f "$shot" ]] && break
    sleep 1
  done
  sleep 1
  kill "$pid" 2>/dev/null || true
  sleep 1
  rm -rf "$profile" 2>/dev/null || true
  if [[ -f "$shot" ]]; then echo "$shot"; else echo "FAILED: $name" >&2; exit 1; fi
done
