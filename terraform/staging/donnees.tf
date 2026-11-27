# =============================================================================
# staging/donnees.tf — PFD-17
# Le staging lit ce qui est créé ailleurs (réseau, profil IAM, target group) :
# appliquer reseau/ et commun/ AVANT staging/.
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

locals {
  subnets = data.terraform_remote_state.reseau.outputs.subnet_ids
  sgs     = data.terraform_remote_state.reseau.outputs.security_group_ids
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

data "aws_iam_instance_profile" "base" {
  name = "taiga-ec2-base"
}

# Target group du staging, créé par commun/ : on le lit par son nom, sans le gérer ici
data "aws_lb_target_group" "staging" {
  name = "taiga-tg-staging"
}
