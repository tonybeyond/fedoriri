# Configuration Citrix

- `wfclient.ini` : déployé dans `/etc/skel/.ICAClient/` (donc hérité par les
  nouveaux comptes). Contient, commenté, le repli multi-moniteurs
  (`UseFullScreen=False` + `TWIMode=0` + `WFICA_OPTS="-span 1"`) documenté
  dans `docs/limites.md`.
- `all-regions-keys.conf` : liste `Section/Clé=Valeur` appliquée à
  `$ICAROOT/config/All_Regions.ini` par `install-citrix.sh`. Vide par défaut
  (les valeurs livrées par Citrix sont saines) — on ne vendore PAS un
  `All_Regions.ini` complet : il change à chaque version du client et un
  fichier figé écraserait silencieusement les nouveautés de sécurité.

Diagnostic n°1 : `WFICA_OPTS="-span h" /opt/Citrix/ICAClient/wfica` liste les
moniteurs vus par Citrix.

Rappel : après CHAQUE mise à jour du client, `install-citrix.sh` doit être
rejoué (il relance `ctx_rehash`, sinon « SSL Error 61 »).
