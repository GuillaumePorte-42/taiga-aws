# Runbook – Tout reconstruire depuis zéro

**Pourquoi** : prouver que l'infrastructure est décrite dans le code. On détruit ce qui « vit » (instances, ALB, certificat, DNS, EFS, Swarm), puis on remonte en suivant ce runbook, en notant l'heure de début et de fin. C'est aussi le plan B de la démo.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, sur `staging` à jour. **Une seule personne** fait les `apply` et lance les playbooks ; l'équipe est prévenue.

## Ce qu'on détruit, ce qu'on garde
| Dossier | Contient | Pendant une reconstruction |
|---|---|---|
| `socle/` | bucket du state, zone DNS, secrets, SES, bucket des sauvegardes | **jamais** détruit (`prevent_destroy`) |
| `reseau/` | VPC, sous-réseaux, security groups, NAT | **gardé** (la NAT est détruite le soir comme d'habitude, et rallumée avant) |
| `donnees/` | RDS (base de la production) | **gardé** : `donnees/` lit `reseau/` (sous-réseaux, SG) : impossible de détruire `reseau/` tant que la base existe (AWS refuse de supprimer un VPC encore utilisé) |
| `commun/` | bastion, supervision, CI, ALB, certificat, DNS de Taiga, rôles IAM, journaux | détruit puis recréé |
| `staging/` | instance du staging | détruit puis recréé |
| `production/` | 3 nœuds, EFS, ID de l'EFS dans Parameter Store | détruit puis recréé |

Reconstruction **totale** (y compris `reseau/` et `donnees/`) : passer `deletion_protection = false` sur la RDS et l'appliquer, détruire (snapshot final `taiga-db-final` prévu), puis restaurer la base. Plus long et plus risqué : à décider à 3. Sur un **autre compte AWS** : `docs/runbooks/7-urgence/changer_de_compte_aws.md`.

Ce qui est **perdu puis recréé** :
- **Staging** : base vide → comptes `admin` et `e2e-test` recréés par `taiga.yml` ; projets de test perdus (voulu : environnement jetable).
- **EFS de la production** : neuf et **vide** → `efs_id` suit seul (Parameter Store) ; **médias** (pièces jointes, exports) à restaurer depuis la sauvegarde.
- **Supervision** : historique de Prometheus et Grafana (accepté).
- **CI** : instance neuve → le runner se réenregistre avec son jeton (Parameter Store).
- **Certificat ACM** : recréé, validé par DNS (quelques minutes, l'`apply` attend).

Ce qui est **gardé** : la base de la production (comptes, projets), les secrets, le domaine SES vérifié, les sauvegardes.

## Avant de détruire
1. **Sauvegarde de la production** (base + médias), puis preuve :
   ```bash
   cd ansible && ansible -i inventories/production/aws_ec2.yml role_swarm_node -b -m command -a /usr/local/sbin/taiga-sauvegarde && cd ..
   aws s3 ls s3://taiga-ledevagilles-backups/postgres/ --recursive | sort | tail -1
   aws s3 ls s3://taiga-ledevagilles-backups/media/ --recursive | sort | tail -1
   ```
   Attendu : un fichier de chaque, daté de maintenant.
2. **Les paramètres sont tous là** (noms seulement) :
   ```bash
   aws ssm get-parameters-by-path --path /taiga --recursive --query "Parameters[].Name" --output text
   ```
   Attendu (voir `docs/reference/parametres.md`) : `/taiga/staging/*` (dont `admin_password`, `e2e_password`, `email_host_*`, `ci_ssh_private_key`, `registry_token`), `/taiga/production/*` (dont `db_host`, `efs_id`, `email_host_*`, `postgres_monitoring_password`, `registry_token`), `/taiga/ci/gitlab_runner_token`, `/taiga/admin/grafana_admin_password`, **`/taiga/admin/alert_webhook_url`** (sans lui, `supervision.yml` échoue), `/taiga/reseau/ips_equipe` (avec les IP du jour).
3. Le runner `taiga-ci` est **en ligne** dans GitLab (son jeton sera réutilisé) ; sinon `docs/runbooks/6-ci/gerer_le_runner.md`.
4. Noter l'heure de début.

## Détruire (ordre inverse de la création)
```bash
terraform -chdir=terraform/production destroy
terraform -chdir=terraform/staging destroy
terraform -chdir=terraform/commun destroy
```
Lire chaque plan avant `yes` : seulement des ressources du dossier. **Jamais `socle/`**, ni `donnees/`, ni `reseau/` (sauf reconstruction totale décidée à 3).

## Reconstruire
### 1. Terraform
NAT allumée **et `available`** (`docs/runbooks/2-chaque-jour/arreter_demarrer.md`, le matin, étape 2), RDS `available`, puis :
```bash
terraform -chdir=terraform/commun apply
terraform -chdir=terraform/staging apply
terraform -chdir=terraform/production apply
```
Chaque `apply` doit finir sans erreur avant le suivant (`staging/` et `production/` lisent `reseau/` et `commun/`). `commun/` relit l'IP de la NAT (règle 11 de l'ALB).

### 2. Accès SSH (chacun)
La routine de `docs/runbooks/1-equipe/se_connecter_ssh.md` : régénérer les 3 fichiers `~/.ssh/taiga_config*`, charger la clé dans l'agent, `ssh bastion hostname`. Attendre une minute après les `apply` (cloud-init pose les clés). `REMOTE HOST IDENTIFICATION HAS CHANGED` : `ssh-keygen -R <ip>`.

### 3. Ansible
Depuis `ansible/`, dans l'ordre de `ansible/README.md` (« Machines neuves : l'ordre »), chaque ligne en `failed=0` avant la suivante :
`ping`, `site`, `docker`, `ci`, `cadvisor`, `supervision`, `efs`, `swarm`, **`sauvegardes`** (à ne pas oublier : sinon plus aucune sauvegarde), `taiga` (staging), puis la production.

