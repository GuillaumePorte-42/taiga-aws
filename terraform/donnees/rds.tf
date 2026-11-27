# =============================================================================
# donnees/rds.tf — Base RDS PostgreSQL de prod
# Dossier à part : jamais détruit le soir, contrairement à reseau/, production/, staging/
# =============================================================================

# Sorties du dossier reseau (sous-réseaux, Security Groups), même méthode que production/
data "terraform_remote_state" "reseau" {
  backend = "s3"
  config = {
    bucket = "taiga-ledevagilles-tfstate"
    key    = "reseau/terraform.tfstate"
    region = "eu-west-3"
  }
}

locals {
  subnets = data.terraform_remote_state.reseau.outputs.subnet_ids
  sgs     = data.terraform_remote_state.reseau.outputs.security_group_ids
}

# Groupe de sous-réseaux pour RDS : tous les sous-réseaux dont le nom commence par "donnees-"
resource "aws_db_subnet_group" "main" {
  name       = "taiga-db"
  subnet_ids = [for nom, id in local.subnets : id if startswith(nom, "donnees-")]

  tags = {
    Name = "taiga-db"
  }
}

# Mot de passe PostgreSQL de prod, lu dans Parameter Store (SecureString, jamais dans Git)
data "aws_ssm_parameter" "postgres_password" {
  name = "/taiga/production/postgres_password"
}

# Base RDS PostgreSQL 17 de prod, Multi-AZ
resource "aws_db_instance" "main" {
  identifier     = "taiga-db"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true # données du client chiffrées sur le disque

  db_name  = "taiga"
  username = "taiga"
  password = data.aws_ssm_parameter.postgres_password.value

  multi_az               = true
  apply_immediately      = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [local.sgs["rds"]]
  publicly_accessible    = false

  # Snapshots automatiques, conservés 7 jours
  backup_retention_period = 7

  # Protection : la base ne doit jamais être supprimée par erreur
  # (pour la supprimer exprès : passer à false, appliquer, puis détruire)
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "taiga-db-final"

  tags = {
    Name = "taiga-db"
  }
}

# Adresse de la base écrite dans Parameter Store : Ansible la lit pour la production, rien à recopier à la main
resource "aws_ssm_parameter" "db_host" {
  name  = "/taiga/production/db_host"
  type  = "String"
  value = aws_db_instance.main.address

  tags = {
    Name = "taiga-db-host"
  }
}