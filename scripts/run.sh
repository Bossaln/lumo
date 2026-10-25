#!/bin/bash
# Beendet eine laufende Instanz, baut die App und startet sie.
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -x lumo || true
scripts/build-app.sh
open build/lumo.app
