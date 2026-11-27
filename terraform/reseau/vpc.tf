# VPC unique pour staging et prod : une seule NAT et une seule config (choix de coût)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "taiga-vpc"
  }
}

# Internet Gateway : la porte du VPC vers Internet, utilisée par la table publique
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "taiga-igw"
  }
}