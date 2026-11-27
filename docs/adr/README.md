# Décisions d'architecture (ADR)

Ces quatre ADR datent du début du projet, entre le 26 et le 28 octobre 2026. La référence de l'équipe était Confluence, un espace privé, et ces fichiers sont mes copies personnelles. Je les publie tels quels, avec leur statut de l'époque. Les chemins ont changé depuis, par exemple `socle/` est devenu `terraform/socle/`.

| Décision | Fichier |
|---|---|
| Le bucket S3 du state Terraform, créé une fois et jamais détruit | [adr-socle-tfstate.md](adr-socle-tfstate.md) |
| Un socle permanent, des environnements jetables | [adr-socle-et-environnements.md](adr-socle-et-environnements.md) |
| Un seul coffre pour les secrets, Parameter Store | [adr-secrets-un-seul-coffre.md](adr-secrets-un-seul-coffre.md) |
| Un seul ALB pour le staging et la production, et les noms de domaine | [adr-alb-et-domaines.md](adr-alb-et-domaines.md) |
