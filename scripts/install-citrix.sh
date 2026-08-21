#!/usr/bin/env bash
# install-citrix.sh — Citrix Workspace app pour Linux, ligne GCC 11.
#
# Pourquoi la ligne GCC 11 (« Technical Preview ») et pas la stable GCC 8 :
# la stable exige webkit2gtk-4.0 + libsoup-2.4, retirés de Fedora (F43) ;
# la ligne GCC 11 est liée à webkit2gtk-4.1 + libsoup-3.0, tous deux dans
# Fedora 44. Elle s'installe donc proprement, SANS rpm --nodeps.
# Compromis assumé : la TP est en retard sur les correctifs de la stable.
#
# Les URL de téléchargement Citrix portent un jeton Akamai signé (?__gda__=…)
# qui expire en ~1 h : impossible de figer un lien, on scrape la page à
# chaque exécution. Le lien réel est dans l'attribut rel= du HTML brut
# (le href visible est javascript:void(0)).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CITRIX_PAGE="https://www.citrix.com/downloads/workspace-app/betas-and-tech-previews/workspace-app-tp-gcc11-for-linux.html"
ICAROOT="/opt/Citrix/ICAClient"
STATE_FILE="$FEDORIRI_STATE_DIR/citrix-version"
INTERACTIVE=0
FORCE=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --interactive  lance setupwfc en interactif (si le pilotage stdin échoue)
  --force        réinstalle même si la version est déjà présente
  --dry-run      affiche les commandes sans les exécuter
  --help         cette aide
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --interactive) INTERACTIVE=1 ;;
    --force)       FORCE=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --help|-h)     usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done

require_root
require_cmd curl tar sha256sum dnf python3

# ---------------------------------------------------------------------------
# Prérequis bibliothèques.
# ---------------------------------------------------------------------------
log "installation des dépendances (webkit2gtk4.1, libsoup3)…"
run dnf install -y webkit2gtk4.1 libsoup3 libxml2

# GARDE-FOU libxml2 : Citrix (selfservice, storebrowse, UtilDaemon) est lié à
# libxml2.so.2. libxml2 a bumpé son SONAME en 2.15 (→ .so.16) ; Fedora 44 est
# en 2.12.x et fournit encore .so.2. Si Fedora passe à libxml2 >= 2.15, Citrix
# casse — mieux vaut un message clair ici qu'un échec obscur à l'exécution.
if [ "$DRY_RUN" -eq 0 ] && ! ldconfig -p | grep -q 'libxml2\.so\.2 '; then
  die "libxml2.so.2 absent du système : Fedora a probablement bumpé libxml2 >= 2.15.
Citrix Workspace ne peut pas fonctionner sans. Pistes :
  - paquet de compatibilité (libxml2 2.12.x) dans un COPR, ou
  - attendre un paquet Citrix reconstruit contre le nouveau SONAME."
fi

# ---------------------------------------------------------------------------
# Scrape de la page : lien signé + version + checksums affichés.
# ---------------------------------------------------------------------------
log "scrape de la page Citrix GCC 11…"
PAGE_HTML="$(mktemp)"
curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64)" -o "$PAGE_HTML" "$CITRIX_PAGE" \
  || die "page Citrix inaccessible : $CITRIX_PAGE"

# Motif observé : rel="//downloads.citrix.com/.../linuxx64-<ver>.tar.gz?__gda__=exp=...~hmac=..."
DL_PATH="$(grep -oE 'rel="//[^"]*linuxx64-[0-9][0-9.]*\.tar\.gz\?__gda__=[^"]*"' "$PAGE_HTML" \
           | head -1 | sed -e 's/^rel="//' -e 's/"$//')"
[ -n "$DL_PATH" ] || die "aucun lien linuxx64-*.tar.gz trouvé sur la page — la structure a peut-être changé.
Vérifiez à la main : $CITRIX_PAGE"
DL_URL="https:${DL_PATH}"
TARBALL_NAME="$(basename "${DL_PATH%%\?*}")"
CITRIX_VERSION="$(sed -E 's/^linuxx64-([0-9.]+)\.tar\.gz$/\1/' <<<"$TARBALL_NAME")"
log "version publiée : $CITRIX_VERSION ($TARBALL_NAME)"

# Idempotence : ne réinstalle pas la même version.
if [ "$FORCE" -eq 0 ] && [ -x "$ICAROOT/wfica" ] && [ -f "$STATE_FILE" ] \
   && [ "$(cat "$STATE_FILE")" = "$CITRIX_VERSION" ]; then
  log "Citrix $CITRIX_VERSION déjà installé — rien à faire (--force pour réinstaller)"
  rm -f "$PAGE_HTML"
  exit 0
fi

# ---------------------------------------------------------------------------
# Téléchargement immédiat (le jeton expire) + vérification sha256.
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$PAGE_HTML"' EXIT
log "téléchargement de $TARBALL_NAME (~400 Mo)…"
run curl -fL --retry 2 -o "$WORK/$TARBALL_NAME" "$DL_URL"

