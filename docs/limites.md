# Limites connues et divergences assumées

Chaque point ci-dessous est une limite RÉELLE, documentée plutôt que
contournée en silence. « Vérifié » = constaté sur source primaire ;
« non testé » = à valider sur le poste cible.

## Niri vs Omarchy (modèle de fenêtrage)

- Niri est à **tuiles défilantes** (colonnes sur un ruban infini), Omarchy
  (Hyprland) à tuiles classiques. Les keybinds sont calqués quand la
  primitive existe (`Mod+1..9` workspaces, `Mod+W` fermer, `Mod+Return`
  terminal, `Mod+Space` lanceur…), mais la correspondance n'est pas forcée :
  `Mod+F` reste « maximiser la colonne » (niri), le gestionnaire de fichiers
  passe sur `Mod+E`.
- **Pas d'animations désactivables par fenêtre** : les window-rules niri ne
  le permettent pas (demandé par le brief pour Citrix). Les animations
  restent globales ; les désactiver entièrement : bloc `animations { off; }`.
- **Pas de « modes » de binds** : contrairement à ce que supposait le brief,
  le wiki niri (Configuration: Key Bindings, consulté le 2026-08-20) ne
  documente aucun système de modes à la sway. La neutralisation des
  raccourcis pour Citrix/Shadow passe par l'action
  `toggle-keyboard-shortcuts-inhibit` + le démon `fedoriri-passthrough`
  (event-stream). Limite : si l'utilisateur bascule aussi à la main
  (`Mod+Escape`), l'état du démon peut se décaler d'un cran — le même
  `Mod+Escape` (bind `allow-inhibiting=false`, donc toujours actif)
  resynchronise.

## Xwayland / xwayland-satellite

- **Vérifié (wiki niri, page Xwayland)** : depuis niri 25.08,
  xwayland-satellite est lancé **automatiquement à la demande** et `DISPLAY`
  est exporté par niri. Le brief demandait un `spawn-at-startup` manuel avec
  DISPLAY fixe : c'est devenu inutile, et le wiki recommande explicitement de
  retirer ce genre de personnalisation. Le paquet `xwayland-satellite` reste
  indispensable (niri n'a pas de Xwayland intégré).
- **xwayland-satellite est rootless uniquement**, et son issue #220 (relais
  de `keyboard-shortcuts-inhibit`) est ouverte : un `XGrabKeyboard` posé par
  Citrix ou Shadow ne remonte PAS au compositeur. D'où le démon
  `fedoriri-passthrough` (mitigation côté compositeur, pas côté client).

## Citrix

- **Ligne GCC 11 = Technical Preview**, en retard sur les correctifs de la
  stable (26.04.0.105 vs 26.04.10.1 au 2026-08-19). C'est le prix de
  l'installation propre sur Fedora 44 (webkit2gtk4.1 + libsoup3, pas de
  `rpm --nodeps`). À réévaluer quand Citrix sortira la ligne GCC 11 en GA.
- **libxml2** : Citrix est lié à `libxml2.so.2`. Fedora 44 (libxml2 2.12.10)
  le fournit ; si Fedora passe à libxml2 ≥ 2.15 (SONAME .so.16), Citrix
  casse. `install-citrix.sh` le vérifie et échoue avec un message clair.
- **Plein écran sur DEUX moniteurs : probablement impossible, NON TESTÉ.**
  Comme sous Hyprland, un client X11 via Xwayland rootless ne voit qu'une
  géométrie ; rien dans xwayland-satellite 0.8.x n'indique un spanning
  multi-sorties. À vérifier sur le poste avec
  `WFICA_OPTS="-span h" wfica` (liste des moniteurs vus). Repli fourni et
  pré-câblé dans `configs/citrix/wfclient.ini` : une session par moniteur
  (`WFICA_OPTS="-span 1"`, `UseFullScreen=False`, `TWIMode=0`).
  Le poste cible n'ayant qu'UN moniteur 4K, ce point n'est pas bloquant ici.
- **Presse-papiers au changement de focus** : sous Hyprland, Citrix perd la
  sélection quand aucun client X n'a le focus (comportement du XWM).
  Comportement de xwayland-satellite : NON TESTÉ ici — test n°7 à jouer sur
  le poste ; si la sélection se perd, copier PUIS coller sans refocuser une
  autre fenêtre X11 entre les deux.
- **setupwfc n'a pas de mode silencieux documenté** : l'installation est
  pilotée par stdin (séquence commentée dans `install-citrix.sh`). Si Citrix
  change ses invites, `install-citrix.sh --interactive`.

## Shadow

