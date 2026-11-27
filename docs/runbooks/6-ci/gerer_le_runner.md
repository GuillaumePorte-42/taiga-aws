# Runbook – Le runner GitLab privé (`taiga-ci`)

**Pourquoi** : les runners partagés de GitLab sont sur Internet et ne peuvent pas joindre nos machines privées. Les jobs qui touchent l'infra (déploiement, E2E, Locust) tournent sur notre runner, installé sur l'instance `taiga-ci`, dans le VPC.

**Comment il est fait** : rôle Ansible `ci` (`ansible/roles/ci/`) ; runner **de groupe** (`projet-final-devops1`), exécuteur **docker** (chaque job tourne dans un conteneur), tag **`taiga-ci`**, « Run untagged jobs » **décochée**, un job à la fois. Token d'authentification dans Parameter Store : `/taiga/ci/gitlab_runner_token` (`SecureString`). Droits AWS : rôle IAM `taiga-ec2-ci` (inventaire EC2, lecture de `/taiga/*`).

## Utiliser le runner dans un job
```yaml
deployer-staging:
  tags: [taiga-ci]     # sans ce tag, le job reste sur les runners partagés
```

## Vérifier qu'il marche
- GitLab : groupe → **Build → Runners** → `taiga-ci` avec un point **vert**.
- Sur la machine (depuis sa VM) :
  ```bash
  ssh ci sudo gitlab-runner status
  ssh ci sudo systemctl is-active gitlab-runner
  ```
  Attendu : `gitlab-runner: Service is running` et `active`.

⚠️ **Jamais `gitlab-runner list`** : la commande affiche le token en clair.

## Changer le token (exposé, ou rotation)
1. GitLab : groupe → **Build → Runners** → supprimer l'ancien runner `taiga-ci`.
2. **New group runner** : tag `taiga-ci`, « Run untagged jobs » décochée, description `taiga-ci` → *Create runner*. Copier le token affiché (`glrt-…`), **sans le coller ailleurs**.
3. Dans sa VM, le mettre dans Parameter Store sans l'afficher :
   ```bash
   read -s -p "Token du runner : " TOKEN && aws ssm put-parameter --name /taiga/ci/gitlab_runner_token --type SecureString --value "$TOKEN" --overwrite && unset TOKEN
   ```
   Attendu : `{"Version": N, "Tier": "Standard"}`.
4. Retirer l'ancien enregistrement de la machine :
   ```bash
   ssh ci sudo gitlab-runner unregister --name taiga-ci
   ```
5. Réenregistrer avec le nouveau token (depuis `ansible/`) :
   ```bash
   ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/ci.yml
   ```
6. GitLab : le nouveau runner passe au **vert**.

## En cas de problème
| Symptôme | Cause probable | Solution |
|---|---|---|
| job bloqué en *pending* | tag absent ou différent, runner éteint | `tags: [taiga-ci]` ; instance `taiga-ci` démarrée ; point vert |
| runner gris (hors ligne) | instance arrêtée, ou pas de sortie Internet | démarrer l'instance ; NAT allumée (`docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md`) |
| `ParameterNotFound` au playbook | token absent de Parameter Store | étape 3 |
| job qui manque de mémoire | `t3.small` (2 Go, swap 2 Go) | un job à la fois ; passer en `t3.medium` dans `terraform/commun/instances.tf` |

## Pièges
- Le runner tourne en mode **privilégié** (nécessaire pour construire des images Docker) : il ne doit exécuter que nos jobs, d'où le tag obligatoire.
- La limite de sauts IMDS est à 2 (`terraform/commun/instances.tf`) : c'est elle qui permet au conteneur du job d'utiliser le rôle IAM de l'instance. À 1, les jobs n'ont plus d'accès AWS.
- Depuis le runner, la CI joint les machines **directement** (SG et UFW autorisent le 22 depuis la CI) : dans un job Ansible, annuler le rebond par le bastion avec `-e ansible_ssh_common_args=""`.
