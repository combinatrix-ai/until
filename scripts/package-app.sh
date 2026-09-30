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

# The App Group's prefix must match the team that signs both bundles. Resolve
# the identity before writing either Info.plist or the signing entitlements.
DISTRIBUTION="${DISTRIBUTION:-0}"
codesign_identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$codesign_identity" ]]; then
  if [[ "$MAS" == "1" ]]; then
    identity_patterns=('Apple Distribution' '3rd Party Mac Developer Application' 'Apple Development')
  elif [[ "$DISTRIBUTION" == "1" ]]; then
    identity_patterns=('Developer ID Application')
  else
    identity_patterns=('Apple Development')
  fi
  for identity_pattern in "${identity_patterns[@]}"; do
    codesign_identity="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n "s/.*\"\\(${identity_pattern}:[^\"]*\\)\".*/\\1/p" \
        | head -n 1
    )"
    [[ -n "$codesign_identity" ]] && break
  done
fi

signing_team=""
if [[ -n "$codesign_identity" ]]; then
  # The suffix in an Apple Development certificate's common name identifies
  # the developer account. Its OU field is the actual signing team.
  certificate_subject="$(
    security find-certificate -c "$codesign_identity" -p 2>/dev/null \
      | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null || true
  )"
  signing_team="$(sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p' <<< "$certificate_subject")"
