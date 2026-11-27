# Socle

**Dossier** : `terraform/socle/` du dépôt `taiga-infrastructure` · **State** : `socle/terraform.tfstate` · **Fait le** 26/10 (Guillaume)

## Ce qui est en place
- Bucket `taiga-ledevagilles-tfstate` : les states Terraform de tous les dossiers (un fichier par dossier). Privé, chiffré, versionné, verrou natif (`use_lockfile`), `prevent_destroy`.
- Zone Route 53 `taiga-ledevagilles.fr`, déléguée depuis IONOS (4 serveurs `awsdns`).
- Bucket `taiga-ledevagilles-backups` : dumps PostgreSQL (`postgres/`) et volume media (`media/`). Mêmes protections ; sauvegardes supprimées après 90 jours, anciennes versions 7 jours plus tard.
- **Secrets** (`secrets.tf`, Parameter Store, `SecureString`) : mots de passe générés par Terraform pour les deux environnements (`postgres_password`, `secret_key`, `rabbitmq_pass`, `rabbitmq_erlang_cookie`), Grafana, utilisateur `monitoring` de RDS, comptes du staging (`/taiga/staging/admin_password` ; `/taiga/staging/e2e_password`, créé à la main le 02/11 puis **importé** le 04/11 avec sa valeur gardée par `ignore_changes`), identifiants SMTP de SES (`/taiga/<env>/email_host_user`, `email_host_password`), emplacement de `/taiga/reseau/ips_equipe` (valeur saisie à la main). Liste complète : `docs/reference/parametres.md`.
- **Amazon SES** (`ses.tf`) : identité du domaine (`prevent_destroy` : recréée, elle aurait de nouveaux jetons DKIM), 3 CNAME DKIM, enregistrement **DMARC** (`p=none`, on observe), utilisateur IAM `taiga-ses-smtp` limité à `ses:SendRawEmail`, sa clé d'accès dont Terraform déduit le mot de passe SMTP (`ses_smtp_password_v4`). Compte en **bac à sable** : seulement vers des adresses vérifiées, 200 mails / 24 h.
- Tags automatiques sur tout : `Projet`, `Environnement = socle`, `GerePar = terraform`.

## Comment ça marche, simplement
Le socle contient ce qui doit survivre à tout `destroy`. Le bucket du state a été créé avec un state local, puis le state a été déplacé dedans (`terraform init -migrate-state`). Les autres dossiers (`reseau/`, `commun/`, `staging/`, `production/`) rangent leur state dans ce bucket, une clé chacun. Déplacé sous `terraform/` le 28/10 : la clé du state n'a pas changé (`plan` → `No changes`).

## L'utiliser
Clés d'accès AWS personnelles configurées (`aws configure`), Terraform ≥ 1.10, puis dans `terraform/socle/` : `terraform init` et `terraform plan` → `No changes`. Toute modification passe par une MR, l'`apply` se fait après la fusion.

## Pièges
- `prevent_destroy` bloque `terraform destroy`, pas une suppression dans la console : tout le monde est admin, prudence.
- Le bloc `backend` n'accepte pas de variable : le nom du bucket est écrit en dur dans chaque dossier.
- L'expiration des sauvegardes compte l'âge, pas le nombre : sans nouvelle sauvegarde pendant 90 jours, le bucket se vide.
- Ne jamais mettre d'expiration sur le bucket du state.
- **Le mot de passe SMTP de SES est dans le state** (bucket privé, chiffré) : c'est le prix de la reproductibilité. Rotation : `terraform apply -replace=aws_iam_access_key.ses_smtp`.
- **Les destinataires SES ne sont pas dans Terraform** : adresses personnelles, vérifiées une par une (`aws sesv2 create-email-identity`, puis clic) : `docs/runbooks/4-verifier/verifier_les_mails.md`.
- Un `import` ne se laisse pas en place : sur un compte neuf, la ressource n'existe pas encore et le `plan` échouerait.

## Outputs
`tfstate_bucket`, `backups_bucket`, `name_servers` (les 4 NS déclarés chez IONOS).

## Décisions et preuves
ADR du tfstate et du socle : page « Décisions d'architecture » dans Confluence.
