# Données

**Dossier** : `terraform/donnees/` · **State** : `donnees/terraform.tfstate` · **Code** : Samuel (RDS), relu et fusionné par Guillaume le 30/10

## Ce qui est dedans
- **Base RDS PostgreSQL 17** `taiga-db` (`db.t3.micro`, 20 Go), base `taiga`, utilisateur `taiga`, dans les 3 sous-réseaux `donnees-*` (groupe `taiga-db`, aucune route vers Internet), SG `rds` (5432 depuis les nœuds et la supervision seulement), pas d'accès public.
- Disque **chiffré**, snapshots automatiques gardés **7 jours**, **`deletion_protection`** et snapshot final `taiga-db-final` en cas de suppression.
- **Single-AZ** (`multi_az = false`) : choix de coût pour le projet ; Multi-AZ = piste (prix doublé, bascule automatique).
- Mot de passe lu dans **`/taiga/production/postgres_password`** (créé par `socle/`), jamais dans Git.
- Adresse de la base écrite dans **`/taiga/production/db_host`** : Ansible la lit (back, sauvegardes, supervision), rien à recopier à la main.

## Pourquoi un dossier à part
La base garde les données du client : elle ne doit jamais être détruite avec `production/` (reconstruction, soirs). Son propre state la protège d'un `destroy` de la production.

## Lit
- `reseau/` (`terraform_remote_state`) : sous-réseaux `donnees-*` et SG `rds`.
- Parameter Store : `/taiga/production/postgres_password`.

## L'utiliser
Après `socle/` et `reseau/` : `terraform init`, `terraform plan`, puis `apply` après la fusion. La création prend plusieurs minutes.

Le soir : **arrêter**, jamais détruire (`docs/runbooks/2-chaque-jour/arreter_demarrer.md`).

## Outputs
`rds_address` (toujours utiliser ce nom, jamais une IP : il suit la base après une bascule), `rds_port`.

## Pièges
- **`reseau/` ne peut pas être détruit tant que la base existe** (elle utilise ses sous-réseaux et son SG).
- Changer `/taiga/production/postgres_password` ne change le mot de passe de la RDS qu'au prochain `apply` de ce dossier ; entre les deux, le back ne se connecte plus (`docs/reference/parametres.md`).
- Le mot de passe passe par le state (bucket privé, chiffré).
- Une RDS arrêtée **redémarre seule au bout de 7 jours** (règle d'AWS).
- Supprimer la base exprès : passer `deletion_protection = false`, appliquer, puis détruire (snapshot final créé).
- Version majeure 17 : `pg_dump` des sauvegardes doit être au moins en 17 (`image_postgres`, `ansible/playbooks/group_vars/all.yml`).
