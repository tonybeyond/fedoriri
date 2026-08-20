#!/usr/bin/env bash
# set-secrets.sh — remplit les deux secrets du kickstart de façon guidée :
#   1. le HASH du mot de passe de l'utilisateur fedo
#      (CHANGEME_PASSWORD_HASH_SHA512 dans includes/10-base.ks) ;
#   2. la phrase de passe LUKS, EN CLAIR — c'est anaconda qui la chiffrera
#      (CHANGEME_LUKS_PASSPHRASE dans includes/20-partitioning.ks).
#
# Rien n'est affiché à l'écran ni passé en argument de commande (pas de
# trace dans l'historique shell). Idempotent : si un placeholder a déjà été
# remplacé, le fichier n'est pas retouché.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_KS="$SCRIPT_DIR/includes/10-base.ks"
PART_KS="$SCRIPT_DIR/includes/20-partitioning.ks"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage : $0   (interactif, aucun argument)"
  exit 0
fi

command -v openssl >/dev/null 2>&1 || { echo "openssl est requis" >&2; exit 1; }

# Lit un secret deux fois, sans écho, et vérifie la concordance.
ask_secret() {
  local prompt="$1" s1 s2
  while :; do
    read -r -s -p "$prompt : " s1; echo >&2
    read -r -s -p "$prompt (confirmation) : " s2; echo >&2
    if [ -z "$s1" ]; then echo "vide — recommencez" >&2; continue; fi
    if [ "$s1" != "$s2" ]; then echo "les deux saisies diffèrent — recommencez" >&2; continue; fi
    printf '%s' "$s1"
    return
  done
}

# --- 1. Mot de passe utilisateur → hash SHA-512 ------------------------------
if grep -q 'CHANGEME_PASSWORD_HASH_SHA512' "$BASE_KS"; then
  PW="$(ask_secret "Mot de passe de l'utilisateur fedo")"
  # openssl lit le mot de passe sur stdin : il n'apparaît ni dans ps ni dans
  # l'historique.
  HASH="$(printf '%s' "$PW" | openssl passwd -6 -stdin)"
  unset PW
  # Le hash ($6$sel$…) ne contient que [./0-9A-Za-z$] : '|' est un délimiteur sûr.
  sed -i.bak "s|CHANGEME_PASSWORD_HASH_SHA512|${HASH}|" "$BASE_KS" && rm -f "$BASE_KS.bak"
  echo "→ hash posé dans includes/10-base.ks"
else
  echo "→ includes/10-base.ks : déjà renseigné, rien à faire"
fi

# --- 2. Phrase de passe LUKS (en clair dans le kickstart) --------------------
if grep -q 'CHANGEME_LUKS_PASSPHRASE' "$PART_KS"; then
  while :; do
    LUKS="$(ask_secret "Phrase de passe LUKS (demandée à chaque démarrage)")"
    # Le sed ci-dessous utilise '|' comme délimiteur et une phrase contenant
    # '\' se corromprait silencieusement : on refuse ces deux caractères.
    case "$LUKS" in
      *'|'*|*'\'*) echo "évitez les caractères | et \\ — recommencez" >&2 ;;
      *) break ;;
    esac
  done
  sed -i.bak "s|CHANGEME_LUKS_PASSPHRASE|${LUKS}|" "$PART_KS" && rm -f "$PART_KS.bak"
  unset LUKS
  echo "→ phrase LUKS posée dans includes/20-partitioning.ks"
else
  echo "→ includes/20-partitioning.ks : déjà renseigné, rien à faire"
fi

cat <<'EOF'

Secrets en place. Rappels :
  - NE COMMITEZ PAS ces deux fichiers modifiés (git ne doit jamais voir les
    secrets) : git restore iso/includes/ pour revenir aux placeholders.
  - l'ISO produite contiendra ces secrets → ne pas la diffuser ;
  - après installation, changez la phrase LUKS sur le poste :
    cryptsetup luksChangeKey /dev/<partition-luks>
EOF
