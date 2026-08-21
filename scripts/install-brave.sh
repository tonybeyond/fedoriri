#!/usr/bin/env bash
# install-brave.sh — Brave Origin (navigateur par défaut de fedoriri).
#
# Brave n'est pas empaqueté par Fedora : on utilise le dépôt RPM officiel de
# Brave Software (signé, mis à jour par dnf ensuite). Le dépôt publie deux
# paquets ; fedoriri installe « brave-origin », l'édition sans les
# fonctionnalités Brave Rewards/Wallet/IA, gratuite sur Linux
# (https://brave.com/origin/linux/). Binaire : /usr/bin/brave-origin-stable,
# lanceur : com.brave.Origin.desktop, app-id Wayland : brave-origin.
# Vérifié sur Fedora 44 le 2026-08-21 (brave-origin 1.93.137).
#
# Idempotent : ne refait rien si le paquet est déjà installé (dnf fait la
# mise à jour). --dry-run affiche les commandes.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

BRAVE_REPO_URL="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
BRAVE_KEY_URL="https://brave-browser-rpm-release.s3.brave.com/brave-core.asc"
BRAVE_PKG="brave-origin"
BRAVE_DESKTOP="com.brave.Origin.desktop"
TARGET_USER="${FEDORIRI_USER:-fedo}"

usage() {
  cat <<EOF
Usage : $0 [options]
  --dry-run  affiche les commandes sans les exécuter
  --help     cette aide
Variable : FEDORIRI_USER (défaut $TARGET_USER) — utilisateur dont Brave devient
           le navigateur par défaut (xdg-settings).
EOF
}
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $arg (voir --help)" ;;
  esac
done

require_root
require_cmd dnf curl rpm

# --- Dépôt officiel + clef -----------------------------------------------
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
  log "ajout du dépôt RPM officiel Brave…"
  # dnf5 : « config-manager addrepo » ; on importe la clef explicitement pour
  # que la première installation soit vérifiée (gpgcheck=1 dans le .repo).
  run dnf install -y -q dnf-plugins-core
  run dnf config-manager addrepo --from-repofile="$BRAVE_REPO_URL"
else
  log "dépôt Brave déjà présent"
fi
run rpm --import "$BRAVE_KEY_URL"

# --- Paquet ----------------------------------------------------------------
if rpm -q "$BRAVE_PKG" >/dev/null 2>&1; then
  log "$BRAVE_PKG déjà installé ($(rpm -q --qf '%{VERSION}' "$BRAVE_PKG")) — rien à faire"
else
  log "installation de $BRAVE_PKG…"
  run dnf install -y "$BRAVE_PKG"
fi
[ "$DRY_RUN" -eq 1 ] || [ -x /usr/bin/brave-origin-stable ] \
  || die "installation incomplète : /usr/bin/brave-origin-stable absent"

# --- Navigateur par défaut de l'utilisateur cible ---------------------------
# xdg-settings écrit ~/.config/mimeapps.list (x-scheme-handler/http[s],
# text/html). Exécuté en tant que l'utilisateur, jamais en root.
if id "$TARGET_USER" >/dev/null 2>&1; then
  log "Brave Origin navigateur par défaut pour $TARGET_USER…"
  run runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
      xdg-settings set default-web-browser "$BRAVE_DESKTOP"
else
  warn "utilisateur $TARGET_USER introuvable : navigateur par défaut non configuré"
fi
log "Brave Origin prêt (Mod+B dans niri)."
