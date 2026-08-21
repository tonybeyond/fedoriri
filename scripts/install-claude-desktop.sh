#!/usr/bin/env bash
# install-claude-desktop.sh — Claude Desktop (Anthropic), paquet OFFICIEL.
#
# Anthropic ne publie pour Linux qu'un dépôt apt (Ubuntu/Debian, bêta) :
# « Fedora and RHEL: only Debian-based distributions are supported today »
# (code.claude.com/docs/en/desktop-linux, consulté le 2026-08-21). Plutôt
# qu'un reconditionnement tiers, fedoriri prend le .deb OFFICIEL dans le
# pool du dépôt Anthropic et le déballe lui-même — c'est une archive ar
# (bsdtar sait la lire) dont tout le contenu vit sous /usr/lib/claude-desktop,
# /usr/bin, /usr/share/{applications,icons}. Pas de postinst utile pour nous
# (il ne fait que poser le dépôt apt et un profil AppArmor « unconfined »).
#
# Chaîne de confiance (comme apt) :
#   clef   : https://downloads.claude.ai/claude-desktop/key.asc
#            empreinte 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE (documentée)
#   InRelease signé par cette clef → sha256 de Packages → sha256 du .deb.
# Dépendances Debian → Fedora : gtk3 libnotify nss xdg-utils at-spi2-core
# libdrm mesa-libgbm libxcb libsecret libXtst libuuid xdg-desktop-portal(-gtk)
# gvfs alsa-lib libappindicator-gtk3 gnome-keyring — toutes dans le jeu de
# paquets de l'ISO (vérifié rpm -q sur le système installé).
#
# Idempotent (version mémorisée dans $FEDORIRI_STATE_DIR/claude-desktop-version).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

BASE_URL="https://downloads.claude.ai/claude-desktop/apt/stable"
KEY_URL="https://downloads.claude.ai/claude-desktop/key.asc"
KEY_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
ARCH_DEB="amd64"
STATE_FILE="$FEDORIRI_STATE_DIR/claude-desktop-version"
FORCE=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --force    réinstalle même si la version est déjà présente
  --dry-run  affiche les commandes sans les exécuter
  --help     cette aide
EOF
}
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $arg (voir --help)" ;;
  esac
done

require_root
require_cmd curl gpg bsdtar sha256sum tar

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# --- 1. Clef Anthropic : téléchargement + contrôle d'empreinte ------------
log "clef de signature Anthropic…"
run curl -fsSLo key.asc "$KEY_URL"
if [ "$DRY_RUN" -eq 0 ]; then
  fpr="$(gpg --batch --with-colons --show-keys key.asc 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
  [ "$fpr" = "$KEY_FPR" ] || die "empreinte de clef inattendue : $fpr (attendu $KEY_FPR)"
  gpg --batch --no-default-keyring --keyring "$WORK/kr.gpg" --import key.asc >/dev/null 2>&1
fi

# --- 2. InRelease signé → Packages vérifié --------------------------------
log "index du dépôt (InRelease signé)…"
run curl -fsSLo InRelease "$BASE_URL/dists/stable/InRelease"
run curl -fsSLo Packages  "$BASE_URL/dists/stable/main/binary-$ARCH_DEB/Packages"
if [ "$DRY_RUN" -eq 0 ]; then
  gpg --batch --no-default-keyring --keyring "$WORK/kr.gpg" --output Release --decrypt InRelease >/dev/null 2>gpg.log \
    || die "signature InRelease invalide : $(cat gpg.log)"
  # Release liste « <sha256> <taille> main/binary-amd64/Packages » sous SHA256:.
  want="$(awk -v f="main/binary-$ARCH_DEB/Packages" '/^SHA256:/{s=1;next} /^[A-Za-z]/{s=0} s && $3==f {print $1; exit}' Release)"
  have="$(sha256sum Packages | awk '{print $1}')"
  [ -n "$want" ] && [ "$want" = "$have" ] || die "sha256 de Packages non conforme à Release"
fi

# --- 3. Dernier .deb : chemin + sha256 depuis Packages ---------------------
if [ "$DRY_RUN" -eq 0 ]; then
  # Blocs séparés par une ligne vide ; on garde le bloc de version la plus haute.
  read -r DEB_PATH DEB_SHA VERSION < <(awk -v RS= -F'\n' '
    { v=""; f=""; s="" ; for (i=1;i<=NF;i++){ if ($i ~ /^Version: /) v=substr($i,10); if ($i ~ /^Filename: /) f=substr($i,11); if ($i ~ /^SHA256: /) s=substr($i,9) }
      if (f!="") print f, s, v }' Packages | sort -k3 -V | tail -1)
  [ -n "${DEB_PATH:-}" ] || die "aucun paquet claude-desktop trouvé dans l'index"
  log "version publiée : $VERSION"
  if [ "$FORCE" -eq 0 ] && [ -x /usr/lib/claude-desktop/claude-desktop ] && [ -f "$STATE_FILE" ] \
     && [ "$(cat "$STATE_FILE")" = "$VERSION" ]; then
    log "Claude Desktop $VERSION déjà installé — rien à faire (--force pour réinstaller)"
    exit 0
  fi
  log "téléchargement de $(basename "$DEB_PATH") (~200 Mo)…"
  curl -fL --retry 2 -o pkg.deb "$BASE_URL/$DEB_PATH"
  [ "$(sha256sum pkg.deb | awk '{print $1}')" = "$DEB_SHA" ] || die "sha256 du .deb non conforme à l'index — abandon"
  log "sha256 du .deb confirmé ✔"
else
  log "(dry-run) téléchargement + vérification du .deb"
fi

# --- 4. Déballage sous / (mêmes chemins que le .deb) ----------------------
if [ "$DRY_RUN" -eq 0 ]; then
  bsdtar -xOf pkg.deb data.tar.xz > data.tar.xz
  rm -rf /usr/lib/claude-desktop
  tar -xJf data.tar.xz -C / \
      --exclude='./usr/share/doc' --exclude='./usr/share/lintian'
  # Bac à sable Chromium : setuid root requis (comme dans le .deb), sans
  # AppArmor ici — SELinux gère.
  chmod 4755 /usr/lib/claude-desktop/chrome-sandbox
  restorecon -RF /usr/lib/claude-desktop /usr/bin/claude-desktop \
      /usr/share/applications/com.anthropic.Claude.desktop 2>/dev/null || true
  gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
  update-desktop-database -q /usr/share/applications 2>/dev/null || true
  [ -x /usr/lib/claude-desktop/claude-desktop ] || die "installation incomplète : binaire absent"
  mkdir -p "$FEDORIRI_STATE_DIR"
  printf '%s\n' "$VERSION" > "$STATE_FILE"
fi
log "Claude Desktop installé (lanceur « Claude », commande claude-desktop). Mise à jour : relancer ce script (la version publiée est comparée à $STATE_FILE)."
