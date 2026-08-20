# 20-partitioning.ks — disque entier, chiffré LUKS2.
#
# ⚠️ EFFACE LE DISQUE CIBLE SANS CONFIRMATION. C'est voulu : l'installation
# est non interactive. Ne démarrez pas cette ISO sur une machine dont vous
# voulez garder les données.

zerombr
ignoredisk --only-use=nvme0n1,sda
clearpart --all --initlabel --disklabel=gpt

# Partitionnement automatique Btrfs (défaut Fedora Workstation) + LUKS2
# full-disk. La phrase de passe est un placeholder : build-iso.sh refuse
# de construire tant qu'elle n'a pas été remplacée.
#
# NOTE SÉCURITÉ : la phrase LUKS figure en clair dans le kickstart, donc
# dans l'ISO. Traitez l'ISO comme un secret, et changez la phrase après le
# premier démarrage :
#   cryptsetup luksChangeKey /dev/<partition-luks>
autopart --type=btrfs --encrypted --luks-version=luks2 --passphrase=CHANGEME_LUKS_PASSPHRASE
