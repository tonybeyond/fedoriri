#!/usr/bin/env bash
# shellcheck disable=SC2034  # DRY_RUN est consommé par run() de lib/common.sh
# qt-guard.sh — recompile Quickshell si qt6-qtbase a changé depuis la
# dernière compilation (voir fedoriri-quickshell-qt-guard.service).
# La source est en cache local : la recompilation marche sans réseau.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "$SCRIPT_DIR/../../scripts/lib/common.sh"

STAMP="$FEDORIRI_STATE_DIR/quickshell.qt-version"
VERSION_FILE="$FEDORIRI_STATE_DIR/quickshell.version"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) echo "Usage : $0 [--dry-run] — lancé par fedoriri-quickshell-qt-guard.service"; exit 0 ;;
    *) die "option inconnue : $arg" ;;
  esac
done

[ -f "$STAMP" ] || exit 0   # Quickshell jamais compilé : rien à garder.
CURRENT="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' qt6-qtbase)"
BUILT_AGAINST="$(cat "$STAMP")"

if [ "$CURRENT" = "$BUILT_AGAINST" ]; then
  exit 0
fi

log "qt6-qtbase a changé ($BUILT_AGAINST → $CURRENT) : recompilation de Quickshell (ABI privée Qt)…"
TAG="v$(cat "$VERSION_FILE" 2>/dev/null || true)"
if [ "$TAG" = "v" ]; then
  run "$SCRIPT_DIR/build-quickshell.sh"
else
  run "$SCRIPT_DIR/build-quickshell.sh" --tag "$TAG"
fi
