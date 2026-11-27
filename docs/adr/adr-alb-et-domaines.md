# ADR – Un seul ALB et les noms de domaine

**Date** : 28/10/2026 · **Statut** : proposé par Guillaume, à valider en équipe

## Contexte
Taiga doit être joignable en HTTPS : sans HTTPS, la connexion échoue (cookies `Secure`). Le staging doit reproduire la prod (même chemin, mêmes réglages), sans être ouvert au public. Un ALB se paie à l'heure.

## Décision
- **Un seul ALB** public pour la prod et le staging.
- **Un nom par environnement** : `taiga-ledevagilles.fr` (prod, enregistrement alias Route 53 à la racine) et `staging.taiga-ledevagilles.fr` (staging). Le front et le back sont sous le même nom : la passerelle nginx de Taiga sépare `/`, `/api`, `/admin` et `/events`.
- **Un seul certificat ACM** : `taiga-ledevagilles.fr` + `*.taiga-ledevagilles.fr`, validé par DNS dans la zone Route 53 du socle.
- **Écouteurs** : HTTP 80 redirigé vers HTTPS 443 ; sur le 443, une règle par nom (`host header`) vers le target group de chaque environnement.
- **Staging fermé** : la règle du staging n'accepte que les IP de `/taiga/reseau/ips_equipe` et l'IP de la NAT ; sinon 403. `sg-alb` reste ouvert à Internet pour la prod.
- **TLS terminé sur l'ALB** : HTTP en clair entre l'ALB et les nœuds, seulement dans le VPC ; le SG des nœuds n'accepte que `sg-alb`.
- **Tests E2E et Locust** lancés par le runner privé : il sort par la NAT, donc avec une IP fixe autorisée sur le staging.

## Conséquences
- Un seul ALB à payer (~0,025 $/h + usage), à détruire quand on ne s'en sert pas.
- L'IP de la NAT change si la NAT est recréée : la règle du staging doit la lire depuis Terraform, jamais en dur.
- Taiga doit savoir que l'utilisateur est en HTTPS (en-tête `X-Forwarded-Proto` posé par l'ALB, schéma `https` dans ses variables).
- Pistes : HTTPS jusqu'aux nœuds (target group en HTTPS) ; un tir Locust depuis l'extérieur d'AWS.

## Preuves
`dig NS taiga-ledevagilles.fr +short` → les 4 serveurs Route 53 (délégation active, 28/10). À venir : certificat « Issued », redirection 80 → 443, 403 sur le staging depuis une IP extérieure.
