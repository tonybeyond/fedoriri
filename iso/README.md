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

### 1. Poser les secrets

Le kickstart contient deux placeholders, et `build-iso.sh` **refuse de
construire** tant qu'ils sont en place. Le plus simple :

```bash
./set-secrets.sh
```

(interactif, sans écho). Ce qu'il remplit, si vous préférez le faire à la
main :

| Placeholder | Fichier | Contenu attendu |
|---|---|---|
| `CHANGEME_PASSWORD_HASH_SHA512` | `includes/10-base.ks` | le **hash** du mot de passe de `fedo`, produit par `openssl passwd -6` (jamais le mot de passe en clair : la ligne `user --iscrypted` attend un hash) |
| `CHANGEME_LUKS_PASSPHRASE` | `includes/20-partitioning.ks` | la phrase LUKS **en clair** (pas un hash) — anaconda s'en sert pour chiffrer le disque ; c'est elle qui sera demandée à chaque démarrage |

Ne commitez jamais ces fichiers une fois remplis
(`git restore iso/includes/` pour revenir aux placeholders).

### 2. Construire

Sur Fedora 44 (VM aarch64 acceptée : rien d'x86 n'est exécuté au build) :

```bash
sudo ./build-iso.sh
```

Depuis un autre OS, sans VM Fedora :

```bash
./build-iso.sh --podman
```

Options utiles : `--skip-pool` accélère les itérations en sautant le pool
local de RPM (l'installation exigera alors le réseau) ; `--dry-run` montre
les commandes sans les exécuter.

### 3. Résultat

`build/fedoriri-44-x86_64.iso` + son `.sha256`. Compter ~25 Go d'espace de
travail et le téléchargement de la netinst (~800 Mo) + ~3 Go de RPM.

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
