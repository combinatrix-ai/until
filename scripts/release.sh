#!/usr/bin/env bash
set -euo pipefail

# Build, Developer ID-sign, notarize, and staple a distributable .app + .zip.
#
# One-time prerequisites:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. notarytool credentials saved as a keychain profile, e.g.:
#        xcrun notarytool store-credentials until-notary \
#          --apple-id "<your-apple-id-email>" \
#          --team-id "<your-team-id>" \
#          --password "<app-specific-password>"
#      Create the app-specific password at https://account.apple.com
#      (Sign-In and Security -> App-Specific Passwords).
#
# Usage:
#   scripts/release.sh                # build + sign + notarize + staple
#   NOTARIZE=0 scripts/release.sh     # build + Developer ID sign only
#
# Env overrides:
#   CODESIGN_IDENTITY   signing identity, e.g. "Developer ID Application: Example Corp (TEAMID)"
#   NOTARY_PROFILE      notarytool keychain profile (default: until-notary)
#   TEAM_ID             Developer Team ID

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID.}"
NOTARY_PROFILE="${NOTARY_PROFILE:-until-notary}"
NOTARIZE="${NOTARIZE:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application signing identity.}"

# Build + bundle with distribution signing (Developer ID + hardened runtime +
# secure timestamp). package-app.sh prints the bundle path on its last line.
APP_DIR="$(
  CONFIGURATION=release \
  DISTRIBUTION=1 \
  CODESIGN_IDENTITY="$CODESIGN_IDENTITY" \
  "$ROOT/scripts/package-app.sh" | tail -n 1
)"
echo "Built: $APP_DIR"

# Fail early if the signature isn't valid / not actually Developer ID-signed.
codesign --verify --strict --verbose=2 "$APP_DIR"

if [[ "$NOTARIZE" != "1" ]]; then
  echo "Skipping notarization (NOTARIZE=$NOTARIZE). Note: an un-notarized"
  echo "Developer ID app will still be blocked by Gatekeeper on other Macs."
  exit 0
fi

# The notary service takes a zip/dmg/pkg, not a raw .app bundle.
ZIP_PATH="${APP_DIR%.app}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# Staple the ticket onto the .app so it validates offline, then re-zip.
xcrun stapler staple "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Notarized + stapled."
echo "Gatekeeper assessment:"
spctl --assess --type execute --verbose=2 "$APP_DIR" || true
echo
echo "Distributable bundle: $APP_DIR"
echo "Distributable zip:    $ZIP_PATH"