fi
if [[ -n "${TEAM_ID:-}" && ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Error: TEAM_ID must be a 10-character Apple Developer Team ID." >&2
  exit 1
fi
if [[ -n "$signing_team" && -n "${TEAM_ID:-}" && "$signing_team" != "$TEAM_ID" ]]; then
  echo "Error: TEAM_ID does not match the selected signing identity." >&2
  exit 1
fi
signing_team="${TEAM_ID:-$signing_team}"
if [[ -n "$codesign_identity" && -z "$signing_team" ]]; then
  echo "Error: cannot determine signing team; set TEAM_ID or use a full signing identity." >&2
  exit 1
fi
WIDGET_GROUP_ID="${signing_team:+$signing_team.ai.combinatrix.until}"
entitlements_dir="$(mktemp -d -t until-entitlements)"
trap 'rm -rf "$entitlements_dir"' EXIT
for kind in app widget mas; do
  sed "s|__WIDGET_GROUP__|$WIDGET_GROUP_ID|g" \
    "$ROOT/scripts/entitlements/$kind.entitlements" > "$entitlements_dir/$kind.entitlements"
done

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
  RB_PLIST="$APP_DIR/Contents/Resources/Until_Until.bundle/Contents/Info.plist"
  if [[ ! -f "$RB_PLIST" ]]; then
    RB_PLIST="$APP_DIR/Contents/Resources/Until_Until.bundle/Info.plist"
  fi
  if [[ ! -f "$RB_PLIST" ]]; then
    echo "Error: Info.plist not found in $RESOURCE_BUNDLE." >&2
    exit 1
  fi
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
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>ai.combinatrix.until.agenda</string>
      <key>CFBundleURLSchemes</key><array><string>until</string></array>
    </dict>
  </array>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ja</string>
  </array>
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
  <key>NSCalendarsUsageDescription</key>
  <string>Until shows your upcoming events from the Calendar app in the menu bar. Nothing leaves your Mac.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Until shows your upcoming events from the Calendar app in the menu bar. Nothing leaves your Mac.</string>
  <key>UntilWidgetGroupIdentifier</key>
  <string>${WIDGET_GROUP_ID}</string>
  <key>GoogleOAuthClientID</key>
  <string>${GOOGLE_OAUTH_CLIENT_ID}</string>
  <key>GoogleOAuthClientSecret</key>
  <string>${GOOGLE_OAUTH_CLIENT_SECRET}</string>
${SPARKLE_PLIST_KEYS}
</dict>
</plist>
PLIST

# Localized Info.plist strings (the Calendar access prompt).
mkdir -p "$APP_DIR/Contents/Resources/en.lproj" "$APP_DIR/Contents/Resources/ja.lproj"
cat > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
"NSCalendarsUsageDescription" = "Until shows your upcoming events from the Calendar app in the menu bar. Nothing leaves your Mac.";
"NSCalendarsFullAccessUsageDescription" = "Until shows your upcoming events from the Calendar app in the menu bar. Nothing leaves your Mac.";
STRINGS
cat > "$APP_DIR/Contents/Resources/ja.lproj/InfoPlist.strings" <<'STRINGS'
"NSCalendarsUsageDescription" = "カレンダーAppの予定をメニューバーに表示するために使います。予定がこのMacの外に送られることはありません。";
"NSCalendarsFullAccessUsageDescription" = "カレンダーAppの予定をメニューバーに表示するために使います。予定がこのMacの外に送られることはありません。";
STRINGS

# App icon. Generated once from scripts/make-icon.swift, then reused so dev
# rebuilds stay fast; delete scripts/Until.icns to regenerate after a redesign.
ICON_SRC="$ROOT/scripts/Until.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  swift "$ROOT/scripts/make-icon.swift" >/dev/null
fi
cp "$ICON_SRC" "$APP_DIR/Contents/Resources/Until.icns"

# WidgetKit runs in its own process. Build a small extension executable using
# the same pure snapshot model as the app, then embed it at the standard macOS
# app-extension location. The extension never receives OAuth credentials.
WIDGET_DIR="$APP_DIR/Contents/PlugIns/UntilWidget.appex"
mkdir -p "$WIDGET_DIR/Contents/MacOS" "$WIDGET_DIR/Contents/Resources"
widget_compile_args=(
  -parse-as-library
  -application-extension
  # ExtensionKit must bootstrap through Foundation's extension entry point.
  # A plain swiftc executable starts at Swift's _main instead and crashes
  # when WidgetKit asks ExtensionFoundation to initialize the widget.
  -Xlinker -e -Xlinker _NSExtensionMain
  -swift-version 5
  -target "$(uname -m)-apple-macos14.0"
  -module-cache-path "$ROOT/.build/widget-module-cache"
  -framework SwiftUI
  -framework WidgetKit
)
if [[ "$CONFIGURATION" == "release" ]]; then
  widget_compile_args+=(-O)
fi
xcrun swiftc "${widget_compile_args[@]}" \
  "$ROOT/Sources/Until/WidgetAgendaSnapshot.swift" \
  "$ROOT/Sources/UntilWidget/UntilWidget.swift" \
  -o "$WIDGET_DIR/Contents/MacOS/UntilWidget"
cp "$ROOT/Sources/UntilWidget/Info.plist" "$WIDGET_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$WIDGET_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$WIDGET_DIR/Contents/Info.plist"
plutil -insert UntilWidgetGroupIdentifier -string "$WIDGET_GROUP_ID" "$WIDGET_DIR/Contents/Info.plist"
cp -R "$ROOT/Sources/UntilWidget/Resources/." "$WIDGET_DIR/Contents/Resources/"

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

# Strip extended attributes (notably com.apple.quarantine, which rides along
# on browser-downloaded files like the provisioning profile). App Store
# processing rejects packages containing quarantined files (error 91109).
xattr -cr "$APP_DIR"

# Signing.
# - Dev (default): an Apple Development identity, no secure timestamp, so
#   rebuilds stay fast/offline and the Keychain doesn't re-prompt every launch.
# - Distribution (DISTRIBUTION=1): a Developer ID Application identity with the
#   hardened runtime and a secure timestamp — both prerequisites for
#   notarization. Driven by scripts/release.sh.
if [[ "$MAS" == "1" ]]; then
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
    entitlements_file="$entitlements_dir/mas.entitlements"
    if [[ -n "${TEAM_ID:-}" && -n "${MAS_PROVISIONING_PROFILE:-}" ]]; then
      entitlements_file="$entitlements_dir/mas-profile.entitlements"
      sed "s|</dict>|  <key>com.apple.application-identifier</key>\\
  <string>${TEAM_ID}.ai.combinatrix.until</string>\\
  <key>com.apple.developer.team-identifier</key>\\
  <string>${TEAM_ID}</string>\\
</dict>|" "$entitlements_dir/mas.entitlements" > "$entitlements_file"
    fi

    # Sign the nested resource bundle first (no entitlements — it has no code),
    # then the app itself with the sandbox entitlements.
    RB_BUNDLE="$APP_DIR/Contents/Resources/Until_Until.bundle"
    if [[ -d "$RB_BUNDLE" ]]; then
      codesign --force --sign "$codesign_identity" --timestamp=none "$RB_BUNDLE" >/dev/null
    fi
    codesign --force --sign "$codesign_identity" --timestamp=none \
      --entitlements "$entitlements_dir/widget.entitlements" "$WIDGET_DIR" >/dev/null

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
  codesign "${codesign_args[@]}" \
    --entitlements "$entitlements_dir/widget.entitlements" "$WIDGET_DIR" >/dev/null

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

  codesign "${codesign_args[@]}" \
    --entitlements "$entitlements_dir/app.entitlements" "$APP_DIR" >/dev/null
  echo "Signed with: $codesign_identity"
elif [[ "$DISTRIBUTION" == "1" ]]; then
  echo "Error: no Developer ID Application signing identity found; cannot build a distributable app." >&2
  exit 1
else
  echo "Warning: no Apple Development signing identity found; Keychain may ask again after rebuilds." >&2
fi

echo "$APP_DIR"
