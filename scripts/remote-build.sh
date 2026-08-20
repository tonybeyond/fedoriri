#!/usr/bin/env bash
# remote-build.sh — orchestre le build de l'ISO sur le LXC de build, puis
# l'envoie sur le serveur Proxmox. À lancer depuis n'importe quel poste ayant
# un accès SSH au LXC (clef dédiée), typiquement le Mac de dev.
#
# Flux : [poste] --ssh--> [LXC : git pull + build-iso.sh] --scp--> [Proxmox]
# Les secrets du kickstart vivent UNIQUEMENT sur le LXC (posés une fois par
# iso/set-secrets.sh, jamais commités) : le git pull ne les touche pas tant
# que les commits ne modifient pas iso/includes/ — dans ce cas le script
# s'arrête avec les instructions plutôt que de perdre ou d'écraser quoi
# que ce soit.

set -euo pipefail

BUILD_HOST="${FEDORIRI_BUILD_HOST:-root@10.11.12.105}"
SSH_KEY="${FEDORIRI_BUILD_KEY:-$HOME/.ssh/fedoriri_build}"
REPO_DIR="/root/fedoriri"
PROXMOX_DEST="${FEDORIRI_PROXMOX_DEST:-root@self.genly.dev:/var/lib/vz/template/iso}"
SKIP_UPLOAD=0
SKIP_POOL_FLAG=""

log() { printf '\033[1;34m[remote-build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[remote-build]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage : $0 [options]
  --no-upload    build seulement, sans envoi vers Proxmox
  --skip-pool    passe --skip-pool à build-iso.sh (itérations rapides)
  --help         cette aide
Variables : FEDORIRI_BUILD_HOST (défaut $BUILD_HOST),
            FEDORIRI_BUILD_KEY (défaut $SSH_KEY),
            FEDORIRI_PROXMOX_DEST (défaut $PROXMOX_DEST)
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --no-upload) SKIP_UPLOAD=1 ;;
    --skip-pool) SKIP_POOL_FLAG="--skip-pool" ;;
    --help|-h)   usage; exit 0 ;;
    *) die "option inconnue : $1" ;;
  esac
  shift
done

SSH=(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$BUILD_HOST")

log "connexion à $BUILD_HOST…"
"${SSH[@]}" true || die "SSH inaccessible ($BUILD_HOST avec $SSH_KEY)"

# Mise à jour du dépôt sur le LXC. Les secrets vivent dans des fichiers
# suivis mais modifiés localement (iso/includes/10-base.ks et
# 20-partitioning.ks) : on ne bloque que si un commit entrant touche UN DE
# CES fichiers-là précisément — un commit sur d'autres fichiers d'includes
# (ex. 30-packages.ks) fusionne sans risque à côté de modifications locales
# non recouvrantes.
log "git pull sur le LXC…"
"${SSH[@]}" "
  set -euo pipefail
  cd $REPO_DIR
  git fetch -q origin main
  incoming=\$(git diff --name-only HEAD origin/main)
  dirty=\$(git status --porcelain --untracked-files=no | awk '{print \$2}')
  overlap=\$(comm -12 <(sort <<<\"\$incoming\") <(sort <<<\"\$dirty\"))
  if [ -n \"\$overlap\" ]; then
    echo \"CONFLIT-SECRETS: \$overlap\"
    exit 42
  fi
  git merge -q --ff-only origin/main
" || {
  rc=$?
  if [ "$rc" -eq 42 ]; then
    die "des commits entrants modifient des fichiers portant vos changements locaux (secrets).
Sur le LXC : notez vos secrets, git checkout -- <fichiers>, git pull, ./iso/set-secrets.sh, puis relancez."
  fi
  die "git pull a échoué sur le LXC (code $rc)"
}

log "build de l'ISO sur le LXC (le pool en cache rend les rebuilds rapides)…"
"${SSH[@]}" "cd $REPO_DIR && ./iso/build-iso.sh $SKIP_POOL_FLAG"

if [ "$SKIP_UPLOAD" -eq 1 ]; then
  log "build terminé (--no-upload) : l'ISO est sur le LXC dans $REPO_DIR/iso/build/"
  exit 0
fi

log "envoi vers $PROXMOX_DEST…"
"${SSH[@]}" "scp -o StrictHostKeyChecking=accept-new \
  $REPO_DIR/iso/build/fedoriri-44-x86_64.iso \
  $REPO_DIR/iso/build/fedoriri-44-x86_64.iso.sha256 \
  '$PROXMOX_DEST/'"
log "terminé : fedoriri-44-x86_64.iso est disponible dans la bibliothèque ISO de Proxmox."