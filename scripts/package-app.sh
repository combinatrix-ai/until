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
MAS="${MAS:-0}"
APP_NAME="Until"
APP_DIR="$ROOT/.build/$CONFIGURATION/$APP_NAME.app"
EXECUTABLE="$ROOT/.build/$CONFIGURATION/Until"

build_args=()
if [[ -n "$CONFIGURATION" ]]; then
  build_args=(--configuration "$CONFIGURATION")
fi
if [[ "$MAS" == "1" ]]; then
  build_args+=(--disable-default-traits)
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
  # SwiftPM writes only CFBundleDevelopmentRegion into the bundle's Info.plist.
  # App Store validation (error 90276) rejects nested bundles without a
  # CFBundleIdentifier, so fill in the standard identity keys here.
  RB_PLIST="$APP_DIR/Contents/Resources/Until_Until.bundle/Info.plist"
  plutil -replace CFBundleIdentifier -string "ai.combinatrix.until.resources" "$RB_PLIST"
  plutil -replace CFBundleName -string "Until_Until" "$RB_PLIST"
  plutil -replace CFBundlePackageType -string "BNDL" "$RB_PLIST"
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$RB_PLIST"
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$RB_PLIST"
else
  echo "Warning: $RESOURCE_BUNDLE not found; localized strings will fall back to English." >&2
fi

SPARKLE_PLIST_KEYS=""
if [[ "$MAS" != "1" ]]; then
  SPARKLE_PLIST_KEYS=$(cat <<'SPARKLE_PLIST'
  <key>SUFeedURL</key>
  <string>https://github.com/combinatrix-ai/until/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>u+Q8/UjDUddA0GV7hkaAaLr6erPJohhGGopaFdv+x2I=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
SPARKLE_PLIST
  )
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
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
  <key>GoogleOAuthClientID</key>
  <string>${GOOGLE_OAUTH_CLIENT_ID}</string>
  <key>GoogleOAuthClientSecret</key>
  <string>${GOOGLE_OAUTH_CLIENT_SECRET}</string>
${SPARKLE_PLIST_KEYS}
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

if [[ "$MAS" != "1" ]]; then
  # Embed Sparkle.framework (auto-update). SwiftPM links against the xcframework
  # but does not copy it into our hand-built bundle, so do it here. The framework's
  # install name is @rpath/Sparkle.framework/..., and the executable's only rpath
  # is @loader_path (Contents/MacOS); add @loader_path/../Frameworks so the loader
  # finds the framework in the conventional Contents/Frameworks location.
  SPARKLE_SRC="$ROOT/.build/$CONFIGURATION/Sparkle.framework"
  if [[ -d "$SPARKLE_SRC" ]]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_SRC" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_DIR/Contents/MacOS/Until"
  else
    echo "Warning: $SPARKLE_SRC not found; auto-update (Sparkle) will be unavailable. Run 'swift build' first." >&2
  fi
fi

if [[ "$MAS" == "1" && -n "${MAS_PROVISIONING_PROFILE:-}" ]]; then
  cp "$MAS_PROVISIONING_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
fi

