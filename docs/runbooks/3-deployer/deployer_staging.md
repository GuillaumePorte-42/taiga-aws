# Runbook – Déployer et exploiter Taiga (staging)

**Pourquoi** : Taiga tourne sur l'instance staging en 10 conteneurs Docker Compose (les 9 de Taiga + Mailpit, faux serveur de mail), déployés par le rôle Ansible `taiga`. Ce runbook dit comment le (re)déployer, le vérifier, changer de version et dépanner.

**Où** : dans sa VM, dossier `taiga-infrastructure/ansible`, clé SSH chargée dans l'agent :
```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion
```

**Prérequis** : NAT allumée (`docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md`), `ssh staging` fonctionne (`docs/runbooks/1-equipe/se_connecter_ssh.md`), Ansible avec boto3 (`pipx inject ansible boto3 botocore` si Ansible est installé par pipx).

## Comment c'est organisé
```
Navigateur ─HTTPS─► ALB (règle : IP de l'équipe seulement) ─HTTP :9000─► instance staging (privée)
                                                                          └─ taiga-gateway (nginx) ─► front, back, events, protected
                                                                                                       back ─► taiga-db, 2 × RabbitMQ ─► async, events
```
- **Rôle** `roles/taiga/` = comment installer Taiga (commun à tous les environnements).
- **Inventaire** `inventories/staging/group_vars/all.yml` = valeurs du staging : domaine, étiquettes des images, compte du registre, secrets (lus dans Parameter Store `/taiga/staging/…`).
- **Sur la machine**, tout est dans `/opt/taiga` (réservé à root) : `docker-compose.yml`, `docker-compose-inits.yml`, `taiga.conf`, `.env` (secrets, `0600`, jamais dans Git).
- Images : les nôtres (`registry.gitlab.com/projet-final-devops1/taiga-backend|frontend:staging-<commit>`) et les officielles en version fixe (`roles/taiga/defaults/main.yml`).

## Déployer (ou redéployer)
```bash
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/taiga.yml
```
Attendu : `failed=0`. Au 2e passage sans changement : `changed=0`.

**Machine neuve** (après une recréation) : d'abord la base, puis Docker, puis Taiga. La base du staging repart **vide** : `taiga.yml` recrée les comptes `admin` et `e2e-test` (voir plus bas).
```bash
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/site.yml --limit role_staging
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/docker.yml --limit role_staging
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/taiga.yml
```

## Vérifier
1. Les 10 conteneurs : `ssh staging sudo docker compose --project-directory /opt/taiga ps` → tous `Up`, `taiga-db` `(healthy)`.
2. Le back : `ssh staging sudo docker compose --project-directory /opt/taiga logs --tail 30 taiga-back` → `Starting Taiga API`, gunicorn sur `0.0.0.0:8000`.
3. Un seul port publié : `ssh staging "sudo docker ps --format '{{.Names}}  {{.Ports}}'"` → seulement `0.0.0.0:9000->80/tcp` sur `taiga-gateway`.
4. La cible de l'ALB :
   ```bash
   aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names taiga-tg-staging --query "TargetGroups[0].TargetGroupArn" --output text) --query "TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]" --output table
   ```
   → `healthy`.
5. De bout en bout : `curl -sI https://staging.taiga-ledevagilles.fr | head -1` → `HTTP/2 200`, puis le navigateur.

## Les comptes du staging (automatiques)
`taiga.yml` crée ou remet à jour deux comptes (tâche 6 du rôle `taiga`, idempotente : `changed=0` s'ils sont déjà bons) :

| Compte | Pour | Mot de passe |
|---|---|---|
| `admin` (`admin@example.com`, super-utilisateur, compte de service) | administrer le staging | `/taiga/staging/admin_password` (généré par `terraform/socle`) |
| `e2e-test` (`e2e-test@example.com`, compte normal) | tests E2E et de charge de la CI | `/taiga/staging/e2e_password` |

Se connecter en `admin` sans afficher le mot de passe :
```bash
aws ssm get-parameter --name /taiga/staging/admin_password --with-decryption --query Parameter.Value --output text | xclip -selection clipboard
```
Puis `Ctrl+V` dans le champ (`sudo apt install xclip` si besoin). Les autres comptes : par **invitation** depuis un projet (le mail arrive dans Mailpit : `docs/runbooks/4-verifier/verifier_les_mails.md`). L'admin de Django (`/admin/`) est fermé (`403`).

## Changer de version / revenir en arrière
1. Lire l'étiquette voulue dans GitLab (*Deploy → Container registry*), toujours `staging-<commit>`, jamais `latest`.
2. La mettre dans `inventories/staging/group_vars/all.yml` (`taiga_etiquette_back` ou `taiga_etiquette_front`), MR, fusion.
3. Relancer `playbooks/taiga.yml` : seuls les conteneurs concernés sont recréés.

Revenir en arrière = remettre l'étiquette précédente et relancer.

## Arrêt et redémarrage
- **Arrêter / rallumer l'instance** : rien à faire. Docker redémarre au boot et `restart: unless-stopped` relance les conteneurs. Les données sont gardées (disque de l'instance).
- **Recréer l'instance** : Taiga revient avec les 3 playbooks, mais **vide** (le disque est supprimé). Données du staging = jetables, par choix.

## Commandes utiles (sur sa VM)
| But | Commande |
|---|---|
| Logs d'un service | `ssh staging sudo docker compose --project-directory /opt/taiga logs --tail 50 <service>` |
| Redémarrer un service | `ssh staging sudo docker compose --project-directory /opt/taiga restart <service>` |
| Entrer dans la base | `ssh -t staging sudo docker compose --project-directory /opt/taiga exec taiga-db psql -U taiga taiga` |

## En cas de problème
| Symptôme | Cause probable | Solution |
|---|---|---|
| 403 « Accès réservé à l'équipe » | son IP publique a changé | `docs/runbooks/1-equipe/changer_son_ip.md` |
| 502 Bad Gateway | un conteneur n'est pas prêt ou a planté | `… ps`, puis les logs du service en cause |
| cible `unhealthy` | la passerelle ne répond pas sur 9000 | `… ps` ; `… logs taiga-gateway` |
| `Lancer Taiga` échoue : `denied` / `unauthorized` | token du registre invalide ou expiré | recréer le deploy token de groupe `staging-pull` (`read_registry`), le remettre dans `/taiga/staging/registry_token` |
| `ParameterNotFound` | secret absent de Parameter Store | `ansible-playbook playbooks/check_secrets.yml -e taiga_env=staging` |
| `Failed to import … boto3` | Ansible (pipx) sans boto3 | `pipx inject ansible boto3 botocore` |
| `Permission denied (publickey)` / `unreachable` | clé pas dans l'agent | `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion` |
| images qui ne se téléchargent pas (timeout) | NAT éteinte | `docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md` |

## Pièges
- `/opt/taiga` est réservé à root : toujours `sudo` (et `--project-directory /opt/taiga`).
- `no_log: true` sur les tâches qui touchent aux secrets : ne jamais le retirer, même pour déboguer.
- Modifier `taiga.conf` : le handler du rôle redémarre la passerelle (le fichier est monté, nginx ne le relit pas seul). La passerelle retrouve seule un service recréé (`resolver` de Docker) : plus besoin de la redémarrer après un déploiement.
- Tester sa branche sur le staging depuis la VM **avant** la MR (prévenir l'équipe) : `--check` ne voit pas tout (il lit les anciens fichiers).
- Ne jamais copier le `.env` de la machine ailleurs : il contient tous les secrets.
