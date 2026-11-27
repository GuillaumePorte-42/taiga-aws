# Rôle `ci`

Transforme l'instance `taiga-ci` en runner GitLab privé : fichier d'échange (swap), installation de GitLab Runner depuis le dépôt officiel, enregistrement auprès de GitLab, un job à la fois. Lancé par `playbooks/ci.yml` (après le rôle `docker`).

## Variables (`defaults/main.yml`)
| Variable | Défaut | Rôle |
|---|---|---|
| `ci_runner_nom` | `taiga-ci` | nom du runner (sert aussi à savoir s'il est déjà enregistré) |
| `ci_runner_token_ssm` | `/taiga/ci/gitlab_runner_token` | token d'authentification, dans Parameter Store |
| `ci_runner_image_defaut` | `alpine:3.20` | image d'un job qui n'en précise pas |
| `ci_runner_concurrent` | `1` | jobs en parallèle (2 Go de mémoire) |
| `ci_runner_privileged` | `true` | Docker-in-Docker, pour construire des images |
| `ci_swap_taille` | `2G` | swap de l'instance `t3.small` |
| `ci_sonar_token_ssm` | `/taiga/ci/sonar_token` | jeton SonarCloud, transmis aux jobs (`SONAR_TOKEN`) par le `config.toml` du runner |

Le tag `taiga-ci` et « Run untagged jobs » se règlent dans GitLab, à la création du runner.

## L'utiliser
```bash
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/ci.yml
```
Le runner n'est enregistré que s'il ne l'est pas déjà : rejouer le playbook ne crée pas de doublon. Vérifier, changer le token : `docs/runbooks/6-ci/gerer_le_runner.md`.

## Pièges
- **Jamais `gitlab-runner list`** à la main : la commande affiche le token. La tâche « Le runner est-il déjà enregistré ? » l'utilise : elle garde `no_log: true` (en place).
- Le token est lu dans Parameter Store au moment de l'enregistrement : NAT allumée, secret présent.
- `/taiga/ci/sonar_token` doit **exister** : sans lui, le `lookup` échoue et `ci.yml` s'arrête (compte neuf : `docs/runbooks/7-urgence/changer_de_compte_aws.md`, étape 6).
