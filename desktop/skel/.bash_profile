# .bash_profile fedoriri — connexion automatique sur tty1 → session niri.
# (façon Omarchy : pas de display manager ; LUKS fait l'authentification
# primaire au démarrage.)

[ -f ~/.bashrc ] && . ~/.bashrc

if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # niri-session est fourni par le paquet niri : session systemd complète
    # (portails, dbus-update-activation-environment, etc.).
    exec niri-session
fi
