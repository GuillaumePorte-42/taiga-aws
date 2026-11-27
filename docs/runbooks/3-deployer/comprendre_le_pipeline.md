# Runbook – Le pipeline : qui déclenche quoi

**Pourquoi** : savoir, avant de pousser ou de fusionner, ce que le pipeline va lancer, où, et s'il va redéployer et tester le staging.

**Où** : `.gitlab-ci.yml` à la racine de `taiga-infrastructure`. État au 04/11/2026.

## Les deux sortes de runners
| Runner | Où il tourne | Pour quels jobs | Coût |
|---|---|---|---|
| Runners partagés de GitLab | sur Internet, chez GitLab | les contrôles (jobs **sans** tag) | minutes du quota du groupe : **400 par mois** pour les 3 dépôts |
| Runner privé `taiga-ci` | sur notre machine CI, **dans le VPC** | déploiement et tests (`tags: [taiga-ci]`) | aucune minute GitLab (l'EC2 tourne déjà) |

Le runner privé n'accepte que les jobs qui portent son tag (« Run untagged jobs » décoché), **un job à la fois** (`concurrent = 1`). Il est **protégé** (04/11) : il n'exécute que les jobs des **branches protégées** (`staging`, `production`, et le motif `ci-*`). Raison : il détient la clé SSH qui ouvre la production ; une branche de test quelconque ne doit pas pouvoir la lire. Une branche qui n'est pas `ci-…` voit ses jobs taggés rester en *pending*. Il **va chercher** les jobs chez GitLab (HTTPS sortant par la NAT) : sans NAT, il ne reçoit rien. Ses requêtes vers le staging sortent par la NAT et reviennent par l'ALB : l'IP de la NAT est autorisée par la **règle 11** (`terraform/commun/alb.tf`), sinon `403`.

## Les jobs
| Job | Stage | Quand | Ce qu'il fait |
|---|---|---|---|
| `terraform-fmt`, `terraform-validate`, `tflint`, `trivy` | `validate` | sur une **branche de travail**, si un fichier de `terraform/` change (`.si-terraform-change`) ; **pas** sur `staging` ni `production` (déjà vérifié avant la fusion) | format, validité (providers mis en cache : téléchargés une fois pour les 7 dossiers), bonnes pratiques, failles de configuration (`HIGH`, `CRITICAL` → échec) |
| `gitleaks` | `validate` | sur une **branche de travail**, toujours (`.sur-branche-de-travail`) | secrets dans tout l'historique |
| `deployer-staging` | `deploy` | sur `staging`, si ce qui compose le staging change (`.si-staging-change`) | déploie Taiga sur le staging, puis `verifier_taiga.yml` |
| `deployer-production` | `deploy` | sur `production`, **bouton ▶ (manuel)**, si ce qui compose la prod change (`.si-production-change`) ou *Run pipeline* | déploie la stack Swarm, puis `verifier_taiga.yml` sur le vrai domaine ; `environment: production`, `resource_group: production` (`docs/runbooks/3-deployer/deployer_production.md`) |
| `tests-e2e` | `test` | comme le déploiement (`.si-staging-change`), après lui s'il tourne | Playwright : `e2e-test` se connecte et arrive sur son tableau de bord |
| `tests-charge` | `test` | **automatique** si `ansible/inventories/staging/group_vars/all.yml` ou `ansible/roles/taiga/` change ; sinon **bouton ▶** (manuel) | Locust : 20 utilisateurs, 1 min ; rapport `rapport-locust.html` en artefact (30 jours) |

`.si-staging-change` = branche `staging` **et** changement dans `ansible/playbooks/taiga.yml`, `ansible/roles/taiga/`, `ansible/inventories/staging/`, `ansible/requirements.yml`, `ansible/ansible.cfg` ou `tests/`. Un *Run pipeline* lancé à la main compte comme « tout a changé » : tout part.

`.si-production-change` = branche `production` **et** changement dans `ansible/playbooks/taiga_production.yml`, `ansible/roles/taiga/`, `ansible/inventories/production/`, **`ansible/playbooks/group_vars/role_swarm_node.yml`** (les empreintes des images), `ansible/requirements.yml` ou `ansible/ansible.cfg` ; `when: manual`.

📘 Un job manuel dans des `rules` **bloque** le pipeline tant que personne n'a cliqué (`allow_failure: false` par défaut) : le pipeline de `production` reste « bloqué », c'est voulu.

`yamllint` et `ansible-lint` existent mais sont **désactivés** (point devant le nom : ce sont des modèles, pas des jobs).

## L'ordre sur `staging`
```
validate (contrôles) → deployer-staging (déploiement + verifier_taiga) → tests-e2e → tests-charge
```
Chaque étape attend la précédente (`needs`, avec `optional: true` : un job absent du pipeline n'est pas attendu). Si l'E2E échoue, la charge ne part pas : pas de test de charge sur une application cassée.

## Ce que fait `deployer-staging`, dans l'ordre
1. Image `python:3.13-slim` ; installe `openssh-client`, `ansible-core`, `boto3` et les collections aux versions de `docs/reference/versions_outils.md`.
2. S'identifie à AWS par le **rôle IAM de la machine CI** (`taiga-ec2-ci`), sans clé d'accès.
3. Lit la clé SSH de la CI dans `/taiga/staging/ci_ssh_private_key`, l'écrit dans un fichier `0600` ; affiche seulement son empreinte (`SHA256:y4bi0yw8…`).
4. `ansible-playbook -i inventories/staging playbooks/taiga.yml` avec cette clé, **sans rebond par le bastion** (la CI est déjà dans le VPC).
5. `ansible-playbook playbooks/verifier_taiga.yml` : interface en `200` avec un certificat valide, API en `200` et en JSON, HTTP redirigé vers HTTPS (10 essais, 15 s d'écart).

Le job déploie **l'application** (rôle `taiga`). Le socle des machines (`site.yml`, `common`, UFW…) reste lancé par un humain.

## Les tests (`tests-e2e`, `tests-charge`)
- Mot de passe du compte `e2e-test` lu dans `/taiga/staging/e2e_password` par le rôle de la CI, jamais affiché (le job E2E affiche seulement sa longueur : 44).
- `tests-charge` : changer le nombre d'utilisateurs ou la durée au lancement manuel (bouton ▶, champ *Variables*) : `LOCUST_UTILISATEURS` (20 par défaut), `LOCUST_DUREE` (`1m`). 20 = toute l'équipe en même temps, en plus actifs que des humains ; 50 avant une mise en production ou pour une démo.
- Le job de charge n'échoue que s'il y a des **erreurs** : si Taiga devient plus lent, il reste vert ; lire le rapport (p95).
- Détail des tests, résultats de référence : `tests/README.md`.

## Cas pratiques
| Je veux… | Je fais… |
|---|---|
| déployer une nouvelle version sur le staging | changer l'étiquette dans `ansible/inventories/staging/group_vars/all.yml`, MR, fusion → déploiement, vérification, E2E, charge |
| revenir à la version précédente | remettre l'ancienne étiquette, MR, fusion → même chaîne |
| tout relancer sans rien changer (machine recréée, vérification) | **Build → Pipelines → Run pipeline**, branche `staging` |
| un test de charge à 50 | bouton ▶ de `tests-charge`, `LOCUST_UTILISATEURS` = `50` |
| savoir ce qui a été déployé | le job `deployer-staging` : commit, `PLAY RECAP` ; sur la machine : `ssh staging 'sudo docker compose -f /opt/taiga/docker-compose.yml images'` |
| lire un rapport Locust | job `tests-charge` → *Job artifacts* → *Browse* → `rapport-locust.html` |
| tester une modif d'Ansible avant de fusionner | depuis sa VM, sur sa branche : `--check --diff`, puis **le vrai lancement sur le staging** (prévenir l'équipe) ; la MR ensuite. `--check` ne voit pas tout (variable oubliée, 502, 404 du 04/11) |
| mettre une modif en production | `docs/runbooks/3-deployer/deployer_production.md` (MR `staging` → `production` sans squash, bouton ▶) |
| essayer un job du runner privé sur une branche | la nommer `ci-…` (branche protégée), ajouter une règle **provisoire** pour elle, la retirer avant la MR |

## Lire le résultat
- `changed=0` : le staging était déjà conforme, rien n'a bougé.
- `changed=N` : seuls les conteneurs concernés sont recréés, les données (volumes) restent.
- `UNREACHABLE` : réseau (SG `staging-ssh-ci`, UFW) ou clé. `401` au registre : token ou utilisateur du registre.
- `verifier_taiga` en échec avec `403` : l'IP de la NAT n'est plus autorisée (NAT recréée sans `apply` de `commun/` après).

## Pièges
- Une fusion qui ne touche que `.gitlab-ci.yml` ne lance **ni** le déploiement **ni** l'E2E : pour tout essayer, *Run pipeline*.
- Après une recréation de la NAT (le matin), **`reseau/` avant `commun/`** : l'`apply` de `commun/` relit la nouvelle IP de la NAT pour la règle 11.
- Une correction faite **à la main** sur une machine sera écrasée au prochain déploiement : on corrige par Git.
- Un chemin personnel dans `ansible/ansible.cfg` (ex. `/home/<prénom>/…`) casse Ansible pour tout le monde, CI comprise.
- Le job de production peut être **vert** alors que Swarm est encore en train de remplacer les copies, ou est revenu en arrière (`rollback`) : `docker stack deploy` n'attend pas. Vérifier `docker service ps` (runbook de la production).
- Minutes partagées : une MR qui touche `terraform/` coûte ~3 min sur sa branche. Si le quota s'épuise, plan B : tous les jobs sur `taiga-ci` (`default: tags`), avec des branches `ci-…` obligatoires.

## Pistes
Traçabilité des images dans le job (`docker compose images`) et `environment: staging` ; seuil de temps de réponse pour Locust ; image CI à nous (outils déjà installés) ou cache `pip` ; job de production qui attend `UpdateStatus = completed` ; promotion automatique de l'image (le pipeline du back ou du front ouvre la MR qui change l'empreinte) ; `terraform plan` en lecture seule dans la CI (demande des droits IAM de lecture larges : à peser).
