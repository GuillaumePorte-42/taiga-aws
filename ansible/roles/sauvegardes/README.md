# Rôle `sauvegardes`

Sauvegarde chaque jour la **base de production** (RDS) et les **médias** (EFS) dans le bucket `taiga-ledevagilles-backups`. Lancé par `playbooks/sauvegardes.yml` sur les 3 nœuds de production (`role_swarm_node`). Ticket PFD-82 (PFD-24).

## Comment ça marche
```
cron (3 nœuds ; 16 h en production) → taiga-sauvegarde : « suis-je le leader Swarm ? »
   non → journal « pas le leader : rien à faire », fin
   oui → pg_dump (conteneur PostgreSQL 17) → taiga-<date>.dump    → s3://…/postgres/
         tar du dossier media de l'EFS      → media-<date>.tar.gz → s3://…/media/
         fichiers locaux supprimés, métrique écrite, journal « OK … »
```
- **Un seul nœud sauvegarde** : la base et l'EFS sont partagés. Le cron est sur les 3 nœuds : si le leader tombe, un autre le devient et la sauvegarde continue (prouvé le 03/11 : après la bascule du test de haute disponibilité, l'ancien leader répond « pas le leader », le nouveau sauvegarde).
- **`pg_dump` dans un conteneur** : il doit être au moins de la version du serveur (RDS 17.9) ; Ubuntu 24.04 ne fournit que le client 16. Le conteneur prête le programme puis s'efface (`--rm`).
- **Droits** : rôle IAM `taiga-ec2-production` (`terraform/commun/iam.tf`) : lister, déposer, relire sous `postgres/` et `media/`, **aucune suppression**. Le ménage est fait par le cycle de vie du bucket (90 jours, `terraform/socle/backups.tf`).
- **Réseau** : S3 par l'endpoint Gateway (sans la NAT) ; la RDS en TLS (`PGSSLMODE=require`).

## Ce qu'il pose sur chaque nœud
| Quoi | Où | Détail |
|---|---|---|
| AWS CLI v2 | `/usr/local/bin/aws` | installeur officiel, version figée ; réinstallée seulement si la version change |
| Mot de passe de la base | `/root/.pgpass` (`0600`) | lu dans Parameter Store (`taiga_secrets.postgres_password`), `no_log` |
| Dossier de travail | `/var/backups/taiga` (`0700`) | vide après chaque sauvegarde réussie |
| Script | `/usr/local/sbin/taiga-sauvegarde` (`0700`) | template `templates/sauvegarde.sh.j2` |
| Cron | crontab de root | chaque nuit à `sauvegardes_cron_heure`:`sauvegardes_cron_minute` (heure de Paris) |
| Métrique | `/var/lib/node_exporter/textfile/sauvegarde.prom` | heure de la dernière réussite (`taiga_sauvegarde_derniere_reussite_timestamp_seconds`), lue par node_exporter ; alerte `SauvegardeTropVieille` au-delà de 26 h (PFD-36) |

## Variables (`defaults/main.yml`)
| Variable | Défaut | Rôle |
|---|---|---|
| `sauvegardes_bucket` | `taiga-ledevagilles-backups` | bucket (output `backups_bucket` de `terraform/socle`) |
| `sauvegardes_prefixe_base`, `sauvegardes_prefixe_media` | `postgres`, `media` | préfixes autorisés par le rôle IAM |
| `sauvegardes_postgres_base`, `…_utilisateur`, `…_port` | `taiga`, `taiga`, `5432` | comme `roles/taiga/templates/back.env.j2` |
| `sauvegardes_dossier_media` | `/mnt/efs/taiga/media` | médias de Taiga sur l'EFS |
| `sauvegardes_dossier_travail` | `/var/backups/taiga` | fichiers avant l'envoi |
| `sauvegardes_image_postgres` | `{{ image_postgres }}` | image du projet (`playbooks/group_vars/all.yml`) |
| `sauvegardes_awscli_version` | `2.39.3` | voir `docs/reference/versions_outils.md` |
| `sauvegardes_cron_heure`, `sauvegardes_cron_minute` | `3`, `0` | heure de la sauvegarde ; **16 h en production** (`inventories/production/group_vars/all.yml` : nœuds éteints la nuit), 3 h reste le bon défaut pour une prod allumée en continu |
| `sauvegardes_dossier_metriques` | `/var/lib/node_exporter/textfile` | dossier du collecteur textfile |

Viennent d'ailleurs : `taiga_postgres_hote` (`playbooks/group_vars/role_swarm_node.yml`), `taiga_secrets` et `aws_region` (`inventories/production/group_vars/all.yml`).

## L'utiliser
Mise en place, vérifications et dépannage : `docs/runbooks/5-donnees/sauvegarder_restaurer.md`.

## Pièges
- **Le code de sortie `0` ne prouve pas qu'une sauvegarde a eu lieu** : le script sort aussi en `0` quand le nœud n'est pas le leader. Ce qui fait foi : la ligne `OK` du journal (`journalctl -t taiga-sauvegarde`).
- Dans le template, `{{ .ManagerStatus.Leader }}` (syntaxe Docker) est protégé par `{% raw %}` : sans lui, Jinja essaie de le remplacer.
- Le PATH du cron ne contient pas `/usr/local/bin` : le script appelle `aws` par son chemin complet.
- `--check` échoue à l'installation de la CLI : en simulation, la tâche `command` « Lire la version » n'est pas lancée, donc le bloc d'installation croit la CLI absente, et le `.zip` n'est pas téléchargé. Piste : `check_mode: false` sur cette tâche (elle ne fait que lire). En attendant : lancer sur un nœud avec `--limit`.
- Un `pg_dump` plus ancien que le serveur refuse de travailler : si la RDS passe en 18, changer `image_postgres`.
- La métrique est lue par node_exporter (`--collector.textfile.directory` dans son service, rôle `common`) et surveillée par l'alerte `SauvegardeTropVieille` (rôle `supervision`). Le script écrit encore une **ancienne** métrique en double (`taiga_sauvegarde.prom`, nom sans `_seconds`) que rien ne lit : ménage à faire dans `templates/sauvegarde.sh.j2` (garder le bloc de fin, `_seconds`).
- Le cron suit l'heure de la machine : **heure de Paris** (le rôle `common` règle `Europe/Paris`). Les noms des fichiers, eux, sont en UTC (`date -u`, avec le `Z` final).
- **Reconstruction** : `sauvegardes.yml` doit être rejoué sur les nœuds neufs (il est dans l'ordre de `ansible/README.md` depuis le 04/11 ; il y manquait). Sauvegarde manuelle avant une opération : `ansible -i inventories/production/aws_ec2.yml role_swarm_node -b -m command -a /usr/local/sbin/taiga-sauvegarde`, puis `aws s3 ls`.
