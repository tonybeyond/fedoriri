# 30-packages.ks — cœur du bureau, installé HORS LIGNE depuis le pool
# de paquets embarqué dans l'ISO (voir build-iso.sh).
#
# RÈGLE : chaque nom de ce fichier doit exister dans l'index Fedora 44.
# scripts/validate-packages.sh interroge mdapi.fedoraproject.org et fait
# échouer le build si un nom est invalide (dnf est atomique : un seul nom
# faux ferait échouer toute la transaction).
#
# Ce qui n'est PAS ici (et pourquoi) :
#   - Citrix, Shadow : binaires propriétaires téléchargés au premier boot.
#   - starship : absent de Fedora → packaging/starship/.
#   - quickshell : version Fedora trop vieille → packaging/quickshell/ (option A).
#   - mesa-va-drivers-freeworld (H264/HEVC) : RPM Fusion, ajouté au premier boot.

%packages
@standard
@hardware-support

# --- Noyau, bootloader, langues ---------------------------------------------
# Anaconda ajoute ces paquets LUI-MÊME à la transaction (ils ne viennent ni
# de @core ni du reste de la liste) : sans eux dans le pool local, une
# installation hors ligne échoue avec « No match for argument: grub2-efi-x64,
# shim-x64, … » — constaté au test n°2. Les déclarer ici les fait entrer
# dans la fermeture de dépendances du pool.
kernel
linux-firmware
grub2-pc
grub2-pc-modules
grub2-efi-x64
shim-x64
efibootmgr
grub2-tools
grub2-tools-extra
grubby
# glibc-langpack-* : exigés par la conf locale (lang en_US + formats fr_CH).
glibc-langpack-en
glibc-langpack-fr

# --- Compositeur et session -------------------------------------------------
niri
# niri >= 25.08 lance xwayland-satellite automatiquement (à la demande) s'il
# est dans le PATH — indispensable pour Citrix et Shadow (clients X11).
xwayland-satellite

# --- Barre, lanceur, notifications, verrouillage (option B) -----------------
waybar
fuzzel
mako
swaybg
swayidle
swaylock
wlogout

# --- Terminaux --------------------------------------------------------------
alacritty
foot

# --- Presse-papiers et captures ---------------------------------------------
wl-clipboard
cliphist
grim
slurp
swappy

# --- Portails, agents, secrets ----------------------------------------------
xdg-desktop-portal-gtk
xdg-desktop-portal-gnome
mate-polkit
gnome-keyring
gnome-keyring-pam

# --- Audio / média / matériel -----------------------------------------------
pipewire
wireplumber
pamixer
playerctl
brightnessctl
bluez

# --- Vidéo : VA-API (test d'acceptation n°10) -------------------------------
# mesa-va-drivers n'existe PLUS dans Fedora 44 (vérifié via mdapi : 400) —
# Fedora avait déjà retiré H264/HEVC de mesa, le sous-paquet a disparu.
# Le pilote VA-API AMD vient de RPM Fusion (mesa-va-drivers-freeworld),
# installé au premier boot. libva-utils fournit vainfo pour le test.
mesa-dri-drivers
# AppImage Shadow : libfuse.so.2 (fuse3 seul ne suffit pas — constaté sur matériel).
fuse-libs
# Déballage du .deb officiel Claude Desktop (archive ar).
bsdtar
libva-utils

# --- AppImage (Shadow) ------------------------------------------------------
# fuse (v2) fournit libfuse.so.2, exigé par le runtime AppImage.
fuse

# --- CLI « Omarchy-like » ---------------------------------------------------
zoxide
eza
bat
fd-find
ripgrep
fzf
btop
fastfetch
neovim
jq

# --- Theming ----------------------------------------------------------------
matugen
papirus-icon-theme
jetbrains-mono-fonts
google-noto-sans-fonts
google-noto-color-emoji-fonts
fontawesome-6-free-fonts
# Police Nerd empaquetée par Fedora : icônes de waybar (zone d'usage privé).
cascadia-mono-nf-fonts

# --- Applications de base ---------------------------------------------------
nautilus
# (navigateur : Brave Origin, dépôt officiel Brave au premier boot — install-brave.sh)

# --- Outillage requis par les scripts fedoriri ------------------------------
git-core
curl
openssl
bsdtar
desktop-file-utils
xdg-utils
python3
%end
