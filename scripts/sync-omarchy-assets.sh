#!/usr/bin/env bash
# sync-omarchy-assets.sh — récupère les fonds d'écran des thèmes Omarchy.
#
# Les colors.toml des 22 thèmes sont vendorés dans ce dépôt (quelques Ko),
# mais pas les ~120 Mo d'images : on les clone depuis le tag v4.0.0 (épinglé,
# donc reproductible) au premier boot. Idempotent : ne refait rien si les
# fonds sont déjà en place.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

OMARCHY_REPO="https://github.com/basecamp/omarchy.git"
OMARCHY_TAG="v4.0.0"
DEST="$FEDORIRI_SHARE_DIR/backgrounds"

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
require_cmd git

if [ "$FORCE" -eq 0 ] && [ -d "$DEST" ] && [ -n "$(find "$DEST" -name '*.png' -o -name '*.jpg' 2>/dev/null | head -1)" ]; then
  log "fonds d'écran déjà présents dans $DEST — rien à faire (--force pour resynchroniser)"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
log "clone d'omarchy $OMARCHY_TAG (shallow)…"
run git clone --quiet --depth 1 --branch "$OMARCHY_TAG" "$OMARCHY_REPO" "$WORK/omarchy"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$DEST"
  for theme_dir in "$WORK/omarchy/themes"/*/; do
    theme="$(basename "$theme_dir")"
    [ -d "$theme_dir/backgrounds" ] || continue
    mkdir -p "$DEST/$theme"
    cp -a "$theme_dir/backgrounds/." "$DEST/$theme/"
  done
  log "fonds installés : $(find "$DEST" -type f | wc -l | tr -d ' ') fichiers dans $DEST"
fi
