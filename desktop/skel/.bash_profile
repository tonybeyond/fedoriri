# .bash_profile fedoriri — connexion automatique sur tty1 → session niri.
# (façon Omarchy : pas de display manager ; LUKS fait l'authentification
# primaire au démarrage.)

[ -f ~/.bashrc ] && . ~/.bashrc

if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # niri est lancé DIRECTEMENT dans la session de login (pas via
    # niri-session) : niri-session délègue à une unité systemd --user
    # (niri.service, Type=notify) qui vit HORS de la session logind — sur ce
    # montage autologin, le service ne notifiait jamais « prêt » et la
    # session bouclait en silence (constaté sur VM ET matériel réel).
    # `niri --session` hérite ici de la session logind du login : prise de
    # seat directe, comportement identique, zéro dépendance aux unités user.
    #
    # Pas de exec : si niri s'arrête, on VOIT son erreur et on retombe sur
    # un shell — plus jamais d'écran figé muet ni de boucle d'autologin.
    mkdir -p "$HOME/.local/share/niri"
    niri --session 2>&1 | tee "$HOME/.local/share/niri/session.log"
    systemctl --user stop fedoriri-session.service 2>/dev/null || true
    echo ""
    echo "=== niri s'est arrêté. Journal : ~/.local/share/niri/session.log ==="
    echo "=== (dernières lignes ci-dessus ; shell de secours ci-dessous)    ==="
fi
