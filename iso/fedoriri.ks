# fedoriri.ks — kickstart principal, Fedora 44 + Niri.
#
# Ce fichier est aplati (ksflatten) puis injecté dans l'ISO netinst par
# iso/build-iso.sh via mkksiso, qui ajoute inst.ks au menu de démarrage :
# l'installation est entièrement non interactive.
#
# Le travail lourd (Citrix, Shadow, thèmes) N'EST PAS ici : il est fait au
# premier démarrage par fedoriri-first-boot.service (voir scripts/), parce
# que le %post s'exécute en chroot sans TTY interactif, sans services
# démarrables et sans compositeur.

%include includes/10-base.ks
%include includes/20-partitioning.ks
%include includes/30-packages.ks
%include includes/40-post.ks
