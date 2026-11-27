# IP publique fixe (Elastic IP) de la NAT : c'est l'adresse de sortie de tout le privé
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "taiga-nat-eip"
  }
}

# Une seule NAT Gateway, en zone A (choix de coût) : sortie vers Internet pour les sous-réseaux privés
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.main["public-a"].id

  tags = {
    Name = "taiga-nat"
  }

  # La NAT a besoin que l'Internet Gateway existe pour sortir
  depends_on = [aws_internet_gateway.main]
}
