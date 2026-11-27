# Runbook – Tout remonter sur un nouveau compte AWS (amorçage)

**Pourquoi** : remonter tout le projet sur un compte AWS vide (changement de compte, compte perdu, passation au client). C'est la reconstruction la plus complète : rien n'existe, pas même le bucket qui garde le state de Terraform. Le code décrit presque tout ; ce runbook liste **ce que le code ne fait pas** (les comptes des personnes, l'œuf et la poule du state, le DNS chez IONOS, les secrets saisis à la main, les données) et l'ordre à suivre.

**Statut** : **jamais fait de bout en bout**. Écrit le 06/11 à partir de ce qui a été fait à la main au début du projet (23/10 et 26/10) et de la reconstruction du 05/11 (`reconstruire_tout.md`). Le premier qui le suit note les écarts et les durées.

**Où** : console AWS (étape 1), puis sa VM, à la racine de `taiga-infrastructure`, sur `staging` à jour. **Une seule personne** fait les `apply` ; l'équipe est prévenue.

**Prérequis** : les outils de la VM (`docs/reference/versions_outils.md`), le dépôt à jour, l'accès au registrar du domaine (IONOS), l'accès au groupe GitLab et au canal Discord des alertes.

## Ce que le code ne recrée pas tout seul
| Quoi | Pourquoi | Étape |
|---|---|---|
| Utilisateurs IAM de l'équipe, groupe, MFA, budgets | faits à la main dans la console (23/10), pas dans Terraform | 1 |
| Noms des buckets `taiga-ledevagilles-tfstate` et `-backups` | un nom de bucket est **unique dans tout AWS** : tant que l'ancien compte les garde, le nouveau ne peut pas les créer | 2 |
| Bucket du state | Terraform a besoin du bucket pour ranger son state… et c'est Terraform qui crée le bucket (œuf et poule) | 3 |
| Délégation du domaine | une nouvelle zone Route 53 a **4 nouveaux serveurs NS**, à recopier chez IONOS | 4 |
| Domaine SES et destinataires | nouvelle identité, nouveaux jetons DKIM ; compte neuf en **bac à sable**, adresses de l'équipe à revérifier | 5 |
| Paramètres saisis à la main | jetons GitLab, clé SSH de la CI, webhook Discord, IP de l'équipe (`docs/reference/parametres.md`) | 6 |
| Données de la production | base RDS **neuve et vide**, EFS vide : à restaurer depuis la dernière sauvegarde de l'ancien compte | 0 et 9 |

Tout le reste (réseau, ALB, certificat, DNS de Taiga, instances, IAM des machines, secrets générés, Swarm, Taiga, supervision, sauvegardes) vient du code, dans l'ordre habituel.

## 0. Avant de quitter l'ancien compte (sinon, données perdues)
1. **Une sauvegarde fraîche** de la production (base + médias) : `docs/runbooks/7-urgence/reconstruire_tout.md`, « Avant de détruire », point 1. Attendu : un fichier de chaque, daté de maintenant.
2. **La rapatrier dans la VM** (le nouveau compte n'aura pas le droit de lire l'ancien bucket) :
   ```bash
   mkdir -p ~/migration && chmod 700 ~/migration
   aws s3 cp s3://taiga-ledevagilles-backups/postgres/<dernier>.dump ~/migration/
   aws s3 cp s3://taiga-ledevagilles-backups/media/<dernier>.tar.gz ~/migration/
   ls -lh ~/migration
   ```
   Copier les noms exacts depuis `aws s3 ls … | sort | tail -1` (piège du 05/11 : le `Z` final oublié). Attendu : deux fichiers, de taille non nulle.
3. **Les paramètres saisis à la main** : soit on les **recrée** (nouveaux jetons GitLab, nouveau webhook Discord : le plus propre), soit on les **copie** de compte à compte sans les afficher (étape 6). Noter lesquels on recrée.
4. **Décider à 3** ce que devient l'ancien compte (tout détruire, fermer le compte) et **quand** : ses buckets bloquent les noms (étape 2).

## 1. Le compte et les personnes (console AWS, une seule fois)
Fait le 23/10 sur le compte actuel, à refaire à l'identique :
1. **Root** : MFA activé ; « accès IAM aux informations de facturation » activé (une fois) ; ensuite, root n'est plus utilisé.
2. **Budgets** : `projet-final-mensuel` (20 $, crédits exclus) et `vrai-argent` (1 $, crédits inclus), alertes par mail.
3. **Groupe IAM** `projet-admins` avec la politique `AdministratorAccess` (choix assumé pour un projet d'équipe ; piste : moindre privilège).
4. **Un utilisateur IAM par personne**, `<prénom>-admin`, dans le groupe (droits **par le groupe seulement**, rien attaché directement), accès console avec mot de passe temporaire à changer, **MFA** obligatoire. Identifiant et mot de passe envoyés par deux canaux différents.
5. **Clés d'accès pour la CLI** : chacun crée sa clé (*Security credentials* → *Create access key* → CLI) et la range dans un **profil** de sa VM, sans toucher à celui de l'ancien compte :
   ```bash
   aws configure --profile nouveau      # clé, secret, région eu-west-3, sortie json
   export AWS_PROFILE=nouveau
   aws sts get-caller-identity
   ```
   Attendu : le **nouveau** numéro de compte et `…:user/<prénom>-admin`. Terraform, Ansible et la CLI utilisent ce profil tant que `AWS_PROFILE` est exporté (à refaire dans chaque nouveau terminal).

Piège vécu le 23/10 : en retirant une politique de son propre utilisateur, on peut se couper tous ses droits. Ne jamais modifier ses propres droits sans root ou un autre admin sous la main.

## 2. Les noms uniques (une MR, avant tout `apply`)
Si l'ancien compte garde ses buckets, choisir de **nouveaux noms** (exemple : suffixe `-2`) et les changer partout :
```bash
grep -rn -e "taiga-ledevagilles-tfstate" -e "taiga-ledevagilles-backups" --include=*.tf --include=*.yml --include=*.j2 --include=*.md .
```
Attendu : le bloc `backend "s3"` des 6 dossiers de `terraform/`, les `terraform_remote_state` (`commun/`, `staging/`, `production/`, `donnees/`), `socle/tfstate.tf`, `socle/backups.tf`, `ansible/roles/sauvegardes/defaults/main.yml` (`sauvegardes_bucket`), et la doc. Le bloc `backend` n'accepte pas de variable : on change le texte. Branche, MR, fusion dans `staging`.

Si l'ancien compte a **supprimé** ses buckets, on peut garder les noms ; AWS prévient qu'un nom libéré peut mettre un moment à redevenir disponible.

## 3. L'amorçage du socle : l'œuf et la poule
Le socle crée le bucket du state, mais son propre state doit d'abord vivre **en local**, puis être déplacé dans le bucket (fait ainsi le 26/10).
1. **Neutraliser le backend** le temps du premier `apply` : dans `terraform/socle/main.tf`, mettre en commentaire tout le bloc `backend "s3" { … }` (sans commit).
2. **Créer le socle avec un state local** :
   ```bash
   terraform -chdir=terraform/socle init
   terraform -chdir=terraform/socle plan
   terraform -chdir=terraform/socle apply
   ```
   Lire le plan : seulement des créations (buckets, zone DNS, secrets, SES, utilisateur `taiga-ses-smtp`…), **0 to destroy**. Attendu : `Apply complete!` et un fichier `terraform/socle/terraform.tfstate` (il contient des secrets : ne jamais le commiter, le `.gitignore` le bloque).
3. **Remettre le backend** (retirer les commentaires), puis déplacer le state dans le bucket :
   ```bash
   terraform -chdir=terraform/socle init -migrate-state
   ```
   Répondre `yes` à la copie. Contrôles :
   ```bash
   aws s3 ls s3://taiga-ledevagilles-tfstate/socle/
   terraform -chdir=terraform/socle plan
   ```
   Attendu : `terraform.tfstate` dans le bucket, puis `No changes`.
4. **Effacer la copie locale** (elle contient les secrets en clair) : `rm terraform/socle/terraform.tfstate terraform/socle/terraform.tfstate.backup`. `git status` ne doit montrer aucun changement dans `main.tf`.

Le socle crée aussi les secrets générés : nouveaux mots de passe (PostgreSQL, Django, RabbitMQ, Grafana, `admin`, `e2e-test`), nouveaux identifiants SMTP de SES. Rien à recopier : Ansible et Terraform les lisent au bon moment.

## 4. Le domaine : la délégation chez IONOS
1. Les 4 serveurs de la nouvelle zone :
   ```bash
   terraform -chdir=terraform/socle output name_servers
   ```
2. Chez IONOS (domaine `taiga-ledevagilles.fr` → serveurs de noms personnalisés) : remplacer les 4 anciens par les 4 nouveaux.
3. Attendre la propagation, puis vérifier :
   ```bash
   dig NS taiga-ledevagilles.fr +short
   ```
   Attendu : les 4 nouveaux serveurs `awsdns`. Tant que ce n'est pas le cas, le certificat (`commun/`) ne se valide pas et SES ne vérifie pas le domaine : l'`apply` de `commun/` attend, puis échoue.

## 5. Les mails (SES)
1. Domaine vérifié par DKIM (les 3 CNAME sont créés par le socle) :
   ```bash
   aws sesv2 get-email-identity --email-identity taiga-ledevagilles.fr --query "DkimAttributes.Status" --output text --region eu-west-3
   ```
   Attendu : `SUCCESS` (quelques minutes après la délégation ; le 04/11 : quelques minutes).
2. Compte neuf = **bac à sable** : seulement vers des adresses vérifiées, 200 mails / 24 h. Revérifier l'adresse de chaque personne : `docs/runbooks/4-verifier/verifier_les_mails.md`.

## 6. Les paramètres saisis à la main
Liste et usage : `docs/reference/parametres.md`, parties « Emplacement créé par Terraform, valeur saisie à la main » et « Créés entièrement à la main ».
1. **IP de l'équipe** (sinon `reseau/` échoue, et personne n'entre sur le bastion) : `docs/runbooks/1-equipe/changer_son_ip.md`.
2. **Les autres**, à recréer ou à copier :

   | Paramètre | Le plus simple |
   |---|---|
   | `/taiga/staging/registry_token`, `/taiga/production/registry_token` | copier (l'utilisateur du token est déjà écrit dans l'inventaire) ou recréer le deploy token dans GitLab (`read_registry`) et changer `taiga_registre_utilisateur` |
   | `/taiga/ci/gitlab_runner_token` | copier : le runner du groupe GitLab ne change pas |
   | `/taiga/ci/sonar_token` | copier (lu par le rôle `ci` : absent → `ci.yml` échoue) |
   | `/taiga/staging/ci_ssh_private_key` | copier (la clé publique est déjà dans `cles_ssh/ci/`) |
   | `/taiga/admin/alert_webhook_url` | copier, ou nouveau webhook Discord (absent → `supervision.yml` échoue) |

   Copier sans afficher, d'un profil à l'autre (`ancien` = le profil de l'ancien compte) :
   ```bash
   P=/taiga/ci/gitlab_runner_token
   VALEUR=$(aws ssm get-parameter --profile ancien --name "$P" --with-decryption --query Parameter.Value --output text --region eu-west-3)
   aws ssm put-parameter --profile nouveau --name "$P" --type SecureString --value "$VALEUR" --region eu-west-3
   unset VALEUR
   ```
   Attendu : `"Version": 1`. Recommencer avec chaque chemin. Pour la clé SSH (plusieurs lignes), les guillemets autour de `$VALEUR` gardent les retours à la ligne.
3. **Contrôle** (noms seulement) :
   ```bash
   aws ssm get-parameters-by-path --path /taiga --recursive --query "Parameters[].Name" --output text --region eu-west-3
   ```
   Attendu : la liste de `docs/runbooks/7-urgence/reconstruire_tout.md`, « Avant de détruire », point 2, **sauf** `db_host` et `efs_id` (créés aux étapes 7).

## 7. Terraform, dans l'ordre
Chaque `apply` doit finir sans erreur avant le suivant ; lire chaque plan (que des créations).
```bash
terraform -chdir=terraform/reseau init && terraform -chdir=terraform/reseau apply
terraform -chdir=terraform/donnees init && terraform -chdir=terraform/donnees apply
terraform -chdir=terraform/commun init && terraform -chdir=terraform/commun apply
terraform -chdir=terraform/staging init && terraform -chdir=terraform/staging apply
terraform -chdir=terraform/production init && terraform -chdir=terraform/production apply
```
- `reseau/` : VPC, sous-réseaux, SG, NAT ; attendre la NAT `available` (`arreter_demarrer.md`, matin, étape 2).
- `donnees/` : la RDS **neuve et vide**, plusieurs minutes ; écrit `/taiga/production/db_host`.
- `commun/` : bastion, supervision, CI, ALB, certificat (attend la délégation de l'étape 4), DNS, rôles IAM.
- `production/` : 3 nœuds, EFS ; écrit `/taiga/production/efs_id`.

## 8. SSH et Ansible
Comme une reconstruction : `docs/runbooks/7-urgence/reconstruire_tout.md`, parties 2 (routine SSH) et 3 (ordre des playbooks de `ansible/README.md`). Le runner se réenregistre seul avec son jeton (rôle `ci`).

## 9. Restaurer les données de la production
1. **Déposer la sauvegarde rapatriée** dans le nouveau bucket des sauvegardes :
   ```bash
   aws s3 cp ~/migration/<dernier>.dump s3://taiga-ledevagilles-backups/postgres/
   aws s3 cp ~/migration/<dernier>.tar.gz s3://taiga-ledevagilles-backups/media/
   ```
2. **Restaurer** la base puis les médias : `docs/runbooks/5-donnees/sauvegarder_restaurer.md`, partie 6 « Restaurer ».
3. **Effacer** `~/migration` une fois la restauration vérifiée (données du client).

## 10. GitLab
- Runner `taiga-ci` en ligne (nouvelle instance) ; supprimer l'ancien « runner manager » hors ligne.
- Rien d'autre : la CI n'a aucune clé AWS, elle utilise le rôle IAM de l'instance CI.

## 11. Vérifier
Comme une reconstruction : `docs/runbooks/7-urgence/reconstruire_tout.md`, partie 5 (sites, services, runner, pipeline du staging, Grafana, `/admin/` en 403, un mail, une sauvegarde manuelle), **plus** : se connecter en production avec un compte existant (preuve que la base restaurée est la bonne) et ouvrir une pièce jointe (médias restaurés).

## Pièges
- **Mauvais compte** : vérifier `aws sts get-caller-identity` avant chaque `apply`. Un `apply` sur l'ancien compte avec le nouveau code (noms changés) y créerait des ressources en double.
- **Le state local du socle** contient des secrets en clair : l'effacer après `-migrate-state`.
- **Délégation IONOS oubliée** : certificat jamais délivré, SES jamais vérifié, `commun/` bloqué.
- **Compte neuf** : quotas par défaut (instances, SES en bac à sable) à vérifier dans *Service Quotas* si une création échoue sur une limite.
- **Les URL et les IP changent** (bastion, NAT, ALB) : routine SSH, `supervision.yml` après la création des machines.
- **Secrets régénérés** : le mot de passe de Grafana et ceux des comptes du staging changent (les lire dans Parameter Store).

## Mesuré (à remplir la première fois)
| Étape | Début | Fin | Remarques |
|---|---|---|---|
| 0. sauvegarde et rapatriement | | | |
| 1. compte et personnes | | | |
| 3. amorçage du socle | | | |
| 4. délégation IONOS | | | |
| 7. Terraform | | | |
| 8. Ansible | | | |
| 9. restauration | | | |
| 11. vérifications | | | |

## Pistes
- Déclarer dans le socle les emplacements des paramètres saisis à la main (valeur `A_REMPLIR` + `ignore_changes`), comme `ips_equipe` : le compte neuf aurait toute la liste.
- Groupe et utilisateurs IAM de l'équipe dans Terraform (ou IAM Identity Center) ; moindre privilège à la place d'`AdministratorAccess`.
- Copie des sauvegardes dans un autre compte ou une autre région (règle 3-2-1) : la migration n'aurait plus besoin de passer par la VM.
