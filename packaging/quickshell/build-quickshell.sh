#!/usr/bin/env bash
# build-quickshell.sh — compile et installe Quickshell >= 0.3.0 (option A).
#
# Pourquoi compiler : le paquet Fedora 44 est en 0.2.1^git20260209, qui n'a
# ni Quickshell.Networking ni Quickshell.Services.Polkit, importés par le
# shell d'Omarchy v4. Il faut >= 0.3.0, depuis
# github.com/quickshell-mirror/quickshell.
#
# ⚠️ ABI Qt : le BUILD.md amont est formel — Quickshell s'appuie sur des API
# Qt PRIVÉES et DOIT être recompilé à chaque release de Qt, sinon crash par
# incompatibilité d'ABI. D'où : (1) le tampon de version Qt écrit ici, et
# (2) fedoriri-quickshell-qt-guard.service qui compare ce tampon à chaque
# démarrage et relance la compilation après un bump de Qt. Ce n'est pas une
# option, c'est une exigence (voir README de ce dossier).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "$SCRIPT_DIR/../../scripts/lib/common.sh"

QS_REPO="https://github.com/quickshell-mirror/quickshell.git"
MIN_VERSION="0.3.0"
SRC_CACHE="$FEDORIRI_STATE_DIR/quickshell-src"
PREFIX="/usr/local"

usage() {
  cat <<EOF
Usage : $0 [--tag vX.Y.Z] [--dry-run|--help]
Sans --tag : dernière release amont >= $MIN_VERSION.
EOF
}
TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag)     shift; TAG="$1" ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $1" ;;
  esac
  shift
done

require_root
require_cmd git dnf rpm

# Dépendances de compilation (noms validés contre mdapi par la CI, comme le
# kickstart — voir build-deps.txt).
mapfile -t DEPS < <(grep -vE '^(#|$)' "$SCRIPT_DIR/build-deps.txt")
log "installation des dépendances de build (${#DEPS[@]} paquets)…"
run dnf install -y "${DEPS[@]}"

# Résolution du tag : dernière release, jamais d'URL/commit figé.
if [ -z "$TAG" ]; then
  TAG="$(git ls-remote --tags --refs "$QS_REPO" \
         | awk -F/ '{print $NF}' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
         | sort -V | tail -1)"
  [ -n "$TAG" ] || die "aucun tag de release trouvé sur $QS_REPO"
fi
VERSION="${TAG#v}"
if [ "$(printf '%s\n%s\n' "$MIN_VERSION" "$VERSION" | sort -V | head -1)" != "$MIN_VERSION" ]; then
  die "version $VERSION < $MIN_VERSION : le shell Omarchy v4 exige >= $MIN_VERSION (Networking, Services.Polkit)"
fi
log "compilation de quickshell $TAG"

# Source en cache : le garde-fou Qt doit pouvoir recompiler SANS réseau.
if [ ! -d "$SRC_CACHE/.git" ]; then
  run git clone "$QS_REPO" "$SRC_CACHE"
fi
run git -C "$SRC_CACHE" fetch --tags --quiet
run git -C "$SRC_CACHE" checkout --quiet "$TAG"

BUILD_DIR="$SRC_CACHE/build"
run cmake -S "$SRC_CACHE" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCRASH_REPORTER=OFF
run cmake --build "$BUILD_DIR"
run cmake --install "$BUILD_DIR"

# Tampons pour le garde-fou ABI Qt.
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$FEDORIRI_STATE_DIR"
  printf '%s\n' "$VERSION" > "$FEDORIRI_STATE_DIR/quickshell.version"
  rpm -q --qf '%{VERSION}-%{RELEASE}\n' qt6-qtbase > "$FEDORIRI_STATE_DIR/quickshell.qt-version"
  "$PREFIX/bin/quickshell" --version || die "le binaire installé ne démarre pas"
fi
log "quickshell $VERSION installé (préfixe $PREFIX), tampon Qt posé."
