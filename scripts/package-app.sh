#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Build-time secrets: sourced from .env (gitignored) if present, then read from
# the environment. Baked into Info.plist below so the GUI app — which does not
# inherit a shell environment when launched via `open` — can read them at runtime.
if [[ -f "$ROOT/.env" ]]; then
  set -a; source "$ROOT/.env"; set +a
fi
GOOGLE_OAUTH_CLIENT_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"
GOOGLE_OAUTH_CLIENT_SECRET="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
if [[ -z "$GOOGLE_OAUTH_CLIENT_ID" || -z "$GOOGLE_OAUTH_CLIENT_SECRET" ]]; then
  echo "Warning: GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET not set (check .env); Google sign-in will fail." >&2
fi

CONFIGURATION="${CONFIGURATION:-debug}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="Until"
APP_DIR="$ROOT/.build/$CONFIGURATION/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/$CONFIGURATION/Until"

build_args=()
if [[ -n "$CONFIGURATION" ]]; then
  build_args=(--configuration "$CONFIGURATION")
fi
swift build "${build_args[@]}"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Until"

# SwiftPM localized resources (en.lproj / ja.lproj) are compiled into
# Until_Until.bundle. At runtime the app resolves them via
# Localization.swift's `localizationBundle`, which looks in Contents/Resources
# (the conventional, codesign-clean location). Copy the bundle there. Without
# this, every localized string would silently fall back to its English key.
RESOURCE_BUNDLE="$ROOT/.build/$CONFIGURATION/Until_Until.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/Until_Until.bundle"
else
  echo "Warning: $RESOURCE_BUNDLE not found; localized strings will fall back to English." >&2
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Until</string>
  <key>CFBundleIconFile</key>
  <string>Until</string>
  <key>CFBundleIdentifier</key>
  <string>ai.combinatrix.until</string>
  <key>CFBundleName</key>
  <string>Until</string>
  <key>CFBundleDisplayName</key>
  <string>Until</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSCalendarsUsageDescription</key>
  <string>Until reads Google Calendar events through Google OAuth.</string>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
  <key>GoogleOAuthClientID</key>
  <string>${GOOGLE_OAUTH_CLIENT_ID}</string>
  <key>GoogleOAuthClientSecret</key>
  <string>${GOOGLE_OAUTH_CLIENT_SECRET}</string>
</dict>
</plist>
PLIST

# App icon. Generated once from scripts/make-icon.swift, then reused so dev
# rebuilds stay fast; delete scripts/Until.icns to regenerate after a redesign.
ICON_SRC="$ROOT/scripts/Until.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  swift "$ROOT/scripts/make-icon.swift" >/dev/null
fi
cp "$ICON_SRC" "$APP_DIR/Contents/Resources/Until.icns"

# Signing.
# - Dev (default): an Apple Development identity, no secure timestamp, so
#   rebuilds stay fast/offline and the Keychain doesn't re-prompt every launch.
# - Distribution (DISTRIBUTION=1): a Developer ID Application identity with the
#   hardened runtime and a secure timestamp — both prerequisites for
#   notarization. Driven by scripts/release.sh.
DISTRIBUTION="${DISTRIBUTION:-0}"
if [[ "$DISTRIBUTION" == "1" ]]; then
  identity_pattern='Developer ID Application'
else
  identity_pattern='Apple Development'
fi

codesign_identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$codesign_identity" ]]; then
  codesign_identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n "s/.*\"\\(${identity_pattern}:[^\"]*\\)\".*/\\1/p" \
      | head -n 1
  )"
fi

if [[ -n "$codesign_identity" ]]; then
  codesign_args=(--force --sign "$codesign_identity")
  if [[ "$DISTRIBUTION" == "1" ]]; then
    codesign_args+=(--options runtime --timestamp)
  else
    codesign_args+=(--timestamp=none)
  fi
  codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null
  echo "Signed with: $codesign_identity"
elif [[ "$DISTRIBUTION" == "1" ]]; then
  echo "Error: no '$identity_pattern' codesigning identity found; cannot build a distributable app." >&2
  exit 1
else
  echo "Warning: no '$identity_pattern' codesigning identity found; Keychain may ask again after rebuilds." >&2
fi

echo "$APP_DIR"