if [ "$DRY_RUN" -eq 0 ]; then
  # La page affiche des checksums SHA-256 : on les collecte tous et on exige
  # que le nôtre en fasse partie. S'il y a des checksums publiés mais aucun ne
  # correspond → échec (fichier corrompu ou page incohérente). S'il n'y en a
  # aucun → avertissement (la confiance repose alors sur TLS + jeton signé).
  ACTUAL_SHA="$(sha256sum "$WORK/$TARBALL_NAME" | awk '{print $1}')"
  if grep -oiE '\b[a-f0-9]{64}\b' "$PAGE_HTML" | grep -qix "$ACTUAL_SHA"; then
    log "sha256 confirmé par la page de téléchargement ✔"
  elif grep -qoiE '\b[a-f0-9]{64}\b' "$PAGE_HTML"; then
    die "sha256 calculé ($ACTUAL_SHA) absent des checksums publiés sur la page — abandon"
  else
    warn "aucun checksum publié détecté sur la page ; poursuite (transport TLS + URL signée)"
  fi
fi

# ---------------------------------------------------------------------------
# Installation via setupwfc.
# ---------------------------------------------------------------------------
run tar -xzf "$WORK/$TARBALL_NAME" -C "$WORK"
[ "$DRY_RUN" -eq 1 ] || [ -x "$WORK/setupwfc" ] || die "setupwfc introuvable dans le tarball"

if [ "$DRY_RUN" -eq 0 ]; then
  if [ "$INTERACTIVE" -eq 1 ]; then
    ( cd "$WORK" && ./setupwfc )
  else
    # setupwfc n'a pas de mode silencieux documenté, et l'ordre de ses
    # questions change d'une version à l'autre (26.04 : répertoire AVANT toute
    # confirmation, puis USB, EPA, App Protection, FIDO2…). Une séquence de
    # réponses figée installait dans un répertoire nommé « y » puis
    # abandonnait (matériel réel, 2026-08-21). lib/citrix-drive.py répond donc
    # à chaque invite RECONNUE par son texte (pty, bibliothèque standard) :
    #   installer → répertoire par défaut → confirmer → intégrations bureau et
    #   USB : oui → EPA, App Protection (incompatible Wayland), FIDO2 : non →
    #   quitter le menu. Invite inconnue = abandon explicite, jamais de
    #   réponse au hasard. Si Citrix change encore : --interactive.
    if ! python3 "$SCRIPT_DIR/lib/citrix-drive.py" "$WORK/setupwfc"; then
      die "setupwfc a échoué en mode piloté — relancez avec --interactive"
    fi
  fi
  [ -x "$ICAROOT/wfica" ] || die "installation incomplète : $ICAROOT/wfica absent"
fi

# ---------------------------------------------------------------------------
# Certificats : le keystore Citrix ne contient que ~10 CA racines et aucun
# lien de hachage → « SSL Error 61 ». ctx_rehash (livré par Citrix) importe
# les CA système. À rejouer après CHAQUE mise à jour du paquet — c'est
# pourquoi il est ici et pas dans un one-shot.
# ---------------------------------------------------------------------------
if [ -x "$ICAROOT/util/ctx_rehash" ]; then
  log "ctx_rehash (import des CA système)…"
  run "$ICAROOT/util/ctx_rehash"
else
  warn "ctx_rehash introuvable — les erreurs SSL 61 sont probables"
fi

# ---------------------------------------------------------------------------
# Configuration : clés All_Regions.ini + modèle wfclient.ini (voir
# configs/citrix/README.md pour le pourquoi de chaque clé).
# ---------------------------------------------------------------------------
apply_ini_keys() {
  # Fichier de clés « Section/Clé=Valeur », appliqué idempotemment.
  local keys_file="$1" target="$2" section key value
  [ -f "$target" ] || { warn "$target absent, clés non appliquées"; return 0; }
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    section="${line%%/*}"; key="${line#*/}"; value="${key#*=}"; key="${key%%=*}"
    if grep -q "^${key}=" "$target"; then
      run sed -i "s|^${key}=.*|${key}=${value}|" "$target"
    else
      run sed -i "/^\[${section}\]/a ${key}=${value}" "$target"
    fi
  done < "$keys_file"
}
if [ -f "$SCRIPT_DIR/../configs/citrix/all-regions-keys.conf" ]; then
  apply_ini_keys "$SCRIPT_DIR/../configs/citrix/all-regions-keys.conf" "$ICAROOT/config/All_Regions.ini"
fi
run install -D -m 0644 "$SCRIPT_DIR/../configs/citrix/wfclient.ini" /etc/skel/.ICAClient/wfclient.ini

run mkdir -p "$FEDORIRI_STATE_DIR"
[ "$DRY_RUN" -eq 1 ] || printf '%s\n' "$CITRIX_VERSION" > "$STATE_FILE"
log "Citrix Workspace $CITRIX_VERSION installé.
Diagnostic moniteurs : WFICA_OPTS=\"-span h\" $ICAROOT/wfica"
