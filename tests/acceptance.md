# Tests d'acceptation

État au 2026-08-20. « Exécutable ici » = depuis l'environnement de
développement (macOS, sans VM Fedora ni matériel AMD) ; le reste exige une VM
ou le poste cible — la procédure est donnée pour chacun.

Tests 1 et 2 validés en réel sur l'infra du commanditaire (LXC Fedora 44 pour
le build, VM Proxmox OVMF pour l'installation). Tests 3–10 : à jouer dans la
session installée (phrase LUKS requise au boot, donc interactifs). 11 partiel
(revue), 12 non applicable tant que l'option A n'est pas déployée.

| # | Test | Bloquant | État | Comment (re)jouer |
|---|------|----------|------|-------------------|
| 1 | L'ISO se construit, checksum amont vérifié (GPG + sha256) | oui | **VALIDÉ** (2026-08-20, VM Fedora 44 aarch64, build croisé) : signature « Good signature from Fedora (44) », sha256 amont OK, pool de 1018 RPM, ISO finale 2,3 Go + .sha256 | `sudo ./iso/build-iso.sh` — échoue volontairement si CHECKSUM non signé ou sha256 faux |
| 2 | Installation non interactive complète en VM, LUKS compris | oui | **VALIDÉ** (2026-08-20, VM Proxmox OVMF + Secure Boot pré-enrôlé, x86_64). Preuves lues depuis l'hôte et la VM : `lsblk` = ESP 600M (`/boot/efi`) + `/boot` ext4 2G + LUKS2→btrfs (`/`, `/home`) ; header LUKS argon2id, 1 keyslot, **0 token, 0 keyfile**, cmdline sans `rd.luks.key` → phrase EXIGÉE au boot (« Please enter passphrase for disk luks-… ») ; installation sans aucune saisie, autologin `fedo`. Voir aussi le piège ksflatten/bootloader dans docs/limites.md | VM Proxmox : `bios=ovmf`, disque EFI, l'ISO en CD ; ou `virt-install … --cdrom iso/build/fedoriri-44-x86_64.iso`. Vérifier ESP + `crypto_LUKS` (`lsblk -f`) |
| 3 | Niri démarre, session utilisable au clavier | oui | **non exécuté ici** | dans la VM : tty1 → autologin → niri ; `Mod+Shift+Slash` affiche l'aide |
| 4 | xwayland-satellite tourne, xeyes s'affiche | oui | **non exécuté ici** | `journalctl --user -u niri -b \| grep "X11 socket"` puis `DISPLAY=:0 xeyes` (niri ≥ 25.08 le lance à la demande) |
| 5 | `WFICA_OPTS="-span h" wfica` liste les moniteurs | non (diagnostic) | **non exécuté ici** | après `install-citrix.sh`, sur le poste cible |
| 6 | Citrix plein écran mono-moniteur sans duplication/redimensionnement | oui | **non exécuté ici** | window-rule `open-fullscreen` posée ; valider visuellement sur le poste |
| 7 | Copier depuis Citrix → coller dans une app Wayland | oui | **non exécuté ici** | copier dans la session ICA, `wl-paste` dans un terminal ; comportement au changement de focus à documenter (cf. docs/limites.md) |
| 8 | Shadow démarre, /dev/uinput accessible, clavier/souris répondent | oui | **non exécuté ici** | `ls -l /dev/uinput` (groupe shadow-input, 0660), `id fedo` (groupes shadow-input,input), lancer Shadow |
| 9 | Alt+Tab et Super consommés par Shadow, pas par niri | oui | **non exécuté ici** | focus sur Shadow → `fedoriri-passthrough` bascule l'inhibition (vérif : `Mod+T` ne doit PLUS ouvrir btop) ; `Mod+Escape` = bascule manuelle |
| 10 | `vainfo` liste des profils H264 | oui | **non exécuté ici** | après premier boot (RPM Fusion + mesa-va-drivers-freeworld) : `vainfo \| grep H264` |
| 11 | Rejouer `post-install.sh` ne casse rien (idempotence) | oui | **partiel** : chaque étape a un garde d'état (relu en revue) ; à confirmer en VM | `sudo /opt/fedoriri/scripts/post-install.sh` deux fois de suite — la 2ᵉ passe ne doit rien retélécharger |
| 12 | Après un bump Qt, le shell Quickshell fonctionne toujours | oui (si option A) | **non applicable pour l'instant** (option A non déployée) | mécanisme livré : `fedoriri-quickshell-qt-guard.service` compare le tampon Qt et recompile ; test : `dnf upgrade qt6-qtbase` puis reboot |

## Exécuté ici (2026-08-20, macOS + réseau)

- `tests/run-local-checks.sh` : bash -n sur tous les scripts, py_compile,
  rendu des 22 thèmes × 8 templates sans jeton non résolu, équilibre du
  config.kdl — **vert**.
- Validation mdapi : les 55 paquets du kickstart et les 23 build-deps
  Quickshell existent dans Fedora 44 — **vert** (a détecté et corrigé
  3 noms invalides : mesa-va-drivers disparu de F44,
  google-noto-emoji-color-fonts et fontawesome-fonts mal orthographiés).
- Manifeste Shadow lu et parsé en réel (version 9.9.10457, sha512 présent).
- Page Citrix GCC 11 scrapée en réel : tarball x86_64 présent ; le lien signé
  est bien dans l'attribut `rel=` du HTML brut.
- `shellcheck` (0.11, brew) : propre en `-S warning` sur tous les scripts.
- `ksvalidator` (pykickstart via pip) : kickstart aplati validé sans erreur.
- Pas de CI hébergée (choix : pas de compte GitHub payant) — l'équivalent se
  rejoue localement, y compris dans un conteneur propre :
  `podman run --rm -v .:/src -w /src registry.fedoraproject.org/fedora:44 \
   bash -c "dnf install -y ShellCheck pykickstart python3 findutils && bash tests/run-local-checks.sh"`
