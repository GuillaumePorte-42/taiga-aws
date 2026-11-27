# ADR – Socle : bucket S3 du tfstate

**Date** : 26/10/2026 · **Statut** : appliqué par Guillaume, à valider en équipe

## Contexte
Le state Terraform doit être partagé par les trois membres de l'équipe, protégé (il peut contenir des secrets) et jamais perdu. Il a besoin d'un bucket, et ce bucket doit lui-même exister avant tout le reste.

## Décision
- Un **socle** créé une seule fois et jamais détruit, dans le dossier `socle/` du dépôt `taiga-infrastructure`, sur le compte AWS de Guillaume (eu-west-3).
- Bucket `taiga-ledevagilles-tfstate` : accès public bloqué, chiffré (SSE-S3, gratuit), versionné, `prevent_destroy`.
- Verrou natif S3 (`use_lockfile`, Terraform ≥ 1.10), sans DynamoDB.
- Un seul bucket, une clé par dossier : `socle/terraform.tfstate`, puis `staging/…` et `production/…`.
- Œuf et poule : premier `apply` avec un state local, puis `terraform init -migrate-state` vers le bucket.
- Tags automatiques (`default_tags`) : `Projet`, `Environnement`, `GerePar`.
- Le socle est appliqué à la main depuis une VM, pas par le pipeline (proposition).

## Conséquences
- Un `terraform destroy` du socle est refusé.
- Le nom du bucket est écrit en dur dans chaque bloc `backend` (pas de variable possible).
- `.tfstate`, `.terraform/` et `*.tfvars` sont exclus de Git ; `.terraform.lock.hcl` est commité.

## Preuves
`aws s3 ls s3://taiga-ledevagilles-tfstate/socle/` ; `terraform plan` → `No changes.` après la migration (capture : `screenshots/socle/tfstate_socle_dans_buckets3_et_lecture_depuis_s3.png`).
