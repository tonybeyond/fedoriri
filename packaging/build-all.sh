#!/usr/bin/env bash
# shellcheck disable=SC2034  # DRY_RUN est consommé par run() de lib/common.sh
# build-all.sh — packaging hors-Fedora : starship (toujours) et, sur demande,
# Quickshell (option A, non requise pour l'ISO — voir README racine).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$SCRIPT_DIR/../scripts/lib/common.sh"

WITH_QUICKSHELL=0
usage() {
  cat <<EOF
Usage : $0 [--with-quickshell] [--dry-run|--help]
  --with-quickshell  compile Quickshell >= 0.3.0 et arme le garde-fou ABI Qt
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --with-quickshell) WITH_QUICKSHELL=1 ;;
    --dry-run)         DRY_RUN=1 ;;
    --help|-h)         usage; exit 0 ;;
    *) die "option inconnue : $1" ;;
  esac
  shift
done
finalize_flags

"$SCRIPT_DIR/starship/install-starship.sh" "${DRY_FLAG[@]}"

if [ "$WITH_QUICKSHELL" -eq 1 ]; then
  "$SCRIPT_DIR/quickshell/build-quickshell.sh" "${DRY_FLAG[@]}"
  run install -m 0644 "$SCRIPT_DIR/quickshell/fedoriri-quickshell-qt-guard.service" /etc/systemd/system/
  run install -m 0755 "$SCRIPT_DIR/quickshell/qt-guard.sh" /opt/fedoriri/packaging/quickshell/qt-guard.sh 2>/dev/null || true
  run systemctl daemon-reload
  run systemctl enable fedoriri-quickshell-qt-guard.service
fi
