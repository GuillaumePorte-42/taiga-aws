# Commun

**Dossier** : `terraform/commun/` · **State** : `commun/terraform.tfstate` · **Créé le** 28/10 (Guillaume, à partir du code des instances de Fatima) ; ALB, certificat et DNS ensuite.

## Ce qui est dedans
Ce qui sert aux deux environnements, pour que `staging/` et `production/` ne dépendent pas l'un de l'autre.
- **Instances** (`instances.tf`) :
  - **bastion** (`t3.micro`, `public-a`, SG `bastion`, IP publique) : la seule porte d'entrée SSH ;
  - **monitoring** (`t3.small`, `applicatif-a`, SG `monitoring`) : supervision des deux environnements ;
  - **ci** (`t3.small`, `applicatif-b`, SG `ci`) : le runner GitLab.
  Toutes : Ubuntu 24.04 (dernière image Canonical, `ignore_changes = [ami]`), IMDSv2 obligatoire (limite de sauts 2 pour les conteneurs), disque gp3 chiffré, clés SSH de `cles_ssh/` posées au premier démarrage (cloud-init).
- **ALB** `taiga-alb` (`alb.tf`) dans les 3 sous-réseaux publics : port 80 redirigé vers 443 ; 443 en TLS 1.2/1.3 avec notre certificat ; un nom inconnu reçoit une `404`. Règles de l'écouteur HTTPS :

  | Priorité | Condition | Action |
  |---|---|---|
  | 10 | `staging.…` et IP de l'équipe (`/taiga/reseau/ips_equipe`) | vers le target group du staging |
  | 11 | `staging.…` et IP de la NAT (la CI et la supervision, qui sortent par elle) | vers le target group du staging |
  | 20 | `staging.…`, toute autre IP | `403` « Accès réservé à l'équipe » |
  | 30 | `taiga-ledevagilles.fr` | vers le target group de la production |

  Deux target groups (`taiga-tg-staging`, `taiga-tg-production`), port 9000, contrôle de santé `/` toutes les 30 s. Les machines y sont inscrites par `staging/` et `production/`.
- **Certificat** ACM (`certificat.tf`) pour `taiga-ledevagilles.fr` et `*.taiga-ledevagilles.fr`, validé par DNS (enregistrements créés dans la zone du socle) ; `create_before_destroy`.
- **DNS** (`dns.tf`) : `taiga-ledevagilles.fr` et `staging.taiga-ledevagilles.fr`, enregistrements « alias » vers l'ALB.
- **IAM** (`iam.tf`), aucun secret ni clé d'accès sur les instances :

  | Rôle et profil | Droits | Porté par |
  |---|---|---|
  | `taiga-ec2-base` | journaux vers CloudWatch (`/taiga/*`) | bastion, supervision, staging |
  | `taiga-ec2-production` | base + déposer et relire les sauvegardes (`postgres/`, `media/`), jamais supprimer | les 3 nœuds |
  | `taiga-ec2-ci` | base + lecture des secrets `/taiga/*` + `ec2:DescribeInstances` (inventaire Ansible) | le runner |
- **Journaux** (`journaux.tf`) : groupe CloudWatch `/taiga/commun`, 7 jours.
- Tags : `Projet`, `Environnement = commun`, `GerePar`, plus `Name` et `Role` (lus par l'inventaire Ansible).

## Lit
- `reseau/` (`terraform_remote_state`) : VPC, sous-réseaux, SG ; et l'IP de la NAT par son tag `Name = taiga-nat-eip` (data source `aws_eip`).
- `socle/` : nom du bucket des sauvegardes (output `backups_bucket`), zone DNS (par son nom), politique `taiga-lecture-secrets` (par son nom).
- Parameter Store : `/taiga/reseau/ips_equipe`.

## L'utiliser
Après `socle/` et `reseau/` (NAT comprise), avant `staging/` et `production/` : `terraform init`, `terraform plan`, puis `apply` après la fusion.

## Outputs
`bastion_public_ip`, `private_ips` (par nom d'instance), `ssh_config` (`terraform output -raw ssh_config > ~/.ssh/taiga_config`, voir `docs/runbooks/1-equipe/se_connecter_ssh.md`), `log_group_name`.

## Pièges
- **Toujours après `reseau/`** : la règle 11 lit l'IP de la NAT. NAT absente → `no matching EC2 EIP found` (vécu le 05/11) ; NAT recréée sans réappliquer `commun/` → la CI reçoit un `403` sur le staging.
- **`destroy -target=aws_lb.taiga` le soir** emporte aussi les 2 enregistrements DNS (ils pointent vers l'ALB) : jusqu'à l'`apply` du matin, les noms n'existent plus. Une machine qui les demande entre-temps garde « ce nom n'existe pas » en cache un moment (sondes de la supervision rouges le 06/11) : `docs/runbooks/2-chaque-jour/arreter_demarrer.md`.
- `staging/` et `production/` cherchent les profils `taiga-ec2-base` et `taiga-ec2-production` et les target groups **par leur nom** : ne pas les renommer, et appliquer `commun/` avant eux.
- Le runner et la supervision sont dans des sous-réseaux privés : sans NAT, ils ne sortent pas sur Internet.
- L'IP publique du bastion change à chaque arrêt / redémarrage (pas d'IP élastique) : régénérer `~/.ssh/taiga_config`.
- Les clés SSH ne sont posées qu'à la création d'une instance : ajouter une personne dans `cles_ssh/` ne la donne pas aux instances existantes.
- Le rôle `ci` lit les secrets des deux environnements (`/taiga/*`) : risque accepté ; piste : un rôle par environnement (OIDC).
- La règle 10 accepte au plus 5 valeurs de condition (quota AWS) : c'est pour ça que l'IP de la NAT est dans une règle à part (11).

## Pistes
Nom DNS pour le bastion (`bastion.taiga-ledevagilles.fr`) ; pas de `destroy` de l'ALB le soir pendant les démos (évite le trou DNS) ; une NAT par zone (`reseau/`).
