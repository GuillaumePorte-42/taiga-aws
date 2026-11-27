# =============================================================================
# commun/certificat.tf — certificat HTTPS de l'ALB (ACM), validé par DNS
# =============================================================================

# Zone DNS créée par socle/ (lue par son nom)
data "aws_route53_zone" "principale" {
  name = "taiga-ledevagilles.fr"
}

# Un seul certificat pour la prod (racine) et tous les sous-domaines (staging.…)
resource "aws_acm_certificate" "taiga" {
  domain_name               = "taiga-ledevagilles.fr"
  subject_alternative_names = ["*.taiga-ledevagilles.fr"]
  validation_method         = "DNS"

  # Si le certificat doit être remplacé, le nouveau est créé avant de supprimer l'ancien :
  # l'ALB n'est jamais sans certificat
  lifecycle {
    create_before_destroy = true
  }
}

# Les enregistrements CNAME demandés par ACM pour prouver qu'on contrôle le domaine
resource "aws_route53_record" "validation_certificat" {
  for_each = {
    for dvo in aws_acm_certificate.taiga.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.principale.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Attend qu'ACM ait trouvé les enregistrements et délivré le certificat ("Issued")
resource "aws_acm_certificate_validation" "taiga" {
  certificate_arn         = aws_acm_certificate.taiga.arn
  validation_record_fqdns = [for r in aws_route53_record.validation_certificat : r.fqdn]
}