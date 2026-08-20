# fedoriri

ISO **Fedora 44** installable et entièrement automatisée : bureau **Niri**
(compositeur Wayland à tuiles défilantes), workflow et esthétique calqués sur
**Omarchy 4** (thèmes repris tels quels), avec **Citrix Workspace App** et le
client **Shadow.tech** comme prérequis durs.

```
ISO netinst Fedora vérifiée (GPG+sha256)
   └─ mkksiso : kickstart non interactif + pool local de RPM + payload
        └─ installation sans réseau (LUKS2, clavier ch-fr, user fedo, niri)
             └─ 1er boot : fedoriri-first-boot.service (console visible)
                  ├─ RPM Fusion + mesa-va-drivers-freeworld (VA-API H264, AMD)
                  ├─ starship (GitHub, sha256 vérifié)
                  ├─ Citrix GCC 11 (scrape + sha256 + ctx_rehash)
                  ├─ Shadow AppImage (manifeste + sha512 + uinput/udev)
                  └─ thème Omarchy par défaut (tokyo-night)
```

## Construction

Voir [iso/README.md](iso/README.md). Résumé :

```bash
openssl passwd -6 'mot-de-passe'   # → remplacer les 2 placeholders CHANGEME_*
./iso/build-iso.sh                 # sur Fedora 44 (ou --podman ailleurs)
```

Le build **refuse** de partir si les placeholders (hash utilisateur, phrase
LUKS) n'ont pas été remplacés, si la signature GPG Fedora du CHECKSUM est
invalide, ou si le sha256 de l'ISO amont ne correspond pas.

## Décisions structurantes (et leur pourquoi)

| Décision | Pourquoi |
|---|---|
| Voie kickstart : netinst officielle + `mkksiso` (lorax), pas d'ISO live recomposée | anaconda ne consomme pas de kickstart en mode live ; `inst.ks` au menu de boot est LE mécanisme officiel d'installation non interactive — détail dans [iso/README.md](iso/README.md) |
| Barre/shell : **option B d'abord** (waybar+fuzzel+mako+swaylock aux couleurs Omarchy), option A (shell Quickshell) préparée | système utilisable de bout en bout sans compilation ; le portage QML (~24 k lignes) ne bloque pas l'ISO — plan dans [packaging/quickshell/README.md](packaging/quickshell/README.md) |
| Citrix ligne **GCC 11** (Technical Preview) | la stable exige webkit2gtk-4.0/libsoup-2.4, absents de Fedora 44 ; la TP se lie à webkit2gtk4.1/libsoup3 → installation propre, sans `rpm --nodeps`. Compromis (retard de correctifs) documenté |
| Travail lourd au **premier boot**, pas dans `%post` | dnf interactif sans TTY, services non démarrables en chroot, compositeur absent ; unité oneshot avec témoin, sortie console, attente réseau par curl |
| Versions **jamais figées dans les URL** | Shadow : manifeste `latest-linux.yml` → URL versionnée + sha512 ; Citrix : scrape (jeton Akamai ~1 h) ; starship/quickshell : dernière release résolue par API/tags |
| Validation des noms de paquets contre **mdapi** = livrable ([scripts/validate-packages.sh](scripts/validate-packages.sh)) | dnf est atomique : un nom invalide fait tout échouer. La CI la rejoue à chaque push |
| Pas de display manager : autologin tty1 → `niri-session` | façon Omarchy ; LUKS fait l'authentification primaire au démarrage |

## Vérifié / non vérifié

**Vérifié le 2026-08-20 (sources primaires)** :

- mdapi f44 : niri 26.04, xwayland-satellite 0.8.2, libxml2 2.12.10,
  quickshell 0.2.1^git20260209 (trop vieux, comme prévu) ; les 55 paquets du
  kickstart et 23 build-deps Quickshell existent tous.
- La validation mdapi a **corrigé trois erreurs** qui auraient cassé
  l'installation : `mesa-va-drivers` n'existe plus dans F44, et deux noms de
  polices étaient faux. Le garde-fou fait exactement ce pour quoi il existe.
- Wiki niri : depuis 25.08, **xwayland-satellite est lancé automatiquement**
  par niri (DISPLAY exporté) — le `spawn-at-startup` manuel du brief est
  devenu contre-indiqué. Et niri n'a **pas de modes de binds** ; la
  neutralisation des raccourcis pour Citrix/Shadow passe par
  `toggle-keyboard-shortcuts-inhibit` + le démon
  [fedoriri-passthrough](scripts/fedoriri-passthrough).
- Manifeste Shadow lu en réel (9.9.10457, sha512 base64) ; page Citrix GCC 11
  scrapée en réel (lien signé dans l'attribut `rel=` du HTML brut).
- Rendu des 22 thèmes Omarchy × 8 templates : zéro jeton non résolu
  (`tests/run-local-checks.sh`).

**Non vérifié ici** (pas de VM Fedora ni de matériel AMD dans l'environnement
de dev) : l'installation de bout en bout, tout ce qui touche l'affichage et
l'entrée (tests 2–10). Chaque test a sa procédure dans
[tests/acceptance.md](tests/acceptance.md) ; les limites connues (multi-moniteur
Citrix, presse-papiers, TP GCC 11…) sont dans [docs/limites.md](docs/limites.md).
Aucun « ça devrait marcher » sans scénario de test associé.

## Arborescence

```
iso/            kickstart (base, partitionnement LUKS, paquets, post) + build-iso.sh
scripts/        post-install (orchestrateur), install-citrix, install-shadow,
                install-shadowusb (opt.), first-boot, validate-packages,
                fedoriri-theme-set, fedoriri-passthrough, render-theme.py
systemd/        fedoriri-first-boot.service
desktop/        config.kdl (niri), waybar, templates de thème, 22 thèmes
                Omarchy (colors.toml), /etc/skel
packaging/      starship (installeur vérifié), quickshell (option A + garde ABI Qt)
configs/citrix/ wfclient.ini (+ repli multi-moniteurs), clés All_Regions
tests/          run-local-checks.sh (CI) + acceptance.md (matrice complète)
docs/           limites.md — à lire avant de déployer
```

## Utilisation quotidienne

- `Mod+Shift+Slash` : aperçu des raccourcis. `Mod+Return` terminal,
  `Mod+Space` lanceur, `Mod+W` fermer, `Mod+1..9` workspaces.
- `Mod+Escape` : bascule manuelle des raccourcis (Citrix/Shadow) — le démon
  `fedoriri-passthrough` le fait automatiquement au focus.
- `fedoriri-theme-set --list` / `<thème>` / `--next` (aussi `Mod+Y`).
- Rejouer la post-installation : `sudo /opt/fedoriri/scripts/post-install.sh`
  (idempotent ; `--dry-run` pour voir sans faire).

## Licences

Projet sous MIT. Les thèmes (`desktop/themes/`) et trois templates
(`alacritty.toml.tpl`, `foot.ini.tpl`, `btop.theme.tpl`) proviennent
d'[Omarchy](https://github.com/basecamp/omarchy) v4.0.0 (MIT,
© David Heinemeier Hansson).
