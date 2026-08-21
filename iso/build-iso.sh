#!/usr/bin/env bash
# build-iso.sh — construit l'ISO fedoriri (Fedora 44 + Niri, non interactive).
#
# Principe (voie kickstart, cf. README) :
#   1. télécharge l'ISO Fedora 44 Everything netinst officielle ;
#   2. VÉRIFIE le fichier CHECKSUM (signature GPG Fedora) puis le sha256 de
#      l'ISO — échec du build si l'une des deux vérifications rate ;
#   3. constitue un pool local de RPM (fermeture complète de dépendances du
#      %packages) pour installer sans réseau ;
#   4. aplatit et valide le kickstart (ksflatten + ksvalidator) ;
#   5. injecte kickstart + pool + payload dans l'ISO avec mkksiso (lorax),
#      qui ajoute inst.ks au menu de démarrage → installation automatique.
#
# À lancer sur Fedora 44 (ou : --podman pour s'auto-exécuter dans un
# conteneur fedora:44). Prérequis Fedora : lorax pykickstart createrepo_c
# xorriso dnf-plugins-core.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

RELEASE=44
ARCH=x86_64
MIRROR_BASE="https://download.fedoraproject.org/pub/fedora/linux/releases/${RELEASE}/Everything/${ARCH}/iso"
FEDORA_GPG_URL="https://fedoraproject.org/fedora.gpg"

BUILD_DIR="$SCRIPT_DIR/build"
OUT_ISO="$BUILD_DIR/fedoriri-${RELEASE}-${ARCH}.iso"
USE_PODMAN=0
SKIP_POOL=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --podman      s'exécute dans un conteneur fedora:${RELEASE} (hôte non Fedora)
  --skip-pool   ne pas (re)télécharger le pool de paquets (itérations rapides ;
                l'installation exigera alors le réseau)
  --output F    chemin de l'ISO produite (défaut : $OUT_ISO)
  --dry-run     affiche les commandes sans les exécuter
  --help        cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --podman)    USE_PODMAN=1 ;;
    --skip-pool) SKIP_POOL=1 ;;
    --output)    shift; OUT_ISO="$1" ;;
    --dry-run)   DRY_RUN=1 ;;
    --help|-h)   usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Garde-fous : refus de builder avec les placeholders du kickstart.
# ---------------------------------------------------------------------------
check_placeholders() {
  local bad=0
  if grep -rq 'CHANGEME_PASSWORD_HASH_SHA512' "$SCRIPT_DIR/includes/"; then
    warn "le hash du mot de passe utilisateur n'a pas été remplacé dans includes/10-base.ks"
    warn "générez-le avec : openssl passwd -6 'votre-mot-de-passe'"
    bad=1
  fi
  if grep -rq 'CHANGEME_LUKS_PASSPHRASE' "$SCRIPT_DIR/includes/"; then
    warn "la phrase de passe LUKS n'a pas été remplacée dans includes/20-partitioning.ks"
    bad=1
  fi
  [ "$bad" -eq 0 ] || die "placeholders non remplacés — build refusé."
}

# ---------------------------------------------------------------------------
# Exécution en conteneur (hôte non Fedora).
# ---------------------------------------------------------------------------
if [ "$USE_PODMAN" -eq 1 ]; then
  require_cmd podman
  log "relance dans un conteneur fedora:${RELEASE}…"
  # --privileged : dnf --installroot a besoin de monter/chrooter proprement.
  exec podman run --rm -it --privileged \
    -v "$REPO_ROOT:/src:Z" -w /src \
    "registry.fedoraproject.org/fedora:${RELEASE}" \
    bash -c "dnf install -y --setopt=install_weak_deps=False \
               lorax pykickstart createrepo_c xorriso dnf-plugins-core rsync \
               zstd mtools isomd5sum \
             && ./iso/build-iso.sh $( [ "$SKIP_POOL" -eq 1 ] && printf -- '--skip-pool' )"
fi

