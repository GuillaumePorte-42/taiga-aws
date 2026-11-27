# Runbook – Sauvegardes de la production (base + médias)

**Pourquoi** : mettre en place, vérifier et dépanner la sauvegarde nuitière de la production vers S3. Fonctionnement et choix : `ansible/roles/sauvegardes/README.md`.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, `staging` à jour, agent SSH chargé (`eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion`), config SSH à jour (`docs/runbooks/1-equipe/se_connecter_ssh.md`). **Prévenir l'équipe** avant un `apply` ou un playbook sur la production.

## Ce qui doit être allumé
| Pour… | Il faut |
|---|---|
| appliquer les droits IAM | rien (API AWS seulement) |
| lancer le playbook | bastion + 3 nœuds + **NAT** (téléchargement de la CLI et de l'image) |
| faire une sauvegarde | en plus la **RDS** `available` ; pas besoin de l'ALB |

## 1. Les droits (Terraform, une fois)
Dans l'ordre : `commun/` crée le profil, `production/` le fait porter aux nœuds.
```bash
terraform -chdir=terraform/commun plan
terraform -chdir=terraform/production plan
```
Attendu : rôle et profil `taiga-ec2-production` déjà présents (`No changes` pour eux) ; dans `production/`, un changement de profil est un **update in-place** (`taiga-ec2-base` → `taiga-ec2-production`). Un `must be replaced` sur un nœud → on s'arrête.

Vérifier sans se connecter :
```bash
aws ec2 describe-iam-instance-profile-associations --region eu-west-3 --query 'IamInstanceProfileAssociations[].[InstanceId,IamInstanceProfile.Arn,State]' --output table
```
Attendu : les 3 nœuds sur `taiga-ec2-production`, `associated` (`associating` tant qu'une instance est arrêtée).

## 2. Déployer le rôle (Ansible)
Depuis `ansible/`. D'abord un seul nœud, puis les 3 :
```bash
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/sauvegardes.yml --limit taiga-node-1
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/sauvegardes.yml
```
Attendu : `failed=0`. Relancé une 2e fois : `changed=0` partout (le rôle est idempotent). Pas de `--check` : la simulation échoue à l'installation de la CLI.

## 3. Vérifier
```bash
# La CLI utilise le rôle du nœud (attendu : assumed-role/taiga-ec2-production/i-…)
ssh node-1 'aws --version; aws sts get-caller-identity'

# Qui est le leader (attendu : true sur un seul nœud)
ssh node-1 "sudo docker node inspect self --format '{{ .ManagerStatus.Leader }}'"

# Le cron est posé (attendu : une ligne #Ansible: taiga-sauvegarde)
ssh node-1 'sudo crontab -l'
```

## 4. Lancer une sauvegarde à la main
Utile avant une opération risquée (mise à jour, restauration, **reconstruction**) ou pour une démo. C'est **le même script** que celui du cron (16 h en production : `sauvegardes_cron_heure` dans `ansible/inventories/production/group_vars/all.yml`, les nœuds étant éteints la nuit).

**1. Trouver le leader** (le script ne sauvegarde que sur lui) :
```bash
for n in node-1 node-2 node-3; do echo -n "$n : "; ssh $n "sudo docker node inspect self --format '{{ .ManagerStatus.Leader }}'"; done
```
Attendu : `true` sur un seul nœud.

**2. Lancer la sauvegarde et lire le compte rendu** (remplacer `node-1` par le leader) :
```bash
ssh node-1 'sudo /usr/local/sbin/taiga-sauvegarde; sudo journalctl -t taiga-sauvegarde --since "5 minutes ago"'
```
- la 1re commande **fait** la sauvegarde ; le `;` enchaîne la 2e quoi qu'il arrive ;
- `journalctl -t taiga-sauvegarde` **relit** la ligne écrite par le script (`logger`).

Attendu : `OK taiga-<date>.dump media-<date>.tar.gz` (date en UTC). **Le code de sortie seul ne suffit pas** : il vaut aussi `0` sur un nœud qui n'est pas le leader (`pas le leader : rien à faire`).

**3. Voir les fichiers dans S3** : étape 5. Les deux fichiers portent la date de la ligne `OK`.

## 5. Voir les sauvegardes
```bash
ssh node-1 '/usr/local/bin/aws s3 ls s3://taiga-ledevagilles-backups/postgres/ --region eu-west-3; /usr/local/bin/aws s3 ls s3://taiga-ledevagilles-backups/media/ --region eu-west-3'
```
Un `media-….tar.gz` de 133 octets = archive vide (aucune pièce jointe dans Taiga) : normal sur une production sans données.

Heure de la dernière réussite (sur le leader) :
```bash
ssh node-1 'date -d @$(cut -d" " -f2 /var/lib/node_exporter/textfile/taiga_sauvegarde.prom)'
```

Preuve du moindre privilège (attendu : `AccessDenied … DeleteObject`) :
```bash
ssh node-1 '/usr/local/bin/aws s3 rm s3://taiga-ledevagilles-backups/postgres/<un-fichier>.dump --region eu-west-3'
```

## 6. Restaurer
Testé le 02/11/2026 en production : une user story avec une image, sauvegardée, supprimée dans Taiga (Taiga efface aussi le fichier sur l'EFS), puis restaurée : la carte et l'image sont revenues.

⚠️ **Restaurer, c'est revenir dans le passé pour tout** : la base revient à l'heure de la sauvegarde, et tout ce qui a été créé après disparaît (comptes compris). **Prévenir l'équipe** : Taiga est coupé quelques minutes, aucun déploiement pendant ce temps.

Tout se fait sur le **leader**, dans une session SSH (`ssh node-1`). Remplacer `<DATE>` par la date de la sauvegarde choisie (`aws s3 ls`, étape 5).

**1. Récupérer les fichiers** (vérifie aussi le droit `GetObject`)
```bash
sudo /usr/local/bin/aws s3 cp s3://taiga-ledevagilles-backups/postgres/taiga-<DATE>.dump /var/backups/taiga/ --region eu-west-3
sudo /usr/local/bin/aws s3 cp s3://taiga-ledevagilles-backups/media/media-<DATE>.tar.gz /var/backups/taiga/ --region eu-west-3
sudo ls -l /var/backups/taiga/
```
Attendu : les mêmes tailles que dans S3.

**2. Arrêter ce qui écrit dans la base** : noter d'abord les répliques (`REPLICAS`), pour les remettre à la fin.
```bash
sudo docker service ls
sudo docker service scale taiga_taiga-back=0 taiga_taiga-async=0
```
Attendu : back et async en `0/0` ; les autres services restent allumés.

**3. Restaurer la base**
```bash
HOTE=$(sudo cut -d: -f1 /root/.pgpass)
sudo docker run --rm -v /root/.pgpass:/root/.pgpass:ro -v /var/backups/taiga:/sauvegarde -e PGSSLMODE=require postgres:17.11-trixie pg_restore -h "$HOTE" -p 5432 -U taiga -d taiga --clean --if-exists --no-owner --no-privileges --no-password /sauvegarde/taiga-<DATE>.dump; echo "code : $?"
```
- `cut -d: -f1` ne lit que l'hôte : le mot de passe ne s'affiche pas ;
- `--clean --if-exists` : supprime chaque objet avant de le recréer ;
- `--no-owner --no-privileges` : sur RDS, on n'est pas super-utilisateur, et tout appartient déjà à `taiga`.

Attendu : aucune sortie, `code : 0`. Un `errors ignored on restore` : ne rien relancer, lire les erreurs.

**4. Restaurer les médias**
```bash
sudo tar -xzpf /var/backups/taiga/media-<DATE>.tar.gz -C /mnt/efs/taiga/media
```
En root, `tar` remet les permissions et les numéros de propriétaire (UID/GID) : Taiga relit ses fichiers. Limite : `tar -x` ajoute et écrase, mais **ne supprime pas** les fichiers créés après la sauvegarde (ils restent orphelins).

**5. Rallumer, vérifier, nettoyer**
```bash
sudo docker service scale taiga_taiga-back=3 taiga_taiga-async=1
sudo docker service ls --filter name=taiga_taiga
sudo rm /var/backups/taiga/taiga-<DATE>.dump /var/backups/taiga/media-<DATE>.tar.gz
```
Attendu : back `3/3`, async `1/1` (les chiffres notés à l'étape 2). Dans le navigateur (Ctrl+F5) : la donnée est revenue, et **ouvrir une pièce jointe** prouve que la base et l'EFS sont revenus ensemble. Prévenir l'équipe que la production est libre.

## Dépannage
| Symptôme | Cause probable | Que faire |
|---|---|---|
| Aucune ligne dans le journal | cron absent, ou nœud éteint | `sudo crontab -l` ; relancer le playbook |
| `ECHEC ligne N` dans le journal | une commande du script a échoué ; les fichiers restent dans `/var/backups/taiga` | lancer le script à la main sur le leader et lire l'erreur |
| `pg_dump: error: … server version mismatch` | RDS passée à une majeure plus récente | changer `image_postgres` (`playbooks/group_vars/all.yml`) |
| `password authentication failed` | mot de passe changé dans Parameter Store | relancer le playbook (il réécrit `/root/.pgpass`) |
| `AccessDenied` sur `PutObject` | mauvais profil sur le nœud, ou préfixe hors `postgres/`/`media/` | étape 1 (associations), puis `aws sts get-caller-identity` |
| `aws: command not found` dans le cron | appel sans chemin complet | le script doit appeler `/usr/local/bin/aws` |
| `docker node inspect` sans leader | moins de 2 nœuds sur 3 allumés (pas de quorum) | démarrer les 3 nœuds |
| La commande SSH ne renvoie rien | guillemets doubles : `$(…)` calculé sur la VM | entourer la commande distante de guillemets simples |
| `cannot attach stdin to a TTY-enabled container` | `ssh node-1 '… docker exec -it …'` : SSH n'ouvre pas de terminal | `ssh -t node-1 '…'`, ou se connecter d'abord |
| Taiga en erreur après une restauration | back ou async encore à `0/0` | `docker service scale` avec les chiffres notés avant |
