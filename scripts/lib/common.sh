# shellcheck shell=bash
# Bibliothèque commune des scripts fedoriri.
# À sourcer, jamais à exécuter. Tous les scripts qui la sourcent obtiennent :
#   - la gestion --help/--dry-run homogène (variables HELP/DRY_RUN)
#   - log/warn/die
#   - run() : exécute ou affiche selon --dry-run
#   - require_root, require_cmd, wait_network
#   - detect_target_user : l'utilisateur "poste" (fedo par défaut)

set -euo pipefail

FEDORIRI_STATE_DIR="${FEDORIRI_STATE_DIR:-/var/lib/fedoriri}"
FEDORIRI_SHARE_DIR="${FEDORIRI_SHARE_DIR:-/usr/share/fedoriri}"

DRY_RUN=0
# Tableau à propager aux sous-scripts ("${DRY_FLAG[@]}") ; rempli par
# finalize_flags après l'analyse des options.
# shellcheck disable=SC2034  # consommé par les scripts qui sourcent ce fichier
DRY_FLAG=()
# shellcheck disable=SC2034  # idem : DRY_FLAG est utilisé par les appelants
finalize_flags() {
  if [ "$DRY_RUN" -eq 1 ]; then DRY_FLAG=(--dry-run); fi
}

log()  { printf '\033[1;34m[fedoriri]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fedoriri][attention]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fedoriri][erreur]\033[0m %s\n' "$*" >&2; exit 1; }

# Exécute la commande, ou l'affiche seulement en mode --dry-run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\033[0;36m[dry-run]\033[0m %s\n' "$*"
  else
    "$@"
  fi
}

require_root() {
  # En dry-run on tolère un utilisateur normal : on ne fait qu'afficher.
  if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    die "ce script doit être lancé en root (ou avec --dry-run)"
  fi
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "commande requise absente : $c"
  done
}

# Attente réseau par HTTP (curl), pas par ping : l'ICMP est souvent filtré.
# $1 = délai max en secondes (défaut 300).
wait_network() {
  local timeout="${1:-300}" waited=0
  log "attente du réseau (curl, max ${timeout}s)…"
  until curl -fsS --max-time 5 -o /dev/null https://fedoraproject.org/static/hotspot.txt 2>/dev/null \
     || curl -fsS --max-time 5 -o /dev/null https://www.google.com/generate_204 2>/dev/null; do
    sleep 5
    waited=$((waited + 5))
    if [ "$waited" -ge "$timeout" ]; then
      return 1
    fi
  done
  log "réseau disponible (après ${waited}s)"
}

# Utilisateur cible des configurations : $FEDORIRI_USER, sinon fedo,
# sinon le premier utilisateur "humain" (uid >= 1000, shell valide).
detect_target_user() {
  if [ -n "${FEDORIRI_USER:-}" ]; then
    printf '%s' "$FEDORIRI_USER"
    return
  fi
  if id fedo >/dev/null 2>&1; then
    printf 'fedo'
    return
  fi
  awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /nologin|false/ { print $1; exit }' /etc/passwd
}

# Analyse les options communes ; les scripts appellent :
#   parse_common_args "usage…" "$@" ; eval set -- "$COMMON_REMAINING_ARGS"
# (implémentation simple : les scripts gèrent eux-mêmes leurs options
#  spécifiques et appellent common_flag "$arg" dans leur boucle).
common_flag() {
  case "$1" in
    --dry-run) DRY_RUN=1; return 0 ;;
    --help|-h) return 2 ;;
  esac
  return 1
}
