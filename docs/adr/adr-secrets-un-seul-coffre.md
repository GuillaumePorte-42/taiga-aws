# ADR – Un seul coffre pour les secrets : Parameter Store

**Date** : 26/10/2026 · **Statut** : accepté en équipe le 26/10 (Ansible Vault abandonné ; la page Confluence des secrets est déjà à jour)

## Contexte
Deux catégories de secrets : ceux de l'application (variables d'environnement de Taiga) et ceux d'administration (mot de passe admin Grafana, SonarQube, jeton du runner GitLab). Prévu au départ : Parameter Store pour les premiers, Ansible Vault pour les seconds.

## Décision
Tous les secrets d'exécution vont dans **SSM Parameter Store** (`SecureString`, niveau standard, nommage `/projet/<env>/<nom>`). Ansible les lit au moment de l'exécution avec le lookup `amazon.aws.aws_ssm`. Les secrets utilisés seulement par le pipeline restent dans les variables CI/CD GitLab.

## Pourquoi pas Ansible Vault
- Le Vault a besoin d'un mot de passe maître : trois copies locales + une variable GitLab, à partager entre nous. Parameter Store n'ajoute aucun secret partagé : l'accès passe par l'identité IAM de chacun (avec MFA).
- Une seule procédure de rotation (`put-parameter --overwrite`) au lieu de deux, un seul runbook.
- Accès tracé dans CloudTrail ; aucune trace avec le Vault.
- Coût identique (0 €).

## Conséquences
- La machine qui lance Ansible (nos VM, puis le runner) doit avoir le droit `ssm:GetParameter` : le lookup s'exécute sur elle, pas sur l'EC2 configurée.
- Il faut la collection `amazon.aws` et `boto3` sur cette machine.
- Ansible Vault reste une piste citée à l'oral (fonctionne sans AWS).
