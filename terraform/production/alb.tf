# Target group de la production, créé par commun/ : on le lit par son nom, sans le gérer ici
data "aws_lb_target_group" "production" {
  name = "taiga-tg-production"
}

# Inscrit les 3 nœuds Swarm sur le port 9000 : le routing mesh de Swarm répond sur chacun d'eux
resource "aws_lb_target_group_attachment" "production" {
  for_each = aws_instance.main

  target_group_arn = data.aws_lb_target_group.production.arn
  target_id        = each.value.id
  port             = 9000
}