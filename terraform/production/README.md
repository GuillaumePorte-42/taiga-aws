# Production

**Dossier** : `terraform/production/` · **State** : `production/terraform.tfstate` · **Code** : Fatima (instances), rangé par Guillaume le 28/10 ; EFS (Samuel), journaux, inscription dans l'ALB ensuite.

## Ce qui est dedans
- **3 nœuds Swarm** `taiga-node-1` à `3` (`t3.medium`), un par zone (`applicatif-a`, `-b`, `-c`), SG `nodes`, pas d'IP publique, disque gp3 chiffré de 20 Go, Ubuntu 24.04, IMDSv2 ; profil `taiga-ec2-production` (journaux + sauvegardes).
- **Inscription dans l'ALB** (`alb.tf`) : les 3 nœuds dans `taiga-tg-production`, port 9000 (le *routing mesh* de Swarm répond sur chaque nœud).
- **EFS** `taiga-production-efs` (`efs.tf`) : chiffré, débit `elastic`, un point de montage par zone, sauvegardes AWS Backup activées. Son ID est écrit dans **`/taiga/production/efs_id`** (lu par Ansible pour le montage). Taiga y range ses fichiers statiques et ses médias.
- **Journaux** (`journaux.tf`) : groupe CloudWatch `/taiga/production`, 7 jours ; les conteneurs y écrivent par le pilote `awslogs` déclaré dans la stack.
- Tags : `Projet`, `Environnement = production`, `GerePar`, `Name`, `Role = swarm-node`.

## Lit
- `reseau/` (`terraform_remote_state`) : sous-réseaux et SG.
- `commun/` (par leur nom) : profil `taiga-ec2-production`, target group `taiga-tg-production`.

## L'utiliser
Après `commun/` : `terraform init`, `terraform plan`, puis `apply` après la fusion. Ensuite Ansible : `efs.yml`, `swarm.yml`, `sauvegardes.yml`, puis la stack (`ansible/README.md`).

## Outputs
- `private_ips`, `efs_id`, `log_group_name`.
- `ssh_config` : `terraform output -raw ssh_config > ~/.ssh/taiga_config_production`, puis `ssh node-1` (`docs/runbooks/1-equipe/se_connecter_ssh.md`).

## Pièges
- `plan` échoue si `commun/` n'est pas appliqué (profil ou target group introuvable).
- Les disques sont supprimés avec les instances ; un EFS recréé est **vide** (médias à restaurer : `docs/runbooks/5-donnees/sauvegarder_restaurer.md`).
- La base n'est pas ici : elle est dans `terraform/donnees/` (jamais détruite avec la production).
- Les 3 nœuds sont des managers Swarm : les démarrer **ensemble** (un nœud seul n'a pas de quorum).
- Coût : 3 `t3.medium` + l'EFS (au stockage) + la NAT tant que la production tourne.
