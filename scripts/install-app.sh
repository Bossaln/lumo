#!/bin/bash
# Ersetzt eine (laufende) notchai-App durch eine neu gebaute und startet sie.
# Aufruf: scripts/install-app.sh <PID der alten App oder ""> <neue App> <Ziel>
# Wird von scripts/install.sh und vom Update-Knopf der App benutzt.
set -euo pipefail
OLD_PID="${1:-}"
NEW_APP="$2"
TARGET="$3"

# Warten, bis die alte App sich beendet hat (höchstens 10 s), sonst beenden.
if [ -n "$OLD_PID" ]; then
  for _ in $(seq 1 50); do
    kill -0 "$OLD_PID" 2>/dev/null || break
    sleep 0.2
  done
  kill "$OLD_PID" 2>/dev/null || true
fi

resolve() { (cd "$1" 2>/dev/null && pwd -P) || true; }
if [ "$(resolve "$NEW_APP")" != "$(resolve "$TARGET")" ]; then
  mkdir -p "$(dirname "$TARGET")"
  rm -rf "$TARGET.neu"
  ditto "$NEW_APP" "$TARGET.neu"
  rm -rf "$TARGET"
  mv "$TARGET.neu" "$TARGET"
fi
open "$TARGET"
echo "notchai läuft: $TARGET"
