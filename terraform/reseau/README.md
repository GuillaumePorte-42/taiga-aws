# Réseau

**Dossier** : `terraform/reseau/` · **State** : `reseau/terraform.tfstate` · **Fait le** 26/10, security groups le 27/10 (Guillaume)

## Ce qui est en place
- Un seul VPC `taiga-vpc` (`10.0.0.0/16`) pour staging et prod.
- 10 sous-réseaux sur les 3 AZ de Paris : publics `10.0.1-3.x`, applicatifs `10.0.11-13.x`, données `10.0.21-23.x`, staging `10.0.33.x` (zone C).
- 3 tables de routage : publique (→ Internet Gateway), privée (→ NAT : applicatifs et staging), isolée (données, aucune sortie). La table principale du VPC (sans nom) n'est utilisée par aucun sous-réseau.
- Une NAT Gateway + son Elastic IP en Public A, créée par chaque `apply` et **détruite le soir** (`destroy -target`, voir `docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md`). Une seule NAT pour les 3 zones : point de défaillance unique **pour le trafic sortant seulement** (le site reste servi par l'ALB) ; piste : une NAT et une table privée par zone (~35 $/mois par NAT).
- Endpoint S3 Gateway (gratuit) sur la table privée.
- 8 security groups (`taiga-sg-alb`, `bastion`, `nodes`, `staging`, `rds`, `efs`, `monitoring`, `ci`), conformes au tableau de la page Confluence. Seuls l'ALB (80, 443) et le bastion (22) acceptent des connexions venant d'Internet. Sortie ouverte partout.
- SSH sur le bastion : seulement depuis les IP de l'équipe, lues dans Parameter Store (`/taiga/reseau/ips_equipe`, créé par `socle/`, rempli à la main : voir `docs/runbooks/1-equipe/changer_son_ip.md`).

## Comment ça marche, simplement
Le plan d'adressage est écrit une fois dans un `locals` (une ligne par sous-réseau, avec son rôle `public` / `prive` / `isole`). Une boucle `for_each` crée les sous-réseaux, une autre les rattache à la table de leur rôle. La route vers la NAT est une ressource à part : on peut détruire la NAT sans toucher à la table privée.

Les security groups suivent la même idée : la matrice `regles_entree` (`security_groups.tf`) a une ligne par flux (SG cible, port, protocole, et l'origine : un autre SG ou une plage d'IP, l'autre case à `null`). Une boucle crée une règle par ligne. Les sources sont des SG plutôt que des IP : la règle reste juste si une machine change d'adresse.

## Utiliser
- Sorties lues par `donnees/`, `commun/`, `staging/` et `production/` (`terraform_remote_state`) : `vpc_id`, `subnet_ids["staging-c"]`, `security_group_ids["nodes"]`… ; `commun/` lit aussi l'IP de la NAT par son tag `Name = taiga-nat-eip`.
- Tant que la NAT est éteinte, un `apply` complet la rallume. Le matin : `reseau/` **avant** `commun/` et **avant** de démarrer les machines (`docs/runbooks/2-chaque-jour/arreter_demarrer.md`). Pour ne toucher qu'aux SG :
  `terraform apply -target=aws_security_group.main -target=aws_vpc_security_group_ingress_rule.main -target=aws_vpc_security_group_ingress_rule.bastion_ssh -target=aws_vpc_security_group_egress_rule.tout`
- Ajouter un flux = une ligne dans `regles_entree`. Ajouter un sous-réseau = une ligne dans `locals` (`subnets.tf`).

## Coût
Tout est gratuit sauf la NAT (~0,05 $/h + trafic) et son IP (~0,005 $/h).

## Pièges
- La NAT met 1 à 3 min à se créer et plusieurs minutes à se supprimer. **Jamais de suppression dans la console** (le state ne le saurait pas).
- Le DNS du VPC (`10.0.0.2`) ne passe pas par la NAT : une machine privée résout les noms même NAT éteinte, mais ne peut pas les joindre.
- La route vers la NAT est une ressource à part (`aws_route`) : ne pas la remettre dans la table, sinon `destroy -target` sur la NAT détruirait toute la table privée.
- Liste d'IP vide ou encore à `A_REMPLIR` : personne n'entre sur le bastion (ou l'`apply` échoue). Quand une IP change : `docs/runbooks/1-equipe/changer_son_ip.md`.
- `insecure_value` et non `.value` pour lire les IP : le provider marque toujours `.value` comme sensible, et Terraform refuse une valeur sensible dans un `for_each`. Les IP ne sont pas un secret, elles s'affichent dans le plan.
- Changer la **description** ou le nom d'un SG le fait détruire puis recréer (bloqué tant qu'une machine l'utilise). Renommer une clé de `regles_entree` supprime puis recrée la règle (coupure brève).
- AWS refuse les accents dans les descriptions de SG.
- Lire la **liste** des ressources d'un plan, pas seulement le total : un « 39 to add » peut être normal (NAT éteinte + SG pas encore créés).

## Décisions et preuves
Un seul VPC, une seule NAT, endpoint S3, tableau des SG : page « Décisions d'architecture » dans Confluence.
