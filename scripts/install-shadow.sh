#!/usr/bin/env bash
# install-shadow.sh — client Shadow.tech (AppImage) + prérequis uinput.
#
# Shadow ne publie que .deb et AppImage → AppImage sur Fedora. L'AppImage ne
# configure RIEN : ce script reproduit le postinst du .deb (groupe
# shadow-input, module uinput, règle udev), corrigé — la doc officielle
# Shadow a deux défauts connus (redirection manquante vers
# /etc/modules-load.d/uinput.conf, et groupadd absent). Sans cette
# configuration : erreurs L-100/L-104, clavier et souris morts en session
# (sous Wayland, pas de XTEST : l'injection d'entrées passe par /dev/uinput).
#
# La version est résolue depuis le manifeste amont à CHAQUE exécution, et le
# téléchargement utilise l'URL VERSIONNÉE (persistante), jamais « latest » :
# c'est précisément le couple inverse qui casse le paquet AUR shadow-tech à
# chaque release.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MANIFEST_URL="https://update.shadow.tech/launcher/prod/linux/ubuntu_18.04/latest-linux.yml"
BASE_URL="https://update.shadow.tech/launcher/prod/linux/ubuntu_18.04"
INSTALL_DIR="/opt/shadow"
STATE_FILE="$FEDORIRI_STATE_DIR/shadow-version"
INPUT_MODE="libinput"
FORCE=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --input-mode libinput|legacy
      libinput (défaut) : l'utilisateur est ajouté au groupe "input" → souris
        précise en session Shadow, mais gestes 2 doigts du pavé tactile HS.
      legacy : pas de groupe "input" → l'inverse. (Poste fixe → libinput.)
  --force    réinstalle même si la version est déjà présente
  --dry-run  affiche les commandes sans les exécuter
  --help     cette aide
Variables : FEDORIRI_USER=<login> pour cibler un autre utilisateur que fedo.
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --input-mode) shift; INPUT_MODE="$1" ;;
    --force)      FORCE=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    --help|-h)    usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done
case "$INPUT_MODE" in libinput|legacy) ;; *) die "--input-mode : libinput ou legacy" ;; esac

require_root
require_cmd curl openssl awk

TARGET_USER="$(detect_target_user)"
[ -n "$TARGET_USER" ] || die "utilisateur cible introuvable (FEDORIRI_USER=?)"

# ---------------------------------------------------------------------------
# 1. Manifeste amont : version + sha512 (base64). On lit, on ne devine pas.
# ---------------------------------------------------------------------------
log "lecture du manifeste $MANIFEST_URL…"
MANIFEST="$(curl -fsSL "$MANIFEST_URL")" || die "manifeste Shadow inaccessible"
SHADOW_VERSION="$(awk '/^version:/ {print $2; exit}' <<<"$MANIFEST" | tr -d '[:space:]')"
# Le sha512 de niveau racine du yml electron-builder correspond au fichier
# `path:` (l'AppImage) ; les entrées files: sont indentées, on les exclut.
SHADOW_SHA512="$(awk '/^sha512:/ {print $2; exit}' <<<"$MANIFEST" | tr -d '[:space:]')"
APPIMAGE_NAME="$(awk '/^path:/ {print $2; exit}' <<<"$MANIFEST" | tr -d '[:space:]')"
[ -n "$SHADOW_VERSION" ] && [ -n "$SHADOW_SHA512" ] && [ -n "$APPIMAGE_NAME" ] \
  || die "manifeste illisible (version/sha512/path manquant) — structure changée ?"
log "version amont : $SHADOW_VERSION ($APPIMAGE_NAME)"

if [ "$FORCE" -eq 0 ] && [ -x "$INSTALL_DIR/ShadowPC.AppImage" ] && [ -f "$STATE_FILE" ] \
   && [ "$(cat "$STATE_FILE")" = "$SHADOW_VERSION" ]; then
  log "Shadow $SHADOW_VERSION déjà installé — configuration système vérifiée quand même"
  SKIP_DOWNLOAD=1
else
  SKIP_DOWNLOAD=0
fi

