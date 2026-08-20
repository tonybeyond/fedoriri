# Construction de l'ISO

## Choix : kickstart + outillage lorax (et pourquoi pas les alternatives)

Le brief proposait « kickstart + livemedia-creator » ou « osbuild ». Implémenté :
la **voie kickstart**, mais avec `mkksiso` (fourni par lorax, même boîte à
outils que livemedia-creator) sur l'ISO **Everything netinst** officielle,
plutôt qu'une ISO live composée par livemedia-creator. Raisons :

1. L'exigence n°1 est une **installation non interactive** : une ISO live
   démarre un bureau et attend que l'utilisateur clique sur « Installer » —
   anaconda ne consomme pas de kickstart en mode live. La netinst + `inst.ks`
   au menu de boot (ce que fait `mkksiso`) est le mécanisme officiel et
   documenté de l'installation automatisée Fedora.
2. L'ISO amont est **vérifiée** (signature GPG Fedora du fichier CHECKSUM,
   puis sha256) au lieu d'être recomposée : moins de surface d'erreur, build
   beaucoup plus court, et l'exigence « vérifier l'ISO amont » est structurelle.
3. Le **pool local** (fermeture complète de dépendances du `%packages`,
   calculée dans un installroot vide) est embarqué dans l'ISO et déclaré via
   `inst.repo=hd:LABEL=…:/fedoriri/repo` : le cœur du bureau s'installe sans
   réseau.

osbuild/image-builder a été écarté : ses blueprints TOML ne couvrent ni le
`%post --nochroot` (copie du payload), ni l'injection d'un dépôt local dans
une ISO d'installation, sans tordre l'outil.

## Utilisation

```bash
# 1. Remplacer les placeholders (le build REFUSE sinon) :
#    - hash du mot de passe :
openssl passwd -6 'votre-mot-de-passe'
#      → coller dans includes/10-base.ks (CHANGEME_PASSWORD_HASH_SHA512)
#    - phrase LUKS : includes/20-partitioning.ks (CHANGEME_LUKS_PASSPHRASE)

# 2. Construire (sur Fedora 44) :
./build-iso.sh
#    ou depuis un autre OS avec podman :
./build-iso.sh --podman

# 3. Résultat : build/fedoriri-44-x86_64.iso (+ .sha256)
```

`--skip-pool` accélère les itérations (pas de pool local : l'installation
exigera alors le réseau).

## Test en VM (test d'acceptation n°2)

```bash
virt-install --name fedoriri --memory 4096 --vcpus 4 \
  --disk size=40 --cdrom build/fedoriri-44-x86_64.iso \
  --os-variant fedora-unknown
```

Attendu : installation sans aucune interaction, reboot, invite LUKS, autologin
`fedo` sur tty1, session niri. Puis `fedoriri-first-boot.service` (progression
visible sur la console) installe Citrix, Shadow et RPM Fusion.

## Sécurité

- L'ISO contient la phrase LUKS et le hash du mot de passe : **ne pas la
  publier**, changer la phrase après installation (`cryptsetup luksChangeKey`).
- L'ISO amont est refusée si la signature GPG du CHECKSUM ou le sha256 ne
  correspondent pas.
