# =============================================================================
# commun/dns.tf — les noms du site pointent vers l'ALB
# =============================================================================

# Prod (racine du domaine) et staging : un enregistrement « alias » vers l'ALB
resource "aws_route53_record" "site" {
  for_each = toset(["taiga-ledevagilles.fr", "staging.taiga-ledevagilles.fr"])

  zone_id = data.aws_route53_zone.principale.zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = aws_lb.taiga.dns_name
    zone_id                = aws_lb.taiga.zone_id
    evaluate_target_health = false
  }
}