# ---------------------------------------------------------------------------
# 2. Téléchargement (URL versionnée) + vérification sha512 base64.
#    openssl et non xxd : xxd n'est pas garanti présent.
# ---------------------------------------------------------------------------
if [ "$SKIP_DOWNLOAD" -eq 0 ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  log "téléchargement de $APPIMAGE_NAME…"
  run curl -fL --retry 3 -o "$WORK/$APPIMAGE_NAME" "$BASE_URL/$APPIMAGE_NAME"
  if [ "$DRY_RUN" -eq 0 ]; then
    ACTUAL="$(openssl dgst -sha512 -binary "$WORK/$APPIMAGE_NAME" | openssl base64 -A)"
    if [ "$ACTUAL" != "$SHADOW_SHA512" ]; then
      die "sha512 invalide pour $APPIMAGE_NAME
attendu : $SHADOW_SHA512
obtenu  : $ACTUAL"
    fi
    log "sha512 vérifié ✔"
  fi
  run install -D -m 0755 "$WORK/$APPIMAGE_NAME" "$INSTALL_DIR/ShadowPC.AppImage"
fi

# ---------------------------------------------------------------------------
# 3. Reproduction (corrigée) du postinst du .deb : uinput + groupes.
# ---------------------------------------------------------------------------
log "configuration uinput/udev (mode $INPUT_MODE)…"
run groupadd -f shadow-input
if [ "$DRY_RUN" -eq 0 ]; then
  echo 'uinput' > /etc/modules-load.d/uinput.conf
  echo 'KERNEL=="uinput", MODE="0660", GROUP="shadow-input"' > /etc/udev/rules.d/65-shadow-client.rules
else
  run echo "écriture /etc/modules-load.d/uinput.conf + /etc/udev/rules.d/65-shadow-client.rules"
fi
GROUPS_TO_ADD="shadow-input"
if [ "$INPUT_MODE" = "libinput" ]; then
  GROUPS_TO_ADD="shadow-input,input"
else
  warn "mode legacy : l'utilisateur n'est PAS ajouté au groupe input ; s'il y est déjà, retirez-le (gpasswd -d $TARGET_USER input)"
fi
run usermod -aG "$GROUPS_TO_ADD" "$TARGET_USER"
# Prise d'effet immédiate pour la session courante si possible ; sinon au
# prochain login. modprobe idempotent.
run modprobe uinput || true
run udevadm control --reload || true
run udevadm trigger --name-match=uinput || true

# ---------------------------------------------------------------------------
# 4. Correctif couleurs : le .deb installe un drirc (allow_rgb10_configs=false).
#    Dans l'AppImage il est sous resources/app.asar.unpacked/release/native/.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ] && [ ! -f /usr/share/drirc.d/99-shadow-prod.conf ]; then
  EXTRACT_DIR="$(mktemp -d)"
  ( cd "$EXTRACT_DIR" \
    && "$INSTALL_DIR/ShadowPC.AppImage" --appimage-extract \
         'resources/app.asar.unpacked/release/native/shadow.conf' >/dev/null 2>&1 ) || true
  SHADOW_DRIRC="$(find "$EXTRACT_DIR/squashfs-root" -name 'shadow.conf' 2>/dev/null | head -1 || true)"
  if [ -n "$SHADOW_DRIRC" ]; then
    install -D -m 0644 "$SHADOW_DRIRC" /usr/share/drirc.d/99-shadow-prod.conf
    log "drirc Shadow installé (allow_rgb10_configs=false) ✔"
  else
    warn "shadow.conf introuvable dans l'AppImage — banding de couleurs possible en 10 bits"
  fi
  rm -rf "$EXTRACT_DIR"
fi

# ---------------------------------------------------------------------------
# 5. Lanceur .desktop (l'AppImage n'en installe pas).
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
  cat > /usr/share/applications/shadow-pc.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Shadow PC
Comment=Client de cloud gaming Shadow.tech
Exec=$INSTALL_DIR/ShadowPC.AppImage
Icon=shadow
Terminal=false
Categories=Game;Network;
StartupWMClass=Shadow
EOF
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /usr/share/applications || true
fi

# ---------------------------------------------------------------------------
# 6. Sanity VA-API : sans profils H264, le streaming retombe en logiciel.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ] && command -v vainfo >/dev/null 2>&1; then
  if ! vainfo 2>/dev/null | grep -qi 'H264'; then
    warn "vainfo ne liste aucun profil H264 : vérifiez mesa-va-drivers-freeworld (RPM Fusion) — cf. post-install.sh"
  fi
fi

run mkdir -p "$FEDORIRI_STATE_DIR"
[ "$DRY_RUN" -eq 1 ] || printf '%s\n' "$SHADOW_VERSION" > "$STATE_FILE"
log "Shadow $SHADOW_VERSION installé. Déconnexion/reconnexion nécessaire pour les nouveaux groupes."
