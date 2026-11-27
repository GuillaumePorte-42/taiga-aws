# Rôle `taiga`

Déploie Taiga de deux façons, avec les mêmes images et la même passerelle :
- **staging** : Docker Compose (10 conteneurs) dans `/opt/taiga`, playbook `taiga.yml`, fichier `tasks/main.yml` ;
- **production** : stack Docker Swarm sur 3 nœuds, playbook `taiga_production.yml`, fichier `tasks/stack.yml` (une seule fois, sur le premier manager).

## Fichiers
| Fichier | Rôle |
|---|---|
| `defaults/main.yml` | dossiers, images (officielles en version fixe, jamais `latest`), registre, réglages mail par défaut (Mailpit) |
| `files/docker-compose.yml` | Compose du staging, d'après `taigaio/taiga-docker` : valeurs lues dans le `.env` ; + `taiga-mailpit` |
| `files/docker-compose-inits.yml` | `taiga-manage` (image du back + `python manage.py`), pour une commande ponctuelle |
| `files/taiga.conf` | passerelle nginx, **commune** au staging et à la production (voir plus bas) |
| `templates/env.j2` | `.env` du staging (lu par Compose) : images, domaine, secrets, mails |
| `templates/back.env.j2` | `back.env` de la production (lu par Docker : back, async, migrations) |
| `templates/taiga-stack.yml.j2` | stack Swarm : 3 copies des services sans état (1 par nœud), mise à jour une copie à la fois (`stop-first`, `rollback` si échec), journaux vers CloudWatch |
| `templates/comptes.py.j2` | script `manage.py shell` : comptes du staging |
| `tasks/main.yml` | staging : dossier `0700`, fichiers, `.env` `0600` (`no_log`), `docker login`, `docker compose up`, comptes |
| `tasks/stack.yml` | production : dossiers sur l'EFS, `back.env`, fichier de stack, réseau overlay chiffré, migrations, `docker stack deploy` |
| `handlers/main.yml` | redémarrer la passerelle du staging quand ses fichiers changent |

## La passerelle (`taiga.conf`)
- **`resolver 127.0.0.11 valid=10s`** + noms des services dans des variables (`set $taiga_back taiga-back;`) : nginx retrouve un service **recréé** (nouvelle IP) sans redémarrer. Avant le 04/11, il gardait l'IP du démarrage → `502` sur l'API après un déploiement qui recréait le back.
- Avec une variable, nginx transmet le chemin **tel quel** : aucun chemin après le port dans `proxy_pass` (sinon `404`) ; `/media/` passe par un `rewrite` qui retire le préfixe.
- **`/admin/` fermé** (`deny all` → `403`) : l'admin de Django n'est pas exposé sur Internet. En cas de besoin : `manage.py` sur une machine (`docs/runbooks/3-deployer/deployer_production.md`).
- `absolute_redirect off` : redirections relatives (l'ALB déchiffre le HTTPS, nginx écrirait sinon `http://`).
- Staging : le fichier est **monté** dans la passerelle → le handler la redémarre quand il change. Production : config Swarm `taiga-conf-<empreinte md5>` → un nouveau contenu crée une nouvelle config et Swarm met la passerelle à jour seul, une copie à la fois.

## Les mails
Variables `taiga_email_*` (backend, hôte, port, TLS, identifiant, mot de passe) :
| | Staging (défauts du rôle) | Production (`playbooks/group_vars/role_swarm_node.yml`) |
|---|---|---|
| Serveur | `taiga-mailpit:1025` : faux serveur, garde tout, n'envoie rien | Amazon SES `email-smtp.eu-west-3.amazonaws.com:587` (STARTTLS) |
| Identifiants | aucun | `/taiga/production/email_host_user` et `email_host_password` (écrits par `terraform/socle`) |

- `env.j2` : identifiant et mot de passe **entre apostrophes** (Compose les retire). `back.env.j2` : **sans** (Docker lit la ligne telle quelle).
- Interface de Mailpit : tunnel `ssh -N -L 8025:127.0.0.1:8025 staging`, puis `http://localhost:8025`. Tester SES depuis le staging : `docs/runbooks/4-verifier/verifier_les_mails.md`.

## Les comptes du staging (tâche 6)
La base du staging est perdue à chaque reconstruction. Après « Lancer Taiga », le script `comptes.py.j2` est envoyé au back par l'**entrée standard** (`docker compose exec -T taiga-back python manage.py shell`) : pour `admin` (super-utilisateur, compte de service) et `e2e-test` (tests de la CI), il crée le compte s'il manque, remet le mot de passe de Parameter Store s'il a changé, sinon ne fait rien (`changed=0`). Réessais (10 × 15 s) le temps que le back démarre. `no_log`.
Mots de passe : `/taiga/staging/admin_password`, `/taiga/staging/e2e_password` (`terraform/socle`).

## Variables attendues dans l'inventaire
- Staging (`inventories/staging/group_vars/all.yml`) : `taiga_domaine`, `taiga_etiquette_back`, `taiga_etiquette_front`, `taiga_registre_utilisateur`, `taiga_admin_nom`, `taiga_admin_email`, `taiga_admin_mdp`, `taiga_e2e_mdp`.
- Production (`playbooks/group_vars/role_swarm_node.yml` et `inventories/production/group_vars/all.yml`) : `taiga_domaine`, `taiga_ref_back`, `taiga_ref_front` (empreintes `@sha256`), `taiga_postgres_hote`, `taiga_postgres_sslmode`, `taiga_email_*`, `efs_id`, `taiga_registre_utilisateur`.
- Partout : `taiga_env`, `aws_region`, `taiga_secrets` ; dans Parameter Store : `/taiga/<env>/postgres_password`, `secret_key`, `rabbitmq_pass`, `rabbitmq_erlang_cookie`, `email_host_password`, `registry_token`.

## L'utiliser
```bash
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/taiga.yml
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/taiga_production.yml
```
D'habitude par la CI : staging à chaque fusion qui le concerne, production par le bouton. Procédures : `docs/runbooks/3-deployer/`.

## Pièges
- Aucun secret dans le dépôt : `.env` et `back.env` n'existent que sur les machines (`0600`). Ne jamais retirer `no_log`.
- Staging : toujours une étiquette `staging-<commit>` ; production : toujours une empreinte `@sha256` (celle validée en staging).
- `--check` ne voit pas tout : il montre ce qui change, pas si ça marche (variable oubliée dans `env.j2`, 502, 404 du 04/11). Tester sa branche sur le staging depuis la VM avant la MR.
- `docker stack deploy` rend la main **avant** la fin de la mise à jour : vérifier `docker service ps` (un `rollback` de Swarm passerait inaperçu dans un job vert).
- Retour arrière d'une image du back : si elle contenait des **migrations**, revenir à l'ancienne image ne les défait pas.