require_cmd curl gpg sha256sum ksflatten ksvalidator mkksiso createrepo_c xorriso rsync dnf
check_placeholders
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 1+2. ISO amont : résolution du nom, téléchargement, vérification GPG+sha256.
# ---------------------------------------------------------------------------
fetch_and_verify_upstream() {
  local listing iso_name checksum_name
  log "résolution du nom de l'ISO netinst sur le miroir…"
  listing="$(curl -fsSL "$MIRROR_BASE/")"
  iso_name="$(grep -oE "Fedora-Everything-netinst-${ARCH}-${RELEASE}-[0-9.]+\.iso" <<<"$listing" | sort -u | tail -1)"
  checksum_name="$(grep -oE "Fedora-Everything-${RELEASE}-[0-9.]+-${ARCH}-CHECKSUM" <<<"$listing" | sort -u | tail -1)"
  [ -n "$iso_name" ] || die "ISO netinst introuvable sur $MIRROR_BASE"
  [ -n "$checksum_name" ] || die "fichier CHECKSUM introuvable sur $MIRROR_BASE"
  log "ISO amont : $iso_name"

  if [ ! -f "$BUILD_DIR/$iso_name" ]; then
    run curl -fL --retry 3 -o "$BUILD_DIR/$iso_name.part" "$MIRROR_BASE/$iso_name"
    run mv "$BUILD_DIR/$iso_name.part" "$BUILD_DIR/$iso_name"
  else
    log "ISO déjà présente, vérification seulement"
  fi
  run curl -fsSL -o "$BUILD_DIR/$checksum_name" "$MIRROR_BASE/$checksum_name"
  run curl -fsSL -o "$BUILD_DIR/fedora.gpg" "$FEDORA_GPG_URL"

  if [ "$DRY_RUN" -eq 0 ]; then
    # Trousseau jetable : on n'importe pas les clés Fedora dans le trousseau
    # de l'utilisateur.
    local gnupg_tmp
    gnupg_tmp="$(mktemp -d)"
    chmod 700 "$gnupg_tmp"
    gpg --homedir "$gnupg_tmp" --import "$BUILD_DIR/fedora.gpg"
    gpg --homedir "$gnupg_tmp" --verify "$BUILD_DIR/$checksum_name" \
      || die "signature GPG du fichier CHECKSUM invalide — build interrompu"
    rm -rf "$gnupg_tmp"
    ( cd "$BUILD_DIR" && grep "$iso_name" "$checksum_name" | sha256sum -c - ) \
      || die "sha256 de l'ISO invalide — build interrompu"
    log "ISO amont vérifiée (GPG + sha256) ✔"
  fi
  UPSTREAM_ISO="$BUILD_DIR/$iso_name"
}

