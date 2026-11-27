# Versions exigées et state du réseau stocké dans le bucket du socle
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
    key          = "reseau/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

# Provider AWS : région Paris, tags posés automatiquement sur toutes les ressources
provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Projet        = "taiga-ledevagilles"
      Environnement = "reseau"
      GerePar       = "terraform"
    }
  }
}
