# Table publique : tout ce qui n'est pas dans le VPC part vers l'Internet Gateway
resource "aws_route_table" "publique" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "taiga-rt-publique"
  }
}

# Table privée : applicatifs A, B, C et staging C (la route vers la NAT est à part, juste en dessous)
resource "aws_route_table" "privee" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "taiga-rt-privee"
  }
}

# Route par défaut de la table privée vers la NAT (sortie seule : images Docker, mises à jour)
resource "aws_route" "privee_nat" {
  route_table_id         = aws_route_table.privee.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Table isolée : données A, B, C, aucune route vers Internet (RDS n'en a pas besoin)
resource "aws_route_table" "isolee" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "taiga-rt-isolee"
  }
}

# Correspondance entre le rôle d'un sous-réseau et sa table de routage
locals {
  table_par_role = {
    public = aws_route_table.publique.id
    prive  = aws_route_table.privee.id
    isole  = aws_route_table.isolee.id
  }
}

# Chaque sous-réseau est rattaché à la table qui correspond à son rôle
resource "aws_route_table_association" "main" {
  for_each = local.subnets

  subnet_id      = aws_subnet.main[each.key].id
  route_table_id = local.table_par_role[each.value.role]
}

# Endpoint S3 (Gateway, gratuit) : les sauvegardes vont vers S3 sans passer par la NAT
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.privee.id]

  tags = {
    Name = "taiga-endpoint-s3"
  }
}
