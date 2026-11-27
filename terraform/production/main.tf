# =============================================================================
# production/main.tf — mêmes versions, backend et conventions que reseau/ (PFD-17)
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
    key          = "production/terraform.tfstate"
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
      Environnement = "production"
      GerePar       = "terraform"
    }
  }
}
