#!/usr/bin/env bash
# validate-packages.sh — vérifie chaque nom de paquet du kickstart contre
# l'index officiel Fedora (mdapi.fedoraproject.org).
#
# Pourquoi c'est un livrable et pas un confort : dnf est atomique — UN SEUL
# nom invalide dans le %packages fait échouer toute la transaction, donc
# toute l'installation. Le piège classique est d'écrire un nom de paquet
# SOURCE à la place du nom de paquet BINAIRE. Ce script fait échouer le
# build (et la CI) avant que l'erreur n'atteigne une ISO.
#
# Utilisable partout (macOS compris) : ne dépend que de curl.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

RELEASE="${FEDORA_RELEASE:-44}"
MDAPI="https://mdapi.fedoraproject.org/f${RELEASE}/pkg"
KS_FILE="$SCRIPT_DIR/../iso/includes/30-packages.ks"

usage() {
  cat <<EOF
Usage : $0 [fichier.ks] [--dry-run|--help]
Vérifie les paquets listés (lignes nues du bloc %packages) contre mdapi
pour Fedora ${RELEASE}. Code retour != 0 si au moins un nom est inconnu.
EOF
}
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    *) KS_FILE="$arg" ;;
  esac
done

require_cmd curl
[ -f "$KS_FILE" ] || die "fichier introuvable : $KS_FILE"

# Deux formats acceptés : un kickstart (on extrait les lignes nues du bloc
# %packages — ni %directives, ni @groupes, ni exclusions) ou une liste plate
# (un paquet par ligne, commentaires #), comme packaging/quickshell/build-deps.txt.
# (pas de mapfile : le script doit aussi tourner sous le bash 3.2 de macOS)
PKGS=()
if grep -q '^%packages' "$KS_FILE"; then
  while IFS= read -r p; do PKGS+=("$p"); done \
    < <(sed -n '/^%packages/,/^%end/p' "$KS_FILE" | grep -vE '^(%|@|#|-|$)' | awk '{print $1}')
else
  while IFS= read -r p; do PKGS+=("$p"); done \
    < <(grep -vE '^(#|$)' "$KS_FILE" | awk '{print $1}')
fi
[ "${#PKGS[@]}" -gt 0 ] || die "aucun paquet trouvé dans $KS_FILE"

log "validation de ${#PKGS[@]} paquets contre mdapi (f${RELEASE})…"
FAILED=()
for pkg in "${PKGS[@]}"; do
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] curl %s/%s\n' "$MDAPI" "$pkg"
    continue
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$MDAPI/$pkg")"
  case "$code" in
    200) printf '  ok      %s\n' "$pkg" ;;
    # mdapi répond 400 (et non 404) pour un nom inconnu — vérifié :
    # /f44/pkg/definitely-not-a-package-xyz → 400, /f44/pkg/bat → 200.
    400|404) printf '  ABSENT  %s\n' "$pkg"; FAILED+=("$pkg") ;;
    *)   die "mdapi a répondu $code pour $pkg — réseau ou service en panne, validation impossible" ;;
  esac
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  die "paquets inconnus de Fedora ${RELEASE} : ${FAILED[*]}"
fi
log "tous les paquets existent dans Fedora ${RELEASE} ✔"