# ---------------------------------------------------------------------------
# 3. Pool local de paquets : fermeture complète du %packages.
# ---------------------------------------------------------------------------
build_package_pool() {
  local pool="$BUILD_DIR/stage/fedoriri/repo" tmproot pkgs
  if [ "$SKIP_POOL" -eq 1 ]; then
    warn "pool de paquets sauté (--skip-pool) : l'installation exigera le réseau"
    mkdir -p "$pool"
    run createrepo_c --update "$pool"
    return
  fi
  mkdir -p "$pool"
  # Liste des paquets : les lignes « nues » du %packages (ni groupe, ni option).
  pkgs="$(sed -n '/^%packages/,/^%end/p' "$SCRIPT_DIR/includes/30-packages.ks" \
          | grep -vE '^(%|@|#|-|$)')"
  log "téléchargement de la fermeture de dépendances ($(wc -l <<<"$pkgs" | tr -d ' ') paquets explicites)…"
  # dnf --installroot a besoin de root (verrous, cache, métadonnées).
  if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    die "cette étape exige root : relancez avec sudo ./iso/build-iso.sh"
  fi
  # Installroot PERSISTANT : le cache libdnf5 qu'il contient évite de
  # retélécharger ~1 Go de RPM à chaque build (seuls les paquets nouveaux ou
  # mis à jour sont récupérés).
  tmproot="$BUILD_DIR/dnf-installroot"
  mkdir -p "$tmproot"
  # --installroot vide : dnf calcule la fermeture COMPLÈTE (comme anaconda),
  # pas seulement les paquets manquants sur l'hôte de build.
  # dnf5 n'accepte ni --downloaddir ni --destdir pour `install` (--destdir
  # n'existe que pour download/reposync/upgrade, et `download` ne sait pas
  # résoudre les groupes @core…) : avec --downloadonly les RPM restent dans
  # le cache libdnf5 de l'installroot, d'où on les récupère ensuite.
  # shellcheck disable=SC2086  # $pkgs doit être éclaté en mots
  run dnf -y --installroot="$tmproot" --releasever="$RELEASE" --forcearch="$ARCH" \
      --use-host-config --setopt=keepcache=1 \
      install --downloadonly \
      @core @standard @hardware-support $pkgs
  if [ "$DRY_RUN" -eq 0 ]; then
    find "$tmproot/var/cache/libdnf5" -name '*.rpm' -exec cp -f {} "$pool/" \;
    [ -n "$(find "$pool" -name '*.rpm' | head -1)" ] \
      || die "aucun RPM récupéré depuis le cache libdnf5 ($tmproot) — chemin de cache inattendu ?"
  fi
  # Métadonnées de groupes (comps) : sans elles, anaconda ne sait pas
  # résoudre @core/@standard/@hardware-support depuis le pool local
  # (« No match for argument: core », constaté au test n°2). On réutilise le
  # comps OFFICIEL du dépôt Fedora Everything — le même que celui avec lequel
  # dnf a résolu la fermeture ci-dessus, donc les membres mandatory/default
  # des groupes sont bien dans le pool.
  local os_base="https://download.fedoraproject.org/pub/fedora/linux/releases/${RELEASE}/Everything/${ARCH}/os"
  local comps="$BUILD_DIR/comps-f${RELEASE}.xml" comps_href repomd
  if [ ! -s "$comps" ]; then
    repomd="$(curl -fsSL "$os_base/repodata/repomd.xml")" \
      || die "repomd.xml inaccessible sur $os_base"
    # Les miroirs Fedora ne publient pas forcément de comps .xml brut :
    # constaté en réel, seuls .xml.zst et .xml.zck étaient proposés. On prend
    # le .xml s'il existe, sinon le .xml.zst (décompressé par zstd). awk en
    # un seul processus : pas de pipeline grep|head sous pipefail, dont
    # l'échec silencieux via set -e a déjà coûté un build.
    comps_href="$(awk 'match($0,/href="repodata\/[^"]*comps[^"]*\.xml"/){print substr($0,RSTART+6,RLENGTH-7); exit}' <<<"$repomd")"
    if [ -z "$comps_href" ]; then
      comps_href="$(awk 'match($0,/href="repodata\/[^"]*comps[^"]*\.xml\.zst"/){print substr($0,RSTART+6,RLENGTH-7); exit}' <<<"$repomd")"
    fi
    [ -n "$comps_href" ] || die "fichier comps introuvable dans le repomd.xml du miroir (formats .xml/.xml.zst)"
    log "comps : $comps_href"
    run curl -fsSL -o "$comps.dl" "$os_base/$comps_href"
    if [ "$DRY_RUN" -eq 0 ]; then
      case "$comps_href" in
        *.zst) require_cmd zstd; zstd -q -dcf "$comps.dl" > "$comps"; rm -f "$comps.dl" ;;
        *)     mv "$comps.dl" "$comps" ;;
      esac
      [ -s "$comps" ] || die "comps vide après téléchargement/décompression"
    fi
  fi
  run createrepo_c --update --groupfile "$comps" "$pool"
  log "pool local prêt : $(find "$pool" -name '*.rpm' 2>/dev/null | wc -l | tr -d ' ') RPM (+ groupes comps)"
}

