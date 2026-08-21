# 20-partitioning.ks — disque entier, chiffré LUKS2.
#
# ⚠️ EFFACE LE DISQUE CIBLE SANS CONFIRMATION. C'est voulu : l'installation
# est non interactive. Ne démarrez pas cette ISO sur une machine dont vous
# voulez garder les données.

zerombr
clearpart --all --initlabel --disklabel=gpt

# Partitionnement automatique Btrfs (défaut Fedora Workstation) + LUKS2
# full-disk. La phrase de passe est un placeholder : build-iso.sh refuse
# de construire tant qu'elle n'a pas été remplacée (iso/set-secrets.sh).
#
# NOTE SÉCURITÉ : la phrase LUKS figure en clair dans le kickstart, donc
# dans l'ISO. Traitez l'ISO comme un secret, et changez la phrase après le
# premier démarrage :
#   cryptsetup luksChangeKey /dev/<partition-luks>
autopart --type=btrfs --encrypted --luks-version=luks2 --passphrase=CHANGEME_LUKS_PASSPHRASE

# Le disque cible est DÉTECTÉ à l'installation (le plus gros disque) : un
# nom codé en dur (nvme0n1…) casserait sur Proxmox (vda), USB (sda), etc. —
# constaté au test n°2. Le %pre ci-dessous écrit la directive ignoredisk
# dans /tmp/fedoriri-ignoredisk.ks, et build-iso.sh ajoute
# « %include /tmp/fedoriri-ignoredisk.ks » au kickstart aplati APRÈS
# ksflatten et ksvalidator (qui ne savent pas résoudre un include créé à
# l'exécution). Anaconda, lui, exécute les %pre avant d'interpréter les
# directives : le fichier existera au bon moment.

%pre --erroronfail
# list-harddrives est fourni par anaconda : il liste les disques utilisables
# (média d'installation exclu) au format « nom taille_en_Mo ».
if command -v list-harddrives >/dev/null 2>&1; then
    DISK="$(list-harddrives | sort -k2 -rn | head -1 | cut -d' ' -f1)"
else
    DISK="$(lsblk -dno NAME,TYPE,SIZE -b | awk '$2=="disk"{print $3, $1}' | sort -rn | head -1 | cut -d' ' -f2)"
fi
if [ -z "$DISK" ]; then
    echo "fedoriri: aucun disque cible détecté" >&2
    exit 1
fi
echo "fedoriri: disque cible détecté : $DISK" > /dev/tty1 || true
echo "ignoredisk --only-use=$DISK" > /tmp/fedoriri-ignoredisk.ks

# --- Localisation du pool local de paquets --------------------------------
# Ne PAS adresser la source par label (inst.repo=hd:LABEL=…) : sur une clé
# USB écrite avec dd, l'ISO hybride expose le même label sur plusieurs nœuds
# (sda ET sda1) et le montage par label d'anaconda échoue — constaté sur le
# matériel réel (« Failed to mount the LABEL=… HDD boot source », qui rend
# l'installation interactive). On cherche donc /fedoriri/repo en montant les
# candidats, et on émet la commande `harddrive` avec le périphérique réel.
mkdir -p /tmp/fedoriri-src
SRCDEV=""
for d in $(lsblk -pnro NAME,TYPE | awk '$2=="rom" || $2=="part" || $2=="disk" {print $1}'); do
    [ -b "$d" ] || continue
    mount -o ro "$d" /tmp/fedoriri-src 2>/dev/null || continue
    if [ -d /tmp/fedoriri-src/fedoriri/repo/repodata ]; then
        SRCDEV="$d"
        umount /tmp/fedoriri-src
        break
    fi
    umount /tmp/fedoriri-src
done
if [ -n "$SRCDEV" ]; then
    echo "fedoriri: pool local trouvé sur $SRCDEV" > /dev/tty1 || true
    echo "harddrive --partition=$SRCDEV --dir=/fedoriri/repo" > /tmp/fedoriri-source.ks
else
    # Pas de pool (ex. build --skip-pool) : laisser anaconda choisir ses
    # dépôts réseau par défaut plutôt que d'échouer.
    echo "fedoriri: PAS de pool local — installation depuis le réseau" > /dev/tty1 || true
    : > /tmp/fedoriri-source.ks
fi
%end
