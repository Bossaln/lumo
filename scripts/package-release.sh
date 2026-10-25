#!/bin/bash
# Baut die fertige Version für GitHub Releases und Homebrew: build/lumo-<Version>.zip samt Prüfsumme.
# Aufruf: scripts/package-release.sh 0.2.0
# Läuft im Release-Workflow (.github/workflows/release.yml), geht aber auch auf dem eigenen Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Version angeben, z. B. scripts/package-release.sh 0.2.0}"
VERSION="${VERSION#v}"

LUMO_RELEASE=1 LUMO_VERSION="$VERSION" scripts/build-app.sh

ZIP="build/lumo-$VERSION.zip"
rm -f "$ZIP"
# ditto erhält Signatur und Rechte im Bundle.
ditto -c -k --sequesterRsrc --keepParent build/lumo.app "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
echo "$SHA256" > "$ZIP.sha256"

echo "Archiv:  $ZIP"
echo "SHA-256: $SHA256"
