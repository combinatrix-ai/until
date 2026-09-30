#!/usr/bin/env bash
set -euo pipefail
# Render docs/og-image.png and docs/og-image-ja.png (1200x630) from
# scripts/og-image.html with headless Chrome. Run scripts/make-site-art.py
# first so the illustration is current.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() {
  local query="$1" shot="$2"
  rm -f "$shot"
  local profile
  profile="$(mktemp -d)"
  "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$profile" \
    --allow-file-access-from-files --window-size=1200,630 --force-device-scale-factor=1 \
    --hide-scrollbars --virtual-time-budget=4000 --screenshot="$shot" \
    "file://$ROOT/scripts/og-image.html$query" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 60); do
    [[ -f "$shot" ]] && break
    sleep 1
  done
  sleep 1
  kill "$pid" 2>/dev/null || true
  rm -rf "$profile" 2>/dev/null || true
  [[ -f "$shot" ]] || { echo "FAILED: $shot" >&2; exit 1; }
  echo "$shot"
}
render "" "$ROOT/docs/og-image.png"
render "?lang=ja" "$ROOT/docs/og-image-ja.png"
