# Identity SES du domaine : jamais détruite (sinon les tokens DKIM changent)
resource "aws_sesv2_email_identity" "taiga" {
  email_identity = var.domain_name

  lifecycle {
    prevent_destroy = true
  }
}

# Les 3 CNAME DKIM, créés directement dans la zone Route 53
resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.main.zone_id
  name    = "${aws_sesv2_email_identity.taiga.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.taiga.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# Politique DMARC du domaine : annonce aux serveurs qui reçoivent nos mails qu'ils doivent vérifier DKIM/SPF.
# « p=none » = on observe seulement (rien n'est rejeté) : première marche conseillée ; moins de mails classés en spam.
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=none;"]
}

# Utilisateur technique de Taiga pour SES : ne sert qu'à envoyer des mails (pas de console, pas d'autre droit)
resource "aws_iam_user" "ses_smtp" {
  name = "taiga-ses-smtp"
}

# Son seul droit : envoyer un mail avec les identités SES de notre compte, dans notre région
resource "aws_iam_user_policy" "ses_smtp" {
  name = "taiga-envoi-ses"
  user = aws_iam_user.ses_smtp.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ses:SendRawEmail"
        Resource = "arn:aws:ses:eu-west-3:${data.aws_caller_identity.current.account_id}:identity/*"
      }
    ]
  })
}

# Clé d'accès de cet utilisateur : Terraform en déduit le mot de passe SMTP (attribut ses_smtp_password_v4)
resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}
