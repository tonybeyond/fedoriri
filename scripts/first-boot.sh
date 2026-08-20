#!/usr/bin/env bash
# shellcheck disable=SC2034  # DRY_RUN est consommé par run() de lib/common.sh
# first-boot.sh — point d'entrée de fedoriri-first-boot.service.
#
# Rôle : attendre le réseau, dérouler post-install.sh, poser le témoin,
# puis désarmer le service. Toute la logique métier est dans post-install.sh
# (rejouable à la main, idempotent).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() { echo "Usage : $0 [--dry-run|--help] — lancé par fedoriri-first-boot.service"; }
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $arg" ;;
  esac
done
finalize_flags

require_root

log "===== fedoriri : premier démarrage — installation en cours ====="
log "Cette étape télécharge Citrix, Shadow et des paquets (plusieurs minutes)."

# Attente réseau par HTTP : l'ICMP (ping) est souvent filtré.
if ! wait_network 600; then
  # Sans réseau on n'échoue pas définitivement : le témoin n'est pas posé,
  # le service retentera au prochain démarrage.
  die "réseau indisponible après 10 min — nouvelle tentative au prochain démarrage"
fi

"$SCRIPT_DIR/post-install.sh" "${DRY_FLAG[@]}"

# Témoin posé AVANT le disable : c'est lui (ConditionPathExists=!) qui
# empêche de rejouer, le disable n'est qu'un confort.
run mkdir -p "$FEDORIRI_STATE_DIR"
run touch "$FEDORIRI_STATE_DIR/first-boot.done"
run systemctl disable fedoriri-first-boot.service

log "===== fedoriri : premier démarrage terminé — redémarrage conseillé ====="