La **production** : bouton `deployer-production` (pipeline de `production`, *Run pipeline*) dès que le runner est en ligne, ou `taiga_production.yml` depuis la VM.

### 4. Restaurer les médias (si on les garde)
`docs/runbooks/5-donnees/sauvegarder_restaurer.md`, partie 6 « Restaurer » (les médias) : la dernière archive de `media/` vers `/mnt/efs/taiga/media`.

### 5. Vérifier
- `ansible-playbook playbooks/verifier_taiga.yml` et `… -e taiga_url=https://taiga-ledevagilles.fr` : `failed=0`.
- `ssh node-1 'sudo docker service ls'` : tout en `3/3` ou `1/1`.
- GitLab : runner `taiga-ci` au vert **sans nouveau jeton** ; supprimer l'ancien « runner manager » hors ligne.
- Pipeline de `staging` (*Run pipeline*) : déploiement, E2E, charge au vert **sans avoir recréé `e2e-test` à la main**.
- Grafana (tunnel) : toutes les cibles `up`, sondes `site` et `api` à 1.
- `curl -s -o /dev/null -w '%{http_code}\n' https://taiga-ledevagilles.fr/admin/` → `403`.
- Un mail : « mot de passe oublié » en production vers une adresse vérifiée.
- Une sauvegarde manuelle (point 1 de « Avant de détruire ») : le nouveau leader sauvegarde.
- Noter l'heure de fin et la durée.

## Pièges
- Les IP privées changent : régénérer les configs SSH, relancer `supervision.yml` (fait dans l'ordre ci-dessus).
- Le certificat ACM est recréé avec `commun/` : sa validation DNS prend quelques minutes, l'`apply` attend.
- Docker est épinglé (rôle `docker`, 05/11) : une machine neuve reçoit la même version que les autres. Une version retirée du dépôt de Docker ferait échouer `docker.yml` (`ansible/roles/docker/README.md`).
- Les minutes de CI partagées (400 par mois) : une reconstruction lance plusieurs pipelines.
- **Horloge de la VM** en retard (veille du PC) : `AuthFailure` sur l'inventaire, `no hosts matched` dans les playbooks, alors que `aws sts get-caller-identity` marche (vécu le 05/11). `sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd`.
- **Nom des archives** : copier le nom exact depuis `aws s3 ls` (le 05/11, `tar` en échec à cause du `Z` final oublié).
- **Test du réseau overlay** (`alpine:3.20` absente des nœuds neufs) : `docker pull -q alpine:3.20` avant le `docker run` (`verifier_production.md`, partie 7).
- **Machines démarrées avant la NAT** : images non téléchargées, services en `Preparing` ; même ordre que le matin (`docs/runbooks/2-chaque-jour/arreter_demarrer.md`).
- Changement de **compte** AWS (rien n'existe, pas même le bucket du state) : `docs/runbooks/7-urgence/changer_de_compte_aws.md`.

## Mesuré le 05/11
Reconstruction faite en suivant seulement les runbooks, sans aide : tout est revenu, supervision comprise. Prévoir **environ 1 h**.

| Étape | Début | Fin | Remarques |
|---|---|---|---|
| sauvegarde | | | |
| destroy | | | |
| apply | | | |
| Ansible | | | horloge de la VM à remettre à l'heure |
| production | | | |
| restauration des médias | | | nom de l'archive sans le `Z` |
| vérifications | | | `alpine:3.20` à télécharger sur chaque nœud |
