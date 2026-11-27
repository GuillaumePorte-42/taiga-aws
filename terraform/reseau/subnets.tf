# Plan d'adressage : une ligne par sous-réseau (plage, zone, rôle)
locals {
  subnets = {
    # Publics : ALB, bastion, NAT (route vers l'Internet Gateway)
    "public-a" = { cidr = "10.0.1.0/24", az = "eu-west-3a", role = "public" }
    "public-b" = { cidr = "10.0.2.0/24", az = "eu-west-3b", role = "public" }
    "public-c" = { cidr = "10.0.3.0/24", az = "eu-west-3c", role = "public" }

    # Privés applicatifs : nœuds Swarm, supervision, CI, EFS (sortie par la NAT)
    "applicatif-a" = { cidr = "10.0.11.0/24", az = "eu-west-3a", role = "prive" }
    "applicatif-b" = { cidr = "10.0.12.0/24", az = "eu-west-3b", role = "prive" }
    "applicatif-c" = { cidr = "10.0.13.0/24", az = "eu-west-3c", role = "prive" }

    # Privés données : RDS (aucune route vers Internet)
    "donnees-a" = { cidr = "10.0.21.0/24", az = "eu-west-3a", role = "isole" }
    "donnees-b" = { cidr = "10.0.22.0/24", az = "eu-west-3b", role = "isole" }
    "donnees-c" = { cidr = "10.0.23.0/24", az = "eu-west-3c", role = "isole" }

    # Privé staging : instance staging, loin de la zone A (sortie par la NAT)
    "staging-c" = { cidr = "10.0.33.0/24", az = "eu-west-3c", role = "prive" }
  }
}

# Un sous-réseau par ligne du plan d'adressage
resource "aws_subnet" "main" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "taiga-${each.key}"
    Role = each.value.role
  }
}
