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

# --- Applications de base ---------------------------------------------------
nautilus
firefox

# --- Outillage requis par les scripts fedoriri ------------------------------
git-core
curl
openssl
bsdtar
desktop-file-utils
xdg-utils
python3
%end
