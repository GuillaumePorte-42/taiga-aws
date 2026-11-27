# =============================================================================
# commun/donnees.tf — PFD-17
# =============================================================================
# Sorties du dossier reseau (VPC, sous-réseaux, Security Groups)
data "terraform_remote_state" "reseau" {
  backend = "s3"
  config = {
    bucket = "taiga-ledevagilles-tfstate"
    key    = "reseau/terraform.tfstate"
    region = "eu-west-3"
  }
}

# State de socle/ : nom du bucket des sauvegardes (output backups_bucket)
data "terraform_remote_state" "socle" {
  backend = "s3"
  config = {
    bucket = "taiga-ledevagilles-tfstate"
    key    = "socle/terraform.tfstate"
    region = "eu-west-3"
  }
}

locals {
  subnets = data.terraform_remote_state.reseau.outputs.subnet_ids
  sgs     = data.terraform_remote_state.reseau.outputs.security_group_ids
  # Nom du bucket des sauvegardes, publié par socle/
  bucket_sauvegardes = data.terraform_remote_state.socle.outputs.backups_bucket
}

# Dernière image Ubuntu 24.04 LTS de Canonical : jamais d identifiant d AMI en dur
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Politique de lecture des secrets, créée dans socle/secrets.tf (PFD-32)
data "aws_iam_policy" "lecture_secrets" {
  name = "taiga-lecture-secrets"
}
