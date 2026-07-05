#!/usr/bin/env bash
set -euo pipefail

# Dev loop for Until: kill the running instance, rebuild as a real
# .app bundle (so notifications / LSUIElement behave like production), and launch.
#
#   scripts/dev.sh            rebuild + launch, keeping existing credentials
#   scripts/dev.sh --fresh    also wipe config + OAuth tokens to reproduce a
#                             clean first launch (onboarding / sign-in flow)
#   scripts/dev.sh --demo-mode
#                             launch with demo calendars/events for screenshots
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_NAME="Until"
APP_DIR="$ROOT/.build/$CONFIGURATION/$APP_NAME.app"

# Credential locations (kept in sync with ConfigStore.swift / KeychainStore.swift).
CONFIG_DIR="$HOME/Library/Application Support/Until"
KEYCHAIN_SERVICE="app.until"
KEYCHAIN_ACCOUNT="google-oauth"

FRESH=0
DEMO_MODE=0
for arg in "$@"; do
  case "$arg" in
    --fresh|-f) FRESH=1 ;;
    --demo-mode) DEMO_MODE=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Stop any instance from a previous run so the new build takes over the menubar.
pkill -f "$APP_NAME.app/Contents/MacOS/Until" 2>/dev/null || true

if [[ "$FRESH" == "1" ]]; then
  echo "Resetting credentials for a clean first launch…"
  rm -rf "$CONFIG_DIR"
  # Delete every matching token entry; ignore "not found".
  while security delete-generic-password \
      -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; do :; done
fi

# Build + bundle. Output streams to the terminal so build errors stay visible;
# package-app.sh exits non-zero on failure and aborts the script via `set -e`.
CONFIGURATION="$CONFIGURATION" "$ROOT/scripts/package-app.sh"

if [[ "$DEMO_MODE" == "1" ]]; then
  open "$APP_DIR" --args --demo-mode
else
  open "$APP_DIR"
fi

if [[ "$FRESH" == "1" && "$DEMO_MODE" == "1" ]]; then
  echo "Launched: $APP_DIR (fresh, demo mode)"
elif [[ "$FRESH" == "1" ]]; then
  echo "Launched: $APP_DIR (fresh)"
elif [[ "$DEMO_MODE" == "1" ]]; then
  echo "Launched: $APP_DIR (demo mode)"
else
  echo "Launched: $APP_DIR"
fi
