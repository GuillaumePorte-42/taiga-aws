# Runbook – Déployer Taiga en production (stack Swarm)

**Pourquoi** : mettre en production une version validée en staging, revenir en arrière, ou redéployer la même version (après une reconstruction). Depuis le 04/11, la production se déploie par un **bouton dans le pipeline** ; le lancement depuis sa VM reste possible (secours).

**Où** : GitLab (projet `taiga-infrastructure`) ; pour le secours et les vérifications, sa VM, dossier `ansible/`, `staging` à jour, agent SSH chargé (`ssh-add ~/.ssh/taiga_bastion`). **Prévenir l'équipe** avant de déployer.

## Comment c'est construit
- `playbooks/taiga_production.yml` → rôle `taiga`, `tasks/stack.yml`, **une seule fois sur le premier manager** (`run_once`) ; Swarm répartit ensuite sur les 3 nœuds.
- Valeurs : `playbooks/group_vars/role_swarm_node.yml` (domaine, **empreintes des images**, base, mails SES) et `inventories/production/group_vars/all.yml` (secrets, EFS, registre).
- Base : RDS `taiga-db`, adresse lue dans `/taiga/production/db_host`. EFS : `/taiga/production/efs_id`. Mails : SES, identifiants `/taiga/production/email_host_*`. Voir `docs/reference/parametres.md`.
- Images désignées par leur **empreinte** (`taiga_ref_back`, `taiga_ref_front` : `@sha256:…`) : la production exécute exactement l'image testée en staging.
- Mise à jour **une copie à la fois** (`parallelism: 1`, `stop-first`, 10 s d'écart) ; `rollback` automatique si une nouvelle copie tombe dans les 30 s.

## Le chemin normal : promotion puis bouton
1. Le changement est **fusionné dans `staging`**, déployé et testé (pipeline vert : déploiement, `verifier_taiga`, E2E, charge).
2. **MR `staging` → `production`** dans GitLab : **Squash décoché** (les deux branches gardent les mêmes commits), **Delete source branch décoché** (la source, c'est `staging`). Lire l'onglet *Changes* : aucune image ni fichier de `terraform/` inattendu. Fusion.
3. **Avant le clic** (optionnel, preuve « sans coupure ») : la sonde dans un terminal de sa VM :
   ```bash
   while true; do echo "$(date +%T) $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://taiga-ledevagilles.fr/api/v1/)"; sleep 1; done | tee deploiement.log
   ```
4. **Build → Pipelines**, pipeline de `production` → **▶ `deployer-production`**. Il n'apparaît que si un fichier de la prod a changé ; sinon *Run pipeline* sur `production` (le bouton apparaît alors toujours).
5. Le job : rôle IAM de la CI, clé SSH de la CI (empreinte `SHA256:y4bi0yw8…`), `taiga_production.yml`, puis `verifier_taiga` sur `https://taiga-ledevagilles.fr`. Attendu : `failed=0` aux deux.

📘 `resource_group: production` : deux clics simultanés ne déploient pas en même temps, le second attend. `environment: production` : chaque déploiement apparaît dans **Operate → Environments** (qui, quand, quel commit).

## Vérifier (le job vert ne suffit pas)
`docker stack deploy` **rend la main avant la fin** de la mise à jour : le job peut être vert pendant que Swarm remplace encore les copies, ou après un `rollback` automatique.
```bash
ssh node-1 'sudo docker service ls'
ssh node-1 'sudo docker service ps taiga_taiga-back --filter desired-state=running --format "{{.Node}} {{.CurrentState}} {{.Error}}"'
ssh node-1 "sudo docker service inspect taiga_taiga-back --format '{{json .UpdateStatus}}'"
```
Attendu : chaque service à son nombre de copies (gateway, front, back, protected en `3/3` ; les autres `1/1`) ; les copies du service changé **récentes**, sans erreur ; `UpdateStatus` à `completed` (pas `rollback_completed`). Puis, si la sonde tournait : `Ctrl+C` et `awk '{print $2}' deploiement.log | sort | uniq -c` → que des `200`.

## Changer de version (promouvoir l'image testée en staging)
1. Sur le staging, lire l'empreinte de l'image qui y tourne (étiquette dans `inventories/staging/group_vars/all.yml`) :
   ```bash
   ssh staging "sudo docker image inspect registry.gitlab.com/projet-final-devops1/taiga-backend:<etiquette> --format '{{index .RepoDigests 0}}'"
   ```
   Attendu : `registry.gitlab.com/…/taiga-backend@sha256:…`. Même chose pour `taiga-frontend`.
2. Mettre `@sha256:…` dans `taiga_ref_back` / `taiga_ref_front` (`playbooks/group_vars/role_swarm_node.yml`) sur une branche `ci-…`, MR vers `staging`, fusion, puis le chemin normal ci-dessus.

## Revenir en arrière
- **Par Git (normal)** : dans GitLab, sur la MR fusionnée qui a changé l'empreinte → **Revert** (crée une MR inverse), ou `git revert -m 1 <commit de fusion>` sur une branche `ci-…`. Fusion dans `staging`, promotion, bouton. Rien n'est perdu : l'historique garde l'aller et le retour.
- **Urgence** : `ssh node-1 'sudo docker service rollback taiga_taiga-front'` remet la version précédente **tout de suite**, mais Git dit encore « nouvelle version » (**dérive**) : faire **quand même** le revert juste après.
- ⚠️ **Le back et les migrations** : si la version annulée a modifié la structure de la base (migrations), revenir à l'ancienne image ne défait pas les migrations. Vérifier le journal du job (« Appliquer les migrations » : `changed` ou `ok`) ; au besoin, restaurer la base (`docs/runbooks/5-donnees/sauvegarder_restaurer.md`). Le **front** se remet en arrière sans risque.

## Secours : déployer depuis sa VM
```bash
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/taiga_production.yml --check --diff
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/taiga_production.yml
ansible-playbook playbooks/verifier_taiga.yml -e taiga_url=https://taiga-ledevagilles.fr
```
En simulation, « Appliquer les migrations » et « Déployer la stack » sont **sautés** (voulu : on ne simule pas une migration). `back.env` et le fichier de stack sont en `no_log` : leur diff n'apparaît pas. Seulement depuis `staging` à jour (sinon on déploie autre chose que ce que dit Git).

## Comptes et administration
- Les comptes de la production sont **dans la RDS** : ils survivent aux reconstructions des instances. Super-utilisateur créé une fois (adresse : une adresse vérifiée dans SES).
- **Ajouter quelqu'un** : depuis Taiga, *projet → Team → Add member* → son adresse. Il reçoit l'**invitation par mail** (SES) et crée son compte, même si les inscriptions publiques sont fermées. En **bac à sable SES**, son adresse doit d'abord être vérifiée (`docs/runbooks/4-verifier/verifier_les_mails.md`).
- **L'admin de Django (`/admin/`) est fermé** (`403`, `taiga.conf`). Pour une opération d'administration, `manage.py` dans un back qui tourne :
  ```bash
  ssh -t node-1 'sudo docker exec -it $(sudo docker ps -q -f name=taiga_taiga-back | head -n1) python manage.py createsuperuser'
  ssh -t node-1 'sudo docker exec -it $(sudo docker ps -q -f name=taiga_taiga-back | head -n1) python manage.py changepassword <utilisateur>'
  ```
  Mot de passe dans son gestionnaire, jamais dans le chat ni dans Git.
- Un chef d'équipe = **compte normal** (ni `superuser` ni `staff`), admin de **son** projet (le créateur d'un projet en devient admin).

## Pièges
- `could not translate host name` : `/taiga/production/db_host` vide ou base absente. `password authentication failed` : le mot de passe de la RDS n'est plus celui de `/taiga/production/postgres_password` (réappliquer `terraform/donnees`).
- 502 de l'ALB (`server: awselb/2.0`) : rien n'écoute sur 9000 (stack pas déployée, gateway qui redémarre). 503 : aucune cible (nœuds arrêtés). 502 avec `server: nginx` : la passerelle ne joint pas un service (voir `docs/runbooks/7-urgence/diagnostiquer_taiga_en_panne.md`).
- Base arrêtée : la page s'affiche (fichiers statiques) mais la connexion échoue ; Swarm relance le back tout seul quand la base revient.
- Mails non reçus : adresse non vérifiée dans SES (bac à sable), ou dossier spam (domaine neuf) ; erreurs dans `ssh node-1 "sudo docker service logs --tail 40 taiga_taiga-async"`.
- Noms : `taiga-node-1` pour Ansible (tag `Name`), `node-1` pour SSH (`~/.ssh/taiga_config_production`).
