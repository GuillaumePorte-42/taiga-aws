# Ansible — projet Taiga

Configure les machines créées par Terraform : base commune, Docker, CI, supervision, Swarm, Taiga. Toutes les commandes se lancent **depuis ce dossier** (`ansible/`), dans sa VM.

## Prérequis (une fois, sur son poste)
```bash
# Ansible installé par pipx : boto3 doit aller dans SON environnement Python
pipx install --include-deps ansible
pipx inject ansible boto3 botocore
ansible-galaxy collection install -r requirements.yml
```
Ansible installé autrement : `python3 -m pip install --user ansible boto3 botocore`.

À chaque nouveau terminal : **la clé SSH dans l'agent** (Ansible ne lit pas les alias `Host` de `~/.ssh/config`) :
```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion
```
Et des identifiants AWS valides (`aws sts get-caller-identity`) : l'inventaire dynamique et les secrets sont lus dans AWS.

## Inventaires
Dynamiques : Ansible demande à AWS les instances **allumées** du projet et les range par tag `Role` → groupes `role_bastion`, `role_monitoring`, `role_ci`, `role_staging`, `role_swarm_node`. Les machines privées sont jointes par le bastion (`ProxyJump`, IP lue dans l'inventaire).

| Inventaire | Machines | Variables |
|---|---|---|
| `inventories/staging/aws_ec2.yml` | staging + `commun` (bastion, supervision, CI) | `taiga_env: staging`, secrets `/taiga/staging/*`, domaine, étiquettes des images |
| `inventories/production/aws_ec2.yml` | nœuds + `commun` | `taiga_env: production`, secrets `/taiga/production/*` |
| `inventories/tous/aws_ec2.yml` | toutes les machines du projet | rien de propre à un environnement |

Voir les groupes : `ansible-inventory -i inventories/<inventaire>/aws_ec2.yml --graph`.

## Variables : où les mettre
| Fichier | Pour |
|---|---|
| `roles/<rôle>/defaults/main.yml` | la valeur par défaut, commune à tous |
| `inventories/<env>/group_vars/all.yml` | ce qui change d'un environnement à l'autre (domaine, étiquettes, secrets) |
| `playbooks/group_vars/role_<type>.yml` | ce qui est propre à un type de machine (règles UFW des nœuds, du staging) |

## Les playbooks
| Playbook | Rôles | Machines | Inventaire conseillé |
|---|---|---|---|
| `ping.yml` | — | toutes | n'importe lequel |
| `check_secrets.yml` | — | localhost | `-e taiga_env=staging` ou `production` (affiche la longueur, jamais la valeur) |
| `site.yml` | `common` | toutes | `tous` (ou `--limit`) |
| `docker.yml` | `docker` | toutes sauf le bastion | `tous` (ou `--limit`) |
| `ci.yml` | `docker`, `ci` | `role_ci` | `tous` |
| `supervision.yml` | `docker`, `supervision` | `role_monitoring` | **`tous`** : la configuration de Prometheus est construite à partir des machines de l'inventaire |
| `cadvisor.yml` | `cadvisor` | staging + nœuds | `tous` |
| `efs.yml` | `efs` | `role_swarm_node` | `production` |
| `swarm.yml` | `swarm` | `role_swarm_node` (le staging est en Compose, ADR-03) | `production` |
| `sauvegardes.yml` | `sauvegardes` | `role_swarm_node` (seul le leader Swarm sauvegarde) | `production` |
| `taiga.yml` | `taiga` (Compose) | `role_staging` | `staging` |
| `taiga_production.yml` | `taiga` (`tasks/stack.yml`, stack Swarm) | premier nœud manager | `production` ; d'habitude par le bouton `deployer-production` de la CI |
| `verifier_taiga.yml` | — | localhost | aucun (`-e taiga_url=…` pour la production) |

## Machines neuves : l'ordre
Après les `apply` Terraform (`../README.md`), **NAT allumée**, toutes les machines démarrées :
```bash
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/ping.yml
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/site.yml
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/docker.yml
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/ci.yml
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/cadvisor.yml
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/supervision.yml
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/efs.yml
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/swarm.yml
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/sauvegardes.yml
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/taiga.yml
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/taiga_production.yml
ansible-playbook playbooks/verifier_taiga.yml
ansible-playbook playbooks/verifier_taiga.yml -e taiga_url=https://taiga-ledevagilles.fr
```
Chaque ligne doit finir par `failed=0` avant de passer à la suivante. Une seule machine : ajouter `--limit <nom>` (ex. `--limit taiga-staging`). Un cluster qui tourne : un nœud à la fois (`../docs/runbooks/4-verifier/verifier_production.md`).

- **`sauvegardes.yml` ne doit pas être oublié** : sans lui, les nœuds neufs n'ont ni script, ni cron, ni `.pgpass`, et plus rien n'est sauvegardé (aucune alerte ne le signale encore).
- **La production** peut aussi se déployer par le bouton `deployer-production` (pipeline de la branche `production`, *Run pipeline*) : c'est la façon habituelle (`../docs/runbooks/3-deployer/deployer_production.md`).
- **Les comptes du staging** (`admin`, `e2e-test`) sont recréés par `taiga.yml` (tâche 6 du rôle `taiga`) : plus rien à créer à la main. En production, les comptes sont dans la RDS et survivent.

## Règles
- Aucun secret dans le dépôt : tout est lu dans Parameter Store (`/taiga/<env>/…`, `/taiga/ci/…`, `/taiga/admin/…`).
- Toute tâche qui manipule un secret porte `no_log: true`, et on ne le retire jamais, même pour déboguer.
- Un playbook se rejoue sans danger : 2e passage = `changed=0` (idempotence).
- On n'active jamais UFW à la main : on passe par `site.yml`, qui autorise SSH **avant** d'activer le pare-feu.

## Pièges
- **`swarm.yml` avec l'inventaire `production`** : le rôle crée le cluster sur la première machine du play et y fait entrer les autres. Depuis le 04/11 il ne vise plus que `role_swarm_node` (avant, il visait aussi le staging : avec `tous`, staging et production se seraient retrouvés dans le même cluster).
- **Lancer depuis `ansible/`** : depuis la racine du dépôt, `inventories/…` est introuvable (« Unable to parse … as an inventory source », aucune machine).
- Une machine arrêtée n'est **pas** dans l'inventaire (filtre `running`) : `supervision.yml` lancé sans elle l'oublie dans Prometheus. Le relancer quand tout est allumé.
- Après la recréation d'une machine (nouvelle IP privée) : relancer `supervision.yml`.

## En cas de problème
| Message | Cause | Solution |
|---|---|---|
| `Failed to import … boto3` | Ansible (pipx) sans boto3 | `pipx inject ansible boto3 botocore` |
| `Permission denied (publickey)` / `UNREACHABLE` | clé absente de l'agent | `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion` |
| groupe vide dans `--graph` | machine arrêtée, ou mauvais inventaire | démarrer la machine ; vérifier son tag `Environnement` |
| `ParameterNotFound` | secret absent | `check_secrets.yml -e taiga_env=<env>` |
| `apt` ou téléchargement bloqué | NAT éteinte | `../docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md` |
| `AuthFailure`, `ExpiredToken`, ou `no hosts matched` alors que `aws sts get-caller-identity` marche | heure de la VM en retard (veille du PC), identifiants AWS | `sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd` ; `aws sts get-caller-identity` |
| après un rallumage, un service de la stack en `0/1`, tâche en `Preparing` (`registry-1.docker.io … deadline exceeded`) | machines démarrées avant la NAT : image pas téléchargée | `../docs/runbooks/2-chaque-jour/arreter_demarrer.md` (contrôles du matin) |
