#!/usr/bin/env bash
set -euo pipefail

# Generate a single-item Sparkle appcast for the just-built release.
#
# Sparkle only needs the appcast to advertise the *latest* version, so a
# one-item feed pointing at this release's .zip is sufficient; older versions
# don't need entries. The feed is published as a `appcast.xml` asset on the
# GitHub release and served via the stable
#   https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml
# URL that Info.plist's SUFeedURL points at.
#
# Required env / args:
#   APP_DIR       path to the built, notarized Until.app (reads version keys)
#   ZIP_PATH      path to the .zip Sparkle will download (must match DOWNLOAD_URL)
#   DOWNLOAD_URL  public URL of that .zip on the GitHub release
#   ED_KEY_FILE   EdDSA private key file (from the SPARKLE_ED_PRIVATE_KEY secret)
#   OUT           output appcast path (default: ./appcast.xml)
#
# The EdDSA signature authenticates the download; without a matching
# SUPublicEDKey in the app, Sparkle refuses the update.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APP_DIR:?Set APP_DIR to the built Until.app}"
ZIP_PATH="${ZIP_PATH:?Set ZIP_PATH to the update .zip}"
DOWNLOAD_URL="${DOWNLOAD_URL:?Set DOWNLOAD_URL to the public URL of the .zip}"
ED_KEY_FILE="${ED_KEY_FILE:?Set ED_KEY_FILE to the EdDSA private key file}"
OUT="${OUT:-$ROOT/appcast.xml}"

PLIST="$APP_DIR/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"

SIGN_UPDATE="$(find "$ROOT/.build/artifacts" -name sign_update -type f 2>/dev/null | head -n 1)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "Error: sign_update tool not found under .build/artifacts (run 'swift build' first)." >&2
  exit 1
fi

# Emits: sparkle:edSignature="..." length="..."
ENCLOSURE_ATTRS="$("$SIGN_UPDATE" "$ZIP_PATH" --ed-key-file "$ED_KEY_FILE")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Until</title>
    <link>https://combinatrix-ai.github.io/until/</link>
    <description>Most recent updates to Until.</description>
    <language>en</language>
    <item>
      <title>Version ${SHORT_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_URL}" ${ENCLOSURE_ATTRS} type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "Wrote appcast: $OUT (v${SHORT_VERSION} build ${BUILD_VERSION})"
