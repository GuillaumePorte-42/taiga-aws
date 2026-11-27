# Versions des outils de l'équipe

**Pourquoi** : la VM de chacun et le pipeline doivent faire **exactement** la même chose. Une version différente peut changer un comportement sans que personne ait touché au code (« ça marche chez moi »).

**La règle** : la version qui fait foi est celle écrite **dans le fichier source** (colonne de droite). Ce tableau est une photo prise le 02/11 (Docker : 05/11) : en cas de doute, c'est le fichier qui a raison. Pour changer une version : on change le fichier source, par une MR, puis on met à jour ce tableau **et** sa copie dans Confluence (page « Versions des outils de l'équipe »), avec la date.

## Sur la VM (contrôleur Ansible et Terraform)
| Outil | Version | Source qui fait foi |
|---|---|---|
| Terraform | 1.16.6 | `README.md` (prérequis) et image `hashicorp/terraform:1.16.6` de `.gitlab-ci.yml` |
| Provider AWS de Terraform | `~> 6.0` | `terraform/*/main.tf` + `.terraform.lock.hcl` |
| `ansible-core` | 2.19.14 | relevée sur la VM (`ansible --version`) |
| `boto3` / `botocore` | 1.43.121 | relevée sur la VM (`pipx runpip ansible-core list`) |
| `amazon.aws` | 10.1.2 | `ansible/requirements.yml` |
| `ansible.posix` | 2.1.0 | `ansible/requirements.yml` |
| `community.docker` | 4.8.5 | `ansible/requirements.yml` |
| `community.general` | 11.4.2 | `ansible/requirements.yml` |
| AWS CLI | 2.9.19 (paquet Debian 12) | relevée sur la VM (`aws --version`) ; ancienne, à mettre à jour (piste) |

Les collections ne servent **que sur la VM** (et dans le conteneur du job CI) : Ansible copie le module sur la machine cible le temps de la tâche. Rien à installer sur les serveurs.

## Sur les nœuds de production (rôle `sauvegardes`)
| Outil | Version | Source qui fait foi |
|---|---|---|
| AWS CLI v2 (installeur officiel) | 2.39.3 | `ansible/roles/sauvegardes/defaults/main.yml` (`sauvegardes_awscli_version`) |
| Image PostgreSQL (prête `pg_dump`, et base du staging) | `postgres:17.11-trixie` | `ansible/playbooks/group_vars/all.yml` (`image_postgres`) |

La RDS de production est en PostgreSQL 17.9 : `pg_dump` 17.11 la lit sans souci (même version **majeure**). Un `pg_dump` plus ancien que le serveur (le client 16 d'Ubuntu 24.04) refuse de travailler.

## Sur toutes les machines sauf le bastion (rôle `docker`)
Relevées le 05/11 sur le staging et node-1 (identiques), avant la reconstruction.

| Paquet | Version | Source qui fait foi |
|---|---|---|
| `docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras` | `5:29.9.3-1~ubuntu.24.04~noble` | `ansible/roles/docker/defaults/main.yml` (`docker_version`) |
| `containerd.io` | `2.4.2-3~ubuntu.24.04~noble` | idem (`docker_containerd_version`) |
| `docker-buildx-plugin` | `0.38.1-1~ubuntu.24.04~noble` | idem (`docker_buildx_version`) |
| `docker-compose-plugin` | `5.7.0-1~ubuntu.24.04~noble` | idem (`docker_compose_version`) |

Le `5:` du début (l'« epoch ») fait partie de la version. Vérifier une machine : `dpkg -l | grep -E 'docker|containerd'`.

## Tests du staging (sur la VM, un environnement Python par outil)
| Outil | Version | Source qui fait foi |
|---|---|---|
| Playwright (+ Chromium qu'il télécharge) | 1.64.1 | `tests/e2e/requirements.txt` |
| `pytest-playwright` | 0.10.0 | `tests/e2e/requirements.txt` |
| `pytest` | 9.2.0 | `tests/e2e/requirements.txt` |
| Locust | 2.47.0 | `tests/charge/requirements.txt` |
| Python de la VM | 3.11.2 | relevée sur la VM (`python3 --version`) |

## Dans le pipeline (`.gitlab-ci.yml`)
| Job | Image |
|---|---|
| `terraform-fmt`, `terraform-validate` | `hashicorp/terraform:1.16.6` |
| `gitleaks` | `zricethezav/gitleaks:v8.30.1` |
| `tflint` | `ghcr.io/terraform-linters/tflint:v0.65.0` |
| `trivy` | `aquasec/trivy:0.76.1` |
| `yamllint` (désactivé) | `python:3.13-slim` + `yamllint==1.38.0` |
| `ansible-lint` (désactivé) | `python:3.13-slim` + `ansible-lint==26.10.1` |

## Vérifier sa VM (2 minutes)
Depuis `taiga-infrastructure/ansible` :
```bash
terraform version | head -1
ansible --version | head -1
ansible-galaxy collection list 2>/dev/null | grep -E "^(amazon\.aws|community\.docker|community\.general|ansible\.posix) "
pipx runpip ansible-core list 2>/dev/null | grep -iE "^(boto3|botocore) "
aws --version
```
Attendu : les versions des tableaux. Une ligne en double pour une collection = installée à deux endroits (le signaler).

## Si une version diffère
- **Collections** (après fusion de `requirements.yml` versions figées) : `ansible-galaxy collection install -r requirements.yml`. Elles s'installent dans `~/.ansible/collections`, qu'Ansible regarde en premier.
- **`ansible-core`**, **Terraform** : en parler à l'équipe avant de changer, pour qu'on change tous en même temps.

## Pièges
- `ansible-galaxy collection list` n'accepte qu'**un** nom de collection : pour plusieurs, filtrer la liste avec `grep`.
- Une collection sans `version:` dans `requirements.yml` = la dernière version publiée, différente d'un jour à l'autre.
- Dans `requirements.yml`, mettre les versions entre guillemets (`"2.10"` n'est pas le nombre `2.1`).
- Une image utilisée par **deux rôles** se range dans `playbooks/group_vars/all.yml` (ex. `image_postgres`) ; utilisée par un seul rôle, elle reste dans ses `defaults`.
