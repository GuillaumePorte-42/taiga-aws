# Carte de Parameter Store

**Pourquoi** : tous les secrets et quelques valeurs partagées vivent dans AWS Systems Manager Parameter Store, jamais dans Git. Cette carte dit, pour chaque paramètre, **qui l'écrit** et **qui le lit**. Avant de changer une valeur, regarder la colonne « lu par » : c'est ce qu'il faudra relancer.

**Règles** : chemins `/taiga/<env>/…` ; secrets en `SecureString` ; jamais affichés (`no_log: true` dans Ansible, `read -s` au clavier). Lecture : politique IAM `taiga-lecture-secrets` (`/taiga/*`), portée par les rôles des machines (dont `taiga-ec2-ci`) et par nos comptes.

Pour voir les noms (sans les valeurs) :
```bash
aws ssm get-parameters-by-path --path /taiga --recursive --query "Parameters[].[Name,Type]" --output table --region eu-west-3
```

## Créés par Terraform, valeur générée
| Paramètre | Écrit par | Lu par |
|---|---|---|
| `/taiga/staging/postgres_password` | `terraform/socle` (`random_password`) | Ansible : `.env` du staging (conteneur `taiga-db` et back) |
| `/taiga/production/postgres_password` | `terraform/socle` | **Terraform `donnees/`** (mot de passe de la RDS) **et** Ansible (`back.env`, `.pgpass` des sauvegardes) : la même valeur des deux côtés |
| `/taiga/<env>/secret_key` | `terraform/socle` | Ansible : clé Django du back et de `taiga-protected` / events |
| `/taiga/<env>/rabbitmq_pass` | `terraform/socle` | Ansible : RabbitMQ, back, async, events |
| `/taiga/<env>/rabbitmq_erlang_cookie` | `terraform/socle` | Ansible : RabbitMQ |
| `/taiga/admin/grafana_admin_password` | `terraform/socle` | Ansible : rôle `supervision` (Grafana) |
| `/taiga/production/postgres_monitoring_password` | `terraform/socle` | Ansible : rôle `supervision` (utilisateur `monitoring` de RDS, postgres_exporter) |
| `/taiga/staging/admin_password` | `terraform/socle` (04/11) | Ansible : compte `admin` du staging (rôle `taiga`, tâche des comptes) ; nous, pour se connecter (presse-papier) |
| `/taiga/staging/e2e_password` | à la main le 02/11 (`openssl rand`), **géré par `terraform/socle` depuis le 04/11** (`import`, valeur gardée par `ignore_changes` ; sur un compte neuf : aléatoire) | Ansible : compte `e2e-test` ; tests E2E et Locust de la CI (`E2E_PASSWORD`) |

## Créés par Terraform, valeur calculée
| Paramètre | Écrit par | Lu par |
|---|---|---|
| `/taiga/production/db_host` (`String`) | `terraform/donnees` : adresse de la RDS | Ansible : `taiga_postgres_hote` (`playbooks/group_vars/role_swarm_node.yml`), supervision |
| `/taiga/production/efs_id` (`String`) | `terraform/production` : ID de l'EFS (04/11) | Ansible : `efs_id` (`inventories/production/group_vars/all.yml`) |
| `/taiga/<env>/email_host_password` | `terraform/socle` : mot de passe SMTP de SES (`ses_smtp_password_v4` de la clé de `taiga-ses-smtp`) ; avant le 04/11 : `A_REMPLIR` | Ansible : `back.env` de la production ; le staging (Mailpit) ne s'en sert pas, sauf test SES avec `-e` |
| `/taiga/<env>/email_host_user` | `terraform/socle` : ID de la clé d'accès de `taiga-ses-smtp` (04/11) | Ansible : `taiga_email_utilisateur` (production) |

## Emplacement créé par Terraform, valeur saisie à la main
| Paramètre | Valeur | Lu par | Procédure |
|---|---|---|---|
| `/taiga/reseau/ips_equipe` (`StringList`) | IP publiques de l'équipe, `1.2.3.4/32,…` | Terraform : SG du bastion (`reseau/`) et règle staging de l'ALB (`commun/`) | `docs/runbooks/1-equipe/changer_son_ip.md` |

## Créés entièrement à la main (pas encore dans Terraform)
| Paramètre | Valeur | Lu par | Procédure |
|---|---|---|---|
| `/taiga/<env>/registry_token` | token de déploiement GitLab (`read_registry`) ; l'**utilisateur** (pas un secret) va dans l'inventaire (`taiga_registre_utilisateur`) | Ansible : `docker login` (staging : `tasks/main.yml` ; production : `tasks/stack.yml`) | à écrire |
| `/taiga/ci/gitlab_runner_token` | token du runner du groupe | Ansible : rôle `ci` (réenregistre le runner sur une machine neuve) | `docs/runbooks/6-ci/gerer_le_runner.md` |
| `/taiga/staging/ci_ssh_private_key` | clé SSH privée de la CI (sert **aussi** à la production malgré son chemin) | jobs `deployer-staging` et `deployer-production` | `docs/runbooks/6-ci/gerer_la_cle_ssh_ci.md` |
| `/taiga/admin/alert_webhook_url` | adresse du webhook Discord des alertes | Ansible : rôle `supervision` (Alertmanager). **Absent → `supervision.yml` échoue** | à écrire (vérifier qu'il existe avant une reconstruction) |
| `/taiga/ci/sonar_token` | jeton SonarCloud | Ansible : rôle `ci` (`ci_sonar_token_ssm`), transmis aux jobs du runner (`SONAR_TOKEN`). **Absent → `ci.yml` échoue** (le `lookup` ne tolère pas un paramètre manquant) | à écrire |

Sur un **compte AWS neuf**, tous ces paramètres sont à recréer ou à copier : `docs/runbooks/7-urgence/changer_de_compte_aws.md`, étape 6.

Piste : déclarer aussi ces emplacements dans `socle` (valeur `A_REMPLIR` + `ignore_changes`), pour qu'un compte neuf les ait tous ; renommer la clé de la CI en `/taiga/ci/ssh_private_key`.

## Changer une valeur
1. `aws ssm put-parameter --name <chemin> --type SecureString --value "…" --overwrite --region eu-west-3` (ou `file://` pour un fichier). Pour ne pas la laisser dans l'historique du shell : `read -s VALEUR` puis `--value "$VALEUR"`.
2. Relancer ce qui la lit (colonne « lu par ») : un playbook, ou un `apply` pour ce que lit Terraform.
3. Une valeur **écrite par Terraform** ne se change pas à la main : Terraform la remettrait au prochain `apply`. On change le code (ou `-replace` pour régénérer).

## Pièges
- `postgres_password` de la production : le changer dans Parameter Store **ne change pas** le mot de passe de la RDS tant que `terraform/donnees` n'est pas réappliqué ; entre les deux, le back ne se connecte plus.
- Une valeur lue ou écrite par Terraform (`ips_equipe`, `postgres_password`, mot de passe SMTP) finit dans son state (bucket chiffré).
- Changement de compte AWS : `socle` régénère les secrets et les identifiants SES ; les paramètres « entièrement à la main » sont à remettre.