- Arbitrage groupe `input` : membre = mode LIBINPUT (souris précise, gestes
  2 doigts du pavé tactile HS) ; non membre = LEGACY (l'inverse). Défaut
  LIBINPUT (poste fixe) ; `install-shadow.sh --input-mode legacy` pour
  l'autre choix.
- GLIBC max exigée par le binaire : 2.30 (relevé amont) — aucun souci sur
  Fedora 44.
- Le sha512 du manifeste est vérifié à chaque installation ; l'URL « latest »
  n'est jamais utilisée pour le binaire (URL versionnée persistante).
- ShadowUSB : distribution amont en HTTP sans checksum → script séparé,
  optionnel, qui exige `--sha256` ou un `--insecure-ok` explicite.

## ISO / installation

- La phrase LUKS et le hash du mot de passe sont dans le kickstart, donc
  dans l'ISO : **traiter l'ISO comme un secret**, changer la phrase après
  installation (`cryptsetup luksChangeKey`). Le build refuse les
  placeholders non remplacés.
- L'installation efface le disque cible **sans confirmation** (c'est le but,
  mais il faut le savoir).
- Le pool local couvre la fermeture de dépendances du `%packages` ; un
  `dnf upgrade` ultérieur et le premier boot (Citrix, Shadow, RPM Fusion)
  exigent le réseau.
- **Build croisé** (hôte aarch64 → ISO x86_64, constaté sur VM UTM) : le
  contrôle « iso arch does not match the host arch » de mkksiso est
  neutralisé par build-iso.sh dans ce cas précis — c'est une simple
  comparaison du `.discinfo` avec `uname -m`, sans effet sur les opérations
  réelles (xorriso/mkefiboot/implantisomd5, toutes indépendantes de l'arch
  hôte ; l'amont marque lui-même ce contrôle d'un TODO). Sur hôte x86_64,
  mkksiso est appelé tel quel, contrôle inclus.
- **Build sans /dev/loop** (conteneur LXC) : `mkefiboot` ne peut pas tourner
  → `--skip-mkefiboot`. Constaté en réel : le grub.cfg CONTENU dans l'image
  El Torito UEFI est alors le menu amont sans `inst.ks` (il ne chaîne pas
  vers la config éditée de l'ISO) — tout boot UEFI perdait le kickstart,
  seul le boot BIOS restait automatisé. build-iso.sh patche donc l'image
  FAT embarquée avec mtools (sans loop ni montage), vérifie la présence
  d'`inst.ks` dans le résultat, et réimplante le md5 de média
  (`patch_embedded_efiboot`). Sur hôte avec loop, `mkefiboot` fait le
  travail normalement.

## VA-API

- `mesa-va-drivers` **n'existe plus dans Fedora 44** (constaté via mdapi le
  2026-08-20 — le brief le supposait encore présent). Le décodage H264/HEVC
  AMD vient exclusivement de RPM Fusion (`mesa-va-drivers-freeworld`),
  installé au premier boot. Sans réseau au premier boot, le test n°10
  échouera jusqu'à la prochaine exécution de `post-install.sh`.

## Piège pykickstart/ksflatten (cause racine des échecs de boot du test n°2)

`ksflatten` n'aplatit pas seulement les `%include` : il **matérialise les
défauts internes de pykickstart** pour les commandes absentes. Pour
`bootloader`, ce défaut est `--location=none`, qu'anaconda interprète comme
« ne pas installer de bootloader » (storage.log : « Bootloader is not
enabled, skipping ») → la partition EFI est jugée inutile et sautée, grub
n'est jamais installé, le système n'amorce ni en UEFI ni en BIOS. Prouvé le
2026-08-20 par reproduction instrumentée (installateur avec inst.sshd, logs
complets). Parades : commande `bootloader --location=mbr --timeout=1`
explicite dans 10-base.ks + garde-fou de build qui refuse un kickstart
aplati contenant `--location=none`.

## Rendu graphique en machine virtuelle (validation du 2026-08-21)

La session est démarrée par `~/.bash_profile` sur tty1 : `niri --session`
tourne DIRECTEMENT dans la session de login (l'ancien montage via
`niri-session`/unité systemd user bouclait en silence — corrigé), avec
journal dans `~/.local/share/niri/session.log`.

Validé en VM Proxmox (installation automatique complète, LUKS, autologin) :
une seule session de login, niri 26.04 démarre, config chargée, sockets
Wayland + X11 créés, toute la pile lancée (waybar, swaybg, mako, agent
polkit, cliphist, fedoriri-passthrough, swayidle), layout « French
(Switzerland) » actif, IPC `niri msg` fonctionnel.

LIMITE : dans une VM **sans accélération 3D** (Proxmox `vga: virtio` sans
VirGL, hôte sans GPU), niri ne peut créer aucune sortie :
`failed to initialize renderer […] software EGL renderers are skipped`
puis `no allocator available for device` — l'écran reste sur la console
(le compositeur tourne pourtant, visible en ssh). Ce n'est PAS un bug
fedoriri : niri refuse le rendu logiciel llvmpipe sur le backend tty. Pour
voir le bureau en VM il faut du VirGL (`vga: virtio-gl`, hôte avec GPU +
libgl1/libegl1). Sur matériel réel (GPU AMD, radeonsi = renderer matériel),
cette branche d'échec ne s'applique pas ; en cas de souci, lire
`~/.local/share/niri/session.log` depuis tty2 ou ssh.
