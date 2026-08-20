#!/usr/bin/env bash
# install-shadowusb.sh — ShadowUSB (redirection USB), OPTIONNEL.
#
# Distribution amont : un .deb sur un bucket GCS public, en HTTP (pas de
# HTTPS, pas de checksum publié). Aucun module noyau : simple démon usbredir
# en espace utilisateur. Pièges connus, traités ici :
#   - marqueurs __SHADOWUSB_EXEC_PATH / __SHADOWUSB_GROUP /
#     __SHADOWUSB_SERVICENAME à substituer (normalement par le postinst deb) ;
#   - le groupe attendu est shadow-users (PAS shadow-input) ;
#   - etc/rsyslog.d/ et le .pkla (polkit <= 0.105) sont inopérants sur
#     Fedora → écartés.
#
# SÉCURITÉ : téléchargement HTTP sans checksum amont. Utilisez --sha256 pour
# épingler un condensat connu ; sans lui le script exige --insecure-ok.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DEB_URL="http://repository.shadow.tech/prod/pool/main/s/shadowusb/shadowusb-amd64.deb"
INSTALL_DIR="/opt/shadowusb"
SERVICE_NAME="shadowusb.service"
PIN_SHA256=""
INSECURE_OK=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --sha256 HEX    condensat sha256 attendu du .deb (recommandé)
  --insecure-ok   accepte le téléchargement HTTP sans checksum (déconseillé)
  --dry-run       affiche les commandes sans les exécuter
  --help          cette aide
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --sha256)      shift; PIN_SHA256="$1" ;;
    --insecure-ok) INSECURE_OK=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --help|-h)     usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done

require_root
require_cmd curl bsdtar sha256sum sed

if [ -z "$PIN_SHA256" ] && [ "$INSECURE_OK" -eq 0 ]; then
  die "téléchargement HTTP sans checksum : fournissez --sha256 <hex>, ou assumez avec --insecure-ok"
fi

TARGET_USER="$(detect_target_user)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
log "téléchargement de shadowusb-amd64.deb…"
run curl -fL --retry 3 -o "$WORK/shadowusb.deb" "$DEB_URL"

if [ "$DRY_RUN" -eq 0 ] && [ -n "$PIN_SHA256" ]; then
  ACTUAL="$(sha256sum "$WORK/shadowusb.deb" | awk '{print $1}')"
  [ "$ACTUAL" = "$PIN_SHA256" ] || die "sha256 invalide (attendu $PIN_SHA256, obtenu $ACTUAL)"
  log "sha256 vérifié ✔"
fi

# Un .deb est une archive ar contenant data.tar.* ; bsdtar sait ouvrir les
# deux d'un coup.
run mkdir -p "$WORK/root"
if [ "$DRY_RUN" -eq 0 ]; then
  bsdtar -xOf "$WORK/shadowusb.deb" 'data.tar*' | bsdtar -xf - -C "$WORK/root"
fi

if [ "$DRY_RUN" -eq 0 ]; then
  # Binaire du démon : premier exécutable trouvé hors etc/.
  DAEMON_SRC="$(find "$WORK/root" -type f -perm -u+x \
                 ! -path '*/etc/*' ! -name '*.so*' | head -1)"
  [ -n "$DAEMON_SRC" ] || die "démon shadowusb introuvable dans le .deb — structure changée ?"
  install -D -m 0755 "$DAEMON_SRC" "$INSTALL_DIR/shadowusb"

  # Unité systemd : celle du .deb si présente (avec substitution des
  # marqueurs), sinon une unité minimale.
  UNIT_SRC="$(find "$WORK/root" -name '*.service' | head -1 || true)"
  if [ -n "$UNIT_SRC" ]; then
    sed -e "s|__SHADOWUSB_EXEC_PATH__*|$INSTALL_DIR/shadowusb|g" \
        -e "s|__SHADOWUSB_GROUP__*|shadow-users|g" \
        -e "s|__SHADOWUSB_SERVICENAME__*|$SERVICE_NAME|g" \
        "$UNIT_SRC" > "/etc/systemd/system/$SERVICE_NAME"
  else
    cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Shadow USB (redirection usbredir)
After=network-online.target

[Service]
ExecStart=$INSTALL_DIR/shadowusb
Restart=on-failure
SupplementaryGroups=shadow-users

[Install]
WantedBy=multi-user.target
EOF
  fi
  # Volontairement ignorés : etc/rsyslog.d/* (journald suffit) et *.pkla
  # (format polkit <= 0.105, inopérant sur Fedora).
fi

run groupadd -f shadow-users
run usermod -aG shadow-users "$TARGET_USER"
run systemctl daemon-reload
run systemctl enable --now "$SERVICE_NAME"
log "ShadowUSB installé (service $SERVICE_NAME). Déconnexion/reconnexion nécessaire (groupe shadow-users)."