# ---------------------------------------------------------------------------
# 4. Kickstart : aplatissement + validation.
# ---------------------------------------------------------------------------
prepare_kickstart() {
  FLAT_KS="$BUILD_DIR/fedoriri-flat.ks"
  run ksflatten -c "$SCRIPT_DIR/fedoriri.ks" -o "$FLAT_KS"
  # `--version` doit suivre la release d'anaconda ; F44 est la plus récente
  # connue de pykickstart 3.69.
  run ksvalidator "$FLAT_KS" || die "kickstart invalide — build interrompu"
  # L'ignoredisk est généré à l'exécution par le %pre de 20-partitioning.ks
  # (détection du disque cible) : ksflatten/ksvalidator ne sauraient pas
  # résoudre un %include vers un fichier qui n'existe pas encore, donc la
  # ligne n'est ajoutée qu'ici, APRÈS validation. Position sans importance :
  # les directives kickstart sont déclaratives, et anaconda exécute les %pre
  # avant d'interpréter les directives — le fichier existera au bon moment.
  if [ "$DRY_RUN" -eq 0 ]; then
    grep -q 'fedoriri-ignoredisk' "$FLAT_KS" \
      || die "le %pre de détection du disque manque dans le kickstart aplati"
    grep -q 'fedoriri-source' "$FLAT_KS" \
      || die "le %pre de localisation du pool manque dans le kickstart aplati"
    printf '\n%%include /tmp/fedoriri-ignoredisk.ks\n' >> "$FLAT_KS"
    # Source d'installation localisée par le %pre (harddrive --partition=…) :
    # remplace l'ancien inst.repo=hd:LABEL=… de la cmdline, qui échouait sur
    # clé USB (label dupliqué sda/sda1 → montage impossible → installation
    # interactive, constaté sur le matériel réel).
    printf '%%include /tmp/fedoriri-source.ks\n' >> "$FLAT_KS"
    # Garde-fou : sans commande bootloader dans les sources, ksflatten émet
    # le défaut pykickstart « --location=none » = PAS de bootloader installé
    # (système non amorçable). La ligne explicite de 10-base.ks doit gagner.
    if grep -q 'bootloader.*--location=none' "$FLAT_KS"; then
      die "le kickstart aplati contient « bootloader --location=none » : la commande bootloader explicite a disparu de 10-base.ks"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 5. Payload + mkksiso.
# ---------------------------------------------------------------------------
assemble_iso() {
  local stage="$BUILD_DIR/stage/fedoriri"
  mkdir -p "$stage/payload"
  run rsync -a --delete \
      --exclude '.git' --exclude 'iso/build' \
      "$REPO_ROOT/scripts" "$REPO_ROOT/systemd" "$REPO_ROOT/desktop" \
      "$REPO_ROOT/configs" "$REPO_ROOT/packaging" \
      "$stage/payload/"

# (l'étiquette de volume n'est plus utilisée : la source d'installation est
# localisée à l'exécution par le %pre — voir includes/20-partitioning.ks.)

  # mkksiso refuse d'écraser une sortie existante : on purge un éventuel
  # artefact d'un build précédent (c'est notre fichier, pas une donnée).
  run rm -f "$OUT_ISO"

  # Sans périphérique loop (cas typique : conteneur LXC), mkefiboot ne peut
  # pas reconstruire l'image efiboot embarquée → --skip-mkefiboot.
  # Conséquence documentée (doc lorax) : seule l'image efiboot EMBARQUÉE
  # garde son grub.cfg d'origine ; or elle ne sert qu'au boot UEFI depuis une
  # CLÉ USB. Une ISO montée en CD/VM (Proxmox, virt-manager) ou un boot BIOS
  # utilisent les configs du système de fichiers ISO, éditées normalement.
  local efi_flag=()
  if ! losetup --find >/dev/null 2>&1; then
    warn "pas de périphérique loop (conteneur ?) → --skip-mkefiboot, puis
patch mtools de l'image EFI embarquée (voir patch_embedded_efiboot)."
    efi_flag=(--skip-mkefiboot)
  fi

  # Le pool local est embarqué dans l'ISO (--add) ; la source d'installation
  # est déclarée par le kickstart (harddrive, généré par le %pre), pas par
  # inst.repo sur la cmdline — qui primerait sur le kickstart et échoue sur
  # clé USB (label dupliqué).
  local mkksiso_args=("${efi_flag[@]}"
                      --ks "$FLAT_KS"
                      --add "$BUILD_DIR/stage/fedoriri"
                      "$UPSTREAM_ISO" "$OUT_ISO")
  if [ "$(uname -m)" = "$ARCH" ]; then
    run mkksiso "${mkksiso_args[@]}"
  else
    # Build croisé (ex. VM Fedora aarch64 → ISO x86_64) : mkksiso s'arrête sur
    # « iso arch does not match the host arch » (CheckDiscinfo compare le
    # .discinfo de l'ISO à uname -m, sans option de contournement). Or tout ce
    # que mkksiso exécute — xorriso, mkefiboot, implantisomd5 — n'est que de
    # la manipulation de fichiers, indépendante de l'arch hôte ; le code
    # amont doute lui-même de l'utilité du contrôle (TODO dans
    # pylorax/cmdline/mkksiso.py). On neutralise donc UNIQUEMENT ce contrôle,
    # en appelant le même main() avec les mêmes arguments.
    log "build croisé $(uname -m) → $ARCH : contrôle d'architecture de mkksiso neutralisé"
    run python3 - "${mkksiso_args[@]}" <<'PYEOF'
import sys
from pylorax.cmdline import mkksiso
mkksiso.CheckDiscinfo = lambda path: None
sys.argv = ["mkksiso"] + sys.argv[1:]
sys.exit(mkksiso.main())
PYEOF
  fi

  if [ "${#efi_flag[@]}" -gt 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    patch_embedded_efiboot
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    # Nom de fichier relatif dans le .sha256 : vérifiable où que l'ISO soit
    # copiée (sha256sum -c échoue sinon sur le chemin absolu de la machine
    # de build — constaté après l'envoi vers Proxmox).
    ( cd "$(dirname "$OUT_ISO")" && sha256sum "$(basename "$OUT_ISO")" | tee "$(basename "$OUT_ISO").sha256" )
  fi
  log "ISO produite : $OUT_ISO"
}

# ---------------------------------------------------------------------------
# Patch de l'image EFI embarquée après --skip-mkefiboot.
#
# Constaté en réel (extraction mtools sur l'ISO produite) : le grub.cfg
# CONTENU dans l'image El Torito UEFI (efiboot.img) est le menu complet
# amont, sans inst.ks — il ne chaîne PAS vers le grub.cfg édité du système
# de fichiers ISO. Donc avec --skip-mkefiboot seul, tout boot UEFI (CD ou
# clé USB) ouvre un installateur INTERACTIF : le kickstart est perdu, seule
# la voie BIOS reste automatisée.
#
# Remède sans /dev/loop ni montage : mtools écrit directement dans l'image
# FAT. L'image est un extent contigu de l'ISO → on l'extrait par dd, on y
# recopie le grub.cfg édité (mcopy), on la réécrit en place (dd conv=notrunc,
# taille inchangée), puis on réimplante le md5 de média (invalidé par la
# réécriture) pour que « Test this media » reste fiable.
# ---------------------------------------------------------------------------
patch_embedded_efiboot() {
  require_cmd mcopy mtype implantisomd5 dd
  local report blocks512 lba img="$BUILD_DIR/efiboot-patch.img" cfg="$BUILD_DIR/efi-grub-edited.cfg"

  report="$(xorriso -indev "$OUT_ISO" -report_el_torito plain 2>/dev/null)"
  # Ligne : « El Torito boot img :  2  UEFI  y  none 0x0000 0x00 <blocs512> <LBA2048> »
  read -r blocks512 lba <<<"$(awk '/El Torito boot img[[:space:]]*:[[:space:]]*[0-9]+[[:space:]]+UEFI/ {print $(NF-1), $NF; exit}' <<<"$report")"
  [ -n "${lba:-}" ] || die "entrée El Torito UEFI introuvable dans $OUT_ISO"
  log "patch de l'image EFI embarquée (LBA $lba, $blocks512 blocs de 512)…"

  dd if="$OUT_ISO" of="$img" bs=512 skip=$((lba * 4)) count="$blocks512" status=none
  rm -f "$cfg"
  osirrox -indev "$OUT_ISO" -extract /EFI/BOOT/grub.cfg "$cfg" 2>/dev/null
  chmod u+w "$cfg"
  grep -q 'inst\.ks=' "$cfg" || die "le grub.cfg du système de fichiers ISO ne contient pas inst.ks — édition mkksiso absente ?"
  mcopy -o -i "$img" "$cfg" ::/EFI/BOOT/grub.cfg \
    || die "mcopy a échoué (image FAT pleine ou structure inattendue)"
  # Vérification : le menu embarqué porte bien le kickstart maintenant.
  mtype -i "$img" ::/EFI/BOOT/grub.cfg | grep -q 'inst\.ks=' \
    || die "vérification post-patch échouée : inst.ks absent du grub.cfg embarqué"
  dd if="$img" of="$OUT_ISO" bs=512 seek=$((lba * 4)) count="$blocks512" conv=notrunc status=none
  implantisomd5 --force "$OUT_ISO" >/dev/null
  rm -f "$img" "$cfg"
  log "image EFI embarquée patchée : le boot UEFI porte le kickstart ✔"
}

fetch_and_verify_upstream
build_package_pool
prepare_kickstart
assemble_iso
