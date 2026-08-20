# 40-post.ks — %post minimal, délibérément.
#
# Ici : uniquement copier le payload fedoriri dans le système installé et
# armer le service de premier démarrage. Tout ce qui télécharge, compile ou
# démarre des services se passe au premier boot (voir scripts/first-boot.sh).

# --- Copie du payload depuis l'ISO (hors chroot) -----------------------------
%post --nochroot --erroronfail
set -eu
# mkksiso a ajouté le dossier fedoriri/ à la racine de l'ISO ; pendant
# l'installation, l'ISO est montée sous /run/install/repo.
SRC=""
for d in /run/install/repo/fedoriri /run/install/sources/mount-0000-cdrom/fedoriri; do
  [ -d "$d" ] && SRC="$d" && break
done
if [ -z "$SRC" ]; then
  echo "fedoriri: payload introuvable sur le média d'installation" >&2
  exit 1
fi
mkdir -p /mnt/sysimage/opt/fedoriri
cp -a "$SRC/payload/." /mnt/sysimage/opt/fedoriri/
%end

# --- Configuration dans le chroot -------------------------------------------
%post --erroronfail
set -eu

# Formats régionaux fr_CH (dates, nombres, monnaie, papier, mesures),
# langue d'affichage en_US — le kickstart `lang` ne sait poser que LANG.
cat > /etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
LC_TIME=fr_CH.UTF-8
LC_NUMERIC=fr_CH.UTF-8
LC_MONETARY=fr_CH.UTF-8
LC_PAPER=fr_CH.UTF-8
LC_MEASUREMENT=fr_CH.UTF-8
EOF

# /etc/skel : dotfiles du bureau (niri, waybar, fuzzel, mako, alacritty…),
# pour les comptes créés PLUS TARD.
cp -a /opt/fedoriri/desktop/skel/. /etc/skel/

# ⚠️ Anaconda traite la commande kickstart `user` PENDANT la configuration,
# AVANT le %post : le home de fedo a donc été peuplé depuis /etc/skel tel
# qu'il était à ce moment — SANS nos dotfiles, d'où un login qui tombait sur
# un shell nu au lieu de lancer niri (constaté au test n°3). On propage donc
# le skel aux comptes déjà créés.
for home in /home/*; do
  [ -d "$home" ] || continue
  u="$(basename "$home")"
  id "$u" >/dev/null 2>&1 || continue
  cp -a /etc/skel/. "$home/"
  chown -R "$u:$(id -gn "$u")" "$home"
done

# Rendre les scripts appelables.
chmod -R u+rwX,go+rX /opt/fedoriri
find /opt/fedoriri/scripts -name '*.sh' -exec chmod 0755 {} +
install -m 0755 /opt/fedoriri/scripts/fedoriri-theme-set    /usr/local/bin/fedoriri-theme-set
install -m 0755 /opt/fedoriri/scripts/fedoriri-passthrough  /usr/local/bin/fedoriri-passthrough
install -m 0755 /opt/fedoriri/scripts/render-theme.py       /usr/local/bin/fedoriri-render-theme

# Thèmes et templates au niveau système.
mkdir -p /usr/share/fedoriri
cp -a /opt/fedoriri/desktop/themes    /usr/share/fedoriri/themes
cp -a /opt/fedoriri/desktop/templates /usr/share/fedoriri/templates

# Service de premier démarrage (Citrix, Shadow, RPM Fusion, thèmes…).
install -m 0644 /opt/fedoriri/systemd/fedoriri-first-boot.service /etc/systemd/system/
systemctl enable fedoriri-first-boot.service

# Connexion automatique sur tty1 + lancement de niri par le profil bash
# (façon Omarchy : pas de display manager). Le disque est chiffré LUKS :
# la phrase de passe au boot fait office d'authentification primaire.
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin fedo --noclear - $TERM
EOF
%end
