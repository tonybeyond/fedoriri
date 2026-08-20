# 10-base.ks — langue, clavier, réseau, utilisateur, services.

# Installation en mode texte : aucune interface graphique nécessaire,
# et c'est plus robuste en VM comme sur métal.
text

# Locale principale en_US.UTF-8 ; les formats fr_CH (dates, nombres,
# monnaie, papier) sont posés dans le %post — le kickstart ne sait
# exprimer que LANG.
lang en_US.UTF-8

# Clavier Suisse romand, pour la console ET le graphique.
keyboard --xlayouts='ch (fr)' --vckeymap=ch-fr

timezone Europe/Zurich --utc

network --bootproto=dhcp --device=link --activate --onboot=yes --hostname=fedoriri

# Bootloader EXPLICITE — ne jamais retirer cette ligne. Piège vérifié :
# si la commande est absente, ksflatten matérialise le défaut interne de
# pykickstart, « bootloader --location=none », qu'anaconda interprète comme
# « ne pas installer de bootloader » → pas de partition EFI, pas de grub,
# système non amorçable (cause racine des échecs de boot du test n°2,
# prouvée dans storage.log : « Bootloader is not enabled, skipping »).
# --location=mbr = emplacement par défaut (anaconda choisit ESP en UEFI).
bootloader --location=mbr --timeout=1

# Compte root verrouillé : tout passe par sudo (groupe wheel).
rootpw --lock

# GARDE-FOU : ce hash est un placeholder. iso/build-iso.sh refuse de
# construire tant qu'il n'a pas été remplacé par un vrai hash produit par :
#   openssl passwd -6 'votre-mot-de-passe'
user --name=fedo --groups=wheel --iscrypted --password=CHANGEME_PASSWORD_HASH_SHA512

# Pas d'assistant gnome-initial-setup au premier démarrage : la machine
# est déjà entièrement configurée par kickstart + first-boot.
firstboot --disable

# SELinux enforcing (défaut Fedora) — on ne le désactive pas.
selinux --enforcing

# Le service de premier démarrage est installé et activé dans le %post ;
# on active ici ce qui est packagé.
services --enabled=NetworkManager,sshd

# Redémarre en éjectant le média une fois l'installation terminée.
reboot --eject
