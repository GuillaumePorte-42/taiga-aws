# Versions exigées : Terraform 1.10+ (verrou S3 natif) et provider AWS 6.x
terraform {
  # Terraform 1.10 minimum : c'est la version qui apporte le verrou natif S3 (use_lockfile)
  required_version = ">= 1.10"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }


  # State stocké dans le bucket du socle, chiffré, avec verrou natif S3 (sans DynamoDB)
  backend "s3" {
    bucket       = "taiga-ledevagilles-tfstate"
    key          = "socle/terraform.tfstate"
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
      Environnement = "socle"
      GerePar       = "terraform"
    }
  }
}

