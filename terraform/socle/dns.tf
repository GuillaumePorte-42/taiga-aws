# Nom de domaine du projet, acheté chez IONOS
variable "domain_name" {
  description = "Domaine du projet, enregistré chez IONOS"
  type        = string
  default     = "taiga-ledevagilles.fr"
}

# Zone DNS hébergée dans Route 53 : socle, jamais détruite (sinon les serveurs NS changent)
resource "aws_route53_zone" "main" {
  name = var.domain_name

  lifecycle {
    prevent_destroy = true
  }
}

# Les 4 serveurs NS de la zone, à recopier chez IONOS pour la délégation
output "name_servers" {
  value = aws_route53_zone.main.name_servers
}
