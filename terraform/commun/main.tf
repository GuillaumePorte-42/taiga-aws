# =============================================================================
# elements communs entre production et staging
# =============================================================================
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "taiga-ledevagilles-tfstate"
    key          = "commun/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

# Tags posés automatiquement sur toutes les ressources : l'inventaire
# dynamique Ansible (PFD-59) filtre sur Projet et Environnement
provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Projet        = "taiga-ledevagilles"
      Environnement = "commun"
      GerePar       = "terraform"
    }
  }
}
