# ADR – Deux couches : un socle permanent, des environnements jetables

**Date** : 26/10/2026 · **Statut** : proposé par Guillaume, à valider en équipe

## Contexte
On veut pouvoir détruire et recréer l'infra (coût la nuit, preuve de reproductibilité) sans perdre ce qui doit durer.

## Décision
Le critère n'est pas le prix mais la **durée de vie** : va dans le socle ce qu'on ne peut pas perdre ou recréer sans casse.

**Socle** (dossier `socle/`, créé une fois, jamais détruit) :
- bucket du tfstate : sans lui, Terraform perd la trace de l'infra (fait, voir `adr-socle-tfstate.md`) ;
- zone Route 53 : la recréer change ses serveurs NS, donc refaire la délégation chez IONOS (0,50 $/mois, gardée quand même) ;
- bucket des sauvegardes : les sauvegardes survivent à la base (prévu) ;
- secrets dans Parameter Store, saisis une fois à la main (prévu) ;
- utilisateurs IAM (faits dans la console le 23/10).

**Environnements** (`staging/`, `production/`, un state chacun) : VPC, NAT, nœud Swarm, RDS. On les détruit et on les recrée avec Terraform. Ils **lisent** le socle (state, zone DNS) mais ne le modifient jamais.

## Conséquences
- Détruire un environnement ne coûte rien de permanent, **sauf les données RDS** : sauvegarde (`pg_dump` vers le bucket du socle) avant de détruire, restauration après.
- Le pipeline ne touchera que les environnements ; le socle est appliqué à la main.
