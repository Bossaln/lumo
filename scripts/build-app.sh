#!/bin/bash
# Baut build/notchai.app aus dem Release-Build.
#
# Umgebung:
#   NOTCHAI_RELEASE=1        fertige Version (GitHub/Homebrew): ohne Quellordner, Updates kommen dann über GitHub
#   NOTCHAI_VERSION=0.2.0    Versionsnummer (sonst die aus Resources/Info.plist)
#   NOTCHAI_SIGN_IDENTITY    Zertifikat zum Signieren; ohne Angabe „notchai Signing“, falls im Schlüsselbund,
#                            sonst ad hoc (siehe scripts/create-signing-certificate.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/notchai.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/notchai" "$APP/Contents/MacOS/notchai"
# Das Hook-Programm reist im Bundle mit; die App kopiert es beim Start an seinen festen Ort.
cp "$BIN_DIR/notchai-hook" "$APP/Contents/MacOS/notchai-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Herkunft für den Update-Knopf: Commit, Branch, Build-Nummer und (nur bei eigenen Builds) der Quellordner.
PLIST="$APP/Contents/Info.plist"
if [ -n "${NOTCHAI_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$NOTCHAI_VERSION" "$PLIST"
fi
plutil -insert NotchaiGitCommit -string "$(git rev-parse --short HEAD 2>/dev/null || echo unbekannt)" "$PLIST"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 1)" "$PLIST"
if [ "${NOTCHAI_RELEASE:-0}" != 1 ]; then
  plutil -insert NotchaiSourceDirectory -string "$(pwd -P)" "$PLIST"
  plutil -insert NotchaiGitBranch -string "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unbekannt)" "$PLIST"
fi

# Mit festem Zertifikat bleiben Freigaben wie „Bedienungshilfen“ über Updates erhalten; ad hoc nicht.
IDENTITY="${NOTCHAI_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"notchai Signing"'; then
  IDENTITY="notchai Signing"
fi
IDENTITY="${IDENTITY:--}"
sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$@"; }
# Eingebettete Programme vor dem Bundle signieren.
sign "$APP/Contents/MacOS/notchai-hook"
sign "$APP"
if [ "$IDENTITY" = "-" ]; then
  echo "Signiert: ad hoc"
else
  echo "Signiert: $IDENTITY"
fi
echo "Fertig: $APP"
