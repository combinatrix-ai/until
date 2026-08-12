#!/usr/bin/env bash
set -euo pipefail

# Build a Mac App Store/TestFlight-ready .app and installer .pkg.
#
# Local verification is supported with the Apple Development identity currently
# available on this machine. A real App Store upload needs an Apple Distribution
# app certificate, a Mac Installer Distribution certificate, and an App Store
# provisioning profile. The profile is copied into the app when
# MAS_PROVISIONING_PROFILE is set.
#
# Usage:
#   TEAM_ID=... scripts/release-mas.sh
#
# Env overrides:
#   TEAM_ID                    required Apple Developer Team ID
#   APP_VERSION                bundle short version (default: 0.1.0)
#   BUILD_NUMBER               bundle build number (default: 1)
#   CODESIGN_IDENTITY          app signing identity
#   MAS_PROVISIONING_PROFILE   App Store provisioning profile path
#   MAS_INSTALLER_IDENTITY     installer signing identity

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID.}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ -z "${MAS_PROVISIONING_PROFILE:-}" ]]; then
  echo "Warning: MAS_PROVISIONING_PROFILE is not set; this build is for local verification only and cannot be submitted to the Mac App Store." >&2
fi

APP_DIR="$(
  CONFIGURATION=release \
  MAS=1 \
  TEAM_ID="$TEAM_ID" \
  APP_VERSION="$APP_VERSION" \
  BUILD_NUMBER="$BUILD_NUMBER" \
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}" \
  MAS_PROVISIONING_PROFILE="${MAS_PROVISIONING_PROFILE:-}" \
  "$ROOT/scripts/package-app.sh" | tail -n 1
)"
echo "Built: $APP_DIR"

# Fail early if the app signature is malformed or its sandbox entitlements were
# not sealed into the bundle.
codesign --verify --strict --verbose=2 "$APP_DIR"
entitlements="$(codesign -d --entitlements :- "$APP_DIR" 2>/dev/null)"
for key in \
  'com.apple.security.app-sandbox' \
  'com.apple.security.network.client' \
  'com.apple.security.network.server'; do
  [[ "$entitlements" == *"<key>$key</key>"* ]] || {
    echo "Error: signed app is missing entitlement '$key'." >&2
    exit 1
  }
done

installer_identity="${MAS_INSTALLER_IDENTITY:-}"
if [[ -z "$installer_identity" ]]; then
  for identity_pattern in \
    '3rd Party Mac Developer Installer' \
    'Apple Distribution Installer' \
    'Mac Installer Distribution'; do
    installer_identity="$(
      security find-identity -v 2>/dev/null \
        | sed -n "s/.*\"\\(${identity_pattern}:[^\"]*\\)\".*/\\1/p" \
        | head -n 1
    )"
    [[ -n "$installer_identity" ]] && break
  done
fi

PKG_PATH="$ROOT/.build/release/Until-mas.pkg"
rm -f "$PKG_PATH"

if [[ -n "$installer_identity" ]]; then
  productbuild \
    --component "$APP_DIR" /Applications \
    --sign "$installer_identity" \
    "$PKG_PATH"
  echo "Signed installer with: $installer_identity"
else
  echo "WARNING: no Mac App Store installer signing identity found; producing an unsigned pkg for local inspection only." >&2
  echo "Next steps for a real Mac App Store/TestFlight submission:" >&2
  echo "  1. Create an 'Apple Distribution' app certificate and a 'Mac Installer Distribution' certificate." >&2
  echo "  2. Create/download an App Store provisioning profile for ai.combinatrix.until in the Apple Developer portal." >&2
  echo "  3. Re-run with MAS_PROVISIONING_PROFILE set and a matching MAS_INSTALLER_IDENTITY." >&2
  echo "  4. Upload the signed .pkg with Transporter.app (or Xcode Organizer)." >&2
  productbuild --component "$APP_DIR" /Applications "$PKG_PATH"
fi

echo
echo "Team ID:              $TEAM_ID"
echo "Mac App Store bundle: $APP_DIR"
echo "Installer package:    $PKG_PATH"
