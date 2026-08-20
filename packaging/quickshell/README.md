# Quickshell (option A — préparé, non déployé par défaut)

## Pourquoi

Le shell d'Omarchy v4 (~33 000 lignes de QML) exige Quickshell ≥ 0.3.0
(`Quickshell.Networking`, `Quickshell.Services.Polkit`). Fedora 44 packe
0.2.1^git20260209 → **trop vieux**, il faut compiler depuis
[quickshell-mirror/quickshell](https://github.com/quickshell-mirror/quickshell).

## L'exigence ABI Qt (pas une suggestion)

Le BUILD.md amont : « Quickshell relies on private Qt APIs and MUST be rebuilt
against each Qt release or crashes via ABI mismatches will occur. »
Mécanisme livré (test d'acceptation n°12) :

- `build-quickshell.sh` pose un tampon (`/var/lib/fedoriri/quickshell.qt-version`
  = version-release de `qt6-qtbase` au moment du build) et garde la source en
  cache local (recompilation possible SANS réseau) ;
- `fedoriri-quickshell-qt-guard.service` (activé par
  `packaging/build-all.sh --with-quickshell`) compare le tampon à chaque
  démarrage et relance la compilation si Qt a changé.

## État du portage du shell Omarchy

L'ISO livre l'**option B** (waybar + fuzzel + mako + swaylock aux couleurs
Omarchy) : système utilisable de bout en bout, zéro compilation. L'option A
est la 2ᵉ phase :

1. `build-all.sh --with-quickshell` (ce dossier) — prêt ;
2. vendorer `omarchy/shell/` et écrire `shell/services/Compositor.qml`
   (~250 lignes) : singleton exposant l'API attendue par le shell, appuyé sur
   `Quickshell.WindowManager` (protocole ext-workspace-v1, implémenté par niri
   — `src/protocols/ext_workspace.rs`) + l'IPC `niri msg` ;
3. remplacer les imports `Quickshell.Hyprland` (5 fichiers) par ce singleton ;
4. basculer `spawn-at-startup waybar` → `spawn-at-startup quickshell` dans
   config.kdl.

Les étapes 2–4 ne bloquent pas l'ISO (décision validée : « B d'abord, puis A »).
