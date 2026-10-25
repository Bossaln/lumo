#!/bin/bash
# Baut build/lumo.app aus dem Release-Build.
#
# Umgebung:
#   LUMO_RELEASE=1        fertige Version (GitHub/Homebrew): ohne Quellordner, Updates kommen dann über GitHub
#   LUMO_VERSION=0.2.0    Versionsnummer (sonst die aus Resources/Info.plist)
#   LUMO_SIGN_IDENTITY    Zertifikat zum Signieren; ohne Angabe „notchai Signing“, falls im Schlüsselbund,
#                            sonst ad hoc (siehe scripts/create-signing-certificate.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/lumo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/lumo" "$APP/Contents/MacOS/lumo"
# Das Hook-Programm reist im Bundle mit; die App kopiert es beim Start an seinen festen Ort.
cp "$BIN_DIR/lumo-hook" "$APP/Contents/MacOS/lumo-hook"
# Die Begrüßungsszene nach `brew install` (Cask: postflight_steps).
cp "$BIN_DIR/lumo-welcome" "$APP/Contents/MacOS/lumo-welcome"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Texte der Freigabe-Abfragen von macOS auf Deutsch und Englisch.
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Herkunft für den Update-Knopf: Commit, Branch, Build-Nummer und (nur bei eigenen Builds) der Quellordner.
PLIST="$APP/Contents/Info.plist"
if [ -n "${LUMO_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$LUMO_VERSION" "$PLIST"
fi
plutil -insert LumoGitCommit -string "$(git rev-parse --short HEAD 2>/dev/null || echo unbekannt)" "$PLIST"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 1)" "$PLIST"
if [ "${LUMO_RELEASE:-0}" != 1 ]; then
  plutil -insert LumoSourceDirectory -string "$(pwd -P)" "$PLIST"
  plutil -insert LumoGitBranch -string "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unbekannt)" "$PLIST"
fi

# Mit festem Zertifikat bleiben Freigaben wie „Bedienungshilfen“ über Updates erhalten; ad hoc nicht.
# Das Zertifikat heißt weiter „notchai Signing“ (so hieß lumo bis 0.7.0): Es ist das vorhandene im Schlüsselbund und in
# den GitHub-Secrets; ein neues würde nur die Signatur wechseln und damit alle Freigaben noch einmal zurücksetzen.
IDENTITY="${LUMO_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"notchai Signing"'; then
  IDENTITY="notchai Signing"
fi
IDENTITY="${IDENTITY:--}"
sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$@"; }
# Eingebettete Programme vor dem Bundle signieren.
sign "$APP/Contents/MacOS/lumo-hook"
sign "$APP/Contents/MacOS/lumo-welcome"
sign "$APP"
if [ "$IDENTITY" = "-" ]; then
  echo "Signiert: ad hoc"
else
  echo "Signiert: $IDENTITY"
fi
echo "Fertig: $APP"
