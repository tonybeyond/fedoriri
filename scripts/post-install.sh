#!/usr/bin/env bash
# shellcheck disable=SC2034  # DRY_RUN est consommé par run() de lib/common.sh
# post-install.sh — orchestrateur de la post-installation fedoriri.
#
# Idempotent : chaque étape vérifie son propre état avant d'agir ; rejouer le
# script entier ne casse rien (test d'acceptation n°11). Utilisable :
#   - automatiquement, via first-boot.sh au premier démarrage ;
#   - à la main, pour réparer ou mettre à jour : sudo ./post-install.sh

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SKIP_CITRIX=0
SKIP_SHADOW=0
WITH_SHADOWUSB=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --skip-citrix     ne pas installer Citrix Workspace app
  --skip-shadow     ne pas installer le client Shadow
  --with-shadowusb  installer aussi ShadowUSB (optionnel, cf. install-shadowusb.sh)
  --dry-run         affiche les commandes sans les exécuter
  --help            cette aide
Variables : FEDORIRI_USER=<login> pour cibler un autre utilisateur que fedo.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-citrix)    SKIP_CITRIX=1 ;;
    --skip-shadow)    SKIP_SHADOW=1 ;;
    --with-shadowusb) WITH_SHADOWUSB=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    --help|-h)        usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done
finalize_flags

require_root
require_cmd dnf curl

TARGET_USER="$(detect_target_user)"
[ -n "$TARGET_USER" ] || die "impossible de déterminer l'utilisateur cible (FEDORIRI_USER=?)"
log "utilisateur cible : $TARGET_USER"

step() { log "--- $* ---"; }

# ---------------------------------------------------------------------------
step "RPM Fusion + décodage vidéo matériel (VA-API H264/HEVC)"
# Fedora a retiré H264/HEVC de mesa-va-drivers : sans le paquet -freeworld de
# RPM Fusion, vainfo ne liste aucun profil H264 sur GPU AMD et le streaming
# Shadow retombe en décodage logiciel (test d'acceptation n°10).
if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  # shellcheck disable=SC2046
  run dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
else
  log "rpmfusion-free-release déjà présent"
fi
if ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
  # mesa-va-drivers n'existe plus dans Fedora 44 (vérifié via mdapi) : selon
  # l'état du système c'est un install direct ou un swap.
  if rpm -q mesa-va-drivers >/dev/null 2>&1; then
    run dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
  else
    run dnf install -y mesa-va-drivers-freeworld
  fi
else
  log "mesa-va-drivers-freeworld déjà présent"
fi

# ---------------------------------------------------------------------------
step "starship (absent de Fedora → binaire GitHub vérifié)"
"$SCRIPT_DIR/../packaging/starship/install-starship.sh" "${DRY_FLAG[@]}"

# ---------------------------------------------------------------------------
step "fonds d'écran des thèmes Omarchy (non embarqués dans le dépôt)"
"$SCRIPT_DIR/sync-omarchy-assets.sh" "${DRY_FLAG[@]}"

# ---------------------------------------------------------------------------
if [ "$SKIP_CITRIX" -eq 0 ]; then
  step "Citrix Workspace app (ligne GCC 11)"
  "$SCRIPT_DIR/install-citrix.sh" "${DRY_FLAG[@]}"
else
  log "Citrix sauté (--skip-citrix)"
fi

# ---------------------------------------------------------------------------
if [ "$SKIP_SHADOW" -eq 0 ]; then
  step "Client Shadow.tech (AppImage + uinput)"
  FEDORIRI_USER="$TARGET_USER" "$SCRIPT_DIR/install-shadow.sh" "${DRY_FLAG[@]}"
else
  log "Shadow sauté (--skip-shadow)"
fi

if [ "$WITH_SHADOWUSB" -eq 1 ]; then
  step "ShadowUSB (optionnel)"
  FEDORIRI_USER="$TARGET_USER" "$SCRIPT_DIR/install-shadowusb.sh" "${DRY_FLAG[@]}"
fi

# ---------------------------------------------------------------------------
step "thème par défaut pour $TARGET_USER"
# Applique tokyo-night si l'utilisateur n'a pas encore de thème courant.
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -n "$USER_HOME" ] && [ ! -e "$USER_HOME/.config/fedoriri/current-theme" ]; then
  run runuser -u "$TARGET_USER" -- /usr/local/bin/fedoriri-theme-set --no-reload tokyo-night
else
  log "thème déjà configuré, rien à faire"
fi

log "post-installation terminée."
