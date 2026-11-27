# Staging

**Dossier** : `terraform/staging/` · **State** : `staging/terraform.tfstate` · **Code** : Fatima (instances), rangé par Guillaume le 28/10

## Ce qui est dedans
- Une instance `taiga-staging` (`t3.medium`, sous-réseau `staging-c`, SG `staging`, pas d'IP publique), disque gp3 chiffré de 20 Go, Ubuntu 24.04, IMDSv2, profil `taiga-ec2-base`.
- Instance tout-en-un : Taiga **et** sa base PostgreSQL en conteneurs (Docker Compose, rôle Ansible `taiga`), plus Mailpit (faux serveur de mails).
- **Inscription dans l'ALB** (`alb.tf`) : l'instance dans `taiga-tg-staging`, port 9000. Le site `https://staging.taiga-ledevagilles.fr` n'est ouvert qu'aux IP de l'équipe et à la NAT (règles de `commun/`).
- Tags : `Projet`, `Environnement = staging`, `GerePar`, `Name`, `Role = staging`.

## L'utiliser
Après `commun/` : `terraform init`, `terraform plan`, puis `apply` après la fusion. Ensuite Ansible : `taiga.yml` (inventaire `staging`). Joindre l'instance : `ssh staging` (rebond par le bastion).

## Lit
- `reseau/` (`terraform_remote_state`) : sous-réseau et SG.
- `commun/` (par leur nom) : profil d'instance `taiga-ec2-base`, target group `taiga-tg-staging`.

## Outputs
- `private_ips`.
- `ssh_config` : `terraform output -raw ssh_config > ~/.ssh/taiga_config_staging` (`docs/runbooks/1-equipe/se_connecter_ssh.md`).

## Pièges
- `plan` échoue si `commun/` n'est pas appliqué (profil ou target group introuvable).
- Le disque est supprimé avec l'instance : la base du staging est **perdue** à chaque recréation (voulu : environnement jetable ; les comptes `admin` et `e2e-test` sont recréés par Ansible).
- La NAT doit être allumée pour installer quoi que ce soit (instance privée).
