#!/usr/bin/env bash
# install-starship.sh — starship est absent de Fedora 44 : on installe le
# binaire officiel GitHub, version résolue via l'API (jamais d'URL figée),
# sha256 vérifié via le fichier .sha256 publié avec chaque release.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "$SCRIPT_DIR/../../scripts/lib/common.sh"

ASSET="starship-x86_64-unknown-linux-gnu.tar.gz"
API="https://api.github.com/repos/starship/starship/releases/latest"
DEST="/usr/local/bin/starship"

usage() { echo "Usage : $0 [--force|--dry-run|--help]"; }
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $arg" ;;
  esac
done

require_root
require_cmd curl tar sha256sum

log "résolution de la dernière release starship…"
RELEASE_JSON="$(curl -fsSL "$API")" || die "API GitHub inaccessible"
TAG="$(grep -m1 '"tag_name"' <<<"$RELEASE_JSON" | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
[ -n "$TAG" ] || die "tag_name introuvable dans la réponse de l'API"
VERSION="${TAG#v}"
log "dernière version : $VERSION"

if [ "$FORCE" -eq 0 ] && command -v starship >/dev/null 2>&1 \
   && starship --version 2>/dev/null | grep -q "starship $VERSION"; then
  log "starship $VERSION déjà installé — rien à faire"
  exit 0
fi

BASE="https://github.com/starship/starship/releases/download/$TAG"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
run curl -fL --retry 3 -o "$WORK/$ASSET" "$BASE/$ASSET"
run curl -fL --retry 3 -o "$WORK/$ASSET.sha256" "$BASE/$ASSET.sha256"
if [ "$DRY_RUN" -eq 0 ]; then
  # Le .sha256 amont ne contient que le condensat (pas le nom de fichier).
  ACTUAL="$(sha256sum "$WORK/$ASSET" | awk '{print $1}')"
  EXPECTED="$(tr -d '[:space:]' < "$WORK/$ASSET.sha256" | awk -F'[^a-f0-9]' '{print $1}')"
  [ "$ACTUAL" = "$EXPECTED" ] || die "sha256 invalide (attendu $EXPECTED, obtenu $ACTUAL)"
  log "sha256 vérifié ✔"
  tar -xzf "$WORK/$ASSET" -C "$WORK"
  install -m 0755 "$WORK/starship" "$DEST"
fi
log "starship $VERSION installé dans $DEST"
