#!/bin/bash
# Holt den neuesten Stand von GitHub, testet und baut lumo und installiert es in den Programme-Ordner.
# Aufruf: scripts/install.sh [--ohne-tests] [Branch]
#   ohne Branch: der Branch, auf dem der Ordner gerade steht
# Später reicht der Knopf „Nach Updates suchen“ in der App.
set -euo pipefail
cd "$(dirname "$0")/.."

RUN_TESTS=1
BRANCH=""
for arg in "$@"; do
  case "$arg" in
    --ohne-tests) RUN_TESTS=0 ;;
    *) BRANCH="$arg" ;;
  esac
done

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Abbruch: Im Ordner gibt es lokale Änderungen. Bitte erst committen oder verwerfen." >&2
  exit 1
fi

echo "== Neuesten Stand holen"
git fetch --prune origin
if [ -n "$BRANCH" ]; then
  git switch "$BRANCH"
fi
git merge --ff-only "@{u}"

if [ "$RUN_TESTS" = 1 ]; then
  echo "== Tests"
  # swift test meldet gelegentlich „plugin for module TestingMacros not found“; dann einmal wiederholen.
  swift test || swift test
fi

echo "== App bauen"
scripts/build-app.sh

TARGET="/Applications/lumo.app"
if [ ! -w /Applications ]; then
  TARGET="$HOME/Applications/lumo.app"
fi
echo "== Installieren nach $TARGET"
scripts/install-app.sh "$(pgrep -x lumo | head -n 1 || true)" build/lumo.app "$TARGET"