# Signing.
# - Dev (default): an Apple Development identity, no secure timestamp, so
#   rebuilds stay fast/offline and the Keychain doesn't re-prompt every launch.
# - Distribution (DISTRIBUTION=1): a Developer ID Application identity with the
#   hardened runtime and a secure timestamp — both prerequisites for
#   notarization. Driven by scripts/release.sh.
if [[ "$MAS" == "1" ]]; then
  codesign_identity="${CODESIGN_IDENTITY:-}"
  if [[ -z "$codesign_identity" ]]; then
    for identity_pattern in \
      'Apple Distribution' \
      '3rd Party Mac Developer Application'; do
      codesign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
          | sed -n "s/.*\"\\(${identity_pattern}:[^\"]*\\)\".*/\\1/p" \
          | head -n 1
      )"
      [[ -n "$codesign_identity" ]] && break
    done
  fi

  if [[ -z "$codesign_identity" ]]; then
    identity_pattern='Apple Development'
    codesign_identity="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n "s/.*\"\\(${identity_pattern}:[^\"]*\\)\".*/\\1/p" \
        | head -n 1
    )"
    if [[ -n "$codesign_identity" ]]; then
      echo "Warning: no Apple Distribution or 3rd Party Mac Developer Application identity found; using '$codesign_identity'. This is a local-test signature only; the app is still sandboxed but cannot be submitted to the Mac App Store." >&2
    fi
  fi

  if [[ -n "$codesign_identity" ]]; then
    if [[ "$codesign_identity" == "Apple Development"* ]]; then
      echo "Warning: MAS build is signed with Apple Development; this is a local-test signature only and cannot be submitted to the Mac App Store." >&2
    fi

    # Store validation requires the application-identifier and team-identifier
    # entitlements that Xcode normally injects from the provisioning profile.
    # They are RESTRICTED entitlements: without an embedded provisioning profile
    # authorizing them, AMFI refuses to launch the app (launchd spawn error 163).
    # So inject them only when both TEAM_ID and a profile are present; the base
    # file alone gives a locally testable sandboxed app.
    entitlements_file="$ROOT/scripts/entitlements/mas.entitlements"
    if [[ -n "${TEAM_ID:-}" && -n "${MAS_PROVISIONING_PROFILE:-}" ]]; then
      entitlements_file="$(mktemp -t until-mas-entitlements).plist"
      sed "s|</dict>|  <key>com.apple.application-identifier</key>\\
  <string>${TEAM_ID}.ai.combinatrix.until</string>\\
  <key>com.apple.developer.team-identifier</key>\\
  <string>${TEAM_ID}</string>\\
</dict>|" "$ROOT/scripts/entitlements/mas.entitlements" > "$entitlements_file"
    fi

    # Sign the nested resource bundle first (no entitlements — it has no code),
    # then the app itself with the sandbox entitlements.
    RB_BUNDLE="$APP_DIR/Contents/Resources/Until_Until.bundle"
    if [[ -d "$RB_BUNDLE" ]]; then
      codesign --force --sign "$codesign_identity" --timestamp=none "$RB_BUNDLE" >/dev/null
    fi

    codesign_args=(
      --force
      --sign "$codesign_identity"
      --entitlements "$entitlements_file"
      --timestamp=none
    )
    codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null
    echo "Signed with: $codesign_identity"
  else
    echo "Warning: no MAS codesigning identity found; app is unsigned and cannot run as a sandboxed local test." >&2
  fi

  echo "$APP_DIR"
  exit 0
fi

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

  # Keep the resource bundle's signature uniform with the app.
  RB_BUNDLE="$APP_DIR/Contents/Resources/Until_Until.bundle"
  if [[ -d "$RB_BUNDLE" ]]; then
    codesign "${codesign_args[@]}" "$RB_BUNDLE" >/dev/null
  fi

  # Sparkle ships nested helper code (XPC services, the Autoupdate CLI, and the
  # Updater UI app) that codesign will NOT reach when sealing the outer app
  # without --deep. Sign them explicitly, inside-out, with the SAME identity +
  # options as the app, so the whole bundle is uniformly Developer ID-signed and
  # notarizable. Order matters: deepest nested code first, framework last, then
  # the app below.
  SPARKLE_FW="$APP_DIR/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$SPARKLE_FW" ]]; then
    V="$SPARKLE_FW/Versions/B"
    for nested in \
      "$V/XPCServices/Downloader.xpc" \
      "$V/XPCServices/Installer.xpc" \
      "$V/Autoupdate" \
      "$V/Updater.app"; do
      [[ -e "$nested" ]] && codesign "${codesign_args[@]}" "$nested" >/dev/null
    done
    codesign "${codesign_args[@]}" "$SPARKLE_FW" >/dev/null
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
